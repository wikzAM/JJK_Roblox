> Historical v7 checkpoint. Current outside-mounted 200-building trial: [FACADE_CLIP_HANDOFF.md](FACADE_CLIP_HANDOFF.md).

# Ground facade feedback — October 10, 2026 (v7)

Read `src/client/ProjectFiles.luau` first. This pass addresses the owner's photograph of signed shops covered by beige walls, excess blank elevations, and repetitive exterior colors. It retains the same 32 ordinary buildings near the lime locator; no further expansion or landmark work was authorized.

**Cross-device checkpoint:** Studio confirmed `Saved new changes in "TestJJK" to Roblox` at **16:34:15 America/Indianapolis on October 10, 2026**. Confirmation image: `tools/preview/facade_v7_saved_roblox_native.png`. Open that place for the current city and pull GitHub branch `shibuya-level-curves` for matching scripts and documentation.

## Current result

TestJJK, place 99539622209675: 228 complete ground runs, 8,663 owned parts, 570 physical glass panes, 33 entry/service/parking portals, 165 supported stair parts, seven grounded planter groups, and one verified open parking bay with a supported WedgePart ramp. Compared with v6, usable portals increased from 23 to 33. White, off-white, grey, charcoal, dark brown, cream/beige and stone palettes are assigned coherently per building (four or five buildings per palette). Branded fascia accents remain independent.

The source models, cores, terrain, roads and generator code were retained. The raised gallery, glass demo and owner spawn remain. Upper glass generation remains disabled. The denser section has 37% more facade parts than v6; this is a limited visual trial, not approval for full-city rollout.

## Why the photographed shops were covered

A neighboring high-ground building's tall facade footings and buried plinths extended across the flower shop and udon glazing. Previous checks tested each shop's own original structure, so they missed neighboring owned additions. The lower obstructed bays now receive quiet enclosure rather than signs and steps advertising an unusable entrance. The higher visible neighboring elevation receives high windows where ground allows them.

`GroundFacadePlacement` now checks opaque original parts regardless of `NoCSG`, neighboring owned geometry, and other facade runs on the same building. Regular pane samples are supplemented by projected bounds probes to catch thin obstructions between sample points. The base ground plane remains 0.75 studs outward of the source outline. Extra whole-run clearance is capped at 1.25 studs; the current maximum is 0.8. Refitting after vetoes never reduces an approved outset, and final bay approaches are checked again.

## Density and approach rules

Very close neighbors (four studs or less) remain blind. Wider constrained sides use quiet windows without entrances. An open face can receive an entrance with a road approach or a verified clear pedestrian approach; actual doorway samples still enforce the four-stud rise, two-stud local ground variation, clear approach, and existing parking/core-depth rules.

Whole-face elevation variation no longer automatically removes all entrances: safety is evaluated at each bay's doorway. A bad doorway demotes its own bay. Raised-ground elevations may receive high slit windows if the sill clears the highest sampled ground by at least 0.5 studs; ground covering usable window height retains a blank wall. `40_PanelSeams` was removed from the window profile to avoid randomly turning intended window sides into fully blank walls.

Road audit found only one centre sample supported by a road rather than terrain. It is a collidable Asphalt service road at `Workspace.Roads.tile_m1_m2.Road`, 73×1.5×22 studs, about 2.07 studs above terrain at that sample. It was not the shopfront occluder and was retained. No speculative road deletion occurred.

## Verification and reproduction

Final `tools/verify_facade_feedback.luau` Edit audit passed: 32 buildings, 228 runs, 570 intact panes, 5,130 rays with no unintended opaque occluders; all 165 stair parts supported, all seven planter assemblies grounded, and the parking wedge/base present. It also confirmed 2,017 original parts in these same 32 models retain their exact CFrame, size and color. Intentional clinic privacy spandrels and workshop partial shutters are excluded from the obstruction audit; they deliberately mask part of their own windows. Maximum outset is 0.8 studs and points outward.

A second read-only review caught and corrected ancestry traversal skipping the immediate run model, and a veto refit that could otherwise pull retained entrances inward. Script-only `rojo build` succeeds; that build is not the live city map. Native review images are under `tools/preview/facade_v7_*_native.png`.

Native Play smoke check completed with all 570 city panes intact and zero generated upper/far glass. Client and server modules initialized without runtime errors. A six-second foreground stationary Starboys view after initialization averaged 9.35 ms across 641 sampled frames. This single local sample is not a moving-route, device-range or full-city performance guarantee. Temporary camera probes were removed and Studio returned to Edit.

Current Studio helper: `ServerStorage.FacadeFeedbackRuntime`. `ServerStorage.GroundFacadePilotManifest` contains the current v7 Manifest and Report. Prior owned facades and registries are archived in `GroundFacadePilotArchive`. The checked-in `facade_section_*.json` files and reusable stock models remain historical v6 evidence, not the new live manifest. New bulk Studio audit exports to localhost were blocked by automatic approval review; no rejected transfer was bypassed. Read the live registry via Studio and run the audit there. The cross-device source of the live map is the saved TestJJK place, with matching scripts on GitHub branch `shibuya-level-curves`.
