-- Edit-only explicit regional rollout. Requiring this module never mutates the map.
local Shared=game:GetService("ReplicatedStorage").Shared
local Catalog=require(Shared.GroundFacadeCatalog)
local Frontage=require(script.Parent.GroundFacadeFrontage)
local Section={}
local palettes={"cream","white","offwhite","grey","charcoal","darkBrown","stone"}
function Section.Select(center,radius,limit,existing)
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	assert(radius>0 and radius<=1500 and limit>=1 and limit<=300,"Bounded regional selection required")
	local scene=Frontage.Index(center,radius+400)
	local rows,known={},{}
	for _,r in existing or {} do table.insert(rows,r);known[r.id]=true end
	local candidates={}
	for _,b in scene.buildings do
		local m=b.model
		local d=(Vector3.new(b.frame.X,0,b.frame.Z)-Vector3.new(center.X,0,center.Z)).Magnitude
		if d<=radius and not known[b.id] and m:GetAttribute("StructuralOnly")==true
			and not m:GetAttribute("CrownInteresting") and not m:GetAttribute("Landmark") and not m:HasTag("Landmark") then
			table.insert(candidates,{building=b,distance=d})
		end
	end
	table.sort(candidates,function(a,b) if a.distance==b.distance then return a.building.id<b.building.id end return a.distance<b.distance end)
	for _,candidate in candidates do
		if #rows>=limit then break end
		local b=candidate.building
		local row=Frontage.Survey(scene,b)
		if #row.faces>0 then
			row.palette=palettes[Catalog.Seed("wall/"..b.id)%#palettes+1]
			row.nameSeed=Catalog.Seed("tenant/"..b.id)
			-- A broad mixed pool includes local stores, homes, services and fictional chains.
			for _,face in row.faces do if face.class=="front" then face.profile="mixed" end end
			table.insert(rows,row);known[b.id]=true
		end
		task.wait()
	end
	return rows,scene
end
return Section
