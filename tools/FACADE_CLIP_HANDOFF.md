# Ground facade clip-on trial v8 — October 10, 2026

## Current truth and scope

The owner requested exterior facades on the outside floor perimeter, with interior dressing allowed inward, a check of every previous trial location, then a large ordinary-building section, Roblox save and GitHub push. This supersedes v7's 32-building expansion limit. The live map is TestJJK, place 99539622209675. GitHub branch: shibuya-level-curves. Cloud save confirmation is recorded below after final validation.

The section has **200 ordinary buildings, 1,911 complete ground runs, 94,472 added BaseParts, 6,431 physical glass panes, 659 portals, 3,146 supported stair parts and 51 supported planter groups**. It retains the original 32 buildings and selects nearby ordinary buildings around (-318,85,-751), radius 1,150 studs, capped at 200. Neighbor surveying extends to 1,550 studs and includes buildings whose footprints intersect that area. Seven coherent building palettes are used: cream 23, white 29, offwhite 26, grey 26, charcoal 30, darkBrown 31 and stone 35. Tenant names and geometry remain independently seeded.

Landmarks and interesting crowns are excluded. Original terrain, roads, floors, cores, generator code and destruction handling were not edited. Raised gallery, glass demo, spawn and lime/magenta markers are retained. Upper glass generation and far proxies remain disabled.

## Exterior and interior mounting

Shared/FacadeMount is the common contract. Local -Z faces the street. The run frame sits **0.75 studs outside the actual source floor outline**. Every flagged exterior part's rear vertices stay at local Z <= 0.45, leaving at least 0.30 studs between its rear face and the outline. Pane and metal door centers use Z=0.15. The fitter may move an entire run farther outward by at most 1.25 studs; the final section requires zero additional outset.

Frames, doors, signs, wall panels and trim therefore clip onto the perimeter. Their positions no longer inherit deep shop recesses. Interior previews have a separate layer and can extend inward. A shallow dark backing prevents a flush concrete core reading as beige wall through a clear window. It is noncolliding, nonqueryable and parented directly to its glass pane. This is a visual fallback, not a complete accessible interior. Deep preview dressing can be obscured by the backing; richer parallax interiors are future work.

Privacy film and advertisements are snapped to actual pane surfaces. Backing, film and advertisements hide with state 3 and are destroyed with state 4; state 3 leaves only the broken edge presentation over a transparent, noncolliding pane. Existing client shard bursts and damage-ring behavior remain unchanged.

The same coordinate contract can span the space between successive floor outlines for upper facades. No upper floors were installed in this change; see UPPER_FACADE_APPROACH.md.

## Placement and regional repairs

Street and usable pedestrian frontage can have shops and entrances. Close neighboring geometry, inaccessible elevation and actual blocked approaches veto entries per bay. Quiet neighboring faces use walls or high windows. Oversized or unusually short wall runs receive complete plain infill instead of invalid stretched kit geometry. Step and planter supports still sample local ground. Vehicle ramps remain filled WedgeParts.

The initial expansion exposed 44 blocked bays across 17 buildings when new neighboring facades and footings were considered together. Those bay vetoes are persisted in the final manifest. Open produce shops were also corrected: their entire open front is now declared as a portal and must pass the same verified 22-stud interior-clearance check as open parking/loading bays. A failed open shop receives closed glazing; no source core is cut to create space.

## Verification and evidence

Final Edit checks covered all 200 buildings and all 1,911 runs:

- 176,685 coverage samples: zero unintended holes. Verified open parking/loading/shop portals are excluded from solid-wall coverage.
- 6,431 exact pane-versus-own-source volume checks: zero intersections.
- 57,785 exterior parts: all rear vertices satisfy the outside mounting contract.
- 57,879 visibility rays: zero unintended opaque pane occluders. Intentional clinic privacy panels and workshop half shutters are exempt.
- All stairs and planter supports passed their ground checks.
- 273,345 original BaseParts across all 2,227 source models retained exactly their CFrame, size and color.

Screenshots in preview/clip_trial cover one reviewed view at each of the previous 32 locations, plus ten distributed examples from the expansion. This is not a claim that every wall was manually photographed; every run was covered by geometry checks. Some quiet rear walls still overlap existing neighboring source geometry/footings, and old orange road pieces remain conspicuous in some views. These map issues were preserved. The glass/entrance clipping defect passes the final audits.

