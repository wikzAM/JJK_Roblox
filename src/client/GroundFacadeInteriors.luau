--!nonstrict
-- Explicit opt-in trial, client-only shallow 3D interiors; no per-pane physics.
local I={}
local RS=game:GetService("ReplicatedStorage")
local G=require(RS.Shared.GroundFacadeInteriorGeometry)
local active,tracked,retryAfter={},{ },{}
local folder,started
local function remove(p)
	local room=active[p];if not room then return end
	for _,back in room.backings do if back.Parent then back.LocalTransparencyModifier=0 end end
	room.model:Destroy();active[p]=nil
end
local function eligible(p)
	if p:GetAttribute("GlassInteriorStaticVersion") then return end
	if not p.Parent or not p:IsDescendantOf(workspace) or (p:GetAttribute("GlassState") or 1)>=3 then return end
	local root=p:FindFirstAncestor("GroundFacadePilot")
	if not root or not root.Parent:GetAttribute("FacadeInteriorTrial") then return end
	return root
end
local function build(p,root)
	local cell=G.Plan(p,root);if not cell then return end
	local filter=RaycastParams.new();filter.FilterType=Enum.RaycastFilterType.Exclude;filter.FilterDescendantsInstances={root,folder}
	-- Core/neighbor walls must not protrude into the fake room. Keep the flat
	-- backing where real structure leaves insufficient space; never cut a core.
	for _,x in {cell.left,0,cell.right} do for _,y in {cell.bottom+.1,(cell.bottom+cell.top)/2,cell.top-.1} do
		local origin=p.CFrame:PointToWorldSpace(Vector3.new(x,y,cell.start))
		if workspace:Raycast(origin,p.CFrame.ZVector*(cell.depth+.1),filter) then return end
	end end
	local model=Instance.new("Model");model.Name="WindowInterior"
	local id=p:GetAttribute("GlassPaneId") or p.Name;local seed=0
	for n=1,#id do seed=(seed*33+id:byte(n))%65521 end
	for _,row in G.Rows(cell,seed) do
		local part=Instance.new(row.shape or "Part");part.Name=row.name;part.CFrame=p.CFrame*row.cframe;part.Size=row.size
		part.Color=row.color;part.Material=Enum.Material.SmoothPlastic;part.Anchored=true
		part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false;part.Parent=model
	end
	local backings={}
	for _,back in p:GetChildren() do if back:IsA("BasePart") and back.Name=="InteriorWindowBacking" then
		back.LocalTransparencyModifier=1;table.insert(backings,back)
	end end
	model:SetAttribute("PaneId",id);model:SetAttribute("Depth",cell.depth);model.Parent=folder
	active[p]={model=model,backings=backings}
end
function I.Init()
	if started then return end;started=true
	folder=Instance.new("Folder");folder.Name="LocalGroundInteriors";folder.Parent=workspace
	local tags=game:GetService("CollectionService")
	local function watch(p)
		local root=p:IsA("BasePart") and p:FindFirstAncestor("GroundFacadePilot")
		if not root or not root.Parent:GetAttribute("FacadeInteriorTrial") or tracked[p] then return end
		tracked[p]=p:GetAttributeChangedSignal("GlassState"):Connect(function()if (p:GetAttribute("GlassState") or 1)>=3 then remove(p) end end)
	end
	for _,p in tags:GetTagged("GlassPane") do watch(p) end
	tags:GetInstanceAddedSignal("GlassPane"):Connect(watch)
	tags:GetInstanceRemovedSignal("GlassPane"):Connect(function(p)remove(p);if tracked[p] then tracked[p]:Disconnect();tracked[p]=nil end end)
	local elapsed=0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.3 then return end;elapsed=0
		local cam=workspace.CurrentCamera;if not cam then return end
		local candidates={};local count=0
		for p in active do if not eligible(p) or (p.Position-cam.CFrame.Position).Magnitude>G.DropRadius then remove(p) else count+=1 end end
		for p in tracked do local root=eligible(p)
			if root and not active[p] and (retryAfter[p] or 0)<os.clock() then local distance=(p.Position-cam.CFrame.Position).Magnitude
				if distance<G.NearRadius then table.insert(candidates,{pane=p,root=root,distance=distance}) end
			end
		end
		table.sort(candidates,function(a,b)return a.distance<b.distance end)
		local built=0
		for _,candidate in candidates do
			if count>=G.MaxRooms or built>=2 then break end
			build(candidate.pane,candidate.root);built+=1
			if active[candidate.pane] then count+=1 else retryAfter[candidate.pane]=os.clock()+5 end
		end
		folder:SetAttribute("Rooms",count);folder:SetAttribute("RoomCap",G.MaxRooms);folder:SetAttribute("TrialOnly",true)
	end)
end
return I
