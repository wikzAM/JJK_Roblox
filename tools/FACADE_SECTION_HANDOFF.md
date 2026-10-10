# Larger ground facade section — October 10, 2026 (v6, historical)

**Current feedback pass is v7:** read `FACADE_FEEDBACK_HANDOFF.md`. The same 32-building area now has 33 usable portals, seven building palettes and stronger neighboring-geometry checks. The counts and JSON evidence below describe the previous v6 checkpoint.

**Cross-device checkpoint:** Studio confirmed `Saved new changes in "TestJJK" to Roblox` on October 10 at **13:51:18 America/Indianapolis (17:51:18 UTC)**. Open TestJJK place 99539622209675 from Roblox Studio on the other device for the live city, terrain, section and raised gallery/demo. Confirmation image: `tools/preview/facade_saved_roblox_native.png`; output log: `tools/source_slices/facade_roblox_save_confirmation.txt`. GitHub branch `shibuya-level-curves` carries the matching scripts, reusable assets, manifests, documentation and test evidence. The older tracked root `JJK_Roblox.rbxl` and a fresh default Rojo build are not this live-city checkpoint.

Read `src/client/ProjectFiles.luau` first. This supersedes the three-building v5 coverage and temporary upper-glass policy. The owner approved expanding the ordinary-building section and asked that cores near the exterior not conceal glass. Work started at 09:33:12 UTC; overnight authorization ends at **15:33:12 UTC on October 10**, or when ordinary usage is exhausted, whichever comes first. No usage reset or credit purchase is authorized. Continued work must remain local to the ground facade trial; a full-city rollout is not approved.

## Live section and navigation

TestJJK, place **99539622209675**. **32 ordinary StructuralOnly buildings** within 350 studs of (-318,85,-751), including the three owner-reviewed v5 buildings, now have **228 complete ground wall runs**. The frontage survey uses actual source footprints and 62 existing road parts within its larger 750-stud index. Landmarks and interesting crowns are excluded. Ground heights follow each building's next slab rather than a generic upper parapet.

Current additions: **6,328 parts, 175 tagged physical glass panes, 23 entrance/parking/service portals, 118 solid stair parts, six supported planter groups and one open parking bay**. Sixteen buildings have glass; quiet sides and cramped courts remain opaque or use limited windows. Full-height blank treatments handle excessive elevation differences. No source core is carved to create an entrance or parking bay.

Find `Workspace.FacadeTestMarkers.Lime_CityFacadeTestArea`, base approximately **(-389,86,-708)**; it marks the city section near the owner-selected ordinary building toward 109. Magenta remains the raised gallery and looping glass demo at (250,1600,-100). Owner spawn was retained. Use `require(game.ServerScriptService.Server.GroundFacadePilot).Focus(1)` for the office/parking building, or `FacadeTestMarkers.FocusCity()` for the locator.

## Core clearance and connected walls

Ground layout now sets its own inset to zero. It had inherited the upper-glass 0.6-stud inset, leaving the ground facade only 0.15 studs outside the source footprint after its nominal 0.75 offset. The corrected ground plane begins **0.75 studs outside**. This does not change upper layout rules.

`GroundFacadePlacement` predicts the seeded and mirrored pane/door geometry before constructing it. Nine points on each relevant rear surface raycast against the original collidable structure. It shifts the entire wall run, including frames, signs and films, by the smallest required extra distance in 0.05-stud increments, with 0.25-stud surface clearance. Extra outset is capped at **1.25 studs**. If that would narrow an occupied passage or exceed the cap, the run becomes a blind treatment.

Three faces need extra outset in this section: 0.70, 0.75 and 0.80 studs. They belong to `fbx_4_-3961_1042_-8296` (1/2), `orph_-177_-770` (1/1), and `fbx_4_-527_1223_-7154` (1/3). Clearance also includes opposed wings of the same building. The cramped court on `fbx_4_-1598_983_-8036` (1/6) is now blind rather than receiving a storefront or a large push outward.

Every wall end has a solid return from the true footprint to the visible plane, including the base 0.75-stud offset. Returns close corners that ordinary face sampling alone would miss. Existing end stiles and widened door/frame overlaps also close the small glass joints. The ray checks prove glass visibility against structure, not traversable room interiors behind static draft doors.

## Ground-only glass and bounded effects

`GlassConfig.GeneratedUpperEnabled=false` disables temporary generated upper glass for this pass. The physical ground pane owner gate remains enabled, preserving damage and suppression of duplicate generic ground glazing. `FarProxyEnabled=false` remains unchanged. There are **zero generated near or far curtain parts** at both old and current review cameras.

All four states remain: intact/collidable; cracked/collidable; shattered with transparent noncolliding base plus transparent edge overlay; removed instance with persistent State 4 tombstone. Ground damage overlays enter at 220 studs and leave at 260 studs to avoid repeated rebuilds at the boundary. Transient shard event geometry is capped at **16 rows per building event**; full damage is preserved in state pages. Existing client particle cap remains 192. No server shard physics or per-pane hit listeners were added.

