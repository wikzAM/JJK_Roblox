-- HitHandler.server.luau
-- PLACE IN: ServerScriptService

local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")
local GeometryService   = game:GetService("GeometryService")
local HttpService       = game:GetService("HttpService")


-- ==========================================================
-- TUNABLES
-- ==========================================================
local STRENGTH          = 6000
local DRAG_COEFFICIENT  = 10
local HOLE_RADIUS       = 50
local RESIDUAL_VELOCITY = STRENGTH / DRAG_COEFFICIENT  -- derived from hit strength; no air resistance so horizontal speed persists
local YIELD_MASK_DELAY  = 0.04
local DUST_LIFETIME     = 10
local FLOOR_Y           = 0    -- dummy won't travel below this Y level
local GROUND_DUST_COOLDOWN = 0.3  -- seconds between ground-contact dust clouds
local VELOCITY_THRESHOLD   = 1    -- studs/sec below which ground tracking stops
local BRACE_DELAY          = .75  -- seconds after first ground contact before bracing
local hitGeneration        = 0    -- incremented each hit; cancels stale ground-tracking loops
local CSG_DEBUG            = false -- per-part [CSG] timing prints (off in normal play — printing is not free)

-- ==========================================================
-- KINEMATIC: endpoint with floor redirect
-- ==========================================================
local function computeEndpoint(startPos, direction, strength)
	local distance  = strength / DRAG_COEFFICIENT
	local rawEndPos = startPos + direction.Unit * distance

	-- If trajectory dips below FLOOR_Y, bend remaining distance flat
	if rawEndPos.Y < FLOOR_Y and direction.Y < 0 then
		local distToFloor   = (startPos.Y - FLOOR_Y) / (-direction.Y)
		local floorHitPos   = startPos + direction.Unit * distToFloor
		local remainingDist = distance - distToFloor

		local horizontalVec = Vector3.new(direction.X, 0, direction.Z)
		if horizontalVec.Magnitude > 0.01 and remainingDist > 0 then
			local flatEnd = floorHitPos + horizontalVec.Unit * remainingDist
			return Vector3.new(flatEnd.X, FLOOR_Y, flatEnd.Z), distance
		end

		return Vector3.new(floorHitPos.X, FLOOR_Y, floorHitPos.Z), distance
	end

	return rawEndPos, distance
end

-- ==========================================================
-- DESTRUCTION
-- ==========================================================
-- Parts tagged this way (by BuildingGenerator: furniture, deco, carpet, lights)
-- are DELETED on hit instead of being carved — CSG on them is wasted time.
local NO_CSG_TAG = "NoCSG"

-- True for parts that should be deleted rather than CSG'd: MeshParts (CSG fails
-- on them anyway) and anything tagged non-structural.
local function shouldDeleteNotCarve(part)
	return part:IsA("MeshPart") or CollectionService:HasTag(part, NO_CSG_TAG)
end

local function isBuildingPart(part)
	local current = part.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") and current.Name:match("^Building") then
			return true
		end
		current = current.Parent
	end
	return false
end

local function distanceToSegment(p, a, b)
	local ab = b - a
	local ap = p - a
	local ab_mag2 = ab.X*ab.X + ab.Y*ab.Y + ab.Z*ab.Z
	if ab_mag2 < 0.001 then
		return ap.Magnitude
	end
	local t = (ap.X*ab.X + ap.Y*ab.Y + ap.Z*ab.Z) / ab_mag2
	t = math.clamp(t, 0, 1)
	local closestPoint = a + t * ab
	return (p - closestPoint).Magnitude
end

local function safeSubtractAsync(part, cutter, startPos, endPos, radius)
	if GeometryService then
		local success, results = pcall(function()
			return GeometryService:SubtractAsync(part, { cutter })
		end)
		if success and results then
			-- If results is empty, the part was completely carved away/consumed by the cutter
			for _, newPart in ipairs(results) do
				newPart.Name = part.Name
				newPart.Anchored = part.Anchored
				newPart.CanCollide = part.CanCollide
				newPart.Material = part.Material
				newPart.Color = part.Color
				for _, tag in ipairs(CollectionService:GetTags(part)) do
					CollectionService:AddTag(newPart, tag)
				end
				for attrName, attrValue in pairs(part:GetAttributes()) do
					newPart:SetAttribute(attrName, attrValue)
				end
				newPart.Parent = part.Parent
			end
			part:Destroy()
			return true, results
		elseif not success then
			-- GeometryService failed (e.g. self-intersecting union or mesh complexity limit exceeded)
			if part:IsA("MeshPart") then
				warn(string.format("[HitHandler] CSG failed on MeshPart '%s'. Error: %s. \n--> IMPORTANT DEVELOPER TIP: MeshParts are highly prone to CSG failures at runtime due to complexity, collision fidelity, and triangle limits. For destructible structural elements like floors and walls, always use primitive Parts or Unions (PartOperations)!", part.Name, tostring(results)))
			end
			-- If the part is small and inside the cutter radius, destroy it to avoid floating artifacts
			if startPos and endPos and radius then
				local dist = distanceToSegment(part.Position, startPos, endPos)
				if dist <= radius then
					local maxDim = math.max(part.Size.X, part.Size.Y, part.Size.Z)
					if maxDim < radius * 3 then -- within 15 studs
						part:Destroy()
						return true, {}
					end
				end
			end
		end
	end

	-- Fallback to old BasePart:SubtractAsync
	local success, union = pcall(function()
		return part:SubtractAsync({ cutter })
	end)
	if success and union then
		union.Name = part.Name
		union.Anchored = part.Anchored
		union.CanCollide = part.CanCollide
		union.Material = part.Material
		union.Color = part.Color
		for _, tag in ipairs(CollectionService:GetTags(part)) do
			CollectionService:AddTag(union, tag)
		end
		for attrName, attrValue in pairs(part:GetAttributes()) do
			union:SetAttribute(attrName, attrValue)
		end
		union.Parent = part.Parent
		part:Destroy()
		return true, { union }
	else
		-- If fallback failed too, and it's small/inside, destroy it
		if startPos and endPos and radius then
			local dist = distanceToSegment(part.Position, startPos, endPos)
			if dist <= radius then
				local maxDim = math.max(part.Size.X, part.Size.Y, part.Size.Z)
				if maxDim < radius * 3 then
					part:Destroy()
					return true, {}
				end
			end
		end
		return false, union
	end
