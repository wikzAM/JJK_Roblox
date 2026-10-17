--!nonstrict
-- Recovery audit after a Studio reconnect; READ-ONLY geometry and metadata.
-- Captures CURRENT non-facade originals, then restores BEFORE values for the
-- exact saved core-backup targets in memory. This CANNOT retrospectively prove
-- historical non-core terrain/road/floor preservation before reconnect.
-- Outputs _G.FacadeV9Baseline, _G.FacadeV9ChangedCoreParts,
-- _G.FacadeV9RecoveredCoreModels, _G.FacadeV9RecoveryReport.
-- Fresh core clearance audits are still required after this structural recovery.
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before recovery")
local H=game:GetService("HttpService")
local S=game:GetService("ServerStorage")
local Layout=require(game.ReplicatedStorage.Shared.FacadeLayout)
local LegacyAdapter=require(assert(game.ReplicatedStorage.Shared:FindFirstChild("FacadeLegacyPlan"),"Sync FacadeLegacyPlan before recovery"))
local OPTIONS=_G.FacadeV9RecoveryOptions or {}
local sourceName=OPTIONS.sourceBackup or "FacadeCoreClearanceBackup_4a75ffb8-36f3-4f58-82e0-505ac23e61ea"
local legacyName=OPTIONS.legacyBackup or "FacadeLegacyCoreBackup_489f9061-bd61-43a5-8c67-4bb9f047150e"
local sourceBackup=assert(S:FindFirstChild(sourceName),"Missing exact saved source core backup")
local legacyBackup=assert(S:FindFirstChild(legacyName),"Missing exact saved legacy core backup")
assert(sourceBackup:GetAttribute("FacadeCoreBackupRevision")==9 and legacyBackup:GetAttribute("LegacyCoreBackupRevision")==9,"Wrong backup versions")
local baseline,allowed,allTargets={},{},{}
local backedModels={}
local sourceModels,legacyModels={},{}
local report={revision=9,sourceBackup=sourceName,legacyBackup=legacyName,currentOriginalParts=0,sourceEntries=0,legacyEntries=0,sourceApplied=0,sourceBefore=0,legacyApplied=0,legacyBefore=0,allowedCoreParts=0,restoredCoreBaselineParts=0,historicalNonCoreProof=false,
 limitation="Non-core baseline starts at reconnect; only exact core backups recover historical before-values. Fresh post-clearance audits remain required."}
local function sameCF(a,b,tolerance)
 if typeof(a)~="CFrame" or typeof(b)~="CFrame" then return false end
 local q=a:ToObjectSpace(b)
 return q.Position.Magnitude<=(tolerance or .002) and q.RightVector.X>.99999 and q.UpVector.Y>.99999
