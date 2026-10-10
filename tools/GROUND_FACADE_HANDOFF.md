# Ground-floor facade drafts — October 8, 2026 (revision 3)

> **Current v6:** [FACADE_SECTION_HANDOFF.md](FACADE_SECTION_HANDOFF.md). 32 buildings, 228 complete ground runs, bounded core clearance and connected corners; library/gallery revision 6 retains all 53 styles with 2,600 portable parts. Earlier trial counts below are historical.

**Latest October 10 — revision 4:** `FACADE_PERIMETER_HANDOFF.md` is current.
53 physical designs (15 added), 79 Japanese business labels and 32 name stems.
The compact trial has three neighboring buildings with 38 whole exterior ground
runs; other sides use quiet walls/windows. Planting is ground-supported and the
parking opening passes an actual 22-stud interior/core clearance check. Existing
roads establish frontage access. Previous 14 scattered fronts are archived.
Generated glass remains restricted to the three explicit trial buildings.
Original structure, terrain, roads and generators are unchanged. Gallery has
53 samples; the wider deck keeps samples, stitched rows and street view separate.

**Earlier October 10:** the kit was revision 3. Generated glass was limited to
the 14 pilot buildings, with opaque far proxies disabled. Lime marks the actual
city frontage sample; magenta marks the elevated gallery/glass demo. See the
latest `GLASS_SYSTEM_HANDOFF.md` section. Building count before/after this task:
2,227, reflecting owner changes since the historical Oct 8 count below.

## Delivered and scope

38 physically different draft facade designs are built in the open **TestJJK** Studio place
(99539622209675). The isolated gallery is `Workspace.GroundFacadeDraftGallery`, around
**(0, 1600, 0)**, above the city. Reusable, facade-only templates are in
`ServerStorage.GroundFacadeDraftLibrary`. The gallery adds shallow interior vignettes to help
read the glazing; these back walls/floors are omitted from the reusable library.

The gallery includes three deterministic stitched examples (mixed retail, office, hotel),
a front/return corner example, and **03_StreetView**: nine adjoining fronts with a review-only
sidewalk, asphalt strip, shallow lit interiors and quiet upper-floor silhouettes/balconies.
The street mix includes chain-style food, Japanese shops, concrete, homes, garage parking and
two-storey glazing. All this context sits on the isolated deck, outside the actual city.
The original 15-design gallery/library and its runtime modules were preserved in
`ServerStorage.GroundFacadeDraftArchive` before replacing the draft roots.
A 14-building ground-front pilot now occupies a small western city section,
outside the crossing and protected landmarks. See `GLASS_SYSTEM_HANDOFF.md` for
the manifest, ownership/undo, four-state glass, damage integration and automatic
gallery demo. The pilot adds owned children; terrain, roads, original building
structure/interiors and generators are unchanged. `Workspace.Buildings` remains
**2,229 children**. Startup now initializes glass rendering/demo; HitHandler calls
the glass service before its existing destruction pass.

**The minimum is 15 physical facade designs. Sign changes do not count toward it.**
Individual door/window components currently share construction helpers (single/double/sliding
door treatment, framed glazing). This delivery does not claim 15 separate door designs plus
15 separate window designs. All doors are static draft geometry, with noncollidable door
panels so the portal can be walked through; no sliding mechanism or interaction is wired.

Source and a local reusable model are saved on disk. Studio gallery changes still need a
normal Studio save to persist in the place; a Rojo build is not a backup of this city.

## Handoffs read and current assumptions

- `src/client/ProjectFiles.luau` first: source/layout conventions and destruction contracts.
- `SHIBUYA_LIVE_STATE.md` and `SHIBUYA_SWEEP_RUNBOOK.md`: protected authored landmarks,
  live vs saved state, replay-safe tooling, cached requires, camera behavior, part budgets.
- `SHIBUYA_SOURCE_SLICE_HANDOFF.md`: source polygon and pivot rules; current ground and
  street history through **TERRAIN WRAP-UP — Oct 6**. The final owner choice is option B:
  flattened city, gentle road-agnostic ground, terrain considered done. Earlier September
  and Oct 4–6 ground recipes are history and must not be reapplied for facades.
