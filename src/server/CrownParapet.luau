--!nonstrict
-- A parapet: the top floor's own outline, extruded a few studs, as one solid.
--
-- This is the DULL path, and it is the right one for ~86% of buildings. Four
-- attempts at reconstructing rooftop detail from the Shibuya scan all failed --
-- wedge shells fanned at corners, slice stacks terraced, per-object prisms
-- terraced again -- because the median crown component retains only 0.38 of a
-- closed box's surface area. The scan saw a roof's top and one or two sides;
-- there is no solid in the data to recover, and every fitter was inventing the
-- missing half differently.
--
-- A parapet invents nothing. The outline comes straight from the plan's last
-- level, which SourceSliceBuilder has already validated, so this cannot produce
-- geometry the plan does not already assert. PolygonSlab tiles a rectangle as
-- one Part and any other polygon into exact right-triangle wedges -- solid, not
-- a shell.
--
-- Crowns classified INTERESTING (sloped area >= 20% or band >= 50 studs; 14% of
-- them, the Cerulean Tower included) get no parapet. They keep whatever crown
-- they have and are marked `CrownInteresting` for detailed or hand work.
--
-- Build(parent, entry, options) -> parts, metrics
--   entry: {yaw, ox, oz, y, h, pieces = {{{a,b}, ...}, ...}}
local CrownParapet = {}

local Collection = game:GetService("CollectionService")
local PolygonSlab = require(script.Parent.PolygonSlab)

local MIN_SIZE = 0.05

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function CrownParapet.Build(parent, entry, options)
	assert(typeof(parent) == "Instance", "Provide a parent for the parapet")
	assert(type(entry) == "table" and type(entry.pieces) == "table", "Provide a parapet entry")
	options = options or {}
	local color = options.color or Color3.fromRGB(163, 162, 165)
	local material = options.material or Enum.Material.Concrete

	local yaw, ox, oz = entry.yaw or 0, entry.ox or 0, entry.oz or 0
	assert(finite(yaw) and finite(ox) and finite(oz), "Parapet entry has a nonfinite origin")
	assert(finite(entry.y) and finite(entry.h) and entry.h >= MIN_SIZE, "Invalid parapet height")
	-- Same frame SourceSliceBuilder uses for level pieces.
	local frame = CFrame.new(ox, 0, oz) * CFrame.Angles(0, yaw, 0)

	local metrics = {pieces = 0, parts = 0, failed = 0}
	for index, piece in entry.pieces do
		if #piece < 3 then
			metrics.failed += 1
			continue
		end
		local points = table.create(#piece)
		for _, p in piece do
			table.insert(points, Vector2.new(p[1], p[2]))
		end
		local ok, err = pcall(function()
			local made, slab = PolygonSlab.Build(parent, points, entry.y, entry.h, frame, "Parapet")
			for _, part in made do
				part.Material = material
				part.Color = color
				part:SetAttribute("CrownParapet", true)
				if options.tag then Collection:AddTag(part, options.tag) end
			end
			metrics.pieces += 1
			metrics.parts += slab.partCount
		end)
		if not ok then
			-- One bad ring must not cost the rest of the parapet.
			metrics.failed += 1
			metrics.lastError = ("piece %d: %s"):format(index, tostring(err))
		end
	end
	return metrics
end

-- A RIM, not a slab. Build() extrudes the whole top-floor outline as one solid,
-- which the map owner correctly reported as invisible: it reads as a slightly
-- thicker top floor, "a flat top part of the highest floor", with no ledge. A
-- real parapet is a low wall around the edge with the roof open inside it.
--
-- One Part per outline edge -- boxes, never wedges -- stood on the roof, inset
-- so its outer face is flush with the building's edge. Each wall is lengthened
-- by its own thickness so walls overlap at convex corners instead of leaving a
-- notch; at a reflex corner that overlap pokes half a thickness past the
-- outline, which at 1 stud is not visible. Edges shorter than the thickness are
-- skipped: their neighbours' overlap already covers them.
--
-- Same entry as Build(); options.height / options.thickness override the wall.
local RIM_HEIGHT = 6.0      -- studs, ~1.7 m: raised from 4 at the map owner's request, still a ledge
local RIM_THICKNESS = 1.0   -- studs, ~0.28 m

local function inside(points, x, z)
	local hit = false
	local j = #points
	for i = 1, #points do
		local a, b = points[i], points[j]
		if (a.Y > z) ~= (b.Y > z) and x < (b.X - a.X) * (z - a.Y) / (b.Y - a.Y) + a.X then
			hit = not hit
		end
		j = i
	end
	return hit
end

function CrownParapet.BuildRim(parent, entry, options)
	assert(typeof(parent) == "Instance", "Provide a parent for the rim")
	assert(type(entry) == "table" and type(entry.pieces) == "table", "Provide a parapet entry")
	options = options or {}
	local color = options.color or Color3.fromRGB(163, 162, 165)
	local material = options.material or Enum.Material.Concrete
	local height = options.height or RIM_HEIGHT
	local thickness = options.thickness or RIM_THICKNESS

	local yaw, ox, oz = entry.yaw or 0, entry.ox or 0, entry.oz or 0
	assert(finite(yaw) and finite(ox) and finite(oz), "Rim entry has a nonfinite origin")
	assert(finite(entry.y), "Rim entry has no roof height")
	local frame = CFrame.new(ox, 0, oz) * CFrame.Angles(0, yaw, 0)

	local metrics = {pieces = 0, parts = 0, failed = 0, skippedEdges = 0}
	for index, piece in entry.pieces do
		if #piece < 3 then
			metrics.failed += 1
			continue
		end
		local points = table.create(#piece)
		for _, p in piece do
			table.insert(points, Vector2.new(p[1], p[2]))
		end
		local made = {}
		local ok, err = pcall(function()
			for i, a in points do
				local b = points[i % #points + 1]
				local edge = b - a
				local length = edge.Magnitude
				if length < thickness then
					metrics.skippedEdges += 1
					continue
				end
				local dir = edge / length
				local normal = Vector2.new(-dir.Y, dir.X)
				local mid = (a + b) / 2
				-- Inward is whichever side of the edge is inside the outline. The
				-- scan's winding is not consistent, so test it rather than trust it.
				if not inside(points, mid.X + normal.X * 0.05, mid.Y + normal.Y * 0.05) then
					normal = -normal
				end
				local centre = mid + normal * (thickness / 2)
				local localCF = CFrame.fromMatrix(
					Vector3.new(centre.X, entry.y + height / 2, centre.Y),
					Vector3.new(dir.X, 0, dir.Y), Vector3.yAxis)
				local wall = Instance.new("Part")
				wall.Name = "ParapetRim"
				wall.Size = Vector3.new(length + thickness, height, thickness)
				wall.CFrame = frame * localCF
				wall.Anchored = true
				wall.CanCollide = true
				wall.CanQuery = true
				wall.Material = material
				wall.Color = color
				wall.TopSurface = Enum.SurfaceType.Smooth
				wall.BottomSurface = Enum.SurfaceType.Smooth
				wall:SetAttribute("CrownParapet", true)
				wall:SetAttribute("ParapetRim", true)
				if options.tag then Collection:AddTag(wall, options.tag) end
				table.insert(made, wall)
			end
			for _, wall in made do wall.Parent = parent end
		end)
		if ok then
			metrics.pieces += 1
			metrics.parts += #made
		else
			for _, wall in made do wall:Destroy() end
			metrics.failed += 1
			metrics.lastError = ("piece %d: %s"):format(index, tostring(err))
		end
	end
	return metrics
end

return CrownParapet
