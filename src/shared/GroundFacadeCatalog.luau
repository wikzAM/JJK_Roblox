--!nonstrict
-- Draft street-level kit, October 8, 2026. No runtime or city mutations.
-- Single-storey types fit existing tuning; tall types explicitly occupy two storeys.
local Names = require(script.Parent.GroundFacadeNames)
local Catalog = {}
Catalog.VERSION = 7
Catalog.PALETTES = {
	stone = {wall=Color3.fromRGB(179,175,165), trim=Color3.fromRGB(43,47,48), accent=Color3.fromRGB(178,146,86)},
	cream = {wall=Color3.fromRGB(219,210,187), trim=Color3.fromRGB(62,54,45), accent=Color3.fromRGB(101,121,98)},
	charcoal = {wall=Color3.fromRGB(63,66,69), trim=Color3.fromRGB(26,29,32), accent=Color3.fromRGB(191,162,110)},
	brick = {wall=Color3.fromRGB(129,87,70), trim=Color3.fromRGB(40,43,45), accent=Color3.fromRGB(220,207,177)},
	grey = {wall=Color3.fromRGB(163,162,165), trim=Color3.fromRGB(74,78,80), accent=Color3.fromRGB(123,133,133)},
	white = {wall=Color3.fromRGB(237,238,234), trim=Color3.fromRGB(57,63,65), accent=Color3.fromRGB(85,112,119)},
	offwhite = {wall=Color3.fromRGB(224,222,212), trim=Color3.fromRGB(67,64,59), accent=Color3.fromRGB(133,116,87)},
	darkBrown = {wall=Color3.fromRGB(83,65,54), trim=Color3.fromRGB(35,29,26), accent=Color3.fromRGB(208,185,145)},
}
-- Widths vary within a type's fit range; doors, handles and trim stay human-scale.
Catalog.TYPES = {
	{id="01_Konbini", title="Convenience shop", family="retail", width=36, minWidth=28, maxWidth=48, palette="stone", brand="まちマート / MACHI MART", subtitle="24H  /  DAILY GOODS", feature="stripe", accent=Color3.fromRGB(45,129,114), door="slide", depth=1.2},
	{id="02_Coffee", title="Neighbourhood coffee", family="retail", width=28, minWidth=22, maxWidth=38, palette="cream", brand="喫茶 なぎ / NAGI", subtitle="COFFEE  &  TEA", feature="awning", accent=Color3.fromRGB(70,99,88), door="single", depth=1.4},
	{id="03_Ramen", title="Ramen ticket shop", family="food", width=20, minWidth=18, maxWidth=28, palette="charcoal", brand="麺処 あお / AO RAMEN", subtitle="らーめん  /  RAMEN", feature="noren", accent=Color3.fromRGB(154,47,39), door="slide", depth=1.4},
	{id="04_Izakaya", title="Timber izakaya", family="food", width=24, minWidth=20, maxWidth=32, palette="charcoal", brand="酒場 こま / KOMA", subtitle="小皿とお酒  /  IZAKAYA", feature="lattice", accent=Color3.fromRGB(169,117,63), door="slide", depth=1.8},
	{id="05_Bakery", title="Brick bakery", family="retail", width=28, minWidth=22, maxWidth=38, palette="brick", brand="こむぎ / KOMUGI", subtitle="BAKERY  /  FRESH DAILY", feature="bakery", accent=Color3.fromRGB(197,157,89), door="single", depth=1.2},
	{id="06_Boutique", title="Recessed fashion boutique", family="retail", width=32, minWidth=24, maxWidth=44, palette="cream", brand="余白 / YOHAKU", subtitle="CLOTHING  &  OBJECTS", feature="display", accent=Color3.fromRGB(182,168,142), door="double", depth=2.6},
	{id="07_Showroom", title="Glass flagship showroom", family="retail", width=36, minWidth=28, maxWidth=48, palette="charcoal", brand="FRAME / フレーム", subtitle="DESIGN  /  STUDIO", feature="showroom", accent=Color3.fromRGB(188,197,206), door="double", depth=2.2},
	{id="08_Pharmacy", title="Neighbourhood pharmacy", family="retail", width=32, minWidth=24, maxWidth=44, palette="stone", brand="あさひ薬局 / ASAHI", subtitle="薬  /  PHARMACY", feature="pharmacy", accent=Color3.fromRGB(61,122,157), door="slide", depth=1.2},
	{id="09_Shutter", title="Closed tenant shutter", family="service", width=24, minWidth=16, maxWidth=36, palette="stone", brand="貸店舗 / TO LET", subtitle="RETAIL SPACE", feature="shutter", accent=Color3.fromRGB(104,113,122), door="none", depth=0.6},
	{id="10_TenantEntry", title="Upper-floor tenant entry", family="entry", width=16, minWidth=14, maxWidth=22, palette="charcoal", brand="青葉ビル / AOBA BLDG", subtitle="2F CAFE  /  3F STUDIO  /  4F OFFICE", feature="directory", accent=Color3.fromRGB(174,181,180), door="double", depth=3.0},
	{id="11_OfficeStone", title="Stone office lobby", family="office", width=40, minWidth=30, maxWidth=52, palette="stone", brand="南青山 / MINAMI OFFICE", subtitle="OFFICE ENTRANCE", feature="stoneLobby", accent=Color3.fromRGB(160,137,91), door="double", depth=3.2},
	{id="12_OfficeGlass", title="Glass office reception", family="office", width=48, minWidth=36, maxWidth=60, palette="charcoal", brand="SAKURA / WORKPLACE", subtitle="LOBBY  /  RECEPTION", feature="glassLobby", accent=Color3.fromRGB(115,142,151), door="slide", depth=2.8},
	{id="13_HotelCanopy", title="Business hotel canopy", family="hotel", width=48, minWidth=36, maxWidth=60, palette="charcoal", brand="HOTEL TSUKI / 月", subtitle="ENTRANCE  /  RECEPTION", feature="hotel", accent=Color3.fromRGB(176,148,98), door="slide", depth=3.4},
	{id="14_HotelTimber", title="Small timber hotel", family="hotel", width=32, minWidth=26, maxWidth=42, palette="cream", brand="HOTEL MORI / 森", subtitle="STAY  /  LOUNGE", feature="timberHotel", accent=Color3.fromRGB(123,92,61), door="double", depth=2.8},
	{id="15_Residential", title="Apartment lobby and mail", family="residential", width=24, minWidth=20, maxWidth=34, palette="stone", brand="桜レジデンス / SAKURA", subtitle="RESIDENCE  /  PRIVATE ENTRY", feature="mail", accent=Color3.fromRGB(101,113,111), door="single", depth=2.4},
}
-- Screenshot-led expansion: physical openings/materials/circulation, not sign reskins.
local additions = {
	{"16_ChainBurger","Wood-clad chain restaurant","food",36,30,48,"brick","burger","ひかりバーガー / HIKARI BURGER"},
	{"17_ChainGrille","Twin restaurant security grilles","food",48,40,60,"charcoal","grille","まちキッチン / MACHI KITCHEN"},
	{"18_PosterKonbini","Poster-dense sliding convenience shop","retail",32,28,44,"stone","posterShop","まちストア / MACHI STORE"},
	{"19_LocalShop","Tiled Japanese local shop","retail",22,20,30,"cream","localShop","つむぎ商店"},
	{"20_ProduceShop","Open-front greengrocer","retail",30,26,40,"cream","produce","青葉青果"},
	{"21_TakeawayHatch","Concrete takeaway serving hatch","food",22,20,30,"stone","hatch","こはる弁当"},
	{"22_HairSalon","Frosted salon with inset entry","retail",28,24,38,"cream","salon","凪音美容室 / NAGINE"},
	{"23_Electronics","Boxed display and repair shop","retail",28,24,38,"charcoal","electronics","みなと電気"},
	{"24_ConcreteSparse","Plain concrete, high windows, steel door","service",30,24,44,"stone","sparse",""},
	{"25_ConcreteDouble","Concrete service front, two doors","service",32,28,44,"stone","servicePair",""},
	{"26_BrickResidential","Brick residence, frost and planted edge","residential",28,24,38,"cream","brickHome","桜レジデンス"},
	{"27_TownhouseColumns","Townhouse columns and privacy fins","residential",24,22,34,"charcoal","townhouse",""},
	{"28_ApartmentGate","Low wall and gated apartment approach","residential",32,28,44,"cream","gateHome","青葉ハウス"},
	{"29_RaisedEntry","Garage shutter and separate raised entry","residential",32,30,44,"cream","raised","楓ハウス"},
	{"30_OpenGarage","Single open concrete parking bay","parking",28,22,40,"stone","garage",""},
	{"31_TwinGarage","Two open bays, central pier","parking",44,36,60,"cream","twinGarage",""},
	{"32_PilotisParking","Open pilotis with round columns","parking",48,40,60,"stone","pilotis",""},
	{"33_LoadingBay","Open loading portal and service entry","service",40,34,52,"charcoal","loading","搬入口 / DELIVERY"},
	{"34_TwoStoreyGlass","Two-storey glazing with ribbed spandrel","office",44,36,60,"charcoal","stackedGlass","AOBA / WORKPLACE"},
	{"35_DoubleHeightGlass","Double-height point-fixed glass vestibule","office",48,40,60,"stone","tallGlass","SAKURA / LOBBY"},
	{"36_McDooDoos","McDooDoo's red canopy restaurant","food",36,28,48,"charcoal","fastFood","McDooDoo's"},
	{"37_SmashKing","Smash King brick and timber burger shop","food",36,28,48,"brick","kingBurger","SMASH KING"},
	{"38_Starboys","Starboys green coffee and timber fins","retail",32,26,44,"cream","coffeeChain","STARBOYS"},
}
for _,a in additions do
	local tall=a[8]=="stackedGlass" or a[8]=="tallGlass"
	table.insert(Catalog.TYPES,{id=a[1],title=a[2],family=a[3],width=a[4],minWidth=a[5],maxWidth=a[6],
		palette=a[7],feature=a[8],brand=a[9],subtitle="",generation=2,height=tall and 29.5 or 12.5,
		minHeight=tall and 27.5 or (a[8]=="raised" and 11.5 or 10.5),maxHeight=tall and 36 or 24,floorSpan=tall and 2 or 1,
		requiresVoid=a[8]=="tallGlass",depth=2})
