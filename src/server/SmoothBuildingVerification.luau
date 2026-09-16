--!nonstrict
-- require(game.ServerScriptService.Server.SmoothBuildingVerification).Run()
-- Disposable fixtures only; the map and its replacement archives are untouched.
local Verify={}
local SLAB,PITCH=1.5/0.28,5/0.28

local function points(values)
	local result={}
	for _,p in values do table.insert(result,Vector2.new(p[1],p[2])) end
	return result
end

local function rectangle(x0,z0,x1,z1)
	return points({{x0,z0},{x1,z0},{x1,z1},{x0,z1}})
end

local function areaOfFloor(floor)
	local area=0
	for _,part in floor:GetChildren() do
		if part:IsA("BasePart") and part.Name=="Slab" then
			area+=part.Size.X*part.Size.Y*part.Size.Z/(part:IsA("WedgePart") and 2 or 1)/SLAB
		end
	end
	return area
end

local function checkCore(model,frame,predicate,floors)
	local coreParts=0
	for _,part in model.Interior:GetDescendants() do
		if part:IsA("BasePart") and game:GetService("CollectionService"):HasTag(part,"BuildingCore") then
			coreParts+=1
			assert(part.Anchored and part.CanCollide and part:IsA("Part"),"Invalid core primitive")
			-- Independent dense footprint check against deliberate fixture geometry.
			for ix=0,8 do for iz=0,8 do
				local p=frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(part.Size.X*(ix/8-0.5),0,part.Size.Z*(iz/8-0.5))))
				assert(predicate(p.X,p.Z),"Core crosses a concave edge or upper setback")
			end end
		end
	end
	assert(coreParts==floors*6,"Core is not continuous on every floor")
