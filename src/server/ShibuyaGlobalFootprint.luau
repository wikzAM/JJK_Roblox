--!nonstrict
-- Read-only global loop tracking inside a legacy model's source envelope.
-- Unlike component massing, unrelated closed loops are tracked independently.
local Footprint = {}

local Http = game:GetService("HttpService")
local History = game:GetService("ChangeHistoryService")
local Storage = game:GetService("ServerStorage")
local FRACTIONS = {0.06, 0.14, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.82, 0.90, 0.97}
local DEFAULTS = {
	RegionPadding = 12,
	MinTrackSamples = 3,
	MinTrackSpan = 0.18,
	MinTrackHeight = 30,
	MaxFirstFraction = 0.22,
	MinLastFraction = 0.50,
	MaxCentroidShift = 18,
	MinAreaRatio = 0.78,
	MaxShapeDistance = 8,
	MinGroundCoverage = 0.78,
	MinVolumeCoverage = 0.72,
	MinBindingOverlap = 0.05,
	MinAreaCoverage = 0.45,
	MaxAreaCoverage = 1.45,
}
local DEFAULT_SLICE = {
	WeldTolerance = 0.8,
	MaxSeamGap = 4,
	MaxCornerGap = 4,
	MaxCornerExtension = 4,
	SimplifyTolerance = 1.2,
	MinArea = 150,
	MinWidth = 10,
}

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function configured(options)
	local result = table.clone(DEFAULTS)
	for key, value in options or {} do
		if key == "SliceOptions" then continue end
		assert(DEFAULTS[key] ~= nil, "Unknown global footprint option: " .. tostring(key))
		result[key] = value
	end
	for key, value in result do
		assert(type(value) == "number" and value >= 0, "Invalid global footprint option: " .. key)
	end
	for _, key in {"MinTrackSamples"} do assert(result[key] >= 1 and result[key] % 1 == 0, key .. " must be an integer") end
	for _, key in {
		"MinTrackSpan", "MaxFirstFraction", "MinLastFraction", "MinAreaRatio",
		"MinGroundCoverage", "MinVolumeCoverage", "MinBindingOverlap", "MinAreaCoverage",
	} do assert(result[key] <= 1, key .. " must be at most one") end
	result.SliceOptions = table.clone(DEFAULT_SLICE)
	for key, value in (options and options.SliceOptions) or {} do result.SliceOptions[key] = value end
	return result
end

local function bounds(model)
	local cf, size = model:GetAttribute("InteriorBBoxCFrame"), model:GetAttribute("InteriorBBoxSize")
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then cf, size = model:GetBoundingBox() end
	local corners = {}
	for x = -1, 1, 2 do for z = -1, 1, 2 do
		table.insert(corners, cf:PointToWorldSpace(Vector3.new(x * size.X / 2, 0, z * size.Z / 2)))
	end end
	local lo, hi = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, point in corners do
		local p = Vector2.new(point.X, point.Z)
		lo, hi = lo:Min(p), hi:Max(p)
	end
	return cf, size, lo, hi, cf.Position.Y - size.Y / 2, cf.Position.Y + size.Y / 2
end

local function nearbyComponents(components, lo, hi, lowY, highY, padding)
	local result = {}
	for _, group in components do
		if group.max.X >= lo.X - padding and group.min.X <= hi.X + padding
			and group.max.Z >= lo.Y - padding and group.min.Z <= hi.Y + padding
			and group.max.Y >= lowY and group.min.Y <= highY then
			table.insert(result, group)
		end
	end
	return result
end

local function inRegion(point, lo, hi, padding)
	return point.X >= lo.X - padding and point.X <= hi.X + padding
		and point.Y >= lo.Y - padding and point.Y <= hi.Y + padding
end

