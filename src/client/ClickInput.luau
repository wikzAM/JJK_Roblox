-- ClickInput.client.luau
-- PLACE IN: StarterPlayer > StarterPlayerScripts
-- On mouse click, raycasts from camera. If the hit object is part of a
-- model tagged "HitTarget", fires HitEvent to the server with the camera's
-- LookVector (the "punch direction" for the demo).

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace        = game:GetService("Workspace")

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
	particle.Lifetime     = NumberRange.new(1.5, 3)
	particle.Speed        = NumberRange.new(4 * scale, 12 * scale)
	particle.SpreadAngle  = Vector2.new(180, 180)
	particle.Size         = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4  * scale),
		NumberSequenceKeypoint.new(1, 10 * scale),
	})
	particle.Color = ColorSequence.new(Color3.fromRGB(100, 100, 100))
	particle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0),
		NumberSequenceKeypoint.new(0.3, 0.15),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(0.8, 0.75),
		NumberSequenceKeypoint.new(1,   1),
	})
	particle.Acceleration = Vector3.new(0, 5, 0)
	particle.Parent       = emitter

	particle:Emit(math.floor(400 * scale))
	game:GetService("Debris"):AddItem(emitter, 5) -- max particle lifetime + buffer for full fade-out
end

-- ==========================================================
-- MODULE
-- ==========================================================
local ClickInput = {}

function ClickInput.Init()
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera
	local mouse  = player:GetMouse()

	local HitEvent = ReplicatedStorage:WaitForChild("HitEvent")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

		-- Raycast from camera through mouse position
		local unitRay  = camera:ScreenPointToRay(mouse.X, mouse.Y)
		local rayResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000)
		if not rayResult then return end

		-- Walk up the parent chain looking for a HitTarget-tagged Model
		local current = rayResult.Instance
		while current and current ~= Workspace do
			if current:IsA("Model") and CollectionService:HasTag(current, "HitTarget") then
				HitEvent:FireServer(current, camera.CFrame.LookVector)
				return
			end
			current = current.Parent
		end
	end)

	print("[ClickInput] Active. Click the red dummy to test.")

	local DustEvent = ReplicatedStorage:WaitForChild("DustEvent")

	DustEvent.OnClientEvent:Connect(function(position, scale)
		spawnDustCloud(position, scale)
	end)
end

return ClickInput
