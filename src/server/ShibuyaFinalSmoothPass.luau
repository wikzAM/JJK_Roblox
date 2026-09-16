--!nonstrict
-- Final live-map conversion: every BuildingAuto becomes robust smooth massing.
-- Exact originals are archived; difficult occupancy is conservatively represented
-- by convex hulls rather than left as jagged voxel slabs.
local Final = {}

local Storage = game:GetService("ServerStorage")
local DEFAULTS = {
	MaxSources = 50,
	MinSegmentCells = 5,
	MinWidth = 10,
	MinHeight = 30,
	MaxBodies = 12,
}

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function configured(options)
	local result = table.clone(DEFAULTS)
	for key, value in options or {} do
		assert(DEFAULTS[key] ~= nil, "Unknown final smooth option: " .. tostring(key))
		result[key] = value
	end
	for key, value in result do
		assert(type(value) == "number" and value >= 1 and value % 1 == 0,
			key .. " must be a positive integer")
	end
	return result
end

local function cross(origin, a, b)
	local p, q = a - origin, b - origin
	return p.X * q.Y - p.Y * q.X
end

local function hull(points)
	table.sort(points, function(a, b)
		if a.X ~= b.X then return a.X < b.X end
		return a.Y < b.Y
	end)
	local unique = {}
	for _, point in points do
		if #unique == 0 or (point - unique[#unique]).Magnitude > 1e-6 then table.insert(unique, point) end
	end
	if #unique < 3 then return nil end
	local lower = {}
	for _, point in unique do
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], point) <= 1e-8 do table.remove(lower) end
		table.insert(lower, point)
	end
	local upper = {}
	for index = #unique, 1, -1 do
		local point = unique[index]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], point) <= 1e-8 do table.remove(upper) end
		table.insert(upper, point)
	end
	table.remove(lower)
	table.remove(upper)
	for _, point in upper do table.insert(lower, point) end
	return #lower >= 3 and lower or nil
end

