-- Independent enclosure/approach checks, including the owner's missing-wall case.
local H=game:GetService("HttpService")
local R=game.ServerStorage.FacadeSectionRuntime
local F=require(R.GroundFacadeFrontage)
local scene=F.Index(Vector3.new(-318,85,-751),750)
local result={buildings=0,runs=0,coverageRays=0,parking=0,stairs=0,planters=0,entries=0,unchanged=0,holes={},occluded={},jointRays=0,outsets=0,cornerConnections=0,paneVolumes=0}
for _,m in workspace.Buildings:GetChildren() do local root=m:FindFirstChild("GroundFacadePilot")
	if root then
		result.buildings+=1
		assert(not m:GetAttribute("CrownInteresting") and not m:GetAttribute("Landmark") and m:GetAttribute("StructuralOnly"))
		local plan=H:JSONDecode(m:GetAttribute("SourceSlicePlan"))
		local expectedHeight=plan.levels[2].y-plan.levels[1].y-plan.levels[1].thickness
		for _,run in root:GetChildren() do if run:IsA("Model") then
			result.runs+=1;local cf=assert(run:GetAttribute("FacadeRunFrame"));local w=run:GetAttribute("FacadeRunWidth")
			assert(math.abs(run:GetAttribute("FacadeExpectedHeight")-expectedHeight)<.02,"Ground wall cut down to parapet height")
			assert((run:GetAttribute("FacadeOutset") or 0)<=1.25)
            if (run:GetAttribute("FacadeOutset") or 0)>0 then result.outsets+=1;assert(run:FindFirstChild("FacadeOutsetReturn")) end
            -- Both ends must physically connect the source footprint to the
            -- visible offset plane; face rays alone cannot prove corner closure.
            local sourceFrame=assert(run:GetAttribute("FacadeSourceFrame"))
            for _,x in {-w/2,w/2} do
                local outline=(sourceFrame*CFrame.new(x,expectedHeight/2,.75)).Position
                local surface=(cf*CFrame.new(x,expectedHeight/2,0)).Position
                local connected=false
                for _,p in run:GetChildren() do if p:IsA("BasePart") and p.Name=="FacadeOutsetReturn" then
                    local a=p.CFrame:PointToObjectSpace(outline)
                    local b=p.CFrame:PointToObjectSpace(surface)
                    local half=p.Size/2+Vector3.one*.001
                    if math.abs(a.X)<=half.X and math.abs(a.Y)<=half.Y and math.abs(a.Z)<=half.Z
                        and math.abs(b.X)<=half.X and math.abs(b.Y)<=half.Y and math.abs(b.Z)<=half.Z then connected=true end
                end end
                assert(connected,"Disconnected offset corner: "..m.Name.."/"..run.Name)
                result.cornerConnections+=1
            end
            local portals={}
			for _,bay in run:GetChildren() do if bay:IsA("Model") and bay:GetAttribute("FacadePortals") then
				for _,p in H:JSONDecode(bay:GetAttribute("FacadePortals")) do
					result.entries+=1
					assert(run:GetAttribute("RoadClass"),"Entry lacks street proof")
					if p.name=="parking" or p.name=="loading" then
						assert(F.OpenDepth(m,bay:GetPivot()*CFrame.new(p.x,0,0),p.width+.5,22),"Core obstructs parking")
						local position=cf:PointToObjectSpace((bay:GetPivot()*CFrame.new(p.x,0,0)).Position)
						table.insert(portals,{x=position.X,width=p.width,height=p.height,y=p.y})
					end
				end
			end end
			local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={run}
			local n=math.max(2,math.ceil(w/2))
			for i=0,n do local x=-w/2+.1+(w-.2)*i/n
				for _,y in {.25,expectedHeight*.25,expectedHeight*.5,expectedHeight*.75,expectedHeight-.1} do
					local intended=false
					for _,p in portals do if math.abs(x-p.x)<p.width/2-.05 and y>p.y and y<p.y+p.height then intended=true end end
					if not intended then
						result.coverageRays+=1
						local hit=workspace:Raycast((cf*CFrame.new(x,y,-4)).Position,cf.ZVector*10,params)
						if not hit then table.insert(result.holes,{id=m:GetAttribute("SourceSliceId"),piece=run:GetAttribute("RunPiece"),run=run:GetAttribute("RunIndex"),x=x,y=y}) end
					end
				end
			end
		end end

        local source={};for _,p in m:GetDescendants() do if p:IsA("BasePart") and p.CanCollide and not p:HasTag("NoCSG") and not p:IsDescendantOf(root) then table.insert(source,p) end end
        local coreParams=RaycastParams.new();coreParams.FilterType=Enum.RaycastFilterType.Include;coreParams.FilterDescendantsInstances=source
        local volumeParams=OverlapParams.new();volumeParams.FilterType=Enum.RaycastFilterType.Include;volumeParams.FilterDescendantsInstances=source;volumeParams.MaxParts=0
        for _,p in root:GetDescendants() do if p:IsA("BasePart") and p:HasTag("GlassPane") then
            result.paneVolumes+=1
            assert(#workspace:GetPartsInPart(p,volumeParams)==0,"Source volume intersects pane: "..m.Name.."/"..p.Name)
            for _,x in {-.45,0,.45} do for _,y in {-.45,0,.45} do
                local q=(p.CFrame*CFrame.new(p.Size.X*x,p.Size.Y*y,p.Size.Z/2)).Position
                local hit=workspace:Raycast(q-p.CFrame.ZVector*12,p.CFrame.ZVector*12,coreParams)
                if hit then table.insert(result.occluded,{id=m:GetAttribute("SourceSliceId"),pane=p.Name,wall=hit.Instance.Name}) end
            end end
        end end
        -- Probe sub-stud pane/frame joints that a two-stud wall sampling grid misses.
        for _,bay in root:GetDescendants() do if bay:IsA("Model") and bay:GetAttribute("FacadeType") then
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={bay}
            for _,p in bay:GetDescendants() do if p:IsA("BasePart") and p:HasTag("GlassPane") and p:GetAttribute("FacadePieceKind")=="glass" and p.Size.X>.3 then
                for _,edge in {-1,1} do
                    local q=(p.CFrame*CFrame.new(edge*(p.Size.X/2+.035),0,-4)).Position
                    result.jointRays+=1
                    assert(workspace:Raycast(q,p.CFrame.ZVector*10,params),"Open pane/frame joint: "..m.Name.."/"..bay.Name.."/"..p.Name)
                end
            end end
        end end
		for _,p in root:GetDescendants() do if p:IsA("BasePart") then
			if p.Name=="GarageApproachRamp" then
				assert(p:IsA("WedgePart"),"Vehicle ramp is a sheet")
				assert(p:GetAttribute("FacadeApproachRise")<=4 and p:GetAttribute("FacadeApproachLength")<=20)
				assert(p.Parent:FindFirstChild("GarageRampSolidBase"),"Wedge lacks ground support")
				result.parking+=1
			elseif p.Name=="EntryApproachStep" then
				local bottom=p.Position.Y-p.Size.Y/2
				for _,x in {-p.Size.X/2,0,p.Size.X/2} do for _,z in {-p.Size.Z/2,0,p.Size.Z/2} do
					local y=F.Ground(p.CFrame,x,z)
					assert(y and bottom<=y+.12,"Floating stair corner")
				end end
				result.stairs+=1
			elseif p:GetAttribute("FacadeSupportBase") then
				assert(p:GetAttribute("FacadeSupportMode")=="grounded-assembly")
				assert(math.abs(p.Position.Y-p.Size.Y/2-p:GetAttribute("FacadeSupportGroundY")-.02)<.05)
				result.planters+=1
			end
		end end
	end
end
for p,v in _G.FacadeSectionOriginal do assert(p.Parent and p.CFrame==v.cf and p.Size==v.size);result.unchanged+=1 end
assert(result.buildings==32 and result.parking>=1)
local backup=game.ServerStorage.FacadeApproachTerrainBackups
assert(#backup:GetChildren()==2,"Terrain repair exceeds intended two pads")
for _,p in backup:GetChildren() do local r=H:JSONDecode(p:GetAttribute("Report"));assert(r.maxColumnChange<=1.501 and p.Before and p.After) end
assert(#workspace.Buildings:GetChildren()==2227)
result.passed=#result.holes==0 and #result.occluded==0
H:PostAsync("http://127.0.0.1:58997/facade_section_verification.json",H:JSONEncode(result))
assert(result.passed,"Unintended opening in full ground enclosure; inspect saved holes")
return result