local function trackLoops(rows, massing, options)
	local tracks, previous = {}, {}
	for sampleIndex, row in rows do
		local nextPrevious, used = {}, {}
		for _, loop in row.loops do
			local best, bestCost
			for _, track in previous do
				if used[track] then continue end
				local prior = track.members[#track.members].loop
				local areaRatio = math.min(prior.area, loop.area) / math.max(prior.area, loop.area)
				local centroidShift = (prior.centroid - loop.centroid).Magnitude
				if areaRatio < options.MinAreaRatio or centroidShift > options.MaxCentroidShift then continue end
				local shapeDistance = massing.ShapeDistance(prior.points, loop.points)
				if shapeDistance > options.MaxShapeDistance then continue end
				local cost = shapeDistance + centroidShift * 0.25 + (1 - areaRatio) * 10
				if not bestCost or cost < bestCost then best, bestCost = track, cost end
			end
			if not best then
				best = {members = {}, firstSample = sampleIndex, lastSample = sampleIndex}
				table.insert(tracks, best)
			end
			table.insert(best.members, {loop = loop, fraction = row.fraction, y = row.y})
			best.lastSample = sampleIndex
			used[best] = true
			table.insert(nextPrevious, best)
		end
		previous = nextPrevious
	end
	return tracks
end

local function inside(point, polygon)
	local contained = false
	for index, a in polygon do
		local b = polygon[index % #polygon + 1]
		local delta = b - a
		local length2 = delta:Dot(delta)
		local t = math.clamp((point - a):Dot(delta) / math.max(length2, 1e-12), 0, 1)
		if (point - (a + delta * t)).Magnitude <= 1e-5 then return true end
		if (a.Y > point.Y) ~= (b.Y > point.Y)
			and point.X < a.X + (point.Y - a.Y) * (b.X - a.X) / (b.Y - a.Y) then
			contained = not contained
		end
	end
	return contained
end

local function groundCoverage(model, polygons)
	local raw = model:GetAttribute("InteriorGrid")
	local cf, size = model:GetAttribute("InteriorBBoxCFrame"), model:GetAttribute("InteriorBBoxSize")
	if type(raw) ~= "string" or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then return nil end
	local ok, grid = pcall(Http.JSONDecode, Http, raw)
	if not ok or type(grid) ~= "table" or type(grid.occ) ~= "table" or type(grid.occ[1]) ~= "string" then return nil end
	local mask = grid.occ[1]
	local occupied, covered = 0, 0
	for i = 1, grid.nx do for j = 1, grid.nz do
		local index = (i - 1) * grid.nz + j
		if mask:byte(index) ~= 49 then continue end
		occupied += 1
		local x = math.min(grid.minX + (i - 0.5) * grid.cell, size.X / 2 - 1e-4)
		local z = math.min(grid.minZ + (j - 0.5) * grid.cell, size.Z / 2 - 1e-4)
		local world = cf:PointToWorldSpace(Vector3.new(x, 0, z))
		local point = Vector2.new(world.X, world.Z)
		for _, polygon in polygons do
			if inside(point, polygon) then covered += 1; break end
		end
	end end
	return occupied > 0 and covered / occupied or 0, occupied * grid.cell * grid.cell
end

local function volumeCoverage(model, tracks)
	local raw = model:GetAttribute("InteriorGrid")
	local cf, size = model:GetAttribute("InteriorBBoxCFrame"), model:GetAttribute("InteriorBBoxSize")
	if type(raw) ~= "string" or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then return nil end
	local ok, grid = pcall(Http.JSONDecode, Http, raw)
	if not ok or type(grid) ~= "table" or type(grid.occ) ~= "table" then return nil end
	local occupied, covered = 0, 0
	for k = 1, grid.floors do
		local mask = grid.occ[k]
		if type(mask) ~= "string" then continue end
		local bottom
		if k <= 1 then bottom = -size.Y / 2
		else bottom = -size.Y / 2 + 1.5 + grid.ground + (k - 2) * (grid.clearUpper + 1.5) end
		for i = 1, grid.nx do for j = 1, grid.nz do
			local index = (i - 1) * grid.nz + j
			if mask:byte(index) ~= 49 then continue end
			occupied += 1
			local x = math.min(grid.minX + (i - 0.5) * grid.cell, size.X / 2 - 1e-4)
			local z = math.min(grid.minZ + (j - 0.5) * grid.cell, size.Z / 2 - 1e-4)
			local world = cf:PointToWorldSpace(Vector3.new(x, bottom, z))
			local point = Vector2.new(world.X, world.Z)
			for _, track in tracks do
				if world.Y >= track.baseY and world.Y <= track.topY
					and inside(point, track.representative.points) then
					covered += 1
					break
				end
			end
		end end
	end
	return occupied > 0 and covered / occupied or 0
end

local function trackBounds(track)
	local lo, hi = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, point in track.representative.points do lo, hi = lo:Min(point), hi:Max(point) end
	return lo, hi
end

local function modelTouchesTracks(model, tracks)
	local _, _, lo, hi, lowY, highY = bounds(model)
	for _, track in tracks do
		if math.min(highY, track.topY) < math.max(lowY, track.baseY) then continue end
		local trackLo, trackHi = trackBounds(track)
		if trackHi.X >= lo.X and trackLo.X <= hi.X and trackHi.Y >= lo.Y and trackLo.Y <= hi.Y then return true end
	end
	return false
end

local function smoothBlockers(folder, tracks)
	local blockers = {}
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") or not model.Name:match("^BuildingSmooth_") then continue end
		local _, _, lo, hi, lowY, highY = bounds(model)
		for _, track in tracks do
			local vertical = math.max(0, math.min(highY, track.topY) - math.max(lowY, track.baseY))
			if vertical <= 0 then continue end
			local height = math.max(1, math.min(highY - lowY, track.topY - track.baseY))
			if vertical / height < 0.2 then continue end
			local loop = track.representative
			local center = (lo + hi) / 2
			local overlap = inRegion(loop.centroid, lo, hi, 0) or inside(center, loop.points)
			if not overlap then
				for _, point in loop.points do
					if inRegion(point, lo, hi, 0) then overlap = true; break end
				end
			end
			if overlap then table.insert(blockers, model); break end
		end
	end
	table.sort(blockers, function(a, b) return a.Name < b.Name end)
	return blockers
end

local function overlappingTracks(tracks)
	local overlaps = 0
	for a = 1, #tracks do for b = a + 1, #tracks do
		local first, second = tracks[a], tracks[b]
		if math.min(first.lastY, second.lastY) < math.max(first.firstY, second.firstY) then continue end
		local p, q = first.representative, second.representative
		if inside(p.centroid, q.points) or inside(q.centroid, p.points)
			or inside(p.points[1], q.points) or inside(q.points[1], p.points) then
			overlaps += 1
		end
	end end
	return overlaps
end

function Footprint.DiagnoseModel(model, components, options)
	editOnly()
	assert(model and model:IsA("Model") and model.Name:match("^BuildingAuto_"), "Pass a legacy BuildingAuto model")
	options = configured(options)
	components = components or require(script.Parent.ShibuyaGeometry).Scan()
	local _, sourceSize, lo, hi, lowY, highY = bounds(model)
	local localComponents = nearbyComponents(components, lo, hi, lowY, highY, options.RegionPadding)
	local massing = require(script.Parent.ShibuyaMassing)
	local rows, sliceFailures = {}, {}
	for _, fraction in FRACTIONS do
		local y = lowY + sourceSize.Y * fraction
		local segments = massing.SectionsAt(localComponents, y)
		local loops, reason, stats = massing.ExtractSectionLoops(segments, options.SliceOptions)
		local accepted = {}
		for _, loop in loops or {} do
			if not loop.hole and inRegion(loop.centroid, lo, hi, options.RegionPadding) then table.insert(accepted, loop) end
		end
		if reason then sliceFailures[reason] = (sliceFailures[reason] or 0) + 1 end
		table.insert(rows, {
			fraction = fraction,
			y = y,
			loops = accepted,
			segments = #segments,
			invalidComponents = stats and stats.invalidComponents or 0,
		})
	end
	local tracks, accepted = trackLoops(rows, massing, options), {}
	for _, track in tracks do
		local first, last = track.members[1], track.members[#track.members]
		local span = last.fraction - first.fraction
		if #track.members < options.MinTrackSamples or span < options.MinTrackSpan
			or last.y - first.y < options.MinTrackHeight
			or first.fraction > options.MaxFirstFraction or last.fraction < options.MinLastFraction then
			continue
		end
		table.sort(track.members, function(a, b) return a.loop.area < b.loop.area end)
		local representative = track.members[math.ceil(#track.members / 2)].loop
		table.sort(track.members, function(a, b) return a.fraction < b.fraction end)
		track.representative = representative
		track.firstFraction, track.lastFraction, track.span = first.fraction, last.fraction, span
		track.firstY, track.lastY = first.y, last.y
		track.baseY = math.max(lowY, first.y - sourceSize.Y * 0.05)
		track.topY = math.min(highY, last.y + sourceSize.Y * 0.05)
		table.insert(accepted, track)
	end
	local polygons, polygonArea = {}, 0
	for _, track in accepted do
		table.insert(polygons, track.representative.points)
		polygonArea += track.representative.area
	end
	local coverage, occupiedArea = groundCoverage(model, polygons)
	local areaCoverage = occupiedArea and polygonArea / math.max(occupiedArea, 1) or 0
	local verticalCoverage = volumeCoverage(model, accepted)
	local ambiguousOverlaps = overlappingTracks(accepted)
	local complete = #accepted > 0 and verticalCoverage and verticalCoverage >= options.MinVolumeCoverage
		and ambiguousOverlaps == 0
	local plans = {}
	if #accepted > 0 then
		for index, track in accepted do
			local loop = track.representative
			local center = loop.centroid
			local points = {}
			for _, point in loop.points do table.insert(points, point - center) end
			local baseY, topY = track.baseY, track.topY
			local height = topY - baseY
			if height >= 30 then
				local min, max = points[1], points[1]
				for _, point in points do min, max = min:Min(point), max:Max(point) end
				table.insert(plans, {
					key = model:GetAttribute("ShibuyaSourceKey") .. "_global" .. index,
					frame = CFrame.new(center.X, baseY, center.Y),
					points = points,
					tiers = {{bottom = 0, top = height, points = points}},
					height = height,
					sourceBaseY = baseY,
					sourceTopY = highY,
					roofTrim = highY - topY,
					area = loop.area,
					confidence = math.clamp(0.55 + #track.members / #FRACTIONS * 0.3 + track.span * 0.15, 0, 0.9),
					reason = "Persistent independent global section loop",
					method = "global multi-loop track",
					size = Vector3.new(max.X - min.X, height, max.Y - min.Y),
					oldModel = model,
					globalTrackIndex = index,
					globalTrackCount = #accepted,
				})
			end
		end
	end
	return {
		model = model,
		components = #localComponents,
		samples = rows,
		tracks = tracks,
		acceptedTracks = accepted,
		plans = plans,
		groundCoverage = coverage,
		volumeCoverage = verticalCoverage,
		areaCoverage = areaCoverage,
		ambiguousOverlaps = ambiguousOverlaps,
		complete = complete and #plans == #accepted,
		sliceFailures = sliceFailures,
		options = options,
	}
end

function Footprint.Bind(report, folder, options)
	editOnly()
	assert(type(report) == "table" and type(report.acceptedTracks) == "table", "Pass a footprint diagnostic report")
	options = configured(options or report.options)
	folder = folder or workspace:FindFirstChild("Buildings")
	assert(folder, "Workspace.Buildings is missing")
	local bindings = {}
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") or not model.Name:match("^BuildingAuto_") then continue end
		if not modelTouchesTracks(model, report.acceptedTracks) then continue end
		local coverage = volumeCoverage(model, report.acceptedTracks)
		if coverage and coverage >= options.MinBindingOverlap then
			table.insert(bindings, {model = model, coverage = coverage})
		end
	end
	table.sort(bindings, function(a, b)
		if a.coverage ~= b.coverage then return a.coverage > b.coverage end
		return a.model.Name < b.model.Name
	end)
	local complete = #bindings > 0
	for _, binding in bindings do
		if binding.coverage < options.MinVolumeCoverage then complete = false; break end
	end
	local oldModels = {}
	for _, binding in bindings do table.insert(oldModels, binding.model) end
	for _, plan in report.plans do plan.oldModels = oldModels end
	report.bindings = bindings
	report.smoothBlockers = smoothBlockers(folder, report.acceptedTracks)
	report.bindingComplete = complete and report.ambiguousOverlaps == 0 and #report.plans > 0
		and #report.smoothBlockers == 0
	return report
end

function Footprint.Stage(report)
	editOnly()
	assert(report and report.bindingComplete and #report.plans > 0 and #report.bindings > 0,
		"Pass a completely bound global footprint report")
	local stage = Instance.new("Folder")
	stage.Name = "ShibuyaGlobalFootprintStage_" .. Http:GenerateGUID(false)
	stage:SetAttribute("GlobalFootprintStageVersion", 1)
	stage:SetAttribute("Expected", #report.plans)
	stage:SetAttribute("ExpectedSources", #report.bindings)
	stage.Parent = Storage
	local failures = {}
	for index, plan in report.plans do
		local sourceKey = report.model:GetAttribute("ShibuyaSourceKey")
		local name = string.format("BuildingSmooth_%s_GlobalTrack%02d", sourceKey, index)
		local ok, building = pcall(require(script.Parent.SmoothBuildingBuilder).StagePlan, name, plan)
		if not ok then
			table.insert(failures, {name = name, reason = tostring(building)})
			continue
		end
		building:SetAttribute("ShibuyaSourceKey", plan.key)
		building:SetAttribute("MassingConfidence", plan.confidence)
		building:SetAttribute("MassingBasis", plan.reason)
		building:SetAttribute("SourceBaseY", plan.sourceBaseY)
		building:SetAttribute("FloorCountBasis", "Independent global loops with complete legacy-volume binding")
		building:SetAttribute("GlobalTrackIndex", index)
		building:SetAttribute("GlobalTrackCount", #report.plans)
		building:SetAttribute("GlobalSourceCount", #report.bindings)
		local links = Instance.new("Folder")
		links.Name = "ReplacementSources"
		links.Parent = building
		for sourceIndex, binding in report.bindings do
			local link = Instance.new("ObjectValue")
			link.Name = string.format("Source%02d", sourceIndex)
			link.Value = binding.model
			link:SetAttribute("ReplacementSourcePivot", binding.model:GetPivot())
			link.Parent = links
		end
		building.Parent = stage
	end
	stage:SetAttribute("BuildFailures", #failures)
	print("GLOBAL_FOOTPRINT_STAGED", #stage:GetChildren(), "tracks from", #report.bindings,
		"sources;", #failures, "failures", stage.Name)
	return stage, failures
end

function Footprint.Apply(stage)
	editOnly()
	assert(stage and stage.Parent == Storage and stage:GetAttribute("GlobalFootprintStageVersion") == 1
		and not stage:GetAttribute("Applied"), "Invalid global footprint stage")
	assert(stage:GetAttribute("BuildFailures") == 0 and #stage:GetChildren() == stage:GetAttribute("Expected"),
		"Global footprint stage is incomplete")
	local audit = require(script.Parent.SmoothBuildingAudit).Run(stage)
	assert(audit.summary.badBuildings == 0, "Global footprint stage failed structural audit")
	local sources, names, expectedSet = {}, {}, nil
	for _, building in stage:GetChildren() do
		assert(not workspace.Buildings:FindFirstChild(building.Name) and not names[building.Name],
			"Global footprint replacement name collision")
		names[building.Name] = true
		local links = building:FindFirstChild("ReplacementSources")
		assert(links and links:IsA("Folder")
			and #links:GetChildren() == building:GetAttribute("GlobalSourceCount"), "Incomplete replacement source set")
		local set = {}
		for _, link in links:GetChildren() do
			local old = link.Value
			assert(old and old.Parent == workspace.Buildings and old.Name:match("^BuildingAuto_"),
				"Global footprint source changed")
			assert(old:GetPivot() == link:GetAttribute("ReplacementSourcePivot"), "Global footprint source moved")
			set[old] = true
			sources[old] = true
		end
		if expectedSet then
			for old in expectedSet do assert(set[old], "Staged global tracks disagree on source set") end
			for old in set do assert(expectedSet[old], "Staged global tracks disagree on source set") end
		else expectedSet = set end
	end
	local sourceCount = 0
	for _ in sources do sourceCount += 1 end
	assert(sourceCount == stage:GetAttribute("ExpectedSources"), "Bound source count changed")
	History:SetWaypoint("Before global footprint replacements")
	local archive = Instance.new("Folder")
	archive.Name = "ShibuyaBeforeGlobalFootprint_" .. Http:GenerateGUID(false)
	archive.Parent = Storage
	local moved = {}
	local ok, err = pcall(function()
		for old in sources do
			old.Parent = archive
			table.insert(moved, {object = old, old = true})
		end
		for _, building in stage:GetChildren() do
			building.Parent = workspace.Buildings
			table.insert(moved, {object = building, old = false})
		end
	end)
	if not ok then
		for index = #moved, 1, -1 do
			local item = moved[index]
			item.object.Parent = item.old and workspace.Buildings or stage
		end
		archive:Destroy()
		error(err)
	end
	stage:SetAttribute("Applied", true)
	archive:SetAttribute("ReplacedSourceCount", sourceCount)
	archive:SetAttribute("GeneratedTrackCount", #moved - sourceCount)
	History:SetWaypoint("Global footprint replacements")
	print("GLOBAL_FOOTPRINT_APPLIED", sourceCount, "legacy sources as", #moved - sourceCount,
		"smooth tracks; originals retained in", archive.Name)
	return archive, audit
end

return Footprint
