--!nonstrict
-- BuildingGenerator.luau
-- EDIT-TIME tool. Run from the Studio command bar (NOT at play time):
--
--   require(game.ServerScriptService.Server.BuildingGenerator).GenerateAll()
--
-- Takes shell Models inside Workspace.Buildings (each named "Building*") and
-- generates a destructible interior from primitive Parts. Original shell
-- parts are retained by default (KEEP_SHELL).
--
-- WHOLE-VOLUME / SILHOUETTE FOLLOWING: the generator samples the model's solid
-- volume floor-by-floor with WorldRoot:GetPartsInPart, which uses each part's
-- TRUE collision geometry. So the shell can be ANY mix of solid primitives —
-- blocks, wedges, cylinders, unions, rotated parts — and the interior follows
-- the real silhouette: wedges taper floor by floor, cylinders read round,
-- height steps drop away. The whole model is treated as one space (not per
-- part). Curves/diagonals are approximated to the sample grid, so they come
-- out lightly stepped.	
--
--   IMPORTANT: the shell parts must be SOLID (a filled block/wedge/cylinder/
--   union that fills the building's mass). A hollow box made of 6 thin wall
--   parts has no interior volume to sample and will generate nothing.
--
-- CORE: every building gets a core (collapse-script anchor). It is placed in
-- the largest solid rectangle of the ground floor and spans every floor whose
-- footprint still covers it. Core wall parts are tagged "BuildingCore"
-- (CollectionService); the building gets CoreCFrame / CoreSize attributes.
--
-- IDEMPOTENT: a building with an existing "Interior" Model child is skipped.
-- The sampled occupancy grid is stored as attributes, so deleting the Interior
-- (or .Regenerate) rebuilds it WITHOUT re-sampling — even after the shell is
-- gone. (The stored grid is world-space: regenerate BEFORE moving a generated
-- building, not after.)
--
--   require(...).Generate(model)      -- generate one building
--   require(...).Regenerate(model)    -- force: deletes Interior, regenerates
--
-- All generated parts are parented under the Building model, so HitHandler's
-- "^Building" CSG filter destroys them automatically.

local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")
local ServerStorage     = game:GetService("ServerStorage")
local MaterialService   = game:GetService("MaterialService")
local Workspace         = game:GetService("Workspace")

-- ==========================================================
-- UNITS
-- ==========================================================
local METER = 1 / 0.28 -- 1 stud = 0.28 m  →  1 m ≈ 3.5714 studs

-- ==========================================================
-- CONFIG
-- ==========================================================
local FLOOR_CLEAR       = 3.5 * METER  -- floor-to-ceiling clear height (preset / height-driven mode)
local MIN_FLOOR_CLEAR   = 2.0 * METER  -- floor-count mode never packs floors tighter than this
local SLAB_THICKNESS    = 1.5 * METER  -- combined floor+ceiling slab (FIXED; never shrinks for floor count)
local FLOOR_PITCH       = FLOOR_CLEAR + SLAB_THICKNESS
local KEEP_SHELL        = true          -- retain the original shell part(s), untouched, after generating

local CORE_RATIO        = 0.40         -- core covers ~40% of the central solid rectangle
-- "Small" buildings (both shell X and Z below SMALL_BUILDING_MAX studs) get a
-- much larger core via SMALL_CORE_RATIO instead of CORE_RATIO.
local SMALL_BUILDING_MAX = 150         -- studs; both footprint axes under this = small
local SMALL_CORE_RATIO   = 0.35        -- small buildings: core covers ~70% of the rectangle
local MAX_RING_DEPTH    = 10 * METER   -- MIN ring-depth cap; raised per-building if the office models need more depth
local MIN_RING_DEPTH    = 2 * METER    -- below this there is no room for offices on that side
local MIN_CORE_SIZE     = 4 * METER    -- preferred minimum core width (shrinks on tiny footprints)
local CORE_WALL_THICK   = 1.0
local HALLWAY_WIDTH     = 1.5 * METER  -- kept clear alongside core walls
local CORE_TAG          = "BuildingCore"
local DECO_GAP          = 1.0          -- min clearance (studs) around core-wall deco (vs each other and office walls)

local PROTRUDE_THICK    = 0.5
local PROTRUDE_SLOT     = 9 * METER    -- MIN slot spacing along core walls; raised per-building to fit the live office width
local PROTRUDE_CHANCE   = 0.8          -- chance a slot actually gets a wall

local CARPET_THICK      = 0.1
local CARPET_COLOR      = Color3.fromRGB(99, 95, 98)

local LIGHT_SPACING     = 10 * METER   -- grid spacing of ceiling light strips
local LIGHT_SIZE        = Vector3.new(4, 0.15, 1)
local LIGHT_BRIGHTNESS  = 0.8
local LIGHT_RANGE       = 12 * METER
local LIGHT_COLOR       = Color3.fromRGB(255, 248, 230)

local INTERIOR_MATERIAL = Enum.Material.Concrete
local INTERIOR_COLOR    = Color3.fromRGB(200, 200, 200)

local MAX_FURNITURE_PER_FLOOR = 14     -- hard cap (main pieces; props extra)
local FURNITURE_MARGIN  = 1          -- studs of clearance required around furniture
local MIN_FURNITURE_SCALE = 0.6        -- small buildings may shrink an office down to this to make it fit
-- DETERMINISTIC SIZE: set this to the longest footprint edge (studs) you want the
-- offices to be, and they're uniformly scaled to match at generation (proportions
-- kept), regardless of the model's authored scale. The bays/ring/core then size to
-- that. Leave nil to use the models exactly as authored in ServerStorage.
local OFFICE_TARGET_LONG = nil :: number?

-- Per-bay fill mix (overall furniture density is intentionally modest):
--   EMPTY  → nothing            BAY_EMPTY_CHANCE
--   PROP   → just a plant/printer/trashcan   BAY_PROP_CHANCE
--   MAIN   → 50/50 GroupOffice vs ConferenceTable   (the rest)
local BAY_EMPTY_CHANCE  = 0.10
local BAY_PROP_CHANCE   = 0.10

-- Occupancy sampling resolution. Smaller cell = finer silhouette, more probes
-- and more slab rectangles. cell auto-scales so neither axis exceeds
-- MAX_CELLS_AXIS, floored at GRID_MIN.
local GRID_MIN          = 2.5          -- studs (~0.7 m)
local MAX_CELLS_AXIS    = 18

-- If your deco/furniture models come in facing the wrong way, fix it once here.
local DECO_YAW_OFFSET      = 0
local FURNITURE_YAW_OFFSET = 0
-- Roll (deg, about the facing axis) for assets that import tipped. Each asset has
-- its own convention: +90 stands the exit sign upright, -90 the trashcan, 180
-- flips the upside-down elevator doors right way up.
local EXIT_SIGN_ROLL       = 90
local ELEVATOR_ROLL        = 180
-- Per-model roll for furniture that imports tipped.
local FURNITURE_ROLL       = { Trashcan = -90 }

local CORE_DECO_FOLDER  = "CoreDeco"   -- ServerStorage.CoreDeco: CoreDoor, ElevatorDoor, ExitSignDoor, InteriorGlass
local FURNITURE_FOLDER  = "Furniture"  -- ServerStorage.Furniture: ConferenceTable, GroupOffice, LowPolyPlant, OfficePrinter, Trashcan

-- A MAIN bay is a 50/50 coin flip between GroupOffice and ConferenceTable
-- (whichever fits; coin flip when both do).
local PROP_FURNITURE    = { "LowPolyPlant", "OfficePrinter", "Trashcan" }

-- Decorative / non-structural interior parts get this tag. HitHandler DELETES
-- tagged parts (and all MeshParts) instead of running CSG on them — keeps hits fast.
local NO_CSG_TAG        = "NoCSG"

-- ==========================================================
-- HELPERS
-- ==========================================================
local function getTemplate(folderName, modelName)
	local folder = ServerStorage:FindFirstChild(folderName)
	if not folder then return nil end
	return folder:FindFirstChild(modelName)
