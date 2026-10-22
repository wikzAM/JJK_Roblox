-- Edit-time cinematic for the sector comparison (run as a temporary ModuleScript via MCP).
-- An attacker punches a dummy; the dummy flies on a kinematic straight path (no physics,
-- tumbling in place), breaks through a building's ground floor and out the far side,
-- lands and slides. Chase camera. Works on either Workspace.SectorTest copy:
--   flat  (B): hole cut into the flat textured skin (texture-aligned pieces)
--   parts (A): detailed facade parts removed, glass panes shown shattered (original
--              glass system), upper skins cut like the flat version.
-- Every change is reversible with Scene.Reset().
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Scene = {}

local state = { hidden = {}, fx = nil, posed = {} }
local G = 196.2

local function fx(): Folder
	if not state.fx or not state.fx.Parent then
		state.fx = Instance.new("Folder")
		state.fx.Name = "_SceneFX"
		state.fx.Parent = workspace
	end
	return state.fx
end

local function hide(p: BasePart)
	if state.hidden[p] == nil then
		local rec = { collide = p.CanCollide, query = p.CanQuery, transparency = p.Transparency, kids = {} }
		state.hidden[p] = rec
		p.Transparency = 1 -- replicated (Team Create viewers see it too)
		p.CanCollide = false
		p.CanQuery = false
		for _, g in p:GetChildren() do
			if g:IsA("Texture") or g:IsA("Decal") then
				rec.kids[g] = g.Transparency
				g.Transparency = 1
			elseif g:IsA("SurfaceGui") then
				rec.kids[g] = g.Enabled
				g.Enabled = false
			end
		end
	end
end

function Scene.Reset()
	for p, rec in state.hidden do
		if p.Parent then
			p.Transparency = rec.transparency
			p.CanCollide, p.CanQuery = rec.collide, rec.query
			for g, v in rec.kids do
				if g.Parent then
					if g:IsA("SurfaceGui") then
						g.Enabled = v
					else
						g.Transparency = v
					end
				end
			end
		end
	end
	state.hidden = {}
	if state.fx then
		state.fx:Destroy()
		state.fx = nil
	end
	local cc = Lighting:FindFirstChild("_SceneImpact")
	if cc then
		cc:Destroy()
	end
	workspace.CurrentCamera.FieldOfView = 70
end

