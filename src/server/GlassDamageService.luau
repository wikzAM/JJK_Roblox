-- Server-authoritative DATA for logical facade panes; no upper-floor glass Parts.
-- Attack code calls these APIs. No client-provided damage RemoteEvent is accepted.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Geometry=require(Shared.GlassGeometry)
local Visual=require(Shared.GlassVisual)
local Config=require(Shared.GlassConfig)
local Http=game:GetService("HttpService")
local Replicated=game:GetService("ReplicatedStorage")
local Service={}
local states={}
local physical={}
local root,event
local initialized=false
local S=Config.State
local function pageOf(key)
	local n=0;for i=1,#key do n=(n*33+string.byte(key,i))%64 end;return n
end
local function readCells(folder)
	local all={}
	for _,p in folder:GetChildren() do
		local raw=p:GetAttribute("Cells")
		if type(raw)=="string" then local ok,c=pcall(function()return Http:JSONDecode(raw)end)
			if ok and type(c)=="table" then for k,v in c do all[k]=v end end
		end
	end
	return all
end
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<1e9 end
local function vector(v)return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function physicalPanes(model)
	local cached=physical[model]
	if not cached then
		cached={};physical[model]=cached
		local function add(p)if p:IsA("BasePart") and p:HasTag("GlassPane") then cached[p]=true end end
		for _,p in model:GetDescendants() do add(p) end
		model.DescendantAdded:Connect(add)
		model.DescendantRemoving:Connect(function(p)cached[p]=nil end)
		model.Destroying:Once(function()physical[model]=nil end)
	end
	local parts={};for p in cached do if p.Parent then table.insert(parts,p) end end;return parts
end
local function record(model)
	local id=Geometry.Id(model);local entry=states[model]
	local version=model:GetAttribute("FacadeVersion") or 0
	if entry and entry.version~=version then
		entry.cells={};entry.version=version
		for _,p in entry.folder:GetChildren() do p:Destroy() end
		entry.folder:SetAttribute("GeometryVersion",version)
		entry.folder:SetAttribute("Revision",(entry.folder:GetAttribute("Revision") or 0)+1)
	end
	if not entry then
		local f=root:FindFirstChild(id)
		if f then assert(f:GetAttribute("GlassOwner")==1,"Unowned glass state folder")
		else f=Instance.new("Folder");f.Name=id;f:SetAttribute("GlassOwner",1);f.Parent=root end
		entry={cells={},version=version,folder=f};states[model]=entry
		model.Destroying:Once(function()if f.Parent then f:Destroy() end;states[model]=nil end)
		-- Persisted edit previews can be replayed in Play and by late joiners.
		if f:GetAttribute("GeometryVersion")==version then entry.cells=readCells(f)
		else for _,p in f:GetChildren() do p:Destroy() end end
	end
	return entry
end
local function write(model,entry,changed,from)
	entry.folder:SetAttribute("GeometryVersion",entry.version)
	-- Pages avoid one enormous replicated string, and update only touched pages.
	local pages={}
	if #changed==0 then for _,p in entry.folder:GetChildren() do if p.Name:match("^P%d+$") then p:Destroy() end end
	else
		for _,row in changed do pages[pageOf(row[1])]={} end
		for key,state in entry.cells do local page=pages[pageOf(key)];if page then page[key]=state end end
		for n,page in pages do
			local name=string.format("P%02d",n);local p=entry.folder:FindFirstChild(name)
			if not p then p=Instance.new("Folder");p.Name=name;p.Parent=entry.folder end
			p:SetAttribute("Cells",Http:JSONEncode(page))
		end
	end
	entry.folder:SetAttribute("ModelName",model.Name)
	entry.folder:SetAttribute("Revision",(entry.folder:GetAttribute("Revision") or 0)+1)
	if game:GetService("RunService"):IsRunning() then
		-- Only cosmetic bursts need an event. Attribute pages and physical states
		-- carry all authoritative changes, including those beyond the burst budget.
		local bursts={}
		for _,row in changed do if row[3] and row[4] then
			if #bursts>=Config.MaxVFXRowsPerEvent then break end
			table.insert(bursts,row)
		end end
		if #bursts>0 then event:FireAllClients(Geometry.Id(model),bursts,from) end
	end
