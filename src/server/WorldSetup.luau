-- WorldSetup.server.luau
-- PLACE IN: ServerScriptService
-- Generates the test scene once when the game starts.
-- Everything created here remains editable in Studio after first run
-- (just stop the game and move/edit/delete parts as you like, then
--  delete this script or comment out the calls to regenerate).

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ==========================================================
-- CONFIG (tweak freely)
-- ==========================================================
local SPAWN_POS         = Vector3.new(0, 5, 0)
local DUMMY_POS         = Vector3.new(0, 163, -5)   -- in front of spawn
local BUILDING_1_POS    = Vector3.new(0, 0, -40)
local BUILDING_2_POS    = Vector3.new(0, 0, -90)
-- Same center Y/Z row as Building1 (cy = 0 ground); offset X so it does not overlap Building1
local BUILDING_TEST_POS = Vector3.new(40, 0, -40)
local BUILDING_SIZE     = Vector3.new(30, 25, 20)  -- width, height, depth
local WALL_THICKNESS    = 1

-- ==========================================================
-- HELPERS
-- ==========================================================
local function makePart(name, size, position, color, material)
	local p = Instance.new("Part")
	p.Name      = name
	p.Size      = size
	p.Position  = position
	p.Anchored  = true
	p.Color     = color    or Color3.fromRGB(160, 160, 160)
	p.Material  = material or Enum.Material.Concrete
	p.Parent    = Workspace
	return p
end

local function makeBuilding(name, centerPos, size)
	local model = Instance.new("Model")
	model.Name   = name
	model.Parent = Workspace

	local w, h, d  = size.X, size.Y, size.Z
	local cx, cy, cz = centerPos.X, centerPos.Y, centerPos.Z
	local t = WALL_THICKNESS

	-- Floor
	makePart("Floor",   Vector3.new(w, t, d), Vector3.new(cx, cy + t/2,       cz)).Parent = model
	-- Ceiling
	makePart("Ceiling", Vector3.new(w, t, d), Vector3.new(cx, cy + h - t/2,   cz)).Parent = model
	-- Front wall (the side facing the spawn / -Z)
	makePart("FrontWall", Vector3.new(w, h, t), Vector3.new(cx, cy + h/2, cz + d/2 - t/2)).Parent = model
	-- Back wall
	makePart("BackWall",  Vector3.new(w, h, t), Vector3.new(cx, cy + h/2, cz - d/2 + t/2)).Parent = model
	-- Side walls
	makePart("LeftWall",  Vector3.new(t, h, d), Vector3.new(cx - w/2 + t/2, cy + h/2, cz)).Parent = model
	makePart("RightWall", Vector3.new(t, h, d), Vector3.new(cx + w/2 - t/2, cy + h/2, cz)).Parent = model

	return model
end

local function anchorModelParts(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function findTestBuildingTemplate()
	return ServerStorage:FindFirstChild("TestBuilding", true)
end

local function waitForTestBuildingTemplate(timeoutSeconds)
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		local template = findTestBuildingTemplate()
		if template then
			return template
		end
		task.wait(0.1)
	end
	return nil
end

local function cloneAsBuildingModel(template)
	if template:IsA("Model") then
		local model = template:Clone()
		model.Name = "Building3"
		return model
	end

	if template:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = "Building3"
		local part = template:Clone()
		part.Anchored = true
		part.Parent = model
		model.PrimaryPart = part
		return model
	end

	warn("[WorldSetup] TestBuilding must be a Model or BasePart, got", template.ClassName)
	return nil
end

local function getGroundYAt(x, z, fallbackY)
	local origin = Vector3.new(x, 100, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -250, 0))
	if result then
		return result.Position.Y
	end
	return fallbackY
end

-- Match makeBuilding: floor bottom on ground. Uses pivot delta (not bbox CFrame) so imports align correctly.
local function placeImportedBuildingAtCenter(model, centerPos)
	anchorModelParts(model)

	if not model.PrimaryPart then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			model.PrimaryPart = firstPart
		end
	end

	model.Parent = Workspace

	local groundY = getGroundYAt(centerPos.X, centerPos.Z, centerPos.Y)
	local bboxCF, bboxSize = model:GetBoundingBox()
	local bboxBottomY = bboxCF.Position.Y - bboxSize.Y / 2
	local offset = Vector3.new(
		centerPos.X - bboxCF.Position.X,
		groundY - bboxBottomY,
		centerPos.Z - bboxCF.Position.Z
	)
	model:PivotTo(model:GetPivot() + offset)

	return model
end

local function spawnTestBuilding(centerPos)
	local template = findTestBuildingTemplate()
	if not template then
		template = waitForTestBuildingTemplate(15)
	end
	if not template then
		warn("[WorldSetup] TestBuilding not found in ServerStorage (searched descendants). Add a Model named TestBuilding there.")
		return
	end

	local model = cloneAsBuildingModel(template)
	if not model then
		return
	end

	placeImportedBuildingAtCenter(model, centerPos)
	print("[WorldSetup] Spawned", model.Name, "from TestBuilding at", model:GetPivot().Position)

	return model
end

local function makeR15Dummy(position)
	-- 1. Get an R15 Dummy (preferably from ServerStorage or create from scratch)
	-- To create from scratch is very complex (15+ parts, Motor6Ds), 
	-- it is better to clone a "R15Dummy" stored in ServerStorage.
	local model = ServerStorage:WaitForChild("R15Dummy"):Clone()
	model.Name = "Dummy"

	-- 2. Position the character
	model:PivotTo(CFrame.new(position))
	model.Parent = workspace

	-- 3. Ensure Humanoid is set to R15
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RigType = Enum.HumanoidRigType.R15
	end

	-- 4. Tag so the click handler can identify it without name lookups
	CollectionService:AddTag(model, "HitTarget")

	-- 5. Store initial spawn CFrame for respawning if it falls off the map
	model:SetAttribute("InitialSpawnCFrame", CFrame.new(position))

	return model
end


-- ==========================================================
-- MODULE
-- ==========================================================
local WorldSetup = {}

function WorldSetup.Init()
	makeBuilding("Building1", BUILDING_1_POS, BUILDING_SIZE)
	makeBuilding("Building2", BUILDING_2_POS, BUILDING_SIZE)
	spawnTestBuilding(BUILDING_TEST_POS)
	makeR15Dummy(DUMMY_POS)

	local spawn = Instance.new("SpawnLocation")
	spawn.Size     = Vector3.new(6, 1, 6)
	spawn.Position = SPAWN_POS
	spawn.Anchored = true
	spawn.Parent   = Workspace

	print("[WorldSetup] World built. Click the red dummy while facing the buildings.")
end

return WorldSetup