Native Play changed one pane through States 2, 3 and 4. Cracks retained collision. Shattered base transparency was 1, collision false, with two edge overlays; leaving range removed the overlays, returning restored them without restoring base color. State 4 removed the instance and retained its replicated tombstone. A trusted mass shockwave changed the other **174 panes across 16 buildings**; 16 events carried at most 16 rows each. These were Play-only tests, reset before returning to Edit. No structural hit or terrain destruction was performed.

## Verification evidence

- Independent final enclosure audit: **20,062 face rays**, **308 narrow pane/frame joint rays**, **456 footprint-to-surface corner connections**, zero unintended openings and zero sampled source-structure glass occlusions. Checks include nine-point stair footprints, supported planters, real WedgePart driveway and its solid base, 22-stud parking depth and landmark exclusion.
- Independent exact physical overlap query: all **175 pane volumes** tested against their original collidable structure with `GetPartsInPart`; zero intersections, covering thin obstructions between ray samples in this applied section. Saved as `facade_section_volume_checks.json`. The edit-time fitter itself still uses bounded rays; automate the volume fallback before broader rollout.
- **8,858 original structural parts** in the indexed scene retain exact CFrame and Size. This baseline excludes NoCSG decorations and is an in-memory verification snapshot, not a durable city backup. All 2,227 original buildings remain.
- Shared geometry suite: 954 layout cases, 318 entrance cases, 112 span compositions and all 53 physical styles. Portable revision 6 kit export: **2,600 stock parts**, four round columns, labels, pivots, attributes and tags preserved; XML and Rojo preview checks passed.
- Glass contract suite: 131 segment cases, 18 partition cells, four states, weak/strong shockwaves and persistent pages passed.
- Short stationary native render comparison before the final additional corner returns: structure only 6.963 ms mean / 8.223 ms p95; intact section 6.971 / 8.088; restored section 6.965 / 8.107; mass shattered 7.108 / 8.269. These are separate five-second local Studio samples, approximately 141–144 FPS, not a hardware guarantee or a city-wide performance result. Worst tested near damage view had 1,832 image labels. Later checks must include movement and the final return geometry before increasing scope.

Evidence under `tools/source_slices`: `facade_section_manifest.json`, `facade_section_survey.json`, `facade_section_report.json`, `facade_section_verification.json`, `facade_section_geometry_tests.json`, `facade_section_glass_contracts.json`, and `facade_section_native_play.json`. `tools/verify_facade_section.luau` is the independent Edit audit; `verify_facade_section_live.client.luau` is an optional temporary native Play probe and is not initialized by normal startup.

## Preservation and reproduction

The source buildings, cores, roads, terrain and both generators were not changed by v6. The two v5 local terrain backups remain the only live facade approach terrain edits: `orph_-318_-751_8_final` and `orph_-318_-751_20_final`, 82 occupied voxels with bounded requested shifts. See the v5 handoff for exact restore instructions. No additional terrain repair is authorized implicitly by this expansion.

Registry: `ServerStorage.GroundFacadePilotManifest`; owned child on each selected building: `GroundFacadePilot`; stable owner: `2026-10-08-ground-pilot`. Before each replacement, owned facades and manifest are archived in `ServerStorage.GroundFacadePilotArchive`. Clear removes only owned additions. For future reapplication, survey again after source/road/terrain changes; preserve stable identity and separate geometry/name/advertisement seeds.

Fresh edit helper modules are in `ServerStorage.FacadeSectionRuntime`; normal Rojo module sources were synchronized explicitly. Some historical helper clones are retained for recovery; use current named modules. Save the Studio place to persist the live map. The portable kit and per-section manifest are not a full place backup.

## Overnight review scope

Same-thread follow-up `overnight-ground-facade-review` was paused after the six-hour cutoff. Studio is in Edit and temporary verification LocalScripts were removed. The built-in screenshot export timed out and the older connector was disconnected; a native desktop office review image was subsequently captured as `tools/preview/facade_section_office_native.png`. The owner then stopped Computer Use, so no further UI actions or place save were attempted.

The final 6,328-part moving-camera probe completed a 30-second route with all 175 panes present and zero generated upper/far parts. It measured 28.023 ms mean, 29.146 ms p95 and 97.684 ms max (35.68 FPS). Studio was not foregrounded for this run, so it is not directly comparable to the earlier stationary samples and cannot isolate facade cost. Saved as `facade_section_route_play.json`; do not use the earlier stationary numbers as a moving-camera performance claim.

Continue visual checks, movement/performance checks and corrections on these same 32 buildings until the cutoff or usage exhaustion. Save screenshots and clear temporary Play helpers. Keep the raised looping glass demo and owner spawn. Upper floors may receive design notes or isolated drafts after ground verification; generated upper glass stays disabled and city-wide deployment remains a separate decision. Native screen capture previously omitted terrain known to raycasts; do not interpret sky in an exported capture as missing live terrain.

Read-only second review found no blocking defect in the applied section. Before a broader rollout, add a volume-overlap fallback for thin source obstructions missed between the nine pane samples, and make building indexing footprint-aware rather than testing model origins alone. These are limits of the current compact-trial proof, not measured failures in its saved audit.