end

local function destroyAlongCylinder(startPos, endPos, radius)
	local direction = endPos - startPos
	local length    = direction.Magnitude
	if length < 1 then return end

	local cutter = Instance.new("Part")
	cutter.Shape        = Enum.PartType.Cylinder
	cutter.Size         = Vector3.new(length, radius * 2, radius * 2)
	cutter.CFrame       = CFrame.lookAt(startPos + direction / 2, endPos)
		* CFrame.Angles(0, math.rad(90), 0)
	cutter.Anchored     = true
	cutter.CanCollide   = false
	cutter.Transparency = 1
	cutter.Parent       = Workspace

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cutter }

	local hits = Workspace:GetPartsInPart(cutter, params)
	local hitSet = {}
	for _, part in ipairs(hits) do
		hitSet[part] = true
	end

	-- 100% reliable mathematical fallback for parts that might be missed
	-- (e.g. due to CanQuery = false, CollisionGroups, or collision fidelity).
	-- BROAD-PHASE: skip whole buildings whose cached bounding box is nowhere
	-- near the hit segment, so this stays cheap with a few hundred buildings on
	-- the map (no per-part scan of distant buildings). Buildings without a
	-- cached bbox (hand-built, not run through BuildingGenerator) are scanned.
	local function buildingNearSegment(building)
		local cf = building:GetAttribute("InteriorBBoxCFrame")
		local size = building:GetAttribute("InteriorBBoxSize")
		if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
			return true
		end
		return distanceToSegment(cf.Position, startPos, endPos) <= (radius + size.Magnitude * 0.5)
	end

	-- GetPartsInPart (OverlapParams default RespectCanCollide = false) already
	-- returns every overlapping part whose CanQuery is true — that's all of
	-- BuildingGenerator's output. The only parts a spatial query can't see are
	-- CanQuery = false ones, so the fallback scan only needs to consider those.
	-- (Skipping the thousands of query-able parts on a tall tower is the win.)
	local function scanBuilding(child)
		if child:IsA("Model") and child.Name:match("^Building") and buildingNearSegment(child) then
			for _, descendant in ipairs(child:GetDescendants()) do
				if descendant:IsA("BasePart") and not descendant.CanQuery and not hitSet[descendant] then
					local dist = distanceToSegment(descendant.Position, startPos, endPos)
					-- If center is within (radius + part size cushion), it is overlapping
					if dist <= (radius + descendant.Size.Magnitude * 0.5) then
						table.insert(hits, descendant)
						hitSet[descendant] = true
					end
				end
			end
		end
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == "Buildings" and (child:IsA("Folder") or child:IsA("Model")) then
			-- Buildings is a container, even when it is a Model. Cull its actual
			-- building children individually instead of scanning the whole city.
			for _, building in ipairs(child:GetChildren()) do scanBuilding(building) end
		else
			-- Preserve support for standalone test/hand-authored buildings.
			scanBuilding(child)
		end
	end

	for _, part in ipairs(hits) do
		if isBuildingPart(part) then
			if shouldDeleteNotCarve(part) then
				-- Furniture / deco / carpet / lights / MeshParts: just remove them.
				part:Destroy()
			else
				local cutterClone  = cutter:Clone()
				cutterClone.Parent = Workspace
				task.spawn(function()
					local csgStart = os.clock()
					local ok, err = safeSubtractAsync(part, cutterClone, startPos, endPos, radius)
					if CSG_DEBUG then
						print(string.format("[CSG] %s: %.2f ms", part.Name, (os.clock() - csgStart) * 1000))
					end
					if not ok then warn("[HitHandler] CSG failed on:", part.Name, err) end
					if cutterClone.Parent then cutterClone:Destroy() end
				end)
			end
		end
	end

	cutter:Destroy()
end

-- ==========================================================
-- VFX
-- ==========================================================
local function spawnDustCloud(position, scale)
	scale = scale or 1

	local emitter = Instance.new("Part")
	emitter.Size         = Vector3.new(1, 1, 1)
	emitter.Position     = position
	emitter.Anchored     = true
	emitter.CanCollide   = false
	emitter.Transparency = 1
	emitter.Parent       = Workspace

	local particle = Instance.new("ParticleEmitter")
	particle.Texture      = "rbxassetid://106896556490763"
	particle.Rate         = 0
	particle.Lifetime     = NumberRange.new(6, 12)
	particle.Speed        = NumberRange.new(5 * scale, 15 * scale)
	particle.SpreadAngle  = Vector2.new(180, 180)
	particle.Size         = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 15  * scale),
		NumberSequenceKeypoint.new(1, 40 * scale),
	})
	particle.Color = ColorSequence.new(Color3.fromRGB(100, 100, 100))
	particle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	particle.Acceleration = Vector3.new(0, 2, 0)
	particle.Parent       = emitter

	particle:Emit(math.floor(1000 * scale))
	Debris:AddItem(emitter, DUST_LIFETIME)
