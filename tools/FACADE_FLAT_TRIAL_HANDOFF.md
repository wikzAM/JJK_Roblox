# Ground facade flat-region trial — October 10, 2026 (v5, historical)

> **Current v6:** [FACADE_SECTION_HANDOFF.md](FACADE_SECTION_HANDOFF.md). Owner-approved expansion covers 32 ordinary buildings and 228 runs; core-safe ground placement and connected corners are verified. Temporary generated upper glass is disabled. The two terrain repair backups below remain current.

Read `src/client/ProjectFiles.luau` first. This supersedes the location and coverage claims in `FACADE_PERIMETER_HANDOFF.md` v4; the earlier style/name/glass requirements still apply. The latest owner request is to finish wall coverage, replace car-ramp sheets with filled wedges, use blank walls on excessive drops, and trial a flatter ordinary-building cluster near the selected building toward 109. Mass deployment waits for the owner's visual review. Upper floors are planning only.

## Live place and navigation

TestJJK, place 99539622209675. Three ordinary buildings now have complete exterior ground perimeters. The previous western three-building trial is archived and its owned facades removed. Original buildings remain.

- `BuildingSourceSlice_orph_-318_-751`: the owner-selected building, 26 ground runs; office entrance and genuinely open parking bay.
- `BuildingSourceSlice_fbx_4_-2009_1297_-6788`: seven runs; convenience shop and Starboys frontage.
- `BuildingSourceSlice_fbx_4_-1598_983_-8036`: nine runs; ramen frontage and rear service door. The attempted McDooDoo's entrance on run 1/6 fails its approach collision check and receives quiet windows instead.

The lime pillar is `Workspace.FacadeTestMarkers.Lime_CityFacadeTestArea`, base **(-388.99, 86.43, -707.63)**. The magenta gallery pillar remains at (250,1600,-100), and the owner's Workspace spawn is unchanged. Studio is left in Edit mode looking at the new office front. Use `require(game.ServerScriptService.Server.FacadeTestMarkers).FocusCity()` to find the cluster again.

Selected-building frontage clear height is 12.5 studs. The original scene has 2,227 buildings and 1,037 road parts; landmarks/crowns and generators are untouched. Ordinary `StructuralOnly` metadata plus actual landmark/crown exclusions replace the old blanket 1,200-stud exclusion, because the owner explicitly chose this nearer building.

## Wall and approach corrections

The v4 test only counted exterior runs; it did not test their full height. Generic upper-floor `FacadeLayout` interpreted some uncovered sides as 3.5-stud parapets. `GroundFacadeFrontage.Survey` now builds a separate ground configuration using the actual next slab height minus ground slab thickness. Upper-floor layout rules are unchanged. Corner overlaps, overlapping bay joints, window end stiles, wider mullions and door/window joint strips close actual slits. There is no backing wall across the open parking portal.

Every run samples ground at five positions along its width, at three distances outward. Entrances get additional checks at their actual bay/door position across the approach. More than four studs of rise, more than two studs of frontage ground variation, an obstructed approach or unknown ground removes the entrance and selects a quiet treatment. Severe elevation mismatch selects a full-height blind wall. A driveway may span three studs of ground variation only when the complete approach is filled and its grade passes the separate bound. Tight adjacent-building gaps stay blind.

Ground footing is divided into at most four-stud-wide segments and samples both ends, rather than using one centre height for the entire side. Steps extend down to their sampled ground instead of floating. Planters move as assemblies, with a plinth when needed.

The vehicle approach is an anchored `WedgePart`, high edge toward the parking opening, plus opaque `GarageRampSolidBase` beneath it. The driveway toe is measured at the actual low edge; rise is at most four studs and grade at most 25%. This selected driveway is about 13 studs long with a shallow top wedge and a substantial supporting base over the local hollow. Interior depth must remain clear for 22 studs; cores are never carved to manufacture parking.

## Local terrain work and recovery

