--!nonstrict
-- Edit-only city repair for overlapping / disconnected source buildings (owner
-- request Oct 18 2026: "no overlapping buildings; small random buildings can be
-- a simple rectangular box"). Plan() is read-only. ApplyBatch() replaces each
-- selected model with a rectangular SourceSliceBuilder mass that stays inside
-- its own ground footprint and clear of every kept neighbor, or archives a model
-- that has no room left (it sat inside another building). Originals are MOVED
-- into ServerStorage.OverlapBoxRepairArchive (never destroyed).
local Repair={VERSION=1}
local Http=game:GetService("HttpService")
local Collection=game:GetService("CollectionService")
local Builder=require(script.Parent.SourceSliceBuilder)
local Crown=require(script.Parent.CrownParapet)
local Layout=require(game.ReplicatedStorage.Shared.FacadeLayout)
local OWNER="2026-10-18-overlap-box-repair"
local CELL,MARGIN=4,2
local SLAB,MIN_CLEAR=1.5/.28,2/.28
local MIN_OVERLAP,MIN_DETACHED=64,64

local function editOnly()
 assert(not game:GetService("RunService"):IsRunning(),"Edit only")
 assert(game:GetService("NetworkClient"):FindFirstChildWhichIsA("ClientReplicator"),"Connected Edit required")
end
local function protected(m)
 if m.Name=="Building1" or m.Name=="Building2" or m.Name=="Building3" then return true end
 for _,key in {"Landmark","CrownInteresting","StationInfrastructure","FacadeExcluded"} do
  if m:GetAttribute(key) or Collection:HasTag(m,key) then return true end
 end
 return false
end
local function signedArea(ring)
 local s=0 for i,a in ring do local b=ring[i%#ring+1] s+=a[1]*b[2]-b[1]*a[2] end return s/2
end
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
 return #out>=3 and math.abs(signedArea(out)) or 0
end
local function covered(pieces,r)
 local expected=(r.maxX-r.minX)*(r.maxZ-r.minZ);local actual=0
 for _,ring in pieces do actual+=clippedArea(ring,r) end
 return math.abs(expected-actual)<=math.max(.0001,expected*1e-6)
end
local function insidePoly(px,pz,poly)
 local c=false local j=#poly
 for i=1,#poly do local a,b=poly[i],poly[j]
  if (a.Z>pz)~=(b.Z>pz) and px<(b.X-a.X)*(pz-a.Z)/(b.Z-a.Z)+a.X then c=not c end j=i end
 return c
end

-- Rasterise every level's pieces into world cells with vertical extents.
local function record(m)
 local raw=m:GetAttribute("SourceSlicePlan") or m:GetAttribute("FacadeSourcePlan")
 local frame=Layout.FrameOf(m)
 if type(raw)~="string" or typeof(frame)~="CFrame" then return nil end
 local ok,plan=pcall(Http.JSONDecode,Http,raw)
 if not ok or type(plan)~="table" or type(plan.levels)~="table" or #plan.levels<2 then return nil end
 local rec={model=m,id=m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId") or m.Name,plan=plan,frame=frame,
  protected=protected(m),floors=m:GetAttribute("GeneratedFloors") or m:GetAttribute("FacadeFloorCount") or (#plan.levels-1),
  cells={},lo=math.huge,hi=-math.huge}
 for li,lv in plan.levels do
  local top=plan.levels[li+1] and plan.levels[li+1].y or lv.y+(lv.thickness or SLAB)
  local ylo,yhi=frame.Y+lv.y,frame.Y+top
  rec.lo=math.min(rec.lo,ylo);rec.hi=math.max(rec.hi,yhi)
  if li==#plan.levels then continue end
  for _,ring in lv.pieces do
   local poly,x0,z0,x1,z1={},math.huge,math.huge,-math.huge,-math.huge
   for _,p in ring do local w=frame:PointToWorldSpace(Vector3.new(p[1],0,p[2]));table.insert(poly,w)
    x0=math.min(x0,w.X);x1=math.max(x1,w.X);z0=math.min(z0,w.Z);z1=math.max(z1,w.Z) end
   for gx=math.floor(x0/CELL),math.floor(x1/CELL) do for gz=math.floor(z0/CELL),math.floor(z1/CELL) do
    local k=gx..","..gz;local e=rec.cells[k]
    if (not e or e.lo>ylo or e.hi<yhi) and insidePoly((gx+.5)*CELL,(gz+.5)*CELL,poly) then
     if not e then rec.cells[k]={lo=ylo,hi=yhi,gx=gx,gz=gz} else e.lo=math.min(e.lo,ylo);e.hi=math.max(e.hi,yhi) end
    end
   end end
  end
 end
 local comps,seen={},{}
 for k,e in rec.cells do if not seen[k] then
  local stack,size={e},0;seen[k]=true
  while #stack>0 do local c=table.remove(stack);size+=1
   for _,d in {{1,0},{-1,0},{0,1},{0,-1}} do local nk=(c.gx+d[1])..","..(c.gz+d[2]);local ne=rec.cells[nk]
    if ne and not seen[nk] then seen[nk]=true;table.insert(stack,ne) end end
  end
  table.insert(comps,size*CELL*CELL)
 end end
 table.sort(comps,function(a,b) return a>b end)
 rec.components=comps;rec.area=0;for _,a in comps do rec.area+=a end
 return rec
end
local function conflict(rec,occupied,lo,hi)
 local area,with=0,{}
 for k in rec.cells do local o=occupied[k]
  if o then for _,e in o do if math.min(hi,e.hi)-math.max(lo,e.lo)>2 then area+=CELL*CELL;with[e.id]=true;break end end end
 end
 return area,with
end
local function occupy(occupied,id,cells,lo,hi)
 for k in cells do local o=occupied[k];if not o then o={};occupied[k]=o end;table.insert(o,{id=id,lo=lo,hi=hi}) end
end
local function blocked(occupied,wx,wz,lo,hi)
 for _,dx in {-MARGIN,0,MARGIN} do for _,dz in {-MARGIN,0,MARGIN} do
  local o=occupied[math.floor((wx+dx)/CELL)..","..math.floor((wz+dz)/CELL)]
  if o then for _,e in o do if math.min(hi,e.hi)-math.max(lo,e.lo)>2 then return true end end end
 end end
 return false
end
-- Largest axis-aligned rectangle (source frame) fully inside level-1 pieces and
-- clear of every occupied world cell (with MARGIN dilation).
local function rectangle(rec,occupied)
 local pieces=rec.plan.levels[1].pieces
 local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
 for _,ring in pieces do for _,p in ring do x0=math.min(x0,p[1]);z0=math.min(z0,p[2]);x1=math.max(x1,p[1]);z1=math.max(z1,p[2]) end end
 local n=48;local dx,dz=(x1-x0)/n,(z1-z0)/n;local heights={};local best,bestArea=nil,0
 for row=1,n do
  for col=1,n do
   local r={minX=x0+(col-1)*dx,maxX=x0+col*dx,minZ=z0+(row-1)*dz,maxZ=z0+row*dz}
   local free=covered(pieces,r)
   if free then
    for _,q in {{r.minX,r.minZ},{r.maxX,r.minZ},{r.minX,r.maxZ},{r.maxX,r.maxZ},{(r.minX+r.maxX)/2,(r.minZ+r.maxZ)/2}} do
     local w=rec.frame:PointToWorldSpace(Vector3.new(q[1],0,q[2]))
     if blocked(occupied,w.X,w.Z,rec.lo,rec.hi) then free=false;break end
    end
   end
   heights[col]=free and ((heights[col] or 0)+1) or 0
  end
  local stack={}
  for col=1,n+1 do
   local h=col<=n and heights[col] or 0;local left=col
   while #stack>0 and stack[#stack].height>h do
    local item=table.remove(stack);left=item.left
    local w,d=(col-left)*dx,item.height*dz
    if w>=10.1 and d>=10.1 and w*d>bestArea then bestArea=w*d;best={minX=x0+(left-1)*dx,maxX=x0+(col-1)*dx,minZ=z0+(row-item.height)*dz,maxZ=z0+row*dz} end
   end
   if #stack==0 or stack[#stack].height<h then table.insert(stack,{left=left,height=h}) end
  end
  if row%12==0 then task.wait() end
 end
 return best
end
local function rectCells(rec,r)
 local cells={}
 local corners={}
 for _,q in {{r.minX,r.minZ},{r.maxX,r.minZ},{r.maxX,r.maxZ},{r.minX,r.maxZ}} do table.insert(corners,rec.frame:PointToWorldSpace(Vector3.new(q[1],0,q[2]))) end
 local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
 for _,w in corners do x0=math.min(x0,w.X);x1=math.max(x1,w.X);z0=math.min(z0,w.Z);z1=math.max(z1,w.Z) end
 for gx=math.floor(x0/CELL),math.floor(x1/CELL) do for gz=math.floor(z0/CELL),math.floor(z1/CELL) do
  if insidePoly((gx+.5)*CELL,(gz+.5)*CELL,corners) then cells[gx..","..gz]=true end
 end end
 return cells
end

-- Read-only. Returns ordered rows: keep / box / archive with reasons.
function Repair.Plan()
 assert(not game:GetService("RunService"):IsRunning(),"Edit only")
 local recs={}
 for i,m in workspace.Buildings:GetChildren() do
  if m:IsA("Model") then local rec=record(m);if rec then table.insert(recs,rec) end end
  if i%10==0 then task.wait() end
 end
 local function detached(rec) return #rec.components>1 and rec.components[2]>=MIN_DETACHED end
 table.sort(recs,function(a,b)
  if a.protected~=b.protected then return a.protected end
  local da,db=detached(a),detached(b)
  if da~=db then return db end
  local sa,sb=a.area*(a.floors+1),b.area*(b.floors+1)
  if sa~=sb then return sa>sb end
  return a.id<b.id
 end)
 local occupied,rows={},{}
 local summary={keep=0,box=0,archive=0,review=0,protectedConflicts=0}
 for i,rec in recs do
  local area,with=conflict(rec,occupied,rec.lo,rec.hi)
  local names={};for id in with do table.insert(names,id) end
  local row={model=rec.model,id=rec.id,floors=rec.floors,area=rec.area,components=rec.components,conflictArea=area,conflictWith=names,lo=rec.lo,hi=rec.hi}
  if rec.protected then
   row.action="keep";row.reason="protected";if area>=MIN_OVERLAP then summary.protectedConflicts+=1 end
   occupy(occupied,rec.id,rec.cells,rec.lo,rec.hi)
  elseif area<MIN_OVERLAP and not detached(rec) then
   row.action="keep";row.reason="clean"
   occupy(occupied,rec.id,rec.cells,rec.lo,rec.hi)
  else
   row.reason=area>=MIN_OVERLAP and "overlap" or "detached"
   local r=rectangle(rec,occupied)
   if r then row.action="box";row.rect=r;row.rec=rec
    occupy(occupied,rec.id,rectCells(rec,r),rec.lo,rec.hi)
   elseif area/math.max(1,rec.area)<.3 then
    -- Mostly its own ground, just too fragmented for a rectangle: never delete,
    -- leave it untouched for manual review.
    row.action="review";row.reason=row.reason..": fragmented footprint, little overlap"
    occupy(occupied,rec.id,rec.cells,rec.lo,rec.hi)
   else row.action="archive";row.reason=row.reason..": no clear 10.1x10.1 rectangle left" end
  end
  summary[row.action]+=1
  table.insert(rows,row)
  if i%20==0 then task.wait() end
 end
 return {rows=rows,summary=summary}
end

local function boxPlan(row)
 local rec=row.rec;local old=rec.plan;local r=row.rect
 local width,depth=r.maxX-r.minX,r.maxZ-r.minZ
 local floors=math.max(1,math.floor(rec.floors))
 local cx,cz=(r.minX+r.maxX)/2,(r.minZ+r.maxZ)/2
 local cw,cd=math.min(width-6.02,math.max(4.02,width*.3)),math.min(depth-6.02,math.max(4.02,depth*.3))
 local c={rec.frame:GetComponents()}
 local bottom=old.levels[1].y
 local pitch=math.max((old.levels[#old.levels].y-bottom)/floors,SLAB+MIN_CLEAR+.01)
 local ring={{r.minX,r.minZ},{r.maxX,r.minZ},{r.maxX,r.maxZ},{r.minX,r.maxZ}}
 local plan={id=rec.id,origin={x=c[1],y=c[2],z=c[3],r00=c[4],r01=c[5],r02=c[6],r10=c[7],r11=c[8],r12=c[9],r20=c[10],r21=c[11],r22=c[12]},
  core={minX=cx-cw/2,maxX=cx+cw/2,minZ=cz-cd/2,maxZ=cz+cd/2},levels={},
  sourceInfo={repairOwner=OWNER,reason=row.reason,originalId=rec.id,conflictWith=row.conflictWith}}
 for i=0,floors do table.insert(plan.levels,{y=bottom+i*pitch,thickness=SLAB,pieces={ring}}) end
 Builder.Validate(plan)
 return plan
end
local function archiveFolder()
 local a=game.ServerStorage:FindFirstChild("OverlapBoxRepairArchive")
 if not a then a=Instance.new("Folder");a.Name="OverlapBoxRepairArchive";a:SetAttribute("Owner",OWNER);a.Parent=game.ServerStorage end
 return a
end
-- Applies up to 15 rows (box or archive). Each original is moved, never destroyed.
function Repair.ApplyBatch(rows)
 editOnly();assert(#rows<=15,"At most 15 per batch")
 local out={boxed=0,archived=0,errors={},crownFailures=0,models={}}
 local archive=archiveFolder()
 for _,row in rows do
  local m=row.model
  if m.Parent~=workspace.Buildings then table.insert(out.errors,row.id..": no longer live (owner removal preserved)");continue end
  local ok,err=pcall(function()
   local holder=Instance.new("Folder");holder.Name=row.id:gsub("/","_");holder:SetAttribute("Owner",OWNER)
   holder:SetAttribute("Action",row.action);holder:SetAttribute("Reason",row.reason)
   holder:SetAttribute("ConflictWith",Http:JSONEncode(row.conflictWith or {}));holder:SetAttribute("ConflictArea",row.conflictArea)
   local built
   if row.action=="box" then
    built=Builder.Build(boxPlan(row))
    built:SetAttribute("OverlapBoxRepairOwner",OWNER);built:SetAttribute("FacadeBoxRepairNeedsFrontageSurvey",true)
   end
   holder.Parent=archive
   m.Parent=holder
   if built then
    built.Parent=workspace.Buildings
    local p=Http:JSONDecode(built:GetAttribute("SourceSlicePlan"));local frame=built:GetAttribute("SourceSliceOriginCFrame");local roof=p.levels[#p.levels]
    local folder=Instance.new("Folder");folder.Name="Crown";folder.Parent=built
    local cok,res=pcall(Crown.BuildRim,folder,{yaw=math.atan2(-frame.RightVector.Z,frame.RightVector.X),ox=frame.X,oz=frame.Z,y=frame.Y+roof.y+roof.thickness,pieces=roof.pieces},{height=6,thickness=1,tag="NoCSG"})
    if not (cok and res.failed==0) then out.crownFailures+=1 end
    local cf,size=built:GetBoundingBox();built:SetAttribute("InteriorBBoxCFrame",cf);built:SetAttribute("InteriorBBoxSize",size)
    local ref=Instance.new("ObjectValue");ref.Name="Replacement";ref.Value=built;ref.Parent=holder
    out.boxed+=1;table.insert(out.models,built)
   else out.archived+=1 end
  end)
  if not ok then
   if m.Parent~=workspace.Buildings and m.Parent and m.Parent.Parent==archive then m.Parent=workspace.Buildings end
   table.insert(out.errors,row.id..": "..tostring(err))
  end
  task.wait()
 end
 game:GetService("ChangeHistoryService"):ResetWaypoints()
 return out
end
return Repair
