--!nonstrict
-- Facade layout from a source-slice plan: where the glass goes, as pure data.
--
-- Shared by the server (hit maths, later) and the client (which builds the
-- parts), so both always agree. Nothing here creates instances.
--
-- A building's floors are already there as slabs, and their edges read as
-- horizontal bands -- they ARE the spandrels. So a facade is one glass strip per
-- wall run per storey, filling the gap between one slab's top and the next
-- slab's underside, set back a little behind the slab edge. Short runs (tight
-- corners, notches) get an opaque pier instead, which reads as a column.
--
-- Measured over the plans (tools, Sept 24): 2,231 buildings, 4.6 storeys each,
-- 13.3 runs per storey; ~109k strips map-wide, ~10k within 700 studs of a
-- camera. That is why the strips are built client-side near the camera only.
--
--   local Layout = require(ReplicatedStorage.Shared.FacadeLayout)
--   local frame, strips = Layout.ForModel(buildingModel)   -- world frame + strips in it
--   for _, s in strips do  part.CFrame = frame * s.cframe; part.Size = s.size  end
local FacadeLayout = {}

local Http = game:GetService("HttpService")

FacadeLayout.CONFIG = {
	mergeDeg = 3,        -- consecutive edges turning less than this are one wall run
	minRun = 6,          -- studs: shorter runs become opaque piers, not glass
	inset = 0.6,         -- studs: glass sits this far behind the slab edge (a shadow line, no z-fighting)
	thickness = 0.3,     -- studs: glass thickness
	overlap = 0.15,      -- studs: glass tucks this far into the slabs above and below
	interiorProbe = 1.0, -- studs: how far outside an edge to test whether it is shared with another piece
	parapet = 3.5,       -- studs: where the storey above does not cover a run (a setback), a low
	                     -- parapet instead of full-height glass standing open to the sky
}

-- Facade styles: tinted glass that reads as real curtain wall, not turquoise.
-- A building's style comes from a hash of its id, so every client picks the same.
FacadeLayout.STYLES = {
	{name = "blue-grey", glass = Color3.fromRGB(52, 66, 80),  transparency = 0.15, reflectance = 0.18},
	{name = "green-grey", glass = Color3.fromRGB(58, 74, 70), transparency = 0.15, reflectance = 0.16},
	{name = "bronze",    glass = Color3.fromRGB(78, 66, 54),  transparency = 0.12, reflectance = 0.15},
	{name = "dark",      glass = Color3.fromRGB(34, 38, 44),  transparency = 0.10, reflectance = 0.22},
	{name = "silver",    glass = Color3.fromRGB(110, 120, 128), transparency = 0.20, reflectance = 0.25},
	{name = "blue",      glass = Color3.fromRGB(46, 70, 98),  transparency = 0.15, reflectance = 0.20},
}
FacadeLayout.PIER = {color = Color3.fromRGB(163, 162, 165), material = Enum.Material.Concrete}

