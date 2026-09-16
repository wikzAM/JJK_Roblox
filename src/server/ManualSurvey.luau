--!nonstrict
-- Edit-time measuring aid. Screen points are chosen by a human visual survey.
-- Does not classify components or generate/alter reference geometry.
local Survey = {}
local meshes = {}
function Survey.Load(source)
	Survey.Close()
	for _, p in source:GetDescendants() do
		if p:IsA("MeshPart") then
			table.insert(meshes, {part=p, mesh=game:GetService("AssetService"):CreateEditableMeshAsync(p.MeshContent)})
		end
	end
	print("VISUAL SURVEY ready", #meshes, workspace.CurrentCamera.ViewportSize)
end
function Survey.Close()
	for _, m in meshes do m.mesh:Destroy() end
	table.clear(meshes)
end
function Survey.Ray(x, y)
	local ray = workspace.CurrentCamera:ViewportPointToRay(x,y)
	local best, distance
	for _, m in meshes do
		local p, mesh = m.part, m.mesh
		local scale = p.Size / p.MeshSize
		local origin = p.CFrame:PointToObjectSpace(ray.Origin) / scale
		local direction = p.CFrame:VectorToObjectSpace(ray.Direction * 25000) / scale
		local face, point = mesh:RaycastLocal(origin, direction)
		if face then
			local world = p.CFrame:PointToWorldSpace(point * scale)
			local d = (world-ray.Origin).Magnitude
			if not distance or d < distance then best={point=world,face=face,entry=m}; distance=d end
		end
	end
	return best
end
function Survey.Points(points)
	local result={}
	for i,p in points do
		local hit=Survey.Ray(p[1],p[2])
		if hit then
			result[i]=hit.point
			print(string.format("POINT %d %.2f %.2f %.2f",i,hit.point.X,hit.point.Y,hit.point.Z))
		else warn("POINT MISS", i) end
	end
	return result
end
function Survey.Look(target, offset)
	workspace.CurrentCamera.Focus=CFrame.new(target)
	workspace.CurrentCamera.CFrame=CFrame.lookAt(target+offset,target, math.abs(offset.Unit.Y)>.999 and Vector3.new(0,0,-1) or Vector3.yAxis)
end
function Survey.View(x,y,offset)
	local hit=assert(Survey.Ray(x,y),"No reference under selected point")
	Survey.Look(hit.point,offset)
	return hit.point
end
return Survey