local function box(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Parent = parent or fx()
	return p
end

-- Rebuild a textured skin Part minus a circle (stair-stepped rows) around world point P.
local function cutSkin(skin: BasePart, P: Vector3, R: number)
	local L, H = skin.Size.X, skin.Size.Y
	local lp = skin.CFrame:PointToObjectSpace(P)
	if math.abs(lp.Z) >= R then
		return false
	end
	R = math.sqrt(R * R - lp.Z * lp.Z)
	local cu, cv = L / 2 - lp.X, H / 2 - lp.Y
	local tex = skin:FindFirstChildOfClass("Texture")
	local function piece(u0, u1, v0, v1)
		if u1 - u0 < 0.05 or v1 - v0 < 0.05 then
			return
		end
		local p = skin:Clone()
		for _, c in p:GetChildren() do
			if not c:IsA("Texture") then
				c:Destroy()
			end
		end
		p.Size = Vector3.new(u1 - u0, v1 - v0, skin.Size.Z)
		p.CFrame = skin.CFrame * CFrame.new(L / 2 - (u0 + u1) / 2, H / 2 - (v0 + v1) / 2, 0)
		p.LocalTransparencyModifier = 0
		p.Transparency = skin.Transparency
		local t = p:FindFirstChildOfClass("Texture")
		if t and tex then
			t.OffsetStudsU = tex.OffsetStudsU + u0
			t.OffsetStudsV = tex.OffsetStudsV + v0
		end
		p.Parent = fx()
	end
	local top, bot = math.max(0, cv - R), math.min(H, cv + R)
	if top >= bot or cu + R < 0 or cu - R > L then
		return false
	end
	piece(0, L, 0, top)
	piece(0, L, bot, H)
	local v = top
	while v < bot - 1e-6 do
		local vb = math.min(v + 1.5, bot)
		local half = math.sqrt(math.max(0, R * R - ((v + vb) / 2 - cv) ^ 2))
		half = math.floor(half / 1.5 + 0.5) * 1.5
		if half <= 0 then
			piece(0, L, v, vb)
		else
			piece(0, math.clamp(cu - half, 0, L), v, vb)
			piece(math.clamp(cu + half, 0, L), L, v, vb)
		end
		v = vb
	end
	hide(skin)
	return true
end

-- Kinematic debris/shards/dust, animated by Scene's frame loop.
local movers = {}
local CONCRETE = { Color3.fromRGB(196, 184, 160), Color3.fromRGB(150, 150, 152), Color3.fromRGB(128, 126, 122) }

-- Burst debris (owner spec: about 20 parts, no collision while flying).
local wallSplit = nil -- {point, normal(inward), inside floor Y, outside ground Y}
local function groundFor(pos: Vector3, default: number): number
	if wallSplit then
		return (pos - wallSplit[1]):Dot(wallSplit[2]) > 0 and wallSplit[3] or wallSplit[4]
	end
	return default
end
local function spawnBurst(P: Vector3, dir: Vector3, groundY: number, rng: Random, glassy: boolean)
	local side = dir:Cross(Vector3.yAxis).Unit
	for i = 1, 20 do
		local s = rng:NextNumber(1.2, 5)
		local c = CONCRETE[rng:NextInteger(1, #CONCRETE)]
		local kind = i % 4
		local p
		if kind == 0 or kind == 2 then
			p = Instance.new("WedgePart")
			p.Anchored, p.CanCollide, p.CanQuery = true, false, false
			p.Material = Enum.Material.Concrete
			p.Color = c
			p.Size = kind == 0 and Vector3.new(s * rng:NextNumber(0.35, 0.7), s, s * rng:NextNumber(0.8, 1.4))
				or Vector3.new(s * 0.3, s * 0.5, s * rng:NextNumber(1.4, 2.2)) -- long sliver
			p.CFrame = CFrame.new(P)
			p.Parent = fx()
		elseif kind == 1 then
			p = box(Vector3.new(s, s * rng:NextNumber(0.25, 0.4), s * rng:NextNumber(0.7, 1.1)), CFrame.new(P), c, Enum.Material.Concrete) -- slab chunk
		else
			p = box(Vector3.new(s * 0.8, s * rng:NextNumber(0.6, 0.9), s * rng:NextNumber(0.7, 1)), CFrame.new(P), c, Enum.Material.Concrete) -- block
		end
		local v = dir * rng:NextNumber(40, 120) + side * rng:NextNumber(-45, 45) + Vector3.yAxis * rng:NextNumber(10, 60)
		table.insert(movers, { part = p, vel = v, spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)), ground = groundY + p.Size.Y * 0.35, baseGround = groundY })
	end
	for i = 1, (glassy and 24 or 12) do
		local w = Instance.new("WedgePart")
		w.Anchored, w.CanCollide, w.CanQuery = true, false, false
		w.Material = Enum.Material.Glass
		w.Transparency = 0.3
		w.Color = Color3.fromRGB(160, 200, 220)
		w.Size = Vector3.new(0.08, rng:NextNumber(0.4, 1.6), rng:NextNumber(0.4, 1.6))
		w.CFrame = CFrame.new(P + side * rng:NextNumber(-6, 6) + Vector3.yAxis * rng:NextNumber(-3, 4))
		w.Parent = fx()
		local v = dir * rng:NextNumber(30, 100) + side * rng:NextNumber(-50, 50) + Vector3.yAxis * rng:NextNumber(0, 40)
		table.insert(movers, { part = w, vel = v, spin = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-14, 14), 0), ground = groundY + 0.05, baseGround = groundY })
	end
	for i = 1, 9 do -- dust puffs
		local b = box(Vector3.one * rng:NextNumber(4, 7), CFrame.new(P + side * rng:NextNumber(-5, 5) + dir * rng:NextNumber(-3, 6)), Color3.fromRGB(176, 168, 152))
		b.Shape = Enum.PartType.Ball
		b.Transparency = 0.25
		b.CastShadow = false
		table.insert(movers, { part = b, dust = true, age = 0, grow = rng:NextNumber(5, 9), vel = dir * rng:NextNumber(5, 18) + Vector3.yAxis * rng:NextNumber(2, 8) })
	end
end

