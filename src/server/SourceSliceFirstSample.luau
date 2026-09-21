--!nonstrict
-- First real source-slice sample. Stage only; never Apply from this module.
-- Roblox caches require(). Clone Builder+sample into a throwaway folder:
--   local s=game.ServerScriptService.Server
--   local f=Instance.new("Folder"); f.Name="SourceSliceFresh"; f.Parent=s
--   s.PolygonSlab:Clone().Parent=f
--   s.SourceSliceBuilder:Clone().Parent=f
--   local m=s.SourceSliceFirstSample:Clone(); m.Parent=f
--   local ok,r=pcall(function() return require(m).Stage() end)
--   f:Destroy(); if not ok then error(r) end; return r
-- .Hide() removes the orange overlay. Do not move or delete Workspace.Shibuya.
local Sample = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local Builder = require(script.Parent.SourceSliceBuilder)
local LIVE_NAME = "BuildingSmooth_1_-21438_3207_4019"
local REVIEW = "SourceSliceReview_FirstSample"
-- Last closed source slice before roof-equipment holes.
local CLEAN_TOP_Y = 477.623

local function live()
	return assert(workspace.Buildings:FindFirstChild(LIVE_NAME), "Live candidate is missing: " .. LIVE_NAME)
end

local function yawOf(cf)
	return math.atan2(-cf.RightVector.Z, cf.RightVector.X)
end

local function liveSlabs(model)
	local interior = assert(model:FindFirstChild("Interior"), "Live interior missing")
	local rows = {}
	for _, floor in interior:GetChildren() do
		local slab
		for _, part in floor:GetChildren() do
			if part.Name == "Slab" and part:IsA("BasePart") then slab = part; break end
		end
		if slab then
			table.insert(rows, {
				name = floor.Name,
				bottom = slab.Position.Y - slab.Size.Y / 2,
				thickness = slab.Size.Y,
			})
		end
	end
	table.sort(rows, function(a, b) return a.bottom < b.bottom end)
	return rows
end

function Sample.Plan()
	local model = live()
	local massing = Http:JSONDecode(assert(model:GetAttribute("SmoothMassing"), "Live SmoothMassing missing"))
	local frame = assert(model:GetAttribute("SmoothFrame"), "Live SmoothFrame missing")
	local baseY = model:GetAttribute("SourceBaseY")
	if type(baseY) ~= "number" then baseY = frame.Position.Y - model:GetAttribute("InteriorBBoxSize").Y / 2 end
	local points = massing.tiers[1].points
	local loX, hiX, loZ, hiZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in points do
		loX = math.min(loX, p[1]); hiX = math.max(hiX, p[1])
		loZ = math.min(loZ, p[2]); hiZ = math.max(hiZ, p[2])
	end
	local rectangle = {{loX, loZ}, {hiX, loZ}, {hiX, hiZ}, {loX, hiZ}}
	local kept = {}
	for _, row in liveSlabs(model) do
		if row.bottom + row.thickness <= CLEAN_TOP_Y then table.insert(kept, row) end
	end
	assert(#kept >= 2, "Not enough live floors below the source equipment cutoff")
	local levels = {}
	for _, row in kept do
		table.insert(levels, {
			y = row.bottom - baseY,
			thickness = row.thickness,
			pieces = {rectangle},
		})
	end
	local coreSize = assert(model:GetAttribute("CoreSize"), "Live CoreSize missing")
	local rot = {frame:GetComponents()}
	return {
		id = "1_-21438_3207_4019",
		origin = {
			x = frame.Position.X,
			y = baseY,
			z = frame.Position.Z,
			yaw = yawOf(frame),
			r00 = rot[4], r01 = rot[5], r02 = rot[6],
			r10 = rot[7], r11 = rot[8], r12 = rot[9],
			r20 = rot[10], r21 = rot[11], r22 = rot[12],
		},
		levels = levels,
		core = {
			minX = -coreSize.X / 2,
			minZ = -coreSize.Z / 2,
			maxX = coreSize.X / 2,
			maxZ = coreSize.Z / 2,
		},
		sourceInfo = {
			liveModel = LIVE_NAME,
			sourceKey = model:GetAttribute("ShibuyaSourceKey"),
			baseY = baseY,
			copiedFloors = #kept - 1,
			copiedRoof = kept[#kept].name,
			sourceCleanTopY = CLEAN_TOP_Y,
			note = "Copies live yawed rectangle and exact slab elevations through the last floor below roof-equipment holes.",
		},
	}
end

local function lookAt(model)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local cf, size = model:GetBoundingBox()
	local focus = cf.Position
	camera.CameraType = Enum.CameraType.Fixed
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(-280, 160, 220), focus)
	camera.Focus = CFrame.new(focus)
	pcall(function() Selection:Set({model}) end)
	return {focus = {focus.X, focus.Y, focus.Z}, size = {size.X, size.Y, size.Z}}
end

function Sample.Hide()
	local folder = workspace:FindFirstChild(REVIEW)
	if folder then folder:Destroy() end
	return true
end

function Sample.Show()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	Sample.Hide()
	local source = live()
	local built = Builder.Build(Sample.Plan())
	local audit = Builder.Audit(built)
	assert(audit.summary.badBuildings == 0, "First sample failed builder audit")
	assert(audit.summary.wedges == 0, "Yawed rectangle still triangulated into wedges")
	local liveSlab, prevSlab
	for _, part in source.Interior.Floor1:GetChildren() do if part.Name == "Slab" then liveSlab = part break end end
	for _, part in built.Interior.Floor1:GetChildren() do if part.Name == "Slab" then prevSlab = part break end end
	assert(liveSlab and prevSlab, "Floor1 slabs missing")
	assert(liveSlab.CFrame.RightVector:Dot(prevSlab.CFrame.RightVector) > 0.999,
		"Preview slab yaw does not match the live building")
	local previewBox, previewSize = built:GetBoundingBox()
	local liveBox, liveSize = source:GetBoundingBox()
	assert(math.abs((previewBox.Position.Y - previewSize.Y / 2) - (liveBox.Position.Y - liveSize.Y / 2)) < 0.05,
		"Preview base does not match the live building")
	for _, part in built:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = Color3.fromRGB(255, 140, 40)
			part.Material = Enum.Material.SmoothPlastic
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = REVIEW
	folder:SetAttribute("SourceSliceReview", true)
	built.Parent = folder
	folder.Parent = workspace
	local view = lookAt(source)
	return {
		preview = built.Name,
		floors = built:GetAttribute("GeneratedFloors"),
		wedges = audit.summary.wedges,
		slabParts = audit.summary.slabParts,
		structuralParts = audit.summary.structuralParts,
		live = source.Name,
		previewBottom = previewBox.Position.Y - previewSize.Y / 2,
		liveBottom = liveBox.Position.Y - liveSize.Y / 2,
		camera = view,
	}
end

function Sample.Stage()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	for _, child in Storage:GetChildren() do
		if child:GetAttribute("SourceSliceFirstSample") then child:Destroy() end
	end
	local stage, failures = Builder.StagePlans({Sample.Plan()})
	assert(#failures == 0, "First sample staging failed")
	stage:SetAttribute("SourceSliceFirstSample", true)
	stage:SetAttribute("LiveModel", LIVE_NAME)
	local shown = Sample.Show()
	shown.stage = stage.Name
	print("SOURCE_SLICE_FIRST_SAMPLE", Http:JSONEncode(shown))
	return shown
end

return Sample
