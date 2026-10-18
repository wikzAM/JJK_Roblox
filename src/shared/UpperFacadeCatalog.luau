--!nonstrict
-- Upper-floor (storey >= 2) facade deck. Pure data + deterministic picks; builds nothing.
-- One building = one family/variant/palette/style, seeded from its SourceSliceId.
-- See tools/UPPER_FACADE_STYLE_DECK.md for the references behind each arrangement.
local Catalog = {}
Catalog.VERSION = 1
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
-- Sign/blade colours shared by every family (zakkyo signboards, hotel accents).
local SIGNS = {rgb(196,46,42),rgb(232,190,40),rgb(40,92,170),rgb(46,140,90),rgb(240,240,236),rgb(226,120,40),rgb(190,50,120),rgb(30,30,34)}
local QUIET = {rgb(150,40,46),rgb(48,78,120),rgb(60,104,84),rgb(176,140,70)}
-- wall/band/pier: opaque surfaces; frame: mullions, fins, trim; band2: alternate floor band.
-- Materials are names so a missing Enum entry falls back to Concrete (see Catalog.Mat).
local function pal(t)
	t.wallMat=t.wallMat or "Concrete";t.band=t.band or t.wall;t.bandMat=t.bandMat or t.wallMat
	t.pier=t.pier or t.wall;t.frameMat=t.frameMat or "Metal";t.glassT=t.glassT or .12;t.refl=t.refl or .18
	t.frost=t.frost or rgb(198,204,204);t.dark=t.dark or rgb(52,56,60);t.band2=t.band2 or t.frame
	t.accents=t.accents or QUIET;t.signFace=t.signFace or rgb(244,242,234)
	return t