end

local function templateSize(folderName, modelName)
	local t = getTemplate(folderName, modelName)
	if not t then return nil end
	if t:IsA("Model") then
		local _, size = t:GetBoundingBox()
		return size
	elseif t:IsA("BasePart") then
		return t.Size
	end
	return nil
end

local function makePart(name, size, worldCF, parent)
	local p = Instance.new("Part")
	p.Name       = name
	p.Size       = size
	p.CFrame     = worldCF
	p.Anchored   = true
	p.Material   = INTERIOR_MATERIAL
	p.Color      = INTERIOR_COLOR
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent     = parent
	return p
end

-- Tag every BasePart of an instance so HitHandler deletes it instead of CSG'ing.
local function tagNoCSG(inst)
	if inst:IsA("BasePart") then CollectionService:AddTag(inst, NO_CSG_TAG) end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then CollectionService:AddTag(d, NO_CSG_TAG) end
	end
end

-- Clone a template Model/Part; bbox bottom-center sits at `floorPos` (world),
-- rotated to `rotCF` (world rotation). Clones are decorative → tagged NoCSG.
-- Half the WORLD-vertical extent of a box of `size` after rotation R, so a
-- tipped/rolled clone still rests its bottom on the floor (not the template's
-- upright half-height, which would sink or float it).
local function rotatedHalfHeight(R, size)
	return 0.5 * (math.abs((R * Vector3.new(size.X, 0, 0)).Y)
		+ math.abs((R * Vector3.new(0, size.Y, 0)).Y)
		+ math.abs((R * Vector3.new(0, 0, size.Z)).Y))
end

