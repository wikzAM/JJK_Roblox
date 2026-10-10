--!nonstrict
-- Fictional sign identities only. No Instances, geometry, global RNG or networking.
local Names = {}
Names.VERSION = 1

Names.Stems = {
	{id="aoba",japanese="青葉",romanized="AOBA"}, {id="nagi",japanese="なぎ",romanized="NAGI"},
	{id="koma",japanese="こま",romanized="KOMA"}, {id="mori",japanese="森",romanized="MORI"},
	{id="tsuki",japanese="月",romanized="TSUKI"}, {id="sakura",japanese="桜",romanized="SAKURA"},
	{id="asahi",japanese="あさひ",romanized="ASAHI"}, {id="hikari",japanese="ひかり",romanized="HIKARI"},
	{id="sora",japanese="空",romanized="SORA"}, {id="kaede",japanese="楓",romanized="KAEDE"},
	{id="koharu",japanese="こはる",romanized="KOHARU"}, {id="tsumugi",japanese="つむぎ",romanized="TSUMUGI"},
	{id="minato",japanese="みなと",romanized="MINATO"}, {id="yohaku",japanese="余白",romanized="YOHAKU"},
	{id="hinata",japanese="ひなた",romanized="HINATA"}, {id="komorebi",japanese="こもれび",romanized="KOMOREBI"},
	{id="nagisa",japanese="なぎさ",romanized="NAGISA"}, {id="akane",japanese="あかね",romanized="AKANE"},
	{id="sumire",japanese="すみれ",romanized="SUMIRE"}, {id="suzuran",japanese="すずらん",romanized="SUZURAN"},
	{id="wakaba",japanese="若葉",romanized="WAKABA"}, {id="futaba",japanese="ふたば",romanized="FUTABA"},
	{id="shiori",japanese="しおり",romanized="SHIORI"}, {id="kotori",japanese="ことり",romanized="KOTORI"},
	{id="kohaku",japanese="琥珀",romanized="KOHAKU"}, {id="yuzu",japanese="ゆず",romanized="YUZU"},
	{id="azuki",japanese="あずき",romanized="AZUKI"}, {id="sazanami",japanese="さざなみ",romanized="SAZANAMI"},
	{id="tsubaki",japanese="椿",romanized="TSUBAKI"}, {id="natsume",japanese="なつめ",romanized="NATSUME"},
	{id="hibari",japanese="ひばり",romanized="HIBARI"}, {id="harukaze",japanese="春風",romanized="HARUKAZE"},
}

local F={"food"}
local R={"retail"}
local FR={"food","retail"}
local S={"service"}
local SR={"service","retail"}
local O={"office","entry"}
local A={"residential"}
local H={"hotel"}
local P={"parking"}
local function label(id,japanese,romanized,english,categories,format,tag)
	return {id=id,japanese=japanese,romanized=romanized,english=english,
		categories=categories,format=format or "suffix",tag=tag or id}
