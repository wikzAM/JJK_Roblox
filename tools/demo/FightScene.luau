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
local wallSplit = nil -- {point, normal(inward), inside floor Y, outside ground Y}
local function groundFor(pos: Vector3, default: number): number
	if wallSplit then
		return (pos - wallSplit[1]):Dot(wallSplit[2]) > 0 and wallSplit[3] or wallSplit[4]
	end
	return default
end
local CONCRETE ={ Color3.fromRGB(196, 184, 160), Color3.fromRGB(150, 150, 152), Color3.fromRGB(128, 126, 122) }

local GLASS_COLOR = Color3.fromRGB(88, 104, 118)
local SLAB_COLOR = Color3.fromRGB(163, 162, 165)

-- Colour of a wall at a world point: sampled from its EditableImage texture (flat
-- skins) or the part colour (composed parts).
local function colorAt(part: BasePart, pos: Vector3): Color3
	local tex = part:FindFirstChildOfClass("Texture")
	local obj = tex and tex.TextureContent and tex.TextureContent.Object
	if obj and obj:IsA("EditableImage") then
		local lp = part.CFrame:PointToObjectSpace(pos)
		local u = part.Size.X / 2 - lp.X + tex.OffsetStudsU
		local v = part.Size.Y / 2 - lp.Y + tex.OffsetStudsV
		local fu = (u % tex.StudsPerTileU) / tex.StudsPerTileU
		local fv = (v % tex.StudsPerTileV) / tex.StudsPerTileV
		local px = math.clamp(math.floor(fu * obj.Size.X), 0, obj.Size.X - 1)
		local py = math.clamp(math.floor(fv * obj.Size.Y), 0, obj.Size.Y - 1)
		local ok, buf = pcall(function()
			return obj:ReadPixelsBuffer(Vector2.new(px, py), Vector2.one)
		end)
		if ok then
			local c = tex.Color3
			return Color3.fromRGB(buffer.readu8(buf, 0) * c.R, buffer.readu8(buf, 1) * c.G, buffer.readu8(buf, 2) * c.B)
		end
	end
	return part.Color
end

local function isGlassColor(c: Color3): boolean
	return math.abs(c.R - GLASS_COLOR.R) + math.abs(c.G - GLASS_COLOR.G) + math.abs(c.B - GLASS_COLOR.B) < 0.12
end

-- Wall colour under a world point, from the wall parts that were cut.
local function wallColor(walls: { BasePart }, pos: Vector3): Color3?
	for _, w in walls do
		local lp = w.CFrame:PointToObjectSpace(pos)
		if math.abs(lp.X) <= w.Size.X / 2 and math.abs(lp.Y) <= w.Size.Y / 2 and math.abs(lp.Z) < 3 then
			return colorAt(w, pos)
		end
	end
	return nil
end

