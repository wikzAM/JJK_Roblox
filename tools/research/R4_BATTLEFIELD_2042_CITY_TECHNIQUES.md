# R4: How Battlefield 2042 (and Frostbite) builds and runs big city maps

Research only. No game files changed. Written 2026-10-21.

**Tags:**
- **[official]**: DICE, EA or engine documentation.
- **[talk]**: a conference talk or paper by the developers.
- **[press]**: journalism, including press reports of developer quotes.
- **[community]**: player reports, modding docs, fan wikis.
- **[est]**: my own inference.

**Caveat up front.** DICE has published **no technical talk on Battlefield 2042's city maps**. I searched GDC Vault, SIGGRAPH and EA's Frostbite pages, plus Digital Foundry coverage (reached only through secondhand summaries). What is public:
- older Frostbite talks on destruction, culling and the *Mirror's Edge Catalyst* city;
- EA's 2025 Battlefield 6 destruction article;
- press reports and developer posts;
- modding documentation of Battlefield 3's data types.

Where I connect those to 2042, the claim is tagged [est].

---

## TL;DR

1. **The skylines in 2042 are mostly static scenery.** Destruction sits in low-rise blocks, walls and set pieces. Destructible skyscrapers were reportedly cut for being "too ambitious" at 128 players [press]. Some Hourglass towers shipped without collision at all [press].
2. **Frostbite's city recipe** comes from the DICE talk on *Mirror's Edge Catalyst*, a Frostbite game set in a glass city [talk]:
   - modular kits;
   - far-away groups of buildings baked into **one object**;
   - many materials baked into **one texture set** for LODs;
   - texture arrays to merge draw calls;
   - "interior mapping" shader tricks behind flat windows.
3. **Destruction is authored, not simulated from scratch.** Each building is pre-split into parts that have their own health. Breaking a part removes it, adds pre-made edge detail and a shader mask, then spawns debris. In Battlefield 3's data, debris clusters have a `clientSideOnly` flag and a cap on active pieces [talk, community].
4. **Battlefield 6 (2025) adds three things** [official]:
   - destruction events are **prioritised and culled over the network**;
   - buildings **"apple-core"**: the shell crumbles and the core stays;
   - the rubble **persists as cover**.

   DICE says levelling everything is "not a good idea" because the game stops being readable [press].
5. **128 players made 2042 CPU-bound.** DICE pulled 128-player Breakthrough back to 64 players [press]. Player count, not graphics, was the scaling wall.

---

## 1. Keeping huge city maps fast

**What 2042 ships.**
- **Hourglass** (Doha) is desert plus a glass-tower downtown, about 1.2 km² by a fan estimate from EA's comparison graphic [community]. It has a sandstorm that sweeps across the map and cuts visibility [press].
- **Kaleidoscope** (Songdo) is the smallest launch map: a central data-centre hub, a park and enterable skyscrapers with elevators and zip lines between rooftops [press].
- **Breakaway** is the largest at 5.9 km² [press].
- **Our map, for scale:** 6,400 × 6,000 studs at 0.24 m per stud is about 1.5 × 1.4 km, or **about 2.2 km²**. That is bigger than Hourglass, with far denser buildings [est].

**The bottleneck was CPU and player count, not pixels.**
- A DICE developer said resolution was not the limit because 128 players were hammering the CPUs [press, quoting ResetEra].
- Digital Foundry's console tests found frame-rate and frame-time drops in 128-player modes even on PS5 and Series X [press, via DTF summary].
- DICE said PC performance was CPU-bound on many machines [press].
- PS4 and Xbox One got 64 players on smaller maps [press].
- In 2022 DICE removed 128-player Breakthrough, saying 64 players was "more tactical" [press].

