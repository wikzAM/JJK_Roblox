--!nonstrict
-- Writes the map's ground as smooth Terrain from tools/ground_terrain.py chunks:
-- zero parts. Each voxel column is solid below its surface height, fractional
-- in the voxel the surface passes through (smooth terrain places the surface by
-- occupancy, so slopes are smooth rather than 4-stud stairs), air above.
-- Edit-time tool; chunks come over the local sink (tools/source_slice_sink.py).
--
--   local T = require(game.ServerScriptService.Server.GroundTerrain)
--   T.ClearAll()            -- wipe the old failed-import terrain (whole map)
--   T.WriteChunk("chunk_3_4")
--   T.WriteAll(first, last) -- chunks by index range, for batching
local GroundTerrain = {}

local Http = game:GetService("HttpService")
local SINK = "http://127.0.0.1:58999/get/tools/source_slices/ground/terrain/"
local VOXEL = 4
-- The density ramp spans 2 voxels: with a 1-voxel ramp a height sitting
-- mid-voxel clamps its neighbours to full and empty, leaving the mesher a
-- single partial voxel and a terraced surface.
local RAMP = 8
local MATERIAL = Enum.Material.Concrete
-- Smooth terrain puts its surface where occupancy crosses 0.5 BETWEEN VOXEL
-- CENTRES. Filling everything below solid and giving the surface voxel a
-- fraction therefore steps the surface by half a voxel whenever the height
-- passes a centre: 2-stud terraces across every slope, and a +2 stud bias.
-- Writing occupancy as a ramp instead -- 0.5 + (height - voxel centre)/4,
-- clamped -- puts the 0.5 crossing exactly on the height, smoothly.

local function fetch(name)
	local ok, body = pcall(function() return Http:GetAsync(SINK .. name .. ".json", true) end)
	assert(ok, "Could not reach the sink -- is tools/source_slice_sink.py running? " .. tostring(body))
	return Http:JSONDecode(body)
end

function GroundTerrain.ClearAll()
	workspace.Terrain:Clear()
	return "terrain cleared"
end

-- offset: studs added to every height (0 = the files as generated)
function GroundTerrain.WriteChunk(name, offset)
	offset = offset or 0
	local c = fetch(name)
	if offset ~= 0 then
		for i, h in c.h do c.h[i] = h + offset end
	end
	local top = -math.huge
	for _, h in c.h do if h > top then top = h end end
	-- one more layer, so the ramp's upper (mostly empty) voxel exists
	local ny = math.max(1, math.ceil((top + RAMP - c.y0) / VOXEL))
	local materials, occupancy = {}, {}
	for i = 1, c.nx do
		local mi, oi = {}, {}
		materials[i], occupancy[i] = mi, oi
		for j = 1, ny do
			local mj, oj = {}, {}
			mi[j], oi[j] = mj, oj
			local yb = c.y0 + (j - 1) * VOXEL
			for k = 1, c.nz do
				local h = c.h[(i - 1) * c.nz + k]
				local occ = math.clamp(0.5 + (h - (yb + VOXEL / 2)) / RAMP, 0, 1)
				mj[k] = occ > 0 and MATERIAL or Enum.Material.Air
				oj[k] = occ
			end
		end
	end
	local region = Region3.new(Vector3.new(c.x0, c.y0, c.z0),
		Vector3.new(c.x0 + c.nx * VOXEL, c.y0 + ny * VOXEL, c.z0 + c.nz * VOXEL))
	workspace.Terrain:WriteVoxels(region, VOXEL, materials, occupancy)
	return string.format("%s: %d x %d x %d voxels", name, c.nx, ny, c.nz)
end

function GroundTerrain.WriteAll(first, last, offset)
	local index = fetch("index")
	local lines = {}
	for i = first or 1, math.min(last or #index, #index) do
		table.insert(lines, GroundTerrain.WriteChunk(index[i], offset))
	end
	return table.concat(lines, "\n")
end

return GroundTerrain