end
-- Curated nouns + one proper-name stem. Prefix/suffix is specified per noun;
-- arbitrary concatenated Japanese words are never generated.
Names.Labelings = {
	label("ramen","麺処","MENDOKORO","RAMEN",F,"prefix","ramen"),
	label("ramenShop","ラーメン","RAMEN","RAMEN",F,"prefix","ramen"),
	label("soba","そば処","SOBADOKORO","SOBA",F,"prefix","soba"),
	label("udon","うどん屋","UDONYA","UDON",F,"prefix","soba"),
	label("diner","食堂","SHOKUDO","DINER",F),
	label("setMeals","定食屋","TEISHOKUYA","SET MEALS",F,"prefix"),
	label("izakaya","酒場","SAKABA","IZAKAYA",F,"prefix","izakaya"),
	label("smallPlates","小料理","KORYORI","SMALL PLATES",F,"prefix","izakaya"),
	label("yakitori","焼鳥","YAKITORI","YAKITORI",F,"prefix","izakaya"),
	label("sushi","寿司","SUSHI","SUSHI",F,"suffix"),
	label("curry","カレー屋","KAREYA","CURRY",F,"prefix"),
	label("gyoza","餃子屋","GYOZAYA","GYOZA",F,"prefix"),
	label("bento","弁当","BENTO","BENTO",F,"suffix","takeaway"),
	label("deli","惣菜店","SOZAI TEN","DELI",FR,"suffix","takeaway"),
	label("onigiri","おにぎり屋","ONIGIRIYA","ONIGIRI",F,"prefix","takeaway"),
	label("takoyaki","たこ焼き","TAKOYAKI","TAKOYAKI",F,"prefix","takeaway"),
	label("okonomiyaki","お好み焼き","OKONOMIYAKI","OKONOMIYAKI",F,"prefix"),
	label("tempura","天ぷら","TEMPURA","TEMPURA",F,"prefix"),
	label("burger","バーガー","BURGER","BURGERS",F,"suffix","burger"),
	label("kitchen","キッチン","KITCHEN","KITCHEN",F,"prefix","burger"),
	label("kissaten","喫茶","KISSA","COFFEE & TEA",FR,"prefix","coffee"),
	label("coffee","珈琲店","KOHITEN","COFFEE",FR,"suffix","coffee"),
	label("cafe","カフェ","CAFE","CAFE",FR,"prefix","coffee"),
	label("wagashi","和菓子店","WAGASHITEN","JAPANESE SWEETS",FR,"suffix","sweets"),
	label("store","商店","SHOTEN","LOCAL SHOP",R,"suffix","localShop"),
	label("foodStore","食品店","SHOKUHINTEN","GROCERIES",R,"suffix","grocery"),
	label("grocery","食料品店","SHOKURYOHINTEN","FOOD & DAILY GOODS",R,"suffix","grocery"),
	label("greengrocer","青果店","SEIKATEN","FRUIT & VEGETABLES",R,"suffix","produce"),
	label("fruit","果物店","KUDAMONOTEN","FRUIT",R,"suffix","produce"),
	label("fish","鮮魚店","SENGYOTEN","FISH",R,"suffix","grocery"),
	label("butcher","精肉店","SEINIKUTEN","BUTCHER",R,"suffix","grocery"),
	label("rice","米店","KOMETEN","RICE",R,"suffix","grocery"),
	label("tea","茶舗","CHAHO","TEA",R,"suffix","localShop"),
	label("liquor","酒店","SAKETEN","SAKE & DRINKS",R,"suffix","grocery"),
	label("bakery","ベーカリー","BAKERY","BAKERY",FR,"suffix","bakery"),
	label("bread","パン工房","PAN KOBO","BREAD",FR,"prefix","bakery"),
	label("confectionery","菓子店","KASHITEN","SWEETS",FR,"suffix","sweets"),
	label("florist","花店","HANATEN","FLOWERS",R,"suffix","florist"),
	label("flowerStudio","花工房","HANA KOBO","FLOWER STUDIO",R,"prefix","florist"),
	label("bookshop","書店","SHOTEN","BOOKS",R,"suffix","bookshop"),
	label("usedBooks","古書店","KOSHOTEN","USED BOOKS",R,"suffix","bookshop"),
	label("stationery","文具店","BUNGUTEN","STATIONERY",R,"suffix","localShop"),
	label("housewares","雑貨店","ZAKKATEN","DAILY OBJECTS",R,"suffix","boutique"),
	label("clothing","洋服店","YOFUKUTEN","CLOTHING",R,"suffix","boutique"),
	label("shoes","靴店","KUTSUTEN","SHOES",R,"suffix","boutique"),
	label("eyewear","眼鏡店","MEGANETEN","EYEWEAR",R,"suffix","boutique"),
	label("convenience","ストア","STORE","DAILY GOODS",R,"suffix","konbini"),
	label("miniMarket","ミニマート","MINI MART","MINI MARKET",R,"suffix","konbini"),
	label("pharmacy","薬局","YAKKYOKU","PHARMACY",SR,"suffix","pharmacy"),
	label("hairSalon","美容室","BIYOSHITSU","HAIR SALON",SR,"suffix","salon"),
	label("barber","理容室","RIYOSHITSU","BARBER",SR,"suffix","salon"),
	label("laundry","コインランドリー","COIN LAUNDRY","LAUNDRY",S,"prefix","laundry"),
	label("cleaners","クリーニング","CLEANING","CLEANERS",S,"prefix","laundry"),
	label("tailor","洋服直し","YOFUKU NAOSHI","ALTERATIONS",S,"prefix","repair"),
	label("shoeRepair","靴修理","KUTSU SHURI","SHOE REPAIR",S,"prefix","repair"),
	label("watchRepair","時計修理","TOKEI SHURI","WATCH REPAIR",S,"prefix","repair"),
	label("electric","電器店","DENKITEN","ELECTRICAL GOODS",SR,"suffix","electronics"),
	label("repairShop","修理工房","SHURI KOBO","REPAIR WORKSHOP",S,"prefix","electronics"),
	label("bicycles","自転車店","JITENSHATEN","BICYCLES",SR,"suffix","bicycle"),
	label("cycleShop","サイクルショップ","CYCLE SHOP","CYCLE SHOP",SR,"prefix","bicycle"),
	label("photos","写真館","SHASHINKAN","PHOTO STUDIO",S,"suffix"),
	label("printShop","印刷工房","INSATSU KOBO","PRINTING",S,"prefix"),
	label("clinic","クリニック","CLINIC","CLINIC",S,"suffix","clinic"),
	label("dentist","歯科","SHIKA","DENTAL CLINIC",S,"suffix","clinic"),
	label("realEstate","不動産","FUDOSAN","REAL ESTATE",S,"suffix"),
	label("parcel","宅配受付","TAKUHAI UKETSUKE","PARCEL COUNTER",S,"prefix"),
	label("bathhouse","湯","YU","BATHHOUSE",S,"suffix","bathhouse"),
	label("designOffice","デザイン事務所","DESIGN JIMUSHO","DESIGN OFFICE",O,"suffix","showroom"),
	label("studio","スタジオ","STUDIO","STUDIO",O,"suffix","showroom"),
	label("office","オフィス","OFFICE","OFFICE",O,"suffix"),
	label("building","ビル","BUILDING","BUILDING",O,"suffix"),
	label("residence","レジデンス","RESIDENCE","RESIDENCE",A,"suffix"),
	label("heights","ハイツ","HEIGHTS","APARTMENTS",A,"suffix"),
	label("house","ハウス","HOUSE","PRIVATE ENTRY",A,"suffix"),
	label("court","コート","COURT","RESIDENCE",A,"suffix"),
	label("hotel","ホテル","HOTEL","HOTEL",H,"prefix"),
	label("inn","旅館","RYOKAN","INN",H,"suffix"),
	label("parking","駐車場","CHUSHAJO","PARKING",P,"suffix"),
	label("monthlyParking","月極駐車場","TSUKIGIME CHUSHAJO","MONTHLY PARKING",P,"suffix"),
}

