# Glass and ground facade handoff — October 8, 2026

> **Current v6:** [FACADE_SECTION_HANDOFF.md](FACADE_SECTION_HANDOFF.md). 32-building ground section, 175 physical panes; generated upper glass disabled, zero near/far curtains. Four native states and LOD persistence verified, with 16 transient shard rows per building event and full state pages. Earlier trial counts below are historical.

> **Latest v5 ground trial:** see `FACADE_FLAT_TRIAL_HANDOFF.md`. Glass now admits the three NEW trial buildings near the selected building toward 109; all 42 exterior ground runs are owned. Native Play confirmed 0 generated facades outside the new trial, 3 inside, no far proxies. Glass states/damage are unchanged. The 38-run western trial below is historical.

## Latest October 10 — compact complete perimeters

The 14 scattered pilots described below are superseded by **three neighboring
buildings with 38 complete ground perimeter runs**. See `FACADE_PERIMETER_HANDOFF.md`.
GlassGeometry retains the same explicit owner/owned-run gate; it now admits
those three buildings only. No far proxies or city-wide rollout. Ground run
ownership covers all exterior runs, suppressing generic ground curtain glazing.
Upper glass remains a temporary trial on the same three. Glass states, damage
bands, demo and particle behavior are unchanged by the perimeter work.
The 53-type gallery/library is revision 4. Existing gallery demo and owner spawn
were retained. Cached-safe edit runtime: `ServerStorage.FacadePerimeterRuntime`.

## Earlier October 10 — scope and locator update

The previous renderer admitted every source-slice building. Its far tier used
opaque SmoothPlastic panels in a glass tint, causing the coloured-panel-to-glass
appearance the owner reported. That rollout exceeded this ground-floor trial.
**Current policy: only the 14 existing owned pilot buildings receive generated
glass; no opaque far proxies are created anywhere.** The gallery and physical
ground storefront glass stay in place. Upper glass inside those 14 buildings is
temporary damage/LOD test geometry, not approved facade art for every floor.

`GlassConfig.GeneratedFacadeScope="groundPilot"` requires an owned
`GroundFacadePilot` child and `GroundFacadeOwnedRuns` metadata.
`GlassGeometry.GeneratedEnabled` gates both construction and logical damage.
The renderer retains only eligible build candidates; direct near/far build helpers
also enforce the gate, and eligibility changes remove queued/active geometry.
`FarProxyEnabled=false` disables the old coloured approximation. Near/detail
pooling and state persistence remain; current material stays real glass rather
than switching to an opaque tinted proxy. An explicit future `"city"` setting is
available, but must not be enabled as part of routine ground-front testing.

HitHandler calls `GlassDamageService.DestroyPath(start,end,HOLE_RADIUS)`.
The structural cutter is unchanged. Glass touching the cutter **or its next
12 studs** is removed (state 4), clearing unsupported panes beside the opening.
The **following 12 studs** cracks (state 2); farther panes remain unchanged.
These are closest-distance-to-pane bounds, so a pane intersecting the removal
zone is removed whole. Ordinary impacts/shockwaves still support state 3.
Tunables: `DestructionClearance=12`, `DestructionCrackBand=12`.

Two noncollidable Neon locator Parts are in `Workspace.FacadeTestMarkers`:

- **Lime_CityFacadeTestArea:** 900 studs tall, base approximately
  **(-1627, 98, 388)**, beside the Starboys frontage in the city pilot.
- **Magenta_GalleryDemo:** 500 studs tall, base **(250, 1600, -100)**,
  beside the raised facade gallery and independent glass demo.

Select either named Part in Explorer and press **F** to frame it. The city camera
was left looking toward the lime marker. Edit-only helpers:

```lua
require(game.ServerStorage.FacadeScopeRuntime.FacadeTestMarkers).FocusCity()
require(game.ServerStorage.GroundFacadeDraftRuntime.GlassDemoDrafts).Focus()
```

Fresh source helpers live at `ServerScriptService.Server.FacadeTestMarkers`.
`Generate()` is ownership-checked and replay-safe; no startup marker generator
was added. `FacadeScopeRuntime` contains fresh config/geometry/damage modules
for this Studio session, avoiding cached older edit-time requires.

