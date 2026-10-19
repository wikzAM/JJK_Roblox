# R2: Tokyo facade art direction for Shibuya

Status: research only (2026-10-19). No code or Studio changes. This revises `tools/UPPER_FACADE_STYLE_DECK.md` against the budget in `GAME_DESIGN_DECISIONS.md`: about 10–25 parts per near building, with facade detail carried by textures.

## Executive summary

- **Why the current deck misses the Tokyo vibe:**
  - Its families are generic international types (stucco, brick, louver).
  - It lacks the Tokyo cues: mosaic tile, aluminium sash, signboard columns, blank party walls, external stairs, AC units, rooftop sign frames, slant-line setbacks, and side-street power lines.
  - It has no night design, yet the Shibuya Incident happens at night (Halloween 2018).
  - It is built from parts, at 1,500–2,500 per building.
- **What Tokyo actually looks like:** muted walls carrying a saturated, dense sign layer. Variety comes from tenants and signs, not wall colour. Uniqueness lives at the first two floors; upper floors repeat.
- **Proposed kit:** 12 facade families plus a 2018 construction overlay. Each is a small set of tileable 1024 px textures on Roblox `Texture` objects, tinted per building through `Color3`. Real Parts are limited to slabs, piers, sign columns and rooftop clutter.
- **Districts get their own character** through family weights, sign density, light colour and street clutter, so Center Gai, Maruyamacho, Miyamasuzaka and the station core each read differently.
- **Hero landmarks** (109, Q-Front, Hikarie, Scramble Square, Mark City, the station) are bespoke, not kit. Their names and logos should be parodied, as Yakuza does.

## 1. Shibuya block by block

