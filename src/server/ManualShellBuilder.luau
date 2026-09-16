--!nonstrict
-- EDIT-TIME, visually authored box massing. Source/reference objects are never changed.
-- local m = require(game.ServerScriptService.Server.ManualShellBuilder)
-- local staged = m.Stage("BuildingManual_01", {
--     {cf=CFrame.new(0,60,0), size=Vector3.new(80,120,60), floors=6},
--     {cf=CFrame.new(60,40,0), size=Vector3.new(40,80,60), floors=4, core=false},
-- })
-- m.Apply(staged, workspace.Buildings, exactOldBuildingOrNil)
-- m.Rebuild(building, {furnished=true}) returns a NEW stage for inspection/apply.
-- Sections must be upright non-overlapping boxes; touching or stacked boxes are OK.
-- Use consistent bases/floor counts for adjacent wings whose floors must align.
-- Wedges and curved outlines are deliberately not approximated with grid edges.

local Manual = {}
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local function editOnly()
	assert(not RunService:IsRunning(), "Stop playtest before generating manual shells")
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function storageFolder(name)
	local folder = ServerStorage:FindFirstChild(name)
	if folder then assert(folder:IsA("Folder"), name .. " must be a Folder"); return folder end
	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = ServerStorage
	return folder
end

-- Separating axes for upright rotated boxes, including the vertical interval.
local function overlaps(a, b)
	local delta = b.cf.Position - a.cf.Position
	if math.abs(delta.Y) >= (a.size.Y + b.size.Y) / 2 - 0.001 then return false end
	for _, axis in {a.cf.RightVector, a.cf.LookVector, b.cf.RightVector, b.cf.LookVector} do
		local ra = math.abs(axis:Dot(a.cf.RightVector)) * a.size.X / 2
			+ math.abs(axis:Dot(a.cf.LookVector)) * a.size.Z / 2
		local rb = math.abs(axis:Dot(b.cf.RightVector)) * b.size.X / 2
			+ math.abs(axis:Dot(b.cf.LookVector)) * b.size.Z / 2
		if math.abs(delta:Dot(axis)) >= ra + rb - 0.001 then return false end
	end
	return true
end

