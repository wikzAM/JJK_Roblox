local M = {}
function M.floors(post)
	local Http = game:GetService("HttpService")
	local gp = RaycastParams.new(); gp.FilterType = Enum.RaycastFilterType.Include
	gp.FilterDescendantsInstances = {workspace.Terrain, workspace.Roads}
	local bp = RaycastParams.new(); bp.FilterType = Enum.RaycastFilterType.Include
	bp.FilterDescendantsInstances = {workspace.Buildings}
	local keep = {Slab = true, Part = true, GrayBlock = true}
	local tot, over, rows, byB, hist = 0, 0, {}, {}, {0, 0, 0, 0, 0}
	for _, m in workspace.Buildings:GetChildren() do
		for _, p in m.Interior.Floor1:GetDescendants() do
			if p:IsA("BasePart") and keep[p.Name] then
				local cf, s = p.CFrame, p.Size
				local wedge = p:IsA("WedgePart")
				local top, cs = -math.huge, {}
				for _, sx in {-1, 1} do for _, sy in {-1, 1} do for _, sz in {-1, 1} do
					if not (wedge and sy == 1 and sz == -1) then
						local c = cf * Vector3.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2)
						top = math.max(top, c.Y); table.insert(cs, c)
					end
				end end end
				local ctr = cf.Position
				for _, c in cs do
					local out = Vector3.new(c.X - ctr.X, 0, c.Z - ctr.Z)
					if out.Magnitude > 0.1 then
						local q = c + out.Unit * 3
						local r = workspace:Raycast(Vector3.new(q.X, top + 40, q.Z), Vector3.new(0, -80, 0), gp)
						if r and not workspace:Raycast(r.Position + Vector3.new(0, 0.2, 0), Vector3.new(0, 14, 0), bp) then
							tot += 1
							local d = r.Position.Y - top
							if d > 0 then
								over += 1
								hist[d < 0.5 and 1 or d < 1 and 2 or d < 2 and 3 or d < 4 and 4 or 5] += 1
								byB[m.Name] = math.max(byB[m.Name] or 0, d)
								if post then table.insert(rows, string.format("%.1f,%.1f,%.2f,%.2f,%s,%s", r.Position.X, r.Position.Z, top, d, r.Instance == workspace.Terrain and "T" or "R", m.Name)) end
							end
						end
					end
				end
			end
		end
	end
	if post then Http:PostAsync("http://localhost:58999/floor_viol.txt", table.concat(rows, "\n")) end
	local nb = 0 for _ in byB do nb += 1 end
	return string.format("exposed samples %d, ground above floor top %d (%.2f%%) in %d buildings; <0.5:%d <1:%d <2:%d <4:%d >=4:%d",
		tot, over, 100 * over / math.max(tot, 1), nb, hist[1], hist[2], hist[3], hist[4], hist[5])
end
return M