-- HitHandler's dust cloud (same texture and fade curve), amplified and longer lasting.
local function dustCloud(P: Vector3, scale: number, color: Color3, lifetime: number)
	local emitter = box(Vector3.one, CFrame.new(P), Color3.new(1, 1, 1))
	emitter.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxassetid://106896556490763"
	e.Rate = 0
	e.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	e.Speed = NumberRange.new(4 * scale, 12 * scale)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4 * scale), NumberSequenceKeypoint.new(1, 10 * scale) })
	e.Color = ColorSequence.new(color)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(0.9, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Drag = 1.2
	e.Acceleration = Vector3.new(0, 3, 0)
	e.Parent = emitter
	e:Emit(math.floor(400 * scale))
end
Scene.DustCloud = dustCloud

-- Free rectangles of an L x H wall minus cut rectangles {u0,u1,v0,v1}.
local function rectSweep(L: number, H: number, cuts)
	local us = { 0, L }
	for _, c in cuts do
		table.insert(us, math.clamp(c[1], 0, L))
		table.insert(us, math.clamp(c[2], 0, L))
	end
	table.sort(us)
	local uniq = {}
	for _, u in us do
		if #uniq == 0 or u - uniq[#uniq] > 1e-4 then
			table.insert(uniq, u)
		end
	end
	local out = {}
	local prevKey, prevStart, prevFree
	local function emit(ua, ub, free)
		for _, iv in free do
			table.insert(out, { ua, ub, iv[1], iv[2] })
		end
	end
	for k = 1, #uniq - 1 do
		local ua, ub = uniq[k], uniq[k + 1]
		local covered = {}
		for _, c in cuts do
			if c[1] <= ua + 1e-4 and c[2] >= ub - 1e-4 then
				table.insert(covered, { math.max(0, c[3]), math.min(H, c[4]) })
			end
		end
		table.sort(covered, function(a, b)
			return a[1] < b[1]
		end)
		local free, v = {}, 0
		for _, c in covered do
			if c[1] > v + 1e-4 then
				table.insert(free, { v, c[1] })
			end
			v = math.max(v, c[2])
		end
		if v < H - 1e-4 then
			table.insert(free, { v, H })
		end
		local key = ""
		for _, iv in free do
			key ..= string.format("%.3f-%.3f;", iv[1], iv[2])
		end
		if key ~= prevKey then
			if prevKey then
				emit(prevStart, ua, prevFree)
			end
			prevKey, prevStart, prevFree = key, ua, free
		end
	end
	if prevKey then
		emit(prevStart, L, prevFree)
	end
	return out
end

-- Pane rectangles painted into a flat skin's texture (fractions of one tile).
local function paneLayout(tex: Texture)
	local T = _G.__SectorT
	local obj = tex.TextureContent and tex.TextureContent.Object
	local lay = T and obj and T.LayoutOf and T.LayoutOf(obj)
	if not lay then
		return nil
	end
	local out = {}
	for _, pr in lay.panes do
		table.insert(out, { pr[1] / 12, pr[2] / 12, lay.pv0 / 14, lay.pv1 / 14 })
	end
	return out
end

local GlassVisual
local function glassPane(cf: CFrame, w: number, h: number, stateN: number, id: string)
	GlassVisual = GlassVisual or require(game:GetService("ReplicatedStorage").Shared.GlassVisual)
	local g = Instance.new("Part")
	g.Anchored, g.CanCollide, g.CanQuery = true, false, false
	g.Name = "GlassPane"
	g.Material = Enum.Material.SmoothPlastic
	g.Color = Color3.fromRGB(38, 48, 58)
	g.Transparency = 0.45
	g.Reflectance = 0.25
	g.Size = Vector3.new(w, h, 0.25)
	g.CFrame = cf
	g.Parent = fx()
	GlassVisual.Capture(g, id, false)
	GlassVisual.Apply(g, stateN)
	g.Material = Enum.Material.SmoothPlastic -- Apply sets Glass; keep plastic (no hide-behind-glass)
	return g
end

-- Ring widths around the structural hole: shattered panes, then cracked panes.
local SHATTER_RING, CRACK_RING = 7, 18

-- Flat skin: cut the stair-stepped hole plus the glass rings (gone / shattered /
-- cracked panes become openings holding real panes from the original glass system).
local function cutSkinWithGlass(skin: BasePart, P: Vector3, R: number): boolean
	local L, H = skin.Size.X, skin.Size.Y
	local lp = skin.CFrame:PointToObjectSpace(P)
	if math.abs(lp.Z) >= R then
		return false
	end
	local r = math.sqrt(R * R - lp.Z * lp.Z)
	local cu, cv = L / 2 - lp.X, H / 2 - lp.Y
	if cu + r < 0 or cu - r > L or cv + r < 0 or cv - r > H then
		return false
	end
	local cuts = {}
	local v = math.max(0, cv - r)
	while v < math.min(H, cv + r) - 1e-6 do
		local vb = math.min(v + 1.5, H, cv + r)
		local half = math.sqrt(math.max(0, r * r - ((v + vb) / 2 - cv) ^ 2))
		half = math.floor(half / 1.5 + 0.5) * 1.5
		if half > 0 then
			table.insert(cuts, { cu - half, cu + half, v, vb })
		end
		v = vb
	end
	local tex = skin:FindFirstChildOfClass("Texture")
	local panes = {}
	local layout = tex and paneLayout(tex)
	if layout then
		local tu, tv = tex.StudsPerTileU, tex.StudsPerTileV
		local reach = r + CRACK_RING
		for i = math.floor((cu - reach + tex.OffsetStudsU) / tu) - 1, math.floor((cu + reach + tex.OffsetStudsU) / tu) + 1 do
			for j = math.floor((cv - reach + tex.OffsetStudsV) / tv) - 1, math.floor((cv + reach + tex.OffsetStudsV) / tv) + 1 do
				for _, pr in layout do
					local u0 = i * tu + pr[1] * tu - tex.OffsetStudsU
					local u1 = i * tu + pr[2] * tu - tex.OffsetStudsU
					local v0 = j * tv + pr[3] * tv - tex.OffsetStudsV
					local v1 = j * tv + pr[4] * tv - tex.OffsetStudsV
					if u0 >= 0 and u1 <= L and v0 >= 0 and v1 <= H then
						local du = math.max(u0 - cu, 0, cu - u1)
						local dv = math.max(v0 - cv, 0, cv - v1)
						local dist = math.sqrt(du * du + dv * dv)
						local stateN = dist < r and 4 or dist < r + SHATTER_RING and 3 or dist < r + CRACK_RING and 2 or nil
						if stateN then
							table.insert(cuts, { u0, u1, v0, v1 })
							table.insert(panes, { u0, u1, v0, v1, stateN })
						end
					end
				end
			end
		end
	end
	for _, rct in rectSweep(L, H, cuts) do
		local u0, u1, v0, v1 = rct[1], rct[2], rct[3], rct[4]
		if u1 - u0 > 0.05 and v1 - v0 > 0.05 then
			local pc = skin:Clone()
			for _, c in pc:GetChildren() do
				if not c:IsA("Texture") then
					c:Destroy()
				end
			end
			pc.Size = Vector3.new(u1 - u0, v1 - v0, skin.Size.Z)
			pc.CFrame = skin.CFrame * CFrame.new(L / 2 - (u0 + u1) / 2, H / 2 - (v0 + v1) / 2, 0)
			pc.Transparency = skin.Transparency
			for _, t in pc:GetChildren() do
				if t:IsA("Texture") then
					local src = skin:FindFirstChild(t.Name)
					local baseU = src and src.OffsetStudsU or 0
					local baseV = src and src.OffsetStudsV or 0
					-- the back face runs the other way along the wall
					t.OffsetStudsU = baseU + (t.Face == Enum.NormalId.Back and (L - u1) or u0)
					t.OffsetStudsV = baseV + v0
				end
			end
			pc.Parent = fx()
		end
	end
	-- Panes partly inside the stair-stepped hole are gone; others get real glass.
	for k, pn in panes do
		if pn[5] ~= 4 then
			local cf = skin.CFrame * CFrame.new(L / 2 - (pn[1] + pn[2]) / 2, H / 2 - (pn[3] + pn[4]) / 2, 0)
			glassPane(cf, pn[2] - pn[1], pn[4] - pn[3], pn[5], skin.Name .. k)
		end
	end
	hide(skin)
	return true
end


local function spawnBurst(P: Vector3, dir: Vector3, groundY: number, rng: Random, glassy: boolean, walls: { BasePart }?)
	local side = dir:Cross(Vector3.yAxis).Unit
	local function sampled(): Color3
		if walls and #walls > 0 then
			for _ = 1, 8 do
				local a = rng:NextNumber(0, math.pi * 2)
				local c = wallColor(walls, P + side * math.cos(a) * 9 + Vector3.yAxis * math.sin(a) * 9)
				if c and not isGlassColor(c) then
					return c
				end
			end
		end
		return CONCRETE[rng:NextInteger(1, #CONCRETE)]
	end
	for i = 1, 20 do
		local s = rng:NextNumber(2, 6.5)
		local c = i % 3 == 0 and SLAB_COLOR or sampled()
		local p
		if i % 4 ~= 0 then -- mostly wedges
			p = Instance.new("WedgePart")
			p.Anchored, p.CanCollide, p.CanQuery = true, false, false
			p.Material = Enum.Material.Concrete
			p.Color = c
			local kind = i % 3
			p.Size = kind == 0 and Vector3.new(s * rng:NextNumber(0.3, 0.6), s, s * rng:NextNumber(0.9, 1.5))
				or kind == 1 and Vector3.new(s * 0.35, s * 0.45, s * rng:NextNumber(1.5, 2.4))
				or Vector3.new(s * rng:NextNumber(0.5, 0.8), s * 0.7, s)
			p.CFrame = CFrame.new(P)
			p.Parent = fx()
		else
			p = box(Vector3.new(s, s * rng:NextNumber(0.25, 0.45), s * rng:NextNumber(0.7, 1.1)), CFrame.new(P), c, Enum.Material.Concrete)
		end
		local v = dir * rng:NextNumber(40, 120) + side * rng:NextNumber(-45, 45) + Vector3.yAxis * rng:NextNumber(10, 60)
		table.insert(movers, { part = p, vel = v, spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6)), ground = groundY + p.Size.Y * 0.35, baseGround = groundY })
	end
	for i = 1, (glassy and 28 or 14) do
		local w = Instance.new("WedgePart")
		w.Anchored, w.CanCollide, w.CanQuery = true, false, false
		w.Material = Enum.Material.Glass
		w.Transparency = 0.3
		w.Color = Color3.fromRGB(160, 200, 220)
		w.Size = Vector3.new(0.08, rng:NextNumber(0.5, 2), rng:NextNumber(0.5, 2))
		w.CFrame = CFrame.new(P + side * rng:NextNumber(-8, 8) + Vector3.yAxis * rng:NextNumber(-4, 5))
		w.Parent = fx()
		local v = dir * rng:NextNumber(30, 100) + side * rng:NextNumber(-50, 50) + Vector3.yAxis * rng:NextNumber(0, 40)
		table.insert(movers, { part = w, vel = v, spin = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-14, 14), 0), ground = groundY + 0.05, baseGround = groundY })
	end
	-- amplified, long-lasting HitHandler dust tinted toward the wall colour
	local dustCol = sampled():Lerp(Color3.fromRGB(150, 145, 138), 0.5)
	dustCloud(P, 2.6, dustCol, 3.2)
	dustCloud(P + dir * 6, 1.8, dustCol, 2.6)
