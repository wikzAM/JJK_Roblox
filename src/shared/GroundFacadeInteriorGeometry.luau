--!nonstrict
-- ONE tapered pseudo-interior per facade/tenant bay, shared by all its windows.
-- Local +Z is inward. Default 45-degree bay ends; corner plane bisectors can
-- taper farther for acute corners. No subdivisions at glass mullions.
local G={VERSION=2,MaxDepth=3,MinDepth=.4,MaxRooms=48,NearRadius=110,DropRadius=135}
local function segmentDistance(point,frame,width)
	local q=frame:PointToObjectSpace(point)
	return Vector2.new(math.max(0,math.abs(q.X)-width/2),q.Z).Magnitude
end
function G.Panes(bay)
	local out={}
	for _,p in bay:GetChildren() do if p:IsA("BasePart") and p:HasTag("GlassPane") then table.insert(out,p) end end
	return out
end
function G.PlanBay(bay,root,requestedDepth)
	local panes=G.Panes(bay)
	if #panes==0 then return nil,"no glazing" end
	local w,h=bay:GetAttribute("FacadeWidth"),bay:GetAttribute("FacadeHeight")
	if not w or not h or w<2 or h<2 then return nil,"small bay" end
	local cf=bay:GetPivot();local start=-math.huge
	for _,p in panes do local q=cf:PointToObjectSpace(p.Position);start=math.max(start,q.Z+p.Size.Z/2+.06) end
	local depth=math.min(requestedDepth or G.MaxDepth,(w-.8)/2)
	for _,run in root:GetChildren() do
		local f,rw=run:GetAttribute("FacadeRunFrame"),run:GetAttribute("FacadeRunWidth")
		if run~=bay.Parent and typeof(f)=="CFrame" and rw and segmentDistance(cf.Position,f,rw)<w/2+depth*3+2 then
			local n=cf:VectorToObjectSpace(f.ZVector);local distance=(cf.Position-f.Position):Dot(f.ZVector)
			if n.Z<-.98 and distance>0 then depth=math.min(depth,(distance-.08)/(1-n.Z)-start) end
		end
	end
	if depth<G.MinDepth then return nil,"small bay" end
	local left,right=-w/2+.08,w/2-.08
	local backLeft,backRight=left+depth,right-depth
	local own=bay.Parent
	for _,run in root:GetChildren() do
		local frame,width=run:GetAttribute("FacadeRunFrame"),run:GetAttribute("FacadeRunWidth")
		if run==own or typeof(frame)~="CFrame" or not width or segmentDistance(cf.Position,frame,width)>w/2+depth*3+2 then continue end
		local normal=cf:VectorToObjectSpace(frame.ZVector)
		if math.abs(normal.X)<.035 or math.abs(normal.Z)>.98 then continue end
		local distance=(cf.Position-frame.Position):Dot(frame.ZVector)
		if distance+(normal.Z-1)*start<-.04 then continue end
		local frontBound=(.06-distance-(normal.Z-1)*start)/normal.X
		local backBound=(.06-distance-(normal.Z-1)*(start+depth))/normal.X
		if normal.X>0 then left=math.max(left,frontBound);backLeft=math.max(backLeft,backBound)
		else right=math.min(right,frontBound);backRight=math.min(backRight,backBound) end
	end
	if right-left<.5 or backRight-backLeft<.35 then return nil,"corner leaves no safe room" end
	return {frame=cf,start=start,depth=depth,left=left,right=right,backLeft=backLeft,backRight=backRight,bottom=.12,top=h-.12}
end
-- A pane is only a way to locate its shared bay; never a room sizing unit.
function G.Plan(pane,root,depth)
	local bay=pane:FindFirstAncestorWhichIsA("Model")
	if not bay or not bay:GetAttribute("FacadeType") then return nil,"missing bay" end
	return G.PlanBay(bay,root,depth)
