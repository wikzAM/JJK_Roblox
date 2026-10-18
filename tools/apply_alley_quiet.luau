-- Edit-only, OWNER-APPROVAL REQUIRED. Converts glazed alley walls (frontage rev 11,
-- class "window" with the between-buildings reason) to the "alleyQuiet" shopfront
-- profile: display windows only, no entrances (Pilot only allows doors on "front").
-- Run repeatedly; each call rebuilds at most 25 buildings, prepares their bay
-- interiors and clears undo history (prevents the Oct 18 OutOfMemory crash).
-- Afterwards: surface resolver pass, PrepareNextBatch, SAT + blocker scans,
-- reconcile_ground_facade_records.luau, then a verified Save to Roblox.
local NC=game:GetService("NetworkClient")
assert(NC:FindFirstChildWhichIsA("ClientReplicator"),"Connected Edit required")
local H=game:GetService("HttpService")
local Server=game.ServerScriptService.Server
local R=require(Server.GroundFacadeRegistry)
local Frontage=require(Server.GroundFacadeFrontage)
local Pilot=require(Server.GroundFacadePilot)
local B=require(Server.GroundFacadeBayInteriors)
local Catalog=require(game.ReplicatedStorage.Shared.GroundFacadeCatalog)
assert(Catalog.PROFILES.alleyQuiet,"Sync GroundFacadeCatalog (alleyQuiet profile) first")
local OWNER="2026-10-08-ground-pilot"
local GL="Between buildings: quiet glazed wall, no verified public approach"
local rows,models={},{}
for _,m in workspace.Buildings:GetChildren() do
	local root=m:FindFirstChild("GroundFacadePilot")
	if not root or root:GetAttribute("Owner")~=OWNER then continue end
	local row=H:JSONDecode(R.Read(root,"ManifestRow"));local changed=false
	for _,f in row.faces do
		local roles={};for k,v in f.bayRoles or {} do roles[tonumber(k) or k]=v end;f.bayRoles=roles
		if f.class=="window" and f.reason==GL and not f.type then f.class="alleyQuiet";f.bayRoles={};changed=true end
	end
	if changed then table.insert(rows,row);table.insert(models,m) end
	if #rows==25 then break end
end
if #rows==0 then return {done=true} end
local parent=game.ServerStorage.GroundFacadePilotArchive
local archive=parent:FindFirstChild("AlleyQuiet_Rollout")
if not archive then archive=Instance.new("Folder");archive.Name="AlleyQuiet_Rollout";archive:SetAttribute("Owner",OWNER);archive:SetAttribute("Revision",9);archive.Parent=parent end
_G.AlleyQuietScene=_G.AlleyQuietScene or Frontage.Index(Vector3.new(11,0,572),100000)
local _,info=Pilot.Upsert(rows,_G.AlleyQuietScene,{city=true,incremental=true,archive=archive,keepReplacedGeometry=false})
local interiors=B.ApplyBatch(models,{preview=false})
game:GetService("ChangeHistoryService"):ResetWaypoints()
return {rebuilt=info.updated,errors=info.errors,interiors=interiors}
