--!nonstrict
-- Edit-mode self-test for UpperFacadeKit (Studio command bar, after a Rojo sync).
-- Builds every variant, crown, palette and a synthetic stepped L-shaped building on a
-- disposable Model at Y=20000, checks the mounting contract, destroys it, returns a report.
-- Read-only for the city: nothing outside the disposable model is touched.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Kit=require(Shared.UpperFacadeKit)
local Catalog=require(Shared.UpperFacadeCatalog)
local Http=game:GetService("HttpService")
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
local BUDGET=14 -- hard ceiling, parts per 10 studs of run at width 40 incl. fixed overhead (target <= 12)
local report={variants={},failures={},overBudget={},variantCount=#Catalog.VARIANTS,familyCount=#Catalog.FAMILIES,picks={},buildings={}}
local root=Instance.new("Model");root.Name="UpperFacadeKitSelfTest";root.Parent=workspace
local function fail(where,msg) if #report.failures<80 then table.insert(report.failures,where..": "..msg) end end
local function checkRun(where,model,expectGlass)
	local frame,width=model:GetAttribute("FacadeRunFrame"),model:GetAttribute("FacadeWidth")
	local parts,panes,ids=0,0,{}
	for _,p in model:GetDescendants() do if p:IsA("BasePart") then
		parts+=1
		if not p.Anchored then fail(where,p.Name.." not anchored") end
		if p.CanTouch then fail(where,p.Name.." CanTouch") end
		if not p:HasTag("NoCSG") then fail(where,p.Name.." missing NoCSG") end
		if p:GetAttribute("FacadeLayer")~="exterior" then fail(where,p.Name.." FacadeLayer") end
		local kind=p:GetAttribute("FacadePieceKind")
		if p:HasTag("GlassPane") then
			panes+=1
			local id=p:GetAttribute("GlassPaneId")
			if type(id)~="string" or not id:match("/bay%d+/pane%d+$") then fail(where,"bad GlassPaneId "..tostring(id)) end
			if ids[id] then fail(where,"duplicate pane id "..tostring(id)) end;ids[id]=true
			if kind~="glass" then fail(where,"pane kind "..tostring(kind)) end
		elseif kind~="wall" then fail(where,p.Name.." kind "..tostring(kind)) end
		if p.Size.X<.05 or p.Size.Y<.05 or p.Size.Z<.05 then fail(where,p.Name.." undersize") end
		local cf=frame:ToObjectSpace(p.CFrame);local s=p.Size/2
		local lo,hi=Vector3.one*math.huge,-Vector3.one*math.huge
		for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do local q=cf*Vector3.new(x*s.X,y*s.Y,z*s.Z);lo=lo:Min(q);hi=hi:Max(q) end end end
		if hi.Z>Kit.REAR+1e-3 then fail(where,string.format("%s rear Z %.3f > %.2f",p.Name,hi.Z,Kit.REAR)) end
		if lo.Z<Kit.FRONT-.02 then fail(where,string.format("%s front Z %.3f",p.Name,lo.Z)) end
		if hi.X>width/2+.01 or lo.X<-width/2-.01 then fail(where,p.Name.." outside run width") end
	end end
	if expectGlass and panes==0 then fail(where,"no glass") end
	return parts,panes
end
local function build(where,width,height,spec,options,cf)
	local ok,m=pcall(Kit.BuildFloorRun,root,cf,width,height,spec,options)
	if not ok then fail(where,tostring(m));return nil end
	return m
end
local crowns={};for _,c in Catalog.CROWNS do table.insert(crowns,c[1]) end
local x=0
for vi,v in Catalog.VARIANTS do
	local fam=Catalog.Family(v.family)
	local row={id=v.id,family=v.family}
	local function frame() x+=90;return CFrame.new(x,20000,0)*CFrame.Angles(0,math.rad(37*vi),0) end
	local pal=fam.palettes[vi%#fam.palettes+1]
	local base={palette=pal,slab=1.5,primary=true,storey=3,cycleOffset=vi}
	-- 1. typical 40-stud floor-run: budget, glass, ids
	local o=table.clone(base);o.key="selftest/"..v.id.."/typical"
	local m=build(v.id.."/typical",40,12.5,v,o,frame())
	if m then
		row.parts,row.panes=checkRun(v.id.."/typical",m,v.corridor==nil)
		row.per10=math.floor(row.parts/4*10+.5)/10
		if row.per10>BUDGET then table.insert(report.overBudget,v.id.." "..row.per10) end
	end
	-- 2. every option at once: corners, blade, AC, rail, alternate band, scaled module
	o=table.clone(base);o.key="selftest/"..v.id.."/loaded";o.cornerLeft=1.05;o.cornerRight=.4;o.ac=true;o.rail=true
	o.blade={side=vi%2==0 and 1 or -1,width=2.2,color=Color3.fromRGB(196,46,42)};o.bandColor=Color3.fromRGB(120,120,120);o.moduleScale=1.2;o.sillScale=.85;o.headScale=1.2
	m=build(v.id.."/loaded",44,14,v,o,frame());if m then row.loadedParts=checkRun(v.id.."/loaded",m,false) end
	-- 3. side (non-primary), low and tall storeys, top floor with each crown
	for _,case in {{"side",22,8,false},{"tall",63,30,true},{"low",18,8,true}} do
		o=table.clone(base);o.key="selftest/"..v.id.."/"..case[1];o.primary=case[4]
		m=build(v.id.."/"..case[1],case[2],case[3],v,o,frame());if m then checkRun(v.id.."/"..case[1],m,false) end
	end
	o=table.clone(base);o.key="selftest/"..v.id.."/crown";o.top=true;o.cap=1.5;o.crown=crowns[vi%#crowns+1]
	m=build(v.id.."/crown/"..o.crown,36,12.5,v,o,frame());if m then checkRun(v.id.."/crown",m,false) end
	-- 4. narrow run becomes exactly one solid panel
	o=table.clone(base);o.key="selftest/"..v.id.."/narrow"
	m=build(v.id.."/narrow",4,12.5,v,o,frame())
	if m and #m:GetChildren()~=1 then fail(v.id.."/narrow","expected 1 solid part, got "..#m:GetChildren()) end
	-- 5. height outside [8,30] must be refused
	for _,h in {7.9,30.1} do if pcall(Kit.Layout,20,h,v,{key="x"}) then fail(v.id,"accepted height "..h) end end
	table.insert(report.variants,row)
end
-- Every palette at least once (resolves materials, no Enum errors).
for _,f in Catalog.FAMILIES do for pi,pal in f.palettes do
	x+=90;local m=build("palette/"..pal,30,12.5,Catalog.Get(f.quiet),{key="selftest/pal/"..pal,palette=pal,slab=1.5},CFrame.new(x,20000,200))
	if m then checkRun("palette/"..pal,m,false) end
end end
-- Deterministic, varied picks.
local varCount,varSeen=0,{}
for _,class in Catalog.CLASSES do
	local fams={}
	for i=1,400 do
		local seed="selftest_seed_"..i
		local a,b=Catalog.Pick(seed,class),Catalog.Pick(seed,class)
		if Http:JSONEncode(a)~=Http:JSONEncode(b) then fail("pick","nondeterministic "..seed) end
		fams[a.family]=(fams[a.family] or 0)+1;varSeen[a.variant]=true
	end
	report.picks[class]=fams
end
for _ in varSeen do varCount+=1 end
report.variantsReachable=varCount
if varCount<24 then fail("pick","only "..varCount.." variants reachable") end
-- Synthetic stepped L-shaped building: convex + concave corners, setback parapets, roof cap.
local L={{0,0},{60,0},{60,30},{30,30},{30,50},{0,50}}
local S={{0,0},{34,0},{34,30},{0,30}}
local levels={}
for i=1,7 do table.insert(levels,{y=(i-1)*14,thickness=1.5,pieces={i<=4 and L or S}}) end
local b=Instance.new("Model");b.Name="BuildingUpperSelfTest"
local anchor=Instance.new("Part");anchor.Anchored=true;anchor.Size=Vector3.one;anchor.CFrame=CFrame.new(5000,20000,5000);anchor.Parent=b
b:SetAttribute("SourceSliceId","selftest_upper");b:SetAttribute("SourceSliceOriginCFrame",CFrame.new(5000,20000,5000)*CFrame.Angles(0,math.rad(20),0))
b:SetAttribute("SourceSlicePlan",Http:JSONEncode({levels=levels}));b.Parent=root
local raw={[60]=true,[30]=true,[20]=true,[50]=true,[34]=true}
for _,f in Catalog.FAMILIES do
	local ok,folder,r=pcall(Kit.BuildBuilding,b,{family=f.id})
	if not ok then fail("building/"..f.id,tostring(folder));continue end
	if folder:GetAttribute("Owner")~=Kit.OWNER or folder.Name~="UpperFacade" or folder.Parent~=b then fail("building/"..f.id,"folder contract") end
	local extended=0
	for _,run in folder:GetChildren() do if run:IsA("Model") then
		checkRun("building/"..f.id.."/"..run.Name,run,false)
		local w=run:GetAttribute("FacadeWidth") or 0
		if not raw[math.floor(w+.5)] or math.abs(w-math.floor(w+.5))>.05 then extended+=1 end
	end end
	if #b:GetChildren()~=2 then fail("building/"..f.id,"stale UpperFacade folders") end
	r.extendedRuns=extended;r.skippedCount=#r.skipped;r.skipped=nil
	table.insert(report.buildings,r)
end
local again=Kit.PlanBuilding(b,{}).style;local once=Kit.PlanBuilding(b,{}).style
if Http:JSONEncode(again)~=Http:JSONEncode(once) then fail("building","style not deterministic") end
report.defaultStyle=once
root:Destroy()
report.ok=#report.failures==0
print("[UpperFacadeKit self-test]",report.ok and "PASS" or "FAIL",#report.variants,"variants,",#report.failures,"failures,",#report.overBudget,"over budget")
for _,line in report.failures do warn(line) end
for _,v in report.variants do print(string.format("  %-22s parts %3s  panes %3s  per10 %s",v.id,tostring(v.parts),tostring(v.panes),tostring(v.per10))) end
return report
