-- Native pre-Apply acceptance for the two explicit rectangular replacements.
-- Requires _G.FacadeBoxPrepared from FacadeBoxRepair.Prepare({exactA,exactB}).
-- Originals stay in place; queryable disposable clones check real neighbors.
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
local prepared=assert(_G.FacadeBoxPrepared,"Prepare the exact two targets first")
local stage=prepared.stage
local R=require(game.ServerScriptService.Server.SourceSliceBuilder)
local Crown=require(game.ServerScriptService.Server.CrownParapet)
local H=game:GetService("HttpService")
local audit=R.Audit(stage)
assert(audit.summary.buildings==2 and audit.summary.goodBuildings==2 and audit.summary.badBuildings==0,"Bad staged structure")
local targets={}
for _,review in prepared.review do
	local found
	for _,m in workspace.Buildings:GetChildren() do if m:GetAttribute("SourceSliceId")==review.id then found=m break end end
	table.insert(targets,assert(found,"Original selected model missing"))
end
local folder=Instance.new("Folder");folder.Name="FacadeBoxStageProbes";folder.Parent=workspace
local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Include
params.FilterDescendantsInstances={workspace.Buildings};params.RespectCanCollide=true
local out={buildings=0,partsTested=0,neighborIntersections=0,replacementIntersections=0,coreClearanceErrors=0,examples={}}
local ok,err=xpcall(function()
	-- Both originals are excluded below because Apply replaces them together.
	-- Their replacements must still be tested against EACH OTHER.
	local probeOwners={}
	for _,model in stage:GetChildren() do if model:IsA("Model") then
		for _,p in model:GetDescendants() do if p:IsA("BasePart") then
			local probe=p:Clone();for _,tag in probe:GetTags() do probe:RemoveTag(tag) end
			probe.CanCollide=false;probe.CanQuery=true;probe.Transparency=1;probe.Parent=folder
			probeOwners[probe]=model
		end end
		local plan=H:JSONDecode(model:GetAttribute("SourceSlicePlan"));local frame=model:GetAttribute("SourceSliceOriginCFrame")
		local roof=plan.levels[#plan.levels]
		local crown=Instance.new("Folder");crown.Name="RoofRimProbes";crown.Parent=folder
		local metrics=Crown.BuildRim(crown,{yaw=math.atan2(-frame.RightVector.Z,frame.RightVector.X),ox=frame.X,oz=frame.Z,y=frame.Y+roof.y+roof.thickness,pieces=roof.pieces},{height=6,thickness=1})
		assert(metrics.failed==0,"Roof rim probe failed")
		for _,probe in crown:GetChildren() do if probe:IsA("BasePart") then
			probe.CanCollide=false;probe.CanQuery=true;probe.Transparency=1;probeOwners[probe]=model
		end end
	end end
	local peers=OverlapParams.new();peers.FilterType=Enum.RaycastFilterType.Include
	peers.FilterDescendantsInstances={folder}
	for probe,model in probeOwners do
		for _,other in workspace:GetPartsInPart(probe,params) do
			local own=false;for _,source in targets do if other:IsDescendantOf(source) then own=true break end end
			if not own then
				out.neighborIntersections+=1
				if #out.examples<15 then table.insert(out.examples,{id=model:GetAttribute("SourceSliceId"),part=probe.Name,neighbor=other:GetFullName()}) end
			end
		end
		for _,other in workspace:GetPartsInPart(probe,peers) do
			if probeOwners[other] and probeOwners[other]~=model then
				out.replacementIntersections+=1
				if #out.examples<15 then table.insert(out.examples,{id=model:GetAttribute("SourceSliceId"),part=probe.Name,neighbor=probeOwners[other]:GetAttribute("SourceSliceId")}) end
			end
		end
	end
	for _,model in stage:GetChildren() do if model:IsA("Model") then
		out.buildings+=1
		local plan=H:JSONDecode(model:GetAttribute("SourceSlicePlan"));local frame=model:GetAttribute("SourceSliceOriginCFrame")
		local ring=plan.levels[1].pieces[1]
		local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
		for _,p in ring do x0=math.min(x0,p[1]);x1=math.max(x1,p[1]);z0=math.min(z0,p[2]);z1=math.max(z1,p[2]) end
		for _,p in model:GetDescendants() do if p:IsA("BasePart") then
			out.partsTested+=1
			if p:HasTag("BuildingCore") then
				for _,x in {-1,1} do for _,z in {-1,1} do
					local q=frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(x*p.Size.X/2,0,z*p.Size.Z/2)))
					if math.min(q.X-x0,x1-q.X,q.Z-z0,z1-q.Z)<2.99 then out.coreClearanceErrors+=1 end
				end end
			end
		end end
	end end
end,debug.traceback)
folder:Destroy();assert(ok,err)
_G.FacadeBoxStageAudit=out
_G.FacadeBoxStageAuditStage=stage
assert(out.neighborIntersections==0 and out.replacementIntersections==0 and out.coreClearanceErrors==0,H:JSONEncode(out))
out.passed=true
return out