end
function Service.Init()
	if initialized then return end
	root=Replicated:FindFirstChild("GlassDamageState")
	if root then assert(root:GetAttribute("GlassSystemVersion")==Config.VERSION,"Unowned glass state root")
	else root=Instance.new("Folder");root.Name="GlassDamageState";root:SetAttribute("GlassSystemVersion",Config.VERSION);root.Parent=Replicated end
	event=Replicated:FindFirstChild("GlassDamageEvent")
	if not event then event=Instance.new("RemoteEvent");event.Name="GlassDamageEvent";event.Parent=Replicated end
	initialized=true
	game:GetService("CollectionService"):GetInstanceAddedSignal("GlassPane"):Connect(function(part)
		local parent=part.Parent
		while parent do
			local cached=physical[parent];if cached and part:IsA("BasePart") then cached[part]=true end
			parent=parent.Parent
		end
	end)
	game:GetService("CollectionService"):GetInstanceRemovedSignal("GlassPane"):Connect(function(part)
		local parent=part.Parent
		while parent do local cached=physical[parent];if cached then cached[part]=nil end;parent=parent.Parent end
	end)
	local buildings=workspace:FindFirstChild("Buildings")
	if buildings then buildings.ChildRemoved:Connect(function(model)
		local e=states[model];if e then e.folder:Destroy();states[model]=nil end
	end) end
end
function Service.GetState(model,key)
	Service.Init();return record(model).cells[key] or S.Intact
