-- Edit-only, read-only site survey. OSM road parts are evidence, never regenerated.
local Shared=game:GetService("ReplicatedStorage").Shared
local Layout=require(Shared.FacadeLayout)
local Http=game:GetService("HttpService")
local Frontage={}
Frontage.MAX_ENTRY_RISE=4
Frontage.MAX_FRONT_GROUND_RANGE=2
local function inside(p,ring)
	local yes=false
	for i,a in ring do local b=ring[i%#ring+1]
		if (a[2]>p.Z)~=(b[2]>p.Z) and p.X<(b[1]-a[1])*(p.Z-a[2])/(b[2]-a[2])+a[1] then yes=not yes end
	end
	return yes
end
function Frontage.Index(center,radius)
	local scene={buildings={},roads={}}
	for _,m in workspace.Buildings:GetChildren() do
		local encoded=m:GetAttribute("SourceSlicePlan")
		if encoded then
			local frame=Layout.FrameOf(m)
			if frame and (Vector3.new(frame.X,0,frame.Z)-Vector3.new(center.X,0,center.Z)).Magnitude<radius then
				local plan=Http:JSONDecode(encoded)
				table.insert(scene.buildings,{model=m,frame=frame,plan=plan,id=m:GetAttribute("SourceSliceId")})
			end
		end
	end
	local roads=workspace:FindFirstChild("Roads")
	if roads then for _,p in roads:GetDescendants() do
		if p:IsA("BasePart") and (p.Position-center).Magnitude<radius+p.Size.Magnitude/2 then table.insert(scene.roads,p) end
	end end
	return scene
end
function Frontage.Occupied(scene,point,exclude)
	for _,b in scene.buildings do if b.model~=exclude then
		local q=b.frame:PointToObjectSpace(point)
		for _,ring in b.plan.levels[1].pieces do if inside(q,ring) then return b.id end end
	end end
	return nil
end
function Frontage.Clearance(scene,cf,width,exclude)
	local nearest=100
	-- Small sampling step in close gaps; evaluate the entire run, not only its centre.
	for _,x in {-width*.46,-width*.23,0,width*.23,width*.46} do
		for _,d in {1,2,3,4,6,8,12,18,24,36,48,64,90} do
			if Frontage.Occupied(scene,(cf*CFrame.new(x,3,-d)).Position,exclude) then nearest=math.min(nearest,d);break end
		end
	end
	return nearest
end
function Frontage.Road(scene,cf,width,exclude)
	local best
	for _,road in scene.roads do
		local localPoint=road.CFrame:PointToObjectSpace(cf.Position)
		local nearest=road.CFrame:PointToWorldSpace(Vector3.new(math.clamp(localPoint.X,-road.Size.X/2,road.Size.X/2),0,math.clamp(localPoint.Z,-road.Size.Z/2,road.Size.Z/2)))
		local q=cf:PointToObjectSpace(nearest)
		local distance=Vector3.new(q.X,0,q.Z).Magnitude
		if q.Z<-.4 and distance<75 and math.abs(q.X)<width/2+24 then
			local delta=nearest-cf.Position;local clear=true
			for t=.08,1,.08 do if Frontage.Occupied(scene,cf.Position+delta*t,exclude) then clear=false;break end end
			if clear and (not best or distance<best.distance) then best={distance=distance,class=road:GetAttribute("RoadClass") or "unknown",way=road:GetAttribute("RoadWay"),point={nearest.X,nearest.Y,nearest.Z}} end
		end
	end
	return best
end
function Frontage.Ground(cf,x,z)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
	local list={workspace.Terrain};if workspace:FindFirstChild("Roads") then table.insert(list,workspace.Roads) end
	params.FilterDescendantsInstances=list
	local point=(cf*CFrame.new(x,0,z)).Position
	local hit=workspace:Raycast(point+Vector3.yAxis*40,-Vector3.yAxis*200,params)
	return hit and hit.Position.Y or nil
end
function Frontage.OpenDepth(model,cf,width,depth)
	local interior=model:FindFirstChild("Interior")
	if not interior then return false,"No verified interior" end
	local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={interior}
	local box=cf*CFrame.new(0,4,depth/2+.8)
	for _,p in workspace:GetPartBoundsInBox(box,Vector3.new(width,6,depth),params) do
		if p.CanCollide then return false,p.Name end
	end
	return true,"Verified clear interior"
end
function Frontage.Survey(scene,b)
	-- Ground enclosure is full-height even where the generic curtain-wall layout
	-- describes a setback parapet. Do not change upper-floor glass rules.
	local config=table.clone(Layout.CONFIG)
	config.inset=0 -- Ground kit has its own reveals; never inherit the upper glass inset.
	local levels=b.plan.levels
	config.parapet=levels[2] and (levels[2].y-levels[1].y-levels[1].thickness+.3) or 12.8
	local frame=Layout.FrameOf(b.model);local strips=Layout.Build(b.plan,config)
	local result={id=b.id,faces={},frame={frame:GetComponents()}}
	for _,s in strips do if s.storey==1 then
		local ring=b.plan.levels[1].pieces[s.piece];local area=0
		for i,a in ring do local v=ring[i%#ring+1];area+=a[1]*v[2]-v[1]*a[2] end
		local world=frame*s.cframe;local normal=area>0 and world.LookVector or -world.LookVector
		local tangent=area>0 and world.XVector or -world.XVector
		local bottom=world.Position-Vector3.yAxis*(s.size.Y/2-.15)+normal*.75
		local cf=CFrame.fromMatrix(bottom,tangent,Vector3.yAxis);local width=s.size.X
		-- Other wings of this same building also block an approach in a narrow court.
		local clearance=Frontage.Clearance(scene,cf,width,nil);local road=Frontage.Road(scene,cf,width,nil)
		local class,reason="window","Open secondary elevation; no road proof"
		if clearance<=4 then class="blind";reason="Neighbor too close for an entrance"
		elseif clearance>=8 and width>=14 and (road or clearance>=12) then
			class="front";reason=road and ("Visible approach to existing "..road.class.." road") or "Open pedestrian approach; doorway ground checked per bay"
		elseif clearance<12 then class="window";reason="Restricted gap: quiet windows without entrances"
		end
		local ground=Frontage.Ground(cf,0,-2);local gap=ground and math.max(0,bottom.Y-ground) or 0
		local samples={};local lo,hi=math.huge,-math.huge
		for _,x in {-width*.49,-width*.25,0,width*.25,width*.49} do for _,z in {-1,-3,-6} do
			local y=Frontage.Ground(cf,x,z)
			if y then lo=math.min(lo,y);hi=math.max(hi,y);table.insert(samples,{x=x,z=z,y=y}) end
		end end
		local range=hi> -math.huge and hi-lo or 100
		local maxRise=lo<math.huge and math.max(0,bottom.Y-lo) or 100
		local highOnly=false
		-- A slope across a long face does not disqualify a locally level doorway.
		-- safePortal still enforces the bounded rise/range at each actual entrance.
		if class~="blind" and (hi>bottom.Y+.3 or maxRise>Frontage.MAX_ENTRY_RISE) then
			if hi<bottom.Y+(s.size.Y-.3)*.65-.5 then
				class="window";highOnly=true;reason="Raised ground: high windows, no oversized approach"
			else class="blind";reason="Ground covers usable window height" end
		end
		if not ground and class=="front" then class="window";reason="No verified approach ground" end
		table.insert(result.faces,{piece=s.piece,run=s.run,kind=s.kind,width=width,height=s.size.Y-.3,frame={cf:GetComponents()},clearance=clearance,road=road,class=class,reason=reason,type=highOnly and "41_HighSlit" or nil,groundGap=gap,groundRange=range,maxRise=maxRise,groundSamples=samples})
	end end
	return result
end
return Frontage
