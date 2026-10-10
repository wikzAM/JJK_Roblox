-- Studio-only contract checks. Run with a fresh GlassDraftRuntime dependency group.
local R=game.ServerStorage:FindFirstChild("FacadeScopeRuntime") or game.ServerStorage.GroundFacadeDraftRuntime
local G=require(R.GlassGeometry);local V=require(R.GlassVisual);local D=require(R.GlassDamageService)
local H=game:GetService("HttpService")
local function near(a,b)assert(math.abs(a-b)<1e-3,tostring(a).." != "..tostring(b))end
near(G.SegmentBoxDistance(Vector3.new(-4,0,0),Vector3.new(4,0,0),CFrame.identity,Vector3.new(2,2,2)),0)
near(G.SegmentBoxDistance(Vector3.new(-4,3,0),Vector3.new(4,3,0),CFrame.identity,Vector3.new(2,2,2)),2)
near(G.SegmentBoxDistance(Vector3.new(3,3,3),Vector3.new(3,3,3),CFrame.identity,Vector3.new(2,2,2)),math.sqrt(12))
local rng=Random.new(1738)
local allowed=Instance.new("Model")
assert(not G.GeneratedEnabled(allowed),"Unselected buildings must not receive generated glass")
local pilot=Instance.new("Folder");pilot.Name="GroundFacadePilot";pilot.Parent=allowed
pilot:SetAttribute("Owner","2026-10-08-ground-pilot");allowed:SetAttribute("GroundFacadeOwnedRuns",'{"1/1":true}')
assert(G.GeneratedEnabled(allowed),"Owned pilot must remain eligible")
pilot:SetAttribute("Owner","other");assert(not G.GeneratedEnabled(allowed),"Name alone cannot opt a building into the trial")
allowed:Destroy()
for i=1,128 do
	local a=Vector3.new(rng:NextNumber(-30,30),rng:NextNumber(-30,30),rng:NextNumber(-30,30))
	local b=Vector3.new(rng:NextNumber(-30,30),rng:NextNumber(-30,30),rng:NextNumber(-30,30))
	local cf=CFrame.new(1,2,3)*CFrame.Angles(.3,.8,.2);local size=Vector3.new(13,8,1)
	local exact=G.SegmentBoxDistance(a,b,cf,size);local sampled=math.huge
	for j=0,200 do local p=a:Lerp(b,j/200);sampled=math.min(sampled,G.SegmentBoxDistance(p,p,cf,size)) end
	assert(exact<=sampled+1e-4 and sampled-exact<(b-a).Magnitude/200+.001,string.format("Segment/OBB mismatch: exact %.9f sampled %.9f length %.4f case %d",exact,sampled,(b-a).Magnitude,i))
end
local cells=G.Split({cframe=CFrame.identity,size=Vector3.new(61,29,.3),storey=1,piece=2,run=3})
assert(#cells==18);local area=0;local keys={}
for _,c in cells do assert(not keys[c.key]);keys[c.key]=true;area+=c.size.X*c.size.Y;assert(c.size.X<=12 and c.size.Y<=12) end
near(area,61*29)
local parent=Instance.new("Model");parent.Name="GlassContractTest";parent:SetAttribute("Owner","verify-glass");parent.Parent=game.ServerStorage
local function pane(x)
	local p=Instance.new("Part");p.Name="TestPane";p.Anchored=true;p.Size=Vector3.new(8,8,.2);p.CFrame=CFrame.new(x,1605,-60)
	p.Material=Enum.Material.Glass;p.Color=Color3.fromRGB(35,99,119);p.Transparency=.3;p.Reflectance=.2;p.Parent=parent
	V.Capture(p,"test/"..x,true);return p
end
local p=pane(0);local film=Instance.new("Part");film.Name="PrivacyFilm";film.Transparency=.2;film.Parent=p
V.Apply(p,2);assert(p.CanCollide and math.abs(p.Transparency-.3)<1e-5 and #p:GetChildren()==3)
V.Apply(p,3);assert(not p.CanCollide and p.Transparency==1 and p.Reflectance==0 and film.Transparency==1)
assert(#p:GetChildren()==3,"Broken edges replace cracks")
V.Apply(p,1);assert(p.CanCollide and math.abs(p.Transparency-.3)<1e-5 and math.abs(film.Transparency-.2)<1e-5 and #p:GetChildren()==1)
V.Apply(p,4);assert(not p.Parent)
local weak=pane(20)
local r=D.Impact(weak.Position,Vector3.new(8,0,0),{radius=1,models={parent}})
assert(r.changed==1 and D.GetState(parent,"test/20")==2 and weak.CanCollide)
r=D.Impact(weak.Position,Vector3.new(90,0,0),{radius=1,models={parent}})
assert(r.changed==1 and D.GetState(parent,"test/20")==3 and not weak.CanCollide and weak.Transparency==1)
assert(not D.SetPane(parent,"test/20",2,weak),"Damage cannot heal implicitly")
assert(D.SetPane(parent,"test/20",4,weak) and not weak.Parent)
assert(D.GetState(parent,"test/20")==4)
-- Far shockwave cracks while inner radius shatters; snapshot keeps both states.
local a,b=pane(0),pane(25)
r=D.Shockwave(a.Position,{shatterRadius=4,crackRadius=25,models={parent}})
assert(a:GetAttribute("GlassState")==3 and b:GetAttribute("GlassState")==2)
local f=game.ReplicatedStorage.GlassDamageState:FindFirstChild(parent.Name)
assert(f and #f:GetChildren()>0)
parent:SetAttribute("FacadeVersion",1)
assert(D.GetState(parent,"test/25")==1 and #f:GetChildren()==0,"Geometry invalidation clears all old pages")
D.Reset(parent);assert(a.CanCollide and math.abs(a.Transparency-.3)<1e-5)
-- A pane outside the structural hole is still removed if it sits in the
-- support-clearance margin. Cracked panes begin beyond that margin.
local removedNear,removedMargin,crackedOuter,intact=pane(110),pane(119),pane(125),pane(140)
for _,window in {removedNear,removedMargin,crackedOuter,intact} do window.Size=Vector3.new(2,6,.2) end
D.DestroyPath(Vector3.new(100,1605,-60),Vector3.new(100,1605,-60),8,{models={parent}})
assert(not removedNear.Parent and not removedMargin.Parent,"Hole margin must use state 4")
assert(D.GetState(parent,"test/110")==4 and D.GetState(parent,"test/119")==4)
assert(crackedOuter.Parent and crackedOuter.CanCollide and D.GetState(parent,"test/125")==2,"Only the outer band cracks")
assert(D.GetState(parent,"test/140")==1 and intact.CanCollide,"Distant panes must remain intact")
f:Destroy();parent:Destroy()
return {segmentCases=131,partitionCells=18,states=4,weakStrongShockwave=true,persistentPages=true,pilotScope=true,destructionClearance=true}
