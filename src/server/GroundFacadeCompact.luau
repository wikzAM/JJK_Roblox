--!nonstrict
-- Explicit Edit tool. No work on require; no facade regeneration or glass edits.
local C={VERSION=1}
local H=game:GetService("HttpService")
local R=require(script.Parent.GroundFacadeRegistry)
local OWNER="2026-10-08-ground-pilot"
local PROPS={"Name","CFrame","Size","Color","Material","MaterialVariant","Shape","Transparency","Reflectance",
	"Anchored","CanCollide","CanTouch","CanQuery","CastShadow","CollisionGroup","Massless","RootPriority",
	"CustomPhysicalProperties","PivotOffset","Locked","Archivable","TopSurface","BottomSurface","FrontSurface","BackSurface","LeftSurface","RightSurface"}
local function guard()
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	assert(game:GetService("NetworkClient"):FindFirstChildWhichIsA("ClientReplicator"),"Connected Edit required")
end
local function denseUnique(rows,key)
	local n=#rows;assert(n>=1 and n<=10,"One to ten targets required");local seen={};local count=0
	for i,row in rows do
		assert(type(i)=="number" and i%1==0 and i>=1 and i<=n,"Dense array required")
		local value=key and row[key] or row;assert(not seen[value],"Duplicate target");seen[value]=true;count+=1
	end
	assert(count==n,"Dense array required")
end
local function pack(v)
	local t=typeof(v)
	if t=="nil" then return {"nil"}
	elseif t=="number" or t=="boolean" or t=="string" then return {t,v}
	elseif t=="Vector3" then return {t,v.X,v.Y,v.Z}
	elseif t=="Color3" then return {t,v.R,v.G,v.B}
	elseif t=="CFrame" then return {t,v:GetComponents()}
	elseif t=="UDim2" then return {t,v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset}
	elseif t=="UDim" then return {t,v.Scale,v.Offset}
	elseif t=="EnumItem" then return {t,tostring(v.EnumType):match("Enum%.(.+)"),v.Name}
	elseif t=="PhysicalProperties" then return {t,v.Density,v.Friction,v.Elasticity,v.FrictionWeight,v.ElasticityWeight} end
	error("Unsupported descriptor type: "..t)
end
local function unpackValue(v)
	local t=v[1]
	if t=="nil" then return nil elseif t=="number" or t=="boolean" or t=="string" then return v[2]
	elseif t=="Vector3" then return Vector3.new(v[2],v[3],v[4])
	elseif t=="Color3" then return Color3.new(v[2],v[3],v[4])
	elseif t=="CFrame" then return CFrame.new(table.unpack(v,2))
	elseif t=="UDim2" then return UDim2.new(v[2],v[3],v[4],v[5])
	elseif t=="UDim" then return UDim.new(v[2],v[3])
	elseif t=="EnumItem" then return Enum[v[2]][v[3]]
	elseif t=="PhysicalProperties" then return PhysicalProperties.new(table.unpack(v,2)) end
	error("Unknown descriptor type")
end
local function metadata(p)
	local tags=p:GetTags();table.sort(tags)
	local keys={};for k in p:GetAttributes() do table.insert(keys,k) end;table.sort(keys)
	local attrs={};for _,k in keys do table.insert(attrs,{k,pack(p:GetAttribute(k))}) end
	return tags,attrs
end
local function descriptor(p)
	local d={props={},tags={},attrs={}}
	for _,k in PROPS do table.insert(d.props,{k,pack(p[k])}) end
	d.tags,d.attrs=metadata(p);return d
end
local function signature(d,geometry)
	local p={};for _,row in d.props do if geometry or (row[1]~="CFrame" and row[1]~="Size") then table.insert(p,row) end end
	return H:JSONEncode({p,d.tags,d.attrs})
end
local function materialize(d)
	local p=Instance.new("Part")
	for _,row in d.props do p[row[1]]=unpackValue(row[2]) end
	for _,row in d.attrs do p:SetAttribute(row[1],unpackValue(row[2])) end
	for _,tag in d.tags do p:AddTag(tag) end
	return p