end

-- ==========================================================
-- INTERSECTION
-- ==========================================================
local function findBuildingIntersections(startPos, endPos)
	local direction = endPos - startPos
	local length = direction.Magnitude
	if length < 1 then return {} end

	local dir = direction.Unit
	local points = {}

	-- Collect all building parts for raycast filter
	local buildingParts = {}
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and isBuildingPart(descendant) then
			table.insert(buildingParts, descendant)
		end
	end

	if #buildingParts == 0 then return points end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = buildingParts

	local currentOrigin = startPos
	local remainingDist = length

	for i = 1, 20 do
		local result = Workspace:Raycast(currentOrigin, dir * remainingDist, rayParams)
		if not result then break end

		table.insert(points, result.Position)

		-- Step past this hit to find the next surface
		currentOrigin = result.Position + dir * 1
		remainingDist = (endPos - currentOrigin).Magnitude
		if remainingDist <= 1 then break end
	end

	return points
end

-- ==========================================================
-- BRACE ANIMATION
-- ==========================================================
local BRACE_ANIM_ID = "rbxassetid://76152813518702"
local braceAnimation = Instance.new("Animation")
braceAnimation.AnimationId = BRACE_ANIM_ID

local activeBraceTracks = {}

-- ==========================================================
-- BRACE & RECOVER (Replaces Sled)
-- ==========================================================
local STAND_SPEED         = 8     -- studs/sec below which dummy stands up

local function braceDummy(targetModel)
	local hrp = targetModel:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Play brace animation
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		
		local track = animator:LoadAnimation(braceAnimation)
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
		activeBraceTracks[targetModel] = track
	end

	-- Stop tumbling
	for _, part in ipairs(targetModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Keep upright and facing opposite of travel direction (facing the user)
	local velocity = hrp.AssemblyLinearVelocity
	local horizontalDir = Vector3.new(velocity.X, 0, velocity.Z)
	if horizontalDir.Magnitude > 0.1 then
		horizontalDir = -horizontalDir.Unit
	else
		horizontalDir = -hrp.CFrame.LookVector
	end

	local align = Instance.new("AlignOrientation")
	align.Name = "UprightAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	
	local attachment = Instance.new("Attachment")
	attachment.Name = "UprightAttachment"
	attachment.Parent = hrp
	align.Attachment0 = attachment
	
	align.CFrame = CFrame.lookAt(Vector3.zero, horizontalDir)
	align.MaxTorque = 100000
	align.MaxAngularVelocity = 100
	align.Responsiveness = 200
	align.Parent = hrp

	print("[HitHandler] Dummy braced.")
end

local function recoverDummy(targetModel)
	local hrp = targetModel:FindFirstChild("HumanoidRootPart")

	-- Remove align orientation
	if hrp then
		local align = hrp:FindFirstChild("UprightAlign")
		if align then align:Destroy() end
		local att = hrp:FindFirstChild("UprightAttachment")
		if att then att:Destroy() end
	end

	-- Stop brace animation
	local track = activeBraceTracks[targetModel]
	if track then
		track:Stop()
		activeBraceTracks[targetModel] = nil
	end

	-- Set Humanoid to GettingUp so it naturally recovers to standing
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Landed, true)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	print("[HitHandler] Dummy recovering to standing.")
end

-- ==========================================================
-- DEBRIS CLEANUP HELPERS (shared by spawn + union)
-- ==========================================================
local DEBRIS_SIZE_SCALE               = 0.8   -- uniform scale on spawned debris (proportions unchanged)
local DEBRIS_MATERIAL                 = Enum.Material.Concrete
local DEBRIS_COLOR_FALLBACK           = Color3.fromRGB(163, 162, 165) -- #A3A2A5 if ground sample fails

-- Concrete part texture + terrain MaterialColors tint from the surface under each piece.
local function getDebrisColorFromGround(groundHit, groundPart)
	if groundHit then
		local inst = groundHit.Instance
		if inst:IsA("Terrain") then
			local ok, color = pcall(function()
				return Workspace.Terrain.MaterialColors:GetMaterialColor(groundHit.Material)
			end)
			if ok and typeof(color) == "Color3" then
				return color
			end
		elseif inst:IsA("BasePart") then
			return inst.Color
		end
	end

	if groundPart and groundPart:IsA("BasePart") and not groundPart:IsA("Terrain") then
		return groundPart.Color
	end

	return DEBRIS_COLOR_FALLBACK
end

local function storeDebrisColor(part, color)
	part:SetAttribute("DebrisColorR", color.R)
	part:SetAttribute("DebrisColorG", color.G)
	part:SetAttribute("DebrisColorB", color.B)
end

local function readDebrisColor(part)
	local r = part:GetAttribute("DebrisColorR")
	local g = part:GetAttribute("DebrisColorG")
	local b = part:GetAttribute("DebrisColorB")
	if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
		return Color3.new(r, g, b)
	end
	return DEBRIS_COLOR_FALLBACK
end

local function applyDebrisAppearance(part, color)
	part.Material = DEBRIS_MATERIAL
	part.Color = color or readDebrisColor(part)
end

local DEBRIS_TRAIL_HEIGHT_DROP      = 3.5  -- studs above trail floor; only isolated pieces above this are dropped
local DEBRIS_DROP_SPEED             = 10
local DEBRIS_SETTLE_TIME            = 0.8
local DEBRIS_GROUND_PENETRATION     = 0.25
local DEBRIS_OVERLAP_SHRINK         = 0.75  -- AABB shrink when testing pile support

