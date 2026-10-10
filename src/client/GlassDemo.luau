-- Demonstration independent of attacks, hits, server damage or user input.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Visual=require(Shared.GlassVisual)
local Config=require(Shared.GlassConfig)
local Shards=require(script.Parent.GlassShards)
local Demo={}
local started=false
function Demo.Init()
	if started then return end;started=true
	-- This large map can take >10 seconds to replicate the review gallery.
	-- Init runs in its own task, so waiting here never blocks normal input.
	local gallery=workspace:WaitForChild("GroundFacadeDraftGallery")
	local root=gallery:WaitForChild("04_GlassDemo")
	local model=root:WaitForChild("AutomaticLoop")
	if model:GetAttribute("DemoLoopRunning") then return end
	model:SetAttribute("DemoLoopRunning",true)
	local original=model:WaitForChild("Glass"):Clone();original.Parent=nil
	if game:GetService("RunService"):IsStudio() and root:GetAttribute("AutoPlaceViewer")~=false then
		local player=game.Players.LocalPlayer;local character=player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart")
		if (character:GetPivot().Position-model:GetPivot().Position).Magnitude>500 then
			local pos=(model:GetPivot()*CFrame.new(0,5,-18)).Position
			character:PivotTo(CFrame.lookAt(pos,model:GetPivot().Position+Vector3.new(0,5,0)))
		end
	end
	-- Asset loading must never hold up the state demonstration.
	task.spawn(function()
		pcall(function()game:GetService("ContentProvider"):PreloadAsync({Config.CrackImage,Config.ShatteredImage,Config.ShardImage},function(id,status)
			if model.Parent then model:SetAttribute("AssetFetch_"..id:match("%d+"),status.Name) end
		end)end)
	end)
	local labels={"1 / INTACT — COLLISION ON","2 / CRACKED — COLLISION ON","3 / SHATTERED — CLEAR OPENING","4 / REMOVED — NO PANE"}
	while root.Parent do
		for state=1,4 do
			if not root.Parent then break end
			local p=model:FindFirstChild("Glass")
			if not p then p=original:Clone();p.Parent=model end
			local cf,size=p.CFrame,p.Size
			Visual.Apply(p,state)
			model:SetAttribute("DemoState",state)
			model.Caption.SurfaceGui.Text.Text=labels[state]
			if state==3 then model:SetAttribute("DemoBurstParticles",Shards.Emit(cf,size,cf.Position-cf.LookVector*8,36,{force=true})) end
			task.wait(4)
		end
	end
	original:Destroy()
end
return Demo
