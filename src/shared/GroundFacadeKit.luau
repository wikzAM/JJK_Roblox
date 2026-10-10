--!nonstrict
-- Standalone facade drafts. Requiring this module does not build anything.
-- Pivot: centre of bay, slab TOP at Y=0, exterior faces local -Z.
-- Layout returns reusable data; Build materialises it for edit previews or a future client renderer.
local Catalog = require(script.Parent.GroundFacadeCatalog)
local Expansion = require(script.Parent.GroundFacadeExpansion)
local GlassVisual = require(script.Parent.GlassVisual)
local HttpService = game:GetService("HttpService")
local Kit = {}
local GLASS = Color3.fromRGB(105,132,137)
local WOOD = Color3.fromRGB(111,80,51)
local WHITE = Color3.fromRGB(239,234,220)
local M = Enum.Material

local function finite(v) return type(v)=="number" and v==v and math.abs(v)<1e12 end

function Kit.Layout(id, options)
	options=options or {}
	local spec=Catalog.Get(id)
	if options.allowEntrance==false and (options.role==nil or options.role=="entrance") then options=table.clone(options);options.role="window" end
	if spec.generation and spec.generation>=2 then return Expansion.Layout(spec,options) end
	if options.role=="window" or options.role=="blind" then
		local quiet=table.clone(Catalog.Get(options.role=="blind" and "40_PanelSeams" or "41_HighSlit"))
		quiet.id=id;quiet.width=spec.width;quiet.minWidth=spec.minWidth;quiet.maxWidth=spec.maxWidth;quiet.palette=spec.palette
		return Expansion.Layout(quiet,options)
	end
	local w,h=options.width or spec.width,options.height or 12.5
	assert(finite(w) and w>=spec.minWidth and w<=spec.maxWidth,"Width outside this type's fit range")
	assert(finite(h) and h>=10.5 and h<=24,"Ground facade clear height must be 10.5..24 studs")
	local role=options.role or "entrance"
	assert(role=="entrance" or role=="window" or role=="blind","Unknown facade role")
	local seed=options.seed or Catalog.Seed(id)
	assert(finite(seed),"Invalid seed")
	local rng=Random.new(seed)
	local pal=assert(Catalog.PALETTES[options.palette or spec.palette],"Unknown facade palette")
	local accent=options.accent or spec.accent or pal.accent
	local out={id=id,width=w,height=h,seed=seed,role=role,parts={}}
	local function p(name,x,y,z,sx,sy,sz,color,material,kind,transparency,rotation)
		assert(sx>=0.05 and sy>=0.05 and sz>=0.05,"Undersize facade part: "..name)
		local cf=CFrame.new(x,y,z)*(rotation or CFrame.identity)
		local row={name=name,cframe=cf,size=Vector3.new(sx,sy,sz),color=color,material=material or M.SmoothPlastic,
			kind=kind or "trim",transparency=transparency or 0}
		table.insert(out.parts,row)
		return row
	end
	local function text(row,value,ink,face)
		row.text=value; row.ink=ink or WHITE; row.face=face or Enum.NormalId.Front
		return row
	end
	local function sign(name,x,y,z,sx,sy,value,bg,ink,face)
		return text(p(name,x,y,z,sx,sy,0.24,bg or accent,M.SmoothPlastic,"sign"),value,ink,face)
	end
	local function planter(x,z,wide)
		wide=wide or 2.8
		local group="planter/"..tostring(#out.parts+1)
		local box=p("Planter",x,0.85,z,wide,1.7,2.3,pal.trim,M.Concrete,"prop")
		box.supportGroup=group;box.supportBase=true;box.supportLocalBottom=Vector3.new(x,0,z)
		local plant=p("ClippedGreenery",x,2.1,z,wide-0.3,1.4,2,Color3.fromRGB(65,87,62),M.Grass,"prop")
		plant.supportGroup=group
	end
	local function canopy(depth,color)
		p("Canopy",0,h-2.8,-depth/2,w-0.8,0.45,depth,color or pal.trim,M.Metal)
		p("CanopyWarmStrip",0,h-3.08,-depth+0.5,w-2,0.12,0.22,Color3.fromRGB(237,207,155),M.Neon,"light")
	end
	local function blade(value)
		local x=w/2-1.1
		p("BladeBracket",x,h-3.0,-1.4,0.18,0.18,2.5,pal.trim,M.Metal)
		local row=p("BladeSign",x,h-4.7,-2.1,0.3,3.6,2.4,accent,M.SmoothPlastic,"sign")
		text(row,value,WHITE,Enum.NormalId.Right);row.twoSided=true
	end
	local feature=spec.feature
	local pier=(feature=="stoneLobby" or feature=="hotel") and 1.4 or 0.65
	local opening=w-2*pier
	local head=h-2.7
	local recess=spec.depth
	local sill=(feature=="glassLobby" or feature=="showroom") and 0.35 or 1.2
	if feature=="noren" or feature=="lattice" then sill=2 end
	local entry=role=="entrance" and spec.door~="none"
	local doorW=spec.door=="single" and 4.8 or 7.2
	if feature=="directory" then doorW=6 end
	local doorH=math.min(9.4,head-0.4)
	local doorX=(feature=="awning" or feature=="bakery" or feature=="mail") and -w*0.20 or 0
	if feature=="noren" or feature=="lattice" then doorX=w*0.17 end
	local doorZ=recess
	-- Piers meet at the stitch boundary, never extend beyond it.
	for _,x in {-w/2+pier/2,w/2-pier/2} do
		p("EndPier",x,h/2,0,pier,h,0.85,pal.wall,feature=="bakery" and M.Brick or M.Concrete,"wall")
	end
	p("HeadBand",0,h-1.35,0,opening,2.7,0.8,pal.wall,M.Concrete,"wall")
	-- The buried plinth hides the existing slab edge; it does not change or carve the floor.
	local plinth=options.plinthDrop or 4.5
	assert(finite(plinth) and plinth>=0 and plinth<=12,"Invalid plinth drop")
	if plinth>0 then p("BuriedPlinth",0,-plinth/2,0,w,plinth,0.8,pal.wall,M.Concrete,"plinth") end
	local function window(x0,x1)
		local span=x1-x0
		if span<0.8 then return end
		local count=math.max(1,math.ceil(span/7))
		local pw=span/count
		p("Kickplate",(x0+x1)/2,sill/2,0,span,sill,0.7,pal.wall,feature=="bakery" and M.Brick or M.Concrete,"wall")
		for i=1,count do
			local x=x0+(i-0.5)*pw
			p("ShopGlazing",x,(head+sill)/2,0.35,pw-0.14,head-sill,0.18,GLASS,M.Glass,"glass",0.36)
			if i<count then p("Mullion",x0+i*pw,(head+sill)/2,0.17,0.20,head-sill,0.26,pal.trim,M.Metal) end
		end
		for _,x in {x0,x1} do p("WindowEndStile",x,(head+sill)/2,0.17,.20,head-sill,.26,pal.trim,M.Metal) end
		p("SillTrim",(x0+x1)/2,sill,0.08,span,0.16,0.38,pal.trim,M.Metal)
		p("WindowHead",(x0+x1)/2,head,0.08,span,0.18,0.38,pal.trim,M.Metal)
	end
	if feature=="shutter" or role=="blind" then
		p("ShutterSheet",0,head/2,0.1,opening,head,0.35,accent,M.Metal,"wall")
		for y=0.5,head,0.55 do p("ShutterRib",0,y,-0.12,opening,0.07,0.08,pal.trim,M.Metal) end
		p("ShutterLock",0,0.7,-0.25,0.5,0.4,0.18,pal.trim,M.Metal)
	elseif entry then
		local left,right=doorX-doorW/2,doorX+doorW/2
		window(-opening/2,left-0.25);window(right+0.25,opening/2)
		-- Three-dimensional reveal: jambs, soffit, inset transom and threshold.
		for _,x in {left-0.125,right+0.125} do p("DoorReveal",x,head/2,recess/2,0.30,head,recess+0.4,pal.trim,M.Metal) end
		p("DoorSoffit",doorX,head,recess/2,doorW+0.48,0.24,recess+0.4,pal.trim,M.Metal)
		p("Threshold",doorX,0.10,recess/2,doorW,0.2,recess+0.5,pal.wall,M.Concrete,"threshold")
		p("DoorTransom",doorX,(head+doorH)/2,doorZ,doorW,head-doorH,0.18,GLASS,M.Glass,"glass",0.32)
		local leaves=spec.door=="single" and 1 or 2
		for i=1,leaves do
			local lw=doorW/leaves
			local x=doorX-doorW/2+(i-0.5)*lw
			p("DoorGlass",x,doorH/2,doorZ,lw-0.16,doorH-0.15,0.18,GLASS,M.Glass,"door",0.32)
			for _,edge in {-1,1} do p("DoorStile",x+edge*(lw/2-0.08),doorH/2,doorZ-0.15,0.16,doorH,0.24,pal.trim,M.Metal) end
			p("DoorBottomRail",x,0.25,doorZ-0.15,lw,0.4,0.26,pal.trim,M.Metal)
			p("DoorTopRail",x,doorH-0.1,doorZ-0.15,lw,0.2,0.26,pal.trim,M.Metal)
			p("DoorHandle",x+(leaves==1 and lw*0.32 or (i==1 and lw*0.32 or -lw*0.32)),4.4,doorZ-0.38,0.12,1.4,0.16,accent,M.Metal)
		end
		out.door={x=doorX,width=doorW,height=doorH,recess=recess,interactive=false}
	else
		window(-opening/2,opening/2)
	end
	local brand=options.brand or spec.brand
	local sub=options.subtitle or spec.subtitle
	if role=="window" and not options.brand then brand="";sub="" end
	if brand~="" then
		local quiet=feature=="display" or feature=="stoneLobby" or feature=="glassLobby" or feature=="mail"
		sign("FasciaSign",0,h-1.1,-0.53,w-2*pier-0.5,1.85,brand,quiet and pal.wall or accent,quiet and pal.trim or WHITE)
	end
	if feature=="stripe" then
		for i,c in {accent,WHITE,Color3.fromRGB(63,82,145)} do p("BrandStripe",0,h-2.3+(i-2)*0.16,-0.5,opening,0.16,0.16,c,M.SmoothPlastic,"sign") end
		if entry then sign("OpeningHours",-w/2+2.6,6,-0.1,3.1,1.8,"24H",accent) end
	elseif feature=="awning" or feature=="bakery" then
		local depth=3
		p("FabricAwning",0,h-3.0,-1.4,opening,0.22,depth,accent,M.Fabric,"trim",0,CFrame.Angles(math.rad(-12),0,0))
		p("AwningValance",0,h-3.5,-2.85,opening,0.55,0.15,accent,M.Fabric)
		if entry then sign("MenuBoard",w/2-3.2,3.7,-0.35,3.4,4.2,feature=="bakery" and "PAN\nBREAD\nTAKE AWAY" or "COFFEE\nTEA\nTAKE AWAY",pal.trim);blade(feature=="bakery" and "PAN" or "喫茶") end
	elseif feature=="noren" then
		if entry then
			for i=1,3 do p("NorenPanel",doorX-doorW/2+(i-0.5)*doorW/3,doorH-0.95,0.5,doorW/3-0.10,1.8,0.12,accent,M.Fabric) end
			local x=-w/2+3.2
			p("TicketMachine",x,2.7,-0.55,2.7,5.4,1.4,WHITE,M.Metal,"prop")
			sign("TicketMenu",x,3.2,-1.32,2.3,2.8,"食券\nRAMEN\n¥ 900",pal.trim)
			p("TicketSlot",x,1.0,-1.32,1.5,0.16,0.12,pal.trim,M.Metal,"prop")
			blade("麺")
		end
	elseif feature=="lattice" then
		local x0,x1=-opening/2,(entry and doorX-doorW/2-0.4 or opening/2)
		for x=x0+0.5,x1-0.2,0.7 do p("TimberSlat",x,head/2,-0.1,0.16,head,0.25,WOOD,M.Wood) end
		canopy(2,WOOD)
		if entry then
			for _,x in {-w/2+2.0,w/2-2.0} do
				p("Lantern",x,7.0,-1.3,1.1,2.0,1.1,Color3.fromRGB(204,88,53),M.Neon,"light")
				p("LanternCap",x,8.05,-1.3,1.15,0.15,1.15,pal.trim,M.Metal)
			end
			blade("酒場")
		end
	elseif feature=="display" or feature=="showroom" then
		p("DisplayLight",0,head-0.3,2.4,w-3,0.12,0.22,WHITE,M.Neon,"light")
		if options.vignette then
			for _,x in {-w*0.30,w*0.30} do
				p("DisplayPlinth",x,0.75,2.5,3,1.5,2.2,pal.wall,M.Concrete,"prop")
				p("DisplayObject",x,2.6,2.5,1.4,2.2,1.2,accent,M.SmoothPlastic,"prop")
			end
		end
	elseif feature=="pharmacy" then
		local x=-w/2+2.8
		p("PharmacyCrossV",x,5.8,-0.2,0.65,2.1,0.22,accent,M.SmoothPlastic,"sign")
		p("PharmacyCrossH",x,5.8,-0.32,2.1,0.65,0.22,accent,M.SmoothPlastic,"sign")
		if entry then blade("薬") end
	elseif feature=="directory" then
		if entry then
			sign("TenantDirectory",-w/2+2.6,4.7,-0.18,3.2,6,"4F  OFFICE\n────────\n3F  STUDIO\n────────\n2F  CAFE\n────────\n1F  ENTRY",pal.trim)
			blade("2F\n3F\n4F")
		end
		canopy(2.0)
	elseif feature=="stoneLobby" or feature=="glassLobby" then
		canopy(feature=="stoneLobby" and 3.5 or 2.5)
		if entry then
			planter(-w/2+2.6,-1.1,3.3);planter(w/2-2.6,-1.1,3.3)
			sign("LobbyDirectory",w/2-5.4,4.5,-0.1,2.8,3.2,"OFFICE\nRECEPTION",pal.trim)
		end
	elseif feature=="hotel" or feature=="timberHotel" then
		canopy(feature=="hotel" and 5 or 3.2)
		if feature=="timberHotel" then
			for _,side in {-1,1} do for i=0,4 do p("TimberFin",side*(w/2-1.4-i*0.55),head/2,-0.1,0.18,head,0.7,WOOD,M.Wood) end end
		end
		if entry then
			planter(-w/2+3.5,-1.6,4);planter(w/2-3.5,-1.6,4)
			sign("HotelEntryPlaque",w/2-5.6,5.3,-0.32,2.4,3.8,"HOTEL\n入口",pal.trim,accent)
		end
	elseif feature=="mail" then
		if entry then
			local x=w/2-4
			p("MailBank",x,3.8,0.1,4.5,3.0,0.6,pal.trim,M.Metal,"prop")
			for i=1,3 do p("MailSlot",x,2.9+(i-1)*0.9,-0.25,3.7,0.12,0.12,accent,M.Metal,"prop") end
			p("Intercom",doorX+doorW/2+0.7,4.5,0,0.6,1.3,0.25,pal.trim,M.Metal,"prop")
		end
		canopy(1.8)
	end
	if entry and sub~="" and feature~="directory" then
		sign("DoorDecal",doorX,6.3,doorZ-0.3,doorW-0.6,0.65,sub,pal.trim)
	end
	-- Preview-only shallow interior, never a solid opaque wall across the facade plane.
	if options.vignette then
		p("PreviewInteriorFloor",0,-0.15,3.4,opening,0.3,6.8,Color3.fromRGB(131,126,117),M.Concrete,"preview")
		p("PreviewInteriorBack",0,head/2,6.8,opening,head,0.3,Color3.fromRGB(74,71,64),M.SmoothPlastic,"preview")
		p("PreviewCeiling",0,head,3.4,opening,0.2,6.8,pal.wall,M.SmoothPlastic,"preview")
		p("PreviewCeilingGlow",0,head-0.2,4.2,opening-2,0.12,0.5,Color3.fromRGB(236,214,176),M.Neon,"light")
		if feature=="stripe" then
			for _,x in {-w*0.3,w*0.3} do p("PreviewShelf",x,2.0,5.0,6,4,0.8,pal.wall,M.SmoothPlastic,"preview") end
		elseif feature=="hotel" or feature=="glassLobby" or feature=="stoneLobby" then
			p("PreviewReception",-w*0.24,1.6,4.7,6,3.2,1.8,WOOD,M.Wood,"preview")
		end
	end
	-- Controlled per-bay variation: an accent plaque and optional mirrored door placement.
	out.variant=rng:NextInteger(1,3)
	if entry then sign("AddressPlate",-w/2+1.1,1.9,-0.52,0.75,0.8,tostring(10+out.variant),pal.trim) end
	if options.mirror then
		-- Mirror the whole bay, including its props, not just the door: otherwise
		-- the ramen ticket machine or menu board can end up across the entrance.
		for _,row in out.parts do
			local cf=row.cframe
			local function flip(v) return Vector3.new(-v.X,v.Y,v.Z) end
			row.cframe=CFrame.fromMatrix(flip(cf.Position),-flip(cf.XVector),flip(cf.YVector))
			if row.supportLocalBottom then row.supportLocalBottom=flip(row.supportLocalBottom) end
			if row.face==Enum.NormalId.Right then row.face=Enum.NormalId.Left
			elseif row.face==Enum.NormalId.Left then row.face=Enum.NormalId.Right end
		end
		if out.door then out.door.x=-out.door.x end
	end
	return out
end

local function addText(part,row)
	local gui=Instance.new("SurfaceGui")
	gui.Name="FacadeTypography";gui.Face=row.face;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud=40;gui.LightInfluence=0.2;gui.AlwaysOnTop=false;gui.MaxDistance=220;gui.Parent=part
	local label=Instance.new("TextLabel")
	label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Text=row.text
	label.Font=Enum.Font.SourceSansSemibold;label.TextScaled=true;label.TextColor3=row.ink
	label.TextWrapped=true;label.Parent=gui
	local pad=Instance.new("UIPadding")
	pad.PaddingLeft=UDim.new(0.04,0);pad.PaddingRight=UDim.new(0.04,0);pad.PaddingTop=UDim.new(0.08,0);pad.PaddingBottom=UDim.new(0.08,0);pad.Parent=label
	if row.twoSided then local other=gui:Clone();other.Face=row.face==Enum.NormalId.Right and Enum.NormalId.Left or Enum.NormalId.Right;other.Parent=part end
end

function Kit.Build(parent,id,frame,options)
	if options and options.nameSeed~=nil and options.brand==nil then
		options=table.clone(options)
		options.brand=Catalog.Brand(id,options.key or id.."/"..tostring(options.seed or Catalog.Seed(id)),options.nameSeed)
	end
	local layout=Kit.Layout(id,options)
	frame=frame or CFrame.identity
	local model=Instance.new("Model")
	model.Name="GroundFacade_"..id
	model:SetAttribute("GroundFacadeDraft",true);model:SetAttribute("FacadeType",id)
	model:SetAttribute("FacadeKitVersion",Catalog.VERSION);model:SetAttribute("FacadeSeed",layout.seed)
	model:SetAttribute("FacadeWidth",layout.width);model:SetAttribute("FacadeHeight",layout.height)
	model:SetAttribute("FacadeRole",layout.role);model:SetAttribute("DoorsInteractive",false)
	model:SetAttribute("FacadePalette",options and options.palette or Catalog.Get(id).palette)
	if options and options.nameSeed then model:SetAttribute("FacadeNameSeed",options.nameSeed) end
	local portals={}
	for _,q in layout.portals or (layout.door and {layout.door} or {}) do table.insert(portals,{x=q.x,width=q.width,y=q.y or 0,height=q.height,recess=q.recess,name=q.name or "entry"}) end
	model:SetAttribute("FacadePortals",HttpService:JSONEncode(portals))
	model:SetAttribute("FacadeFloorSpan",layout.floorSpan or 1);model:SetAttribute("FacadeRequiresVoid",layout.requiresVoid or false)
	if layout.adSeed then model:SetAttribute("FacadeAdSeed",layout.adSeed) end
	if layout.closed then model:SetAttribute("FacadeClosed",true) end
	local ok,err=pcall(function()
		for _,row in layout.parts do
			local part=Instance.new("Part")
			part.Name=row.name;part.Size=row.size;part.CFrame=frame*row.cframe
			part.Color=row.color;part.Material=row.material;part.Transparency=row.transparency
			if row.shape then part.Shape=row.shape end
			part.Reflectance=row.kind=="glass" and 0.06 or 0
			part.Anchored=true;part.CanQuery=true;part.CanTouch=false
			-- Draft doors are a traversable visual portal; windows/walls remain solid.
			part.CanCollide=row.kind=="wall" or row.kind=="glass" or row.kind=="plinth" or row.kind=="threshold"
			part.CastShadow=row.kind~="light" and row.kind~="glass"
			part.TopSurface=Enum.SurfaceType.Smooth;part.BottomSurface=Enum.SurfaceType.Smooth
			part:SetAttribute("FacadePieceKind",row.kind)
			if row.supportGroup then
				part:SetAttribute("FacadeSupportGroup",row.supportGroup)
				part:SetAttribute("FacadeSupportBase",row.supportBase or false)
				if row.supportLocalBottom then
					part:SetAttribute("FacadeSupportLocalX",row.supportLocalBottom.X)
					part:SetAttribute("FacadeSupportLocalBottomY",row.supportLocalBottom.Y)
					part:SetAttribute("FacadeSupportLocalZ",row.supportLocalBottom.Z)
				end
			end
			part:AddTag("NoCSG")
			part.Parent=model
			if row.material==M.Glass then
				GlassVisual.Capture(part,"ground/"..(options and options.key or id.."/"..layout.seed).."/"..tostring(_),part.CanCollide)
			end
			if row.text then addText(part,row) end
		end
		-- A privacy overlay belongs to its physical pane so it disappears with
		-- shattered/removed glass instead of floating across the broken opening.
		for _,film in model:GetChildren() do if film:IsA("BasePart") and film.Name=="PrivacyFilm" then
			local best,dist=nil,math.huge
			for _,pane in model:GetChildren() do if pane:IsA("BasePart") and pane:HasTag("GlassPane") then
				local d=(pane.Position-film.Position).Magnitude;if d<dist then best,dist=pane,d end
			end end
			if best then film.Parent=best;film.CanCollide=false;film.CanQuery=false end
		end end
		-- Window stickers belong to their pane, so paper ads cannot float across
		-- a shattered opening. Fascia signs and wall-mounted boards stay separate.
		for _,overlay in model:GetChildren() do
			if overlay:IsA("BasePart") and (overlay.Name=="JapaneseWindowAd" or overlay.Name=="AdOfferStrip" or overlay.Name=="DoorDecal") then
				local nearest,best=nil,math.huge
				for _,pane in model:GetChildren() do if pane:IsA("BasePart") and pane:HasTag("GlassPane") then
					local q=pane.CFrame:PointToObjectSpace(overlay.Position)
					if math.abs(q.X)<=pane.Size.X/2+.15 and math.abs(q.Y)<=pane.Size.Y/2+.15 and math.abs(q.Z)<.8 and q.Magnitude<best then nearest,best=pane,q.Magnitude end
				end end
				if nearest then overlay:SetAttribute("GlassAttachedOverlay",true);overlay.Parent=nearest;overlay.CanCollide=false;overlay.CanQuery=false end
			end
		end
		model.WorldPivot=frame
		model.Parent=parent
	end)
	if not ok then model:Destroy();error(err) end
	return model,layout
end

-- Exact-length composition, no scaled doorways and no half shop at a corner.
-- Stable key should be SourceSliceId .. piece/run identity, not position or child order.
function Kit.PlanRun(width,key,profile,options)
	options=options or {}
	assert(finite(width) and width>0 and width<=1000,"Invalid facade run width")
	assert(type(key)=="string" and #key>0,"Run needs a stable string key")
	assert(Catalog.PROFILES[profile],"Unknown facade profile")
	local target=options.targetWidth or 28
	assert(finite(target) and target>=14 and target<=60,"Target bay width must be 14..60 studs")
	local n=math.max(1,math.floor(width/target+0.5))
	local bays
	for count=n,1,-1 do
		local bw=width/count
		local rows={}
		for i=1,count do
			local spec=options.facadeType and Catalog.Get(options.facadeType) or Catalog.Pick(profile,key.."/"..i,bw,options.height or 12.5)
			if spec and (bw<spec.minWidth or bw>spec.maxWidth or (options.height or 12.5)<(spec.minHeight or 10.5) or (options.height or 12.5)>(spec.maxHeight or 24)) then spec=nil end
			if not spec then rows=nil;break end
			table.insert(rows,{id=spec.id,width=bw,seed=Catalog.Seed(key.."/"..i),role="entrance"})
		end
		if rows then bays=rows;break end
	end
	-- Too short/awkward to fit a tenant: one simple infill, never a crushed door.
	if not bays then return {{infill=true,width=width,role="blind"}} end
	if profile=="office" or profile=="hotel" or profile=="residential" or profile=="chains" or profile=="twoStorey" or profile=="atrium" then
		local main=options.mainBay or options.portalIndex or (Catalog.Seed(key.."/main")%#bays+1)
		assert(type(main)=="number" and main%1==0 and main>=1 and main<=#bays,"mainBay must select an existing bay")
		for i,b in bays do b.role=i==main and "entrance" or "window" end
		local chosen=bays[main].id
		for _,b in bays do b.id=chosen end
	end
	if profile=="blind" or options.role=="blind" then for _,b in bays do b.role="blind" end
	elseif profile=="window" or options.role=="window" or options.allowEntrance==false then for _,b in bays do b.role="window" end end
	return bays
end

function Kit.BuildRun(parent,width,key,profile,frame,options)
	options=options or {};frame=frame or CFrame.identity
	if profile=="twoStorey" or profile=="atrium" then
		assert(options.height and options.height>=27.5,"Tall frontage needs explicit two-storey clearance")
		if profile=="atrium" then assert(options.confirmedVoid==true,"Atrium facade needs confirmed existing slab-free void") end
	end
	local bays=Kit.PlanRun(width,key,profile,options)
	local holder=Instance.new("Model");holder.Name="GroundFacadeRun_"..profile
	local cursor=-width/2
	local ok,err=pcall(function()
		for index,bay in bays do
			local cf=frame*CFrame.new(cursor+bay.width/2,0,0)
			if bay.infill then
				local h=options.height or 12.5
				assert(finite(h) and h>=10.5 and h<=((profile=="twoStorey" or profile=="atrium") and 36 or 24),"Invalid facade height")
				local p=Instance.new("Part");p.Name="FacadeInfill";p.Size=Vector3.new(width,h,0.8)
				p.CFrame=cf*CFrame.new(0,h/2,0);p.Color=Catalog.PALETTES[options.palette or "stone"].wall;p.Material=M.Concrete
				p.Anchored=true;p.CanTouch=false;p:AddTag("NoCSG");p.Parent=holder
			else
				local opts=table.clone(options);opts.width=bay.width;opts.seed=bay.seed;opts.role=bay.role
				opts.mirror=bay.seed%2==0
				opts.key=key.."/bay"..index
				opts.brand=bay.role=="entrance" and (options.brand or Catalog.Brand(bay.id,key.."/"..index,options.nameSeed)) or ""
				Kit.Build(holder,bay.id,cf,opts)
			end
			cursor+=bay.width
			if index<#bays then
				-- Adjacent bay edges need a physical overlap, especially at rotated frames.
				local seam=Instance.new("Part");seam.Name="FacadeBayJoint";seam.Size=Vector3.new(.18,options.height or 12.5,.8)
				seam.CFrame=frame*CFrame.new(cursor,seam.Size.Y/2,0);seam.Anchored=true;seam.CanTouch=false
				seam.Material=M.Concrete;seam.Color=Catalog.PALETTES[options.palette or "stone"].wall;seam:AddTag("NoCSG");seam.Parent=holder
			end
		end
		holder.WorldPivot=frame;holder:SetAttribute("FacadeRunKey",key);holder:SetAttribute("GroundFacadeDraft",true)
		holder.Parent=parent
	end)
	if not ok then holder:Destroy();error(err) end
	return holder,bays
end
return Kit