local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function buildGroundRayFilter(debrisList)
	local filter = {}
	for _, part in ipairs(debrisList) do
		if part and part.Parent then
			table.insert(filter, part)
		end
	end
	for _, model in CollectionService:GetTagged("HitTarget") do
		table.insert(filter, model)
	end
	for _, name in { "PermanentDebrisUnion", "PermanentDebrisTrail" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			table.insert(filter, existing)
		end
	end
	return filter
end

local function getLocalGroundY(position, rayFilter)
	groundRayParams.FilterDescendantsInstances = rayFilter or {}
	local hit = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundRayParams)
	if hit then
		return hit.Position.Y
	end
	return position.Y
end

local function getDebrisBottomY(part)
	-- Because parts are rotated, their visual bottom is lower than Position.Y - Size.Y/2.
	-- We approximate the lowest point using the part's bounding box.
	local size = part.Size
	local cf = part.CFrame
	local corners = {
		cf * Vector3.new(size.X/2, size.Y/2, size.Z/2),
		cf * Vector3.new(size.X/2, size.Y/2, -size.Z/2),
		cf * Vector3.new(size.X/2, -size.Y/2, size.Z/2),
		cf * Vector3.new(size.X/2, -size.Y/2, -size.Z/2),
		cf * Vector3.new(-size.X/2, size.Y/2, size.Z/2),
		cf * Vector3.new(-size.X/2, size.Y/2, -size.Z/2),
		cf * Vector3.new(-size.X/2, -size.Y/2, size.Z/2),
		cf * Vector3.new(-size.X/2, -size.Y/2, -size.Z/2),
	}
	local minY = corners[1].Y
	for i = 2, 8 do
		if corners[i].Y < minY then
			minY = corners[i].Y
		end
	end
	return minY
end

local function getDebrisTopY(part)
	local size = part.Size
	local cf = part.CFrame
	local corners = {
		cf * Vector3.new(size.X/2, size.Y/2, size.Z/2),
		cf * Vector3.new(size.X/2, size.Y/2, -size.Z/2),
		cf * Vector3.new(size.X/2, -size.Y/2, size.Z/2),
		cf * Vector3.new(size.X/2, -size.Y/2, -size.Z/2),
		cf * Vector3.new(-size.X/2, size.Y/2, size.Z/2),
		cf * Vector3.new(-size.X/2, size.Y/2, -size.Z/2),
		cf * Vector3.new(-size.X/2, -size.Y/2, size.Z/2),
		cf * Vector3.new(-size.X/2, -size.Y/2, -size.Z/2),
	}
	local maxY = corners[1].Y
	for i = 2, 8 do
		if corners[i].Y > maxY then
			maxY = corners[i].Y
		end
	end
	return maxY
end

