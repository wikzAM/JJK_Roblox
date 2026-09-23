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
		part.Name = kind == "roadway" and "Road" or "Pavement"
		part.Size = Vector3.new(length, thickness, width)
		-- y is the SURFACE height: drop the part by half its depth so its top lands there
		part.CFrame = CFrame.new(x, y - thickness / 2, z)
			* CFrame.Angles(0, -yaw, 0)
			* CFrame.Angles(0, 0, pitch)
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
