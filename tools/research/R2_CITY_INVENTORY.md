# City inventory and migration map (2026-10-19, read-only census in Edit)

## What the place is made of

- Instances: 1,140,921 in total. Buildings: 1,941, averaging 4.4 generated floors.

| Category | Parts | Share of building parts | Notes |
|---|---|---|---|
| Ground facades (opaque) | 607,279 | about 70% | GroundFacadePilot roots |
| Ground facade glass panes | 46,128 | about 5% | GlassPane-tagged |
| Floor slab WedgeParts | 140,288 | about 16% | Irregular outlines are triangulated: about **13.4 pieces per level** on average |
| Floor slab Parts | 18,335 | about 2% | |
| Interior, other (cores, etc.) | 27,305 | about 3% | |
| Crowns, rooftop | 9,676 | about 1% | |
| Other building parts | 16,709 | about 2% | |
| Bay interior Edit previews | 297 | — | |

Parts per building:
- p10: 134
- median: 313
- p90: 850
- max: 29,907 (`Building1`, the WorldSetup test building with BuildingGenerator furniture: about 3% of all building parts by itself)

The 50 heaviest buildings hold 131k parts. They are tall towers with long facades, many with more than 1,000 slab wedges.

## Implications for the 10–25 parts per building target

- The ground facades are about 75% of the problem. Baking them to textures, plus a small near-player part version, is the largest lever.
- Slabs are the second lever. About 13 wedges per level must become 1–3 pieces per level, either rectangular shells or a merged MeshPart per floor if MeshParts prove carvable or acceptable.
  - A 5-floor box building costs about 6 slab pieces plus 6 core walls plus about 4 skins plus about 8 piers, roughly 24 parts. That is inside the target.
  - Towers need merged meshes or floor-band skins, not per-floor geometry.
- `Building1` (29,907 parts) should spawn only in test mode, or be slimmed.
- Crowns at about 10k are cheap to merge per building.

## Code systems that a texture/skin migration touches

Counts are references to GlassPane, GroundFacadePilot, FacadeInteriorBay, UpperFacade or GlassDamage.

| File | Lines | Role today | Fate in the plan |
|---|---|---|---|
| server/GroundFacadePilot.luau | 460 | Builds part facades from manifest rows | Keep as the part-version and bake-source builder |
| shared/GroundFacadeKit.luau, GroundFacadeCatalog.luau | 442 + | 50+ designs | Bake source; keep |
| server/GroundFacadeSurfaceResolver.luau | 246 | Coplanar trims | Simpler with skins (one skin per face) |
| server/GlassDamageService.luau | 219 | Per-pane damage state (physical and logical) | Keep. Becomes logical-first: crack overlays, CSG pane holes |
| shared/GlassVisual.luau, GlassGeometry.luau | 139 / 68 | Pane visuals | Adapt to overlay parts and skin holes |
| server/GroundFacadeBayInteriors.luau + client/GroundFacadeInteriors.luau | 162 / 91 | Pseudo-3D bay rooms | Keep for the part-version zones only (main streets, near the player) |
| client/UpperFacadeRenderer.luau + shared/UpperFacadeKit.luau | 179 / 370 | Tear-down/rebuild prototype | Replace with baked skins; the kit becomes a bake source |
| client/FacadeRenderer.luau | 334 | Older v1 strip renderer | Retire after migration |
| server/HitHandler.luau | 1,329 | Hits and CSG | Fixes A/B; later the timeline system |
| server/UpperFacadeHits.luau | 26 | Hit capsule log | Generalize into the hit timeline |
| server/GroundFacadeCompact.luau, ObsoleteFacadeSnapshotCleanup.luau | — | One-off tools | Retire |

## Map extents (Edit census, 2026-10-19 overnight)

- **Footprint:** 1,941 building models span X −3,155 to 3,235 and Z −2,603 to 3,431, which is **about 6,400 × 6,000 studs** (about 1.5 × 1.4 km at this map's scale of 0.2391 m per stud, per the handoff docs). The diagonal is **about 8,800 studs**.
- **Heights:** the tallest roof is at Y ≈ 967. Building heights are p50 74 studs, p90 154 studs, max 910 studs.
- **Pacing implication:** "anywhere within about 20 s" means crossing about 6,000 studs (edge to edge) or about 8,800 (corner to corner). That is an average of **about 300–440 studs/s** including fighting and detours. In practice it calls for long-range movement of about 600+ studs/s, or teleport-tier abilities.

## Footprint shape census (2026-10-21, read-only)

**Method:** for each building, take the `Slab` parts per level (WedgeParts use their true triangle). Build the convex hull of the largest level, then the minimum-area rotated rectangle around it (rotating calipers). "Fill" is slab area ÷ that rectangle's area. Slabs are 5.36 studs thick.

| Fill vs best rotated rectangle | Buildings | Avg levels | Avg slab pieces per level today | With setbacks |
|---|---|---|---|---|
| ≥ 95% (effectively a rectangle) | **1,015** | 5.1 | 8.8 | 395 |
| 90–95% | 230 | 5.1 | 14.2 | 100 |
| 80–90% | 308 | 5.7 | 17.6 | 167 |
| < 80% | 388 | 6.3 | 19.8 | 176 |

- **Over half the city (1,015 of 1,941) is effectively rectangular**, yet each of those levels uses about 9 slab pieces. One box per level would do, or one box per run of identical levels.
- **About 64% (1,245) are at least 90% rectangular, and about 80% (1,553) at least 80%.**
- **1,571 buildings are convex** (slab area ≥ 95% of the hull). They can be one rectangle plus a few corner wedges per level, the "big rectangle + wedges for the perimeter" idea.
- **838 buildings have setbacks** (some level under 90% of the largest). Treat them as a stack of boxes, one per distinct footprint band.
- `Building1` (Shibuya Sky tower, 910 studs tall) has no shell. All 29,907 parts are inside `Interior`: 29,584 `NoCSG` furnishings (furniture, lights, carpet, office walls, 6,400 unions, 590 MeshParts) plus slabs and 276 core walls.