end
function G.Rows(c,seed)
	local rows={};local center=(c.backLeft+c.backRight)/2
	local width=c.backRight-c.backLeft;local height=c.top-c.bottom;local middle=(c.top+c.bottom)/2
	local function part(name,cf,size,color,shape) table.insert(rows,{name=name,cframe=cf,size=size,color=color,shape=shape}) end
	local wall=Color3.fromRGB(112+seed%25,109+seed%20,99+seed%17)
	part("BayInteriorRear",CFrame.new(center,middle,c.start+c.depth),Vector3.new(width,height,.05),wall)
	for _,edge in {{c.left,c.backLeft},{c.right,c.backRight}} do
		local a,b=Vector3.new(edge[1],middle,c.start),Vector3.new(edge[2],middle,c.start+c.depth)
		local x=(b-a).Unit;local z=x:Cross(Vector3.yAxis)
		part("BayInteriorSide",CFrame.fromMatrix((a+b)/2,x,Vector3.yAxis,z),Vector3.new((b-a).Magnitude,height,.035),wall)
	end
	for _,y in {c.bottom,c.top} do
		local color=y==c.bottom and Color3.fromRGB(110,103,90) or Color3.fromRGB(172,166,150)
		part("BayInteriorHorizontal",CFrame.new(center,y,c.start+c.depth/2),Vector3.new(width,.035,c.depth),color)
		for _,side in {{c.left,c.backLeft,1},{c.backRight,c.right,-1}} do
			local delta=side[2]-side[1]
			if delta>.01 then part("BayInteriorTaperFill",CFrame.new((side[1]+side[2])/2,y,c.start+c.depth/2)*CFrame.Angles(0,0,side[3]*math.pi/2)*CFrame.Angles(0,math.pi,0),Vector3.new(.035,delta,c.depth),color,"WedgePart") end
		end
	end
	return rows
end
-- Exact solid probes cover the ENTIRE trapezoid, not just its boundary walls.
function G.VolumeRows(c)
	local center=(c.backLeft+c.backRight)/2;local width=c.backRight-c.backLeft
	local height=c.top-c.bottom;local y=(c.top+c.bottom)/2
	local rows={{cframe=CFrame.new(center,y,c.start+c.depth/2),size=Vector3.new(width,height,c.depth)}}
	for _,s in {{c.left,c.backLeft,1},{c.backRight,c.right,-1}} do
		local delta=s[2]-s[1]
		if delta>.01 then table.insert(rows,{cframe=CFrame.new((s[1]+s[2])/2,y,c.start+c.depth/2)*CFrame.Angles(0,0,s[3]*math.pi/2)*CFrame.Angles(0,math.pi,0),size=Vector3.new(height,delta,c.depth),shape="WedgePart"}) end
	end
	return rows
end
function G.Shape(c)
	local lo,hi=Vector2.one*math.huge,-Vector2.one*math.huge
	local s={poly={},bottom=c.frame.Y+c.bottom,top=c.frame.Y+c.top}
	for _,v in {{c.left,c.start},{c.right,c.start},{c.backRight,c.start+c.depth},{c.backLeft,c.start+c.depth}} do
		local p=c.frame:PointToWorldSpace(Vector3.new(v[1],0,v[2]));local q=Vector2.new(p.X,p.Z)
		table.insert(s.poly,q);lo=lo:Min(q);hi=hi:Max(q)
	end
	s.lo=lo;s.hi=hi;return s
end
function G.OverlapShapes(a,b)
	if not a or not b or math.min(a.top,b.top)-math.max(a.bottom,b.bottom)<.01 then return false end
	if math.min(a.hi.X,b.hi.X)-math.max(a.lo.X,b.lo.X)<.01 or math.min(a.hi.Y,b.hi.Y)-math.max(a.lo.Y,b.lo.Y)<.01 then return false end
	for _,poly in {a.poly,b.poly} do for i,p in poly do
		local edge=poly[i%#poly+1]-p;local axis=Vector2.new(-edge.Y,edge.X).Unit
		local al,ah,bl,bh=math.huge,-math.huge,math.huge,-math.huge
		for _,v in a.poly do local d=v:Dot(axis);al=math.min(al,d);ah=math.max(ah,d) end
		for _,v in b.poly do local d=v:Dot(axis);bl=math.min(bl,d);bh=math.max(bh,d) end
		if math.min(ah,bh)-math.max(al,bl)<.01 then return false end
	end end
	return true
end
return G
