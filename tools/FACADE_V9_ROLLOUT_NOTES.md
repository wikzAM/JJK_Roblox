# Current checkpoint — rollout paused for interior trial

Final reconciled Edit counts after inlet trial:1066 buildings,359743 owned parts,24365 panes.39 shallow inlets and5 garages added376 parts. See FACADE_INTERIOR_TRIAL.md for checks and save limitations. Full city acceptance and Play verification remain pending.

October 16,2026. Owner explicitly requested the trapezoidal/parallax interior trial before further city application, and prohibited computer control while using the browser. Use Studio MCP only.

- Current policy:2091 eligible /132 held, after verifying all157 legacy models and admitting152. Held reasons:protected71,large footprint18,story limit18,landmark/crown22,explicit3.
- Source core changes1657,already clear181,skipped101. Post-source audit before reconnect:1838 clear,zero ready,101 skips. Legacy cores:24 changed,107 clear,21 skipped among152 eligible; final live post-audit pending.
- Both exact saved backup folders persisted across reconnects:source:`FacadeCoreClearanceBackup_4a75ffb8-36f3-4f58-82e0-505ac23e61ea`; legacy:`FacadeLegacyCoreBackup_489f9061-bd61-43a5-8c67-4bb9f047150e`.
- Latest confirmed live geometry:1066 facade roots,988 revision9,359367 owned parts,24365 panes. This is PARTIAL installation, not completion of2091 targets.1103 targets remained to create/upgrade at this checkpoint.
- Team Create disconnected twice (1027/Protocol14). Reopened same TestJJK. Cause unproven; registry property sizes reached Manifest12.5MB/Report7.1MB/Checkpoint19.7MB. New GroundFacadeRegistry stores UTF8-safe <=60000-byte StringValue chunks with atomic generation pointers and legacy-read fallback. Migration completed across25 registries/52 properties. Use Registry.Read/Write for live and archived registry access. Historical verification tools reading attributes directly require adapting before reuse.
- Recovery reconciled1066 actual roots using each root's ManifestRow/ReportRow and legacy checkpoint records. Reconnect erased `_G`; source/legacy backups remain. `recover_facade_v9_baseline.luau` restores historical CORE properties only and starts noncore baseline at reconnect; it cannot prove prior noncore preservation.
- Driveramp preflight now shares exact toe/slope/support calculation with construction; unsafe bays downgrade before build. Old two failed IDs were `fbx_10_-23750_1406_-7887` and `fbx_11_20198_1279_7051`; their replacement still needs live retest.
- Client damage-detail scanning is bounded256 panes/soft.75ms per Heartbeat, preserving immediate state-change handling. No intact-pane rewrite burst; texture detail can lag several seconds across a huge pane population. Needs final Play check.
- Interior trial details and current validation are in FACADE_INTERIOR_TRIAL.md. Do not expand scope until this is reviewed.

The following older ledger is historical; do not treat its1939/284 checkpoint as current.

# Ground facade rollout v9 — acceptance policy and verification notes

October 16, 2026. This document describes the read-only acceptance audit and eligibility rationale. It is not a claim that a rollout, Play test, save or GitHub push has already completed. The final orchestration handoff records those outcomes.

## In-progress ledger — October 16

The following operations are confirmed by the coordinating agent. Final core adjustment, facade installation, geometric acceptance, Play verification, Roblox save and GitHub push remain pending until completion evidence is appended.

