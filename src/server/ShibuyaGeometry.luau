--!nonstrict
-- Read-only triangle-component extraction for ShibuyaAutoBuilder.
local Geometry = {}
function Geometry.Scan(source)
assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
source = source or game.ServerStorage:FindFirstChild("Shibuya") or workspace:FindFirstChild("Shibuya")
assert(source, "Pass the imported Shibuya model (Workspace or ServerStorage) to Scan")
local AS = game:GetService("AssetService")
local components = {}
for meshIndex, part in source:GetDescendants() do
	if not part:IsA("MeshPart") then continue end
	local mesh = AS:CreateEditableMeshAsync(part.MeshContent)
	local vertices, roots, keys, positions = mesh:GetVertices(), {}, {}, {}
	local scale = part.Size / part.MeshSize
	local function root(id)
		while roots[id] ~= id do roots[id] = roots[roots[id]]; id = roots[id] end
		return id
	end
	for _, id in vertices do
		local p = part.CFrame:PointToWorldSpace(mesh:GetPosition(id) * scale)
		positions[id] = p
		local key = string.format("%d:%d:%d", math.round(p.X * 20), math.round(p.Y * 20), math.round(p.Z * 20))
		roots[id] = keys[key] or id
		keys[key] = roots[id]
	end
	local faces = mesh:GetFaces()
	local triangles = {}
	for _, f in faces do
		local vs = mesh:GetFaceVertices(f)
		local a = root(vs[1])
		for j = 2, #vs do roots[root(vs[j])] = a end
		table.insert(triangles, vs)
	end
	local groups = {}
	for _, id in vertices do
		local r, p = root(id), positions[id]
		local g = groups[r]
		if not g then g = {min = p, max = p, triangles = {}, meshIndex = meshIndex}; groups[r] = g end
		g.min = g.min:Min(p); g.max = g.max:Max(p)
	end
	for _, vs in triangles do
		table.insert(groups[root(vs[1])].triangles, {positions[vs[1]], positions[vs[2]], positions[vs[3]]})
	end
	local accepted, total = 0, 0
	for _, g in groups do
		total += 1
		local s = g.max - g.min
		if s.Y >= 25 and s.X >= 12 and s.Z >= 12 and s.X < 900 and s.Z < 900 then
			table.insert(components, g); accepted += 1
		end
	end
	print("SHIBUYA_COMPONENTS", meshIndex, total, accepted)
	mesh:Destroy()
	task.wait()
end
table.sort(components, function(a,b) return (a.max.Y-a.min.Y) > (b.max.Y-b.min.Y) end)
return components
end
return Geometry