The live city had **2,227 buildings before and after** this task: 14 eligible,
2,213 excluded. This reflects owner changes since the Oct 8 snapshot. No terrain,
roads, generators, original structure or stock facade art was altered here.
`tools/verify_glass.luau` now checks allowlist ownership and the removal/crack
margin in addition to the existing state/distance/persistence contracts.
Native Play scope checks: `tools/verify_facade_scope_live.client.luau`.
The final Play run passed: at the crossing viewpoint **0 near / 0 far** models;
at the Starboys viewpoint **13 near models / 1,130 generated Parts / 0 far**,
all from the 14 eligible buildings. One pilot was outside the current near radius.
Proof: `tools/source_slices/facade_scope_verification_2026-10-10.json`.

Before broader facade rollout, define physical families for each building/floor,
including opaque residential/service walls. LOD should simplify subdivisions and
small signage while preserving material, opening placement and silhouette.
Avoid allocating panes server-side for the whole city; retain stable logical
damage and budget local geometry/shards. Current checks measure scope/geometry,
not device FPS. October 8 historical measurements and commands below are context;
the temporary city-wide/far-tier policy there is superseded by this section.

Read `src/client/ProjectFiles.luau` first, then this file and
`GROUND_FACADE_HANDOFF.md`. The Oct 6 **TERRAIN WRAP-UP** in
`SHIBUYA_SOURCE_SLICE_HANDOFF.md` remains the ground authority: flattened city,
terrain DONE. This work changes facades and their glass, plus the glass-only hook
in HitHandler. Terrain, roads, generators, original slabs, cores and crowns were
not edited. TestJJK place ID: **99539622209675**. Studio place save is still needed.

## What is in Studio

- `Workspace.GroundFacadeDraftGallery`: revision 3, **38 physical types**.
- `ServerStorage.GroundFacadeDraftLibrary`: **38 templates / 1,808 Parts**,
  with stable glass IDs, baseline attributes and `GlassPane`/`NoCSG` tags.
- `GroundFacadeDraftGallery.04_GlassDemo`: beside the existing deck, with a
  walkway from near the owner's raised spawn point. Four static states, a wide
  shattered sample and an automatic looping sample. **Press Play; no attacks or
  clicks are needed.** Each state lasts four seconds. The loop restores itself.
  In Studio only, it places the viewer on the demo deck if the existing startup
  code spawns them more than 500 studs away. Set `AutoPlaceViewer=false` on the
  demo folder to disable that convenience. The owner's spawn was not moved.
- **14 small city buildings** have one owned ground-frontage run each, in the
  western neighbourhood around X=-1700, Z=700. **1,011 added Parts / 101 panes**.
  Chains, Japanese shops, residences, concrete service fronts and open garages.
  Crossing exclusion radius: 1,200 studs around X/Z origin; protected crown IDs,
  interesting crowns and landmarks were excluded during selection. Original
  building Parts and total building count (**2,229**) were checked unchanged.
- `ServerStorage.GroundFacadePilotManifest`: exact reversible pilot manifest
  and report. No city-wide automatic application has been added.
- `ServerStorage.GroundFacadeDraftRuntime`: fresh dependency group for edit-time
  requires; older draft galleries, libraries and runtimes are archived under
  `GroundFacadeDraftArchive`. Previous live glass sources are preserved under
  `GlassDraftRuntime.PreviousLiveSources`.

## Four states

1. **Intact:** baseline tint/transparency/reflectance; window collision on.
2. **Cracked:** same collidable pane, real crack texture on both faces.
3. **Shattered:** **base Part Transparency=1, Reflectance=0, CanCollide=false**.
   Only a thin jagged image border remains visible; the centre is truly empty.
   Frost/privacy overlays and window stickers are hidden as well.
4. **Removed:** the Instance is destroyed. Its logical state remains a tombstone
   so moving away, changing LOD or joining later cannot restore the pane.

State changes are monotonic damage until an explicit repair. `Reset` repairs
remaining physical panes and logical cells but cannot recreate deleted Instances.
Rebuilding the owned kit recreates those. Prototype doors are traversable static
visuals; their glass also breaks, but keeps its existing noncollidable baseline
in states 1/2. Working open/close door mechanics are a separate future feature.

## Modules and integration

- Shared `GlassConfig`: states, uploaded asset IDs and tuning.
- Shared `GlassVisual`: baseline capture, crack overlay, cropped edge overlay,
  hidden films/stickers and pooling cleanup. Uses current `ColorMapContent`
  with compatibility fallback for textures. No guessed decal conversion IDs.
