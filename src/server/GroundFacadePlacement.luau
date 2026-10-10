-- Edit-only checks against existing structure. Never moves or carves a core.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Kit=require(Shared.GroundFacadeKit)
local Frontage=require(script.Parent.GroundFacadeFrontage)
local P={MaxOutset=1.25,SurfaceClearance=.25}
local function structures(model)
	local rows={};local owned=model:FindFirstChild("GroundFacadePilot")
	for _,p in model:GetDescendants() do
		if p:IsA("BasePart") and p.CanQuery and p.Transparency<.95 and not (owned and p:IsDescendantOf(owned)) then table.insert(rows,p) end
	end
	return rows
end
function P.Fit(model,scene,cf,width,key,profile,options)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=structures(model)
	local shift,probes=0,0;local cursor=-width/2
	for _,bay in Kit.PlanRun(width,key,profile,options) do
		if not bay.infill then
			local opts=table.clone(options);opts.width=bay.width;opts.seed=bay.seed;opts.role=bay.role;opts.mirror=bay.seed%2==0
			local l=Kit.Layout(bay.id,opts);local bcf=cf*CFrame.new(cursor+bay.width/2,0,0)
			for _,row in l.parts do if row.material==Enum.Material.Glass or row.kind=="door" then
				local pc=bcf*row.cframe
				for _,x in {-.45,0,.45} do for _,y in {-.45,0,.45} do
					local q=(pc*CFrame.new(row.size.X*x,row.size.Y*y,row.size.Z/2)).Position
					local hit=workspace:Raycast(q-cf.ZVector*12,cf.ZVector*12,params);probes+=1
					if hit then shift=math.max(shift,(q-hit.Position):Dot(cf.ZVector)+P.SurfaceClearance) end
				end end
			end end
		end
		cursor+=bay.width
	end
	shift=math.ceil(shift*20)/20 -- stable .05-stud increments; no tiny coplanar flicker.
	if shift>P.MaxOutset then return nil,"Core clearance exceeds bounded facade outset",probes end
	-- Clearance includes opposed wings of the same building. Keep a narrow court quiet.
	if shift>0 and Frontage.Clearance(scene,cf,width,nil)<=shift+6 then return nil,"Outset would narrow an occupied passage",probes end
	return shift,"Glazing clear of existing structure",probes
end
-- Neighbors can extend below their own ground storey: a tall footing is a
-- real obstruction even when the source footprint survey reports an open side.
function P.NeighborBlocked(model,scene,cf,bay,options)
	local candidates={}
	for _,b in scene.buildings do
		for _,p in b.model:GetDescendants() do
			local include=b.model~=model
			if not include then
				local run=p:FindFirstAncestorOfClass("Model")
				while run and run.Parent and run.Parent.Name~="GroundFacadePilot" do run=run:FindFirstAncestorOfClass("Model") end
				include=run and run:GetAttribute("RunPiece") and (run:GetAttribute("RunPiece")~=options.sitePiece or run:GetAttribute("RunIndex")~=options.siteRun)
			end
			if include and p:IsA("BasePart") and p.CanQuery and p.Transparency<.05 and p.Material~=Enum.Material.Glass then table.insert(candidates,p) end
		end
	end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=candidates
	local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances=candidates
	local o=table.clone(options);o.width=bay.width;o.seed=bay.seed;o.role=bay.role;o.mirror=bay.seed%2==0
	for _,p in Kit.Layout(bay.id,o).parts do if p.material==Enum.Material.Glass or p.kind=="door" then
		local pc=cf*p.cframe
		for _,x in {-.4,0,.4} do for _,y in {-.4,0,.4} do
			local q=(pc*CFrame.new(p.size.X*x,p.size.Y*y,p.size.Z/2)).Position
			local hit=workspace:Raycast(q-cf.ZVector*3,cf.ZVector*3,params)
			if hit then return true,hit.Instance:GetFullName() end
		end end
		-- A thin opposed wall can fall between the nine regular samples. Project
		-- each nearby obstruction's bounds into the pane and probe that overlap.
		for _,other in workspace:GetPartBoundsInBox(pc*CFrame.new(0,0,-1.4),Vector3.new(p.size.X,p.size.Y,3.2),overlap) do
			local lo,hi=Vector3.one*math.huge,-Vector3.one*math.huge
			for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
				local q=pc:PointToObjectSpace((other.CFrame*CFrame.new(other.Size*Vector3.new(x,y,z)/2)).Position)
				lo=lo:Min(q);hi=hi:Max(q)
			end end end
			local x0,x1=math.max(lo.X,-p.size.X*.49),math.min(hi.X,p.size.X*.49)
			local y0,y1=math.max(lo.Y,-p.size.Y*.49),math.min(hi.Y,p.size.Y*.49)
			if x1>x0 and y1>y0 then
				for _,x in {x0+.001,(x0+x1)/2,x1-.001} do for _,y in {y0+.001,(y0+y1)/2,y1-.001} do
					local q=(pc*CFrame.new(x,y,p.size.Z/2)).Position
					local hit=workspace:Raycast(q-cf.ZVector*3,cf.ZVector*3,params)
					if hit then return true,hit.Instance:GetFullName() end
				end end
			end
		end
	end end
	return false
end
return P
