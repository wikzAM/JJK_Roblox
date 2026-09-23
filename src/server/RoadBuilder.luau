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
		local kind, x, y, z, yaw, pitch, length, thickness, width, class, wayId = table.unpack(s)
		local look = LOOK[kind]
		local part = Instance.new("Part")
		part.Name = kind == "roadway" and "Road" or (kind == "apron" and "Apron" or "Pavement")
		part.Size = Vector3.new(length, thickness, width)
		-- y is the SURFACE height: drop the part by half its depth so its top lands there
		if kind == "apron" then
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
