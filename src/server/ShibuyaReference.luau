--!nonstrict
-- Show or hide the Shibuya FBX reference without dragging it through the tree.
--
-- The manual routine was: drag ServerStorage.Shibuya into Workspace, look at it,
-- then press Ctrl+Z to put it back rather than drag it down the tree again.
-- That undo is not free. Replacement.Apply sets its history waypoint at the END
-- of the replacement, so anything done AFTER it -- crown parts, SweepCrowned and
-- Archive attributes -- belongs to the next, still-open undo group. One Ctrl+Z
-- removed 276 crown parts from a committed chunk and reverted its lock, while
-- leaving the replacement itself applied, so every building count still looked
-- correct. It was only caught because a lock attribute had reverted.
--
--   require(game.ServerScriptService.Server.ShibuyaReference).Show()
--   require(game.ServerScriptService.Server.ShibuyaReference).Hide()
--   require(game.ServerScriptService.Server.ShibuyaReference).Toggle()
--
-- Reparenting is its own history waypoint, so Hide() is the undo -- there is
-- never a reason to press Ctrl+Z for this.
local Reference = {}

local Storage = game:GetService("ServerStorage")
local History = game:GetService("ChangeHistoryService")
local NAME = "Shibuya"

local function findIt()
	return workspace:FindFirstChild(NAME) or Storage:FindFirstChild(NAME)
end

function Reference.Show()
	local model = assert(findIt(), "No Shibuya model in Workspace or ServerStorage")
	if model.Parent == workspace then
		return "already in Workspace"
	end
	History:SetWaypoint("Before showing Shibuya reference")
	model.Parent = workspace
	History:SetWaypoint("Shibuya reference shown")
	return "Shibuya -> Workspace (" .. #model:GetChildren() .. " children)"
end

function Reference.Hide()
	local model = assert(findIt(), "No Shibuya model in Workspace or ServerStorage")
	if model.Parent == Storage then
		return "already in ServerStorage"
	end
	History:SetWaypoint("Before hiding Shibuya reference")
	model.Parent = Storage
	History:SetWaypoint("Shibuya reference hidden")
	return "Shibuya -> ServerStorage (" .. #model:GetChildren() .. " children)"
end

function Reference.Toggle()
	local model = assert(findIt(), "No Shibuya model in Workspace or ServerStorage")
	return model.Parent == workspace and Reference.Hide() or Reference.Show()
end

return Reference
