--!nonstrict
-- Conservative replacement pass. Preview is read-only; Build stages results in
-- ServerStorage; Apply archives earlier auto-generated geometry before swapping.
-- No runtime initialization. Complex massing is deliberately deferred.
local Box = {}
local EPS = 0.1

local function key(p)
	return string.format("%d:%d", math.round(p.X/EPS), math.round(p.Z/EPS))
end

-- Reconstruct one closed horizontal contour. Degree checks reject open facades,
-- branches and touching/disconnected bodies rather than inventing filled space.
local function sections(g,y)
	local segments={}
	for _, t in g.triangles do
		local hits = {}
		for i = 1, 3 do
			local a,b = t[i],t[i%3+1]
			if (a.Y <= y and b.Y > y) or (b.Y <= y and a.Y > y) then
				table.insert(hits,a:Lerp(b,(y-a.Y)/(b.Y-a.Y)))
			end
		end
		if #hits==2 then table.insert(segments,hits) end
	end
	return segments
end

local function contour(g, y)
	local vertices, edges, adjacency = {}, {}, {}
	for _,hits in sections(g,y) do
		if #hits == 2 then
			local a,b = key(hits[1]),key(hits[2])
			local edge = a < b and a.."/"..b or b.."/"..a
			if a ~= b and not edges[edge] then
				edges[edge] = true
				vertices[a],vertices[b] = hits[1],hits[2]
				adjacency[a] = adjacency[a] or {}; adjacency[b] = adjacency[b] or {}
				table.insert(adjacency[a],b); table.insert(adjacency[b],a)
			end
		end
	end
	local start, count = nil,0
	for id,neighbors in adjacency do
		if #neighbors ~= 2 then return nil end
		start = start or id; count += 1
	end
	if count < 3 then return nil end
	local polygon, seen, previous, current = {}, {}, nil, start
	repeat
		if seen[current] then return nil end
		seen[current] = true; table.insert(polygon,vertices[current])
		local neighbors = adjacency[current]
		local nextId = neighbors[1] == previous and neighbors[2] or neighbors[1]
		previous,current = current,nextId
	until current == start
	if #polygon ~= count then return nil end -- multiple loops/holes
	return polygon
end

