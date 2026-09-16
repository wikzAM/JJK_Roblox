# Shibuya source-slice reconstruction handoff

Updated September 16, 2026. This is the operational resume point for a Cursor agent, including Opus 5 or 5.6 Sol medium. Read `src/client/ProjectFiles.luau` first, then this file. This file's **current source-slice work** follows the older generation history in ProjectFiles.

## Current status — read before doing anything

- User wants complete, clean floors cut from the **actual FBX building envelope**, with a coherent core and one logical `Building` model per physical building. They explicitly prefer individual buildings; sectors may organize processing, but must not merge building ownership.
- The previous pass eliminated jagged `BuildingAuto_*` models using smooth approximations. It did **not** solve source identity, complete outlines, overlapping sections, or duplicate cores. Its structurally valid model count is not a count of real buildings.
- Last confirmed live baseline: **3,190 `BuildingSmooth_*` models**, **11,731 floors**, **174,531 structural parts**, including **101,782 wedges**, plus preserved `Building1`, `Building2`, `Building3`. Re-query Studio before trusting this after a restart or another agent's work.
- **No source-slice geometry has been staged or applied.** `SourceSliceBuilder.luau` and `SourceSliceReplacement.luau` have been written but are **untested**. Their agents hit usage limits before verification. No source-slice verification files exist yet. Review and test these modules before use, even if Rojo has synced them.
- `live_buildings.json` is complete: **3,193 records**, exported in 300-model chunks to avoid MCP's response limit. The 16 reference mesh transforms and raw FBX export are also complete. Re-export after applying changes; this inventory is the pre-source-slice baseline.
- Source coordinate alignment now passes **174 live-vertex comparisons**, maximum error **0.00067947 studs**. Transform is recorded below. Source polygonization is being explored; no real building plans are certified yet.
- Existing map changes may be unsaved: MCP does not provide Studio's Save to Roblox/File action. Never infer a saved map from a successful source build or source sync.

## Tools and connection

Workspace: `D:\GameDownloads\JJK_Roblox`.

Use the **official capitalized** Roblox MCP tools (`mcp__Roblox_Studio__...`) for inspection and Luau execution. `list_roblox_studios` currently reports TestJJK, Studio ID `ef23da77-5868-44cf-b310-e9d5ec4e0817`; last reported state is Edit. Re-list after a restart. The similarly named lowercase `mcp__robloxstudio...` connection timed out/disconnected: do not waste repeated attempts on it.

For `execute_luau`, return a compact result (`return ...`); do not rely on `print`. The sandbox has **`_G == nil`**. Persist plans/stages in DataModel instances or files, not `_G`. Responses truncate at roughly 100,000 characters; return summaries or bounded chunks. Inspect the actual tool schema before calling it.

Blender is installed at `D:\Blender\blender.exe`. The supplied FBX is `C:\Users\anubh\Downloads\Shibuya.fbx`. The open Blender scene is unsaved; leave it intact. The exporter runs a **separate background Blender process** and resets only that process's scene:

```powershell
& 'D:\Blender\blender.exe' --background --python 'D:\GameDownloads\JJK_Roblox\tools\export_shibuya_fbx.py'
```

Python geometry libraries (Shapely, SciPy, Matplotlib) were installed locally in `tools/python_deps`. Use the bundled Python runtime already discovered by the parent, or rediscover it through `load_workspace_dependencies`; its exact executable path has not yet been recorded here. Set the dependency path only for the task's Python process. Do not reinstall blindly.

## Files and what they mean

