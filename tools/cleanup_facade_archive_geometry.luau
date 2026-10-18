-- Edit-only, OWNER-APPROVAL REQUIRED, IRREVERSIBLE. Deletes superseded facade-generated
-- BaseParts from rollback archives while keeping every folder, registry chunk,
-- ManifestRow/ReportRow recipe and ObjectValue. Never touches source structure
-- (Station/Core/LegacyCore/Greys/RemovedInfrastructure/DetachedBuildingRecovery).
-- Preflight on Oct 18: 157,530 top-level parts, 0 source-building parts, 0 refs.
-- Run repeatedly; each call removes at most 10,000 parts. Then verify and save.
local NC=game:GetService("NetworkClient")
local function connected() return NC:FindFirstChildWhichIsA("ClientReplicator")~=nil end
assert(connected(),"Connected Edit required")
local SS=game.ServerStorage
local NAMES={"FacadePerPaneInteriorBackup_v2","FacadeSharedSurfaceBackup_c7f2c99e-5f87-4440-8e37-c1b9b39293d1",
	"FacadeSharedSurfaceBackup_656f3476-2f2f-4bf9-953b-09ebebe771be","FacadeSharedSurfaceBackup_123cf4ba-c19c-41ff-9261-ffefc81a45b6",
	"GroundFacadeDraftArchive","GroundFacadePilotArchive"}
local function sourceLike(p,top)
	local a=p.Parent
	while a and a~=top do
		if a:IsA("Model") and (a:GetAttribute("StructuralOnly") or a:GetAttribute("SourceSlicePlan")) then return true end
		a=a.Parent
	end
	return false
end
local removed,skipped=0,0
for _,name in NAMES do
	local top=SS:FindFirstChild(name)
	if not top then continue end
	for _,p in top:GetDescendants() do
		if p:IsA("BasePart") and p.Parent and not p.Parent:IsA("BasePart") then
			if sourceLike(p,top) then skipped+=1 else p:Destroy();removed+=1 end
			if removed%2000==0 then task.wait();assert(connected(),"Disconnected; stop and reopen") end
			if removed>=10000 then break end
		end
	end
	if removed>=10000 then break end
end
game:GetService("ChangeHistoryService"):ResetWaypoints()
local left=0
for _,name in NAMES do local top=SS:FindFirstChild(name);if top then for _,p in top:GetDescendants() do if p:IsA("BasePart") then left+=1 end end end end
return {removed=removed,skippedSourceLike=skipped,partsLeft=left}