- The four owner-selected infrastructure models were moved intact from their original Workspace.Buildings paths into **`ServerStorage.StationInfrastructureArchive.Selected_64885e25-70d4-4926-b845-f52c23fa71f5`**. Their model names/source IDs are listed below. The archive retains their original instances and geometry.
- The new `StationInfrastructureArchive` module supports capture and reconstruction. Reconstruction clones clean infrastructure into `Workspace.StationInfrastructure`, strips generic facade additions from the reconstructed clones, and keeps the original archive intact.
- `Workspace.Buildings` now contains **2,223 children**, following removal of the four selected models from the ordinary-building container. This is a container count, not a claim that every child is an ordinary eligible source building.
- The current city policy census is **1,939 eligible / 284 held**: protected zones 68; large footprint 16; story limit/mismatch 18; explicit exclusions 3; landmark/crown 22; missing source plan 157. The reason categories sum to 284; each held model receives its first applicable policy reason.
- Seven formerly facaded models that are now held had only their owned facade roots moved into `ServerStorage.GroundFacadePilotArchive`. Their original building structure remains intact.
- Style checks covered **53 geometry-neutral facade types, 17 palettes and six fonts**. A 1,000-name sample produced **802 Japanese-only / 198 bilingual** signs. These are variation-check results, not final city label counts or proof that every Japanese glyph renders correctly.
- The core clearance audit exposed a float32 precision issue, which was corrected. Core audit/adjustment is rerunning. The full `SelectCity` frontage survey is underway; the city-wide facade upsert has not yet completed at this ledger checkpoint.

To reconstruct the selected station/walkway geometry later, run in Edit mode:

```lua
local archive = game.ServerStorage.StationInfrastructureArchive
local source = archive:FindFirstChild("Selected_64885e25-70d4-4926-b845-f52c23fa71f5")
assert(source, "Missing selected infrastructure archive")
local Infrastructure = require(game.ServerScriptService.Server.StationInfrastructureArchive)
Infrastructure.Rebuild(source)
```

This reconstruction is separate from the ordinary-building facade process. Review the cloned infrastructure before authoring its train station and walkways.

## Eligible buildings

The owner now authorizes applying ground facades to remaining random buildings, approximately 15 stories and below, while excluding station infrastructure, Shibuya 109, crossing landmarks and substantially large/tall buildings. Upper-floor facade design remains future work.

Read `GeneratedFloors` and verify it against `#SourceSlicePlan.levels - 1`; the last level is the roof. Require `StructuralOnly=true` and a valid source plan. Reject `CrownInteresting`, a `Landmark` attribute/tag, the authored `Building1`, and all explicit infrastructure or landmark IDs. Do not infer story count from the source ID's middle number or a model bounding-box Y: historical models had rotated pivots, and source numbers are not story counts.

Legacy ordinary massing can be admitted after its existing `SmoothMassing` tiers are validated by the pure `FacadeLegacyPlan.Read(model)` adapter. The coordinating tool explicitly attaches **`FacadeSourcePlan`**, **`FacadeSourceId`** and **`FacadeSourceOriginCFrame`** as facade-only metadata. No reader automatically runs that adapter, regenerates slabs, or spoofs original `SourceSlicePlan` attributes. Selection and neighborhood indexing use those fallback attributes; facade-only `FacadeFloorCount` records the verified actual native floor count; the original `GeneratedFloors` is preserved (33 legacy models have stale counts). `FacadeLayout.FrameOf` optionally supports `FacadeSourceSavedPivot` for a subsequently moved legacy model. Glass state IDs use the same fallback identity, while `GlassGeometry.UpperEnabled` explicitly rejects legacy facade-only plans even if a future global upper flag is enabled. The 157 missing-plan holds in the early ledger are a pre-adaptation checkpoint, not the final count of unsupported buildings.

A fresh read-only census before this rollout found 2,068 source-plan models, 2,046 ordinary models after crown/landmark protection, and 2,027 ordinary models with 1–15 floors. Low-rise footprint distribution: 1,830 below 10,000 square studs; 180 from 10,000 to 30,000; 15 from 30,000 to 60,000; two above 60,000. These categories describe candidates, not final installations. A conservative 30,000-square-stud footprint ceiling holds larger complexes for case-by-case review. It avoids giving vast low-rise station/department-store forms generic shops solely because their story count is low.

Selected station infrastructure supplied by the owner/current Studio selection:

- `orph_-1012_-190`
- `orph_-912_-37`
- `part_-424_296` (ground footprint approximately 217,457 square studs)
- `BuildingSmooth_14_-6819_752_-938_Body01` (legacy model without the source-plan eligibility contract)

Archive these separately with exact instances/attributes/geometry retained, rather than treating them as ordinary facade targets. An archive preserves original train-station/walkway geometry for a later authored reconstruction. This audit never moves or deletes selected geometry.

