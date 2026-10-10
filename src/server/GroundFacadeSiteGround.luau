-- Explicit edit-only terrain pads. Never wired into startup or terrain generation.
-- Bounded +/-1.5-stud correction, with voxel backups and conservative road caps.
local H=game:GetService("HttpService")
local Ground={}
local OWNER="2026-10-10-facade-approaches"
local function encoded(region,materials,occupancies)
	local names,values={},{}
	for x=1,#materials do names[x]={};values[x]={};for y=1,#materials[x] do names[x][y]={};values[x][y]={};for z=1,#materials[x][y] do names[x][y][z]=materials[x][y][z].Name;values[x][y][z]=occupancies[x][y][z] end end end
	return H:JSONEncode({min={region.CFrame.Position.X-region.Size.X/2,region.CFrame.Position.Y-region.Size.Y/2,region.CFrame.Position.Z-region.Size.Z/2},max={region.CFrame.Position.X+region.Size.X/2,region.CFrame.Position.Y+region.Size.Y/2,region.CFrame.Position.Z+region.Size.Z/2},materials=names,occupancies=values})
end
local function registry()
	local r=game.ServerStorage:FindFirstChild("FacadeApproachTerrainBackups")
	if r then assert(r:GetAttribute("Owner")==OWNER,"Unowned terrain backup")
	else r=Instance.new("Folder");r.Name="FacadeApproachTerrainBackups";r:SetAttribute("Owner",OWNER);r.Parent=game.ServerStorage end
	return r
end
function Ground.LevelPad(cf,width,length,key)
	assert(not game:GetService("RunService"):IsRunning(),"Edit-only terrain repair")
	assert(width>=3 and width<=30 and length>=2 and length<=20,"Pad exceeds local repair limits")
	local reg=registry();local item=reg:FindFirstChild(key)
	if item then return H:JSONDecode(item:GetAttribute("Report")) end
	local target=cf.Position.Y-2.5;local margin=8
	local low=Vector3.new(math.huge,math.huge,math.huge);local high=-low
	for _,x in {-width/2-margin,width/2+margin} do for _,z in {-length-margin,margin} do
		local p=(cf*CFrame.new(x,-2.5,z)).Position;low=low:Min(p);high=high:Max(p)
	end end
	local region=Region3.new(Vector3.new(low.X,target-8,low.Z),Vector3.new(high.X,target+8,high.Z)):ExpandToGrid(4)
	local terrain=workspace.Terrain;local materials,occupancies=terrain:ReadVoxels(region,4)
	item=Instance.new("Folder");item.Name=key;item:SetAttribute("State","backed-up");item.Parent=reg
	local before=Instance.new("StringValue");before.Name="Before";before.Value=encoded(region,materials,occupancies);before.Parent=item
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={terrain}
	local roads=RaycastParams.new();roads.FilterType=Enum.RaycastFilterType.Include;roads.FilterDescendantsInstances=workspace:FindFirstChild("Roads") and {workspace.Roads} or {}
	local origin=region.CFrame.Position-region.Size/2;local changed=0;local maxChange=0
	for x=1,materials.Size.X do for z=1,materials.Size.Z do
		local world=Vector3.new(origin.X+(x-.5)*4,target,origin.Z+(z-.5)*4)
		local q=cf:PointToObjectSpace(world)
		local dx=math.max(0,math.abs(q.X)-width/2);local dz=math.max(0,q.Z,-length-q.Z)
		local distance=math.sqrt(dx*dx+dz*dz);local weight=math.clamp(1-distance/margin,0,1)
		local hit=weight>0 and terrain.Parent:Raycast(world+Vector3.yAxis*30,-Vector3.yAxis*70,params)
		if hit then
			local desired=hit.Position.Y+math.clamp(target-hit.Position.Y,-1.5,1.5)*weight
			local road=workspace:Raycast(world+Vector3.yAxis*30,-Vector3.yAxis*70,roads)
			if road then desired=math.min(desired,road.Position.Y-road.Instance.Size.Y-.2) end
			local delta=desired-hit.Position.Y
			-- Do not excavate a road trench; skip cells incompatible with the bound.
			if math.abs(delta)<=1.51 and math.abs(delta)>.08 then
				-- Translate the measured density profile. An absolute occupancy
				-- cutoff does not reproduce Roblox smooth terrain's visible surface.
				local original={};for y=1,materials.Size.Y do original[y]=occupancies[x][y][z] end
				for y=1,materials.Size.Y do
					local bottom=origin.Y+(y-1)*4
					if bottom>math.min(hit.Position.Y,desired)-4 and bottom<math.max(hit.Position.Y,desired)+4 then
						local sample=y-delta/4;local a=math.floor(sample);local t=sample-a
						local value=(original[math.clamp(a,1,#original)] or 0)*(1-t)+(original[math.clamp(a+1,1,#original)] or 0)*t
						-- Activating an almost-empty Air cell can move the rendered
						-- terrain boundary a whole voxel. Stay within existing surface
						-- cells for this small repair; never create a new raised layer.
						if materials[x][y][z]==Enum.Material.Air then value=0 end
						if math.abs(value-occupancies[x][y][z])>.001 then
							occupancies[x][y][z]=value;materials[x][y][z]=value>0 and Enum.Material.Asphalt or Enum.Material.Air;changed+=1
						end
					end
				end
				maxChange=math.max(maxChange,math.abs(delta))
			end
		end
	end end
	terrain:WriteVoxels(region,4,materials,occupancies)
	local am,ao=terrain:ReadVoxels(region,4);local after=Instance.new("StringValue");after.Name="After";after.Value=encoded(region,am,ao);after.Parent=item
	local result={key=key,changedVoxels=changed,maxColumnChange=maxChange,target=target,width=width,length=length}
	item:SetAttribute("Report",H:JSONEncode(result));item:SetAttribute("State","ready")
	return result
end
function Ground.Restore(keys)
	assert(not game:GetService("RunService"):IsRunning(),"Edit-only terrain restore")
	local reg=registry()
	for i=#keys,1,-1 do
		local item=assert(reg:FindFirstChild(keys[i]),"Missing terrain backup")
		local row=H:JSONDecode(item.Before.Value);local region=Region3.new(Vector3.new(table.unpack(row.min)),Vector3.new(table.unpack(row.max)))
		local materials,occupancies=workspace.Terrain:ReadVoxels(region,4)
		assert(encoded(region,materials,occupancies)==item.After.Value,"Terrain changed later; refusing to overwrite it")
		for x,col in row.materials do for y,r in col do for z,name in r do materials[x][y][z]=Enum.Material[name] end end end
		workspace.Terrain:WriteVoxels(region,4,materials,row.occupancies);item:Destroy()
	end
end
return Ground