end

-- Static "baked" debris placed under the dust (about 50 parts):
--  rim: pieces lying in the wall plane (barely proud of it), coloured from the wall
--  ceiling edge: broken slab pieces and rebar hanging down
--  floor lip: slab wedges tipped down at the hole bottom
--  rubble pile just inside
local function bakeDebris(P: Vector3, dir: Vector3, R: number, floorY: number, ceilY: number, rng: Random, walls: { BasePart }?)
	local side = dir:Cross(Vector3.yAxis).Unit
	local function wedgeOrBox(wedge: boolean, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?)
		if wedge then
			local w = Instance.new("WedgePart")
			w.Anchored, w.CanCollide, w.CanQuery = true, false, false
			w.Material = mat or Enum.Material.Concrete
			w.Size = size
			w.CFrame = cf
			w.Color = color
			w.Parent = fx()
			return w
		end
		return box(size, cf, color, mat or Enum.Material.Concrete)
	end
	-- 1) rim, flush with the facade: thickness along the wall normal, rotated only in-plane
	for i = 1, 18 do
		local a = (i / 18) * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
		local r = R + rng:NextNumber(-0.8, 0.6)
		local pos = P + side * math.cos(a) * r + Vector3.yAxis * math.sin(a) * r
		if pos.Y > floorY + 0.3 then
			local col = walls and wallColor(walls, pos) or nil
			local glassy = col and isGlassColor(col)
			local inPlane = CFrame.fromAxisAngle(dir, rng:NextNumber(-math.pi, math.pi))
			local u, v = inPlane:VectorToWorldSpace(side), inPlane:VectorToWorldSpace(Vector3.yAxis)
			local s = rng:NextNumber(2.2, 4.8)
			local thick = glassy and 0.15 or rng:NextNumber(0.5, 1.1)
			local depth = rng:NextNumber(-0.25, 0.2) -- never more than a fraction of a stud proud
			local centre = pos + dir * (thick / 2 + depth)
			if i % 2 == 0 then
				-- wedge: local X = thickness (along the wall normal), triangle lies in the wall plane
				local cf = CFrame.fromMatrix(centre, dir, v, dir:Cross(v))
				wedgeOrBox(true, Vector3.new(thick, s * rng:NextNumber(0.5, 0.9), s), cf, glassy and Color3.fromRGB(160, 200, 220) or col or CONCRETE[1], glassy and Enum.Material.Glass or nil)
			else
				local cf = CFrame.fromMatrix(centre, u, v, u:Cross(v))
				wedgeOrBox(false, Vector3.new(s, s * rng:NextNumber(0.35, 0.7), thick), cf, glassy and Color3.fromRGB(160, 200, 220) or col or CONCRETE[1], glassy and Enum.Material.Glass or nil)
			end
		end
	end
	-- 2) ceiling edge: broken slab pieces hanging down + rebar
	for i = 1, 8 do
		local off = rng:NextNumber(-R, R)
		local pos = Vector3.new(P.X, ceilY - rng:NextNumber(0.4, 1.4), P.Z) + side * off + dir * rng:NextNumber(0.5, 3.5)
		local s = rng:NextNumber(3, 6.5)
		wedgeOrBox(i % 3 ~= 0, Vector3.new(rng:NextNumber(0.9, 1.6), s * rng:NextNumber(0.5, 0.9), s), CFrame.new(pos) * CFrame.Angles(math.rad(rng:NextNumber(25, 70)), math.rad(rng:NextNumber(-35, 35)), math.rad(rng:NextNumber(-15, 15))), SLAB_COLOR)
	end
	for i = 1, 8 do
		local off = rng:NextNumber(-R * 0.9, R * 0.9)
		local len = rng:NextNumber(2.5, 5.5)
		local top = Vector3.new(P.X, ceilY, P.Z) + side * off + dir * rng:NextNumber(3, 7)
		box(Vector3.new(0.2, len, 0.2), CFrame.new(top - Vector3.yAxis * len / 2) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), 0, math.rad(rng:NextNumber(-25, 25))), Color3.fromRGB(92, 70, 58), Enum.Material.CorrodedMetal)
	end
	-- 3) broken floor lip: slab wedges tipped down at the hole bottom
	for i = 1, 6 do
		local off = rng:NextNumber(-R * 0.8, R * 0.8)
		local pos = Vector3.new(P.X, floorY - rng:NextNumber(0.3, 1.2), P.Z) + side * off + dir * rng:NextNumber(-0.5, 1.5)
		local s = rng:NextNumber(3, 6)
		wedgeOrBox(true, Vector3.new(rng:NextNumber(0.9, 1.6), s * 0.6, s), CFrame.new(pos) * CFrame.Angles(math.rad(rng:NextNumber(-45, -15)), math.rad(rng:NextNumber(-25, 25)), 0), SLAB_COLOR)
	end
	-- 4) rubble pile just inside the opening (mixed slab and facade colours)
	for i = 1, 12 do
		local pos = Vector3.new(P.X, floorY, P.Z) + dir * rng:NextNumber(1, 8) + side * rng:NextNumber(-R, R)
		local s = rng:NextNumber(1.6, 4.8)
		local col = (i % 3 == 0 and walls) and (wallColor(walls, P + side * rng:NextNumber(-R, R)) or SLAB_COLOR) or SLAB_COLOR
		if isGlassColor(col) then
			col = SLAB_COLOR
		end
		wedgeOrBox(i % 3 ~= 1, Vector3.new(s, s * rng:NextNumber(0.35, 0.8), s * rng:NextNumber(0.6, 1.3)), CFrame.new(pos + Vector3.yAxis * s * 0.25) * CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), math.rad(rng:NextNumber(-180, 180)), math.rad(rng:NextNumber(-30, 30))), col)
	end
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