The owner authorized correcting terrain for this test. Only TWO small approach pads on the selected building are adjusted; the old western region and the city terrain are not globally reflattened. `GroundFacadeSiteGround` is edit-only and is not initialized at startup. It bounds requested column movement to 1.5 studs, blends into the surrounding terrain, caps beneath existing road skins and leaves previously empty Air cells empty to avoid a new four-stud raised voxel layer.

The final pads changed 82 occupied voxels: 50 at the parking approach and 32 at the office approach. The reported bound is the requested density-profile shift, not a guarantee of exact rendered smooth-terrain elevation. Existing road surfaces can dominate the ground ray; the centre ray heights are unchanged. Solid footing/steps/driveway support still handle the remaining ground mismatch. Earlier trial terrain edits were fully restored before these two final pads.

Live before/after voxel snapshots are in `ServerStorage.FacadeApproachTerrainBackups`, with final keys `orph_-318_-751_8_final` and `orph_-318_-751_20_final`. Disk snapshots use those keys in `tools/source_slices/facade_ground_before_*.json` and `facade_ground_after_*.json`. Restore in reverse application order with:

```lua
require(game.ServerScriptService.Server.GroundFacadeSiteGround).Restore({
    "orph_-318_-751_8_final", "orph_-318_-751_20_final"
})
```

Restore refuses to overwrite a region changed since its saved after snapshot. `facade_flat_terrain_pads_final.json` is the current pad record. Other pad records are restored experiments, not additional live edits.

## Facade library and glass

Catalog/library/gallery revision is now 5, with the same 53 physical facade types, 79 business labels and independent naming seeds. Geometry corrections add real frame overlaps; the reusable library has 2,544 parts. Gallery replacement archives the prior version and retains `04_GlassDemo` and owner spawns. Updated portable files: `assets/GroundFacadeDraftLibrary.rbxmx` and `assets/GroundFacadeDraftsPreview.rbxlx`.

Glass owner contract stays `2026-10-08-ground-pilot`. Only the three new buildings qualify for generated trial glass, with all 42 ground runs owned to suppress generic curtain glazing there. Temporary generated upper glass remains restricted to these same three until designed upper-floor families replace it. No city-wide activation, far proxies, damage changes, hit changes or new server shard physics are introduced here.

## Verification and reproduction

- `verify_facade_flat_trial.luau`: **2,712 physical enclosure rays, zero unintended openings** across 42 runs at five heights; six portal cases, one clear parking bay, 27 stair parts grounded at all nine footprint samples, three grounded planters; **6,441 original nearby scene parts** retain exact CFrame/Size. It also checks the two terrain backups, solid wedge support and unchanged building count.
- Fresh kit semantic checks: 954 layout cases, 318 entrance cases, 112 span compositions, 53 distinct types, independent ad seed and idempotent gallery generation.
- XML and Rojo preview export verification: 53 templates / 2,544 parts / four round columns, retaining geometry, Japanese labels, pivots, attributes and tags.
- Native Studio Play: former western test camera sees **zero near / zero far** generated facades; new-cluster camera sees **three near / zero far**, exactly three eligible buildings, 442 client facade parts. Temporary verification LocalScript was removed after Play.

Saved evidence: `facade_flat_manifest.json`, `facade_flat_report.json`, `facade_flat_verification.json`, `facade_flat_native_play.json`, and `facade_flat_terrain_pads_final.json` under `tools/source_slices`. Current placement adds 1,106 owned parts including 62 tagged panes. `ServerStorage.FacadeFlatTrialRuntime` contains fresh edit-helper modules for re-running the current manifest; normal Rojo module sources are also updated. A later reapply should survey again if the owner changes terrain, roads or source buildings.

The exact original-part preservation baseline is an in-memory verification snapshot for this Studio session, not a durable map archive. Save the Studio place to persist the map edits. Portable kit files and voxel snapshots do not constitute a full city backup.

Next-pass design notes: `UPPER_FACADE_APPROACH.md`. Do not mass apply or modify normal floors until this trial has been reviewed.

The native edit capture confirmed the office frontage but omitted terrain visible to raycasts, so it is not evidence that the ground is visually flat. The lime beacon was moved to the side after it obscured the frontage in that capture. Inspect the actual Studio viewport for final terrain/approach appearance before expanding the trial.
