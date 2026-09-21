--!nonstrict
-- World-space extents of REAL part geometry.
--
-- A WedgePart fills only half of its Size box: the mirror corner of its two legs
-- is empty space. Measuring all eight box corners therefore reports a footprint
-- the building does not have. That is exactly what produced the FBX overlay's
-- unexplained overhang -- measured 201.8 x 187.1 against a true 181.3 x 177.7,
-- the whole 20-stud excess coming from 16 roof wedges -- and it contaminates any
-- grey-vs-slice comparison, because BuildingSmooth_* massing is mostly wedges.
--
-- Corner convention matches SourceSliceBuilder.slabShape (audited live): the
-- wedge cross-section is (-Y,-Z), (-Y,+Z), (+Y,+Z); (+Y,-Z) is not material.
--
-- Corners(part) -> {Vector3} world-space material corners.
-- Box(target, filter?) -> min, max, count. target is a BasePart, or any Instance
--   whose BasePart descendants are measured, or an array of either.
-- Footprint(target, filter?) -> table with horizontal size/area, or nil if empty.
local PartExtents = {}

local WEDGE_YZ = {{-1,-1},{-1,1},{1,1}}
local BOX_YZ = {{-1,-1},{-1,1},{1,1},{1,-1}}

function PartExtents.Corners(part)
	local half = part.Size / 2
	local cf = part.CFrame
	local pattern = part:IsA("WedgePart") and WEDGE_YZ or BOX_YZ
	local corners = {}
	for _, x in {-half.X, half.X} do
		for _, yz in pattern do
			table.insert(corners, cf:PointToWorldSpace(Vector3.new(x, yz[1]*half.Y, yz[2]*half.Z)))
		end
	end
	return corners
end

local function collect(target, out)
	if typeof(target) == "table" then
		for _, item in target do collect(item, out) end
	elseif typeof(target) == "Instance" then
		if target:IsA("BasePart") then table.insert(out, target) end
		for _, child in target:GetDescendants() do
			if child:IsA("BasePart") then table.insert(out, child) end
		end
	end
	return out
end

function PartExtents.Box(target, filter)
	local min, max, count = nil, nil, 0
	for _, part in collect(target, {}) do
		if filter and not filter(part) then continue end
		count += 1
		for _, corner in PartExtents.Corners(part) do
			min = min and min:Min(corner) or corner
			max = max and max:Max(corner) or corner
		end
	end
	return min, max, count
end

function PartExtents.Footprint(target, filter)
	local min, max, count = PartExtents.Box(target, filter)
	if not min then return nil end
	local size = max - min
	return {
		minX = min.X, maxX = max.X, minY = min.Y, maxY = max.Y, minZ = min.Z, maxZ = max.Z,
		sizeX = size.X, sizeY = size.Y, sizeZ = size.Z,
		area = size.X * size.Z,
		parts = count,
	}
end

-- Horizontal MATERIAL area of an upright slab part -- the area it actually covers,
-- not the area of its bounding box. These differ by 2x for every wedge, and by the
-- rotation artifact for anything yawed, which is why extent comparisons cannot
-- answer "is this footprint bigger than that one".
-- PolygonSlab stamps SlabFootprintArea on everything it builds; the geometric
-- fallback is for parts it did not.
-- Returns area, exact.
function PartExtents.SlabArea(part)
	local stored = part:GetAttribute("SlabFootprintArea")
	if type(stored) == "number" then return stored, true end
	local size, cf = part.Size, part.CFrame
	local horizontal, vertical = {}, false
	for _, axis in {{cf.RightVector, size.X}, {cf.UpVector, size.Y}, {cf.LookVector, size.Z}} do
		if not vertical and math.abs(axis[1].Y) > 0.999 then vertical = true
		else table.insert(horizontal, axis[2]) end
	end
	if not vertical or #horizontal ~= 2 then return nil, false end
	local rectangle = horizontal[1] * horizontal[2]
	-- A wedge covers half of its box footprint.
	return part:IsA("WedgePart") and rectangle / 2 or rectangle, false
end

-- Groups upright slab parts into storeys by measured bottom, summing real material
-- area per storey. Rows are sorted bottom-up. `estimated` counts parts whose area
-- had to be inferred rather than read from SlabFootprintArea.
function PartExtents.Storeys(target, filter)
	local rows = {}
	for _, part in collect(target, {}) do
		if filter and not filter(part) then continue end
		local min, max = PartExtents.Box(part)
		local row
		for _, candidate in rows do
			if math.abs(candidate.bottom - min.Y) <= 0.05 then row = candidate; break end
		end
		if not row then
			row = {bottom = min.Y, thickness = 0, area = 0, parts = 0, estimated = 0}
			table.insert(rows, row)
		end
		row.thickness = math.max(row.thickness, max.Y - min.Y)
		row.parts += 1
		local slabArea, exact = PartExtents.SlabArea(part)
		if slabArea then
			row.area += slabArea
			if not exact then row.estimated += 1 end
		else
			row.estimated += 1
		end
	end
	table.sort(rows, function(a, b) return a.bottom < b.bottom end)
	return rows
end

return PartExtents
