--!nonstrict
-- Edit-time preview and reversible cleanup of the old BuildingAuto_* pass.
-- local c = require(game.ServerScriptService.Server.ShibuyaFragmentCleanup)
-- local r = c.Preview(workspace.Buildings, {MaxFloorArea=250})
-- print(game.HttpService:JSONEncode(r.summary))
-- print(game.HttpService:JSONEncode(r.examples))
-- c.Apply(r) -- separate, explicit action; archives exact candidates in ServerStorage
-- Override automatic selection with {Explicit={exactModel1, exactModel2}}.
-- Eligibility still protects original, clean-box and manually authored models.
-- Areas are studs^2, volumes studs^3, and distances studs. A hollow shell's
-- low part volume ALONE is never evidence that its building is a fragment.

local Cleanup = {}
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local DEFAULTS = {
	MaxFloorArea = 250,
	MaxEnvelopeVolume = 24000,
	MaxSlabVolume = 6000,
	MaxShortHeight = 35,
	ElevatedClearance = 20,
	GroundRayRise = 500,
	GroundRayDepth = 2000,
	ExampleCount = 25,
	YieldEvery = 50,
}

local function editOnly()
	assert(not RunService:IsRunning(), "Stop playtest before fragment cleanup")
end

local function eligible(model)
	return model:IsA("Model") and model.Name:match("^BuildingAuto_") ~= nil
		and model:GetAttribute("ShibuyaSourceKey") ~= nil
		and model:GetAttribute("ManualShellVersion") == nil
		and model:GetAttribute("ShibuyaBoxKey") == nil
end

local function optionsFrom(options)
	options = options or {}
	local result = {}
	for name, default in DEFAULTS do
		local n = options[name]
		if n == nil then n = default end
		assert(type(n) == "number" and n == n and n >= 0 and n < math.huge, "Invalid option " .. name)
		result[name] = n
	end
	assert(result.GroundRayRise + result.GroundRayDepth > 0, "Ground ray must have positive length")
	assert(result.YieldEvery >= 1 and result.YieldEvery % 1 == 0, "YieldEvery must be a positive integer")
	assert(result.ExampleCount % 1 == 0, "ExampleCount must be an integer")
	return result
end

local function slabFloor(part, building)
	local ancestor = part.Parent
	while ancestor and ancestor ~= building do
		local number = ancestor.Name:match("^Floor(%d+)$")
		if number then return tonumber(number) end
		if ancestor.Name == "Roof" then return nil end
		ancestor = ancestor.Parent
	end
	return nil
end

-- One descendant pass; actual slab dimensions, not the saved occupancy grid.
local function measure(model, options, groundParams)
	local savedCF = model:GetAttribute("InteriorBBoxCFrame")
	local frame = typeof(savedCF) == "CFrame" and savedCF.Rotation or CFrame.identity
	local lo, hi = Vector3.new(math.huge,math.huge,math.huge), Vector3.new(-math.huge,-math.huge,-math.huge)
	local parts, slabs, slabVolume, roofArea, hasCore, floorAreas = 0, 0, 0, 0, false, {}
	local tiltedSlab = false
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			parts += 1
			local localCF, half = frame:ToObjectSpace(part.CFrame), part.Size / 2
			local right, up, look = localCF.RightVector, localCF.UpVector, localCF.LookVector
			local extent = Vector3.new(
				math.abs(right.X)*half.X + math.abs(up.X)*half.Y + math.abs(look.X)*half.Z,
				math.abs(right.Y)*half.X + math.abs(up.Y)*half.Y + math.abs(look.Y)*half.Z,
				math.abs(right.Z)*half.X + math.abs(up.Z)*half.Y + math.abs(look.Z)*half.Z)
			lo = lo:Min(localCF.Position - extent)
			hi = hi:Max(localCF.Position + extent)
			if CollectionService:HasTag(part, "BuildingCore") then hasCore = true end
			if part.Name == "Slab" then
				slabs += 1
				local area = part.Size.X * part.Size.Z
				slabVolume += area * part.Size.Y
				tiltedSlab = tiltedSlab or math.abs(part.CFrame.UpVector.Y) < 0.9999
				local floor = slabFloor(part, model)
				if floor then floorAreas[floor] = (floorAreas[floor] or 0) + area
				else roofArea += area end
			end
		end
	end
	local row = {model=model, parent=model.Parent, name=model.Name,
		sourceKey=model:GetAttribute("ShibuyaSourceKey"), parts=parts, slabs=slabs,
		slabVolume=slabVolume, roofArea=roofArea, hasCore=hasCore,
		generatedFloors=model:GetAttribute("GeneratedFloors"), floorAreas={},
		measuredFloors=0, maxFloorArea=0, totalFloorArea=0, tiltedSlab=tiltedSlab}
	for floor, area in floorAreas do
		table.insert(row.floorAreas, {floor=floor, area=area})
		row.measuredFloors += 1
		row.maxFloorArea = math.max(row.maxFloorArea, area)
		row.totalFloorArea += area
	end
	table.sort(row.floorAreas, function(a,b) return a.floor < b.floor end)
	row.meanFloorArea = row.measuredFloors > 0 and row.totalFloorArea / row.measuredFloors or 0
	if parts > 0 then
		row.size = hi - lo
		row.cf = frame * CFrame.new((lo + hi) / 2)
		row.height = row.size.Y
		row.envelopeVolume = row.size.X * row.size.Y * row.size.Z
		-- Upright saved frames are standard for this generation. Terrain only:
		-- imported roofs and nearby building floors cannot act as false ground.
		row.baseY = row.cf.Position.Y - row.height / 2
		local origin = Vector3.new(row.cf.Position.X, row.baseY + options.GroundRayRise, row.cf.Position.Z)
		local ground = workspace:Raycast(origin, Vector3.new(0,-options.GroundRayRise-options.GroundRayDepth,0), groundParams)
		if ground then
			row.groundY = ground.Position.Y
			row.groundClearance = row.baseY - ground.Position.Y
		end
	end
	return row
