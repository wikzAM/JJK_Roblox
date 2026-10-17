--!nonstrict
-- Pure art direction. No new geometry, Instances, global RNG, or damage hooks.
local Catalog=require(script.Parent.GroundFacadeCatalog)
local Names=require(script.Parent.GroundFacadeNames)
local P={VERSION=9}
local C=Color3.fromRGB
P.SIGN_COLORS={C(104,38,33),C(32,71,62),C(31,53,81),C(78,55,43),C(44,48,49),C(103,70,38),C(84,54,81),C(40,79,88),C(102,75,49),C(52,69,46),C(130,50,37),C(69,68,104)}
P.WOODS={C(91,63,43),C(117,82,53),C(143,111,77),C(74,55,44),C(163,137,101),C(85,77,64)}
P.GLASS={C(105,132,137),C(116,138,145),C(123,140,133),C(105,122,139),C(134,143,140)}
P.FONTS={Enum.Font.SourceSansSemibold,Enum.Font.SourceSans,Enum.Font.SourceSansBold,
	Enum.Font.RobotoCondensed,Enum.Font.GothamMedium,Enum.Font.Garamond}
local JP={
	["PAN\nBREAD\nTAKE AWAY"]="焼きたて\nパン\nお持ち帰り",
	["COFFEE\nTEA\nTAKE AWAY"]="珈琲\n紅茶\nお持ち帰り",
	["食券\nRAMEN\n¥ 900"]="食券\nらーめん\n¥ 900",
	["4F  OFFICE\n────────\n3F  STUDIO\n────────\n2F  CAFE\n────────\n1F  ENTRY"]="4階  事務所\n────────\n3階  スタジオ\n────────\n2階  喫茶\n────────\n1階  入口",
	["OFFICE\nRECEPTION"]="事務所\n受付",["HOTEL\n入口"]="ホテル\n入口",
	["営業中\nOPEN"]="営業中\nいらっしゃいませ",["COFFEE"]="珈琲",["TEA"]="紅茶",
	["BAKERY"]="パン工房",["PARKING"]="駐車場",["IN"]="入口",["OUT"]="出口",
	["PAN"]="パン",["24H"]="24時間営業",
	["NO PARKING"]="駐車禁止",["DELIVERY"]="搬入口",["ENTRANCE"]="入口",
	["RESIDENCE  /  PRIVATE ENTRY"]="居住者専用入口",["RETAIL SPACE"]="貸店舗",
	["LOBBY  /  RECEPTION"]="ロビー・受付",["OFFICE ENTRANCE"]="事務所入口",
	["ENTRANCE  /  RECEPTION"]="入口・受付",["STAY  /  LOUNGE"]="宿泊・ラウンジ",
	["24H  /  DAILY GOODS"]="24時間営業・日用品",["COFFEE  &  TEA"]="珈琲と紅茶",
	["らーめん  /  RAMEN"]="らーめん",["小皿とお酒  /  IZAKAYA"]="小皿とお酒",
	["BAKERY  /  FRESH DAILY"]="毎日焼きたて",["CLOTHING  &  OBJECTS"]="洋服と雑貨",
	["DESIGN  /  STUDIO"]="デザイン・スタジオ",["薬  /  PHARMACY"]="薬・処方箋受付",
	["2F CAFE  /  3F STUDIO  /  4F OFFICE"]="2階 喫茶・3階 スタジオ・4階 事務所",
}
local function pick(rows,key) return rows[Names.Seed(key)%#rows+1] end
local function same(a,b)
	return a and b and math.abs(a.R-b.R)+math.abs(a.G-b.G)+math.abs(a.B-b.B)<.004
end
local function japanese(value)
	if JP[value] then return JP[value] end
	-- Strip a bilingual suffix only when the retained portion has Japanese
	-- glyphs. Named chains and unsupported English-only wording stay readable.
	local first=value:match("^(.-)%s*/%s*")
	if first and first:find("[\128-\255]") then return first end
	return value
end
function P.Apply(layout,spec,options)
	options=options or {}
	local nameKey=tostring(options.nameSeed~=nil and options.nameSeed or options.key or layout.seed or spec.id)
	-- A building may deliberately share a proper-name stem; its individual bays
	-- still get their own display palette and font through the stable bay key.
	local key=nameKey.."/"..tostring(options.key or spec.id)
	local language=Names.Language(nameKey,options)
	local pal=assert(Catalog.PALETTES[options.palette or spec.palette],"Unknown presentation palette")
	local sign=options.accent or pick(P.SIGN_COLORS,key.."/sign-color-v9")
	local wood=pick(P.WOODS,key.."/wood-v9")
	local glass=pick(P.GLASS,key.."/glass-v9")
	local font=pick(P.FONTS,key.."/font-v9")
	local f=spec.feature
	-- These are intentionally recognizable fictional chains; vary their joinery
	-- and walls while keeping the identifying brand colors and Latin name.
	if f=="fastFood" then sign=C(182,43,41)
	elseif f=="kingBurger" then sign=C(142,51,32)
	elseif f=="coffeeChain" then sign=C(28,99,77) end
	local warm=C(239,234,220)
	local trim=pal.trim:Lerp(pick({C(26,30,33),C(71,65,56),C(47,60,60),C(81,73,63)},key.."/trim-v9"),.35)
	for _,row in layout.parts do
		-- Wall tone stays coherent with the building's selected palette. Avoid
		-- recoloring privacy films, glass backing, foliage, lighting or product props.
		if same(row.color,pal.trim) and row.kind~="preview" then row.color=trim end
		if same(row.color,C(111,80,51)) or same(row.color,C(127,94,63)) then row.color=wood end
		if row.material==Enum.Material.Glass then row.color=glass end
		if row.name=="Canopy" or row.name=="ProjectingCanopy" or row.name=="FabricAwning" then row.color=sign end
		if row.text then
			row.font=font
			if language=="japanese" then row.text=japanese(row.text) end
			if row.name=="FasciaSign" or row.name=="IdentityPanel" or row.name=="BladeSign" then
				row.color=sign;row.ink=warm
			end
			-- Small notices use a plain font so dense Japanese labels stay legible;
			-- prominent fascia/blade lettering uses the tenant's display family.
			if row.ad or row.name=="AddressPlate" or row.name=="AddressPlaque" then row.font=Enum.Font.SourceSansSemibold end
		end
	end
	layout.language=language;layout.displayFont=font.Name;layout.presentationSeed=key
	return layout
end
return P