end
-- Quiet sides/back faces are physical designs too, with no default shop identity.
local perimeter = {
	{"39_PlainConcrete","Blank grey concrete wall","service",24,2,48,"grey","plainWall",true},
	{"40_PanelSeams","Concrete panels with recessed seams","service",28,8,48,"grey","panelWall",true},
	{"41_HighSlit","High horizontal privacy window","service",24,12,40,"grey","highSlit",true},
	{"42_PairedFrost","Two modest frosted residential windows","residential",24,16,40,"stone","pairedFrost",true},
	{"43_UtilityWall","Vent and drainpipe service wall","service",24,12,40,"grey","utilityWall",true},
	{"44_RearSteelDoor","Quiet rear steel door and small transom","service",20,14,34,"grey","rearDoor",true},
	{"45_TiledBoundary","Tiled wall with low ledge and inset window","residential",28,18,42,"cream","tiledWall",true},
	{"46_Laundry","Laundry with split transom and machine display","retail",28,24,40,"stone","laundry",false},
	{"47_BicycleRepair","Cycle repair shutter and workshop glazing","service",28,24,40,"charcoal","bicycle",false},
	{"48_Florist","Timber flower shop and recessed display shelves","retail",26,24,38,"cream","florist",false},
	{"49_Clinic","Pale clinic with opaque privacy panels","service",30,26,42,"stone","clinic",false},
	{"50_Bookshop","Deep framed bookshop with display pilasters","retail",28,24,40,"brick","bookshop",false},
	{"51_SobaShop","Soba shop with half wall and narrow noren","food",24,22,34,"charcoal","soba",false},
	{"52_Bathhouse","Tiled bathhouse-style split entrance","service",32,28,44,"stone","bathhouse",false},
	{"53_TimberHouse","Quiet timber house with projecting screen","residential",24,22,36,"cream","timberHouse",false},
}
for _,a in perimeter do
	local identity=not a[9] and Names.Generate(a[3],a[1],{feature=a[8]}) or nil
	table.insert(Catalog.TYPES,{id=a[1],title=a[2],family=a[3],width=a[4],minWidth=a[5],maxWidth=a[6],palette=a[7],feature=a[8],signless=a[9],brand=identity and identity.brand or "",subtitle=identity and identity.subtitle or "",generation=3,height=12.5,minHeight=10.5,maxHeight=24,floorSpan=1,depth=1.5})
