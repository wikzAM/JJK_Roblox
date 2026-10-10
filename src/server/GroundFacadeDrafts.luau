--!nonstrict
-- EDIT-TIME ONLY. Not wired into init.server. Never finds/edits live buildings.
-- require(game.ServerScriptService.Server.GroundFacadeDrafts).Generate()
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Kit=require(Shared.GroundFacadeKit)
local Catalog=require(Shared.GroundFacadeCatalog)
local Drafts={}
local ROOT="GroundFacadeDraftGallery"
local LIBRARY="GroundFacadeDraftLibrary"
local VERSION="2026-10-07-v1"

local function ownRoot(parent,name)
	local existing=parent:FindFirstChild(name)
	if existing then
		assert(existing:GetAttribute("GroundFacadeOwner")==VERSION,"Name is occupied by another object: "..name)
		return existing
	end
	local root=Instance.new("Folder");root.Name=name
	root:SetAttribute("GroundFacadeOwner",VERSION);root:SetAttribute("State","building");root.Parent=parent
	return root
end

local function part(parent,name,cf,size,color)
	local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.Size=size;p.CFrame=cf;p.Color=color
	p.Material=Enum.Material.SmoothPlastic;p.CanTouch=false;p.TopSurface=Enum.SurfaceType.Smooth
	p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent
	return p
end

local function caption(parent,cf,width,value)
	local board=part(parent,"DraftCaption",cf,Vector3.new(width,2.2,0.2),Color3.fromRGB(25,30,35))
	local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Front;gui.PixelsPerStud=35
	gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.LightInfluence=0;gui.Parent=board
	local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
	label.Text=value;label.TextColor3=Color3.fromRGB(231,220,197);label.Font=Enum.Font.SourceSansSemibold
	label.TextScaled=true;label.Parent=gui
end

local function illuminate(model)
	-- Review-only warm interior illumination; reusable facades carry no lights.
	local emitter=model:FindFirstChild("PreviewCeilingLight") or model:FindFirstChild("PreviewCeilingGlow")
	if emitter then
		local light=Instance.new("PointLight");light.Name="PreviewInteriorLight";light.Range=24
		light.Brightness=2;light.Color=Color3.fromRGB(242,224,198);light.Shadows=false;light.Parent=emitter
	end
end