-- ==========================================================
-- GROUND DEBRIS & CRATER
-- ==========================================================
local function createGroundCrater(startPos, endPos, velocity, groundPart, debrisList)
	-- Flatten positions to ground level so carving stays on the surface
	local groundY = math.min(startPos.Y, endPos.Y)
	startPos = Vector3.new(startPos.X, groundY, startPos.Z)
	endPos = Vector3.new(endPos.X, groundY, endPos.Z)

	local direction = endPos - startPos
	local distance = direction.Magnitude
	local dirUnit

	-- Fallback for point crater (e.g. initial impact tumbling)
	if distance < 0.1 then
		distance = 4
		dirUnit = velocity.Magnitude > 0.1 and velocity.Unit or Vector3.new(1, 0, 0)
		direction = dirUnit * distance
	else
		dirUnit = direction.Unit
	end
	
	-- Flatten the direction so the crater doesn't pitch up/down into the ground
	local flatDir = Vector3.new(dirUnit.X, 0, dirUnit.Z)
	if flatDir.Magnitude > 0.01 then flatDir = flatDir.Unit else flatDir = Vector3.new(1.5, 0, 0) end
	
	-- Calculate right vector
	local right = Vector3.new(0, 1, 0):Cross(flatDir).Unit
	
	-- Shallow rectangular trench (terrain voxels are 4x4x4 — keep depth modest)
	local trenchWidth = 4
	local trenchDepth = 3
	local centerPos = startPos + direction / 2
	local carveLength = math.max(distance + 2, 4)
	
	local blockCFrame = CFrame.lookAt(centerPos, centerPos + flatDir)
		* CFrame.new(0, -1, 0)
	local blockSize = Vector3.new(trenchWidth, trenchDepth, carveLength)

	-- Sample terrain tint BEFORE carving — post-carve spawn raycasts often miss and fall back to grey
	local colorRayParams = RaycastParams.new()
	colorRayParams.FilterType = Enum.RaycastFilterType.Exclude
	colorRayParams.FilterDescendantsInstances = CollectionService:GetTagged("HitTarget")
	local colorSampleHit = workspace:Raycast(
		centerPos + Vector3.new(0, 8, 0),
		Vector3.new(0, -40, 0),
		colorRayParams
	)
	local segmentDebrisColor = getDebrisColorFromGround(colorSampleHit, groundPart)
	
	-- 1. Carve Terrain (if any)
	workspace.Terrain:FillBlock(blockCFrame, blockSize, Enum.Material.Air)
	
	-- 2. Carve Parts (CSG)
	if groundPart and groundPart:IsA("BasePart") and not groundPart:IsA("Terrain") then
		local cutter = Instance.new("Part")
		cutter.Shape = Enum.PartType.Block
		cutter.Size = blockSize
		cutter.CFrame = blockCFrame
		cutter.Anchored = true
		cutter.CanCollide = false
		cutter.Transparency = 1
		cutter.Parent = Workspace
		
		task.spawn(function()
			local csgStart = os.clock()
			local ok, err = safeSubtractAsync(groundPart, cutter)
			if CSG_DEBUG then
				print(string.format("[CSG Ground] %.2f ms", (os.clock() - csgStart) * 1000))
			end
			if not ok then warn("[CSG Ground] Failed:", err) end
			if cutter.Parent then cutter:Destroy() end
		end)
	end
	
	-- 3. Spawn Static Debris Trail
	-- Generate debris along the segment (spaced out along the trench)
	local steps = math.max(1, math.floor(distance / 3.5))
	for i = 0, steps do
		local fraction = steps > 0 and (i / steps) or 0.5
		local segPos = startPos + direction * fraction
		
		-- Left and Right debris
		for side = -1, 1, 2 do
			local count = math.random(3, 5)
			for j = 1, count do
				-- Wedges are the majority; remaining rolls are flat block variants
				local debrisType
				if math.random(1, 10) <= 8 then
					debrisType = 6
				elseif math.random(1, 10) <= 7 then
					debrisType = math.random(2, 4)
				else
					debrisType = math.random(1, 5)
				end
				
				local sizeX, sizeY, sizeZ
				local isWedge = debrisType == 6
				
				-- Horizontal prisms: Y is the thin axis but taller than before (wide base, visible height)
				local function horizontalPrism(xMul, zMul)
					local base = (math.random() * 1.1 + 1.45) * DEBRIS_SIZE_SCALE
					local thickness = base * (math.random() * 0.18 + 0.50)
					local x = base * (math.random() * 0.5 + xMul)
					local z = base * (math.random() * 0.5 + zMul)
					return x, thickness, z
				end
				
				local function wedgeSizes()
					local base = (math.random() * 1.1 + 1.45) * DEBRIS_SIZE_SCALE
					local height = base * (math.random() * 0.18 + 0.45)
					local width = base * (math.random() * 0.5 + 1.35)
					local length = base * (math.random() * 0.8 + 2.2)
					return width, height, length
				end
				
				if debrisType == 1 then
					sizeX, sizeY, sizeZ = horizontalPrism(1.05, 1.05)
				elseif debrisType == 2 then
					sizeX, sizeY, sizeZ = horizontalPrism(1.0, 1.55)
				elseif debrisType == 3 then
					sizeX, sizeY, sizeZ = horizontalPrism(1.55, 1.0)
				elseif debrisType == 4 then
					sizeX, sizeY, sizeZ = horizontalPrism(1.35, 1.35)
				elseif debrisType == 5 then
					sizeX, sizeY, sizeZ = horizontalPrism(1.25, 1.15)
				else
					sizeX, sizeY, sizeZ = wedgeSizes()
				end
				
				local sideSpread = trenchWidth / 2 + 1.5 + math.random() * 2
				local sideOffset = right * side * sideSpread
				local forwardOffset = flatDir * (math.random() * 3.5 - 1.75)
				local clusterJitter = Vector3.new(math.random() * 1.4 - 0.7, 0, math.random() * 1.4 - 0.7)
				local outward = right * side
				
				-- Snap spawn XZ first, then raycast down to terrain so debris sits on the ground
				local spawnXZ = segPos + sideOffset + forwardOffset + clusterJitter
				local surfaceY = segPos.Y
				local spawnFilter = debrisList and buildGroundRayFilter(debrisList) or {}
				groundRayParams.FilterDescendantsInstances = spawnFilter
				local groundHit = workspace:Raycast(
					spawnXZ + Vector3.new(0, 3, 0),
					Vector3.new(0, -12, 0),
					groundRayParams
				)
				if groundHit then
					surfaceY = groundHit.Position.Y
				end

				local debrisColor = segmentDebrisColor
				
				-- Keep world-up so carved terrain normals don't tilt pieces into the air
				local up = Vector3.yAxis
				local inward = -outward
				-- Bottom rests on/near surface; slight embed keeps piles visually grounded
				local groundPos = Vector3.new(spawnXZ.X, surfaceY + sizeY * 0.5 - 0.15, spawnXZ.Z)
				
				local debris = Instance.new("Part")
				if isWedge then
					debris.Shape = Enum.PartType.Wedge
				end
				debris.Size = Vector3.new(sizeX, sizeY, sizeZ)
				
				local yawJitter = math.rad(math.random(-18, 18))
				local baseCFrame
				if isWedge then
					-- Roblox wedge slopes upward along local +Z.
					-- lookAt aims -Z at the target, so +Z points inward toward the trench.
					-- Result: flat on the ground, ramping up toward the trench.
					local flatInward = inward - inward:Dot(up) * up
					if flatInward.Magnitude < 0.01 then
						flatInward = Vector3.new(inward.X, 0, inward.Z)
					end
					flatInward = flatInward.Unit
					baseCFrame = CFrame.lookAt(groundPos, groundPos - flatInward, up)
						* CFrame.Angles(0, yawJitter, 0)
				else
					local faceDir = debrisType == 3 and outward or flatDir
					faceDir = faceDir - faceDir:Dot(up) * up
					if faceDir.Magnitude < 0.01 then
						faceDir = flatDir - flatDir:Dot(up) * up
					end
					if faceDir.Magnitude > 0.01 then
						faceDir = faceDir.Unit
					else
						faceDir = Vector3.new(1, 0, 0)
					end
					-- Yaw-only rotation keeps blocks/prisms flat on the ground
					baseCFrame = CFrame.lookAt(groundPos, groundPos + faceDir, up)
						* CFrame.Angles(0, math.rad(math.random(-20, 20)), 0)
				end
				
				debris.CFrame = baseCFrame
				
				debris.Anchored = true
				debris.CanCollide = false -- Keep false so players don't get stuck on it
				debris:SetAttribute("SpawnGroundY", surfaceY)
				debris.Parent = Workspace
				storeDebrisColor(debris, debrisColor)
				applyDebrisAppearance(debris, debrisColor)
				
				if debrisList then
					table.insert(debrisList, debris)
				else
					Debris:AddItem(debris, 10)
				end
			end
		end
	end