local function polygonArea(points)
	local result = 0
	for index, point in points do
		local nextPoint = points[index % #points + 1]
		result += point.X * nextPoint.Y - point.Y * nextPoint.X
	end
	return math.abs(result) / 2
end

local function occupiedCorners(grid, sourceSize, segmentRows)
	local points = {}
	for _, row in segmentRows do
		for _, node in row.segment.nodes do
			for _, index in node.cells do
				local i = math.floor((index - 1) / grid.nz) + 1
				local j = (index - 1) % grid.nz + 1
				local x0 = math.max(grid.minX + (i - 1) * grid.cell, -sourceSize.X / 2)
				local x1 = math.min(grid.minX + i * grid.cell, sourceSize.X / 2)
				local z0 = math.max(grid.minZ + (j - 1) * grid.cell, -sourceSize.Z / 2)
				local z1 = math.min(grid.minZ + j * grid.cell, sourceSize.Z / 2)
				table.insert(points, Vector2.new(x0, z0))
				table.insert(points, Vector2.new(x1, z0))
				table.insert(points, Vector2.new(x1, z1))
				table.insert(points, Vector2.new(x0, z1))
			end
		end
	end
	return points
end

local function planFor(sourceRow, segmentRows, index, aggregate, options)
	local grid, sourceCF, sourceSize = sourceRow.grid, sourceRow.sourceCF, sourceRow.sourceSize
	local points = hull(occupiedCorners(grid, sourceSize, segmentRows))
	if not points then return nil, "occupied footprint has no area" end
	local min, max = points[1], points[1]
	for _, point in points do min, max = min:Min(point), max:Max(point) end
	local width, depth = max.X - min.X, max.Y - min.Y
	if width < options.MinWidth or depth < options.MinWidth then return nil, "footprint is too narrow" end
	local baseY, topY
	if aggregate then
		baseY, topY = 0, sourceSize.Y
	else
		baseY, topY = math.huge, -math.huge
		for _, row in segmentRows do
			local proxyCF = row.proxy:GetAttribute("InteriorBBoxCFrame")
			local proxySize = row.proxy:GetAttribute("InteriorBBoxSize")
			local localCenter = sourceCF:PointToObjectSpace(proxyCF.Position)
			local bottom = localCenter.Y - proxySize.Y / 2 + sourceSize.Y / 2
			baseY, topY = math.min(baseY, bottom), math.max(topY, bottom + proxySize.Y)
		end
	end
	local height = topY - baseY
	if height < options.MinHeight then return nil, "vertical segment is too short" end
	local center = (min + max) / 2
	local localPoints = {}
	for _, point in points do table.insert(localPoints, point - center) end
	local frame = sourceCF * CFrame.new(center.X, -sourceSize.Y / 2 + baseY, center.Y)
	local key = sourceRow.source:GetAttribute("ShibuyaSourceKey") .. (aggregate and "_final" or "_final" .. index)
	return {
		key = key,
		frame = frame,
		points = localPoints,
		tiers = {{bottom = 0, top = height, points = localPoints}},
		height = height,
		sourceBaseY = frame.Position.Y,
		sourceTopY = frame.Position.Y + height,
		roofTrim = 0,
		area = polygonArea(localPoints),
		confidence = aggregate and 0.35 or 0.48,
		reason = aggregate and "Final aggregate convex-hull approximation"
			or "Final vertical-segment convex-hull approximation",
		method = aggregate and "final aggregate hull" or "final segment hull",
		size = Vector3.new(width, height, depth),
		oldModel = sourceRow.source,
		splitBodyIndex = index,
	}
end

local function envelopePlan(decomposition)
	local source, sourceCF, size = decomposition.source, decomposition.sourceCF, decomposition.sourceSize
	local width, depth, height = math.max(10, size.X), math.max(10, size.Z), math.max(30, size.Y)
	local points = {
		Vector2.new(-width / 2, -depth / 2),
		Vector2.new(width / 2, -depth / 2),
		Vector2.new(width / 2, depth / 2),
		Vector2.new(-width / 2, depth / 2),
	}
	local frame = sourceCF * CFrame.new(0, -size.Y / 2, 0)
	return {
		key = source:GetAttribute("ShibuyaSourceKey") .. "_finalbox",
		frame = frame,
		points = points,
		tiers = {{bottom = 0, top = height, points = points}},
		height = height,
		sourceBaseY = frame.Position.Y,
		sourceTopY = frame.Position.Y + height,
		roofTrim = 0,
		area = width * depth,
		confidence = 0.25,
		reason = "Final source-envelope box fallback",
		method = "final envelope box",
		size = Vector3.new(width, height, depth),
		oldModel = source,
	}
end

local function envelopeFromSource(source)
	local cf, size = source:GetAttribute("InteriorBBoxCFrame"), source:GetAttribute("InteriorBBoxSize")
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then cf, size = source:GetBoundingBox() end
	assert(typeof(cf) == "CFrame" and typeof(size) == "Vector3"
		and size.X > 0 and size.Y > 0 and size.Z > 0, "source has no usable envelope")
	local plan = envelopePlan({source = source, sourceCF = cf, sourceSize = size})
	plan.splitBodyIndex = 1
	plan.splitBodyCount = 1
	return {plan}
end

local function sourcePlans(source, options)
	local decomposition = require(script.Parent.ShibuyaGridSplitPass).DecomposeSegments(source)
	local usable = {}
	for _, row in decomposition.segments do
		if row.proxy and row.totalCells >= options.MinSegmentCells then
			local size = row.proxy:GetAttribute("InteriorBBoxSize")
			if size.X >= options.MinWidth and size.Z >= options.MinWidth and size.Y >= options.MinHeight then
				table.insert(usable, row)
			end
		end
	end
	local plans = {}
	if #usable > 0 and #usable <= options.MaxBodies then
		for index, row in usable do
			local plan = planFor(decomposition, {row}, index, false, options)
			if plan then table.insert(plans, plan) end
		end
	end
	if #usable == 0 or #plans ~= #usable or #usable > options.MaxBodies then
		local allRows = {}
		for _, row in decomposition.segments do if row.proxy then table.insert(allRows, row) end end
		local plan = planFor(decomposition, allRows, 1, true, options)
		if not plan then plan = envelopePlan(decomposition) end
		plans = {plan}
	end
	for index, plan in plans do
		plan.splitBodyIndex = index
		plan.splitBodyCount = #plans
	end
	for _, row in decomposition.segments do if row.proxy then row.proxy:Destroy() end end
	return plans
end

function Final.Preview(folder, options)
	editOnly()
	folder = folder or workspace:FindFirstChild("Buildings")
	assert(typeof(folder) == "Instance" or type(folder) == "table", "Pass a folder or source-model list")
	options = configured(options)
	local candidates = typeof(folder) == "Instance" and folder:GetChildren() or folder
	local report = {sources = {}, plans = {}, rejected = {}, readOnly = true, options = options}
	local tested = 0
	for _, source in candidates do
		if tested >= options.MaxSources then break end
		if not source:IsA("Model") or not source.Name:match("^BuildingAuto_") then continue end
		tested += 1
		local ok, plans, reason = pcall(sourcePlans, source, options)
		if not ok then
			reason = tostring(plans)
			local fallbackOk, fallback = pcall(envelopeFromSource, source)
			plans = fallbackOk and fallback or nil
			if not fallbackOk then reason ..= "; envelope fallback: " .. tostring(fallback) end
		end
		if not plans then
			report.rejected[reason or "final approximation failed"] =
				(report.rejected[reason or "final approximation failed"] or 0) + 1
			continue
		end
		local row = {oldModel = source, plans = plans, key = source:GetAttribute("ShibuyaSourceKey")}
		table.insert(report.sources, row)
		for _, plan in plans do table.insert(report.plans, plan) end
		if tested % 20 == 0 then task.wait() end
	end
	report.tested = tested
	print("FINAL_SMOOTH_PREVIEW", tested, "sources tested,", #report.sources,
		"sources and", #report.plans, "smooth bodies; no geometry changed")
	return report
end

function Final.Stage(report, options)
	editOnly()
	options = configured(options or report.options)
	local stage, failures = require(script.Parent.ShibuyaGridSplitPass).Stage(report, {MaxSources = options.MaxSources})
	local sources = {}
	for _, output in stage:GetChildren() do
		local link = output:FindFirstChild("ReplacementSource")
		if link and link.Value then sources[link.Value] = true end
	end
	local sourceCount = 0
	for _ in sources do sourceCount += 1 end
	stage:SetAttribute("ExpectedSources", sourceCount)
	return stage, failures
end

function Final.Apply(stage)
	editOnly()
	return require(script.Parent.ShibuyaGridSplitPass).Apply(stage)
end

return Final
