--!nonstrict
-- Explicit Edit preview only. Never required by the server entry point.
local Shared=game:GetService("ReplicatedStorage").Shared
local Geometry=require(Shared.GroundFacadeInteriorGeometry)
local GlassVisual=require(Shared.GlassVisual)
local Layout=require(Shared.FacadeLayout)
local Http=game:GetService("HttpService")
local T={}
local function add(parent,name,cf,size,color,shape)
	local p=Instance.new(shape or "Part");p.Name=name;p.CFrame=cf;p.Size=size;p.Color=color
	p.Material=Enum.Material.SmoothPlastic;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
	p.CastShadow=false;p:SetAttribute("FacadeLayer","interior");p:SetAttribute("FacadePieceKind","preview")
	p:SetAttribute("FacadeInteriorTrialPart",true);p:AddTag("NoCSG");p.Parent=parent;return p
end
local function pointIn(x,z,ring)
	local inside=false
	for i,a in ring do local b=ring[i%#ring+1]
		if (a[2]>z)~=(b[2]>z) and x<(b[1]-a[1])*(z-a[2])/(b[2]-a[2])+a[1] then inside=not inside end
	end
	return inside
end
local function garageFits(m,cf,width,height,depth,bay)
	local interior=m:FindFirstChild("Interior");if not interior then return false end
	local plan=Http:JSONDecode(m:GetAttribute("SourceSlicePlan") or m:GetAttribute("FacadeSourcePlan"))
	local frame=Layout.FrameOf(m);local filter=RaycastParams.new()
	filter.FilterType=Enum.RaycastFilterType.Include;filter.FilterDescendantsInstances={interior}
	local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances={workspace.Buildings}
	for _,p in workspace:GetPartBoundsInBox(cf*CFrame.new(0,height/2,depth/2+.6),Vector3.new(width,height-.5,depth),overlap) do
		if not p:IsDescendantOf(bay) and (p.CanCollide or p:GetAttribute("FacadeInteriorTrialPart")) then return false end
	end
	for z=1,depth,2 do for _,x in {-width/2,0,width/2} do
		local world=(cf*CFrame.new(x,0,z)).Position;local localPoint=frame:PointToObjectSpace(world);local inside=false
		for _,ring in plan.levels[1].pieces do if pointIn(localPoint.X,localPoint.Z,ring) then inside=true break end end
		if not inside then return false end
		local hit=workspace:Raycast(world+Vector3.yAxis*.25,-Vector3.yAxis*.8,filter)
		if not hit or not hit.Instance.CanCollide or math.abs(hit.Position.Y-world.Y)>.3 then return false end
	end end
	return true
end
function T.Apply(models,options)
	assert(not game:GetService("RunService"):IsRunning(),"Edit-only trial")
	options=options or {};local limit=options.maxInlets or 48
	assert(#models<=12 and limit<=96,"Bounded explicit trial only")
	local report={models=#models,inlets=0,blocked=0,garages=0,garageDepths={},parts=0}
	for _,m in models do
		local root=assert(m:FindFirstChild("GroundFacadePilot"),"Missing owned facade")
		assert(root:GetAttribute("Owner")=="2026-10-08-ground-pilot","Unowned facade")
		m:SetAttribute("FacadeInteriorTrial",true)
		local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include
		local sourceInterior=assert(m:FindFirstChild("Interior"),"Missing source interior")
		overlap.FilterDescendantsInstances={sourceInterior}
		local modelInlets=0
		for _,pane in root:GetDescendants() do
			if report.inlets>=limit or modelInlets>=math.ceil(limit/#models) then break end
			if pane:IsA("BasePart") and pane:HasTag("GlassPane") and not pane:GetAttribute("GlassInteriorStaticVersion") and (not options.panes or options.panes[pane]) then
				local cell=Geometry.Plan(pane,root)
				if cell then
					local rows=Geometry.Rows(cell,report.inlets*337+19);local stage={};local clear=true
					for _,row in rows do if not row.name:find("Display") then
						local p=add(pane,row.name,pane.CFrame*row.cframe,row.size,row.color,row.shape)
						p:SetAttribute("GlassAttachedOverlay",true);table.insert(stage,p)
						for _,hit in workspace:GetPartsInPart(p,overlap) do if hit.CanCollide then clear=false break end end
					end end
					if clear then
						for _,back in pane:GetChildren() do if back:IsA("BasePart") and back.Name=="InteriorWindowBacking" then
							back:SetAttribute("InteriorBeforeTransparency",back.Transparency);back:SetAttribute("InteriorBeforeFilmTransparency",back:GetAttribute("GlassFilmTransparency"))
							back.Transparency=1;back:SetAttribute("GlassFilmTransparency",1)
						end end
						GlassVisual.SetInteriorView(pane,true)
						pane:SetAttribute("GlassInteriorStaticVersion",1);report.inlets+=1;modelInlets+=1;report.parts+=#stage
					else for _,p in stage do p:Destroy() end;report.blocked+=1 end
				end
			end
		end
		for _,bay in root:GetDescendants() do if bay:IsA("Model") and bay:GetAttribute("FacadePortals") and not bay:FindFirstChild("GarageInteriorTrial") then
			local bays=Http:JSONDecode(bay:GetAttribute("FacadePortals"));local holder
			for _,portal in bays do if portal.name=="parking" or portal.name=="loading" then
				local cf=bay:GetPivot()*CFrame.new(portal.x,portal.y or 0,0);local width=portal.width-.5;local height=portal.height-.3;local depth
				for _,candidate in {48,36,28,24} do if garageFits(m,cf,width,height,candidate,bay) then depth=candidate break end end
				if depth then
					if not holder then holder=Instance.new("Folder");holder.Name="GarageInteriorTrial";holder.Parent=bay end
					local color=Color3.fromRGB(119,121,117)
					add(holder,"GarageRear",cf*CFrame.new(0,height/2,depth),Vector3.new(width,height,.14),color)
					for _,side in {-1,1} do add(holder,"GarageSide",cf*CFrame.new(side*width/2,height/2,depth/2),Vector3.new(.12,height,depth),color) end
					for _,x in {-width*.39,width*.39} do add(holder,"ParkingLine",cf*CFrame.new(x,.045,depth/2),Vector3.new(.08,.025,depth-2),Color3.fromRGB(231,231,220)) end
					holder:SetAttribute("Depth",depth);holder:SetAttribute("ExistingFloorVerified",true)
					report.garages+=1;report.parts+=5;table.insert(report.garageDepths,depth)
				end
			end end
		end end
		task.wait()
	end
	return report
end
return T