end

local function classify(row, options)
	local reasons = {}
	if not row.size or row.slabs == 0 or row.tiltedSlab then return false, reasons end
	local smallArea = row.maxFloorArea <= options.MaxFloorArea
	local smallEnvelope = row.envelopeVolume <= options.MaxEnvelopeVolume
	local smallSlabs = row.slabVolume <= options.MaxSlabVolume
	local elevated = row.groundClearance ~= nil and row.groundClearance >= options.ElevatedClearance
	local short = row.height <= options.MaxShortHeight
	local noCore = not row.hasCore
	if smallArea then table.insert(reasons, "small usable floor area") end
	if smallEnvelope then table.insert(reasons, "small envelope") end
	if smallSlabs then table.insert(reasons, "small total slab volume") end
	if elevated then table.insert(reasons, "elevated above terrain") end
	if short then table.insert(reasons, "short section") end
	if noCore then table.insert(reasons, "no generated core") end
	return smallArea and (smallEnvelope or smallSlabs) and (elevated or short or noCore), reasons
end

local function distribution(rows, field, bins)
	local values, counts = {}, table.create(#bins + 1, 0)
	for _, row in rows do
		local value = row[field]
		if type(value) == "number" then
			table.insert(values, value)
			local bucket = #bins + 1
			for i, limit in bins do if value <= limit then bucket = i; break end end
			counts[bucket] += 1
		end
	end
	table.sort(values)
	local function quantile(q)
		return #values > 0 and values[math.clamp(math.ceil(#values*q),1,#values)] or nil
	end
	return {count=#values, missing=#rows-#values, min=values[1], p10=quantile(0.1), p25=quantile(0.25),
		median=quantile(0.5), p75=quantile(0.75), p90=quantile(0.9), max=values[#values],
		upperBounds=bins, counts=counts} -- final count is values above the last bound
end

local function example(row)
	return {name=row.name, candidate=row.candidate, reasons=row.reasons,
		position=row.cf and {row.cf.X,row.cf.Y,row.cf.Z}, size=row.size and {row.size.X,row.size.Y,row.size.Z},
		maxFloorArea=row.maxFloorArea, meanFloorArea=row.meanFloorArea, measuredFloors=row.measuredFloors,
		generatedFloors=row.generatedFloors, height=row.height, slabVolume=row.slabVolume,
		envelopeVolume=row.envelopeVolume, groundClearance=row.groundClearance, hasCore=row.hasCore}
end

function Cleanup.Preview(folder, options)
	editOnly()
	assert(typeof(folder) == "Instance" and (folder:IsA("Folder") or folder:IsA("Model")), "Provide the direct building container")
	local config = optionsFrom(options)
	local explicit = options and options.Explicit
	local chosen
	if explicit ~= nil then
		assert(type(explicit) == "table", "Explicit must be an exact model list")
		chosen = {}
		for _, model in explicit do
			assert(typeof(model) == "Instance" and model.Parent == folder and eligible(model), "Explicit contains an ineligible model")
			chosen[model] = true
		end
	end
	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Include
	ground.FilterDescendantsInstances = {workspace.Terrain}
	local rows, candidates, preserved, groundUnknown = {}, {}, 0, 0
	for _, model in folder:GetChildren() do
		if not eligible(model) then preserved += 1; continue end
		local row = measure(model, config, ground)
		local automatic, reasons = classify(row, config)
		row.candidate = chosen ~= nil and chosen[model] == true or chosen == nil and automatic
		row.reasons = chosen ~= nil and (row.candidate and {"explicitly selected object"} or {}) or reasons
		table.insert(rows, row)
		if row.groundClearance == nil then groundUnknown += 1 end
		if row.candidate then table.insert(candidates, row) end
		if #rows % config.YieldEvery == 0 then task.wait() end
	end
	local function bySmallest(a,b)
		if a.maxFloorArea ~= b.maxFloorArea then return a.maxFloorArea < b.maxFloorArea end
		if a.slabVolume ~= b.slabVolume then return a.slabVolume < b.slabVolume end
		return a.name < b.name
	end
	table.sort(rows, bySmallest)
	table.sort(candidates, bySmallest)
	local examples = {smallest={}, candidates={}}
	for i = 1, math.min(config.ExampleCount,#rows) do table.insert(examples.smallest, example(rows[i])) end
	for i = 1, math.min(config.ExampleCount,#candidates) do table.insert(examples.candidates, example(candidates[i])) end
	local summary = {eligible=#rows, candidates=#candidates, protected=preserved, groundUnknown=groundUnknown,
		explicit=chosen ~= nil, options=config, distributions={
			maxFloorArea=distribution(rows,"maxFloorArea",{100,250,500,1000,2500,10000}),
			envelopeVolume=distribution(rows,"envelopeVolume",{10000,24000,50000,100000,500000,2000000}),
			slabVolume=distribution(rows,"slabVolume",{1000,3000,6000,12000,30000,100000}),
			height=distribution(rows,"height",{20,35,60,100,200,500}),
			groundClearance=distribution(rows,"groundClearance",{0,5,20,50,100,250}),
			generatedFloors=distribution(rows,"generatedFloors",{1,2,3,5,10,20}),
			measuredFloors=distribution(rows,"measuredFloors",{1,2,3,5,10,20}),
		}}
	print("FRAGMENT_PREVIEW", #rows, "eligible", #candidates, "candidates; no models changed")
	return {kind="ShibuyaFragmentCleanup.v1", folder=folder, options=config,
		rows=rows, candidates=candidates, summary=summary, examples=examples}
end

function Cleanup.Apply(report)
	editOnly()
	assert(type(report) == "table" and report.kind == "ShibuyaFragmentCleanup.v1" and not report.applied, "Invalid or applied report")
	assert(#report.candidates > 0, "No candidates to archive")
	local seen = {}
	-- Validate the entire exact-object set before moving anything.
	for _, row in report.candidates do
		local model = row.model
		assert(eligible(model) and model.Parent == report.folder and model.Parent == row.parent
			and model.Name == row.name and model:GetAttribute("ShibuyaSourceKey") == row.sourceKey, "Candidate changed since preview")
		assert(not seen[model], "Duplicate candidate")
		seen[model] = true
	end
	local history = game:GetService("ChangeHistoryService")
	history:SetWaypoint("Before archiving Shibuya fragments")
	local archive = Instance.new("Folder")
	archive.Name = "ShibuyaFragmentArchive_" .. HttpService:GenerateGUID(false)
	archive:SetAttribute("CandidateCount", #report.candidates)
	archive:SetAttribute("CleanupSummary", HttpService:JSONEncode(report.summary))
	archive.Parent = ServerStorage
	local moved = {}
	local ok, err = pcall(function()
		for _, row in report.candidates do
			row.model.Parent = archive
			table.insert(moved, row)
		end
	end)
	if not ok then
		for _, row in moved do row.model.Parent = row.parent end
		archive:Destroy()
		error(err, 2)
	end
	report.applied = true
	report.archive = archive
	history:SetWaypoint("Archived Shibuya fragments")
	print("FRAGMENT_ARCHIVED", #moved, archive:GetFullName(), "all models preserved")
	return archive
end

return Cleanup