end
Catalog.PALETTES = {
	-- Glass curtain wall offices (Shibuya Scramble Square / Hikarie / Dogenzaka towers).
	curtainBlue = pal{wall=rgb(150,156,160),wallMat="Metal",band=rgb(44,56,68),bandMat="SmoothPlastic",bandRefl=.15,frame=rgb(168,174,178),glass=rgb(58,78,96),band2=rgb(92,102,112)},
	curtainGreen = pal{wall=rgb(132,140,138),wallMat="Metal",band=rgb(46,60,58),bandMat="SmoothPlastic",bandRefl=.15,frame=rgb(140,148,146),glass=rgb(60,82,78),band2=rgb(88,100,96)},
	curtainSilver = pal{wall=rgb(186,190,192),wallMat="Metal",band=rgb(130,138,144),bandMat="SmoothPlastic",bandRefl=.2,frame=rgb(205,208,210),glass=rgb(112,124,132),glassT=.08,refl=.3,band2=rgb(70,76,82)},
	curtainBronze = pal{wall=rgb(96,84,72),wallMat="Metal",band=rgb(58,50,44),bandMat="SmoothPlastic",bandRefl=.12,frame=rgb(96,84,72),glass=rgb(82,70,58),band2=rgb(140,124,100)},
	curtainBlack = pal{wall=rgb(52,56,60),wallMat="Metal",band=rgb(28,30,34),bandMat="SmoothPlastic",bandRefl=.15,frame=rgb(52,56,60),glass=rgb(36,40,46),glassT=.06,refl=.25,band2=rgb(120,124,128)},
	-- Concrete / tile ribbon-window offices (1970s-90s zakkyo office stock).
	ribbonConcrete = pal{wall=rgb(172,170,163),frame=rgb(190,194,196),glass=rgb(70,86,96),band2=rgb(132,132,128)},
	ribbonWarm = pal{wall=rgb(189,180,164),frame=rgb(120,110,96),glass=rgb(74,80,82),band2=rgb(150,140,124)},
	ribbonTileBeige = pal{wall=rgb(206,192,166),wallMat="CeramicTiles",frame=rgb(176,180,182),glass=rgb(66,80,90),band2=rgb(170,150,120)},
	ribbonTileBrown = pal{wall=rgb(128,96,74),wallMat="CeramicTiles",frame=rgb(70,62,56),glass=rgb(60,66,70),band2=rgb(196,186,168)},
	ribbonWhite = pal{wall=rgb(226,226,220),wallMat="Plaster",frame=rgb(60,64,68),glass=rgb(52,62,70),band2=rgb(150,154,156)},
	-- Aluminium panel / precast grid offices.
	gridWhite = pal{wall=rgb(232,233,230),wallMat="SmoothPlastic",frame=rgb(200,204,206),glass=rgb(62,78,90),band2=rgb(180,184,186)},
	gridSilver = pal{wall=rgb(178,184,188),wallMat="SmoothPlastic",frame=rgb(120,126,130),glass=rgb(56,70,82),band2=rgb(120,126,130)},
	gridChampagne = pal{wall=rgb(200,190,170),wallMat="SmoothPlastic",frame=rgb(150,138,116),glass=rgb(70,74,74),band2=rgb(160,148,126)},
	gridGraphite = pal{wall=rgb(88,92,96),wallMat="SmoothPlastic",frame=rgb(40,44,48),glass=rgb(46,56,64),band2=rgb(130,134,138)},
	gridPrecast = pal{wall=rgb(186,182,172),frame=rgb(110,112,112),glass=rgb(64,76,84),band2=rgb(150,146,138)},
	-- Tile-faced mansions (apartments): white parapet bands over tile walls.
	mansionBeigeTile = pal{wall=rgb(214,198,170),wallMat="CeramicTiles",band=rgb(232,228,218),bandMat="Plaster",frame=rgb(190,192,190),glass=rgb(78,90,96),glassT=.18,band2=rgb(190,176,150)},
	mansionBrownTile = pal{wall=rgb(140,104,80),wallMat="CeramicTiles",band=rgb(196,186,170),bandMat="Plaster",frame=rgb(110,104,96),glass=rgb(70,80,86),glassT=.18,band2=rgb(120,88,66)},
	mansionWhite = pal{wall=rgb(236,234,228),wallMat="Plaster",band=rgb(128,128,124),frame=rgb(170,172,170),glass=rgb(74,88,96),glassT=.18,band2=rgb(210,206,196)},
	mansionGreyTile = pal{wall=rgb(150,148,142),wallMat="CeramicTiles",band=rgb(220,218,210),bandMat="Plaster",frame=rgb(196,198,198),glass=rgb(66,78,86),glassT=.18,band2=rgb(120,118,112)},
	mansionTerracotta = pal{wall=rgb(176,120,92),wallMat="CeramicTiles",band=rgb(230,222,206),bandMat="Plaster",frame=rgb(150,146,140),glass=rgb(72,82,86),glassT=.18,band2=rgb(150,100,76)},
	-- Mortar / stucco small residential and walk-up offices.
	stuccoCream = pal{wall=rgb(226,214,190),wallMat="Plaster",frame=rgb(170,172,170),glass=rgb(80,92,98),glassT=.2,band2=rgb(196,184,160)},
	stuccoWhite = pal{wall=rgb(238,238,232),wallMat="Plaster",frame=rgb(120,124,126),glass=rgb(76,88,96),glassT=.2,band2=rgb(200,200,194)},
	stuccoSand = pal{wall=rgb(204,188,158),wallMat="Plaster",frame=rgb(110,96,80),glass=rgb(74,82,86),glassT=.2,band2=rgb(176,160,130)},
	stuccoMint = pal{wall=rgb(196,210,198),wallMat="Plaster",frame=rgb(150,156,152),glass=rgb(76,90,92),glassT=.2,band2=rgb(166,182,170)},
	stuccoPink = pal{wall=rgb(220,196,188),wallMat="Plaster",frame=rgb(160,150,146),glass=rgb(80,88,92),glassT=.2,band2=rgb(196,168,160)},
	stuccoGrey = pal{wall=rgb(176,176,172),wallMat="Plaster",frame=rgb(96,98,100),glass=rgb(70,80,88),glassT=.2,band2=rgb(146,146,142)},
	-- Brick-tile older offices and mixed use.
	brickBrown = pal{wall=rgb(124,82,62),wallMat="Brick",bandMat="Concrete",band=rgb(196,188,172),frame=rgb(184,186,184),glass=rgb(62,70,74),band2=rgb(150,140,124)},
	brickRed = pal{wall=rgb(150,72,56),wallMat="Brick",bandMat="Concrete",band=rgb(210,202,186),frame=rgb(200,200,196),glass=rgb(60,68,72),band2=rgb(120,60,48)},
	brickDark = pal{wall=rgb(84,62,52),wallMat="Brick",bandMat="Concrete",band=rgb(150,146,138),frame=rgb(60,58,56),glass=rgb(52,58,62),band2=rgb(110,84,70)},
	brickOchre = pal{wall=rgb(176,136,92),wallMat="Brick",bandMat="Concrete",band=rgb(220,210,190),frame=rgb(120,104,86),glass=rgb(66,72,74),band2=rgb(150,112,76)},
	-- Fin / louver commercial (Omotesando, Jingumae, Shibuya boutique offices).
	louverAlu = pal{wall=rgb(120,124,128),wallMat="Metal",band=rgb(70,74,78),bandMat="SmoothPlastic",frame=rgb(210,212,212),glass=rgb(44,54,62),band2=rgb(160,164,166)},
	louverBronze = pal{wall=rgb(84,72,60),wallMat="Metal",band=rgb(60,52,46),bandMat="SmoothPlastic",frame=rgb(128,104,76),glass=rgb(50,52,52),band2=rgb(110,96,80)},
	louverWhite = pal{wall=rgb(220,220,216),wallMat="SmoothPlastic",band=rgb(200,200,196),frame=rgb(240,240,236),glass=rgb(60,72,80),band2=rgb(170,172,170)},
	louverTimber = pal{wall=rgb(60,62,64),wallMat="SmoothPlastic",band=rgb(48,50,52),frame=rgb(150,112,72),frameMat="Wood",glass=rgb(46,52,56),band2=rgb(120,90,60)},
	louverBlack = pal{wall=rgb(34,36,38),wallMat="SmoothPlastic",band=rgb(28,30,32),frame=rgb(40,42,44),glass=rgb(30,34,38),glassT=.06,band2=rgb(90,92,94)},
	-- Zakkyo / pencil mixed-use with stacked signboards.
	zakkyoTile = pal{wall=rgb(186,176,160),wallMat="CeramicTiles",frame=rgb(170,174,176),glass=rgb(70,82,90),accents=SIGNS,band2=rgb(150,140,124)},
	zakkyoGrey = pal{wall=rgb(150,152,152),frame=rgb(200,202,204),glass=rgb(60,72,82),accents=SIGNS,band2=rgb(110,112,112)},
	zakkyoWhite = pal{wall=rgb(228,228,222),wallMat="SmoothPlastic",frame=rgb(150,154,156),glass=rgb(64,78,88),accents=SIGNS,band2=rgb(196,196,190)},
	zakkyoBrown = pal{wall=rgb(112,88,70),wallMat="CeramicTiles",frame=rgb(180,180,176),glass=rgb(60,66,70),accents=SIGNS,band2=rgb(150,124,100)},
	zakkyoBlack = pal{wall=rgb(52,54,58),wallMat="SmoothPlastic",frame=rgb(120,122,124),glass=rgb(40,46,52),accents=SIGNS,band2=rgb(86,88,92)},
	-- Business hotels: dense small room windows.
	hotelWhite = pal{wall=rgb(232,232,228),wallMat="SmoothPlastic",band=rgb(210,210,206),frame=rgb(150,154,156),glass=rgb(60,72,82),accents={rgb(150,40,46),rgb(48,78,120)},band2=rgb(180,180,176)},
	hotelGrey = pal{wall=rgb(140,144,148),wallMat="SmoothPlastic",band=rgb(120,124,128),frame=rgb(210,212,212),glass=rgb(50,60,70),accents={rgb(196,160,90),rgb(220,220,214)},band2=rgb(96,100,104)},
	hotelBeige = pal{wall=rgb(206,196,176),wallMat="CeramicTiles",frame=rgb(140,128,110),glass=rgb(64,72,78),accents={rgb(120,70,50),rgb(60,90,80)},band2=rgb(176,164,140)},
	hotelNavy = pal{wall=rgb(54,64,84),wallMat="SmoothPlastic",frame=rgb(200,200,200),glass=rgb(40,48,60),accents={rgb(200,200,196),rgb(196,160,90)},band2=rgb(80,92,112)},
	-- Showa-era walk-ups: mosaic tile, steel sash, small windows.
	showaBrown = pal{wall=rgb(112,82,62),wallMat="CeramicTiles",frame=rgb(122,150,134),frameMat="SmoothPlastic",glass=rgb(80,92,94),glassT=.2,band2=rgb(150,130,108)},
	showaMustard = pal{wall=rgb(190,160,96),wallMat="CeramicTiles",frame=rgb(90,92,90),glass=rgb(76,86,88),glassT=.2,band2=rgb(150,124,70)},
	showaMortar = pal{wall=rgb(168,164,152),frame=rgb(90,110,120),frameMat="SmoothPlastic",glass=rgb(80,92,98),glassT=.2,band2=rgb(136,132,122)},
	showaOlive = pal{wall=rgb(110,118,86),wallMat="CeramicTiles",frame=rgb(196,196,186),glass=rgb(70,80,80),glassT=.2,band2=rgb(150,150,120)},
}
-- Variant defaults (studs): module = target bay width, pier = solid between windows,
-- sill = band above slab top, head = band below next slab. ribbon = mullions, no piers.
local DEFAULT = {endPier=1.2,mullion=.25,paneW=5,sill=3,head=2.4,minWidth=8,autoTransom=14}
Catalog.VARIANTS = {
	{id="A1_CurtainGrid",family="curtain",title="Unitised glass grid",ribbon=true,module=10,paneW=5,sill=.8,head=1.2,endPier=.9,minWidth=6,paneChoices={1,2}},
	{id="A2_CurtainFins",family="curtain",title="Glass with proud vertical aluminium fins",ribbon=true,module=9,paneW=4.5,sill=.8,head=1.2,endPier=.9,minWidth=6,fins={spacing="bay",depth=.9,width=.35,full=true}},
	{id="A3_CurtainStripe",family="curtain",title="Alternating glass and spandrel-glass stripes",ribbon=true,module=10,paneW=5,sill=3.4,head=1.8,endPier=.9,minWidth=6},
	{id="A4_CurtainChecker",family="curtain",title="Curtain wall with opaque panel columns",ribbon=true,module=6,paneW=6,sill=.8,head=1.2,endPier=.9,minWidth=6,cycle={"window","window","panel"}},
	{id="B1_RibbonConcrete",family="ribbon",title="Concrete office, continuous ribbon window",ribbon=true,module=6,paneW=6,sill=3.2,head=2.4,mullion=.3},
	{id="B2_RibbonTile",family="ribbon",title="Tile spandrel ribbon, sliding sash with fanlight",ribbon=true,module=7,paneW=3.5,sill=3,head=2.8,transom=.78,paneChoices={1,2}},
	{id="B3_RibbonEave",family="ribbon",title="Ribbon window under a thin sunshade eave",ribbon=true,module=8,paneW=4,sill=2.8,head=2.4,eave={depth=.9,thick=.3}},
	{id="C1_PanelGrid",family="grid",title="Aluminium panel grid, single punched windows",module=8,pier=2.6,panes=1,sill=3.4,head=2.8},
	{id="C2_PairedGrid",family="grid",title="Wide panel grid, paired windows",module=12,pier=3.4,panes=2,sill=3,head=2.4},
	{id="C3_PrecastVertical",family="grid",title="Precast vertical piers, recessed spandrels",module=6,pier=1.8,pierProud=true,panes=1,sill=3.6,head=2,transom=.75},
	{id="D1_BalconySolid",family="mansion",title="Continuous balcony, solid parapet, unit dividers",module=18,pier=.8,paneW=4.5,sill=0,head=2.4,balcony={height=3.6,divider=true},side="D3_PunchedTile",minWidth=14},
	{id="D2_CorridorSide",family="mansion",title="Open access corridor: parapet, doors, small windows",module=16,pier=.8,sill=0,head=2.4,corridor={height=3.6},side="D3_PunchedTile",minWidth=14},
	{id="D3_PunchedTile",family="mansion",title="Tile wall, sliding pair windows, bathroom slots",module=10,pier=4,panes=2,sill=3.4,head=2.6,cycle={"window","window","small"}},
	{id="D4_BalconyRail",family="mansion",title="Balcony with translucent rail band",module=16,pier=.8,paneW=4,sill=0,head=2.4,balcony={height=3.4,rail=true,divider=true},side="D3_PunchedTile",minWidth=14},
	{id="E1_StuccoPunched",family="stucco",title="Mortar wall, punched sliding windows",module=10,pier=4.4,panes=2,sill=3.4,head=2.8,sillTrim=true},
	{id="E2_StuccoPrivacy",family="stucco",title="Mortar wall, window / frosted slot / vent rhythm",module=9,pier=3,panes=1,sill=3.4,head=2.8,cycle={"window","small","vent"}},
	{id="E3_StuccoSlots",family="stucco",title="Narrow vertical slot windows",module=6,pier=1,sill=1.6,head=2.2,cycle={"slot"},minWidth=6},
	{id="F1_BrickPunched",family="brick",title="Brick tile, punched windows with fanlight",module=9,pier=3.6,panes=2,sill=3.2,head=2.6,sillTrim=true,transom=.78,bandWall=true},
	{id="F2_BrickPierSpandrel",family="brick",title="Brick piers over pale concrete spandrels",module=8,pier=1.6,panes=1,sill=3.4,head=2.4},
	{id="G1_VerticalLouver",family="louver",title="Glass behind dense vertical louvers",ribbon=true,module=10,paneW=5,sill=1,head=1.4,endPier=.9,fins={spacing=2.2,depth=.9,width=.25,full=true}},
	{id="G2_HorizontalLouver",family="louver",title="Glass with horizontal sunshade blades",ribbon=true,module=10,paneW=5,sill=1,head=1.4,endPier=.9,louvers={gap=2.6,depth=.8,thick=.22}},
	{id="G3_MetalScreen",family="louver",title="Expanded-metal screen over upper glazing",ribbon=true,module=9,paneW=4.5,sill=1.2,head=1.4,endPier=.9,screen={from=.45,transparency=.35}},
	{id="H1_SignStack",family="zakkyo",title="Mixed-use with a stacked signboard bay",module=9,pier=1.4,panes=2,sill=3,head=2.2,signs="vertical",side="H3_PencilPunched"},
	{id="H2_FasciaBand",family="zakkyo",title="Tenant fascia sign on every floor over ribbon glass",ribbon=true,module=8,paneW=4,sill=2.6,head=3.4,signs="band",side="H3_PencilPunched"},
	{id="H3_PencilPunched",family="zakkyo",title="Pencil building, single punched windows",module=7,pier=2.4,panes=1,sill=3.2,head=2.6,sillTrim=true,minWidth=6},
	{id="I1_HotelSlots",family="hotel",title="Business hotel, one small window per room",module=6,pier=2.6,panes=1,sill=3.6,head=2.8,minWidth=6},
	{id="I2_HotelAccentBay",family="hotel",title="Hotel with continuous coloured piers",module=7,pier=1.6,panes=1,sill=3.2,head=2.4,accentPiers=true,minWidth=6},
	{id="J1_ShowaSmall",family="showa",title="Showa walk-up, small windows and slots",module=8,pier=4.4,panes=2,sill=3.6,head=3,sillTrim=true,cycle={"window","small"}},
	{id="J2_ShowaSteelSash",family="showa",title="Showa steel sash band, two-row lights",ribbon=true,module=5,paneW=5,sill=3.2,head=2.6,transom=.6,mullion=.2},
}
-- Family weights by building class: small (<=3 storeys), pencil (narrow), mid, tall (>=9).
-- blade/ac/rail: chance that a building carries that feature.
Catalog.FAMILIES = {
	{id="curtain",quiet="A1_CurtainGrid",weights={small=0,pencil=1,mid=2,tall=6},blade=0,ac=0,rail=0,palettes={"curtainBlue","curtainGreen","curtainSilver","curtainBronze","curtainBlack"}},
	{id="ribbon",quiet="B1_RibbonConcrete",weights={small=1,pencil=2,mid=4,tall=3},blade=.25,ac=.2,rail=0,palettes={"ribbonConcrete","ribbonWarm","ribbonTileBeige","ribbonTileBrown","ribbonWhite"}},
	{id="grid",quiet="C1_PanelGrid",weights={small=1,pencil=1,mid=3,tall=4},blade=.1,ac=0,rail=0,palettes={"gridWhite","gridSilver","gridChampagne","gridGraphite","gridPrecast"}},
	{id="mansion",quiet="D3_PunchedTile",weights={small=2,pencil=1,mid=4,tall=3},blade=0,ac=.5,rail=.2,palettes={"mansionBeigeTile","mansionBrownTile","mansionWhite","mansionGreyTile","mansionTerracotta"}},
	{id="stucco",quiet="E1_StuccoPunched",weights={small=5,pencil=2,mid=2,tall=0},blade=.15,ac=.45,rail=.3,palettes={"stuccoCream","stuccoWhite","stuccoSand","stuccoMint","stuccoPink","stuccoGrey"}},
	{id="brick",quiet="F1_BrickPunched",weights={small=2,pencil=1,mid=3,tall=1},blade=.2,ac=.25,rail=.15,palettes={"brickBrown","brickRed","brickDark","brickOchre"}},
	{id="louver",quiet="G2_HorizontalLouver",weights={small=1,pencil=2,mid=2,tall=2},blade=0,ac=0,rail=0,palettes={"louverAlu","louverBronze","louverWhite","louverTimber","louverBlack"}},
	{id="zakkyo",quiet="H3_PencilPunched",weights={small=2,pencil=6,mid=3,tall=0},blade=.6,ac=.4,rail=.15,palettes={"zakkyoTile","zakkyoGrey","zakkyoWhite","zakkyoBrown","zakkyoBlack"}},
	{id="hotel",quiet="I1_HotelSlots",weights={small=0,pencil=2,mid=2,tall=3},blade=.3,ac=0,rail=0,palettes={"hotelWhite","hotelGrey","hotelBeige","hotelNavy"}},
	{id="showa",quiet="J1_ShowaSmall",weights={small=3,pencil=2,mid=2,tall=0},blade=.3,ac=.5,rail=.25,palettes={"showaBrown","showaMustard","showaMortar","showaOlive"}},
}
Catalog.CLASSES = {"small","pencil","mid","tall"}
Catalog.BAND_MODES = {{"none",5},{"alt",1},{"podium",2},{"every3",1}}
Catalog.CROWNS = {{"none",13},{"attic",3},{"cornice",3},{"colorTop",2},{"glassTop",1}}
local byId,famById={},{}
for _,v in Catalog.VARIANTS do
	for k,d in DEFAULT do if v[k]==nil then v[k]=d end end
	v.pier=v.pier or (v.ribbon and v.mullion or 2);byId[v.id]=v
