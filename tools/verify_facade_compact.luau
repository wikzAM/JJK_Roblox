-- Connected Edit fixture only. Disposable synthetic building, never city repair.
local C=require(game.ServerScriptService.Server.GroundFacadeCompact)
local building=Instance.new("Model");building.Name="DisposableFacadeCompactProof"
local root=Instance.new("Folder");root.Name="GroundFacadePilot";root:SetAttribute("Owner","2026-10-08-ground-pilot");root.Parent=building
local bays,glass,before={}, {},{}
local archive,probe
local report={nativeSamples=0,glassChecks=0,referenceChecks=0,restoreChecks=0}
local function count(parent)local n=0;for _,p in parent:GetDescendants() do if p:IsA("BasePart") then n+=1 end end;return n end
local function make(parent,name,cf,size)
	local p=Instance.new("Part");p.Name=name;p.CFrame=cf;p.Size=size;p.Anchored=true;p.CanTouch=false;p.Parent=parent;return p
end
local function verifyCoverage()
	for _,bay in bays do
		local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Include
		local walls={};for _,p in bay:GetChildren() do if p.Name=="OpaqueFront" then table.insert(walls,p) end end
		op.FilterDescendantsInstances=walls
		for x=-5,5,.5 do for y=-.5,9.5,.5 do
			-- Avoid exact cell boundaries to test solid membership unambiguously.
			local xx,yy=x+.137,y+.173
			probe.CFrame=bay:GetPivot()*CFrame.new(xx,yy,0)
			local expected=xx>-4.5 and xx<4.5 and yy>0 and yy<9 and not (xx>-1.5 and xx<1.5 and yy>3 and yy<6)
			assert((#workspace:GetPartsInPart(probe,op)>0)==expected,"Native merged wall hole/exterior mismatch")
			report.nativeSamples+=1
		end end
	end
end
local function verifyGlass()
	for _,g in glass do
		assert(g.p.Parent==g.bay and g.p.CFrame==g.cf and g.p.Size==g.size and g.p:GetAttribute("GlassPaneId")==g.id and g.p:HasTag("GlassPane") and g.p.CanCollide,"Glass instance/geometry/identity changed")
		report.glassChecks+=1
	end
end
local ok,err=xpcall(function()
	for index=1,6 do
		local bay=Instance.new("Model");bay.Name="Bay"..index;bay.WorldPivot=CFrame.new(index*20,20000,0);bay:SetAttribute("FacadeType","proof");bay:SetAttribute("FacadeRole","entrance")
		bay:SetAttribute("FacadeBayInteriorVersion",2);bay:SetAttribute("FacadeBayInteriorPlan","proof-recipe-unchanged");bay.Parent=root;table.insert(bays,bay)
		local snapshots={};before[bay]=snapshots
		for x=-1,1 do for y=0,2 do if x~=0 or y~=1 then
			local p=make(bay,"OpaqueFront",bay:GetPivot()*CFrame.new(x*3,y*3+1.5,0),Vector3.new(3,3,.75))
			p.Material=Enum.Material.Concrete;p.Color=Color3.fromRGB(170,168,160);p:SetAttribute("FacadePieceKind","wall");p:SetAttribute("FacadeLayer","exterior");p:SetAttribute("ProofPreserved",27);p:AddTag("NoCSG")
			table.insert(snapshots,{cf=p.CFrame,size=p.Size,color=p.Color})
		end end end
		local g=make(bay,"Window",bay:GetPivot()*CFrame.new(0,4.5,-.45),Vector3.new(2.8,2.8,.1));g:AddTag("GlassPane");g:AddTag("NoCSG")
		local id="compact-proof/"..index;g:SetAttribute("GlassPaneId",id);table.insert(glass,{p=g,bay=bay,cf=g.CFrame,size=g.Size,id=id})
		local sign=make(bay,"Sign",bay:GetPivot()*CFrame.new(0,10,-.5),Vector3.new(8,1,.1))
		local gui=Instance.new("SurfaceGui");gui.Name="FacadeTypography";gui.Parent=sign
		local label=Instance.new("TextLabel");label.Name="Label";label.BackgroundTransparency=1;label.BorderSizePixel=0;label.Size=UDim2.fromScale(1,1);label.Text="検証";label.Parent=gui
		local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(.04,0);pad.PaddingRight=UDim.new(.04,0);pad.PaddingTop=UDim.new(.08,0);pad.PaddingBottom=UDim.new(.08,0);pad.Parent=label
	end
	building.Parent=workspace.Buildings
	probe=make(workspace,"DisposableCompactProbe",CFrame.new(),Vector3.new(.01,.01,.01));probe.CanCollide=false
	verifyCoverage();verifyGlass()
	assert(not pcall(C.ProveUnion,{{0,1,0,1},{2,3,0,1}},{{0,3,0,1}}),"Union proof accepted a filled hole")
	assert(not pcall(C.ProveUnion,{{0,1,0,1}},{{0,2,0,1}}),"Union proof accepted exterior growth")
	-- Any directly referenced wall is skipped, without changing live geometry.
	local references=Instance.new("Folder");references.Parent=building
	local walls=0
	for _,bay in bays do for _,p in bay:GetChildren() do if p.Name=="OpaqueFront" then local r=Instance.new("ObjectValue");r.Value=p;r.Parent=references;walls+=1 end end end
	local blocked=C.Plan({building});assert(blocked.summary.partsBefore==0 and blocked.summary.skippedReferences==walls,"Referenced walls were not refused");report.referenceChecks=walls
	references:Destroy()
	local initial=count(building);local plan=C.Plan({building})
	assert(plan.summary.partsBefore==48 and plan.summary.partsAfter<48 and plan.summary.paddings==6,"Unexpected compact fixture plan")
	local result=C.Apply(plan);archive=assert(game.ServerStorage:FindFirstChild(result.archive))
	assert(count(building)==initial-result.netPartsRemoved,"Part count reduction mismatch")
	assert(#archive:GetDescendants()<result.netPartsRemoved+6,"Recipe instances erased the fixture savings")
	verifyCoverage();verifyGlass()
	for _,bay in bays do assert(bay:GetAttribute("FacadeRole")=="entrance" and bay:GetAttribute("FacadeBayInteriorPlan")=="proof-recipe-unchanged","Bay metadata changed") end
	local restored=C.Restore(archive);assert(restored.restoredParts==48 and restored.restoredPaddings==6 and count(building)==initial,"Restore counts differ")
	verifyCoverage();verifyGlass()
	for _,bay in bays do
		local actual={};for _,p in bay:GetChildren() do if p.Name=="OpaqueFront" then table.insert(actual,p) end end
		assert(#actual==8)
		for _,original in before[bay] do local matched=false
			for _,p in actual do if p.CFrame==original.cf and p.Size==original.size and p.Color==original.color then
				assert(p:GetAttribute("ProofPreserved")==27 and p:HasTag("NoCSG"));matched=true;break
			end end
			assert(matched,"Original descriptor did not restore exact geometry");report.restoreChecks+=1
		end
	end
	report.partsRemoved=result.netPartsRemoved;report.proofSamples=plan.summary.proofSamples;report.passed=true
end,debug.traceback)
if probe then probe:Destroy() end
building:Destroy()
if archive then archive:Destroy() end -- This archive belongs ONLY to the synthetic fixture.
assert(ok,err)
return report
