# Ground facade v9 core clearance

`src/server/FacadeCoreClearance.luau` is an edit-only, explicitly invoked tool. Requiring it does nothing. It is not initialized by server startup.

## Representation and clearance proof

SourceSliceBuilder produces six full-height one-stud-thick walls/dividers in `Interior.Floor1`. They span floor-1 slab top to roof slab underside. `SourceSlicePlan.core` stores their **outer** local X/Z rectangle; `CoreCFrame` and `CoreSize` store common-core metadata. The metadata Y extent includes both slab envelopes and is deliberately preserved.

Audit preserves center/yaw/Y extents. It asks whether the rectangle expanded by 3.01 studs is wholly covered by the exact nonoverlapping polygon union on **every** source level, including roof. Sutherland-Hodgman clipping and summed polygon area prove coverage, including concavities, holes and internal tile seams. `SourceSliceBuilder.Validate` first proves canonical simple polygons, no overlapping pieces, and original-core containment; area tolerance is numeric (max 0.0001 square studs / area * 1e-8), not a multi-stud geometric allowance. The square expansion is conservative: it provides at least 3 studs of Euclidean clearance, including around corners.

A fixed-center minimum 4x4 core must fit first. Otherwise the building is skipped with a reason; no core is removed or moved. A uniform shrink followed by both axis-expansion orders retains a substantial rectangle while respecting the exact union proof. The larger retained-area order wins. This is conservative, not an optimization claim of globally maximum possible area. A final 0.02-stud safety shrink avoids native CFrame/size roundoff.

Only the six recognized primitive source core parts change. Floors, terrain, roads, crowns, facade mounting and destruction are untouched. Saved plan core and `CoreSize` are updated, so SourceSliceBuilder regeneration keeps the new width/depth. `CoreCFrame`, source frame/pivot, vertical extents, material/color/tags/flags, instance identities and structural bbox remain intact. The bbox was already an enclosing volume and remains conservative after shrinkage.

## API

```luau
local tool = require(game.ServerScriptService.Server.FacadeCoreClearance)
-- Explicit eligible list chosen by the main rollout, with station/crossing cutouts.
local audit = tool.Audit(models, {
    margin = 3, minimum = 4, maxFloors = 15,
    excludeIds = infrastructureAndCrossingIds,
    exclude = protectedModels,
})
-- audit.rows contains model/id/status/reason and planned before/after data.
-- audit.ready, audit.unchanged, audit.skipped are counts.
local applied = tool.Apply(audit)
-- applied.changed, applied.backup (ServerStorage folder, or nil if zero changes)
-- Explicit manual rollback:
tool.Rollback(applied.backup)
```

`Plan` is an alias of `Audit`. Audit is read-only and yields once per building. Apply first checks all ready rows for unchanged source plan, effective frame, core properties and metadata. Then it stores every backup **before** editing anything. Each building backup contains its target reference, prior plan/Core attributes, six original part references/property records and six reference geometry clones. Apply yields per building and verifies the native resized walls. An error rolls the entire batch back, including any already edited buildings.

Rollback restores the original instances' CFrame/Size and metadata, retaining the backup for inspection. It refuses missing target buildings/parts. Invoke immediately after an unwanted Apply; it intentionally restores saved values and would overwrite later deliberate core edits. A cloud-saved backup retains ObjectValue references to the original live targets.

## Eligibility and limitations

Module refuses non-live/nonordinary models, buildings over 15 floors, Landmark/CrownInteresting/StationInfrastructure/FacadeExcluded attributes/tags, explicit model/ID exclusions, noncanonical six-wall cores, attached core decoration, modified core flags, stale metadata, invalid source plans, tilted frames, and inconsistent floor counts. Caller must supply the agreed crossing and station exclusion lists; a street address is not inferred by the core tool.

