# Upper-floor facade style deck (storeys 2..N)

Status: written October 18, 2026. Files are in the repo only. Nothing has been synced to Studio or built in the city.
Code: `src/shared/UpperFacadeCatalog.luau` (data and picks), `src/shared/UpperFacadeKit.luau` (builder), `tools/verify_upper_facade_kit.luau` (Edit-mode self-test).
This doc fills in the families from `UPPER_FACADE_APPROACH.md` and follows its mounting contract.

## 1. Research summary

The search was text only. I could not view Google Street View imagery from this session. The arrangements below combine the sources listed here with the well-known look of Shibuya side streets: Dogenzaka, Center Gai, Udagawacho, Jingumae/Omotesando, Ebisu, and mid-rise blocks in Shinjuku and Ikebukuro. **Owner: please check the deck against Street View** of Udagawacho 3-chome, Dogenzaka 2-chome, Center Gai and Meiji-dori (Jingumae), then adjust the weights and palettes.

- **Zakkyo biru (mixed-tenant buildings).** These are narrow mixed-use blocks from roughly 1960 to 1990, typical of Ginza and Shibuya. A different tenant on each floor (bar, salon, karaoke, clinic) shows up as a vertical tenant directory and stacked signboards. Cladding is glazed tile (olive, brown, beige), mortar or plain concrete. Floors are repetitive, with single or paired windows. Sources: varnelis.net "The Zakkyo Biru of Ginza"; Almazán (cited there) on the zoning, inheritance-tax and regulation system that produces them.
- **Kanban kenchiku (signboard architecture).** These are flat decorative street faces in mortar, copper or tile on top of a plain structure. This supports the owner's rule that the upper facade is one-dimensional: a flat street face, not a deep relief. Sources: Dwell "Japan's Dwindling Signboard Buildings"; Tokyo Unfolded "Why signboard architecture".
- **Pencil buildings.** These are tall, very thin plots of about 3.8 to 6 m. Facades are a regular grid of a few large openings, or a mosaic-tile skin with small or irregular windows. Sources: Domus (pencil-building penthouse), Thisispaper (Kumagaya pencil building), Dezeen (Apollo "Flag", a grid of large openings), CCA "Models Talk".
- **Mansions (apartment blocks).** Continuous balconies run along the facade, partly because they double as evacuation routes. Outdoor AC units sit on those balconies. Fully tiled facades were the norm in the 1980s and 1990s. The back side is often an open access corridor: a parapet, steel doors and small frosted windows. Aluminium balcony handrails are a standard catalogue product. Sources: Concrete Decor ("Concrete offers a new model for apartment block design"); TCI-ThaiJo "Characteristics of Ceramic Tiling Facade in the Metropolitan Condominium" (Japan and Thailand); IPROS aluminium handrail catalogues (Kume Industries).
- **Offices.** Postwar offices used tile or concrete walls with aluminium sash, and from the 1960s vertical aluminium louvres (Sony Building, Ginza, 1966). Half-mirrored curtain walls appeared in the 1970s (Sogetsu Kaikan, 1977). Current Shibuya towers use tall low-E unitised curtain walls with expressed mullions. Shibuya Scramble Square has panes over 4 m tall with mullion rhythm shifting at the corners. The Dear Jingumae conversion added metallic louvres over an older office. Sources: M+ (Sony Building louvre); Wikipedia and KKAA (Shibuya Scramble Square); gooood.cn (Scramble Square phase 1); archilovers (Dear Jingumae); CTBUH (Shibuya Hikarie).
- **Shibuya side streets.** Udagawacho still has chunky brown, boxy Showa-era walk-ups with tiny single-pane windows (Craig Mod, Ridgeline #231). Dogenzaka mixes worn older hotels and nightlife buildings with new bark-textured offices (AD-O Dogenzaka, KKAA; Japan Travel; Lonely Planet).

**Takeaways for the deck:**
- Repetition within a building, variety between buildings.
- Muted greys, beige and brown tile, white aluminium and dark glass.
- Colour comes from signboards on mixed-use buildings, not from the walls.
- Horizontal emphasis (ribbon windows, balcony bands) on offices and mansions. Vertical emphasis (fins, piers, blade signs) on commercial and pencil buildings.
- Every element can be flat.

## 2. Families and variants (10 families, 29 arrangements)

All sizes are in studs. Storey clear height is about 12.5, so a module of 10 is about 3 m.

- **Sill:** the opaque floor band above slab top. The floor band also covers the slab edge below.
- **Head:** the opaque band under the next slab. The head band and the next floor's floor band read together as one spandrel.
- **Module:** target bay width. Bays are stretched to fill the run exactly.
- **Pier:** solid wall between windows. On ribbon variants a mullion of the listed width replaces it.

| Family | Variant | Window rhythm | Sill / head | Module / pier | Extras |
|---|---|---|---|---|---|
| curtain (glass offices, Scramble Square / Hikarie podium style) | A1_CurtainGrid | continuous glass, 1 or 2 panes per bay | .8 / 1.2 | 10 / mullion .25 | spandrel is dark reflective panel |
| | A2_CurtainFins | continuous glass, 2 panes per bay | .8 / 1.2 | 9 | proud aluminium fin at every bay line, full height |
| | A3_CurtainStripe | glass alternating with deep spandrel-glass stripes | 3.4 / 1.8 | 10 | horizontal stripe office |
| | A4_CurtainChecker | glass, glass, opaque panel column | .8 / 1.2 | 6 | panel columns break up large walls |
| ribbon (1970s-90s concrete/tile offices) | B1_RibbonConcrete | continuous ribbon, one sash per bay | 3.2 / 2.4 | 6 / .3 | exposed concrete bands |
| | B2_RibbonTile | sliding pair plus fanlight (transom at 78%) | 3.0 / 2.8 | 7 | tile bands |
| | B3_RibbonEave | ribbon | 2.8 / 2.4 | 8 | thin sunshade eave (hisashi) at the head |
| grid (aluminium panel / precast) | C1_PanelGrid | single punched window | 3.4 / 2.8 | 8 / 2.6 | recessed glass shows a .4 reveal |
| | C2_PairedGrid | paired windows | 3.0 / 2.4 | 12 / 3.4 | |
| | C3_PrecastVertical | tall single window with transom | 3.6 / 2.0 | 6 / 1.8 proud | continuous proud piers give vertical emphasis |
| mansion (tile apartments) | D1_BalconySolid | full-height sliding doors behind solid parapet | 0 (parapet 3.6) / 2.4 | 18 / .8 | unit divider fins; side faces use D3 |
| | D2_CorridorSide | open access corridor: parapet, dark recess, doors, small frosted windows | parapet 3.6 / 2.4 | 16 | |
| | D3_PunchedTile | window, window, frosted bathroom slot | 3.4 / 2.6 | 10 / 4 | quiet/side variant |
| | D4_BalconyRail | sliding doors behind translucent rail band | rail 3.4 / 2.4 | 16 / .8 | AC units visible behind the rail |
| stucco (mortar small residential / walk-up office) | E1_StuccoPunched | sliding pair windows | 3.4 / 2.8 | 10 / 4.4 | sill trim |
| | E2_StuccoPrivacy | window, frosted slot, vent | 3.4 / 2.8 | 9 / 3 | |
| | E3_StuccoSlots | narrow vertical slots | 1.6 / 2.2 | 6 / 1 | |
| brick (brick-tile older offices) | F1_BrickPunched | paired windows with fanlight | 3.2 / 2.6 | 9 / 3.6 | brick floor bands, sill trim |
| | F2_BrickPierSpandrel | single windows | 3.4 / 2.4 | 8 / 1.6 | brick piers, pale concrete spandrels |
| louver (Omotesando / Jingumae commercial) | G1_VerticalLouver | glass behind fins every ~2.2 | 1.0 / 1.4 | 10 | full-height thin fins |
| | G2_HorizontalLouver | glass with 1 to 5 horizontal blades | 1.0 / 1.4 | 10 | |
| | G3_MetalScreen | glass, upper 55% behind a translucent metal screen | 1.2 / 1.4 | 9 | |
| zakkyo (mixed-use / pencil) | H1_SignStack | paired windows plus one signboard bay per floor | 3.0 / 2.2 | 9 / 1.4 | colours stack floor by floor, primary face only |
| | H2_FasciaBand | ribbon glass with a tenant fascia sign in the head band | 2.6 / 3.4 | 8 | primary face only |
| | H3_PencilPunched | single punched windows | 3.2 / 2.6 | 7 / 2.4 | quiet/side variant |
| hotel (business hotels) | I1_HotelSlots | one small window per room | 3.6 / 2.8 | 6 / 2.6 | |
| | I2_HotelAccentBay | single window | 3.2 / 2.4 | 7 / 1.6 | continuous coloured piers |
| showa (Showa walk-ups, Udagawacho) | J1_ShowaSmall | small pair window alternating with frosted slot | 3.6 / 3.0 | 8 / 4.4 | |
| | J2_ShowaSteelSash | two-row steel sash band | 3.2 / 2.6 | 5 / mullion .2 | painted green or grey frames |

**Palettes** are in `UpperFacadeCatalog.PALETTES`: 48 in total, 4 to 6 per family.
- Fields: `wall`, `band`, `band2`, `pier`, `frame`, `glass` (with transparency and reflectance), `frost`, `dark`, `accents`, and material names.
- Materials: `Concrete`, `CeramicTiles`, `Brick`, `Plaster`, `Metal`, `SmoothPlastic` and `Wood`, resolved through `Catalog.Mat` with a Concrete fallback.
- Glass is dark and fairly opaque (transparency .06 to .2), so the empty floors behind (slabs and core only) don't read through.
- Signboard colours (red, yellow, blue, green, white, orange, magenta, black) belong to the zakkyo palettes only. Other families use four muted accents.

**Suitability, as family weights in `Catalog.FAMILIES`.** Each building gets one class: small (3 storeys or fewer), pencil (widest run under 28 studs and at least 3 storeys), mid, or tall (9+ storeys).

| Class | Most likely families |
|---|---|
| tall | curtain, grid, ribbon, mansion, hotel |
| mid | ribbon, mansion, grid, brick |
| pencil | zakkyo, then ribbon, louver, hotel, stucco, showa |
| small | stucco, showa, then mansion, brick, zakkyo |

## 3. One identity per building

`Catalog.Pick(SourceSliceId, class)` returns the whole building style.
- Every field comes from its own roll: `Random.new(Seed(id.."/"..tag))`. Adding a field later never reshuffles existing buildings.
- The style is stored on the folder as the `UpperFacadeStyle` attribute (JSON).

What the style fixes for the whole building:
- **Family, variant and palette.**
- **Proportions:** module scale (.85 to 1.2), sill scale (.85 to 1.2), head scale (.85 to 1.2), and pane count where the variant offers choices.
- **Floor-band mode:**
  - none (most common)
  - `alt`: every other floor uses `band2`
  - `podium`: the first upper floor uses `band2`
  - `every3`: every third floor uses `band2`
- **Crown on the top storey:** none (about 60%), `attic` (shorter clerestory windows), `cornice`, `colorTop`, or `glassTop` (forced ribbon).
- **Occasional features:**
  - **Vertical blade sign:** 2 to 5 floors, on the widest primary run only, from the first upper floor. Chance ranges from 0% (curtain, louver) to 60% (zakkyo).
  - **Wall-hung AC units:** on every other window.
  - **Balcony rail band.**
- **Cycle offset and accent colour.**

**Primary facade.** This is the direction of the widest run on the lowest upper storey. Runs facing within about 30° of it, and at least 10 studs wide, are primary. Only primary runs carry stacked signs, fascia signs, balconies and the blade. Other runs use the variant's `side` arrangement (D3, H3), so mansions show balconies on one face and punched tile elsewhere. `opts.primaryNormal` can override this with a road-facing normal taken from `GroundFacadeFrontage.Survey`, which is recommended for the rollout.

**Consistency.** The same spec, palette and scales apply on every run and floor. Bays come from the run width, so identical outlines stack into identical columns.

## 4. Geometry contract, corners and narrow runs

**Run frames.** `Kit.PlanBuilding` mirrors `GroundFacadeFrontage.Survey`:
- `Layout.Build(plan, config with inset = 0)`; storey 2 and up only.
- The outward normal and tangent come from the sign of the ring's area.
- `bottom = centre - Y*(size.Y/2 - .15) + normal*.75`
- `frame = CFrame.fromMatrix(bottom, tangent, Y)`
- Height = `size.Y - .3` (the clear height); runs outside 8..30 are skipped and listed in the report.
- Each floor-run covers its own floor slab edge with the floor band (`options.slab = levels[storey].thickness`).
- The top storey also covers the roof slab (`options.cap`) and adds a coping or cornice.

**Depth layers** (all exterior rear faces at Z ≤ .45):

| Layer | Z range |
|---|---|
| Walls and bands | -.25..+.35 |
| Glass (`Mount.PaneZ` .15, .18 thick) | .06..+.24 |
| Mullions | -.2..+.16 |
| Recessed infills | +.2..+.4 |
| Fins, louvers, parapets, signs | front no further than -.6 |

**Corners.** Each run end is matched to its neighbour in the same storey and piece, by shared endpoint. The run is then lengthened or shortened so the two .75-stud stand-off planes meet:
- Convex corners get the meeting point plus .3, so the outer faces close.
- Concave corners are trimmed back.
- The adjustment is clamped to -2..+3.
- The overlap is absorbed by widening that end pier (`cornerLeft` / `cornerRight` = extension + .6), so glass never sits inside a neighbour.

**Narrow and short runs:**
- Width under 6 becomes one solid panel.
- Width under the variant's `minWidth` uses the family's quiet variant.
- An opening under 2.5 high, or end piers that take up the run, becomes a solid panel.
- Layout `parapet` strips (storey edges not covered by the slab above) get one `UpperParapet` part.

**Tags and attributes:**
- Every part is Anchored, `CanTouch = false` and tagged `NoCSG`, with `FacadeLayer = "exterior"`.
- Opaque parts have `FacadePieceKind = "wall"`. Their finer role (`wall`, `trim` or `sign`) is in `FacadeUpperRole`.
- Glass has `FacadePieceKind = "glass"`, goes through `GlassVisual.Capture`, and is tagged `GlassPane` with `GlassPaneId = key.."/bay"..i.."/pane"..j`. The key is `SourceSliceId/storey/piece/run`.
- Trim, signs and glass have `CastShadow = false`. Only walls and glass collide.

## 5. Performance budget

These are parts per floor-run at width 40 and height 12.5, hand-computed from the layout rules. The self-test prints the measured values.

| Variant | Parts | Per 10 studs | Variant | Parts | Per 10 studs |
|---|---|---|---|---|---|
| A1 | 19 | 4.8 | E1 | 23 | 5.8 |
| A2 | 24 | 6.0 | E2 | ~14 | 3.5 |
| A3 | 19 | 4.8 | E3 | 21 | 5.3 |
| A4 | 15 | 3.8 | F1 | 35 | 8.8 |
| B1 | 15 | 3.8 | F2 | 13 | 3.3 |
| B2 | 34 | 8.5 | G1 | 37 | 9.3 |
| B3 | 24 | 6.0 | G2 | 22 | 5.5 |
| C1 | 13 | 3.3 | G3 | 20 | 5.0 |
| C2 | 15 | 3.8 | H1 | 19 | 4.8 |
| C3 | 27 | 6.8 | H2 | 25 | 6.3 |
| D1 | 20 | 5.0 | H3 | 18 | 4.5 |
| D2 | 9 | 2.3 | I1 | 15 | 3.8 |
| D3 | 18 | 4.5 | I2 | 13 | 3.3 |
| D4 | 26 | 6.5 | J1 | 24 | 6.0 |
| | | | J2 | 28 | 7.0 |

- Every variant is under the target of 12 per 10 studs. The self-test fails anything over 14.
- Optional features add per run: blade +2, rail +2, AC +1 per two bays, fascia sign +2, crown +1.
- Each run has fixed overhead of 4 parts (floor band, head band and 2 end piers).
- Bands and louvers are one part per floor-run, and ribbon transoms are a single run-wide bar. Glass is one part per pane, which pane identity requires.

**Scale warning.** A 6-storey building with 13 runs per storey comes to about 1,500 to 2,500 parts. Across about 2,000 ordinary buildings that is 3 to 5 million parts, well beyond what the place can hold (it already has about 626k facade parts). A city-wide rollout needs the client-side near-radius build described in `UPPER_FACADE_APPROACH.md`, reusing `Kit.Layout` rows, which are pure data. Edit-time `BuildBuilding` is for small trials (3 buildings first, as the approach doc says). Medium-range merging can join each run's coplanar bands and piers into about 3 parts without changing the silhouette.

## 6. API

- `Catalog.Pick(seed, class)` returns a style. The pieces are also available separately: `PickFamily`, `PickVariant`, `PickPalette`, `Classify`.
- `Catalog.Get(id)`, `Catalog.Palette(nameOrTable)`, `Catalog.Mat(name)`.
- `Kit.Layout(width, height, spec, options)` returns pure part rows.
- `Kit.BuildFloorRun(parent, frame, width, height, spec, options)` returns a Model.
- `Kit.PlanBuilding(model, opts)` returns a pure plan (style, runs, parapets, skipped).
- `Kit.BuildBuilding(model, opts)` returns `(Folder "UpperFacade" with Owner = "upper-facade-v1", report)`.
  - Options: `family`, `variant`, `palette`, `style`, `class`, `primaryNormal`, `minStorey`, `replace`.
  - It replaces only a folder this kit owns.

Self-test: run `tools/verify_upper_facade_kit.luau` in the command bar (Edit mode, after a Rojo sync). It covers every variant, every crown and every palette, plus a synthetic stepped L building at Y 20000 that is destroyed afterwards. It returns a report and prints PASS or FAIL.

## 7. Open questions

1. `GlassGeometry.GeneratedEnabled` and the glass damage services only recognise the ground-pilot owner. Upper panes are tagged `GlassPane`, but damage routing for `Owner = "upper-facade-v1"` is not wired yet.
2. The primary face should come from the frontage survey's road data instead of the widest run.
3. Should glass get the dark `InteriorWindowBacking`? It is currently omitted, and the glass is near-opaque instead.
4. `CeramicTiles` and `Plaster` texture scale may read too coarse or fine at city distance. Swapping to Concrete is a palette change.
5. Layout's level-curve outlines shift slightly per floor, so the bay columns may step a little. Snapping widths per piece would be a later refinement.