local function placeClone(template, floorPos, rotCF, parent, scale)
	local clone = template:Clone()
	local R = rotCF.Rotation
	if scale and scale ~= 1 then
		if clone:IsA("BasePart") then
			clone.Size = clone.Size * scale
		elseif clone:IsA("Model") then
			-- ScaleTo is ABSOLUTE (relative to the model's authored scale=1), so
			-- multiply by the current scale to keep `scale` a relative factor that
			-- composes with whatever the template was already scaled to in Studio.
			clone:ScaleTo(clone:GetScale() * scale)
		end
	end
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CFrame = rotCF + floorPos + Vector3.new(0, rotatedHalfHeight(R, clone.Size), 0)
		clone.Parent = parent
		tagNoCSG(clone)
		return clone
	end
	local bboxCF, bboxSize = clone:GetBoundingBox()
	local rel = bboxCF:ToObjectSpace(clone:GetPivot())
	local targetBBox = (rotCF + floorPos + Vector3.new(0, rotatedHalfHeight(R, bboxSize), 0))
	clone:PivotTo(targetBBox * rel)
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	clone.Parent = parent
	tagNoCSG(clone)
	return clone
end

local function applyCeilingMaterial(part)
	local variant = MaterialService:FindFirstChild("Ceiling")
	if variant and variant:IsA("MaterialVariant") then
		part.Material = variant.BaseMaterial
		part.MaterialVariant = "Ceiling"
	end
end

local function applyCarpetMaterial(part)
	local variant = MaterialService:FindFirstChild("Carpet")
	if variant and variant:IsA("MaterialVariant") then
		part.Material = variant.BaseMaterial
		part.MaterialVariant = "Carpet"
	else
		part.Material = Enum.Material.Fabric
	end
	part.Color = CARPET_COLOR
end

local function buildingSeed(pos)
	return math.floor(pos.X * 73856093 + pos.Y * 19349663 + pos.Z * 83492791) % 2^31
end

-- Tight, YAW-ALIGNED bounding box of the shell. We DON'T use Model:GetBoundingBox
-- because, with no PrimaryPart, it returns the loose WORLD-AXIS AABB. If the shell
-- Part is rotated about Y (even slightly), that AABB's axes run diagonally across
-- the real faces, so the axis-aligned interior (walls, slabs) cut through the
-- exterior and the overshoot grows steadily along the face. Instead we take the
-- largest shell part's yaw (pitch/roll dropped — buildings are upright) and box
-- every shell part in THAT frame, so the interior grid lines up with the shell's
-- actual faces at any rotation.
local function computeOrientedBox(building)
	local parts = {}
	local largest, largestVol = nil, -1
	for _, p in building:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > largestVol then largestVol, largest = v, p end
		end
	end
	if not largest then return nil, nil end

	local _, yaw = largest.CFrame:ToEulerAnglesYXZ()
	local R = CFrame.fromEulerAnglesYXZ(0, yaw, 0) -- level frame, rotation only (zero position)
	local Rinv = R:Inverse()

	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in parts do
		local cf = Rinv * p.CFrame -- part expressed in the yaw frame
		local h = p.Size * 0.5
		for _, sgx in { -1, 1 } do
			for _, sgy in { -1, 1 } do
				for _, sgz in { -1, 1 } do
					local c = cf * Vector3.new(sgx * h.X, sgy * h.Y, sgz * h.Z)
					minV = Vector3.new(math.min(minV.X, c.X), math.min(minV.Y, c.Y), math.min(minV.Z, c.Z))
					maxV = Vector3.new(math.max(maxV.X, c.X), math.max(maxV.Y, c.Y), math.max(maxV.Z, c.Z))
				end
			end
		end
	end

	local size = maxV - minV
	local worldCenter = R:PointToWorldSpace((minV + maxV) * 0.5)
	local bboxCF = CFrame.new(worldCenter) * R
	return bboxCF, size
end

-- ==========================================================
-- FLOOR MATH
-- Layout bottom-up: bottomSlab | groundClear | [slab | clear] x (n-1) | topSlab
-- Returns: floorCount, groundClear, upperClear
--   * No requestedFloors  → height-driven: whole floors at FLOOR_CLEAR, the
--     ground floor absorbing all excess height.
--   * requestedFloors set → exactly that many uniform floors. The SLAB is fixed;
--     the floor-to-ceiling height is what gives (shrinks) to make them fit. It
--     won't pack tighter than MIN_FLOOR_CLEAR (then it drops floors and warns).
-- ==========================================================
local function computeFloors(totalHeight, requestedFloors)
	if requestedFloors and requestedFloors >= 1 then
		local n = math.floor(requestedFloors)
		local clear = (totalHeight - (n + 1) * SLAB_THICKNESS) / n
		if clear < MIN_FLOOR_CLEAR then
			local maxN = math.max(1, math.floor((totalHeight - SLAB_THICKNESS) / (MIN_FLOOR_CLEAR + SLAB_THICKNESS)))
			warn(string.format("[BuildingGenerator] Requested %d floors needs %.2fm clear (< %.2fm floor min); clamping to %d floors.",
				n, clear / METER, MIN_FLOOR_CLEAR / METER, maxN))
			n = maxN
			clear = (totalHeight - (n + 1) * SLAB_THICKNESS) / n
		end
		return n, clear, clear
	end

	local minHeight = 2 * SLAB_THICKNESS + FLOOR_CLEAR
	if totalHeight < minHeight then
		return 1, math.max(totalHeight - 2 * SLAB_THICKNESS, FLOOR_CLEAR * 0.5), FLOOR_CLEAR
	end
	local n = math.floor((totalHeight - 2 * SLAB_THICKNESS - FLOOR_CLEAR) / FLOOR_PITCH) + 1
	local groundClear = totalHeight - 2 * SLAB_THICKNESS - (n - 1) * FLOOR_PITCH
	return n, groundClear, FLOOR_CLEAR
end

-- ==========================================================
-- OCCUPANCY GRID
-- grid = { cell, nx, nz, minX, minZ, floors, ground, clearUpper,
--          occ      = { [k] = "0110..." },   -- LOOSE: solid at the floor base
--          occTight = { [k] = "0110..." } }  -- TIGHT: solid at floor base AND ceiling
-- occ char index for cell (i,j): (i-1)*nz + j   (i along local X, j along local Z)
-- Full-height things (office walls, furniture, ceiling lights) use TIGHT so they
-- can't poke out through a sloped/tapered face higher up the floor; flat things
-- (slabs, carpet, core) use LOOSE.
-- ==========================================================
local function lineBottom(grid, sy, k)
	local minBottom = -sy / 2
	if k <= 1 then return minBottom end
	local pitch = grid.clearUpper + SLAB_THICKNESS
	return minBottom + SLAB_THICKNESS + grid.ground + (k - 2) * pitch
end

local function clearOf(grid, k)
	return (k == 1) and grid.ground or grid.clearUpper
end

local function occGetFrom(layer, grid, k, i, j)
	if k < 1 or k > grid.floors then return false end
	if i < 1 or i > grid.nx or j < 1 or j > grid.nz then return false end
	local s = layer and layer[k]
	if not s then return false end
	local idx = (i - 1) * grid.nz + j
	return string.sub(s, idx, idx) == "1"
end

local function occGet(grid, k, i, j)
	return occGetFrom(grid.occ, grid, k, i, j)
end

local function occGetTight(grid, k, i, j)
	return occGetFrom(grid.occTight or grid.occ, grid, k, i, j)
end

local function cellCenterLocal(grid, i, j)
	return grid.minX + (i - 0.5) * grid.cell, grid.minZ + (j - 0.5) * grid.cell
end

local function occAtLocal(grid, k, x, z)
	local i = math.floor((x - grid.minX) / grid.cell) + 1
	local j = math.floor((z - grid.minZ) / grid.cell) + 1
	return occGet(grid, k, i, j)
end

local function occAtLocalTight(grid, k, x, z)
	local i = math.floor((x - grid.minX) / grid.cell) + 1
	local j = math.floor((z - grid.minZ) / grid.cell) + 1
	return occGetTight(grid, k, i, j)
end

-- Sample the model's solid volume into an occupancy grid.
local function sampleOccupancy(building, bboxCF, bboxSize, requestedFloors)
	local sx, sy, sz = bboxSize.X, bboxSize.Y, bboxSize.Z
	local floors, ground, clearUpper = computeFloors(sy, requestedFloors)

	local shellParts = {}
	for _, p in building:GetDescendants() do
		if p:IsA("BasePart") then table.insert(shellParts, p) end
	end

	local cell = math.max(GRID_MIN, math.max(sx, sz) / MAX_CELLS_AXIS)
	local nx = math.max(1, math.ceil(sx / cell))
	local nz = math.max(1, math.ceil(sz / cell))

	local grid = { cell = cell, nx = nx, nz = nz, minX = -sx / 2, minZ = -sz / 2,
		floors = floors, ground = ground, clearUpper = clearUpper, occ = {}, occTight = {} }

	-- A single upright block is exact geometry, not a collision sampling problem.
	-- Fill the logical layout grid completely; slab decomposition emits ONE part
	-- clipped to the actual box dimensions, including partial boundary cells.
	if #shellParts == 1 and shellParts[1]:IsA("Part")
		and shellParts[1].Shape == Enum.PartType.Block
		and math.abs(shellParts[1].CFrame.UpVector.Y) > 0.999999 then
		local full = string.rep("1", nx * nz)
		for k = 1, floors do grid.occ[k] = full; grid.occTight[k] = full end
		return grid
	end

	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = shellParts
	op.MaxParts = 1

	local probe = Instance.new("Part")
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = false
	probe.Transparency = 1
	probe.Parent = Workspace

	-- small probe biased to the cell centre so the interior never pokes OUT past
	-- a sloped/curved face
	local probeSide = math.max(1, cell * 0.5)

	local function solidAt(cx, cz, y)
		probe.CFrame = bboxCF * CFrame.new(cx, y, cz)
		return #Workspace:GetPartsInPart(probe, op) > 0
	end

	for k = 1, floors do
		local clear = clearOf(grid, k)
		local base = lineBottom(grid, sy, k) + SLAB_THICKNESS -- floor surface
		-- Sample just above the floor and RIGHT under the ceiling. LOOSE = solid at
		-- the base; TIGHT = solid at BOTH, so full-height objects (and the ceiling
		-- light strips, which hang flush with the ceiling) stay inside a sloped face
		-- for the whole floor height. yHigh is kept near the very top (0.95) because
		-- on an inward-leaning wall the silhouette keeps receding above 0.85 — a
		-- strip sampled at 0.85 still overhangs at the ceiling.
		local yLow  = base + clear * 0.15
		local yHigh = base + clear * 0.95
		-- thin probe so yHigh reads the silhouette right at the ceiling (and never
		-- bleeds up into the slab above)
		probe.Size = Vector3.new(probeSide, math.max(1, clear * 0.06), probeSide)
		local loose = table.create(nx * nz, "0")
		local tight = table.create(nx * nz, "0")
		for i = 1, nx do
			for j = 1, nz do
				local cx, cz = cellCenterLocal(grid, i, j)
				local lo = solidAt(cx, cz, yLow)
				local idx = (i - 1) * nz + j
				if lo then
					loose[idx] = "1"
					if solidAt(cx, cz, yHigh) then tight[idx] = "1" end
				end
			end
		end
		grid.occ[k] = table.concat(loose)
		grid.occTight[k] = table.concat(tight)
	end

	probe:Destroy()
	return grid
end

-- ==========================================================
-- RECTANGLE DECOMPOSITION  (greedy maximal rectangles over a cell matrix)
-- ==========================================================
-- Largest all-true rectangle in M[i][j] (i = 1..nx, j = 1..nz).
local function largestRect(M, nx, nz)
	local best = { area = 0 }
	local h = table.create(nz, 0)
	for i = 1, nx do
		for j = 1, nz do
			h[j] = M[i][j] and (h[j] + 1) or 0
		end
		-- largest rectangle in histogram h[1..nz], with a 0 sentinel at nz+1
		local stack = {} -- entries: { startCol, height }
		for j = 1, nz + 1 do
			local cur = (j <= nz) and h[j] or 0
			local startCol = j
			while #stack > 0 and stack[#stack].height >= cur do
				local top = table.remove(stack)
				local width = j - top.startCol
				local area = top.height * width
				if area > best.area then
					best = { area = area, i0 = i - top.height + 1, i1 = i,
						j0 = top.startCol, j1 = j - 1 }
				end
				startCol = top.startCol
			end
			if cur > 0 then table.insert(stack, { startCol = startCol, height = cur }) end
		end
	end
	return best
end

-- Decompose a boolean matrix into a small set of rectangles {i0,i1,j0,j1}.
local function decompose(M, nx, nz)
	-- work on a copy we can clear
	local C = {}
	local any = false
	for i = 1, nx do
		C[i] = {}
		for j = 1, nz do
			C[i][j] = M[i][j]
			if M[i][j] then any = true end
		end
	end
	local rects = {}
	while any do
		local r = largestRect(C, nx, nz)
		if r.area == 0 then break end
		table.insert(rects, r)
		for i = r.i0, r.i1 do
			for j = r.j0, r.j1 do C[i][j] = false end
		end
		any = false
		for i = 1, nx do
			for j = 1, nz do if C[i][j] then any = true break end end
			if any then break end
		end
	end
	return rects
end

-- Build a line matrix for the slab/floor at line k. The slab is floor k's floor
-- (occ[k], loose) UNION the ceiling cap for the floor below. The cap uses the
-- TIGHT lower-floor footprint so it doesn't overhang outward on a tapered face.
-- union=false (carpet) is just floor k.
local function lineMatrix(grid, k, union)
	local M = {}
	for i = 1, grid.nx do
		M[i] = {}
		for j = 1, grid.nz do
			local v = occGet(grid, k, i, j)
			if union then v = v or occGetTight(grid, k - 1, i, j) end
			M[i][j] = v
		end
	end
	return M
end

-- Local-space edges of a cell rectangle, clamped to the footprint.
local function rectLocalBounds(grid, sx, sz, r)
	local xMin = math.max(-sx / 2, grid.minX + (r.i0 - 1) * grid.cell)
	local xMax = math.min(sx / 2,  grid.minX + r.i1 * grid.cell)
	local zMin = math.max(-sz / 2, grid.minZ + (r.j0 - 1) * grid.cell)
	local zMax = math.min(sz / 2,  grid.minZ + r.j1 * grid.cell)
	return xMin, xMax, zMin, zMax
end

-- ==========================================================
-- CORE DECO (per floor)
-- ==========================================================
local function decorateCoreWalls(grid, k, bboxCF, cx, cz, coreX, coreZ, floorY, parent, rng)
	local decoFolder = ServerStorage:FindFirstChild(CORE_DECO_FOLDER)
	if not decoFolder then
		warn("[BuildingGenerator] ServerStorage." .. CORE_DECO_FOLDER .. " not found — skipping core deco.")
		return
	end
	local elevator = decoFolder:FindFirstChild("ElevatorDoor")
	local exitDoor = decoFolder:FindFirstChild("ExitSignDoor")
	local coreDoor = decoFolder:FindFirstChild("CoreDoor")
	local glass    = decoFolder:FindFirstChild("InteriorGlass")

	local longAxisX = coreX >= coreZ
	local walls = {
		{ normal = Vector3.new(0, 0, 1),  runDir = Vector3.new(1, 0, 0), runLen = coreX, off = coreZ / 2 },
		{ normal = Vector3.new(0, 0, -1), runDir = Vector3.new(1, 0, 0), runLen = coreX, off = coreZ / 2 },
		{ normal = Vector3.new(1, 0, 0),  runDir = Vector3.new(0, 0, 1), runLen = coreZ, off = coreX / 2 },
		{ normal = Vector3.new(-1, 0, 0), runDir = Vector3.new(0, 0, 1), runLen = coreZ, off = coreX / 2 },
	}
	local elevIdx = longAxisX and 1 or 3
	local exitIdx = longAxisX and 2 or 4

	-- Reserved along-intervals per wall side. Every placed deco records the span
	-- it occupies (+DECO_GAP), so later deco won't overlap it and office dividing
	-- walls can steer clear of all of them.
	local reserved = {}
	local function alongFree(i, lo, hi)
		local ivs = reserved[i]
		if ivs then
			for _, iv in ivs do
				if lo < iv.hi and hi > iv.lo then return false end
			end
		end
		return true
	end
	local function reserveAlong(i, center, halfW)
		reserved[i] = reserved[i] or {}
		table.insert(reserved[i], { lo = center - halfW, hi = center + halfW })
	end

	-- Try to place `template` flat on wall `i` at `alongOffset`. Fails (returns
	-- false, places nothing) if it would run past the wall ends, overlap deco
	-- already on this wall, or have no solid floor in front.
	local function placeOnWall(i, template, wall, alongOffset, yawOffsetDeg, rollDeg)
		if not template then return false end
		local tSize
		if template:IsA("Model") then
			local _, s = template:GetBoundingBox(); tSize = s
		else
			tSize = template.Size
		end
		local halfW = tSize.X / 2
		-- stay within the wall run
		if math.abs(alongOffset) + halfW > wall.runLen / 2 then return false end
		-- don't collide with deco already placed on this wall
		if not alongFree(i, alongOffset - halfW - DECO_GAP, alongOffset + halfW + DECO_GAP) then return false end
		-- need solid floor in front of the wall for the deco to stand on
		local frontX = cx + wall.runDir.X * alongOffset + wall.normal.X * (wall.off + tSize.Z / 2 + 1)
		local frontZ = cz + wall.runDir.Z * alongOffset + wall.normal.Z * (wall.off + tSize.Z / 2 + 1)
		if not occAtLocal(grid, k, frontX, frontZ) then return false end
		local localPos = Vector3.new(cx, floorY, cz)
			+ wall.runDir * alongOffset
			+ wall.normal * (wall.off + CORE_WALL_THICK / 2 + tSize.Z / 2)
		local worldPos = bboxCF:PointToWorldSpace(localPos)
		local rotCF = (bboxCF - bboxCF.Position)
			* CFrame.lookAt(Vector3.zero, wall.normal)
			* CFrame.Angles(0, math.rad(DECO_YAW_OFFSET + (yawOffsetDeg or 0)), math.rad(rollDeg or 0))
		placeClone(template, worldPos, rotCF, parent)
		reserveAlong(i, alongOffset, halfW + DECO_GAP)
		return true
	end

	local elevSideIndex, elevHalf, exitSideIndex, exitHalf
	for i, wall in walls do
		if i == elevIdx and elevator then
			-- EXACTLY two elevator doors, side by side, centred on the wall.
			local size = templateSize(CORE_DECO_FOLDER, "ElevatorDoor")
			local w = size and size.X or 2 * METER
			local gap = 0.25
			local total = 2 * w + gap
			if total <= wall.runLen then
				placeOnWall(i, elevator, wall, -(w + gap) / 2, nil, ELEVATOR_ROLL)
				placeOnWall(i, elevator, wall,  (w + gap) / 2, nil, ELEVATOR_ROLL)
				elevSideIndex, elevHalf = i, total / 2
			else
				placeOnWall(i, elevator, wall, 0, nil, ELEVATOR_ROLL)
				elevSideIndex, elevHalf = i, w / 2
			end
		elseif i == exitIdx and exitDoor then
			if placeOnWall(i, exitDoor, wall, 0, nil, EXIT_SIGN_ROLL) then
				-- reserve this spot so an office dividing wall never cuts the sign
				local size = templateSize(CORE_DECO_FOLDER, "ExitSignDoor")
				exitSideIndex, exitHalf = i, (size and size.X or 2 * METER) / 2
			end
		elseif coreDoor then
			placeOnWall(i, coreDoor, wall, (rng:NextNumber() - 0.5) * wall.runLen * 0.4)
		end
		-- InteriorGlass fills the other walls, never the elevator wall. Each panel
		-- skips itself if it would overlap the door/sign already on the wall.
		if glass and i ~= elevIdx and wall.runLen > 6 * METER then
			for _, frac in { -0.33, 0.33 } do
				if rng:NextNumber() < 0.7 then
					placeOnWall(i, glass, wall, wall.runLen * frac)
				end
			end
		end
	end

	return elevSideIndex, elevHalf, exitSideIndex, exitHalf, reserved
end

-- ==========================================================
-- FURNITURE (per bay)
-- ==========================================================
-- kind: nil = normal bay (empty / prop / main mix); "elevator" = the elevator
-- room (kept empty, maybe a single plant).
-- smallBuilding: prioritise the office pieces — skip the empty/prop rolls so the
-- few bays a small building has go to GroupOffice/ConferenceTable.
local function placeFurnitureInBay(bayCenterLocal, bayW, bayD, faceNormal, bboxCF, floorY, parent, rng, budget, kind, smallBuilding)
	local furnFolder = ServerStorage:FindFirstChild(FURNITURE_FOLDER)
	if not furnFolder then return end

	local rotCF = (bboxCF - bboxCF.Position)
		* CFrame.lookAt(Vector3.zero, -faceNormal)
		* CFrame.Angles(0, math.rad(FURNITURE_YAW_OFFSET), 0)

	-- extraYaw (deg) rotates the piece about Y so a long item can lie along the
	-- bay's DEEP axis instead of its narrow (along-wall) axis. scale (<=1) shrinks
	-- it to fit a tight bay.
	local function placeNamed(name, extraYaw, scale)
		local template = furnFolder:FindFirstChild(name)
		if not template then return false end
		local cf = rotCF
		if extraYaw and extraYaw ~= 0 then cf = cf * CFrame.Angles(0, math.rad(extraYaw), 0) end
		local roll = FURNITURE_ROLL[name]
		if roll then cf = cf * CFrame.Angles(0, 0, math.rad(roll)) end
		local worldPos = bboxCF:PointToWorldSpace(bayCenterLocal + Vector3.new(0, floorY, 0))
		placeClone(template, worldPos, cf, parent, scale)
		return true
	end

	local function placeProp()
		local name = PROP_FURNITURE[rng:NextInteger(1, #PROP_FURNITURE)]
		local size = templateSize(FURNITURE_FOLDER, name)
		if size and size.X + 1 <= bayW and size.Z + 1 <= bayD then
			placeNamed(name)
		end
	end

	-- Elevator room: keep it open; maybe one plant.
	if kind == "elevator" then
		if rng:NextNumber() < 0.5 then
			local size = templateSize(FURNITURE_FOLDER, "LowPolyPlant")
			if size and size.X + 1 <= bayW and size.Z + 1 <= bayD then
				placeNamed("LowPolyPlant")
			end
		end
		return
	end

	if budget.count >= MAX_FURNITURE_PER_FLOOR then return end

	-- Small buildings skip the empty/prop rolls so their scarce bays go to offices.
	if not smallBuilding then
		local roll = rng:NextNumber()
		if roll < BAY_EMPTY_CHANCE then
			return                                          -- empty
		elseif roll < BAY_EMPTY_CHANCE + BAY_PROP_CHANCE then
			placeProp()                                     -- just a prop
			return
		end
	end

	-- MAIN: 50/50 GroupOffice vs ConferenceTable. The base rotCF maps the template
	-- axes DIFFERENTLY per wall side (lookAt(-faceNormal) sends template +X to bbox
	-- +X on a Z-normal wall but to bbox +Z on an X-normal wall), so we can't just
	-- compare size.X to bayW. Instead compute the ACTUAL bbox-axis footprint at
	-- yaw 0 and yaw 90 and compare that. Returns (yaw, scale) that fits, or nil;
	-- small buildings may shrink down to MIN_FURNITURE_SCALE to make it fit.
	local rotOnly = rotCF - rotCF.Position
	local function footprintAABB(yaw, size)
		local R = rotOnly * CFrame.Angles(0, math.rad(yaw), 0)
		local fx = math.abs((R * Vector3.new(size.X, 0, 0)).X) + math.abs((R * Vector3.new(0, 0, size.Z)).X)
		local fz = math.abs((R * Vector3.new(size.X, 0, 0)).Z) + math.abs((R * Vector3.new(0, 0, size.Z)).Z)
		return fx + 2 * FURNITURE_MARGIN, fz + 2 * FURNITURE_MARGIN
	end
	-- Returns (yaw, scale) where scale is RELATIVE to the template (= the optional
	-- OFFICE_TARGET_LONG base scale, times any small-building shrink-to-fit).
	local function solveFit(name)
		local size = templateSize(FURNITURE_FOLDER, name)
		if size == nil then return nil end
		local base = (OFFICE_TARGET_LONG and OFFICE_TARGET_LONG / math.max(size.X, size.Z)) or 1
		size = size * base
		local best
		for _, yaw in { 0, 90 } do
			local fx, fz = footprintAABB(yaw, size)
			if fx <= bayW and fz <= bayD then
				return yaw, base                           -- fits at target size
			elseif smallBuilding then
				local s = math.min(bayW / fx, bayD / fz)   -- extra shrink to fit this orientation
				if not best or s > best.s then best = { yaw = yaw, s = s } end
			end
		end
		if best and best.s >= MIN_FURNITURE_SCALE then return best.yaw, base * best.s end
		return nil
	end
	local confYaw, confScale = solveFit("ConferenceTable")
	local grpYaw, grpScale   = solveFit("GroupOffice")
	local chosen, yaw, scale
	if confYaw ~= nil and grpYaw ~= nil then
		if rng:NextNumber() < 0.5 then chosen, yaw, scale = "ConferenceTable", confYaw, confScale
		else chosen, yaw, scale = "GroupOffice", grpYaw, grpScale end
	elseif confYaw ~= nil then chosen, yaw, scale = "ConferenceTable", confYaw, confScale
	elseif grpYaw ~= nil then chosen, yaw, scale = "GroupOffice", grpYaw, grpScale
	end
	if chosen then
		if placeNamed(chosen, yaw, scale) then budget.count += 1 end
	else
		placeProp()                                     -- too small for either → prop
	end
end

-- ==========================================================
-- CORE + OFFICES for one floor (offices clipped to the sampled silhouette)
-- ==========================================================
local function generateCoreFloor(grid, k, bboxCF, localCF, floorModel, cx, cz, coreX, coreZ, floorY, wallH, rng, budget, smallBuilding, slotSpacing, maxRingDepth, structuralOnly)
	local wallY = floorY + wallH / 2

	local function corePart(name, size, ox, oz)
		local p = makePart(name, size, localCF(cx + ox, wallY, cz + oz), floorModel)
		CollectionService:AddTag(p, CORE_TAG)
		return p
	end

	corePart("CoreWallFront", Vector3.new(coreX + CORE_WALL_THICK, wallH, CORE_WALL_THICK), 0, coreZ / 2)
	corePart("CoreWallBack",  Vector3.new(coreX + CORE_WALL_THICK, wallH, CORE_WALL_THICK), 0, -coreZ / 2)
	corePart("CoreWallRight", Vector3.new(CORE_WALL_THICK, wallH, coreZ - CORE_WALL_THICK), coreX / 2, 0)
	corePart("CoreWallLeft",  Vector3.new(CORE_WALL_THICK, wallH, coreZ - CORE_WALL_THICK), -coreX / 2, 0)
	corePart("CoreDividerX", Vector3.new(coreX - CORE_WALL_THICK, wallH, CORE_WALL_THICK), 0, 0)
	corePart("CoreDividerZ", Vector3.new(CORE_WALL_THICK, wallH, coreZ - CORE_WALL_THICK), 0, 0)
	if structuralOnly then return end

	local elevSideIndex, elevHalf, _exitSideIndex, _exitHalf, decoReserved =
		decorateCoreWalls(grid, k, bboxCF, cx, cz, coreX, coreZ, floorY, floorModel, rng)
	local elevReserve = elevHalf and (elevHalf + grid.cell) or 0 -- along-range kept clear for the elevator room

	-- true if an office wall of thickness PROTRUDE_THICK centred at `along` on side
	-- `sIdx` would overlap ANY core-wall deco placed there (door/sign/glass/elevator)
	local function alongHitsDeco(sIdx, along)
		local ivs = decoReserved and decoReserved[sIdx]
		if not ivs then return false end
		local lo, hi = along - PROTRUDE_THICK / 2, along + PROTRUDE_THICK / 2
		for _, iv in ivs do
			if lo < iv.hi and hi > iv.lo then return true end
		end
		return false
	end

	local sides = {
		{ normal = Vector3.new(0, 0, 1),  runDir = Vector3.new(1, 0, 0), runLen = coreX, wallOff = coreZ / 2 },
		{ normal = Vector3.new(0, 0, -1), runDir = Vector3.new(1, 0, 0), runLen = coreX, wallOff = coreZ / 2 },
		{ normal = Vector3.new(1, 0, 0),  runDir = Vector3.new(0, 0, 1), runLen = coreZ, wallOff = coreX / 2 },
		{ normal = Vector3.new(-1, 0, 0), runDir = Vector3.new(0, 0, 1), runLen = coreZ, wallOff = coreX / 2 },
	}

	-- How deep the solid footprint runs outward from the core wall at a given
	-- along-offset, by marching across the occupancy grid (this is what makes
	-- offices follow the silhouette — short on a wedge's sloped side, etc.).
	local function ringDepthAt(side, along)
		local baseX = cx + side.runDir.X * along + side.normal.X * (side.wallOff + CORE_WALL_THICK / 2)
		local baseZ = cz + side.runDir.Z * along + side.normal.Z * (side.wallOff + CORE_WALL_THICK / 2)
		local d = 0
		while d < maxRingDepth do
			local px = baseX + side.normal.X * (d + grid.cell * 0.5)
			local pz = baseZ + side.normal.Z * (d + grid.cell * 0.5)
			if not occAtLocalTight(grid, k, px, pz) then break end -- TIGHT: walls are full-height
			d += grid.cell
		end
		return d
	end

	for sIdx, side in sides do
		local frontOff = side.wallOff + CORE_WALL_THICK / 2 -- core's OUTER face on this side
		local slots = math.max(1, math.floor(side.runLen / slotSpacing))
		local posts = {} -- { along, depth } at slot lines deep enough for offices

		-- is this along-offset inside the reserved elevator room?
		local function inElevReserve(along)
			return sIdx == elevSideIndex and math.abs(along) <= elevReserve
		end

		for s = 0, slots do
			local along = -side.runLen / 2 + side.runLen * s / slots
			local depth = ringDepthAt(side, along)
			if depth >= MIN_RING_DEPTH then
				table.insert(posts, { along = along, depth = depth })
				-- interior posts get a dividing wall STUCK TO THE CORE (inner end
				-- flush with the core's outer face — no gap) running out toward the
				-- exterior. Pull back one cell so the wall can't poke out past a
				-- sloped/curved silhouette (sampling overshoots by up to a cell).
				-- Never put a wall inside the elevator room (it'd split the doors)
				-- or where it would cut through any core-wall deco.
				if s > 0 and s < slots and not inElevReserve(along) and not alongHitsDeco(sIdx, along)
					and rng:NextNumber() < PROTRUDE_CHANCE then
					local protrudeLen = depth - grid.cell
					if protrudeLen >= 2 then
						local center = side.runDir * along
							+ side.normal * (frontOff + protrudeLen / 2)
						local size
						if side.runDir.X ~= 0 then
							size = Vector3.new(PROTRUDE_THICK, wallH, protrudeLen)
						else
							size = Vector3.new(protrudeLen, wallH, PROTRUDE_THICK)
						end
						CollectionService:AddTag(
							makePart("OfficeWall", size, localCF(cx + center.X, wallY, cz + center.Z), floorModel),
							NO_CSG_TAG)
					end
				end
			end
		end

		for p = 1, #posts - 1 do
			local a, b = posts[p], posts[p + 1]
			local usable = math.min(a.depth, b.depth) - grid.cell -- conservative interior depth
			local bayW = (b.along - a.along) - PROTRUDE_THICK - 1
			local bayD = usable - 2 * FURNITURE_MARGIN
			if bayW > 2 * METER and bayD > MIN_RING_DEPTH * 0.5 then
				local mid = (a.along + b.along) / 2
				local centerLocal = Vector3.new(cx, 0, cz)
					+ side.runDir * mid
					+ side.normal * (frontOff + usable / 2)
				local w, d
				if side.runDir.X ~= 0 then w, d = bayW, bayD else w, d = bayD, bayW end
				local kind = inElevReserve(mid) and "elevator" or nil
				placeFurnitureInBay(centerLocal, w, d, side.normal, bboxCF, floorY, floorModel, rng, budget, kind, smallBuilding)
			end
		end
	end
end

-- ==========================================================
-- BUILDING GENERATION
-- ==========================================================
local BuildingGenerator = {}

local function loadStoredGrid(building)
	local raw = building:GetAttribute("InteriorGrid")
	if not raw then return nil end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or not t then return nil end
	return { cell = t.cell, nx = t.nx, nz = t.nz, minX = t.minX, minZ = t.minZ,
		floors = t.floors, ground = t.ground, clearUpper = t.clearUpper or FLOOR_CLEAR,
		occ = t.occ, occTight = t.occTight or t.occ }
end

local function storeGrid(building, grid)
	building:SetAttribute("InteriorGrid", HttpService:JSONEncode({
		cell = grid.cell, nx = grid.nx, nz = grid.nz, minX = grid.minX, minZ = grid.minZ,
		floors = grid.floors, ground = grid.ground, clearUpper = grid.clearUpper,
		occ = grid.occ, occTight = grid.occTight,
	}))
end

-- requestedFloors (optional): generate EXACTLY this many floors (slab fixed,
-- floor-to-ceiling height gives). If omitted, floors are derived from the
-- model's height at the preset FLOOR_CLEAR.
function BuildingGenerator.Generate(building, requestedFloors)
	if not building:IsA("Model") then return false end
	requestedFloors = requestedFloors or building:GetAttribute("RequestedFloors")
	if requestedFloors ~= nil then
		assert(type(requestedFloors) == "number" and requestedFloors == requestedFloors
			and requestedFloors < math.huge and requestedFloors >= 1
			and requestedFloors % 1 == 0, "RequestedFloors must be a finite positive integer")
	end
	if not building.Name:match("^Building") then
		warn("[BuildingGenerator]", building.Name, "does not start with 'Building' — CSG destruction will NOT work on it.")
	end
	if building:FindFirstChild("Interior") then
		print("[BuildingGenerator] Skipping", building:GetFullName(), "(Interior already exists)")
		return false
	end
	if building:GetAttribute("SmoothMassing") then
		error("Saved polygon building is missing its Interior; restore its archived Interior before regenerating")
	end

	-- Sample the live shell, or reload a stored grid (regen after shell deletion)
	local bboxCF, bboxSize, grid
	local hasParts = building:FindFirstChildWhichIsA("BasePart", true) ~= nil
	if hasParts then
		bboxCF, bboxSize = computeOrientedBox(building) -- yaw-aligned, NOT the world AABB
		grid = sampleOccupancy(building, bboxCF, bboxSize, requestedFloors)
		building:SetAttribute("InteriorBBoxCFrame", bboxCF)
		building:SetAttribute("InteriorBBoxSize", bboxSize)
		storeGrid(building, grid)
	else
		bboxCF = building:GetAttribute("InteriorBBoxCFrame")
		bboxSize = building:GetAttribute("InteriorBBoxSize")
		grid = loadStoredGrid(building)
		if not bboxCF or not bboxSize or not grid then
			warn("[BuildingGenerator]", building:GetFullName(), "has no parts and no stored grid — cannot generate.")
			return false
		end
	end

	local sx, sy, sz = bboxSize.X, bboxSize.Y, bboxSize.Z
	local structuralOnly = building:GetAttribute("StructuralOnly") == true
	local floorCount = grid.floors
	local groundClear = grid.ground
	local smallBuilding = sx < SMALL_BUILDING_MAX and sz < SMALL_BUILDING_MAX
	local rng = Random.new(buildingSeed(bboxCF.Position))

	-- Derive bay spacing / ring depth from the LIVE office footprints so that
	-- resizing ConferenceTable / GroupOffice automatically widens the bays, the
	-- ring, and the core to fit them at FULL size (no silent scale-down). officeLong
	-- = the longest footprint edge across both pieces, officeShort = the longest of
	-- their short edges; a bay must be >= officeLong along one axis and >= officeShort
	-- on the other (rotation picks which).
	local officeLong, officeShort = 0, 0
	for _, n in { "ConferenceTable", "GroupOffice" } do
		local s = templateSize(FURNITURE_FOLDER, n)
		if s then
			local sc = OFFICE_TARGET_LONG and (OFFICE_TARGET_LONG / math.max(s.X, s.Z)) or 1
			officeLong  = math.max(officeLong, math.max(s.X, s.Z) * sc)
			officeShort = math.max(officeShort, math.min(s.X, s.Z) * sc)
		end
	end
	-- bay width = slot - PROTRUDE_THICK - 1, so size the slot for officeLong + margins
	local slotSpacing  = math.max(PROTRUDE_SLOT, officeLong + 2 * FURNITURE_MARGIN + PROTRUDE_THICK + 1)
	-- ringDepthAt subtracts a cell and 2 margins downstream, so add that headroom
	local maxRingDepth = math.max(MAX_RING_DEPTH, officeShort + 2 * FURNITURE_MARGIN + grid.cell)

	-- Empty-volume guard (hollow shells sample to nothing)
	local anyOcc = false
	for k = 1, floorCount do
		if grid.occ[k] and string.find(grid.occ[k], "1", 1, true) then anyOcc = true break end
	end
	if not anyOcc then
		warn("[BuildingGenerator]", building.Name, "sampled empty — is the shell solid? (a hollow wall box has no interior volume).")
		return false
	end

	local interior = Instance.new("Model")
	interior.Name = "Interior"
	local function localCF(x, y, z) return bboxCF * CFrame.new(x, y, z) end

	local floorModels = {}
	local function floorModelFor(k)
		if not floorModels[k] then
			local m = Instance.new("Model")
			m.Name = (k == floorCount + 1) and "Roof" or ("Floor" .. k)
			m.Parent = interior
			floorModels[k] = m
		end
		return floorModels[k]
	end

	-- --- Core placement: biggest solid rectangle of the ground floor. Computed
	-- BEFORE slabs/lights so lights can skip the core interior.
	local groundRect = largestRect(lineMatrix(grid, 1, false), grid.nx, grid.nz)
	local coreX, coreZ, ccx, ccz, coreTopFloor
	if groundRect.area > 0 then
		local xMin, xMax, zMin, zMax = rectLocalBounds(grid, sx, sz, groundRect)
		local rw, rd = xMax - xMin, zMax - zMin
		ccx, ccz = (xMin + xMax) / 2, (zMin + zMax) / 2
		-- small buildings (both shell axes under SMALL_BUILDING_MAX) get a
		-- different core ratio
		local ratio = smallBuilding and SMALL_CORE_RATIO or CORE_RATIO
		coreX = math.clamp(math.max(rw * ratio, rw - 2 * maxRingDepth, math.min(MIN_CORE_SIZE, rw * 0.5)), 2, math.max(2, rw - 2))
		coreZ = math.clamp(math.max(rd * ratio, rd - 2 * maxRingDepth, math.min(MIN_CORE_SIZE, rd * 0.5)), 2, math.max(2, rd - 2))
		if rw <= 4 or rd <= 4 then
			coreX = nil
		else
			-- core spans floors whose footprint still fully covers it
			coreTopFloor = 0
			for k = 1, floorCount do
				local covered = occAtLocalTight(grid, k, ccx - coreX / 2 + 0.5, ccz - coreZ / 2 + 0.5)
					and occAtLocalTight(grid, k, ccx + coreX / 2 - 0.5, ccz - coreZ / 2 + 0.5)
					and occAtLocalTight(grid, k, ccx - coreX / 2 + 0.5, ccz + coreZ / 2 - 0.5)
					and occAtLocalTight(grid, k, ccx + coreX / 2 - 0.5, ccz + coreZ / 2 - 0.5)
				if covered then coreTopFloor = k else break end
			end
		end
	end
	if not coreX then
		warn("[BuildingGenerator]", building.Name, "footprint too small for a core.")
	end
	-- true when local (x,z) is inside the core footprint on a floor that has the core
	local function insideCore(k, x, z)
		return coreX ~= nil and k <= coreTopFloor
			and math.abs(x - ccx) < coreX / 2 and math.abs(z - ccz) < coreZ / 2
	end

	-- --- Slabs (floor k union floor k-1), carpet + lights (floor k only)
	for k = 1, floorCount + 1 do
		-- slab line: every cell that is a floor here OR a ceiling for below
		local slabRects = decompose(lineMatrix(grid, k, true), grid.nx, grid.nz)
		local model = (#slabRects > 0) and floorModelFor(k) or nil
		for _, r in slabRects do
			local xMin, xMax, zMin, zMax = rectLocalBounds(grid, sx, sz, r)
			local slab = makePart("Slab", Vector3.new(xMax - xMin, SLAB_THICKNESS, zMax - zMin),
				localCF((xMin + xMax) / 2, lineBottom(grid, sy, k) + SLAB_THICKNESS / 2, (zMin + zMax) / 2), model)
			applyCeilingMaterial(slab)
		end

		if k <= floorCount and not structuralOnly then
			local floorY = lineBottom(grid, sy, k) + SLAB_THICKNESS
			local carpetRects = decompose(lineMatrix(grid, k, false), grid.nx, grid.nz)
			for _, r in carpetRects do
				local xMin, xMax, zMin, zMax = rectLocalBounds(grid, sx, sz, r)
				local carpet = makePart("Carpet", Vector3.new(xMax - xMin - 0.2, CARPET_THICK, zMax - zMin - 0.2),
					localCF((xMin + xMax) / 2, floorY + CARPET_THICK / 2, (zMin + zMax) / 2), floorModelFor(k))
				applyCarpetMaterial(carpet)
				carpet.CanCollide = false
				CollectionService:AddTag(carpet, NO_CSG_TAG)
			end

			-- Lights on a grid. Two things keep a strip from poking past a wall:
			--   1. occGetTight gate — the cell must be solid at the ceiling (handles
			--      a genuinely tapered/stepped silhouette).
			--   2. CLAMP to the box — the occupancy grid overshoots the real box on
			--      the far side (nx*cell > sx, plus the probe's own width), so a
			--      boundary cell centre can sit at/over the wall and the strip would
			--      hang out. Clamping the draw position so the whole footprint stays
			--      inside the box fixes it regardless of cell size (the per-corner
			--      occupancy test is useless here: at cell ~10 studs the corners land
			--      in the SAME cell). For a perfect prism the box IS the wall.
			local ceilY = lineBottom(grid, sy, k + 1) - LIGHT_SIZE.Y / 2
			local step = math.max(1, math.floor(LIGHT_SPACING / grid.cell))
			local dxMax = math.max(0, sx / 2 - LIGHT_SIZE.X / 2 - 0.5) -- keep strip inside the box (+inset)
			local dzMax = math.max(0, sz / 2 - LIGHT_SIZE.Z / 2 - 0.5)
			for i = math.ceil(step / 2), grid.nx, step do
				for j = math.ceil(step / 2), grid.nz, step do
					local lx, lz = cellCenterLocal(grid, i, j)
					if occGetTight(grid, k, i, j)
						and not insideCore(k, lx, lz) -- no lights inside the core
					then
						local px = math.clamp(lx, -dxMax, dxMax)
						local pz = math.clamp(lz, -dzMax, dzMax)
						local strip = makePart("LightStrip", LIGHT_SIZE, localCF(px, ceilY, pz), floorModelFor(k))
						strip.Material = Enum.Material.Neon
						strip.Color = LIGHT_COLOR
						strip.CanCollide = false
						CollectionService:AddTag(strip, NO_CSG_TAG)
						local light = Instance.new("SurfaceLight")
						light.Face = Enum.NormalId.Bottom
						light.Brightness = LIGHT_BRIGHTNESS
						light.Range = LIGHT_RANGE
						light.Color = LIGHT_COLOR
						light.Shadows = false
						light.Parent = strip
					end
				end
			end
		end
	end

	-- --- Per-floor content
	for k = 1, floorCount do
		local floorY = lineBottom(grid, sy, k) + SLAB_THICKNESS
		local wallH = lineBottom(grid, sy, k + 1) - floorY
		local budget = { count = 0 }
		if coreX and k <= coreTopFloor then
			generateCoreFloor(grid, k, bboxCF, localCF, floorModelFor(k), ccx, ccz, coreX, coreZ, floorY, wallH, rng, budget, smallBuilding, slotSpacing, maxRingDepth, structuralOnly)
		elseif not structuralOnly then
			-- no core on this floor: sprinkle a little furniture in the largest room
			local r = largestRect(lineMatrix(grid, k, false), grid.nx, grid.nz)
			if r.area > 0 then
				local xMin, xMax, zMin, zMax = rectLocalBounds(grid, sx, sz, r)
				placeFurnitureInBay(Vector3.new((xMin + xMax) / 2, 0, (zMin + zMax) / 2),
					(xMax - xMin) * 0.6, (zMax - zMin) * 0.6, Vector3.new(0, 0, 1),
					bboxCF, floorY, floorModelFor(k), rng, budget, nil, smallBuilding)
			end
		end
	end

	interior.Parent = building
	building:SetAttribute("GeneratedFloors", floorCount)

	-- Core metadata for future collapse scripts (world-space column)
	if coreX and coreTopFloor and coreTopFloor >= 1 then
		local coreBot = lineBottom(grid, sy, 1)
		local coreTop = lineBottom(grid, sy, coreTopFloor + 1) + SLAB_THICKNESS
		building:SetAttribute("CoreCFrame", localCF(ccx, (coreBot + coreTop) / 2, ccz))
		building:SetAttribute("CoreSize", Vector3.new(coreX, coreTop - coreBot, coreZ))
	else
		building:SetAttribute("CoreCFrame", nil)
		building:SetAttribute("CoreSize", nil)
	end

	-- Shell handling. By default KEEP_SHELL leaves the original shell part(s)
	-- completely untouched (easy to undo / move / re-run the script). Set
	-- KEEP_SHELL = false to carve the model down to just its interior.
	if not KEEP_SHELL then
		for _, p in building:GetDescendants() do
			if p:IsA("BasePart") and not p:IsDescendantOf(interior) then
				p:Destroy()
			end
		end
		for _, child in building:GetChildren() do
			if child ~= interior and child:IsA("Model") and not child:FindFirstChildWhichIsA("BasePart", true) then
				child:Destroy()
			end
		end
	end

	local confSz = templateSize(FURNITURE_FOLDER, "ConferenceTable")
	local grpSz  = templateSize(FURNITURE_FOLDER, "GroupOffice")
	print(string.format("[BuildingGenerator v12] %s%s: %d floors, grid %dx%d @ %.1f, core %s | ConferenceTable=%s GroupOffice=%s target=%s -> slot=%.0f ringMax=%.0f",
		building.Name, smallBuilding and " [small]" or "", floorCount, grid.nx, grid.nz, grid.cell,
		coreX and string.format("%.0fx%.0f x%d floors", coreX, coreZ, coreTopFloor or 0) or "none",
		confSz and string.format("%.0fx%.0f", confSz.X, confSz.Z) or "?",
		grpSz and string.format("%.0fx%.0f", grpSz.X, grpSz.Z) or "?",
		OFFICE_TARGET_LONG and string.format("%.0f", OFFICE_TARGET_LONG) or "off",
		slotSpacing, maxRingDepth))
	return true
end

-- Exact box input for imported massing. No retained solid shell obscures it.
-- The grid is used for core/furniture layout, never for the visible boundary.
function BuildingGenerator.GenerateBox(building, cf, size, requestedFloors)
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	assert(not building:FindFirstChildWhichIsA("BasePart", true), "GenerateBox expects an empty model")
	assert(math.abs(cf.UpVector.Y) > 0.999999, "Box frame must be upright")
	assert(size.X > 0 and size.Z > 0 and size.Y >= 2 * SLAB_THICKNESS + FLOOR_CLEAR, "Box is too small")
	requestedFloors = requestedFloors or building:GetAttribute("RequestedFloors")
	assert(requestedFloors == nil or (type(requestedFloors) == "number" and requestedFloors >= 1
		and requestedFloors < math.huge and requestedFloors % 1 == 0), "Invalid floor count")
	local floors, ground, clear = computeFloors(size.Y, requestedFloors)
	local cell = math.max(GRID_MIN, math.max(size.X, size.Z) / MAX_CELLS_AXIS)
	local nx, nz = math.ceil(size.X / cell), math.ceil(size.Z / cell)
	local full = string.rep("1", nx * nz)
	local grid = {cell=cell,nx=nx,nz=nz,minX=-size.X/2,minZ=-size.Z/2,
		floors=floors,ground=ground,clearUpper=clear,occ={},occTight={}}
	for k = 1, floors do grid.occ[k] = full; grid.occTight[k] = full end
	building:SetAttribute("InteriorBBoxCFrame", cf)
	building:SetAttribute("InteriorBBoxSize", size)
	building:SetAttribute("FootprintMode", "ExactBox")
	storeGrid(building, grid)
	return BuildingGenerator.Generate(building, requestedFloors)
end

function BuildingGenerator.Regenerate(building, requestedFloors)
	if building:GetAttribute("SourceSlicePlan")
		or building:GetAttribute("FootprintMode") == "ExplicitSourceSlices" then
		assert(requestedFloors == nil, "Source-slice floor counts come from explicit levels, not RequestedFloors")
		return require(script.Parent.SourceSliceBuilder).Regenerate(building)
	end
	if building:GetAttribute("SmoothMassing") then
		return require(script.Parent.SmoothBuildingBuilder).Regenerate(building, requestedFloors)
	end
	local existing = building:FindFirstChild("Interior")
	local hasShell = false
	for _, p in building:GetDescendants() do
		if p:IsA("BasePart") and not (existing and p:IsDescendantOf(existing)) then hasShell = true; break end
	end
	assert(hasShell or loadStoredGrid(building), "No shell or saved grid; cannot regenerate")
	assert(hasShell or requestedFloors == nil, "Changing floor count requires the original shell/triangle resampling")
	if existing then existing:Destroy() end
	-- Imported interiors have no solid shell; their sampled grid IS the source.
	if hasShell then building:SetAttribute("InteriorGrid", nil) end
	return BuildingGenerator.Generate(building, requestedFloors)
end

-- Traverse grouping folders/models, but stop at each Building model so its
-- component models and an existing Interior are never treated as buildings.
local function collectBuildings(folder, result)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child.Name:match("^Building") then
			table.insert(result, child)
		elseif child:IsA("Folder") or child:IsA("Model") then
			collectBuildings(child, result)
		end
	end
end

-- GenerateAll(folder?, requestedFloors?, dryRun?): an explicit floor count
-- overrides each model's RequestedFloors attribute; otherwise use its height.
-- dryRun=true inventories candidates without modifying the map. One failed
-- building does not prevent the rest of the district from being generated.
function BuildingGenerator.GenerateAll(folder, requestedFloors, dryRun)
	assert(not game:GetService("RunService"):IsRunning(), "GenerateAll is an edit-time tool; stop playtest first")
	folder = folder or Workspace:FindFirstChild("Buildings")
	if not folder then
		warn("[BuildingGenerator] No Workspace.Buildings folder found.")
		return
	end
	local buildings = {}
	collectBuildings(folder, buildings)
	table.sort(buildings, function(a, b) return a:GetFullName() < b:GetFullName() end)
	local report = { generated = 0, skipped = 0, failed = 0, ready = 0, entries = {} }
	for _, building in buildings do
		local entry = { path = building:GetFullName(), requestedFloors = requestedFloors or building:GetAttribute("RequestedFloors") }
		if building:FindFirstChild("Interior") then
			entry.status, entry.reason = "skipped", "Interior already exists"
		elseif building:GetAttribute("SkipGeneration") == true then
			entry.status, entry.reason = "skipped", "SkipGeneration attribute"
		else
			local primitives, meshes = 0, 0
			for _, part in building:GetDescendants() do
				if part:IsA("MeshPart") then meshes += 1
				elseif part:IsA("BasePart") then primitives += 1 end
			end
			if meshes > 0 and primitives == 0 then
				entry.status, entry.reason = "skipped", "Mesh-only reference: requires an individual solid building shell"
			elseif dryRun then
				entry.status = "ready"
			else
				local ok, result = pcall(BuildingGenerator.Generate, building, requestedFloors)
				if ok and result then
					entry.status = "generated"
					entry.floors = building:GetAttribute("GeneratedFloors")
				else
					entry.status = "failed"
					entry.reason = ok and "No usable solid volume or stored grid; see Output" or tostring(result)
				end
			end
		end
		report[entry.status] += 1
		table.insert(report.entries, entry)
		print(string.format("[BuildingGenerator] %s: %s %s", entry.path, entry.status, entry.reason or ""))
		task.wait() -- keep Studio responsive between buildings
	end
	print(string.format("[BuildingGenerator] Done. Generated %d, skipped %d, failed %d, ready %d.",
		report.generated, report.skipped, report.failed, report.ready))
	return report
end

return BuildingGenerator