function FacadeLayout.StyleOf(id)
	local h = 5381
	for i = 1, #id do h = (h * 33 + string.byte(id, i)) % 2147483647 end
	return FacadeLayout.STYLES[h % #FacadeLayout.STYLES + 1]
end

local function signedArea(ring)
	local a = 0
	for i = 1, #ring do
		local p, q = ring[i], ring[i % #ring + 1]
		a += p[1] * q[2] - q[1] * p[2]
	end
	return a / 2
end

local function inside(ring, x, z)
	local hit = false
	local j = #ring
	for i = 1, #ring do
		local xi, zi, xj, zj = ring[i][1], ring[i][2], ring[j][1], ring[j][2]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then hit = not hit end
		j = i
	end
	return hit
end

-- Merge a ring's nearly collinear edges into runs: {a = {x, z}, b = {x, z}}
local function runsOf(ring, mergeRad)
	local n = #ring
	local ang = {}
	for i = 1, n do
		local p, q = ring[i], ring[i % n + 1]
		ang[i] = math.atan2(q[2] - p[2], q[1] - p[1])
	end
	-- signed turn at vertex j, between the edge arriving there and the one leaving
	local function turnAt(j)
		local i = (j - 2) % n + 1
		return (ang[j] - ang[i] + math.pi) % (2 * math.pi) - math.pi
	end
	-- start at a real corner, so a run never straddles the ring's seam
	local start = 1
	for i = 1, n do
		if math.abs(turnAt(i)) >= mergeRad then start = i break end
	end
	local runs, i, count = {}, start, 0
	while count < n do
		local a = ring[i]
		local j, acc = i, 0
		while true do
			j = j % n + 1
			count += 1
			if count >= n then break end
			local t = turnAt(j)
			-- a corner ends the run; so does a gentle curve once its turning adds up,
			-- or a round tower (every vertex under the limit) would become one chord
			-- cutting straight through the building
			if math.abs(t) >= mergeRad or math.abs(acc + t) >= mergeRad then break end
			acc += t
		end
		table.insert(runs, {a = a, b = ring[j]})
		i = j
	end
	return runs
end

-- Strips in the plan's own frame. level i's outline carries the storey from
-- level i's top to level i+1's underside; the roof level gets none.
function FacadeLayout.Build(plan, config)
	local cfg = config or FacadeLayout.CONFIG
	local mergeRad = math.rad(cfg.mergeDeg)
	local strips = {}
	local levels = plan.levels
	for i = 1, #levels - 1 do
		local lv, above = levels[i], levels[i + 1]
		local y0 = lv.y + lv.thickness - cfg.overlap
		local y1 = above.y + cfg.overlap
		local h = y1 - y0
		if h > 1 then
			for pi, ring in lv.pieces do
				local outward = signedArea(ring) > 0 and 1 or -1
				for ri, run in runsOf(ring, mergeRad) do
					local ax, az, bx, bz = run.a[1], run.a[2], run.b[1], run.b[2]
					local dx, dz = bx - ax, bz - az
					local len = math.sqrt(dx * dx + dz * dz)
					if len > 0.5 then
						local ux, uz = dx / len, dz / len
						local nx, nz = uz * outward, -ux * outward     -- outward normal
						-- an edge shared with another piece of the same floor is interior: no facade
						local shared = false
						if #lv.pieces > 1 then
							local mx = (ax + bx) / 2 + nx * cfg.interiorProbe
							local mz = (az + bz) / 2 + nz * cfg.interiorProbe
							for pj, other in lv.pieces do
								if pj ~= pi and inside(other, mx, mz) then shared = true break end
							end
						end
						if not shared then
							local cx = (ax + bx) / 2 - nx * cfg.inset
							local cz = (az + bz) / 2 - nz * cfg.inset
							-- is this run under the storey above? test a point just inside its edge
							local px, pz = (ax + bx) / 2 - nx * 1.5, (az + bz) / 2 - nz * 1.5
							local covered = false
							for _, upper in above.pieces do
								if inside(upper, px, pz) then covered = true break end
							end
							local kind, sh = len < cfg.minRun and "pier" or "glass", h
							if not covered then kind, sh = "parapet", math.min(cfg.parapet, h) end
							table.insert(strips, {
								kind = kind,
								storey = i, piece = pi, run = ri,
								cframe = CFrame.fromMatrix(Vector3.new(cx, y0 + sh / 2, cz), Vector3.new(ux, 0, uz), Vector3.yAxis),
								size = Vector3.new(len, sh, cfg.thickness),
							})
						end
					end
				end
			end
		end
	end
	return strips
end

-- The FAR shell, coarse on purpose. Merging the near strips wherever a run
-- repeats on consecutive storeys kept 87% of them (the level-curve outlines
-- shift a little every floor), so instead: storeys in bands of FAR_BAND, each
-- band one ring of tall panels from its bottom floor's outline, with edges
-- merged up to FAR_MERGE_DEG and runs under FAR_MIN_RUN dropped. Seen only
-- beyond the near radius, where that precision is invisible.
FacadeLayout.FAR = {band = 5, mergeDeg = 15, minRun = 8, inset = 0.6, thickness = 0.3}

function FacadeLayout.BuildFarCoarse(plan, far)
	far = far or FacadeLayout.FAR
	local out = {}
	local levels = plan.levels
	local mergeRad = math.rad(far.mergeDeg)
	local i = 1
	while i < #levels do
		local j = math.min(i + far.band, #levels)
		local lv = levels[i]
		local y0 = lv.y + lv.thickness
		local y1 = levels[j].y
		local h = y1 - y0
		if h > 1 then
			for pi, ring in lv.pieces do
				local outward = signedArea(ring) > 0 and 1 or -1
				for _, run in runsOf(ring, mergeRad) do
					local ax, az, bx, bz = run.a[1], run.a[2], run.b[1], run.b[2]
					local dx, dz = bx - ax, bz - az
					local len = math.sqrt(dx * dx + dz * dz)
					if len >= far.minRun then
						local ux, uz = dx / len, dz / len
						local nx, nz = uz * outward, -ux * outward
						local shared = false
						if #lv.pieces > 1 then
							local mx, mz = (ax + bx) / 2 + nx, (az + bz) / 2 + nz
							for pj, other in lv.pieces do
								if pj ~= pi and inside(other, mx, mz) then shared = true break end
							end
						end
						if not shared then
							table.insert(out, {kind = "glass",
								cframe = CFrame.fromMatrix(Vector3.new((ax + bx) / 2 - nx * far.inset, y0 + h / 2, (az + bz) / 2 - nz * far.inset),
									Vector3.new(ux, 0, uz), Vector3.yAxis),
								size = Vector3.new(len, h, far.thickness)})
						end
					end
				end
			end
		end
		i = j
	end
	return out
end

-- (kept for the record: the exact vertical merge that saved only 13%)
function FacadeLayout.BuildFar(strips)
	local open = {}     -- key -> the merged strip still growing upward
	local out = {}
	local function key(s)
		local p = s.cframe.Position
		return string.format("%s|%.1f|%.1f|%.1f|%.1f", s.kind, p.X, p.Z, s.size.X, s.cframe.XVector.X)
	end
	for _, s in strips do
		if s.kind ~= "parapet" then
			local k = key(s)
			local m = open[k]
			local bottom = s.cframe.Position.Y - s.size.Y / 2
			if m and m.storey == s.storey - 1 and math.abs(m.top - bottom) < 1 then
				m.top = s.cframe.Position.Y + s.size.Y / 2
				m.storey = s.storey
			else
				m = {kind = s.kind, storey = s.storey, bottom = bottom, top = s.cframe.Position.Y + s.size.Y / 2,
					cframe = s.cframe, size = s.size}
				open[k] = m
				table.insert(out, m)
			end
		end
	end
	for _, m in out do
		local p = m.cframe.Position
		local h = m.top - m.bottom
		m.cframe = CFrame.fromMatrix(Vector3.new(p.X, m.bottom + h / 2, p.Z), m.cframe.XVector, Vector3.yAxis)
		m.size = Vector3.new(m.size.X, h, m.size.Z)
	end
	return out
end

-- The building's CURRENT plan frame (it may have been moved since it was built),
-- the same rule SourceSliceBuilder.Regenerate uses.
function FacadeLayout.FrameOf(model)
	local origin = model:GetAttribute("SourceSliceOriginCFrame")
	local saved = model:GetAttribute("SourceSliceSavedPivot")
	if typeof(origin) ~= "CFrame" then return nil end
	if typeof(saved) == "CFrame" then return model:GetPivot() * saved:Inverse() * origin end
	return origin
end

local cache = setmetatable({}, {__mode = "k"})
function FacadeLayout.ForModel(model, config)
	local encoded = model:GetAttribute("SourceSlicePlan")
	if type(encoded) ~= "string" then return nil end
	local frame = FacadeLayout.FrameOf(model)
	if not frame then return nil end
	local entry = cache[model]
	if not entry or entry.encoded ~= encoded then
		entry = {encoded = encoded, strips = FacadeLayout.Build(Http:JSONDecode(encoded), config)}
		cache[model] = entry
	end
	return frame, entry.strips
end

return FacadeLayout
