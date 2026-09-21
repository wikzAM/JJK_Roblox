--!nonstrict
-- Builds arbitrary 3D triangles out of WedgeParts.
--
-- Floors are horizontal plates and PolygonSlab covers them. Everything ABOVE a
-- building's last floor is not floors: a stepped crown, a parapet, a ledge, a
-- plant enclosure. That geometry has no storeys to lay out, so it does not need
-- slicing at all -- the FBX already describes it, and it can be rendered
-- directly. On the 6_4510_4915_-8852 tower the whole crown is 85 triangles.
--
-- Any triangle is two right triangles joined at the foot of the altitude from
-- the vertex opposite the longest edge, and a Roblox WedgePart is exactly a
-- right-triangular prism. So one triangle costs two wedges, at any orientation
-- -- including vertical, which is what a stepped crown is mostly made of.
--
-- Build(parent, triangles, options) -> parts, metrics
--   triangles: array of {aVector3, bVector3, cVector3} OR {{x,y,z},{x,y,z},{x,y,z}}
--   options:  thickness (default 0.5), name, color, material, tag,
--             fillToward (Vector3) -- grow the thickness INWARD towards this
--             point instead of centring it, so a thick shell reads as a solid
--             mass without fattening the silhouette
--
-- Degenerate triangles (any side or altitude under Roblox's 0.05 stud minimum)
-- are skipped and counted, never silently clamped -- clamping would extrude the
-- shell outward, which is the failure this project has repeatedly been bitten by.
local TriangleShell = {}

local Collection = game:GetService("CollectionService")
local MIN_SIZE = 0.05

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function toVector(value)
	if typeof(value) == "Vector3" then return value end
	assert(type(value) == "table" and #value == 3, "Triangle vertex must be Vector3 or {x,y,z}")
	assert(finite(value[1]) and finite(value[2]) and finite(value[3]), "Nonfinite triangle vertex")
	return Vector3.new(value[1], value[2], value[3])
end

-- Two wedges spanning one triangle. Returns nil when the triangle is too thin
-- for Roblox to represent without the engine resizing it.
local function wedgesFor(a, b, c, thickness, fillToward)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Put `a` opposite the longest edge so the altitude lands inside `bc`.
	if abd > acd and abd > bcd then
		a, c = c, a
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-6 then return nil end
	local right = normal.Unit
	local along = bc.Magnitude
	if along < MIN_SIZE then return nil end
	local back = bc / along
	local up = back:Cross(right)
	if up.Magnitude < 1e-6 then return nil end
	up = up.Unit
	local height = math.abs(ab:Dot(up))
	local first, second = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if height < MIN_SIZE or first < MIN_SIZE or second < MIN_SIZE then return nil end
	-- A wedge is centred on its triangle, so a thick one bulges half its
	-- thickness OUTWARD and fattens the building. With fillToward, slide the
	-- body so its outer face stays on the triangle and the thickness grows
	-- inward instead: the shell reads solid without changing the silhouette.
	local shift = Vector3.zero
	if fillToward then
		local centre = (a + b + c) / 3
		local inward = if (fillToward - centre):Dot(right) >= 0 then right else -right
		shift = inward * (thickness / 2)
	end
	return {
		{size = Vector3.new(thickness, height, first),
		 cf = CFrame.fromMatrix((a + b) / 2 + shift, right, up, back)},
		{size = Vector3.new(thickness, height, second),
		 cf = CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back)},
	}
end

function TriangleShell.Build(parent, triangles, options)
	assert(typeof(parent) == "Instance", "Provide a parent for the shell")
	assert(type(triangles) == "table" and #triangles > 0, "Provide a nonempty triangle array")
	options = options or {}
	local thickness = options.thickness or 0.5
	assert(finite(thickness) and thickness >= MIN_SIZE, "Invalid shell thickness")
	local name = options.name or "ShellWedge"
	local color = options.color or Color3.fromRGB(163, 162, 165)
	local material = options.material or Enum.Material.Concrete

	local parts = {}
	local metrics = {triangles = #triangles, wedges = 0, skipped = 0, area = 0}
	local ok, err = pcall(function()
		for _, triangle in triangles do
			assert(type(triangle) == "table" and #triangle == 3, "Each triangle needs 3 vertices")
			local a, b, c = toVector(triangle[1]), toVector(triangle[2]), toVector(triangle[3])
			metrics.area += (b - a):Cross(c - a).Magnitude / 2
			local specs = wedgesFor(a, b, c, thickness, options.fillToward)
			if not specs then
				metrics.skipped += 1
				continue
			end
			for _, spec in specs do
				local part = Instance.new("WedgePart")
				part.Name = name
				part.Size = spec.size
				-- Never accept engine clamping; it would push the shell outward.
				assert((part.Size - spec.size).Magnitude < math.max(0.0001, spec.size.Magnitude * 1e-6),
					"Roblox clamped a shell wedge size")
				part.CFrame = spec.cf
				part.Anchored = true
				part.CanCollide = true
				part.CanQuery = true
				part.Material = material
				part.Color = color
				part.TopSurface = Enum.SurfaceType.Smooth
				part.BottomSurface = Enum.SurfaceType.Smooth
				part:SetAttribute("ShellWedge", true)
				if options.tag then Collection:AddTag(part, options.tag) end
				table.insert(parts, part)
				metrics.wedges += 1
			end
		end
		for _, part in parts do part.Parent = parent end
	end)
	if not ok then
		for _, part in parts do part:Destroy() end
		error(err, 2)
	end
	return parts, metrics
end

return TriangleShell