**How Frostbite builds a dense city.** The best primary source is DICE's SIGGRAPH 2015 talk *Building the City of Glass in Mirror's Edge* (Johansson & Schmid) [talk]:
- **CSG to whitebox, kept to final.** Level artists block out buildings with in-engine CSG and refine that blockout all the way into the shipped asset.
- **Modular kits per building style,** combined in different ways to make unique buildings.
- **Cluster baking.** "To keep our instance counts down", buildings made of many objects are baked down to **a single object** for parts of the city far from the viewer.
- **Material reduction.** Several shaders and textures are baked into **one texture set**, which gives "much more efficient LOD steps". LODs are generated automatically.
- **Texture arrays.** Combining textures lets several draw calls be grouped into one.
- **Interior mapping.** This is DICE's name for the shader and texture tricks that make flat geometry look like it has rooms behind it.
- **Heavier streaming than Battlefield.** The city shows much more unique content per frame than Battlefield's open vistas, so it needed more streaming.

EA also documents an automatic LOD tool, Quad Mesh Simplification, used "from Battlefield to Plants vs Zombies" [official].

**Occlusion.** DICE's GDC 2011 talk *Culling the Battlefield* describes Frostbite's software occlusion [talk]:
- Artist-made occluder meshes plus terrain are drawn on the CPU into a tiny **256 × 114** depth buffer.
- Objects are then tested against that buffer.
- Listed goals include saving CPU, not just GPU, time and "support destruction": occluders must go away when walls do.
- Frustum culling of 15,000 bounding spheres took about 0.2–1 ms.

**Draw distance.** PC settings mostly cut shadow distance and mesh and foliage quality, not view distance [press]. Players reported more pop-in after the beta [community]. No source says how far towers draw; the skyline is most likely baked cluster LODs [est].

**Weather as cover.**
- DICE spent over three years on the weather and set-piece tech: tornadoes and the Hourglass sandstorm [press, quoting GM Oskar Gabrielson].
- The sandstorm is a gameplay event. DICE has not said it is a performance tool.
- But a wall of particles that hides the far city and lowers visibility does also hide LOD swaps [est].

## 2. Destruction

**History in one line each:**
- **Bad Company 2:** whole houses collapse [community].
- **Battlefield 3:**
  - fewer fully destructible buildings;
  - on Rush maps, long rounds ground the defenders' areas to rubble, so DICE added "covers that actually are not destructible" (GM Karl-Magnus Troedsson) [press].
- **Battlefield 4:** "Levolution" set pieces such as the Siege of Shanghai tower [press].
  - Players drop the tower by blowing up four cracked pillars.
  - It falls into the bay, kills anyone inside and becomes a new flag, "Ruins".
  - Dust then blankets the map [press].
  - DICE's Lars Gustavsson later called Levolution "heavily scripted": impressive the first time, then not. DICE moved to general, system-driven destruction [press].
  - Players remember frame-rate drops during the collapse [press, anecdotal].
