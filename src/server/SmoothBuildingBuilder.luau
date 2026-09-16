--!nonstrict
-- Edit-time exact polygon floors. Visible edges never come from a sample grid.
-- Preview massing -> Build(report) in ServerStorage -> inspect -> Apply(stage).
local Smooth = {}
local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local SLAB, PITCH = 1.5/0.28, 5/0.28
local EPS = 1e-6

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function inside(poly,p)
	local yes=false
	for i,a in poly do
		local b=poly[i%#poly+1]
		local d=b-a
		local t=math.clamp((p-a):Dot(d)/math.max(d:Dot(d),1e-12),0,1)
		if (p-(a+d*t)).Magnitude<=EPS then return true end
		if (a.Y>p.Y)~=(b.Y>p.Y) and p.X<a.X+(p.Y-a.Y)*(b.X-a.X)/(b.Y-a.Y) then yes=not yes end
	end
	return yes
end

local function finite(n)
	return type(n)=="number" and n==n and math.abs(n)<math.huge
end

local function cross(a,b) return a.X*b.Y-a.Y*b.X end

-- Split a candidate edge at every boundary crossing, then classify each open
-- interval. This catches a segment crossing a concave inlet between its ends.
local function edgeInside(poly,a,b)
	if not inside(poly,a) or not inside(poly,b) then return false end
	local r=b-a
	local rr=r:Dot(r)
	local cuts={0,1}
	for i,c in poly do
		local d=poly[i%#poly+1]
		local s=d-c
		local denominator=cross(r,s)
		if math.abs(denominator)>EPS then
			local t,u=cross(c-a,s)/denominator,cross(c-a,r)/denominator
			if t>0 and t<1 and u>= -EPS and u<=1+EPS then table.insert(cuts,t) end
		elseif math.abs(cross(c-a,r))<=EPS then
			for _,p in {c,d} do
				local t=(p-a):Dot(r)/rr
				if t>0 and t<1 then table.insert(cuts,t) end
			end
		end
	end
	table.sort(cuts)
	for i=1,#cuts-1 do
		if cuts[i+1]-cuts[i]>EPS and not inside(poly,a+r*((cuts[i]+cuts[i+1])/2)) then return false end
	end
	return true
end

local function containsPolygon(outer,inner)
	for i,a in inner do if not edgeInside(outer,a,inner[i%#inner+1]) then return false end end
	return true
end

-- Liang-Barsky clipping against the cell's OPEN interior. A polygon boundary
-- entering a cell rejects it even if all corners and its center are inside.
local function edgeEntersCell(a,b,x0,z0,x1,z1)
	local lo,hi=0,1
	local delta=b-a
	for _,axis in {{a.X,delta.X,x0+EPS,x1-EPS},{a.Y,delta.Y,z0+EPS,z1-EPS}} do
		local origin,direction,minimum,maximum=table.unpack(axis)
		if minimum>=maximum then return true end
		if math.abs(direction)<=EPS then
			if origin<=minimum or origin>=maximum then return false end
		else
			local enter,leave=(minimum-origin)/direction,(maximum-origin)/direction
			if enter>leave then enter,leave=leave,enter end
			lo,hi=math.max(lo,enter),math.min(hi,leave)
			if hi<=lo then return false end
		end
	end
	return hi>lo
end

local function cellInside(poly,x0,z0,x1,z1)
	for _,p in {Vector2.new(x0,z0),Vector2.new(x1,z0),Vector2.new(x1,z1),Vector2.new(x0,z1)} do
		if not inside(poly,p) then return false end
	end
	for i,a in poly do if edgeEntersCell(a,poly[i%#poly+1],x0,z0,x1,z1) then return false end end
	return true
end

local function normalizedPlan(plan)
	local polygon=require(script.Parent.PolygonSlab)
	assert(type(plan)=="table" and finite(plan.height),"Invalid massing plan")
	assert(typeof(plan.frame)=="CFrame" and plan.frame.UpVector.Y>0.999999,"Massing frame must be upright")
	for _,n in {plan.frame:GetComponents()} do assert(finite(n),"Nonfinite massing frame") end
	assert(plan.height>=2*SLAB+2/0.28,"Massing is too short")
	local result={frame=plan.frame,height=plan.height,key=plan.key,tiers={}}
	local tiers=plan.tiers or {{bottom=0,top=plan.height,points=plan.points}}
	assert(type(tiers)=="table" and #tiers>0 and #tiers<=100,"Invalid tier list")
	local priorTop,priorPoints=0,nil
	for _,t in tiers do
		assert(finite(t.bottom) and finite(t.top) and t.top>t.bottom,"Invalid tier height interval")
		assert(math.abs(t.bottom-priorTop)<=EPS,"Tiers must be ordered, contiguous, and start at zero")
		assert(t.top<=plan.height+EPS,"Tier extends above massing height")
		local points=polygon.Validate(t.points)
		assert(not priorPoints or containsPolygon(priorPoints,points),"Upper tier extends outside its supporting lower tier")
		table.insert(result.tiers,{bottom=priorTop,top=t.top,points=points})
		priorTop,priorPoints=t.top,points
	end
	assert(math.abs(priorTop-plan.height)<=EPS,"Tiers must cover the full massing height")
	result.points=result.tiers[1].points
	return result
end

local function encodePlan(plan)
	local result={version=1,frame={plan.frame:GetComponents()},height=plan.height,tiers={},key=plan.key}
	for _,tier in plan.tiers or {{bottom=0,top=plan.height,points=plan.points}} do
		local row={bottom=tier.bottom,top=tier.top,points={}}
		for _,p in tier.points do table.insert(row.points,{p.X,p.Y}) end
		table.insert(result.tiers,row)
	end
	return Http:JSONEncode(result)
end

local function decodePlan(raw)
	local s=Http:JSONDecode(raw)
	assert(s.version==1,"Unknown smooth massing version")
	local p={frame=CFrame.new(table.unpack(s.frame)),height=s.height,key=s.key,tiers={}}
	for _,t in s.tiers do
		local points={}
		for _,v in t.points do table.insert(points,Vector2.new(v[1],v[2])) end
		table.insert(p.tiers,{bottom=t.bottom,top=t.top,points=points})
	end
	p.points=p.tiers[1].points
	return p
end

local function generate(building,plan,requestedFloors)
	local polygon=require(script.Parent.PolygonSlab)
	plan=normalizedPlan(plan)
	local h=plan.height
	local tiers=plan.tiers
	local n=requestedFloors or math.max(1,math.floor((h-SLAB)/PITCH))
	if not requestedFloors and #tiers>n then
		local tierPitch=(h-SLAB)/#tiers
		if tierPitch-SLAB>=2/0.28 then n=#tiers end
	end
	assert(finite(n) and n>=1 and n%1==0 and n<200,"Invalid floor count")
	local pitch=(h-SLAB)/n
	assert(pitch-SLAB>=2/0.28,"Requested floors leave less than 2m clear")
	local lo,hi=Vector2.new(math.huge,math.huge),Vector2.new(-math.huge,-math.huge)
	for _,t in tiers do
		for _,p in t.points do lo=lo:Min(p); hi=hi:Max(p) end
	end
	local center=(lo+hi)/2
	local size=Vector3.new(hi.X-lo.X,h,hi.Y-lo.Y)
	local cf=plan.frame*CFrame.new(center.X,h/2,center.Y)
	-- Snap deliberate tier changes to slab levels, keeping every floor complete.
	-- A measured setback can be thinner than the uniform floor pitch. Assign
	-- monotonic first-floor indices and reserve one floor per supported tier
	-- instead of rejecting an otherwise valid nested massing plan.
	assert(#tiers<=n,"More supported massing tiers than floors permitted by the 2m minimum clear height")
	local outlines,tierOutlines,firstFloor={},{},{1}
	for _,tier in tiers do
		local points={}
		for _,p in tier.points do table.insert(points,p-center) end
		tierOutlines[tier]=points
	end
	for index=2,#tiers do
		local ideal=math.ceil(tiers[index].bottom/pitch+0.5-1e-9)
		local earliest=firstFloor[index-1]+1
		local latest=n-(#tiers-index)
		firstFloor[index]=math.clamp(ideal,earliest,latest)
	end
	local tierIndex=1
	for k=1,n do
		while firstFloor[tierIndex+1] and k>=firstFloor[tierIndex+1] do tierIndex+=1 end
		outlines[k]=tierOutlines[tiers[tierIndex]]
	end
	-- Core layout uses only cells fully inside EVERY floor. This prevents the
	-- old core from disappearing where an upper setback no longer covered it.
	local cell=math.max(2,math.max(size.X,size.Z)/36)
	local nx,nz=math.ceil(size.X/cell),math.ceil(size.Z/cell)
	local bits=table.create(nx*nz,"0")
	for i=1,nx do for j=1,nz do
		local x0,z0=-size.X/2+(i-1)*cell,-size.Z/2+(j-1)*cell
		local x1,z1=math.min(x0+cell,size.X/2),math.min(z0+cell,size.Z/2)
		local fits=true
		for _,pts in tierOutlines do
			if not cellInside(pts,x0,z0,x1,z1) then fits=false; break end
		end
		if fits then bits[(i-1)*nz+j]="1" end
	end end
	local full=table.concat(bits)
	assert(full:find("1"),"No continuous core footprint")
	local grid={cell=cell,nx=nx,nz=nz,minX=-size.X/2,minZ=-size.Z/2,floors=n,
		ground=pitch-SLAB,clearUpper=pitch-SLAB,occ={},occTight={}}
	for k=1,n do grid.occ[k]=full; grid.occTight[k]=full end
	building:SetAttribute("InteriorGrid",Http:JSONEncode(grid))
	building:SetAttribute("InteriorBBoxCFrame",cf)
	building:SetAttribute("InteriorBBoxSize",size)
	building:SetAttribute("StructuralOnly",true)
	assert(require(script.Parent.BuildingGenerator).Generate(building),"Core generation failed")
	assert(building:GetAttribute("CoreSize"),"No usable continuous structural core")
	local interior=building.Interior
	local removed={}
	for _,p in interior:GetDescendants() do if p:IsA("BasePart") and p.Name=="Slab" then table.insert(removed,p) end end
	for _,p in removed do p:Destroy() end -- freshly generated staging geometry only
	local count,wedges=0,0
	for k=1,n+1 do
		-- At a setback the wider lower roof meets the smaller upper footprint.
		local points=outlines[math.max(1,k-1)]
		local floor=interior:FindFirstChild(k==n+1 and "Roof" or "Floor"..k)
		assert(floor,"Missing staged floor")
		local parts=polygon.Build(floor,points,-h/2+(k-1)*pitch,SLAB,cf,"Slab")
		for _,p in parts do count+=1; if p:IsA("WedgePart") then wedges+=1 end end
	end
	building:SetAttribute("SmoothMassing",encodePlan(plan))
	building:SetAttribute("SmoothFrame",building:GetPivot())
	building:SetAttribute("FootprintMode","ExactPolygon")
	building:SetAttribute("SmoothSlabParts",count)
	building:SetAttribute("SmoothWedgeParts",wedges)
	building:SetAttribute("SmoothTierCount",#tiers)
	building:SetAttribute("RequestedFloors",requestedFloors)
	return building
end

-- Standalone staging entry for deliberate authored massing and verification.
-- Returns an unparented complete Model; a failed build leaves no partial model.
function Smooth.StagePlan(name,plan,requestedFloors)
	editOnly()
	assert(type(name)=="string" and name:match("^Building"),"Building name must start with Building")
	local building=Instance.new("Model"); building.Name=name
	local ok,err=pcall(generate,building,plan,requestedFloors)
	if not ok then building:Destroy(); error(err,2) end
	return building
end

local function verifyStructure(building)
	assert(building:IsA("Model") and building:FindFirstChild("Interior") and building:GetAttribute("SmoothMassing"),"Missing smooth interior")
	local count=0
	for _,part in building.Interior:GetDescendants() do
		if part:IsA("BasePart") then
			assert((part:IsA("Part") or part:IsA("WedgePart") or part:IsA("PartOperation"))
				and part.Anchored and part.CanCollide,"Invalid smooth structural part")
			count+=1
		end
	end
	assert(count>0,"Empty smooth structure")
	local cf,size=building:GetBoundingBox()
	building:SetAttribute("InteriorBBoxCFrame",cf)
	building:SetAttribute("InteriorBBoxSize",size)
end

function Smooth.Build(report,options)
	editOnly(); options=options or {}
	assert(type(report)=="table" and type(report.plans)=="table","Provide a massing report")
	local seen,keys={},{}
	for _,p in report.plans do
		local old=p.oldModel
		assert(old and old.Parent==workspace.Buildings and old.Name:match("^BuildingAuto_") and not seen[old],"Replacement source changed or duplicated")
		assert(type(p.key)=="string" and #p.key>0,"Massing key must be nonempty text")
		assert(not keys[p.key],"Duplicate staged massing key")
		seen[old]=true
		keys[p.key]=true
	end
	local stage=Instance.new("Folder")
	stage.Name="ShibuyaSmoothStage_"..Http:GenerateGUID(false)
	stage:SetAttribute("SmoothStageVersion",1); stage.Parent=Storage
	local failures={}
	for i,p in report.plans do
		local old=p.oldModel
		local b=Instance.new("Model"); b.Name="BuildingSmooth_"..p.key
		local ok,err=pcall(generate,b,p,options.RequestedFloors)
		if ok then
			b:SetAttribute("ShibuyaSourceKey",p.key)
			b:SetAttribute("MassingConfidence",p.confidence)
			b:SetAttribute("MassingBasis",p.reason or "Simplified persistent facade outline")
			b:SetAttribute("SourceBaseY",p.sourceBaseY)
			b:SetAttribute("FloorCountBasis","Height estimate; simplified polygon massing")
			local link=Instance.new("ObjectValue"); link.Name="ReplacementSource"; link.Value=old; link.Parent=b
			b:SetAttribute("ReplacementSourcePivot",old:GetPivot())
			b.Parent=stage
		else b:Destroy(); table.insert(failures,{name=old.Name,reason=tostring(err)}) end
		if i%10==0 then task.wait() end
	end
	stage:SetAttribute("BuildFailures",#failures); stage:SetAttribute("Expected",#stage:GetChildren())
	print("SMOOTH_STAGED",#stage:GetChildren(),"ready",#failures,"failed",stage.Name)
	return stage,failures
end

function Smooth.Apply(stage)
	editOnly()
	assert(stage.Parent==Storage and stage:GetAttribute("SmoothStageVersion")==1 and not stage:GetAttribute("Applied"),"Invalid stage")
	local list=stage:GetChildren(); assert(#list>0 and #list==stage:GetAttribute("Expected"),"Incomplete stage")
	local seen,names={},{}
	for _,b in list do
		local link=b:FindFirstChild("ReplacementSource")
		assert(link and link:IsA("ObjectValue"),"Missing replacement identity")
		local old=link.Value
		assert(old and old.Parent==workspace.Buildings and old.Name:match("^BuildingAuto_") and not seen[old],"Source changed")
		assert(old:GetPivot()==b:GetAttribute("ReplacementSourcePivot"),"Source moved after staging")
		assert(not workspace.Buildings:FindFirstChild(b.Name),"A building already uses the staged name")
		assert(not names[b.Name],"Duplicate staged building name")
		verifyStructure(b)
		seen[old]=true
		names[b.Name]=true
	end
	local history=game:GetService("ChangeHistoryService"); history:SetWaypoint("Before smooth polygon replacements")
	local archive=Instance.new("Folder"); archive.Name="ShibuyaBeforeSmooth_"..Http:GenerateGUID(false); archive.Parent=Storage
	local moved={}
	local ok,err=pcall(function()
		for _,b in list do
			local old=b.ReplacementSource.Value
			table.insert(moved,{old=old,new=b})
			old.Parent=archive; b.Parent=workspace.Buildings
		end
	end)
	if not ok then for _,pair in moved do pair.old.Parent=workspace.Buildings; pair.new.Parent=stage end; error(err) end
	stage:SetAttribute("Applied",true); archive:SetAttribute("ReplacedCount",#list)
	history:SetWaypoint("Smooth polygon replacements")
	print("SMOOTH_APPLIED",#list,"recoverable originals",archive.Name)
	return archive
end

function Smooth.Regenerate(building,requestedFloors)
	editOnly()
	local prior=assert(building:FindFirstChild("Interior"),"Existing smooth interior is missing")
	local p=decodePlan(assert(building:GetAttribute("SmoothMassing"),"No saved polygon massing"))
	local saved=building:GetAttribute("SmoothFrame")
	if saved then p.frame=building:GetPivot()*saved:Inverse()*p.frame end
	local stage=Instance.new("Model"); stage.Name=building.Name
	local ok,err=pcall(generate,stage,p,requestedFloors or building:GetAttribute("RequestedFloors"))
	if not ok then stage:Destroy(); error(err) end
	local priorAttributes=building:GetAttributes()
	local fresh=stage.Interior
	local history=game:GetService("ChangeHistoryService")
	history:SetWaypoint("Before regenerating smooth building")
	local backup=Instance.new("Folder"); backup.Name="SmoothRegenerationBackup_"..Http:GenerateGUID(false); backup.Parent=Storage
	local applied,applyError=pcall(function()
		prior.Parent=backup
		fresh.Parent=building
		for key,value in stage:GetAttributes() do building:SetAttribute(key,value) end
		building:SetAttribute("SmoothFrame",building:GetPivot())
		verifyStructure(building)
	end)
	if not applied then
		fresh.Parent=stage
		prior.Parent=building
		for key in building:GetAttributes() do if priorAttributes[key]==nil then building:SetAttribute(key,nil) end end
		for key,value in priorAttributes do building:SetAttribute(key,value) end
		backup:Destroy(); stage:Destroy(); error(applyError,2)
	end
	stage:Destroy()
	history:SetWaypoint("Regenerated smooth building")
	return true,backup
end

return Smooth
