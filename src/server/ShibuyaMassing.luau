--!nonstrict
-- Edit-time, read-only massing reconstruction. No occupancy grid is used for
-- visible edges. A mesh component is evidence for a building, not a guarantee
-- that it is one: ambiguous courtyards, offset bodies and open facades are
-- reported instead of silently filling their convex hull.
local Massing = {}
local DEFAULTS = {
	MinHeight = 30,
	MinArea = 150,
	MinWidth = 10,
	-- Live source diagnostics found repeated facade seams of 0.38-2.40 studs,
	-- including perpendicular corner gaps and sub-stud triangle-edge slivers.
	WeldTolerance = 0.6,
	MaxSeamGap = 3,
	MaxCornerGap = 3,
	MaxCornerExtension = 3,
	SimplifyTolerance = 1.2,
	MaxVertices = 64,
	MinSupportSamples = 3,
	MinSupportSpan = 0.30,
	MaxTiers = 4,
	RoofFallback = true,
}
local FRACTIONS = {0.035, 0.10, 0.18, 0.28, 0.40, 0.52, 0.64, 0.76, 0.86, 0.93, 0.98}

local function optionsWithDefaults(options)
	local result = table.clone(DEFAULTS)
	for k, v in options or {} do result[k] = v end
	return result
end

local function cross(a, b, c)
	return (b.X-a.X)*(c.Y-a.Y)-(b.Y-a.Y)*(c.X-a.X)
end

