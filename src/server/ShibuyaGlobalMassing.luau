--!nonstrict
-- Conservative cross-component reconstruction for imported FBX sections.
-- Components are stitched only when their envelopes nearly touch and their
-- vertical spans agree. The combined triangle set must still pass the ordinary
-- closed-contour massing analysis; adjacent independent buildings are rejected.
local Global = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local History = game:GetService("ChangeHistoryService")
local DEFAULTS = {
	MaxHorizontalGap = 6,
	MinVerticalOverlap = 0.55,
	MaxBaseDelta = 12,
	MaxTopDelta = 30,
	MinComponents = 2,
	MaxComponents = 12,
	MaxClusterWidth = 900,
	MaxClusterDepth = 900,
	MaxSubsetComponents = 6,
	MaxCandidateStates = 2000,
	StartRoot = 1,
	RootCount = 50,
	BatchSize = 25,
}
local DEFAULT_MASSING = {
	WeldTolerance = 0.9,
	MaxSeamGap = 6,
	MaxCornerGap = 6,
	MaxCornerExtension = 6,
	MinSupportSamples = 2,
	MinSupportSpan = 0.10,
}

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function configured(options)
	local result = table.clone(DEFAULTS)
	for key, value in options or {} do
		if key == "Buildings" then
			assert(typeof(value) == "Instance", "Buildings must be an Instance")
			result.Buildings = value
		elseif key ~= "MassingOptions" then
			assert(DEFAULTS[key] ~= nil, "Unknown global massing option: " .. tostring(key))
			result[key] = value
		end
	end
	for _, key in {
		"MaxHorizontalGap", "MinVerticalOverlap", "MaxBaseDelta", "MaxTopDelta",
		"MinComponents", "MaxComponents", "MaxClusterWidth", "MaxClusterDepth",
		"MaxSubsetComponents", "MaxCandidateStates", "StartRoot", "RootCount", "BatchSize",
	} do
		assert(type(result[key]) == "number" and result[key] >= 0, "Invalid global massing option: " .. key)
	end
	for _, key in {
		"MinComponents", "MaxComponents", "MaxSubsetComponents", "MaxCandidateStates",
		"StartRoot", "RootCount", "BatchSize",
	} do
		assert(result[key] >= 1 and result[key] % 1 == 0, key .. " must be a positive integer")
	end
	assert(result.MinComponents <= result.MaxComponents, "MinComponents exceeds MaxComponents")
	assert(result.MaxSubsetComponents <= result.MaxComponents, "MaxSubsetComponents exceeds MaxComponents")
	assert(result.MinVerticalOverlap <= 1, "MinVerticalOverlap must be at most one")
	result.MassingOptions = table.clone(DEFAULT_MASSING)
	for key, value in (options and options.MassingOptions) or {} do result.MassingOptions[key] = value end
	return result
end

local function geometricKey(key)
	if type(key) ~= "string" then return nil end
	return key:match("^%d+_(%-?%d+_%-?%d+_%-?%d+)$")
end

local function matchesStoredEnvelope(component, old)
	local cf, size = old:GetAttribute("InteriorBBoxCFrame"), old:GetAttribute("InteriorBBoxSize")
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then return false end
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, triangle in component.triangles do
		for _, point in triangle do
			local localPoint = cf:PointToObjectSpace(point)
			lo, hi = lo:Min(localPoint), hi:Max(localPoint)
		end
	end
	local lowError, highError = lo + size / 2, hi - size / 2
	return math.max(
		math.abs(lowError.X), math.abs(lowError.Y), math.abs(lowError.Z),
		math.abs(highError.X), math.abs(highError.Y), math.abs(highError.Z)
	) <= 0.35
end