end
local function pathOf(node,root)
	local path={}
	while node~=root do
		local parent=assert(node.Parent,"Detached recipe target");local n=0
		for _,sibling in parent:GetChildren() do if sibling.Name==node.Name then n+=1;if sibling==node then break end end end
		table.insert(path,1,{node.Name,n});node=parent
	end
	return path
end
local function resolve(root,path)
	for _,step in path do local n=0;local found
		for _,child in root:GetChildren() do if child.Name==step[1] then n+=1;if n==step[2] then found=child;break end end end
		root=assert(found,"Recipe path no longer resolves")
	end
	return root
end
-- Generated childless boxes cannot have attachments. Check external direct
-- Instance links used by values, joints, welds, constraints and adornments.
local function referenced(targets)
	local out={}
	local stack={game};local visited=0
	while #stack>0 do
		local x=table.remove(stack)
		for _,child in x:GetChildren() do table.insert(stack,child) end
		local properties={}
		if x:IsA("ObjectValue") then properties={"Value"}
		elseif x:IsA("Model") then properties={"PrimaryPart"}
		elseif x:IsA("JointInstance") or x:IsA("WeldConstraint") or x:IsA("NoCollisionConstraint") then properties={"Part0","Part1"}
		elseif x:IsA("Highlight") or x:IsA("PVAdornment") or x:IsA("SurfaceGui") or x:IsA("BillboardGui") then properties={"Adornee"} end
		for _,key in properties do local ok,value=pcall(function()return x[key]end);if ok and targets[value] then out[value]=true end end
		visited+=1;if visited%1000==0 then task.wait();guard() end
	end
	return out
end
local function close(a,b)return math.abs(a-b)<.00001 end
local function merge(a,b)
	if close(a[1],b[1]) and close(a[2],b[2]) and (close(a[4],b[3]) or close(b[4],a[3])) then
		return {a[1],a[2],math.min(a[3],b[3]),math.max(a[4],b[4])}
	elseif close(a[3],b[3]) and close(a[4],b[4]) and (close(a[2],b[1]) or close(b[2],a[1])) then
		return {math.min(a[1],b[1]),math.max(a[2],b[2]),a[3],a[4]}
	end
end
local function contains(rects,x,y)
	for _,q in rects do if x>q[1] and x<q[2] and y>q[3] and y<q[4] then return true end end
	return false
end
function C.ProveUnion(before,after)
	local xs,ys={},{}
	for _,rows in {before,after} do for _,q in rows do table.insert(xs,q[1]);table.insert(xs,q[2]);table.insert(ys,q[3]);table.insert(ys,q[4]) end end
	table.sort(xs);table.sort(ys);local area,samples=0,0
	for i=1,#xs-1 do for j=1,#ys-1 do
		if xs[i+1]-xs[i]>.000001 and ys[j+1]-ys[j]>.000001 then
			local x,y=(xs[i]+xs[i+1])/2,(ys[j]+ys[j+1])/2
			assert(contains(before,x,y)==contains(after,x,y),"Rectangle union changed (hole or exterior growth)")
			if contains(before,x,y) then area+=(xs[i+1]-xs[i])*(ys[j+1]-ys[j]) end;samples+=1
		end
	end end
	return {area=area,samples=samples}
