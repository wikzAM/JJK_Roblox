--!nonstrict
-- Edit-time preparation: one checked room recipe per bay, client detail at run
-- time. Only the previous explicit review buildings receive native Edit previews.
local Shared=game.ReplicatedStorage.Shared
local G=require(Shared.GroundFacadeInteriorGeometry)
local V=require(Shared.GlassVisual)
local H=game:GetService("HttpService")
local B={VERSION=2}
local OWNER="2026-10-08-ground-pilot"
local function seedOf(bay)
	local key=bay.Parent:GetAttribute("FacadeRunKey") or bay.Parent.Name
	key..="/"..tostring(bay:GetAttribute("FacadeSeed"));local seed=0
	for i=1,#key do seed=(seed*33+key:byte(i))%65521 end
	return seed
end
local function makePart(row,frame,parent)
	local p=Instance.new(row.shape or "Part");p.Name=row.name or "BayVolumeProbe";p.Size=row.size;p.CFrame=frame*row.cframe
	p.Color=row.color or Color3.new();p.Material=Enum.Material.SmoothPlastic
	p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
	p:SetAttribute("FacadeLayer","interior");p:SetAttribute("FacadePieceKind","preview")
	p:SetAttribute("FacadeBayInteriorPart",true);p:AddTag("NoCSG");p.Parent=parent;return p
end
function B.Preview(bay,cell,seed)
	local old=bay:FindFirstChild("BayInterior");if old then return old end
	local folder=Instance.new("Folder");folder.Name="BayInterior"
	folder:SetAttribute("FacadeBayInteriorVersion",2);folder:SetAttribute("EditPreview",true)
	for _,row in G.Rows(cell,seed) do makePart(row,cell.frame,folder) end
	folder.Parent=bay;V.RefreshBayInterior(bay);return folder
end
local function archiveLegacy(pane,archive)
	if not pane:GetAttribute("GlassInteriorStaticVersion") then return 0 end
	local holder=Instance.new("Folder");holder.Name="OldPaneCell";holder.Parent=archive
	local target=Instance.new("ObjectValue");target.Name="Pane";target.Value=pane;target.Parent=holder
	local n=0
	for _,p in pane:GetChildren() do if p:IsA("BasePart") and p:GetAttribute("FacadeInteriorTrialPart") then p.Parent=holder;n+=1 end end
	pane:SetAttribute("GlassInteriorStaticVersion",nil)
	for _,p in pane:GetChildren() do if p:IsA("BasePart") and p.Name=="InteriorWindowBacking" then
		p.Transparency=p:GetAttribute("InteriorBeforeTransparency") or 0
		p:SetAttribute("GlassFilmTransparency",p:GetAttribute("InteriorBeforeFilmTransparency") or 0)
	end end
	V.SetInteriorView(pane,false);return n
end
local function fit(bay,root,probeFolder,maxDepth,peers)
	local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances={root,probeFolder};params.RespectCanCollide=true;params.MaxParts=1
	local function clear(cell)
		local shape=G.Shape(cell)
		if peers then
			for other,s in peers do if other~=bay and G.OverlapShapes(shape,s) then return false end end
		else
			for _,other in root:GetDescendants() do if other~=bay and other:IsA("Model") and other:GetAttribute("FacadeBayInteriorVersion")==2 then
				local c=H:JSONDecode(other:GetAttribute("FacadeBayInteriorPlan"));c.frame=other:GetPivot()
				if G.OverlapShapes(shape,G.Shape(c)) then return false end
			end end
		end
		for _,row in G.VolumeRows(cell) do
			local p=makePart(row,cell.frame,probeFolder);p.Transparency=1
			local hit=workspace:GetPartsInPart(p,params);p:Destroy()
			if #hit>0 then return false end
		end
		return true
	end
	for _,depth in {3,2,1,.6,.4} do if depth>(maxDepth or 3)+.001 then continue end;local cell=G.PlanBay(bay,root,depth)
		if cell and clear(cell) then return cell end
	end
	return nil
end
function B.ConflictContext()
	local peers={}
	for _,bay in game.CollectionService:GetTagged("FacadeInteriorBay") do if bay:IsDescendantOf(workspace.Buildings) then
		local c=H:JSONDecode(bay:GetAttribute("FacadeBayInteriorPlan"));c.frame=bay:GetPivot();peers[bay]=G.Shape(c)
	end end
	return peers