end

-- ==========================================================
-- DEBRIS CLEANUP & UNION
-- ==========================================================
local function debrisAabbOverlap(a, b, shrink)
	local halfA = a.Size * 0.5 * shrink
	local halfB = b.Size * 0.5 * shrink
	local delta = a.Position - b.Position
	return math.abs(delta.X) < (halfA.X + halfB.X)
		and math.abs(delta.Y) < (halfA.Y + halfB.Y)
		and math.abs(delta.Z) < (halfA.Z + halfB.Z)
end

local function debrisOverlapsAnyOther(part, debrisList, shrink)
	for _, other in ipairs(debrisList) do
		if other ~= part and other.Parent and debrisAabbOverlap(part, other, shrink) then
			return true
		end
	end
	return false
end

-- Lowest debris bottom across the whole trail — blanket height reference for the slide.
local function getTrailGroundY(debrisList)
	local minBottom = math.huge
	for _, part in ipairs(debrisList) do
		if part and part.Parent then
			minBottom = math.min(minBottom, getDebrisBottomY(part))
		end
	end
	if minBottom == math.huge then
		return 0
	end
	return minBottom
end

-- Drop only pieces that sit well above the trail floor AND don't touch any other debris.
local function shouldDropIsolatedHighDebris(part, debrisList, trailGroundY)
	local bottomY = getDebrisBottomY(part)
	if bottomY <= trailGroundY + DEBRIS_TRAIL_HEIGHT_DROP then
		return false
	end
	return not debrisOverlapsAnyOther(part, debrisList, DEBRIS_OVERLAP_SHRINK)
end

local function dropDebrisThroughGround(floaters, rayFilter)
	for _, part in ipairs(floaters) do
		part.Anchored = false
		part.CanCollide = false
		part.AssemblyLinearVelocity = Vector3.new(0, -DEBRIS_DROP_SPEED, 0)
		part.AssemblyAngularVelocity = Vector3.zero
	end

	local dropDeadline = os.clock() + DEBRIS_SETTLE_TIME
	while os.clock() < dropDeadline do
		local anyLeft = false
		for i = #floaters, 1, -1 do
			local part = floaters[i]
			if not part or not part.Parent then
				table.remove(floaters, i)
				continue
			end

			local groundY = getLocalGroundY(part.Position, rayFilter)
			if getDebrisTopY(part) < groundY - DEBRIS_GROUND_PENETRATION then
				part:Destroy()
				table.remove(floaters, i)
			else
				anyLeft = true
				part.AssemblyLinearVelocity = Vector3.new(0, -DEBRIS_DROP_SPEED, 0)
			end
		end
		if not anyLeft then
			break
		end
		task.wait(0.05)
	end

	for _, part in ipairs(floaters) do
		if part and part.Parent then
			part:Destroy()
		end
	end
end

local function cleanupDebrisBeforeUnion(debrisList)
	local rayFilter = buildGroundRayFilter(debrisList)
	local trailGroundY = getTrailGroundY(debrisList)
	local kept = {}
	local toDrop = {}

	for _, part in ipairs(debrisList) do
		if not part or not part.Parent then
			continue
		end
		if shouldDropIsolatedHighDebris(part, debrisList, trailGroundY) then
			table.insert(toDrop, part)
		else
			table.insert(kept, part)
		end
	end

	dropDebrisThroughGround(toDrop, rayFilter)

	local validDebris = {}
	for _, part in ipairs(kept) do
		if not part or not part.Parent then
			continue
		end
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part.Anchored = true
		part.CanCollide = false
		applyDebrisAppearance(part)
		table.insert(validDebris, part)
	end

	print(string.format(
		"[HitHandler] Debris cleanup: dropped %d isolated high | kept %d for union (trail floor Y=%.2f)",
		#toDrop,
		#validDebris,
		trailGroundY
	))

	return validDebris
end

