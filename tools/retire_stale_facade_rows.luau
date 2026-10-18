-- Edit-only metadata. For every latest registry row whose building is no longer
-- live, move its journal recipe into GroundFacadePilotArchive.RetiredRows and add
-- a committed "remove" entry. Never touches geometry or restores anything.
assert(game:GetService("NetworkClient"):FindFirstChildWhichIsA("ClientReplicator"),"Connected Edit required")
local H=game:GetService("HttpService")
local R=require(game.ServerScriptService.Server.GroundFacadeRegistry)
local OWNER="2026-10-08-ground-pilot"
local reg=game.ServerStorage.GroundFacadePilotManifest
local journal=reg.CommitJournal
local live={}
for _,m in workspace.Buildings:GetChildren() do
	if m:FindFirstChild("GroundFacadePilot") then live[m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId") or m.Name]=true end
end
local holder=game.ServerStorage.GroundFacadePilotArchive:FindFirstChild("RetiredRows")
if not holder then holder=Instance.new("Folder");holder.Name="RetiredRows";holder:SetAttribute("Owner",OWNER);holder.Parent=game.ServerStorage.GroundFacadePilotArchive end
local retired={}
for _,row in H:JSONDecode(R.ReadLatest(reg,"Report")).rows do
	if not live[row.id] then
		local old=journal:FindFirstChild(row.id);if old then old.Name=row.id;old.Parent=holder end
		local e=Instance.new("Folder");e.Name=row.id;e:SetAttribute("SourceSliceId",row.id);e:SetAttribute("Kind","remove")
		e:SetAttribute("Reason","building no longer live (archived/merged/owner removed)");e:SetAttribute("Committed",true);e.Parent=journal
		table.insert(retired,row.id)
	end
end
local roots=0;for _ in live do roots+=1 end
return {retired=#retired,latestRows=#H:JSONDecode(R.ReadLatest(reg,"Report")).rows,liveRoots=roots}