-- Steep variant: enter through the facade at floor `entryLevel`, dive down through
-- `drop` floor slabs (each carved), land on the floor below them, slide and stop.
function Scene.PlanDive(folder: Instance, name: string, dir: Vector3, entryLevel: number, drop: number)
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
	local landLevel = entryLevel - drop
	local h = list[entryLevel] + t / 2 + 6
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
	local E = (wall.CFrame * CFrame.new(0, h - wall.Position.Y, -wall.Size.Z / 2)).Position
	local landY = list[landLevel] + t / 2 + 1.2
	local horiz = 40
	local L = Vector3.new(E.X, landY, E.Z) + dir * horiz
	local u = (L - E).Unit
	local crossings = {}
	for k = entryLevel, landLevel + 1, -1 do
		local s = (E.Y - list[k]) / -u.Y
		table.insert(crossings, { dist = s, point = E + u * s, floorBelow = list[k - 1] + t / 2, ceilBelow = list[k] - t / 2 })
	end
	return {
		model = m, dir = dir, u = u, entry = E, landPoint = L, start = E - u * 75, exit = nil,
		grade = grade, floorTop = list[landLevel] + t / 2, ceil = list[entryLevel + 1] - t / 2,
		entryFloorTop = list[entryLevel] + t / 2, height = h, crossings = crossings, dive = true, air = true,
		insideStop = horiz + 7,
	}