end
function Service.SetPane(model,key,state,part,from)
	Service.Init()
	assert(type(key)=="string" and #key>0,"Pane key required")
	assert(state==S.Intact or state==S.Cracked or state==S.Shattered or state==S.Removed,"Invalid glass state")
	local e=record(model);local old=e.cells[key] or S.Intact
	if state<=old then return false end -- damage only; Reset is the explicit repair API
	e.cells[key]=state
	if part and part.Parent then Visual.Apply(part,state,{textures=false,serverPhysics=true}) end
	write(model,e,{{key,state}},from)
	return true
end
function Service.Reset(model)
	Service.Init();local e=record(model);e.cells={};write(model,e,{},nil)
	-- Removed physical panes must be rebuilt from the kit; repairing data cannot
	-- resurrect a destroyed Instance. Pilot.Clear/Apply performs that rebuild.
	for _,p in model:GetDescendants() do if p:IsA("BasePart") and p:HasTag("GlassPane") then Visual.Apply(p,S.Intact,{textures=false,serverPhysics=true}) end end
end
function Service.RepairRun(model,prefix)
	-- Used when an owned ground run is explicitly removed/rebuilt. Upper-floor
	-- states retain their stable IDs; a facade-only edit does not bump geometry.
	Service.Init();local e=record(model);local changed={}
	for key in e.cells do if key:sub(1,#prefix)==prefix then e.cells[key]=nil;table.insert(changed,{key,S.Intact}) end end
	for _,p in physicalPanes(model) do if (p:GetAttribute("GlassPaneId") or ""):sub(1,#prefix)==prefix then Visual.Apply(p,S.Intact,{textures=false,serverPhysics=true}) end end
	if #changed>0 then write(model,e,changed,nil) end
end
local function candidate(model,a,b,reach)
	local cf,size=model:GetAttribute("InteriorBBoxCFrame"),model:GetAttribute("InteriorBBoxSize")
	if typeof(cf)=="CFrame" and typeof(size)=="Vector3" then return Geometry.SegmentBoxDistance(a,b,cf,size)<=reach+2+(model:GetAttribute("GroundFacadeMaxOutset") or 0) end
	-- Fallback uses real current bounds only for these rare models, never to place a facade.
	local box,dim=model:GetBoundingBox();return Geometry.SegmentBoxDistance(a,b,box,dim)<=reach+2
end
function Service.Capsule(a,b,options)
	Service.Init();options=options or {}
	assert(vector(a) and vector(b),"Invalid glass capsule")
	local radius=options.radius or 1;local band=options.crackBand or Config.DefaultCrackBand
	local state=options.state or S.Shattered
	assert(finite(radius) and radius>=0 and radius<=1000 and finite(band) and band>=0 and band<=500,"Invalid damage radius")
	assert(state>=S.Cracked and state<=S.Removed and state%1==0,"Invalid damage state")
	local targets=options.models or workspace:WaitForChild("Buildings"):GetChildren()
	local changes,models,cells=0,0,0
	for _,model in targets do
		if model:IsA("Model") and model.Parent and (options.models or Geometry.GeneratedEnabled(model)) and candidate(model,a,b,radius+band) then
			local frame,strips
			if Geometry.GeneratedEnabled(model) then frame,strips=Geometry.Strips(model) end
			local e,changed=nil,{}
			local function damage(key,cf,size,part)
				local d=Geometry.SegmentBoxDistance(a,b,cf,size);cells+=1
				local nextState=d<=radius and state or (d<=radius+band and S.Cracked or nil)
				if not nextState then return end
				e=e or record(model)
				if nextState>(e.cells[key] or S.Intact) then
					local old=e.cells[key] or S.Intact
					e.cells[key]=nextState
					local row={key,nextState}
					-- Event-only burst geometry survives state 4 deleting the physical pane.
					if nextState>=S.Shattered and old<S.Shattered then
						row[3]={cf:GetComponents()};row[4]={size.X,size.Y,size.Z}
					end
					table.insert(changed,row);changes+=1
					if part and part.Parent then Visual.Apply(part,nextState,{textures=false,serverPhysics=true}) end
				end
			end
			if frame then
				for _,strip in strips do
					if strip.kind=="glass" and Geometry.SegmentBoxDistance(a,b,frame*strip.cframe,strip.size)<=radius+band then
						for _,pane in Geometry.Split(strip) do damage(pane.key,frame*pane.cframe,pane.size) end
					end
				end
			end
			-- Ground storefronts in the pilot are server-owned ordinary glass Parts.
			local ground=physicalPanes(model)
			for _,p in ground do if p.Parent then
				local key=p:GetAttribute("GlassPaneId")
				if type(key)=="string" and #key>0 then damage(key,p.CFrame,p.Size,p) end
			end end
			if #changed>0 then models+=1;write(model,e,changed,(a+b)/2) end
		end
	end
	return {changed=changes,buildings=models,testedCells=cells}
end
function Service.DestroyPath(a,b,holeRadius,options)
	-- Keep glass away from missing supporting wall/slab. The outer band cracks;
	-- ordinary impact/shockwave APIs retain their separate state-3 behaviour.
	options=options or {}
	assert(finite(holeRadius) and holeRadius>=0,"Invalid structural hole radius")
	local clearance=options.clearance or Config.DestructionClearance
	local crackBand=options.crackBand or Config.DestructionCrackBand
	assert(finite(clearance) and clearance>=0,"Invalid glass clearance")
	return Service.Capsule(a,b,{radius=holeRadius+clearance,crackBand=crackBand,
		state=S.Removed,models=options.models})
end
function Service.Shockwave(position,options)
	options=options or {}
	local inner=options.shatterRadius or 0;local outer=options.crackRadius or inner+Config.DefaultCrackBand
	assert(outer>=inner,"Crack radius must enclose shatter radius")
	return Service.Capsule(position,position,{radius=inner,crackBand=outer-inner,state=options.state or S.Shattered,models=options.models})
end
function Service.Impact(position,velocity,options)
	options=options or {};assert(vector(velocity),"Invalid impact velocity")
	return Service.Capsule(position,position,{radius=options.radius or 1.5,crackBand=0,
		state=velocity.Magnitude<(options.shatterSpeed or Config.ShatterSpeed) and S.Cracked or S.Shattered,models=options.models})
end
return Service