-- Static "baked" debris placed under the dust (owner spec: about 50 parts): jagged
-- chunks on the hole rim, broken slab and rebar hanging from the ceiling edge, a broken
-- floor lip, and a rubble pile just inside. P is the hole centre on the wall plane.
local function bakeDebris(P: Vector3, dir: Vector3, R: number, floorY: number, ceilY: number, rng: Random)
	local side = dir:Cross(Vector3.yAxis).Unit
	local count = 0
	local function chunk(pos: Vector3, size: Vector3, rot: CFrame, wedge: boolean)
		local p
		if wedge then
			p = Instance.new("WedgePart")
			p.Anchored, p.CanCollide, p.CanQuery = true, false, false
			p.Material = Enum.Material.Concrete
			p.Size = size
			p.CFrame = CFrame.new(pos) * rot
			p.Color = CONCRETE[rng:NextInteger(1, #CONCRETE)]
			p.Parent = fx()
		else
			p = box(size, CFrame.new(pos) * rot, CONCRETE[rng:NextInteger(1, #CONCRETE)], Enum.Material.Concrete)
		end
		count += 1
		return p
	end
	local function randRot(maxDeg: number)
		return CFrame.Angles(math.rad(rng:NextNumber(-maxDeg, maxDeg)), math.rad(rng:NextNumber(-180, 180)), math.rad(rng:NextNumber(-maxDeg, maxDeg)))
	end
	-- 1) jagged rim: 16 pieces around the opening, half inside the wall line
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = R + rng:NextNumber(-0.6, 0.4)
		local pos = P + side * math.cos(a) * r + Vector3.yAxis * math.sin(a) * r + dir * rng:NextNumber(-0.4, 0.6)
		if pos.Y > floorY + 0.3 then
			local s = rng:NextNumber(2, 4.5)
			local shape = i % 3
			local size = shape == 0 and Vector3.new(s * 0.5, s, s * 0.9) or shape == 1 and Vector3.new(s, s * 0.35, s * 0.8) or Vector3.new(s * 0.4, s * 0.6, s * 1.6)
			chunk(pos, size, randRot(60), i % 2 == 0)
		end
	end
	-- 2) ceiling edge: broken slab pieces hanging down + rebar
	for i = 1, 8 do
		local off = rng:NextNumber(-R, R)
		local pos = Vector3.new(P.X, ceilY - rng:NextNumber(0.3, 1.2), P.Z) + side * off + dir * rng:NextNumber(0.5, 3)
		local s = rng:NextNumber(2.5, 5.5)
		chunk(pos, Vector3.new(s, rng:NextNumber(0.8, 1.6), s * rng:NextNumber(0.5, 0.9)), CFrame.Angles(math.rad(rng:NextNumber(20, 65)), math.rad(rng:NextNumber(-30, 30)), 0), i % 3 == 0)
	end
	for i = 1, 8 do
		local off = rng:NextNumber(-R * 0.9, R * 0.9)
		local len = rng:NextNumber(2, 4.5)
		local top = Vector3.new(P.X, ceilY, P.Z) + side * off + dir * rng:NextNumber(0, 2.5)
		local rb = box(Vector3.new(0.18, len, 0.18), CFrame.new(top - Vector3.yAxis * len / 2) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), 0, math.rad(rng:NextNumber(-25, 25))), Color3.fromRGB(92, 70, 58), Enum.Material.CorrodedMetal)
		count += 1
	end
	-- 3) broken floor lip: slab wedges tipped down at the hole bottom
	for i = 1, 6 do
		local off = rng:NextNumber(-R * 0.8, R * 0.8)
		local pos = Vector3.new(P.X, floorY - rng:NextNumber(0.2, 1.0), P.Z) + side * off + dir * rng:NextNumber(-0.5, 1.5)
		local s = rng:NextNumber(2.5, 5)
		chunk(pos, Vector3.new(s, rng:NextNumber(0.8, 1.6), s * 0.8), CFrame.Angles(math.rad(rng:NextNumber(-40, -10)), math.rad(rng:NextNumber(-20, 20)), 0), true)
	end
	-- 4) rubble pile just inside the opening
	for i = 1, 12 do
		local pos = Vector3.new(P.X, floorY, P.Z) + dir * rng:NextNumber(1, 7) + side * rng:NextNumber(-R, R)
		local s = rng:NextNumber(1.2, 4)
		chunk(pos + Vector3.yAxis * s * 0.3, Vector3.new(s, s * rng:NextNumber(0.35, 0.8), s * rng:NextNumber(0.6, 1.2)), randRot(35), i % 2 == 0)
	end
	return count
end
Scene.BakeDebris = bakeDebris