local function unionDebris(debrisList)
	if not debrisList or #debrisList == 0 then return end
	
	print("[HitHandler] Attempting to process", #debrisList, "debris parts...")
	task.spawn(function()
		-- Wait a few seconds before unioning so the player sees the individual rocks first
		task.wait(3)
		
		local validDebris = cleanupDebrisBeforeUnion(debrisList)
		
		print("[HitHandler] Valid debris for union/model:", #validDebris)
		if #validDebris == 0 then return end
		
		-- Fallback: Group them in a model to keep workspace clean
		local model = Instance.new("Model")
		model.Name = "PermanentDebrisTrail"
		model.Parent = Workspace
		
		for _, p in ipairs(validDebris) do
			p.Parent = model
			applyDebrisAppearance(p)
		end
		
		-- Attempt UnionAsync for true single-part optimization
		if #validDebris >= 2 then
			local firstPart = validDebris[1]
			local unionColor = readDebrisColor(firstPart)
			local others = {}
			for i = 2, #validDebris do
				table.insert(others, validDebris[i])
			end
			
			local ok, result = pcall(function()
				return firstPart:UnionAsync(others)
			end)
			
			if ok and result then
				print("[HitHandler] Successfully unioned debris into a single part!")
				result.Name = "PermanentDebrisUnion"
				result.Anchored = true
				result.CanCollide = true
				result.Parent = Workspace
				storeDebrisColor(result, unionColor)
				applyDebrisAppearance(result, unionColor)
				model:Destroy()
			else
				warn("[HitHandler] UnionAsync failed, falling back to Model. Error:", result)
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then
						p.CanCollide = true
						applyDebrisAppearance(p)
					end
				end
			end
		else
			local sole = validDebris[1]
			sole.CanCollide = true
			applyDebrisAppearance(sole)
		end
	end)
end

-- ==========================================================
-- GROUND TRACKING
-- ==========================================================
local function trackGroundContacts(targetModel, DustEvent, gen)
	local hrp = targetModel:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { targetModel }

	local lastDustTime = 0
	local firstGroundContactTime = nil
	local isBraced = false

	local slideDebris = {}
	local lastCraterPos = nil
	local lastCraterTime = os.clock()

	while targetModel.Parent do
		task.wait(0.1)

		-- Cancel if a newer hit has started
		if hitGeneration ~= gen then
			unionDebris(slideDebris)
			return
		end

		if not hrp or not hrp.Parent then break end

		local speed = hrp.AssemblyLinearVelocity.Magnitude

		if isBraced then
			if speed < STAND_SPEED then
				-- Final segment
				local currentPos = hrp.Position
				local dustRayParams = RaycastParams.new()
				dustRayParams.FilterType = Enum.RaycastFilterType.Exclude
				dustRayParams.FilterDescendantsInstances = { targetModel }
				local groundRay = Workspace:Raycast(currentPos, Vector3.new(0, -5, 0), dustRayParams)
				if groundRay then
					if lastCraterPos then
						createGroundCrater(lastCraterPos, groundRay.Position, hrp.AssemblyLinearVelocity, groundRay.Instance, slideDebris)
					end
				end
				
				recoverDummy(targetModel)
				unionDebris(slideDebris)
				break
			end

			-- Handle animation looping (seconds 5 to 8)
			local track = activeBraceTracks[targetModel]
			if track and track.TimePosition >= 8 then
				track.TimePosition = 5
			end

			-- Dust and continuous crater while sliding
			local now = os.clock()
			if now - lastCraterTime >= GROUND_DUST_COOLDOWN then
				local currentPos = hrp.Position
				local dustRayParams = RaycastParams.new()
				dustRayParams.FilterType = Enum.RaycastFilterType.Exclude
				dustRayParams.FilterDescendantsInstances = { targetModel }
				local groundRay = Workspace:Raycast(currentPos, Vector3.new(0, -5, 0), dustRayParams)
				if groundRay then
					DustEvent:FireAllClients(groundRay.Position, 0.5)
					if lastCraterPos then
						createGroundCrater(lastCraterPos, groundRay.Position, hrp.AssemblyLinearVelocity, groundRay.Instance, slideDebris)
					else
						createGroundCrater(groundRay.Position, groundRay.Position, hrp.AssemblyLinearVelocity, groundRay.Instance, slideDebris)
					end
					lastCraterPos = groundRay.Position
					lastCraterTime = now
				else
					lastCraterPos = nil
				end
			end
			continue
		end

		-- Pre-brace: ragdoll phase — track ground contact and dust
		local rayResult = Workspace:Raycast(
			hrp.Position,
			Vector3.new(0, -10, 0),
			rayParams
		)

		if rayResult then
			local distToGround = (hrp.Position - rayResult.Position).Magnitude
			if distToGround < 4 then
				-- Track first ground contact
				if not firstGroundContactTime then
					firstGroundContactTime = os.clock()
				end

				-- Dust effects while tumbling
				local now = os.clock()
				if now - lastDustTime >= GROUND_DUST_COOLDOWN then
					DustEvent:FireAllClients(rayResult.Position, 0.5)
					if lastCraterPos then
						createGroundCrater(lastCraterPos, rayResult.Position, hrp.AssemblyLinearVelocity, rayResult.Instance, slideDebris)
					else
						createGroundCrater(rayResult.Position, rayResult.Position, hrp.AssemblyLinearVelocity, rayResult.Instance, slideDebris)
					end
					lastDustTime = now
					lastCraterPos = rayResult.Position
					lastCraterTime = now
				end

				-- After BRACE_DELAY, brace
				if not isBraced and (os.clock() - firstGroundContactTime >= BRACE_DELAY) then
					isBraced = true
					braceDummy(targetModel)
					lastCraterPos = rayResult.Position
					lastCraterTime = os.clock()
				end
			else
				-- Dummy is airborne (higher than 4 studs)
				lastCraterPos = nil
			end
		else
			-- Dummy is airborne (raycast didn't hit anything within 10 studs)
			lastCraterPos = nil
		end

		-- If not braced and velocity is very low, just stand up
		if not isBraced and speed < VELOCITY_THRESHOLD then
			recoverDummy(targetModel)
			unionDebris(slideDebris)
			break
		end
	end
end

-- ==========================================================
-- MODULE
-- ==========================================================
local HitHandler = {}

function HitHandler.Init()
	local DustEvent = ReplicatedStorage:FindFirstChild("DustEvent")
	if not DustEvent then
		DustEvent = Instance.new("RemoteEvent")
		DustEvent.Name = "DustEvent"
		DustEvent.Parent = ReplicatedStorage
	end

	local HitEvent = ReplicatedStorage:FindFirstChild("HitEvent")
	if not HitEvent then
		HitEvent = Instance.new("RemoteEvent")
		HitEvent.Name = "HitEvent"
		HitEvent.Parent = ReplicatedStorage
	end

	-- Persist logical glass damage independently of client LOD and late joins.
	local GlassDamage=require(script.Parent.GlassDamageService)
	GlassDamage.Init()

	HitEvent.OnServerEvent:Connect(function(player, targetModel, hitDirection)
		if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end
		if not CollectionService:HasTag(targetModel, "HitTarget") then return end
		if typeof(hitDirection) ~= "Vector3" or hitDirection.Magnitude < 0.01 then return end

		hitGeneration = hitGeneration + 1
		local currentGen = hitGeneration

		local t0 = os.clock()
		local root = targetModel.PrimaryPart
			or targetModel:FindFirstChild("HumanoidRootPart")
			or targetModel:FindFirstChildWhichIsA("BasePart")

		if not root then
			warn("[HitHandler] Could not find a root part on", targetModel.Name)
			return
		end

		-- Clean up any previous sled/brace state so a re-hit starts fresh
		local oldAlign = root:FindFirstChild("UprightAlign")
		if oldAlign then oldAlign.Parent = nil end
		local oldAttachment = root:FindFirstChild("UprightAttachment")
		if oldAttachment then oldAttachment.Parent = nil end
		
		local track = activeBraceTracks[targetModel]
		if track then
			track:Stop()
			activeBraceTracks[targetModel] = nil
		end

		-- Anchor all parts first so the Humanoid can't fight the teleport.
		-- On the first hit the dummy starts anchored, but on re-hits it's
		-- unanchored and the Humanoid actively resists Physics state changes.
		-- Anchoring freezes the Humanoid so we can cleanly reposition.
		for _, part in ipairs(targetModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end

		local startPos = root.Position
		local direction = hitDirection.Unit

		local endPos, distance = computeEndpoint(startPos, direction, STRENGTH)

		DustEvent:FireAllClients(startPos, 0.5) -- small dust at hit point

		-- Dust at each building surface intersection along the path
		local intersections = findBuildingIntersections(startPos, endPos)
		for _, point in ipairs(intersections) do
			DustEvent:FireAllClients(point, 1.0)
		end

		task.spawn(function()
			GlassDamage.DestroyPath(startPos,endPos,HOLE_RADIUS)
			destroyAlongCylinder(startPos, endPos, HOLE_RADIUS)
		end)

		task.wait(YIELD_MASK_DELAY)

		-- Put Humanoid in Physics state WHILE STILL ANCHORED so it won't
		-- fight the teleport when we unanchor. On re-hits the Humanoid
		-- is in Running/GettingUp and actively resists position changes.
		local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = true
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Landed, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end

		-- Teleport while still anchored — no physics interference possible
		-- We make the dummy face the opposite of the hit direction (so it faces the attacker)
		targetModel:PivotTo(CFrame.lookAt(endPos, endPos - direction))

		-- NOW unanchor — Humanoid is already in Physics, won't fight
		for _, part in ipairs(targetModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		-- Yield one physics step so ragdoll state commits before applying velocity
		task.wait(0.05)

		local launchVelocity = direction * RESIDUAL_VELOCITY
		local launchSpin = Vector3.new(
			math.random(-15, 15),
			math.random(-15, 15),
			math.random(-15, 15)
		)

		for _, part in ipairs(targetModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = launchVelocity
				part.AssemblyAngularVelocity = launchSpin
			end
		end

		-- Track ground contacts for ongoing dust while sliding/bouncing
		task.spawn(function()
			trackGroundContacts(targetModel, DustEvent, currentGen)
		end)

		print(string.format("[HitHandler] Done | dist: %.1f studs | total: %.2f ms",
			distance, (os.clock() - t0) * 1000))
	end)

	-- Periodically check if any HitTarget has fallen off the map
	task.spawn(function()
		while true do
			task.wait(1)
			for _, model in ipairs(CollectionService:GetTagged("HitTarget")) do
				if model:IsA("Model") and model.Parent then
					-- Initialize InitialSpawnCFrame if not set yet
					if not model:GetAttribute("InitialSpawnCFrame") then
						model:SetAttribute("InitialSpawnCFrame", model:GetPivot())
					end

					-- Check if it fell off the map (Y < 0)
					local currentPos = model:GetPivot().Position
					if currentPos.Y < 0 then
						print(string.format("[HitHandler] %s fell off the map! Respawning at initial position.", model.Name))
						
						-- Cancel any active ground tracking loop
						hitGeneration = hitGeneration + 1
						
						-- Stop animations, reset states, stand up
						recoverDummy(model)
						
						-- Reset velocity and temporarily anchor to prevent physics fighting during teleport
						for _, part in ipairs(model:GetDescendants()) do
							if part:IsA("BasePart") then
								part.AssemblyLinearVelocity = Vector3.zero
								part.AssemblyAngularVelocity = Vector3.zero
								part.Anchored = true
							end
						end
						
						-- Teleport back to initial spawn position
						local initialCF = model:GetAttribute("InitialSpawnCFrame")
						if initialCF then
							model:PivotTo(initialCF)
						end
						
						-- Wait a brief moment to let the teleport settle, then unanchor
						task.wait(0.1)
						for _, part in ipairs(model:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Anchored = false
							end
						end
					end
				end
			end
		end
	end)

	print("[HitHandler] Ready.")
end

return HitHandler
