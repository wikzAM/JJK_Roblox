--!nonstrict
-- Builds the roads and pavements that tools/road_parts.py lays out from
-- OpenStreetMap, one 512-stud tile per call. Each slab is a single Part: its
-- length runs along the street, it is tilted to the ground's slope, and its TOP
-- sits at the ground surface (pavements one stud higher, as a curb). The slabs
-- are deep enough to cover the terrain's voxel steps under them, and pavements
-- simply run under the buildings' ground-floor slabs.
--
--   local R = require(game.ServerScriptService.Server.RoadBuilder)
--   R.BuildTile("tile_p0_m1")
--   R.BuildAll(first, last)   -- by index, for batching
--   R.Clear()
local RoadBuilder = {}

local Http = game:GetService("HttpService")
local SINK = "http://127.0.0.1:58999/get/tools/source_slices/ground/roads/"

local LOOK = {
	roadway = {material = Enum.Material.Asphalt, color = Color3.fromRGB(62, 62, 66)},
	pavement = {material = Enum.Material.Concrete, color = Color3.fromRGB(154, 152, 148)},
	-- the ground between the roads: terrain alone terraces on gentle slopes
	apron = {material = Enum.Material.Concrete, color = Color3.fromRGB(138, 136, 132)},
	-- a round cap at a node where a road bends or ends: fills the outside of the corner
	joint = {material = Enum.Material.Asphalt, color = Color3.fromRGB(62, 62, 66)},
	-- one flat square per junction (tools/road_fit.py); the streets stop at its edge
	pad = {material = Enum.Material.Asphalt, color = Color3.fromRGB(62, 62, 66)},
}

local function fetch(name)
	local ok, body = pcall(function() return Http:GetAsync(SINK .. name .. ".json", true) end)
	assert(ok, "Could not reach the sink -- is tools/source_slice_sink.py running? " .. tostring(body))
	return Http:JSONDecode(body)
end

local function folder()
	local f = workspace:FindFirstChild("Roads")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Roads"
		f.Parent = workspace
	end
	return f
end

