-- Run in Studio EDIT mode after sync. Synthetic fixtures never touch map buildings.
local server=game.ServerScriptService.Server
local Box=require(server.ShibuyaBoxBuilder)
local Generator=require(server.BuildingGenerator)
local function fixture(cf,size)
	local vertices={}
	for _,v in {Vector3.new(-1,-1,-1),Vector3.new(1,-1,-1),Vector3.new(1,-1,1),Vector3.new(-1,-1,1),
		Vector3.new(-1,1,-1),Vector3.new(1,1,-1),Vector3.new(1,1,1),Vector3.new(-1,1,1)} do
		table.insert(vertices,cf:PointToWorldSpace(v*size/2))
	end
	local g={triangles={},min=vertices[1],max=vertices[1]}
	for _,v in vertices do g.min=g.min:Min(v); g.max=g.max:Max(v) end
	for _,face in {{1,2,3,4},{5,8,7,6},{1,5,6,2},{2,6,7,3},{3,7,8,4},{4,8,5,1}} do
		table.insert(g.triangles,{vertices[face[1]],vertices[face[2]],vertices[face[3]]})
		table.insert(g.triangles,{vertices[face[1]],vertices[face[3]],vertices[face[4]]})
	end
	return g
end

for _,yaw in {0,0.13,0.71,1.43} do
	local cf=CFrame.new(120,85,-300)*CFrame.Angles(0,yaw,0)
	local size=Vector3.new(83.3,110,51.7) -- deliberately not grid multiples
	local g=fixture(cf,size)
	local plan,reason=Box.Classify(g)
	assert(plan,reason)
	assert(math.abs(plan.size.X*plan.size.Z-size.X*size.Z)<0.1,"Rotated footprint area changed")
	assert((plan.cf.Position-cf.Position).Magnitude<0.1,"Center shifted")
	local model=Instance.new("Model"); model.Name="BuildingBoxVerification"
	model:SetAttribute("StructuralOnly",true)
	local ok,err=pcall(function()
		assert(Generator.GenerateBox(model,plan.cf,plan.size))
		local levels=0
		for _,floor in model.Interior:GetChildren() do
			local slabs=0
			for _,p in floor:GetChildren() do
				if p.Name=="Slab" then
					slabs+=1
					assert(p:IsA("Part") and p.Anchored and p.CanCollide,"Invalid slab")
					assert(math.abs(p.Size.X*p.Size.Z-size.X*size.Z)<0.1,"Clipped/stepped floor")
				end
			end
			assert(slabs==1,"Each level must have exactly one full slab")
			levels+=1
		end
		assert(levels==model:GetAttribute("GeneratedFloors")+1,"Missing floor/roof")
		assert(model:GetAttribute("CoreSize"),"Missing core")
	end)
	model:Destroy()
	assert(ok,err)
	-- Open facade must fail closure instead of producing a floating floor.
	table.remove(g.triangles,8); table.remove(g.triangles,7)
	assert(Box.Classify(g)==nil,"Open body accepted")
end
-- Triangular prism must be deferred, even if its bounding box looks ordinary.
local wedge={min=Vector3.new(0,0,0),max=Vector3.new(100,100,100),triangles={}}
local a,b,c=Vector3.new(0,0,0),Vector3.new(100,0,0),Vector3.new(0,0,100)
local up=Vector3.new(0,100,0)
table.insert(wedge.triangles,{a,b,c}); table.insert(wedge.triangles,{a+up,c+up,b+up})
for _,edge in {{a,b},{b,c},{c,a}} do
	local p,q=edge[1],edge[2]
	table.insert(wedge.triangles,{p,q,q+up}); table.insert(wedge.triangles,{p,q+up,p+up})
end
assert(Box.Classify(wedge)==nil,"Triangular building was simplified to a box")
print("BOX_VERIFICATION_PASSED: rotated boxes, exact slabs, core, open facade and triangle rejection")
