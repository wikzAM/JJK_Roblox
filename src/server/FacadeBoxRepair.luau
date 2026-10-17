--!nonstrict
-- Explicit two-building edit repair. Prepare stages only; Apply archives exact originals.
local Repair = {}
local Http = game:GetService("HttpService")
local Collection = game:GetService("CollectionService")
local Builder = require(script.Parent.SourceSliceBuilder)
local Replacement = require(script.Parent.SourceSliceReplacement)
local Crown = require(script.Parent.CrownParapet)
local Registry = require(script.Parent.GroundFacadeRegistry)
local OWNER = "2026-10-17-selected-box-repair"
local TARGETS = {["fbx_6_16012_2445_-12199"]=10, ["fbx_11_13048_1764_5668"]=5}
local SLAB, MIN_CLEAR = 1.5/.28, 2/.28

local function editOnly()
 assert(not game:GetService("RunService"):IsRunning(), "Stop Play before box repair")
 assert(game:GetService("NetworkClient"):FindFirstChildWhichIsA("ClientReplicator"), "Editing server disconnected; reopen TestJJK before box repair")
end
local function signedArea(ring)
 if #ring<3 then return 0 end
 local sum=0;local o=ring[1]
 for i,a in ring do local b=ring[i%#ring+1];sum+=(a[1]-o[1])*(b[2]-o[2])-(b[1]-o[1])*(a[2]-o[2]) end
 return sum/2
end
-- Exact numeric polygon/rectangle clipping, including concave source rings.
local function clippedArea(ring,r)
 local out=ring
 for _,e in {{1,r.minX,1},{1,r.maxX,-1},{2,r.minZ,1},{2,r.maxZ,-1}} do
  if #out==0 then break end
  local input=out;out={};local prior=input[#input]
  local function side(p) return (p[e[1]]-e[2])*e[3] end
  local ps=side(prior)
  for _,p in input do
   local s=side(p)
   if (s>=0)~=(ps>=0) then local t=ps/(ps-s);table.insert(out,{prior[1]+(p[1]-prior[1])*t,prior[2]+(p[2]-prior[2])*t}) end
   if s>=0 then table.insert(out,p) end
   prior=p;ps=s
  end
 end
 return math.abs(signedArea(out))
end
local function covered(pieces,r)
 local expected=(r.maxX-r.minX)*(r.maxZ-r.minZ);local actual=0
 for _,ring in pieces do actual+=clippedArea(ring,r) end
 return math.abs(expected-actual)<=math.max(.0001,expected*1e-8)
end
local function insideRectangle(pieces)
 local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
 for _,ring in pieces do for _,p in ring do x0=math.min(x0,p[1]);z0=math.min(z0,p[2]);x1=math.max(x1,p[1]);z1=math.max(z1,p[2]) end end
 assert(x1>x0 and z1>z0,"Empty original ground footprint")
 local full={minX=x0,minZ=z0,maxX=x1,maxZ=z1}
 if covered(pieces,full) then return full end
 -- Largest rectangle in a conservative 64x64 binary occupancy grid. A cell is
 -- occupied only if its ENTIRE area is covered, never by point sampling.
 local n=64;local dx,dz=(x1-x0)/n,(z1-z0)/n;local heights={};local best,bestArea=nil,0
 for row=1,n do
  for col=1,n do
   local r={minX=x0+(col-1)*dx,maxX=x0+col*dx,minZ=z0+(row-1)*dz,maxZ=z0+row*dz}
   heights[col]=covered(pieces,r) and ((heights[col] or 0)+1) or 0
  end
  local stack={}
  for col=1,n+1 do
   local h=col<=n and heights[col] or 0;local left=col
   while #stack>0 and stack[#stack].height>h do
    local item=table.remove(stack);left=item.left
    local area=(col-left)*dx*item.height*dz
    if area>bestArea then bestArea=area;best={minX=x0+(left-1)*dx,maxX=x0+(col-1)*dx,minZ=z0+(row-item.height)*dz,maxZ=z0+row*dz} end
   end
   if #stack==0 or stack[#stack].height<h then table.insert(stack,{left=left,height=h}) end
  end
  if row%8==0 then task.wait() end
 end
 assert(best and covered(pieces,best),"No fully contained rectangular footprint")
 return best
end
local function liveFrame(model)
 local frame=assert(model:GetAttribute("SourceSliceOriginCFrame"),"Missing source frame")
 local pivot=assert(model:GetAttribute("SourceSliceSavedPivot"),"Missing saved source pivot")
 frame=model:GetPivot()*pivot:Inverse()*frame
 assert(frame.UpVector.Y>.999999,"Repair must remain upright")
 return frame
end
local function makePlan(model)
 local id=model:GetAttribute("SourceSliceId");local floors=assert(TARGETS[id],"Not an authorized repair ID")
 assert(model.Parent==workspace:FindFirstChild("Buildings"),"Repair source must be live")
 assert(model:GetAttribute("GeneratedFloors")==floors,"Selected building floor count changed")
 for _,key in {"Landmark","CrownInteresting","StationInfrastructure","FacadeExcluded"} do
  assert(not model:GetAttribute(key) and not Collection:HasTag(model,key),"Protected source: "..key)
 end
 local old=Http:JSONDecode(assert(model:GetAttribute("SourceSlicePlan"),"Missing plan"))
 Builder.Validate(old)
 local r=insideRectangle(old.levels[1].pieces)
 local width,depth=r.maxX-r.minX,r.maxZ-r.minZ
 assert(width>=10.1 and depth>=10.1,"Ground rectangle too narrow for a 4-stud core and 3-stud clearance")
 local cx,cz=(r.minX+r.maxX)/2,(r.minZ+r.maxZ)/2
 local cw,cd=math.min(width-6.02,math.max(4,width*.3)),math.min(depth-6.02,math.max(4,depth*.3))
 local frame=liveFrame(model);local c={frame:GetComponents()}
 local bottom=old.levels[1].y
 local pitch=math.max((old.levels[#old.levels].y-bottom)/floors,SLAB+MIN_CLEAR+.01)
 local ring={{r.minX,r.minZ},{r.maxX,r.minZ},{r.maxX,r.maxZ},{r.minX,r.maxZ}}
 local plan={id=id,origin={x=c[1],y=c[2],z=c[3],r00=c[4],r01=c[5],r02=c[6],r10=c[7],r11=c[8],r12=c[9],r20=c[10],r21=c[11],r22=c[12]},
  core={minX=cx-cw/2,maxX=cx+cw/2,minZ=cz-cd/2,maxZ=cz+cd/2},levels={},
  sourceInfo={repairOwner=OWNER,reason="Owner-selected malformed source replaced by contained rectangular mass",originalId=id}}
 for i=0,floors do table.insert(plan.levels,{y=bottom+i*pitch,thickness=SLAB,pieces={ring}}) end
 Builder.Validate(plan)
 return plan,{id=id,floors=floors,width=width,depth=depth,pitch=pitch,groundY=frame.Y+bottom,roofY=frame.Y+bottom+floors*pitch+SLAB,coreClearance=3.01,groundRectangle=r}
end

function Repair.Prepare(models)
 editOnly();assert(type(models)=="table" and #models==2,"Pass exactly the two selected Models")
 local plans,reviews,seen={},{},{}
 for _,model in models do
  local plan,review=makePlan(model);assert(not seen[plan.id],"Duplicate repair ID");seen[plan.id]=true
  table.insert(plans,plan);table.insert(reviews,review)
 end
 local stage,failures=Builder.StagePlans(plans)
 assert(#failures==0 and #stage:GetChildren()==2,"Repair staging failed; originals remain unchanged")
 stage:SetAttribute("FacadeBoxRepairOwner",OWNER)
 stage:SetAttribute("FacadeBoxRepairReview",Http:JSONEncode(reviews))
 local audit=Builder.Audit(stage)
 assert(audit.summary.buildings==2 and audit.summary.goodBuildings==2 and audit.summary.badBuildings==0,"Repair structure audit failed")
 Replacement.Capture(stage,models)
 -- Metadata copies complement the exact original models that Apply archives.
 local metadata=Instance.new("Folder");metadata.Name="FacadeBoxRepairMetadata"
 for _,model in models do
  local row=Instance.new("Folder");row.Name=model:GetAttribute("SourceSliceId");row.Parent=metadata
  Registry.Write(row,"OriginalSourceSlicePlan",model:GetAttribute("SourceSlicePlan"))
  local root=model:FindFirstChild("GroundFacadePilot")
  if root then
   for _,key in {"ManifestRow","ReportRow"} do local raw=Registry.Read(root,key);if raw then Registry.Write(row,key,raw) end end
  end
 end
 -- A sibling metadata folder would invalidate stage's exact-output ownership.
 metadata.Parent=stage.SourceSliceBindings
 return {stage=stage,plans=plans,review=reviews,audit=audit}
end

function Repair.Apply(stage)
 editOnly();assert(stage and stage:GetAttribute("FacadeBoxRepairOwner")==OWNER,"Pass this helper's reviewed stage")
 local repairs={}
 for _,m in stage:GetChildren() do if m:IsA("Model") then
  assert(TARGETS[m:GetAttribute("SourceSliceId")],"Unexpected repair output")
  table.insert(repairs,m)
 end end
 assert(#repairs==2,"Repair output count changed")
 -- Apply performs a fresh structural audit and verifies original snapshots.
 local archive,audit=Replacement.Apply(stage)
 archive:SetAttribute("FacadeBoxRepairOwner",OWNER)
 archive:SetAttribute("FacadeBoxRepairReview",stage:GetAttribute("FacadeBoxRepairReview"))
 local crownResults={}
 for _,model in repairs do
  local p=Http:JSONDecode(model:GetAttribute("SourceSlicePlan"));local frame=model:GetAttribute("SourceSliceOriginCFrame")
  local roof=p.levels[#p.levels]
  local folder=Instance.new("Folder");folder.Name="Crown";folder.Parent=model
  local ok,result=pcall(Crown.BuildRim,folder,{yaw=math.atan2(-frame.RightVector.Z,frame.RightVector.X),ox=frame.X,oz=frame.Z,y=frame.Y+roof.y+roof.thickness,pieces=roof.pieces},{height=6,thickness=1,tag="NoCSG"})
  table.insert(crownResults,{id=p.id,okay=ok and result.failed==0,result=ok and result or tostring(result)})
  model:SetAttribute("FacadeBoxRepairOwner",OWNER)
  model:SetAttribute("FacadeBoxRepairNeedsFrontageSurvey",true)
  local cf,size=model:GetBoundingBox();model:SetAttribute("InteriorBBoxCFrame",cf);model:SetAttribute("InteriorBBoxSize",size)
 end
 return {archive=archive,models=repairs,audit=audit,crowns=crownResults,needsFreshFrontageSurvey=true}
end

return Repair
