-- Edit-time locator Parts only. No startup, terrain or building mutations.
local Markers={}
local OWNER="2026-10-10-facade-markers"
local function beacon(root,name,base,height,color,text)
	local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false
	p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Material=Enum.Material.Neon
	p.Color=color;p.Transparency=.12;p.Size=Vector3.new(12,height,12)
	p.Position=base+Vector3.yAxis*(height/2);p:SetAttribute("BasePosition",base);p.Parent=root
	local gui=Instance.new("BillboardGui");gui.Name="LocatorLabel";gui.AlwaysOnTop=true
	gui.Size=UDim2.fromOffset(380,80);gui.StudsOffsetWorldSpace=Vector3.new(0,height/2+12,0)
	gui.MaxDistance=6000;gui.Parent=p
	local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1)
	label.BackgroundColor3=Color3.fromRGB(22,25,29);label.BackgroundTransparency=.2
	label.TextColor3=color;label.TextScaled=true;label.Font=Enum.Font.SourceSansBold
	label.Text=text;label.Parent=gui
	return p
end
function Markers.Generate()
	local gallery=assert(workspace:FindFirstChild("GroundFacadeDraftGallery"),"Facade gallery missing")
	local old=workspace:FindFirstChild("FacadeTestMarkers")
	if old then assert(old:GetAttribute("Owner")==OWNER,"Unowned locator folder");Markers.UpdateCity(old);return old end
	local root=Instance.new("Folder");root.Name="FacadeTestMarkers";root:SetAttribute("Owner",OWNER);root.Parent=workspace
	local origin=gallery:GetAttribute("Origin") or CFrame.new(0,1600,0)
	beacon(root,"Magenta_GalleryDemo",(origin*CFrame.new(250,0,-100)).Position,500,
		Color3.fromRGB(255,35,208),"FACADE GALLERY + GLASS DEMO\nRAISED PLATFORM")
	local registry=game.ServerStorage:FindFirstChild("GroundFacadePilotManifest")
	if registry then
		local report=game:GetService("HttpService"):JSONDecode(registry:GetAttribute("Report"))
		local row=report.rows[1];assert(row,"Pilot review frontage missing")
		local face=row.faces and row.faces[1]
		if row.faces then for _,f in row.faces do if f.portals>0 and f.class~="parking" then face=f;break end end end
		local cf=CFrame.new(table.unpack(face and face.frame or row.frame))
		beacon(root,"Lime_CityFacadeTestArea",(cf*CFrame.new((face and face.width or 28)/2+28,0,-20)).Position,900,
			Color3.fromRGB(125,255,30),"CITY GROUND-FACADE TEST AREA\n"..report.buildings.." COMPLETE PERIMETERS / NEAR 109")
	end
	game:GetService("ChangeHistoryService"):SetWaypoint("Facade test area locators")
	return root
end
function Markers.UpdateCity(root)
	local p=root:FindFirstChild("Lime_CityFacadeTestArea")
	local reg=game.ServerStorage:FindFirstChild("GroundFacadePilotManifest")
	if not p or not reg then return end
	local report=game:GetService("HttpService"):JSONDecode(reg:GetAttribute("Report"))
	local row=report.rows[1];local face=row.faces and row.faces[1]
	if row.faces then for _,f in row.faces do if f.portals>0 and f.class~="parking" then face=f;break end end end
	local cf=CFrame.new(table.unpack(face and face.frame or row.frame));local base=(cf*CFrame.new((face and face.width or 28)/2+28,0,-20)).Position
	p:SetAttribute("BasePosition",base);p.Position=base+Vector3.yAxis*(p.Size.Y/2)
	p.LocatorLabel.TextLabel.Text="CITY GROUND-FACADE TEST AREA\n"..report.buildings.." COMPLETE PERIMETERS / NEAR 109"
end
function Markers.FocusCity()
	local p=Markers.Generate():FindFirstChild("Lime_CityFacadeTestArea")
	assert(p,"City pilot marker missing")
	game:GetService("Selection"):Set({p})
	local base=p:GetAttribute("BasePosition");local cam=workspace.CurrentCamera
	cam.Focus=CFrame.new(base+Vector3.new(0,12,0))
	cam.CFrame=CFrame.lookAt(base+Vector3.new(-110,75,-110),base+Vector3.new(0,12,0))
end
return Markers
