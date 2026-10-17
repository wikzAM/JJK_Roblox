--!nonstrict
-- Read-only final-neighborhood blocker collector, Edit mode only.
-- Optional _G.FacadeV9BlockerOptions={modelIds={id=true,...}} limits a repair pass.
-- First/final acceptance scans should omit modelIds to include earlier neighbors.
-- Global result: _G.FacadeV9BlockedBays[id]["piece/run"][bayIndex]=true.
-- Flat repair rows: _G.FacadeV9BlockerRows. Diagnostics: _G.FacadeV9BlockerScan.
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before scanning facade blockers")
local O=_G.FacadeV9BlockerOptions or {}
local H=game:GetService("HttpService")
local Registry=require(game.ServerScriptService.Server.GroundFacadeRegistry)
local all=workspace:WaitForChild("Buildings")
local reportById={}
local registry=game.ServerStorage:FindFirstChild("GroundFacadePilotManifest")
if registry and Registry.ReadLatest(registry,"Report") then
 local report=H:JSONDecode(Registry.ReadLatest(registry,"Report"))
 for _,row in report.rows or {} do
  local faces={};reportById[row.id]=faces
  for _,face in row.faces or {} do faces[tostring(face.piece).."/"..tostring(face.run)]=face end
 end
end
local blocked,repairRows={},{}
local out={buildings=0,bays=0,failed=0,scannedBuildings=0,scannedBays=0,panesTested=0,visibilityRays=0,volumeChecks=0,unresolved=0,examples={}}
local function example(row) if #out.examples<100 then table.insert(out.examples,row) end end
local function isOpaque(p)
 if not p:IsA("BasePart") or not p.CanQuery or p.Transparency>=.05 or p.Material==Enum.Material.Glass then return false end
 if p.Name=="ClinicPrivacySpandrel" or p.Name=="WorkshopHalfShutter" then return false end
 local owner=p:FindFirstAncestor("GroundFacadePilot");local kind=p:GetAttribute("FacadePieceKind")
 return not owner or kind=="wall" or kind=="plinth" or (not kind and p.Name~="EntryApproachStep")
end
local function resolveIndex(bay,run,panes,id,runKey,ordered)
 -- Physical pane identity is assigned from opts.key=runKey.."/bay"..index.
 -- It survives mirrors, repeated type names and arbitrary child order.
 for _,pane in panes do
  local key=pane:GetAttribute("GlassPaneId")
  local index=type(key)=="string" and tonumber(key:match("/bay(%d+)/"))
  if index then return index,key end
 end
 local runFrame=run:GetAttribute("FacadeRunFrame")
 local width=run:GetAttribute("FacadeRunWidth")
 local face=reportById[id] and reportById[id][runKey]
 if runFrame and width and face and face.types then
  local x=runFrame:PointToObjectSpace(bay:GetPivot().Position).X;local cursor=-width/2
  for index,spec in face.types do
   local w=spec.width
   if type(w)=="number" then
    if math.abs(x-(cursor+w/2))<.25 then return index,"report/"..runKey.."/bay"..index end
    cursor+=w
   end
  end
 end
 -- Kit.PlanRun either creates all equal non-infill bays, or a single plain
 -- infill with no panes. Sorting actual bay pivots is a final stable fallback.
 for index,item in ordered do if item==bay then return index,"position/"..runKey.."/bay"..index end end
 return nil
