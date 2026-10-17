--!nonstrict
-- Edit-only geometric acceptance audit. Set _G.FacadeV9AuditOptions first.
-- Read-only: no Instance creation, Source edits, state changes or HTTP exports.
-- Options: helper (fresh module folder), manifest (optional decoded rows),
-- excludedIds/set, crossingCenter/Vector3, crossingRadius/number, maxFootprintArea,
-- baseline/{[BasePart]={CFrame,Size,Color}}, changedCoreParts/set,
-- requireBaseline/boolean, allowExistingExceptions/set, failOnError/boolean.
local O=_G.FacadeV9AuditOptions or {}
assert(not game:GetService("RunService"):IsRunning(),"Stop Play for the Edit audit")
local H=game:GetService("HttpService")
local Registry=require(game.ServerScriptService.Server.GroundFacadeRegistry)
local helper=O.helper or game.ServerStorage:FindFirstChild("FacadeV9Runtime") or game.ServerStorage:FindFirstChild("FacadeClipRuntime")
assert(helper and helper:FindFirstChild("GroundFacadeFrontage"),"Provide the current fresh facade helper")
local F=require(helper.GroundFacadeFrontage)
local config=require(game.ReplicatedStorage.Shared.GlassConfig)
local manifest=O.manifest or H:JSONDecode(Registry.Read(assert(game.ServerStorage:FindFirstChild("GroundFacadePilotManifest")),"Manifest"))
local out={revision=9,buildings=0,runs=0,panes=0,parts=0,exteriorParts=0,coverageRays=0,visibilityRays=0,volumeChecks=0,
 stairs=0,planters=0,ramps=0,portals=0,unchanged=0,changedCores=0,labels=0,japaneseOnly=0,bilingual=0,fonts={},palettes={},glassColors={},wallColors={},errors={},errorCount=0}
local function issue(kind,id,detail)
 out.errorCount+=1
 if #out.errors<500 then table.insert(out.errors,{kind=kind,id=id,detail=detail}) end
end
local expected={};local expectedRuns=0
for _,row in manifest do
 if expected[row.id] then issue("duplicate-manifest-id",row.id) end
 expected[row.id]=row;expectedRuns+=#row.faces
