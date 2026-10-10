-- Edit-only checks against existing structure. Never moves or carves a core.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Kit=require(Shared.GroundFacadeKit)
local Frontage=require(script.Parent.GroundFacadeFrontage)
local P={MaxOutset=1.25,SurfaceClearance=.25}
local function structures(model)
	local rows={};local owned=model:FindFirstChild("GroundFacadePilot")
	for _,p in model:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide and not p:HasTag("NoCSG") and not (owned and p:IsDescendantOf(owned)) then table.insert(rows,p) end
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
return P