end

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	local Smooth=require(script.Parent.SmoothBuildingBuilder)
	local world=Instance.new("WorldModel"); world.Name="SmoothBuildingVerificationTemporary"; world.Parent=workspace
	local cleanup={world}
	local stats={fixtures=0,invalidRejected=0,regeneration=false,wedgeCSG=false}
	local ok,err=pcall(function()
		local frame=CFrame.new(12000,5000,-12000)*CFrame.Angles(0,0.63,0)
		local rectangular={frame=frame,height=6*PITCH+SLAB,points=rectangle(-40,-30,40,30),key="verification_rect"}
		local box=Smooth.StagePlan("BuildingVerifySmoothRectangle",rectangular,6); box.Parent=world
		assert(box:GetAttribute("GeneratedFloors")==6 and box:GetAttribute("SmoothWedgeParts")==0)
		for _,floor in box.Interior:GetChildren() do assert(math.abs(areaOfFloor(floor)-4800)<0.05,"Rectangle footprint changed") end
		checkCore(box,frame,function(x,z) return math.abs(x)<=40.01 and math.abs(z)<=30.01 end,6)
		stats.fixtures+=1
		local L=points({{-50,-40},{50,-40},{50,-10},{0,-10},{0,40},{-50,40}})
		local concave={frame=frame*CFrame.new(250,0,0),height=5*PITCH+SLAB,points=L,key="verification_L"}
		local l=Smooth.StagePlan("BuildingVerifySmoothL",concave,5); l.Parent=world
		assert(l:GetAttribute("SmoothWedgeParts")>0,"Concave floor did not use wedges")
		for _,floor in l.Interior:GetChildren() do assert(math.abs(areaOfFloor(floor)-5500)<0.05,"L-shaped area/notch changed") end
		checkCore(l,concave.frame,function(x,z)
			return x>=-50.01 and x<=50.01 and z>=-40.01 and z<=40.01 and (x<=0.01 or z<=-9.99)
		end,5)
		stats.fixtures+=1
		local h=6*PITCH+SLAB
		local tiered={frame=frame*CFrame.new(500,0,0),height=h,key="verification_tiers",tiers={
			{bottom=0,top=3*PITCH,points=rectangle(-60,-50,60,50)},
			{bottom=3*PITCH,top=h,points=rectangle(-5,-25,35,25)},
		}}
		local tower=Smooth.StagePlan("BuildingVerifySmoothSetback",tiered,6); tower.Parent=world
		for _,floor in tower.Interior:GetChildren() do
			local index=tonumber(floor.Name:match("^Floor(%d+)$")) or 7
			assert(math.abs(areaOfFloor(floor)-(index<=4 and 12000 or 2000))<0.1,"Setback transition slab is incomplete")
		end
		checkCore(tower,tiered.frame,function(x,z) return x>=-5.01 and x<=35.01 and math.abs(z)<=25.01 end,6)
		stats.fixtures+=1
		local invalid={frame=frame,height=h,tiers={
			{bottom=0,top=3*PITCH,points=rectangle(-40,-40,40,40)},
			{bottom=3*PITCH,top=h,points=rectangle(20,-20,60,20)},
		}}
		assert(not pcall(Smooth.StagePlan,"BuildingVerifyInvalidOffset",invalid,6),"Unsupported offset tier accepted")
		stats.invalidRejected+=1
		local U=points({{-60,-50},{60,-50},{60,50},{20,50},{20,0},{-20,0},{-20,50},{-60,50}})
		invalid.tiers[1].points=U
		invalid.tiers[2].points=rectangle(-50,10,50,40) -- corners in both arms, edges cross the inlet
		assert(not pcall(Smooth.StagePlan,"BuildingVerifyInvalidBridge",invalid,6),"Tier edge crossed a concave inlet")
		stats.invalidRejected+=1
		invalid.tiers[2].bottom+=1
		assert(not pcall(Smooth.StagePlan,"BuildingVerifyTierGap",invalid,6),"Gap between tiers accepted")
		stats.invalidRejected+=1
		local delta=CFrame.new(30,20,-70)*CFrame.Angles(0,0.23,0)
		local beforeParts=#l.Interior:GetDescendants()
		l:PivotTo(delta*l:GetPivot())
		local regenerated,backup=Smooth.Regenerate(l)
		table.insert(cleanup,backup)
		assert(regenerated and #l.Interior:GetDescendants()==beforeParts,"Regeneration lost structure")
		assert(backup:FindFirstChild("Interior"),"Regeneration backup missing")
		checkCore(l,delta*concave.frame,function(x,z)
			return x>=-50.03 and x<=50.03 and z>=-40.03 and z<=40.03 and (x<=0.03 or z<=-9.97)
		end,5)
		local cf,size=l:GetBoundingBox()
		assert((cf.Position-l:GetAttribute("InteriorBBoxCFrame").Position).Magnitude<0.01
			and (size-l:GetAttribute("InteriorBBoxSize")).Magnitude<0.01,"Moved regeneration bbox is stale")
		stats.regeneration=true
		local wedge
		for _,p in l.Interior:GetDescendants() do if p:IsA("WedgePart") then wedge=p; break end end
		assert(wedge,"No wedge available for CSG check")
		local clone=wedge:Clone(); clone.Parent=world
		local cutter=Instance.new("Part"); cutter.Shape=Enum.PartType.Ball
		local diameter=math.min(clone.Size.X,clone.Size.Y,clone.Size.Z)*0.6
		cutter.Size=Vector3.one*diameter
		cutter.CFrame=clone.CFrame*CFrame.new(0,-clone.Size.Y/6,clone.Size.Z/6)
		cutter.Anchored=true; cutter.CanCollide=false; cutter.Parent=world
		local carved=clone:SubtractAsync({cutter})
		assert(carved and carved:IsA("UnionOperation"),"Wedge cannot be carved through CSG")
		carved:Destroy(); cutter:Destroy(); clone:Destroy()
		stats.wedgeCSG=true
	end)
	for _,item in cleanup do if item then item:Destroy() end end
	assert(ok,err)
	print("SMOOTH_BUILDING_VERIFIED",game:GetService("HttpService"):JSONEncode(stats))
	return stats
end

return Verify
