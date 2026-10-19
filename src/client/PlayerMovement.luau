--!nonstrict
-- The player never ragdolls on its own. Roblox trips fast characters into the
-- FallingDown/Ragdoll states on hard landings and collisions; the Humanoid state
-- machine runs on the owning client, so disabling them here stops it entirely.
-- Gameplay code can still ragdoll on purpose via PlayerMovement.SetAutoRagdoll(true)
-- or by changing the Humanoid state itself.
local PlayerMovement={}
local Players=game:GetService("Players")
local AUTO_STATES={Enum.HumanoidStateType.FallingDown,Enum.HumanoidStateType.Ragdoll}
local allowAuto=false
local function apply(humanoid)
	for _,state in AUTO_STATES do humanoid:SetStateEnabled(state,allowAuto) end
end
local function onCharacter(character)
	local humanoid=character:WaitForChild("Humanoid",10)
	if humanoid then apply(humanoid) end
end
function PlayerMovement.SetAutoRagdoll(enabled)
	allowAuto=enabled==true
	local character=Players.LocalPlayer.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then apply(humanoid) end
end
function PlayerMovement.Init()
	local player=Players.LocalPlayer
	if player.Character then task.spawn(onCharacter,player.Character) end
	player.CharacterAdded:Connect(onCharacter)
end
return PlayerMovement