function Drafts.Generate(origin)
	-- Acquire replay lock before creating any assets. Failed roots stay identifiable.
	local gallery=ownRoot(workspace,ROOT)
	if gallery:GetAttribute("State")=="ready" then
		assert(gallery:GetAttribute("Revision")==Catalog.VERSION,"Older gallery: use Upgrade() to archive and replace it")
		return gallery,game.ServerStorage:FindFirstChild(LIBRARY)
	end
	assert(#gallery:GetChildren()==0,"A draft build is incomplete; call Clear() before retrying")
	origin=origin or CFrame.new(0,1600,0)
	gallery:SetAttribute("Origin",origin)
	local library=ownRoot(game.ServerStorage,LIBRARY)
	assert(#library:GetChildren()==0 or (library:GetAttribute("State")=="ready" and library:GetAttribute("Revision")==Catalog.VERSION),"Older/incomplete library; use Upgrade()")
	local samples=Instance.new("Folder");samples.Name="01_IndividualTypes";samples.Parent=gallery
	local compositions=Instance.new("Folder");compositions.Name="02_StitchedExamples";compositions.Parent=gallery
	local stitchedZ=math.ceil(#Catalog.TYPES/5)*54+22
	local streetZ=stitchedZ+150
	local deckLength=streetZ+90
	gallery:SetAttribute("StreetViewZ",streetZ)
	part(gallery,"PreviewDeck",origin*CFrame.new(132,-0.55,(deckLength-60)/2),Vector3.new(366,1,deckLength),Color3.fromRGB(95,99,100))
	caption(gallery,origin*CFrame.new(132,38,stitchedZ-32),284,"GROUND FLOOR / "..#Catalog.TYPES.." SHIBUYA-INSPIRED DRAFTS")
	for i,spec in Catalog.TYPES do
		local column,row=(i-1)%5,math.floor((i-1)/5)
		local cf=origin*CFrame.new(column*66,0,row*54)
		local model=Kit.Build(samples,spec.id,cf,{seed=1000+i,vignette=true})
		illuminate(model)
		model.Name=spec.id
		caption(samples,cf*CFrame.new(0,(spec.height or 12.5)+3.5,1),spec.width+5,string.format("%02d / %s",i,spec.title))
		if not library:FindFirstChild(spec.id) then
			local template=Kit.Build(library,spec.id,CFrame.identity,{seed=1000+i});template.Name=spec.id
		end
	end
	for i,row in {{"mixed",96},{"office",96},{"hotel",96}} do
		local profile,width=row[1],row[2]
	local cf=origin*CFrame.new(-4+(i-1)*114,0,stitchedZ)
		local model=Kit.BuildRun(compositions,width,"draft-street-17/"..profile,profile,cf,{vignette=true,targetWidth=32})
		model.Name="Stitched_"..profile
		caption(compositions,cf*CFrame.new(0,16,1),width,"SEEDED / "..string.upper(profile))
	end
	-- Separate return wall demonstrates joining two runs around a corner.
	local corner=Instance.new("Model");corner.Name="Corner_Return";corner.Parent=compositions
	local cornerCF=origin*CFrame.new(-28,0,stitchedZ+55)
	Kit.BuildRun(corner,36,"draft-corner/front","retail",cornerCF,{vignette=false})
	Kit.BuildRun(corner,28,"draft-corner/return","alley",cornerCF*CFrame.new(18,0,14)*CFrame.Angles(0,math.rad(-90),0),{vignette=false})
	corner.WorldPivot=cornerCF
	caption(compositions,cornerCF*CFrame.new(0,16,1),42,"CORNER / FRONT + RETURN")
	-- Curated street context for reading adjacency. Entirely on this isolated preview deck.
	local street=Instance.new("Folder");street.Name="03_StreetView";street.Parent=gallery
	local streetCF=origin*CFrame.new(132,0,streetZ)
	part(street,"PreviewAsphalt",streetCF*CFrame.new(0,-.02,-25),Vector3.new(312,.15,32),Color3.fromRGB(54,57,60))
	part(street,"PreviewSidewalk",streetCF*CFrame.new(0,.05,-5),Vector3.new(312,.2,8),Color3.fromRGB(165,164,155))
	part(street,"PreviewCurb",streetCF*CFrame.new(0,.15,-9),Vector3.new(312,.3,.35),Color3.fromRGB(195,193,183))
	for x=-150,150,12 do part(street,"SidewalkJoint",streetCF*CFrame.new(x,.16,-5),Vector3.new(.05,.05,8),Color3.fromRGB(110,110,107)) end
	local ids={"16_ChainBurger","19_LocalShop","18_PosterKonbini","24_ConcreteSparse","26_BrickResidential","30_OpenGarage","27_TownhouseColumns","29_RaisedEntry","34_TwoStoreyGlass"}
	local total=0;for _,id in ids do total+=Catalog.Get(id).width end
	local cursor=-total/2
	for i,id in ids do
		local s=Catalog.Get(id);local cf=streetCF*CFrame.new(cursor+s.width/2,0,0)
		local model=Kit.Build(street,id,cf,{seed=800+i,adSeed=900+i,vignette=true,mirror=i%3==0,brand=Catalog.Brand(id,"street-view/"..i)})
		illuminate(model)
		model.Name="Street_"..id
		-- Quiet upper-floor silhouettes are preview set dressing, not an upper-floor kit.
		local base=(s.height or 12.5)+4.5;local rows=i%2+1
		local color=Catalog.PALETTES[s.palette].wall
		part(street,"PreviewUpperBody",cf*CFrame.new(0,base+rows*6.25,5),Vector3.new(s.width,rows*12.5,10),color)
		part(street,"PreviewFloorBand",cf*CFrame.new(0,base-2.25,5),Vector3.new(s.width,4.5,10),color)
		for row=1,rows do for x=-s.width/2+4,s.width/2-2,7 do
			local y=base+(row-.5)*12.5
			part(street,"PreviewUpperWindow",cf*CFrame.new(x,y,-.08),Vector3.new(3.8,5.6,.18),Color3.fromRGB(70,87,89))
			for _,edge in {-1,1} do
				part(street,"PreviewWindowJamb",cf*CFrame.new(x+edge*2,y,-.19),Vector3.new(.15,5.9,.2),Color3.fromRGB(134,137,133))
				part(street,"PreviewWindowRail",cf*CFrame.new(x,y+edge*2.9,-.19),Vector3.new(4.1,.15,.2),Color3.fromRGB(134,137,133))
			end
			if s.family=="residential" then
				part(street,"PreviewBalconySlab",cf*CFrame.new(x,y-3.1,-1.6),Vector3.new(5,.35,3.3),color)
				part(street,"PreviewBalconyTopRail",cf*CFrame.new(x,y-.8,-3),Vector3.new(5,.1,.12),Color3.fromRGB(85,80,72))
				for dx=-2.4,2.4,.6 do part(street,"PreviewBalconyBar",cf*CFrame.new(x+dx,y-1.95,-3),Vector3.new(.08,2.3,.1),Color3.fromRGB(85,80,72)) end
			end
		end end
		part(street,"PreviewDrainPipe",cf*CFrame.new(s.width/2-.55,(base+rows*12.5)/2,-.35),Vector3.new(.16,base+rows*12.5,.18),Color3.fromRGB(172,165,150))
		if s.family=="residential" then
			part(street,"PreviewACBox",cf*CFrame.new(-s.width/2+1.9,base+1.5,-.7),Vector3.new(2.7,1.7,1.0),Color3.fromRGB(196,191,177))
		end
		cursor+=s.width
	end
	gallery:SetAttribute("State","ready");library:SetAttribute("State","ready")
	gallery:SetAttribute("DraftTypes",#Catalog.TYPES)
	gallery:SetAttribute("Revision",Catalog.VERSION);library:SetAttribute("Revision",Catalog.VERSION)
	game:GetService("ChangeHistoryService"):SetWaypoint("Ground facade draft gallery")
	return gallery,library
end

function Drafts.Focus(id)
	local root=assert(workspace:FindFirstChild(ROOT),"Generate the gallery first")
	local camera=workspace.CurrentCamera
	if root:GetAttribute("PreviousCamera")==nil then
		root:SetAttribute("PreviousCamera",camera.CFrame);root:SetAttribute("PreviousCameraType",camera.CameraType.Name)
	end
	local origin=root:GetAttribute("Origin")
	local target=root:FindFirstChild("01_IndividualTypes"):FindFirstChild(id or "")
	camera.CameraType=Enum.CameraType.Scriptable
	if target and target:IsA("Model") then
		local cf=target:GetPivot()
		local h=target:GetAttribute("FacadeHeight") or 12.5
		camera.CFrame=CFrame.lookAt((cf*CFrame.new(-6,h*.8+3,-math.max(42,h*2))).Position,(cf*CFrame.new(0,h*.45,0)).Position)
		game:GetService("Selection"):Set({target})
	else
		camera.CFrame=CFrame.lookAt((origin*CFrame.new(132,270,-180)).Position,(origin*CFrame.new(132,5,230)).Position)
		game:GetService("Selection"):Set({root})
	end
end

function Drafts.FocusStreet()
	local root=assert(workspace:FindFirstChild(ROOT),"Generate gallery first")
	Drafts.Focus()
	local cf=root:GetAttribute("Origin")*CFrame.new(132,0,root:GetAttribute("StreetViewZ") or 550)
	workspace.CurrentCamera.CFrame=CFrame.lookAt((cf*CFrame.new(-42,7,-45)).Position,(cf*CFrame.new(-37,8,0)).Position)
	game:GetService("Selection"):Set({root:FindFirstChild("03_StreetView")})
end

function Drafts.Upgrade(origin)
	local root=workspace:FindFirstChild(ROOT)
	if root and root:GetAttribute("Revision")==Catalog.VERSION and root:GetAttribute("State")=="ready" then return Drafts.Generate() end
	local archive=game.ServerStorage:FindFirstChild("GroundFacadeDraftArchive")
	if archive then assert(archive:GetAttribute("GroundFacadeOwner")==VERSION,"Unowned archive")
	else archive=ownRoot(game.ServerStorage,"GroundFacadeDraftArchive") end
	local snapshot=Instance.new("Folder");snapshot.Name="BeforeRevision"..Catalog.VERSION.."_"..tostring(os.time());snapshot.Parent=archive
	for _,pair in {{workspace,ROOT},{game.ServerStorage,LIBRARY}} do
		local object=pair[1]:FindFirstChild(pair[2])
		if object then assert(object:GetAttribute("GroundFacadeOwner")==VERSION,"Unowned draft root");object:Clone().Parent=snapshot end
	end
	local oldOrigin=root and root:GetAttribute("Origin")
	-- Keep owner-placed spawns and the live glass demo across gallery replacement.
	local retained={}
	if root then for _,child in root:GetChildren() do
		if child:IsA("SpawnLocation") or child.Name=="04_GlassDemo" then child.Parent=game.ServerStorage;table.insert(retained,child) end
	end end
	Drafts.Clear()
	local gallery,library=Drafts.Generate(origin or oldOrigin)
	for _,child in retained do child.Parent=gallery end
	return gallery,library
end

function Drafts.RestoreCamera()
	local root=workspace:FindFirstChild(ROOT)
	if root and root:GetAttribute("PreviousCamera") then
		workspace.CurrentCamera.CFrame=root:GetAttribute("PreviousCamera")
		workspace.CurrentCamera.CameraType=Enum.CameraType[root:GetAttribute("PreviousCameraType")]
		root:SetAttribute("PreviousCamera",nil);root:SetAttribute("PreviousCameraType",nil)
	end
end

function Drafts.Clear()
	Drafts.RestoreCamera()
	for _,pair in {{workspace,ROOT},{game.ServerStorage,LIBRARY}} do
		local root=pair[1]:FindFirstChild(pair[2])
		if root then
			assert(root:GetAttribute("GroundFacadeOwner")==VERSION,"Refusing to clear unowned object")
			root:Destroy()
		end
	end
end
return Drafts