## Crossing protection

The old first pilot's 1,200-stud circle around X/Z origin is historical; v5 deliberately replaced that blanket exclusion so the owner-selected ordinary building at approximately (-318,-751) could be tested. Neither that blanket circle nor an assumed crossing at the origin is a reliable current boundary. The saved OSM building polygons were aligned independently to the known Scramble Square, PARCO and Cerulean landmarks. A north-mirrored similarity fit using the actual OSM polygon centroids gives scale 4.15556 studs/metre, rotation 178.50993 degrees, and control residuals 27.3, 14.9 and 22.1 studs. The opposite mirror has residuals of 643–1,174 studs and is rejected. Old fit scripts used coarse landmark latitude/longitude guesses, including a Cerulean longitude approximately 140 metres west of the saved named building, which explains contradictory historical transforms.

This fit places the crossing reference (35.6595,139.7005) at approximately **(11,572)** and Shibuya 109's OSM footprint at approximately **(683,596)**. The actual 109 source model is **`fbx_5_6952_1857_6146`**, ground polygon centroid **(713.63,611.12)**, nine floors, 32 vertices, and 27,283 square studs. Direct comparison of the projected OSM109 boundary to nearby live source polygons gives mean boundary distance 24.19 studs and maximum 42.13 for this model; the next-best model has mean 86.33 and maximum 156.20. Its round/triangular geometry and close boundary match support the identification.

The orchestration proposal is a conservative crossing disk centered (11,572), radius 500 studs, plus a 109 district disk centered (683,596), radius 275. The final manifest/policy records the values actually used. `SelectCity` tests whole ground polygons against those circles, including edge intersections and a circle contained inside a polygon; a source origin outside the disk is not sufficient to admit a building. The auditor supports an explicit ID set plus an optional center-distance disk, so supply the selector's complete held-ID set to audit footprint-intersection exclusions accurately.

`Building1` is the authored Shibuya Scramble Square. The actual Cerulean is `fbx_6_4510_4915_-8852`; older handoff material calling `fbx_4_-9770_4222_-4948` Cerulean is expressly corrected later in the source-slice handoff. Shibuya PARCO was `orph_703_1736` in prior documentation; the current matching large model is **`orph_706_1735`**, 22 floors, bounding-box center approximately (712.39,1757.97). The exact old ID was absent in this session's control query. Retain both known IDs as explicit protection; the current model is independently held by the story cap. The substantial untagged model `fbx_14_-1157_1866_2078`, around (-109,219), 12 floors and 43,826 square studs, is already held by the large-footprint gate.

Some crossing and >15-floor models already carried ground facades when this session's census ran. Eligibility must be applied to the final installed manifest, not only to newly added candidates. Previously installed facades on now-excluded station/landmark/tall buildings must be archived or explicitly reported as preserved exceptions; otherwise a new selector alone cannot satisfy the owner's restriction.

## Source preservation and authorized core adjustment

Preserve original floor/slab/crown geometry, terrain and roads. Capture an in-Studio pre-edit mapping of every original BasePart to `{CFrame, Size, Color}`, excluding old owned facade descendants. Keep that mapping in Studio memory; no bulk geometry export is required. Station geometry may move into ServerStorage intact and still satisfy the baseline.

The owner authorizes slight horizontal shrinkage of only cores that crowd the outer floor edge. Maintain core height, vertical location, source-plan consistency, structural tags and at least the configured edge margin. Record exact changed instances in an allow-list and retain original core bounds/parts for rollback. Do not grant a whole-building source-preservation exception: the audit permits only listed `SourceSliceCore`/`BuildingCore` parts to change horizontally. Independently check revised core bounds inside the actual polygon perimeter; a bounding box alone does not establish clearance for a concave or multi-piece footprint. Core-specific geometry validation is separate from this facade acceptance script.

## Read-only audit

`tools/verify_facade_v9.luau` consumes `_G.FacadeV9AuditOptions` and stores its diagnostic result as `_G.FacadeV9Audit`. It creates no Instances and does not change any glass state. Its default behavior raises an error after collecting failures, with up to 500 detailed diagnostics retained. Use `failOnError=false` only while inspecting/reparing a draft; zero failures is the final acceptance criterion.

