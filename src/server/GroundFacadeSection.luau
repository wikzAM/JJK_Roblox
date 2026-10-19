-- Edit-only explicit regional or city rollout. Requiring this module never mutates the map.
local Shared=game:GetService("ReplicatedStorage").Shared
local Catalog=require(Shared.GroundFacadeCatalog)
local Layout=require(Shared.FacadeLayout)
local Frontage=require(script.Parent.GroundFacadeFrontage)
local Http=game:GetService("HttpService")
local Section={}
local fallbackPalettes={"cream","white","offwhite","grey","charcoal","darkBrown","stone"}
local excluded={
 ["fbx_6_4510_4915_-8852"]=true, -- Cerulean; old wrong ID corrected in source-slice handoff
 ["orph_703_1736"]=true, -- PARCO
 ["orph_-1012_-190"]=true,["orph_-912_-37"]=true,["part_-424_296"]=true,
 ["BuildingSmooth_14_-6819_752_-938_Body01"]=true,
}
local function listed(set,key)
 if not set or not key then return false end
 if set[key] then return true end
 for _,value in set do if value==key then return true end end
 return false
end
local function footprintArea(plan)
 local area=0
 for _,ring in plan.levels[1].pieces do
  local s=0
  for i,a in ring do local b=ring[i%#ring+1];s+=a[1]*b[2]-b[1]*a[2] end
  area+=math.abs(s)/2
 end
 return area
end
local function segmentDistance(p,a,b)
 local d=b-a;local t=d:Dot(d)>0 and math.clamp((p-a):Dot(d)/d:Dot(d),0,1) or 0
 return (p-(a+d*t)).Magnitude
end
local function inZone(plan,frame,zone)
 local center=zone.center or zone.Center
 local radius=zone.radius or zone.Radius
 if not center or not radius then return false end
 local p=typeof(center)=="Vector3" and Vector2.new(center.X,center.Z) or center
 for _,ring in plan.levels[1].pieces do
  local world={}
  for _,a in ring do local v=frame:PointToWorldSpace(Vector3.new(a[1],0,a[2]));table.insert(world,Vector2.new(v.X,v.Z)) end
  local inside=false
  for i,a in world do
   local b=world[i%#world+1]
   if segmentDistance(p,a,b)<=radius then return true end
   if (a.Y>p.Y)~=(b.Y>p.Y) and p.X<(b.X-a.X)*(p.Y-a.Y)/(b.Y-a.Y)+a.X then inside=not inside end
  end
  if inside then return true end
 end
 return false
end
-- Read-only predicate. No assumed crossing coordinate: caller supplies reviewed zones/IDs.
-- Returns allowed, reason, scalar diagnostic facts. Ground footprint includes all pieces.
function Section.Eligible(model,options)
 local o=options or {};local id=model:GetAttribute("SourceSliceId") or model:GetAttribute("FacadeSourceId")
 local facts={id=id,name=model.Name}
 if excluded[id] or excluded[model.Name] or listed(o.excludedIds,id) or listed(o.excludedIds,model.Name) then return false,"explicit-exclusion",facts end
 if model.Name=="Building1" or model:GetAttribute("Landmark") or model:HasTag("Landmark") or model:GetAttribute("CrownInteresting") then return false,"landmark-or-crown",facts end
 if model:GetAttribute("FacadeExcluded") or model:GetAttribute("StationInfrastructure") then return false,"infrastructure-or-excluded",facts end
 if model:GetAttribute("StructuralOnly")~=true then return false,"not-ordinary",facts end
 local encoded=model:GetAttribute("SourceSlicePlan") or model:GetAttribute("FacadeSourcePlan")
 if type(encoded)~="string" or not id then return false,"missing-source-plan",facts end
 local okay,plan=pcall(function() return Http:JSONDecode(encoded) end)
 if not okay or type(plan)~="table" or type(plan.levels)~="table" or #plan.levels<2 or not plan.levels[1].pieces then return false,"invalid-source-plan",facts end
 local n=model:GetAttribute("SourceSlicePlan") and model:GetAttribute("GeneratedFloors") or model:GetAttribute("FacadeFloorCount") or model:GetAttribute("GeneratedFloors");facts.floors=n
 if type(n)~="number" or n~=n or n%1~=0 or n<1 or n>(o.maxFloors or 15) or n~=#plan.levels-1 then return false,"story-limit-or-mismatch",facts end
 local areaOkay,area=pcall(footprintArea,plan)
 if not areaOkay or area~=area or area<=0 or area==math.huge then return false,"invalid-footprint",facts end
 facts.area=area
 if area>(o.maxFootprintArea or 30000) then return false,"large-footprint",facts end
 local frame=Layout.FrameOf(model)
 if typeof(frame)~="CFrame" then return false,"missing-source-frame",facts end
 for _,zone in o.zones or o.excludedZones or {} do
  if inZone(plan,frame,zone) then facts.zone=zone.id or zone.name or "protected-zone";return false,"protected-zone",facts end
 end
 if o.crossingCenter and o.crossingRadius and inZone(plan,frame,{center=o.crossingCenter,radius=o.crossingRadius}) then return false,"crossing-zone",facts end
 return true,"eligible",facts
end
local function copy(value)
 if type(value)~="table" then return value end
 local result={};for k,v in value do result[k]=copy(v) end;return result
end
function Section.SelectCity(options)
 assert(not game:GetService("RunService"):IsRunning(),"Edit only")
 local o=options or {};local center=o.center or Vector3.zero
 local scene=Frontage.Index(center,100000)
 local existing={};for _,row in o.existing or {} do existing[row.id]=row end
 local rows,candidates={},{ }
 local report={eligible=0,held=0,reasons={},heldBuildings={},eligibleIds={},sourceCandidates=#scene.buildings}
 report.reasonCounts=report.reasons
 local byModel={};for _,b in scene.buildings do byModel[b.model]=b end
 for i,m in workspace.Buildings:GetChildren() do
  local allowed,reason,facts=Section.Eligible(m,o)
  if allowed and byModel[m] then table.insert(candidates,byModel[m])
  else
   if allowed then reason="not-indexed" end
   report.held+=1;report.reasons[reason]=(report.reasons[reason] or 0)+1;facts.reason=reason;table.insert(report.heldBuildings,facts)
  end
  if i%50==0 then task.wait() end
 end
 table.sort(candidates,function(a,b) return a.id<b.id end)
 local palettes=Catalog.PALETTE_ORDER or fallbackPalettes
 for _,b in candidates do
  local saved=existing[b.id]
  local row=saved and saved.frontageRevision==Frontage.REVISION and copy(saved) or Frontage.Survey(scene,b)
  if saved then row.palette=saved.palette;row.nameSeed=saved.nameSeed end
  if #row.faces>0 then
   row.palette=palettes[Catalog.Seed("wall/"..b.id)%#palettes+1]
   row.nameSeed=row.nameSeed or Catalog.Seed("tenant/"..b.id)
   for _,face in row.faces do if face.class=="front" then face.profile=face.profile or "street" end end
   table.insert(rows,row);report.eligible+=1;table.insert(report.eligibleIds,b.id)
  else
   report.held+=1;report.reasons["no-ground-runs"]=(report.reasons["no-ground-runs"] or 0)+1
   table.insert(report.heldBuildings,{id=b.id,reason="no-ground-runs"})
  end
  task.wait()
 end
 return rows,scene,report
end
-- Original bounded v8 regional API retained for replay tools.
function Section.Select(center,radius,limit,existing)
 assert(not game:GetService("RunService"):IsRunning(),"Edit only")
 assert(radius>0 and radius<=1500 and limit>=1 and limit<=300,"Bounded regional selection required")
 local scene=Frontage.Index(center,radius+400)
 local rows,known={},{}
 for _,r in existing or {} do table.insert(rows,r);known[r.id]=true end
 local candidates={}
 for _,b in scene.buildings do
  local m=b.model
  local d=(Vector3.new(b.frame.X,0,b.frame.Z)-Vector3.new(center.X,0,center.Z)).Magnitude
  if d<=radius and not known[b.id] and m:GetAttribute("StructuralOnly")==true and not m:GetAttribute("CrownInteresting") and not m:GetAttribute("Landmark") and not m:HasTag("Landmark") then table.insert(candidates,{building=b,distance=d}) end
 end
 table.sort(candidates,function(a,b) if a.distance==b.distance then return a.building.id<b.building.id end return a.distance<b.distance end)
 for _,candidate in candidates do
  if #rows>=limit then break end
  local b=candidate.building;local row=Frontage.Survey(scene,b)
  if #row.faces>0 then
   local palettes=Catalog.PALETTE_ORDER or fallbackPalettes
   row.palette=palettes[Catalog.Seed("wall/"..b.id)%#palettes+1];row.nameSeed=Catalog.Seed("tenant/"..b.id)
   for _,face in row.faces do if face.class=="front" then face.profile="mixed" end end
   table.insert(rows,row);known[b.id]=true
  end
  task.wait()
 end
 return rows,scene
end
return Section
