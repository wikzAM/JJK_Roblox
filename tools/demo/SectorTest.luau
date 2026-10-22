-- Edit-time test (temporary ModuleScript via MCP). Copies a sector of real buildings
-- twice, off-map, so the two facade approaches can be compared on identical geometry:
--   Parts version: reduced slabs + flat upper-floor skins + today's GroundFacadePilot.
--   Flat version:  reduced slabs + flat upper-floor skins + flat ground-floor skins.
-- Skin textures are EditableImages (session-only), tinted per building.
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local T = {}

local PPS = 8
local GLASS = { 88, 104, 118 } -- flat glass colour (owner: no streaks or gradients)
local function newImage(w, h, painter)
	local iw, ih = w * PPS, h * PPS
	local img = AssetService:CreateEditableImage({ Size = Vector2.new(iw, ih) })
	local buf = buffer.create(iw * ih * 4)
	local function set(x, y, r, g, b, a)
		local i = (y * iw + x) * 4
		buffer.writeu8(buf, i, math.clamp(r, 0, 255))
		buffer.writeu8(buf, i + 1, math.clamp(g, 0, 255))
		buffer.writeu8(buf, i + 2, math.clamp(b, 0, 255))
		buffer.writeu8(buf, i + 3, a or 255)
	end
	painter(iw, ih, set)
	img:WritePixelsBuffer(Vector2.zero, img.Size, buf)
	return img
end

-- Ground floor shopfront, one tile = 24 x 18 studs (stretched to the real floor height).
local shopfront
function T.Shopfront()
	shopfront = shopfront
		or newImage(24, 18, function(iw, ih, set)
			local rng = Random.new(4)
			for y = 0, ih - 1 do
				for x = 0, iw - 1 do
					local sv = y / PPS
					local su = x / PPS
					if sv < 3.5 then -- fascia / sign band
						local r = 236 + rng:NextInteger(-3, 3)
						if y == 27 or y == 26 then
							r = 150
						end
						set(x, y, r, r, r - 4)
					elseif sv >= 17 then -- plinth
						set(x, y, 110, 110, 112)
					elseif su % 6 < 0.35 or su % 6 > 5.65 or sv < 3.9 or sv > 16.6 then -- mullions and frame
						set(x, y, 70, 72, 76)
					elseif su > 9.5 and su < 14.5 and sv > 9.5 and math.abs(su - 12) < 0.15 then -- door split
						set(x, y, 70, 72, 76)
					else
						set(x, y, GLASS[1], GLASS[2], GLASS[3])
					end
				end
			end
		end)
	return shopfront
end

-- Upper-floor layouts in one 12 x 14 tile (stretched to the storey height). v runs from
-- the top of the storey; the floor slab sits in the bottom ~5.4 of 17.86 studs, so the
-- window band must sit above it: v 1.2 .. 9.0 (ribbon) / 1.0 .. 9.2 (office grid).
T.Layout = {
	ribbon = { pv0 = 1.2, pv1 = 9.0, panes = { { 0.18, 5.82 }, { 6.18, 11.82 } } },
	office = { pv0 = 1.0, pv1 = 9.2, panes = { { 1.7, 5.85 }, { 6.15, 10.3 } } },
}

-- alpha = window-pixel opacity (255 = opaque painted glass, lower = see-through)
local office = {}
function T.Office(alpha: number?)
	alpha = alpha or 255
	if office[alpha] then
		return office[alpha]
	end
	local L = T.Layout.office
	office[alpha] = newImage(12, 14, function(iw, ih, set)
		local rng = Random.new(7)
		for y = 0, ih - 1 do
			for x = 0, iw - 1 do
				local su, sv = x / PPS, y / PPS
				if sv < L.pv0 - 0.3 or sv >= L.pv1 + 0.3 then -- spandrel covers the slab edge
					local r = 176 + rng:NextInteger(-4, 4)
					set(x, y, r, r - 4, r - 12)
				elseif su < 1.4 or su > 10.6 then -- pier
					local r = 196 + rng:NextInteger(-4, 4)
					set(x, y, r, r - 6, r - 16)
				elseif su < 1.7 or su > 10.3 or sv < L.pv0 or sv > L.pv1 or math.abs(su - 6) < 0.15 then
					set(x, y, 182, 186, 191) -- frame and mullion
				else
					set(x, y, GLASS[1], GLASS[2], GLASS[3], alpha)
				end
			end
		end
	end)
	return office[alpha]
