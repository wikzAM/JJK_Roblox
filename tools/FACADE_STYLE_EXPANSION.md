# Ground facade physical expansion — October 10, 2026

Catalog version 4 contains **53 physical types**, preserving types 01–38 and adding
exactly 15. This document describes kit geometry and placement metadata. The current
city selection and perimeter access rules belong to the ground pilot/frontage handoff.
It does not authorize any terrain, road, generator, core or structure changes.

## New physical layouts

- **39 PlainConcrete:** uninterrupted grey concrete; accepts 2–48 stud widths.
- **40 PanelSeams:** opaque concrete with vertical and horizontal panel joints.
- **41 HighSlit:** one high privacy window with a projecting rain hood.
- **42 PairedFrost:** two small frosted windows and independent concrete sills.
- **43 UtilityWall:** opaque rear wall, vent louvers and a clamped drainpipe.
- **44 RearSteelDoor:** a small steel service door and separate high transom.
- **45 TiledBoundary:** quiet tiled wall, inset window, low ledge and coping.
- **46 Laundry:** split transom band, offset entry and washer display geometry.
- **47 BicycleRepair:** partially lowered workshop shutter and separate repair window.
- **48 Florist:** projecting green canopy, timber posts, flower shelf and grounded planter.
- **49 Clinic:** opaque privacy spandrels, frosted windows and small entry canopy.
- **50 Bookshop:** deep book display sills/shelves and brick pilasters.
- **51 SobaShop:** high opaque window sill, timber lattice and narrow four-panel noren.
- **52 Bathhouse:** tile piers, split curtains, wider opaque entry and shallow canopy.
- **53 TimberHouse:** projecting timber privacy screen, high sill and quiet inset door.

Types 39–45 have `signless=true`: even a supplied business name does not create a
retail fascia. Type 44 creates its service door only in an explicitly allowed entrance
role. Quiet and public layouts use the normal 10.5–24 stud height contract. Existing
34/35 tall types retain their opt-in two-storey/confirmed-void contracts.

## Frontage roles and coherent appearance

`Kit.BuildRun(..., options)` supports `allowEntrance=false`, `role="window"` and
`role="blind"`. Every bay obeys these rules, including parking/loading/produce types.
Window roles contain no door, portal, public sign, menu board or entry fixture. Old
retail types become quiet wall/window continuation bays. Blind roles contain no
glass; suitable panel/utility types keep their opaque architectural details.

Profiles `blind`, `window`, `backStreet` and `tokyo` are deterministic weighted
selections. Road visibility alone does not establish access: the city planner must
also check outward clearance, entrance approach and an actual interior void before
choosing an open parking/loading front. `backStreet` does not force an entrance.

`options.palette` overrides the full bay palette so a building can use the same wall
and trim colors around its perimeter. Quiet grey uses the game's concrete color
RGB(163,162,165). Existing chain identity accents remain intentional exceptions.
`mainBay` (alias `portalIndex`) chooses the coordinated entrance for office, hotel,
residential, chains or tall run profiles. It must reference an existing bay. A run too
short for a proper tenant receives one plain infill instead of a compressed doorway.

## Stable names and support metadata

`Catalog.Brand(id,key,nameSeed)` uses `GroundFacadeNames.Generate`. The optional
name seed does not alter geometry, door placement or ads. Fixed fictional chain
identities remain fixed. `BuildRun` accepts `options.nameSeed` and `options.brand`.
The names module curates compatible Japanese business nouns and proper-name stems;
blank walls never receive those public labels.

Each built bay stores `FacadePalette`, `FacadeRole`, dimensions and JSON
`FacadePortals` (x, width, y, height, recess, name). This lets the planner inspect actual
entry/open-bay bounds rather than assume the entire face is traversable.

Planter boxes and their greenery share a bay-local `FacadeSupportGroup`. Only the
box has `FacadeSupportBase=true`. Its scalar attributes `FacadeSupportLocalX`,
`FacadeSupportLocalBottomY` and `FacadeSupportLocalZ` locate the contact point in the
bay pivot's coordinate system. Mirroring also mirrors that contact point. Scalar
attributes survive the existing library JSON/RBXMX exporter.

The placement pass must move **all parts in the support group together** to the
ground, or add an explicitly supported facade-only plinth. Do not lower the foliage
alone. Default boxes begin at local Y=0 so gallery placement stays grounded. Raised
city slab heights require a separate measured support pass; plinth hiding does not
by itself ground the planter.

## Verification

Run the existing `tools/verify_ground_facades.luau` against fresh modules. It checks
all type fit extremes and heights, mirrored bounds, deterministic replay, physical
uniqueness, entry clearance, exact stitched spans, NoCSG/stock flags and independent
ad variation. Additional perimeter checks should verify every forbidden-entry bay
has no portals/signs/doors, blind bays have zero glass and each support group has
exactly one contact base. Studio verification results are recorded by the main task.

Fresh Studio geometry contracts passed on October 10: **954 fit/height/mirror
layouts, 318 entrance cases, 112 profile span cases and 53 unique physical designs**.
The final gallery/stock and city placement checks are recorded by the main task.

All structural outlines, terrain, roads and original cores remain outside this kit.
Static draft doors are noncollidable visual portals; this expansion does not add an
interactive sliding-door mechanism.
