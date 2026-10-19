--!nonstrict
-- Keeps the hit dummy findable: an always-on-top outline plus a distance label,
-- and key G asks the server to bring it in front of the player.
local Tracker={KEY=Enum.KeyCode.G}
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Collection=game:GetService("CollectionService")
local UIS=game:GetService("UserInputService")
local function attach(model)
	if model:FindFirstChild("DummyMarker") then return end
	local h=Instance.new("Highlight");h.Name="DummyMarker";h.FillTransparency=1;h.OutlineTransparency=0
	h.OutlineColor=Color3.fromRGB(255,214,40);h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.Adornee=model;h.Parent=model
	local head=model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local gui=Instance.new("BillboardGui");gui.Name="DummyLabel";gui.AlwaysOnTop=true;gui.Size=UDim2.fromOffset(160,36)
	gui.StudsOffset=Vector3.new(0,3.5,0);gui.LightInfluence=0;gui.MaxDistance=1e6;gui.Adornee=head;gui.Parent=model
	local label=Instance.new("TextLabel");label.BackgroundTransparency=.35;label.BackgroundColor3=Color3.fromRGB(20,20,24)
	label.TextColor3=Color3.fromRGB(255,214,40);label.Font=Enum.Font.GothamBold;label.TextScaled=true
	label.Size=UDim2.fromScale(1,1);label.Text="DUMMY";label.Parent=gui
	local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,8);corner.Parent=label
	task.spawn(function()
		while gui.Parent do
			local hrp=Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp and head and head.Parent then
				label.Text=string.format("DUMMY  %d studs  [%s]",math.floor((head.Position-hrp.Position).Magnitude),Tracker.KEY.Name)
			end
			task.wait(.2)
		end
	end)
end
function Tracker.Init()
	for _,m in Collection:GetTagged("HitTarget") do if m:IsA("Model") then attach(m) end end
	Collection:GetInstanceAddedSignal("HitTarget"):Connect(function(m) if m:IsA("Model") then attach(m) end end)
	local event=RS:WaitForChild("SummonDummyEvent",30)
	UIS.InputBegan:Connect(function(input,processed)
		if processed or input.KeyCode~=Tracker.KEY then return end
		if event then event:FireServer() end
	end)
end
return Tracker