end
local function sameSize(a,b,tolerance)return typeof(a)=="Vector3" and typeof(b)=="Vector3" and (a-b).Magnitude<=(tolerance or .002)end
local function deep(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in a do if not deep(v,b[k]) then return false end end
 for k in b do if a[k]==nil then return false end end
 return true
end
local function original(p)
 local ancestor=p.Parent
 while ancestor and ancestor~=workspace.Buildings do
  if ancestor.Name=="GroundFacadePilot" and ancestor:GetAttribute("Owner")=="2026-10-08-ground-pilot" then return false end
  ancestor=ancestor.Parent
 end
 return ancestor==workspace.Buildings
end
for _,m in workspace.Buildings:GetChildren() do
 for _,p in m:GetDescendants() do if p:IsA("BasePart") and original(p) then baseline[p]={p.CFrame,p.Size,p.Color};report.currentOriginalParts+=1 end end
 task.wait()
end
local function backupParts(entry,model)
 local parts={}
 for _,saved in entry:GetChildren() do if saved:IsA("Folder") then
  local ref=saved:FindFirstChild("Target");local p=ref and ref:IsA("ObjectValue") and ref.Value
  local clone=saved:FindFirstChild("ReferenceGeometry")
  local cf,size=saved:GetAttribute("CFrame"),saved:GetAttribute("Size")
  assert(p and p:IsA("BasePart") and p:IsDescendantOf(model) and baseline[p],"Missing/nonoriginal saved core target")
  assert(not allTargets[p],"Ambiguous duplicate saved core target across exact backups")
  assert(clone and clone:IsA("BasePart") and typeof(cf)=="CFrame" and typeof(size)=="Vector3","Incomplete saved core properties")
  assert(sameCF(clone.CFrame,cf) and sameSize(clone.Size,size),"Reference geometry disagrees with saved properties")
  assert(p:IsA("Part") and p:HasTag("BuildingCore") and p.Anchored and p.CanCollide and p.CanQuery,"Saved target lost core provenance/flags")
  assert(p.Color==clone.Color and p.Material==clone.Material,"Core appearance changed outside the allowed resize")
  allTargets[p]=true
  table.insert(parts,{part=p,cf=cf,size=size,color=clone.Color,name=p.Name})
 end end
 assert(#parts>0,"Empty saved core entry")
 return parts
end
local function beforeParts(parts)
 for _,s in parts do if not sameCF(s.part.CFrame,s.cf) or not sameSize(s.part.Size,s.size) then return false end end
 return true
end
local function retainBaseline(parts,applied)
 for _,s in parts do
  baseline[s.part]={s.cf,s.size,s.color};report.restoredCoreBaselineParts+=1
  if applied then allowed[s.part]=true;report.allowedCoreParts+=1 end
 end
end
local function target(entry,idAttribute)
 local value=entry:FindFirstChild("Target");local model=value and value:IsA("ObjectValue") and value.Value
 assert(model and model:IsA("Model") and model.Parent==workspace.Buildings,"Backup target is missing or no longer a live city building")
 local id=entry:GetAttribute(idAttribute);assert(type(id)=="string","Backup lacks stable ID")
 assert(not backedModels[model],"Ambiguous duplicate model across exact backups");backedModels[model]=true
 return model,id
end
local NAMES={"CoreWallFront","CoreWallBack","CoreWallRight","CoreWallLeft","CoreDividerX","CoreDividerZ"}
local function sourceSpecs(c,bottom,top)
 local x,z,w,d=(c.minX+c.maxX)/2,(c.minZ+c.maxZ)/2,c.maxX-c.minX,c.maxZ-c.minZ
 local h,y=top-bottom,(top+bottom)/2
 return {
  {Vector3.new(w,h,1),Vector3.new(x,y,c.maxZ-.5)},
  {Vector3.new(w,h,1),Vector3.new(x,y,c.minZ+.5)},
  {Vector3.new(1,h,d-2),Vector3.new(c.maxX-.5,y,z)},
  {Vector3.new(1,h,d-2),Vector3.new(c.minX+.5,y,z)},
  {Vector3.new(w-2,h,1),Vector3.new(x,y,z)},
  {Vector3.new(1,h,d-2),Vector3.new(x,y,z)},
 }
end
for _,entry in sourceBackup:GetChildren() do
 assert(entry:IsA("Folder"),"Unexpected source backup entry")
 local model,id=target(entry,"SourceSliceId");assert(model:GetAttribute("SourceSliceId")==id,"Source backup identity mismatch")
 local parts=backupParts(entry,model);assert(#parts==6,"Source backup must contain six full-height core pieces")
 local oldRaw=assert(entry:GetAttribute("Before_SourceSlicePlan"),"Missing original source plan")
 local newRaw=assert(model:GetAttribute("SourceSlicePlan"),"Missing live source plan")
 local old,new=H:JSONDecode(oldRaw),H:JSONDecode(newRaw)
 local oldCore,newCore=old.core,new.core;old.core=nil;new.core=nil
 assert(deep(old,new),"Source levels/origin/source metadata changed beyond core bounds: "..id)
 old.core=oldCore;new.core=newCore
 local oldCF=entry:GetAttribute("Before_CoreCFrame");local oldSize=entry:GetAttribute("Before_CoreSize")
 assert(model:GetAttribute("CoreCFrame")==oldCF,"Source core center/orientation changed: "..id)
 local before=beforeParts(parts) and sameSize(model:GetAttribute("CoreSize"),oldSize) and deep(oldCore,newCore)
 if before then
  assert(model:GetAttribute("FacadeCoreClearanceRevision")==entry:GetAttribute("Before_FacadeCoreClearanceRevision") and model:GetAttribute("FacadeCoreClearanceMargin")==entry:GetAttribute("Before_FacadeCoreClearanceMargin"),"Mixed source before-state revision metadata")
  report.sourceBefore+=1
 else
  assert(model:GetAttribute("FacadeCoreClearanceRevision")==9,"Mixed source core revision: "..id)
  assert(math.abs(oldCore.minX+oldCore.maxX-newCore.minX-newCore.maxX)<.001 and math.abs(oldCore.minZ+oldCore.maxZ-newCore.minZ-newCore.maxZ)<.001,"Source core moved horizontally: "..id)
  for _,pair in {{newCore.minX-oldCore.minX},{oldCore.maxX-newCore.maxX},{newCore.minZ-oldCore.minZ},{oldCore.maxZ-newCore.maxZ}} do assert(pair[1]>=-.001 and pair[1]<=6.001,"Unbounded/enlarged source core: "..id) end
  local w,d=newCore.maxX-newCore.minX,newCore.maxZ-newCore.minZ
  assert(w>=3.999 and d>=3.999 and sameSize(model:GetAttribute("CoreSize"),Vector3.new(w,oldSize.Y,d)),"Mixed source CoreSize: "..id)
  local frame=assert(Layout.FrameOf(model),"Missing source frame")
  local specs=sourceSpecs(newCore,new.levels[1].y+new.levels[1].thickness,new.levels[#new.levels].y)
  local seen={}
  for _,s in parts do local index=table.find(NAMES,s.name);assert(index and not seen[index],"Duplicate/unrecognized saved source wall");seen[index]=true
   assert(sameCF(s.part.CFrame,frame*CFrame.new(specs[index][2]),.025) and sameSize(s.part.Size,specs[index][1],.025),"Mixed source core wall: "..id.."/"..s.name)
   assert(math.abs(s.part.Position.Y-s.cf.Y)<.01 and s.part.Size.Y==s.size.Y and s.part.CFrame.RightVector:Dot(s.cf.RightVector)>.99999 and s.part.CFrame.UpVector:Dot(s.cf.UpVector)>.99999,"Source wall Y/orientation changed")
  end
  report.sourceApplied+=1;table.insert(sourceModels,model)
 end
 report.sourceEntries+=1;retainBaseline(parts,not before);task.wait()
end
for _,entry in legacyBackup:GetChildren() do
 assert(entry:IsA("Folder"),"Unexpected legacy backup entry")
 local model,id=target(entry,"Id");assert(not model:GetAttribute("SourceSlicePlan") and id=="legacy/"..model.Name,"Legacy identity mismatch")
 local geometry,why=LegacyAdapter.Read(model);assert(geometry,why)
 local attached=model:GetAttribute("FacadeSourcePlan")
 if attached then
  local saved=H:JSONDecode(attached)
  assert(saved.id==id and #saved.levels==#geometry.plan.levels,"Legacy facade identity/level metadata changed")
  for index,level in saved.levels do local actual=geometry.plan.levels[index]
   assert(math.abs(level.y-actual.y)<.03 and math.abs(level.thickness-actual.thickness)<.03 and deep(level.pieces,actual.pieces),"Legacy native floors disagree with saved facade-level metadata")
  end
 end
 local parts=backupParts(entry,model)
 assert(#parts==6*model:GetAttribute("GeneratedFloors"),"Legacy backup does not cover every per-floor core wall")
 local oldSize=entry:GetAttribute("CoreSize");local size=model:GetAttribute("CoreSize");local cf=model:GetAttribute("CoreCFrame")
 assert(typeof(oldSize)=="Vector3" and typeof(size)=="Vector3" and typeof(cf)=="CFrame" and cf.UpVector.Y>.99999,"Missing legacy core metadata")
 local before=beforeParts(parts) and sameSize(size,oldSize)
 if before then
  assert(model:GetAttribute("FacadeLegacyCoreRevision")==entry:GetAttribute("OldRevision") and model:GetAttribute("FacadeLegacyCoreMargin")==entry:GetAttribute("OldMargin"),"Mixed legacy before-state revision metadata")
  report.legacyBefore+=1
 else
  assert(model:GetAttribute("FacadeLegacyCoreRevision")==9 and size.Y==oldSize.Y,"Mixed legacy core metadata")
  local sx,sz=size.X/oldSize.X,size.Z/oldSize.Z
  assert(sx>0 and sz>0 and sx<=1.000001 and sz<=1.000001 and math.min(size.X,size.Z)>=3.999,"Enlarged/undersized legacy core")
  local maxX,maxZ=0,0;local centerMinY,centerMaxY=math.huge,-math.huge
  for _,s in parts do
   local q=cf:ToObjectSpace(s.cf)
   assert(math.abs(q.RightVector.X)>.99999 and math.abs(q.UpVector.Y)>.99999,"Legacy reference orientation mismatch")
   maxX=math.max(maxX,math.abs(q.X)+s.size.X/2);maxZ=math.max(maxZ,math.abs(q.Z)+s.size.Z/2)
   centerMinY=math.min(centerMinY,s.cf.Y-s.size.Y/2);centerMaxY=math.max(centerMaxY,s.cf.Y+s.size.Y/2)
   local expected=cf*CFrame.new(q.X*sx,q.Y,q.Z*sz)*q.Rotation
   assert(sameCF(s.part.CFrame,expected,.025) and sameSize(s.part.Size,Vector3.new(s.size.X*sx,s.size.Y,s.size.Z*sz),.025),"Mixed/nonaffine legacy wall: "..id)
   assert(s.part.Size.Y==s.size.Y and math.abs(s.part.Position.Y-s.cf.Y)<.01 and math.min(s.part.Size.X,s.part.Size.Z)>=.3999,"Legacy wall height/thickness changed")
   -- Derive original fixed horizontal center from the symmetric legacy wall pairs.
   if s.name=="CoreWallFront" then assert(math.abs(q.X)<.03 and math.abs(q.Z-oldSize.Z/2)<.03,"Legacy core center changed")
   elseif s.name=="CoreWallBack" then assert(math.abs(q.X)<.03 and math.abs(q.Z+oldSize.Z/2)<.03,"Legacy core center changed")
   elseif s.name=="CoreWallLeft" then assert(math.abs(q.Z)<.03 and math.abs(q.X+oldSize.X/2)<.03,"Legacy core center changed")
   elseif s.name=="CoreWallRight" then assert(math.abs(q.Z)<.03 and math.abs(q.X-oldSize.X/2)<.03,"Legacy core center changed") end
  end
  assert(math.abs((centerMinY+centerMaxY)/2-cf.Y)<.03,"Legacy core vertical center changed")
  assert(maxX*(1-sx)<=6.001 and maxZ*(1-sz)<=6.001,"Legacy core shrink exceeded six studs per edge")
  report.legacyApplied+=1;table.insert(legacyModels,model)
 end
 report.legacyEntries+=1;retainBaseline(parts,not before);task.wait()
end
assert(report.sourceEntries==(OPTIONS.expectedSourceEntries or 1657),"Unexpected saved source backup count")
assert(report.legacyEntries==(OPTIONS.expectedLegacyEntries or 24),"Unexpected saved legacy backup count")
for _,model in workspace.Buildings:GetChildren() do
 if model:GetAttribute("FacadeCoreClearanceRevision")==9 or model:GetAttribute("FacadeLegacyCoreRevision")==9 then
  assert(backedModels[model],"Found a v9 core change outside the two exact saved backups: "..model.Name)
 end
end
-- Publish only after EVERY row passes; errors leave no partially trusted new map.
_G.FacadeV9Baseline=baseline
_G.FacadeV9ChangedCoreParts=allowed
_G.FacadeV9RecoveredCoreModels={source=sourceModels,legacy=legacyModels}
_G.FacadeV9RecoveryReport=report
return report