end

-- Hole punched down through a floor slab: CSG cylinder, burst falling to the floor
-- below, and baked debris hanging from the hole rim (slab shards + rebar, inside only).
local function slabHole(plan, c, u: Vector3, rng: Random)
	local R = 9
	local cut = Instance.new("Part")
	cut.Shape = Enum.PartType.Cylinder
	cut.Size = Vector3.new(14, R * 2, R * 2)
	cut.CFrame = CFrame.new(c.point) * CFrame.Angles(0, 0, math.rad(90))
	task.spawn(carveSlabs, plan.model, cut, R + 8)
	spawnBurst(c.point, (u + Vector3.new(0, -0.3, 0)).Unit, c.floorBelow, rng, false, nil)
	task.delay(0.45, function()
		if not state.fx then
			return
		end
		for i = 1, 14 do
			local a = (i / 14) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
			local r = R + rng:NextNumber(-0.6, 0.5)
			local pos = c.point + Vector3.new(math.cos(a) * r, -rng:NextNumber(3.2, 4.6), math.sin(a) * r)
			local s = rng:NextNumber(2.2, 4.8)
			local w = Instance.new("WedgePart")
			w.Anchored, w.CanCollide, w.CanQuery = true, false, false
			w.Material = Enum.Material.Concrete
			w.Color = SLAB_COLOR
			w.Size = Vector3.new(rng:NextNumber(0.8, 1.5), s * 0.6, s)
			-- tipped down into the hole, pointing at its centre
			w.CFrame = CFrame.lookAt(pos, Vector3.new(c.point.X, pos.Y - 3, c.point.Z)) * CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), 0, math.rad(rng:NextNumber(-15, 15)))
			w.Parent = fx()
		end
		for i = 1, 7 do
			local a = rng:NextNumber(0, math.pi * 2)
			local top = c.point + Vector3.new(math.cos(a) * (R - 0.3), -2.6, math.sin(a) * (R - 0.3))
			local len = rng:NextNumber(2.5, 5)
			box(Vector3.new(0.2, len, 0.2), CFrame.new(top - Vector3.yAxis * len / 2) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), 0, math.rad(rng:NextNumber(-25, 25))), Color3.fromRGB(92, 70, 58), Enum.Material.CorrodedMetal)
		end
		for i = 1, 8 do
			local pos = Vector3.new(c.point.X, c.floorBelow, c.point.Z) + Vector3.new(rng:NextNumber(-R, R), 0, rng:NextNumber(-R, R))
			local s = rng:NextNumber(1.5, 4)
			local w = Instance.new("WedgePart")
			w.Anchored, w.CanCollide, w.CanQuery = true, false, false
			w.Material = Enum.Material.Concrete
			w.Color = SLAB_COLOR
			w.Size = Vector3.new(s, s * rng:NextNumber(0.35, 0.7), s * rng:NextNumber(0.6, 1.2))
			w.CFrame = CFrame.new(pos + Vector3.yAxis * s * 0.25) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(-180, 180)), 0)
			w.Parent = fx()
		end
	end)
	dustCloud(c.point, 2.0, Color3.fromRGB(160, 158, 154), 3)
end

