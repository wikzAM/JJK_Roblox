--!nonstrict
-- Builds a crown as SOLID objects: one box or one prism per physical object.
--
-- The first crown renderer turned every FBX triangle into two WedgeParts. That
-- is the wrong representation for roof clutter three times over:
--   * a thin feature (a mast, a fin, a sign) has two surfaces a few studs apart,
--     so shelled it becomes a fan of overlapping plates at every corner;
--   * clipping the soup to the crown band manufactures slivers -- 9.7% of
--     clipped triangles had a shortest altitude under one stud;
--   * the result is hollow, which is what made lighting and collisions feel odd.
-- A box is one part, solid, seamless, and roof clutter is overwhelmingly boxy.
--
-- tools/source_slice_crown_boxes.py writes the payload. It splits the crown mesh
-- into connected components -- one physical object each -- and asks of every one
-- whether it fills its own bounding rectangle. If it does it is a BOX; if it
-- does not it is a PRISM, its footprint extruded over its own height. Either way
-- one solid per object, spanning its full height, so nothing terraces.
--
-- Everything arrives in the BUILDING'S OWN yaw frame: only 3.2% of vertical
-- crown faces are world-axis-aligned, so world-axis fitting finds almost
-- nothing. Local (a, b) here are the same coordinates the plan's level pieces
-- use, and the frame is built the same way SourceSliceBuilder builds theirs.
--
-- Build(parent, entry, options) -> parts, metrics
--   entry: {yaw, ox, oz, boxes = {{x,y,z,sx,sy,sz}},
--           prisms = {{y, h, points = {{a,b}, ...}}}}
--   options: name, color, material, tag
local CrownBoxes = {}

local Collection = game:GetService("CollectionService")
local PolygonSlab = require(script.Parent.PolygonSlab)

local MIN_SIZE = 0.05

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function CrownBoxes.Build(parent, entry, options)
	assert(typeof(parent) == "Instance", "Provide a parent for the crown")
	assert(type(entry) == "table", "Provide a crown entry table")
	options = options or {}
	local name = options.name or "CrownBox"
	local color = options.color or Color3.fromRGB(163, 162, 165)
	local material = options.material or Enum.Material.Concrete

	local yaw = entry.yaw or 0
	local ox, oz = entry.ox or 0, entry.oz or 0
	assert(finite(yaw) and finite(ox) and finite(oz), "Crown entry has a nonfinite origin")
	local cos, sin = math.cos(yaw), math.sin(yaw)
	-- Same mapping the plan uses for level pieces: (a,b) -> world XZ.
	local right = Vector3.new(cos, 0, -sin)
	local back = Vector3.new(sin, 0, cos)

	local parts = {}
	local metrics = {boxes = 0, prisms = 0, prismParts = 0, skipped = 0, failed = 0}
	local ok, err = pcall(function()
		for _, box in entry.boxes or {} do
			local size = Vector3.new(box.sx, box.sy, box.sz)
			if size.X < MIN_SIZE or size.Y < MIN_SIZE or size.Z < MIN_SIZE then
				metrics.skipped += 1
				continue
			end
			local part = Instance.new("Part")
			part.Name = name
			part.Size = size
			-- Never accept engine clamping; it would push the crown outward.
			assert((part.Size - size).Magnitude < math.max(0.0001, size.Magnitude * 1e-6),
				"Roblox clamped a crown box size")
			part.CFrame = CFrame.fromMatrix(
				Vector3.new(ox + cos * box.x + sin * box.z, box.y, oz - sin * box.x + cos * box.z),
				right, Vector3.yAxis, back)
			part.Anchored = true
			part.CanCollide = true
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Material = material
			part.Color = color
			part:SetAttribute("CrownBox", true)
			if options.tag then Collection:AddTag(part, options.tag) end
			table.insert(parts, part)
			metrics.boxes += 1
		end
		for _, part in parts do part.Parent = parent end
	end)
	if not ok then
		for _, part in parts do part:Destroy() end
		error(err, 2)
	end

	-- Anything not box-like is a PRISM: its own footprint extruded over its own
	-- height, as one solid. PolygonSlab tiles a rectangle as a single Part and
	-- any other polygon into exact right-triangle wedges, so this is solid too
	-- -- it is a filled volume, not a shell around one.
	local frame = CFrame.new(ox, 0, oz) * CFrame.Angles(0, yaw, 0)
	for index, prism in entry.prisms or {} do
		if prism.h < MIN_SIZE or #prism.points < 3 then
			metrics.skipped += 1
			continue
		end
		local points = table.create(#prism.points)
		for _, p in prism.points do
			table.insert(points, Vector2.new(p[1], p[2]))
		end
		local ok, err = pcall(function()
			local made, slab = PolygonSlab.Build(parent, points, prism.y, prism.h, frame,
				(options.name or "Crown") .. "Prism")
			for _, part in made do
				part.Material = material
				part.Color = color
				part:SetAttribute("CrownPrism", true)
				if options.tag then Collection:AddTag(part, options.tag) end
			end
			metrics.prisms += 1
			metrics.prismParts += slab.partCount
		end)
		if not ok then
			-- One bad ring must not lose the rest of the crown; count and move on.
			metrics.failed += 1
			metrics.lastError = ("prism %d: %s"):format(index, tostring(err))
		end
	end
	return parts, metrics
end

return CrownBoxes
