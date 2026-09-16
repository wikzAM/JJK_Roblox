--!nonstrict
-- Exact horizontal slabs from one simple polygon (Vector2.X = X, Y = Z).
-- Validate(points) returns a fresh, simple CCW polygon. Holes are not supported.
-- Build(parent, points, yBottom, thickness, frame, name?) -> parts, metrics.
-- Coordinates and yBottom are local to an upright, yaw-only frame.
-- Rectangles use one Part; other polygons retain concave notches via ear clipping
-- and exact right-triangle WedgeParts. No grid, hull or boundary stair-stepping.

local PolygonSlab = {}
local MIN_SIZE = 0.05

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function cross(a, b)
	return a.X*b.Y - a.Y*b.X
end

local function turn(a, b, c)
	return cross(b-a, c-a)
end

local function tolerances(points)
	local lo, hi = points[1], points[1]
	for _, p in points do lo=lo:Min(p); hi=hi:Max(p) end
	local scale = math.max(1, (hi-lo).Magnitude)
	return 1e-7*scale, 1e-7*scale*scale
end

local function signedArea(points)
	local twice, origin = 0, points[1]
	for i, p in points do twice += cross(p-origin, points[i%#points+1]-origin) end
	return twice/2
end

local function onSegment(p, a, b, lengthEps, areaEps)
	return math.abs(turn(a,b,p)) <= areaEps
		and p.X >= math.min(a.X,b.X)-lengthEps and p.X <= math.max(a.X,b.X)+lengthEps
		and p.Y >= math.min(a.Y,b.Y)-lengthEps and p.Y <= math.max(a.Y,b.Y)+lengthEps
end

local function segmentsMeet(a,b,c,d,lengthEps,areaEps)
	local abC,abD,cdA,cdB = turn(a,b,c),turn(a,b,d),turn(c,d,a),turn(c,d,b)
	if ((abC>areaEps and abD< -areaEps) or (abC< -areaEps and abD>areaEps))
		and ((cdA>areaEps and cdB< -areaEps) or (cdA< -areaEps and cdB>areaEps)) then return true end
	return onSegment(c,a,b,lengthEps,areaEps) or onSegment(d,a,b,lengthEps,areaEps)
		or onSegment(a,c,d,lengthEps,areaEps) or onSegment(b,c,d,lengthEps,areaEps)
end

function PolygonSlab.Validate(input)
	assert(type(input)=="table" and #input>=3 and #input<=512, "Polygon needs 3–512 ordered vertices")
	local copied = {}
	for i=1,#input do
		local p=input[i]
		assert(typeof(p)=="Vector2" and finite(p.X) and finite(p.Y), "Polygon vertices must be finite Vector2 values")
		copied[i]=p
	end
	for key in input do assert(type(key)=="number" and key%1==0 and key>=1 and key<=#input,"Polygon must be an array") end
	local lengthEps,areaEps=tolerances(copied)
	local points={}
	for _,p in copied do
		if #points==0 or (p-points[#points]).Magnitude>lengthEps then table.insert(points,p) end
	end
	if #points>1 and (points[1]-points[#points]).Magnitude<=lengthEps then table.remove(points) end
	assert(#points>=3,"Degenerate polygon")
	-- Reject self-touching/crossing outlines before removing collinear vertices.
	for i,a in points do
		local nextI=i%#points+1
		for j=i+1,#points do
			local nextJ=j%#points+1
			if j~=nextI and nextJ~=i then
				assert(not segmentsMeet(a,points[nextI],points[j],points[nextJ],lengthEps,areaEps),"Polygon edges cross or touch")
			end
		end
	end
	local changed=true
	while changed and #points>=3 do
		changed=false
		for i,b in points do
			local a,c=points[(i-2)%#points+1],points[i%#points+1]
			if math.abs(turn(a,b,c))<=areaEps then
				assert((b-a):Dot(c-b)>0,"Polygon doubles back on an edge")
				table.remove(points,i); changed=true; break
			end
		end
	end
	assert(#points>=3 and math.abs(signedArea(points))>areaEps,"Polygon has no usable area")
	if signedArea(points)<0 then
		local reversed={}
		for i=#points,1,-1 do table.insert(reversed,points[i]) end
		points=reversed
	end
	return points
end

local function inTriangle(p,a,b,c,eps)
	return turn(a,b,p)>= -eps and turn(b,c,p)>= -eps and turn(c,a,p)>= -eps
end

local function triangulate(points,eps,makePieces)
	-- Constrain ears by actual native-size feasibility. Backtracking changes only
	-- internal diagonals, so a bad first ear need not reject the whole outline.
	local failed,cache={},{}
	local attempts,limit=0,(#points<=64 and 2048 or 512)
	local function piecesFor(a,b,c)
		local key=a..":"..b..":"..c
		if cache[key]==nil then
			local pieces,subdivisions=makePieces({points[a],points[b],points[c]})
			cache[key]=pieces and {pieces=pieces,subdivisions=subdivisions} or false
		end
		return cache[key]
	end
	local function solve(indices)
		attempts+=1
		if attempts>limit then return nil end
		local key=table.concat(indices,",")
		if failed[key] then return nil end
		if #indices==3 then
			local a,b,c=table.unpack(indices)
			if turn(points[a],points[b],points[c])<=eps then failed[key]=true; return nil end
			local pieces=piecesFor(a,b,c)
			if not pieces then failed[key]=true; return nil end
			return {triangles={{points[a],points[b],points[c]}},pieces=table.clone(pieces.pieces),subdivisions=pieces.subdivisions}
		end
		local ears={}
		for i,b in indices do
			local a,c=indices[(i-2)%#indices+1],indices[i%#indices+1]
			local area=turn(points[a],points[b],points[c])
			if area>eps then
				local blocked=false
				for _,j in indices do
					if j~=a and j~=b and j~=c and inTriangle(points[j],points[a],points[b],points[c],eps) then blocked=true; break end
				end
				if not blocked then
					local pieces=piecesFor(a,b,c)
					if pieces then table.insert(ears,{index=i,a=a,b=b,c=c,area=area,pieces=pieces}) end
				end
			end
		end
		table.sort(ears,function(a,b)
			if #a.pieces.pieces~=#b.pieces.pieces then return #a.pieces.pieces<#b.pieces.pieces end
			if a.area~=b.area then return a.area>b.area end
			return a.index<b.index
		end)
		for _,ear in ears do
			local remaining=table.clone(indices); table.remove(remaining,ear.index)
			local result=solve(remaining)
			if result then
				table.insert(result.triangles,{points[ear.a],points[ear.b],points[ear.c]})
				for _,piece in ear.pieces.pieces do table.insert(result.pieces,piece) end
				result.subdivisions+=ear.pieces.subdivisions
				return result
			end
			if attempts>=limit then break end
		end
		failed[key]=true
		return nil
	end
	local indices={}
	for i=1,#points do indices[i]=i end
	local result=solve(indices)
	assert(result,string.format("No exact native-size triangulation (%.2f stud minimum; %d search states). Outline unchanged",MIN_SIZE,attempts))
	return result.triangles,result.pieces,result.subdivisions,attempts
end

local function v3(p,y)
	return Vector3.new(p.X,y,p.Y)
end

local function isRectangle(points,eps)
	if #points~=4 then return false end
	for i=1,4 do
		local a,b,c=points[i],points[i%4+1],points[(i+1)%4+1]
		if math.abs((b-a):Dot(c-b))>eps then return false end
	end
	return true
end

local function addWedge(plan,a,b,right,up,back,height,depth,thickness,area)
	assert(height>=MIN_SIZE and depth>=MIN_SIZE,"Triangle requires a wedge thinner than Roblox's minimum size; author a simpler outline")
	table.insert(plan,{class="WedgePart",size=Vector3.new(thickness,height,depth),
		cf=CFrame.fromMatrix((a+b)/2,right,up,back),area=area})
end

local function trianglePieces(triangle,y,thickness,eps,allowInteriorSplit)
	local plan={}
	-- A right triangle needs one wedge. Local wedge geometry has its right
	-- angle at (Y=-halfHeight,Z=+halfDepth); the slope rises toward local +Z.
	for i=1,3 do
		local r=triangle[i]
		local u,v=triangle[i%3+1]-r,triangle[(i+1)%3+1]-r
		local rightTolerance=math.min(eps,u.Magnitude*v.Magnitude*1e-7)
		if math.abs(u:Dot(v))<=rightTolerance and u.Magnitude>=MIN_SIZE and v.Magnitude>=MIN_SIZE then
			local up,back=v3(u.Unit,0),-v3(v.Unit,0)
			addWedge(plan,v3(r+u,y),v3(r+v,y),up:Cross(back),up,back,u.Magnitude,v.Magnitude,thickness,math.abs(cross(u,v))/2)
			return plan,0
		end
	end
	-- The longest-side altitude is safe geometrically, but may create a tiny
	-- projection. Examine all three bases and use the best fully internal split.
	local best
	for i=1,3 do
		local a,b,c=triangle[i],triangle[i%3+1],triangle[(i+1)%3+1]
		local edge=c-b
		local depth=edge.Magnitude
		local back=edge/depth
		local left=(a-b):Dot(back)
		local altitude=(a-b)-back*left
		local height=altitude.Magnitude
		local margin=math.min(height,left,depth-left)
		if margin>=MIN_SIZE and (not best or margin>best.margin) then
			best={a=a,b=b,c=c,depth=depth,back=back,left=left,altitude=altitude,height=height,margin=margin}
		end
	end
	if best then
		local up,back=v3(best.altitude/best.height,0),v3(best.back,0)
		local right=up:Cross(back)
		addWedge(plan,v3(best.a,y),v3(best.b,y),right,up,back,best.height,best.left,thickness,best.height*best.left/2)
		addWedge(plan,v3(best.a,y),v3(best.c,y),-right,up,-back,best.height,best.depth-best.left,thickness,best.height*(best.depth-best.left)/2)
		return plan,0
	end
	if allowInteriorSplit then
		-- A nearly right, obtuse corner can have no suitable two-wedge split.
		-- Its incenter lies strictly inside the UNCHANGED triangle; three triangles
		-- meeting there preserve the full area and introduce no boundary vertices.
		local a,b,c=table.unpack(triangle)
		local ab,ac,bc=(a-b).Magnitude,(a-c).Magnitude,(b-c).Magnitude
		local perimeter=ab+ac+bc
		local radius=math.abs(turn(a,b,c))/perimeter
		if radius>=MIN_SIZE then
			local center=a+(b-a)*(ac/perimeter)+(c-a)*(ab/perimeter)
			for i=1,3 do
				local pieces=trianglePieces({center,triangle[i],triangle[i%3+1]},y,thickness,eps,false)
				if not pieces then return nil end
				for _,piece in pieces do table.insert(plan,piece) end
			end
			return plan,1
		end
	end
	return nil
end

function PolygonSlab.Build(parent,input,yBottom,thickness,frame,name)
	assert(typeof(parent)=="Instance","Provide a parent for the slab")
	assert(finite(yBottom) and finite(thickness) and thickness>=MIN_SIZE,"Invalid slab height/thickness")
	assert(typeof(frame)=="CFrame" and frame.UpVector.Y>0.999999,"Slab frame must be upright")
	for _,n in {frame:GetComponents()} do assert(finite(n),"Nonfinite slab frame") end
	assert(name==nil or type(name)=="string","Slab name must be text")
	local points=PolygonSlab.Validate(input)
	local _,eps=tolerances(points)
	local plan,triangles={},{}
	local interiorSubdivisions,triangulationStates=0,0
	local area=signedArea(points)
	local midY=yBottom+thickness/2
	if isRectangle(points,eps) then
		local along,across=points[2]-points[1],points[4]-points[1]
		local center=(points[1]+points[3])/2
		assert(along.Magnitude>=MIN_SIZE and across.Magnitude>=MIN_SIZE,"Rectangle is too thin for Roblox Parts")
		table.insert(plan,{class="Part",size=Vector3.new(along.Magnitude,thickness,across.Magnitude),
			cf=CFrame.fromMatrix(v3(center,midY),v3(along.Unit,0),Vector3.yAxis,v3(across.Unit,0)),area=area})
	else
		triangles,plan,interiorSubdivisions,triangulationStates=triangulate(points,eps,function(triangle)
			return trianglePieces(triangle,midY,thickness,eps,true)
		end)
	end
	local parts={}
	local metrics={area=area,volume=area*thickness,partCount=#plan,rectangleCount=0,wedgeCount=0,
		triangleCount=#triangles,vertexCount=#points,points=points,
		interiorSubdivisions=interiorSubdivisions,triangulationStates=triangulationStates,outlineModified=false}
	local ok,err=pcall(function()
		local builtArea=0
		for _,piece in plan do
			local part=Instance.new(piece.class)
			table.insert(parts,part)
			part.Name=name or "Slab"
			part.Size=piece.size
			-- Do not silently accept engine size clamping (which extrudes edges).
			assert((part.Size-piece.size).Magnitude<math.max(0.0001,piece.size.Magnitude*1e-6),"Roblox clamped a slab piece size")
			part.CFrame=frame*piece.cf
			part.Anchored=true
			part.CanCollide=true
			part.CanQuery=true
			part.Material=Enum.Material.Concrete
			part.Color=Color3.fromRGB(163,162,165)
			part.TopSurface=Enum.SurfaceType.Smooth
			part.BottomSurface=Enum.SurfaceType.Smooth
			part:SetAttribute("PolygonSlab",true)
			part:SetAttribute("SlabFootprintArea",piece.area)
			part:SetAttribute("SlabThickness",thickness)
			if piece.class=="Part" then metrics.rectangleCount+=1 else metrics.wedgeCount+=1 end
			builtArea+=piece.area
		end
		assert(math.abs(builtArea-area)<=math.max(0.001,area*1e-5),"Triangulated area differs from polygon")
		for _,part in parts do part.Parent=parent end
	end)
	if not ok then for _,part in parts do part:Destroy() end; error(err,2) end
	return parts,metrics
end

return PolygonSlab
