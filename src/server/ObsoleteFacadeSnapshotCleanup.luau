-- Explicit, approval-gated cleanup of two reviewed generated-only snapshots.
-- Nothing runs on require. Recipes/reports and every other archive stay intact.
local C={VERSION=1,MAX_PARTS=1000}
local R=require(script.Parent.GroundFacadeRegistry)
local H=game:GetService("HttpService")
local OWNER="2026-10-08-ground-pilot"
local EXPECTED={BeforePerimeter_1791668032=100117,BeforePerimeter_1791668306=93642}
local contexts=setmetatable({},{__mode="k"})
local busy=false
local function guard()
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	assert(game.NetworkClient:FindFirstChildWhichIsA("ClientReplicator"),"Editing server disconnected")
end
local function recipes(snapshot)
	local reg=assert(snapshot:FindFirstChild("GroundFacadePilotManifest"),"Embedded recipes missing")
	assert(reg:GetAttribute("Owner")==OWNER,"Unowned recipes")
	local manifest,report=assert(R.Read(reg,"Manifest")),assert(R.Read(reg,"Report"))
	local rows=H:JSONDecode(manifest);local reports=H:JSONDecode(report).rows
	assert(#rows==200 and #reports==200,"Reviewed recipe count changed")
	local ids={};for _,row in rows do assert(type(row.id)=="string" and not ids[row.id],"Duplicate/invalid manifest identity");ids[row.id]=true end
	local seen={};for _,row in reports do assert(ids[row.id] and not seen[row.id],"Recipe/report identities differ");seen[row.id]=true end
	return reg,manifest,report,ids
end
-- Read-only. Refuses already-partially-cleaned snapshots; retain context while
-- connected. After interruption, inspect remaining geometry before a new plan.
function C.Prepare()
	guard();assert(not busy,"Cleanup already running")
	local parent=assert(game.ServerStorage:FindFirstChild("GroundFacadePilotArchive"))
	local ctx={snapshots={},roots={},parts={},partRoots={},rootSnapshots={},rootNames={},protected={},cursor=1,approved=false}
	local depths={}
	for name,expected in EXPECTED do
		local snapshot=assert(parent:FindFirstChild(name),"Reviewed snapshot missing: "..name)
		local reg,manifest,report,ids=recipes(snapshot)
		ctx.protected[reg]=true;for _,item in reg:GetDescendants() do ctx.protected[item]=true end
		local n,roots=0,0
		for _,child in snapshot:GetChildren() do if child~=reg then
			assert(child:IsA("Folder") and child:GetAttribute("Owner")==OWNER and ids[child.Name],"Unexpected snapshot child")
			table.insert(ctx.roots,child);ctx.rootSnapshots[child]=snapshot;ctx.rootNames[child]=child.Name;roots+=1
			for _,p in child:GetDescendants() do if p:IsA("BasePart") then
				assert(not p:HasTag("BuildingCore") and not p:HasTag("StationInfrastructure"),"Protected geometry in snapshot")
				table.insert(ctx.parts,p);ctx.partRoots[p]=child;n+=1
				local depth,parent=0,p.Parent;while parent and parent~=child do depth+=1;parent=parent.Parent end;depths[p]=depth
			end end
			task.wait();guard()
		end end
		assert(n==expected and roots==200,"Reviewed geometry count changed")
		table.insert(ctx.snapshots,{folder=snapshot,registry=reg,manifest=manifest,report=report})
	end
	assert(#ctx.roots==400 and #ctx.parts==193759)
	table.sort(ctx.parts,function(a,b)return depths[a]>depths[b] end)
	contexts[ctx]=true
	return ctx,{copies=#ctx.roots,parts=#ctx.parts,recipes=400,requiresExplicitApproval=true}
end
-- The calling operator must supply the human's explicit approval for these
-- exact two snapshots; prior approval of a different cleanup does not qualify.
function C.Approve(ctx,authorization)
	guard();assert(contexts[ctx] and not busy)
	assert(type(authorization)=="string" and #authorization>=20,"Record the explicit human approval")
	ctx.approved=authorization
end
function C.Step(ctx)
	guard();assert(contexts[ctx] and ctx.approved,"Explicit approval required")
	assert(not busy,"Cleanup already running");busy=true
	local ok,result=pcall(function()
		for _,s in ctx.snapshots do
			assert(s.folder.Parent==game.ServerStorage.GroundFacadePilotArchive)
			assert(s.registry.Parent==s.folder,"Recipe registry moved; stop")
			assert(R.Read(s.registry,"Manifest")==s.manifest and R.Read(s.registry,"Report")==s.report,"Recipes changed; stop")
		end
		for _,root in ctx.roots do
			assert(root.Parent==ctx.rootSnapshots[root] and root.Name==ctx.rootNames[root] and root:GetAttribute("Owner")==OWNER,"Reviewed root moved/changed; stop")
		end
		local last=math.min(#ctx.parts,ctx.cursor+C.MAX_PARTS-1)
		for i=ctx.cursor,last do
			local p=ctx.parts[i]
			if p.Parent then
				local root=ctx.partRoots[p]
				assert(root.Parent==ctx.rootSnapshots[root] and p:IsDescendantOf(root),"Target moved out of its reviewed root; stop")
				assert(not p:HasTag("BuildingCore") and not p:HasTag("StationInfrastructure"),"Target became protected; stop")
				for _,d in p:GetDescendants() do
					assert(not ctx.protected[d],"Recipe data moved under a cleanup target; stop")
					assert(not d:IsA("BasePart"),"Unexpected child geometry; stop before cascading destruction")
					assert(not d:HasTag("BuildingCore") and not d:HasTag("StationInfrastructure"),"Protected child; stop")
				end
				for _,s in ctx.snapshots do assert(s.registry.Parent==s.folder and not s.registry:IsDescendantOf(p),"Recipe registry moved; stop") end
				local contained=false
				for _,s in ctx.snapshots do if p:IsDescendantOf(s.folder) and not p:IsDescendantOf(s.registry) then contained=true break end end
				assert(contained,"Target moved out of reviewed snapshot; stop")
				p:Destroy()
			end
			ctx.cursor=i+1
			if i%100==0 then
				task.wait();guard()
				for _,s in ctx.snapshots do
					assert(s.registry.Parent==s.folder,"Recipe registry moved; stop")
					assert(R.Read(s.registry,"Manifest")==s.manifest and R.Read(s.registry,"Report")==s.report,"Recipes changed; stop")
				end
			end
		end
		local remaining=0
		if ctx.cursor>#ctx.parts then
			for _,root in ctx.roots do
				assert(root.Parent==ctx.rootSnapshots[root] and root.Name==ctx.rootNames[root] and root:GetAttribute("Owner")==OWNER,"Reviewed root moved/changed; stop")
				for _,s in ctx.snapshots do assert(s.registry.Parent==s.folder,"Recipe registry moved; stop") end
				for _,p in root:GetDescendants() do assert(not p:IsA("BasePart") and not p:HasTag("BuildingCore") and not p:HasTag("StationInfrastructure"),"Unexpected remaining/protected geometry") end
				root:Destroy()
			end
			for _,s in ctx.snapshots do
				assert(R.Read(s.registry,"Manifest")==s.manifest and R.Read(s.registry,"Report")==s.report)
				s.folder:SetAttribute("GeometryCleanupAuthorization",ctx.approved)
				s.folder:SetAttribute("GeometryCleanupParts",EXPECTED[s.folder.Name])
				s.folder:SetAttribute("GeometryCleanupRecipeCopies",200)
			end
		else remaining=#ctx.parts-ctx.cursor+1 end
		return {processed=ctx.cursor-1,queued=#ctx.parts,remaining=remaining,complete=remaining==0}
	end)
	busy=false
	if not ok then error(result,2) end
	return result
end
return C
