local M = {}
-- place the camera looking at target from a clear spot with line of sight
function M.look(target, dist, elev)
	dist = dist or 120; elev = elev or 0.6
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local best
	for _, e in {elev, elev + 0.25, elev + 0.5, 1.2} do
		for a = 0, 330, 30 do
			local r = math.rad(a)
			local dir = Vector3.new(math.cos(r), e, math.sin(r)).Unit
			local pos = target + dir * dist
			local ov = OverlapParams.new()
			if #workspace:GetPartBoundsInRadius(pos, 3, ov) == 0 then
				local hit = workspace:Raycast(pos, (target - pos) * 0.97)
				if not hit then best = pos break end
			end
		end
		if best then break end
	end
	best = best or target + Vector3.new(0, dist * 2, 1)
	cam.CFrame = CFrame.lookAt(best, target)
	return best
end
-- stand on the road slab nearest P (XZ), eye height up, looking along it
function M.street(P, eye, sign, pitchDown)
	eye = eye or 7; sign = sign or 1; pitchDown = pitchDown or 4
	local best, bd
	for _, p in workspace.Roads:GetDescendants() do
		if p:IsA("BasePart") then
			local loc = p.CFrame:PointToObjectSpace(Vector3.new(P.X, p.Position.Y, P.Z))
			local dx = math.max(math.abs(loc.X) - p.Size.X/2, 0)
			local dz = math.max(math.abs(loc.Z) - p.Size.Z/2, 0)
			local d = dx + dz
			if not bd or d < bd then best, bd = p, d end
		end
	end
	local cf = best.CFrame
	local loc = cf:PointToObjectSpace(Vector3.new(P.X, cf.Position.Y, P.Z))
	local lx = math.clamp(loc.X, -best.Size.X/2, best.Size.X/2)
	local at = cf * CFrame.new(lx, best.Size.Y/2 + eye, 0)
	local dir = cf.RightVector * sign
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(at.Position, at.Position + dir * 100 - Vector3.new(0, pitchDown, 0))
	return best, at.Position
end
-- street-level view of point P: a clear spot 25-70 studs away, eye above the ground there
function M.near(P, eye)
	eye = eye or 9
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local tp = RaycastParams.new(); tp.FilterType = Enum.RaycastFilterType.Include
	tp.FilterDescendantsInstances = {workspace.Terrain, workspace.Roads}
	for _, dist in {35, 50, 25, 70} do
		for a = 0, 345, 15 do
			local r = math.rad(a)
			local q = P + Vector3.new(math.cos(r), 0, math.sin(r)) * dist
			local g = workspace:Raycast(q + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), tp)
			if g then
				local pos = g.Position + Vector3.new(0, eye, 0)
				if #workspace:GetPartBoundsInRadius(pos, 3) == 0 then
					local hit = workspace:Raycast(pos, (P + Vector3.new(0, 2, 0) - pos) * 0.95)
					if not hit then
						cam.CFrame = CFrame.lookAt(pos, P)
						return pos
					end
				end
			end
		end
	end
	return nil
end
return M