end
-- Art-direction weights, not a measured census. No random storefronts on a landmark.
Catalog.PROFILES = {
	mixed = {{"01_Konbini",2},{"02_Coffee",3},{"03_Ramen",2},{"04_Izakaya",2},{"05_Bakery",2},{"06_Boutique",3},{"07_Showroom",1},{"08_Pharmacy",1},{"09_Shutter",1}},
	retail = {{"01_Konbini",2},{"02_Coffee",2},{"05_Bakery",2},{"06_Boutique",4},{"07_Showroom",2},{"08_Pharmacy",1}},
	alley = {{"03_Ramen",4},{"04_Izakaya",4},{"09_Shutter",2},{"02_Coffee",1}},
	office = {{"11_OfficeStone",1},{"12_OfficeGlass",1}},
	hotel = {{"13_HotelCanopy",1},{"14_HotelTimber",1}},
	residential = {{"15_Residential",1}},
}
Catalog.PROFILES.mixed = {{"01_Konbini",2},{"02_Coffee",2},{"03_Ramen",2},{"04_Izakaya",2},{"05_Bakery",1},{"06_Boutique",2},{"09_Shutter",1},{"16_ChainBurger",2},{"17_ChainGrille",1},{"18_PosterKonbini",2},{"19_LocalShop",3},{"20_ProduceShop",1},{"21_TakeawayHatch",2},{"22_HairSalon",2},{"23_Electronics",1},{"24_ConcreteSparse",1},{"26_BrickResidential",1},{"30_OpenGarage",1}}
Catalog.PROFILES.retail = {{"01_Konbini",2},{"02_Coffee",2},{"05_Bakery",1},{"06_Boutique",2},{"07_Showroom",1},{"08_Pharmacy",1},{"18_PosterKonbini",3},{"19_LocalShop",3},{"20_ProduceShop",1},{"22_HairSalon",2},{"23_Electronics",2}}
Catalog.PROFILES.alley = {{"03_Ramen",3},{"04_Izakaya",3},{"09_Shutter",2},{"19_LocalShop",2},{"21_TakeawayHatch",2},{"24_ConcreteSparse",2},{"25_ConcreteDouble",1},{"30_OpenGarage",2}}
Catalog.PROFILES.residential = {{"15_Residential",1},{"26_BrickResidential",3},{"27_TownhouseColumns",2},{"28_ApartmentGate",2}}
Catalog.PROFILES.residentialStreet = {{"24_ConcreteSparse",2},{"26_BrickResidential",3},{"27_TownhouseColumns",3},{"28_ApartmentGate",2},{"29_RaisedEntry",2},{"30_OpenGarage",2},{"31_TwinGarage",1}}
Catalog.PROFILES.parking = {{"30_OpenGarage",3},{"31_TwinGarage",2},{"32_PilotisParking",1}}
Catalog.PROFILES.service = {{"24_ConcreteSparse",3},{"25_ConcreteDouble",2},{"33_LoadingBay",1},{"09_Shutter",2}}
-- Tall types are opt-in: never picked for an ordinary ground storey.
Catalog.PROFILES.twoStorey = {{"34_TwoStoreyGlass",1}}
Catalog.PROFILES.atrium = {{"35_DoubleHeightGlass",1}}
Catalog.PROFILES.chains = {{"36_McDooDoos",1},{"37_SmashKing",1},{"38_Starboys",1}}
table.insert(Catalog.PROFILES.mixed,{"36_McDooDoos",1})
table.insert(Catalog.PROFILES.mixed,{"37_SmashKing",1})
table.insert(Catalog.PROFILES.retail,{"38_Starboys",1})
Catalog.PROFILES.blind = {{"39_PlainConcrete",5},{"40_PanelSeams",3},{"43_UtilityWall",1},{"45_TiledBoundary",1}}
Catalog.PROFILES.window = {{"41_HighSlit",3},{"42_PairedFrost",3},{"45_TiledBoundary",2}}
Catalog.PROFILES.backStreet = {{"39_PlainConcrete",2},{"40_PanelSeams",2},{"41_HighSlit",2},{"42_PairedFrost",2},{"43_UtilityWall",2},{"44_RearSteelDoor",1},{"45_TiledBoundary",1}}
Catalog.PROFILES.tokyo = {{"46_Laundry",2},{"47_BicycleRepair",1},{"48_Florist",2},{"49_Clinic",1},{"50_Bookshop",2},{"51_SobaShop",3},{"52_Bathhouse",1},{"53_TimberHouse",2}}
for _,id in {"46_Laundry","48_Florist","50_Bookshop"} do table.insert(Catalog.PROFILES.retail,{id,1});table.insert(Catalog.PROFILES.mixed,{id,1}) end
for _,id in {"47_BicycleRepair","49_Clinic","52_Bathhouse"} do table.insert(Catalog.PROFILES.service,{id,1}) end
table.insert(Catalog.PROFILES.mixed,{"51_SobaShop",2})
table.insert(Catalog.PROFILES.residential,{"53_TimberHouse",2})
function Catalog.Get(id)
	for _, spec in Catalog.TYPES do if spec.id == id then return spec end end
	error("Unknown ground facade: "..tostring(id))