end
for _,f in Catalog.FAMILIES do
	famById[f.id]=f;f.variants={}
	for _,v in Catalog.VARIANTS do if v.family==f.id then table.insert(f.variants,v.id);v.palette=v.palette or f.palettes[1] end end
end
function Catalog.Get(id) return byId[id] or error("Unknown upper facade variant: "..tostring(id)) end
function Catalog.Family(id) return famById[id] or error("Unknown upper facade family: "..tostring(id)) end
function Catalog.Palette(p)
	if type(p)=="table" then return p end
	return Catalog.PALETTES[p] or error("Unknown upper facade palette: "..tostring(p))
end
local mats={}
function Catalog.Mat(name)
	if typeof(name)=="EnumItem" then return name end
	if mats[name]==nil then local ok,m=pcall(function() return Enum.Material[name] end);mats[name]=ok and m or Enum.Material.Concrete end
	return mats[name]
end
-- Same djb2 hash as GroundFacadeCatalog.Seed, so keys stay comparable.
function Catalog.Seed(key)
	local h=5381
	for i=1,#key do h=(h*33+string.byte(key,i))%2147483647 end
	return h
end
-- Independent roll per tag: adding a new style field never reshuffles older ones.
function Catalog.Roll(seed,tag) return Random.new(Catalog.Seed(seed.."/"..tag)):NextNumber() end
local function weighted(rows,r)
	local total=0;for _,row in rows do total+=row[2] end
	if total<=0 then return nil end
	r*=total
	for _,row in rows do r-=row[2];if r<=0 then return row[1] end end
	return rows[#rows][1]
end
function Catalog.Classify(storeys,maxRun)
	if storeys>=9 then return "tall" end
	if maxRun and maxRun<28 and storeys>=3 then return "pencil" end
	if storeys<=3 then return "small" end
	return "mid"
end
function Catalog.PickFamily(seed,class)
	local rows={};for _,f in Catalog.FAMILIES do table.insert(rows,{f.id,f.weights[class or "mid"] or 0}) end
	return Catalog.Family(weighted(rows,Catalog.Roll(seed,"family")) or "ribbon")
end
function Catalog.PickVariant(family,seed)
	local f=type(family)=="table" and family or Catalog.Family(family)
	local rows={};for _,id in f.variants do table.insert(rows,{id,byId[id].weight or 1}) end
	return Catalog.Get(weighted(rows,Catalog.Roll(seed,"variant")))
end
function Catalog.PickPalette(family,seed)
	local f=type(family)=="table" and family or Catalog.Family(family)
	return f.palettes[math.floor(Catalog.Roll(seed,"palette")*#f.palettes)+1]
end
-- Whole-building style: every choice is a pure function of (seed, class).
function Catalog.Pick(seed,class)
	assert(type(seed)=="string" and #seed>0,"Upper facade pick needs a stable seed string")
	local f=Catalog.PickFamily(seed,class)
	local v=Catalog.PickVariant(f,seed)
	local paletteName=Catalog.PickPalette(f,seed)
	local function span(tag,lo,hi,step) return math.floor((lo+Catalog.Roll(seed,tag)*(hi-lo))/step+.5)*step end
	local style={seed=seed,class=class or "mid",family=f.id,variant=v.id,palette=paletteName,
		moduleScale=span("module",.85,1.2,.05),sillScale=span("sill",.85,1.2,.05),headScale=span("head",.85,1.2,.05),
		bandMode=weighted(Catalog.BAND_MODES,Catalog.Roll(seed,"band")),crown=weighted(Catalog.CROWNS,Catalog.Roll(seed,"crown")),
		cycleOffset=math.floor(Catalog.Roll(seed,"cycle")*6),accentIndex=math.floor(Catalog.Roll(seed,"accent")*8)+1}
	if v.paneChoices then style.panes=v.paneChoices[math.floor(Catalog.Roll(seed,"panes")*#v.paneChoices)+1] end
	if Catalog.Roll(seed,"blade")<f.blade then
		style.blade={side=Catalog.Roll(seed,"bladeSide")<.5 and -1 or 1,floors=2+math.floor(Catalog.Roll(seed,"bladeFloors")*4),width=1.8+math.floor(Catalog.Roll(seed,"bladeWidth")*3)*.4}
	end
	style.ac=Catalog.Roll(seed,"ac")<f.ac
	style.rail=Catalog.Roll(seed,"rail")<f.rail
	return style
end
return Catalog