local function matchedComponents(components, folder, massing)
	local exact, exactCount, oldGeometric, oldGeometricCount = {}, {}, {}, {}
	for _, model in folder:GetChildren() do
		local key = model:GetAttribute("ShibuyaSourceKey")
		if model:IsA("Model") and model.Name:match("^BuildingAuto_") and type(key) == "string" then
			exact[key] = model
			exactCount[key] = (exactCount[key] or 0) + 1
			local suffix = geometricKey(key)
			if suffix then
				oldGeometric[suffix] = model
				oldGeometricCount[suffix] = (oldGeometricCount[suffix] or 0) + 1
			end
		end
	end
	local componentGeometricCount = {}
	for _, component in components do
		local suffix = geometricKey(massing.SourceKey(component))
		if suffix then componentGeometricCount[suffix] = (componentGeometricCount[suffix] or 0) + 1 end
	end
	local rows, unmatched = {}, 0
	for _, component in components do
		local key = massing.SourceKey(component)
		local old = exactCount[key] == 1 and exact[key] or nil
		if not old then
			local suffix = geometricKey(key)
			if suffix and oldGeometricCount[suffix] == 1 and componentGeometricCount[suffix] == 1 then
				local candidate = oldGeometric[suffix]
				if matchesStoredEnvelope(component, candidate) then old = candidate end
			end
		end
		if old then table.insert(rows, {component = component, oldModel = old, key = key})
		else unmatched += 1 end
	end
	return rows, unmatched
end

local function horizontalGap(a, b)
	local dx = math.max(0, a.min.X - b.max.X, b.min.X - a.max.X)
	local dz = math.max(0, a.min.Z - b.max.Z, b.min.Z - a.max.Z)
	return math.sqrt(dx * dx + dz * dz)
end

local function compatible(a, b, options)
	local overlap = math.min(a.max.Y, b.max.Y) - math.max(a.min.Y, b.min.Y)
	local smallerHeight = math.min(a.max.Y - a.min.Y, b.max.Y - b.min.Y)
	if overlap <= 0 or overlap / smallerHeight < options.MinVerticalOverlap then return false end
	if math.abs(a.min.Y - b.min.Y) > options.MaxBaseDelta
		and math.abs(a.max.Y - b.max.Y) > options.MaxTopDelta then return false end
	return horizontalGap(a, b) <= options.MaxHorizontalGap
end

local function clusters(rows, options)
	local parent = {}
	for index = 1, #rows do parent[index] = index end
	local function root(index)
		while parent[index] ~= index do
			parent[index] = parent[parent[index]]
			index = parent[index]
		end
		return index
	end
	for a = 1, #rows do
		for b = a + 1, #rows do
			if compatible(rows[a].component, rows[b].component, options) then
				local rootA, rootB = root(a), root(b)
				if rootA ~= rootB then parent[rootB] = rootA end
			end
		end
		if a % 80 == 0 then task.wait() end
	end
	local grouped = {}
	for index, row in rows do
		local id = root(index)
		grouped[id] = grouped[id] or {}
		table.insert(grouped[id], row)
	end
	local result = {}
	for _, group in grouped do table.insert(result, group) end
	return result
end

local function combinedComponent(group)
	local merged = {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge),
		triangles = {},
		meshIndex = 0,
	}
	for _, row in group do
		merged.min, merged.max = merged.min:Min(row.component.min), merged.max:Max(row.component.max)
		for _, triangle in row.component.triangles do table.insert(merged.triangles, triangle) end
	end
	return merged
end

local function clusterKey(group, merged)
	local keys = {}
	for _, row in group do table.insert(keys, row.key) end
	table.sort(keys)
	local center = (merged.min + merged.max) / 2
	local checksum = 0
	for _, key in keys do
		for index = 1, #key do checksum = (checksum * 131 + key:byte(index)) % 1000000007 end
	end
	return string.format("Global%d_%d_%d_%d_%d", #group,
		checksum,
		math.round(center.X * 10), math.round(center.Y * 10), math.round(center.Z * 10)), keys
end

