-- Read-only acceptance for the installed-building road/frontage correction.
-- Requires fresh expected rows from Frontage.Survey in _G.FrontageV10Expected.
-- Counts genuine access/size/structure exceptions separately from violations.
local H=game:GetService("HttpService")
local R=require(game.ServerScriptService.Server.GroundFacadeRegistry)
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
local expected=_G.FrontageV10Expected
if not expected then
 local F=require(game.ServerScriptService.Server.GroundFacadeFrontage)
 local scene=F.Index(Vector3.zero,100000);expected={}
 for _,b in scene.buildings do if b.model:FindFirstChild("GroundFacadePilot") then expected[b.id]=F.Survey(scene,b);task.wait() end end
end
local report=H:JSONDecode(R.ReadLatest(game.ServerStorage.GroundFacadePilotManifest,"Report"))
local out={hasOriginalBaseline=_G.FrontageV10Baseline~=nil,buildings=0,faces=0,roadFronts=0,roadEntrances=0,quietFaces=0,quietEntrances=0,
	unsafeOrSmallFronts={},errors={},originalParts=0,originalChanges=0}
local models={}
for _,m in workspace.Buildings:GetChildren() do models[m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId") or m.Name]=m end
for _,row in report.rows do
	local target=expected[row.id];assert(target,"Unexpected installed building: "..row.id)
	local m=assert(models[row.id]);assert(m:FindFirstChild("GroundFacadePilot"))
	local faces={};for _,f in row.faces do faces[f.piece.."/"..f.run]=f end
	for _,want in target.faces do
		out.faces+=1
		local got=faces[want.piece.."/"..want.run]
		if not got then table.insert(out.errors,{id=row.id,run=want.run,reason="Missing perimeter run"})
		elseif want.class~="front" then
			out.quietFaces+=1;out.quietEntrances+=got.portals or 0
			if (got.portals or 0)>0 then table.insert(out.errors,{id=row.id,run=want.run,reason="Entrance without a verified public approach"}) end
		else
			out.roadFronts+=1;out.roadEntrances+=got.portals or 0
			assert(want.road and (want.road.way or 0)>0,"Unverified expected frontage")
			if (got.portals or 0)==0 then
				table.insert(out.unsafeOrSmallFronts,{id=row.id,piece=want.piece,run=want.run,width=want.width,height=want.height,fit=got.fitReason,vetoes=got.vetoes,types=got.types})
			end
		end
	end
	out.buildings+=1;task.wait()
end
for p,before in _G.FrontageV10Baseline or {} do
	out.originalParts+=1
	if not p.Parent or p.CFrame~=before[1] or p.Size~=before[2] or p.Color~=before[3] then out.originalChanges+=1 end
end
assert(out.originalChanges==0,"Original source geometry changed")
_G.FrontageV10Audit=out
return out
