-- Edit-only disposable native geometry acceptance. Does not touch city models.
-- Run after syncing the current shared modules; every created object is removed.
local G=require(game.ReplicatedStorage.Shared.GroundFacadeInteriorGeometry)
local V=require(game.ReplicatedStorage.Shared.GlassVisual)
assert(G.VERSION==2,"Expected bay interior geometry v2")
local fixture=Instance.new("Folder");fixture.Name="DisposableBayInteriorProof";fixture.Parent=workspace
local report={cases={},occupancySamples=0,exteriorSamples=0,cornerPairs=0,glassChecks=0}
local base=CFrame.new(0,20000,0)
local function check(ok,message) assert(ok,message) end
local function part(parent,cf,size,shape)
	local p=Instance.new(shape or "Part");p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=true
	p.CFrame=cf;p.Size=size;p.Parent=parent;return p
end
local function run(root,cf,width,name)
	local r=Instance.new("Model");r.Name=name;r:SetAttribute("FacadeRunFrame",cf);r:SetAttribute("FacadeRunWidth",width);r.Parent=root
	local b=Instance.new("Model");b.Name="TenantBay";b.WorldPivot=cf;b:SetAttribute("FacadeType","proof")
	b:SetAttribute("FacadeWidth",width);b:SetAttribute("FacadeHeight",10);b.Parent=r
	for _,x in {-width*.25,width*.25} do
		local p=part(b,cf*CFrame.new(x,4,.15),Vector3.new(width*.44,7,.1));p.Name="ProofPane";p.Material=Enum.Material.Glass
		p.Transparency=.2;p.Reflectance=.1;V.Capture(p)
	end
	return b
end
local function rows(parent,c,source)
	for _,row in source do part(parent,c.frame*row.cframe,row.size,row.shape) end
end
local function hits(probe,target)
	local op=OverlapParams.new();op.FilterType=Enum.RaycastFilterType.Include;op.FilterDescendantsInstances={target}
	op.RespectCanCollide=false;return #workspace:GetPartsInPart(probe,op)>0
end
local function coverage(c,name)
	local solids=Instance.new("Folder");solids.Name=name.."Solids";solids.Parent=fixture;rows(solids,c,G.VolumeRows(c))
	local floor=Instance.new("Folder");floor.Name=name.."Floor";floor.Parent=fixture
	for _,row in G.Rows(c,19) do
		if (row.name=="BayInteriorHorizontal" or row.name=="BayInteriorTaperFill") and row.cframe.Y<c.bottom+.03 then
			part(floor,c.frame*row.cframe,row.size,row.shape)
		end
	end
	local probe=part(fixture,CFrame.new(),Vector3.new(.015,.015,.015))
	for _,t in {.08,.25,.5,.75,.92} do
		local l=c.left+(c.backLeft-c.left)*t;local r=c.right+(c.backRight-c.right)*t;local z=c.start+c.depth*t
		for _,u in {.06,.25,.5,.75,.94} do
			local x=l+(r-l)*u
			probe.CFrame=c.frame*CFrame.new(x,(c.bottom+c.top)/2,z)
			check(hits(probe,solids),name..": solid trapezoid missing sampled volume")
			probe.CFrame=c.frame*CFrame.new(x,c.bottom,z)
			check(hits(probe,floor),name..": wedge-filled floor missing sampled volume")
			report.occupancySamples+=2
		end
		for _,x in {l-.15,r+.15} do
			probe.CFrame=c.frame*CFrame.new(x,(c.bottom+c.top)/2,z)
			check(not hits(probe,solids),name..": trapezoid leaks outside analytic boundary")
			report.exteriorSamples+=1
		end
	end
	probe:Destroy();floor:Destroy();return solids
end
local function pair(name,yaw,offset,straight)
	local root=Instance.new("Folder");root.Name=name;root.Parent=fixture
	local width=12;local a=run(root,base*CFrame.new(-6,0,0),width,"RunA")
	local bcf
	if straight then bcf=base*CFrame.new(6,0,0)
	else
		local rotation=CFrame.Angles(0,yaw,0)
		bcf=base*CFrame.new(rotation.XVector*6+rotation.ZVector*(offset or 0))*rotation
	end
	local b=run(root,bcf,width,"RunB")
	local ca,why=G.PlanBay(a,root);check(ca,name..": A plan failed: "..tostring(why))
	local cb,whyB=G.PlanBay(b,root);check(cb,name..": B plan failed: "..tostring(whyB))
	local aa=coverage(ca,name.."A");local bb=coverage(cb,name.."B")
	for _,p in aa:GetChildren() do check(not hits(p,bb),name..": neighboring interior volumes intersect") end
	for _,p in bb:GetChildren() do check(not hits(p,aa),name..": inverse volume intersection") end
	local panes=G.Panes(a);local one=G.Plan(panes[1],root);local two=G.Plan(panes[2],root)
	check(one.frame==two.frame and one.left==two.left and one.right==two.right and one.backLeft==two.backLeft and one.backRight==two.backRight,
		name..": windows in same bay did not share identical room")
	check(math.abs(one.right-one.left)>panes[1].Size.X*1.5,name..": room incorrectly sized to individual pane")
	report.cornerPairs+=1;table.insert(report.cases,name)
	aa:Destroy();bb:Destroy();root:Destroy()
end
local function glass()
	local root=Instance.new("Folder");root.Parent=fixture
	local bay=run(root,base*CFrame.new(60,0,0),12,"GlassStateProof");bay:SetAttribute("FacadeBayInteriorVersion",2)
	local cell=assert(G.PlanBay(bay,root));local room=Instance.new("Folder");room.Name="BayInterior";room.Parent=bay
	rows(room,cell,G.Rows(cell,19));local panes=G.Panes(bay)
	local function visible(expected)
		for _,p in room:GetChildren() do check(p.Transparency==(expected and 0 or 1),"Shared room visibility does not match surviving panes") end
		report.glassChecks+=1
	end
	for _,p in panes do V.SetInteriorView(p,true);check(p.Transparency>=.649 and p.Reflectance<=.021,"Inlet glass did not become clearer") end
	V.RefreshBayInterior(bay);visible(true)
	V.Apply(panes[1],2,{textures=false});visible(true)
	V.Apply(panes[1],3,{textures=false});visible(true);check(panes[1].Transparency==1 and not panes[1].CanCollide,"State3 retained colored/colliding glass")
	V.Apply(panes[2],4,{textures=false});visible(false);check(panes[2].Parent==nil,"State4 did not remove pane")
	V.Apply(panes[1],1,{textures=false});visible(true)
	V.SetInteriorView(panes[1],false);check(math.abs(panes[1].Transparency-.2)<.001,"Exterior glass baseline did not restore")
	V.Apply(panes[1],4,{textures=false});visible(false)
	root:Destroy();table.insert(report.cases,"shared-room-glass-states")
end
local ok,err=xpcall(function()
	pair("right-angle",-math.pi/2,0,false)
	pair("acute-sixty",-2*math.pi/3,0,false)
	pair("straight-tenant-join",0,0,true)
	pair("offset-right-angle",-math.pi/2,.35,false)
	glass()
end,debug.traceback)
fixture:Destroy()
assert(ok,err)
report.passed=true
return report