local function area(poly)
	local sum = 0
	for i,a in poly do local b=poly[i%#poly+1]; sum += a.X*b.Z-b.X*a.Z end
	return math.abs(sum)/2
end

local function bounds(poly, frame)
	local lo,hi = Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
	for _,p in poly do local q=frame:PointToObjectSpace(p); lo=lo:Min(q); hi=hi:Max(q) end
	return lo,hi
end

local function rectangle(poly)
	local best
	-- Contour edges are facade edges; mesh triangle diagonals never choose yaw.
	for i,p in poly do
		local d = poly[i%#poly+1]-p
		if d.Magnitude < 1 then continue end
		local frame = CFrame.new(poly[1])*CFrame.Angles(0,-math.atan2(d.Z,d.X),0)
		local lo,hi = bounds(poly,frame)
		local score = (hi.X-lo.X)*(hi.Z-lo.Z)
		if not best or score < best.area then best={cf=frame,lo=lo,hi=hi,area=score} end
	end
	return best
end

-- Imported facades sometimes have unwelded seams. A convex hull alone would
-- invent walls, so require measured segment coverage on ALL four box faces and
-- reject substantial internal edges (holes/recesses/disconnected structures).
local function facadeContour(g,y)
	local segments=sections(g,y)
	local pts={}
	for _,s in segments do table.insert(pts,s[1]); table.insert(pts,s[2]) end
	table.sort(pts,function(a,b) return a.X==b.X and a.Z<b.Z or a.X<b.X end)
	local function cross(a,b,c) return (b.X-a.X)*(c.Z-a.Z)-(b.Z-a.Z)*(c.X-a.X) end
	local lower,upper={},{}
	for _,p in pts do
		while #lower>=2 and cross(lower[#lower-1],lower[#lower],p)<=0 do table.remove(lower) end
		table.insert(lower,p)
	end
	for i=#pts,1,-1 do
		local p=pts[i]
		while #upper>=2 and cross(upper[#upper-1],upper[#upper],p)<=0 do table.remove(upper) end
		table.insert(upper,p)
	end
	if #lower<2 or #upper<2 then return nil end
	table.remove(lower); table.remove(upper)
	for _,p in upper do table.insert(lower,p) end
	local r=rectangle(lower)
	if not r or r.area<1 or area(lower)/r.area<0.97 then return nil end
	local w,d=r.hi.X-r.lo.X,r.hi.Z-r.lo.Z
	local tolerance=math.min(1,math.min(w,d)*0.02)
	local spans={{},{},{},{}}
	local interiorLength=0
	for _,s in segments do
		local a,b=r.cf:PointToObjectSpace(s[1]),r.cf:PointToObjectSpace(s[2])
		local found=false
		for index,side in {{"X",r.lo.X,"Z"},{"X",r.hi.X,"Z"},{"Z",r.lo.Z,"X"},{"Z",r.hi.Z,"X"}} do
			if math.abs(a[side[1]]-side[2])<=tolerance and math.abs(b[side[1]]-side[2])<=tolerance then
				table.insert(spans[index],{math.min(a[side[3]],b[side[3]]),math.max(a[side[3]],b[side[3]])})
				found=true; break
			end
		end
		if not found then interiorLength+=(a-b).Magnitude end
	end
	if interiorLength>2*(w+d)*0.07 then return nil end
	for i,list in spans do
		table.sort(list,function(a,b) return a[1]<b[1] end)
		local covered,last=0,-math.huge
		for _,span in list do covered+=math.max(0,span[2]-math.max(last,span[1])); last=math.max(last,span[2]) end
		if covered<(i<=2 and d or w)*0.97 then return nil end
	end
	return lower
end

-- Five independently closed slices must stay close to one rectangular prism.
-- Small facade recesses may be simplified; wedges, large setbacks and towers
-- with disconnected wings are not silently boxed over.
function Box.Classify(g)
	local h=g.max.Y-g.min.Y
	if h < 35 or #g.triangles < 8 then return nil,"small" end
	local samples = {}
	for _, fraction in {0.08,0.25,0.5,0.75,0.92} do
		local y=g.min.Y+h*fraction
		local p=contour(g,y) or facadeContour(g,y)
		if not p then return nil,"open or disconnected" end
		table.insert(samples,p)
	end
	local rect=rectangle(samples[3])
	if not rect or rect.area < 600 then return nil,"small footprint" end
	local width,depth=rect.hi.X-rect.lo.X,rect.hi.Z-rect.lo.Z
	if math.min(width,depth)<20 or math.max(width,depth)>500 then return nil,"size" end
	local tolerance=math.min(2,math.min(width,depth)*0.025)
	local confidence=1
	for _,poly in samples do
		local lo,hi=bounds(poly,rect.cf)
		local ratio=area(poly)/rect.area
		if ratio<0.93 or ratio>1.03 then return nil,"non rectangular" end
		if math.abs(lo.X-rect.lo.X)>tolerance or math.abs(hi.X-rect.hi.X)>tolerance
			or math.abs(lo.Z-rect.lo.Z)>tolerance or math.abs(hi.Z-rect.hi.Z)>tolerance then
			return nil,"changing footprint"
		end
		confidence=math.min(confidence,ratio)
	end
	local center=rect.cf:PointToWorldSpace((rect.lo+rect.hi)/2)
	local cf=CFrame.new(center.X,(g.min.Y+g.max.Y)/2,center.Z)*rect.cf.Rotation
	return {cf=cf,size=Vector3.new(width,h,depth),confidence=confidence,
		key=string.format("%d_%d_%d",math.round(center.X),math.round(g.min.Y),math.round(center.Z))}
end

local function corners(p)
	local points={}
	for _,v in {Vector3.new(-1,0,-1),Vector3.new(1,0,-1),Vector3.new(1,0,1),Vector3.new(-1,0,1)} do
		table.insert(points,p.cf:PointToWorldSpace(v*p.size/2))
	end
	return points
end

-- Clip one rotated rectangle against another, to reject duplicate/overlapping
-- candidate bodies. Axis-aligned bounding boxes are too loose in Shibuya.
local function overlap(a,b)
	local points={}
	for _,p in corners(a) do table.insert(points,b.cf:PointToObjectSpace(p)) end
	for _,side in {{"X",1,b.size.X/2},{"X",-1,b.size.X/2},{"Z",1,b.size.Z/2},{"Z",-1,b.size.Z/2}} do
		local output={}
		for i,p in points do
			local q=points[i%#points+1]
			local dp,dq=p[side[1]]*side[2]-side[3],q[side[1]]*side[2]-side[3]
			if dp<=0 then table.insert(output,p) end
			if (dp<=0) ~= (dq<=0) then table.insert(output,p:Lerp(q,dp/(dp-dq))) end
		end
		points=output
		if #points==0 then return 0 end
	end
	return area(points)
end

function Box.Preview(source, components)
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	components=components or require(script.Parent.ShibuyaGeometry).Scan(source)
	local plans,reasons={},{}
	local function reject(reason) reasons[reason]=(reasons[reason] or 0)+1 end
	local ground=RaycastParams.new()
	ground.FilterType=Enum.RaycastFilterType.Include
	local surfaces={workspace.Terrain}
	if workspace:FindFirstChild("Baseplate") then table.insert(surfaces,workspace.Baseplate) end
	ground.FilterDescendantsInstances=surfaces
	for i,g in components do
		local p,reason=Box.Classify(g)
		if p then
			local base=p.cf.Position-Vector3.new(0,p.size.Y/2,0)
			local hit=workspace:Raycast(base+Vector3.new(0,500,0),Vector3.new(0,-1500,0),ground)
			if not hit then reject("ground unverified")
			elseif base.Y-hit.Position.Y>math.min(125,p.size.Y) or base.Y-hit.Position.Y < -15 then reject("floating or buried")
			else
				local levelGround=true
				for _,corner in corners(p) do
					local probe=Vector3.new(corner.X,base.Y+500,corner.Z)
					local support=workspace:Raycast(probe,Vector3.new(0,-1500,0),ground)
					if not support or math.abs(support.Position.Y-hit.Position.Y)>4 then levelGround=false; break end
				end
				if not levelGround or p.size.Y+base.Y-hit.Position.Y<35 then reject("uneven ground"); continue end
				-- The imported terrain elevations differ from the current flat map.
				-- Extend a verified simple body down to terrain, preserving its roof.
				-- Do not accept a rooftop fragment requiring more than its own height.
				local delta=base.Y-hit.Position.Y
				p.sourceBaseY=base.Y; p.groundAdjustment=delta
				p.cf=p.cf*CFrame.new(0,-delta/2,0)
				p.size+=Vector3.new(0,delta,0)
				table.insert(plans,p)
			end
		else reject(reason) end
		if i%50==0 then task.wait() end
	end
	table.sort(plans,function(a,b)
		local aa,bb=a.size.X*a.size.Z,b.size.X*b.size.Z
		if aa==bb then return a.key<b.key end
		return aa>bb
	end)
	local preserved={}
	local buildings=workspace:FindFirstChild("Buildings")
	if buildings then
		for _,b in buildings:GetChildren() do
			if b:IsA("Model") and not b:GetAttribute("ShibuyaSourceKey") and not b:GetAttribute("ShibuyaBoxKey") then
				local cf,size=b:GetBoundingBox(); table.insert(preserved,{cf=cf,size=size})
			end
		end
	end
	local accepted,keys={},{}
	for _,p in plans do
		local blocked=keys[p.key] == true
		for _,group in {preserved,accepted} do
			for _,q in group do
				local intersection=overlap(p,q)
				if intersection>math.min(p.size.X*p.size.Z,q.size.X*q.size.Z)*0.05 then blocked=true; break end
			end
			if blocked then break end
		end
		if blocked then reject("overlap") else table.insert(accepted,p); keys[p.key]=true end
	end
	local report={plans=accepted,rejected=reasons,scanned=#components}
	print("BOX_PREVIEW",#accepted,"ready",game.HttpService:JSONEncode(reasons))
	return report
end

function Box.Build(report)
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	assert(#report.plans>0,"No approved box candidates; existing map unchanged")
	local generator=require(script.Parent.BuildingGenerator)
	local stage=Instance.new("Folder"); stage.Name="ShibuyaBoxStage_"..os.time()
	stage.Parent=game.ServerStorage
	local failed=0
	for i,p in report.plans do
		local b=Instance.new("Model"); b.Name="BuildingBox_"..p.key
		b:SetAttribute("ShibuyaBoxKey",p.key)
		b:SetAttribute("StructuralOnly",true)
		b:SetAttribute("BoxConfidence",p.confidence)
		b:SetAttribute("SourceBaseY",p.sourceBaseY)
		b:SetAttribute("GroundAdjustment",p.groundAdjustment)
		b:SetAttribute("FloorCountBasis","Height estimate; simplified rectangular massing")
		b.Parent=stage
		local ok,result=pcall(generator.GenerateBox,b,p.cf,p.size)
		if not ok or not result then
			failed+=1; b:SetAttribute("GenerationError",tostring(result))
		end
		if i%10==0 then task.wait() end
	end
	stage:SetAttribute("Failed",failed)
	stage:SetAttribute("Expected",#report.plans)
	stage:SetAttribute("BoxStageVersion",1)
	print("BOX_STAGED",stage.Name,#report.plans,failed)
	return stage
end

function Box.Apply(stage)
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	assert(stage.Parent==game.ServerStorage and stage:GetAttribute("BoxStageVersion")==1,"Invalid stage")
	assert(stage:GetAttribute("Failed")==0 and #stage:GetChildren()==stage:GetAttribute("Expected")
		and #stage:GetChildren()>0,"Stage incomplete; existing map unchanged")
	for _,b in stage:GetChildren() do
		assert(b:GetAttribute("ShibuyaBoxKey") and b:FindFirstChild("Interior"),"Incomplete building")
	end
	local buildings=workspace:FindFirstChild("Buildings")
	assert(buildings,"Workspace.Buildings is missing")
	game:GetService("ChangeHistoryService"):SetWaypoint("Before clean Shibuya box pass")
	local archive=Instance.new("Folder"); archive.Name="ShibuyaPreviousGeneration_"..os.time(); archive.Parent=game.ServerStorage
	for _,b in buildings:GetChildren() do
		if b:GetAttribute("ShibuyaSourceKey") or b:GetAttribute("ShibuyaBoxKey") then b.Parent=archive end
	end
	for _,b in stage:GetChildren() do b.Parent=buildings end
	stage:SetAttribute("Applied",true)
	game:GetService("ChangeHistoryService"):SetWaypoint("Clean Shibuya box pass")
	print("BOX_APPLIED",stage:GetAttribute("Expected"),"previous generation archived at",archive:GetFullName())
	return archive
end

return Box