function Global.Preview(components, options)
	editOnly()
	options = configured(options)
	local folder = (options and options.Buildings) or workspace:FindFirstChild("Buildings")
	assert(folder, "Workspace.Buildings is missing")
	local massing = require(script.Parent.ShibuyaMassing)
	components = components or require(script.Parent.ShibuyaGeometry).Scan()
	local rows, unmatched = matchedComponents(components, folder, massing)
	local report = {
		plans = {},
		clusters = {},
		rejected = {},
		matchedComponents = #rows,
		unmatchedComponents = unmatched,
		sourceFolder = folder,
		readOnly = true,
	}
	local function reject(reason)
		report.rejected[reason] = (report.rejected[reason] or 0) + 1
	end
	for _, group in clusters(rows, options) do
		if #group < options.MinComponents then reject("isolated component"); continue end
		if #group > options.MaxComponents then reject("cluster has too many source components"); continue end
		local merged = combinedComponent(group)
		local size = merged.max - merged.min
		if size.X > options.MaxClusterWidth or size.Z > options.MaxClusterDepth then
			reject("cluster envelope is too large"); continue
		end
		local ok, plan, reason = pcall(massing.Analyze, merged, options.MassingOptions)
		if not ok then reason, plan = tostring(plan), nil end
		if not plan then reject(reason or "combined contour rejected"); continue end
		local key, sourceKeys = clusterKey(group, merged)
		local oldModels, seen = {}, {}
		for _, row in group do
			if seen[row.oldModel] then reject("cluster repeats a legacy source"); oldModels = nil; break end
			seen[row.oldModel] = true
			table.insert(oldModels, row.oldModel)
		end
		if not oldModels then continue end
		plan.key = key
		plan.oldModels = oldModels
		plan.sourceKeys = sourceKeys
		plan.clusterComponentCount = #group
		plan.reason = "Cross-component stitched contour; " .. (plan.reason or "persistent merged shell")
		plan.confidence = math.max(0, (plan.confidence or 0) - math.max(0, #group - 2) * 0.005)
		table.insert(report.plans, plan)
		table.insert(report.clusters, {plan = plan, rows = group, merged = merged})
	end
	table.sort(report.plans, function(a, b)
		if a.confidence ~= b.confidence then return a.confidence > b.confidence end
		if a.area ~= b.area then return a.area > b.area end
		return a.key < b.key
	end)
	print("GLOBAL_MASSING_PREVIEW", #rows, "matched components,", #report.plans,
		"stitched plans; no geometry changed")
	return report
end

-- Searches small connected subsets inside broad proximity neighborhoods. This
-- avoids transitive city-block merging: each candidate subset must independently
-- close into one persistent building, and selected candidates cannot share a
-- legacy source model.
function Global.PreviewSubclusters(components, options)
	editOnly()
	options = configured(options)
	local folder = options.Buildings or workspace:FindFirstChild("Buildings")
	assert(folder, "Workspace.Buildings is missing")
	local massing = require(script.Parent.ShibuyaMassing)
	components = components or require(script.Parent.ShibuyaGeometry).Scan()
	local rows, unmatched = matchedComponents(components, folder, massing)
	local adjacent = {}
	for index = 1, #rows do adjacent[index] = {} end
	for a = 1, #rows do
		for b = a + 1, #rows do
			if compatible(rows[a].component, rows[b].component, options) then
				table.insert(adjacent[a], b)
				table.insert(adjacent[b], a)
			end
		end
		if a % 80 == 0 then task.wait() end
	end
	local report = {
		plans = {},
		candidates = {},
		rejected = {},
		matchedComponents = #rows,
		unmatchedComponents = unmatched,
		sourceFolder = folder,
		readOnly = true,
		subclusterMode = true,
		states = 0,
		truncated = false,
		startRoot = math.min(options.StartRoot, math.max(1, #rows)),
		endRoot = math.min(#rows, options.StartRoot + options.RootCount - 1),
	}
	local seenSubsets = {}
	local function reject(reason)
		report.rejected[reason] = (report.rejected[reason] or 0) + 1
	end
	local function analyzeMembers(members)
		local keyParts = {}
		for _, index in members do table.insert(keyParts, tostring(index)) end
		local identity = table.concat(keyParts, ":")
		if seenSubsets[identity] then return end
		seenSubsets[identity] = true
		report.states += 1
		if report.states > options.MaxCandidateStates then report.truncated = true; return end
		if #members < options.MinComponents then return end
		local group = {}
		for _, index in members do table.insert(group, rows[index]) end
		local merged = combinedComponent(group)
		local size = merged.max - merged.min
		if size.X > options.MaxClusterWidth or size.Z > options.MaxClusterDepth then
			reject("subset envelope is too large")
			return
		end
		local ok, plan, reason = pcall(massing.Analyze, merged, options.MassingOptions)
		if not ok then reason, plan = tostring(plan), nil end
		if not plan then reject(reason or "combined subset contour rejected"); return end
		local key, sourceKeys = clusterKey(group, merged)
		local oldModels = {}
		for _, row in group do table.insert(oldModels, row.oldModel) end
		plan.key = key
		plan.oldModels = oldModels
		plan.sourceKeys = sourceKeys
		plan.clusterComponentCount = #group
		plan.reason = "Bounded cross-component subset contour; " .. (plan.reason or "persistent merged shell")
		plan.confidence = math.max(0, (plan.confidence or 0) - math.max(0, #group - 2) * 0.005)
		plan.selectionScore = plan.confidence ^ 3 * math.sqrt(plan.area) * plan.height * (1 + #group * 0.05)
		table.insert(report.candidates, plan)
	end
	local function explore(root, members, frontier)
		if report.truncated then return end
		analyzeMembers(members)
		if #members >= options.MaxSubsetComponents then return end
		for _, nextIndex in frontier do
			if report.truncated then return end
			local memberSet, nextMembers = {}, table.clone(members)
			for _, index in nextMembers do memberSet[index] = true end
			if memberSet[nextIndex] then continue end
			table.insert(nextMembers, nextIndex)
			table.sort(nextMembers)
			memberSet[nextIndex] = true
			local frontierSet = {}
			for _, index in frontier do
				if index >= root and not memberSet[index] then frontierSet[index] = true end
			end
			for _, index in adjacent[nextIndex] do
				if index >= root and not memberSet[index] then frontierSet[index] = true end
			end
			local nextFrontier = {}
			for index in frontierSet do table.insert(nextFrontier, index) end
			table.sort(nextFrontier)
			explore(root, nextMembers, nextFrontier)
		end
	end
	for root = report.startRoot, report.endRoot do
		if report.truncated then break end
		local frontier = {}
		for _, index in adjacent[root] do if index >= root then table.insert(frontier, index) end end
		table.sort(frontier)
		explore(root, {root}, frontier)
		if root % 20 == 0 then task.wait() end
	end
	table.sort(report.candidates, function(a, b)
		if a.selectionScore ~= b.selectionScore then return a.selectionScore > b.selectionScore end
		if a.confidence ~= b.confidence then return a.confidence > b.confidence end
		return a.key < b.key
	end)
	local used = {}
	for _, plan in report.candidates do
		local available = true
		for _, old in plan.oldModels do if used[old] then available = false; break end end
		if not available then continue end
		for _, old in plan.oldModels do used[old] = true end
		table.insert(report.plans, plan)
	end
	print("GLOBAL_SUBCLUSTER_PREVIEW", report.states, "subsets tested,", #report.candidates,
		"closed candidates,", #report.plans, "disjoint plans; no geometry changed")
	return report
end

function Global.Stage(report, options)
	editOnly()
	options = configured(options)
	assert(type(report) == "table" and type(report.plans) == "table" and report.sourceFolder,
		"Pass a global massing preview")
	local stage = Instance.new("Folder")
	stage.Name = "ShibuyaGlobalStage_" .. Http:GenerateGUID(false)
	stage:SetAttribute("GlobalStageVersion", 1)
	stage.Parent = Storage
	local failures = {}
	for index = 1, math.min(options.BatchSize, #report.plans) do
		local plan = report.plans[index]
		local valid = true
		for _, old in plan.oldModels do
			if old.Parent ~= report.sourceFolder then valid = false; break end
		end
		if not valid then
			table.insert(failures, {name = plan.key, reason = "one or more source models changed"})
			continue
		end
		local ok, building = pcall(require(script.Parent.SmoothBuildingBuilder).StagePlan,
			"BuildingSmooth_" .. plan.key, plan)
		if not ok then
			table.insert(failures, {name = plan.key, reason = tostring(building)})
			continue
		end
		building:SetAttribute("ShibuyaSourceKey", plan.key)
		building:SetAttribute("MassingConfidence", plan.confidence)
		building:SetAttribute("MassingBasis", plan.reason)
		building:SetAttribute("SourceBaseY", plan.sourceBaseY)
		building:SetAttribute("FloorCountBasis", "Cross-component persistent source contour")
		building:SetAttribute("GlobalSourceCount", #plan.oldModels)
		local links = Instance.new("Folder")
		links.Name = "ReplacementSources"
		links.Parent = building
		for sourceIndex, old in plan.oldModels do
			local link = Instance.new("ObjectValue")
			link.Name = string.format("Source%02d", sourceIndex)
			link.Value = old
			link:SetAttribute("ReplacementSourcePivot", old:GetPivot())
			link.Parent = links
		end
		building.Parent = stage
		if index % 5 == 0 then task.wait() end
	end
	stage:SetAttribute("Expected", #stage:GetChildren())
	stage:SetAttribute("BuildFailures", #failures)
	print("GLOBAL_MASSING_STAGED", #stage:GetChildren(), "buildings;", #failures, "failures", stage.Name)
	return stage, failures
end

function Global.Apply(stage)
	editOnly()
	assert(stage and stage.Parent == Storage and stage:GetAttribute("GlobalStageVersion") == 1
		and not stage:GetAttribute("Applied"), "Invalid global stage")
	assert(stage:GetAttribute("BuildFailures") == 0, "Global stage has build failures")
	local audit = require(script.Parent.SmoothBuildingAudit).Run(stage)
	assert(audit.summary.badBuildings == 0 and audit.summary.buildings == stage:GetAttribute("Expected"),
		"Global stage failed structural audit")
	local sources, names = {}, {}
	for _, building in stage:GetChildren() do
		assert(not workspace.Buildings:FindFirstChild(building.Name) and not names[building.Name],
			"Global replacement name collision")
		names[building.Name] = true
		local links = building:FindFirstChild("ReplacementSources")
		assert(links and links:IsA("Folder") and #links:GetChildren() == building:GetAttribute("GlobalSourceCount"),
			"Global replacement source set is incomplete")
		for _, link in links:GetChildren() do
			local old = link.Value
			assert(old and old.Parent == workspace.Buildings and old.Name:match("^BuildingAuto_") and not sources[old],
				"Global source changed or appears in two replacements")
			assert(old:GetPivot() == link:GetAttribute("ReplacementSourcePivot"), "Global source moved after staging")
			sources[old] = true
		end
	end
	History:SetWaypoint("Before global smooth replacements")
	local archive = Instance.new("Folder")
	archive.Name = "ShibuyaBeforeGlobalSmooth_" .. Http:GenerateGUID(false)
	archive.Parent = Storage
	local buildingCount = #stage:GetChildren()
	local moved = {}
	local ok, err = pcall(function()
		for old in sources do
			old.Parent = archive
			table.insert(moved, {kind = "old", object = old})
		end
		for _, building in stage:GetChildren() do
			building.Parent = workspace.Buildings
			table.insert(moved, {kind = "new", object = building})
		end
	end)
	if not ok then
		for index = #moved, 1, -1 do
			local item = moved[index]
			item.object.Parent = item.kind == "old" and workspace.Buildings or stage
		end
		error(err)
	end
	local sourceCount = 0
	for _ in sources do sourceCount += 1 end
	stage:SetAttribute("Applied", true)
	archive:SetAttribute("ReplacedSourceCount", sourceCount)
	archive:SetAttribute("GeneratedBuildingCount", buildingCount)
	History:SetWaypoint("Global smooth replacements")
	print("GLOBAL_MASSING_APPLIED", sourceCount, "source models as", buildingCount,
		"smooth buildings; originals retained in", archive.Name)
	return archive, audit
end

return Global
