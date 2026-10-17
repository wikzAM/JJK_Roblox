--!nonstrict
-- Cosmetic window cells. Exterior geometry and floor/core structure stay untouched.
-- Inward-tapering cells are separated by the bisectors of nearby facade planes.
local G={VERSION=1,MaxDepth=3,MaxRooms=32,NearRadius=95,DropRadius=115}
local function segmentDistance(point,frame,width)
	local q=frame:PointToObjectSpace(point)
	return Vector2.new(math.max(0,math.abs(q.X)-width/2),q.Z).Magnitude
end
function G.Plan(pane,root)
	local w,h=pane.Size.X,pane.Size.Y
	if w<1.2 or h<2 or pane.Name=="DoorTransom" then return nil,"small pane" end
	local start=pane.Size.Z/2+.04
	local depth=math.min(G.MaxDepth,w*.34,h*.42)
	if depth<.6 then return nil,"small cell" end
	local left,right=-w/2+.06,w/2-.06
	local backLeft,backRight=left+depth,right-depth
	local own=pane:FindFirstAncestorWhichIsA("Model")
	while own and not own:GetAttribute("FacadeRunFrame") do own=own:FindFirstAncestorWhichIsA("Model") end
	if not own then return nil,"missing run" end
	local ownFrame=own:GetAttribute("FacadeRunFrame")
	local ownDistance=(pane.Position-ownFrame.Position):Dot(ownFrame.ZVector)
	for _,run in root:GetChildren() do
		local frame,width=run:GetAttribute("FacadeRunFrame"),run:GetAttribute("FacadeRunWidth")
		if run~=own and typeof(frame)=="CFrame" and width and segmentDistance(pane.Position,frame,width)<w+depth*3 then
			local normal=pane.CFrame:VectorToObjectSpace(frame.ZVector)
			local distance=(pane.Position-frame.Position):Dot(frame.ZVector)-ownDistance
			-- Ignore opposed/concave half-planes that don't contain this window.
			local frontMinimum=distance+math.min(normal.X*left,normal.X*right)+(normal.Z-1)*start
			if frontMinimum>=-.015 and math.abs(normal.X)>.015 then
				local bound=(.04-distance-(normal.Z-1)*(start+depth))/normal.X
				if normal.X>0 then backLeft=math.max(backLeft,bound) else backRight=math.min(backRight,bound) end
			end
		end
	end
	if backRight-backLeft<.35 then return nil,"corner cell too narrow" end
	return {frame=pane.CFrame,start=start,depth=depth,left=left,right=right,backLeft=backLeft,backRight=backRight,
		bottom=-h/2+.06,top=h/2-.06}
end
function G.Rows(cell,seed)
	local c=cell;local rows={};local center=(c.backLeft+c.backRight)/2
	local width=c.backRight-c.backLeft;local height=c.top-c.bottom;local middle=(c.top+c.bottom)/2
	local function part(name,cf,size,color,shape)
		table.insert(rows,{name=name,cframe=cf,size=size,color=color,shape=shape})
	end
	local wall=Color3.fromRGB(104+seed%25,101+seed%20,91+seed%17)
	part("InteriorRear",CFrame.new(center,middle,c.start+c.depth),Vector3.new(width,height,.06),wall)
	for _,edge in {{c.left,c.backLeft},{c.right,c.backRight}} do
		local a,b=Vector3.new(edge[1],middle,c.start),Vector3.new(edge[2],middle,c.start+c.depth)
		local x=(b-a).Unit;local z=x:Cross(Vector3.yAxis)
		part("InteriorTaperSide",CFrame.fromMatrix((a+b)/2,x,Vector3.yAxis,z),Vector3.new((b-a).Magnitude,height,.045),wall)
	end
	for _,y in {c.bottom,c.top} do
		local color=y==c.bottom and Color3.fromRGB(110,103,90) or Color3.fromRGB(172,166,150)
		part("InteriorHorizontal",CFrame.new(center,y,c.start+c.depth/2),Vector3.new(width,.045,c.depth),color)
		for _,side in {{c.left,c.backLeft,1},{c.backRight,c.right,-1}} do
			local delta=side[2]-side[1]
			if delta>.01 then
				part("InteriorTaperFill",CFrame.new((side[1]+side[2])/2,y,c.start+c.depth/2)*CFrame.Angles(0,0,side[3]*math.pi/2)*CFrame.Angles(0,math.pi,0),Vector3.new(.045,delta,c.depth),color,"WedgePart")
			end
		end
	end
	part("InteriorDisplayShelf",CFrame.new(center,c.bottom+height*.32,c.start+c.depth-.27),Vector3.new(width*.82,.14,.42),Color3.fromRGB(62,48,36))
	part("InteriorDisplay",CFrame.new(center,c.bottom+height*.48,c.start+c.depth-.22),Vector3.new(math.min(width*.5,1.5),height*.25,.25),Color3.fromRGB(103+seed%110,73+seed%80,58+seed%95))
	return rows
end
return G