end
function Catalog.Seed(key)
	local h = 5381
	for i=1,#key do h=(h*33+string.byte(key,i))%2147483647 end
	return h
end
-- Fictional identities, independent of the physical template choice.
Catalog.NAMES = {
	{"青葉","AOBA"},{"なぎ","NAGI"},{"こま","KOMA"},{"森","MORI"},{"月","TSUKI"},
	{"桜","SAKURA"},{"あさひ","ASAHI"},{"ひかり","HIKARI"},{"空","SORA"},{"楓","KAEDE"},
	{"こはる","KOHARU"},{"つむぎ","TSUMUGI"},{"みなと","MINATO"},{"凪音","NAGINE"},{"余白","YOHAKU"},
}
function Catalog.Brand(id,key,nameSeed)
	local s=Catalog.Get(id)
	if s.signless or s.family=="parking" or s.feature=="sparse" or s.feature=="servicePair" or s.feature=="townhouse" then return "" end
	if s.feature=="loading" then return "搬入口 / DELIVERY" end
	if s.feature=="shutter" then return "貸店舗 / TO LET" end
	return Names.Generate(s.family,key,{feature=s.feature,nameSeed=nameSeed}).brand
end
function Catalog.Pick(profile, key, width, height)
	local rows=assert(Catalog.PROFILES[profile], "Unknown facade profile")
	local eligible,total={},0
	for _,row in rows do
		local s=Catalog.Get(row[1])
		if width>=s.minWidth and width<=s.maxWidth and (not height or (height>=(s.minHeight or 10.5) and height<=(s.maxHeight or 24))) then total+=row[2]; table.insert(eligible,row) end
	end
	if total==0 then return nil end
	local roll=Random.new(Catalog.Seed(key)):NextNumber()*total
	for _,row in eligible do roll-=row[2]; if roll<=0 then return Catalog.Get(row[1]) end end
	return Catalog.Get(eligible[#eligible][1])
end
return Catalog