local function stepMovers(dt: number)
	for i = #movers, 1, -1 do
		local m = movers[i]
		if m.dust then
			m.age += dt
			local p = m.part
			p.Size += Vector3.one * m.grow * dt
			p.CFrame += m.vel * dt
			m.vel *= (1 - 1.5 * dt)
			p.Transparency = math.clamp(0.25 + m.age / 2.6, 0, 1)
			if m.age > 2.6 then
				table.remove(movers, i)
			end
		elseif not m.rest then
			m.vel += Vector3.new(0, -G, 0) * dt
			local cf = m.part.CFrame + m.vel * dt
			cf = cf * CFrame.Angles(m.spin.X * dt, m.spin.Y * dt, m.spin.Z * dt)
			local gy = groundFor(cf.Position, m.ground) + (m.ground - (m.baseGround or m.ground))
			if cf.Position.Y <= gy then
				cf = CFrame.new(cf.Position.X, gy, cf.Position.Z) * cf.Rotation
				m.vel = Vector3.new(m.vel.X * 0.35, -m.vel.Y * 0.25, m.vel.Z * 0.35)
				m.spin *= 0.4
				if m.vel.Magnitude < 6 then
					m.rest = true
				end
			end
			m.part.CFrame = cf
		end
	end
end

local function motors(model: Model)
	local t = {}
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") then
			t[m.Name] = { motor = m, c0 = m.C0 }
		end
	end
	return t
end

local function dummy(name: string, cf: CFrame): Model
	local d = game:GetService("ServerStorage").R15Dummy:Clone()
	d.Name = name
	for _, p in d:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = p.Name == "HumanoidRootPart"
			p.CanCollide = false
		end
	end
	local hum = d:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	d.Parent = fx()
	d:PivotTo(cf)
	return d
end

-- Pick a target building and a straight path through its ground floor with open space around.
function Scene.Plan(folder: Instance, flat: boolean, onlyName: string?, onlyDir: Vector3?)
	local slabMin = math.huge
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Slab" then
			slabMin = math.min(slabMin, d.Position.Y - 5.3571 / 2)
		end
	end
	local grade = slabMin
	local sum, n = Vector3.zero, 0
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			sum += m:GetBoundingBox().Position
			n += 1
		end
	end
	local center = sum / math.max(n, 1)
	local qp = OverlapParams.new()
	qp.FilterType = Enum.RaycastFilterType.Include
	qp.FilterDescendantsInstances = { folder }
	local best
	for _, m in folder:GetChildren() do
		if not m:IsA("Model") or (onlyName and m.Name ~= onlyName) then
			continue
		end
		local mcf, msz = m:GetBoundingBox()
		local fl = m:GetAttribute("GeneratedFloors") or 0
		local grade = math.huge
		for _, x in m:GetDescendants() do
			if x:IsA("BasePart") and x.Name == "Slab" then
				grade = math.min(grade, x.Position.Y - 5.3571 / 2)
			end
		end
		if fl >= 2 and fl <= 10 and msz.X > 25 and msz.Z > 25 and grade < math.huge then
			for k = 0, (onlyDir and 0 or 15) do
				local a = k / 16 * math.pi * 2
				local d = onlyDir or Vector3.new(math.cos(a), 0, math.sin(a))
				local h = grade + 9
				local mid = Vector3.new(mcf.X, h, mcf.Z)
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Include
				rp.FilterDescendantsInstances = { m }
				local far = 260
				local entry = workspace:Raycast(mid - d * far, d * far, rp)
				local exit = workspace:Raycast(mid + d * far, -d * far, rp)
				if entry and exit then
					local start = entry.Position - d * 45
					local landing = exit.Position + d * 100
					local clear = true
					-- approach and run-out must be free: rays along the path (and offset for body width)
					local fp = RaycastParams.new()
					fp.FilterType = Enum.RaycastFilterType.Include
					fp.FilterDescendantsInstances = { folder }
					local sideV = d:Cross(Vector3.yAxis).Unit
					for _, o in { -2.5, 0, 2.5 } do
						local off = sideV * o
						local a = workspace:Raycast(start + off, (entry.Position - start) - d * 1, fp)
						if a and not a.Instance:IsDescendantOf(m) then
							clear = false
						end
						if a and a.Instance:IsDescendantOf(m) and (a.Position - entry.Position).Magnitude > 6 then
							clear = false
						end
						local b = workspace:Raycast(exit.Position + d * 1 + off, landing - exit.Position, fp)
						if b then
							clear = false
						end
						for _, hgt in { -2, 3 } do
							local c = workspace:Raycast(start + off + Vector3.new(0, hgt, 0), (entry.Position - start) - d * 1, fp)
							if c and not c.Instance:IsDescendantOf(m) then
								clear = false
							end
						end
					end
					-- no core walls on the path inside
					if clear then
						local cp = RaycastParams.new()
						cp.FilterType = Enum.RaycastFilterType.Include
						local cores = {}
						for _, x in m:GetDescendants() do
							if x:IsA("BasePart") and x.Name:find("^Core") then
								table.insert(cores, x)
							end
						end
						cp.FilterDescendantsInstances = cores
						if workspace:Raycast(entry.Position, exit.Position - entry.Position, cp) then
							clear = false
						end
					end
					if onlyDir then
						clear = true
					end
					if clear then
						local span = (exit.Position - entry.Position).Magnitude
						local score = span + (mcf.Position - center).Magnitude * 0.1
						if not best or score > best.score then
							local ys = {}
							for _, x in m:GetDescendants() do
								if x:IsA("BasePart") and x.Name == "Slab" then
									local k = math.floor(x.Position.Y * 10 + 0.5)
									ys[k] = x.Position.Y
								end
							end
							local list = {}
							for _, y in ys do
								table.insert(list, y)
							end
							table.sort(list)
							local t = 5.3571
							best = { model = m, dir = d, start = start, entry = entry.Position, exit = exit.Position, grade = grade, score = score,
								floorTop = (list[1] or grade) + t / 2, ceil = (list[2] or grade + 17.86) - t / 2 }
						end
					end
				end
			end
		end
	end
	return best