end

local ribbons = {}
function T.Ribbon(variant: string, alpha: number?)
	alpha = alpha or 255
	local key = variant .. alpha
	if ribbons[key] then
		return ribbons[key]
	end
	local L = T.Layout.ribbon
	local tile = variant == "brown" and { 150, 128, 106 } or { 176, 176, 172 }
	local grout = variant == "brown" and { 122, 104, 86 } or { 148, 148, 146 }
	ribbons[key] = newImage(12, 14, function(iw, ih, set)
		for y = 0, ih - 1 do
			for x = 0, iw - 1 do
				local su, sv = x / PPS, y / PPS
				if sv < L.pv0 - 0.25 or sv >= L.pv1 + 0.25 then -- tiled spandrel
					local j = ((x // 8) * 7 + (y // 4) * 13) % 9 - 4
					if x % 8 == 0 or y % 4 == 0 then
						set(x, y, grout[1] + j, grout[2] + j, grout[3] + j)
					else
						set(x, y, tile[1] + j, tile[2] + j, tile[3] + j)
					end
					if sv >= L.pv1 + 0.25 and sv < L.pv1 + 0.5 then -- shadow under the sill
						set(x, y, grout[1] - 30, grout[2] - 30, grout[3] - 30)
					end
				elseif sv < L.pv0 or sv > L.pv1 or su % 6 < 0.18 or su % 6 > 5.82 then
					set(x, y, 205, 208, 211) -- aluminium head, sill and mullions
				else
					set(x, y, GLASS[1], GLASS[2], GLASS[3], alpha)
				end
			end
		end
	end)
	return ribbons[key]
end

-- Which layout a texture image belongs to (any alpha variant).
function T.LayoutOf(img)
	for _, a in { 255, T.SeeThroughAlpha } do
		if img == T.Ribbon("grey", a) or img == T.Ribbon("brown", a) then
			return T.Layout.ribbon
		elseif img == T.Office(a) then
			return T.Layout.office
		end
	end
	return nil
end
T.SeeThroughAlpha = 70

-- Re-style the upper skins of every building in a folder: cycles grid / brown ribbon / grey ribbon.
-- seeThrough: window pixels partly transparent, skin part fully transparent, texture on both faces.
function T.Restyle(folder: Instance, seeThrough: boolean?)
	local styles = { "grid", "brown", "grey" }
	local alpha = seeThrough and T.SeeThroughAlpha or 255
	local n = 0
	local list = {}
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			table.insert(list, m)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	for i, model in list do
		local style = styles[(i - 1) % 3 + 1]
		local rng = Random.new(i * 31)
		local tint = Color3.fromHSV(rng:NextNumber(0.05, 0.12), rng:NextNumber(0, 0.05), rng:NextNumber(0.92, 1))
		local skins = model:FindFirstChild("FacadeSkins")
		if skins then
			for _, p in skins:GetChildren() do
				if p.Name == "UpperSkin" then
					local t = p:FindFirstChildOfClass("Texture")
					t.TextureContent = Content.fromObject(style == "grid" and T.Office(alpha) or T.Ribbon(style, alpha))
					t.StudsPerTileU = 12
					t.Color3 = tint
					local back = p:FindFirstChild("BackTexture")
					if seeThrough then
						p.Transparency = 1
						back = back or t:Clone()
						back.Name = "BackTexture"
						back.Face = Enum.NormalId.Back
						back.TextureContent = t.TextureContent
						back.Color3 = tint
						back.Parent = p
					elseif back then
						back:Destroy()
					end
					n += 1
				end
			end
		end
	end
	return n
end

-- Parts version of the upper floors: replaces each UpperSkin with a per-floor part
-- composition (spandrel bands, head/sill strips, mullions or piers, real glass panes
-- tagged for the glass system). Colours are sampled from the skin's own texture.
local GLASS_C = Color3.fromRGB(88, 104, 118)
local function texColor(tex: Texture, img, fu: number, fv: number): Color3
	local px = math.clamp(math.floor(fu * img.Size.X), 0, img.Size.X - 1)
	local py = math.clamp(math.floor(fv * img.Size.Y), 0, img.Size.Y - 1)
	local buf = img:ReadPixelsBuffer(Vector2.new(px, py), Vector2.one)
	local c = tex.Color3
	return Color3.fromRGB(buffer.readu8(buf, 0) * c.R, buffer.readu8(buf, 1) * c.G, buffer.readu8(buf, 2) * c.B)
end

function T.ComposeUpper(model: Model): number
	local skins = model:FindFirstChild("FacadeSkins")
	if not skins then
		return 0
	end
	local GlassVisual = require(game:GetService("ReplicatedStorage").Shared.GlassVisual)
	local out = model:FindFirstChild("FacadeParts") or Instance.new("Folder")
	out.Name = "FacadeParts"
	out.Parent = model
	local made = 0
	for _, sk in skins:GetChildren() do
		if sk.Name ~= "UpperSkin" then
			continue
		end
		local tex = sk:FindFirstChildOfClass("Texture")
		local img = tex and tex.TextureContent and tex.TextureContent.Object
		local lay = img and T.LayoutOf(img)
		if not lay then
			continue
		end
		local ribbon = lay == T.Layout.ribbon
		local pv0, pv1 = lay.pv0, lay.pv1
		local wallCol = texColor(tex, img, 0.31, 0.8)
		local frameCol = Color3.fromRGB(200, 203, 206)
		local pierCol = ribbon and frameCol or texColor(tex, img, 0.05, (pv0 + pv1) / 28)
		local L, H = sk.Size.X, sk.Size.Y
		local fh = tex.StudsPerTileV
		local k = fh / 14
		local floors = math.max(1, math.floor(H / fh + 0.5))
		local function put(u0, u1, v0, v1, color, mat, isGlass, name)
			if u1 - u0 < 0.05 or v1 - v0 < 0.05 then
				return
			end
			local p = Instance.new("Part")
			p.Anchored = true
			p.Name = name
			p.Material = mat or Enum.Material.SmoothPlastic
			p.Color = color
			p.Size = Vector3.new(u1 - u0, v1 - v0, isGlass and 0.25 or (name == "Mullion" and 0.9 or 0.6))
			p.CFrame = sk.CFrame * CFrame.new(L / 2 - (u0 + u1) / 2, H / 2 - (v0 + v1) / 2, isGlass and 0.15 or 0)
			if isGlass then
				p.Transparency = 0.3
				p.Reflectance = 0.1
				p.Parent = out
				GlassVisual.Capture(p, model.Name .. ":" .. made, true)
			else
				p.Parent = out
			end
			made += 1
		end
		for f = 0, floors - 1 do
			local top = f * fh
			put(0, L, top, top + pv0 * k - 0.25, wallCol, Enum.Material.SmoothPlastic, false, "Spandrel")
			put(0, L, top + pv0 * k - 0.25, top + pv0 * k, frameCol, Enum.Material.Metal, false, "Head")
			put(0, L, top + pv1 * k, top + pv1 * k + 0.25, frameCol, Enum.Material.Metal, false, "Sill")
			put(0, L, top + pv1 * k + 0.25, top + fh, wallCol, Enum.Material.SmoothPlastic, false, "Spandrel")
			local u = 0
			local i = 0
			while u < L - 0.05 do
				for _, pr in lay.panes do
					local a, b = i * 12 + pr[1], math.min(i * 12 + pr[2], L)
					if a < L then
						put(u, math.min(a, L), top + pv0 * k, top + pv1 * k, pierCol, Enum.Material.Metal, false, "Mullion")
						if b - a > 0.5 then
							put(a, b, top + pv0 * k, top + pv1 * k, GLASS_C, Enum.Material.Glass, true, "GlassPane")
						end
						u = b
					end
				end
				i += 1
				if i * 12 >= L then
					put(u, L, top + pv0 * k, top + pv1 * k, pierCol, Enum.Material.Metal, false, "Mullion")
					u = L
				end
			end
		end
		sk:Destroy()
	end
	return made
end

local function skin(parent: Instance, origin: CFrame, a, b, y0: number, y1: number, img, tileU: number, tileV: number, tint: Color3, name: string)
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1 then
		return nil
	end
	local ox, oz = dz / len, -dx / len -- outward for counter-clockwise outlines
	local mx, mz = (a[1] + b[1]) / 2 + ox * 0.3, (a[2] + b[2]) / 2 + oz * 0.3
	local xAxis = Vector3.new(-oz, 0, ox)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Name = name
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(150, 146, 140)
	p.Size = Vector3.new(len + 0.6, y1 - y0, 0.6) -- overlap at corners so they close
	p.CFrame = origin * CFrame.fromMatrix(Vector3.new(mx, (y0 + y1) / 2, mz), xAxis, Vector3.yAxis)
	local t = Instance.new("Texture")
	t.Face = Enum.NormalId.Front
	t.TextureContent = Content.fromObject(img)
	t.StudsPerTileU, t.StudsPerTileV = tileU, tileV
	t.OffsetStudsV = 0
	t.Color3 = tint
	t.Parent = p
	p.Parent = parent
	return p
end

local function outlineKey(polys)
	local parts = {}
	for _, p in polys do
		for _, v in p do
			table.insert(parts, string.format("%.0f,%.0f", v[1], v[2]))
		end
		table.insert(parts, "|")
	end
	return table.concat(parts, ";")
end

-- Adds facade skins to a model whose slabs were already rebuilt (level count matches plan).
-- groundFlat: also skin the ground floor (the flat version); otherwise leave GroundFacadePilot.
function T.AddSkins(model: Model, Reducer, groundFlat: boolean, seed: number): (number, string?)
	local plan = HttpService:JSONDecode(model:GetAttribute("SourceSlicePlan"))
	local origin = model:GetAttribute("SourceSliceOriginCFrame")
	local slabYs = {}
	local seen = {}
	for _, d in model.Interior:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Slab" then
			local k = math.floor(d.Position.Y * 10 + 0.5)
			if not seen[k] then
				seen[k] = true
				table.insert(slabYs, d.Position.Y)
			end
		end
	end
	table.sort(slabYs)
	if #slabYs ~= #plan.levels then
		return 0, "level mismatch"
	end
	local rng = Random.new(seed)
	local tint = Color3.fromHSV(rng:NextNumber(0.05, 0.6), rng:NextNumber(0.0, 0.18), rng:NextNumber(0.85, 1))
	local folder = Instance.new("Folder")
	folder.Name = "FacadeSkins"
	local made = 0
	local t = plan.levels[1].thickness
	local function localY(worldY: number): number
		return worldY - origin.Y
	end
	local outlines = {}
	for i, level in plan.levels do
		local polys = {}
		for _, poly in Reducer.reduceLevel(level.pieces, { areaTol = 20, snapDeg = 8, dropSlivers = true, returnOutline = true }) do
			if #poly >= 3 then
				table.insert(polys, poly)
			end
		end
		outlines[i] = polys
	end
	local n = #plan.levels
	-- floor i spans from slab i bottom to slab i+1 bottom; the last level is the roof slab.
	local i = 1
	while i < n do
		local isGround = i == 1
		local j = i
		if not isGround then
			while j + 1 < n and outlineKey(outlines[j + 1]) == outlineKey(outlines[i]) do
				j += 1
			end
		end
		local y0 = localY(slabYs[i] - t / 2) - (isGround and 3 or 0)
		local y1 = localY(slabYs[j + 1] - t / 2)
		local floorH = (slabYs[i + 1] - slabYs[i])
		if not isGround or groundFlat then
			for _, poly in outlines[i] do
				for k = 1, #poly do
					local a, b = poly[k], poly[k % #poly + 1]
					local p
					if isGround then
						p = skin(folder, origin, a, b, y0, y1, T.Shopfront(), 24, y1 - y0, tint, "GroundSkin")
					else
						p = skin(folder, origin, a, b, y0, y1, T.Office(), 12, floorH, tint, "UpperSkin")
					end
					if p then
						made += 1
					end
				end
			end
		end
		i = j + 1
	end
	folder.Parent = model
	return made, nil
end

return T
