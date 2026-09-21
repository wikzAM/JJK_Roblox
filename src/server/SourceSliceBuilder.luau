--!nonstrict
-- Exact source floor pieces with ONE common core; no legacy occupancy builder.
-- Plan: {id,origin={x,y,z,yaw?,r00..r22?},levels={{y,thickness,pieces={{{x,z},...},...}},...},
--        core={minX,minZ,maxX,maxZ},sourceInfo?}. Last level is Roof.
-- Origin frame prefers r00–r22; otherwise CFrame.new(x,y,z)*Angles(0,yaw,0).
-- Pieces must tile their intended region without overlap. Holes remain empty.
-- Core min/max are OUTER wall bounds, not wall centerlines.
-- Build(plan) -> unparented Model. StagePlans(plans) -> ServerStorage stage, failures.
-- Audit(modelOrFolder) is read-only. No Apply operation is provided.
local Builder = {}
local Http = game:GetService("HttpService")
local Collection = game:GetService("CollectionService")
local Storage = game:GetService("ServerStorage")
local Polygon = require(script.Parent.PolygonSlab)
local SLAB, MIN_CLEAR, WALL, MIN_SIZE = 1.5/0.28, 2/0.28, 1, 0.05
local CORE_NAMES = {"CoreWallFront","CoreWallBack","CoreWallRight","CoreWallLeft","CoreDividerX","CoreDividerZ"}

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function cross(a,b) return a.X*b.Y-a.Y*b.X end
local function turn(a,b,c) return cross(b-a,c-a) end
local function area(points)
	if #points<3 then return 0 end
	local total,origin=0,points[1]
	for i,a in points do total+=cross(a-origin,points[i%#points+1]-origin) end
	return math.abs(total)/2
end
local function array(t,minimum,maximum,label)
	assert(type(t)=="table" and #t>=minimum and #t<=maximum, "Invalid "..label.." count")
	for key in t do assert(type(key)=="number" and key%1==0 and key>=1 and key<=#t, label.." must be an array") end
end
local function rectangle(x0,z0,x1,z1)
	return {Vector2.new(x0,z0),Vector2.new(x1,z0),Vector2.new(x1,z1),Vector2.new(x0,z1)}
end
local function bounds(points)
	local lo,hi=points[1],points[1]
	for _,p in points do lo=lo:Min(p); hi=hi:Max(p) end
	return lo,hi
end

-- Sutherland-Hodgman clipping against a convex CCW ring. It is also valid for
-- measuring a concave subject clipped to a rectangle: boundary connectors have
-- cancelling signed area. We triangulate subjects for general intersections.
local function clip(subject,convex)
	local output=subject
	for index,a in convex do
		if #output==0 then break end
		local b=convex[index%#convex+1]
		local input=output; output={}
		local previous=input[#input]
		local previousSide=turn(a,b,previous)
		for _,current in input do
			local side=turn(a,b,current)
			if (side>=0)~=(previousSide>=0) then
				local fraction=previousSide/(previousSide-side)
				table.insert(output,previous+(current-previous)*fraction)
			end
			if side>=0 then table.insert(output,current) end
			previous,previousSide=current,side
		end
	end
	return output
end

-- Validation triangulation only; visible geometry still uses PolygonSlab's
-- native-size-aware triangulator. These triangles never modify a source ring.
local function triangles(points)
	local indices,result={},{}
	for i=1,#points do indices[i]=i end
	local lo,hi=bounds(points)
	local eps=math.max(1e-10,(hi-lo).Magnitude^2*1e-10)
	while #indices>3 do
		local found=false
		for index,b in indices do
			local a,c=indices[(index-2)%#indices+1],indices[index%#indices+1]
			if turn(points[a],points[b],points[c])<=eps then continue end
			local blocked=false
			for _,other in indices do
				if other~=a and other~=b and other~=c then
					local p=points[other]
					if turn(points[a],points[b],p)>=-eps and turn(points[b],points[c],p)>=-eps
						and turn(points[c],points[a],p)>=-eps then blocked=true; break end
				end
			end
			if not blocked then
				table.insert(result,{points[a],points[b],points[c]})
				table.remove(indices,index); found=true; break
			end
		end
		assert(found,"Cannot validate polygon triangulation")
	end
	table.insert(result,{points[indices[1]],points[indices[2]],points[indices[3]]})
	return result
end
local function shape(points)
	local lo,hi=bounds(points)
	-- Perimeter is carried for the native overlap tolerance: float32 error on a
	-- round-tripped world CFrame displaces a CORNER, and a displaced edge costs
	-- area in proportion to its LENGTH, not to the plate's area.
	local perimeter=0
	for index,point in points do perimeter+=(points[index%#points+1]-point).Magnitude end
	return {points=points,lo=lo,hi=hi,area=area(points),perimeter=perimeter}
end
local function shapeTriangles(s)
	if not s.triangles then s.triangles=triangles(s.points) end
	return s.triangles
end
local function overlap(a,b)
	if math.min(a.hi.X,b.hi.X)<=math.max(a.lo.X,b.lo.X)
		or math.min(a.hi.Y,b.hi.Y)<=math.max(a.lo.Y,b.lo.Y) then return 0 end
	local total=0
	for _,ta in shapeTriangles(a) do
		for _,tb in shapeTriangles(b) do total+=area(clip(ta,tb)) end
	end
	return total
end
local function noOverlaps(pieces,label,nativeTolerance)
	for i=1,#pieces do for j=i+1,#pieces do
		local tolerance=math.max(nativeTolerance or 0.0001,math.min(pieces[i].area,pieces[j].area)*(nativeTolerance and 2e-5 or 1e-7))
		-- NATIVE ONLY. Measured Sept 20 on the whole-map sweep: a 14-vertex,
		-- 21,516 sq stud plate at |x| 2061 / |z| 2051 triangulates to 30 wedges
		-- whose shared edges accumulated 0.5185 sq studs -- just past the flat
		-- 0.5 -- while the source ring is exact and 24 of 25 buildings passed.
		-- The area term cannot see this: error follows edge length, which is why
		-- the slab-protrusion tolerance above already carries perimeter*0.01.
		-- Same mechanism, same constant. A REAL double slab still overlaps by
		-- its whole area, hundreds of times this.
		if nativeTolerance then
			tolerance=math.max(tolerance,math.min(pieces[i].perimeter or 0,pieces[j].perimeter or 0)*0.01)
		end
		local sharedArea=overlap(pieces[i],pieces[j])
		assert(sharedArea<=tolerance,
			string.format("%s pieces %d and %d overlap (%.6f > %.6f)",label,i,j,sharedArea,tolerance))
	end end
end

local function compile(input)
	assert(type(input)=="table" and type(input.id)=="string" and #input.id>0 and #input.id<=180,"Plan needs a short nonempty id")
	local o=input.origin
	assert(type(o)=="table" and finite(o.x) and finite(o.y) and finite(o.z),"Invalid source origin")
	local yaw=o.yaw or 0
	assert(finite(yaw),"Invalid origin yaw")
	local frame
	if finite(o.r00) then
		for _,key in {"r00","r01","r02","r10","r11","r12","r20","r21","r22"} do
			assert(finite(o[key]),"Invalid origin rotation "..key)
		end
		frame=CFrame.new(o.x,o.y,o.z,o.r00,o.r01,o.r02,o.r10,o.r11,o.r12,o.r20,o.r21,o.r22)
	else
		frame=CFrame.new(o.x,o.y,o.z)*CFrame.Angles(0,yaw,0)
	end
	assert(frame.UpVector.Y>0.999999,"Source origin must stay upright")
	local rot={frame:GetComponents()}
	array(input.levels,2,200,"levels")
	local core=input.core
	assert(type(core)=="table","Missing common core rectangle")
	for _,key in {"minX","minZ","maxX","maxZ"} do assert(finite(core[key]),"Invalid core "..key) end
	assert(core.maxX-core.minX>=4 and core.maxZ-core.minZ>=4,"Common core must be at least 4 studs wide and deep")
	local c={minX=core.minX,minZ=core.minZ,maxX=core.maxX,maxZ=core.maxZ}
	local coreRing=rectangle(c.minX,c.minZ,c.maxX,c.maxZ)
	local coreArea=area(coreRing)
	local canonical={version=1,id=input.id,origin={
		x=o.x,y=o.y,z=o.z,yaw=yaw,
		r00=rot[4],r01=rot[5],r02=rot[6],r10=rot[7],r11=rot[8],r12=rot[9],r20=rot[10],r21=rot[11],r22=rot[12],
	},levels={},core=c,sourceInfo=input.sourceInfo}
	local levels,pieceCount={},0
	local prior
	for index,level in input.levels do
		assert(type(level)=="table" and finite(level.y),"Invalid level elevation")
		local thickness=level.thickness or SLAB
		assert(finite(thickness) and thickness>=MIN_SIZE,"Invalid slab thickness")
		if prior then
			assert(level.y-prior.y-prior.thickness>=MIN_CLEAR-1e-5,"Consecutive levels leave less than 2m clear")
		end
		array(level.pieces,1,2048,"floor pieces")
		local normalized={y=level.y,thickness=thickness,pieces={}}
		local compiled={y=level.y,thickness=thickness,pieces={},area=0}
		local covered=0
		for _,raw in level.pieces do
			array(raw,3,512,"piece vertices")
			local values={}
			for _,p in raw do
				assert(type(p)=="table" and finite(p[1]) and finite(p[2]),"Piece vertices must be [x,z] pairs")
				table.insert(values,Vector2.new(p[1],p[2]))
			end
			local points=Polygon.Validate(values)
			local polygon=shape(points)
			table.insert(compiled.pieces,polygon)
			compiled.area+=polygon.area
			covered+=area(clip(points,coreRing))
			local packed={}
			for _,p in points do table.insert(packed,{p.X,p.Y}) end
			table.insert(normalized.pieces,packed)
			pieceCount+=1
		end
		noOverlaps(compiled.pieces,"Level "..index)
		assert(math.abs(covered-coreArea)<=math.max(0.002,coreArea*1e-6),
			"Common core rectangle leaves the polygon union or enters a hole on level "..index)
		levels[index]=compiled; canonical.levels[index]=normalized; prior=normalized
	end
	local encoded=Http:JSONEncode(canonical) -- reject non-JSON sourceInfo before creating any parts
	return {data=canonical,levels=levels,encoded=encoded,core=c,
		frame=frame,floors=#levels-1,pieces=pieceCount}
end

function Builder.Validate(plan)
	local p=compile(plan)
	return p.data,{floors=p.floors,levels=#p.levels,pieces=p.pieces}
end

local function coreSpecs(core,bottom,top)
	local cx,cz=(core.minX+core.maxX)/2,(core.minZ+core.maxZ)/2
	local width,depth=core.maxX-core.minX,core.maxZ-core.minZ
	local height,y=top-bottom,(bottom+top)/2
	return {
		{CORE_NAMES[1],Vector3.new(width,height,WALL),Vector3.new(cx,y,core.maxZ-WALL/2)},
		{CORE_NAMES[2],Vector3.new(width,height,WALL),Vector3.new(cx,y,core.minZ+WALL/2)},
		{CORE_NAMES[3],Vector3.new(WALL,height,depth-2*WALL),Vector3.new(core.maxX-WALL/2,y,cz)},
		{CORE_NAMES[4],Vector3.new(WALL,height,depth-2*WALL),Vector3.new(core.minX+WALL/2,y,cz)},
		{CORE_NAMES[5],Vector3.new(width-2*WALL,height,WALL),Vector3.new(cx,y,cz)},
		{CORE_NAMES[6],Vector3.new(WALL,height,depth-2*WALL),Vector3.new(cx,y,cz)},
	}
end
local function frameFinite(cf)
	if typeof(cf)~="CFrame" then return false end
	for _,n in {cf:GetComponents()} do if not finite(n) then return false end end
	return true
end
local function sameFrame(a,b)
	local relative=a:ToObjectSpace(b)
	return relative.Position.Magnitude<=0.03 and relative.RightVector:Dot(Vector3.xAxis)>0.99999
		and relative.UpVector:Dot(Vector3.yAxis)>0.99999
end
local function makeCore(parent,spec,frame)
	local part=Instance.new("Part")
	part.Name=spec[1]; part.Size=spec[2]; part.CFrame=frame*CFrame.new(spec[3])
	part.Anchored=true; part.CanCollide=true; part.CanQuery=true
	part.Material=Enum.Material.Concrete; part.Color=Color3.fromRGB(163,162,165)
	part.TopSurface=Enum.SurfaceType.Smooth; part.BottomSurface=Enum.SurfaceType.Smooth
	part:SetAttribute("SourceSliceCore",true)
	Collection:AddTag(part,"BuildingCore")
	part.Parent=parent
	return part
end
local function buildCompiled(p,frame,name)
	local model=Instance.new("Model"); model.Name=name or "BuildingSourceSlice_"..p.data.id
	local ok,err=pcall(function()
		local interior=Instance.new("Model"); interior.Name="Interior"; interior.Parent=model
		local partCount,wedgeCount=0,0
		for index,level in p.levels do
			local floor=Instance.new("Model")
			floor.Name=index==#p.levels and "Roof" or "Floor"..index
			floor:SetAttribute("SourceSliceLevel",index); floor:SetAttribute("SourceSliceY",level.y)
			floor:SetAttribute("SourceSliceArea",level.area); floor.Parent=interior
			for pieceIndex,piece in level.pieces do
				local parts=Polygon.Build(floor,piece.points,level.y,level.thickness,frame,"Slab")
				for _,part in parts do
					part:SetAttribute("SourceSlicePiece",pieceIndex)
					partCount+=1; if part:IsA("WedgePart") then wedgeCount+=1 end
				end
			end
			if index<=p.floors then
				for _,spec in coreSpecs(p.core,level.y+level.thickness,p.levels[index+1].y) do makeCore(floor,spec,frame) end
			end
		end
		local first,last=p.levels[1],p.levels[#p.levels]
		local c=p.core
		model:SetAttribute("SourceSlicePlan",p.encoded)
		model:SetAttribute("SourceSliceVersion",1)
		model:SetAttribute("SourceSliceId",p.data.id)
		model:SetAttribute("SourceSliceOriginCFrame",frame)
		model:SetAttribute("GeneratedFloors",p.floors)
		model:SetAttribute("StructuralOnly",true)
		model:SetAttribute("FootprintMode","ExplicitSourceSlices")
		model:SetAttribute("SourceSliceSlabParts",partCount)
		model:SetAttribute("SourceSliceWedgeParts",wedgeCount)
		model:SetAttribute("CoreCFrame",frame*CFrame.new((c.minX+c.maxX)/2,(first.y+last.y+last.thickness)/2,(c.minZ+c.maxZ)/2))
		model:SetAttribute("CoreSize",Vector3.new(c.maxX-c.minX,last.y+last.thickness-first.y,c.maxZ-c.minZ))
		local cf,size=model:GetBoundingBox()
		model:SetAttribute("InteriorBBoxCFrame",cf); model:SetAttribute("InteriorBBoxSize",size)
		model:SetAttribute("SourceSliceSavedPivot",model:GetPivot())
	end)
	if not ok then model:Destroy(); error(err,2) end
	return model
end

function Builder.Build(plan)
	editOnly()
	local p=compile(plan)
	return buildCompiled(p,p.frame)
end

function Builder.StagePlans(plans)
	editOnly(); array(plans,1,10000,"plans")
	local stage=Instance.new("Folder")
	stage.Name="SourceSliceStage_"..Http:GenerateGUID(false)
	stage:SetAttribute("SourceSliceStageVersion",1); stage.Parent=Storage
	local failures,seen={},{}
	for index,plan in plans do
		local id=type(plan)=="table" and plan.id
		local ok,result=pcall(function()
			assert(not (id and seen[id]),"Duplicate plan id")
			local building=Builder.Build(plan)
			seen[id]=true
			return building
		end)
		if ok then result.Parent=stage
		else table.insert(failures,{index=index,id=tostring(id),reason=tostring(result)}) end
		if index%5==0 then task.wait() end
	end
	stage:SetAttribute("Expected",#stage:GetChildren()); stage:SetAttribute("BuildFailures",#failures)
	print("SOURCE_SLICES_STAGED",#stage:GetChildren(),"ready",#failures,"failed",stage.Name)
	return stage,failures
end

-- Actual projected polygon and vertical extent of a native horizontal slab.
-- Sample both thickness faces, then keep unique XZ corners so a moved
-- regeneration does not depend on loop order or a single face.
local function slabShape(part,frame)
	local vertices={}
	local half=part.Size/2
	if part:IsA("WedgePart") then
		for _,x in {-half.X,half.X} do
			for _,yz in {{-half.Y,-half.Z},{-half.Y,half.Z},{half.Y,half.Z}} do
				table.insert(vertices,frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(x,yz[1],yz[2]))))
			end
		end
	else
		for _,y in {-half.Y,half.Y} do
			for _,xz in {{-half.X,-half.Z},{half.X,-half.Z},{half.X,half.Z},{-half.X,half.Z}} do
				table.insert(vertices,frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(xz[1],y,xz[2]))))
			end
		end
	end
	local low,high=math.huge,-math.huge
	for _,v in vertices do low=math.min(low,v.Y); high=math.max(high,v.Y) end
	local unique={}
	for _,v in vertices do
		local p=Vector2.new(v.X,v.Z)
		local seen=false
		for _,q in unique do if (p-q).Magnitude<0.001 then seen=true; break end end
		if not seen then table.insert(unique,p) end
	end
	return shape(Polygon.Validate(unique)),low,high
end

local function auditModel(model)
	local raw=model:GetAttribute("SourceSlicePlan")
	assert(type(raw)=="string","Missing SourceSlicePlan")
	local p=compile(Http:JSONDecode(raw))
	local frame=model:GetAttribute("SourceSliceOriginCFrame")
	assert(frameFinite(frame) and frame.UpVector.Y>0.999999,"Invalid source slice frame")
	assert(model.Name:match("^Building"),"Invalid building name")
	assert(model:GetAttribute("GeneratedFloors")==p.floors,"GeneratedFloors disagrees with explicit levels")
	assert(not model:GetAttribute("SmoothMassing"),"Source slices incorrectly use the legacy smooth route")
	local interior=model:FindFirstChild("Interior")
	assert(interior and interior:IsA("Model") and #interior:GetChildren()==#p.levels,"Missing/extra floor models")
	local counts={floors=p.floors,levels=#p.levels,slabParts=0,coreParts=0,wedges=0,structuralParts=0,crownParts=0}
	local allowed={}
	for index,level in p.levels do
		local name=index==#p.levels and "Roof" or "Floor"..index
		local floor=interior:FindFirstChild(name)
		assert(floor and floor:IsA("Model"),"Missing "..name)
		local coreExpected={}
		if index<=p.floors then
			for _,spec in coreSpecs(p.core,level.y+level.thickness,p.levels[index+1].y) do coreExpected[spec[1]]=spec end
		end
		local pieceAreas,actualShapes={},{}
		for _,part in floor:GetChildren() do
			assert(part:IsA("Part") or part:IsA("WedgePart"),"Unexpected floor object/class: "..part.Name)
			assert(part.Anchored and part.CanCollide and part.CanQuery,"Invalid structural flags: "..part.Name)
			assert(frameFinite(part.CFrame),"Nonfinite structural frame")
			local size=part.Size
			assert(finite(size.X) and finite(size.Y) and finite(size.Z) and math.min(size.X,size.Y,size.Z)>=MIN_SIZE-1e-6,"Invalid structural size")
			assert(not Collection:HasTag(part,"NoCSG"),"Structure tagged NoCSG")
			allowed[part]=true; counts.structuralParts+=1
			if part.Name=="Slab" then
				assert(part:GetAttribute("PolygonSlab")==true and not Collection:HasTag(part,"BuildingCore"),"Invalid slab tags")
				local pieceIndex=part:GetAttribute("SourceSlicePiece")
				assert(type(pieceIndex)=="number" and level.pieces[pieceIndex],"Unknown source slab piece")
				local relative=frame:ToObjectSpace(part.CFrame)
				local up=part:IsA("WedgePart") and math.abs(relative.RightVector.Y) or math.abs(relative.UpVector.Y)
				assert(up>0.99999,"Slab thickness axis is not vertical")
				local actual,low,high=slabShape(part,frame)
				assert(math.abs(low-level.y)<0.02 and math.abs(high-level.y-level.thickness)<0.02,"Slab vertical extent differs from source level")
				local expected=level.pieces[pieceIndex]
				-- Tolerance tracks the actual error mechanism. slabShape round-trips
				-- each corner through WORLD space, where Roblox stores float32; at
				-- Shibuya coordinates (|x| up to ~3000) that moves a corner by a few
				-- thousandths of a stud. Measured on the two buildings this rejected:
				-- max corner displacement 0.0024 and 0.0027 studs over 212 and 314
				-- slabs. A displaced edge costs AREA proportional to its LENGTH, so a
				-- flat 0.01 sq stud floor fails any large plate for free -- a 400-stud
				-- perimeter turns 0.003 studs into ~1.2 sq studs. Scale by perimeter
				-- instead; a real protrusion is studs wide, not thousandths.
				local perimeter=0
				for index,point in actual.points do
					perimeter+=(actual.points[index%#actual.points+1]-point).Magnitude
				end
				local slack=math.max(0.05,actual.area*2e-5,perimeter*0.01)
				assert(math.abs(overlap(actual,expected)-actual.area)<=slack,"Slab protrudes beyond its source polygon")
				pieceAreas[pieceIndex]=(pieceAreas[pieceIndex] or 0)+actual.area
				table.insert(actualShapes,actual); counts.slabParts+=1
				if part:IsA("WedgePart") then counts.wedges+=1 end
			else
				local expected=coreExpected[part.Name]
				assert(expected and part:IsA("Part") and Collection:HasTag(part,"BuildingCore") and part:GetAttribute("SourceSliceCore")==true,"Missing/duplicate/unexpected core piece")
				assert((part.Size-expected[2]).Magnitude<0.02 and sameFrame(frame*CFrame.new(expected[3]),part.CFrame),"Core geometry shifts or breaks story continuity")
				coreExpected[part.Name]=nil; counts.coreParts+=1
			end
		end
		assert(next(coreExpected)==nil,"Missing core pieces on "..name)
		for pieceIndex,expected in level.pieces do
			assert(math.abs((pieceAreas[pieceIndex] or 0)-expected.area)<=math.max(0.02,expected.area*2e-5),"Slab area differs from source on "..name)
		end
		-- Reconstructing native wedge footprints after a moved regeneration
		-- round-trips world-space float32 CFrames. At Shibuya-scale coordinates,
		-- shared edges can accumulate a fraction of a square stud of numerical
		-- overlap even though the source triangulation is exact.
		-- Raised 0.1 -> 0.5 on Sept 17 against measurement: staging 52 generated
		-- plans (6,258 slab parts, up to 38 vertices a plate) produced overlaps up
		-- to 0.243 sq studs, failing 6 of 51 buildings whose geometry was correct.
		-- 0.5 sq studs is a 0.7-stud square against plates of thousands of sq
		-- studs -- far below anything visible -- and still catches a real double
		-- slab, which overlaps by its whole area. Lower it again if a genuine
		-- overlap ever slips through.
		noOverlaps(actualShapes,name.." native slab",0.5)
	end
	-- Crowns are not floors and never claimed to be: CrownParapet and TriangleShell
	-- parent their parts to the building, beside Interior, so this check failed
	-- every crowned building outright. They are still audited, against the crown
	-- contract instead of the floor contract: a crown part must carry its own
	-- attribute AND be tagged NoCSG, or HitHandler would try to CSG it.
	for _,part in model:GetDescendants() do
		if part:IsA("BasePart") and not allowed[part] then
			assert(part:GetAttribute("CrownParapet") or part:GetAttribute("ShellWedge"),
				"Structural part outside declared floors: "..part.Name)
			assert(Collection:HasTag(part,"NoCSG"),"Crown part is not tagged NoCSG: "..part.Name)
			counts.crownParts+=1
		end
	end
	assert(counts.coreParts==p.floors*6,"Incorrect total common core parts")
	local c,first,last=p.core,p.levels[1],p.levels[#p.levels]
	local expectedCF=frame*CFrame.new((c.minX+c.maxX)/2,(first.y+last.y+last.thickness)/2,(c.minZ+c.maxZ)/2)
	local expectedSize=Vector3.new(c.maxX-c.minX,last.y+last.thickness-first.y,c.maxZ-c.minZ)
	assert(frameFinite(model:GetAttribute("CoreCFrame")) and sameFrame(expectedCF,model:GetAttribute("CoreCFrame")),"CoreCFrame is stale")
	assert(typeof(model:GetAttribute("CoreSize"))=="Vector3" and (model:GetAttribute("CoreSize")-expectedSize).Magnitude<0.02,"CoreSize is stale")
	return counts
end

function Builder.Audit(target)
	assert(typeof(target)=="Instance","Pass a source-slice building or container")
	local list=target:IsA("Model") and target:GetAttribute("SourceSlicePlan") and {target} or target:GetChildren()
	local summary={buildings=0,goodBuildings=0,badBuildings=0,otherModels=0,floors=0,levels=0,slabParts=0,coreParts=0,wedges=0,structuralParts=0,crownParts=0}
	local badModels={}
	for _,model in list do
		if not model:IsA("Model") or not model:GetAttribute("SourceSlicePlan") then summary.otherModels+=1; continue end
		summary.buildings+=1
		local ok,result=pcall(auditModel,model)
		if ok then summary.goodBuildings+=1; for key,value in result do summary[key]+=value end
		else table.insert(badModels,{model=model,name=model.Name,reasons={tostring(result)}}) end
		if summary.buildings%5==0 then task.wait() end
	end
	summary.badBuildings=#badModels
	print("SOURCE_SLICES_AUDIT",Http:JSONEncode(summary))
	return {summary=summary,badModels=badModels}
end

-- Explicit slices retain floor count/elevations. Changing RequestedFloors would
-- require fresh source slices, so this route intentionally has no count override.
function Builder.Regenerate(model)
	editOnly()
	assert(model:IsA("Model"),"Pass a source-slice building")
	local prior=assert(model:FindFirstChild("Interior"),"Missing existing interior")
	local p=compile(Http:JSONDecode(assert(model:GetAttribute("SourceSlicePlan"),"Missing slice plan")))
	local stored=model:GetAttribute("SourceSliceSavedPivot")
	local frame=model:GetAttribute("SourceSliceOriginCFrame")
	assert(frameFinite(stored) and frameFinite(frame),"Missing source slice placement")
	frame=model:GetPivot()*stored:Inverse()*frame
	assert(frame.UpVector.Y>0.999999,"Moved source building must remain upright")
	local staged=buildCompiled(p,frame,model.Name)
	local before=model:GetAttributes()
	local backup=Instance.new("Folder"); backup.Name="SourceSliceRegenerationBackup_"..Http:GenerateGUID(false); backup.Parent=Storage
	local fresh=staged.Interior
	local ok,err=pcall(function()
		prior.Parent=backup; fresh.Parent=model
		for key,value in staged:GetAttributes() do model:SetAttribute(key,value) end
		model:SetAttribute("SourceSliceSavedPivot",model:GetPivot())
		local cf,size=model:GetBoundingBox()
		model:SetAttribute("InteriorBBoxCFrame",cf); model:SetAttribute("InteriorBBoxSize",size)
	end)
	if not ok then
		fresh.Parent=staged; prior.Parent=model
		for key in model:GetAttributes() do if before[key]==nil then model:SetAttribute(key,nil) end end
		for key,value in before do model:SetAttribute(key,value) end
		backup:Destroy(); staged:Destroy(); error(err,2)
	end
	staged:Destroy()
	return true,backup
end

return Builder
