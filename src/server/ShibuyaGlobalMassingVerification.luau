--!nonstrict
-- Disposable cross-component stitching fixtures. No live building is changed.
local Verify = {}

local function triangle(group, a, b, c)
	table.insert(group.triangles, {a, b, c})
	for _, point in {a, b, c} do
		group.min, group.max = group.min:Min(point), group.max:Max(point)
	end
end

local function component(meshIndex)
	return {
		meshIndex = meshIndex,
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge),
		triangles = {},
	}
end

local function wall(group, a, b, bottom, top)
	local p = Vector3.new(a.X, bottom, a.Y)
	local q = Vector3.new(b.X, bottom, b.Y)
	local r = Vector3.new(b.X, top, b.Y)
	local s = Vector3.new(a.X, top, a.Y)
	triangle(group, p, q, r)
	triangle(group, p, r, s)
end

local function prism(meshIndex, x, z, width, depth)
	local group = component(meshIndex)
	local points = {
		Vector2.new(x, z),
		Vector2.new(x + width, z),
		Vector2.new(x + width, z + depth),
		Vector2.new(x, z + depth),
	}
	for index, point in points do wall(group, point, points[index % #points + 1], 0, 100) end
	return group
end

local function source(folder, massing, group)
	local key = massing.SourceKey(group)
	local model = Instance.new("Model")
	model.Name = "BuildingAuto_" .. key
	model:SetAttribute("ShibuyaSourceKey", key)
	model.Parent = folder
	return model
end

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local storage = game:GetService("ServerStorage")
	local folders, stages = {}, {}
	local ok, result = pcall(function()
		local global = require(script.Parent.ShibuyaGlobalMassing)
		local massing = require(script.Parent.ShibuyaMassing)
		local fragmented = Instance.new("Folder")
		fragmented.Name = "GlobalMassingFragmentedFixture"
		fragmented.Parent = storage
		table.insert(folders, fragmented)
		local pieces = {}
		for index = 1, 4 do pieces[index] = component(700 + index) end
		wall(pieces[1], Vector2.new(1, 0), Vector2.new(99, 0), 0, 100)
		wall(pieces[2], Vector2.new(100, 1), Vector2.new(100, 59), 0, 100)
		wall(pieces[3], Vector2.new(99, 60), Vector2.new(1, 60), 0, 100)
		wall(pieces[4], Vector2.new(0, 59), Vector2.new(0, 1), 0, 100)
		for _, group in pieces do source(fragmented, massing, group) end
		local report = global.Preview(pieces, {Buildings = fragmented})
		assert(#report.plans == 1 and #report.plans[1].oldModels == 4,
			"Four fragmented facades did not become one closed building")
		local subsetReport = global.PreviewSubclusters(pieces, {Buildings = fragmented})
		assert(#subsetReport.plans == 1 and #subsetReport.plans[1].oldModels == 4,
			"Bounded subset search did not recover the fragmented shell")
		assert(math.abs(report.plans[1].area - 6000) < 1,
			"Stitched rectangle area changed")
		local stage, failures = global.Stage(report)
		table.insert(stages, stage)
		assert(#failures == 0 and #stage:GetChildren() == 1,
			"Verified stitched shell did not stage")
		local audit = require(script.Parent.SmoothBuildingAudit).Run(stage)
		assert(audit.summary.badBuildings == 0 and audit.summary.buildings == 1,
			"Stitched staged building failed structural audit")

		local adjacent = Instance.new("Folder")
		adjacent.Name = "GlobalMassingAdjacentFixture"
		adjacent.Parent = storage
		table.insert(folders, adjacent)
		local separate = {prism(801, 0, 0, 60, 60), prism(802, 63, 0, 60, 60)}
		for _, group in separate do source(adjacent, massing, group) end
		local rejected = global.Preview(separate, {Buildings = adjacent})
		assert(#rejected.plans == 0,
			"Nearby independent closed buildings were incorrectly merged")
		local subsetRejected = global.PreviewSubclusters(separate, {Buildings = adjacent})
		assert(#subsetRejected.plans == 0,
			"Subset search incorrectly merged nearby independent buildings")
		return {
			stitchedSources = 4,
			stitchedPlans = #report.plans,
			subsetPlans = #subsetReport.plans,
			adjacentRejected = 2,
			structuralParts = audit.summary.structuralParts,
		}
	end)
	for _, stage in stages do if stage then stage:Destroy() end end
	for _, folder in folders do if folder then folder:Destroy() end end
	assert(ok, result)
	print("GLOBAL_MASSING_VERIFIED", game:GetService("HttpService"):JSONEncode(result))
	return result
end

return Verify
