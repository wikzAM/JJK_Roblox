-- Lune: map-wide slab part estimate from exported plans (tools/offline/data/all/plans_*.json).
-- `lune run tools/offline/estimate_slabs.luau`
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local R = require("./SlabReducer")

local buildings = {}
for _, f in fs.readDir("tools/offline/data/all") do
	for _, b in serde.decode("json", fs.readFile("tools/offline/data/all/" .. f)) do
		table.insert(buildings, b)
	end
end

local settings = {
	{ label = "pilot (tol 20, snap 8)", opts = { areaTol = 20, snapDeg = 8, dropSlivers = true } },
	{ label = "+ near-rect levels >=95% -> 1 box", opts = { areaTol = 20, snapDeg = 8, dropSlivers = true, rectFill = 0.95 } },
	{ label = "+ near-rect levels >=90% -> 1 box", opts = { areaTol = 20, snapDeg = 8, dropSlivers = true, rectFill = 0.90 } },
	{ label = "coarser (tol 40, snap 12) + >=90%", opts = { areaTol = 40, snapDeg = 12, dropSlivers = true, rectFill = 0.90 } },
}

local before = 0
for _, b in buildings do
	before += b.slabs
end
print(string.format("%d buildings with plans, current slab parts %d", #buildings, before))
for _, s in settings do
	local total, maxErr, over5 = 0, 0, 0
	local small, smallCount = 0, 0
	for _, b in buildings do
		local parts, bErr = 0, 0
		for _, level in b.plan.levels do
			local src = 0
			for _, p in level.pieces do
				src += math.abs(R.polyArea(p))
			end
			local prims = R.reduceLevel(level.pieces, s.opts)
			parts += #prims
			bErr = math.max(bErr, math.abs(R.primitiveArea(prims) - src) / math.max(src, 1))
		end
		total += parts
		maxErr = math.max(maxErr, bErr)
		if bErr > 0.05 then
			over5 += 1
		end
		if b.floors <= 10 then
			small += parts
			smallCount += 1
		end
	end
	print(string.format("%-38s slab parts %6d (%.0f%% fewer), <=10 floors: %d in %d bldgs; levels >5%% area change: %d bldgs",
		s.label, total, (1 - total / before) * 100, small, smallCount, over5))
end
