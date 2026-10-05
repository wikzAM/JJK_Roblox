-- Command Bar / MCP (Edit): export every ground-floor slab piece for tools/floor_cap.py.
-- Needs tools/source_slice_sink.py running; writes tools/source_slices/floor1_parts.txt
-- (building|topY|x,z;... -- 8 corners for a box, 6 for a wedge: a wedge has no top-front edge).
local Http = game:GetService("HttpService")
local keep = {Slab = true, Part = true, GrayBlock = true}
local lines = {}
for _, m in workspace.Buildings:GetChildren() do
	for _, p in m.Interior.Floor1:GetDescendants() do
		if p:IsA("BasePart") and keep[p.Name] then
			local cf, s = p.CFrame, p.Size
			local wedge = p:IsA("WedgePart")
			local top, pts = -math.huge, {}
			for _, sx in {-1, 1} do for _, sy in {-1, 1} do for _, sz in {-1, 1} do
				if not (wedge and sy == 1 and sz == -1) then
					local c = cf * Vector3.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2)
					top = math.max(top, c.Y)
					table.insert(pts, string.format("%.1f,%.1f", c.X, c.Z))
				end
			end end end
			table.insert(lines, string.format("%s|%.2f|%s", m.Name, top, table.concat(pts, ";")))
		end
	end
end
local chunk, size, first = {}, 0, true
local function flush()
	if #chunk == 0 then return end
	Http:PostAsync("http://localhost:58999/floor1_parts.txt", table.concat(chunk, "\n") .. "\n",
		Enum.HttpContentType.TextPlain, false, (not first) and {["X-Append"] = "1"} or nil)
	first = false; chunk = {}; size = 0
end
for _, l in lines do
	table.insert(chunk, l); size += #l + 1
	if size > 700000 then flush() end
end
flush()
print(#lines .. " ground-floor pieces exported")
