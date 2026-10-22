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
	local function set(x, y, r, g, b)
		local i = (y * iw + x) * 4
		buffer.writeu8(buf, i, math.clamp(r, 0, 255))
		buffer.writeu8(buf, i + 1, math.clamp(g, 0, 255))
		buffer.writeu8(buf, i + 2, math.clamp(b, 0, 255))
		buffer.writeu8(buf, i + 3, 255)
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

-- Simple office floor, one tile = 12 x 14 studs (stretched to floor height).
local office
function T.Office()
	office = office
		or newImage(12, 14, function(iw, ih, set)
			local rng = Random.new(7)
			for y = 0, ih - 1 do
				for x = 0, iw - 1 do
					local su, sv = x / PPS, y / PPS
					if sv < 2.5 or sv >= 11.5 then -- spandrel / slab band
						local r = 176 + rng:NextInteger(-4, 4)
						set(x, y, r, r - 4, r - 12)
					elseif su < 1.4 or su > 10.6 then -- pier
						local r = 196 + rng:NextInteger(-4, 4)
						set(x, y, r, r - 6, r - 16)
					elseif su < 1.7 or su > 10.3 or sv < 2.8 or sv > 11.2 or math.abs(su - 6) < 0.15 then
						set(x, y, 182, 186, 191) -- frame and mullion
					else
						set(x, y, GLASS[1], GLASS[2], GLASS[3])
					end
				end
			end
		end)
	return office
end

-- Tokyo ribbon-window office (small-tile spandrels, continuous glazing, aluminium
-- mullions every 3 studs, flat glass colour). Tile = 12 x 14 studs.
local ribbons = {}
function T.Ribbon(variant: string)
	if ribbons[variant] then
		return ribbons[variant]
	end
	local tile = variant == "brown" and { 150, 128, 106 } or { 176, 176, 172 }
	local grout = variant == "brown" and { 122, 104, 86 } or { 148, 148, 146 }
	ribbons[variant] = newImage(12, 14, function(iw, ih, set)
		for y = 0, ih - 1 do
			for x = 0, iw - 1 do
				local su, sv = x / PPS, y / PPS
				if sv < 6.2 or sv >= 12.6 then -- tiled spandrel
					local j = ((x // 8) * 7 + (y // 4) * 13) % 9 - 4
					if x % 8 == 0 or y % 4 == 0 then
						set(x, y, grout[1] + j, grout[2] + j, grout[3] + j)
					else
						set(x, y, tile[1] + j, tile[2] + j, tile[3] + j)
					end
					if sv >= 12.6 and sv < 12.85 then -- shadow under the window sill
						set(x, y, grout[1] - 30, grout[2] - 30, grout[3] - 30)
					end
				elseif sv < 6.45 or sv > 12.35 or su % 3 < 0.18 or su % 3 > 2.82 then
					set(x, y, 205, 208, 211) -- aluminium head, sill and mullions
				else
					set(x, y, GLASS[1], GLASS[2], GLASS[3])
				end
			end
		end
	end)
	return ribbons[variant]
end

-- Re-style the upper skins of every building in a folder: cycles grid / brown ribbon / grey ribbon.
function T.Restyle(folder: Instance)
	local styles = { "grid", "brown", "grey" }
	local n = 0
	for i, model in folder:GetChildren() do
		local style = styles[(i - 1) % 3 + 1]
		local rng = Random.new(i * 31)
		local tint = Color3.fromHSV(rng:NextNumber(0.05, 0.12), rng:NextNumber(0, 0.05), rng:NextNumber(0.92, 1))
		local skins = model:FindFirstChild("FacadeSkins")
		if skins then
			for _, p in skins:GetChildren() do
				if p.Name == "UpperSkin" then
					local t = p:FindFirstChildOfClass("Texture")
					t.TextureContent = Content.fromObject(style == "grid" and T.Office() or T.Ribbon(style))
					t.StudsPerTileU = 12
					t.Color3 = tint
					n += 1
				end
			end
		end
	end
	return n
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
	p.Size = Vector3.new(len, y1 - y0, 0.6)
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
		for _, p in level.pieces do
			local s = Reducer.simplify(p, 20)
			if #s >= 3 then
				table.insert(polys, s)
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
