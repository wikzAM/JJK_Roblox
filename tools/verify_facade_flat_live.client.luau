-- Temporary native LocalScript, deliberately not synced as game startup.
local H=game:GetService("HttpService");local Run=game:GetService("RunService")
local result=Instance.new("Folder");result.Name="FacadeFlatScopeVerification";result.Parent=workspace
local cam=workspace.CurrentCamera;local previousCF,previousFocus,previousType=cam.CFrame,cam.Focus,cam.CameraType
local position,target=Vector3.new(-1700,110,400),Vector3.new(-1600,100,400)
local camera=Run.Heartbeat:Connect(function()
	cam=workspace.CurrentCamera;cam.CameraType=Enum.CameraType.Scriptable
	cam.Focus=CFrame.new(target);cam.CFrame=CFrame.lookAt(position,target)
end)
local function main()
	workspace:WaitForChild("LocalFacades",30);workspace:WaitForChild("LocalFacadesFar",30)
	result:SetAttribute("Phase","outside-test-area");task.wait(10)
	local outside={near=#workspace.LocalFacades:GetChildren(),far=#workspace.LocalFacadesFar:GetChildren(),metrics=workspace.LocalFacades:GetAttributes()}
	assert(outside.near==0 and outside.far==0,"Glass generated outside the selected test area")
	position,target=Vector3.new(-336.881,93.425,-658.491),Vector3.new(-333.199,91.425,-705.782)
	result:SetAttribute("Phase","inside-test-area");task.wait(18)
	local allowed={};local eligible=0
	for _,m in workspace.Buildings:GetChildren() do
		local p=m:FindFirstChild("GroundFacadePilot")
		if p and p:GetAttribute("Owner")=="2026-10-08-ground-pilot" then allowed[m.Name]=true;eligible+=1 end
	end
	local near=#workspace.LocalFacades:GetChildren();assert(near>0 and near<=eligible,"Pilot renderer has no geometry or escaped the allowlist")
	for _,m in workspace.LocalFacades:GetChildren() do assert(allowed[m.Name],"Non-pilot generated glass: "..m.Name) end
	assert(#workspace.LocalFacadesFar:GetChildren()==0,"Opaque far proxies must be disabled")
	local metrics=workspace.LocalFacades:GetAttributes();assert(metrics.EligibleBuildings==eligible and metrics.GeneratedFacadeScope=="groundPilot")
	result:SetAttribute("Result",H:JSONEncode({outside=outside,inside={near=near,far=0,eligible=eligible,metrics=metrics}}))
end
local ok,err=pcall(main)
camera:Disconnect();cam.CameraType=previousType;cam.CFrame=previousCF;cam.Focus=previousFocus
result:SetAttribute("Passed",ok);result:SetAttribute("Error",ok and "" or tostring(err));result:SetAttribute("Phase","complete")
