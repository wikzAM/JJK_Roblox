--!nonstrict
-- READ-ONLY alternative evidence from the full legacy generated map.
-- Preview(workspace.Buildings, options?) -> report accepted by Smooth.Build.
-- It traces stored occupancy, simplifies ordinary massing, and returns REAL
-- polygons. It never regenerates voxel slabs or modifies/replaces any model.
-- Simplification is intentional and reported; this is not recovery of lost
-- source detail. Meaningful courtyards, secondary bodies, and half-envelope
-- fragments remain deferred; only bounded tiny islands/holes are cleaned.
-- Visually inspect a staged Smooth.Build result before Apply.
local GridMassing={}
local Http=game:GetService("HttpService")
local SLAB=1.5/0.28
local DEFAULTS={
	MinArea=200, MinWidth=10, MinFloors=3, MinSupportFloors=3,
	MinValidFraction=0.80, MinHeightCoverage=0.75, MinEnvelopeSpan=0.80,
	MinEnvelopeArea=0.40, Similarity=0.86, NearbySimilarity=0.76,
	ToleranceCells=0.90, MaxSimplifyStuds=10, MaxAreaChange=0.16,
	RectangleAgreement=0.95, MaxVertices=48, MaxTiers=3, YieldEvery=20,
	MinDominantArea=0.95, MaxIslandCells=4, MaxIslandArea=200,
	MaxHoleCells=1, MaxHoleArea=36, MaxHoleFraction=0.01,
}

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function cross(a,b) return a.X*b.Y-a.Y*b.X end
local function area(poly)
	local result,origin=0,poly[1]
	for i,a in poly do result+=cross(a-origin,poly[i%#poly+1]-origin) end
	return math.abs(result)/2
end
local function distance(p,a,b)
	local d=b-a
	return (p-(a+d*math.clamp((p-a):Dot(d)/math.max(d:Dot(d),1e-12),0,1))).Magnitude
end
local function inside(poly,p)
	local yes=false
	for i,a in poly do
		local b=poly[i%#poly+1]
		if distance(p,a,b)<=1e-5 then return true end
		if (a.Y>p.Y)~=(b.Y>p.Y) and p.X<a.X+(p.Y-a.Y)*(b.X-a.X)/(b.Y-a.Y) then yes=not yes end
	end
	return yes
end

local function contains(outer,inner)
	for i,a in inner do
		local b=inner[i%#inner+1]
		if not inside(outer,a) or not inside(outer,b) then return false end
		local r=b-a
		local cuts={0,1}
		for j,c in outer do
			local d=outer[j%#outer+1]
			local s=d-c
			local det=cross(r,s)
			if math.abs(det)>1e-8 then
				local t,u=cross(c-a,s)/det,cross(c-a,r)/det
				if t>0 and t<1 and u>=0 and u<=1 then table.insert(cuts,t) end
			elseif math.abs(cross(c-a,r))<=1e-8 then
				for _,p in {c,d} do local t=(p-a):Dot(r)/r:Dot(r); if t>0 and t<1 then table.insert(cuts,t) end end
			end
		end
		table.sort(cuts)
		for j=1,#cuts-1 do
			if cuts[j+1]-cuts[j]>1e-7 and not inside(outer,a+r*((cuts[j]+cuts[j+1])/2)) then return false end
		end
	end
	return true
end

local function optionsWithDefaults(options)
	local configured=table.clone(DEFAULTS)
	for key,value in options or {} do
		assert(DEFAULTS[key]~=nil,"Unknown grid massing option: "..tostring(key))
		assert(finite(value) and value>0,"Invalid grid massing option: "..key)
		configured[key]=value
	end
	for _,key in {"MinValidFraction","MinHeightCoverage","MinEnvelopeSpan","MinEnvelopeArea","Similarity","NearbySimilarity","RectangleAgreement","MinDominantArea","MaxHoleFraction"} do
		assert(configured[key]<=1,key.." must be <=1")
	end
	for _,key in {"MinFloors","MinSupportFloors","MaxVertices","MaxTiers","YieldEvery","MaxIslandCells","MaxHoleCells"} do assert(configured[key]%1==0,key.." must be an integer") end
	return configured
end

local function floorBottom(grid,k)
	if k<=1 then return 0 end
	return SLAB+grid.ground+(k-2)*(grid.clearUpper+SLAB)
end

local function readGrid(model)
	local raw=model:GetAttribute("InteriorGrid")
	assert(type(raw)=="string","missing saved grid")
	local g=Http:JSONDecode(raw)
	local cf,size=model:GetAttribute("InteriorBBoxCFrame"),model:GetAttribute("InteriorBBoxSize")
	assert(typeof(cf)=="CFrame" and typeof(size)=="Vector3" and cf.UpVector.Y>0.999999,"invalid source envelope")
	assert(size.X>0 and size.Y>0 and size.Z>0,"invalid source dimensions")
	for _,key in {"cell","nx","nz","floors","minX","minZ","ground"} do assert(finite(g[key]),"invalid grid "..key) end
	g.clearUpper=g.clearUpper or 3.5/0.28
	assert(finite(g.clearUpper) and g.clearUpper>0 and g.ground>0,"invalid floor spacing")
	assert(g.cell>0 and g.nx>=1 and g.nz>=1 and g.nx%1==0 and g.nz%1==0 and g.nx*g.nz<=16384,"invalid grid dimensions")
	assert(g.floors>=1 and g.floors<200 and g.floors%1==0 and type(g.occ)=="table","invalid floor masks")
	assert(math.abs(g.minX+size.X/2)<0.05 and math.abs(g.minZ+size.Z/2)<0.05,"grid origin does not match source envelope")
	return g,cf,size
end

-- Remove only explicitly bounded sampling debris before tracing. Occupied
-- four-neighbor components remain separate; meaningful holes are never filled.
-- This creates a fresh mask and never changes the saved InteriorGrid.
local function cleanMask(mask,g,size,options)
	local bits,areas={},{}
	local stats={originalArea=0,components=0,dominantFraction=1,removedIslands=0,removedIslandCells=0,
		removedIslandArea=0,filledHoles=0,filledHoleCells=0,filledHoleArea=0,ambiguous=false}
	for i=1,g.nx do for j=1,g.nz do
		local index=(i-1)*g.nz+j
		bits[index]=mask:byte(index)==49
		local w=math.max(0,math.min(g.cell,size.X/2-(g.minX+(i-1)*g.cell)))
		local d=math.max(0,math.min(g.cell,size.Z/2-(g.minZ+(j-1)*g.cell)))
		areas[index]=w*d
		if bits[index] then
			if areas[index]<=0 then return nil,"occupied cells outside source envelope",stats end
			stats.originalArea+=areas[index]
		end
	end end
	local function components(occupied)
		local seen,result={},{}
		for start=1,#bits do
			if seen[start] or bits[start]~=occupied then continue end
			local component={cells={},area=0,exterior=false}
			local queue,head={start},1; seen[start]=true
			while head<=#queue do
				local index=queue[head]; head+=1
				local i=math.floor((index-1)/g.nz)+1; local j=(index-1)%g.nz+1
				table.insert(component.cells,index); component.area+=areas[index]
				if i==1 or i==g.nx or j==1 or j==g.nz then component.exterior=true end
				for _,nextIndex in {i>1 and index-g.nz or 0,i<g.nx and index+g.nz or 0,
					j>1 and index-1 or 0,j<g.nz and index+1 or 0} do
					if nextIndex>0 and not seen[nextIndex] and bits[nextIndex]==occupied then
						seen[nextIndex]=true; table.insert(queue,nextIndex)
					end
				end
			end
			table.insert(result,component)
		end
		return result
	end
	local solids=components(true)
	stats.components=#solids
	if #solids==0 then return nil,"empty floor",stats end
	table.sort(solids,function(a,b) return a.area>b.area end)
	stats.dominantFraction=solids[1].area/stats.originalArea
	if #solids>1 then
		if stats.dominantFraction<options.MinDominantArea then
			stats.ambiguous=true; return nil,"substantial disconnected floor bodies",stats
		end
		for index=2,#solids do
			local island=solids[index]
			if #island.cells>options.MaxIslandCells or island.area>options.MaxIslandArea then
				stats.ambiguous=true; return nil,"detached floor body exceeds fragment bounds",stats
			end
			for _,cell in island.cells do bits[cell]=false end
			stats.removedIslands+=1; stats.removedIslandCells+=#island.cells; stats.removedIslandArea+=island.area
		end
	end
	local holes={}
	for _,empty in components(false) do
		if empty.exterior then continue end
		if #empty.cells>options.MaxHoleCells or empty.area>options.MaxHoleArea then
			stats.ambiguous=true; return nil,"courtyard exceeds small-hole bounds",stats
		end
		table.insert(holes,empty); stats.filledHoleArea+=empty.area
	end
	if stats.filledHoleArea>stats.originalArea*options.MaxHoleFraction then
		stats.ambiguous=true; return nil,"too much enclosed empty area",stats
	end
	for _,hole in holes do
		stats.filledHoles+=1; stats.filledHoleCells+=#hole.cells
		for _,cell in hole.cells do bits[cell]=true end
	end
	local chars={}; for index,value in bits do chars[index]=value and "1" or "0" end
	stats.cleanedArea=stats.originalArea-stats.removedIslandArea+stats.filledHoleArea
	return table.concat(chars),nil,stats
end

local function trace(mask,g,size,options)
	if type(mask)~="string" or #mask~=g.nx*g.nz or mask:find("[^01]") then return nil,"invalid floor mask" end
	local cleaned,reason,cleanup=cleanMask(mask,g,size,options)
	if not cleaned then return nil,reason,cleanup end
	mask=cleaned
	local function fail(message)
		cleanup.ambiguous=message:find("disconnected")~=nil or message:find("courtyard")~=nil or message:find("touching")~=nil
		return nil,message,cleanup
	end
	local function occupied(i,j) return i>=1 and i<=g.nx and j>=1 and j<=g.nz and mask:byte((i-1)*g.nz+j)==49 end
	local nextVertex,indegree,positions={},{},{}
	local occupiedArea,cells=0,0
	local function id(x,z) return x..":"..z end
	local function edge(x0,z0,x1,z1)
		local a,b=id(x0,z0),id(x1,z1)
		if nextVertex[a] or indegree[b] then return false end
		nextVertex[a]=b; indegree[b]=true
		positions[a]=Vector2.new(math.min(g.minX+x0*g.cell,size.X/2),math.min(g.minZ+z0*g.cell,size.Z/2))
		return true
	end
	for i=1,g.nx do for j=1,g.nz do
		if not occupied(i,j) then continue end
		local w=math.min(g.cell,size.X/2-(g.minX+(i-1)*g.cell))
		local d=math.min(g.cell,size.Z/2-(g.minZ+(j-1)*g.cell))
		if w<=0 or d<=0 then return fail("occupied cells outside source envelope") end
		occupiedArea+=w*d; cells+=1
		if not occupied(i,j-1) and not edge(i-1,j-1,i,j-1) then return fail("self-touching or disconnected floor") end
		if not occupied(i+1,j) and not edge(i,j-1,i,j) then return fail("self-touching or disconnected floor") end
		if not occupied(i,j+1) and not edge(i,j,i-1,j) then return fail("self-touching or disconnected floor") end
		if not occupied(i-1,j) and not edge(i-1,j,i-1,j-1) then return fail("self-touching or disconnected floor") end
	end end
	if cells==0 then return fail("empty floor") end
	local seen,loops={},{}
	for start in nextVertex do
		if seen[start] then continue end
		local ring,current={},start
		repeat
			if not current or seen[current] then return fail("open or touching floor boundary") end
			seen[current]=true; table.insert(ring,positions[current]); current=nextVertex[current]
		until current==start
		table.insert(loops,ring)
	end
	if #loops~=1 then return fail("disconnected floor or courtyard") end
	return {mask=mask,rawPoints=loops[1],rawArea=occupiedArea,cells=cells,cleanup=cleanup},nil,cleanup
end

local function simplifyRing(ring,tolerance)
	local first=1
	for i,p in ring do if p.X<ring[first].X or (p.X==ring[first].X and p.Y<ring[first].Y) then first=i end end
	local far,furthest=first,0
	for i,p in ring do local d=(p-ring[first]).Magnitude; if d>furthest then far,furthest=i,d end end
	local function chain(a,b)
		local list={ring[a]}
		while a~=b do a=a%#ring+1; table.insert(list,ring[a]) end
		return list
	end
	local function rdp(list)
		local keep,pending={[1]=true,[#list]=true},{{1,#list}}
		while #pending>0 do
			local pair=table.remove(pending)
			local a,b=pair[1],pair[2]
			local index,best=nil,tolerance
			for i=a+1,b-1 do local d=distance(list[i],list[a],list[b]); if d>best then index,best=i,d end end
			if index then keep[index]=true; table.insert(pending,{a,index}); table.insert(pending,{index,b}) end
		end
		local result={}; for i,p in list do if keep[i] then table.insert(result,p) end end
		return result
	end
	local a,b=rdp(chain(first,far)),rdp(chain(far,first))
	local result={}
	for i=1,#a-1 do table.insert(result,a[i]) end
	for i=1,#b-1 do table.insert(result,b[i]) end
	return result
end

local function rectangle(poly)
	local best
	for i,a in poly do
		local u=(poly[i%#poly+1]-a).Unit
		local v=Vector2.new(-u.Y,u.X)
		local lo,hi=Vector2.new(math.huge,math.huge),Vector2.new(-math.huge,-math.huge)
		for _,p in poly do local q=Vector2.new(p:Dot(u),p:Dot(v)); lo=lo:Min(q); hi=hi:Max(q) end
		local size=hi-lo
		local candidateArea=size.X*size.Y
		if not best or candidateArea<best.area then
			best={area=candidateArea,size=size,points={u*lo.X+v*lo.Y,u*hi.X+v*lo.Y,u*hi.X+v*hi.Y,u*lo.X+v*hi.Y}}
		end
	end
	return best
end

local function simplifyFloor(floor,g,size,options)
	if floor.rawArea<options.MinArea then return nil,"tiny usable floor" end
	local tolerance=math.min(g.cell*options.ToleranceCells,options.MaxSimplifyStuds)
	local validate=require(script.Parent.PolygonSlab).Validate
	local ok,poly=pcall(validate,simplifyRing(floor.rawPoints,tolerance))
	if not ok then return nil,"simplified boundary is not simple" end
	if #poly>options.MaxVertices then return nil,"too many significant footprint corners" end
	local simplifiedArea=area(poly)
	if math.abs(simplifiedArea/floor.rawArea-1)>options.MaxAreaChange then return nil,"simplification changes too much floor area" end
	local rect=rectangle(poly)
	if math.min(rect.size.X,rect.size.Y)<options.MinWidth then return nil,"narrow fragment footprint" end
	local method="simplified repeated grid polygon"
	if simplifiedArea/rect.area>=options.RectangleAgreement and math.abs(rect.area/floor.rawArea-1)<=options.MaxAreaChange then
		poly=rect.points; simplifiedArea=rect.area; method="high agreement grid rectangle"
	end
	local lo,hi=poly[1],poly[1]
	for _,p in poly do lo=lo:Min(p); hi=hi:Max(p) end
	if (hi.X-lo.X)/size.X<options.MinEnvelopeSpan or (hi.Y-lo.Y)/size.Z<options.MinEnvelopeSpan
		or floor.rawArea/(size.X*size.Z)<options.MinEnvelopeArea then
		floor.lowEnvelopeCoverage=true -- upper setbacks may legitimately be small
	end
	floor.points=poly; floor.area=simplifiedArea; floor.tolerance=tolerance; floor.method=method
	floor.areaChange=simplifiedArea/floor.rawArea-1
	return floor
end

local function similarity(a,b)
	local common=0
	local smaller,other=a,b
	if smaller.cells>other.cells then smaller,other=other,smaller end
	for i=1,#smaller.mask do if smaller.mask:byte(i)==49 and other.mask:byte(i)==49 then common+=1 end end
	return common/(a.cells+b.cells-common)
end

local function analyze(model,options)
	local grid,sourceCF,size=readGrid(model)
	if grid.floors<options.MinFloors then return nil,"too few legacy floors" end
	local cache,rows,groups,failures={},{},{},{}
	local valid=0
	for k=1,grid.floors do
		local mask=grid.occ[k]
		local cached=type(mask)=="string" and cache[mask]
		if not cached then
			local f,reason,topology=trace(mask,grid,size,options)
			if f then f,reason=simplifyFloor(f,grid,size,options) end
			cached={floor=f,reason=reason,topology=topology}; if type(mask)=="string" then cache[mask]=cached end
		end
		if not cached.floor then
			if (cached.topology and cached.topology.ambiguous) or cached.reason:find("disconnected")
				or cached.reason:find("courtyard") or cached.reason:find("touching") then
				return nil,"ambiguous floor topology: "..cached.reason
			end
			failures[cached.reason]=(failures[cached.reason] or 0)+1; continue
		end
		local floor=cached.floor
		local group
		for _,candidate in groups do if similarity(floor,candidate.representative)>=options.Similarity then group=candidate; break end end
		if not group then group={representative=floor,members={},indices={}}; table.insert(groups,group) end
		table.insert(group.members,floor); table.insert(group.indices,k)
		rows[k]={floor=floor,group=group}; valid+=1
	end
	if not rows[1] then return nil,"ground floor is not a complete usable body" end
	if valid/grid.floors<options.MinValidFraction then return nil,"too little complete floor coverage" end
	local supported={}
	for _,group in groups do
		table.sort(group.members,function(a,b) return a.rawArea<b.rawArea end)
		group.representative=group.members[math.ceil(#group.members/2)]
		local shortMajority=grid.floors==3 and #group.members>=2 and valid==3
		if #group.members>=options.MinSupportFloors or shortMajority then group.supported=true; table.insert(supported,group) end
	end
	if #supported==0 then return nil,"no repeated major footprint" end
	if #supported>options.MaxTiers then return nil,"too many distinct major footprints" end
	local assigned,lastSupported={},0
	local regularizedFloors,maxRegularizedAreaChange,bridgedMissingFloors=0,0,0
	for k,row in rows do
		local group=row.group.supported and row.group or nil
		if not group then
			for _,candidate in supported do
				local ratio=row.floor.rawArea/candidate.representative.rawArea
				if ratio>=0.85 and ratio<=1.15 and similarity(row.floor,candidate.representative)>=options.NearbySimilarity then group=candidate; break end
			end
		end
		assigned[k]=group
		if group then
			lastSupported=math.max(lastSupported,k)
			if row.floor.mask~=group.representative.mask then
				regularizedFloors+=1
			end
			-- Include masks clustered into the same supported group, not only
			-- reassigned outliers, when reporting the final area change.
			maxRegularizedAreaChange=math.max(maxRegularizedAreaChange,math.abs(group.representative.area/row.floor.rawArea-1))
		end
	end
	if not assigned[1] then return nil,"base has no persistent footprint support" end
	if assigned[1].representative.lowEnvelopeCoverage then return nil,"base footprint covers too little source envelope" end
	local height=math.min(size.Y,floorBottom(grid,lastSupported+1)+SLAB)
	if height/size.Y<options.MinHeightCoverage then return nil,"persistent body covers too little height" end
	local runs,seen,last={},{},nil
	local supportedCount=0
	for k=1,lastSupported do
		local group=assigned[k]
		if not group then
			-- Fill a missing single level only when the same independently repeated
			-- footprint exists immediately above and below; never bridge half a body.
			if rows[k] or k==1 or assigned[k-1]~=assigned[k+1] then return nil,"unsupported interior footprint transition" end
			group=assigned[k-1]
			bridgedMissingFloors+=1
		end
		if not group then return nil,"unresolved missing floor" end
		supportedCount+=1
		if group~=last then
			if seen[group] then return nil,"oscillating major footprints" end
			if last and not contains(last.representative.points,group.representative.points) then return nil,"offset or expanding grid tier" end
			table.insert(runs,{group=group,first=k}); seen[group]=true; last=group
		end
	end
	if supportedCount/grid.floors<options.MinValidFraction then return nil,"too little supported building coverage" end
	-- Unsupported levels above the supported roof must be small, not another
	-- unproven full-height wing or half-building that this pass would erase.
	for k=lastSupported+1,grid.floors do
		if rows[k] and rows[k].floor.rawArea>last.representative.rawArea*0.65 then return nil,"unsupported substantial upper body" end
	end
	local tiers,methods={},{}
	local removedIslandArea,filledHoleArea,cleanupFloors=0,0,0
	for _,row in rows do
		local cleanup=row.floor.cleanup
		if cleanup and (cleanup.removedIslandArea>0 or cleanup.filledHoleArea>0) then
			removedIslandArea+=cleanup.removedIslandArea; filledHoleArea+=cleanup.filledHoleArea; cleanupFloors+=1
		end
	end
	local maxChange=0
	for i,run in runs do
		local floor=run.group.representative
		local top=i<#runs and floorBottom(grid,runs[i+1].first) or height
		table.insert(tiers,{bottom=i==1 and 0 or floorBottom(grid,run.first),top=top,points=floor.points})
		methods[floor.method]=(methods[floor.method] or 0)+1
		maxChange=math.max(maxChange,math.abs(floor.areaChange))
	end
	local baseFrame=sourceCF*CFrame.new(0,-size.Y/2,0)
	local base=runs[1].group.representative
	return {oldModel=model,key=model:GetAttribute("ShibuyaSourceKey"),frame=baseFrame,points=tiers[1].points,
		tiers=tiers,height=height,sourceBaseY=baseFrame.Y,sourceTopY=baseFrame.Y+size.Y,roofTrim=size.Y-height,
		area=base.area,confidence=math.clamp(0.60+0.20*(valid/grid.floors)-maxChange*0.5,0,0.85),
		reason="Repeated complete legacy floor plates; deliberate grid-to-polygon simplification",
		method="repeated legacy grid massing",size=Vector3.new(size.X,height,size.Z),
		gridEvidence={sourceFloors=grid.floors,validFloors=valid,supportedFloors=supportedCount,
			baseSupportFloors=#runs[1].group.members,sourceEnvelopeCoverage=base.rawArea/(size.X*size.Z),
			maxAreaChange=maxChange,tolerance=base.tolerance,sourceCell=grid.cell,methods=methods,floorFailures=failures,
			regularizedFloors=regularizedFloors,maxRegularizedAreaChange=maxRegularizedAreaChange,
			bridgedMissingFloors=bridgedMissingFloors,cleanupFloors=cleanupFloors,
			removedIslandArea=removedIslandArea,filledHoleArea=filledHoleArea}},nil
end

function GridMassing.Diagnose(model,options)
	local configured=optionsWithDefaults(options)
	local grid,_,size=readGrid(model)
	local report={key=model:GetAttribute("ShibuyaSourceKey"),floors=grid.floors,samples={},failureCounts={},valid=0}
	local cache={}
	for k=1,grid.floors do
		local mask=grid.occ[k]
		local cached=type(mask)=="string" and cache[mask]
		if not cached then
			local floor,reason,cleanup=trace(mask,grid,size,configured)
			cached={ok=floor~=nil,reason=reason,cleanup=cleanup}
			if type(mask)=="string" then cache[mask]=cached end
		end
		local row=table.clone(cached); row.floor=k
		table.insert(report.samples,row)
		if row.ok then report.valid+=1 else
			local reason=row.reason or "unknown topology failure"
			report.failureCounts[reason]=(report.failureCounts[reason] or 0)+1
		end
	end
	return report
end

function GridMassing.Preview(folder,options)
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	folder=folder or workspace:FindFirstChild("Buildings")
	assert(folder and (folder:IsA("Model") or folder:IsA("Folder")),"Provide the direct building container")
	local configured=optionsWithDefaults(options)
	local report={plans={},rejected={},rejectedModels={},methods={},matched=0,scanned=0,protected=0,options=configured}
	local keyCounts={}
	for _,b in folder:GetChildren() do
		local key=b:GetAttribute("ShibuyaSourceKey")
		if b:IsA("Model") and b.Name:match("^BuildingAuto_") and key then keyCounts[key]=(keyCounts[key] or 0)+1 end
	end
	for _,b in folder:GetChildren() do
		local key=b:GetAttribute("ShibuyaSourceKey")
		if not b:IsA("Model") or not b.Name:match("^BuildingAuto_") or type(key)~="string" or #key==0
			or b:GetAttribute("SmoothMassing") or b:GetAttribute("ManualShellVersion") then report.protected+=1; continue end
		report.scanned+=1; report.matched+=1
		local ok,plan,reason
		if keyCounts[key]>1 then ok,reason=true,"duplicate source key" else ok,plan,reason=pcall(analyze,b,configured) end
		if not ok then reason=tostring(plan):gsub("^.-:%d+: ",""); plan=nil end
		if plan then
			table.insert(report.plans,plan)
			report.methods[plan.method]=(report.methods[plan.method] or 0)+1
		else
			reason=reason or "unresolved grid evidence"
			report.rejected[reason]=(report.rejected[reason] or 0)+1
			table.insert(report.rejectedModels,{oldModel=b,key=key,reason=reason})
		end
		if report.scanned%configured.YieldEvery==0 then task.wait() end
	end
	table.sort(report.plans,function(a,b) if a.area~=b.area then return a.area>b.area end; return a.key<b.key end)
	print("GRID_MASSING_PREVIEW",report.scanned,"legacy models",#report.plans,"plans; no geometry changed")
	return report
end

return GridMassing
