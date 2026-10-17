--!nonstrict
-- Pure read-only adapter for legacy exact-polygon floors. Never changes source
-- geometry or adds canonical SourceSlice attributes. Read returns record OR nil,reason.
local Adapter={}
local Http=game:GetService("HttpService")
local EPS=.0005
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function cross(a,b,c)return (b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1]) end
local function area(p)
	if #p<3 then return 0 end
	local sum=0;local o=p[1]
	for i,a in p do local b=p[i%#p+1];sum+=(a[1]-o[1])*(b[2]-o[2])-(a[2]-o[2])*(b[1]-o[1]) end
	return sum/2
end
local function perimeter(p)local v=0;for i,a in p do local b=p[i%#p+1];v+=math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2) end;return v end
local function on(a,b,p)
	return math.abs(cross(a,b,p))<1e-7 and p[1]>=math.min(a[1],b[1])-1e-7 and p[1]<=math.max(a[1],b[1])+1e-7 and p[2]>=math.min(a[2],b[2])-1e-7 and p[2]<=math.max(a[2],b[2])+1e-7
end
local function intersects(a,b,c,d)
	local p,q,r,s=cross(a,b,c),cross(a,b,d),cross(c,d,a),cross(c,d,b)
	return (p*q<0 and r*s<0) or on(a,b,c) or on(a,b,d) or on(c,d,a) or on(c,d,b)
end
local function ring(raw)
	assert(type(raw)=="table" and #raw>=3 and #raw<=512,"Missing/oversized tier ring")
	local p={};for _,a in raw do assert(type(a)=="table" and finite(a[1]) and finite(a[2]),"Invalid tier coordinate");table.insert(p,{a[1],a[2]}) end
	assert(math.abs(area(p))>.01,"Degenerate tier ring")
	for i,a in p do local b=p[i%#p+1];assert((a[1]-b[1])^2+(a[2]-b[2])^2>1e-12,"Duplicate tier vertex")
		for j=i+1,#p do if j~=i%#p+1 and i~=j%#p+1 then assert(not intersects(a,b,p[j],p[j%#p+1]),"Self-intersecting tier ring") end end
	end
	if area(p)<0 then local q={};for i=#p,1,-1 do table.insert(q,p[i]) end;p=q end
	return p
end
local function hull(p)
	table.sort(p,function(a,b)return a[1]==b[1] and a[2]<b[2] or a[1]<b[1] end)
	local unique={};for _,a in p do local b=unique[#unique];if not b or math.abs(a[1]-b[1])+math.abs(a[2]-b[2])>EPS then table.insert(unique,a) end end
	assert(#unique>=3,"Degenerate native slab projection")
	local lower,upper={},{}
	for _,a in unique do while #lower>=2 and cross(lower[#lower-1],lower[#lower],a)<=1e-9 do table.remove(lower) end;table.insert(lower,a) end
	for i=#unique,1,-1 do local a=unique[i];while #upper>=2 and cross(upper[#upper-1],upper[#upper],a)<=1e-9 do table.remove(upper) end;table.insert(upper,a) end
	table.remove(lower);table.remove(upper);for _,a in upper do table.insert(lower,a) end
	return lower
end
local function clippedArea(subject,convex)
	local output=subject
	for i,a in convex do
		if #output==0 then break end
		local b=convex[i%#convex+1];local input=output;output={};local prior=input[#input];local ps=cross(a,b,prior)
		for _,p in input do local s=cross(a,b,p)
			if (s>=0)~=(ps>=0) then local t=ps/(ps-s);table.insert(output,{prior[1]+(p[1]-prior[1])*t,prior[2]+(p[2]-prior[2])*t}) end
			if s>=0 then table.insert(output,p) end;prior=p;ps=s
		end
	end
	return math.abs(area(output))
end
local function native(part,frame)
	assert(part:GetAttribute("PolygonSlab")==true and part.Anchored and part.CanCollide,"Unverified native slab provenance/flags")
	local half=part.Size/2;local points={};local low,high=math.huge,-math.huge
	local function vertex(x,y,z)
		local p=frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(x,y,z)))
		low=math.min(low,p.Y);high=math.max(high,p.Y);table.insert(points,{p.X,p.Z})
	end
	if part:IsA("WedgePart") then
		assert(math.abs(part.CFrame.RightVector.Y)>.99999,"Tilted wedge slab")
		for _,x in {-half.X,half.X} do for _,yz in {{-half.Y,-half.Z},{-half.Y,half.Z},{half.Y,half.Z}} do vertex(x,yz[1],yz[2]) end end
	else
		assert(part:IsA("Part") and part.Shape==Enum.PartType.Block and math.abs(part.CFrame.UpVector.Y)>.99999,"Unsupported native slab shape")
		for _,x in {-half.X,half.X} do for _,y in {-half.Y,half.Y} do for _,z in {-half.Z,half.Z} do vertex(x,y,z) end end end
	end
	return {points=hull(points),lo=low,hi=high}
end
local function inspect(model,useSavedWorldFrame)
	assert(typeof(model)=="Instance" and model:IsA("Model"),"Pass a legacy building Model")
	assert(not model:GetAttribute("SourceSlicePlan"),"Canonical source slices do not use legacy adapter")
	assert(model:GetAttribute("FootprintMode")=="ExactPolygon" and model:GetAttribute("StructuralOnly")==true,"Not an ordinary exact polygon legacy building")
	local p=Http:JSONDecode(assert(model:GetAttribute("SmoothMassing"),"No saved SmoothMassing"))
	assert(p.version==1 and type(p.frame)=="table" and #p.frame==12 and finite(p.height),"Unsupported saved massing")
	local n=model:GetAttribute("GeneratedFloors");assert(finite(n) and n>=1 and n<=15 and n%1==0,"Outside legacy facade floor eligibility")
	local saved=model:GetAttribute("SmoothFrame");assert(typeof(saved)=="CFrame","Missing saved smooth pivot")
	local frame=CFrame.new(table.unpack(p.frame))
	if not useSavedWorldFrame then frame=model:GetPivot()*saved:Inverse()*frame end
	assert(frame.UpVector.Y>.9999 and math.abs(frame.UpVector.X)<.0001 and math.abs(frame.UpVector.Z)<.0001,"Legacy frame is tilted")
local back=Vector3.new(frame.ZVector.X,0,frame.ZVector.Z).Unit;frame=CFrame.fromMatrix(frame.Position,Vector3.yAxis:Cross(back),Vector3.yAxis,back)
	local tiers={};assert(type(p.tiers)=="table" and #p.tiers>=1 and #p.tiers<=n,"Invalid tier count")
	local lastTop=0
	for _,t in p.tiers do
		assert(finite(t.bottom) and finite(t.top) and math.abs(t.bottom-lastTop)<.001 and t.top>t.bottom,"Invalid tier elevation")
		table.insert(tiers,{bottom=t.bottom,top=t.top,points=ring(t.points)});lastTop=t.top
	end
	assert(math.abs(lastTop-p.height)<.001,"Incomplete massing tier height")
	local interior=assert(model:FindFirstChild("Interior"),"Missing native Interior")
	local groups={};local totalSlabs=0
	-- Some legacy Roof models contain multiple real slab planes; native levels,
	-- not stale folder names or GeneratedFloors, define the facade level curves.
	for _,part in interior:GetDescendants() do if part:IsA("BasePart") and part.Name=="Slab" then
		local s=native(part,frame);local group
		for _,g in groups do if math.abs(g.lo-s.lo)<.03 and math.abs(g.hi-s.hi)<.03 then group=g;break end end
		if not group then group={lo=s.lo,hi=s.hi,pieces={},floor1=false};table.insert(groups,group) end
		group.floor1=group.floor1 or part.Parent.Name=="Floor1";table.insert(group.pieces,s);totalSlabs+=1
	end end
	table.sort(groups,function(a,b)return a.lo<b.lo end)
	assert(#groups>=2 and #groups<=16 and groups[1].floor1,"Missing floor1/roof or more than 15 actual storeys")
	local function prove(g,source)
		local expected=area(source);local tolerance=math.max(.02,perimeter(source)*.01,expected*2e-5)
		local total,covered=0,0
		for _,s in g.pieces do
			local a=area(s.points);total+=a;local overlap=clippedArea(source,s.points);covered+=overlap
			if a-overlap>math.max(.02,perimeter(s.points)*.01) then return false,"Native slab leaves saved concave polygon" end
		end
		if math.abs(total-expected)>tolerance or math.abs(covered-expected)>tolerance then return false,"Native slab union differs from saved tier ring" end
		return true,math.max(math.abs(total-expected),math.abs(covered-expected))
	end
	local levels={};local maxError=0;local priorTier=1
	for index,g in groups do
		assert(#g.pieces<=2048,"Excessive native floor pieces")
		for i=1,#g.pieces do for j=i+1,#g.pieces do
			local a,b=g.pieces[i].points,g.pieces[j].points
			assert(clippedArea(a,b)<=math.max(.02,math.min(perimeter(a),perimeter(b))*.01),"Native floor pieces overlap")
		end end
		local selected,errorValue,why
		for t=priorTier,index==1 and 1 or #tiers do
			local okay,result=prove(g,tiers[t].points)
			if okay then selected=t;errorValue=result;break else why=result end
		end
		assert(selected,why or "No exact source tier matches native floor union")
		priorTier=selected;maxError=math.max(maxError,errorValue)
		if index>1 then assert(g.lo-levels[index-1].y-levels[index-1].thickness>=2/.28-.05,"Native floors leave insufficient clearance") end
		table.insert(levels,{y=g.lo,thickness=g.hi-g.lo,pieces={tiers[selected].points}})
	end
	-- Saved SmoothMassing Y can predate FlattenDY; native slab Y is authoritative.
	-- Rebase the adapter to actual floor1 bottom, preserving validated X/Z/yaw.
	local base=levels[1].y;frame=frame*CFrame.new(0,base,0)
	for _,level in levels do level.y-=base end
	local id="legacy/"..model.Name
	local o={frame:GetComponents()}
	local plan={version=1,id=id,origin={x=o[1],y=o[2],z=o[3],r00=o[4],r01=o[5],r02=o[6],r10=o[7],r11=o[8],r12=o[9],r20=o[10],r21=o[11],r22=o[12]},levels=levels,sourceInfo={adapter="SmoothMassing",canonicalSourceSlice=false}}
	return {plan=plan,frame=frame,id=id,floors=#levels-1,verification={levels=#levels,slabParts=totalSlabs,maxAreaError=maxError,baseCorrection=base,actualFloors=#levels-1,savedFloors=n,frameBasis=useSavedWorldFrame and "saved-world-verified" or "pivot-delta-verified"}}
end
function Adapter.Read(model)
	local ok,result=pcall(inspect,model)
	if ok then return result end
	-- Legacy implicit pivots can flip between equivalent wedge-part frames
	-- without moving native geometry. The saved world pose is a second candidate,
	-- accepted ONLY after the same complete native union/elevation proof.
	local fallback,value=pcall(inspect,model,true)
	if fallback then return value end
	return nil,tostring(result).."; saved-world fallback: "..tostring(value)
end
return Adapter
