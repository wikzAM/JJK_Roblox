--!nonstrict
-- Camera-bounded facade geometry. Server stores sparse logical pane damage;
-- this client creates Parts, damage overlays and brief shard particles.
local Renderer={}
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local Http=game:GetService("HttpService")
local Tags=game:GetService("CollectionService")
local Shared=RS:WaitForChild("Shared")
local Layout=require(Shared.FacadeLayout)
local Geometry=require(Shared.GlassGeometry)
local Visual=require(Shared.GlassVisual)
local Config=require(Shared.GlassConfig)
local Shards=require(script.Parent.GlassShards)
local built,far,pool,snapshots,candidates,ground={},{},{},{},{},{}
local nearFolder,farFolder,damageRoot
local dirty,epochs={},{}
local initialized=false
local function snapshot(model)
 local f=damageRoot and damageRoot:FindFirstChild(Geometry.Id(model))
 if not f or f:GetAttribute("GeometryVersion")~=(model:GetAttribute("FacadeVersion") or 0) then return {} end
 local rev=f:GetAttribute("Revision")
 local cached=snapshots[f]
 if cached and cached.rev==rev then return cached.cells end
 local cells={}
 for _,p in f:GetChildren() do
  local raw=p:GetAttribute("Cells")
  if type(raw)=="string" then local ok,t=pcall(function()return Http:JSONDecode(raw)end)
   if ok then for key,state in t do cells[key]=state end end
  end
 end
 snapshots[f]={rev=rev,cells=cells}
 return cells
end
local function acquire()
 local p=table.remove(pool) or Instance.new("Part")
 p.Anchored=true;p.CanQuery=false;p.CanTouch=false;p.CanCollide=true;p.CastShadow=false
 p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 return p
end
local function release(p)
 Visual.ResetPooled(p);p.Parent=nil
 if #pool<Config.MaxPooledParts then table.insert(pool,p) else p:Destroy() end
end
local function paint(p,kind,style)
 p.Transparency=0;p.Reflectance=0
 if kind=="glass" then p.Material=Enum.Material.Glass;p.Color=style.glass;p.Transparency=style.transparency;p.Reflectance=style.reflectance
 else p.Material=Layout.PIER.material;p.Color=Layout.PIER.color end
end
function Renderer.Drop(model)
 local e=built[model]
 if e then for p in e.parts do release(p) end;e.model:Destroy();built[model]=nil end
end
local function dropFar(model)
 if far[model] then far[model]:Destroy();far[model]=nil end
end
function Renderer.BuildInto(parent,model,options)
 if not Geometry.UpperEnabled(model) then return nil end
 options=options or {};local frame,strips=Geometry.Strips(model)
 if not frame then return nil end
 local cells=snapshot(model)
 local damagedRuns={}
 for key in cells do local prefix=key:match("^(%d+/%d+/%d+):");if prefix then damagedRuns[prefix]=true end end
 local entry={parts={},frame=frame,style=Layout.StyleOf(Geometry.Id(model)),detail=options.detail~=false}
 local holder=Instance.new("Model");holder.Name=model.Name;entry.model=holder;holder.Parent=parent
 if options.onStart then options.onStart(entry) end
 local count=0
 local function add(s,key,state)
  if state==4 then return end
  local p=acquire();p.Name=key or s.kind;p.Size=s.size;p.CFrame=frame*s.cframe
  paint(p,s.kind,entry.style)
  if s.kind=="glass" then
   p:SetAttribute("GlassClientGeometry",true);Visual.Capture(p,key,true)
   Visual.Apply(p,state or 1,{textures=entry.detail})
  end
  p.Parent=holder;entry.parts[p]=s;count+=1
  if options.yieldParts and count%24==0 then coroutine.yield() end
 end
 for _,s in strips do
  local run=string.format("%d/%d/%d",s.storey,s.piece,s.run)
  if s.kind=="glass" and (entry.detail or damagedRuns[run]) then
   for _,cell in Geometry.Split(s) do add(cell,cell.key,cells[cell.key] or 1) end
  else add(s,s.kind=="glass" and run..":strip" or nil,1) end
 end
 return entry