end
function B.ResolveConflictBatch(pairs,peers)
	assert(not game:GetService("RunService"):IsRunning() and #pairs<=25,"Bounded Edit correction only")
	local probes=Instance.new("Folder");probes.Name="FacadeBayInteriorProbes";probes.Parent=workspace
	local out={shortened=0,fallback=0,alreadyClear=0}
	local ok,err=pcall(function() for _,pair in pairs do
		local a,b=pair.a,pair.b
		if not G.OverlapShapes(peers[a],peers[b]) then out.alreadyClear+=1;continue end
		local function rank(bay)
			return (bay.Parent:GetAttribute("FrontageClass")=="street" and 100 or 0)+#G.Panes(bay)
		end
		local loser=b;if rank(a)<rank(b) then loser=a end
		local root=loser:FindFirstAncestor("GroundFacadePilot")
		local old=H:JSONDecode(loser:GetAttribute("FacadeBayInteriorPlan"))
		local cell=fit(loser,root,probes,old.depth-.05,peers)
		local preview=loser:FindFirstChild("BayInterior")
		if preview then
			local holder=Instance.new("Folder");holder.Name="SharedPreviewBeforeConflict";holder.Parent=game.ServerStorage.FacadePerPaneInteriorBackup_v2
			local ref=Instance.new("ObjectValue");ref.Name="Bay";ref.Value=loser;ref.Parent=holder;preview.Parent=holder
		end
		if cell then
			local serial=table.clone(cell);serial.frame=nil
			loser:SetAttribute("FacadeBayInteriorPlan",H:JSONEncode(serial));loser:SetAttribute("FacadeBayInteriorFit","shortened to avoid irregular neighbor bay")
			peers[loser]=G.Shape(cell);out.shortened+=1
			if preview then B.Preview(loser,cell,loser:GetAttribute("FacadeBayInteriorSeed")) end
		else
			loser:SetAttribute("FacadeBayInteriorRejectedPlan",loser:GetAttribute("FacadeBayInteriorPlan"))
			loser:SetAttribute("FacadeBayInteriorPlan",nil);loser:SetAttribute("FacadeBayInteriorVersion",nil)
			loser:SetAttribute("FacadeBayInteriorFit","irregular overlap: flat backing retained");loser:RemoveTag("FacadeInteriorBay")
			peers[loser]=nil;out.fallback+=1
			for _,pane in G.Panes(loser) do V.SetInteriorView(pane,false)
				for _,p in pane:GetChildren() do if p:IsA("BasePart") and p.Name=="InteriorWindowBacking" then p.Transparency=0;p:SetAttribute("GlassFilmTransparency",0) end end
			end
		end
		task.wait()
	end end)
	probes:Destroy();if not ok then error(err) end;return out
end
function B.ApplyBatch(models,options)
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	assert(#models<=25,"Use synchronous batches of at most25 buildings")
	options=options or {};local out={buildings=0,bays=0,prepared=0,blocked=0,panes=0,previews=0,archivedLegacyParts=0,already=0}
	local archive=game.ServerStorage:FindFirstChild("FacadePerPaneInteriorBackup_v2")
	if not archive then archive=Instance.new("Folder");archive.Name="FacadePerPaneInteriorBackup_v2";archive:SetAttribute("Owner","bay-interior-migration-v2");archive.Parent=game.ServerStorage end
	assert(archive:GetAttribute("Owner")=="bay-interior-migration-v2")
	local probeFolder=Instance.new("Folder");probeFolder.Name="FacadeBayInteriorProbes";probeFolder.Parent=workspace
	local ok,err=pcall(function()
		for _,m in models do
			local root=assert(m:FindFirstChild("GroundFacadePilot"));assert(root:GetAttribute("Owner")==OWNER,"Unowned facade")
			out.buildings+=1
			for _,bay in root:GetDescendants() do if bay:IsA("Model") and bay:GetAttribute("FacadeType") then
				local panes=G.Panes(bay);if #panes==0 then continue end
				out.bays+=1
				if bay:GetAttribute("FacadeBayInteriorVersion")==2 then out.already+=1;continue end
				local cell=fit(bay,root,probeFolder)
				-- Retire the erroneous per-window cells even where a whole-bay
				-- recess cannot fit. The flat backing is the safe fallback there.
				for _,pane in panes do out.archivedLegacyParts+=archiveLegacy(pane,archive) end
				if not cell then bay:SetAttribute("FacadeBayInteriorFit","blocked: flat backing retained");out.blocked+=1;continue end
				local seed=seedOf(bay);local serial=table.clone(cell);serial.frame=nil
				bay:SetAttribute("FacadeBayInteriorPlan",H:JSONEncode(serial));bay:SetAttribute("FacadeBayInteriorFrame",cell.frame)
				bay:SetAttribute("FacadeBayInteriorSeed",seed);bay:SetAttribute("FacadeBayInteriorVersion",2)
				bay:SetAttribute("FacadeBayInteriorFit","native full-volume clearance");bay:AddTag("FacadeInteriorBay")
				for _,pane in panes do V.SetInteriorView(pane,true);out.panes+=1 end
				if options.preview==true or (options.preview==nil and m:GetAttribute("FacadeInteriorTrial")) then
					B.Preview(bay,cell,seed);out.previews+=1
					for _,pane in panes do for _,back in pane:GetChildren() do if back:IsA("BasePart") and back.Name=="InteriorWindowBacking" then back.Transparency=1;back:SetAttribute("GlassFilmTransparency",1) end end end
				end
				out.prepared+=1
				if out.bays%8==0 then task.wait() end
			end end
			m:SetAttribute("FacadeBayInteriorsVersion",2);root:SetAttribute("FacadeBayInteriorsVersion",2);task.wait()
		end
	end)
	probeFolder:Destroy();if not ok then error(err) end
	return out
end
-- One bounded, restartable edit step. A newly replaced facade root lacks this
-- completion marker even if its parent building was prepared previously.
function B.PrepareNextBatch()
	local pending={}
	for _,m in workspace.Buildings:GetChildren() do local root=m:FindFirstChild("GroundFacadePilot")
		if root and root:GetAttribute("Owner")==OWNER and root:GetAttribute("FacadeBayInteriorsVersion")~=2 then table.insert(pending,m) end
	end
	table.sort(pending,function(a,b)return a.Name<b.Name end)
	local batch={} for i=1,math.min(25,#pending) do table.insert(batch,pending[i]) end
	local result=B.ApplyBatch(batch);result.remainingBuildings=#pending-#batch;return result
end
return B