end
local boxParams=OverlapParams.new();boxParams.FilterType=Enum.RaycastFilterType.Include;boxParams.FilterDescendantsInstances={all}
for _,model in all:GetChildren() do
 local id=model:GetAttribute("SourceSliceId") or model:GetAttribute("FacadeSourceId")
 local root=model:FindFirstChild("GroundFacadePilot")
 if not root or (O.modelIds and not O.modelIds[id]) then continue end
 out.scannedBuildings+=1
 local source={}
 for _,p in model:GetDescendants() do if p:IsA("BasePart") and p.CanQuery and p.Transparency<.95 and not p:IsDescendantOf(root) then table.insert(source,p) end end
 local volume=OverlapParams.new();volume.FilterType=Enum.RaycastFilterType.Include;volume.FilterDescendantsInstances=source;volume.MaxParts=1
 local bc,bs=model:GetBoundingBox();local pool={}
 for _,p in workspace:GetPartBoundsInBox(bc,bs+Vector3.new(60,10,60),boxParams) do if isOpaque(p) then table.insert(pool,p) end end
 local sight=RaycastParams.new();sight.FilterType=Enum.RaycastFilterType.Include;sight.FilterDescendantsInstances=pool
 for _,run in root:GetChildren() do if run:IsA("Model") then
  local piece,index=run:GetAttribute("RunPiece"),run:GetAttribute("RunIndex")
  local runKey=tostring(piece).."/"..tostring(index)
  local ordered={};local runFrame=run:GetAttribute("FacadeRunFrame") or run:GetPivot()
  for _,bay in run:GetChildren() do if bay:IsA("Model") and bay:GetAttribute("FacadeType") then table.insert(ordered,bay) end end
  table.sort(ordered,function(a,b)return runFrame:PointToObjectSpace(a:GetPivot().Position).X<runFrame:PointToObjectSpace(b:GetPivot().Position).X end)
  for _,bay in ordered do
   -- These two authored trims intentionally cover their own glazing. They
   -- remain opaque blockers for every OTHER bay/building.
   local bayPool={}
   for _,p in pool do
    if not (p:IsDescendantOf(bay) and (p.Name=="SmashBrickButtress" or p.Name=="SecurityGrilleBar")) then table.insert(bayPool,p) end
   end
   sight.FilterDescendantsInstances=bayPool
   local panes={}
   for _,p in bay:GetDescendants() do if p:IsA("BasePart") and p:HasTag("GlassPane") then table.insert(panes,p) end end
   if #panes==0 then continue end
   out.scannedBays+=1
   local bayIndex,sourceKey=resolveIndex(bay,run,panes,id,runKey,ordered)
   local failure
   for _,pane in panes do
    out.panesTested+=1;out.volumeChecks+=1
    local hits=workspace:GetPartsInPart(pane,volume)
    if #hits>0 then failure={reason="own-source-overlap",pane=pane:GetFullName(),blocker=hits[1]:GetFullName()};break end
    for _,x in {-.35,0,.35} do
     for _,y in {-.35,0,.35} do
      local q=(pane.CFrame*CFrame.new(pane.Size.X*x,pane.Size.Y*y,pane.Size.Z/2)).Position
      local hit=workspace:Raycast(q-pane.CFrame.ZVector*3,pane.CFrame.ZVector*3.05,sight);out.visibilityRays+=1
      if hit then failure={reason="opaque-occlusion",pane=pane:GetFullName(),blocker=hit.Instance:GetFullName()};break end
     end
     if failure then break end
    end
    if failure then break end -- Further pane tests cannot add another repair bay.
   end
   if failure then
    if not id or not piece or not index or not bayIndex then
     out.unresolved+=1;example({reason="unresolved-bay",buildingid=id,runPiece=piece,runIndex=index,bay=bay:GetFullName(),failure=failure})
    else
     if not blocked[id] then blocked[id]={};out.buildings+=1 end
     blocked[id][runKey]=blocked[id][runKey] or {}
     if not blocked[id][runKey][bayIndex] then
      blocked[id][runKey][bayIndex]=true;out.bays+=1
      local row={buildingid=id,id=id,runPiece=piece,piece=piece,runIndex=index,run=index,bayIndex=bayIndex,runKey=runKey,baySourceKey=sourceKey,reason=failure.reason}
      table.insert(repairRows,row)
      failure.buildingid=id;failure.runPiece=piece;failure.runIndex=index;failure.bayIndex=bayIndex;example(failure)
     end
    end
   end
  end
 end end
 task.wait()
end
out.failed=out.bays+out.unresolved
_G.FacadeV9BlockedBays=blocked
_G.FacadeV9BlockerRows=repairRows
_G.FacadeV9BlockerScan=out
return out
