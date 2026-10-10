-- Edit-only v7 regression audit. No HTTP export and no map mutation.
local H=game:GetService("HttpService")
local F=require(game.ServerScriptService.Server.GroundFacadeFrontage)
local scene=F.Index(Vector3.new(-318,85,-751),750)
local opaque={}
for _,b in scene.buildings do
	for _,p in b.model:GetDescendants() do
		if p:IsA("BasePart") and p.CanQuery and p.Transparency<.05 and p.Material~=Enum.Material.Glass then
			local root=p:FindFirstAncestor("GroundFacadePilot")
			local kind=p:GetAttribute("FacadePieceKind")
			-- These two fixtures deliberately mask a portion of their own glazing.
			if p.Name~="ClinicPrivacySpandrel" and p.Name~="WorkshopHalfShutter" and
				(not root or kind=="wall" or kind=="plinth" or (not kind and p.Name~="EntryApproachStep")) then table.insert(opaque,p) end
		end
	end
	task.wait()
end
local ps=RaycastParams.new();ps.FilterType=Enum.RaycastFilterType.Include;ps.FilterDescendantsInstances=opaque
local out={buildings=0,runs=0,panes=0,visibilityRays=0,blocked={},palettes={},portals=0,stairs=0,planters=0,parking=0,unchanged=0,maxOutset=0}
for _,b in scene.buildings do
	local root=b.model:FindFirstChild("GroundFacadePilot")
	if root then
		out.buildings+=1;local palette=root:GetAttribute("Palette");out.palettes[palette]=(out.palettes[palette] or 0)+1
		for _,run in root:GetChildren() do if run:IsA("Model") then
			out.runs+=1;local offset=run:GetAttribute("FacadeOutset") or 0;out.maxOutset=math.max(out.maxOutset,offset)
			assert(offset>=0 and offset<=1.25,"Facade moved inward or beyond bounded outset")
			local cf=run:GetAttribute("FacadeRunFrame");local source=run:GetAttribute("FacadeSourceFrame")
			assert(math.abs(source:PointToObjectSpace(cf.Position).Z+offset)<.01,"Wrong offset direction")
		end end
		for _,p in root:GetDescendants() do
			if p:IsA("Model") and p:GetAttribute("FacadePortals") then out.portals+=#H:JSONDecode(p:GetAttribute("FacadePortals")) end
			if p:IsA("BasePart") then
				if p:HasTag("GlassPane") then
					out.panes+=1;assert(p:GetAttribute("GlassState")==1 and p.Transparency<1)
					for _,x in {-.35,0,.35} do for _,y in {-.35,0,.35} do
						local q=(p.CFrame*CFrame.new(p.Size.X*x,p.Size.Y*y,p.Size.Z/2)).Position
						local hit=workspace:Raycast(q-p.CFrame.ZVector*3,p.CFrame.ZVector*3.05,ps);out.visibilityRays+=1
						if hit then table.insert(out.blocked,{pane=p:GetFullName(),blocker=hit.Instance:GetFullName()}) end
					end end
				elseif p.Name=="EntryApproachStep" then
					out.stairs+=1
					for _,x in {-p.Size.X/2,0,p.Size.X/2} do for _,z in {-p.Size.Z/2,0,p.Size.Z/2} do
						local ground=F.Ground(p.CFrame,x,z);assert(ground and p.Position.Y-p.Size.Y/2<=ground+.12,"Floating stair")
					end end
				elseif p:GetAttribute("FacadeSupportBase") then
					out.planters+=1;assert(math.abs(p.Position.Y-p.Size.Y/2-p:GetAttribute("FacadeSupportGroundY")-.02)<.05,"Floating planter")
				elseif p.Name=="GarageApproachRamp" then
					out.parking+=1;assert(p:IsA("WedgePart") and p.Parent:FindFirstChild("GarageRampSolidBase"))
				end
			end
		end
	end
	task.wait()
end
for p,v in _G.FacadeV7Original or {} do assert(p.Parent and p.CFrame==v.cf and p.Size==v.size and p.Color==v.color,"Original source changed");out.unchanged+=1 end
assert(out.buildings==32 and out.runs==228 and out.parking>=1)
assert(#out.blocked==0,"An opening is hidden by opaque geometry")
return out
