-- Lune test: run `lune run tools/offline/test_slab_reducer.luau [plans.json] [areaTol] [snapDeg]` from the repo root.
-- Reduces every level of every exported building plan and checks the area is preserved.
-- With no tolerance arguments it sweeps a grid of settings and prints totals only.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local SlabReducer = require("./SlabReducer")

local path = process.args[1] or "tools/offline/data/pilot_plans.json"
local buildings = serde.decode("json", fs.readFile(path))

local function run(areaTol: number, snapDeg: number, verbose: boolean)
	local totalBefore, totalAfter, worstErr = 0, 0, 0
	for _, b in buildings do
		local parts, errMax = 0, 0
		for _, level in b.plan.levels do
			local src = 0
			for _, poly in level.pieces do
				src += math.abs(SlabReducer.polyArea(poly))
			end
			local prims = SlabReducer.reduceLevel(level.pieces, { areaTol = areaTol, snapDeg = snapDeg })
			local err = math.abs(SlabReducer.primitiveArea(prims) - src) / math.max(src, 1)
			errMax = math.max(errMax, err)
			parts += #prims
		end
		worstErr = math.max(worstErr, errMax)
		totalBefore += b.slabs
		totalAfter += parts
		if verbose then
			print(string.format("%-48s fill=%.2f floors=%2d slabs %4d -> %3d  maxAreaErr=%.2f%%", b.name, b.fill, b.floors, b.slabs, parts, errMax * 100))
		end
	end
	print(string.format("areaTol=%5.1f snapDeg=%4.1f  slab parts %d -> %d (%.0f%% fewer); worst area error %.2f%%",
		areaTol, snapDeg, totalBefore, totalAfter, (1 - totalAfter / totalBefore) * 100, worstErr * 100))
end

if process.args[2] then
	run(tonumber(process.args[2]) :: number, tonumber(process.args[3] or "0") :: number, true)
else
	for _, tol in { 2, 8, 20, 40 } do
		for _, snap in { 0, 4, 8, 12 } do
			run(tol, snap, false)
		end
	end
end
