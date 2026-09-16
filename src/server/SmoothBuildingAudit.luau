--!nonstrict
-- Read-only: require(game.ServerScriptService.Server.SmoothBuildingAudit).Run(workspace.Buildings)
-- summary is JSON-safe. badModels entries retain exact model objects + reasons.
local Audit={}
local Collection=game:GetService("CollectionService")
local CORE_NAMES={CoreWallFront=true,CoreWallBack=true,CoreWallRight=true,
	CoreWallLeft=true,CoreDividerX=true,CoreDividerZ=true}

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function positive(v)
	return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) and v.X>0 and v.Y>0 and v.Z>0
end
local function validFrame(cf)
	if typeof(cf)~="CFrame" then return false end
	for _,n in {cf:GetComponents()} do if not finite(n) then return false end end
	return true
end

local function inspect(model,summary)
	local reasons,seenReasons={},{}
	local function bad(reason)
		if not seenReasons[reason] then seenReasons[reason]=true; table.insert(reasons,reason) end
	end
	local interior=model:FindFirstChild("Interior")
	if not interior or not interior:IsA("Model") then bad("Missing Interior model") end
	local n=model:GetAttribute("GeneratedFloors")
	if not finite(n) or n<1 or n%1~=0 or n>=200 then bad("Invalid GeneratedFloors count"); n=0 end
	summary.plannedFloors+=n
	local coreCF,coreSize=model:GetAttribute("CoreCFrame"),model:GetAttribute("CoreSize")
	local coreValid=validFrame(coreCF) and positive(coreSize)
	if not coreValid then bad("Missing or invalid core bounds") end
	local floors,knownFloors={},{}
	if interior then
		for _,child in interior:GetChildren() do
			local index=tonumber(child.Name:match("^Floor(%d+)$"))
			if index or child.Name=="Roof" then
				if not child:IsA("Model") then bad(child.Name.." is not a Model") end
				if knownFloors[child.Name] then bad("Duplicate "..child.Name) end
				if index and (index<1 or index>n) then bad("Unexpected "..child.Name) end
				knownFloors[child.Name]=child
				floors[child]={name=child.Name,index=index,slabs=0,coreNames={},coreCount=0}
			end
		end
	end
	local baselineCore={}
	local counts={parts=0,structuralParts=0,wedges=0,slabParts=0,coreParts=0,floors=0}
	for _,part in model:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		counts.parts+=1
		if not part.Anchored then bad("Unanchored part: "..part.Name) end
		local structural=not Collection:HasTag(part,"NoCSG")
		if not structural then summary.decorationParts+=1; continue end
		counts.structuralParts+=1
		if part:IsA("WedgePart") then counts.wedges+=1
		elseif not part:IsA("Part") then bad("Unexpected structural class: "..part.ClassName) end
		if not part.CanCollide then bad("Non-collidable structural part: "..part.Name) end
		if not positive(part.Size) or math.min(part.Size.X,part.Size.Y,part.Size.Z)<0.05-1e-6 then bad("Invalid/minimum size: "..part.Name) end
		if not validFrame(part.CFrame) then bad("Nonfinite part frame: "..part.Name) end
		local ancestor=part.Parent
		while ancestor and ancestor~=model and not floors[ancestor] do ancestor=ancestor.Parent end
		local floor=floors[ancestor]
		if not floor then bad("Structural part outside a named floor/roof: "..part.Name) end
		if part.Name=="Slab" then
			counts.slabParts+=1
			if part:GetAttribute("PolygonSlab")~=true then bad("Slab lacks exact PolygonSlab marker")
			elseif floor then floor.slabs+=1 end
			local up=part:IsA("WedgePart") and math.abs(part.CFrame.RightVector.Y) or math.abs(part.CFrame.UpVector.Y)
			if up<0.9999 then bad("Slab thickness axis is not vertical") end
		end
		if Collection:HasTag(part,"BuildingCore") then
			counts.coreParts+=1
			if not floor or not floor.index then bad("Core part outside an occupied floor")
			else
				floor.coreCount+=1
				floor.coreNames[part.Name]=(floor.coreNames[part.Name] or 0)+1
			end
			if not CORE_NAMES[part.Name] then bad("Unexpected core part: "..part.Name) end
			if coreValid then
				local relative=coreCF:ToObjectSpace(part.CFrame)
				local planar=Vector2.new(relative.X,relative.Z)
				if baselineCore[part.Name] and (planar-baselineCore[part.Name]).Magnitude>0.03 then bad("Core shifts between floors: "..part.Name)
				else baselineCore[part.Name]=planar end
				if math.abs(relative.X)>coreSize.X/2+1 or math.abs(relative.Z)>coreSize.Z/2+1
					or math.abs(relative.Y)+part.Size.Y/2>coreSize.Y/2+0.05 then bad("Core geometry disagrees with stored bounds") end
				if math.abs(relative.UpVector.Y)<0.9999 then bad("Core wall is not upright") end
			end
		end
	end
	for k=1,n do
		local name="Floor"..k
		local object=knownFloors[name]
		local floor=object and floors[object]
		if not floor then bad("Missing "..name)
		else
			if floor.slabs==0 then bad(name.." has no exact polygon slab")
			else counts.floors+=1 end
			if floor.coreCount~=6 then bad(name.." does not have all six core pieces") end
			for coreName in CORE_NAMES do if floor.coreNames[coreName]~=1 then bad(name.." missing/duplicate "..coreName) end end
		end
	end
	local roof=knownFloors.Roof and floors[knownFloors.Roof]
	if not roof then bad("Missing Roof")
	elseif roof.slabs==0 then bad("Roof has no exact polygon slab")
	else summary.roofs+=1 end
	if counts.coreParts~=6*n then bad("Total core count does not match generated floors") end
	for key,value in counts do summary[key]+=value end
	return reasons,counts
end

function Audit.Run(folder)
	folder=folder or workspace:FindFirstChild("Buildings")
	assert(typeof(folder)=="Instance","Provide the building container")
	local summary={buildings=0,goodBuildings=0,badBuildings=0,otherModels=0,
		floors=0,plannedFloors=0,roofs=0,parts=0,structuralParts=0,decorationParts=0,
		wedges=0,slabParts=0,coreParts=0}
	local badModels={}
	for _,model in folder:GetChildren() do
		if not model:IsA("Model") or not model:GetAttribute("SmoothMassing") then summary.otherModels+=1; continue end
		summary.buildings+=1
		local reasons,counts=inspect(model,summary)
		if #reasons>0 then table.insert(badModels,{model=model,name=model.Name,reasons=reasons,counts=counts})
		else summary.goodBuildings+=1 end
		if summary.buildings%50==0 then task.wait() end
	end
	summary.badBuildings=#badModels
	table.sort(badModels,function(a,b) return a.name<b.name end)
	print(string.format("SMOOTH AUDIT: %d buildings, %d/%d populated floors, %d roofs, %d structural parts (%d wedges); %d buildings need attention.",
		summary.buildings,summary.floors,summary.plannedFloors,summary.roofs,summary.structuralParts,summary.wedges,summary.badBuildings))
	for i=1,math.min(20,#badModels) do print("AUDIT ISSUE",badModels[i].name,table.concat(badModels[i].reasons,"; ")) end
	return {summary=summary,badModels=badModels}
end

return Audit
