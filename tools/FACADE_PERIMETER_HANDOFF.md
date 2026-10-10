# Ground facade perimeter trial — October 10, 2026

> **Superseded location/coverage:** the latest two-photo feedback is handled in `FACADE_FLAT_TRIAL_HANDOFF.md` (v5). The western trial below has been archived and replaced by 42 full-height ground runs on three buildings near the selected ordinary building toward 109. Two explicitly authorized local terrain pads were corrected. V4 counts and no-terrain claims below are historical.

This is the current truth document for the owner's six-photo feedback. Read `src/client/ProjectFiles.luau`, then this file, `GROUND_FACADE_HANDOFF.md`, `GLASS_SYSTEM_HANDOFF.md`, and the October 6 terrain wrap-up in `SHIBUYA_SOURCE_SLICE_HANDOFF.md`.

## Accepted requirements

- Add 15 physical styles before replacing the city test; total 53. Include quiet grey walls, modest windows, service elevations and Tokyo small businesses.
- Vary Japanese business identities separately from architectural seeds. At least 50 category-compatible business labels; preserve McDooDoo's, Smash King and Starboys identities.
- Ground whole planter assemblies, including foliage. Raised building slabs must not make planters float.
- Existing roads and pedestrian routes establish plausible frontages. Neighboring buildings establish clearance. Confined gaps receive quiet walls, never shop signs or entrances.
- Open parking requires verified empty interior depth. Preserve cores; use a closed treatment when obstructed.
- Replace scattered one-face pilots with a compact cluster of complete exterior ground perimeters. Keep each building's wall palette consistent.
- Preserve terrain, OSM road geometry, structures, cores, crowns, generators and destruction behavior. Glass remains an explicit pilot trial.

## Approach

`GroundFacadeFrontage` surveys actual saved ground polygons in their current world frames. It uses existing `Workspace.Roads` parts and their RoadClass/RoadWay metadata, including pedestrian/service routes; it does not rebuild OSM. No sidewalk instances are assumed. Neighbor occupancy is sampled along each exterior run. Six-stud-or-smaller clearances are blind walls; restricted gaps below twelve studs stay quiet. Fronts need an outward road within 75 studs, a clear connection, adequate width and verified terrain/road ground. Unknown access stays quiet. Portal approaches are checked again at individual bay positions.

`GroundFacadePilot` owns removable children and a multi-run manifest. Exact source exterior run lengths are covered; shared/internal edges remain omitted by FacadeLayout. Shallow parapets receive shallow infill. The chosen building palette carries around its perimeter. Stock draft geometry remains separate from site footing, entry steps and planter grounding.

This remains a conservative draft classifier: geometric clearance does not identify real tenancy or public access rights. Whole-height neighbor footprints deliberately err toward quiet walls. Parking is vetoed by actual structural/core overlap behind the proposed opening. No core is carved to make the art fit.

## Naming and styles

See `FACADE_NAMES.md` for 79 Japanese labeling records and 32 stems (2,528 compositions), compatible pools and independent name seeding. See `FACADE_STYLE_EXPANSION.md` for styles 39–53 and the prop-support contract.

## Verification and recovery

Survey, selected manifest and final verification are saved under `tools/source_slices/facade_perimeter_*`. Previous pilot children and registry are archived under `ServerStorage.GroundFacadePilotArchive` before replacement. Gallery/library upgrades archive previous revisions. The owner-placed `Workspace.SpawnLocation` remains at (11,1600.45,-17.75), and the gallery glass demo is retained.

Installed cluster, all within approximately 145 studs of the lime-marker survey centre:

- `fbx_9_-15603_1695_4366`: cream perimeter, Starboys main street face, bookshop on its accessible secondary street face, quiet confined sides; 19 exterior runs.
- `fbx_9_-16128_2013_4831`: grey perimeter, one clear open parking bay and quiet walls/windows; 11 runs.
- `fbx_9_-16556_1738_5184`: stone perimeter, laundry and bicycle workshop facing existing roads; 8 runs.

The lime beacon remains near **(-1627,98,388)** and labels three complete perimeters. Magenta marks the raised gallery at **(250,1600,-100)**. The gallery has 53 physical sample models; its stitched rows and street view moved beyond the added rows to prevent overlap. Library: 2,410 parts across 53 reusable templates, saved in `assets/GroundFacadeDraftLibrary.rbxmx` and the rebuilt `assets/GroundFacadeDraftsPreview.rbxlx`.

Semantic Studio checks passed: 38 covered exterior runs, six entrances with road/clearance proof, one parking portal with clear actual 22-stud depth, one grounded planter assembly, 106 forbidden-entry quiet-role cases and 500 deterministic naming cases. Geometry contracts passed 954 size/mirror layouts, 318 portal cases and 112 composition widths, including 53 distinct physical signatures. Name-seed changes alter sign text without changing part transforms/sizes. XML/Rojo export checks retain all shapes, text, pivots, glass attributes and tags.

1,566 pre-existing original parts in the nearby survey buildings retained exactly their instances, transforms and sizes. The live city still has 2,227 buildings and 1,037 road parts. No terrain/road/generator/hit-system edits were made for this task. `facade_perimeter_verification.json` and `facade_perimeter_geometry_tests.json` record the checks. The original-part comparison uses this edit session's `_G.FacadePerimeterOriginal` baseline; a future session needs a fresh baseline before replacement.

Native Play verification passed: outside the trial, zero generated near/far facade groups; inside, exactly three eligible/built groups with 1,040 current pooled-renderer parts and zero far proxies. Proof: `facade_perimeter_native_play.json`. This confirms scope and runtime reconstruction, not device FPS. Viewport capture timed out, so no fresh visual screenshot has been certified. Studio is left in Edit mode, with the camera facing Starboys and the lime beacon selected.

## Performance and next steps

The 756-part physical perimeter trial is deliberately small; the ServerStorage reusable library is not replicated into every building. Quiet sides reduce glass and advertising density. Only the three selected buildings get the temporary upper-floor glass/LOD trial. Existing budgets, pane partitioning, sparse damage state and disabled far proxies remain intact.

Before wider deployment, derive consistent per-building facade families from these seeded plans. Keep cheap opaque wall/window silhouettes at distance, reconstruct mullions, ads, planting and crack overlays near the camera, and retain authoritative damage/collision state independently of client detail. Do not repeat the old city-wide glass rollout. Normal-floor design and a whole-city FPS/device benchmark remain future work.

The live city edits and archives are in the open Studio session; **save the Studio place to retain them**. Local source, manifests and the portable 53-template library/preview have been saved. No place publication was performed.
