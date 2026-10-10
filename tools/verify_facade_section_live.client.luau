-- Temporary native Play probe; never part of ordinary game startup.
local H=game:GetService("HttpService");local Run=game:GetService("RunService")
local root=Instance.new("Folder");root.Name="FacadeSectionVerification";root.Parent=workspace
local cam=workspace.CurrentCamera;local prior={cam.CFrame,cam.Focus,cam.CameraType}
local position,target=Vector3.new(-1700,110,400),Vector3.new(-1600,100,400)
local beats,renderFrames=0,0
local samples={};local measurement,started=nil,nil
local hold=Run.Heartbeat:Connect(function() beats+=1;
 if root:GetAttribute("CameraPosition") then position=root:GetAttribute("CameraPosition");target=root:GetAttribute("CameraTarget") end
cam=workspace.CurrentCamera;cam.CameraType=Enum.CameraType.Scriptable;cam.CFrame=CFrame.lookAt(position,target);cam.Focus=CFrame.new(target) end)
local render=Run.RenderStepped:Connect(function(dt)
 renderFrames+=1
 local requested=root:GetAttribute("Measure")
 if requested~=measurement then measurement=requested;samples={};started=os.clock() end
 if measurement and started then
  table.insert(samples,dt)
  if os.clock()-started>=5 then
   local sorted=table.clone(samples);table.sort(sorted);local sum=0;for _,v in samples do sum+=v end
   root:SetAttribute("MeasureResult",H:JSONEncode({name=measurement,frames=#samples,seconds=os.clock()-started,meanMs=sum/#samples*1000,p95Ms=sorted[math.ceil(#sorted*.95)]*1000,maxMs=sorted[#sorted]*1000,renderFPS=#samples/sum}))
   started=nil
  end
 end
end)
local function info()
 local panes,damaged,edges,labels,cracks=0,0,0,0,0
 for _,m in workspace.Buildings:GetChildren() do local f=m:FindFirstChild("GroundFacadePilot");if f then
  for _,p in f:GetDescendants() do if p:IsA("BasePart") and p:HasTag("GlassPane") then
   panes+=1;if (p:GetAttribute("GlassState") or 1)>1 then damaged+=1 end
   for _,o in p:GetDescendants() do if o.Name=="GlassDamage_Edges" then edges+=1 elseif o:IsA("ImageLabel") then labels+=1 elseif o.Name=="GlassDamage_Cracks" then cracks+=1 end end
  end end
 end end
 return {panes=panes,damaged=damaged,edges=edges,labels=labels,cracks=cracks,metrics=workspace.LocalFacades:GetAttributes(),near=#workspace.LocalFacades:GetChildren(),far=#workspace.LocalFacadesFar:GetChildren()}
end
local function main()
 workspace:WaitForChild("LocalFacades",30);workspace:WaitForChild("LocalFacadesFar",30)
 root:SetAttribute("Phase","outside");task.wait(5);local outside=info()
 assert(outside.near==0 and outside.far==0 and outside.metrics.GeneratedUpperEnabled==false)
 position,target=Vector3.new(-336.881,93.425,-658.491),Vector3.new(-333.199,91.425,-705.782)
 root:SetAttribute("Phase","inside");task.wait(6);local inside=info()
 assert(inside.near==0 and inside.far==0 and inside.panes==175,"Unexpected upper generation or missing ground glass")
 root:SetAttribute("Baseline",H:JSONEncode({outside=outside,inside=inside,beats=beats,renderFrames=renderFrames}))
 root:SetAttribute("Phase","ready-for-damage")
end
local ok,err=pcall(main)
root:SetAttribute("PassedBaseline",ok);root:SetAttribute("Error",ok and "" or tostring(err))
if not ok then root:SetAttribute("Phase","failed");hold:Disconnect();render:Disconnect();cam.CFrame=prior[1];cam.Focus=prior[2];cam.CameraType=prior[3] end
root:GetAttributeChangedSignal("Cleanup"):Connect(function() if root:GetAttribute("Cleanup") then hold:Disconnect();render:Disconnect();cam.CFrame=prior[1];cam.Focus=prior[2];cam.CameraType=prior[3] end end)
