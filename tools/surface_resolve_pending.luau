-- Edit-only. Runs GroundFacadeSurfaceResolver only on runs whose masks still
-- touch untrimmed generated parts (idempotent), then re-prepares bay interiors
-- the trims invalidated and verifies masks. Backups go to one shared archive.
assert(game:GetService("NetworkClient"):FindFirstChildWhichIsA("ClientReplicator"),"Connected Edit required")
local S=require(game.ServerScriptService.Server.GroundFacadeSurfaceResolver)
local B=require(game.ServerScriptService.Server.GroundFacadeBayInteriors)
local plan=S.Plan(workspace.Buildings)
local function bounds(p,cf)
	local q=cf:ToObjectSpace(p.CFrame);local s=p.Size/2;local xs,ys={},{}
	for _,dx in {-1,1} do for _,dy in {-1,1} do for _,dz in {-1,1} do
		local v=q:PointToWorldSpace(Vector3.new(dx*s.X,dy*s.Y,dz*s.Z));table.insert(xs,v.X);table.insert(ys,v.Y)
	end end end
	return {math.min(table.unpack(xs)),math.max(table.unpack(xs)),math.min(table.unpack(ys)),math.max(table.unpack(ys))}
end
local function hit(a,b) return math.min(a[2],b[2])-math.max(a[1],b[1])>.01 and math.min(a[4],b[4])-math.max(a[3],b[3])>.01 end
local needs={}
for _,row in plan.runs do
	local touched=false
	for _,p in row.run:GetDescendants() do
		if p:IsA("BasePart") and not p.Parent:IsA("BasePart") and not p:FindFirstAncestor("BayInterior") then
			local b=bounds(p,row.cf)
			for _,m in row.masks do if hit(b,m) then touched=true;break end end
		end
		if touched then break end
	end
	if touched then table.insert(needs,row) end
end
local archive=game.ServerStorage:FindFirstChild("FacadeSharedSurfaceBackup_Pending")
if not archive then archive=Instance.new("Folder");archive.Name="FacadeSharedSurfaceBackup_Pending";archive:SetAttribute("Owner","facade-surface-repair-v1");archive.Parent=game.ServerStorage end
local out={pairs=plan.pairs,needTrim=#needs,originals=0,fragments=0,errors={}}
for _,row in needs do
	local ok,r=pcall(S.ApplyRun,row,archive)
	if ok then out.originals+=r.originals;out.fragments+=r.fragments else table.insert(out.errors,tostring(r):sub(1,120)) end
	task.wait()
end
for _=1,6 do local r=B.PrepareNextBatch();if r.buildings==0 or r.remainingBuildings==0 then break end end
game:GetService("ChangeHistoryService"):ResetWaypoints()
out.verify=S.VerifyInstalled()
return out