- `tools/export_shibuya_fbx.py`: imports supplied FBX in background Blender, exports world-space mesh vertices and loop triangles.
- `tools/source_slices/fbx_raw.npz`: completed raw export. Arrays are `v0`, `f0`, `v1`, `f1`, etc.; vertices are float64, triangles int32. Coordinates are Blender/FBX space; apply the verified global transform below.
- `tools/source_slices/fbx_summary.json`: completed per-mesh names, indices, counts and min/max bounds. FBX names are `surfaceMember...`; these are mesh chunks, not individual building IDs.
- `tools/source_slices/live_meshes.json`: completed 16 Roblox reference mesh CFrames (12 numbers) and Sizes (3 numbers); repeated name `Shibuya` is not unique identity. Align by geometry/bounds and verify orientation and scale.
- `tools/source_slices/live_buildings.json`: 3,193 baseline model names/bounds and available attributes; not a building ownership classification.
- `tools/source_slices/live_vertex_samples.json`: 174 reference-mesh world-space samples used to verify alignment.
- `tools/source_slices/alignment.json`: recorded global transform and numerical checks. **Do not independently scale mesh chunks to their Roblox bounding boxes:** some imported chunks lost extrema, and separate fits would pull shared geometry apart.
- `tools/source_slice_pipeline.py`: offline preparation and initial horizontal polygonization. Runs using the Python runtime with dependencies in `tools/python_deps`; command is `python tools/source_slice_pipeline.py` after choosing the proper executable. The in-progress `world_triangles.npz` output must open successfully before reuse. The script currently explores several citywide slice heights; it does not produce approved building replacement plans.
- `src/server/SourceSliceBuilder.luau`: new explicit floor-piece builder; **untested**.
- `src/server/SourceSliceReplacement.luau`: new explicit many-to-one replacement/rollback helper; **untested**.
- `src/server/PolygonSlab.luau`: existing native Part/Wedge triangulation; previously tested, including actual wedge CSG. Reuse it rather than rebuilding the slab engine.
- `src/server/SmoothBuildingAudit.luau`: useful for the old baseline; old structural success does not establish accuracy against source geometry.

Old maps and `ServerStorage.ShibuyaBefore*` archives preserve earlier generations. Do not delete or bulk overwrite them. `rojo build` produces a scripts-only place, **not a backup of the live hand-built map**.

## Intended geometry pipeline

1. **Use and recheck the verified transform.** For FBX `(x,y,z)`, Roblox world coordinates are `(-x,z,y) * 4.182817489324327 + (117.42021163650827,-4.628656099976979,253.12012546710255)`. Four intact tile centers matched within 0.00079677 studs; 174 reference vertices matched within 0.00067947 studs. The export contains 409,039 vertices and 174,613 triangles. Check several distinctive landmarks and low buildings visually too. Keep source elevation; do not ground everything on the flat terrain.
2. Pick a small, visually identifiable test area containing a simple building, a setback/tower building, and a compound building currently split into overlapping cores. Start from source triangles, not archived occupancy grids or previous convex hulls.
3. Intersect triangles with horizontal floor planes. Weld only numerical endpoint noise, polygonize closed loops, preserve real concavities and courtyard holes, and report open contours. Cross-sections must change where the actual envelope changes.
4. Track connected floor regions vertically and reconcile touching/overlapping source components into **physical building ownership**. Mesh chunk or connected component IDs alone are not building IDs. A podium and its tower should not acquire competing overlapping floors and cores. Bridges must not automatically merge two neighboring buildings.
5. Construct valid non-overlapping polygon pieces for each complete floor. Any triangulation/decomposition must preserve the union and holes; do not fill a convex hull across a recess. Strip roof equipment only with explicit evidence and recorded tolerances.
6. Select one core rectangle that is contained in every relevant floor union. Reject or explicitly review structures without a viable common core. Do not split a building into several overlapping models merely to make core placement pass.
7. Stage new models, check real floor coverage and inter-building overlap, visually compare source and preview, then atomically replace **explicitly identified complete old models**. Keep full originals in an archive. Start with the test section; broaden only after it passes.

Do not call the entire map finished because there are zero invalid parts. Current failures are semantic/geometry completeness failures, not merely primitive validity failures.

## New builder contract (provisional; verify against current code)

`SourceSliceBuilder` accepts:

```lua
{
    id = "stable_building_id",
    origin = {x = 0, y = 0, z = 0}, -- Roblox world origin
    levels = {
        {y = 0, thickness = 1.5 / 0.28, pieces = {
            {{0, 0}, {30, 0}, {30, 20}, {0, 20}}, -- local X/Z polygon
        }},
        -- ascending levels; final level is Roof
    },
    core = {minX = 5, minZ = 5, maxX = 15, maxZ = 15},
    sourceInfo = {}, -- JSON-compatible provenance
}
```

- `Validate(plan)` checks shapes, level clearance, piece overlaps and common-core coverage.
- `Build(plan)` returns an unparented `BuildingSourceSlice_<id>` model.
- `StagePlans(plans)` returns a ServerStorage stage and failure list. Require zero failures for a complete replacement set.
- `Audit(modelOrFolder)` is read-only. Inspect `summary.badBuildings` and errors, not just a successful return.
- `Regenerate(model)` retains its plan and archives the old interior; moved-model behavior still needs verification.