function RoadBuilder.BuildTile(name)
	local tile = fetch(name)
	local parent = folder()
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local model = Instance.new("Model")
	model.Name = name
	for _, s in tile.slabs do
		local kind, x, y, z, yaw, pitch, length, thickness, width, class, wayId, slopeZ = table.unpack(s)
		local look = LOOK[kind]
		local part = Instance.new("Part")
		part.Name = kind == "roadway" and "Road" or kind == "apron" and "Apron" or kind == "joint" and "Joint"
			or kind == "pad" and "Pad" or "Pavement"
		part.Size = Vector3.new(length, thickness, width)
		-- y is the SURFACE height: drop the part by half its depth so its top lands there
		if kind == "joint" then
			-- a cylinder's axis is its X: turn it upright, diameter = the road's width
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(thickness, width, width)
			part.CFrame = CFrame.new(x, y - thickness / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		elseif kind == "pad" then
			-- a square tilted to the ground field: pitch = slope along its local X
			-- (the widest street's direction), slopeZ = slope along its local Z
			local ux, uz = math.cos(yaw), math.sin(yaw)
			local ax = Vector3.new(ux, pitch, uz).Unit
			local az = Vector3.new(-uz, slopeZ or 0, ux).Unit
			local up = az:Cross(ax).Unit
			part.CFrame = CFrame.fromMatrix(Vector3.new(x, y, z) - up * thickness / 2, ax, up)
		elseif kind == "apron" then
			-- a square of ground: yaw is unused, the two angles are its slopes
			-- along z (roll) and along x (pitch)
			part.CFrame = CFrame.new(x, y - thickness / 2, z) * CFrame.Angles(-yaw, 0, pitch)
		else
			part.CFrame = CFrame.new(x, y - thickness / 2, z)
				* CFrame.Angles(0, -yaw, 0)
				* CFrame.Angles(0, 0, pitch)
		end
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.Material = look.material
		part.Color = look.color
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part:SetAttribute("RoadClass", class)
		part:SetAttribute("RoadWay", wayId)
		part.Parent = model
	end
	model.Parent = parent
	return string.format("%s: %d slabs", name, #tile.slabs)
end

-- Terrain is written from the same height field, but its surface lands up to a
-- couple of studs off (smooth terrain reconstructs it from voxel occupancy), so
-- a few slabs end up under it. Lift those until their top clears.
function RoadBuilder.LiftOverTerrain(margin, maxLift)
	margin = margin or 0.3
	-- beyond this the ground genuinely rises there (a pad, a bank): a slab that
	-- needs more would hover, so it is removed instead
	maxLift = maxLift or 3.0
	local maxGap = 4.0    -- studs of air UNDER a slab before it is dropped back onto the ground
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {workspace.Terrain}
	local f = workspace:FindFirstChild("Roads")
	if not f then return "no roads" end
	local lifted, removed, dropped, worst = 0, 0, 0, 0
	for _, model in f:GetChildren() do
		for _, part in model:GetChildren() do
			local top = part.Position.Y + part.Size.Y / 2
			local hit = workspace:Raycast(Vector3.new(part.Position.X, top + 40, part.Position.Z), Vector3.new(0, -80, 0), params)
			-- FLOATING is measured from the slab's UNDERSIDE, not its top: a slab
			-- is 8 studs thick and terrain is written 3 studs below the surface,
			-- so a few studs between top and terrain is the slab sitting IN the
			-- ground, which is what it should do.
			local bottom = top - part.Size.Y
			if hit and bottom - hit.Position.Y > maxGap then
				local drop = bottom - hit.Position.Y - 1.0
				part.CFrame = part.CFrame - Vector3.new(0, drop, 0)
				dropped += 1
			elseif hit and hit.Position.Y > top + 0.05 then
				local lift = hit.Position.Y - top + margin
				if lift > maxLift then
					part:Destroy()
					removed += 1
				else
					part.CFrame = part.CFrame + Vector3.new(0, lift, 0)
					lifted += 1
					worst = math.max(worst, lift)
				end
			end
		end
	end
	return string.format("lifted %d (worst %.1f studs), dropped %d back onto the ground, removed %d that would have hovered",
		lifted, worst, dropped, removed)
end

-- Draw order where roads of different class overlap (matches tools/road_parts.py KIND)
local PRIORITY = {motorway = 6, trunk = 5, primary = 4, secondary = 3, tertiary = 2, residential = 1,
	unclassified = 1, living_street = 1, pedestrian = 1, service = 0}

-- Terrain was written 3 studs BELOW the ground field so the old part ground
-- could sit on it; that part ground is gone, so roads placed at the field rode
-- 5.2 studs above the open ground on average. Settle every slab end and joint
-- onto the terrain itself. Heights come from one smoothed terrain sample per
-- POINT, so the slabs and joint meeting at a node all read the same value and
-- junctions stay level (nudging whole slabs one by one is what broke them).
function RoadBuilder.SettleOnTerrain(first, last, lift)
	lift = lift or 0.15
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {workspace.Terrain}
	local cache = {}
	local function terrainY(x, z)
		local key = string.format("%.0f,%.0f", x * 2, z * 2)     -- half-stud grid: shared nodes hit the same entry
		if cache[key] then return cache[key] end
		local sum, n = 0, 0
		for _, o in {{0, 0}, {4, 0}, {-4, 0}, {0, 4}, {0, -4}} do  -- smooths the terrain's 2-stud terraces
			local hit = workspace:Raycast(Vector3.new(x + o[1], 2000, z + o[2]), Vector3.new(0, -4000, 0), params)
			if hit then sum += hit.Position.Y; n += 1 end
		end
		cache[key] = n > 0 and sum / n or nil
		return cache[key]
	end
	local f = workspace:FindFirstChild("Roads")
	if not f then return "no roads" end
	local tiles = f:GetChildren()
	local moved, skipped, total = 0, 0, 0
	for i = first or 1, math.min(last or #tiles, #tiles) do
		for _, part in tiles[i]:GetChildren() do
			local bump = (PRIORITY[part:GetAttribute("RoadClass")] or 0) * 0.05
			if part.Name == "Joint" then
				local y = terrainY(part.Position.X, part.Position.Z)
				if y then
					local t = part.Size.X
					local before = part.Position.Y
					part.CFrame = CFrame.new(part.Position.X, y + lift + bump - 0.03 - t / 2, part.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
					total += math.abs(part.Position.Y - before); moved += 1
				else skipped += 1 end
			elseif part.Name == "Pad" then
				-- flat, at the terrain under its centre, a hair over the streets meeting it
				local y = terrainY(part.Position.X, part.Position.Z)
				if y then
					local before = part.Position.Y
					local yaw = math.atan2(part.CFrame.RightVector.Z, part.CFrame.RightVector.X)
					part.CFrame = CFrame.new(part.Position.X, y + lift + bump + 0.08 - part.Size.Y / 2, part.Position.Z)
						* CFrame.Angles(0, -yaw, 0)
					total += math.abs(part.Position.Y - before); moved += 1
				else skipped += 1 end
			elseif part.Name == "Road" then
				local d = Vector3.new(part.CFrame.RightVector.X, 0, part.CFrame.RightVector.Z).Unit
				local hl = (part.Size.X / 2 - 1) * math.cos(math.asin(math.clamp(part.CFrame.RightVector.Y, -1, 1)))
				local c = part.Position
				local a, b = Vector3.new(c.X, 0, c.Z) - d * hl, Vector3.new(c.X, 0, c.Z) + d * hl
				local ya, yb = terrainY(a.X, a.Z), terrainY(b.X, b.Z)
				if ya and yb then
					local t = part.Size.Y
					local yaw = math.atan2(d.Z, d.X)
					local pitch = math.atan2(yb - ya, 2 * hl)
					local before = part.Position.Y
					part.CFrame = CFrame.new(c.X, (ya + yb) / 2 + lift + bump - t / 2, c.Z)
						* CFrame.Angles(0, -yaw, 0) * CFrame.Angles(0, 0, pitch)
					total += math.abs(part.Position.Y - before); moved += 1
				else skipped += 1 end
			end
		end
	end
	return string.format("settled %d road parts onto the terrain (mean move %.1f studs), %d had no terrain under them",
		moved, moved > 0 and total / moved or 0, skipped)
end

-- Lay the WHOLE network onto the terrain with ONE offset. Every piece's height
-- comes from the same smooth ground field (tools/road_fit.py), so pieces that
-- meet at a point already agree; settling each piece onto the terrain on its
-- own put neighbours on different 2-stud terrain levels -- steps at every
-- junction. Measure the median gap between the field and the terrain under the
-- road centres, and move everything by that.
function RoadBuilder.SettleOnField()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {workspace.Terrain}
	local f = workspace:FindFirstChild("Roads")
	if not f then return "no roads" end
	local gaps, parts = {}, {}
	for _, tile in f:GetChildren() do
		for _, part in tile:GetChildren() do
			table.insert(parts, part)
			local top = part.Name == "Joint" and part.Position.Y + part.Size.X / 2
				or (part.Position + part.CFrame.UpVector * part.Size.Y / 2).Y
			local hit = workspace:Raycast(Vector3.new(part.Position.X, top + 200, part.Position.Z), Vector3.new(0, -400, 0), params)
			if hit then table.insert(gaps, hit.Position.Y - top) end
		end
	end
	table.sort(gaps)
	local offset = gaps[math.ceil(#gaps / 2)] + 0.15
	for _, part in parts do part.CFrame = part.CFrame + Vector3.new(0, offset, 0) end
	return string.format("moved %d road parts by %.2f studs (median field-to-terrain gap; p10 %.1f, p90 %.1f)",
		#parts, offset, gaps[math.ceil(#gaps * 0.1)], gaps[math.ceil(#gaps * 0.9)])
end

-- Shape the terrain along each road, voxel by voxel. Box carving (CarveTerrain)
-- steps at the 4-stud voxel grid, so a diagonal road's edge came out as a
-- sawtooth wherever the ground was higher than the road. Instead every voxel
-- near a road gets a height window: under the road the ground is held just below
-- the asphalt, and moving out from the edge the window opens at SLOPE studs per
-- stud -- a cut bank where the road runs into a slope, an embankment where it
-- runs out over a dip, and no floating slab edge either way. Only terrain inside
-- REACH studs of a road is touched, and only toward the road's own level.
function RoadBuilder.ShapeShoulders(first, last, reach, slope, fill)
	reach = reach or 14
	-- 0.4, not steeper: in the gap between two carriageways the window rises from
	-- both sides, and at 0.8 a thin ridge of terrain peaked up as a row of spikes
	slope = slope or 0.4
	-- FILL IS OFF BY DEFAULT: an embankment raised for one road buried a
	-- neighbouring road the pass had not reached yet. The cut alone only ever
	-- lowers terrain, so any number of roads combine safely (the lowest wins),
	-- and SettleOnTerrain has already put the ground near road level.
	fill = fill == true
	local V = 4
	local T = workspace.Terrain
	local f = workspace:FindFirstChild("Roads")
	if not f then return "no roads" end
	local tiles = f:GetChildren()
	local shaped, cut, filled = 0, 0, 0
	for i = first or 1, math.min(last or #tiles, #tiles) do
		for _, part in tiles[i]:GetChildren() do
			-- the road's footprint in plan, and its top height as a function of position
			local pos = part.Position
			local d, hx, hz, slopeAlong, topC
			if part.Name == "Joint" then
				d, hx, hz, slopeAlong, topC = Vector3.xAxis, 0, 0, 0, pos.Y + part.Size.X / 2
			else
				local r = part.CFrame.RightVector
				local horiz = math.sqrt(r.X * r.X + r.Z * r.Z)
				d = Vector3.new(r.X / horiz, 0, r.Z / horiz)
				hx, hz = part.Size.X / 2 * horiz, part.Size.Z / 2
				slopeAlong = r.Y / horiz
				topC = (pos + part.CFrame.UpVector * part.Size.Y / 2).Y
			end
			local radius = part.Name == "Joint" and part.Size.Y / 2 or 0
			local perp = Vector3.new(-d.Z, 0, d.X)
			local ext = math.max(hx, hz) + radius + reach
			local span = math.abs(hx * slopeAlong) + reach * slope + V * 2
			local region = Region3.new(Vector3.new(pos.X - ext, topC - span, pos.Z - ext),
				Vector3.new(pos.X + ext, topC + span, pos.Z + ext)):ExpandToGrid(V)
			local mats, occ = T:ReadVoxels(region, V)
			local lo = region.CFrame.Position - region.Size / 2
			local changed = false
			for ix = 1, #occ do
				local cx = lo.X + (ix - 0.5) * V
				for iz = 1, #occ[1][1] do
					local cz = lo.Z + (iz - 0.5) * V
					local rx, rz = cx - pos.X, cz - pos.Z
					local a, b = rx * d.X + rz * d.Z, rx * perp.X + rz * perp.Z
					local dist
					if part.Name == "Joint" then
						dist = math.max(math.sqrt(rx * rx + rz * rz) - radius, 0)
					else
						local dx, dz = math.max(math.abs(a) - hx, 0), math.max(math.abs(b) - hz, 0)
						dist = math.sqrt(dx * dx + dz * dz)
					end
					if dist < reach then
						local top = topC + math.clamp(a, -hx, hx) * slopeAlong
						-- MEASURED (a flat test block, raycast): a voxel [yb, yb+4] draws the
						-- surface at yb+2 when (nearly) empty over a full voxel, yb+4 at half
						-- occupancy and yb+6 when full -- 2 studs ABOVE its own top. So terrain
						-- only lands on 2-stud levels, and a linear occupancy-to-height reading
						-- buries the road. Work in those levels: a voxel may hold at most the
						-- level that stays under CAP, and at least the level that reaches FLOOR.
						-- ...and the RENDERED surface sits up to ~2 studs above the collision one
						-- measured by that raycast (a first pass at these +2 levels left spikes
						-- and blobs over the asphalt), so the window is held another 2 lower.
						-- Under the road itself hold the ground 6 down: a lone part-filled
						-- voxel renders as a PEAK whose apex climbs above the flat-plane level
						-- measured above, and these came up through the asphalt as spikes.
						-- The slab is 8 deep, so nothing down there is ever seen.
						local cap = dist <= 0 and top - 6 or top - 2.5 + dist * slope   -- the ground may not rise above this
						local floor = fill and top - 4.5 - dist * slope or -math.huge   -- nor sit below this
						for iy = 1, #occ[1] do
							local yb = lo.Y + (iy - 1) * V
							local o = occ[ix][iy][iz]
							local capOcc = cap >= yb + 6 and 1 or cap >= yb + 4 and 0.5 or 0
							local want = floor > yb + 4 and 1 or floor > yb + 2 and 0.5 or 0
							local n = math.min(math.max(math.min(o, capOcc), want), capOcc)
							if n > o and o <= 0.001 then mats[ix][iy][iz] = Enum.Material.Concrete end
							if math.abs(n - o) > 0.01 then
								if n < o then cut += 1 else filled += 1 end
								if n <= 0.001 then mats[ix][iy][iz] = Enum.Material.Air end
								occ[ix][iy][iz] = n
								changed = true
							end
						end
					end
				end
			end
			if changed then T:WriteVoxels(region, V, mats, occ) end
			shaped += 1
		end
	end
	return string.format("shaped terrain along %d road parts (%d voxels lowered, %d raised)", shaped, cut, filled)
end

-- Every road part's plan geometry, hashed by 32-stud cell, and a probe that
-- gives a point's distance from a part's footprint and the road's top there.
-- Shared by ShapeTerrain and RestoreCorridors.
local CELL = 32
-- Studio's terrain = the chunk files + FILE_TO_STUDIO. Until Sept 24 it was -5
-- (terrain written with SUBSURFACE 8 under the old part ground, never rewritten
-- when that ground was removed, so every building stood on a 5-stud plinth).
-- It was then rewritten from the files at +2.5 (GroundTerrain.WriteAll(1, n,
-- 2.5)), which puts the ground a median 1.7 studs under the ground-floor slab
-- tops -- the look the part ground had. Keep this in step with that offset.
local FILE_TO_STUDIO = 2.5
local function roadIndex(reach)
	local f = workspace:FindFirstChild("Roads")
	if not f then return nil end
	local all, hash = {}, {}
	for _, tile in f:GetChildren() do
		for _, part in tile:GetChildren() do
			local g = {part = part, pos = part.Position, joint = part.Name == "Joint", way = part:GetAttribute("RoadWay") or part}
			if g.joint then
				g.d, g.hx, g.hz, g.slopeAlong, g.top, g.radius = Vector3.xAxis, 0, 0, 0, g.pos.Y + part.Size.X / 2, part.Size.Y / 2
			else
				local r = part.CFrame.RightVector
				local horiz = math.sqrt(r.X * r.X + r.Z * r.Z)
				g.d = Vector3.new(r.X / horiz, 0, r.Z / horiz)
				g.hx, g.hz, g.slopeAlong, g.radius = part.Size.X / 2 * horiz, part.Size.Z / 2, r.Y / horiz, 0
				g.top = (g.pos + part.CFrame.UpVector * part.Size.Y / 2).Y
			end
			g.ext = math.max(g.hx, g.hz) + g.radius + reach
			all[part] = g
			for cx = math.floor((g.pos.X - g.ext) / CELL), math.floor((g.pos.X + g.ext) / CELL) do
				for cz = math.floor((g.pos.Z - g.ext) / CELL), math.floor((g.pos.Z + g.ext) / CELL) do
					local key = cx * 100000 + cz
					local list = hash[key]
					if not list then list = {}; hash[key] = list end
					table.insert(list, g)
				end
			end
		end
	end
	local function probe(g, x, z)
		local rx, rz = x - g.pos.X, z - g.pos.Z
		if g.joint then
			return math.max(math.sqrt(rx * rx + rz * rz) - g.radius, 0), g.top
		end
		local a, b = rx * g.d.X + rz * g.d.Z, rx * -g.d.Z + rz * g.d.X
		local dx, dz = math.max(math.abs(a) - g.hx, 0), math.max(math.abs(b) - g.hz, 0)
		return math.sqrt(dx * dx + dz * dz), g.top + math.clamp(a, -g.hx, g.hx) * g.slopeAlong
	end
	local function near(x, z)
		return hash[math.floor(x / CELL) * 100000 + math.floor(z / CELL)] or {}
	end
	return all, near, probe
end

-- Put the ORIGINAL ground back near the roads, from the same chunks
-- GroundTerrain wrote it from, before shaping again. Voxels further than
-- MARGIN from every road are left exactly as they are, so nothing else --
-- including any hand edits -- is touched.
function RoadBuilder.RestoreCorridors(first, last, margin)
	margin = margin or 24
	local TSINK = "http://127.0.0.1:58999/get/tools/source_slices/ground/terrain/"
	local V, RAMP = 4, 8     -- GroundTerrain's own values
	local _, near, probe = roadIndex(margin)
	if not near then return "no roads" end
	local index = Http:JSONDecode(Http:GetAsync(TSINK .. "index.json", true))
	local restored, chunks = 0, 0
	for ci = first or 1, math.min(last or #index, #index) do
		local c = Http:JSONDecode(Http:GetAsync(TSINK .. index[ci] .. ".json", true))
		-- which columns are in a road corridor?
		local want, any = {}, false
		for i = 1, c.nx do
			local x = c.x0 + (i - 0.5) * V
			for k = 1, c.nz do
				local z = c.z0 + (k - 0.5) * V
				for _, g in near(x, z) do
					if (probe(g, x, z)) < margin then want[(i - 1) * c.nz + k] = true; any = true; break end
				end
			end
		end
		if any then
			local top = -math.huge
			for _, h in c.h do if h > top then top = h end end
			-- a little headroom above the old top, to clear anything a fill raised there
			local ny = math.max(1, math.ceil((top + RAMP - c.y0) / V)) + 4
			local region = Region3.new(Vector3.new(c.x0, c.y0, c.z0), Vector3.new(c.x0 + c.nx * V, c.y0 + ny * V, c.z0 + c.nz * V))
			local mats, occ = workspace.Terrain:ReadVoxels(region, V)
			for i = 1, c.nx do
				for k = 1, c.nz do
					if want[(i - 1) * c.nz + k] then
						local h = c.h[(i - 1) * c.nz + k] + FILE_TO_STUDIO
						for j = 1, ny do
							local o = math.clamp(0.5 + (h - (c.y0 + (j - 1) * V + V / 2)) / RAMP, 0, 1)
							occ[i][j][k] = o
							mats[i][j][k] = o > 0 and Enum.Material.Concrete or Enum.Material.Air
						end
						restored += 1
					end
				end
			end
			workspace.Terrain:WriteVoxels(region, V, mats, occ)
			chunks += 1
		end
	end
	return string.format("restored the original ground in %d road-corridor columns across %d chunks", restored, chunks)
end

-- GRADE THE ROAD CORRIDORS IN THE HEIGHT DOMAIN. This supersedes ShapeTerrain,
-- ShapeShoulders and CarveTerrain. The original ground is written with a smooth
-- occupancy RAMP over two voxels (GroundTerrain), which is what makes its
-- slopes smooth; every per-voxel pass set hard 0 / 0.5 / 1 occupancies and left
-- lumps, rock-like ridges and terraces along the roads. Here each column near a
-- road starts from its ORIGINAL height (the chunk data GroundTerrain wrote
-- from), takes the roads' limits as a HEIGHT, and is rewritten with the same
-- ramp -- so the ground stays exactly as smooth as the rest of the map:
--   under a road      at most top - 1.2   (hidden inside the 8-deep slab)
--   beside it         at most top - 0.3 + dist * CUT     (a cut bank)
--   within BERM studs at least top - 0.6 - dist          (a 45-degree berm, no slab side showing)
-- ...all measured as where the surface SHOWS. The ramp draws the surface ~2
-- studs above the height it encodes (the first run at these numbers buried the
-- roads; the same bias is why terrain written 3 under the ground floors shows
-- ~1 under them), so the heights written are RAMP_BIAS lower.
-- Every road near a column constrains it (lowest ceiling, highest floor, ceiling
-- wins), so one road's berm can never bury another road.
function RoadBuilder.GradeCorridors(first, last, reach, cut, berm)
	reach = reach or 16
	cut = cut or 0.7
	-- the ground rises to meet a road edge over BERM studs at BERM_SLOPE, so the
	-- slab's side does not show. It was off (Sept 24) because a 3-stud berm is
	-- narrower than a voxel and rendered as spikes; 8 studs is two voxels wide.
	berm = berm or 8
	local BERM_SLOPE = 0.6
	local TSINK = "http://127.0.0.1:58999/get/tools/source_slices/ground/terrain/"
	local V, RAMP = 4, 8     -- GroundTerrain's own values
	local RAMP_BIAS = 4.0    -- studs the ramp's visible surface sits above the height it encodes (measured 3 to 3.9)
	local GAP = 18           -- studs: ground between two different streets closer than this is held flat
	local TERRACE_MARGIN = 2.5
	-- ...and painted: terrain under a road, within PAVE of its edge, or in such a
	-- gap is Asphalt, so gaps between OSM ways at junctions read as road instead
	-- of pale ground showing through (terrain Asphalt is tinted to the slabs)
	local PAVE = 2
	workspace.Terrain:SetMaterialColor(Enum.Material.Asphalt, Color3.fromRGB(62, 62, 66))
	local _, near, probe = roadIndex(reach)
	if not near then return "no roads" end
	local index = Http:JSONDecode(Http:GetAsync(TSINK .. "index.json", true))
	local graded, lowered, raised, chunks = 0, 0, 0, 0
	for ci = first or 1, math.min(last or #index, #index) do
		local c = Http:JSONDecode(Http:GetAsync(TSINK .. index[ci] .. ".json", true))
		local target, any, top = {}, false, -math.huge
		local pavedCols = {}
		for i = 1, c.nx do
			local x = c.x0 + (i - 0.5) * V
			for k = 1, c.nz do
				local z = c.z0 + (k - 0.5) * V
				local ceil, floor, hit = math.huge, -math.huge, false
				local byWay = {}    -- the nearest part of each street near this column
				for _, g in near(x, z) do
					local d, t = probe(g, x, z)
					if d < reach then
						hit = true
						-- TERRACE_MARGIN deeper than the collision surface needs: on a slope
						-- smooth terrain RENDERS in steps that swing 2-4 studs around its
						-- collision surface (a ramp slope tested at y 1600, Sept 29), and the
						-- step peaks came up through roads that were correctly above it
						ceil = math.min(ceil, (d <= 0 and t - 1.2 - TERRACE_MARGIN
							or t - 0.3 - TERRACE_MARGIN * math.max(0, 1 - d / 6) + d * cut) - RAMP_BIAS)
						if d < berm then floor = math.max(floor, t - 0.6 - TERRACE_MARGIN - d * BERM_SLOPE - RAMP_BIAS) end
						local way = g.way
						if not byWay[way] or d < byWay[way][1] then byWay[way] = {d, t} end
					end
				end
				-- Between two DIFFERENT streets less than GAP apart, the cut banks
				-- rising from each meet in a thin ridge, and smooth terrain draws a
				-- ridge one or two voxels wide as spikes above its height -- rims
				-- tracing every junction. Hold such a gap flat at road level instead,
				-- so it reads as paving between the carriageways.
				local d1, t1, d2, t2 = math.huge, 0, math.huge, 0
				for _, v in byWay do
					if v[1] < d1 then d2, t2, d1, t1 = d1, t1, v[1], v[2]
					elseif v[1] < d2 then d2, t2 = v[1], v[2] end
				end
				local paved = d1 <= PAVE
				if d1 + d2 < GAP then
					ceil = math.min(ceil, math.min(t1, t2) - 0.3 - TERRACE_MARGIN - RAMP_BIAS)
					paved = true
				end
				if hit then
					local idx = (i - 1) * c.nz + k
					local h0 = c.h[idx] + FILE_TO_STUDIO
					local h = math.min(math.max(h0, floor), ceil)
					target[idx] = h
					if paved then pavedCols[idx] = true end
					any = true
					if h < h0 - 0.05 then lowered += 1 elseif h > h0 + 0.05 then raised += 1 end
					top = math.max(top, h0, h)
				end
			end
		end
		if any then
			-- headroom above the highest ground here, so earlier fills above it are cleared too
			local ny = math.max(1, math.ceil((top + RAMP - c.y0) / V)) + 4
			local region = Region3.new(Vector3.new(c.x0, c.y0, c.z0), Vector3.new(c.x0 + c.nx * V, c.y0 + ny * V, c.z0 + c.nz * V))
			local mats, occ = workspace.Terrain:ReadVoxels(region, V)
			for i = 1, c.nx do
				for k = 1, c.nz do
					local h = target[(i - 1) * c.nz + k]
					if h then
						local mat = pavedCols[(i - 1) * c.nz + k] and Enum.Material.Asphalt or Enum.Material.Concrete
						for j = 1, ny do
							local o = math.clamp(0.5 + (h - (c.y0 + (j - 1) * V + V / 2)) / RAMP, 0, 1)
							occ[i][j][k] = o
							mats[i][j][k] = o > 0 and mat or Enum.Material.Air
						end
						graded += 1
					end
				end
			end
			workspace.Terrain:WriteVoxels(region, V, mats, occ)
			chunks += 1
		end
	end
	return string.format("graded %d columns in %d chunks (%d lowered for a road, %d raised into a berm)", graded, chunks, lowered, raised)
end

-- Shape the ground along every road, with a spatial hash so each voxel's
-- ceiling is the LOWEST cap of every road near it (a per-road fill buried
-- neighbouring roads).
--  * under a road: held 6 studs down -- isolated part-filled voxels render as
--    peaks that climb above the flat level, and came up through the asphalt;
--  * beside it: a cut bank rising at CUTSLOPE, so ground higher than the road
--    steps back instead of a sawtooth at the voxel grid;
--  * right at the edge: a short berm (BERM studs, 45 degrees) so the slab's side
--    does not show. A 14-stud embankment ended in a cliff wherever the natural
--    ground fell away further -- visible as a jagged ridge along the road.
-- Smooth terrain lands on 2-stud levels (measured: a voxel draws its surface at
-- yb+2 / yb+4 / yb+6 as it goes low / half / full), and the render matches the
-- raycast within half a stud on flat ground, so the window between ceiling and
-- floor is kept 2 studs wide.
function RoadBuilder.ShapeTerrain(first, last, reach, cutSlope, berm)
	reach = reach or 16
	cutSlope = cutSlope or 0.7
	berm = berm or 4
	local V = 4
	local T = workspace.Terrain
	local all, near, probe = roadIndex(reach)
	if not all then return "no roads" end
	local tiles = workspace.Roads:GetChildren()
	local function capOf(dist, top) return dist <= 0 and top - 6 or top - 0.2 + dist * cutSlope end
	local function floorOf(dist, top) return dist < berm and top - 2.2 - dist or -math.huge end
	local cut, filled, shaped = 0, 0, 0
	for i = first or 1, math.min(last or #tiles, #tiles) do
		for _, part in tiles[i]:GetChildren() do
			local g = all[part]
			local span = math.abs(g.hx * g.slopeAlong) + reach * cutSlope + V * 3
			local region = Region3.new(Vector3.new(g.pos.X - g.ext, g.top - span, g.pos.Z - g.ext),
				Vector3.new(g.pos.X + g.ext, g.top + span, g.pos.Z + g.ext)):ExpandToGrid(V)
			local mats, occ = T:ReadVoxels(region, V)
			local lo = region.CFrame.Position - region.Size / 2
			local changed = false
			for ix = 1, #occ do
				local x = lo.X + (ix - 0.5) * V
				for iz = 1, #occ[1][1] do
					local z = lo.Z + (iz - 0.5) * V
					local myDist, myTop = probe(g, x, z)
					if myDist < reach then
						local cap = math.huge
						for _, h in near(x, z) do
							local dd, tt = probe(h, x, z)
							if dd < reach then cap = math.min(cap, capOf(dd, tt)) end
						end
						local floor = math.min(floorOf(myDist, myTop), cap - 2)
						for iy = 1, #occ[1] do
							local yb = lo.Y + (iy - 1) * V
							local o = occ[ix][iy][iz]
							local capOcc = cap >= yb + 6 and 1 or cap >= yb + 4 and 0.5 or 0
							local want = floor > yb + 4 and 1 or floor > yb + 2 and 0.5 or 0
							local n = math.min(math.max(math.min(o, capOcc), want), capOcc)
							if math.abs(n - o) > 0.01 then
								if n < o then cut += 1 else filled += 1 end
								if n <= 0.001 then mats[ix][iy][iz] = Enum.Material.Air
								elseif o <= 0.001 then mats[ix][iy][iz] = Enum.Material.Concrete end
								occ[ix][iy][iz] = n
								changed = true
							end
						end
					end
				end
			end
			if changed then T:WriteVoxels(region, V, mats, occ) end
			shaped += 1
		end
	end
	return string.format("shaped terrain along %d road parts (%d voxels lowered, %d raised)", shaped, cut, filled)
end

-- Where terrain rises through the asphalt, cut the terrain rather than move the
-- road. LiftOverTerrain nudged slabs one at a time, so the slabs meeting at a
-- junction ended up at different heights; every slab and joint here stays where
-- the ground field put it, so junctions stay level. Only terrain ABOVE a road's
-- top, inside its footprint, is removed.
function RoadBuilder.CarveTerrain(first, last, clearance, sink)
	clearance = clearance or 14
	-- start the cut this far BELOW the road's top: smooth terrain rebuilds its
	-- surface from the part-filled voxel that straddles the top, so a cut that
	-- starts exactly at the top leaves a skin up to ~2.5 studs thick. The slab
	-- is 8 studs deep, so what is cut below its top is hidden inside it.
	sink = sink or 2
	clearance += sink
	local f = workspace:FindFirstChild("Roads")
	if not f then return "no roads" end
	local tiles = f:GetChildren()
	local carved = 0
	for i = first or 1, math.min(last or #tiles, #tiles) do
		for _, part in tiles[i]:GetChildren() do
			if part.Name == "Joint" then
				local top = part.Position.Y + part.Size.X / 2
				workspace.Terrain:FillBlock(CFrame.new(part.Position.X, top - sink + clearance / 2, part.Position.Z),
					Vector3.new(part.Size.Y, clearance, part.Size.Z), Enum.Material.Air)
			else
				workspace.Terrain:FillBlock(part.CFrame * CFrame.new(0, part.Size.Y / 2 - sink + clearance / 2, 0),
					Vector3.new(part.Size.X, clearance, part.Size.Z), Enum.Material.Air)
			end
			carved += 1
		end
	end
	return string.format("cleared terrain above %d road parts", carved)
end

-- Ground truth, last: any road piece with a building part in the 2.5 studs
-- over its surface is narrowed 2 studs at a time until clear, or removed.
-- tools/road_fit.py fits roads to a rasterised footprint mask, which leaves a
-- handful of corner-grazing cases (4 of 3,112 on Sept 29); this makes it exact.
function RoadBuilder.ClearOfBuildings(minWidth)
	minWidth = minWidth or 8
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = {workspace.Buildings}
	local probe = Instance.new("Part")
	probe.Anchored = true; probe.CanCollide = false; probe.CanQuery = false; probe.Transparency = 1
	probe.Parent = workspace
	local function touches(p, width)
		if p.Name == "Joint" then
			probe.Shape = Enum.PartType.Cylinder
			probe.Size = Vector3.new(2.5, width, width)
			probe.CFrame = CFrame.new(p.Position + Vector3.new(0, p.Size.X / 2 + 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		else
			probe.Shape = Enum.PartType.Block
			probe.Size = Vector3.new(p.Size.X, 2.5, width)
			probe.CFrame = p.CFrame * CFrame.new(0, p.Size.Y / 2 + 1.5, 0)
		end
		return #workspace:GetPartsInPart(probe, op) > 0
	end
	local narrowed, removed = 0, 0
	for _, tile in workspace.Roads:GetChildren() do
		for _, p in tile:GetChildren() do
			local w = p.Name == "Joint" and p.Size.Y or p.Size.Z
			if touches(p, w) then
				while w >= minWidth and touches(p, w) do w -= 2 end
				if w < minWidth then
					p:Destroy(); removed += 1
				else
					if p.Name == "Joint" then p.Size = Vector3.new(p.Size.X, w, w)
					else p.Size = Vector3.new(p.Size.X, p.Size.Y, w) end
					narrowed += 1
				end
			end
		end
	end
	probe:Destroy()
	return string.format("clear of buildings: %d narrowed, %d removed", narrowed, removed)
end

function RoadBuilder.BuildAll(first, last)
	local index = fetch("index")
	local built = 0
	for i = first or 1, math.min(last or #index, #index) do
		RoadBuilder.BuildTile(index[i][1])
		built += 1
	end
	return string.format("%d tiles built (%d in the index)", built, #index)
end

function RoadBuilder.Clear()
	local f = workspace:FindFirstChild("Roads")
	if f then f:Destroy() end
	return "roads cleared"
end

return RoadBuilder