- **Battlefield V:**
  - collapses driven by physics and materials, not fixed animations;
  - walls "crack, move, and then crumble" over a longer time;
  - a tank pushes debris inward [press, quoting DICE's blog].
- **Battlefield 2042:**
  - Community manager Kevin Johnson promised "Battlefield V's level of destruction across most maps" [press].
  - Reporter Tom Henderson said destructible skyscrapers were cut as "too ambitious" for the team and hardware at 128 players [press, leak]. Spanish press added that engineers were given six weeks for a six-month job [press].
  - Shipped destruction is mostly walls and barriers, plus set pieces: tornadoes, the Orbital rocket and the destructible Hourglass village [press].
  - Kaleidoscope's 2022 rework added "tactical destruction" and cover around the data centre [press].
  - Battlefield Portal remasters kept Bad Company 2 and Battlefield 3 destruction, and added destruction to the Battlefield 1942 maps [press].

**What players said.** The press summary of player opinion was that 2042 "barely has any destructible buildings" [press]. EA forum threads call it the series' weakest destruction [community]. Battlefield 6's marketing was largely a response to that.

**How Frostbite destruction is actually built** (Kihl, SIGGRAPH 2010) [talk]:
1. Remove a pre-authored piece of geometry (a destructible "part").
2. Add pre-made **detail meshes** around the hole.
3. Apply a **destruction mask**. Artists place spheres where holes go, the spheres become a tiny distance-field volume texture (about 2 m per texel, typically 8 × 8 × 8), and a shader uses it to fray the hole edge.
4. Add particles and mesh debris.

Drawing the mask cost about **0.2–0.8 ms per frame on PS3**, depending on technique. This has been the basis since Bad Company.

**Battlefield 3's data types** (Venice Unleashed modding reference) [community] show the same model:
- **`HealthStateData`** holds `health`, a `partIndex`, `canSupportOtherParts` and `loosePartPhysics`.
- **`BreakablePartComponentData`** has `collapsable` and `destroyNearbyStaticEntities`.
- **`BreakableRuinComponentData`** holds a `ruinModel`, the mesh swapped in after collapse.
- **`DebrisClusterData`** has `clientSideOnly`, `maxActivePartsCount`, `clusterLifetime`, `noCollision`, `killPartsOnCollision` and `deactivatePartsOnSleep`.

My reading [est]:
- The server owns **which numbered part is at what health**.
- Clients play pre-authored removals, masks and ruin swaps from that state.
- **Debris is mostly client-side cosmetic**, capped per cluster and lifetime-limited.
- The structural "support" flags give a simple collapse graph without real structural physics.

I found no public DICE description of the destruction packet format or of what late joiners receive.

**Battlefield 6 (2025)** [official]:
- Frostbite and the Battlefield teams "overhauled how destruction events are networked", optimising bandwidth and prioritisation so 64-player matches stay in sync.
- More realistic destruction required "prioritization and culling of part destruction and debris spawning" (Frostbite engineer Talan Le Geyt).
- A reworked **health-transition system** lets designers run custom logic or spawn assets whenever a building's health state changes.
- Battlefield Labs notes:
  - buildings **"apple-core"**: the shell crumbles and the core stays exposed while rubble piles up;
  - **rubble persists as cover**;
  - surfaces show **persistent damage** before they break;
  - early playtests had **server stability and performance problems**.

Lead producer David Sirland added [press, quoting his posts on X]:
- "just destroying everything isn't a good idea", and readable, playable destruction is much harder;
- tuning is "per material and type of damage";
- debris "does do damage – just not instantly – because that is not fun and too random".

Technical director Christian Buhl credited dropping PS4 and Xbox One, and their memory and CPU limits, as one of the main enablers [press].

## 3. Glass

**No DICE talk or blog on Frostbite glass was found.** What is visible in play:
- Battlefield games have long had shootable windows at street level [community].
- 2042's Hourglass towers were hollow and in places had **no collision**. Helicopters flew through walls and hid inside, and a jet bounced off some towers and passed through others [press].

That strongly suggests [est] the tower glass is **a material on a static shell**, not a set of breakable panes. The lack of breakable skyscraper glass was not a major complaint; the lack of building destruction was.

For a documented approach to cost tiers, CryEngine 3's breakable-glass guide is the clearest public reference [official, other engine]:
- **Fully breakable panes:**
  - simple, near-flat, under 100–200 triangles;
  - a costlier "small" variant for panes the player can reach;
  - a **cheaper "large" variant for panes the player cannot get close to**.
- **"Material switch" glass:** goes to a spiderweb-cracked look instead of a hole, for **facades that should never fully vanish**.
- **Unbreakable glass:** only shows a crack decal and particles.
- **Caps:** at most 5 breakable glass nodes per object. Breakable glass also stops static mesh merging, which is the hidden cost.

Frostbite's equivalent is very likely the same idea [est]: real pane breakage only where players fight, and decal or mask cracks elsewhere.

## 4. Skyscraper facades: textures, not geometry

The only Frostbite-specific facade source is the Catalyst talk above [talk]:
- **Interior mapping** behind flat windows.
- **Texture arrays,** so many facade materials share a draw call.
- **Material-reduction baking** for LODs.
- **Cluster baking** for far blocks.

Kihl's destruction mask shows the second habit: **damage is painted onto existing geometry with a shader** (a decal), not modelled, until a part is actually removed [talk].

2042's tower art pipeline has not been published. The no-collision bug suggests the hero towers were built and handled as background art, separate from the playable buildings [est].

## 5. High-speed traversal

2042 combines:
- jets and helicopters across 1–6 km² maps;
- a Specialist wingsuit;
- a grappling hook;
- zip lines and elevators up the Kaleidoscope towers [press].

No rendering talk covers how 2042 handles this. What the evidence shows:
- **Static, cheap skylines make low passes affordable.** A jet at rooftop height sees only cluster-baked towers [talk + est].
- **Fast movers find every collision gap.** Aircraft flew inside the hollow towers, and grapples hooked onto smoke and tornadoes [press].
- **CPU-side occlusion** culls before GPU work, which matters most when the visible set changes every frame [talk, est].

## 6. Lessons for our Roblox game

1. **A static skyline is the norm at AAA, not a compromise.**
   - DICE cut destructible skyscrapers at 128 players and shipped static, partly hollow towers.
   - Our per-block stand-in meshes and painted horizon match that, and our destruction can stay focused where fights happen.
   - **But fix what 2042 got wrong:** everything a player can reach at speed needs collision that matches what they see. That means the stand-ins (or a cheap collision box under each) whenever a player is within reach.
2. **Catalyst's cluster bake *is* our block stand-in, and its material reduction *is* our atlas per facade family** (T12/T13).
   - DICE's motive, "keep our instance counts down", is exactly our memory and draw-call problem.
   - Copy their two-step authoring: CSG or Part kits as the **source**, baked output as the **runtime**. That is already our "one design source, two outputs" (synthesis §3.2).
3. **Copy Frostbite's destruction data model for the deterministic mirror** (synthesis §8.1):
   - **Per part:** a stable `idx`, `health`, a `canSupport` flag and an optional `ruinModel` swap. That is what Battlefield 3 stores.
   - **The server replicates only health and state changes.** Clients play pre-authored removals and edge detail.
   - **Debris is `clientSideOnly`, non-colliding, capped** (our ≤250 pool) and lifetime-limited.
   - This confirms our 200–500-byte event design. Battlefield 6's "prioritization and culling" supports our plan to send far clients less detail for each event.
4. **Battlefield 6's apple-core collapse maps directly onto our `BuildingCore` walls.**
   - The facade and slabs crumble; the core stays up as a readable landmark; designed rubble piles stay as cover.
   - That is cheaper than full collapse, reads better in a fight, and gives the "map-wipe ultimates" a distinct top tier.
   - Keep some **indestructible anchors**, as Battlefield 3 did after Rush maps were ground flat.
5. **Destruction masking before geometry.**
   - Frostbite shows damage as a shader or decal mask before removing a part.
   - For us: crack overlay or decal first, and remove geometry (octagon primitives, CSG) only on a real break.
   - Hide every swap under dust, as the existing `YIELD_MASK_DELAY` already does.
6. **Glass in three tiers**, after CryEngine's documented scheme and our T8 numbers:
   - **(a) Real breakable panes** only within about 150 studs or about 150 panes of the player.
   - **(b) "Material switch" panes in mid range:** our cracked opaque overlay part, never a hole, so facades never look torn open from afar.
   - **(c) Far glass** stays baked into the facade texture and is **never breakable**.
   - The CryEngine note that breakable glass stops static merging is the same trap as our transparent panes hiding particles. Keep live panes rare.
7. **Use scripted set pieces for hero moments.**
   - Levolution's scripted tower fall is cheap, networks as one event, and is easy to make deterministic. It suits ultimates on hero buildings (Hikarie, 109).
   - The lessons from Battlefield 4: set pieces lose impact on repeat, and the dust and debris burst dropped frame rate. **Budget the dust** for those events, and make it hide the stand-in-to-ruin swap.
8. **Readability over realism.**
   - Sirland's "destroying everything isn't a good idea", plus non-instant debris damage, argue for:
     - capped per-event destruction;
     - debris that does little or no damage;
     - designed rubble instead of simulated piles.
   - This fits our physics-off pillar.
9. **Player count is the real scaling wall.** 2042 was CPU-bound at 128 and retreated to 64 for one mode. Our server budgets (heartbeat ≥58 Hz, ≤40 KB/s per client) should be tested at our **maximum** lobby size with bots before we promise a number.

---

## Sources

**Talks and official documents**
- Kihl, *Destruction Masking in Frostbite 2 using Volume Distance Fields*, SIGGRAPH 2010 [talk]: https://www.advances.realtimerendering.com/s2010/Kihl-Destruction%20in%20Frostbite(SIGGRAPH%202010%20Advanced%20RealTime%20Rendering%20Course).pdf ; slides: https://www.slideshare.net/DICEStudio/siggraph10-arrdestruction-maskinginfrostbite2
- Johansson & Schmid, *Building the City of Glass in Mirror's Edge*, SIGGRAPH 2015 Talks [talk]: https://history.siggraph.org/wp-content/uploads/2022/10/2015-Talks-Johansson_Building-the-City-of-Glass-in-Mirrors-EdgeTM.pdf
- Collin, *Culling the Battlefield: Data Oriented Design in Practice*, GDC 2011 [talk]: https://www.slideshare.net/DICEStudio/culling-the-battlefield-data-oriented-design-in-practice ; https://www.ea.com/frostbite/news/culling-the-battlefield-data-oriented-design-in-practice
- Christin, *Lighting the City of Glass*, GDC 2016 [talk]: https://www.gdcvault.com/play/1023284/Lighting-the-City-of-Glass
- EA, *How Battlefield 6 redefined destruction* [official]: https://www.ea.com/en/news/how-battlefield-6-redefined-destruction
- EA, *Battlefield Labs: destruction* [official]: https://www.ea.com/games/battlefield/battlefield-6/news/battlefield-labs-destruction
- EA Frostbite, *Quad Mesh Simplification* [official]: https://www.ea.com/frostbite/amp/news/discover-frostbites-quad-mesh-simplification
- EA, *Battlefield 2042 dev notes: Stadium / Hourglass rework* [official]: https://www.ea.com/en/games/battlefield/battlefield-2042/news/dev-notes-stadium
- CryEngine 3 docs, *Breakable Glass* [official, other engine]: https://cryengine.com/docs/static/engines/cryengine-3/categories/1114113/pages/1310744

**Press**
- 2042 destruction at "BFV level" (Kevin Johnson): https://mp1st.com/news/battlefield-2042-destruction-to-be-at-bf5s-level-for-most-maps-new-maps-have-areas-to-focus-on-infantry-only-combat
- Destructible skyscrapers cut (Henderson): https://www.ggrecon.com/articles/battlefield-2042-insider-confirms-destructible-skyscrapers-were-cut/ ; https://www.3djuegos.com/noticias-ver/218523/battlefield-2042-peco-de-ambicioso-y-por-ello-tiene-una/
- Which 2042 buildings are destructible: https://www.gamerevolution.com/guides/697812-battlefield-2042-destruction-which-buildings-destructible
- Missing tower collision: https://kotaku.com/dice-forgot-about-building-collision-in-battlefield-204-1848110213 ; https://www.nme.com/news/battlefield-2042-players-are-hiding-in-buildings-that-have-no-collision-boxes-3102734
- Grapple into smoke and tornadoes: https://www.thegamer.com/battlefield-2042-glitch-is-causing-players-to-grapple-into-smoke-and-even-tornadoes/
- Digital Foundry console tests (summary): https://dtf.ru/hard/959038
- 120 fps and CPU (DICE developer comment): https://www.purexbox.com/news/2021/11/battlefield-2042-could-potentially-bring-120fps-to-xbox-series-xs-claims-dev ; DICE on the CPU-bound PC version: https://www.tweaktown.com/news/82941/dice-admits-battlefield-2042-pc-performance-issues-fix-taking-while/
- 128-player Breakthrough removed: https://www.pcgamer.com/uk/dice-is-removing-battlefield-2042s-128-player-breakthrough-playlist-says-64-players-is-more-tactical/
- Last-gen 64 players: https://press-start.com.au/news/playstation/2021/06/10/battlefield-2042-will-support-128-player-matches-on-ps5-xbox-series-x-pc-and-64-players-on-ps4-xbox-one/
- Weather and Levolution tech, three years: https://mp1st.com/news/battlefield-2042-frostbite-engine-worked-on-for-over-3-years-for-weather-levolution-system-tech
- Hourglass sandstorm: https://www.neowin.net/news/battlefield-2042-gameplay-trailer-shows-off-the-sandstorm-hit-hourglass-map/
- Map sizes and Kaleidoscope layout: https://www.gamesradar.com/battlefield-2042-maps ; https://earlygame.com/es/battlefield/battlefield-2042-comparacion-del-tamano-de-los-mapas
- Kaleidoscope 1.2 rework: https://mp1st.com/news/battlefield-2042-next-update-1-2-patch-notes-revealed-patch-set-to-drop-tomorrow ; https://www.techradar.com/news/battlefield-2042s-big-map-changes-leave-fans-disappointed
- Hourglass 5.2 rework: https://www.gamingnexus.com/News/63332/
- Portal remasters: https://windowscentral.com/battlefield-2042-revives-battlefield-3-bad-company-2-1942-maps-new-sandbox-mode
- PC settings and shadow distance: https://shacknews.com/article/127841/pc-graphics-settings-guide-battlefield-2042
- BF3 indestructible cover (Troedsson): https://mp1st.com/news/less-destructible-environments-in-battlefield-3-dice-explains
- Gustavsson on scripted Levolution: https://stevivor.com/2016/08/dices-lars-gustavsson-levolution-is-the-most-depreciated-word-in-the-industry
- Siege of Shanghai collapse: https://primagames.com/eguides/battlefield-4-eguide/levels/siege-of-shanghai ; https://pcgamesn.com/battlefield/battlefield-4-s-levolution-lets-you-flood-cities-block-alleys-shoot-out-power ; frame-rate recollection: https://mp1st.com/news/should-levolution-return-in-the-next-battlefield-game
- BFV physics destruction: https://www.dsogaming.com/?p=113506 ; https://techraptor.net/content/dice-details-gameplay-changes-new-modes-for-battlefield-v
- BF6 Sirland on debris damage: https://mp1st.com/news/battlefield-6-destruction-damage-why-you-dont-die-at-debris-explained ; "not a good idea": https://insider-gaming.com/battlefield-6-battle-royale-and-multiplayer-has-the-same-destruction-system/ ; https://ixbt.games/en/news/2025/09/17/polnaia-razrusaemost-zdanii-v-battlefield-6-byla-ploxoi-ideei-govorit-ea.html
- BF6 Buhl on dropping last-gen: https://insider-gaming.com/battlefield-6s-destruction-improved-after-dropping-ps4-and-xbox-one/
- History of Frostbite destruction (Troedsson): https://www.gamedeveloper.com/design/how-dice-fell-in-love-with-destruction

**Community**
- Venice Unleashed Frostbite type reference (Battlefield 3 data): https://docs.veniceunleashed.net/vext/ref/fb/debrisclusterdata ; https://docs.veniceunleashed.net/vext/ref/fb/healthstatedata ; https://docs.veniceunleashed.net/vext/ref/fb/breakablepartcomponentdata/ ; https://docs.veniceunleashed.net/vext/ref/fb/breakableruincomponentdata/ ; https://docs.veniceunleashed.net/vext/ref/fb/destructioncontrollercomponentdata
- Pop-in reports between beta and launch (EA forums): https://forums.ea.com/discussions/battlefield-2042-general-discussion-en/low-graphics-for-ps5-and-series-x/7058720
