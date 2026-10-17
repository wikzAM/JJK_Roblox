# Selected rectangular building repairs

`FacadeBoxRepair` is an edit-only helper for the owner's two selected malformed source buildings. It does not run automatically and was prepared separately from the facade expansion.

Authorized identities and retained floor counts:

- `fbx_6_16012_2445_-12199`: 10 floors.
- `fbx_11_13048_1764_5668`: 5 floors.

Call `require(game.ServerScriptService.Server.FacadeBoxRepair).Prepare({exactModel1, exactModel2})` while connected in Edit. Inspect the returned `review`, `plans`, `audit`, and native `stage`. Existing map geometry stays unchanged. Store it in `_G.FacadeBoxPrepared`, then run `tools/verify_facade_box_stage.luau`. That disposable native check tests structural parts and final roof rims against collidable neighboring building parts, tests the two replacements against each other, and checks core clearance. It always removes its probes. It does not verify terrain, roads, external infrastructure or noncollidable dressing; visually review those too. Immediately before `.Apply(prepared.stage)`, require `_G.FacadeBoxStageAudit.passed` and `_G.FacadeBoxStageAuditStage == prepared.stage`. Any stage/source edit requires fresh verification. SourceSliceReplacement's optional Preview/Restore may be used; restore previews before verification and Apply.

The footprint is an axis-aligned rectangle in the original source frame wholly contained in the original ground floor polygon union. A rectangular footprint is retained exactly. Other outlines use the largest rectangle in a conservative 64 by 64 occupancy grid, with exact polygon-area coverage for each cell and the final rectangle. Upper overhangs never determine footprint bounds. This is a conservative grid approximation, not a mathematically maximal inscribed rectangle. Neighbor clearance still needs visual review; containment cannot repair a source footprint that was already inside another building.

Each replacement retains the current live upright source placement and the stated floor count. Levels have uniform spacing, fixed 1.5 metre slabs, and at least 2 metres clear. Existing base and roof elevations determine spacing unless they violate minimum clearance. The same rectangle repeats through the roof, with a centered six-wall common core and at least 3.01 studs of exterior clearance. Rectangles narrower than 10.1 studs are refused.

Prepare validates and builds native SourceSliceBuilder geometry, audits it, and durably binds the exact original and staged models through SourceSliceReplacement. Original plan and facade ManifestRow/ReportRow metadata are copied into `stage.SourceSliceBindings.FacadeBoxRepairMetadata`. Apply rechecks snapshots and structure, then moves the exact originals—including their old facades—into `ServerStorage.ShibuyaBeforeSourceSlice_<GUID>`. No original model is deleted. Retain that archive and the stage's bindings/metadata for recovery.

Roof rims are added **after** SourceSliceReplacement Apply, because its structure audit rejects undeclared decorative geometry. A rectangle gets four six-stud roof ledges tagged NoCSG. A crown failure is reported in `crowns`; the structural replacement and original archive remain valid. Structural bounds are updated after crowning.

Apply deliberately does not replay old facade rows: their dimensions/orientation are stale. The caller must build a fresh GroundFacadeFrontage index and survey, use GroundFacadePilot Upsert, run shared-surface correction and whole-bay interior preparation, and reconcile facade registry records. New models are marked `FacadeBoxRepairNeedsFrontageSurvey=true` until the caller completes those checks. Preserve road-front entrance and quiet-alley rules. A build succeeding is not Studio visual verification or a confirmed Roblox save.

No terrain, road, broader building-generator, station, or unrelated archive changes are included. These helpers do not resurrect the separately removed malformed building.

Validation status: repository Rojo serialization and whitespace checks passed. Rojo does not compile Luau. The initial target table's negative-number-containing IDs were corrected to quoted string keys during source review. Native module require subsequently compiled successfully in TestJJK. Prepare,stage audits,neighbor checks and visual inspection still remain before Apply;no live replacement has been performed. The owner requested these repairs AFTER the broader facade rollout,which is currently interrupted by editing-server shutdowns.