| Area | What it looks like (reference cues) | Reference images |
|---|---|---|
| **Scramble / Hachiko / station front** | Four corners of screens: Q-Front's full-height LED screen over Tsutaya and Starbucks ([gotokyo](https://www.gotokyo.org/en/spot/366/index.html)), billboard-wrapped mid-rises, and the old Tokyu department-store block. In 2018 Scramble Square was a construction site; it opened 1 Nov 2019 ([japan-guide](https://www.japan-guide.com/e/e3007.html)). | [Shibuya Crossing](https://commons.wikimedia.org/wiki/Category:Shibuya_Crossing), [QFRONT](https://commons.wikimedia.org/wiki/Category:QFRONT), [Shibuya Station](https://commons.wikimedia.org/wiki/Category:Shibuya_Station) |
| **Shibuya 109** | A silver cylindrical tower at the fork of Dogenzaka and Bunkamura-dori, by Minoru Takeyama, 1979. "109" is a trademark that media usually alter ([Wikipedia](https://en.wikipedia.org/wiki/Shibuya_109)). | [Shibuya 109](https://commons.wikimedia.org/wiki/Category:Shibuya_109) |
| **Dogenzaka** | A wide slope. Older hotels and nightlife buildings sit beside new offices ([Lonely Planet](https://www.lonelyplanet.com/japan/tokyo/attractions/dogenzaka/a/poi-sig/396615/356817)). Narrow side lanes (Dogenzaka-koji) appear in the manga ([mapple](https://www.mapple.net/original/235810/)). | [Dōgenzaka](https://commons.wikimedia.org/wiki/Category:D%C5%8Dgenzaka), [Pakutaso photo](https://www.pakutaso.com/en/20240501130post-51201.html) |
| **Maruyamacho (Love Hotel Hill)** | Hundreds of love hotels: some with fantastical, worn facades, others plain white business-hotel fronts with rate boards and separate entry and exit doors ([Tokyo Weekender](https://www.tokyoweekender.com/japan-life/dogenzaka-love-hotel-hill/), [Lonely Planet](https://www.lonelyplanet.com/japan/tokyo/attractions/dogenzaka/a/poi-sig/396615/356817)). Live houses and clubs are mixed in. | [Maruyama-chō](https://commons.wikimedia.org/wiki/Category:Maruyama-ch%C5%8D,_Shibuya,_Tokyo), [Love hotels](https://commons.wikimedia.org/wiki/Category:Love_hotels_in_Japan) |
| **Center Gai** | A narrow pedestrian street of chain food, game centres, karaoke and drugstores. Buildings bristle with signboards ([Wikipedia](https://en.wikipedia.org/wiki/Center_Gai), [Architizer](https://architizer.com/projects/hulic-new-shibuya)). | [Shibuya Center-Gai](https://commons.wikimedia.org/wiki/Category:Shibuya_Center-Gai) |
| **Udagawacho / Spain-zaka** | Chunky brown Showa walk-ups with small windows (cited in the old deck: Craig Mod). Spain-zaka is a short stepped lane of boutiques and cafes with stonework, entered unmarked off Inokashira-dori ([Japan Travel](https://en.japantravel.com/tokyo/supeinzaka-spanish-hill/5488)). PARCO was closed for rebuilding 2016–19. | [Udagawa-chō](https://commons.wikimedia.org/wiki/Category:Udagawa-ch%C5%8D), [Spain-zaka](https://commons.wikimedia.org/wiki/Category:Spain-zaka_%28Shibuya%29) |
| **Mark City** | A long low-rise retail spine linking Dogenzaka to the station, with a hotel tower, glass walkways and high ceilings. It is a manga and anime location ([Tabimania](https://tabimaniajapan.com/culture/jujutsu-kaisen-real-life-guide-how-to-visit-shibuya-incident)). | [Shibuya Mark City](https://commons.wikimedia.org/wiki/Category:Shibuya_Mark_City) |
| **Hikarie / Miyamasuzaka** | Hikarie's exterior reads as a "stack of blocks" (Nikken Sekkei, via [PR Newswire](https://www.prnewswire.co.uk/news-releases/tokyo-famous-shibuya-hikarie-complex-shortlisted-as-finalist-at-2013-mipim-awards-197933721.html)). The slope east toward Aoyama is mid-rise office slabs: ribbon windows, tile and panel. | [Shibuya Hikarie](https://commons.wikimedia.org/wiki/Category:Shibuya_Hikarie) |
| **Scramble Square** | Low-E panes over 4 m tall, mullions that shift at the corners, exterior ceramic frit, and spiralling louvres ([archify](https://www.archify.com/au/project/shibuya-scramble-square), [designboom](https://www.designboom.com/architecture/shibuya-scramble-square-nikken-sekkei-station-tokyo-japan-05-04-2021/), [KKAA](https://kkaa.co.jp/en/project/shibuya-scramble-square)). For a 2018 setting, show it as a crane-topped frame. | [Scramble Square](https://commons.wikimedia.org/wiki/Category:Shibuya_Scramble_Square) |
| **Meiji-dori** | A wide arterial. North, toward Jingumae, it is fashion boxes and louvred retail. Miyashita Park was being rebuilt in 2018 and reopened in 2020 ([Time Out](https://www.timeout.com/tokyo/news/miyashita-park-in-shibuya-to-reopen-as-a-rooftop-park-in-june-2020)). South is Shibuya Stream (2018) and office and residential blocks. | [Shibuya Stream](https://commons.wikimedia.org/wiki/Category:Shibuya_Stream) |
| **Yokocho** | Nonbei Yokocho is a tiny lane of six-seat bars beside the tracks ([Unseen Japan](https://unseen-japan.com/emergent-tokyo-what-makes-japans-capital-so-alluring/)). Almazán's *Emergent Tokyo* treats yokocho, zakkyo buildings and under-track infill as Tokyo's defining "emergent" forms ([Keio](https://almazan.sd.keio.ac.jp/?p=2096)). | [Night in Shibuya](https://commons.wikimedia.org/wiki/Category:Night_in_Shibuya,_Tokyo) |

**Street-level clutter (real Parts, near only):**
- **Power lines.** Only about 3% of ward-managed roads are undergrounded, against about 55% of metropolitan roads ([Toyo Keizai](https://toyokeizai.net/articles/-/186932), [Tokyo Metro Gov](https://www.2020games.metro.tokyo.lg.jp/02%20Promotion%20of%20the%20removal%20of%20utility%20poles.pdf)). Rule: no poles on Meiji-dori, Dogenzaka or Aoyama-dori; poles and sagging bundles on every side street ([Unseen Japan](https://unseen-japan.com/whats-with-the-chaos-of-japanese-power-lines/), [Commons](https://commons.wikimedia.org/wiki/Category:Utility_poles_in_Tokyo)).
- **Vending machines** in pairs at building corners and car-park edges ([Commons](https://commons.wikimedia.org/wiki/Category:Vending_machines_in_Japan)).
- **AC units** on balconies, side-wall brackets, rooftops and stair landings; **external steel stairs** on zakkyo and Showa flanks.
- **Convenience stores:** full glass at the first floor, with a 3-stud fascia carrying 2–3 brand stripes. Use a parody brand: Yakuza swapped FamilyMart for its fictional "Poppo" ([Engadget](https://www.engadget.com/2018-03-15-yakuza-6-kabukicho-real-life-comparison.html)).

## 2. The anime's Shibuya Incident look (MAPPA)

**Sourced:**
- Season 2 was directed by Shota Goshozono, with art direction by Junichi Higashi ([Wikipedia](https://en.wikipedia.org/wiki/Jujutsu_Kaisen_season_2)).
- A director and producer interview appears in the official guidebook. The producer stressed whole-screen visuals ([Oricon](https://www.oricon.co.jp/news/2346500/full/)).
- I found no online interview with the art or colour staff on Shibuya's backgrounds. The art book or guidebook is the primary source to buy.
- Fan and travel guides report:
  - The background art reproduces real light reflections and the placement of advertising ([japan-food.guide](https://japan-food.guide/en/articles/Anime-Pilgrimage-to-the-sacred-sites-in-Shibuya-of-Jujutsu-Kaisen-Shibuya-Incident-and-recommended-restaurants-and-eateries)).
  - The battle map follows real Shibuya geography, and scenes use the layering of ground level and deep platforms ([Tabimania](https://tabimaniajapan.com/culture/jujutsu-kaisen-real-life-guide-how-to-visit-shibuya-incident), [mapple](https://www.mapple.net/original/235810/)).
- Named locations: 109 on Dogenzaka, Dogenzaka-koji, Mark City, the Fukutoshin Line B5F platforms, Shibuya Stream and the New South Exit, Meiji-jingumae Exit 2, and Shibuya C Tower ([mapple](https://www.mapple.net/original/235810/)).
- The black outer "Curtain" veil seals the district ([Tabimania](https://tabimaniajapan.com/culture/jujutsu-kaisen-real-life-guide-how-to-visit-shibuya-incident)).
- The Sukuna vs Mahoraga episode is widely singled out for its city-scale destruction ([Sportskeeda](https://sportskeeda.com/anime/jujutsu-kaisen-season-2-episode-17-sukuna-defeats-mahoraga-causing-shibuya-incident)).

**Observed (my reading of the broadcast; the owner should confirm with a frame-grab board):**
- **Grading:** cool blue-teal ambient shadows. Practical lights come in two kinds: warm sodium and orange, and cold white fluorescent.
- **Signs:** flat glowing colour with bloom. Facades go nearly black between signs, and the veil makes the sky near-black.
- **Destruction:** pale grey concrete dust columns, chunky slab fragments, black scorch, and orange fire light (Jogo, Fuga). After Sukuna's domain, a flattened rubble field.
- **Takeaway:** at night the anime reads Shibuya through its lights, not its walls. A dark sky is accurate and hides far detail cheaply, so the lit-window and sign layer is the most important texture channel.

## 3. Typology: what drives variety

| Type | Window rhythm | Materials | Colour | Signage |
|---|---|---|---|---|
| **Zakkyo-biru** (mixed tenants) | One bay per floor, repeated: a sliding pair or ribbon | Mosaic or 45×95 tile; aluminium sash | Beige, brown, grey tile | A tenant column per building, a sign box per floor, lettering on the glass |
| **Pencil building** | 1–2 bays on a 3.8–6 m frontage | Tile mosaic, exposed concrete | Any; often a single strong tile colour | One column sign; floors double as signs |
| **Mansion** (apartments) | Continuous balconies on the front, a corridor on the back | Fully tiled in the 1980s and 90s ([TCI-ThaiJo](https://so02.tci-thaijo.org/index.php/jars/article/view/277371)) | Cream, grey, brick-red | Only a name plate at the entrance |
| **Office, 1970s–90s** | Ribbon windows or punched grid on a 3.2–3.6 m bay | ALC panels, precast, aluminium panel | Grey, champagne | A rooftop name sign |
| **Office tower** | Unitised curtain wall | Low-E glass, frit, fins | Blue-grey glass | A logo at the crown |
| **Department store** | Few or no windows | Aluminium or terracotta panel, giant billboards | Silver, white | Huge brand panels, screens |
| **Pachinko / game centre** | Windowless, with LED bands | Panel, light boxes | White, red, gold | Chaser lights, giant name board ([Commons billboards](https://commons.wikimedia.org/wiki/Category:Pachinko_billboards_in_Japan)) |
| **Love hotel** | Tiny shuttered or blank windows | Tile, faux stone, stucco trims | Pastel, mauve, charcoal | Small neon name, rate board |
| **Showa walk-up** | Small steel-sash pairs | Brown tile, mortar | Brown, ochre, rust | Hand-painted, faded |
| **Kanban-kenchiku** | A flat false front | Mortar, copper, tile | Patina green, grey | Lettering on the front |

Also Tokyo-specific: **slant-line setbacks** (stepped street-facing tops, cheap roofline variety) and **blank party walls** rising above low neighbours.

## 4. Procedural generation and game practice

- **Wonka et al., *Instant Architecture* (SIGGRAPH 2003):** split grammars subdivide a facade; a control grammar and attribute matching keep each building consistent ([TU Wien](https://www.cg.tuwien.ac.at/research/publications/2003/Wonka-2003-Ins/)). Our equivalent: one style roll per building, stored as attributes.
- **Müller et al., *Procedural Modeling of Buildings* (SIGGRAPH 2006, CGA shape):** mass model, then facade structure, then windows; context-sensitive rules stop collisions ([PDF](https://course.ccs.neu.edu/cs5150f13/readings/muller_buildings.pdf), [SIGGRAPH](https://history.siggraph.org/?p=113547)).
- **CityEngine split syntax:** `~` sizes float to fill the space, and `{...}*` repeats a tile as many times as fits with minimal stretch ([Esri docs](https://doc.arcgis.com/en/cityengine/latest/cga/cga-split.htm)).
  - Our facade becomes `split(y){ground | ~floor* | crown}` and `floor → split(x){pier | ~bay* | pier}`.
  - In Roblox, do the split in texture space: set `StudsPerTileU = runWidth / round(runWidth / module)` so whole bays fit each run.
- **Marvel's Spider-Man (Insomniac):** Manhattan came from procedural systems designed to accept manual polish, under a disc-size asset budget ([GDC Vault](https://gdcvault.com/play/1026496), [GDC 2019](https://www.gdcvault.com/play/1025765)).
- **Cyberpunk 2077:** mostly hand-built. District identity came from colour coding, four era styles and a "rule of contrast"; later guidelines grouped detail into readable clusters with negative space; heavy decal use ([80.lv](https://80.lv/articles/interview-how-cyberpunk-2077-s-night-city-was-built-almost-entirely-by-hand/), [RPG Site](https://rpgsite.net/interview/8896-cyberpunk-2077-interview-exploring-the-environment-with-senior-concept-artist-marthe-jonkers)).
- **Yakuza / Judgment (Kamurocho):**
  - A few blocks of Kabukicho, compressed. Street signage, clutter and landmark scale are copied closely, with some buildings enlarged and parody brands substituted ([Engadget](https://www.engadget.com/2018-03-15-yakuza-6-kabukicho-real-life-comparison.html)).
  - Academic analysis names RGG's core method as "cyclical reuse and recombination of urban assets" ([CityU](https://scholars.cityu.edu.hk/en/publications/urban-redevelopment-for-video-games-effective-ludoforming-and-the/)).
  - Doors and bricks repeat, but every shopfront's sign is distinct ([Aftermath](https://aftermath.site/yakuzas-shopfronts-are-one-of-lifes-little-pleasures/)).
  - The Dragon Engine was tuned for night neon and animated signs, and crowds use instancing ([Automaton](https://automaton-media.com/en/news/like-a-dragon-graphics-switch-to-the-dragon-engine-was-a-big-part-of-the-series-graphical-evolution-devs-say/)).
- **Lesson for us:**
  - Spend the uniqueness budget on the first floors and the sign layer (cheap Parts and textures). Reuse shells and upper floors aggressively.
  - Compress distances but keep landmark scale and placement correct.

## 5. Texture sources

| Source | Licence | Use |
|---|---|---|
| [Poly Haven](https://polyhaven.com/license) | CC0, commercial use allowed, no attribution | Concrete, plaster, corrugated metal, tile and metal base materials |
| [ambientCG](https://docs.ambientcg.com/license/) | CC0 1.0, game use explicitly allowed | Its Tiles, Concrete, Metal and Terrazzo categories for mosaic and panel bases |
| [Textures.com](https://www.textures.com/about/terms-of-use) | Proprietary. Game use allowed ([how it works](https://www.textures.com/about/how-it-works)). Free tier limited, and free credits reportedly ended ([gamedev.tv](https://community.gamedev.tv/t/textures-com-no-longer-offers-free-credits/219803)) | Paid fallback for photo facades. Never ship raw files. |
| Wikimedia Commons | Per-file (often CC BY or BY-SA) | **Reference only.** Signs in photos carry trademarks. |
| [Pakutaso](https://www.pakutaso.com/en/20240501130post-51201.html) | Free Japanese stock with its own terms | Reference only |

Method: paint window, sash and sign layers (fictional katakana and kanji names) over CC0 bases. Roblox caps images at 1024 px, so author one floor × 2–4 bays per image.

## 6. Style kit: 12 families plus an overlay

Units are studs (1 stud ≈ 0.28 m). Storey heights:

| Building type | Storey height |
|---|---|
| Mansion | 10.5 |
| Zakkyo / hotel | 11.5 |
| Office | 12.5 |
| Tower | 15 |
| Department store | 18 |

Each family ships these textures (about 3–5 images per family, about 50 in total):
- a **day** floor tile;
- a **night** floor tile, in 2–3 lit-pattern variants;
- a **side wall** tile;
- one **first-floor** strip;
- one **crown**.

| # | Family | Palette (wall / accent / frame / glass) | Window module | Signage rule |
|---|---|---|---|---|
| F1 | **Zakkyo sign-stack** | Beige tile #C9B9A0, mosaic grey #9A9A94, brown #7A5A44 / sign white #F4F4EE / silver #B8BCC0 / #2E3A3F | Sliding pair 6.4w × 5.4h in a 9-stud bay | Vertical column 2.5w, projecting 3–5, one 3.5-tall panel per tenant floor. A sign box on every floor and lettering on the glass. |
| F2 | **Pencil** | One strong tile: terracotta #A0583C, teal #3E6F6A, white #E6E3DC, or black #2A2A2A | 1–2 bays, 5.5w × 6h, on a 14–22 frontage | One column sign. External stair on the side. |
| F3 | **Showa walk-up** | Brown tile #6E4B35, ochre #A07848, concrete #8E8B84 / rust streak / steel sash #5D6B5E | Small pair 4w × 3.5h on an 8 pitch | Faded hand-painted panels. AC units and a stair. |
| F4 | **Tile mansion** | Cream #D8CFC0, grey #BEBAB2, brick-red #8C4A3A / white parapet #E8E6E0 | Balcony doors 6w × 7h, unit 22 wide. The rear is a corridor with 3×3 frosted windows. | Name plate only. AC units and laundry on balconies. |
| F5 | **ALC / precast office** | Grey #9EA2A3, champagne aluminium #C2B79E / #2B3236 | Ribbon or punched, 11.4 bay, 3.5 sill band | A rooftop name frame on a steel lattice |
| F6 | **Curtain-wall tower** | #3C4A55 glass, #2A2F33 spandrel, #A9B0B5 mullion | Mullion every 5.4, panes 15 tall, frit gradient | Logo at the crown. Cool-white LED lines at night. |
| F7 | **Fashion box / department store** | Silver panel #C8CCD0, white #EDEDED, louvre bronze #8A7A62 | Mostly blank. Louvred variant: fins every 2.2 | Billboard frames 40×25, plus brand panels |
| F8 | **Screen corner** (station core) | Black glass #1C2226 / screen | Full-height glass | 1–2 LED screens per building, with texture offset scrolling (no video) |
| F9 | **Pachinko / game centre** | White #F2F2F2, red #E0262B, gold #E8B828, black | Windowless on floors 1–3; F5 above | Giant name board, chaser-light strips (Neon parts, near only) |
| F10 | **Love hotel** | Mauve #8E6A86, pink #E3A6B6, ivory #E7DECB, charcoal #2F2B2E | Shuttered 3×3 on a 7 pitch, or blank | Small neon name, rate board at the entry, screen wall |
| F11 | **Business hotel / slim office** | White #E4E2DD, grey #B5B3AE, one accent pier colour | Slots 3.2w × 4.3h on a 6 pitch | One vertical name blade, full height |
| F12 | **Yokocho / track-side low-rise** | Corrugated #7B7D7A, dark wood #5A4030, red lantern #C8322A | 2 storeys, with real Parts at street level | Noren, lanterns, and a small sign on every unit |
| O1 | **2018 construction overlay** | Sheeting #DADDE0, mesh green #4E7D55, crane yellow #E2B32B | None | Developer hoarding graphics. Used for Scramble Square, PARCO and Miyashita. |

**Global signage rules:**
- Text runs vertically on columns and horizontally on boxes.
- Each tenant gets one saturated hue (red, yellow, blue, green, magenta, orange) on a white light box.
- At most 4 hues per building, and adjacent columns never share a hue.
- Projecting signs start at about 13 studs (3.5 m) above the pavement. This is a common Tokyo norm; verify it against the Tokyo ordinance booklet ([TMG](https://www.toshiseibi.metro.tokyo.lg.jp/documents/d/toshiseibi/kou-siori2026-frontpage_booklet)).
- Only fictional names and parody brands.

**Variation recipe** (a seeded roll per building, as in the old deck):
1. **District weights** pick the family (see section 7).
2. **Neighbour rule:** buildings that share a lot line, or face each other within 30 studs, must differ in at least two of these: family, wall tone, window module, height band, sign hue. Re-roll the palette first.
3. **Tint jitter:** `Texture.Color3` value ±6%, hue ±3°. Grime overlay transparency 0.6–0.9.
4. **Phase:** a random `OffsetStudsU`, so bay columns never line up with the neighbour's.
5. **Height:** the storey height comes from the family; the floor count comes from the lot. Street-facing tops get 0–2 slant-line setback steps.
6. **Night:** one of 2–3 lit masks per family. Office windows are cool #DDEBFF, homes warm #FFD9A0, zakkyo mixed.
7. **Roof:** 1–3 Parts chosen from water tank, cooling tower, sign frame, lift penthouse and antenna.
8. **Party walls:** any face above a lower neighbour gets the blank side-wall texture, not windows.

**Part budget** (fits the 10–25 per building target):

| Item | Parts |
|---|---|
| Skin Parts, with Textures | 4–6 |
| Slabs and piers (in place when a hit happens) | 4–8 |
| Sign column | 1–3 |
| Roof clutter | 1–3 |
| First-floor detail, near only | 3–6 |

- Lit signs at night: test SurfaceGui ImageLabels with `LightInfluence = 0` against Neon parts, on near buildings only. Measure the cost.
- Check whether `SurfaceAppearance` emissive is available, for the stand-in meshes.

## 7. District assignments

| District | Family weights | Sign density | Street clutter | Light |
|---|---|---|---|---|
| **Station core / Scramble** | F8 40, F7 25, F6 15, O1 20 | Maximum: screens and billboards | No poles. Barriers, taxis. | Screen-white, multicolour |
| **Center Gai** | F9 30, F1 40, F2 20, F7 10 | Very high: a column on every building | Arch gate sign, A-frames | Saturated, warm |
| **Udagawacho N / Spain-zaka** | F3 35, F1 25, F2 25, F12 15 | Medium | Poles, stairs, steps, vending machines | Warm, sparse |
| **Dogenzaka (main slope)** | F1 35, F11 25, F5 20, F7 20 | High, with rooftop frames | No poles | Mixed |
| **Dogenzaka-koji alleys** | F1 40, F3 30, F12 30 | Very high, small signs | Poles, AC units, crates | Warm, orange |
| **Maruyamacho** | F10 50, F11 30, F3 20 | Low, but neon name signs | Poles, screen walls | Dim pink and purple, dark streets |
| **Mark City spine** | Bespoke, plus F6 and F5 | Low | Walkways | Cool |
| **Miyamasuzaka / Aoyama-dori** | F5 45, F11 25, F4 15, F6 15 | Low: rooftop names | Few poles | Cool office white |
| **Meiji-dori north** | F7 40, F5 30, F4 20, O1 10 | Medium: brand panels | No poles | Clean white |
| **East of tracks / Stream south** | F4 40, F5 30, F6 15, F3 15 | Low | Poles on side streets | Warm residential |
| **Track-side (Nonbei)** | F12 80, F3 20 | Lanterns | Tracks and overhead wires | Red, orange |

Bespoke heroes, not built from the kit:
- 109, as a parody "1O9"-style mark
- Q-Front
- Hikarie
- Scramble Square, as a 2018 construction frame
- Mark City
- Tokyu Toyoko
- the station

**Next step for the owner:** a reference board of about 30 Commons and Street View photos (2018-era Street View where available) plus about 20 anime frame grabs, one row per district. Then author F1, F4 and F9 first: they carry the most Tokyo identity per texture.