end
function Renderer.BuildFarInto(parent,model,options)
 if not Config.FarProxyEnabled or not Geometry.UpperEnabled(model) then return nil end
 options=options or {};local frame,strips=Geometry.Strips(model)
 if not frame then return nil end
 local plan=Http:JSONDecode(model:GetAttribute("SourceSlicePlan"))
 local style=Layout.StyleOf(Geometry.Id(model));local cells=snapshot(model);local holes={}
 for _,s in strips do if s.kind=="glass" then
  local prefix=string.format("%d/%d/%d:",s.storey,s.piece,s.run);local damaged=false
  for key,state in cells do if state>=3 and key:sub(1,#prefix)==prefix then damaged=true;break end end
  if damaged then for _,cell in Geometry.Split(s) do if (cells[cell.key] or 1)>=3 then table.insert(holes,cell) end end end
 end end
 local holder=Instance.new("Model");holder.Name=model.Name;holder.Parent=parent
 if options.onStart then options.onStart(holder) end
 local owned=next(Geometry.OwnedRuns(model))~=nil
 local count=0
 for _,s in Layout.BuildFarCoarse(plan) do
  local hidden=false
  for _,cell in holes do
   if Geometry.SegmentBoxDistance(cell.cframe.Position,cell.cframe.Position,s.cframe,s.size)<=cell.size.Magnitude*.5 then hidden=true;break end
  end
  -- Ground-floor kits take ownership. Coarse first bands start above them.
  if owned and plan.levels[2] then
   local bottom=s.cframe.Position.Y-s.size.Y/2;local top=bottom+s.size.Y
   local y=plan.levels[2].y+plan.levels[2].thickness
   if bottom<y then
    if top<=y then hidden=true else
     s.cframe=s.cframe+CFrame.new(0,(y-bottom)/2,0).Position
     s.size=Vector3.new(s.size.X,top-y,s.size.Z)
    end
   end
  end
  if not hidden then
   local p=Instance.new("Part");p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
   p.Size=s.size;p.CFrame=frame*s.cframe;p.Material=Enum.Material.SmoothPlastic;p.Color=style.glass;p.Parent=holder
   count+=1;if options.yieldParts and count%24==0 then coroutine.yield() end
  end
 end
 return holder
end
function Renderer.Preview(parent,model,options)
 damageRoot=RS:FindFirstChild("GlassDamageState")
 Renderer.Drop(model);built[model]=Renderer.BuildInto(parent,model,options)
 return built[model]
end
function Renderer.Stats()
 local n,p,f=0,0,0
 for _,e in built do n+=1;for _ in e.parts do p+=1 end end
 for _ in far do f+=1 end
 return n,p,#pool,f,Shards.Stats()
end
function Renderer.Init()
 if initialized then return end;initialized=true
 nearFolder=Instance.new("Folder");nearFolder.Name="LocalFacades";nearFolder.Parent=workspace
 farFolder=Instance.new("Folder");farFolder.Name="LocalFacadesFar";farFolder.Parent=workspace
 damageRoot=RS:WaitForChild("GlassDamageState",30)
 local modelsById={}
 local function invalidate(m) dirty[m]=true;epochs[m]=(epochs[m] or 0)+1 end
 local function watchDamage(f)
  local function watchPage(p) p:GetAttributeChangedSignal("Cells"):Connect(function()
   snapshots[f]=nil;local m=modelsById[f.Name];if m then invalidate(m) end
  end) end
  for _,p in f:GetChildren() do watchPage(p) end
  f:GetAttributeChangedSignal("Revision"):Connect(function()
   snapshots[f]=nil;local m=modelsById[f.Name];if m then invalidate(m) end
  end)
  f.ChildAdded:Connect(function(p)watchPage(p);snapshots[f]=nil;local m=modelsById[f.Name];if m then invalidate(m) end end)
 end
 if damageRoot then
  for _,f in damageRoot:GetChildren() do watchDamage(f) end
  damageRoot.ChildAdded:Connect(watchDamage)
  damageRoot.ChildRemoved:Connect(function(f)snapshots[f]=nil;local m=modelsById[f.Name];if m then invalidate(m) end end)
 end
 local buildings=workspace:WaitForChild("Buildings")
 local eligibilityConnections={}
 local function refreshEligibility(m)
  if not Geometry.UpperEnabled(m) then
   local old=candidates[m];if old then for _,c in old.connections do c:Disconnect() end end
   candidates[m]=nil;invalidate(m);Renderer.Drop(m);dropFar(m)
   return
  end
  if not candidates[m] then
   local connections={};candidates[m]={connections=connections}
   for _,attr in {"FacadeVersion","SourceSlicePlan"} do
    table.insert(connections,m:GetAttributeChangedSignal(attr):Connect(function()invalidate(m)end))
   end
  end
  invalidate(m)
 end
 local function consider(m)
  if not m:IsA("Model") or not m:GetAttribute("SourceSlicePlan") or eligibilityConnections[m] then return end
  local connections={};eligibilityConnections[m]=connections;modelsById[Geometry.Id(m)]=m
  for _,attr in {"GroundFacadeOwnedRuns"} do
   table.insert(connections,m:GetAttributeChangedSignal(attr):Connect(function()refreshEligibility(m)end))
  end
  table.insert(connections,m.ChildAdded:Connect(function(c)if c.Name=="GroundFacadePilot" then refreshEligibility(m) end end))
  table.insert(connections,m.ChildRemoved:Connect(function(c)if c.Name=="GroundFacadePilot" then refreshEligibility(m) end end))
  refreshEligibility(m)
 end
 for _,m in buildings:GetChildren() do consider(m) end
 buildings.ChildAdded:Connect(consider)
 buildings.ChildRemoved:Connect(function(m)
  local connections=eligibilityConnections[m];if connections then for _,c in connections do c:Disconnect() end end
  eligibilityConnections[m]=nil
  local e=candidates[m];if e then for _,c in e.connections do c:Disconnect() end end
  candidates[m]=nil;dirty[m]=nil;modelsById[Geometry.Id(m)]=nil;Renderer.Drop(m);dropFar(m)
 end)
 local function watchGround(p)
  if not p:IsA("BasePart") or not p:IsDescendantOf(workspace) or p:GetAttribute("GlassClientGeometry") or p:GetAttribute("GlassDemoPane") then return end
  if ground[p] then return end
  local info={detail=nil};ground[p]=info
  info.connection=p:GetAttributeChangedSignal("GlassState"):Connect(function()
   task.defer(function()if p.Parent then Visual.Apply(p,p:GetAttribute("GlassState") or 1,{textures=info.detail~=false}) end end)
  end)
 end
 for _,p in Tags:GetTagged("GlassPane") do watchGround(p) end
 Tags:GetInstanceAddedSignal("GlassPane"):Connect(watchGround)
 Tags:GetInstanceRemovedSignal("GlassPane"):Connect(function(p)
  local info=ground[p];if info then info.connection:Disconnect();ground[p]=nil end
 end)
 local event=RS:WaitForChild("GlassDamageEvent",30)
 if event then event.OnClientEvent:Connect(function(id,rows,from)
  local m=modelsById[id];if m then invalidate(m) end
  local budget=Config.MaxShardsPerEvent
  for _,row in rows do if budget<=0 then break end
   if row[2]>=3 and row[3] and row[4] then
    local count=Shards.Emit(CFrame.new(table.unpack(row[3])),Vector3.new(table.unpack(row[4])),from,math.min(Config.ShardsPerPane,budget))
    budget-=count
   end
  end
 end) end
 local queue,lastScan,lastPos={},0,nil
 local active
 local function cancel()
  if active then
   if active.partial then
    if active.job.near then for p in active.partial.parts do release(p) end;active.partial.model:Destroy()
    else active.partial:Destroy() end
   end
   active=nil
  end
 end
 Run.Heartbeat:Connect(function(dt)
  local cam=workspace.CurrentCamera;if not cam then return end
  local pos=cam.CFrame.Position;local speed=lastPos and (pos-lastPos).Magnitude/math.max(dt,.001) or 0;lastPos=pos
  if os.clock()-lastScan>.5 then
   lastScan=os.clock();queue={}
   for p,info in ground do
    if p.Parent then local detail=(p.Position-pos).Magnitude<(info.detail and Config.DetailRadius+40 or Config.DetailRadius)
     if info.detail~=detail then info.detail=detail;Visual.Apply(p,p:GetAttribute("GlassState") or 1,{textures=detail}) end
    else info.connection:Disconnect();ground[p]=nil end
   end
   for m in candidates do
    local d=(m:GetPivot().Position-pos).Magnitude
    if dirty[m] then Renderer.Drop(m);dropFar(m);dirty[m]=nil end
    local detail=built[m] and built[m].detail and d<Config.DetailRadius+40 or d<Config.DetailRadius
    if built[m] and (d>Config.DropRadius or built[m].detail~=detail) then Renderer.Drop(m) end
    if far[m] and (not Config.FarProxyEnabled or d>Config.FarDropRadius or d<Config.NearRadius) then dropFar(m) end
    if not built[m] and d<Config.NearRadius then table.insert(queue,{model=m,d=d,near=true,detail=d<Config.DetailRadius})
    elseif Config.FarProxyEnabled and not built[m] and not far[m] and d<Config.FarRadius then table.insert(queue,{model=m,d=d,near=false}) end
   end
   table.sort(queue,function(a,b)return a.d<b.d end)
   local n,p,pooled,f,particles=Renderer.Stats()
   nearFolder:SetAttribute("BuiltBuildings",n);nearFolder:SetAttribute("Parts",p)
   nearFolder:SetAttribute("PooledParts",pooled);nearFolder:SetAttribute("FarBuildings",f)
   nearFolder:SetAttribute("LiveShardParticles",particles);nearFolder:SetAttribute("GlassVersion",Config.VERSION)
   local allowed=0;for _ in candidates do allowed+=1 end
   nearFolder:SetAttribute("EligibleBuildings",allowed)
   nearFolder:SetAttribute("GeneratedFacadeScope",Config.GeneratedFacadeScope)
   nearFolder:SetAttribute("FarProxyEnabled",Config.FarProxyEnabled)
   nearFolder:SetAttribute("GeneratedUpperEnabled",Config.GeneratedUpperEnabled~=false)
   local physicalCount=0;for _ in ground do physicalCount+=1 end
   nearFolder:SetAttribute("PhysicalGroundPanes",physicalCount)
  end
  if speed>Config.MaxBuildSpeed then return end
  local start=os.clock()
  while os.clock()-start<Config.FrameBudget do
   if not active then
    local q=table.remove(queue,1);if not q then break end
    if not q.model.Parent or not candidates[q.model] or (q.near and built[q.model]) or (not q.near and far[q.model]) then continue end
    local parent=q.near and nearFolder or farFolder
    q.epoch=epochs[q.model] or 0
    local co=coroutine.create(function()
     if q.near then return Renderer.BuildInto(parent,q.model,{detail=q.detail,yieldParts=true,onStart=function(e)active.partial=e end})
     else return Renderer.BuildFarInto(parent,q.model,{yieldParts=true,onStart=function(e)active.partial=e end}) end
    end)
    active={co=co,job=q,parent=parent}
   end
   local ok,result=coroutine.resume(active.co)
   if not ok then warn("[Glass] Facade build failed:",result);cancel()
   elseif coroutine.status(active.co)=="dead" then
    local q=active.job
    if q.model.Parent and candidates[q.model] and not dirty[q.model] and q.epoch==(epochs[q.model] or 0) then
     if q.near then built[q.model]=result;dropFar(q.model) else far[q.model]=result end
    elseif result then
     if q.near then for p in result.parts do release(p) end;result.model:Destroy() else result:Destroy() end
    end
    active=nil
   end
  end
 end)
end
return Renderer