- `FACADE_ROADMAP.md`: previous glass layout/rendering architecture and ground-floor intent.
- `ShibuyaSmoothPass.md`, `ShibuyaBoxPass.md`: prior representation/rollback contracts;
  their old model counts and box workflows do not describe the latest city.

Edit view has no client-generated `LocalFacades`/`LocalFacadesFar` geometry.
Play initializes the renderer, reconstructs persistent glass damage and suppresses
generic ground strips on pilot-owned runs. Ground kit panes carry `GlassPane`
tags and stable IDs. Native Play checks cover all four stages, local shard bursts,
pilot damage and ground ownership; details are in the glass handoff.

## Research and visual vocabulary

### Owner photographs — October 8 expansion

The owner supplied ten Shibuya street-view screenshots (nine unique views: #6 and #8 repeat).
These are visual references, not additional project instructions or a measured land-use census.
They broaden the vocabulary beyond a street made entirely of glazed shops:

- **#1/#3:** chain restaurants have substantial solid/wood-clad fascias, contrasting bands,
  separate window and entrance functions, menus on glass, occasional closed security grilles.
  Types 16/17 interpret these cues with fictional identities. The draft grille uses bars/rails,
  not a detailed animated accordion gate or copied chain logo.
- **#2:** a narrow convenience shop has thin metal frames, transoms, sliding-door hardware,
  and several tiers of Japanese notices. Type 18 uses separately seeded poster clusters.
- **#4:** parking can be an actual open void between concrete piers, with a deep shaded ceiling,
  protection strips and painted lines. Types 30–32 have no front glazing or shutter; rear/side
  walls and parking lines are gallery vignettes, omitted from reusable facade-only models.
- **#5:** stacked glazing has an opaque ribbed band at the floor division. Type 34 respects an
  existing 4.5-stud slab behind its band, with clear glazing above and below.
- **#6/#8:** a double-height glass lobby has slender frames, point fixings and a distinct inset
  vestibule. Type 35 requires an existing slab-free void; this kit never removes a slab.
- **#7:** quiet brick housing has a small identity plaque, frosted window, recessed entry and
  planted edge. Type 26 keeps signs subdued and residential privacy visible.
- **#9:** a garage shutter and an independent stair approach can share an older residential
  frontage. Type 29 models seven treads to a 2.8-stud raised entrance, beside the shutter.
- **#10:** narrow homes use opaque doors, round entrance columns and vertical privacy fins.
  Type 27 adds that physical vocabulary, without dressing it as another restaurant.

The added street context is intended to read as an urban Tokyo/Shibuya frontage at eye level:
busy and quiet uses adjacent, different opening proportions, mostly restrained wall materials,
Japanese signs at local shops, several parking/residential interruptions. It is an original draft
composition, not a recreation of the photographed blocks. Weighted profiles below are art
direction; the supplied photos do not establish city-wide percentages.

### Earlier online references

Research accessed October 7, 2026. These are references for an original generic kit, not
claims to reconstruct specific current tenants or landmarks. Widths/proportions below are
game art decisions, not a surveyed census of Tokyo storefronts.

- [Tokyo Workspace: Udagawacho shop/office building](https://www.tokyoworkspace.com/plus/detail/2188):
  photographed convenience/restaurant fronts and a separate route to other tenants. Use
  readable individual tenant bays and a dedicated upper-floor entrance, rather than one
  continuous office curtain wall. The page explicitly describes mixed tenants and basement
  access; our upper-floor entrance is a kit interpretation of that circulation vocabulary.
- [Shibuya Stream's official first-floor guide](https://shibuyastream.jp/shop/?floor=1f):
  street level can contain several restaurant identities in a larger mixed-use development.
  Do not assign ground-floor use solely from the building's overall height. Tenant lists
  change; references are used for the mix, not copied shop identities.
- [Olive LOUNGE Shibuya, Klein Dytham architecture](https://www.klein-dytham.com/olive-lounge-shibuya):
  the architect describes convex glazing and a first-floor cafe/bank mix with green, gold
  and wood tones. This suggests transparent public lobbies and coordinated material families;
  the draft uses straight native panes and does not reproduce the bespoke curved facade.
- [Daikanyama T-SITE, Klein Dytham architecture](https://www.klein-dytham.com/daikanyama-t-site):
  reference photographs for calm display glazing, pale framing and retail rhythm. The
  boutique/showroom drafts are a simplified visual interpretation, not T-SITE replicas.
- [Shibuya Fukuras, Tokyu Land](https://www.tokyu-land.co.jp/english/mxd/shibuyafukuras/):
  the first floor contains transit/tourism functions, while its advertised main commercial
  entry is [on 2F](https://city-media-shibuya.tokyu-land.co.jp/en/media-space/main-entrance/).
  This is a reminder to preserve special landmark circulation and not guess it from a box.
- [Shibuya Tokyu REI Hotel, official site](https://www.tokyuhotels.co.jp/en/shibuya-r/index.html)
  and [OneFive Tokyo Shibuya entrance photographs](https://travelspot.jp/562236/): visual
  references for sheltered doors, hotel identification, glazing and warmer entrance trim.
  Canopy sizes in the drafts are illustrative, not measured hotel dimensions.
- [Ramen-Ō Koraku Honpo photographed entrance](https://ameblo.jp/kuishinbou33/entry-12574192130.html):
  reference for the noren curtain, ticket machine and dense entrance signage. The ramen
  draft translates those cues into a compact native-part facade.

Names and signs in the kit are fictional. Signs use native geometry/text; the shared glass
system uses the generated uploaded overlays documented in `GLASS_SYSTEM_HANDOFF.md`.
Typography uses SurfaceGui text with actual Japanese
characters and a romanized name; sign faces are physical panels.

## The 38 physical types

Each type has a permitted width range, a nominal width and a distinct physical treatment.
Single-storey defaults use **12.5 studs of clear height**, matching existing storey tuning. Do not rebuild
the city to suit these drafts. The true georeference scale remains 4.182937 studs/metre;
that does not replace the project's deliberately tuned storey dimensions.

1. **01_Konbini** — 36 studs (28–48): broad sliding entry, low kickplate, thin metal frames,
   stacked fascia stripes, opening-hours panel.
2. **02_Coffee** — 28 (22–38): offset single doorway, fabric awning/valance, menu and blade sign.
3. **03_Ramen** — 20 (18–28): narrow offset sliding entry, three noren panels, ticket machine.
4. **04_Izakaya** — 24 (20–32): timber lattice screen, small canopy, two lanterns, recessed door.
5. **05_Bakery** — 28 (22–38): brick kickplate/piers, warm awning, bread menu, offset doorway.
6. **06_Boutique** — 32 (24–44): deeper double-door reveal, quiet pale fascia and display lighting.
7. **07_Showroom** — 36 (28–48): low-sill glazed display front, dark framing, wider double entry.
8. **08_Pharmacy** — 32 (24–44): bright clean fascia, framed sliding entrance, cross and blade panel.
9. **09_Shutter** — 24 (16–36): fully closed metal shutter, horizontal ribs, ground lock.
10. **10_TenantEntry** — 16 (14–22): narrow recessed entrance, tall floor directory, compact canopy.
11. **11_OfficeStone** — 40 (30–52): substantial stone piers, deeper portal, shallow metal canopy,
    paired planters and tenant plaque.
12. **12_OfficeGlass** — 48 (36–60): low-sill reception glazing, slender frames, broad sliding entry.
13. **13_HotelCanopy** — 48 (36–60): deeper sheltered entrance, five-stud canopy, warm soffit strip,
    hotel plaque and paired planters.
14. **14_HotelTimber** — 32 (26–42): timber fins framing a smaller hotel entry and compact canopy.
15. **15_Residential** — 24 (20–34): offset private entrance, mail bank, intercom and short canopy.
16. **16_ChainBurger** — 36 (30–48): wood-course fascia, red strip, offset glass entry and menus.
17. **17_ChainGrille** — 48 (40–60): two shop windows divided by a solid central pier, full closed
    security grids and projecting canopy. Explicitly marked `FacadeClosed`; no open door claimed.
18. **18_PosterKonbini** — 32 (28–44): central sliding-style entry, sensor/transom, thin glazing,
    stripe fascia and dense Japanese poster tiers.
19. **19_LocalShop** — 22 (20–30): tiled/brick piers, narrower offset entry, small noren and canopy.
20. **20_ProduceShop** — 30 (26–40): open frontage, green canopy, flanking produce counters/crates
    and a clear central approach.
21. **21_TakeawayHatch** — 22 (20–30): mostly concrete wall, serving opening, timber ledge,
    small hatch canopy and independent steel entry.
22. **22_HairSalon** — 28 (24–38): low-sill frosted glazing, deeper offset entry and small white canopy.
23. **23_Electronics** — 28 (24–38): higher display sill, projecting boxed window treatment,
    shelf/appliance silhouettes and local notices.
24. **24_ConcreteSparse** — 30 (24–44): one steel entry, a high shallow window strip, vent and pipes.
25. **25_ConcreteDouble** — 32 (28–44): two separate steel doors with a small high centre window.
26. **26_BrickResidential** — 28 (24–38): recessed private door, frosted broad window,
    planted edge, short canopy and small building-name plaque.
27. **27_TownhouseColumns** — 24 (22–34): opaque inset entry, two real cylindrical columns,
    full-height timber privacy fins, planted edge and narrow canopy.
28. **28_ApartmentGate** — 32 (28–44): frosted window, low masonry boundary, railing,
    a static noncollidable gate and separate inset door.
29. **29_RaisedEntry** — 32 (30–44): garage shutter left, seven stair treads and railings to a
    raised door right. Minimum clear height 11.5 studs; check actual street setback before use.
30. **30_OpenGarage** — 28 (22–40): two piers, deep concrete header, ceiling strip, open portal.
31. **31_TwinGarage** — 44 (36–60): central pier splits two independent open parking bays.
32. **32_PilotisParking** — 48 (40–60): two inner cylindrical supports, broad open pilotis frontage.
33. **33_LoadingBay** — 40 (34–52): wide open loading portal beside an independent steel service door.
34. **34_TwoStoreyGlass** — 44 (36–60): 29.5-stud total frontage, 12.5-stud ground glazing,
    4.5-stud ribbed opaque spandrel and upper glazing, inset entry and black canopy.
35. **35_DoubleHeightGlass** — 48 (40–60): 29.5-stud continuous glass lobby, point fixings,
    slender frames and a separate vestibule. Requires a genuine double-height void.

36. **36_McDooDoos** — 36 (28–48): red/yellow canopy, central entrance and
    projecting beacon columns; fictional fast-food identity.
37. **37_SmashKing** — 36 (28–48): timber fascia, red lintel, brick buttresses and
    offset glass entrance; fictional burger identity.
38. **38_Starboys** — 32 (26–44): green canopy, timber fins, window ledge, planter
    and left entry; fictional coffee identity.

The 38 stock templates contain **1,808 BaseParts**, including four cylindrical
columns. Gallery context adds review-only geometry. These are draft costs,
not an approved city-wide allocation.

## Composition contract

`GroundFacadeCatalog` holds physical type definitions, palettes, eligible profile weights,
15 fictional name stems, and stable hashes. `GroundFacadeExpansion` supplies the 23 new physical
layouts. `GroundFacadeKit.Layout` produces data;
`Build` creates one model; `PlanRun` partitions a span; `BuildRun` materialises a composition.
`GroundFacadeDrafts` is an edit-time gallery/library helper, not required by startup.

- **Coordinates:** bay centre X=0, ground-floor **slab top** Y=0, exterior facing local **-Z**.
  Positive Z is inside the building. Model pivots stay at that baseline; duplicate/rotate
  with `PivotTo`, not a bounding-box centre that moves with a canopy.
- **Stitching:** bay bodies fit their declared width; adjacent bays share a baseline and their
  end piers meet. Door dimensions, handles and trim remain at human scale. Width fits change
  glazing subdivisions rather than stretching a finished model.
- **Corners:** each face is a separate run. The gallery shows a perpendicular front/return;
  arbitrary concave/acute city corners still require a dedicated closing-pier solution and
  setback/clearance checks before rollout.
- **Stable randomisation:** use a persistent building identity plus piece/run identity.
  Do not derive seeds from position or child enumeration. Moving a building should preserve
  its frontage. Changing polygon/run topology may intentionally change the run keys.
- **Profiles:** `mixed`, `retail`, `alley`, `office`, `hotel`, `residential`, `residentialStreet`,
  `parking`, `service`, `chains`, `twoStorey`, `atrium`. The weights are
  art direction. Mixed fronts can contain independent tenants; office/hotel/residential/chains
  runs use **one entrance bay**, with matching window bays elsewhere. `residentialStreet` mixes
  individual homes and parking; it intentionally permits separate entrances. `twoStorey` and
  `atrium` also coordinate a single main entrance and never occur in ordinary profile picks.
- **Fit:** ordinary types accept 10.5–24 studs, except type 29 needs at least 11.5. Types 34/35
  accept 27.5–36, nominal 29.5 = 12.5 clear + 4.5 slab + 12.5 clear. Height filtering also applies
  while planning a run. An awkward span becomes blind infill; a doorway is never crushed to fit.
  Tall `BuildRun` profiles require explicit `height`; `atrium` additionally requires
  `confirmedVoid=true`. Standalone `Layout`/`Build` and stock clones are preview geometry;
  callers still must check real building clearance. No helper detects/removes existing slabs.
- **Variation:** physical type and bay width first; then whole-bay mirror, wall palette,
  accent, fictional name and subtitle. The 15 name stems are independent of physical type,
  with appropriate hotel/pharmacy/ramen/office prefixes. `brand` and `subtitle` can override
  the generated text. `window` role suppresses tenant signs/entry props.
- **Independent ads:** expansion shop types accept `ads="none"|"normal"|"dense"` and numeric
  `adSeed`. Dense convenience fronts use two tiers of three notices per eligible window span.
  Changing `adSeed` changes text/colors, while the architecture, poster positions and entry stay
  fixed. Changing density changes the ad arrangement only. Eight fictional Japanese notice texts
  combine with palettes, names, widths and mirroring. These notices never count as physical types.
- **Ground:** default 4.5-stud plinth extends downward behind the existing slab edge, and
  glass has a kickplate/sill above baseline. This is a visual draft, not an automatic terrain
  fitter. Sample actual street/terrain heights at the ends and doorway before placement;
  raise a sill or flag a ramp requirement locally. Never alter terrain to fit a template.
- **Attributes:** model attributes describe the built result; changing `FacadeSeed` or
  `FacadeWidth` in Properties alone does not rebuild it. Rebuild from options to change geometry.

## Using the drafts

In this current Studio session, cached-module-safe helpers are in
`ServerStorage.GroundFacadeDraftRuntime`. View an individual or the whole gallery:

```lua
local D = require(game.ServerStorage.GroundFacadeDraftRuntime.GroundFacadeDrafts)
D.Focus("03_Ramen")  -- or 13_HotelCanopy, etc.
D.Focus()            -- overview
D.FocusStreet()      -- eye-level composed street, initial review camera
D.RestoreCamera()    -- previous city view
```

After reopening Studio / a fresh Rojo sync, source helpers are at their standard paths:

```lua
local D = require(game.ServerScriptService.Server.GroundFacadeDrafts)
D.Generate()         -- idempotent; returns gallery and library
D.Focus("13_HotelCanopy")
```

The existing gallery's owner/state/revision attributes prevent duplicate creation on MCP replay.
`Upgrade()` preserves the previous draft roots under `GroundFacadeDraftArchive` before rebuilding
an older revision; it does nothing when the current revision is already ready. A fresh preview
place can reuse the matching imported revision-3 library while generating its gallery.
`Clear()` removes only this helper's two explicitly owned draft roots, never live city models.
After source edits, clone the modules with their dependencies as a group; Studio caches
`require()` for the session. Current runtime clones reflect the final kit source.

Build a duplicate/reseeded review piece in a separate preview folder:

```lua
local K = require(game.ReplicatedStorage.Shared.GroundFacadeKit)
K.Build(workspace.MyPreviewFolder, "06_Boutique", CFrame.new(0,1600,0), {
    width=30, height=12.5, seed=72, mirror=true,
    palette="charcoal", brand="余白 / YOHAKU", subtitle="CLOTHING & OBJECTS",
})
K.BuildRun(workspace.MyPreviewFolder, 96, "building-17/front", "mixed",
    CFrame.new(0,1600,50), {targetWidth=32})
K.Build(workspace.MyPreviewFolder, "18_PosterKonbini", CFrame.new(0,1600,100), {
    seed=72, adSeed=450, ads="dense", brand="青葉商店",
})
K.BuildRun(workspace.MyPreviewFolder, 96, "building-17/atrium", "atrium",
    CFrame.new(0,1600,150), {height=29.5, targetWidth=48, confirmedVoid=true})
```

`assets/GroundFacadeDraftLibrary.rbxmx` is the facade-only local library: import into
ServerStorage or an isolated review folder, then clone the named models. Uniform Studio
scaling is useful for rough visual experiments but does not preserve the kit's human-scale
door/trim contract; generate the requested width from source for actual placement.

Optional facade-only preview place build (contains these scripts/library, no city):

```powershell
rojo build tools/ground-facades.project.json -o assets/GroundFacadeDraftsPreview.rbxlx
```

Do not serve `ground-facades.project.json` into TestJJK: it is a separate preview build
definition. Continue using the main project for normal script sync.

## Destruction and city integration

All kit BaseParts are anchored, non-touchable and tagged **NoCSG**. Glass-attached
posters and privacy films are non-queryable/noncollidable; ordinary structure is
queryable. Physical glass is tagged `GlassPane`, captures baseline tint/collision
and carries a stable ground building/piece/run/bay/pane identity. State 3 hides
the base pane and attached posters/film; state 4 removes them. Static draft door
panels retain their intentionally noncollidable intact baseline.

`GroundFacadePilot` places along actual current polygon runs, reserves coordinated
entrances, records `GroundFacadeOwnedRuns`, and supplies small facade-only
approach steps/ramps. The renderer skips its owned ground strips, avoiding duplicate
glazing across doorways. Clearing the pilot repairs only its ground damage prefix,
removes owned children/metadata and preserves upper-floor geometry identities.
The glass handoff documents the 14-building manifest and replay/undo commands.

City-wide rollout remains future work. Continue excluding landmarks and authored
overrides, checking neighboring footprints, cores, street heights and awkward
corners. Dense native detailing needs additional simplification before broad
deployment. The pilot does not imply automatic facade placement at startup.

## Verification and remaining art work

Studio edit-time assertions passed: **684 width/height/mirror layouts**, **228 entrance/portal
clearance cases**, and **84 profile/span compositions** across the 38 types. The repeatable
check is `tools/verify_ground_facades.luau`, run against the fresh Studio runtime group.
Checks cover transformed bay bounds, opaque/prop doorway clearance, deterministic geometry
and profile choice, exact stitched width, one entrance for coordinated profiles, the atrium
void guard and independent ad seeding. All 1,808 template parts passed anchored/query/tag
checks. Geometry signatures excluding signs and lights are distinct for all 38 types.
Gallery/street screenshots were inspected. Replaying Generate returns the same roots.
Both the whole script project and facade-only preview passed Rojo builds. The Studio snapshot
was checked against the exported `.rbxmx` and Rojo-built preview `.rbxlx`: **38 models / 1,808
parts / four cylindrical columns**, with geometry, Japanese text, model attributes, baseline
pivots and NoCSG tags retained. Run `tools/verify_ground_facade_export.py` to repeat that check.
The official connector could not reload a local asset for an additional Studio import check;
the model checks therefore cover the exported XML and Rojo-normalised result. Native glass/demo and pilot-rendering Play checks are recorded in the glass handoff.
A full combat regression and device FPS benchmark are outside these checks.

Still draft quality: static doors, simplified chunky native geometry, no detailed shelf goods,
full stairs/elevator circulation, curved glazing, slope-following thresholds, animated shutters,
real fabric/wood normal maps, final lighting polish or city-wide placement. Type 29 has actual
draft stair treads, but does not build internal circulation. Gallery back/side walls and ceilings
are set dressing. Warm PointLights exist only in review vignettes, not the stock library or city.

For normal upper floors later, keep the building's slab rhythm and coherent palette, then vary
window subdivisions, opaque wall vs glass share and balcony/louver treatment by building family.
Ground-floor entrance decisions should not be reseeded on every storey. The street preview's
simple upper walls/windows/balconies provide visual context only; no new production
upper-floor art kit or terrain work is included in this delivery. The existing
upper-floor renderer now uses the shared persistent glass state and LOD rules.
