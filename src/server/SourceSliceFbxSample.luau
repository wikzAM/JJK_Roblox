--!nonstrict
-- First sample built from ACTUAL FBX geometry (tools/source_slices/world_triangles.npz),
-- not from live SmoothMassing. Stage/overlay only; never Apply from this module.
--
-- Seed: the five grey models named BuildingSmooth_16_7714_* are ONE physical building.
-- Horizontal sections of the FBX under their shared centre are a single closed polygon
-- from Y 109.70 to Y 311.70: a yawed 141.6 x 135.2 rectangle up to Y ~296.5, then an
-- L-shaped setback to the top. The real building is yawed 21.5 deg off the world
-- axes and the greys are world-axis boxes around it, so this overlay is the first
-- one that can beat grey instead of copying it.
--
-- HOW MUCH it beats grey by is currently UNMEASURED. Both published figures are
-- withdrawn: 2.00x divided an AABB by a tight rotated rectangle (a 1.68x artifact
-- at this yaw all by itself), and the 1.79x "correction" measured all eight corners
-- of every part, which counts the empty half of every WedgePart's Size box. Compare()
-- now measures both sides the same way, through PartExtents. Quote its number, and
-- record it in the handoff doc -- do not resurrect either old one.
--
-- Roblox caches require(). Clone Builder+PolygonSlab+this module into a throwaway
-- folder, or loadstring the synced Source (see the handoff doc).
--   local s=game.ServerScriptService.Server
--   local f=Instance.new("Folder"); f.Name="SourceSliceFresh"; f.Parent=s
--   s.PolygonSlab:Clone().Parent=f
--   s.PartExtents:Clone().Parent=f
--   s.SourceSliceBuilder:Clone().Parent=f
--   local m=s.SourceSliceFbxSample:Clone(); m.Parent=f
--   local ok,r=pcall(function() return require(m).Stage() end)
--   f:Destroy(); if not ok then error(r) end; return r
-- .Hide() removes the overlay. Do not move or delete the Shibuya FBX model.
local Sample = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")
local Collection = game:GetService("CollectionService")
local Builder = require(script.Parent.SourceSliceBuilder)
local PartExtents = require(script.Parent.PartExtents)

local REVIEW = "SourceSliceReview_FbxSample"
-- The tallest member carries the live floor elevations we reuse.
local FLOOR_SOURCE = "BuildingSmooth_16_7714_2072_-5958"
local MEMBERS = {
	"BuildingSmooth_16_7714_2072_-5958",
	"BuildingSmooth_16_7714_3083_-5951_Body01",
	"BuildingSmooth_16_7714_3083_-5951_Body02",
	"BuildingSmooth_16_7714_3083_-5951_Body03",
	"BuildingSmooth_16_7714_3083_-5951_Body04",
}

-- Frame fitted to the FBX section's minimum-area rectangle, not to any live model.
local ORIGIN_X, ORIGIN_Z = 771.455, -595.699
local YAW = -2.766790
-- Binary-searched extent of closed FBX sections under the shared centre.
local FBX_BOTTOM, SETBACK_Y, FBX_TOP = 109.70, 296.5, 311.70

-- Local XZ in the frame above, snapped to the section's minimum-area rectangle.
-- The measured ring is four-sided but its corners disagree by up to 0.7 studs
-- (FBX export noise), and PolygonSlab only emits a single Part when
-- isRectangle() passes - four sides alone is not enough. Unsnapped, this
-- triangulated every floor and produced 56 wedges.
local MAIN = {
	{-70.816, -67.620}, {-70.816, 67.620}, {70.816, 67.620}, {70.816, -67.620},
}
local SETBACK = {
	{-62.616, -20.011}, {-62.672, 10.861}, {-69.097, 10.805}, {-69.127, 65.921},
	{69.163, 65.949}, {69.023, 13.722}, {38.803, 14.192}, {38.866, -66.003},
	{-69.043, -65.953}, {-69.060, -20.021},
}
-- Comfortably inside MAIN n SETBACK (the largest centred rectangle that fits is 76 x 118).
local CORE_HALF_X, CORE_HALF_Z = 26, 26