Clearance is proved against authoritative source-slice polygons. This assumes live native floors still match their saved source plan; the main rollout's unchanged-floor baseline and source geometry audit are separate verification. The tool does not redraw slabs or repair corrupted/deleted floors. It also does not repair overlapping source buildings or guarantee walkable interiors around the core. Very narrow/tapered buildings can legitimately skip because a centered 4x4 core plus 3-stud margin cannot fit every level. Conservatively including roof polygons may skip some cases that a custom vertical analysis could allow.

Audit performs canonical polygon validation once per candidate and repeated clipped-area tests only for near-edge cores. Apply has constant six-wall work per changed building. Neither operation creates heartbeat loops or runtime scanning.

## Read-only live census, October 16, 2026

TestJJK Studio `6f4ce284-6b00-4d5c-969d-c98b20a4bff3`: 2,068 source-slice models. A coarse <=15-floor ordinary filter (excluding selected station source IDs `orph_-1012_-190`, `orph_-912_-37`, `part_-424_296` and existing landmark/crown flags, but before full crossing/size cutouts) includes 2,024. Of those, **1,557** have a core within 3 studs of at least one level's axis-aligned outer bounding box. This is a lower-bound diagnostic only: concave edges can add near-edge cases, and exact minimum-fit/eligibility tests can skip cases. No Studio core mutation was performed by this census. Main rollout must record its actual audit/apply/rollback evidence separately.

## Precision regression correction

The first audit used Roblox `Vector2` for clipping coordinates. Those vectors store float32, while rectangle area used Lua double precision; the tight area tolerance then caused nonmonotonic numerical matches during binary search. A final *smaller* rectangle could falsely fail coverage. This was a numerical bug, not evidence that 386 buildings needed manual geometry intervention.

Clipping and signed-area math now keep plain Lua numeric pairs throughout, preserving double precision. The tolerance and conservative 3.01-stud expansion were not weakened. Four reported source IDs were re-audited with a fresh isolated temporary module: three ready, one already clear, no skips. Another 50 formerly failing cases produced 40 ready and 10 already clear, **zero skips**. These probes were read-only against live geometry; temporary helper modules were removed. The main orchestrator must refresh its helper copy and rerun the full eligible audit before any Apply, since old results include false positives/false skips.

## Read-only legacy facade adapter

`src/shared/FacadeLegacyPlan.luau` adds `Adapter.Read(model) -> record` or `nil, reason` for ordinary `SmoothMassing`/`ExactPolygon` legacy buildings. It never writes native geometry or attributes and never calls regeneration. Record fields are `plan`, `frame`, `id`, `floors`, and `verification`. Stable IDs are `legacy/` followed by the exact model name. `floors` counts actual validated native slab planes minus one; source `GeneratedFloors` remains unchanged. Caller may store the result under **facade-only** metadata (`FacadeSourcePlan`, `FacadeSourceId`, `FacadeSourceOriginCFrame`, `FacadeFloorCount`), never canonical `SourceSlicePlan`/`SourceSliceId`.

The adapter validates saved simple concave tier rings, reconstructs each native Part/WedgePart's true projected convex polygon from its vertices, and groups all native slabs by elevation. It proves every native level's union matches one exact saved tier ring: each native polygon lies inside that ring, summed coverage/area agrees, and native polygons have no significant mutual overlap. Tolerances follow the existing native slab audit convention (perimeter * 0.01 plus small area/absolute terms), accounting for Shibuya world-coordinate float32 rounding; they do not replace concavities with a hull or bbox. Levels must remain vertically separated by the established minimum clear height, and actual storeys must be <=15.

Legacy `Roof` sometimes contains several genuine slab planes. Grouping by native elevation instead of trusting folder labels preserves these real curves. Native floor1 elevation is authoritative: the old saved massing frame can predate `FlattenDY`. Current pivot versus `SmoothFrame` is one candidate pose, but implicit pivots can flip between wedge orientations without moving geometry. Therefore a saved-world-pose fallback is also considered. **Either pose is accepted only after the same all-level native union proof**. No pose guess is trusted on its own.

