--!nonstrict
-- Map-wide, bounded client detail. ONE room per tenant bay; no pane-sized cells.
local I={}
local RS=game.ReplicatedStorage
local G=require(RS.Shared.GroundFacadeInteriorGeometry)
local V=require(RS.Shared.GlassVisual)
local H=game:GetService("HttpService")
local entries,lookup,active={},{},{}
local cursor,started=1,false
local function backing(entry,detail)
	for _,pane in entry.panes do if pane.Parent then
		local intact=(pane:GetAttribute("GlassState") or 1)<=2
		for _,p in pane:GetChildren() do if p:IsA("BasePart") and p.Name=="InteriorWindowBacking" then
			p.Transparency=(detail or not intact) and 1 or 0
			p:SetAttribute("GlassFilmTransparency",detail and 1 or 0)
		end end
	end end
end
local function remove(entry)
	if entry.room then
		if entry.preview then for _,p in entry.room:GetChildren() do if p:IsA("BasePart") then p.LocalTransparencyModifier=1 end end
		else entry.room:Destroy();entry.room=nil end
	end
	active[entry]=nil;backing(entry,false)
end
local function usable(entry)
	if not entry.bay:IsDescendantOf(workspace) then return false end
	for _,p in entry.panes do if p.Parent and (p:GetAttribute("GlassState") or 1)<=2 then return true end end
	return false
end
local function build(entry)
	local bay=entry.bay
	if not usable(entry) then return false end
	if not entry.room then
		local cell=H:JSONDecode(bay:GetAttribute("FacadeBayInteriorPlan"));cell.frame=bay:GetPivot()
		local folder=Instance.new("Folder");folder.Name="BayInterior"
		for _,row in G.Rows(cell,bay:GetAttribute("FacadeBayInteriorSeed") or 19) do
			local p=Instance.new(row.shape or "Part");p.Name=row.name;p.CFrame=cell.frame*row.cframe;p.Size=row.size
			p.Color=row.color;p.Material=Enum.Material.SmoothPlastic;p.Anchored=true
			p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Parent=folder
		end
		folder.Parent=bay;entry.room=folder
	else for _,p in entry.room:GetChildren() do if p:IsA("BasePart") then p.LocalTransparencyModifier=0 end end end
	V.RefreshBayInterior(bay);backing(entry,true);active[entry]=true;return true
end
local function track(bay)
	if lookup[bay] or not bay:IsA("Model") or bay:GetAttribute("FacadeBayInteriorVersion")~=2 then return end
	local entry={bay=bay,panes=G.Panes(bay),room=bay:FindFirstChild("BayInterior")}
	entry.preview=entry.room~=nil;lookup[bay]=entry;table.insert(entries,entry)
	remove(entry)
end
function I.Init()
	if started then return end;started=true
	local tags=game:GetService("CollectionService")
	-- Registration yields between small groups; no initial city-sized room build.
	for i,bay in tags:GetTagged("FacadeInteriorBay") do track(bay);if i%32==0 then task.wait() end end
	tags:GetInstanceAddedSignal("FacadeInteriorBay"):Connect(track)
	tags:GetInstanceRemovedSignal("FacadeInteriorBay"):Connect(function(bay)
		local entry=lookup[bay];if entry then remove(entry);lookup[bay]=nil end
	end)
	local attempts=0;local elapsed=0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		local cam=workspace.CurrentCamera;if not cam or #entries==0 then return end
		local position=cam.CFrame.Position
		elapsed+=dt;if elapsed>=.3 then elapsed=0;attempts=0 end
		local count,furthest,farDistance=0,nil,0
		for entry in active do
			local d=(entry.bay:GetPivot().Position-position).Magnitude
			if not usable(entry) or d>G.DropRadius then remove(entry)
			else
				count+=1
				if d>farDistance then furthest=entry;farDistance=d end
			end
		end
		local start=os.clock();local visited=0;local nearest,nearDistance
		-- A budgeted sweep discovers nearby bays without sorting all17029 panes.
		while visited<64 and os.clock()-start<.00075 do
			if cursor>#entries then cursor=1 end
			local entry=entries[cursor];cursor+=1;visited+=1
			if lookup[entry.bay]==entry and not active[entry] and usable(entry) then
				local d=(entry.bay:GetPivot().Position-position).Magnitude
				if d<G.NearRadius and (not nearDistance or d<nearDistance) then nearest=entry;nearDistance=d end
			end
		end
		if nearest and attempts<2 then
			if count>=G.MaxRooms and furthest and nearDistance<farDistance-5 then remove(furthest);count-=1 end
			if count<G.MaxRooms then attempts+=1;build(nearest) end
		end
	end)
end
return I