- Shared `GlassGeometry`: exact segment-to-oriented-box distance and stable
  logical pane partitioning in X **and Y**, with cells at most 12 × 12 studs.
- Server `GlassDamageService`: trusted attack APIs and sparse authoritative
  state. Logical upper glass requires no saved server Parts. Physical ground
  panes use server collision/query state. Physical panes are indexed lazily
  rather than scanning every building descendant on every subsequent hit.
- Client `FacadeRenderer`: camera-bound near/far geometry, persistent snapshot
  reconstruction, local collision for upper windows, local overlays for physical
  ground panes. `GroundFacadeOwnedRuns` prevents a generic glass strip being
  generated across a storefront doorway. Adding an owned facade does not change
  the building's structural `FacadeVersion` or invalidate upper pane IDs.
- Client `GlassShards`: bounded, short-lived local ParticleEmitter bursts.
- `GlassDemoDrafts` / client `GlassDemo`: review display and independent loop.
- Edit-time `GroundFacadePilot`: manifest-driven add/clear/focus. Places along
  actual plan polygon runs using the current moved/flattened frame, not a bounding
  box. Adds small entry steps, garage ramps and facade footing where needed.

HitHandler now calls `GlassDamageService.Capsule` along the existing destruction
path, with the existing **50-stud HOLE_RADIUS**, a six-stud cracked perimeter and
state 4 in the direct path. Its teleport sequence, dust masking delay, CSG,
terrain carving and ragdoll tracking remain unchanged. The old capped 256-hit
facade replay is replaced by per-pane snapshots; old legacy event/folder objects
are not deleted from the authored place.

## Trusted server APIs

```lua
local Glass=require(game.ServerScriptService.Server.GlassDamageService)
Glass.Init()
Glass.Impact(position, velocity, {radius=1.5, shatterSpeed=65})
Glass.Shockwave(position, {shatterRadius=20, crackRadius=45})
Glass.Capsule(startPosition,endPosition,{radius=4,crackBand=8,state=2})
Glass.Capsule(startPosition,endPosition,{radius=12,crackBand=6,state=4})
Glass.SetPane(building, paneKey, 3, physicalPane)
Glass.Reset(building)
```

`Impact` below 65 studs/s cracks; above it shatters. This threshold is initial
art/gameplay tuning, not a real-world simulation. Attacks can specify state 2
for a heat/shock path and a separate shockwave/explosion afterwards. `models`
may restrict any capsule/impact/shockwave to explicit targets for testing.
`RepairRun` clears only an owned ground prefix when the pilot is rebuilt.

There is **no client-to-server glass damage remote**, and no per-pane Touched
loop. Future combat/projectile/contact systems must call these trusted APIs;
automatic weak player/object collision detection and Sukuna attack implementation
are not added here. Upper glass is client collision geometry, so server projectiles
must use this logical geometry/API rather than expecting saved upper glass Parts.

## Performance and damage persistence

- Sparse damaged cells are stored in `ReplicatedStorage.GlassDamageState` under
  stable building IDs, hashed into up to 64 pages. Only touched pages change.
  New clients read snapshots, not an ever-growing hit history. Geometry-version
  changes clear old pages. Destroyed/removed buildings clean up their state.
- Near build radius 700, drop radius 850 studs. Individual panes and damage
  textures inside 220 studs; detail drops at 260 to avoid thrashing. Outside
  detail range, intact runs are strips, damaged runs retain their logical holes.
- Coarse far shell radius 1,700, drop 1,900, replacing the historical all-city
  permanently loaded far shell. Far panels intersecting a destroyed cell are
  omitted conservatively, so distant glass does not heal. This can hide more
  facade than the exact hole; near geometry remains precise.
- Soft 2 ms work budget, coroutine yields every 24 created Parts, build pause
  above 400 studs/s, pool cap 1,800. Initial plan decoding/one chunk can exceed
  that soft budget; this is not a measured frame-time guarantee.
- Shards: **48 particles per building damage event**, **192 live per client**,
  distance culled outside 220 studs, maximum three-second lifetime. Demo burst:
  36, with distance culling bypassed only for the review demo. The global cap still
  applies. No unanchored or replicated shard Parts. A transparent noncollidable local
  emitter holder is cleaned up after the burst.
