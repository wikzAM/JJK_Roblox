-- Edit-time display only, appended to the existing facade review platform.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Visual=require(Shared.GlassVisual)
local Demo={}
local OWNER="2026-10-08-glass"
local function part(parent,name,cf,size,color)
	local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanTouch=false;p.Size=size;p.CFrame=cf;p.Color=color;p.Parent=parent;return p
end
local function label(parent,name,cf,text,width)
	local p=part(parent,name,cf,Vector3.new(width,2,.2),Color3.fromRGB(28,34,40));p.CanCollide=false
	local g=Instance.new("SurfaceGui");g.Face=Enum.NormalId.Front;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=35;g.Parent=p
	local t=Instance.new("TextLabel");t.Name="Text";t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.TextScaled=true;t.Text=text;t.Font=Enum.Font.SourceSansSemibold;t.TextColor3=Color3.fromRGB(229,237,240);t.Parent=g
end
function Demo.Generate()
	local gallery=assert(workspace:FindFirstChild("GroundFacadeDraftGallery"),"Generate facade gallery first")
	local old=gallery:FindFirstChild("04_GlassDemo")
	if old then assert(old:GetAttribute("Owner")==OWNER,"Unowned demo");return old end
	-- First mutation is the ownership/replay lock.
	local root=Instance.new("Folder");root.Name="04_GlassDemo";root:SetAttribute("Owner",OWNER);root:SetAttribute("State","building");root.Parent=gallery
	local origin=gallery:GetAttribute("Origin") or CFrame.new(0,1600,0)
	part(root,"DemoDeck",origin*CFrame.new(110,-.55,-100),Vector3.new(244,1,58),Color3.fromRGB(94,99,102))
	part(root,"DemoWalkway",origin*CFrame.new(12,-.55,-56),Vector3.new(14,1,30),Color3.fromRGB(94,99,102))
	label(root,"Title",origin*CFrame.new(110,17,-100),"GLASS / 4 STATES + AUTOMATIC PLAY DEMO",228)
	for i=1,6 do
		local x=(i-1)*39;local width=i==6 and 28 or 24
		local cf=origin*CFrame.new(x,0,-100)
		local m=Instance.new("Model");m.Name=i==5 and "AutomaticLoop" or i==6 and "WideShattered" or "State"..i;m.Parent=root
		for _,dx in {-width/2,width/2} do part(m,"Frame",cf*CFrame.new(dx,5,0),Vector3.new(.3,10,.5),Color3.fromRGB(67,75,81)) end
		for _,y in {0,10} do part(m,"Frame",cf*CFrame.new(0,y,0),Vector3.new(width,.3,.5),Color3.fromRGB(67,75,81)) end
		-- A bright backing accent makes an unobstructed hole easy to judge.
		part(m,"Backdrop",cf*CFrame.new(0,5,6),Vector3.new(width+1,11,.3),Color3.fromRGB(57,69,76))
		part(m,"BackdropAccent",cf*CFrame.new(0,4,5.7),Vector3.new(width-3,.25,.2),Color3.fromRGB(230,184,80))
		local p=part(m,"Glass",cf*CFrame.new(0,5,0),Vector3.new(width-.3,9.7,.2),Color3.fromRGB(45,107,131))
		p.Material=Enum.Material.Glass;p.Transparency=.32;p.Reflectance=.18;p:SetAttribute("GlassDemoPane",true);Visual.Capture(p,"demo/"..i,true)
		local state=i<=4 and i or i==6 and 3 or 1;Visual.Apply(p,state)
		local text=({"1 / INTACT","2 / CRACKED","3 / SHATTERED","4 / REMOVED","AUTO LOOP / PRESS PLAY","WIDE / SAME EDGE SCALE"})[i]
		label(m,"Caption",cf*CFrame.new(0,12,0),text,width+7)
		m.WorldPivot=cf
	end
	root:SetAttribute("State","ready")
	root:SetAttribute("AutoPlaceViewer",true)
	return root
end
function Demo.Focus()
	local root=Demo.Generate();local g=root.Parent;local cf=g:GetAttribute("Origin")
	workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
	local target=(cf*CFrame.new(110,7,-100)).Position
	workspace.CurrentCamera.Focus=CFrame.new(target)
	workspace.CurrentCamera.CFrame=CFrame.lookAt((cf*CFrame.new(110,12,-168)).Position,target)
	game:GetService("Selection"):Set({root})
end
return Demo
