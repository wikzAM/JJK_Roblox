--!nonstrict
-- Client-only upper-floor facades (storey >= 2) built near the camera from each
-- building's SourceSlicePlan with the pure UpperFacadeKit. Nothing is saved in the
-- place: the server only keeps a bounded hit-capsule log (UpperFacadeHits), so
-- every client derives the same seeded facade and the same damage. Builds advance
-- one floor-run at a time inside a per-frame budget, so tall towers never hitch.
-- Two tiers: full kit detail within BUILD_RADIUS; a 2-part-per-run silhouette
-- (tinted wall + window band, same palette) out to FAR_RADIUS for the skyline.
local Renderer={BUILD_RADIUS=380,DROP_RADIUS=480,MAX_BUILDINGS=60,FAR_RADIUS=750,FAR_DROP=850,MAX_FAR=150,BUDGET_MS=4}
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local Collection=game:GetService("CollectionService")
-- Same protected identities/zones as the ground-facade selector (GroundFacadeSection).
local EXCLUDED={["fbx_6_4510_4915_-8852"]=true,["orph_703_1736"]=true,["orph_706_1735"]=true,["fbx_5_6952_1857_6146"]=true,
	["orph_-1012_-190"]=true,["orph_-912_-37"]=true,["part_-424_296"]=true}
local ZONES={{Vector2.new(11,572),220}} -- the Scramble Crossing itself stays bare (owner)
local Kit,Catalog
local candidates,built={},{}
local styles={} -- model -> deduplicated style (deterministic on every client)
local hits={}
local container
local function eligible(m,pos)
	if not m:IsA("Model") or type(m:GetAttribute("SourceSlicePlan"))~="string" then return false end
	if m:FindFirstChild("UpperFacade") then return false end -- baked Edit preview owns this building
	if EXCLUDED[m:GetAttribute("SourceSliceId") or ""] then return false end
	for _,key in {"Landmark","CrownInteresting","StationInfrastructure","FacadeExcluded"} do
		if m:GetAttribute(key) or Collection:HasTag(m,key) then return false end
	end
	for _,z in ZONES do if (Vector2.new(pos.X,pos.Z)-z[1]).Magnitude<z[2] then return false end end
	return (m:GetAttribute("GeneratedFloors") or 0)>=2
end
-- Horizontal distance: a tall tower's box centre sits hundreds of studs up.
local function flatDistance(a,b) return Vector2.new(a.X-b.X,a.Z-b.Z).Magnitude end
local function segmentDistance(p,a,b)
	local d=b-a;local t=d:Dot(d)>0 and math.clamp((p-a):Dot(d)/d:Dot(d),0,1) or 0
	return (p-(a+d*t)).Magnitude
end
local function inHit(part,hit)
	return segmentDistance(part.Position,hit.a,hit.b)<hit.r+part.Size.Magnitude/2
end
local function addHit(h)
	local a,b,r=h:GetAttribute("A"),h:GetAttribute("B"),h:GetAttribute("R")
	if typeof(a)~="Vector3" or typeof(b)~="Vector3" or type(r)~="number" then return end
	local hit={a=a,b=b,r=r};table.insert(hits,hit)
	for _,e in built do
		for _,p in e.folder:GetDescendants() do if p:IsA("BasePart") and inHit(p,hit) then p:Destroy() end end
	end
end
local function start(m,d,lite)
	local folder=Instance.new("Folder");folder.Name=m.Name;folder.Parent=container
	return {model=m,folder=folder,i=1,d=d,lite=lite}
end
local function litePart(parent,cf,size,color,refl)
	local p=Instance.new("Part");p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
	p.Material=Enum.Material.SmoothPlastic;p.Color=color;p.Reflectance=refl or 0;p.Size=size;p.CFrame=cf
	for _,hit in hits do if inHit(p,hit) then p:Destroy();return end end
	p.Parent=parent