Inputs:

- `helper`: current fresh helper folder containing GroundFacadeFrontage; avoids stale Studio require caches.
- `manifest`: decoded final manifest; otherwise reads ServerStorage.GroundFacadePilotManifest.
- `excludedIds`: set of protected IDs, including footprint-intersection crossing cases.
- `crossingCenter`, `crossingRadius`, `maxFootprintArea`: explicit policy tunables, if used by the selector.
- `baseline`: original-part mapping captured before changes; `requireBaseline=true` makes omission fail.
- `changedCoreParts`: exact instance set that the core adjustment legitimately modified.
- `allowExistingExceptions`: explicit reviewed IDs only; bypasses floor/area/disk limits, never landmark or station gates. Prefer an empty set.

The auditor checks every final owned building against the manifest and policy. It samples complete run coverage every two horizontal studs at five vertical heights, permitting holes only inside verified open parking/loading/produce portals. Every open portal must have 22 studs of clear interior; source cores are never cut to create a parking bay. Every flagged exterior part has all eight vertices checked against the outside-mount contract. Every pane gets an exact own-source volume overlap check and nine outward visibility rays against the final built neighborhood. This catches the v8 class of failures where newly installed neighboring walls/footings hide earlier reviewed panes.

Opaque visibility filters are rebuilt per building using a local spatial broad phase. This avoids constructing a many-hundred-thousand-instance ray filter for every pane and includes all final neighboring facades. Intentional clinic privacy spandrels and workshop partial shutters are exempt. Stairs receive nine footprint support checks, planters verify their saved support height or declared footing mode, and vehicle ramps must be WedgeParts with their filled base. The audit also counts labels, Japanese-only and bilingual labels, fonts, palettes, wall colors and glass colors. Counts are evidence for variation; Japanese glyph availability and readability need visual review in Studio because a numeric Font enum cannot prove fallback glyph rendering.

Generated upper glass and far proxies must remain disabled. Existing four-state glass should additionally be tested on a cloned installed pane in Play: 1 → 2 → 3 → 1 → 4, checking collision and hiding/restoration of backing, film, posters and attached GUIs. Never destroy an installed source pane merely to run this check. Inspect server/client console output and sample multiple distributed street views, a narrow building with an adjusted core, a quiet alley, every palette/font family and the retained gallery/glass demo.

For selective repair after a complete installation, run the separate read-only `tools/scan_facade_v9_blockers.luau`. It records every unique blocked bay in `_G.FacadeV9BlockedBays[buildingId]["piece/run"][bayIndex]`, with flat repair identities in `_G.FacadeV9BlockerRows`. Its returned/global `_G.FacadeV9BlockerScan` counts failed buildings, unique bad bays, unresolved identities, source-volume tests and visibility rays; examples are capped at 100 while the repair sets are complete. It derives bay indices from stable `GlassPaneId` keys (`/bayN/`), using report widths and geometric bay ordering only as fallbacks. A bay stops further pane tests after its first obstruction because one persisted `bayRoles[index]="blind"` veto already identifies the repair. Rebuild only affected buildings through the normal owned-facade upsert, preserving that veto in the manifest. An optional `_G.FacadeV9BlockerOptions.modelIds` set restricts an intermediate repair scan; the initial and final scan must include all installed buildings so later neighboring geometry cannot silently invalidate earlier panes. Final acceptance requires zero blocked bays and zero unresolved identities, followed by the full support/perimeter audit.

## Performance limits

A complete Edit geometric pass is not a shipping performance budget. V8 alone added 94,472 anchored replicated parts across 200 buildings. Record final parts/panes and the increase; run a short distributed camera route with first seconds excluded and report actual frame intervals without extrapolating target-device FPS. Keep server glass state sparse, shards client-only and bounded, upper generation off, and do not add a server heartbeat per pane. Ground geometry currently remains replicated even when damage-texture detail is distance gated. Full-city installation needs a measured cost report and future batching/geometry LOD work.
