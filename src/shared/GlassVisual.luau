-- Four glass states on an ordinary Part. Textures are presentation, not physics.
local Config=require(script.Parent.GlassConfig)
local V={}
local S=Config.State
local PREFIX="GlassDamage_"
local function textureContent(texture,uri)
	-- Current content API; compatibility for older Studio builds.
	local ok=pcall(function()texture.ColorMapContent=Content.fromUri(uri)end)
	if not ok then texture.Texture=uri end
end
function V.ClearTextures(part)
	for _,o in part:GetChildren() do if o:IsA("Decal") and o.Name:sub(1,#PREFIX)==PREFIX then o:Destroy() end end
end
function V.Capture(part,id,collision)
	if part:GetAttribute("GlassBaseTransparency")==nil then
		part:SetAttribute("GlassBaseTransparency",part.Transparency)
		part:SetAttribute("GlassBaseReflectance",part.Reflectance)
		part:SetAttribute("GlassBaseR",part.Color.R);part:SetAttribute("GlassBaseG",part.Color.G);part:SetAttribute("GlassBaseB",part.Color.B)
		local intact=collision;if intact==nil then intact=part.CanCollide end
		part:SetAttribute("GlassIntactCollision",intact)
	end
	if id then part:SetAttribute("GlassPaneId",id) end
	if part:GetAttribute("GlassState")==nil then part:SetAttribute("GlassState",S.Intact) end
	part:AddTag("GlassPane")
end
local function baseline(part)
	return Color3.new(part:GetAttribute("GlassBaseR") or part.Color.R,part:GetAttribute("GlassBaseG") or part.Color.G,part:GetAttribute("GlassBaseB") or part.Color.B)
end
local function cracks(part)
	for _,face in {Enum.NormalId.Front,Enum.NormalId.Back} do
		local t=Instance.new("Texture");t.Name=PREFIX.."Cracks";t.Face=face
		textureContent(t,Config.CrackImage)
		t.StudsPerTileU=Config.CrackTileStuds;t.StudsPerTileV=Config.CrackTileStuds
		-- Offsets vary per physical pane, stable across rebuilds.
		local h=0;for c in (part:GetAttribute("GlassPaneId") or part.Name):gmatch(".") do h=(h*33+string.byte(c))%997 end
		t.OffsetStudsU=(h%12)*.5;t.OffsetStudsV=(math.floor(h/12)%12)*.5
		t.Transparency=.08;t.Parent=part
	end
end
local function brokenEdges(part)
 -- Cropped, fixed-scale strips. Explicit short ImageLabels avoid the engine's
 -- Tile + ImageRect interaction (which sampled the wrong border in Studio).
 for _,face in {Enum.NormalId.Front,Enum.NormalId.Back} do
  local gui=Instance.new("SurfaceGui");gui.Name=PREFIX.."Edges";gui.Face=face
  gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=36
  gui.LightInfluence=.15;gui.MaxDistance=350;gui.Parent=part
  local w,h=part.Size.X,part.Size.Y
  local t=math.min(Config.EdgeThicknessStuds,w*.20,h*.20)
  -- Roblox transcoded this upload to 1024px; crop in uploaded pixels.
  local n,band=1024,155
  local function image(name,x,y,sx,sy,ox,oy,rx,ry)
   local im=Instance.new("ImageLabel");im.Name=name;im.BackgroundTransparency=1
   im.Size=UDim2.fromScale(sx/w,sy/h);im.Position=UDim2.fromScale(x/w,y/h)
   im.Image=Config.ShatteredImage;im.ImageTransparency=.12
   im.ImageRectOffset=Vector2.new(ox,oy);im.ImageRectSize=Vector2.new(rx,ry)
   im.ScaleType=Enum.ScaleType.Stretch;im.Parent=gui
  end
  for _,corner in {{0,0,0,0},{w-t,0,n-band,0},{0,h-t,0,n-band},{w-t,h-t,n-band,n-band}} do
   image("Corner",corner[1],corner[2],t,t,corner[3],corner[4],band,band)
  end
  local span=(n-2*band)/band*t
  local nx=math.max(1,math.ceil((w-2*t)/span));local dx=(w-2*t)/nx
  for i=1,nx do
   image("Top",t+(i-1)*dx,0,dx,t,band,0,n-2*band,band)
   image("Bottom",t+(i-1)*dx,h-t,dx,t,band,n-band,n-2*band,band)
  end
  local ny=math.max(1,math.ceil((h-2*t)/span));local dy=(h-2*t)/ny
  for i=1,ny do
   image("Left",0,t+(i-1)*dy,t,dy,0,band,band,n-2*band)
   image("Right",w-t,t+(i-1)*dy,t,dy,n-band,band,band,n-2*band)
  end
 end
end
local function clearEdges(part)
	for _,o in part:GetChildren() do if o.Name==PREFIX.."Edges" then o:Destroy() end end
end
function V.Apply(part,state,options)
	options=options or {}
	assert(type(state)=="number" and state%1==0 and state>=1 and state<=4,"Invalid glass state")
	V.Capture(part)
	V.ClearTextures(part);clearEdges(part)
	part:SetAttribute("GlassState",state)
	if state==S.Removed then part:Destroy();return end
	part.Material=Enum.Material.Glass
	part.Color=baseline(part)
	part.CanCollide=state<=S.Cracked and part:GetAttribute("GlassIntactCollision")==true
	part.CanTouch=false
	part.Transparency=state==S.Shattered and 1 or part:GetAttribute("GlassBaseTransparency")
	part.Reflectance=state==S.Shattered and 0 or part:GetAttribute("GlassBaseReflectance")
	if options.serverPhysics then part.CanQuery=state<=S.Cracked end
	for _,o in part:GetChildren() do
		if o:IsA("BasePart") and (o.Name=="PrivacyFilm" or o:GetAttribute("GlassAttachedOverlay")) then
			if o:GetAttribute("GlassFilmTransparency")==nil then o:SetAttribute("GlassFilmTransparency",o.Transparency) end
			o.Transparency=state==S.Shattered and 1 or o:GetAttribute("GlassFilmTransparency")
			o.CanCollide=false;o.CanQuery=false
			for _,g in o:GetChildren() do if g:IsA("SurfaceGui") then g.Enabled=state~=S.Shattered end end
		end
	end
	if options.textures~=false then
		if state==S.Cracked then cracks(part)
		elseif state==S.Shattered then brokenEdges(part) end
	end
end
function V.ResetPooled(part)
	V.ClearTextures(part);clearEdges(part)
	part:RemoveTag("GlassPane")
	for key in part:GetAttributes() do if key:sub(1,5)=="Glass" then part:SetAttribute(key,nil) end end
end
return V
