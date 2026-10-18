--!nonstrict
-- Upper-floor facade kit (storey >= 2). Flat only: bands, piers, glass, mullions, fins,
-- louvers and flush signs; no parallax, no interiors. Requiring this builds nothing.
-- Run frame: bottom-centre of the wall strip at slab top, +X along the wall, +Y up,
-- -Z outward (FacadeMount contract: .75 outside the outline, rear <= Z .45, front >= -.6).
local Catalog=require(script.Parent.UpperFacadeCatalog)
local Layout=require(script.Parent.FacadeLayout)
local GlassVisual=require(script.Parent.GlassVisual)
local Http=game:GetService("HttpService")
local Kit={OWNER="upper-facade-v1",VERSION=1,MIN_HEIGHT=8,MAX_HEIGHT=30,MIN_WIDTH=6,STANDOFF=.75,REAR=.45,FRONT=-.6}
-- Depth layers {centre Z, depth}. Walls [-.25,.35], glass [.06,.24], proud [-.6,.3].
local WALL,PROUD,GLASS,MULL,FILL,SIGN={.05,.6},{-.15,.9},{.15,.18},{-.02,.36},{.3,.2},{-.33,.45}
local FACE,BALC,TRIM={-.35,.5},{-.3,.6},{-.2,.7}
local AC_COLOR=Color3.fromRGB(214,214,208)
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<1e12 end
local function proud(depth) return {-.6+depth/2,depth} end