local SLAB = 1.5 / 0.28
local PITCH = SLAB + 3.5 / 0.28

local function buildings()
	return assert(workspace:FindFirstChild("Buildings"), "Workspace.Buildings is missing")
end

local function member(name)
	return buildings():FindFirstChild(name)
end

-- Live slab elevations, so the overlay lines up with the neighbourhood rather
-- than inventing its own storey heights.
--
-- Measured from real corners via PartExtents. The previous reading,
-- `part.Position.Y - part.Size.Y/2`, assumed the thickness axis was world Y.
-- PolygonSlab puts a wedge's thickness on LOCAL X (its CFrame RightVector is the
-- vertical one), so on a BuildingSmooth floor -- which is mostly WedgeParts --
-- that read a triangle's height as its thickness and threw the storey hundreds of
-- studs below the FBX band. Every row then failed the band filter, fewer than two
-- survived, and Plan() silently fell back to `elevations = "uniform"`.
local function isSlab(part)
	return part:IsA("BasePart")
		and (part:GetAttribute("PolygonSlab") == true or part.Name == "Slab")
		and not Collection:HasTag(part, "BuildingCore")
end

local function liveSlabs(model)
	local interior = model and model:FindFirstChild("Interior")
	if not interior then return nil end
	local rows = PartExtents.Storeys(interior, isSlab)
	return #rows > 0 and rows or nil
end

