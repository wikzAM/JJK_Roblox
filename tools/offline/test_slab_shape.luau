-- Lune: point-sample check that reduced primitives cover the same region as the source polygons.
-- `lune run tools/offline/test_slab_shape.luau <nameSubstring> [areaTol] [snapDeg]`
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local R = require("./SlabReducer")

local buildings = serde.decode("json", fs.readFile("tools/offline/data/pilot_plans.json"))
local filter = process.args[1] or ""
local areaTol = tonumber(process.args[2] or "20") :: number
local snapDeg = tonumber(process.args[3] or "8") :: number

local function inPoly(p, x, z)
	local inside = false
	local j = #p
	for i = 1, #p do
		local a, b = p[i], p[j]
		if (a[2] > z) ~= (b[2] > z) and x < (b[1] - a[1]) * (z - a[2]) / (b[2] - a[2]) + a[1] then
			inside = not inside
		end
		j = i
	end
	return inside
end
local function inTri(A, B, C, x, z)
	local function s(p, q)
		return (q[1] - p[1]) * (z - p[2]) - (q[2] - p[2]) * (x - p[1])
	end
	local d1, d2, d3 = s(A, B), s(B, C), s(C, A)
	local neg = d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
	local pos = d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
	return not (neg and pos)
end
local function inPrim(p, x, z)
	if p.kind == "box" then
		local dx, dz = x - p.cx, z - p.cz
		local u = dx * p.ux + dz * p.uz
		local v = -dx * p.uz + dz * p.ux
		return math.abs(u) <= p.sx / 2 and math.abs(v) <= p.sz / 2
	end
	return inTri(p.a, p.b, p.c, x, z)
end

for _, b in buildings do
	if string.find(b.name, filter, 1, true) then
		local xorN, uniN, overlapN = 0, 0, 0
		for li, level in b.plan.levels do
			local prims = R.reduceLevel(level.pieces, { areaTol = areaTol, snapDeg = snapDeg })
			local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
			for _, poly in level.pieces do
				for _, v in poly do
					x0, x1, z0, z1 = math.min(x0, v[1]), math.max(x1, v[1]), math.min(z0, v[2]), math.max(z1, v[2])
				end
			end
			local lx, lu, lo = 0, 0, 0
			for x = x0 - 2, x1 + 2, 1 do
				for z = z0 - 2, z1 + 2, 1 do
					local a = false
					for _, poly in level.pieces do
						if inPoly(poly, x + 0.37, z + 0.29) then
							a = true
							break
						end
					end
					local cnt = 0
					for _, p in prims do
						if inPrim(p, x + 0.37, z + 0.29) then
							cnt += 1
						end
					end
					local bb = cnt > 0
					if a or bb then
						lu += 1
					end
					if a ~= bb then
						lx += 1
					end
					if cnt > 1 then
						lo += 1
					end
				end
			end
			xorN += lx
			uniN += lu
			overlapN += lo
			print(string.format("  level %d: prims=%d mismatch=%.2f%% overlap=%.2f%%", li, #prims, lx / math.max(lu, 1) * 100, lo / math.max(lu, 1) * 100))
		end
		print(string.format("%s mismatch=%.2f%% overlap=%.2f%%", b.name, xorN / uniN * 100, overlapN / uniN * 100))
	end
end
