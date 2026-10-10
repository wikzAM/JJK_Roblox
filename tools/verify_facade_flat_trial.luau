-- Independent enclosure/approach checks, including the owner's missing-wall case.
local H=game:GetService("HttpService")
local R=game.ServerStorage.FacadeFlatTrialRuntime
local F=require(R.GroundFacadeFrontage)
local scene=F.Index(Vector3.new(-318,85,-751),650)
local result={buildings=0,runs=0,coverageRays=0,parking=0,stairs=0,planters=0,entries=0,unchanged=0,holes={}}
for _,m in workspace.Buildings:GetChildren() do local root=m:FindFirstChild("GroundFacadePilot")
	if root then
		result.buildings+=1
		assert(not m:GetAttribute("CrownInteresting") and not m:GetAttribute("Landmark") and m:GetAttribute("StructuralOnly"))
		local plan=H:JSONDecode(m:GetAttribute("SourceSlicePlan"))
		local expectedHeight=plan.levels[2].y-plan.levels[1].y-plan.levels[1].thickness
		for _,run in root:GetChildren() do if run:IsA("Model") then
			result.runs+=1;local cf=assert(run:GetAttribute("FacadeRunFrame"));local w=run:GetAttribute("FacadeRunWidth")
			assert(math.abs(run:GetAttribute("FacadeExpectedHeight")-expectedHeight)<.02,"Ground wall cut down to parapet height")
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
for p,v in _G.FacadeFlatOriginal do assert(p.Parent and p.CFrame==v.cf and p.Size==v.size);result.unchanged+=1 end
assert(result.buildings==3 and result.parking>=1)
local backup=game.ServerStorage.FacadeApproachTerrainBackups
assert(#backup:GetChildren()==2,"Terrain repair exceeds intended two pads")
for _,p in backup:GetChildren() do local r=H:JSONDecode(p:GetAttribute("Report"));assert(r.maxColumnChange<=1.501 and p.Before and p.After) end
assert(#workspace.Buildings:GetChildren()==2227)
result.passed=#result.holes==0
H:PostAsync("http://127.0.0.1:58997/facade_flat_verification.json",H:JSONEncode(result))
assert(result.passed,"Unintended opening in full ground enclosure; inspect saved holes")
return result