end
local function candidate(p,bay)
	if not (p:IsA("Part") and p.Shape==Enum.PartType.Block and p.Name=="OpaqueFront" and p.Parent==bay
		and p:GetAttribute("FacadePieceKind")=="wall" and p:GetAttribute("FacadeLayer")=="exterior"
		and p:HasTag("NoCSG") and not p:HasTag("GlassPane") and p.Anchored and #p:GetChildren()==0) then return false end
	if p:GetAttribute("FacadeSharedSurfaceVersion") or p:GetAttribute("FacadeCompactBatch") then return false end
	if p.AssemblyLinearVelocity.Magnitude>0 or p.AssemblyAngularVelocity.Magnitude>0 then return false end
	local q=bay:GetPivot():ToObjectSpace(p.CFrame)
	return (q.XVector-Vector3.xAxis).Magnitude<.000001 and (q.YVector-Vector3.yAxis).Magnitude<.000001
end
local function uiCandidate(pad,bay)
	local label=pad.Parent
	if not (pad:IsA("UIPadding") and label:IsA("TextLabel") and label.AutomaticSize==Enum.AutomaticSize.None
		and label.BackgroundTransparency==1 and label.BorderSizePixel==0
		and label.Size==UDim2.fromScale(1,1) and label.Position==UDim2.fromScale(0,0) and label.AnchorPoint==Vector2.zero
		and #label:GetChildren()==1 and label.Parent:IsA("SurfaceGui") and label.Parent.Name=="FacadeTypography") then return end
	if pad.PaddingLeft~=UDim.new(.04,0) or pad.PaddingRight~=UDim.new(.04,0)
		or pad.PaddingTop~=UDim.new(.08,0) or pad.PaddingBottom~=UDim.new(.08,0) then return end
	local tags,attrs=metadata(pad)
	return {label=label,pad=pad,path=pathOf(label,bay),name=pad.Name,archivable=pad.Archivable,tags=tags,attrs=attrs,
		beforePosition=pack(label.Position),beforeSize=pack(label.Size),text=label.Text,
		left=pack(pad.PaddingLeft),right=pack(pad.PaddingRight),top=pack(pad.PaddingTop),bottom=pack(pad.PaddingBottom)}
end
function C.Plan(models)
	guard();denseUnique(models)
	local plan={models={},summary={buildings=#models,bays=0,partsBefore=0,partsAfter=0,paddings=0,skippedReferences=0,proofSamples=0}}
	local targets={};local candidates={}
	for _,m in models do
		assert(m:IsDescendantOf(workspace.Buildings),"Live building required")
		local root=assert(m:FindFirstChild("GroundFacadePilot"));assert(root:GetAttribute("Owner")==OWNER,"Unowned facade")
		local mr={model=m,bays={}};table.insert(plan.models,mr)
		for _,bay in root:GetDescendants() do if bay:IsA("Model") and bay:GetAttribute("FacadeType") then
			local br={bay=bay,path=pathOf(bay,m),groups={},uis={}};table.insert(mr.bays,br)
			for _,p in bay:GetChildren() do if candidate(p,bay) then targets[p]=true;table.insert(candidates,{p=p,bay=bay,record=br}) end end
			for _,p in bay:GetDescendants() do if p:IsA("UIPadding") then local ui=uiCandidate(p,bay);if ui then targets[p]=true;table.insert(br.uis,ui) end end end
		end end
	end
	local refs=referenced(targets)
	for _,item in candidates do local p,br=item.p,item.record
		if refs[p] then plan.summary.skippedReferences+=1;continue end
		local ok,d=pcall(descriptor,p);if not ok then continue end
		local q=item.bay:GetPivot():ToObjectSpace(p.CFrame)
		local key=signature(d,false).."/"..string.format("%.9f/%.9f",q.Z,p.Size.Z)
		local group=br.groups[key]
		if not group then group={originals={},descriptors={},before={},z=q.Z,depth=p.Size.Z};br.groups[key]=group end
		table.insert(group.originals,p);table.insert(group.descriptors,d)
		table.insert(group.before,{q.X-p.Size.X/2,q.X+p.Size.X/2,q.Y-p.Size.Y/2,q.Y+p.Size.Y/2})
	end
	for _,mr in plan.models do for _,br in mr.bays do
		local groups={}
		for _,g in br.groups do
			local rects=table.clone(g.before);local changed=true
			while changed do changed=false
				for i=1,#rects do for j=i+1,#rects do local q=merge(rects[i],rects[j]);if q then rects[i]=q;table.remove(rects,j);changed=true;break end end;if changed then break end end
			end
			if #rects<#g.before then
				g.after=rects;local proof=C.ProveUnion(g.before,g.after);plan.summary.proofSamples+=proof.samples
				plan.summary.partsBefore+=#g.before;plan.summary.partsAfter+=#g.after;table.insert(groups,g)
			end
		end
		br.groups=groups
		local uis={};for _,ui in br.uis do if not refs[ui.pad] then table.insert(uis,ui) end end;br.uis=uis
		if #groups>0 or #uis>0 then plan.summary.bays+=1;plan.summary.paddings+=#uis end
	end end
	return plan
end
local function apply(plan,stage)
	guard();denseUnique(plan.models,"model")
	local id=H:GenerateGUID(false);local serial={version=C.VERSION,models={}};local targets={}
	for mi,mr in plan.models do
		local m=mr.model;assert(m:IsDescendantOf(workspace.Buildings),"Owner removed target")
		local root=assert(m:FindFirstChild("GroundFacadePilot"));assert(root:GetAttribute("Owner")==OWNER)
		local sm={ref="Model"..mi,bays={}};table.insert(serial.models,sm)
		for _,br in mr.bays do if #br.groups>0 or #br.uis>0 then
			assert(resolve(m,br.path)==br.bay and br.bay:IsDescendantOf(root),"Bay moved/replaced")
			local sb={path=br.path,groups={},uis={}};table.insert(sm.bays,sb)
			for gi,g in br.groups do
				for i,p in g.originals do assert(candidate(p,br.bay) and signature(descriptor(p),true)==signature(g.descriptors[i],true),"Original changed since plan");targets[p]=true end
				C.ProveUnion(g.before,g.after)
				local sg={before=g.descriptors,after={}};table.insert(sb.groups,sg)
				for _,rect in g.after do
					local p=materialize(g.descriptors[1]);p.CFrame=br.bay:GetPivot()*CFrame.new((rect[1]+rect[2])/2,(rect[3]+rect[4])/2,g.z)
					p.Size=Vector3.new(rect[2]-rect[1],rect[4]-rect[3],g.depth)
					p:SetAttribute("FacadeCompactBatch",id);p:SetAttribute("FacadeCompactGroup",gi)
					table.insert(sg.after,descriptor(p));table.insert(stage,{part=p,parent=br.bay})
				end
			end
			for _,ui in br.uis do
				assert(resolve(br.bay,ui.path)==ui.label and uiCandidate(ui.pad,br.bay) and ui.label.Text==ui.text,"Typography changed since plan")
				targets[ui.pad]=true;local copy=table.clone(ui);copy.label=nil;copy.pad=nil;table.insert(sb.uis,copy)
			end
		end end
	end
	local refs=referenced(targets);assert(not next(refs),"New external references; replan")
	-- The bounded tree walk yields. Recheck every target after its final yield.
	for _,mr in plan.models do
		local root=mr.model:FindFirstChild("GroundFacadePilot")
		assert(mr.model:IsDescendantOf(workspace.Buildings) and root and root:GetAttribute("Owner")==OWNER,"Owner changed target during scan")
		for _,br in mr.bays do
			assert(resolve(mr.model,br.path)==br.bay and br.bay:IsDescendantOf(root),"Bay changed during scan")
			for _,g in br.groups do for i,p in g.originals do assert(candidate(p,br.bay) and signature(descriptor(p),true)==signature(g.descriptors[i],true),"Wall changed during scan") end end
			for _,ui in br.uis do assert(resolve(br.bay,ui.path)==ui.label and uiCandidate(ui.pad,br.bay) and ui.label.Text==ui.text,"Typography changed during scan") end
		end
	end
	local archive=Instance.new("Folder");archive.Name="FacadeCompact_"..id;archive:SetAttribute("Owner","facade-compact-v1");archive:SetAttribute("State","prepared")
	local raw=H:JSONEncode(serial);R.Write(archive,"Recipe",raw);assert(R.Read(archive,"Recipe")==raw,"Recipe verification failed")
	for mi,mr in plan.models do local ref=Instance.new("ObjectValue");ref.Name="Model"..mi;ref.Value=mr.model;ref.Parent=archive end
	archive.Parent=game.ServerStorage
	-- All checks and recoverable recipe writes precede removing originals.
	for _,s in stage do s.part.Parent=s.parent end
	for _,mr in plan.models do for _,br in mr.bays do
		for _,g in br.groups do for _,p in g.originals do p:Destroy() end end
		for _,ui in br.uis do ui.label.Position=UDim2.fromScale(.04,.08);ui.label.Size=UDim2.fromScale(.92,.84);ui.pad:Destroy() end
	end end
	archive:SetAttribute("State","applied");archive:SetAttribute("BatchId",id)
	return {archive=archive.Name,summary=plan.summary,netPartsRemoved=plan.summary.partsBefore-plan.summary.partsAfter}
end
function C.Apply(plan)
	local stage={};local ok,result=pcall(apply,plan,stage)
	if not ok then for _,s in stage do if not s.part.Parent then s.part:Destroy() end end;error(result) end
	return result
end
local function restore(archive,stage)
	guard();assert(archive:IsDescendantOf(game.ServerStorage) and archive:GetAttribute("Owner")=="facade-compact-v1" and archive:GetAttribute("State")=="applied","Not an applied owned compact archive")
	local recipe=H:JSONDecode(assert(R.Read(archive,"Recipe")));local id=archive:GetAttribute("BatchId")
	local remove,uis={},{}
	for _,sm in recipe.models do
		local ref=assert(archive:FindFirstChild(sm.ref));local m=assert(ref.Value)
		assert(m:IsDescendantOf(workspace.Buildings),"Owner removed target; preserve recipe")
		local root=assert(m:FindFirstChild("GroundFacadePilot"));assert(root:GetAttribute("Owner")==OWNER,"Facade ownership changed")
		for _,sb in sm.bays do local bay=resolve(m,sb.path)
			assert(bay:IsA("Model") and bay:GetAttribute("FacadeType") and bay:IsDescendantOf(root),"Bay replaced; preserve recipe")
			for gi,g in sb.groups do
				local current={};for _,p in bay:GetChildren() do if p:IsA("Part") and p:GetAttribute("FacadeCompactBatch")==id and p:GetAttribute("FacadeCompactGroup")==gi then table.insert(current,p) end end
				assert(#current==#g.after,"Compact geometry changed; preserve recipe")
				local expected={};for _,d in g.after do local key=signature(d,true);expected[key]=(expected[key] or 0)+1 end
				for _,p in current do assert(#p:GetChildren()==0);local key=signature(descriptor(p),true);assert((expected[key] or 0)>0,"Replacement edited; preserve recipe");expected[key]-=1;table.insert(remove,p) end
				for _,d in g.before do table.insert(stage,{part=materialize(d),parent=bay}) end
			end
			for _,ui in sb.uis do local label=resolve(bay,ui.path)
				assert(label:IsA("TextLabel") and label.Position==UDim2.fromScale(.04,.08) and label.Size==UDim2.fromScale(.92,.84) and label.Text==ui.text and #label:GetChildren()==0,"Typography edited; preserve recipe")
				table.insert(uis,{label=label,spec=ui})
			end
		end
	end
	local targets={};for _,p in remove do targets[p]=true end;assert(not next(referenced(targets)),"Replacement externally referenced")
	for _,s in stage do s.part.Parent=s.parent end
	for _,p in remove do p:Destroy() end
	for _,item in uis do local ui,label=item.spec,item.label;local pad=Instance.new("UIPadding");pad.Name=ui.name
		pad.Archivable=ui.archivable;pad.PaddingLeft=unpackValue(ui.left);pad.PaddingRight=unpackValue(ui.right);pad.PaddingTop=unpackValue(ui.top);pad.PaddingBottom=unpackValue(ui.bottom)
		for _,a in ui.attrs do pad:SetAttribute(a[1],unpackValue(a[2])) end;for _,tag in ui.tags do pad:AddTag(tag) end
		label.Position=unpackValue(ui.beforePosition);label.Size=unpackValue(ui.beforeSize);pad.Parent=label
	end
	archive:SetAttribute("State","restored");return {restoredParts=#stage,removedParts=#remove,restoredPaddings=#uis}
end
function C.Restore(archive)
	local stage={};local ok,result=pcall(restore,archive,stage)
	if not ok then for _,s in stage do if not s.part.Parent then s.part:Destroy() end end;error(result) end
	return result
end
return C