end

-- Mid-air variant: approach at floor `level` (1 = ground floor), enter through the facade
-- and stop inside on that floor before the core.
function Scene.PlanAir(folder: Instance, name: string, dir: Vector3, level: number)
	local m = folder:FindFirstChild(name)
	local t = 5.3571
	local ys = {}
	for _, x in m:GetDescendants() do
		if x:IsA("BasePart") and x.Name == "Slab" then
			ys[math.floor(x.Position.Y * 10 + 0.5)] = x.Position.Y
		end
	end
	local list = {}
	for _, y in ys do
		table.insert(list, y)
	end
	table.sort(list)
	local grade = list[1] - t / 2
	local floorTop = list[level] + t / 2
	local ceil = list[level + 1] - t / 2
	local h = floorTop + 5
	-- aim at the middle of the widest wall that faces the approach and spans this floor
	local wall
	for _, sk in m.FacadeSkins:GetChildren() do
		local top, bottom = sk.Position.Y + sk.Size.Y / 2, sk.Position.Y - sk.Size.Y / 2
		if sk.CFrame.LookVector:Dot(dir) < -0.85 and bottom < h - 6 and top > h + 6 then
			if not wall or sk.Size.X > wall.Size.X then
				wall = sk
			end
		end
	end
	if not wall then
		return nil
	end
	dir = -wall.CFrame.LookVector
	local face = wall.CFrame * CFrame.new(0, h - wall.Position.Y, -wall.Size.Z / 2)
	local entry = { Position = face.Position }
	local cores = {}
	for _, x in m:GetDescendants() do
		if x:IsA("BasePart") and x.Name:find("^Core") then
			table.insert(cores, x)
		end
	end
	local cp = RaycastParams.new()
	cp.FilterType = Enum.RaycastFilterType.Include
	cp.FilterDescendantsInstances = cores
	local coreHit = workspace:Raycast(entry.Position, dir * 300, cp)
	local inside = coreHit and math.min(30, (coreHit.Position - entry.Position).Magnitude - 7) or 30
	return {
		model = m, dir = dir, start = entry.Position - dir * 85, entry = entry.Position, exit = nil,
		grade = grade, floorTop = floorTop, ceil = ceil, height = h, insideStop = inside, air = true,
	}
end

-- CSG carve of structural slabs (floor/ceiling) with a given cutter; originals hidden.
local GeometryService = game:GetService("GeometryService")
local function carveSlabs(model: Model, cutter: BasePart, reach: number)
	local qp = OverlapParams.new()
	qp.FilterType = Enum.RaycastFilterType.Include
	qp.FilterDescendantsInstances = { model }
	for _, p in workspace:GetPartBoundsInRadius(cutter.Position, reach, qp) do
		if p.Name == "Slab" and not state.hidden[p] then
			local ok, res = pcall(function()
				return GeometryService:SubtractAsync(p, { cutter }, { CollisionFidelity = Enum.CollisionFidelity.Box, SplitApart = false })
			end)
			if ok and res and res[1] then
				res[1].Anchored = true
				res[1].Parent = fx()
				hide(p)
			end
		end
	end
	cutter:Destroy()
end

-- Hole through the facade continues into the slab edges above and below.
local function carveHole(model: Model, P: Vector3, dir: Vector3, R: number)
	local c = Instance.new("Part")
	c.Shape = Enum.PartType.Cylinder
	c.Size = Vector3.new(14, R * 2, R * 2)
	c.CFrame = CFrame.lookAt(P, P + dir) * CFrame.Angles(0, math.rad(90), 0)
	carveSlabs(model, c, R + 8)