Important details: polygons use local X/Z pairs; level `y` is relative to `origin.y`; final level is the roof; minimum floor-to-ceiling clear is 2 m; core bounds describe its outer walls; one core spans the levels. Metadata includes `SourceSlicePlan`, `SourceSliceId`, `SourceSliceOriginCFrame`, `SourceSliceSavedPivot`, `CoreCFrame`, `CoreSize`, `InteriorBBoxCFrame` and `InteriorBBoxSize`. No furniture layer is generated.

## New replacement contract (provisional; verify against current code)

`SourceSliceReplacement` never guesses ownership spatially:

1. `Capture(stage, sources)` binds the exact current old model instances and snapshots their geometry/identity. Sources must be explicit `BuildingSmooth_*` or prior `BuildingSourceSlice_*` models in `Workspace.Buildings`, with source identity attributes. New outputs must be a complete replacement for the bound set.
2. `Preview(stage, "before"/"after")` temporarily shows the selected generation.
3. **Always `Restore(stage)` before Apply or saving.** Ensure the source originals are back and disposable previews gone.
4. `Apply(stage)` revalidates unchanged bound geometry, audits the outputs, installs them and archives originals into `ServerStorage.ShibuyaBeforeSourceSlice_<guid>`.

Read the implementation before first call; this has not passed fixtures yet. Do not weaken snapshots just to make an apply succeed after changes. Recapture a fresh, verified stage instead.

## Required next work, in order

1. Re-list Studio and confirm **Edit**, current counts, presence of the 16 reference meshes, and any existing source-slice stage/preview/archive. Do not assume interrupted calls did nothing or that transient globals survived.
2. Validate that the 3,193-record live-model inventory still matches the current scene and that `world_triangles.npz` opens. Do not remove anything from a model's bounds alone.
3. Review both new modules. Create and run meaningful fixtures: rectangle; concave outline; courtyard represented by pieces; changing setback; overlapping pieces rejected; no-common-core rejected; moved regeneration; exact many-to-one apply and restore; stale-source mutation rejected; rollback retains all originals. Verify Parts/Wedges stay anchored/collidable and usable by existing CSG destruction.
4. Visually confirm the numerically verified FBX-to-Roblox transform. Produce the small real section plans and source-versus-slice coverage metrics. The present global polygonization is exploratory: open contours, holes and physical ownership still need resolution.
5. Stage the real sample, run geometry and structure checks, use a few Studio screenshots/camera comparisons, then explicitly bind its old models. **No whole-map overwrite.**
6. Apply only the validated sample; record model IDs, source IDs, counts, archive name and screenshots/validation evidence here. Expand to more buildings once the sample genuinely fixes shape and duplicate-core issues.
7. Save the full Studio map through Studio's UI and confirm the save, plus a local full-map copy when possible. Update this file and the authoritative ProjectFiles handoff with exact applied/saved status. Never describe merely synced scripts as an applied or saved city.

## Constraints that must survive the handoff

- Destructible models retain the `Building` prefix; HitHandler uses it. Structural geometry must be native `Part`/`WedgePart`/Union, not reference MeshParts.
- Preserve per-building identity, floor polygons and facade boundary data for later scripted windows/exteriors. Sectors are optional folders/batch limits, not a substitute for building ownership.
- Preserve the 3 intentional original buildings, Shibuya reference meshes, furniture/templates, existing archives and user edits. Do not use source raw triangle count or generated model count as a target.
- Do not change combat/destruction logic, player movement preferences, or terrain during this reconstruction task unless an actual compatibility fix is necessary and explained.
- User authorizes inspection, generation, recoverable cleanup and saving. Prefer MCP over repetitive UI input. Use UI only for visual inspection and app-only operations such as Save.
- Earlier credit cap was $90; there is no reliable per-task dollar meter. Avoid repeated full-map rebuilds, huge tool dumps or repeated disconnected-MCP retries.

## Update discipline

The handoff agent owns only this file. After each milestone, replace the status and next-step facts rather than accumulating a transcript. Every update must distinguish **written**, **tested**, **staged**, **applied** and **saved**. Include exact archive names and unresolved errors. An interrupted worker should be able to resume without guessing or repeating destructive work.
