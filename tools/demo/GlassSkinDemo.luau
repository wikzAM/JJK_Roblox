-- Edit-time demo (run through MCP as a temporary ModuleScript): one floor of facade
-- as a single textured "skin" Part, then the same floor cracked, with panes broken
-- (skin split into plain boxes around each opening), hit by a physical attack
-- (blocky hole + debris) and by a beam (crisp CSG hole). Everything is built under
-- Workspace.GlassSkinDemo, off-map. The painted texture is an EditableImage, so it
-- only exists in this Studio session (not saved or replicated).
local AssetService = game:GetService("AssetService")
local GeometryService = game:GetService("GeometryService")

local Demo = {}

local W, H = 48, 14 -- studs
local PPS = 8 -- pixels per stud
Demo.W, Demo.H = W, H
-- Pane rectangles in stud space (u left->right, v top->bottom as seen from the street).
Demo.Panes = {}
for i = 0, 3 do
	table.insert(Demo.Panes, { u0 = 1.5 + i * 12, u1 = 10.5 + i * 12, v0 = 3, v1 = 11 })
end

local function paint(): EditableImage
	local iw, ih = W * PPS, H * PPS
	local img = AssetService:CreateEditableImage({ Size = Vector2.new(iw, ih) })
	local buf = buffer.create(iw * ih * 4)
	local rng = Random.new(11)
	local function set(x, y, r, g, b)
		local i = (y * iw + x) * 4
		buffer.writeu8(buf, i, math.clamp(r, 0, 255))
		buffer.writeu8(buf, i + 1, math.clamp(g, 0, 255))
		buffer.writeu8(buf, i + 2, math.clamp(b, 0, 255))
		buffer.writeu8(buf, i + 3, 255)
	end
	local tileJitter = {}
	for y = 0, ih - 1 do
		for x = 0, iw - 1 do
			local su, sv = x / PPS, y / PPS
			if sv < 3 then -- top spandrel band
				local r = 118 + (y == 23 and 30 or 0) + rng:NextInteger(-3, 3)
				set(x, y, r, r - 2, r - 6)
			elseif sv >= 11 then -- slab edge band
				local r = 150 + (y == 88 and 25 or 0) + rng:NextInteger(-4, 4)
				set(x, y, r, r, r + 2)
			else -- tiled wall
				local tx, ty = x // 16, y // 16
				local key = tx * 100 + ty
				tileJitter[key] = tileJitter[key] or rng:NextInteger(-7, 7)
				local j = tileJitter[key]
				if x % 16 == 0 or y % 16 == 0 then
					set(x, y, 172 + j, 160 + j, 140 + j)
				else
					set(x, y, 206 + j, 191 + j, 166 + j)
				end
			end
		end
	end
	for _, p in Demo.Panes do
		local x0, x1, y0, y1 = p.u0 * PPS, p.u1 * PPS - 1, p.v0 * PPS, p.v1 * PPS - 1
		for y = y0 - 2, y1 + 3 do
			for x = x0 - 2, x1 + 2 do
				local frame = x < x0 or x > x1 or y < y0 or y > y1
				if y > y1 + 1 then
					set(x, y, 222, 222, 220) -- sill
				elseif frame then
					set(x, y, 184, 188, 193) -- aluminium frame
				else
					local t = (y - y0) / (y1 - y0)
					local r, g, b = 66 - 22 * t, 84 - 28 * t, 104 - 34 * t
					local d = (x - x0) + (y - y0) * 0.9 -- diagonal reflection streak
					if d % 70 > 18 and d % 70 < 34 then
						r, g, b = r + 38, g + 42, b + 44
					end
					local mid = (x0 + x1) // 2
					if math.abs(x - mid) <= 1 or y == y0 + (y1 - y0) // 3 or y == y0 + (y1 - y0) // 3 + 1 then
						r, g, b = 172, 176, 181 -- mullion and transom
					end
					set(x, y, r, g, b)
				end
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, img.Size, buf)
	return img
end

local image
function Demo.Image(): EditableImage
	image = image or paint()
	return image
end

-- One skin piece covering stud rect (u0..u1, v0..v1) of a facade whose top-left
-- corner (as seen from the street, facing -Z) is at `origin`.
function Demo.SkinPiece(origin: CFrame, u0: number, u1: number, v0: number, v1: number, parent: Instance, signU: number, signV: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(150, 146, 140) -- reveal colour seen on cut edges
	p.Size = Vector3.new(u1 - u0, v1 - v0, 0.6)
	-- Viewer looks along +Z, so screen-right is -X.
	p.CFrame = origin * CFrame.new(-(u0 + u1) / 2, -(v0 + v1) / 2, 0)
	local t = Instance.new("Texture")
	t.Face = Enum.NormalId.Front
	t.TextureContent = Content.fromObject(Demo.Image())
	t.StudsPerTileU, t.StudsPerTileV = W, H
	t.OffsetStudsU, t.OffsetStudsV = signU * u0, signV * v0
	t.Parent = p
	p.Parent = parent
	return p
end

-- Split the full skin around a list of rectangular openings (all in one row band):
-- strips between openings plus above/below boxes. Returns the parts made.
function Demo.SkinWithOpenings(origin: CFrame, holes, parent: Instance, signU: number, signV: number)
	table.sort(holes, function(a, b)
		return a.u0 < b.u0
	end)
	local made = {}
	local u = 0
	for _, h in holes do
		if h.u0 > u then
			table.insert(made, Demo.SkinPiece(origin, u, h.u0, 0, H, parent, signU, signV))
		end
		if h.v0 > 0 then
			table.insert(made, Demo.SkinPiece(origin, h.u0, h.u1, 0, h.v0, parent, signU, signV))
		end
		if h.v1 < H then
			table.insert(made, Demo.SkinPiece(origin, h.u0, h.u1, h.v1, H, parent, signU, signV))
		end
		u = h.u1
	end
	if u < W then
		table.insert(made, Demo.SkinPiece(origin, u, W, 0, H, parent, signU, signV))
	end
	return made
end

return Demo
