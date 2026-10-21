--!strict
-- SlabReducer: rebuilds a floor footprint (list of polygons in plan-local XZ) as
-- few primitives: one box per trapezoid strip plus right-triangle wedges for
-- slanted edges. Pure Luau (no Roblox types) so it runs in Lune and Studio.
--
-- Output primitives are in the same plan-local XZ frame:
--   { kind = "box", cx, cz, sx, sz, ux, uz }   -- box with local X along (ux, uz)
--   { kind = "wedge", a = {x,z}, b = {x,z}, c = {x,z} } -- right angle at a
-- Callers turn them into Parts/WedgeParts (see buildPart helpers in Studio scripts).

export type Pt = { number }
export type Poly = { Pt }

local SlabReducer = {}

local EPS = 1e-6

local function polyArea(p: Poly): number
	local a = 0
	for i = 1, #p do
		local q = p[i % #p + 1]
		a += p[i][1] * q[2] - q[1] * p[i][2]
	end
	return a / 2
end
SlabReducer.polyArea = polyArea

-- Drop duplicate and collinear vertices, then remove "notch" vertices whose
-- triangle with its neighbours is smaller than areaTol (Visvalingam).
function SlabReducer.simplify(poly: Poly, areaTol: number): Poly
	local p: Poly = {}
	for _, v in poly do
		local last = p[#p]
		if not last or math.abs(last[1] - v[1]) + math.abs(last[2] - v[2]) > 0.02 then
			table.insert(p, { v[1], v[2] })
		end
	end
	if #p > 1 and math.abs(p[1][1] - p[#p][1]) + math.abs(p[1][2] - p[#p][2]) <= 0.02 then
		table.remove(p)
	end
	local changed = true
	while changed and #p > 3 do
		changed = false
		local bestI, bestA = 0, math.huge
		for i = 1, #p do
			local a, b, c = p[(i - 2) % #p + 1], p[i], p[i % #p + 1]
			local tri = math.abs((b[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (b[2] - a[2])) / 2
			if tri < bestA then
				bestA, bestI = tri, i
			end
		end
		if bestA < areaTol then
			table.remove(p, bestI)
			changed = true
		end
	end
	if polyArea(p) < 0 then
		local r: Poly = {}
		for i = #p, 1, -1 do
			table.insert(r, p[i])
		end
		p = r
	end
	return p
end

-- Orientation of the minimum-area bounding rectangle over all polygon edges.
function SlabReducer.dominantAxis(polys: { Poly }): (number, number)
	local pts = {}
	for _, p in polys do
		for _, v in p do
			table.insert(pts, v)
		end
	end
	local bestArea, bux, buz = math.huge, 1, 0
	for _, p in polys do
		for i = 1, #p do
			local a, b = p[i], p[i % #p + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 1 then
				local ux, uz = dx / len, dz / len
				local u0, u1, v0, v1 = math.huge, -math.huge, math.huge, -math.huge
				for _, r in pts do
					local u, v = r[1] * ux + r[2] * uz, -r[1] * uz + r[2] * ux
					u0, u1, v0, v1 = math.min(u0, u), math.max(u1, u), math.min(v0, v), math.max(v1, v)
				end
				local area = (u1 - u0) * (v1 - v0)
				if area < bestArea - 1e-6 then
					bestArea, bux, buz = area, ux, uz
				end
			end
		end
	end
	return bux, buz
end

type Edge = { u0: number, v0: number, u1: number, v1: number, id: number }
type Trap = { v0: number, v1: number, l: Edge, r: Edge }

local function uAt(e: Edge, v: number): number
	if math.abs(e.v1 - e.v0) < EPS then
		return e.u0
	end
	return e.u0 + (e.u1 - e.u0) * (v - e.v0) / (e.v1 - e.v0)
end

-- Split a general triangle into two right triangles (altitude from the vertex
-- opposite the longest side); returns wedge primitives in (u,v).
local function triToWedges(p1: Pt, p2: Pt, p3: Pt, out: { any })
	local pts = { p1, p2, p3 }
	local bestI, bestL = 1, -1
	for i = 1, 3 do
		local a, b = pts[i], pts[i % 3 + 1]
		local l = (b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2
		if l > bestL then
			bestL, bestI = l, i
		end
	end
	local a, b, c = pts[bestI], pts[bestI % 3 + 1], pts[(bestI + 1) % 3 + 1]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local t = ((c[1] - a[1]) * dx + (c[2] - a[2]) * dz) / bestL
	local h = { a[1] + dx * t, a[2] + dz * t }
	local function push(r: Pt, x: Pt, y: Pt)
		local area = math.abs((x[1] - r[1]) * (y[2] - r[2]) - (y[1] - r[1]) * (x[2] - r[2]))
		if area > 0.01 then
			table.insert(out, { kind = "wedge", a = r, b = x, c = y })
		end
	end
	push(h, a, c)
	push(h, b, c)
end

-- Main entry: polygons of one level -> primitives in plan-local XZ.
function SlabReducer.reduceLevel(
	polysIn: { Poly },
	opts: { areaTol: number?, snapDeg: number?, rectFill: number?, dropSlivers: boolean? }?
): { any }
	local areaTol = (opts and opts.areaTol) or 2
	local polys: { Poly } = {}
	for _, p in polysIn do
		local s = SlabReducer.simplify(p, areaTol)
		local a = math.abs(polyArea(s))
		local perimeter = 0
		for i = 1, #s do
			local q = s[i % #s + 1]
			perimeter += math.sqrt((q[1] - s[i][1]) ^ 2 + (q[2] - s[i][2]) ^ 2)
		end
		-- Wall slivers from the source slicing (about 2-3 studs thick): drop them.
		local sliver = opts and opts.dropSlivers and a < 400 and 2 * a / math.max(perimeter, 1) < 2.5
		if #s >= 3 and a > 1 and not sliver then
			table.insert(polys, s)
		end
	end
	if #polys == 0 then
		return {}
	end
	local ux, uz = SlabReducer.dominantAxis(polys)

	-- Optional: a single near-rectangular outline becomes exactly its bounding rectangle.
	local rectFill = opts and opts.rectFill
	if rectFill and #polys == 1 then
		local u0, u1, v0, v1 = math.huge, -math.huge, math.huge, -math.huge
		for _, v in polys[1] do
			local u, w = v[1] * ux + v[2] * uz, -v[1] * uz + v[2] * ux
			u0, u1, v0, v1 = math.min(u0, u), math.max(u1, u), math.min(v0, w), math.max(v1, w)
		end
		local rectArea = (u1 - u0) * (v1 - v0)
		if rectArea > 0 and math.abs(polyArea(polys[1])) / rectArea >= rectFill then
			local cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
			return { { kind = "box", cx = cu * ux - cv * uz, cz = cu * uz + cv * ux, sx = u1 - u0, sz = v1 - v0, ux = ux, uz = uz } }
		end
	end
	local function toUV(x: number, z: number): (number, number)
		return x * ux + z * uz, -x * uz + z * ux
	end
	local function toXZ(u: number, v: number): Pt
		return { u * ux - v * uz, u * uz + v * ux }
	end

	-- Convert to (u,v) and snap edges within snapDeg of an axis onto that axis:
	-- each vertex becomes the intersection of its two (possibly snapped) edges.
	local snapTan = math.tan(math.rad((opts and opts.snapDeg) or 0))
	local uvPolys: { Poly } = {}
	for _, p in polys do
		local q: Poly = {}
		for _, v in p do
			local u, w = toUV(v[1], v[2])
			table.insert(q, { u, w })
		end
		if snapTan > 0 then
			local n = #q
			local lines = {}
			for i = 1, n do
				local a, b = q[i], q[i % n + 1]
				local du, dv = b[1] - a[1], b[2] - a[2]
				if math.abs(dv) <= math.abs(du) * snapTan then
					lines[i] = { kind = "v", c = (a[2] + b[2]) / 2 }
				elseif math.abs(du) <= math.abs(dv) * snapTan then
					lines[i] = { kind = "u", c = (a[1] + b[1]) / 2 }
				else
					lines[i] = { kind = "g", a = a, b = b }
				end
			end
			local function intersect(l1, l2): Pt?
				if l1.kind ~= "g" and l1.kind == l2.kind then
					return nil
				end
				local function asLine(l)
					if l.kind == "v" then
						return { 0, l.c }, { 1, 0 }
					elseif l.kind == "u" then
						return { l.c, 0 }, { 0, 1 }
					end
					return l.a, { l.b[1] - l.a[1], l.b[2] - l.a[2] }
				end
				local p1, d1 = asLine(l1)
				local p2, d2 = asLine(l2)
				local den = d1[1] * d2[2] - d1[2] * d2[1]
				if math.abs(den) < 1e-9 then
					return nil
				end
				local t = ((p2[1] - p1[1]) * d2[2] - (p2[2] - p1[2]) * d2[1]) / den
				return { p1[1] + d1[1] * t, p1[2] + d1[2] * t }
			end
			local snapped: Poly = {}
			for i = 1, n do
				local prev = lines[(i - 2) % n + 1]
				local pt = intersect(prev, lines[i])
				if pt and (pt[1] - q[i][1]) ^ 2 + (pt[2] - q[i][2]) ^ 2 < 25 then
					table.insert(snapped, pt)
				elseif not pt then
					-- parallel snapped neighbours: vertex is redundant
				else
					table.insert(snapped, q[i])
				end
			end
			if #snapped >= 3 then
				q = snapped
			end
		end
		table.insert(uvPolys, q)
	end

	-- Edges in (u,v); collect vertex v values for strip boundaries.
	local edges: { Edge } = {}
	local vs: { number } = {}
	for _, p in uvPolys do
		for i = 1, #p do
			local a, b = p[i], p[i % #p + 1]
			local au, av = a[1], a[2]
			local bu, bv = b[1], b[2]
			table.insert(vs, av)
			if math.abs(bv - av) > 1e-4 then
				table.insert(edges, { u0 = au, v0 = av, u1 = bu, v1 = bv, id = #edges + 1 })
			end
		end
	end
	table.sort(vs)
	local levels: { number } = {}
	for _, v in vs do
		if #levels == 0 or v - levels[#levels] > 0.02 then
			table.insert(levels, v)
		end
	end

	-- Build trapezoids strip by strip, merging with the previous strip when the
	-- same pair of polygon edges continues (exact, no approximation).
	local open: { [string]: Trap } = {}
	local done: { Trap } = {}
	for i = 1, #levels - 1 do
		local va, vb = levels[i], levels[i + 1]
		local vm = (va + vb) / 2
		local hits = {}
		for _, e in edges do
			local lo, hi = math.min(e.v0, e.v1), math.max(e.v0, e.v1)
			if vm > lo and vm < hi then
				table.insert(hits, { u = uAt(e, vm), e = e })
			end
		end
		table.sort(hits, function(x, y)
			return x.u < y.u
		end)
		-- Non-zero winding so overlapping source pieces union instead of cancelling.
		local spans = {}
		local wind, left = 0, nil
		for _, h in hits do
			local before = wind
			wind += if h.e.v1 > h.e.v0 then 1 else -1
			if before == 0 and wind ~= 0 then
				left = h.e
			elseif before ~= 0 and wind == 0 and left then
				table.insert(spans, { left, h.e })
				left = nil
			end
		end
		local nextOpen: { [string]: Trap } = {}
		for _, span in spans do
			local l, r = span[1], span[2]
			local key = l.id .. ":" .. r.id
			local t = open[key]
			if t and math.abs(t.v1 - va) < 1e-6 then
				t.v1 = vb
				open[key] = nil
			else
				t = { v0 = va, v1 = vb, l = l, r = r }
			end
			nextOpen[key] = t
		end
		for _, t in open do
			table.insert(done, t)
		end
		open = nextOpen
	end
	for _, t in open do
		table.insert(done, t)
	end

	local out = {}
	for _, t in done do
		local v0, v1 = t.v0, t.v1
		local l0, l1 = uAt(t.l, v0), uAt(t.l, v1)
		local r0, r1 = uAt(t.r, v0), uAt(t.r, v1)
		local boxL, boxR = math.max(l0, l1), math.min(r0, r1)
		if boxR - boxL < 0.05 then
			-- Slanted sides cross: fall back to two triangles.
			triToWedges(toXZ(l0, v0), toXZ(r0, v0), toXZ(r1, v1), out)
			triToWedges(toXZ(l0, v0), toXZ(r1, v1), toXZ(l1, v1), out)
		else
			local cu, cv = (boxL + boxR) / 2, (v0 + v1) / 2
			local c = toXZ(cu, cv)
			table.insert(out, { kind = "box", cx = c[1], cz = c[2], sx = boxR - boxL, sz = v1 - v0, ux = ux, uz = uz })
			if math.abs(l0 - l1) > 0.05 then
				if l0 < l1 then
					table.insert(out, { kind = "wedge", a = toXZ(l1, v0), b = toXZ(l0, v0), c = toXZ(l1, v1) })
				else
					table.insert(out, { kind = "wedge", a = toXZ(l0, v1), b = toXZ(l1, v1), c = toXZ(l0, v0) })
				end
			end
			if math.abs(r0 - r1) > 0.05 then
				if r0 > r1 then
					table.insert(out, { kind = "wedge", a = toXZ(r1, v0), b = toXZ(r0, v0), c = toXZ(r1, v1) })
				else
					table.insert(out, { kind = "wedge", a = toXZ(r0, v1), b = toXZ(r1, v1), c = toXZ(r0, v0) })
				end
			end
		end
	end
	return out
end

-- Area covered by primitives (for validation).
function SlabReducer.primitiveArea(prims: { any }): number
	local a = 0
	for _, p in prims do
		if p.kind == "box" then
			a += p.sx * p.sz
		else
			local A, B, C = p.a, p.b, p.c
			a += math.abs((B[1] - A[1]) * (C[2] - A[2]) - (C[1] - A[1]) * (B[2] - A[2])) / 2
		end
	end
	return a
end

return SlabReducer