local function signedArea(points)
	local sum = 0
	for i, a in points do local b = points[i % #points + 1]; sum += a.X*b.Y-b.X*a.Y end
	return sum/2
end

local function area(points) return math.abs(signedArea(points)) end

local function distanceToSegment(p, a, b)
	local d = b-a
	local length2 = d:Dot(d)
	if length2 < 1e-12 then return (p-a).Magnitude end
	return (p-(a+d*math.clamp((p-a):Dot(d)/length2, 0, 1))).Magnitude
end

local function onBoundary(p, polygon, tolerance)
	for i, a in polygon do
		if distanceToSegment(p, a, polygon[i % #polygon + 1]) <= tolerance then return true end
	end
	return false
end

local function inside(p, polygon, tolerance)
	if tolerance and onBoundary(p, polygon, tolerance) then return true end
	local contained = false
	for i, a in polygon do
		local b = polygon[i % #polygon + 1]
		if (a.Y > p.Y) ~= (b.Y > p.Y) and p.X < (b.X-a.X)*(p.Y-a.Y)/(b.Y-a.Y)+a.X then
			contained = not contained
		end
	end
	return contained
end

local function intersects(a, b, c, d)
	local abC, abD, cdA, cdB = cross(a,b,c), cross(a,b,d), cross(c,d,a), cross(c,d,b)
	if abC*abD < -1e-8 and cdA*cdB < -1e-8 then return true end
	return (math.abs(abC)<1e-6 and distanceToSegment(c,a,b)<1e-6)
		or (math.abs(abD)<1e-6 and distanceToSegment(d,a,b)<1e-6)
		or (math.abs(cdA)<1e-6 and distanceToSegment(a,c,d)<1e-6)
		or (math.abs(cdB)<1e-6 and distanceToSegment(b,c,d)<1e-6)
end

local function simple(points)
	if #points < 3 or area(points) < 1e-4 then return false end
	for i, a in points do
		local b = points[i % #points + 1]
		if (a-b).Magnitude < 1e-4 then return false end
		for j = i+1, #points do
			if j == i+1 or (i == 1 and j == #points) then continue end
			if intersects(a,b,points[j],points[j % #points+1]) then return false end
		end
	end
	return true
end

local function sections(g, y)
	local segments = {}
	for _, t in g.triangles do
		local hits = {}
		for i = 1, 3 do
			local a, b = t[i], t[i % 3 + 1]
			if (a.Y <= y and b.Y > y) or (b.Y <= y and a.Y > y) then
				local p = a:Lerp(b, (y-a.Y)/(b.Y-a.Y))
				table.insert(hits, Vector2.new(p.X,p.Z))
			end
		end
		if #hits == 2 and (hits[1]-hits[2]).Magnitude > 1e-5 then table.insert(segments,hits) end
	end
	return segments
end

-- Radius welding searches adjacent hash cells; rounding alone fails when two
-- almost coincident seam vertices lie on opposite sides of a cell boundary.
local function loopsFromSegments(segments, weld, seam, trace, cornerGap, cornerExtension, allowRoofHoles, returnAll)
	local vertices, neighbors, cells, edges = {}, {}, {}, {}
	local stats={segments=#segments,graphVertices=0,branchVertices=0,openEndpoints=0,remainingEndpoints=0,repairedSeams=0,cornerRepairs=0,loops=0}
	local function intern(p)
		local x, z = math.floor(p.X/weld), math.floor(p.Y/weld)
		for dx = -1, 1 do for dz = -1, 1 do
			for _, id in cells[(x+dx)..":"..(z+dz)] or {} do
				if (vertices[id]-p).Magnitude <= weld then return id end
			end
		end end
		local id = #vertices+1
		vertices[id], neighbors[id] = p, {}
		local key = x..":"..z; cells[key] = cells[key] or {}; table.insert(cells[key],id)
		return id
	end
	local function connect(a,b)
		local key = math.min(a,b)..":"..math.max(a,b)
		if a ~= b and not edges[key] then
			edges[key] = true; table.insert(neighbors[a],b); table.insert(neighbors[b],a)
		end
	end
	for _, s in segments do connect(intern(s[1]),intern(s[2])) end
	stats.graphVertices=#vertices
	if #vertices < 3 then return nil, "no cross-section",nil,stats end
	local endpoints = {}
	for i, n in neighbors do
		if #n > 2 then stats.branchVertices+=1 end
		if #n == 1 then table.insert(endpoints,i) end
	end
	stats.openEndpoints=#endpoints; stats.remainingEndpoints=#endpoints
	if trace then
		stats.endpoints={}
		local function crossVector(a,b) return a.X*b.Y-a.Y*b.X end
		for _,a in endpoints do
			local pa=vertices[a]; local tangent=(pa-vertices[neighbors[a][1]]).Unit
			local row={id=a,position={x=pa.X,z=pa.Y},tangent={x=tangent.X,z=tangent.Y},
				incidentLength=(pa-vertices[neighbors[a][1]]).Magnitude}
			local nearest,bestDistance=nil,math.huge
			for _,b in endpoints do
				if a==b then continue end
				local delta=vertices[b]-pa; local distance=delta.Magnitude
				if distance<bestDistance and distance>1e-6 then
					bestDistance=distance; nearest=b
				end
			end
			if nearest then
				local pb=vertices[nearest]; local otherTangent=(pb-vertices[neighbors[nearest][1]]).Unit
				local delta=pb-pa; local determinant=crossVector(tangent,otherTangent)
				row.nearestId=nearest; row.nearestDistance=bestDistance
				row.towardNearest=tangent:Dot(delta.Unit); row.otherTowardThis=otherTangent:Dot(-delta.Unit)
				if math.abs(determinant)>1e-4 then
					local ta=crossVector(delta,otherTangent)/determinant
					local tb=crossVector(delta,tangent)/determinant
					local intersection=pa+tangent*ta
					row.intersection={x=intersection.X,z=intersection.Y,extensionA=ta,extensionB=tb}
				end
			end
			table.insert(stats.endpoints,row)
		end
	end
	if stats.branchVertices>0 and not returnAll then return nil,"branched cross-section",nil,stats end
	local repaired = 0
	-- Only bridge mutual-nearest, short, almost straight endpoint gaps. This
	-- cannot close a missing facade or connect unrelated building wings.
	local nearest = {}
	for _, a in endpoints do
		local best, distance = nil, seam
		for _, b in endpoints do
			if a == b or neighbors[a][1] == b then continue end
			local delta = vertices[b]-vertices[a]
			local length = delta.Magnitude
			if length > 1e-6 and length <= distance then
				local direction = delta/length
				local outgoingA = (vertices[a]-vertices[neighbors[a][1]]).Unit
				local outgoingB = (vertices[b]-vertices[neighbors[b][1]]).Unit
				local lateralA=math.abs(outgoingA.X*delta.Y-outgoingA.Y*delta.X)
				local lateralB=math.abs(outgoingB.X*delta.Y-outgoingB.Y*delta.X)
				if outgoingA:Dot(outgoingB)<-0.98 and outgoingA:Dot(direction)>0.70
					and outgoingB:Dot(-direction)>0.70 and math.max(lateralA,lateralB)<=weld then
					best, distance = b, length
				end
			end
		end
		nearest[a] = best
	end
	for _, a in endpoints do
		local b = nearest[a]
		if b and nearest[b] == a and #neighbors[a] == 1 and #neighbors[b] == 1 then
			connect(a,b); repaired += 1
		end
	end
	-- Missing tiny corner triangles can leave two facade ends aimed at their
	-- original corner. Intersect those measured tangents, with strict absolute
	-- and relative extension limits; never draw a long arbitrary closing edge.
	if (cornerGap or 0)>0 and (cornerExtension or 0)>0 then
		local function crossVector(a,b) return a.X*b.Y-a.Y*b.X end
		local function continuationLength(endpoint,tangent)
			local previous,current=endpoint,neighbors[endpoint][1]
			local origin=vertices[endpoint]; local direction=-tangent
			local length=(vertices[current]-origin):Dot(direction)
			local seen={[endpoint]=true}
			while #neighbors[current]==2 and not seen[current] do
				seen[current]=true
				local nextId=neighbors[current][1]==previous and neighbors[current][2] or neighbors[current][1]
				local delta=vertices[nextId]-origin
				local along=delta:Dot(direction)
				local lateral=math.abs(crossVector(direction,delta))
				if lateral>weld or along<length-weld then break end
				length=math.max(length,along); previous,current=current,nextId
			end
			return length
		end
		local nearestCorner,corners={},{}
		for _,a in endpoints do
			if #neighbors[a]~=1 then continue end
			local closest,distance=nil,cornerGap
			for _,b in endpoints do
				if a==b or #neighbors[b]~=1 or neighbors[a][1]==b then continue end
				local gap=(vertices[b]-vertices[a]).Magnitude
				if gap<distance then closest,distance=b,gap end
			end
			if not closest then continue end
			local b=closest; local pa,pb=vertices[a],vertices[b]
			local ta=(pa-vertices[neighbors[a][1]]).Unit
			local tb=(pb-vertices[neighbors[b][1]]).Unit
			local determinant=crossVector(ta,tb)
			if math.abs(determinant)<0.25 then continue end
			local delta=pb-pa
			local extensionA=crossVector(delta,tb)/determinant
			local extensionB=crossVector(delta,ta)/determinant
			if extensionA < -weld*0.25 or extensionB < -weld*0.25
				or extensionA>cornerExtension or extensionB>cornerExtension then continue end
			if extensionA>math.max(math.min(3,cornerExtension),continuationLength(a,ta)*0.15)
				or extensionB>math.max(math.min(3,cornerExtension),continuationLength(b,tb)*0.15) then continue end
			nearestCorner[a]=b; corners[a]=pa+ta*extensionA
		end
		for _,a in endpoints do
			local b=nearestCorner[a]
			if not b or nearestCorner[b]~=a or #neighbors[a]~=1 or #neighbors[b]~=1 then continue end
			local point=(corners[a]+corners[b])/2
			local blocked=false
			for u,adjacent in neighbors do
				for _,v in adjacent do
					if u>=v then continue end
					for _,edge in {{vertices[a],point},{point,vertices[b]}} do
						if cross(edge[1],edge[2],vertices[u])*cross(edge[1],edge[2],vertices[v]) < -1e-8
							and cross(vertices[u],vertices[v],edge[1])*cross(vertices[u],vertices[v],edge[2]) < -1e-8 then
							blocked=true; break
						end
					end
					if blocked then break end
				end
				if blocked then break end
			end
			if not blocked then
				local corner=intern(point); connect(a,corner); connect(corner,b)
				stats.cornerRepairs+=1; repaired+=1
			end
		end
	end
	stats.repairedSeams=repaired; stats.remainingEndpoints=#endpoints-repaired*2
	if returnAll then
		local loops, seen, invalidComponents = {}, {}, 0
		for start in vertices do
			if seen[start] or #neighbors[start] == 0 then continue end
			local component, queue, head, valid = {}, {start}, 1, true
			seen[start] = true
			while head <= #queue do
				local id = queue[head]
				head += 1
				table.insert(component, id)
				if #neighbors[id] ~= 2 then valid = false end
				for _, nextId in neighbors[id] do
					if not seen[nextId] then seen[nextId] = true; table.insert(queue, nextId) end
				end
			end
			if not valid then invalidComponents += 1; continue end
			local points, previous, current, localSeen = {}, nil, start, {}
			repeat
				if localSeen[current] then valid = false; break end
				localSeen[current] = true
				table.insert(points, vertices[current])
				local adjacent = neighbors[current]
				local nextId = adjacent[1] == previous and adjacent[2] or adjacent[1]
				previous, current = current, nextId
			until current == start
			if valid and #points >= 3 and area(points) > 0.1 then table.insert(loops, points)
			else invalidComponents += 1 end
		end
		stats.invalidComponents = invalidComponents
		stats.loops = #loops
		if #loops == 0 then return nil, "no independently enclosed cross-section", nil, stats end
		table.sort(loops, function(a, b) return area(a) > area(b) end)
		return loops, nil, repaired, stats
	end
	for _, n in neighbors do if #n ~= 0 and #n ~= 2 then return nil, "open cross-section",nil,stats end end
	local loops, seen = {}, {}
	for start in vertices do
		if seen[start] or #neighbors[start] == 0 then continue end
		local points, previous, current = {}, nil, start
		repeat
			if seen[current] then return nil, "self-touching cross-section",nil,stats end
			seen[current] = true; table.insert(points,vertices[current])
			local n = neighbors[current]
			local nextId = n[1] == previous and n[2] or n[1]
			previous, current = current, nextId
		until current == start
		if #points >= 3 and area(points)>0.1 then table.insert(loops,points) end
	end
	stats.loops=#loops
	if #loops == 0 then return nil, "no enclosed cross-section",nil,stats end
	table.sort(loops,function(a,b) return area(a)>area(b) end)
	local main, mainArea = loops[1], area(loops[1])
	stats.holeArea=0; stats.holes=0
	for i = 2, #loops do
		local loop = loops[i]
		if inside(loop[1],main,0.01) then
			stats.holeArea+=area(loop); stats.holes+=1
			if not allowRoofHoles then return nil, "courtyard or internal loop",nil,stats end
			if area(loop)>mainArea*0.025 then return nil,"large roof opening",nil,stats end
		elseif area(loop) > math.min(50,mainArea*0.015) then return nil, "multiple substantial bodies",nil,stats end
	end
	if stats.holeArea>mainArea*0.04 then return nil,"many roof openings",nil,stats end
	return main, nil, repaired,stats
end

-- RDP is applied to two chains of a closed ring, retaining the original
-- contour's recesses when their depth exceeds tolerance. Every result is
-- checked for self intersections and excessive area change.
local function simplify(points,tolerance)
	local first = 1
	for i,p in points do if p.X < points[first].X then first=i end end
	local opposite, farthest = first, 0
	for i,p in points do
		local distance = (p-points[first]).Magnitude
		if distance > farthest then opposite,farthest=i,distance end
	end
	local function chain(a,b)
		local result, i = {}, a
		repeat table.insert(result,points[i]); i=i % #points+1 until i==b
		table.insert(result,points[b]); return result
	end
	local function rdp(list)
		local keep = {[1]=true,[#list]=true}
		local pending = {{1,#list}}
		while #pending>0 do
			local range = table.remove(pending)
			local a,b = range[1],range[2]
			local furthest, distance = nil,tolerance
			for i=a+1,b-1 do
				local d=distanceToSegment(list[i],list[a],list[b])
				if d>distance then distance,furthest=d,i end
			end
			if furthest then
				keep[furthest]=true
				table.insert(pending,{a,furthest}); table.insert(pending,{furthest,b})
			end
		end
		local result={}; for i,p in list do if keep[i] then table.insert(result,p) end end
		return result
	end
	local a,b=rdp(chain(first,opposite)),rdp(chain(opposite,first))
	table.remove(a); table.remove(b)
	for _,p in b do table.insert(a,p) end
	if not simple(a) or math.abs(area(a)/area(points)-1)>0.035 then
		if tolerance>0.05 then return simplify(points,tolerance/2) end
		return nil
	end
	if signedArea(a)<0 then
		local reversed={}; for i=#a,1,-1 do table.insert(reversed,a[i]) end; a=reversed
	end
	return a
end

local function rectangle(points)
	local best
	for i,a in points do
		local delta=points[i % #points+1]-a
		if delta.Magnitude<0.1 then continue end
		local u=delta.Unit; local v=Vector2.new(-u.Y,u.X)
		local lo,hi=Vector2.new(math.huge,math.huge),Vector2.new(-math.huge,-math.huge)
		for _,p in points do
			local localP=Vector2.new(p:Dot(u),p:Dot(v))
			lo=lo:Min(localP); hi=hi:Max(localP)
		end
		local size=hi-lo; local score=size.X*size.Y
		if not best or score<best.area then best={u=u,v=v,lo=lo,hi=hi,area=score,size=size} end
	end
	return best
end

local function rectanglePoints(r)
	return {r.u*r.lo.X+r.v*r.lo.Y,r.u*r.hi.X+r.v*r.lo.Y,
		r.u*r.hi.X+r.v*r.hi.Y,r.u*r.lo.X+r.v*r.hi.Y}
end

-- Optional repair of near-box seams still requires actual facade coverage on
-- each of four faces. A convex hull by itself is never used as a footprint.
local function supportedRectangle(segments,tolerance)
	local points={}
	for _,s in segments do table.insert(points,s[1]); table.insert(points,s[2]) end
	if #points<4 then return nil end
	-- Orient only from substantial measured facade segments, not arbitrary
	-- jumps between sorted mesh points.
	local candidates,orientations={},{}
	for _,s in segments do
		if (s[2]-s[1]).Magnitude>1 then
			local delta=s[2]-s[1]
			local angle=math.atan2(delta.Y,delta.X) % (math.pi/2)
			local key=math.round(angle*720/math.pi)
			local entry=orientations[key] or {u=delta.Unit,length=0}
			entry.length+=delta.Magnitude; orientations[key]=entry
		end
	end
	local ranked={}; for _,orientation in orientations do table.insert(ranked,orientation) end
	table.sort(ranked,function(a,b) return a.length>b.length end)
	for index=1,math.min(12,#ranked) do
		local u=ranked[index].u; local v=Vector2.new(-u.Y,u.X)
		local lo,hi=Vector2.new(math.huge,math.huge),Vector2.new(-math.huge,-math.huge)
		for _,p in points do local q=Vector2.new(p:Dot(u),p:Dot(v)); lo=lo:Min(q); hi=hi:Max(q) end
		local size=hi-lo
		table.insert(candidates,{u=u,v=v,lo=lo,hi=hi,size=size,area=size.X*size.Y})
	end
	table.sort(candidates,function(a,b) return a.area<b.area end)
	local r=candidates[1]
	if not r or math.min(r.size.X,r.size.Y)<1 then return nil end
	local spans={{},{},{},{}}; local internal=0
	local allowed=math.min(tolerance, math.min(r.size.X,r.size.Y)*0.025)
	for _,s in segments do
		local a=Vector2.new(s[1]:Dot(r.u),s[1]:Dot(r.v))
		local b=Vector2.new(s[2]:Dot(r.u),s[2]:Dot(r.v))
		local side
		if math.abs(a.X-r.lo.X)<=allowed and math.abs(b.X-r.lo.X)<=allowed then side=1
		elseif math.abs(a.X-r.hi.X)<=allowed and math.abs(b.X-r.hi.X)<=allowed then side=2
		elseif math.abs(a.Y-r.lo.Y)<=allowed and math.abs(b.Y-r.lo.Y)<=allowed then side=3
		elseif math.abs(a.Y-r.hi.Y)<=allowed and math.abs(b.Y-r.hi.Y)<=allowed then side=4 end
		if side then
			local va,vb = side<=2 and a.Y or a.X, side<=2 and b.Y or b.X
			table.insert(spans[side],{math.min(va,vb),math.max(va,vb)})
		else internal+=(a-b).Magnitude end
	end
	if internal>2*(r.size.X+r.size.Y)*0.045 then return nil end
	for i,list in spans do
		table.sort(list,function(a,b) return a[1]<b[1] end)
		local covered,last=0,-math.huge
		for _,s in list do covered+=math.max(0,s[2]-math.max(last,s[1])); last=math.max(last,s[2]) end
		if covered<(i<=2 and r.size.Y or r.size.X)*0.97 then return nil end
	end
	return rectanglePoints(r)
end

local function sample(g,y,options)
	local segments=sections(g,y)
	local points,reason,repaired,diagnostics=loopsFromSegments(segments,options.WeldTolerance,options.MaxSeamGap,
		options.TraceTopology,options.MaxCornerGap,options.MaxCornerExtension)
	if options.IncludeSegments then
		diagnostics.sliceSegments={}
		for _,s in segments do table.insert(diagnostics.sliceSegments,{{x=s[1].X,z=s[1].Y},{x=s[2].X,z=s[2].Y}}) end
	end
	diagnostics.loopFailure=reason
	local fallback=false
	if not points and (reason=="open cross-section" or reason=="branched cross-section") then
		points=supportedRectangle(segments,options.SimplifyTolerance)
		fallback=points~=nil
	end
	diagnostics.rectangleFallback=fallback
	if not points then return nil,reason,diagnostics end
	local rawArea=area(points)
	diagnostics.rawArea=rawArea; diagnostics.rawCorners=#points
	points=simplify(points,options.SimplifyTolerance)
	if not points then return nil,"invalid simplified boundary",diagnostics end
	diagnostics.simplifiedArea=area(points); diagnostics.simplifiedCorners=#points
	if #points>options.MaxVertices then return nil,"boundary remains too complex",diagnostics end
	if area(points)<options.MinArea then return nil,"small footprint",diagnostics end
	local rect=rectangle(points)
	if not rect or math.min(rect.size.X,rect.size.Y)<options.MinWidth then return nil,"narrow fragment",diagnostics end
	diagnostics.width=math.min(rect.size.X,rect.size.Y); diagnostics.rectangleAreaRatio=area(points)/rect.area
	-- Near rectangles become an exact rotated box only when all four sides are
	-- supported and the area change is under 2%; substantial notches survive.
	if area(points)/rect.area>=0.98 then
		local exact=supportedRectangle(segments,options.SimplifyTolerance)
		if exact then points=exact end
	end
	return {points=points,area=area(points),y=y,rawArea=rawArea,
		repaired=repaired or 0,fallback=fallback,width=math.min(rect.size.X,rect.size.Y)},nil,diagnostics
end

-- Global reconstruction helpers intentionally return every independently
-- enclosed loop while ignoring unrelated open/branched graph components.
-- Existing single-component Analyze behavior remains unchanged.
function Massing.SectionsAt(components,y)
	local result={}
	for _,g in components do
		if y<=g.min.Y or y>=g.max.Y then continue end
		for _,segment in sections(g,y) do table.insert(result,segment) end
	end
	return result
end

function Massing.ExtractSectionLoops(segments,options)
	options=optionsWithDefaults(options)
	local raw,reason,repaired,stats=loopsFromSegments(segments,options.WeldTolerance,options.MaxSeamGap,
		options.TraceTopology,options.MaxCornerGap,options.MaxCornerExtension,false,true)
	if not raw then return nil,reason,stats end
	local rows={}
	for _,ring in raw do
		local rawArea=area(ring)
		local points=simplify(ring,options.SimplifyTolerance)
		local rect=points and rectangle(points) or nil
		if points and #points<=options.MaxVertices and area(points)>=options.MinArea
			and rect and math.min(rect.size.X,rect.size.Y)>=options.MinWidth then
			local centroid=Vector2.zero
			for _,point in points do centroid+=point end
			centroid/=#points
			table.insert(rows,{points=points,area=area(points),rawArea=rawArea,centroid=centroid,
				width=math.min(rect.size.X,rect.size.Y),repaired=repaired or 0,hole=false,nestingDepth=0})
		end
	end
	table.sort(rows,function(a,b) return a.area>b.area end)
	for index,row in rows do
		local depth=0
		for outerIndex=1,index-1 do
			if inside(row.points[1],rows[outerIndex].points,0.01) then depth+=1 end
		end
		row.nestingDepth=depth; row.hole=depth%2==1
	end
	stats.acceptedLoops=#rows
	if #rows==0 then return nil,"no usable independently enclosed loop",stats end
	return rows,nil,stats
end

local function shapeDistance(a,b)
	local maximum=0
	for _,pair in {{a,b},{b,a}} do
		for i,p in pair[1] do
			for _,q in {p,(p+pair[1][i % #pair[1]+1])/2} do
				local nearest=math.huge
				for j,v in pair[2] do nearest=math.min(nearest,distanceToSegment(q,v,pair[2][j % #pair[2]+1])) end
				maximum=math.max(maximum,nearest)
			end
		end
	end
	return maximum
end

local function similar(a,b)
	if math.min(a.area,b.area)/math.max(a.area,b.area)<0.92 then return false end
	return shapeDistance(a.points,b.points)<=math.max(1.5,math.min(a.width,b.width)*0.035)
end

Massing.ShapeDistance=shapeDistance
Massing.SimilarFootprints=similar

local function contains(outer,inner,tolerance)
	for i,p in inner do
		local nextP=inner[i % #inner+1]
		for j,a in outer do
			local b=outer[j % #outer+1]
			-- Vertex/midpoint probes alone can miss a narrow recess crossed by a
			-- long upper edge. Any proper boundary crossing means an overhang.
			if cross(p,nextP,a)*cross(p,nextP,b)<-1e-8 and cross(a,b,p)*cross(a,b,nextP)<-1e-8 then
				return false
			end
		end
		for _,fraction in {0,0.25,0.5,0.75} do
			if not inside(p:Lerp(nextP,fraction),outer,tolerance) then return false end
		end
	end
	return true
end

Massing.Contains=contains

local function roofPlanes(g)
	local bands={}
	for _,t in g.triangles do
		local normal=(t[2]-t[1]):Cross(t[3]-t[1]); local magnitude=normal.Magnitude
		if magnitude>0.1 and math.abs(normal.Y)/magnitude>0.995
			and math.max(t[1].Y,t[2].Y,t[3].Y)-math.min(t[1].Y,t[2].Y,t[3].Y)<0.5 then
			local y=(t[1].Y+t[2].Y+t[3].Y)/3; local key=math.round(y*4)
			local band=bands[key] or {y=y,area=0}; band.area+=math.abs(normal.Y)/2; bands[key]=band
		end
	end
	local planes={}; for _,p in bands do table.insert(planes,p) end
	table.sort(planes,function(a,b) return a.y<b.y end)
	return planes
end

function Massing.SourceKey(g)
	local p=(g.min+g.max)/2
	return string.format("%d_%d_%d_%d",g.meshIndex,math.round(p.X*10),math.round(p.Y*10),math.round(p.Z*10))
end

local function geometricKey(key)
	if type(key)~="string" then return nil end
	return key:match("^%d+_(%-?%d+_%-?%d+_%-?%d+)$")
end

Massing.GeometricKey=geometricKey

-- Reimporting/reordering the 16 source MeshParts changes their descendant
-- indices. The XYZ suffix can still identify the exact same component, but
-- only when it is unique on BOTH sides and its complete geometric envelope
-- agrees with the old source envelope. No nearest-neighbor matching is used.
local function matchesStoredEnvelope(g,old)
	local cf,size=old:GetAttribute("InteriorBBoxCFrame"),old:GetAttribute("InteriorBBoxSize")
	if typeof(cf)~="CFrame" or typeof(size)~="Vector3" then return false end
	local lo,hi=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
	for _,triangle in g.triangles do
		for _,p in triangle do local q=cf:PointToObjectSpace(p); lo=lo:Min(q); hi=hi:Max(q) end
	end
	local lowError,highError=lo+size/2,hi-size/2
	return math.max(math.abs(lowError.X),math.abs(lowError.Y),math.abs(lowError.Z),
		math.abs(highError.X),math.abs(highError.Y),math.abs(highError.Z))<=0.35
end

local ROOF_FACADE_FRACTIONS={0.08,0.22,0.38,0.55,0.72,0.88}

local function broadRoofBands(g)
	local faces={}
	for _,t in g.triangles do
		local normal=(t[2]-t[1]):Cross(t[3]-t[1]); local magnitude=normal.Magnitude
		if magnitude>0.1 and math.abs(normal.Y)/magnitude>=0.99
			and math.max(t[1].Y,t[2].Y,t[3].Y)-math.min(t[1].Y,t[2].Y,t[3].Y)<=0.7 then
			table.insert(faces,{triangle=t,y=(t[1].Y+t[2].Y+t[3].Y)/3,area=math.abs(normal.Y)/2})
		end
	end
	table.sort(faces,function(a,b) return a.y<b.y end)
	local bands={}
	for _,face in faces do
		local band=bands[#bands]
		if not band or face.y-band.lowY>0.6 then
			band={lowY=face.y,ySum=0,area=0,faces={}}; table.insert(bands,band)
		end
		band.ySum+=face.y*face.area; band.area+=face.area; table.insert(band.faces,face)
	end
	for _,band in bands do band.y=band.ySum/band.area end
	return bands
end

-- The roof perimeter is the actual boundary of a planar triangle patch:
-- shared triangle edges cancel, unique exterior edges remain. This does not
-- compute a convex hull or connect distant roof pieces.
local function roofBoundary(band,options)
	local vertices,cells,faces,edges,rawEdges={},{},{},{},{}
	local weld=options.WeldTolerance
	local function intern(p)
		local x,z=math.floor(p.X/weld),math.floor(p.Y/weld)
		for dx=-1,1 do for dz=-1,1 do
			for _,id in cells[(x+dx)..":"..(z+dz)] or {} do
				if (vertices[id]-p).Magnitude<=weld then return id end
			end
		end end
		local id=#vertices+1; vertices[id]=p
		local key=x..":"..z; cells[key]=cells[key] or {}; table.insert(cells[key],id)
		return id
	end
	local totalArea=0
	for _,face in band.faces do
		local ids={}
		for _,p in face.triangle do table.insert(ids,intern(Vector2.new(p.X,p.Z))) end
		if ids[1]==ids[2] or ids[1]==ids[3] or ids[2]==ids[3] then continue end
		local sorted=table.clone(ids); table.sort(sorted)
		local faceKey=table.concat(sorted,":")
		if faces[faceKey] then continue end
		faces[faceKey]=true; totalArea+=face.area
		for i,a in ids do
			table.insert(rawEdges,{a=a,b=ids[i % 3+1]})
		end
	end
	if #vertices>1600 then return nil,"planar roof triangulation too complex" end
	-- Imported roof patches can meet at T junctions. Split an edge at an
	-- existing collinear vertex before canceling shared edges, so a long edge
	-- cancels two shorter neighbors without leaving fictitious internal seams.
	local splitTolerance=math.min(0.06,weld*0.1)
	for _,raw in rawEdges do
		local a,b=vertices[raw.a],vertices[raw.b]; local delta=b-a; local length2=delta:Dot(delta)
		local cuts={{t=0,id=raw.a},{t=1,id=raw.b}}
		local minX,maxX=math.min(a.X,b.X)-splitTolerance,math.max(a.X,b.X)+splitTolerance
		local minZ,maxZ=math.min(a.Y,b.Y)-splitTolerance,math.max(a.Y,b.Y)+splitTolerance
		for id,p in vertices do
			if id==raw.a or id==raw.b or p.X<minX or p.X>maxX or p.Y<minZ or p.Y>maxZ then continue end
			local t=(p-a):Dot(delta)/length2
			if t>1e-5 and t<1-1e-5 and (p-(a+delta*t)).Magnitude<=splitTolerance then
				table.insert(cuts,{t=t,id=id})
			end
		end
		table.sort(cuts,function(x,y) return x.t<y.t end)
		for index=1,#cuts-1 do
			local u,v=cuts[index].id,cuts[index+1].id
			if u==v then continue end
			local key=math.min(u,v)..":"..math.max(u,v)
			local edge=edges[key] or {a=u,b=v,count=0}; edge.count+=1; edges[key]=edge
		end
	end
	local boundary={}
	for _,edge in edges do
		if edge.count>2 then return nil,"non-manifold planar roof" end
		if edge.count==1 then table.insert(boundary,{vertices[edge.a],vertices[edge.b]}) end
	end
	local polygon,reason,repaired,stats=loopsFromSegments(boundary,options.WeldTolerance,options.MaxSeamGap,
		options.TraceTopology,options.MaxCornerGap,options.MaxCornerExtension,true)
	if not polygon then return nil,"roof "..tostring(reason),stats end
	polygon=simplify(polygon,options.SimplifyTolerance)
	if not polygon or #polygon>options.MaxVertices then return nil,"invalid or excessive roof boundary",stats end
	local roofArea=area(polygon); local rect=rectangle(polygon)
	if roofArea<options.MinArea or not rect or math.min(rect.size.X,rect.size.Y)<options.MinWidth then
		return nil,"roof too small or narrow",stats
	end
	local coverage=totalArea/roofArea
	-- A parapet ring, a roof with a large unmodeled hole, or overlapping patches
	-- cannot stand in for a complete floor plate.
	if coverage<0.92 or coverage>1.06 then return nil,"roof surface does not cover its boundary",stats end
	return {points=polygon,area=roofArea,width=math.min(rect.size.X,rect.size.Y),rect=rect,
		coverage=coverage,measuredArea=totalArea,repairs=repaired or 0,holes=stats.holes or 0,holeArea=stats.holeArea or 0}
end

local function coveredLength(spans)
	table.sort(spans,function(a,b) return a[1]<b[1] end)
	local covered,last=0,-math.huge
	for _,span in spans do
		covered+=math.max(0,span[2]-math.max(last,span[1])); last=math.max(last,span[2])
	end
	return covered
end

local function verifyRoofFacades(g,roof,roofY,options)
	local points=roof.points
	local edges,perimeter={},0
	for i,a in points do
		local delta=points[i % #points+1]-a; local length=delta.Magnitude
		table.insert(edges,{a=a,b=points[i % #points+1],direction=delta/length,length=length})
		perimeter+=length
	end
	local tolerance=math.clamp(roof.width*0.015,1.2,3)
	local allSpans={}; for i=1,#edges do allSpans[i]={} end
	local result={samples={},validSamples=0,firstFraction=1,lastFraction=0,meanSupport=0,
		perimeter=perimeter,tolerance=tolerance,unsupportedEdges=0,unsupportedLength=0}
	for _,fraction in ROOF_FACADE_FRACTIONS do
		local y=g.min.Y+(roofY-g.min.Y)*fraction
		local spans={}; for i=1,#edges do spans[i]={} end
		local unexplainedInside,unexplainedOutside=0,0
		local segments=sections(g,y)
		for _,s in segments do
			local delta=s[2]-s[1]; local length=delta.Magnitude
			if length<1e-5 then continue end
			local match,bestCost,interval=nil,math.huge,nil
			for index,edge in edges do
				if math.abs(delta.Unit:Dot(edge.direction))<0.975 then continue end
				local qa,qb=s[1]-edge.a,s[2]-edge.a
				local da=math.abs(edge.direction.X*qa.Y-edge.direction.Y*qa.X)
				local db=math.abs(edge.direction.X*qb.Y-edge.direction.Y*qb.X)
				if math.max(da,db)>tolerance then continue end
				local ta,tb=qa:Dot(edge.direction),qb:Dot(edge.direction)
				local low,high=math.max(0,math.min(ta,tb)),math.min(edge.length,math.max(ta,tb))
				if high-low>0.05 and da+db<bestCost then match,bestCost,interval=index,da+db,{low,high} end
			end
			if match then table.insert(spans[match],interval)
			else
				local outside=0
				for _,t in {0,0.25,0.5,0.75,1} do if not inside(s[1]:Lerp(s[2],t),points,tolerance) then outside+=1 end end
				unexplainedOutside+=length*outside/5; unexplainedInside+=length*(1-outside/5)
			end
		end
		local supported=0
		for _,list in spans do supported+=coveredLength(list) end
		local supportRatio=supported/perimeter
		local ok=supportRatio>=0.72 and unexplainedOutside<=perimeter*0.12 and unexplainedInside<=perimeter*0.16
		table.insert(result.samples,{fraction=fraction,y=y,ok=ok,segments=#segments,support=supportRatio,
			unexplainedOutside=unexplainedOutside/perimeter,unexplainedInside=unexplainedInside/perimeter})
		if ok then
			result.validSamples+=1; result.firstFraction=math.min(result.firstFraction,fraction)
			result.lastFraction=fraction; result.meanSupport+=supportRatio
			for index,list in spans do for _,span in list do table.insert(allSpans[index],span) end end
		end
	end
	if result.validSamples>0 then result.meanSupport/=result.validSamples end
	for index,edge in edges do
		local coverage=coveredLength(allSpans[index])/edge.length
		result.unsupportedLength+=edge.length*(1-coverage)
		if coverage<0.2 and edge.length>math.max(5,perimeter*0.04) then result.unsupportedEdges+=1 end
	end
	result.unsupportedFraction=result.unsupportedLength/perimeter
	if result.validSamples<4 or result.firstFraction>0.22 or result.lastFraction<0.72
		or result.lastFraction-result.firstFraction<0.5 then
		return nil,"roof footprint lacks persistent facade support",result
	end
	-- A complete measured roof can supply one missing wall, provided at least
	-- three quarters of its outline is independently evidenced below. Several
	-- absent sides or substantial lower/inner bodies remain ambiguous.
	if result.unsupportedFraction>0.26 or result.unsupportedEdges>1 then
		return nil,"too many unsupported roof edges",result
	end
	return result,nil,result
end

local function analyzeRoof(g,options)
	local height=g.max.Y-g.min.Y
	local diagnostics={candidates={},failureCounts={},eligibleBands=0}
	if height<options.MinHeight then return nil,"short fragment",diagnostics end
	local candidates={}
	for _,band in broadRoofBands(g) do
		if band.y>=g.min.Y+height*0.78 and band.y-g.min.Y>=options.MinHeight and band.area>=options.MinArea then
			table.insert(candidates,band)
		end
	end
	table.sort(candidates,function(a,b) return a.area>b.area end)
	diagnostics.eligibleBands=#candidates
	local best
	-- Rooftop hardware may contribute many tiny planes. The eight broadest
	-- near-top planes bound work while favoring the actual main roof surface.
	for index=1,math.min(8,#candidates) do
		local band=candidates[index]
		local row={y=band.y,triangleArea=band.area,triangles=#band.faces}
		local roof,reason,topology=roofBoundary(band,options)
		if roof then
			row.area=roof.area; row.corners=#roof.points; row.coverage=roof.coverage
			row.holes=roof.holes; row.holeArea=roof.holeArea
			local facades,failure,details=verifyRoofFacades(g,roof,band.y,options)
			row.facades=details
			if facades then
				row.accepted=true
				local score=roof.area*(band.y-g.min.Y)*facades.meanSupport
				if not best or score>best.score then best={roof=roof,facades=facades,y=band.y,score=score} end
			else reason=failure end
		elseif topology then row.topology=topology end
		if reason then row.reason=reason; diagnostics.failureCounts[reason]=(diagnostics.failureCounts[reason] or 0)+1 end
		table.insert(diagnostics.candidates,row)
	end
	if not best then return nil,#candidates==0 and "no broad planar roof near source top" or "no roof with verified facade support",diagnostics end
	local roof,rect=best.roof,best.roof.rect
	local center=rect.u*((rect.lo.X+rect.hi.X)/2)+rect.v*((rect.lo.Y+rect.hi.Y)/2)
	local frame=CFrame.new(center.X,g.min.Y,center.Y)*CFrame.Angles(0,-math.atan2(rect.u.Y,rect.u.X),0)
	local points={}
	for _,p in roof.points do
		local q=frame:PointToObjectSpace(Vector3.new(p.X,g.min.Y,p.Y)); table.insert(points,Vector2.new(q.X,q.Z))
	end
	local bodyHeight=best.y-g.min.Y
	local confidence=math.clamp(0.67+best.facades.meanSupport*0.18+best.facades.validSamples/6*0.1-roof.repairs*0.005,0,0.95)
	return {key=Massing.SourceKey(g),frame=frame,points=points,tiers={{bottom=0,top=bodyHeight,points=points}},
		height=bodyHeight,sourceBaseY=g.min.Y,sourceTopY=g.max.Y,roofTrim=g.max.Y-best.y,area=roof.area,
		confidence=confidence,reason="Complete planar roof and persistent matching facade evidence",method="verified planar roof",
		sampleCount=best.facades.validSamples,sampleFailures={},seamRepairs=roof.repairs,rectangleRepairs=0,
		size=Vector3.new(rect.size.X,bodyHeight,rect.size.Y),roofEvidence={coverage=roof.coverage,
			facadeSupport=best.facades.meanSupport,unsupportedFraction=best.facades.unsupportedFraction,
			validSamples=best.facades.validSamples,holes=roof.holes}},nil,diagnostics
end

function Massing.AnalyzeRoof(g,options)
	return analyzeRoof(g,optionsWithDefaults(options))
end

function Massing.DiagnoseRoof(g,options)
	local p,reason,report=analyzeRoof(g,optionsWithDefaults(options))
	report.accepted=p~=nil; report.reason=reason
	if p then report.area=p.area; report.height=p.height; report.corners=#p.points; report.confidence=p.confidence end
	return report
end

-- JSON-safe diagnostics expose why a component failed without changing any
-- acceptance rules. Useful for aggregating failures before tuning thresholds.
function Massing.Diagnose(g,options)
	options=optionsWithDefaults(options)
	options.TraceTopology=true
	assert(g and g.triangles and g.min and g.max,"Pass a scanned geometry component")
	local height=g.max.Y-g.min.Y
	local report={key=Massing.SourceKey(g),height=height,triangleCount=#g.triangles,
		samples={},groups={},failureCounts={},validSamples=0,dominantCount=0,dominantSpan=0,persistentGroups=0}
	local groups={}
	for index,fraction in FRACTIONS do
		local y=g.min.Y+height*fraction
		local s,reason,diagnostics=sample(g,y,options)
		local row=diagnostics or {}
		row.index=index; row.fraction=fraction; row.y=y; row.ok=s~=nil
		if s then
			row.area=s.area; row.corners=#s.points; row.width=s.width
			report.validSamples+=1
			local matched
			for groupIndex,group in groups do
				if similar(s,group.representative) then matched=group; row.group=groupIndex; break end
			end
			if not matched then
				matched={representative=s,count=0,first=fraction,last=fraction,minArea=s.area,maxArea=s.area}
				table.insert(groups,matched); row.group=#groups
			end
			matched.count+=1; matched.last=fraction
			matched.minArea=math.min(matched.minArea,s.area); matched.maxArea=math.max(matched.maxArea,s.area)
		else
			row.reason=reason or "unknown sample failure"
			report.failureCounts[row.reason]=(report.failureCounts[row.reason] or 0)+1
		end
		table.insert(report.samples,row)
	end
	for index,group in groups do
		local span=group.last-group.first
		local persistent=group.count>=options.MinSupportSamples and span>=options.MinSupportSpan
		if persistent then report.persistentGroups+=1 end
		table.insert(report.groups,{index=index,count=group.count,firstFraction=group.first,lastFraction=group.last,
			span=span,minArea=group.minArea,maxArea=group.maxArea,corners=#group.representative.points,persistent=persistent})
		if group.count>report.dominantCount then report.dominantCount=group.count; report.dominantSpan=span end
	end
	if height<options.MinHeight then report.reason="short fragment"
	elseif #g.triangles<6 then report.reason="insufficient facade geometry"
	elseif report.dominantCount<options.MinSupportSamples or report.dominantSpan<options.MinSupportSpan then
		report.reason="no persistent building body"
	else report.reason="persistent body; Analyze validates tiers and roof" end
	return report
end

local function analyzeContours(g,options)
	options=optionsWithDefaults(options)
	if not g or not g.triangles or #g.triangles<6 then return nil,"insufficient facade geometry" end
	local height=g.max.Y-g.min.Y
	if height<options.MinHeight then return nil,"short fragment" end
	local samples,failures,groups={},{},{}
	for i,fraction in FRACTIONS do
		local s,reason=sample(g,g.min.Y+height*fraction,options)
		if not s then
			failures[reason]=(failures[reason] or 0)+1
			if fraction>=0.15 and fraction<=0.85 and (reason=="courtyard or internal loop" or reason=="multiple substantial bodies") then
				return nil,reason
			end
			continue
		end
		s.index=i; s.fraction=fraction; samples[i]=s
		local best
		for _,group in groups do if similar(s,group.representative) then best=group; break end end
		if not best then
			best={members={},representative=s,first=fraction,last=fraction}; table.insert(groups,best)
		end
		table.insert(best.members,s); best.last=fraction; s.group=best
	end
	local dominant
	for _,group in groups do
		if not dominant or #group.members>#dominant.members then dominant=group end
		-- Select a real median-area slice; averaging mismatched corner lists
		-- would distort notches and chamfers.
		table.sort(group.members,function(a,b) return a.area<b.area end)
		group.representative=group.members[math.ceil(#group.members/2)]
	end
	if not dominant or #dominant.members<options.MinSupportSamples
		or dominant.last-dominant.first<options.MinSupportSpan then
		return nil,"no persistent building body"
	end
	local supported={}
	for _,group in groups do
		if group==dominant or (#group.members>=2 and group.last-group.first>=0.055) then
			table.insert(supported,group); group.supported=true
		end
	end
	if #supported>options.MaxTiers then return nil,"too many independent massing changes" end
	local usable,previous={},nil
	for i=1,#FRACTIONS do
		local s=samples[i]
		if s and s.group.supported then
			if s.group~=previous then
				for _,run in usable do if run.group==s.group then return nil,"oscillating footprint" end end
				table.insert(usable,{group=s.group,first=s,last=s})
			else usable[#usable].last=s end
			previous=s.group
		end
	end
	if #usable==0 then return nil,"no usable massing" end
	local roofY=g.max.Y
	local planes=roofPlanes(g)
	local top=usable[#usable].group.representative
	-- A small roof object may itself have two valid contours. It is equipment
	-- only when short, confined to the top, and a broad roof below supports it.
	if #usable>1 then
		local last,below=usable[#usable],usable[#usable-1]
		local small=last.group.representative.area<below.group.representative.area*0.45
		if small and last.first.fraction>=0.86 then
			for _,plane in planes do
				if plane.y>below.last.y and plane.y<=last.first.y
					and plane.area>=below.group.representative.area*0.4 then
					roofY=plane.y; table.remove(usable); top=below.group.representative; break
				end
			end
		end
	end
	-- Trim isolated rooftop geometry only with a broad horizontal roof close to
	-- the component top. Without that evidence the imported height is retained.
	for _,plane in planes do
		if plane.y>=g.min.Y+height*0.80 and plane.y>=usable[#usable].last.y-0.5
			and plane.y<roofY-0.5 and plane.area>=top.area*0.50 then roofY=plane.y end
	end
	if roofY-g.min.Y<options.MinHeight then return nil,"body too short after roof trim" end
	local worldTiers={}
	local bottom=g.min.Y
	for i,run in usable do
		local points=run.group.representative.points
		local tierTop=roofY
		if i<#usable then
			local nextRun=usable[i+1]; local nextPoints=nextRun.group.representative.points
			if not contains(points,nextPoints,options.SimplifyTolerance*1.5) then
				return nil,"offset or expanding upper body"
			end
			local lower,upper=run.last.y,nextRun.first.y
			-- Refine the actual setback elevation rather than placing it halfway
			-- through a storey just because samples were widely spaced.
			for _=1,7 do
				local mid=(lower+upper)/2; local s=sample(g,mid,options)
				if not s then break end
				if similar(s,run.group.representative) then lower=mid
				elseif similar(s,nextRun.group.representative) then upper=mid else break end
			end
			tierTop=(lower+upper)/2
			local nearest,nearestDelta=nil,math.max(1,(upper-lower)/2)
			for _,plane in planes do
				if math.abs(plane.y-tierTop)<nearestDelta and plane.area>math.abs(run.group.representative.area-nextRun.group.representative.area)*0.25 then
					nearest,nearestDelta=plane.y,math.abs(plane.y-tierTop)
				end
			end
			tierTop=nearest or tierTop
		end
		if tierTop-bottom<2 then return nil,"unusable thin massing tier" end
		table.insert(worldTiers,{bottom=bottom,top=tierTop,points=points})
		bottom=tierTop
	end
	local basePolygon=worldTiers[1].points
	local rect=rectangle(basePolygon)
	local center=rect.u*((rect.lo.X+rect.hi.X)/2)+rect.v*((rect.lo.Y+rect.hi.Y)/2)
	local frame=CFrame.new(center.X,g.min.Y,center.Y)*CFrame.Angles(0,-math.atan2(rect.u.Y,rect.u.X),0)
	local tiers={}
	for _,tier in worldTiers do
		local points={}
		for _,p in tier.points do
			local q=frame:PointToObjectSpace(Vector3.new(p.X,g.min.Y,p.Y))
			table.insert(points,Vector2.new(q.X,q.Z))
		end
		table.insert(tiers,{bottom=tier.bottom-g.min.Y,top=tier.top-g.min.Y,points=points})
	end
	local count,repaired,fallback=0,0,0
	for _,s in samples do count+=1; repaired+=s.repaired; if s.fallback then fallback+=1 end end
	local confidence=math.clamp(0.52+0.35*(count/#FRACTIONS)+0.13*(dominant.last-dominant.first)-fallback*0.006-repaired*0.003,0,1)
	return {key=Massing.SourceKey(g),frame=frame,points=tiers[1].points,tiers=tiers,
		height=roofY-g.min.Y,sourceBaseY=g.min.Y,sourceTopY=g.max.Y,roofTrim=g.max.Y-roofY,
		area=area(basePolygon),confidence=confidence,reason="Repeated simplified facade contours",method="repeated facade contours",
		sampleCount=count,sampleFailures=failures,seamRepairs=repaired,rectangleRepairs=fallback,
		size=Vector3.new(rect.size.X,roofY-g.min.Y,rect.size.Y)}
end

function Massing.Analyze(g,options)
	local configured=optionsWithDefaults(options)
	local plan,reason=analyzeContours(g,configured)
	if plan or reason~="no persistent building body" or not configured.RoofFallback then return plan,reason end
	local roofPlan,roofReason,diagnostics=analyzeRoof(g,configured)
	if roofPlan then roofPlan.contourFailure=reason; return roofPlan end
	return nil,reason,{roofFailure=roofReason,roofFailureCounts=diagnostics.failureCounts,eligibleRoofBands=diagnostics.eligibleBands}
end

function Massing.Preview(components,options)
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	options=options or {}
	components=components or require(script.Parent.ShibuyaGeometry).Scan(options.Source)
	local folder=options.Buildings or workspace:FindFirstChild("Buildings")
	assert(folder,"Workspace.Buildings is missing")
	local existing,duplicates,geometricModels,modelGeometricCounts={},{},{},{}
	for _,b in folder:GetChildren() do
		local key=b:GetAttribute("ShibuyaSourceKey")
		if b:IsA("Model") and b.Name:match("^BuildingAuto_") and key then
			if existing[key] then duplicates[key]=true else existing[key]=b end
			local geometry=geometricKey(key)
			if geometry then
				geometricModels[geometry]=b
				modelGeometricCounts[geometry]=(modelGeometricCounts[geometry] or 0)+1
			end
		end
	end
	local report={plans={},rejected={},rejectedModels={},roofRejections={},methods={},scanned=#components,matched=0,unmatched=0,
		exactMatches=0,geometricMatches=0,unverifiedGeometricMatches=0}
	local componentKeyCounts,componentGeometricCounts={},{}
	for _,g in components do
		local key=Massing.SourceKey(g); componentKeyCounts[key]=(componentKeyCounts[key] or 0)+1
		local geometry=geometricKey(key)
		if geometry then componentGeometricCounts[geometry]=(componentGeometricCounts[geometry] or 0)+1 end
	end
	for i,g in components do
		local key=Massing.SourceKey(g); local old=existing[key]
		local matchMethod="exact source key"
		if not old then
			local geometry=geometricKey(key)
			if geometry and modelGeometricCounts[geometry]==1 and componentGeometricCounts[geometry]==1 then
				local candidate=geometricModels[geometry]
				if matchesStoredEnvelope(g,candidate) then
					old=candidate; matchMethod="unique XYZ key and verified source envelope"
				else report.unverifiedGeometricMatches+=1 end
			end
		end
		if not old then report.unmatched+=1; continue end
		report.matched+=1
		if matchMethod=="exact source key" then report.exactMatches+=1 else report.geometricMatches+=1 end
		local oldKey=old:GetAttribute("ShibuyaSourceKey")
		local p,reason,details
		if duplicates[oldKey] or componentKeyCounts[key]>1 then reason="duplicate source key" else p,reason,details=Massing.Analyze(g,options) end
		if p then
			p.key=oldKey; p.componentSourceKey=key; p.matchMethod=matchMethod
			p.oldModel=old; p.component=i; table.insert(report.plans,p)
			local method=p.method or "repeated facade contours"; report.methods[method]=(report.methods[method] or 0)+1
		else
			reason=reason or "unknown geometry failure"
			report.rejected[reason]=(report.rejected[reason] or 0)+1
			table.insert(report.rejectedModels,{oldModel=old,key=oldKey,componentSourceKey=key,
				matchMethod=matchMethod,component=i,reason=reason,diagnostics=details})
			if details and details.roofFailure then
				report.roofRejections[details.roofFailure]=(report.roofRejections[details.roofFailure] or 0)+1
			end
		end
		if i%30==0 then task.wait() end
	end
	table.sort(report.plans,function(a,b)
		if a.area==b.area then return a.key<b.key end
		return a.area>b.area
	end)
	return report
end

return Massing
