--!nonstrict
-- Disposable vertical-track and legacy-grid binding fixture.
local Verify = {}

local Http = game:GetService("HttpService")

local function component()
	return {
		meshIndex = 950,
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge),
		triangles = {},
	}
end

local function triangle(group, a, b, c)
	table.insert(group.triangles, {a, b, c})
	for _, point in {a, b, c} do group.min, group.max = group.min:Min(point), group.max:Max(point) end
end

local function wall(group, a, b)
	local p, q = Vector3.new(a.X, 0, a.Y), Vector3.new(b.X, 0, b.Y)
	local r, s = Vector3.new(b.X, 100, b.Y), Vector3.new(a.X, 100, a.Y)
	triangle(group, p, q, r)
	triangle(group, p, r, s)
end

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local folder = Instance.new("Folder")
	folder.Name = "GlobalFootprintVerificationTemporary"
	folder.Parent = game.ServerStorage
	local ok, result = pcall(function()
		local model = Instance.new("Model")
		model.Name = "BuildingAuto_global_track_fixture"
		model:SetAttribute("ShibuyaSourceKey", "global_track_fixture")
		model:SetAttribute("InteriorBBoxCFrame", CFrame.new(50, 50, 30))
		model:SetAttribute("InteriorBBoxSize", Vector3.new(100, 100, 60))
		local full = string.rep("1", 20 * 12)
		model:SetAttribute("InteriorGrid", Http:JSONEncode({
			cell = 5, nx = 20, nz = 12, minX = -50, minZ = -30,
			floors = 5, ground = 12, clearUpper = 12,
			occ = {full, full, full, full, full},
			occTight = {full, full, full, full, full},
		}))
		model.Parent = folder
		local pieces = {component(), component(), component(), component(), component()}
		wall(pieces[1], Vector2.new(1, 0), Vector2.new(99, 0))
		wall(pieces[2], Vector2.new(100, 1), Vector2.new(100, 59))
		wall(pieces[3], Vector2.new(99, 60), Vector2.new(1, 60))
		wall(pieces[4], Vector2.new(0, 59), Vector2.new(0, 1))
		-- Nearby open geometry must not invalidate the independently closed track.
		wall(pieces[5], Vector2.new(130, 0), Vector2.new(170, 0))
		local report = require(script.Parent.ShibuyaGlobalFootprint).DiagnoseModel(model, pieces)
		assert(report.complete and #report.plans == 1, "Complete global loop did not bind to the legacy grid")
		assert(#report.acceptedTracks == 1 and report.groundCoverage >= 0.99,
			"Persistent global track or coverage is incomplete")
		assert(report.volumeCoverage >= 0.99 and report.ambiguousOverlaps == 0,
			"Volumetric binding or overlap guard failed")
		assert(math.abs(report.plans[1].area - 6000) < 1, "Tracked footprint area changed")
		return {
			plans = #report.plans,
			samples = #report.samples,
			groundCoverage = report.groundCoverage,
			volumeCoverage = report.volumeCoverage,
			areaCoverage = report.areaCoverage,
		}
	end)
	folder:Destroy()
	assert(ok, result)
	print("GLOBAL_FOOTPRINT_VERIFIED", Http:JSONEncode(result))
	return result
end

return Verify