end
local buildings={};local seen={}
for _,m in workspace.Buildings:GetChildren() do
 local root=m:FindFirstChild("GroundFacadePilot")
 if root then table.insert(buildings,{model=m,root=root,id=m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId")}) end
end
local function opaque(p)
 if not p:IsA("BasePart") or not p.CanQuery or p.Transparency>=.05 or p.Material==Enum.Material.Glass then return false end
 if p.Name=="ClinicPrivacySpandrel" or p.Name=="WorkshopHalfShutter" then return false end
 local root=p:FindFirstAncestor("GroundFacadePilot");local kind=p:GetAttribute("FacadePieceKind")
 return not root or kind=="wall" or kind=="plinth" or (not kind and p.Name~="EntryApproachStep")
end
local function polygonArea(ring)
 local s=0;for i,a in ring do local b=ring[i%#ring+1];s+=a[1]*b[2]-b[1]*a[2] end
 return math.abs(s)/2
end
local function recordColor(counts,c)
 local key=string.format("%d,%d,%d",math.round(c.R*255),math.round(c.G*255),math.round(c.B*255))
 counts[key]=(counts[key] or 0)+1
end
local boxes=OverlapParams.new();boxes.FilterType=Enum.RaycastFilterType.Include;boxes.FilterDescendantsInstances={workspace.Buildings}
for _,b in buildings do
 local m,root,id=b.model,b.root,b.id
 out.buildings+=1;seen[id or m.Name]=true
 if not expected[id] then issue("unmanifested-owned-building",id or m.Name) end
 local planEncoded=m:GetAttribute("SourceSlicePlan") or m:GetAttribute("FacadeSourcePlan")
 local plan=planEncoded and H:JSONDecode(planEncoded)
 local grandfathered=O.allowExistingExceptions and O.allowExistingExceptions[id]
 if not plan or m:GetAttribute("StructuralOnly")~=true or m:GetAttribute("CrownInteresting") or m:GetAttribute("Landmark") or m:HasTag("Landmark") or m.Name=="Building1" then issue("ineligible-building",id or m.Name) end
 if O.excludedIds and O.excludedIds[id] then issue("protected-infrastructure",id) end
 if plan and not grandfathered then
  local floors=#plan.levels-1
  local declared=m:GetAttribute("SourceSlicePlan") and m:GetAttribute("GeneratedFloors") or m:GetAttribute("FacadeFloorCount") or m:GetAttribute("GeneratedFloors")
  if floors<1 or floors>15 or declared~=floors then issue("story-count",id,floors) end
  local area=0;for _,r in plan.levels[1].pieces do area+=polygonArea(r) end
  if O.maxFootprintArea and area>O.maxFootprintArea then issue("large-footprint",id,area) end
  local cf=m:GetAttribute("SourceSliceOriginCFrame") or m:GetAttribute("FacadeSourceOriginCFrame")
  if O.crossingRadius and O.crossingCenter and cf and (Vector2.new(cf.X,cf.Z)-Vector2.new(O.crossingCenter.X,O.crossingCenter.Z)).Magnitude<O.crossingRadius then issue("crossing-protection",id) end
 end
 local palette=root:GetAttribute("Palette") or "missing";out.palettes[palette]=(out.palettes[palette] or 0)+1
 local source={}
 for _,p in m:GetDescendants() do if p:IsA("BasePart") and p.CanQuery and p.Transparency<.95 and not p:IsDescendantOf(root) then table.insert(source,p) end end
 local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances=source
 -- Spatial broad phase first: pool includes final neighbors, rather than a stale survey
 -- cache or a global 300k-instance ray filter. Refresh once per owned building.
 local bc,bs=m:GetBoundingBox();local pool={}
 for _,p in workspace:GetPartBoundsInBox(bc,bs+Vector3.new(60,10,60),boxes) do if opaque(p) then table.insert(pool,p) end end
 local sight=RaycastParams.new();sight.FilterType=Enum.RaycastFilterType.Include;sight.FilterDescendantsInstances=pool
 for _,run in root:GetChildren() do if run:IsA("Model") then
  out.runs+=1
  local cf=run:GetAttribute("FacadeRunFrame");local w,h=run:GetAttribute("FacadeRunWidth"),run:GetAttribute("FacadeExpectedHeight")
  if not cf or not w or not h then issue("missing-run-dimensions",id,run.Name);continue end
  local offset=run:GetAttribute("FacadeOutset") or 0
  if offset<0 or offset>1.25 then issue("unbounded-outset",id,offset) end
  local sourceCF=run:GetAttribute("FacadeSourceFrame")
  if not sourceCF or math.abs(sourceCF:PointToObjectSpace(cf.Position).Z+offset)>.01 then issue("wrong-outset-direction",id,run.Name) end
  local portals={}
  for _,bay in run:GetChildren() do if bay:IsA("Model") and bay:GetAttribute("FacadePortals") then
   for _,p in H:JSONDecode(bay:GetAttribute("FacadePortals")) do
    out.portals+=1
    if p.name=="parking" or p.name=="loading" or p.name=="openShop" then
     local q=cf:PointToObjectSpace((bay:GetPivot()*CFrame.new(p.x,0,0)).Position)
     table.insert(portals,{x=q.X,width=p.width,height=p.height,y=p.y or 0})
     if not F.OpenDepth(m,bay:GetPivot()*CFrame.new(p.x,0,0),p.width+.5,22) then issue("blocked-open-portal",id,bay.Name) end
    end
   end
  end end
  local wallRay=RaycastParams.new();wallRay.FilterType=Enum.RaycastFilterType.Include;wallRay.FilterDescendantsInstances={run}
  local n=math.max(2,math.ceil(w/2))
  for i=0,n do for _,y in {.25,h*.25,h*.5,h*.75,h-.1} do
   local x=-w/2+.1+(w-.2)*i/n;local open=false
   for _,p in portals do if math.abs(x-p.x)<p.width/2+.01 and y>p.y-.01 and y<p.y+p.height+.01 then open=true;break end end
   if not open then
    out.coverageRays+=1
    if not workspace:Raycast((cf*CFrame.new(x,y,-2)).Position,cf.ZVector*3,wallRay) then issue("perimeter-hole",id,{run=run.Name,x=x,y=y}) end
   end
  end end
  for _,p in run:GetDescendants() do
   if p:IsA("TextLabel") then
    out.labels+=1;local font=p.FontFace.Family.."/"..tostring(p.FontFace.Weight).."/"..tostring(p.FontFace.Style);out.fonts[font]=(out.fonts[font] or 0)+1
    local hasJapanese=false
    for _,cp in utf8.codes(p.Text) do if (cp>=0x3040 and cp<=0x30FF) or (cp>=0x3400 and cp<=0x9FFF) or (cp>=0xFF66 and cp<=0xFF9F) then hasJapanese=true;break end end
    if hasJapanese then if string.find(p.Text,"[A-Za-z]") then out.bilingual+=1 else out.japaneseOnly+=1 end end
   elseif p:IsA("BasePart") then
    out.parts+=1
    if p:GetAttribute("FacadePieceKind")=="wall" then recordColor(out.wallColors,p.Color) end
    if p:GetAttribute("FacadeLayer")=="exterior" then
     out.exteriorParts+=1
     local bad=false
     for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
      if cf:PointToObjectSpace((p.CFrame*CFrame.new(p.Size*Vector3.new(x,y,z)/2)).Position).Z>.452 then bad=true end
     end end end
     if bad then issue("exterior-inset",id,p:GetFullName()) end
    end
    if p:HasTag("GlassPane") then
     out.panes+=1;out.volumeChecks+=1;recordColor(out.glassColors,p.Color)
     if p:GetAttribute("GlassState")~=1 or p.Transparency>=1 then issue("unexpected-edit-glass-state",id,p:GetFullName()) end
     for _,hit in workspace:GetPartsInPart(p,overlap) do issue("glass-source-intersection",id,{pane=p:GetFullName(),blocker=hit:GetFullName()}) end
     local backing=p:FindFirstChild("InteriorWindowBacking")
     if not backing or backing.CanQuery or backing.CanCollide or not backing:GetAttribute("GlassAttachedOverlay") then issue("invalid-glass-backing",id,p:GetFullName()) end
     for _,x in {-.35,0,.35} do for _,y in {-.35,0,.35} do
      local q=(p.CFrame*CFrame.new(p.Size.X*x,p.Size.Y*y,p.Size.Z/2)).Position
      local hit=workspace:Raycast(q-p.CFrame.ZVector*3,p.CFrame.ZVector*3.05,sight);out.visibilityRays+=1
      if hit then issue("glass-opaque-occlusion",id,{pane=p:GetFullName(),blocker=hit.Instance:GetFullName()}) end
     end end
    elseif p.Name=="EntryApproachStep" then
     out.stairs+=1
     for _,x in {-p.Size.X/2,0,p.Size.X/2} do for _,z in {-p.Size.Z/2,0,p.Size.Z/2} do
      local ground=F.Ground(p.CFrame,x,z)
      if not ground or p.Position.Y-p.Size.Y/2>ground+.12 then issue("floating-step",id,p:GetFullName()) end
     end end
    elseif p:GetAttribute("FacadeSupportBase") then
     out.planters+=1
     local ground=p:GetAttribute("FacadeSupportGroundY")
     if ground then
      if math.abs(p.Position.Y-p.Size.Y/2-ground-.02)>.05 then issue("floating-planter",id,p:GetFullName()) end
     elseif p:GetAttribute("FacadeSupportMode")~="footing-plinth" then issue("unverified-planter-support",id,p:GetFullName()) end
    elseif p.Name=="GarageApproachRamp" then
     out.ramps+=1
     if not p:IsA("WedgePart") or not p.Parent:FindFirstChild("GarageRampSolidBase") then issue("unfilled-car-ramp",id,p:GetFullName()) end
    end
   end
  end
 end end
 task.wait()
end
for id in expected do if not seen[id] then issue("missing-owned-building",id) end end
if out.runs~=expectedRuns then issue("run-count",nil,{expected=expectedRuns,actual=out.runs}) end
if config.GeneratedUpperEnabled~=false or config.FarProxyEnabled~=false then issue("upper-glass-enabled") end
if O.requireBaseline and not O.baseline then issue("missing-source-baseline") end
local baselineScanned=0
for p,v in O.baseline or {} do
 baselineScanned+=1
 if not p.Parent then issue("source-deleted",p.Name)
 elseif O.changedCoreParts and O.changedCoreParts[p] then
  out.changedCores+=1
  if not p:HasTag("BuildingCore") or p.Color~=v[3] or math.abs(p.Size.Y-v[2].Y)>.01 or math.abs(p.Position.Y-v[1].Y)>.01
   or p.Size.X>v[2].X+.01 or p.Size.Z>v[2].Z+.01 or p.CFrame.RightVector:Dot(v[1].RightVector)<.99999 or p.CFrame.UpVector:Dot(v[1].UpVector)<.99999 then issue("invalid-core-change",p:GetFullName()) end
 elseif p.CFrame~=v[1] or p.Size~=v[2] or p.Color~=v[3] then issue("source-changed",p:GetFullName())
 else out.unchanged+=1 end
 if baselineScanned%1000==0 then task.wait() end
end
_G.FacadeV9Audit=out
if O.failOnError~=false then assert(out.errorCount==0,"Facade v9 audit failed: "..out.errorCount.." issues; inspect _G.FacadeV9Audit.errors") end
return out
