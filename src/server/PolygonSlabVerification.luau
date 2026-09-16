--!nonstrict
-- Studio edit-mode runner. Creates disposable geometry in its own WorldModel,
-- checks actual ray collisions, then removes the entire fixture even on failure.
-- require(game.ServerScriptService.Server.PolygonSlabVerification).Run()
local Verification = {}

local function polygon(list)
	local points={}
	for _,p in list do table.insert(points,Vector2.new(p[1],p[2])) end
	return points
end

local function classifyPoint(p,points)
	local inside=false
	for i,a in points do
		local b=points[i%#points+1]
		local edge=b-a
		local closest=a+edge*math.clamp((p-a):Dot(edge)/edge:Dot(edge),0,1)
		if (p-closest).Magnitude<0.003 then return nil end
		if (a.Y>p.Y)~=(b.Y>p.Y) and p.X<(b.X-a.X)*(p.Y-a.Y)/(b.Y-a.Y)+a.X then inside=not inside end
	end
	return inside
end

-- Independent half-space check of the actual Part/WedgePart local geometry.
local function contains(part,world,eps)
	local p=part.CFrame:PointToObjectSpace(world)
	local h=part.Size/2
	if math.abs(p.X)>h.X+eps or math.abs(p.Y)>h.Y+eps or math.abs(p.Z)>h.Z+eps then return false end
	if part:IsA("WedgePart") then
		-- The slope equation is dimensionless. Normalize by its gradient to
		-- compare an actual stud distance; dividing epsilon by the longest side
		-- makes a thin wedge's tolerance hundreds of times too small.
		local gradient=math.sqrt(1/(part.Size.Y*part.Size.Y)+1/(part.Size.Z*part.Size.Z))
		return (p.Y/part.Size.Y-p.Z/part.Size.Z)/gradient<=eps
	end
	return true
end

local function fixtureCorners(part)
	local corners={}
	local half=part.Size/2
	local yz=part:IsA("WedgePart") and {{-1,-1},{-1,1},{1,1}} or {{-1,-1},{-1,1},{1,1},{1,-1}}
	for _,x in {-1,1} do
		for _,q in yz do table.insert(corners,part.CFrame:PointToWorldSpace(Vector3.new(x*half.X,q[1]*half.Y,q[2]*half.Z))) end
	end
	return corners
end

function Verification.Run()
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest before verification")
	local Slab=require(script.Parent.PolygonSlab)
	local world=Instance.new("WorldModel")
	world.Name="PolygonSlabVerificationTemporary"
	world.Parent=workspace
	local stats={fixtures=0,collisionSamples=0,parts=0,invalidRejected=0}
	local ok,err=pcall(function()
		local L=polygon({{0,0},{60,0},{60,20},{20,20},{20,60},{0,60}})
		local clockwise={}
		for i=#L,1,-1 do table.insert(clockwise,L[i]) end
		local rotated={}
		for _,p in polygon({{-30,-20},{30,-20},{30,20},{-30,20}}) do
			table.insert(rotated,Vector2.new(p.X*math.cos(0.37)-p.Y*math.sin(0.37),p.X*math.sin(0.37)+p.Y*math.cos(0.37)))
		end
		local fixtures={
			{name="rectangle",points=polygon({{0,0},{40,0},{40,20},{0,20}}),area=800,parts=1},
			{name="rotated rectangle",points=rotated,area=2400,parts=1},
			{name="right triangle",points=polygon({{0,0},{40,0},{0,20}}),area=400,parts=1},
			{name="acute triangle",points=polygon({{0,0},{60,0},{25,40}}),area=1200},
			{name="obtuse triangle",points=polygon({{0,0},{60,0},{-20,10}}),area=300},
			{name="thin acute alternative altitude",points=polygon({{0,0},{100,0},{0.00015,0.2}}),area=10,parts=2},
			{name="thin obtuse incenter split",points=polygon({{0,0},{100,0},{-0.001,0.2}}),area=10,subdivisions=1},
			{name="small boundary deviation retained",points=polygon({{0,0},{50,-0.01},{100,0},{100,100},{0,100}}),area=10000.5,vertices=5},
			{name="concave L",points=L,area=2000},
			{name="clockwise L",points=clockwise,area=2000},
			{name="deep U notch",points=polygon({{0,0},{60,0},{60,60},{40,60},{40,20},{20,20},{20,60},{0,60}}),area=2800},
			{name="redundant collinear/closed",points=polygon({{0,0},{20,0},{40,0},{40,20},{0,20},{0,0}}),area=800,parts=1},
		}
		local rng=Random.new(19381)
		for index,test in fixtures do
			local holder=Instance.new("Model"); holder.Name=test.name; holder.Parent=world
			local frame=CFrame.new(10000+index*200,5000+index*10,10000)*CFrame.Angles(0,0.53+index*0.071,0)
			local bottom,thickness=7.25,3.5
			local parts,metrics=Slab.Build(holder,test.points,bottom,thickness,frame)
			task.wait() -- allow WorldModel collision state to observe the new parts
			assert(math.abs(metrics.area-test.area)<0.02,test.name..": polygon area")
			if test.parts then assert(#parts==test.parts,test.name..": unnecessary pieces") end
			if test.subdivisions then assert(metrics.interiorSubdivisions==test.subdivisions,test.name..": exact interior subdivision not exercised") end
			if test.vertices then assert(metrics.vertexCount==test.vertices,test.name..": boundary vertex was simplified away") end
			assert(metrics.outlineModified==false,"Native-size repair must not alter the outline")
			local physicalArea=0
			for _,part in parts do
				assert((part:IsA("Part") or part:IsA("WedgePart")) and part.Anchored and part.CanCollide and part.CanQuery,"Invalid structure")
				physicalArea+=part.Size.X*part.Size.Y*part.Size.Z/(part:IsA("WedgePart") and 2 or 1)/thickness
				for _,corner in fixtureCorners(part) do
					local localPoint=frame:PointToObjectSpace(corner)
					assert(localPoint.Y>=bottom-0.01 and localPoint.Y<=bottom+thickness+0.01,test.name..": vertical extrusion")
					assert(classifyPoint(Vector2.new(localPoint.X,localPoint.Z),metrics.points)~=false,test.name..": vertex outside polygon")
				end
			end
			assert(math.abs(physicalArea-test.area)<0.02,test.name..": primitive area mismatch")
			for _,point in metrics.points do
				local worldPoint=frame:PointToWorldSpace(Vector3.new(point.X,bottom+thickness/2,point.Y))
				local covered=false
				for _,part in parts do if contains(part,worldPoint,0.02) then covered=true; break end end
				assert(covered,test.name..": missing input vertex")
			end
			local lo,hi=metrics.points[1],metrics.points[1]
			for _,point in metrics.points do lo=lo:Min(point); hi=hi:Max(point) end
			local padding=math.min(4,math.max(0.1,math.min(hi.X-lo.X,hi.Y-lo.Y)*0.25))
			local all=RaycastParams.new(); all.FilterType=Enum.RaycastFilterType.Include; all.FilterDescendantsInstances={holder}
			local one=RaycastParams.new(); one.FilterType=Enum.RaycastFilterType.Include
			for _=1,300 do
				local point=Vector2.new(rng:NextNumber(lo.X-padding,hi.X+padding),rng:NextNumber(lo.Y-padding,hi.Y+padding))
				local expected=classifyPoint(point,metrics.points)
				if expected~=nil then
					local origin=frame:PointToWorldSpace(Vector3.new(point.X,bottom+thickness+10,point.Y))
					local direction=Vector3.new(0,-(thickness+20),0)
					local hit=world:Raycast(origin,direction,all)
					assert((hit~=nil)==expected,test.name..": collision gap or filled notch at "..tostring(point))
					if hit then
						assert(math.abs(hit.Position.Y-(frame.Y+bottom+thickness))<0.02,test.name..": wrong top surface")
						local count=0
						local center=frame:PointToWorldSpace(Vector3.new(point.X,bottom+thickness/2,point.Y))
						for _,part in parts do
							one.FilterDescendantsInstances={part}
							if world:Raycast(origin,direction,one) and contains(part,center,-0.003) then count+=1 end
						end
						assert(count<=1,test.name..": overlapping piece interiors")
					end
					stats.collisionSamples+=1
				end
			end
			stats.fixtures+=1; stats.parts+=#parts
			holder:Destroy()
		end
		for _,bad in {
			polygon({{0,0},{40,40},{0,40},{40,0}}), -- crossing
			polygon({{0,0},{20,0},{40,0}}), -- zero area
			polygon({{0,0},{40,0},{20,0},{20,20},{0,20}}), -- doubled edge
			polygon({{0,0},{40,0},{40,40},{20,0},{0,40}}), -- non-adjacent touch
		} do
			assert(not pcall(Slab.Validate,bad),"Invalid polygon accepted")
			stats.invalidRejected+=1
		end
		local before=#world:GetDescendants()
		assert(not pcall(Slab.Build,world,polygon({{0,0},{0.01,0},{0.01,20},{0,20}}),0,2,CFrame.identity),"Subminimum feature expanded silently")
		assert(#world:GetDescendants()==before,"Failed build left partial parts")
		stats.invalidRejected+=1
	end)
	world:Destroy()
	assert(ok,err)
	print("POLYGON_SLAB_VERIFIED",game:GetService("HttpService"):JSONEncode(stats))
	return stats
end

return Verification
