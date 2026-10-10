--!nonstrict
-- Native-part interpretations of the owner's October 8 Shibuya photographs.
-- Pure layout data. No terrain, building discovery, runtime hooks, or external assets.
local Catalog=require(script.Parent.GroundFacadeCatalog)
local Mount=require(script.Parent.FacadeMount)
local E={}
local M=Enum.Material
local GLASS=Color3.fromRGB(111,139,143)
local WHITE=Color3.fromRGB(235,233,221)
local WOOD=Color3.fromRGB(127,94,63)
local POSTERS={
	{"新発売\nお弁当",Color3.fromRGB(192,61,45)}, {"ランチ\nセット",Color3.fromRGB(218,162,46)},
	{"営業中\nOPEN",Color3.fromRGB(51,114,92)}, {"おすすめ\n珈琲",Color3.fromRGB(69,101,145)},
	{"お持ち帰り\nできます",Color3.fromRGB(180,86,94)}, {"本日の\nおすすめ",Color3.fromRGB(83,124,128)},
	{"新商品\n入荷",Color3.fromRGB(153,84,49)}, {"毎日\nできたて",Color3.fromRGB(97,105,61)},
}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<1e12 end

function E.Layout(spec,options)
	options=options or {}
	local w,h=options.width or spec.width,options.height or spec.height
	assert(finite(w) and w>=spec.minWidth and w<=spec.maxWidth,"Width outside type fit range")
	assert(finite(h) and h>=spec.minHeight and h<=spec.maxHeight,"Height outside type fit range")
	local role=options.role or "entrance"
	if options.allowEntrance==false and role=="entrance" then role="window" end
	assert(role=="entrance" or role=="window" or role=="blind","Unknown facade role")
	local seed=options.seed or Catalog.Seed(spec.id)
	assert(finite(seed),"Invalid seed")
	local rng=Random.new(seed)
	local pal=assert(Catalog.PALETTES[options.palette or spec.palette],"Unknown palette")
	local accent=options.accent or (spec.family=="food" and Color3.fromRGB(174,48,40) or pal.accent)
	local f=spec.feature
	if f=="fastFood" then accent=Color3.fromRGB(182,43,41)
	elseif f=="kingBurger" then accent=Color3.fromRGB(142,51,32)
	elseif f=="coffeeChain" then accent=Color3.fromRGB(28,99,77) end
	local out={id=spec.id,width=w,height=h,seed=seed,role=role,parts={},portals={},floorSpan=spec.floorSpan,requiresVoid=spec.requiresVoid}
	local function p(name,x,y,z,sx,sy,sz,c,mat,kind,t,rot,shape)
		assert(sx>=.05 and sy>=.05 and sz>=.05,"Undersize part: "..name)
		local row={name=name,cframe=CFrame.new(x,y,z)*(rot or CFrame.identity),size=Vector3.new(sx,sy,sz),
			color=c or pal.wall,material=mat or M.Concrete,kind=kind or "trim",transparency=t or 0,shape=shape}
		table.insert(out.parts,row);return row
	end
	local function sign(name,x,y,z,sx,sy,value,bg,ink)
		if value=="" then return end
		local row=p(name,x,y,z,sx,sy,.10,bg or accent,M.SmoothPlastic,"sign")
		row.text=value;row.ink=ink or WHITE;row.face=Enum.NormalId.Front;return row
	end
	local function wall(name,x0,x1,y0,y1,z,depth,mat)
		if x1-x0>=.05 and y1-y0>=.05 then p(name,(x0+x1)/2,(y0+y1)/2,z,x1-x0,y1-y0,depth or .7,pal.wall,mat or M.Concrete,"wall") end
	end
	local function pier(x,width) wall("ConcretePier",x-width/2,x+width/2,0,h,0,.9) end
	local function portal(x,width,y0,height,depth,name)
		table.insert(out.portals,{x=x,width=width,y=y0,height=height,recess=depth,name=name or "entry"})
	end
	local function door(x,width,y0,height,z,opaque)
		if options.mount~="recessed" then z=Mount.PaneZ end
		local leaves=width>5.5 and 2 or 1
		for i=1,leaves do
			local lw=width/leaves;local cx=x-width/2+(i-.5)*lw
			p(opaque and "SteelDoorLeaf" or "EntryGlazing",cx,y0+height/2,z,lw-.16,height-.08,.18,opaque and pal.trim or GLASS,opaque and M.Metal or M.Glass,"door",opaque and 0 or .34)
			for _,dx in {-lw/2+.08,lw/2-.08} do p("EntryStile",cx+dx,y0+height/2,z-.14,.16,height,.24,pal.trim,M.Metal) end
			p("EntryTopRail",cx,y0+height-.1,z-.14,lw,.2,.25,pal.trim,M.Metal)
			p("EntryBottomRail",cx,y0+.2,z-.14,lw,.35,.25,pal.trim,M.Metal)
			p("EntryHandle",cx+lw*.30,y0+4,z-.34,.12,1.4,.16,WHITE,M.Metal)
		end
		for _,dx in {-width/2-.1,width/2+.1} do p("InsetDoorJamb",x+dx,y0+height/2,z/2,.2,height,z+.4,pal.trim,M.Metal) end
		p("InsetDoorSoffit",x,y0+height,z/2,width+.4,.2,z+.4,pal.trim,M.Metal)
		p("EntryThreshold",x,y0+.08,z/2,width,.16,z+.4,pal.wall,M.Concrete,"threshold")
		portal(x,width,y0,height,z)
		out.door=out.door or {x=x,width=width,y=y0,height=height,recess=z,interactive=false}
	end
	local function glass(x0,x1,y0,y1,z,frost)
		if options.mount~="recessed" then z=Mount.PaneZ end
		if x1-x0<.6 or y1-y0<.6 then return end
		local n=math.max(1,math.ceil((x1-x0)/7));local span=(x1-x0)/n
		for i=1,n do
			p("WindowPane",x0+(i-.5)*span,(y0+y1)/2,z,span-.16,y1-y0,.18,GLASS,M.Glass,"glass",frost and .13 or .36)
			if frost then p("PrivacyFilm",x0+(i-.5)*span,y0+(y1-y0)*.32,z-.11,span-.22,(y1-y0)*.62,.05,WHITE,M.SmoothPlastic,"glass",.2) end
			if i<n then p("WindowMullion",x0+i*span,(y0+y1)/2,z-.14,.20,y1-y0,.24,pal.trim,M.Metal) end
		end
		-- Overlap the .08 pane inset; a visible window cannot have open perimeter slits.
		for _,x in {x0,x1} do p("WindowEndStile",x,(y0+y1)/2,z-.14,.20,y1-y0,.24,pal.trim,M.Metal) end
		for _,y in {y0,y1} do p("WindowRail",(x0+x1)/2,y,z-.12,x1-x0,.16,.28,pal.trim,M.Metal) end
	end
	-- Rectangle decomposition creates actual holes in an opaque front.
	local function concrete(holes,mat)
		local xs={-w/2,w/2};local ys={0,h}
		for _,q in holes do table.insert(xs,q[1]);table.insert(xs,q[2]);table.insert(ys,q[3]);table.insert(ys,q[4]) end
		table.sort(xs);table.sort(ys)
		for i=1,#xs-1 do for j=1,#ys-1 do
			local cx,cy=(xs[i]+xs[i+1])/2,(ys[j]+ys[j+1])/2;local empty=false
			for _,q in holes do if cx>q[1] and cx<q[2] and cy>q[3] and cy<q[4] then empty=true;break end end
			if not empty then wall("OpaqueFront",xs[i],xs[i+1],ys[j],ys[j+1],0,.75,mat) end
		end end
	end
	local function canopy(x,width,y,depth,color)
		p("ProjectingCanopy",x,y,-depth/2,width,.35,depth,color or pal.trim,M.Metal)
		p("SoffitStrip",x,y-.23,-depth+.4,width-.8,.1,.16,Color3.fromRGB(229,211,176),M.Neon,"light")
	end
	local function planter(x,z,width)
		local group="planter/"..tostring(#out.parts+1)
		local box=p("PlantedEdgeBox",x,.6,z,width,1.2,1.8,pal.wall,M.Brick,"prop")
		box.supportGroup=group;box.supportBase=true;box.supportLocalBottom=Vector3.new(x,0,z)
		local plant=p("ClippedPlanting",x,1.7,z,width-.2,1.2,1.6,Color3.fromRGB(60,86,56),M.Grass,"prop")
		plant.supportGroup=group
	end
	-- Ad stream is independently seeded. Shape selection and entrance never move with adSeed.
	local ads=options.ads or "normal"
	assert(ads=="none" or ads=="normal" or ads=="dense","Unknown ad density")
	local adSeed=options.adSeed or Catalog.Seed(tostring(seed).."/ads")
	assert(finite(adSeed),"Invalid ad seed")
	local ar=Random.new(adSeed)
	local function posters(x0,x1,y0,y1,z,dense)
		if options.mount~="recessed" then z=Mount.PaneZ-.15 end
		if ads=="none" or x1-x0<2 then return end
		local busy=ads=="dense" or dense
		local n,rows=busy and 3 or 2,busy and 2 or 1
		for tier=1,rows do for i=1,n do
			local pw=math.min(2.7,(x1-x0)/n-.3);local ph=math.min(2.3,(y1-y0)/rows-.2)
			local a=POSTERS[ar:NextInteger(1,#POSTERS)]
			local row=sign("JapaneseWindowAd",x0+(i-.5)*(x1-x0)/n,y0+(tier-.5)*(y1-y0)/rows,z,pw,ph,a[1],a[2])
			row.ad=true
			-- Stylised product/offer block, entirely fictional and asset-free.
			p("AdOfferStrip",row.cframe.X,row.cframe.Y-ph*.37,z-.06,pw*.85,.28,.05,WHITE,M.SmoothPlastic,"sign")
		end end
	end
	local plinth=options.plinthDrop or 4.5
	assert(finite(plinth) and plinth>=0 and plinth<=12,"Invalid plinth drop")
	if plinth>0 then p("BuriedPlinth",0,-plinth/2,0,w,plinth,.8,pal.wall,M.Concrete,"plinth") end
	local entry=role=="entrance"
	local brand=spec.signless and "" or (options.brand or spec.brand)
	if role~="entrance" then brand="" end
	local head=h-2.5
	if role=="blind" and f~="plainWall" and f~="panelWall" and f~="utilityWall" then
		wall("QuietBlindFront",-w/2,w/2,0,h,0,.8)
	elseif role=="window" and spec.generation~=3 then
		-- Continuation bays are quiet wall/window treatments, never duplicate shop
		-- entries, parking portals, menu boards or produce counters in an alley.
		local a,b=-w/2+1.1,w/2-1.1
		concrete({{a,b,3.2,math.min(h-2.2,8.2)}})
		glass(a,b,3.2,math.min(h-2.2,8.2),.3,spec.family=="residential" or spec.family=="service")
	elseif spec.generation==3 then
		if f=="plainWall" then
			wall("PlainConcreteWall",-w/2,w/2,0,h,0,.8)
		elseif f=="panelWall" then
			wall("PanelConcreteWall",-w/2,w/2,0,h,0,.8)
			for x=-w/2+6,w/2-.5,6 do p("VerticalPanelSeam",x,h/2,-.415,.055,h,.06,pal.trim,M.Concrete) end
			p("HorizontalPanelSeam",0,h*.52,-.415,w,.055,.06,pal.trim,M.Concrete)
		elseif f=="highSlit" then
			local a,b=-w/2+1.5,w/2-1.5;local y=h*.65
			concrete({{a,b,y,y+1.5}});glass(a,b,y,y+1.5,.24,true)
			p("SlitRainHood",0,y+1.8,-.48,w-2.4,.15,.8,pal.trim,M.Metal)
		elseif f=="pairedFrost" then
			local ww=math.min(5.2,w*.24);local y=3.5;local top=math.min(8,h-2.2)
			concrete({{-w*.24-ww/2,-w*.24+ww/2,y,top},{w*.24-ww/2,w*.24+ww/2,y,top}})
			for _,x in {-w*.24,w*.24} do glass(x-ww/2,x+ww/2,y,top,.28,true);p("WindowConcreteSill",x,y-.15,-.25,ww+.4,.3,.75,pal.wall,M.Concrete) end
		elseif f=="utilityWall" then
			wall("UtilityConcreteWall",-w/2,w/2,0,h,0,.85)
			p("UtilityVentFrame",w*.2,4.7,-.5,3.4,2.5,.25,pal.trim,M.Metal)
			for y=3.65,5.75,.25 do p("UtilityVentSlat",w*.2,y,-.68,3.0,.1,.2,WHITE,M.Metal) end
			p("VerticalDrainPipe",-w*.32,h/2,-.6,.2,h,.2,WHITE,M.Metal)
			for y=1,h-1,3.5 do p("DrainPipeClamp",-w*.32,y,-.6,.42,.15,.32,pal.trim,M.Metal) end
		elseif f=="rearDoor" then
			local dx=-w*.2;local dw=4.4;local dh=8.1
			local holes={{w*.18,w*.18+3,6.4,8.1}}
			if entry then table.insert(holes,{dx-dw/2,dx+dw/2,0,dh}) end
			concrete(holes);glass(w*.18,w*.18+3,6.4,8.1,.25,true)
			if entry then door(dx,dw,0,dh,.45,true) end
		elseif f=="tiledWall" then
			local a,b=-w*.28,w*.12;local y,top=4.6,math.min(8.2,h-2)
			concrete({{a,b,y,top}},M.Brick);glass(a,b,y,top,.27,true)
			p("LowTiledLedge",0,1,-.25,w,2,1.15,pal.wall,M.Brick,"wall")
			p("BoundaryCoping",0,2.08,-.25,w,.16,1.35,pal.trim,M.Concrete)
		else
			-- Eight new public frontages share framing, but use distinct opaque
			-- opening proportions and fixtures. Window role removes every portal.
			local dx,dw=w*.27,4.8;local dh=8.2
			local sill=f=="clinic" and 2.5 or f=="soba" and 3.2 or f=="timberHouse" and 3.5 or .7
			if f=="laundry" then dx=-w*.27;dw=5.2 end
			if f=="bathhouse" then dx=0;dw=7.2 end
			local wx0,wx1=-w/2+1,w/2-1
			local holes={}
			if entry then table.insert(holes,{dx-dw/2,dx+dw/2,0,dh}) end
			local windows={}
			if entry then
				if dx-dw/2-.4-wx0>.7 then table.insert(windows,{wx0,dx-dw/2-.4}) end
				if wx1-dx-dw/2-.4>.7 then table.insert(windows,{dx+dw/2+.4,wx1}) end
			else table.insert(windows,{wx0,wx1}) end
			for _,q in windows do table.insert(holes,{q[1],q[2],sill,head}) end
			concrete(holes,(f=="bathhouse" or f=="bookshop") and M.Brick or M.Concrete)
			for _,q in windows do glass(q[1],q[2],sill,head,.3,f=="clinic" or f=="timberHouse" or f=="bathhouse") end
			if entry then door(dx,dw,0,dh,1.2,f=="timberHouse" or f=="bathhouse") end
			if f=="laundry" then
				for _,q in windows do p("LaundryTransomBand",(q[1]+q[2])/2,head-1.25,-.1,q[2]-q[1],.2,.5,pal.trim,M.Metal) end
				if entry then for _,x in {w*.04,w*.26} do
					p("LaundryMachineDisplay",x,2.1,1.6,3.8,4.2,1.8,WHITE,M.Metal,"prop")
					p("RoundWasherWindow",x,2.3,.63,.14,2.5,2.5,pal.trim,M.Metal,"prop",0,CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
				end end
			elseif f=="bicycle" then
				local a,b=wx0,dx-dw/2-.4
				p("WorkshopHalfShutter",(a+b)/2,head-1.4,-.05,b-a,2.8,.3,pal.trim,M.Metal,"wall")
				for y=head-2.7,head-.1,.3 do p("WorkshopShutterRib",(a+b)/2,y,-.24,b-a,.07,.09,WHITE,M.Metal) end
				if entry then p("RepairWorkbench",-w*.18,1.6,1.4,w*.36,3.2,1.6,WOOD,M.Wood,"prop") end
			elseif f=="florist" then
				canopy(0,w-.8,head,2.7,Color3.fromRGB(68,106,77))
				for _,x in {-w/2+1,w/2-1} do p("FloristTimberPost",x,head/2,-.2,.4,head,.8,WOOD,M.Wood) end
				if entry then planter(-w*.30,-1.2,3.2);p("FlowerDisplayShelf",-w*.16,2.4,1.6,w*.3,.25,2,WOOD,M.Wood,"prop") end
			elseif f=="clinic" then
				p("ClinicPrivacySpandrel",0,3.3,-.03,w-2,1.4,.4,WHITE,M.SmoothPlastic,"wall")
				-- Split around the door, rather than an opaque bar across its portal.
				out.parts[#out.parts]=nil
				for _,q in windows do p("ClinicPrivacySpandrel",(q[1]+q[2])/2,3.3,-.03,q[2]-q[1],1.4,.4,WHITE,M.SmoothPlastic,"wall") end
				if entry then canopy(dx,dw+1.4,dh+.35,1.8,WHITE) end
			elseif f=="bookshop" then
				for _,q in windows do
					p("DeepBookDisplaySill",(q[1]+q[2])/2,sill+.15,1.0,q[2]-q[1],.3,2,WOOD,M.Wood)
					if entry then for y=2,6.5,1.5 do p("BookDisplayShelf",(q[1]+q[2])/2,y,1.4,q[2]-q[1]-.3,.14,.7,WOOD,M.Wood,"prop") end end
				end
				for _,x in {-w/2+.65,w/2-.65} do p("BookshopPilaster",x,head/2,-.4,.4,head,1.1,pal.wall,M.Brick,"wall") end
			elseif f=="soba" then
				for _,q in windows do for x=q[1]+.2,q[2]-.2,.65 do p("SobaWindowLattice",x,(head+sill)/2,-.02,.12,head-sill,.3,WOOD,M.Wood) end end
				canopy(0,w-1,head,2.1,WOOD)
				if entry then for i=1,4 do p("SobaNoren",dx-dw/2+(i-.5)*dw/4,dh-.75,.4,dw/4-.08,1.5,.12,Color3.fromRGB(58,72,84),M.Fabric) end end
			elseif f=="bathhouse" then
				for _,x in {-w/2+1,w/2-1} do p("TiledEntryPier",x,head/2,-.1,.8,head,1.1,Color3.fromRGB(174,194,195),M.Brick,"wall") end
				if entry then for i=1,2 do p("BathhouseSplitCurtain",dx-dw/2+(i-.5)*dw/2,dh-.8,.4,dw/2-.12,1.6,.12,i==1 and Color3.fromRGB(55,78,125) or Color3.fromRGB(152,63,65),M.Fabric) end end
				canopy(0,w-1,head,2.8,pal.trim)
			elseif f=="timberHouse" then
				for _,q in windows do for x=q[1]+.3,q[2]-.3,.55 do p("HouseTimberScreen",x,(head+sill)/2,-.4,.15,head-sill,.9,WOOD,M.Wood) end end
				if entry then canopy(dx,dw+.9,dh+.3,2.5,WOOD) end
			end
		end
	elseif f=="garage" or f=="twinGarage" or f=="pilotis" or f=="loading" then
		local side=1.0;local top=h-2.0
		pier(-w/2+side/2,side);pier(w/2-side/2,side)
		wall("ParkingHeader",-w/2+side,w/2-side,top,h,0,1.5)
		if f=="twinGarage" then
			pier(0,1.2)
			portal(-w/4+.2,w/2-1.6,0,top,8,"parking");portal(w/4-.2,w/2-1.6,0,top,8,"parking")
		elseif f=="pilotis" then
			for _,x in {-w*.23,w*.23} do p("RoundPilotis",x,top/2,1.2,top,1.0,1.0,pal.wall,M.Concrete,"wall",0,CFrame.Angles(0,0,math.pi/2),Enum.PartType.Cylinder) end
			portal(0,w*.46-1.1,0,top,9,"parking")
		elseif f=="loading" then
			local split=w/2-8
			wall("ServiceSidePanel",split,w/2-1,0,top,0,.9)
			-- Independent service door in the panel; replace its covered region with holes.
			out.parts[#out.parts]=nil
			wall("ServiceSidePier",split,split+.7,0,top,0,.9)
			wall("ServiceDoorHead",split+.7,w/2-1,8.2,top,0,.9)
			door((split+.7+w/2-1)/2,w/2-1-split-.7,0,8.2,.8,true)
			portal((-w/2+1+split)/2,split+w/2-1,0,top,8,"loading")
		else portal(0,w-2,0,top,8,"parking") end
		p("GarageCeilingStrip",0,top-.2,2.8,w-3,.1,.32,WHITE,M.Neon,"light")
		for _,x in {-w/2+.65,w/2-.65} do p("PierProtection",x,2.8,-.51,.28,5.6,.12,pal.trim,M.Metal) end
	elseif f=="sparse" or f=="servicePair" then
		local dw=4.8;local dx=-w*.27;local dh=math.min(8.4,h-2)
		local holes={};if entry then table.insert(holes,{dx-dw/2,dx+dw/2,0,dh}) end
		if f=="servicePair" and entry then table.insert(holes,{w*.22-dw/2,w*.22+dw/2,0,dh}) end
		local wx0,wx1=f=="servicePair" and -2 or 0,f=="servicePair" and 2 or w/2-2
		table.insert(holes,{wx0,wx1,5.4,7.6});concrete(holes)
		glass(wx0,wx1,5.4,7.6,.3,true)
		if entry then door(dx,dw,0,dh,.6,true);if f=="servicePair" then door(w*.22,dw,0,dh,.6,true) end end
		p("WallVent",w/2-2.4,2.8,-.45,2.2,1.3,.15,pal.trim,M.Metal)
		for y=2.3,3.3,.2 do p("VentLouver",w/2-2.4,y,-.56,2,.06,.12,WHITE,M.Metal) end
		for _,x in {-w/2+1,w/2-1} do p("DrainPipe",x,h/2,-.55,.12,h,.16,WHITE,M.Metal) end
	elseif f=="brickHome" or f=="townhouse" or f=="gateHome" or f=="raised" then
		local dx,dw=w*.27,4.8;local y0=f=="raised" and 2.8 or 0
		local dh=math.min(8.5,h-y0-1.2)
		local wx0,wx1=-w/2+1,dx-dw/2-1.0
		local holes={};if entry then table.insert(holes,{dx-dw/2,dx+dw/2,y0,y0+dh}) end
		if f~="townhouse" then table.insert(holes,{wx0,wx1,2.2,math.min(8.6,h-2.0)}) end
		concrete(holes,(f=="brickHome" or f=="gateHome") and M.Brick or M.Concrete)
		if f=="raised" then
			-- Street-level shutter with stairs beside it, not an opening across the slab.
			p("GarageShutter",(wx0+wx1)/2,4.2,-.45,wx1-wx0,8.4,.24,WHITE,M.Metal,"wall")
			for y=.3,8.2,.4 do p("GarageShutterRib",(wx0+wx1)/2,y,-.6,wx1-wx0,.06,.06,pal.trim,M.Metal) end
			if entry then
				for i=1,7 do local rise=y0*i/7;p("RaisedEntryTread",dx,rise/2,-4.8+(i-.5)*.7,dw,rise,.7,pal.wall,M.Concrete,"threshold") end
				for _,x in {dx-dw/2-.12,dx+dw/2+.12} do p("StairRail",x,3.2,-2.2,.12,.12,5.1,pal.trim,M.Metal) end
			end
		elseif f~="townhouse" then glass(wx0,wx1,2.2,math.min(8.6,h-2),.3,true) end
		if entry then
			door(dx,dw,y0,dh,f=="townhouse" and 2.5 or 1.6,f=="townhouse")
			p("EntryIntercom",dx-dw/2-.5,y0+4.4,-.48,.5,1.0,.2,pal.trim,M.Metal,"prop")
		end
		if f=="townhouse" then
			for _,x in {dx-dw/2-.8,dx+dw/2+.8} do p("RoundEntryColumn",x,head/2,-1,head,.65,.65,Color3.fromRGB(162,150,126),M.Metal,"wall",0,CFrame.Angles(0,0,math.pi/2),Enum.PartType.Cylinder) end
			for x=-w/2+.7,dx-dw/2-2,.55 do p("PrivacyFin",x,h/2,-.65,.13,h,.8,WOOD,M.Wood) end
			canopy(dx,dw+2.5,head,3.5);planter(-w*.25,-1.6,3.8)
		elseif f=="gateHome" then
			wall("LowBoundaryWall",-w/2,dx-dw/2-.5,0,2.0,-2,1,M.Brick)
			for x=wx0+.4,dx-dw/2-.5,.6 do p("BoundaryRailing",x,3,-2,.08,2,.1,pal.trim,M.Metal) end
			if entry then for i=1,6 do p("ApproachGateBar",dx-dw/2+(i-.5)*dw/6,1.5,-2,.1,3,.15,pal.trim,M.Metal,"door") end end
			planter(-w/2+2,-3.1,3)
		elseif f=="brickHome" then
			planter(-w/2+3,-1.5,4.2);canopy(dx,dw+1,head,2)
			sign("SmallResidenceName",-w*.15,h-1.1,-.44,w*.42,.7,brand,pal.wall,pal.trim);brand=""
		end
	elseif f=="stackedGlass" or f=="tallGlass" then
		local dw,dx=7.2,w*.27;local dh=9.4
		pier(-w/2+.6,1.2);pier(w/2-.6,1.2)
		wall("TopCap",-w/2+1.2,w/2-1.2,h-.8,h,0,.9)
		local left,right=entry and dx-dw/2 or w/2-1.2+.25,entry and dx+dw/2 or w/2
		if f=="stackedGlass" then
			local seam=12.5
			-- Existing 4.5-stud slab lies behind this opaque spandrel; it is not removed.
			wall("StoreySpandrel",-w/2+1.2,w/2-1.2,seam,seam+4.5,0,.8)
			for x=-w/2+1.5,w/2-1.5,.45 do p("SpandrelRib",x,seam+2.25,-.5,.12,4.5,.25,Color3.fromRGB(164,147,112),M.Metal) end
			glass(-w/2+1.2,left-.25,.4,seam,.3);if entry then glass(right+.25,w/2-1.2,.4,seam,.3) end
			glass(-w/2+1.2,w/2-1.2,seam+4.5,h-.8,.3)
			if entry then glass(dx-dw/2,dx+dw/2,dh,seam,2);canopy(dx,dw+2,10.2,3.3) end
		else
			-- True void is required; never automatically erase an existing first-floor slab.
			glass(-w/2+1.2,left-.25,.4,h-.8,.3);if entry then glass(right+.25,w/2-1.2,.4,h-.8,.3) end
			for x=-w/2+2,w/2-2,6 do for y=6,h-1,6 do p("PointGlassFixing",x,y,-.01,.23,.23,.14,WHITE,M.Metal) end end
			if entry then
				glass(dx-dw/2,dx+dw/2,dh+1,h-.8,.3)
				p("VestibuleRoof",dx,dh+.8,1.4,dw+1,.4,3.5,pal.trim,M.Metal)
			end
		end
		if entry then door(dx,dw,0,dh,2,false) end
	else
		-- Retail families: different proportions, pier patterns and opening functions.
		local dx,dw=w*.25,5.0
		if f=="posterShop" then dx=0;dw=7.2 end
		if f=="localShop" then dx=w*.25;dw=4.5 end
		if f=="salon" then dx=-w*.24;dw=4.8 end
		if f=="fastFood" then dx=0;dw=6.4 end
		if f=="kingBurger" then dx=w*.28;dw=5.2 end
		if f=="coffeeChain" then dx=-w*.27;dw=4.8 end
		local dh=math.min(8.8,head-.25)
		pier(-w/2+.45,.9);pier(w/2-.45,.9)
		wall("ShopFascia",-w/2+.9,w/2-.9,head,h,0,.8,f=="localShop" and M.Brick or M.Concrete)
		local x0,x1=-w/2+.9,w/2-.9
		if f=="produce" then
			portal(0,w-1.8,0,head,5,"openShop")
			canopy(0,w-.8,head,3.5,Color3.fromRGB(76,112,65))
			for _,x in {-w*.30,w*.30} do
				p("ProduceCounter",x,1.25,1.5,w*.22,2.5,2.3,WOOD,M.Wood,"prop")
				for i=1,3 do p("ProduceCrate",x+(i-2)*1.6,2.9,1.5,1.45,.7,1.5,Color3.fromRGB(95,128,67),M.SmoothPlastic,"prop") end
			end
		elseif f=="hatch" then
			local hx0,hx1=-w/2+2,1
			local holes={{hx0,hx1,3.5,7.0}};if entry then table.insert(holes,{dx-dw/2,dx+dw/2,0,dh}) end
			-- Replace generic header/piers with a decomposed opaque wall.
			for i=#out.parts,1,-1 do if out.parts[i].name=="ConcretePier" or out.parts[i].name=="ShopFascia" then table.remove(out.parts,i) end end
			concrete(holes);glass(hx0,hx1,5.2,7,.3)
			p("ServingLedge",(hx0+hx1)/2,3.5,-.9,hx1-hx0,.3,2,WOOD,M.Wood)
			p("HatchCanopy",(hx0+hx1)/2,7.4,-1,hx1-hx0+1,.3,2.3,pal.trim,M.Metal)
			if entry then door(dx,dw,0,dh,1,true) end
			posters(hx0,hx1,7.5,9.8,-.5)
		elseif f=="grille" then
			local center=1.7;pier(0,center)
			for _,side in {-1,1} do
				local a,b=side==-1 and x0 or center/2,side==-1 and -center/2 or x1
				glass(a,b,.6,head,.4)
				for x=a+.2,b-.2,.7 do p("SecurityGrilleBar",x,head/2,-.12,.07,head,.12,pal.trim,M.Metal,"wall") end
				for y=.8,head,1.6 do p("SecurityGrilleRail",(a+b)/2,y,-.15,b-a,.06,.1,pal.trim,M.Metal) end
				posters(a+.3,b-.3,2.8,5.3,.17,true)
			end
			canopy(0,w-1,head,2.7,pal.trim)
			-- This is explicitly a closed restaurant variant, no traversable entry claimed.
			out.closed=true
		else
			local function shopWindow(a,b)
				local sill=f=="electronics" and 2.4 or f=="salon" and .5 or 1.1
				wall("ShopKickplate",a,b,0,sill,0,.7,f=="localShop" and M.Brick or M.Concrete)
				glass(a,b,sill,head,.3,f=="salon")
				if f~="salon" then posters(a+.2,b-.2,3.8,6.2,.15,f=="posterShop") end
				if f=="electronics" then
					p("BoxedDisplayShelf",(a+b)/2,2.6,1.0,b-a-.2,.2,1.3,pal.trim,M.Metal,"prop")
					for x=a+1,b-.6,2 do p("DisplayAppliance",x,3.6,1.1,1.1,1.8,.8,WHITE,M.Metal,"prop") end
				end
			end
			if entry then
				shopWindow(x0,dx-dw/2-.25);shopWindow(dx+dw/2+.25,x1)
				door(dx,dw,0,dh,f=="salon" and 2.4 or 1.0,false)
				glass(dx-dw/2,dx+dw/2,dh,head,1.0)
				for _,x in {dx-dw/2-.125,dx+dw/2+.125} do p("ShopDoorWindowJoint",x,head/2,.15,.30,head,.45,pal.trim,M.Metal) end
			else shopWindow(x0,x1) end
			if f=="fastFood" then
				canopy(0,w-1,head,.95,accent)
				p("YellowCanopyLip",0,head-.22,-.98,w-1,.14,.14,Color3.fromRGB(228,184,51),M.Metal)
				for _,x in {-w/2+1.5,w/2-1.5} do p("RedRestaurantBlade",x,head/2,-.38,.7,head,.2,accent,M.Metal) end
				for _,x in {-dw/2-.55,dw/2+.55} do p("EntranceBeacon",x,head-.7,-.4,.3,.85,.2,Color3.fromRGB(229,190,61),M.Neon,"light") end
			elseif f=="kingBurger" then
				for y=head+.2,h-.1,.36 do p("SmashTimberFascia",0,y,-.5,w-1.8,.28,.15,WOOD,M.Wood) end
				p("SmashRedLintel",0,head-.15,-.46,w-1.8,.25,.35,accent,M.Metal)
				for _,x in {-w/2+1.2,w/2-1.2} do p("SmashBrickButtress",x,head/2,-.08,.45,head,.8,pal.wall,M.Brick,"wall") end
			elseif f=="coffeeChain" then
				canopy(0,w-1,head,2.1,accent)
				for x=w*.24,w/2-1.4,.7 do p("CoffeeTimberFin",x,head/2,-.3,.2,head,1.0,WOOD,M.Wood) end
				p("CoffeeWindowLedge",w*.01,2,-.75,w*.35,.18,1.3,WOOD,M.Wood)
				planter(w/2-2,-1.4,2.1)
			elseif f=="burger" then
				for y=head+.2,h-.1,.35 do p("WoodFasciaCourse",0,y,-.48,w-1.8,.28,.14,WOOD,M.Wood) end
				p("RestaurantRedBand",0,head-.15,-.5,w-1.8,.28,.24,accent,M.Metal)
			elseif f=="posterShop" then
				for i,c in {Color3.fromRGB(47,143,71),WHITE,Color3.fromRGB(44,110,177)} do p("ConvenienceStripe",0,head+.2+(i-1)*.18,-.5,w-1.8,.13,.1,c,M.SmoothPlastic,"sign") end
				p("AutomaticDoorSensor",dx,dh-.1,options.mount=="recessed" and .7 or -.15,1.3,.24,.22,pal.trim,M.Metal)
			elseif f=="localShop" then
				canopy(0,w-1,head,1.8,WOOD)
				if entry then for i=1,3 do p("SmallShopNoren",dx-dw/2+(i-.5)*dw/3,dh-.8,.6,dw/3-.08,1.5,.12,accent,M.Fabric) end end
			elseif f=="salon" then canopy(dx,dw+1,dh+.3,2.3,WHITE)
			elseif f=="electronics" then p("DisplayBoxHead",-w*.18,head-.2,-.2,w*.55,.35,.8,pal.trim,M.Metal) end
		end
	end
	if brand~="" and role=="entrance" then
		local small=spec.family=="residential" or spec.family=="service" or spec.family=="office"
		sign("IdentityPanel",0,h-(small and .9 or 1.15),-.62,w-2.3,small and .75 or 1.4,brand,small and pal.wall or accent,small and pal.trim or WHITE)
	end
	if entry and out.door then sign("AddressPlaque",-w/2+.65,1.6,-.54,.65,.8,tostring(rng:NextInteger(1,99)),pal.trim) end
	-- Shallow interior context belongs to the review gallery only.
	if options.vignette then
		local depth=(spec.family=="parking" or f=="loading") and 9 or 7
		p("PreviewFloor",0,-.12,depth/2,w-.2,.24,depth,Color3.fromRGB(135,130,119),M.Concrete,"preview")
		p("PreviewRearWall",0,h/2,depth,w-.2,h,.24,Color3.fromRGB(86,83,75),M.SmoothPlastic,"preview")
		for _,x in {-w/2+.12,w/2-.12} do p("PreviewSideWall",x,h/2,depth/2,.24,h,depth,Color3.fromRGB(116,111,100),M.Concrete,"preview") end
		p("PreviewCeiling",0,h-.2,depth/2,w-.2,.2,depth,pal.wall,M.SmoothPlastic,"preview")
		p("PreviewCeilingLight",0,h-2.4,depth*.7,w*.55,.10,.25,WHITE,M.Neon,"light")
		if spec.family=="parking" then
			for _,x in {-w*.28,0,w*.28} do p("PreviewParkingLine",x,.035,depth/2,.12,.06,depth-1,WHITE,M.SmoothPlastic,"preview") end
		elseif f=="burger" or f=="posterShop" or f=="localShop" then
			p("PreviewShopCounter",-w*.20,1.4,5,w*.35,2.8,1.3,WOOD,M.Wood,"preview")
		end
	end
	out.adSeed=adSeed;out.variant=rng:NextInteger(1,3)
	if options.mirror then
		local function flip(v) return Vector3.new(-v.X,v.Y,v.Z) end
		for _,r in out.parts do local cf=r.cframe;r.cframe=CFrame.fromMatrix(flip(cf.Position),-flip(cf.XVector),flip(cf.YVector));if r.supportLocalBottom then r.supportLocalBottom=flip(r.supportLocalBottom) end end
		for _,q in out.portals do q.x=-q.x end
		if out.door then out.door.x=-out.door.x end
	end
	return out
end
return E