-- Break one wall face of the target at P (world), moving along dir.
local function breakWall(plan, P: Vector3, dir: Vector3, flat: boolean, rng: Random)
	local R = 8
	local qp = OverlapParams.new()
	qp.FilterType = Enum.RaycastFilterType.Include
	qp.FilterDescendantsInstances = { plan.model }
	local near = workspace:GetPartBoundsInRadius(P, R + CRACK_RING + 6, qp)
	local glassy = false
	local walls = {}
	GlassVisual = GlassVisual or require(game:GetService("ReplicatedStorage").Shared.GlassVisual)
	for _, p in near do
		if state.hidden[p] then
			continue
		end
		local lp = p.CFrame:PointToObjectSpace(P)
		local half = p.Size / 2
		local q = Vector3.new(math.max(math.abs(lp.X) - half.X, 0), math.max(math.abs(lp.Y) - half.Y, 0), math.max(math.abs(lp.Z) - half.Z, 0))
		local dist = q.Magnitude
		if p.Name:find("Skin") then
			table.insert(walls, p)
			if cutSkinWithGlass(p, P, R) then
				glassy = true
			end
		elseif p:HasTag("GlassPane") then
			-- composed facades and ground facades: same ring rules as the flat skins
			glassy = true
			if dist < R then
				hide(p)
			elseif dist < R + SHATTER_RING or dist < R + CRACK_RING then
				local c = p:Clone()
				c.Transparency = p.Transparency
				c.Parent = fx()
				hide(p)
				for key in c:GetAttributes() do
					if key:sub(1, 5) == "Glass" then
						c:SetAttribute(key, nil)
					end
				end
				pcall(GlassVisual.Capture, c, p.Name .. tostring(p.Position), false)
				pcall(GlassVisual.Apply, c, dist < R + SHATTER_RING and 3 or 2)
				c.Material = Enum.Material.SmoothPlastic
			end
		elseif p:FindFirstAncestor("GroundFacadePilot") or p:FindFirstAncestor("FacadeParts") then
			if dist < R then
				table.insert(walls, p)
				if p.Size.Z <= 1.2 and p.Size.X > R and p.Size.Y > 4 then
					cutSkin(p, P, R)
				else
					hide(p)
				end
			end
		end
	end
	spawnBurst(P, dir, plan.air and plan.floorTop or plan.grade, rng, glassy or flat, walls)
	task.spawn(carveHole, plan.model, P, dir, R)
	task.delay(0.45, function()
		if state.fx then
			bakeDebris(P, dir, R, plan.floorTop, plan.ceil, rng, walls)
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
	local S = plan.dive and (plan.start - Vector3.new(0, 2.9, 0)) or Vector3.new(plan.start.X, plan.air and (plan.height - 2.9) or plan.grade, plan.start.Z)
	local victim = dummy("Victim", CFrame.lookAt(S + Vector3.new(0, 2.9, 0), S + Vector3.new(0, 2.9, 0) - d))
	local back = plan.dive and plan.u or d
	local attacker = dummy("Attacker", CFrame.lookAt(S - back * 5 + Vector3.new(0, 2.9, 0), S + Vector3.new(0, 2.9, 0)))
	local vM, aM = motors(victim), motors(attacker)
	local distEntry = (Vector3.new(plan.entry.X, 0, plan.entry.Z) - Vector3.new(S.X, 0, S.Z)).Magnitude
	local distExit = plan.exit and (Vector3.new(plan.exit.X, 0, plan.exit.Z) - Vector3.new(S.X, 0, S.Z)).Magnitude or math.huge
	local cam = workspace.CurrentCamera
	local t0 = os.clock() + 0.6
	local broke1, broke2, impact = false, false, false
	local v0, decel = (plan.air and 150 or 240), (plan.air and 18 or 55)
	local tLaunch = 1.12
	local vy, distNow = 0, 0
	local launched, inside, grounded, stopped, vel = false, false, false, false, 0
	local yNow = h
	local landAt = nil
	local diveDist, nextCross, slideLeft, slid = 0, 1, 0, 0
	local arrivedT = nil
	local roll = 0
	local stopT = nil
	-- walk-around ending (dummy POV): get up, walk back toward the hole, look around
	local standPos, walkTarget, facing = nil, nil, -d
	local function clearEye(target: Vector3)
		local rpc = RaycastParams.new()
		rpc.FilterType = Enum.RaycastFilterType.Exclude
		rpc.FilterDescendantsInstances = { fx() }
		for _, cand in { -d * 16 + side * 9 + Vector3.new(0, 6, 0), -d * 16 - side * 9 + Vector3.new(0, 6, 0), side * 18 + Vector3.new(0, 5, 0), -side * 18 + Vector3.new(0, 5, 0), -d * 22 + Vector3.new(0, 10, 0), -d * 14 + Vector3.new(0, 30, 0) } do
			local eye = target + cand
			local openSky = not workspace:Raycast(eye, Vector3.new(0, 400, 0), rpc)
			if openSky and not workspace:Raycast(target, cand, rpc) and #workspace:GetPartBoundsInRadius(eye, 2) == 0 then
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
		end
		-- victim motion (frame integrator: launch, impact, fall to the floor, slide, stop)
		local pos
		if t < tLaunch then
			pos = S + Vector3.new(0, 2.9, 0)
		elseif plan.dive and not stopped then
			-- straight 3D dive: facade, then each slab, then land and slide along d
			if not launched then
				launched = true
				vel = v0
				diveDist = 0
				nextCross = 1
			end
			local u = plan.u
			local entryD = (plan.entry - plan.start).Magnitude
			local landD = (plan.landPoint - plan.start).Magnitude
			if not grounded then
				vel = math.max(60, vel - (inside and 60 or 10) * dt)
				diveDist += vel * dt
				if not broke1 and diveDist >= entryD - 1 then
					broke1 = true
					inside = true
					wallSplit = { plan.entry, d, plan.floorTop, plan.grade }
					vel *= 0.7
					breakWall(plan, plan.entry, d, flat, rng)
					local l1 = Instance.new("PointLight")
					l1.Range, l1.Brightness, l1.Color = 45, 1.8, Color3.fromRGB(255, 244, 228)
					local holder = box(Vector3.one * 0.2, CFrame.new(plan.landPoint + Vector3.new(0, 9, 0) - d * 6), Color3.new(1, 1, 1))
					holder.Transparency = 1
					l1.Parent = holder
				end
				while plan.crossings[nextCross] and diveDist >= entryD + plan.crossings[nextCross].dist do
					slabHole(plan, plan.crossings[nextCross], u, rng)
					vel *= 0.8
					nextCross += 1
				end
				if diveDist >= landD then
					diveDist = landD
					grounded = true
					landAt = Vector3.new(plan.landPoint.X, plan.floorTop, plan.landPoint.Z)
					dustCloud(landAt + Vector3.yAxis, 1.8, Color3.fromRGB(150, 148, 145), 2.6)
					slideLeft = plan.insideStop - 40
				end
				pos = plan.start + u * diveDist
			else
				local slide = math.min(slideLeft, 0) -- placeholder to keep types simple
				local step = math.min(slideLeft, math.max(vel, 20) * dt * 0.5)
				slideLeft -= step
				slid += step
				vel = math.max(0, vel - 200 * dt)
				pos = plan.landPoint + d * slid
				if slideLeft <= 0.01 or vel <= 0 then
					local stopAt = Vector3.new(pos.X, plan.floorTop, pos.Z)
					task.spawn(Scene.CarveTrench, plan.model, landAt, stopAt, plan.floorTop)
					stopped = true
					stopT = t
					standPos = stopAt + Vector3.new(0, 2.9, 0)
					-- walk back under the holes so the camera can look up through them
					local c1 = plan.crossings[#plan.crossings]
					walkTarget = Vector3.new(c1.point.X, standPos.Y, c1.point.Z) + d * 4.5 + side * 1.5 -- hole just ahead, overhead
				end
			end
		elseif not stopped then
			if not launched then
				launched = true
				vel = v0
			end
			if not inside then
				vel = math.max(0, vel - decel * dt)
			else
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
					l1.Range, l1.Brightness, l1.Color = 40, 1.8, Color3.fromRGB(255, 244, 228)
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
			if (plan.air and inside) or (plan.exit and distNow > distExit + 10) then
				if not grounded then
					vy -= G * 0.6 * dt
					yNow += vy * dt
					if yNow <= floorY + 1.2 then
						yNow = floorY + 1.2
						vy = 0
						grounded = true
						landAt = Vector3.new(S.X, floorY, S.Z) + d * distNow
						dustCloud(landAt + Vector3.yAxis, 1.6, Color3.fromRGB(150, 148, 145), 2.6)
					end
				end
			end
			if plan.air and inside and distNow >= distEntry + plan.insideStop then
				distNow = distEntry + plan.insideStop
				vel = 0
			end
			if grounded and vel <= 0 then
				local stopAt = Vector3.new(S.X, floorY, S.Z) + d * distNow
				if landAt then
					task.spawn(Scene.CarveTrench, plan.model, landAt, stopAt, floorY)
				end
				stopped = true
				stopT = t
				standPos = stopAt + Vector3.new(0, 2.9, 0)
				walkTarget = Vector3.new(plan.entry.X, standPos.Y, plan.entry.Z) + d * 7 + side * 2.5
			end
			pos = Vector3.new(S.X, 0, S.Z) + d * distNow + Vector3.new(0, yNow, 0)
		end
		-- body pose: tumble in flight; lie still; then get up and walk
		local body
		local phase = "fly"
		if t < tLaunch then
			phase = "idle"
		elseif stopped then
			local since = t - stopT
			phase = since < 0.9 and "lie" or since < 1.5 and "getup" or "walk"
		end
		if phase == "idle" then
			body = CFrame.lookAt(pos, pos - d)
		elseif phase == "fly" then
			roll += (grounded and 4 or 13) * dt
			body = CFrame.lookAt(pos, pos - d) * CFrame.Angles(-roll, 0, math.sin(roll * 0.7) * 0.6)
		else
			local lying = CFrame.new(Vector3.new(standPos.X, standPos.Y - 1.7, standPos.Z)) * CFrame.lookAt(Vector3.zero, -d).Rotation * CFrame.Angles(math.rad(-90), 0, 0)
			local upright = CFrame.lookAt(standPos, standPos + facing)
			if phase == "lie" then
				body = lying
			elseif phase == "getup" then
				local k = (t - stopT - 0.9) / 0.6
				body = lying:Lerp(upright, k * k * (3 - 2 * k))
			else
				-- walk toward the hole, then stop and look around at the damage
				local toT = Vector3.new(walkTarget.X - standPos.X, 0, walkTarget.Z - standPos.Z)
				local walking = toT.Magnitude > 0.4
				if walking then
					local stepLen = math.min(toT.Magnitude, 7 * dt)
					standPos += toT.Unit * stepLen
					facing = facing:Lerp(toT.Unit, math.clamp(dt * 5, 0, 1)).Unit
				else
					local look = math.sin((t - stopT - 1.5) * 0.9) * 0.55
					facing = (CFrame.fromAxisAngle(Vector3.yAxis, look) * -d)
				end
				body = CFrame.lookAt(standPos, standPos + facing)
			end
		end
		victim:PivotTo(body)
		-- limbs: flail in flight, slack while lying, walk cycle when walking
		local walkingNow = phase == "walk" and (Vector3.new(walkTarget.X - standPos.X, 0, walkTarget.Z - standPos.Z).Magnitude > 0.4)
		for name, m in vM do
			local ph = #name
			if phase == "fly" then
				local amp = name:find("Shoulder") and 1.1 or name:find("Hip") and 0.8 or name:find("Elbow") and 0.9 or name:find("Knee") and 0.9 or 0.15
				m.motor.C0 = m.c0 * CFrame.Angles(math.sin(t * 11 + ph) * amp, 0, math.cos(t * 9 + ph * 2) * amp * 0.6)
			elseif walkingNow and (name:find("Hip") or name:find("Shoulder")) then
				local sgn = (name:find("Left") and 1 or -1) * (name:find("Shoulder") and -0.6 or 1)
				m.motor.C0 = m.c0 * CFrame.Angles(math.sin(t * 9) * 0.55 * sgn, 0, 0)
			else
				m.motor.C0 = m.c0
			end
		end
		-- camera: opening shot, chase in flight, over-the-shoulder POV once standing
		local targetCF
		local alpha = math.clamp(dt * 9, 0, 1)
		if phase == "idle" or not standPos and phase ~= "fly" then
			targetCF = CFrame.lookAt(openEye, S + Vector3.new(0, 3, 0))
			alpha = 1
		elseif plan.dive and broke1 and phase ~= "walk" then
			-- wait on the landing floor and watch the body come down through the ceiling
			local eye = plan.landPoint + d * 18 + side * 10 + Vector3.new(0, 3.5, 0)
			targetCF = CFrame.lookAt(eye, plan.landPoint + Vector3.new(0, 6, 0))
			alpha = math.clamp(dt * 7, 0, 1)
		elseif phase == "fly" or phase == "lie" or phase == "getup" then
			local p0 = phase == "fly" and pos or standPos
			local behind = p0 - back * 18 + side * 6 + Vector3.new(0, 5, 0)
			if stopped then
				behind = standPos + d * 9 + side * 3 + Vector3.new(0, 4, 0) -- look back at the body from deeper inside
			end
			targetCF = CFrame.lookAt(behind, (stopped and standPos or p0 + back * 14) + Vector3.new(0, 0.5, 0))
			alpha = math.clamp(dt * (stopped and 3 or 9), 0, 1)
		else
			local right = facing:Cross(Vector3.yAxis).Unit
			local eye = standPos - facing * 9 + Vector3.new(0, 3.4, 0) + right * 3.6
			local lookUp = 0.8
			if plan.dive and (Vector3.new(walkTarget.X - standPos.X, 0, walkTarget.Z - standPos.Z).Magnitude <= 0.4) then
				arrivedT = arrivedT or t
				lookUp = 0.8 + math.clamp((t - arrivedT) * 12, 0, 26) -- tilt up to the ceiling holes
			end
			targetCF = CFrame.lookAt(eye, standPos + facing * 14 + Vector3.new(0, lookUp, 0))
			alpha = math.clamp(dt * 4, 0, 1)
		end
		camCF = camCF:Lerp(targetCF, alpha)
		cam.CFrame = camCF
		local speed = (phase == "fly" and not grounded) and 1 or 0
		cam.FieldOfView = cam.FieldOfView + ((70 + 12 * speed) - cam.FieldOfView) * math.clamp(dt * 6, 0, 1)
		if t > (duration or 7.5) then
			conn:Disconnect()
			_G.__SceneDone = true
		end
	end)
	return { distEntry = distEntry, distExit = distExit }
end

return Scene
