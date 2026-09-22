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
local MATERIAL = Enum.Material.Concrete
-- Measured: smooth terrain puts the surface ~2 studs (half a voxel) above the
-- height the occupancy encodes (200 probes: median +2.00, p5 +1.21, p95 +2.84).
local SURFACE_BIAS = 2.0

local function fetch(name)
	local ok, body = pcall(function() return Http:GetAsync(SINK .. name .. ".json", true) end)
	assert(ok, "Could not reach the sink -- is tools/source_slice_sink.py running? " .. tostring(body))
	return Http:JSONDecode(body)
end

function GroundTerrain.ClearAll()
	workspace.Terrain:Clear()
	return "terrain cleared"
end

function GroundTerrain.WriteChunk(name)
	local c = fetch(name)
	local top = -math.huge
	for _, h in c.h do if h > top then top = h end end
	local ny = math.max(1, math.ceil((top + VOXEL - c.y0) / VOXEL))
	local materials, occupancy = {}, {}
	for i = 1, c.nx do
		local mi, oi = {}, {}
		materials[i], occupancy[i] = mi, oi
		for j = 1, ny do
			local mj, oj = {}, {}
			mi[j], oi[j] = mj, oj
			local yb = c.y0 + (j - 1) * VOXEL
			for k = 1, c.nz do
				local h = c.h[(i - 1) * c.nz + k] - SURFACE_BIAS
				local occ = math.clamp((h - yb) / VOXEL, 0, 1)
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

function GroundTerrain.WriteAll(first, last)
	local index = fetch("index")
	local lines = {}
	for i = first or 1, math.min(last or #index, #index) do
		table.insert(lines, GroundTerrain.WriteChunk(index[i]))
	end
	return table.concat(lines, "\n")
end

return GroundTerrain
