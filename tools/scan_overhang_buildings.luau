-- Read-only. Finds buildings whose upper floors spread over area with no ground
-- floor beneath (several source buildings stitched into one model). Rows go to
-- _G.OverhangRows: {model,id,floors,upper,unsupported,ratio}.
local H=game:GetService("HttpService")
local Layout=require(game.ReplicatedStorage.Shared.FacadeLayout)
local Collection=game:GetService("CollectionService")
local CELL=4
local function protected(m)
	for _,key in {"Landmark","CrownInteresting","StationInfrastructure","FacadeExcluded"} do
		if m:GetAttribute(key) or Collection:HasTag(m,key) then return true end
	end
	return m.Name=="Building1" or m.Name=="Building2" or m.Name=="Building3"
end
local function inside(px,pz,poly)
	local c=false;local j=#poly
	for i=1,#poly do local a,b=poly[i],poly[j]
		if (a.Z>pz)~=(b.Z>pz) and px<(b.X-a.X)*(pz-a.Z)/(b.Z-a.Z)+a.X then c=not c end
		j=i
	end
	return c
end
local function cells(frame,pieces,set)
	for _,ring in pieces do
		local poly,x0,z0,x1,z1={},math.huge,math.huge,-math.huge,-math.huge
		for _,p in ring do local w=frame:PointToWorldSpace(Vector3.new(p[1],0,p[2]));table.insert(poly,w)
			x0=math.min(x0,w.X);x1=math.max(x1,w.X);z0=math.min(z0,w.Z);z1=math.max(z1,w.Z) end
		for gx=math.floor(x0/CELL),math.floor(x1/CELL) do for gz=math.floor(z0/CELL),math.floor(z1/CELL) do
			if inside((gx+.5)*CELL,(gz+.5)*CELL,poly) then set[gx..","..gz]={gx,gz} end
		end end
	end
end
local rows={}
for i,m in workspace.Buildings:GetChildren() do
	if m:IsA("Model") and not protected(m) then
		local raw=m:GetAttribute("SourceSlicePlan") or m:GetAttribute("FacadeSourcePlan");local frame=Layout.FrameOf(m)
		if type(raw)=="string" and typeof(frame)=="CFrame" then
			local ok,plan=pcall(H.JSONDecode,H,raw)
			if ok and type(plan.levels)=="table" and #plan.levels>=3 then
				local ground,upper={}, {}
				cells(frame,plan.levels[1].pieces,ground)
				for li=2,#plan.levels-1 do cells(frame,plan.levels[li].pieces,upper) end
				local n,un=0,0
				for k,c in upper do
					n+=1
					-- One-cell tolerance: slab edges and small cantilevers are normal.
					local supported=false
					for dx=-1,1 do for dz=-1,1 do if ground[(c[1]+dx)..","..(c[2]+dz)] then supported=true end end end
					if not supported then un+=1 end
				end
				local upperArea,unArea=n*CELL*CELL,un*CELL*CELL
				if unArea>=400 and upperArea>0 and unArea/upperArea>=.25 then
					table.insert(rows,{model=m,id=m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId") or m.Name,
						floors=m:GetAttribute("GeneratedFloors") or (#plan.levels-1),upper=upperArea,unsupported=unArea,ratio=unArea/upperArea})
				end
			end
		end
	end
	if i%25==0 then task.wait() end
end
table.sort(rows,function(a,b) return a.unsupported>b.unsupported end)
_G.OverhangRows=rows
local top={}
for k=1,math.min(15,#rows) do local r=rows[k];top[k]=string.format("%s f%s unsupported %d / %d (%d%%)",r.id,tostring(r.floors),r.unsupported,r.upper,math.floor(r.ratio*100)) end
return {flagged=#rows,top=top}
