-- Temporary native LocalScript for Play verification; never synced to the game.
local Http=game:GetService("HttpService")
local Run=game:GetService("RunService")
local result=Instance.new("Folder");result.Name="GlassLiveVerification";result.Parent=workspace
local function main()
	local demo=workspace:WaitForChild("GroundFacadeDraftGallery"):WaitForChild("04_GlassDemo").AutomaticLoop
	local cam=workspace.CurrentCamera;local previousCF,previousFocus,previousType=cam.CFrame,cam.Focus,cam.CameraType
	local pos,target=Vector3.new(156,1610,-134),Vector3.new(156,1605,-100)
	-- Studio may suspend RenderStepped while its window is backgrounded.
	local cameraConnection=Run.Heartbeat:Connect(function()
		cam=workspace.CurrentCamera
		cam.CameraType=Enum.CameraType.Scriptable;cam.Focus=CFrame.new(target);cam.CFrame=CFrame.lookAt(pos,target)
	end)
	local seen,burst,holders={},0,0
	result:SetAttribute("Phase","demo")
	for i=1,100 do
		local state=demo:GetAttribute("DemoState");local p=demo:FindFirstChild("Glass")
		if state then seen[tostring(state)]={exists=p~=nil,collision=p and p.CanCollide,transparency=p and p.Transparency,overlays=p and #p:GetChildren()} end
		burst=math.max(burst,demo:GetAttribute("DemoBurstParticles") or 0)
		local n=0;for _,o in workspace:GetChildren() do if o.Name=="LocalGlassBurst" then n+=1 end end;holders=math.max(holders,n)
		task.wait(.2)
	end
	result:SetAttribute("DemoResult",Http:JSONEncode({states=seen,burstParticles=burst,maxBurstHolders=holders}))
	pos,target=Vector3.new(-1639.66,106,378.95),Vector3.new(-1613.79,103,397.78)
	result:SetAttribute("Phase","city")
	task.wait(18)
	local metrics=workspace.LocalFacades:GetAttributes()
	local overlap=0
	local model
	for _,m in workspace.Buildings:GetChildren() do if m:GetAttribute("SourceSliceId")=="fbx_9_-15603_1695_4366" then model=m end end
	local localModel=workspace.LocalFacades:FindFirstChild(model.Name)
	if localModel then for _,p in localModel:GetChildren() do if p:IsA("BasePart") and (p:GetAttribute("GlassPaneId") or ""):match("^1/2/10:") then overlap+=1 end end end
	local damaged={}
	for _,p in model.GroundFacadePilot:GetDescendants() do if p:IsA("BasePart") and p:GetAttribute("GlassState")==3 then
		local edges=0;local hiddenAds=0
		for _,c in p:GetChildren() do
			if c.Name=="GlassDamage_Edges" then edges+=1 end
			if c:IsA("BasePart") and c:GetAttribute("GlassAttachedOverlay") then assert(c.Transparency==1,"Shattered poster remains visible");hiddenAds+=1 end
		end
		table.insert(damaged,{transparency=p.Transparency,collision=p.CanCollide,overlays=edges,hiddenAds=hiddenAds})
	end end
	result:SetAttribute("CityResult",Http:JSONEncode({metrics=metrics,duplicateGroundPanes=overlap,damaged=damaged,camera={cam.CFrame.Position.X,cam.CFrame.Position.Y,cam.CFrame.Position.Z}}))
	cameraConnection:Disconnect();cam.CameraType=previousType;cam.Focus=previousFocus;cam.CFrame=previousCF
	assert(seen["1"] and seen["2"] and seen["3"] and seen["4"],"Demo did not complete all states")
	assert(seen["2"].collision and seen["3"].transparency==1 and not seen["3"].collision and not seen["4"].exists,"Demo state contract failed")
	assert(seen["3"].overlays==2 and burst>0 and holders>0,"Demo particles or edge overlays failed")
	assert((metrics.BuiltBuildings or 0)>0 and (metrics.Parts or 0)>0 and overlap==0,"City renderer/ground ownership failed")
	assert(#damaged>0 and damaged[1].transparency==1 and not damaged[1].collision and damaged[1].overlays==2,"Ground glass damage did not render")
end
local ok,err=pcall(main)
result:SetAttribute("Passed",ok);result:SetAttribute("Error",ok and "" or tostring(err));result:SetAttribute("Phase","complete")