function Sample.Plan()
	local levels, source = {}, "uniform"
	-- The live slabs start at 109.34, just under the FBX band's 109.70, so the
	-- base is whatever the lowest kept storey actually is. Deriving it instead of
	-- assuming FBX_BOTTOM keeps every level y >= 0 and the origin on the slab.
	local baseY = FBX_BOTTOM
	local rows = liveSlabs(member(FLOOR_SOURCE))
	if rows then
		local kept, previousTop = {}, nil
		for _, row in rows do
			-- Keep only storeys inside the closed FBX band, below the setback.
			if row.bottom >= FBX_BOTTOM - 1 and row.bottom + row.thickness <= SETBACK_Y then
				if not previousTop or row.bottom - previousTop >= 2 / 0.28 then
					table.insert(kept, row)
					previousTop = row.bottom + row.thickness
				end
			end
		end
		if #kept >= 2 then
			baseY = kept[1].bottom
			for _, row in kept do
				table.insert(levels, {
					y = row.bottom - baseY,
					thickness = row.thickness,
					pieces = {MAIN},
				})
			end
			source = FLOOR_SOURCE
		end
	end
	if #levels == 0 then
		baseY = FBX_BOTTOM
		local y = 0
		while baseY + y + SLAB <= SETBACK_Y do
			table.insert(levels, {y = y, thickness = SLAB, pieces = {MAIN}})
			y += PITCH
		end
	end
	assert(#levels >= 2, "No usable storeys inside the FBX band")
	-- Final level is the Roof: the FBX setback, which grey does not have at all.
	-- Drop top storeys that would leave the roof less than the builder's 2 m clear.
	local roofY = SETBACK_Y - baseY
	while #levels > 1 do
		local previous = levels[#levels]
		if roofY - previous.y - previous.thickness >= 2 / 0.28 then break end
		table.remove(levels)
	end
	assert(#levels >= 1 and roofY - levels[#levels].y - levels[#levels].thickness >= 2 / 0.28,
		"Setback roof crowds the top storey")
	table.insert(levels, {y = roofY, thickness = SLAB, pieces = {SETBACK}})

	return {
		id = "fbx_16_7714",
		origin = {x = ORIGIN_X, y = baseY, z = ORIGIN_Z, yaw = YAW},
		levels = levels,
		core = {minX = -CORE_HALF_X, minZ = -CORE_HALF_Z, maxX = CORE_HALF_X, maxZ = CORE_HALF_Z},
		sourceInfo = {
			origin = "world_triangles.npz horizontal sections",
			elevations = source,
			baseY = baseY,
			fbxBottom = FBX_BOTTOM,
			setbackY = SETBACK_Y,
			fbxTop = FBX_TOP,
			replaces = MEMBERS,
			note = "One Building per physical building. Footprint is the FBX section, "
				.. "not a world-axis box around it.",
		},
	}
end

-- Reports how much smaller the FBX footprint is than the grey boxes it would replace.
--
-- MEASUREMENT CONTRACT -- read before quoting any number from here.
-- The retracted "grey is 2.00x too big" claim divided a TIGHT ROTATED rectangle
-- (the FBX section) by an AXIS-ALIGNED box (grey). Those are not the same kind of
-- quantity: a rotated rectangle's own AABB is 1.68x itself at this 21.5 deg yaw.
-- Both sides here are therefore measured the same way -- world-space axis-aligned
-- extents of real part geometry -- and the polygon-vs-AABB ratio is reported
-- separately and labelled, never as an oversize factor.
-- Grey is also measured with PartExtents rather than Model:GetBoundingBox(),
-- which is PIVOT-oriented; these models' pivots are not upright
-- (BuildingSmooth_16_7714_2072_-5958 has RightVector 0.000, 0.907, 0.420), so its
-- size.X * size.Z is not a horizontal area at all.
local function polygonArea(points)
	local twice = 0
	for index, a in points do
		local b = points[index % #points + 1]
		twice += a[1] * b[2] - b[1] * a[2]
	end
	return math.abs(twice) / 2
end

-- World AABB of a local-frame polygon under the sample's origin yaw.
local function polygonWorldAABB(points)
	local frame = CFrame.new(ORIGIN_X, 0, ORIGIN_Z) * CFrame.Angles(0, YAW, 0)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in points do
		local world = frame * Vector3.new(p[1], 0, p[2])
		minX, maxX = math.min(minX, world.X), math.max(maxX, world.X)
		minZ, maxZ = math.min(minZ, world.Z), math.max(maxZ, world.Z)
	end
	return {minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ,
		sizeX = maxX - minX, sizeZ = maxZ - minZ, area = (maxX - minX) * (maxZ - minZ)}
end

function Sample.Compare()
	local rows, present = {}, {}
	for _, name in MEMBERS do
		local model = member(name)
		if model then
			table.insert(present, model)
			local footprint = PartExtents.Footprint(model)
			table.insert(rows, {name = name, footprint = footprint})
		else
			table.insert(rows, {name = name, missing = true})
		end
	end
	local grey = #present > 0 and PartExtents.Footprint(present) or nil
	local sectionArea = polygonArea(MAIN)
	local sectionAABB = polygonWorldAABB(MAIN)

	-- Material area, storey by storey, inside the band MAIN actually describes.
	-- This is the only measurement that can answer "is grey carrying more floor
	-- than the real building". Extents cannot: grey turned out to be almost exactly
	-- the section's bounding box (0.017 studs apart), and a rotated rectangle and its
	-- own bounding box have the SAME extent by construction, so any extent ratio is
	-- pinned at 1.0 no matter how much extra material grey holds.
	local storeys, widest, estimated = PartExtents.Storeys(present, isSlab), nil, 0
	local inBand = {}
	for _, row in storeys do
		if row.bottom >= FBX_BOTTOM - 1 and row.bottom + row.thickness <= SETBACK_Y then
			table.insert(inBand, row)
			estimated += row.estimated
			if not widest or row.area > widest.area then widest = row end
		end
	end

	return {
		members = rows,
		liveCount = #MEMBERS,
		foundCount = #present,
		-- THE number. Material against material, both horizontal areas of real geometry.
		greyFloorArea = widest and widest.area,
		fbxSectionArea = sectionArea,
		greyAreaFactor = (widest and sectionArea > 0) and widest.area / sectionArea or 0,
		greyStoreysInBand = #inBand,
		greyTotalStoreys = #storeys,
		-- Non-zero means some areas were inferred, not read from SlabFootprintArea.
		greyEstimatedParts = estimated,
		-- Extents. Useful for checking placement, USELESS as an oversize measure -- see above.
		greyFootprint = grey,
		sliceFootprint = sectionAABB,
		greyExtentFactor = (grey and sectionAABB.area > 0) and grey.area / sectionAABB.area or 0,
	}
end

local function lookAt()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local focus = Vector3.new(ORIGIN_X, (FBX_BOTTOM + FBX_TOP) / 2, ORIGIN_Z)
	camera.CameraType = Enum.CameraType.Fixed
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(-300, 170, 240), focus)
	camera.Focus = CFrame.new(focus)
	return {focus = {focus.X, focus.Y, focus.Z}}
end

function Sample.Hide()
	local folder = workspace:FindFirstChild(REVIEW)
	if folder then folder:Destroy() end
	return true
end

function Sample.Show()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	Sample.Hide()
	local plan = Sample.Plan()
	local built = Builder.Build(plan)
	local audit = Builder.Audit(built)
	assert(audit.summary.badBuildings == 0, "FBX sample failed builder audit")

	-- Measured from real part corners, not Model:GetBoundingBox(). GetBoundingBox
	-- uses each part's full Size box, and a WedgePart fills only half of its own --
	-- the mirror corner of its two legs is empty. That inflation, not any geometry
	-- error, is the whole of the previously unexplained overlay overhang: 16 roof
	-- wedges reported 201.8 x 187.1 where the real footprint is 181.3 x 177.7.
	local measured = assert(PartExtents.Footprint(built), "Preview built no parts")
	local bottom, top = measured.minY, measured.maxY
	-- Reported, not asserted. A hard assert here aborted the whole preview and
	-- threw away the numbers needed to explain the drift; the overlay is worth
	-- seeing even when the base is off, and baseDrift says by how much.
	local drift = bottom - plan.origin.y
	if math.abs(drift) > 0.05 then
		warn(string.format(
			"SourceSliceFbxSample: preview base %.3f is %.3f off its plan origin %.3f (level1 y=%.3f)",
			bottom, drift, plan.origin.y, plan.levels[1].y))
	end
	assert(top <= FBX_TOP + 0.5, "Preview rose above the closed FBX band")

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
	pcall(function() Selection:Set({built}) end)

	local comparison = Sample.Compare()
	return {
		preview = built.Name,
		floors = built:GetAttribute("GeneratedFloors"),
		wedges = audit.summary.wedges,
		slabParts = audit.summary.slabParts,
		structuralParts = audit.summary.structuralParts,
		previewBottom = bottom,
		previewTop = top,
		planOriginY = plan.origin.y,
		baseDrift = drift,
		firstLevelY = plan.levels[1].y,
		elevations = plan.sourceInfo.elevations,
		measuredSizeX = measured.sizeX,
		measuredSizeZ = measured.sizeZ,
		measuredParts = measured.parts,
		-- Predicted from MAIN under the origin yaw; measured should equal this.
		predictedSizeX = comparison.sliceFootprint.sizeX,
		predictedSizeZ = comparison.sliceFootprint.sizeZ,
		greyAreaFactor = comparison.greyAreaFactor,
		greyFloorArea = comparison.greyFloorArea,
		fbxSectionArea = comparison.fbxSectionArea,
		greyStoreysInBand = comparison.greyStoreysInBand,
		greyEstimatedParts = comparison.greyEstimatedParts,
		greyExtentFactor = comparison.greyExtentFactor,
		greySizeX = comparison.greyFootprint and comparison.greyFootprint.sizeX,
		greySizeZ = comparison.greyFootprint and comparison.greyFootprint.sizeZ,
		replacesLiveModels = comparison.liveCount,
		camera = lookAt(),
	}
end

function Sample.Stage()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	for _, child in Storage:GetChildren() do
		if child:GetAttribute("SourceSliceFbxSample") then child:Destroy() end
	end
	local stage, failures = Builder.StagePlans({Sample.Plan()})
	assert(#failures == 0, "FBX sample staging failed: " .. Http:JSONEncode(failures))
	stage:SetAttribute("SourceSliceFbxSample", true)
	stage:SetAttribute("Members", table.concat(MEMBERS, ","))
	local shown = Sample.Show()
	shown.stage = stage.Name
	print("SOURCE_SLICE_FBX_SAMPLE", Http:JSONEncode(shown))
	return shown
end

return Sample