- Particle gravity, speed, spin and pale glass sprite suggest falling shards.
  Particles do not collide with pavement. One downward ray per emitter estimates
  a shorter fade lifetime near the ground; landing is approximate.
- No distance-based server building streaming and no permanent particle emitter
  on every window. The ordinary game does not allocate the entire city as panes.

The uploaded shattered texture uses **1024-pixel crop coordinates**, although its
preserved generated original is 1254 square. Fixed-width borders and corner crops
avoid stretching an entire square hole over a long pane. Texture drafts can still
be polished for less visible repeated patterns. Asset provenance and prompt briefs:
`assets/glass/README.md`.

## Review, rebuild and undo

Fresh edit-runtime commands (avoids Studio require caching):

```lua
local R=game.ServerStorage.GroundFacadeDraftRuntime
require(R.GlassDemoDrafts).Focus()
require(R.GroundFacadePilot).Focus(4) -- Starboys neighbourhood sample
require(R.GroundFacadePilot).Clear() -- owned facade children/metadata only
```

Reapply using `tools/source_slices/ground_facade_pilot_manifest.json` as the
decoded argument to `Pilot.Apply`. Drafts.Generate builds the gallery; run
GlassDemoDrafts.Generate afterwards to append its display. City pilot is edit
time only, and no terrain/building generator is called by either module.

Local assets: `GroundFacadeDraftLibrary.rbxmx`, `GroundFacadeDraftsPreview.rbxlx`
and **`GlassDemoPreview.rbxlx`**. The last is a small standalone demonstration
place with only glass assets/demo scripts, no HitHandler, terrain or city generator.
Do not replace the open unsaved city with a preview file without saving it first.

Builds:

```powershell
rojo build tools/ground-facades.project.json -o assets/GroundFacadeDraftsPreview.rbxlx
rojo build tools/glass-demo.project.json -o assets/GlassDemoPreview.rbxlx
```

## Verification and known limits

Studio contract checks (`tools/verify_glass.luau`): 131 distance cases including
128 randomized comparisons, an exact-area 18-cell partition, all four physical
states, weak/strong impacts, shockwave bands, monotonic damage, paged persistence
and clearing stale geometry-version pages. Facade checks: 684 layout combinations,
228 entrance-clearance cases, 84 stitched profiles; all 38 have distinct physical
designs. Ads have an independent seed. XML and Rojo exports were compared to the
Studio library for geometry, text, pivots, flags and retained glass tags.

Native Play checks and any remaining visual-review limitations are recorded in
`tools/source_slices/glass_live_verification.json` and the final session note below.
Edit state screenshots confirmed the transparent shattered centre and corrected
edge sampling. The city trial remains draft art: most adjacent upper floors are
still grey structural skeletons, authored interiors are sparse, and doors are
static portals. This is not yet a fully dressed street or a measured device/FPS
benchmark. No city-wide rollout beyond the 14-building pilot.

Primary API references checked during implementation:
[Texture](https://create.roblox.com/docs/reference/engine/classes/Texture),
[Decal](https://create.roblox.com/docs/reference/engine/classes/Decal),
[ParticleEmitter](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter).

## Final native Play verification

The automatic sample completed all four states: states 1/2 collidable, state 3
fully transparent and noncollidable with two edge overlays, state 4 absent.
The burst emitted 36 particles and created a local emitter holder. All three
uploaded images fetched successfully. At the Starboys pilot, a strong trusted
impact changed one pane; the client showed two edge overlays, hid all 12 attached
poster pieces and retained a clear noncollidable opening. No generic ground panes
overlapped the owned frontage. The camera-bound renderer built 95 nearby buildings
with 10,804 Parts and 521 coarse far representations at that test viewpoint;
these are geometry counts, not a performance benchmark.

Studio's background window suspended RenderStepped (zero frames in the probe),
so the native verification used a Heartbeat camera override. Final city screenshots
could not be reviewed through the capture tool. The edit-view glass images were
reviewed, but final city appearance needs owner review in the foreground. The
pilot combines red/yellow and timber burger fronts, green coffee fronts, Japanese
shops, restrained homes, concrete and open garage bays against the existing grey
upper structure. Adjacent upper floors/interiors still need dressing.

Play was stopped after verification; test damage reverted to intact Edit panes.
The owner can open the place and press Play to see the independent demo without
using hit handling. Save the current Studio place to retain the gallery/pilot.