end

-- Gouge where the body lands and skids, matching HitHandler's ground trench
-- (4 wide, 3 deep, centred 1 below the contact line, CSG on the slab) plus its
-- wedge-lip debris trail along both edges.
function Scene.CarveTrench(model: Model, from: Vector3, to: Vector3, floorY: number)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local dist = flat.Magnitude
	local dirU = dist > 0.1 and flat.Unit or Vector3.xAxis
	local mid = Vector3.new((from.X + to.X) / 2, floorY, (from.Z + to.Z) / 2)
	local len = math.max(dist + 2, 4)
	local c = Instance.new("Part")
	c.Size = Vector3.new(4, 3, len)
	c.CFrame = CFrame.lookAt(mid, mid + dirU) * CFrame.new(0, -1, 0)
	local right = Vector3.yAxis:Cross(dirU).Unit
	local rng = Random.new(17)
	for i = 0, math.max(1, math.floor(dist / 3.5)) do
		local seg = Vector3.new(from.X, floorY, from.Z) + dirU * (i * 3.5)
		for _, sideSign in { -1, 1 } do
			for j = 1, 2 do
				local w = Instance.new("WedgePart")
				w.Anchored, w.CanCollide, w.CanQuery = true, false, false
				w.Material = Enum.Material.Concrete
				w.Color = CONCRETE[rng:NextInteger(1, #CONCRETE)]
				local b = rng:NextNumber(1.45, 2.55)
				w.Size = Vector3.new(b, b * 0.55, b * 1.2)
				local at = seg + right * sideSign * (2 + 1.5 * rng:NextNumber()) + dirU * rng:NextNumber(-1.2, 1.2)
				w.CFrame = CFrame.lookAt(at + Vector3.new(0, w.Size.Y / 2, 0), seg + Vector3.new(0, w.Size.Y / 2, 0))
				w.Parent = fx()
			end
		end
	end
	carveSlabs(model, c, len / 2 + 4)
end

-- Break one wall face of the target at P (world), moving along dir.
local function breakWall(plan, P: Vector3, dir: Vector3, flat: boolean, rng: Random)
	local R = 8
	local qp = OverlapParams.new()
	qp.FilterType = Enum.RaycastFilterType.Include
	qp.FilterDescendantsInstances = { plan.model }
	local near = workspace:GetPartBoundsInRadius(P, R + 10, qp)
	local glassy = false
	for _, p in near do
		if state.hidden[p] then
			continue
		end
		if p.Name:find("Skin") then
			cutSkin(p, P, R)
		elseif not flat and p:FindFirstAncestor("GroundFacadePilot") then
			local d = (p.Position - P).Magnitude
			if p:HasTag("GlassPane") then
				glassy = true
				if d < R + 1 then
					hide(p)
				else
					local ok, Visual = pcall(function()
						return require(game:GetService("ReplicatedStorage").Shared.GlassVisual)
					end)
					if ok then
						local c = p:Clone()
						c.LocalTransparencyModifier = 0
						c.Parent = fx()
						hide(p)
						pcall(Visual.Apply, c, 3)
					end
				end
			else
				-- Thin wall-like parts (thin along local Z) get the same stair-stepped cut;
				-- small detail parts touching the hole are removed.
				local lp = p.CFrame:PointToObjectSpace(P)
				local half = p.Size / 2
				local q = Vector3.new(math.max(math.abs(lp.X) - half.X, 0), math.max(math.abs(lp.Y) - half.Y, 0), math.max(math.abs(lp.Z) - half.Z, 0))
				if q.Magnitude < R then
					if p.Size.Z <= 1.2 and p.Size.X > R and p.Size.Y > 4 then
						cutSkin(p, P, R)
					else
						hide(p)
					end
				end
			end
		end
	end
	spawnBurst(P, dir, plan.air and plan.floorTop or plan.grade, rng, glassy or flat)
	task.spawn(carveHole, plan.model, P, dir, R)
	task.delay(0.45, function()
		if state.fx then
			bakeDebris(P, dir, R, plan.floorTop, plan.ceil, rng)
		end
	end)
end

-- Plays the scene; returns immediately. _G.__SceneDone becomes true at the end.
function Scene.Play(plan, flat: boolean, duration: number?)
	Scene.Reset()
	movers = {}
	wallSplit = nil
	_G.__SceneDone = false
	local rng = Random.new(5)
	local d = plan.dir
	local side = d:Cross(Vector3.yAxis).Unit
	local h = plan.grade + 9
	if plan.air then
		h = plan.height
	end
	local S = Vector3.new(plan.start.X, plan.air and (plan.height - 2.9) or plan.grade, plan.start.Z)
	local victim = dummy("Victim", CFrame.lookAt(S + Vector3.new(0, 2.9, 0), S + Vector3.new(0, 2.9, 0) - d))
	local attacker = dummy("Attacker", CFrame.lookAt(S - d * 5 + Vector3.new(0, 2.9, 0), S + Vector3.new(0, 2.9, 0)))
	local vM, aM = motors(victim), motors(attacker)
	local distEntry = (Vector3.new(plan.entry.X, 0, plan.entry.Z) - Vector3.new(S.X, 0, S.Z)).Magnitude
	local distExit = plan.exit and (Vector3.new(plan.exit.X, 0, plan.exit.Z) - Vector3.new(S.X, 0, S.Z)).Magnitude or math.huge
	local cam = workspace.CurrentCamera
	local t0 = os.clock() + 0.6
	local broke1, broke2, impact = false, false, false
	local v0, decel = (plan.air and 150 or 240), (plan.air and 18 or 55)
	local tLaunch = 1.12
	local vy, onGround, slideV, distNow = 0, false, nil, 0
	local launched, inside, grounded, stopped, vel = false, false, false, false, 0
	local yNow = h
	local landAt = nil
	local roll = 0
	local function clearEye(target: Vector3)
		local rpc = RaycastParams.new()
		rpc.FilterType = Enum.RaycastFilterType.Exclude
		rpc.FilterDescendantsInstances = { fx() }
		for _, cand in { -d * 16 + side * 9 + Vector3.new(0, 6, 0), -d * 16 - side * 9 + Vector3.new(0, 6, 0), side * 18 + Vector3.new(0, 5, 0), -side * 18 + Vector3.new(0, 5, 0), -d * 10 + Vector3.new(0, 14, 0) } do
			local eye = target + cand
			if not workspace:Raycast(target, cand, rpc) and #workspace:GetPartBoundsInRadius(eye, 2) == 0 then
				return eye
			end
		end
		return target - d * 16 + Vector3.new(0, 14, 0)
	end
	local openEye = clearEye(S + Vector3.new(0, 3, 0))
	local camCF = CFrame.lookAt(openEye, S + Vector3.new(0, 3, 0))
	cam.CFrame = camCF
	local last = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 1 / 20)
		last = now
		local t = now - t0
		stepMovers(dt)
		-- attacker punch
		local rs = aM.RightShoulder
		if rs then
			local a = t < 0.75 and 0 or t < 0.95 and (t - 0.75) / 0.2 or t < 1.6 and 1 or math.max(0, 1 - (t - 1.6) * 2)
			rs.motor.C0 = rs.c0 * CFrame.Angles(math.rad(95) * a, 0, 0)
		end
		if t >= 0.95 and not impact then
			impact = true
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "_SceneImpact"
			cc.Saturation = -1
			cc.Contrast = 0.6
			cc.Brightness = 0.15
			cc.Parent = Lighting
			task.delay(0.1, function()
				cc:Destroy()
			end)
			local ring = box(Vector3.new(0.4, 2, 2), CFrame.new(S + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
			ring.Shape = Enum.PartType.Cylinder
			ring.Transparency = 0.2
			table.insert(movers, { part = ring, dust = true, age = 0, grow = 0, vel = Vector3.zero })
			task.spawn(function()
				for i = 1, 24 do
					ring.Size = Vector3.new(0.3, 2 + i * 1.1, 2 + i * 1.1)
					ring.Transparency = 0.2 + i / 30
					task.wait(1 / 60)
				end
				ring:Destroy()
			end)
		end
		-- victim motion (frame integrator: launch, impact, fall to the floor, slide, stop)
		local pos
		if t < tLaunch then
			pos = S + Vector3.new(0, 2.9, 0)
		else
			if not launched then
				launched = true
				vel = v0
			end
			if not inside then
				vel = math.max(0, vel - decel * dt)
			elseif not stopped then
				vel = math.max(0, vel - (grounded and 260 or 120) * dt)
			end
			distNow += vel * dt
			if not broke1 and distNow >= distEntry - 1 then
				broke1 = true
				inside = plan.air == true
				if plan.air then
					wallSplit = { plan.entry, d, plan.floorTop, plan.grade }
				end
				vel *= 0.55
				breakWall(plan, plan.entry, d, flat, rng)
				if plan.air then
					local l1 = Instance.new("PointLight")
					l1.Range, l1.Brightness, l1.Color = 34, 1.6, Color3.fromRGB(255, 244, 228)
					local holder = box(Vector3.one * 0.2, CFrame.new(plan.entry + d * 14 + Vector3.new(0, plan.ceil - plan.height - 1.5, 0)), Color3.new(1, 1, 1))
					holder.Transparency = 1
					l1.Parent = holder
				end
			end
			if plan.exit and not broke2 and distNow >= distExit - 1 then
				broke2 = true
				breakWall(plan, plan.exit, d, flat, rng)
			end
			local floorY = (plan.air and inside) and plan.floorTop or plan.grade
			local airborneOutside = plan.exit and distNow > distExit + 10
			if (plan.air and inside) or airborneOutside then
				if not grounded then
					vy -= G * 0.6 * dt
					yNow += vy * dt
					if yNow <= floorY + 1.2 then
						yNow = floorY + 1.2
						vy = 0
						grounded = true
						if plan.air and inside then
							landAt = Vector3.new(S.X, floorY, S.Z) + d * distNow
						end
					end
				end
			end
			if plan.air and inside and distNow >= distEntry + plan.insideStop then
				distNow = distEntry + plan.insideStop
				vel = 0
			end
			if grounded and vel <= 0 then
				if not stopped and landAt then
					local stopAt = Vector3.new(S.X, floorY, S.Z) + d * distNow
					task.spawn(Scene.CarveTrench, plan.model, landAt, stopAt, floorY)
					spawnBurst(stopAt + Vector3.new(0, 1, 0), -d, floorY, rng, false)
				end
				stopped = true
			end
			pos = Vector3.new(S.X, 0, S.Z) + d * distNow + Vector3.new(0, yNow, 0)
		end
		onGround = grounded
		slideV = stopped and 0 or 1
		-- in-place ragdoll: tumble the body, flail limbs; no interaction with the world
		local airborne = t >= tLaunch and not (onGround and slideV <= 0)
		if airborne then
			roll += (onGround and 4 or 13) * dt
		end
		local flail = airborne and 1 or (t >= tLaunch and 0.25 or 0)
		for name, m in vM do
			local ph = #name
			local amp = name:find("Shoulder") and 1.1 or name:find("Hip") and 0.8 or name:find("Elbow") and 0.9 or name:find("Knee") and 0.9 or 0.15
			m.motor.C0 = m.c0 * CFrame.Angles(math.sin(t * 11 + ph) * amp * flail, 0, math.cos(t * 9 + ph * 2) * amp * 0.6 * flail)
		end
		local face = CFrame.lookAt(pos, pos - d)
		local body
		if t < tLaunch then
			body = face
		elseif onGround and slideV <= 0 then
			body = CFrame.new(pos) * CFrame.lookAt(Vector3.zero, -d).Rotation * CFrame.Angles(math.rad(-90), 0, 0)
		else
			body = face * CFrame.Angles(-roll, 0, math.sin(roll * 0.7) * 0.6)
		end
		victim:PivotTo(body)
		-- camera
		local targetCF
		if t < tLaunch - 0.05 then
			targetCF = CFrame.lookAt(openEye, S + Vector3.new(0, 3, 0))
		else
			local behind = pos - d * 18 + side * 6 + Vector3.new(0, 5, 0)
			if behind.Y < plan.grade + 3 then
				behind = Vector3.new(behind.X, plan.grade + 3, behind.Z)
			end
			targetCF = CFrame.lookAt(behind, pos + d * 14 + Vector3.new(0, 1, 0))
		end
		if plan.air and stopped then
			-- settle outside the hole, looking in at the body
			local eye = plan.entry - d * 34 + side * 9 + Vector3.new(0, 2, 0)
			targetCF = CFrame.lookAt(eye, plan.entry + d * 4)
		end
		local alpha = t < tLaunch and 1 or math.clamp(dt * ((plan.air and stopped) and 4 or 9), 0, 1)
		camCF = camCF:Lerp(targetCF, alpha)
		cam.CFrame = camCF
		local speed = (t >= tLaunch and not onGround) and 1 or 0
		cam.FieldOfView = cam.FieldOfView + ((70 + 12 * speed) - cam.FieldOfView) * math.clamp(dt * 6, 0, 1)
		if t > (duration or 7.5) then
			conn:Disconnect()
			_G.__SceneDone = true
		end
	end)
	return { distEntry = distEntry, distExit = distExit }
end

return Scene