local function validate(name, sections)
	assert(type(name) == "string" and name:match("^Building"), "Name must begin with Building")
	assert(type(sections) == "table" and #sections > 0 and #sections <= 100, "Provide 1–100 box sections")
	for i, s in sections do
		assert(type(i) == "number" and i >= 1 and i <= #sections and i % 1 == 0, "Sections must be an array")
		assert(typeof(s.cf) == "CFrame" and typeof(s.size) == "Vector3", "Each section needs cf and size")
		for _, n in {s.cf:GetComponents()} do assert(finite(n), "Nonfinite frame") end
		assert(finite(s.size.X) and finite(s.size.Y) and finite(s.size.Z), "Nonfinite size")
		assert(s.cf.UpVector.Y > 0.999999, "Section frame must face upright")
		assert(s.size.X > 4 and s.size.Z > 4 and s.size.Y >= 6.5 / 0.28, "Section is too small for interior floors")
		assert(s.floors == nil or (finite(s.floors) and s.floors >= 1 and s.floors % 1 == 0), "Invalid floors")
		assert(s.core == nil or type(s.core) == "boolean", "core must be a boolean")
		for j = 1, i - 1 do
			assert(not overlaps(s, sections[j]), string.format("Sections %d and %d overlap; split the massing into non-overlapping boxes", j, i))
		end
	end
end

local function encodeSections(sections)
	local encoded = {}
	for _, s in sections do
		table.insert(encoded, {cf={s.cf:GetComponents()}, size={s.size.X,s.size.Y,s.size.Z}, floors=s.floors, core=s.core})
	end
	return HttpService:JSONEncode(encoded)
end

local function checkStructure(building)
	assert(building:IsA("Model") and building.Name:match("^Building"), "Invalid building")
	local interior = building:FindFirstChild("Interior")
	assert(interior and #interior:GetChildren() == building:GetAttribute("ManualSectionCount"), "Incomplete sections")
	local count = 0
	for _, section in interior:GetChildren() do
		assert(section:FindFirstChild("Interior") and section:GetAttribute("GeneratedFloors"), "Incomplete section")
	end
	for _, p in building:GetDescendants() do
		if p:IsA("BasePart") then
			assert(p.Anchored, "Unanchored generated part")
			if not CollectionService:HasTag(p, "NoCSG") then
				assert((p:IsA("Part") or p:IsA("PartOperation")) and p.CanCollide, "Invalid structural part")
			end
			count += 1
		end
	end
	assert(count > 0, "Empty building")
	return count
end

function Manual.Stage(name, sections, options)
	editOnly()
	validate(name, sections)
	options = options or {}
	assert(options.furnished == nil or type(options.furnished) == "boolean", "furnished must be a boolean")
	local generator = require(script.Parent.BuildingGenerator)
	local building = Instance.new("Model")
	building.Name = name
	building:SetAttribute("ManualShellVersion", 1)
	building:SetAttribute("ManualSectionCount", #sections)
	building:SetAttribute("ManualShellSpec", encodeSections(sections))
	building:SetAttribute("StructuralOnly", options.furnished ~= true)
	building:SetAttribute("FloorCountBasis", "Visually authored massing; per-section requested counts or height estimates")
	local interior = Instance.new("Model")
	interior.Name = "Interior"
	interior.Parent = building
	local ok, err = pcall(function()
		local totalFloors, levels = 0, {}
		for i, s in sections do
			local section = Instance.new("Model")
			section.Name = string.format("BuildingSection_%02d", i)
			section:SetAttribute("StructuralOnly", options.furnished ~= true)
			section.Parent = interior
			assert(generator.GenerateBox(section, s.cf, s.size, s.floors), "Section generation failed")
			if s.core == false then
				for _, p in section:GetDescendants() do
					if CollectionService:HasTag(p, "BuildingCore") then p:Destroy() end
				end
				section:SetAttribute("CoreCFrame", nil)
				section:SetAttribute("CoreSize", nil)
			end
			totalFloors += section:GetAttribute("GeneratedFloors")
			for _, floor in section.Interior:GetChildren() do
				local slab = floor:FindFirstChild("Slab")
				assert(slab, "Missing exact slab")
				if floor.Name ~= "Roof" then levels[math.round(slab.Position.Y * 1000)] = true end
			end
			if i % 10 == 0 then task.wait() end
		end
		local uniqueLevels = 0
		for _ in levels do uniqueLevels += 1 end
		building:SetAttribute("GeneratedFloors", uniqueLevels)
		building:SetAttribute("GeneratedFloorSections", totalFloors)
		local cf, size = building:GetBoundingBox()
		building:SetAttribute("InteriorBBoxCFrame", cf)
		building:SetAttribute("InteriorBBoxSize", size)
		building:SetAttribute("ManualShellFrame", building:GetPivot())
		building:SetAttribute("GeneratedParts", checkStructure(building))
	end)
	if not ok then building:Destroy(); error(err, 2) end
	building:SetAttribute("ManualShellStaged", true)
	building.Parent = storageFolder("ManualShellStages")
	return building
end

-- Read an authored shell without altering or moving any of its parts.
function Manual.StageFromShell(name, shell, options)
	local sections = {}
	for _, p in shell:GetDescendants() do
		if p:IsA("BasePart") then
			assert(p:IsA("Part") and p.Shape == Enum.PartType.Block, "Manual box pass accepts only block Parts")
			table.insert(sections, {cf=p.CFrame, size=p.Size, floors=p:GetAttribute("RequestedFloors"), core=p:GetAttribute("GenerateCore")})
		end
	end
	return Manual.Stage(name, sections, options)
end

-- Rebuild at the current pivot, including after a user moves the whole Model.
-- Existing structure remains untouched until Apply is explicitly called.
function Manual.Rebuild(building, options)
	editOnly()
	assert(building:GetAttribute("ManualShellVersion") == 1, "Not a manual shell building")
	local shift = building:GetPivot() * building:GetAttribute("ManualShellFrame"):Inverse()
	local sections = {}
	for _, s in HttpService:JSONDecode(building:GetAttribute("ManualShellSpec")) do
		table.insert(sections, {cf=shift * CFrame.new(table.unpack(s.cf)), size=Vector3.new(table.unpack(s.size)), floors=s.floors, core=s.core})
	end
	return Manual.Stage(building.Name, sections, options or {furnished=building:GetAttribute("StructuralOnly") ~= true})
end

-- Apply one inspected stage. Only the explicitly supplied old model is archived.
function Manual.Apply(staged, parent, replace)
	editOnly()
	assert(parent and (parent:IsA("Folder") or parent:IsA("Model")) and parent:IsDescendantOf(workspace), "Target must be a Workspace folder/model")
	assert(staged.Parent == ServerStorage:FindFirstChild("ManualShellStages") and staged:GetAttribute("ManualShellStaged"), "Not a staged manual building")
	checkStructure(staged)
	if replace then
		assert(replace ~= staged and replace:IsA("Model") and replace.Parent == parent, "Replacement must be an exact model in target folder")
	end
	local duplicate = parent:FindFirstChild(staged.Name)
	assert(not duplicate or duplicate == replace, "A different building already has this name")
	local history = game:GetService("ChangeHistoryService")
	history:SetWaypoint("Before applying manual shell")
	-- A visually inspected stage may have been moved before it is applied.
	-- Keep the whole-building hit cull centered on its current geometry.
	local cf, size = staged:GetBoundingBox()
	staged:SetAttribute("InteriorBBoxCFrame", cf)
	staged:SetAttribute("InteriorBBoxSize", size)
	local archive
	if replace then
		archive = Instance.new("Folder")
		archive.Name = "ManualShellArchive_" .. HttpService:GenerateGUID(false)
		archive.Parent = ServerStorage
		replace.Parent = archive
	end
	staged.Parent = parent
	staged:SetAttribute("ManualShellStaged", false)
	history:SetWaypoint("Applied manual shell")
	return staged, archive
end

return Manual