end
local function liteRun(e,run)
	local pal=Catalog.Palette(run.options.palette)
	local k=1+(run.options.tint or 0)*.09
	local function shade(c) return Color3.new(math.clamp(c.R*k,0,1),math.clamp(c.G*k,0,1),math.clamp(c.B*k,0,1)) end
	local w,h=run.width,run.height
	litePart(e.folder,run.frame*CFrame.new(0,h/2,.05),Vector3.new(w,h,.5),shade(pal.wall))
	if w>=6 and not (Catalog.Get(run.spec).cycle and #Catalog.Get(run.spec).cycle==1 and Catalog.Get(run.spec).cycle[1]=="vent") then
		litePart(e.folder,run.frame*CFrame.new(0,h*.55,-.25),Vector3.new(w-1.6,h*.42,.2),pal.glass,.15)
	end
end
local function step(e)
	if not e.runs then -- planning is a budgeted step of its own
		local ok,plan=pcall(Kit.PlanBuilding,e.model,{style=styles[e.model]})
		e.runs=ok and plan.runs or {};return
	end
	local run=e.runs[e.i];e.i+=1
	if e.lite then pcall(liteRun,e,run);return end
	local ok,model=pcall(Kit.BuildFloorRun,nil,run.frame,run.width,run.height,run.spec,run.options)
	if not ok then return end
	for _,p in model:GetDescendants() do if p:IsA("BasePart") then
		-- Visual only: no client collision or click/raycast interference.
		p.CanCollide=false;p.CanQuery=false
		for _,hit in hits do if inHit(p,hit) then p:Destroy();break end end
	end end
	model.Parent=e.folder
end
local function drop(m)
	local e=built[m];if e then if e.folder then e.folder:Destroy() end;built[m]=nil end
end
local function refreshCandidates()
	table.clear(candidates)
	for _,m in workspace.Buildings:GetChildren() do
		if m:IsA("Model") then
			local cf=m:GetAttribute("InteriorBBoxCFrame")
			local pos=typeof(cf)=="CFrame" and cf.Position or m:GetPivot().Position
			if eligible(m,pos) then table.insert(candidates,{model=m,pos=pos}) end
		end
	end
end
-- Neighbouring buildings must not share family AND palette. Walk buildings in id
-- order and re-roll a salted seed (up to 3x) on a clash within 90 studs. Inputs
-- are replicated data only, so every client reaches the same assignment.
local function assignStyles()
	local list=table.clone(candidates)
	local function id(c) return tostring(c.model:GetAttribute("SourceSliceId") or c.model.Name) end
	table.sort(list,function(a,b) return id(a)<id(b) end)
	local grid={};local t0=os.clock()
	for i,c in list do
		local ok,plan=pcall(Kit.PlanBuilding,c.model,{})
		if ok then
			local key=id(c);local style=plan.style
			local gx,gz=math.floor(c.pos.X/90),math.floor(c.pos.Z/90)
			for salt=1,3 do
				local clash=false
				for dx=-1,1 do for dz=-1,1 do for _,o in grid[(gx+dx)..","..(gz+dz)] or {} do
					if (Vector2.new(o.pos.X,o.pos.Z)-Vector2.new(c.pos.X,c.pos.Z)).Magnitude<90 and o.family==style.family and o.palette==style.palette then clash=true end
				end end end
				if not clash then break end
				style=Catalog.Pick(key.."#"..salt,plan.class)
			end
			styles[c.model]=style
			local cell=gx..","..gz;grid[cell]=grid[cell] or {}
			table.insert(grid[cell],{pos=c.pos,family=style.family,palette=style.palette})
		end
		if os.clock()-t0>.004 then task.wait();t0=os.clock() end
	end
end
function Renderer.Init()
	local Shared=RS:WaitForChild("Shared")
	Kit=require(Shared:WaitForChild("UpperFacadeKit"));Catalog=require(Shared:WaitForChild("UpperFacadeCatalog"))
	workspace:WaitForChild("Buildings")
	container=Instance.new("Folder");container.Name="ClientUpperFacades";container.Parent=workspace
	local log=RS:WaitForChild("UpperFacadeHits",10)
	if log then
		for _,h in log:GetChildren() do addHit(h) end
		log.ChildAdded:Connect(addHit)
	end
	refreshCandidates()
	task.spawn(assignStyles)
	workspace.Buildings.ChildAdded:Connect(function() task.defer(refreshCandidates) end)
	workspace.Buildings.ChildRemoved:Connect(function(m) drop(m);task.defer(refreshCandidates) end)
	local queue,lastSort={},0
	Run.Heartbeat:Connect(function()
		local cam=workspace.CurrentCamera;if not cam then return end
		local eye=cam.CFrame.Position
		local now=os.clock()
		if now-lastSort>.75 then
			lastSort=now
			local near,far=0,0
			for m,e in built do
				local cf=m:GetAttribute("InteriorBBoxCFrame")
				local pos=typeof(cf)=="CFrame" and cf.Position or m:GetPivot().Position
				local d=flatDistance(pos,eye);e.d=d
				-- Swap tiers as the camera moves: far silhouettes upgrade, detail downgrades.
				if not m.Parent or d>Renderer.FAR_DROP or (e.lite and d<Renderer.BUILD_RADIUS) or (not e.lite and d>Renderer.DROP_RADIUS) then drop(m)
				elseif e.lite then far+=1 else near+=1 end
			end
			local order={}
			for _,c in candidates do
				local d=flatDistance(c.pos,eye)
				if d<Renderer.FAR_RADIUS and not built[c.model] and styles[c.model] then table.insert(order,{m=c.model,d=d}) end
			end
			table.sort(order,function(a,b) return a.d<b.d end)
			for _,o in order do
				if o.d<Renderer.BUILD_RADIUS then
					if near<Renderer.MAX_BUILDINGS then built[o.m]=start(o.m,o.d,false);near+=1 end
				elseif far<Renderer.MAX_FAR then built[o.m]=start(o.m,o.d,true);far+=1 end
			end
			queue={}
			for m,e in built do if not e.runs or e.i<=#e.runs then table.insert(queue,e) end end
			table.sort(queue,function(a,b) return a.d<b.d end)
		end
		local t0=os.clock()
		while #queue>0 and (os.clock()-t0)*1000<Renderer.BUDGET_MS do
			local e=queue[1]
			if not e.folder.Parent then table.remove(queue,1)
			else step(e);if e.runs and e.i>#e.runs then table.remove(queue,1) end end
		end
	end)
end
return Renderer