-- Pure data: rows of {name,cframe,size,color,material,kind,transparency,reflectance,paneId}
-- in run-frame space. kind: wall | trim | sign | glass.
function Kit.Layout(width,height,spec,options)
	options=options or {}
	if type(spec)=="string" then spec=Catalog.Get(spec) end
	assert(type(spec)=="table" and spec.id,"Unknown upper facade spec")
	assert(finite(width) and width>0 and width<=1000,"Invalid upper facade width")
	assert(finite(height) and height>=Kit.MIN_HEIGHT and height<=Kit.MAX_HEIGHT,"Upper facade height must be 8..30 studs")
	local pal=Catalog.Palette(options.palette or spec.palette)
	local M=Catalog.Mat
	local w,h=width,height
	local slab=math.clamp(options.slab or 0,0,6);local cap=math.clamp(options.cap or 0,0,6)
	local key=options.key or spec.id
	local out={id=spec.id,family=spec.family,width=w,height=h,key=key,parts={},panes=0,bays=0}
	local function p(name,x0,x1,y0,y1,layer,color,material,kind,extra)
		if x1-x0<.05 or y1-y0<.05 then return nil end
		local row={name=name,cframe=CFrame.new((x0+x1)/2,(y0+y1)/2,layer[1]),size=Vector3.new(x1-x0,y1-y0,layer[2]),
			color=color,material=material,kind=kind or "wall",transparency=0,reflectance=0}
		if extra then for k,v in extra do row[k]=v end end
		table.insert(out.parts,row);return row
	end
	local wallMat,frameMat=M(pal.wallMat),M(pal.frameMat)
	local bandMat=M(spec.bandWall and pal.wallMat or pal.bandMat)
	local function solid(reason)
		table.clear(out.parts);out.solid=reason
		p("SolidPanel",-w/2,w/2,-slab,h+cap,WALL,pal.wall,wallMat,"wall")
		return out
	end
	if w<Kit.MIN_WIDTH then return solid("narrow") end
	local mode=spec.balcony and "balcony" or spec.corridor and "corridor" or nil
	local crown=options.top and options.crown or "none"
	if mode and (crown=="attic" or crown=="glassTop") then crown="none" end
	local bandColor=options.bandColor or (spec.bandWall and pal.wall or pal.band)
	if crown=="colorTop" then bandColor=pal.band2 end
	local ribbon=spec.ribbon or crown=="glassTop"
	local sill=math.clamp(spec.sill*(options.sillScale or 1),0,h*.45)
	local head=math.clamp(spec.head*(options.headScale or 1),.4,h*.35)
	if crown=="glassTop" then sill=math.min(sill,.8) end
	local ph=mode and math.min((spec.balcony or spec.corridor).height,h*.4) or 0
	-- Low storeys keep a usable opening: shrink the head band first, then the sill.
	local minOpen=math.max(2.5,h*.3)
	local short=minOpen-(h-head-(mode=="corridor" and ph or sill))
	if short>0 then
		local cut=math.min(short,head-.4);head-=cut;short-=cut
		if short>0 and mode~="corridor" then sill=math.max(0,sill-short) end
	end
	local ys0,ys1=mode=="corridor" and ph or sill,h-head
	if crown=="attic" and ys1-ys0>=6 then ys0+=(ys1-ys0)*.45 end
	if ys1-ys0<2.5 then return solid("short") end
	local L=math.max(spec.endPier,(options.cornerLeft or 0)+.6)
	local R=math.max(spec.endPier,(options.cornerRight or 0)+.6)
	local blade=options.blade
	if blade then
		local need=(blade.width or 2.2)+.8
		if blade.side<0 then L=math.max(L,(options.cornerLeft or 0)+need) else R=math.max(R,(options.cornerRight or 0)+need) end
	end
	if L+R>w-2.5 then return solid("corners") end
	-- Horizontal bands: one floor band (covers the slab edge below) and one head band per run.
	local refl=pal.bandRefl or 0
	if mode~="balcony" then p("FloorBand",-w/2,w/2,-slab,ys0,mode=="corridor" and PROUD or WALL,bandColor,bandMat,"wall",{reflectance=refl}) end
	p("HeadBand",-w/2,w/2,ys1,h+cap,WALL,bandColor,bandMat,"wall",{reflectance=refl})
	if crown=="cornice" then p("CrownCornice",-w/2,w/2,h-1.2,h+cap+(cap>0 and .5 or 0),BALC,pal.band2,bandMat,"wall")
	elseif cap>0 then p("RoofCoping",-w/2,w/2,h+cap,h+cap+.5,{-.25,.7},pal.frame,frameMat,"trim") end
	local fullPier=spec.pierProud or spec.accentPiers
	local pierLayer=fullPier and PROUD or WALL
	local py0,py1=fullPier and -slab or ys0,fullPier and h or ys1
	local pierColor=spec.accentPiers and (options.accentColor or pal.accents[1]) or pal.pier
	p("EndPier",-w/2,-w/2+L,py0,py1,pierLayer,pal.pier,wallMat,"wall")
	p("EndPier",w/2-R,w/2,py0,py1,pierLayer,pal.pier,wallMat,"wall")
	local x0,x1=-w/2+L,w/2-R
	local span=x1-x0
	local module=math.clamp(spec.module*(options.moduleScale or 1),3,40)
	local gap=ribbon and spec.mullion or spec.pier
	local n=math.max(1,math.floor(span/module+.5))
	while n>1 and (span-(n-1)*gap)/n<2 do n-=1 end
	local ww=(span-(n-1)*gap)/n
	out.bays=n
	local offset=options.cycleOffset or 0
	local function glass(i,j,gx0,gx1,gy0,gy1,frost)
		local row=p("Glass",gx0,gx1,gy0,gy1,GLASS,frost and pal.frost or pal.glass,Enum.Material.Glass,"glass",
			{transparency=frost and .05 or pal.glassT,reflectance=frost and .02 or pal.refl,paneId=key.."/bay"..i.."/pane"..j})
		if row then out.panes+=1 end
	end
	local transomY
	local function window(i,bx0,bx1,gy0,gy1)
		local bw,mull=bx1-bx0,spec.mullion
		local k=options.panes or spec.panes or math.max(1,math.floor(bw/spec.paneW+.5))
		while k>1 and (bw-(k-1)*mull)/k<1.2 do k-=1 end
		local pw=(bw-(k-1)*mull)/k
		local split=spec.transom or (gy1-gy0>spec.autoTransom and .72) or nil
		local rows={{gy0,gy1}}
		if split then
			local ty=gy0+(gy1-gy0)*split;rows={{gy0,ty-mull/2},{ty+mull/2,gy1}}
			if ribbon then transomY=ty else p("Transom",bx0,bx1,ty-mull/2,ty+mull/2,MULL,pal.frame,frameMat,"trim") end
		end
		local j=0
		for ri,yr in rows do for c=1,k do
			j+=1;local gx=bx0+(c-1)*(pw+mull)
			glass(i,j,gx,gx+pw,yr[1],yr[2],spec.frost=="lower" and ri==1 and #rows>1)
		end end
		for c=1,k-1 do local mx=bx0+c*pw+(c-1)*mull;p("Mullion",mx,mx+mull,gy0,gy1,MULL,pal.frame,frameMat,"trim") end
		if spec.sillTrim then p("SillTrim",bx0-.2,bx1+.2,gy0-.25,gy0,TRIM,pal.frame,frameMat,"trim") end
		-- Wall-hung outdoor AC unit on the band under every other window (flat face only).
		if options.ac and not mode and (i+offset)%2==0 and gy0>=2.8 and bw>=3 then
			local c=(bx0+bx1)/2;p("ACUnit",c-1.3,c+1.3,gy0-2.5,gy0-.45,{-.35,.4},AC_COLOR,Enum.Material.SmoothPlastic,"trim")
		end
	end
	local cycle=not mode and crown~="glassTop" and spec.cycle or nil
	local signBay=spec.signs=="vertical" and options.primary and n>=2 and ((options.signSide or 1)<0 and 1 or n) or nil
	local signColor=pal.accents[Catalog.Seed(key.."/sign")%#pal.accents+1]
	if mode=="corridor" then p("CorridorShadow",x0,x1,ys0,ys1,FILL,pal.dark,Enum.Material.SmoothPlastic,"wall") end
	for i=1,n do
		local bx0=x0+(i-1)*(ww+gap);local bx1=bx0+ww;local c=(bx0+bx1)/2
		if i<n then
			if ribbon then p("Mullion",bx1,bx1+gap,ys0,ys1,MULL,pal.frame,frameMat,"trim")
			else p("Pier",bx1,bx1+gap,py0,py1,pierLayer,pierColor,wallMat,"wall") end
			if mode=="balcony" and spec.balcony.divider then local mx=bx1+gap/2;p("UnitDivider",mx-.2,mx+.2,-slab,h,{-.25,.7},pal.band,bandMat,"wall") end
		end
		local role=cycle and cycle[(i-1+offset)%#cycle+1] or "window"
		if i==signBay then role="sign" end
		if mode=="corridor" then
			if (i+offset)%2==0 then p("UnitDoor",c-math.min(1.6,ww*.25),c+math.min(1.6,ww*.25),ys0,math.min(ys1-.3,ys0+4.2),{.1,.2},pal.band2,M("Metal"),"wall")
			else local sw=math.min(4,ww*.5);glass(i,1,c-sw/2,c+sw/2,ys0+1,math.min(ys1-.5,ys0+3.8),true) end
		elseif role=="window" then window(i,bx0,bx1,ys0,ys1)
		elseif role=="small" or role=="slot" then
			p("BayInfill",bx0,bx1,ys0,ys1,FILL,pal.wall,wallMat,"wall")
			if role=="small" then local sw=math.min(ww*.55,4);glass(i,1,c-sw/2,c+sw/2,ys0+(ys1-ys0)*.45,ys1-.5,true)
			else local sw=math.min(2,ww*.45);glass(i,1,c-sw/2,c+sw/2,ys0+.3,ys1-.3,false) end
		elseif role=="vent" then
			p("BayInfill",bx0,bx1,ys0,ys1,WALL,pal.wall,wallMat,"wall")
			p("VentGrille",c-.9,c+.9,ys1-1.8,ys1-.8,{-.33,.2},pal.frame,frameMat,"trim")
		elseif role=="panel" then
			p("SpandrelPanel",bx0,bx1,ys0,ys1,WALL,pal.band,bandMat,"wall",{reflectance=refl})
		elseif role=="sign" then
			-- Stacked signboards: a flush panel per floor, colour seeded by the floor-run key.
			p("BayInfill",bx0,bx1,ys0,ys1,WALL,pal.wall,wallMat,"wall")
			p("Signboard",bx0+.2,bx1-.2,.4,h-.4,SIGN,signColor,Enum.Material.SmoothPlastic,"sign")
			p("SignFace",bx0+.7,bx1-.7,1,h-1,FACE,pal.signFace,Enum.Material.SmoothPlastic,"sign")
		end
	end
	if transomY then p("Transom",x0,x1,transomY-spec.mullion/2,transomY+spec.mullion/2,MULL,pal.frame,frameMat,"trim") end
	if mode=="balcony" then
		local b=spec.balcony
		if b.rail then
			p("BalconySlabEdge",-w/2,w/2,-slab,.3,BALC,pal.band,bandMat,"wall")
			p("BalconyRailInfill",-w/2,w/2,.3,ph,{-.45,.2},pal.frost,Enum.Material.SmoothPlastic,"trim",{transparency=.35})
			p("BalconyRailTop",-w/2,w/2,ph,ph+.2,{-.4,.4},pal.frame,frameMat,"trim")
			if options.ac then for i=1,n,2 do
				local c=x0+(i-.5)*ww+(i-1)*gap;p("ACUnit",c-1.3,c+1.3,.35,2.3,{-.15,.3},AC_COLOR,Enum.Material.SmoothPlastic,"trim")
			end end
		else p("BalconyParapet",-w/2,w/2,-slab,ph,BALC,pal.band,bandMat,"wall") end
	elseif mode=="corridor" then
		p("ParapetCap",-w/2,w/2,ph-.15,ph+.15,{-.35,.5},pal.frame,frameMat,"trim")
	end
	if spec.fins then
		local f=spec.fins;local xs={x0}
		if f.spacing=="bay" then for i=1,n-1 do table.insert(xs,x0+i*ww+(i-.5)*gap) end
		else local k=math.max(1,math.floor(span/f.spacing+.5));for t=1,k-1 do table.insert(xs,x0+span*t/k) end end
		table.insert(xs,x1)
		for _,x in xs do p("Fin",x-f.width/2,x+f.width/2,f.full and -slab or ys0,f.full and h or ys1,proud(f.depth),pal.frame,frameMat,"trim") end
	end
	if spec.louvers then
		local lv=spec.louvers;local count=math.clamp(math.floor((ys1-ys0)/lv.gap),1,5)
		for t=1,count do local y=ys0+(ys1-ys0)*t/(count+1);p("LouverBlade",x0,x1,y-lv.thick/2,y+lv.thick/2,proud(lv.depth),pal.frame,frameMat,"trim") end
	end
	if spec.eave then p("Sunshade",-w/2,w/2,ys1-spec.eave.thick,ys1,proud(spec.eave.depth),pal.frame,frameMat,"trim") end
	if spec.screen then p("MetalScreen",x0,x1,ys0+(ys1-ys0)*spec.screen.from,ys1,{-.4,.3},pal.frame,frameMat,"trim",{transparency=spec.screen.transparency}) end
	if spec.signs=="band" and options.primary then
		local fw=span*.8
		p("FasciaSign",-fw/2,fw/2,ys1+.15,h-.15,SIGN,signColor,Enum.Material.SmoothPlastic,"sign")
		if h-ys1>1.6 then p("SignFace",-fw*.3,fw*.3,ys1+.5,h-.5,FACE,pal.signFace,Enum.Material.SmoothPlastic,"sign") end
	end
	if options.rail and not mode and ys1-ys0>5 then
		local ry=ys0+math.min(2.6,(ys1-ys0)*.4)
		p("RailInfill",x0,x1,ys0,ry,{-.45,.2},pal.frame,Enum.Material.SmoothPlastic,"trim",{transparency=.55})
		p("RailTop",x0,x1,ry,ry+.18,{-.4,.4},pal.frame,frameMat,"trim")
	end
	if blade then
		local bw=blade.width or 2.2
		local c=(blade.side<0 and x0 or x1)+blade.side*(bw/2+.4)
		p("BladeSign",c-bw/2,c+bw/2,-slab,h,SIGN,blade.color or pal.accents[1],Enum.Material.SmoothPlastic,"sign")
		p("BladeFace",c-bw/2+.25,c+bw/2-.25,.6,h-.6,FACE,pal.signFace,Enum.Material.SmoothPlastic,"sign")
	end
	return out
end

function Kit.BuildFloorRun(parent,frame,width,height,spec,options)
	options=options or {}
	if type(spec)=="string" then spec=Catalog.Get(spec) end
	local layout=Kit.Layout(width,height,spec,options)
	frame=frame or CFrame.identity
	local model=Instance.new("Model");model.Name=options.name or "UpperFacadeRun_"..spec.id
	model:SetAttribute("UpperFacadeVariant",spec.id);model:SetAttribute("UpperFacadeFamily",spec.family)
	model:SetAttribute("UpperFacadePalette",type(options.palette)=="string" and options.palette or spec.palette)
	model:SetAttribute("UpperFacadeKitVersion",Kit.VERSION);model:SetAttribute("FacadeRunKey",layout.key)
	model:SetAttribute("FacadeWidth",width);model:SetAttribute("FacadeHeight",height);model:SetAttribute("FacadeRunFrame",frame)
	if layout.solid then model:SetAttribute("UpperFacadeSolid",layout.solid) end
	local ok,err=pcall(function()
		for _,row in layout.parts do
			local part=Instance.new("Part")
			part.Name=row.name;part.Size=row.size;part.CFrame=frame*row.cframe
			part.Color=row.color;part.Material=row.material;part.Transparency=row.transparency;part.Reflectance=row.reflectance
			part.Anchored=true;part.CanTouch=false;part.CanQuery=true
			part.CanCollide=row.kind=="wall" or row.kind=="glass"
			part.CastShadow=row.kind=="wall"
			part.TopSurface=Enum.SurfaceType.Smooth;part.BottomSurface=Enum.SurfaceType.Smooth
			part:SetAttribute("FacadePieceKind",row.kind=="glass" and "glass" or "wall")
			part:SetAttribute("FacadeUpperRole",row.kind);part:SetAttribute("FacadeLayer","exterior")
			part:AddTag("NoCSG")
			if row.paneId then GlassVisual.Capture(part,row.paneId,true) end
			part.Parent=model
		end
		model.WorldPivot=frame;model.Parent=parent
	end)
	if not ok then model:Destroy();error(err) end
	return model,layout
end

local function flat(v) return Vector2.new(v.X,v.Z) end
local function cross(a,b) return a.X*b.Y-a.Y*b.X end
-- Signed extension of run r at endpoint E so its .75 stand-off plane meets neighbour q's:
-- positive at convex corners (plus .3 so the outer faces close), negative at concave ones.
local function cornerExt(r,E,q,qE)
	local dA=(E-flat(r.centre)).Unit;local dB=(qE-flat(q.centre)).Unit
	local denom=cross(dA,dB)
	if math.abs(denom)<.02 then return 0 end
	local a=E+flat(r.normal)*Kit.STANDOFF;local b=qE+flat(q.normal)*Kit.STANDOFF
	local t=cross(b-a,dB)/denom
	if t>.05 then t+=.3 end
	return math.clamp(t,-2,3)
end

-- Pure plan for one building: style + one row per storey>=2 strip (no instances).
function Kit.PlanBuilding(model,opts)
	opts=opts or {}
	local encoded=model:GetAttribute("SourceSlicePlan")
	assert(type(encoded)=="string","Upper facades need a SourceSlicePlan")
	local frame=assert(Layout.FrameOf(model),"Model has no source frame")
	local plan=Http:JSONDecode(encoded);local levels=plan.levels
	local id=model:GetAttribute("SourceSliceId") or model.Name
	local minStorey=opts.minStorey or 2
	local config=table.clone(Layout.CONFIG);config.inset=0 -- run frames sit on the outline, mounted .75 out
	local rows,groups,first={}, {},math.huge
	for _,s in Layout.Build(plan,config) do if s.storey>=minStorey then
		local ring=levels[s.storey].pieces[s.piece];local area=0
		for i,a in ring do local v=ring[i%#ring+1];area+=a[1]*v[2]-v[1]*a[2] end
		local world=frame*s.cframe
		local r={s=s,width=s.size.X,height=s.size.Y-.3,centre=world.Position,
			normal=area>0 and world.LookVector or -world.LookVector,tangent=area>0 and world.XVector or -world.XVector}
		r.e0=flat(r.centre-r.tangent*r.width/2);r.e1=flat(r.centre+r.tangent*r.width/2)
		local g=s.storey..":"..s.piece;groups[g]=groups[g] or {};table.insert(groups[g],r);table.insert(rows,r)
		first=math.min(first,s.storey)
	end end
	-- Primary facade: the direction of the widest run on the lowest upper storey.
	local primary,maxRun=opts.primaryNormal,0
	for _,r in rows do if r.s.storey==first and r.s.kind~="parapet" and r.width>maxRun then maxRun=r.width;if not opts.primaryNormal then primary=r.normal end end end
	local class=opts.class or Catalog.Classify(#levels-1,maxRun)
	local style=opts.style or Catalog.Pick(tostring(id),class)
	if opts.family or opts.variant then style.panes=nil end
	if opts.family then style.family=opts.family;style.variant=Catalog.PickVariant(opts.family,tostring(id)).id;style.palette=Catalog.PickPalette(opts.family,tostring(id)) end
	if opts.variant then style.variant=opts.variant;style.family=Catalog.Get(opts.variant).family end
	if opts.palette then style.palette=opts.palette end
	local base=Catalog.Get(style.variant);local fam=Catalog.Family(style.family);local pal=Catalog.Palette(style.palette)
	local accent=pal.accents[(style.accentIndex-1)%#pal.accents+1]
	local bladeRun={}
	for _,r in rows do
		r.primary=primary~=nil and r.width>=10 and r.normal:Dot(primary)>.85 and r.s.kind~="parapet"
		if r.primary and (not bladeRun[r.s.storey] or r.width>bladeRun[r.s.storey].width) then bladeRun[r.s.storey]=r end
	end
	local out={id=id,class=class,style=style,runs={},parapets={},skipped={}}
	for _,r in rows do
		local s=r.s;local extL,extR=0,0
		for _,q in groups[s.storey..":"..s.piece] do if q~=r then
			for _,qE in {q.e0,q.e1} do
				if (qE-r.e0).Magnitude<.1 then extL=cornerExt(r,r.e0,q,qE) end
				if (qE-r.e1).Magnitude<.1 then extR=cornerExt(r,r.e1,q,qE) end
			end
		end end
		local width=r.width+extL+extR
		local bottom=r.centre+r.tangent*(extR-extL)/2-Vector3.yAxis*(s.size.Y/2-.15)+r.normal*Kit.STANDOFF
		local cf=CFrame.fromMatrix(bottom,r.tangent,Vector3.yAxis)
		local key=tostring(id).."/"..s.storey.."/"..s.piece.."/"..s.run
		local slab=levels[s.storey].thickness or 0
		if width<1 then table.insert(out.skipped,{key=key,reason="degenerate corner"});continue end
		if s.kind=="parapet" then table.insert(out.parapets,{key=key,frame=cf,width=width,height=math.max(.5,s.size.Y-.15),slab=slab});continue end
		if r.height<Kit.MIN_HEIGHT or r.height>Kit.MAX_HEIGHT then table.insert(out.skipped,{key=key,reason="height "..string.format("%.1f",r.height)});continue end
		local spec=base
		if not r.primary and spec.side then spec=Catalog.Get(spec.side) end
		if width<spec.minWidth then spec=Catalog.Get(fam.quiet) end
		local top=s.storey==#levels-1
		local band
		if style.bandMode=="alt" and s.storey%2==0 or style.bandMode=="every3" and s.storey%3==0 or style.bandMode=="podium" and s.storey==first then band=pal.band2 end
		local o={key=key,palette=style.palette,slab=slab,cap=top and (levels[#levels].thickness or 0) or 0,top=top,crown=style.crown,
			primary=r.primary,storey=s.storey,cornerLeft=math.max(0,extL),cornerRight=math.max(0,extR),bandColor=band,
			moduleScale=style.moduleScale,sillScale=style.sillScale,headScale=style.headScale,panes=spec==base and style.panes or nil,
			cycleOffset=style.cycleOffset,accentColor=accent,ac=style.ac,rail=style.rail,signSide=style.blade and -style.blade.side or 1,
			name="UpperRun_"..s.storey.."_"..s.piece.."_"..s.run}
		if style.blade and bladeRun[s.storey]==r and r.width>=14 and s.storey<first+style.blade.floors then
			o.blade={side=style.blade.side,width=style.blade.width,color=accent}
		end
		table.insert(out.runs,{key=key,frame=cf,width=width,height=r.height,spec=spec.id,options=o,storey=s.storey,piece=s.piece,run=s.run})
	end
	return out
end

-- Edit-time builder: one Folder "UpperFacade" per building, one Model per floor-run.
function Kit.BuildBuilding(model,opts)
	opts=opts or {}
	assert(typeof(model)=="Instance" and model:IsA("Model"),"BuildBuilding needs a building Model")
	local old=model:FindFirstChild("UpperFacade")
	if old then
		assert(old:GetAttribute("Owner")==Kit.OWNER,"Existing UpperFacade is not owned by this kit")
		if opts.replace==false then return old,{skipped="exists"} end
	end
	local plan=Kit.PlanBuilding(model,opts)
	local folder=Instance.new("Folder");folder.Name="UpperFacade"
	folder:SetAttribute("Owner",Kit.OWNER);folder:SetAttribute("UpperFacadeKitVersion",Kit.VERSION)
	folder:SetAttribute("UpperFacadeFamily",plan.style.family);folder:SetAttribute("UpperFacadeVariant",plan.style.variant)
	folder:SetAttribute("UpperFacadePalette",plan.style.palette);folder:SetAttribute("UpperFacadeClass",plan.class)
	local style=table.clone(plan.style);style.blade=style.blade and Http:JSONEncode(style.blade) or nil
	folder:SetAttribute("UpperFacadeStyle",Http:JSONEncode(style))
	local report={id=plan.id,class=plan.class,family=plan.style.family,variant=plan.style.variant,palette=plan.style.palette,
		runs=0,parapets=0,parts=0,panes=0,skipped=plan.skipped,variants={}}
	local ok,err=pcall(function()
		for _,run in plan.runs do
			local m=Kit.BuildFloorRun(folder,run.frame,run.width,run.height,run.spec,run.options)
			m:SetAttribute("RunStorey",run.storey);m:SetAttribute("RunPiece",run.piece);m:SetAttribute("RunIndex",run.run)
			m:SetAttribute("UpperFacadePrimary",run.options.primary)
			report.runs+=1;report.variants[run.spec]=(report.variants[run.spec] or 0)+1
		end
		local pal=Catalog.Palette(plan.style.palette)
		for _,q in plan.parapets do
			local part=Instance.new("Part");part.Name="UpperParapet";part.Size=Vector3.new(q.width,q.height+q.slab,.6)
			part.CFrame=q.frame*CFrame.new(0,(q.height-q.slab)/2,WALL[1]);part.Color=pal.band;part.Material=Catalog.Mat(pal.bandMat)
			part.Anchored=true;part.CanTouch=false;part:SetAttribute("FacadePieceKind","wall");part:SetAttribute("FacadeUpperRole","parapet")
			part:SetAttribute("FacadeLayer","exterior");part:SetAttribute("FacadeRunKey",q.key);part:AddTag("NoCSG");part.Parent=folder
			report.parapets+=1
		end
		for _,p in folder:GetDescendants() do if p:IsA("BasePart") then report.parts+=1;if p:HasTag("GlassPane") then report.panes+=1 end end end
		folder:SetAttribute("UpperFacadeParts",report.parts);folder:SetAttribute("UpperFacadePanes",report.panes)
		if old then old:Destroy() end
		folder.Parent=model
	end)
	if not ok then folder:Destroy();error(err) end
	return folder,report
end
return Kit
