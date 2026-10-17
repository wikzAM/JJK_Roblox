--!nonstrict
-- Explicit edit-only legacy core repair. No startup hook or geometry regeneration.
local M={}
local H=game:GetService("HttpService")
local S=game:GetService("ServerStorage")
local C=game:GetService("CollectionService")
local Adapter=require(game:GetService("ReplicatedStorage").Shared.FacadeLegacyPlan)
local NAMES={CoreWallFront=true,CoreWallBack=true,CoreWallRight=true,CoreWallLeft=true,CoreDividerX=true,CoreDividerZ=true}
local function editOnly()assert(not game:GetService("RunService"):IsRunning(),"Edit only")end
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function area(p)
	if #p<3 then return 0 end;local o=p[1];local sum=0
	for i,a in p do local b=p[i%#p+1];sum+=(a[1]-o[1])*(b[2]-o[2])-(b[1]-o[1])*(a[2]-o[2]) end
	return math.abs(sum/2)
end
local function cross(a,b,p)return (b[1]-a[1])*(p[2]-a[2])-(b[2]-a[2])*(p[1]-a[1])end
local function clipped(subject,convex)
	local output=subject
	for i,a in convex do
		if #output==0 then break end
		local b=convex[i%#convex+1];local input=output;output={};local previous=input[#input];local ps=cross(a,b,previous)
		for _,p in input do local side=cross(a,b,p)
			if (side>=0)~=(ps>=0) then local t=ps/(ps-side);table.insert(output,{previous[1]+(p[1]-previous[1])*t,previous[2]+(p[2]-previous[2])*t}) end
			if side>=0 then table.insert(output,p) end;previous=p;ps=side
		end
	end
	return area(output)
end
local function sameCF(a,b)
	if typeof(a)~="CFrame" or typeof(b)~="CFrame" then return false end
	local q=a:ToObjectSpace(b);return q.Position.Magnitude<.025 and q.RightVector.X>.99999 and q.UpVector.Y>.99999
end
local function excluded(m,options)
	if m.Parent~=workspace:FindFirstChild("Buildings") or m:GetAttribute("SourceSlicePlan") then return "Not a live legacy building" end
	for _,flag in {"Landmark","CrownInteresting","StationInfrastructure","FacadeExcluded"} do if m:GetAttribute(flag) or C:HasTag(m,flag) then return "Protected "..flag end end
	if options.exclude and options.exclude[m] then return "Explicit exclusion" end
	local id=m:GetAttribute("FacadeSourceId") or "legacy/"..m.Name
	if options.excludeIds and options.excludeIds[id] then return "Explicit ID exclusion" end
end
local function auditOne(m,options)
	local reason=excluded(m,options);assert(not reason,reason)
	local geometry,why=Adapter.Read(m);assert(geometry,why)
	local coreCF,coreSize=m:GetAttribute("CoreCFrame"),m:GetAttribute("CoreSize")
	assert(typeof(coreCF)=="CFrame" and typeof(coreSize)=="Vector3" and coreCF.UpVector.Y>.99999 and math.min(coreSize.X,coreSize.Z)>=4,"Invalid core metadata")
	local interior=assert(m:FindFirstChild("Interior"),"Missing Interior")
	local parts,slabs,perFloor={},{},{}
	local ex,ez,minX,minZ=0,0,math.huge,math.huge
	for _,p in interior:GetDescendants() do if p:IsA("BasePart") then
		if p.Name=="Slab" then table.insert(slabs,{part=p,cf=p.CFrame,size=p.Size,parent=p.Parent}) end
		if C:HasTag(p,"BuildingCore") then
			assert(p:IsA("Part") and p.Shape==Enum.PartType.Block and p.Anchored and p.CanCollide and p.CanQuery and #p:GetChildren()==0 and NAMES[p.Name],"Noncanonical legacy core part")
			local q=coreCF:ToObjectSpace(p.CFrame)
			assert(math.abs(q.RightVector.X)>.99999 and math.abs(q.UpVector.Y)>.99999 and math.abs(q.ZVector.Z)>.99999,"Core piece rotated outside metadata axes")
			assert(math.abs(q.Y)+p.Size.Y/2<=coreSize.Y/2+.03,"Core part leaves vertical metadata")
			local names=perFloor[p.Parent] or {};assert(not names[p.Name],"Duplicate per-floor core piece");names[p.Name]=true;perFloor[p.Parent]=names
			ex=math.max(ex,math.abs(q.X)+p.Size.X/2);ez=math.max(ez,math.abs(q.Z)+p.Size.Z/2)
			minX=math.min(minX,p.Size.X);minZ=math.min(minZ,p.Size.Z)
			table.insert(parts,{part=p,parent=p.Parent,cf=p.CFrame,size=p.Size,relative=q})
		end
	end end
	assert(#parts==6*m:GetAttribute("GeneratedFloors"),"Legacy per-floor core count disagrees")
	for _,names in perFloor do for name in NAMES do assert(names[name],"Incomplete per-floor core") end end
	assert(math.abs(ex-coreSize.X/2-minX/2)<.04 and math.abs(ez-coreSize.Z/2-minZ/2)<.04,"Outer wall envelope disagrees with centerline metadata")
	local q=geometry.frame:ToObjectSpace(coreCF)
	assert(q.UpVector.Y>.99999,"Core and validated facade frame disagree")
	local function fits(sx,sz)
		local ring={};local x,z=ex*sx+options.margin+.015,ez*sz+options.margin+.015
		for _,a in {{-x,-z},{x,-z},{x,z},{-x,z}} do
			table.insert(ring,{q.X+q.RightVector.X*a[1]+q.ZVector.X*a[2],q.Z+q.RightVector.Z*a[1]+q.ZVector.Z*a[2]})
		end
		local expected=area(ring);local tolerance=math.max(.0001,expected*1e-8)
		for _,l in geometry.plan.levels do local coverage=0;for _,p in l.pieces do coverage+=clipped(p,ring) end;if math.abs(coverage-expected)>tolerance then return false end end
		return true
	end
	local result={id=geometry.id,model=m,status="unchanged",geometry=geometry,parts=parts,slabs=slabs,coreCF=coreCF,coreSize=coreSize,options=options,source=m:GetAttribute("SmoothMassing"),facadePlan=m:GetAttribute("FacadeSourcePlan"),oldRevision=m:GetAttribute("FacadeLegacyCoreRevision"),oldMargin=m:GetAttribute("FacadeLegacyCoreMargin")}
	if fits(1,1) then return result end
	local lowX=math.max(4/coreSize.X,.4/minX,1-options.maxInset/ex)
	local lowZ=math.max(4/coreSize.Z,.4/minZ,1-options.maxInset/ez)
	if lowX>1 or lowZ>1 or not fits(lowX,lowZ) then result.status="skipped";result.reason="Cannot retain minimum core/wall thickness and 3-stud clearance within 6-stud per-edge shrink";return result end
	local lo,hi=0,1
	for _=1,32 do local t=(lo+hi)/2;if fits(lowX+(1-lowX)*t,lowZ+(1-lowZ)*t) then lo=t else hi=t end end
	local sx,sz=lowX+(1-lowX)*lo,lowZ+(1-lowZ)*lo
	local function expand(x,z,first)
		for _,axis in {first,not first} do local a,b=axis and x or z,1
			for _=1,32 do local t=(a+b)/2;if fits(axis and t or x,axis and z or t) then a=t else b=t end end
			if axis then x=a else z=a end
		end
		return x,z
	end
	local ax,az=expand(sx,sz,true);local bx,bz=expand(sx,sz,false);if bx*bz>ax*az then ax,az=bx,bz end
	ax=math.max(lowX,ax-.01/ex);az=math.max(lowZ,az-.01/ez)
	assert(ax<=1 and az<=1 and fits(ax,az),"Final bounded legacy clearance proof failed")
	result.status="ready";result.scaleX=ax;result.scaleZ=az;result.insetX=ex*(1-ax);result.insetZ=ez*(1-az)
	result.newCoreSize=Vector3.new(coreSize.X*ax,coreSize.Y,coreSize.Z*az)
	for _,s in parts do
		local p=s.relative;s.newSize=Vector3.new(s.size.X*ax,s.size.Y,s.size.Z*az)
		s.newCF=coreCF*CFrame.new(p.X*ax,p.Y,p.Z*az)*p.Rotation
		assert(s.newSize.X<=s.size.X+.0001 and s.newSize.Z<=s.size.Z+.0001 and math.min(s.newSize.X,s.newSize.Z)>=.3999,"Unsafe wall scale")
	end
	return result
end
function M.Audit(models,options)
	editOnly();options=table.clone(options or {});options.margin=options.margin or 3;options.maxInset=options.maxInset or 6
	assert(finite(options.margin) and options.margin>=3 and options.margin<=6 and finite(options.maxInset) and options.maxInset>0 and options.maxInset<=6,"Bounded margin/inset required")
	local result={revision=9,rows={},ready=0,unchanged=0,skipped=0};local seen={}
	for _,m in models do assert(typeof(m)=="Instance" and m:IsA("Model") and not seen[m],"Unique explicit model list required");seen[m]=true
		local ok,r=pcall(auditOne,m,options);if not ok then r={model=m,id=m:GetAttribute("FacadeSourceId") or "legacy/"..m.Name,status="skipped",reason=tostring(r)} end
		table.insert(result.rows,r);result[r.status]+=1;task.wait()
	end
	return result
end
M.Plan=M.Audit
local function stale(r)
	assert(not excluded(r.model,r.options),"Legacy target became excluded")
	assert(r.model:GetAttribute("SmoothMassing")==r.source and r.model:GetAttribute("FacadeSourcePlan")==r.facadePlan and r.model:GetAttribute("CoreCFrame")==r.coreCF and r.model:GetAttribute("CoreSize")==r.coreSize,"Legacy metadata changed after Audit")
	for _,list in {r.parts,r.slabs} do for _,s in list do assert(s.part.Parent==s.parent and s.part.CFrame==s.cf and s.part.Size==s.size,"Legacy native geometry changed after Audit") end end
end
function M.Rollback(backup)
	editOnly();assert(backup:GetAttribute("LegacyCoreBackupRevision")==9,"Pass legacy core backup")
	for _,e in backup:GetChildren() do assert(e.Target.Value and e.Target.Value.Parent,"Missing backup building");for _,s in e:GetChildren() do if s:IsA("Folder") then assert(s.Target.Value and s.Target.Value.Parent,"Missing backup core") end end end
	for _,e in backup:GetChildren() do local model=e.Target.Value
		model:SetAttribute("CoreSize",e:GetAttribute("CoreSize"));model:SetAttribute("FacadeLegacyCoreRevision",e:GetAttribute("OldRevision"));model:SetAttribute("FacadeLegacyCoreMargin",e:GetAttribute("OldMargin"))
		for _,s in e:GetChildren() do if s:IsA("Folder") then s.Target.Value.Size=s:GetAttribute("Size");s.Target.Value.CFrame=s:GetAttribute("CFrame") end end;task.wait()
	end
	backup:SetAttribute("State","rolledBack")
end
function M.Apply(report)
	editOnly();assert(report.revision==9 and report.rows,"Pass explicit audit report")
	local ready={};for _,r in report.rows do if r.status=="ready" then stale(r);table.insert(ready,r) end end
	if #ready==0 then return {changed=0} end
	local backup=Instance.new("Folder");backup.Name="FacadeLegacyCoreBackup_"..H:GenerateGUID(false);backup:SetAttribute("LegacyCoreBackupRevision",9);backup:SetAttribute("State","preparing");backup.Parent=S
	for i,r in ready do local e=Instance.new("Folder");e.Name=tostring(i);e:SetAttribute("Id",r.id);e:SetAttribute("CoreSize",r.coreSize);e:SetAttribute("OldRevision",r.oldRevision);e:SetAttribute("OldMargin",r.oldMargin)
		local target=Instance.new("ObjectValue");target.Name="Target";target.Value=r.model;target.Parent=e
		for j,s in r.parts do local p=Instance.new("Folder");p.Name=tostring(j);p:SetAttribute("CFrame",s.cf);p:SetAttribute("Size",s.size)
			local ref=Instance.new("ObjectValue");ref.Name="Target";ref.Value=s.part;ref.Parent=p;local clone=s.part:Clone();clone.Name="ReferenceGeometry";clone.Parent=p;p.Parent=e
		end;e.Parent=backup;task.wait()
	end
	backup:SetAttribute("State","prepared")
	local ok,err=pcall(function()for _,r in ready do stale(r)
		for _,s in r.parts do s.part.Size=s.newSize;s.part.CFrame=s.newCF;assert((s.part.Size-s.newSize).Magnitude<.025 and sameCF(s.part.CFrame,s.newCF),"Native legacy resize failed") end
		r.model:SetAttribute("CoreSize",r.newCoreSize);r.model:SetAttribute("FacadeLegacyCoreRevision",9);r.model:SetAttribute("FacadeLegacyCoreMargin",r.options.margin);task.wait()
	end end)
	if not ok then local restored,why=pcall(M.Rollback,backup);error(tostring(err)..(restored and " (batch rolled back)" or " (rollback failed: "..tostring(why)..")"),2) end
	backup:SetAttribute("State","applied");backup:SetAttribute("Changed",#ready);return {changed=#ready,backup=backup}
end
return M
