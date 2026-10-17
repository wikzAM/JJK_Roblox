--!nonstrict
-- EDIT ONLY. Audit/Plan never mutate. Apply accepts only an explicit audit result.
-- Source-slice common cores only; this is intentionally not a general CSG repair.
local Core = {}
local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local Collection = game:GetService("CollectionService")
local Builder = require(script.Parent.SourceSliceBuilder)
local Layout = require(game:GetService("ReplicatedStorage").Shared.FacadeLayout)
local NAMES = {"CoreWallFront", "CoreWallBack", "CoreWallRight", "CoreWallLeft", "CoreDividerX", "CoreDividerZ"}
local ATTRIBUTES = {"SourceSlicePlan", "CoreCFrame", "CoreSize", "FacadeCoreClearanceRevision", "FacadeCoreClearanceMargin"}
local function editOnly() assert(not game:GetService("RunService"):IsRunning(), "Stop Play before core editing") end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function sameCF(a,b)
	if typeof(a)~="CFrame" or typeof(b)~="CFrame" then return false end
	local q=a:ToObjectSpace(b)
	return q.Position.Magnitude<.025 and q.RightVector:Dot(Vector3.xAxis)>.99999 and q.UpVector:Dot(Vector3.yAxis)>.99999
end
local function signedArea(ring)
	if #ring<3 then return 0 end
	local sum=0; local o=ring[1]
	for i,a in ring do local b=ring[i%#ring+1];sum+=(a[1]-o[1])*(b[2]-o[2])-(b[1]-o[1])*(a[2]-o[2]) end
	return sum/2
end
-- Clip a possibly concave simple polygon to an axis-aligned rectangle. Artificial
-- connectors between disconnected clipped lobes cancel in the signed area.
local function clippedArea(ring,r)
	-- Keep numeric pairs throughout: Vector2 stores float32 and can introduce
	-- enough clipped-area jitter to break the monotonic containment search.
	local out={};for _,v in ring do table.insert(out,{v[1],v[2]}) end
	for _,edge in {{1,r.minX,1},{1,r.maxX,-1},{2,r.minZ,1},{2,r.maxZ,-1}} do
		if #out==0 then break end
		local input=out;out={}
		local function side(p) return (p[edge[1]]-edge[2])*edge[3] end
		local prior=input[#input];local ps=side(prior)
		for _,p in input do
			local s=side(p)
			if (s>=0)~=(ps>=0) then
				local t=ps/(ps-s)
				table.insert(out,{prior[1]+(p[1]-prior[1])*t,prior[2]+(p[2]-prior[2])*t})
			end
			if s>=0 then table.insert(out,p) end
			prior=p;ps=s
		end
	end
	return math.abs(signedArea(out))
end
local function rectangle(cx,cz,w,d,margin)
	return {minX=cx-w/2-margin,maxX=cx+w/2+margin,minZ=cz-d/2-margin,maxZ=cz+d/2+margin}
end
local function covered(plan,r)
	local expected=(r.maxX-r.minX)*(r.maxZ-r.minZ)
	-- Tiny numeric area tolerance, not a geometric clearance allowance. Actual
	-- requested margin gets an extra .01 stud before this coverage test.
	local tolerance=math.max(.0001,expected*1e-8)
	for i,level in plan.levels do
		local total=0;for _,ring in level.pieces do total+=clippedArea(ring,r) end
		if math.abs(total-expected)>tolerance then return false,i,expected-total end
	end
	return true
end
local function specs(c,bottom,top)
	local x,z=(c.minX+c.maxX)/2,(c.minZ+c.maxZ)/2
	local w,d,h,y=c.maxX-c.minX,c.maxZ-c.minZ,top-bottom,(bottom+top)/2
	return {
		{Vector3.new(w,h,1),Vector3.new(x,y,c.maxZ-.5)},
		{Vector3.new(w,h,1),Vector3.new(x,y,c.minZ+.5)},
		{Vector3.new(1,h,d-2),Vector3.new(c.maxX-.5,y,z)},
		{Vector3.new(1,h,d-2),Vector3.new(c.minX+.5,y,z)},
		{Vector3.new(w-2,h,1),Vector3.new(x,y,z)},
		{Vector3.new(1,h,d-2),Vector3.new(x,y,z)},
	}
end
local function protected(model,options)
	if not model:IsDescendantOf(workspace:FindFirstChild("Buildings")) then return "Not a live city building" end
	if model:GetAttribute("StructuralOnly")~=true then return "Not ordinary StructuralOnly source-slice geometry" end
	for _,name in {"Landmark","CrownInteresting","StationInfrastructure","FacadeExcluded"} do
		if model:GetAttribute(name) or Collection:HasTag(model,name) then return "Protected "..name end
	end
	if options.exclude and options.exclude[model] then return "Explicit exclusion" end
	if options.excludeIds and options.excludeIds[model:GetAttribute("SourceSliceId")] then return "Explicit ID exclusion" end
end
local function auditOne(model,options)
	local exclusion=protected(model,options);assert(not exclusion,exclusion)
	local raw=assert(model:GetAttribute("SourceSlicePlan"),"Missing source plan")
	local plan=Http:JSONDecode(raw)
	assert(#plan.levels>=2 and #plan.levels-1<=options.maxFloors,"Outside allowed floor count")
	assert(model:GetAttribute("GeneratedFloors")==#plan.levels-1,"Floor count metadata disagrees")
	-- Canonical validator proves simple polygon pieces, no double coverage, and
	-- the old core lies within every union; otherwise summed areas could lie.
	plan=Builder.Validate(plan)
	assert(model:GetAttribute("SourceSliceId")==plan.id,"Source identity metadata disagrees")
	local frame=assert(Layout.FrameOf(model),"Missing source frame")
	assert(frame.UpVector.Y>.999999,"Tilted source frame")
	local c=plan.core;local w,d=c.maxX-c.minX,c.maxZ-c.minZ
	local x,z=(c.minX+c.maxX)/2,(c.minZ+c.maxZ)/2
	local first,last=plan.levels[1],plan.levels[#plan.levels]
	local interior=assert(model:FindFirstChild("Interior"),"Missing Interior")
	local floor=assert(interior:FindFirstChild("Floor1"),"Missing Floor1")
	local oldSpecs=specs(c,first.y+first.thickness,last.y)
	local parts,seen={},{}
	for _,part in interior:GetDescendants() do
		if part:IsA("BasePart") and (part:GetAttribute("SourceSliceCore") or Collection:HasTag(part,"BuildingCore")) then
			local i=table.find(NAMES,part.Name)
			assert(i and not seen[i] and part.Parent==floor and part:IsA("Part"),"Noncanonical or duplicated core piece")
			assert(part.Anchored and part.CanCollide and part.CanQuery and #part:GetChildren()==0,"Modified core flags or attached decoration")
			assert(part:GetAttribute("SourceSliceCore")==true and Collection:HasTag(part,"BuildingCore"),"Missing core provenance")
			assert((part.Size-oldSpecs[i][1]).Magnitude<.025 and sameCF(part.CFrame,frame*CFrame.new(oldSpecs[i][2])),"Live core differs from saved source plan")
			seen[i]=true;parts[i]=part
		end
	end
	for i=1,6 do assert(parts[i],"Expected exactly six common core walls") end
	local oldSize=Vector3.new(w,last.y+last.thickness-first.y,d)
	local oldCF=frame*CFrame.new(x,(first.y+last.y+last.thickness)/2,z)
	assert(typeof(model:GetAttribute("CoreSize"))=="Vector3" and (model:GetAttribute("CoreSize")-oldSize).Magnitude<.025 and sameCF(model:GetAttribute("CoreCFrame"),oldCF),"Stale common core metadata")
	local margin=options.margin+.01
	local function fits(a,b) return covered(plan,rectangle(x,z,a,b,margin)) end
	local result={model=model,id=plan.id,status="unchanged",originalPlan=raw,frame=frame,parts=parts,margin=options.margin,options=options}
	result.oldCore=table.clone(c)
	if fits(w,d) then return result end
	if w<options.minimum or d<options.minimum then result.status="skipped";result.reason="Existing core is narrower than the retained minimum; never enlarge a core";return result end
	local minW,minD=math.max(options.minimum,w-2*options.maxInset),math.max(options.minimum,d-2*options.maxInset)
	if not fits(minW,minD) then result.status="skipped";result.reason="Required clearance needs more than the bounded core inset or loses the retained minimum";return result end
	local lo,hi=0,1
	for _=1,32 do local t=(lo+hi)/2;if fits(minW+(w-minW)*t,minD+(d-minD)*t) then lo=t else hi=t end end
	local sw,sd=minW+(w-minW)*lo,minD+(d-minD)*lo
	-- Grow one axis then the other; test both orders and keep greater retained
	-- area. Every accepted candidate gets the exact all-level union proof.
	local function expand(a,b,firstX)
		for _,axis in {firstX,not firstX} do
			local low,high=axis and a or b,axis and w or d
			for _=1,32 do local n=(low+high)/2;if fits(axis and n or a,axis and b or n) then low=n else high=n end end
			if axis then a=low else b=low end
		end
		return a,b
	end
	local aw,ad=expand(sw,sd,true);local bw,bd=expand(sw,sd,false)
	if bw*bd>aw*ad then aw,ad=bw,bd end
	-- Small additional shrink avoids native float32 roundoff eating margin.
	aw=math.max(minW,aw-.02);ad=math.max(minD,ad-.02)
	assert(fits(aw,ad),"Final clearance proof failed")
	result.status="ready";result.core=rectangle(x,z,aw,ad,0)
	plan.core=result.core;result.updatedPlan=Http:JSONEncode(plan)
	result.specs=specs(result.core,first.y+first.thickness,last.y)
	result.updatedCoreSize=Vector3.new(aw,oldSize.Y,ad)
	result.snapshot={}
	for i,part in parts do result.snapshot[i]={part=part,parent=part.Parent,cf=part.CFrame,size=part.Size} end
	result.attributeSnapshot=model:GetAttributes()
	return result
end
function Core.Audit(models,options)
	editOnly();assert(type(models)=="table" and #models>0,"Provide an explicit nonempty building list")
	options=table.clone(options or {});options.margin=options.margin or 3;options.minimum=options.minimum or 4;options.maxFloors=options.maxFloors or 15;options.maxInset=options.maxInset or 6
	assert(finite(options.maxInset) and options.maxInset>=3 and options.maxInset<=6,"Core inset is bounded to six studs per edge")
	assert(finite(options.margin) and options.margin>=3 and options.margin<=10,"Clearance must be 3-10 studs")
	assert(finite(options.minimum) and options.minimum>=4,"Minimum core must be at least 4 studs")
	assert(options.maxFloors>=1 and options.maxFloors<=15,"Only ordinary buildings up to 15 floors")
	local report={revision=9,precision="double-number-pairs-v2",auditedAt=os.clock(),rows={},ready=0,unchanged=0,skipped=0,options=options};local seen={}
	for _,model in models do
		assert(typeof(model)=="Instance" and model:IsA("Model") and not seen[model],"Unique explicit Models required");seen[model]=true
		local ok,row=pcall(auditOne,model,options)
		if not ok then row={model=model,id=model:GetAttribute("SourceSliceId"),status="skipped",reason=tostring(row)} end
		table.insert(report.rows,row);report[row.status]+=1;task.wait()
	end
	return report
end
Core.Plan=Core.Audit
local function stale(row)
	assert(row.model:GetAttribute("SourceSlicePlan")==row.originalPlan and sameCF(Layout.FrameOf(row.model),row.frame),"Plan or source placement changed after Audit")
	for _,name in ATTRIBUTES do assert(row.model:GetAttribute(name)==row.attributeSnapshot[name],"Core metadata changed after Audit") end
	local reason=protected(row.model,row.options);assert(not reason,reason)
	for _,s in row.snapshot do
		assert(s.part.Parent==s.parent and s.part.CFrame==s.cf and s.part.Size==s.size,"Core changed after Audit")
	end
end
function Core.Rollback(backup)
	editOnly();assert(backup and backup:GetAttribute("FacadeCoreBackupRevision")==9,"Pass a v9 core backup")
	local entries=backup:GetChildren()
	for _,entry in entries do
		assert(entry.Target.Value and entry.Target.Value.Parent,"A backed-up building no longer exists")
		for _,saved in entry:GetChildren() do if saved:IsA("Folder") then assert(saved.Target.Value and saved.Target.Value.Parent,"A backed-up core wall no longer exists") end end
	end
	for _,entry in entries do
		local model=entry.Target.Value
		for _,name in ATTRIBUTES do model:SetAttribute(name,entry:GetAttribute("Before_"..name)) end
		for _,saved in entry:GetChildren() do if saved:IsA("Folder") then saved.Target.Value.CFrame=saved:GetAttribute("CFrame");saved.Target.Value.Size=saved:GetAttribute("Size") end end
		task.wait()
	end
	backup:SetAttribute("State","rolledBack")
end
function Core.Apply(report)
	editOnly();assert(report.revision==9 and report.rows,"Pass a report from Audit/Plan")
	local ready={};for _,row in report.rows do if row.status=="ready" then stale(row);table.insert(ready,row) end end
	if #ready==0 then return {changed=0,backup=nil} end
	local backup=Instance.new("Folder");backup.Name="FacadeCoreClearanceBackup_"..Http:GenerateGUID(false)
	backup:SetAttribute("FacadeCoreBackupRevision",9);backup:SetAttribute("State","preparing");backup.Parent=Storage
	-- Prepare every backup BEFORE touching any original. These are property
	-- records plus six reference clones, not duplicated floors or world geometry.
	for index,row in ready do
		local entry=Instance.new("Folder");entry.Name=tostring(index);entry:SetAttribute("SourceSliceId",row.id)
		for _,name in ATTRIBUTES do entry:SetAttribute("Before_"..name,row.model:GetAttribute(name)) end
		local target=Instance.new("ObjectValue");target.Name="Target";target.Value=row.model;target.Parent=entry
		for i,s in row.snapshot do
			local saved=Instance.new("Folder");saved.Name=NAMES[i];saved:SetAttribute("CFrame",s.cf);saved:SetAttribute("Size",s.size)
			local ref=Instance.new("ObjectValue");ref.Name="Target";ref.Value=s.part;ref.Parent=saved
			local clone=s.part:Clone();clone.Name="ReferenceGeometry";clone.Parent=saved;saved.Parent=entry
		end
		entry.Parent=backup;task.wait()
	end
	backup:SetAttribute("State","prepared")
	local ok,err=pcall(function()
		for _,row in ready do
			stale(row)
			for i,part in row.parts do part.Size=row.specs[i][1];part.CFrame=row.frame*CFrame.new(row.specs[i][2]) end
			row.model:SetAttribute("SourceSlicePlan",row.updatedPlan)
			row.model:SetAttribute("CoreSize",row.updatedCoreSize)
			row.model:SetAttribute("FacadeCoreClearanceRevision",9);row.model:SetAttribute("FacadeCoreClearanceMargin",row.margin)
			-- CoreCFrame stays exact: center, yaw and metadata Y range unchanged.
			for i,part in row.parts do
				assert((part.Size-row.specs[i][1]).Magnitude<.025 and sameCF(part.CFrame,row.frame*CFrame.new(row.specs[i][2])),"Native core resize verification failed")
			end
			task.wait()
		end
	end)
	if not ok then
		local restored,restoreError=pcall(Core.Rollback,backup)
		error(tostring(err)..(restored and " (batch rolled back)" or " (rollback failed: "..tostring(restoreError)..")"),2)
	end
	backup:SetAttribute("State","applied");backup:SetAttribute("Changed",#ready)
	return {changed=#ready,backup=backup}
end
return Core