October 16 full live verification: **157/157** legacy exact-polygon models passed, comprising **607** real slab planes and **3,245** native slab parts. Thirty-three have actual storey count differing from old `GeneratedFloors`; three require the verified saved-world fallback. Maximum union-area discrepancy is 0.140421 square studs. There is also a huge nonordinary test `Building1` without reliable GeneratedFloors; it is outside this adapter and city rollout.

Samples:

- `BuildingSmooth_2_25850_1792_-7829`: 7 actual floors, 20.1100-stud native base correction, 0.0122-square-stud area discrepancy.
- `BuildingSmooth_10_-16793_886_-13524_Residual_64acfd9d_Body01`: 2 actual floors, saved-world fallback, 0.0160-square-stud discrepancy.
- `BuildingSmooth_15_-25566_1458_-20286_Body01`: 10 actual floors, saved-world fallback; its implicit current/saved pivots disagree by a flip although native slabs stay upright.

The adapter's successful records are not automatic rollout eligibility: the orchestrator must still exclude station infrastructure, crossing landmarks, protected crowns and deliberately oversized footprints. This adapter does not resize legacy per-floor cores; source-slice core repair remains a separate tool.

## Legacy per-floor core clearance tool

`src/server/FacadeLegacyCoreClearance.luau` is a separate explicit edit-only tool. `Audit(models, {margin=3, maxInset=6, exclude=..., excludeIds=...})` returns ready/unchanged/skipped rows; `Plan` aliases Audit. `Apply(report)` returns changed count and a `ServerStorage.FacadeLegacyCoreBackup_<GUID>`; `Rollback(backup)` restores original instances and metadata. It never modifies source-slice cores or generators.

Read-only census found all 157 legacy models have the expected six tagged primitive core wall/divider parts per old GeneratedFloors, totaling 2,502 parts, aligned to their upright CoreCFrame. Legacy `CoreSize` widths describe wall centerlines; the actual exterior envelope is wider by one wall thickness. The tool derives this true envelope from all native pieces and checks it against metadata. It then scales native local X/Z sizes and offsets around the unchanged CoreCFrame. Each wall's Y extent, original rotation, material, color, flags, tags and instance identity are retained. CoreSize X/Z scale consistently; Y and CoreCFrame are untouched. There is no enlargement on either horizontal axis.

Exact adapter-validated level polygons provide all-level clearance testing, using numeric-pair clipping in double precision. A 3.015-stud square-expanded envelope must fit every level. Maximum outer-edge shrink is six studs; minimum CoreSize X/Z is four studs and minimum scaled wall thickness is 0.4 studs. Unsafe/ambiguous or already undersized cores are skipped. Source slabs are snapshotted and must remain exact during Apply; current core geometry/metadata and saved massing/facade plan must also match the Audit. All candidate core properties/reference clones are backed up before any original changes. A failed Apply rolls the batch back.

Initial full census audit: **24 ready, 112 already clear, 21 skipped**. Fifteen skipped cases cannot satisfy clearance plus minimum dimensions within the bounded shrink, and six already have CoreSize widths below four studs. Rollout eligibility cutouts are an additional filter.

Every one of the 24 ready cases was tested on a separate **ServerStorage clone** of its native Interior and metadata. All 24 applied successfully, passed a fresh post-Apply Audit as unchanged/clear, and rolled back to exact prior CFrame/Size for every cloned native part and exact CoreSize. Largest proposed outer-edge reduction was **3.11736 studs**. No live legacy geometry was modified by these tests; all temporary helper/clone/test backup objects were removed.

This preserves the *current* native city edit. Future `SmoothBuildingBuilder.Regenerate` still constructs its older original core dimensions from its saved massing/grid; rerun this explicit repair after such regeneration. No regeneration hook or runtime loop was added. The orchestrator must refresh Audit with the final eligible/excluded list before applying any old read-only report.
