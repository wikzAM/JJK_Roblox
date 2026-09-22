--!nonstrict
-- Builds the map's ground from the tiles tools/ground_tin.py writes: triangles
-- between the city blocks, each two WedgeParts (TriangleShell), solid downward.
-- Edit-time tool, not required at game start. Tiles come over the local sink
-- (tools/source_slice_sink.py) because a tile is up to a few hundred KB.
--
--   local G = require(game.ServerScriptService.Server.GroundBuilder)
--   G.BuildTile("ground_p0_m1")   -- one 512-stud tile, replaced if it exists
--   G.BuildAll()                  -- every tile in the index
--   G.Clear()                     -- remove workspace.Ground
local GroundBuilder = {}

local Http = game:GetService("HttpService")
local TriangleShell = require(script.Parent.TriangleShell)

local SINK = "http://127.0.0.1:58999/get/tools/source_slices/ground/tiles/"
local THICKNESS = 2.0
local COLOR = Color3.fromRGB(98, 98, 102)   -- asphalt grey: reads apart from the concrete slabs; hit debris takes this colour
local MATERIAL = Enum.Material.Concrete

local function fetch(name)
	local ok, body = pcall(function() return Http:GetAsync(SINK .. name .. ".json", true) end)
	assert(ok, "Could not reach the sink -- is tools/source_slice_sink.py running? " .. tostring(body))
	return Http:JSONDecode(body)
end

local function folder()
	local f = workspace:FindFirstChild("Ground")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Ground"
		f.Parent = workspace
	end
	return f
end

function GroundBuilder.BuildTile(name)
	local tile = fetch(name)
	local parent = folder()
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local model = Instance.new("Model")
	model.Name = name
	-- thickness grows DOWN from every triangle
	local sum = Vector3.zero
	for _, t in tile.triangles do sum += Vector3.new(t[1][1], t[1][2], t[1][3]) end
	local centre = sum / #tile.triangles
	local _, metrics = TriangleShell.Build(model, tile.triangles, {
		thickness = THICKNESS,
		name = "Ground",
		color = COLOR,
		material = MATERIAL,
		fillToward = centre - Vector3.new(0, 100000, 0),
	})
	for _, p in model:GetChildren() do p:SetAttribute("ShellWedge", nil) end
	model.Parent = parent
	return string.format("%s: %d triangles -> %d wedges (%d too thin, skipped)",
		name, metrics.triangles, metrics.wedges, metrics.skipped)
end

function GroundBuilder.BuildAll()
	local index = fetch("index")
	local total, lines = 0, {}
	for i, row in index do
		local line = GroundBuilder.BuildTile(row[1])
		total += 1
		if i % 4 == 0 then task.wait() end
		table.insert(lines, line)
	end
	return total .. " tiles\n" .. table.concat(lines, "\n")
end

function GroundBuilder.Clear()
	local f = workspace:FindFirstChild("Ground")
	if f then f:Destroy() end
end

return GroundBuilder
