--!nonstrict
-- Disposable checks for global multi-loop extraction.
local Verify = {}

local function component()
	return {
		meshIndex = 900,
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge),
		triangles = {},
	}
end

local function triangle(group, a, b, c)
	table.insert(group.triangles, {a, b, c})
	for _, point in {a, b, c} do group.min, group.max = group.min:Min(point), group.max:Max(point) end
end

local function wall(group, a, b, bottom, top)
	local p, q = Vector3.new(a.X, bottom, a.Y), Vector3.new(b.X, bottom, b.Y)
	local r, s = Vector3.new(b.X, top, b.Y), Vector3.new(a.X, top, a.Y)
	triangle(group, p, q, r)
	triangle(group, p, r, s)
end

local function rectangle(group, x, z, width, depth, openSide)
	local points = {
		Vector2.new(x, z),
		Vector2.new(x + width, z),
		Vector2.new(x + width, z + depth),
		Vector2.new(x, z + depth),
	}
	for index, point in points do
		if index ~= openSide then wall(group, point, points[index % #points + 1], 0, 100) end
	end
end

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local massing = require(script.Parent.ShibuyaMassing)
	local first, second, open = component(), component(), component()
	rectangle(first, 0, 0, 80, 60)
	rectangle(second, 140, 0, 70, 50)
	rectangle(open, 280, 0, 80, 60, 4)
	local loops, reason, stats = massing.ExtractSectionLoops(
		massing.SectionsAt({first, second, open}, 50)
	)
	assert(loops and #loops == 2, "Open component poisoned independent loops: " .. tostring(reason))
	assert(not loops[1].hole and not loops[2].hole and stats.invalidComponents == 1,
		"Independent outer-loop classification failed")

	local courtyard = component()
	rectangle(courtyard, 0, 0, 120, 120)
	rectangle(courtyard, 40, 40, 40, 40)
	local rings, courtyardReason = massing.ExtractSectionLoops(massing.SectionsAt({courtyard}, 50))
	assert(rings and #rings == 2, "Courtyard rings were not retained: " .. tostring(courtyardReason))
	assert(not rings[1].hole and rings[2].hole and rings[2].nestingDepth == 1,
		"Courtyard hole was not classified")
	local result = {
		independentOuters = #loops,
		ignoredOpenComponents = stats.invalidComponents,
		courtyardRings = #rings,
	}
	print("GLOBAL_SLICE_VERIFIED", game:GetService("HttpService"):JSONEncode(result))
	return result
end

return Verify