Play checks and save confirmation are appended below. Short local frame timings are smoke checks, not production or multiplayer performance budgets.

## Reproduce, continue and roll back

Open the saved TestJJK on the other device, pull this GitHub branch, then connect Rojo for scripts. A fresh default Rojo build and the older root JJK_Roblox.rbxl do not contain the live city checkpoint. Historical disk section JSONs and reusable stock assets remain older checkpoints.

The authoritative current manifest/report is ServerStorage.GroundFacadePilotManifest, report revision 8. Preserve its final bayRoles vetoes. The current isolated Edit helper is ServerStorage.FacadeClipRuntime; it contains fresh clones of the relevant Shared and Server modules with dependency paths adapted for that folder. Live production script sources match the repo. Fresh helper clones avoid Studio's cached require results.

To rebuild the same section, decode the current manifest and call GroundFacadePilot.Apply(rows, GroundFacadeFrontage.Index(Vector3.new(-318,85,-751),1550)) through fresh helper modules. The selector GroundFacadeSection.Select(center,radius,limit,existing) is Edit-only, bounded and never runs on require or game startup. A new survey may change frontage; replay the saved manifest to preserve the reviewed trial. Always rebuild the frontage index before each Apply because cached owned instances belong to the previous installation.

GroundFacadePilot.Apply stages per building and archives the previous owned facade children and manifest in ServerStorage.GroundFacadePilotArchive. Source building parts are not deleted. Pilot.Clear removes only owned facade children. Retain the archive for rollback.

tools/verify_facade_visibility.luau is a repeatable read-only check of live opaque occlusion, supports and manifest coverage. tools/verify_facade_clip.luau additionally checks the outside geometry contract and original source preservation; it requires an in-session _G.ClipOriginal snapshot captured BEFORE Apply. Snapshot each original BasePart's CFrame, Size and Color, excluding descendants of GroundFacadePilot. Keep that snapshot inside Studio; no bulk source geometry export is needed.

## Performance boundary and next work

This is a large bounded trial, not a city-wide LOD implementation. Ground facade geometry remains anchored replicated geometry; damage texture detail is distance gated at 220/260 studs. All 6,431 ground panes remain physical parts. Upper generation and far proxies are off. There is no new per-pane server heartbeat or shard physics.

94,472 added parts are substantial. Before full-city or upper-floor rollout, reduce repeated opaque trim/preview geometry, measure memory and fast movement on target devices, and design consistent near/medium/far representations that preserve pane IDs and state 4 holes. Do not infer a shipping budget from this Edit audit or a short local Play route.

## Final Play and build results

All 6,431 trial panes were present in Play. A cloned installed pane passed states 1 → 2 → 3 → 1 → 4, including backing restoration/hiding and attached advertisement GUI hiding. Near generated buildings/parts and far buildings were all zero. Server/client initialization completed without runtime errors; the console camera-reset warning came from the MCP inspection tool. Temporary test panes, scripts and route data were removed when returning to Edit.

A 24-second six-view local camera route, excluding the first three seconds, recorded 1,368 frame samples: mean 15.36 ms, p95 23.29 ms, maximum 68.14 ms. Views changed every four seconds with a small lateral camera movement; this measures local Studio frame intervals and includes view transitions, not multiplayer or target-device performance. Both the default script project and the standalone ground-facade project built successfully.

## Roblox checkpoint

Native Studio Save to Roblox confirmed: **October 10, 2026, 17:50:59 America/Indianapolis** — “Saved new changes in TestJJK to Roblox.” Evidence: preview/clip_trial/save_v8.png. This checkpoint contains the 200-building v8 geometry, live manifest, current script sources and updated ProjectFiles handoff. Open this cloud place for the actual city; GitHub contains the scripts, documentation and review images.

Image numbering 01–32 follows the first 32 manifest/report rows. Expanded images 1–10 are distributed examples at rows 39, 54, 67, 85, 102, 117, 138, 155, 173 and 189. play_gallery_retained.png confirms the raised gallery and owner spawn are retained; it is not route performance evidence.