Names.FeatureTags = {
	noren="ramen", lattice="izakaya", awning="coffee", bakery="bakery",
	pharmacy="pharmacy", burger="burger", grille="burger", posterShop="konbini",
	stripe="konbini", localShop="localShop", produce="produce", hatch="takeaway",
	salon="salon", electronics="electronics", display="boutique", showroom="showroom",
	laundry="laundry", bicycle="bicycle", florist="florist", clinic="clinic",
	bookshop="bookshop", soba="soba", bathhouse="bathhouse", timberHouse="house",
}
Names.FixedChains = {
	fastFood={id="mcdoodoos",brand="McDooDoo's",japanese="",romanized="McDooDoo's",label="BURGERS"},
	kingBurger={id="smashKing",brand="SMASH KING",japanese="",romanized="SMASH KING",label="BURGERS"},
	coffeeChain={id="starboys",brand="STARBOYS",japanese="",romanized="STARBOYS",label="COFFEE"},
}

function Names.Seed(key)
	local h=5381
	key=tostring(key)
	for i=1,#key do h=(h*33+string.byte(key,i))%2147483647 end
	return h
end
local function compatible(row,category)
	for _,c in row.categories do if c==category then return true end end
	return false
end
local function find(rows,id)
	for _,r in rows do if r.id==id then return r end end
	return nil
end

function Names.Generate(category,keyOrSeed,options)
	options=options or {}
	category=category or "retail"
	local nameKey=tostring(options.nameSeed~=nil and options.nameSeed or keyOrSeed or "default")
	local feature=options.feature
	local fixed=Names.FixedChains[feature]
	if category=="chains" and not fixed then
		local keys={"fastFood","kingBurger","coffeeChain"}
		fixed=Names.FixedChains[keys[Random.new(Names.Seed(nameKey.."/chain")):NextInteger(1,#keys)]]
	end
	if fixed then
		return {brand=options.brandOverride or fixed.brand,japanese=fixed.japanese,romanized=fixed.romanized,
			label=fixed.label,subtitle=fixed.label,category="chains",labelId=fixed.id,stemId="fixed",
			identityKey="ground-name-v1/chains/"..fixed.id,nameSeed=nameKey}
	end
	local tag=options.tag or Names.FeatureTags[feature]
	local eligible={}
	for _,r in Names.Labelings do
		-- A specific feature takes precedence over a broad legacy family (salons
		-- and coffee are historically retail). It never mixes incompatible tags.
		if (tag and r.tag==tag) or (not tag and compatible(r,category)) then table.insert(eligible,r) end
	end
	assert(#eligible>0,"No facade name labelings for category/tag: "..category.."/"..tostring(tag))
	local chosen
	if options.labelId then chosen=find(eligible,options.labelId)
	else chosen=eligible[Random.new(Names.Seed(nameKey.."/label")):NextInteger(1,#eligible)] end
	assert(chosen,"Incompatible facade name labelId: "..tostring(options.labelId))
	local stem
	if options.stemId then stem=find(Names.Stems,options.stemId)
	else stem=Names.Stems[Random.new(Names.Seed(nameKey.."/stem")):NextInteger(1,#Names.Stems)] end
	assert(stem,"Unknown facade name stemId: "..tostring(options.stemId))
	local jp=chosen.format=="prefix" and (chosen.japanese.." "..stem.japanese) or (stem.japanese..chosen.japanese)
	local rom=stem.romanized.." "..chosen.english
	return {brand=options.brandOverride or (jp.." / "..rom),japanese=jp,romanized=rom,
		label=chosen.japanese,subtitle=chosen.english,category=category,labelId=chosen.id,stemId=stem.id,
		identityKey="ground-name-v1/"..chosen.id.."/"..stem.id,nameSeed=nameKey}
end

return Names
