# Optimization research: instance count, memory, save size (2026-10-18)

Research only. No game logic was changed. Scope: the Shibuya place at ~1.38M instances,
~904k Workspace BaseParts, ~626k ground-facade parts (2078 roots, 19,664 runs, ~301
facade parts per building), Studio OOM on a 16 GB machine, Team Create save disconnects.

Confidence tags: **[doc]** current Roblox Creator Hub docs, **[staff]** Roblox staff
DevForum post, **[community]** non-staff DevForum report, **[local]** measured in this
repo (see `src/client/ProjectFiles.luau`), **[est]** my estimate, to be measured.

---

## 1. Findings

### 1.1 The binding limit is server and edit-server memory, not the client

- Live game servers get **6.25 GiB + 100 MiB x peak players** **[staff, doc]**. Roblox
  staff confirmed the Creator Docs figure (6,400 MiB) in Sept 2025.
  <https://devforum.roblox.com/t/server-memory-formula-inaccurate-on-creator-docs/3913740>,
  <https://create.roblox.com/docs/performance-optimization/identify#server-memory>
- When an RCC (Roblox server process) nears its memory limit it "gracefully shut[s] down and disconnect[s] all players"
  (error 288). That thread's server had ~931k instances. Staff (May 2025): most servers
  run "fewer than about 1 million instances" **[staff]**.
  <https://devforum.roblox.com/t/servers-crashing-error-288/3303682>
- This place has **~1.38M instances**. Measured cost was 6.4 KB per part in Studio:
  PhysicsParts plus Instances alone are ~5.3 KB per part **[local]**. At 904k Workspace parts that
  is roughly **4.6 GiB of server memory before scripts, terrain and ServerStorage** **[est]**.
  So the place is at or over a live server's budget. The project notes mention a "server288
  shutdown" in the historical logs, which is consistent with this.
- I found no published spec for the Team Create edit server's own memory cap. It is
  presumably an RCC with a similar budget **[est]**. Fewer stored instances helps both.
- **Instance streaming does not reduce server memory or Studio edit memory.** The server and
  Studio still hold the whole DataModel. Streaming only trims client memory and join time
  **[doc]**. <https://create.roblox.com/docs/workspace/streaming>
- So to fix OOM and disconnects, **stop storing decorative parts in the place**.

### 1.2 Place size and Team Create saves

- Hard limit **100 MB (104,857,600 bytes)**. Saves and publishes may fail above it. The uploaded
  size is "slightly smaller" than the `.rbxl`. With collaboration on, a failed save writes
  the last three attempts as recovery files **[doc]**.
  <https://create.roblox.com/docs/projects/place-files>
- Staff are investigating a case where the upload-time serialization measured 158.9 MB
  for a 72.6 MB local file **[staff]**. The ~73 MB place here may already be near the
  real limit. <https://devforum.roblox.com/t/726-mb-game-returns-the-place-is-too-large-when-trying-to-publish-it-as-another-game/4037386>
- Older reports: HTTP 413 at ~124 MB, and "File too large" now appears in Output **[community/staff]**.
  <https://devforum.roblox.com/t/team-create-place-too-large/1015366>
- The docs' size levers are: delete redundant parts and instances, simplify terrain (horizontal
  layers compress best), use Box/Hull collision on meshes, and split into places **[doc]**.

### 1.3 Streaming (for client memory, join time, FPS)

- Recommended settings **[doc]**: `StreamingEnabled`, `ModelStreamingBehavior=Improved`,
  `StreamOutBehavior=Opportunistic` (the default is LowMemory; Opportunistic "reduces memory
  use and out-of-memory crashes"), `StreamingMinRadius=64`, `StreamingTargetRadius=1024`,
  `StreamingIntegrityMode=PauseOutsideLoadedArea`.
  <https://create.roblox.com/docs/workspace/streaming/techniques>
- ModelStreamingMode values **[doc]**:
  - **Atomic:** the whole model streams together.
  - **Persistent:** never streams out and permanently uses memory. Use it sparingly.
  - **PersistentPerPlayer:** persistent only for chosen players.
  - **Nonatomic/Default:** with Improved behavior, streams per part.
  Keep model extents small, around 64 studs. Flatten nesting: a Persistent model inside an
  Atomic one makes the parent persistent.
  <https://create.roblox.com/docs/reference/engine/enums/ModelStreamingMode>,
  <https://devforum.roblox.com/t/upgrades-to-model-streaming/2699921>
- **Client-created instances are exempt from stream-out unless parented under a
  server-created instance** **[doc]**. Client-built facades must live in a client-owned
  folder, not inside the streamed building Model.
- Client `GetChildren`/`GetDescendants`, raycasts and spatial queries see only streamed
  content. Use CollectionService Added/Removed signals, which fire on stream in and out
  **[doc]**.
- `Player:AddReplicationFocus()` and `RequestStreamAroundAsync()` pre-load areas before
  teleports **[doc]**. This matters for the 600 studs/s dummy and WalkSpeed 256.

### 1.4 LOD: SLIM / Model.LevelOfDetail

- SLIM replaced StreamingMesh LOD as of the late-2025 roadmap. It merges distant models into
  composite meshes and cuts draw calls, triangles and memory **[doc]**.
- Requirements: StreamingEnabled, place saved to Roblox, Team Create on **[doc]**.
- Caveats **[doc]**:
  - **Adding or removing parts or changing geometry at runtime "prevents SLIM from rendering the model correctly."**
  - Unions may render wrong.
  - Coplanar faces z-fight.
  <https://create.roblox.com/docs/workspace/streaming/slim>,
  <https://devforum.roblox.com/t/creator-roadmap-2025-rdc-update/3961527>
- **Implication:** SLIM conflicts with CSG destruction. At best it is an experiment for
  far-field rendering, and a hit building would need to leave SLIM. Whether
  LevelOfDetail can be switched at runtime is **unverified**.

### 1.5 CSG at runtime (GeometryService)

- The improved GeometryService CSG APIs reached full release on 2025-11-12. They are faster and crash less, and
  "all new features, fixes and performance improvements" target GeometryService **[staff]**.
  <https://devforum.roblox.com/t/full-release-improved-constructive-solid-geometry-csg-apis/4065505>
- Current GeometryService docs: `SubtractAsync`/`UnionAsync`/`IntersectAsync` accept
  "Primitive Parts, PartOperations, and **MeshParts**". If any input is a MeshPart, the
  outputs are MeshParts. Also listed: `FragmentAsync` + `GenerateFragmentSites` (Voronoi
  fracture into MeshParts), `SweepPartAsync`, and the options `CollisionFidelity`/`RenderFidelity`/`SplitApart` **[doc]**.
  <https://create.roblox.com/docs/reference/engine/classes/GeometryService>
  - **This contradicts CLAUDE.md** ("SubtractAsync fails on MeshParts"). That rule holds
    for the legacy `BasePart:SubtractAsync`. Verify with a 5-minute in-engine test before
    relying on GeometryService with MeshParts.
- Staff say GeometryService works in LocalScripts **[staff]**. Bandwidth and replication
  improvements for CSG results were listed as future work, so each carved slab still
  replicates a new mesh.
- Community voxel systems use greedy meshing, part caching and client offload. One
  estimated a practical ceiling of ~730k parts **[community]**.
  <https://devforum.roblox.com/t/voxeldestruct-21-voxelated-destruction-physics-with-greedy-meshing-hitboxes-and-more/3044264>,
  <https://devforum.roblox.com/t/voxel-destruction-system/3864250>

### 1.6 EditableMesh / dynamic meshes

- Limits **[doc]**:
  - **60,000 vertices / 20,000 triangles** per EditableMesh.
  - Clients have **strict, unpublished memory budgets** ("currently expensive").
  - Published games need "Enable Mesh / Image APIs".
  - Display needs `AssetService:CreateMeshPartAsync(Content.fromObject(mesh))`.
  <https://create.roblox.com/docs/reference/engine/classes/EditableMesh>
- Measured costs from one developer **[community]**:
  - CreateMeshPartAsync costs about **22 ms fixed plus 0.27 ms per 1k triangles**. It cannot be split across frames.
  - Another developer hit the budget at ~8 meshes.
  <https://devforum.roblox.com/t/allow-applying-baked-mesh-content-to-a-meshpart-without-a-lag-spike/4752538>,
  <https://devforum.roblox.com/t/editablemesh-restrictions/4566101>
- **Verdict:** not a fit for ~2000 buildings' facades. Maybe later for a handful of far-field
  district impostors.

### 1.7 Rendering, instancing, flags

- Draw calls **[doc]**:
  - Parts of the same shape and meshes with the same MeshId are GPU-instanced.
  - Decals/Textures/particles "batch poorly".
  - Use CastShadow=false on small or distant parts.
  - Layered transparency causes overdraw.
  <https://create.roblox.com/docs/performance-optimization/improve>,
  <https://devforum.roblox.com/t/rendering-updates-september-2017/54148>
- Collision **[doc]**:
  - Set CanCollide/CanTouch/CanQuery false where they are not needed.
  - Box/Hull fidelity for meshes and unions; collision geometry is "still stored in memory" even when collisions are off.
  - For primitive Parts, fidelity does not apply.
- **[local]** Setting CanTouch=false on 16,698 wedges saved 0.0 MB, so the flags are not a
  memory lever here. CastShadow=false helps FPS, not memory.
- Unions vs MeshParts: each union is a unique asset and is not instanced. MeshParts that
  reuse one MeshId instance well **[community, mixed evidence]**.
  <https://devforum.roblox.com/t/unions-vs-meshparts-2023/2638232>
- Custom materials (MaterialVariant) tile by `StudsPerTile` with no extra instance per part.
  `Texture` has per-instance `StudsPerTileU/V` and `OffsetStudsU/V`, so it can align to bays.
  Texture memory scales with pixel count, not file size **[doc]**.
  <https://create.roblox.com/docs/parts/materials>
- Script-built instances **[doc]**: set Parent last, after all properties. Pool and reuse
  instances. Avoid creating and destroying large trees on the server, which is "very network intensive".
  <https://create.roblox.com/docs/reference/engine/datatypes/Instance>

### 1.8 Client-side generation from compact data

- Common pattern **[community]**: seed- or recipe-driven client generation, with the server
  replicating only the seed or data and notifying clients of changes.
  <https://devforum.roblox.com/t/how-are-large-terrain-maps-possible/3890299>,
  <https://devforum.roblox.com/t/rochipelago-a-fully-customizable-non-voxel-procedural-blocky-island-generator/4734869>
- Effects should be created on each client; the server sends only the location **[doc]**.
- **This repo already does this for upper floors.** `FacadeRenderer` builds geometry
  within NearRadius 700 / DetailRadius 220 on a 2 ms frame budget with pooling.
  `GlassDamageService` keeps sparse logical pane damage on the server. `GroundFacadeInteriors`
  builds rooms client-side from `FacadeBayInteriorPlan`. `GroundFacadeKit.BuildRun` is in
  `ReplicatedStorage.Shared` and requires only shared modules, so a client can already call it.
  The ground facades are the outlier: they are saved as 626k server parts.

### 1.9 Measurement tools

- Developer Console Memory **[doc]**:
  - PlaceMemory: Instances / PhysicsParts / PhysicsCollision / GraphicsParts / GraphicsMeshParts / GraphicsTexture.
  - PlaceScriptMemory.
  - Luau Heap snapshots.
  <https://create.roblox.com/docs/studio/optimization/memory-usage>
- From scripts: `Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.X)`,
  `Stats:GetTotalMemoryUsageMb()`, `Stats.InstanceCount`, `Stats.PrimitivesCount` **[doc]**.
  <https://create.roblox.com/docs/reference/engine/classes/Stats>
- Use the MicroProfiler (Ctrl+F6) for frame spikes from client build bursts and CSG.
- Studio memory leaks reported in 2025-2026 **[community]**: Script Analysis leaking ~1 GB/min in
  places with huge table-literal ModuleScripts, and the new Luau type solver adding ~2-4 GB.
  Check these before blaming geometry.
  <https://devforum.roblox.com/t/studio-leaks-1-gbmin-of-memory-while-idle-when-script-analysis-is-enabled-grows-to-100-gb-then-crashes/4743637>,
  <https://devforum.roblox.com/t/roblox-studio-using-40gb-of-memory/3975130>

---

## 2. Ranked changes for this codebase

"Inst" = instances in the place, which drives Studio, edit-server and live-server memory and save size.

| # | Change | Inst / memory | Client FPS | Save size | Effort | Risk | Files |
|---|---|---|---|---|---|---|---|
| 1 | **Ground facades built on the client from recipes**; server keeps 1 proxy per run | **-590k parts (~-43% of the place, ~-65% of Workspace parts)**, ~-3 GiB server [est] | + (only ~R-radius built) | large drop [est 30-50%] | M-L (1-2 wk) | M | new `src/client/GroundFacadeBuilder.luau`, `src/shared/GroundFacadeRecipe.luau`, `HitHandler.luau`, `GroundFacadePilot.luau`, `GroundFacadeInteriors.luau`, `GlassDamageService.luau` |
| 2 | **Move archives/backups out of the place** to `.rbxm` files | -150k to -290k instances (ServerStorage) | 0 | -10-20% [est] | S (hours) | L (needs owner approval) | `tools/cleanup_facade_archive_geometry.luau`, ledger |
| 3 | **Upper-floor facades client-only from day one** (flat textured bands; cells only near or damaged) | avoids +200k to +1M future parts | + | avoids growth | M | L-M | `FacadeRenderer.luau`, `FacadeLayout.luau`, `GlassGeometry.luau`, `GlassConfig.luau` |
| 4 | StreamingEnabled (Improved, Opportunistic, Target 1024-1536) | client memory only | ++ | 0 | M | M-H (fast movement, client scripts) | `default.project.json`, `HitHandler.luau`, `ClickInput.luau`, `FacadeRenderer.luau` |
| 5 | Apply the same client-recipe treatment to other **NoCSG** decoration (crown wedges, deco, furniture), since hits delete these anyway | -100k+ [est; crowns were 70% of a source-slice building] | + | drop | M | M | `HitHandler.luau`, crown builders |
| 6 | Crown box-fitting in building yaw frame (4 wedges to 1 part; closed box 24 to 1) | -x0k [local estimate pattern] | + | drop | M | L | `CrownBoxes.luau`, `CrownParapet.luau` |
| 7 | Studio hygiene: Script Analysis off for big ModuleScripts, avoid new-solver blowups, keep `ResetWaypoints` after bulk ops, no Play with <2 GB free | Studio RAM only | 0 | 0 | XS | L | none |
| 8 | CastShadow=false on facade trim, CSG fragments with `CollisionFidelity=Box` for small debris | ~0 memory | + | 0 | XS | L | `GroundFacadeKit.luau`, `HitHandler.luau` |
| 9 | Coplanar merge (`GroundFacadeCompact`) | ~-36k (~2%) [local] | small | small | M | M | skip; superseded by #1 |
| 10 | SLIM LOD | client draw calls | + | 0 | S | H (incompatible with runtime destruction) | experiment only |
| 11 | EditableMesh facades | none or negative | ? | 0 | H | H | do not do |

---

## 3. Phased plan

**Phase 0: baseline and quick wins (1-2 days)**
1. Record a baseline in Play (server and client) and in Edit:
   - `Stats.InstanceCount`
   - `GetMemoryUsageMbForTag` for Instances, PhysicsParts, PhysicsCollision and GraphicsParts
   - exported `.rbxl` size
   - Write the results to `FACADE_CLOUD_SAVE_LEDGER.md`.
2. Change #2 (archive offload), after owner approval.
3. Change #7 (Studio settings).

**Phase 1: client-built ground facades (change #1)**
1. Pilot on 25 buildings.
2. Compare parity: count rows per run against the registry's owned-part counts, plus screenshots.
3. Roll out in 50-building batches with save checkpoints, then remove the server geometry.

**Phase 2: upper floors (change #3)**
- Build all new upper facades only through FacadeRenderer, so no saved parts are added.

**Phase 3: decide on streaming (change #4)**
1. Test with Target 1024, then 1536, at WalkSpeed 256 and with the dummy at 600 studs/s.
2. Get an owner decision, because CLAUDE.md currently rejects streaming.

**Phase 4: structure and decoration**
- Changes #5 and #6. Try SLIM only for never-destroyed far buildings, if wanted.

Exit criteria:
- Place under ~600k instances.
- Workspace BaseParts under 350k.
- Edit memory comfortably under 10 GB.
- Live server under 4 GiB with headroom.

### 3.1 Top change 1: ground facades become client-built from recipes

**What the server and place keep, per building:**
- `GroundFacadeRecipe` (string attribute on the building Model, JSON, version field). It
  replicates and streams with the building. One entry per run, holding the resolved inputs
  that `GroundFacadePilot.build` already computes:
  `{piece, run, key=row.id.."/"..piece.."/"..run, frame=cf:GetComponents() (after outset),
  sourceFrame, width, height, profile, palette, nameSeed, facadeType, allowEntrance,
  bayRoles (numeric keys), footing=[{x,w,depth}], steps=[...], ramps=[...], outset, interiors=[{bay, plan, seed}]}`.
  - Footing, steps and ramps are baked so the client never raycasts terrain, which may not
    be streamed and could differ slightly.
  - Expect ~2-6 KB per building, ~10 MB total [est]. If an attribute gets too long, split it
    per run onto the proxy parts.
- **One `FacadeRunProxy` Part per run**: ~19.7k parts in total, replacing ~626k.
  - Settings: size `width x height x 0.8` at the run frame, `Anchored`, `CanCollide=true`
    (server-side dummy and NPC collision), `CanQuery=true` (so `GetPartsInPart` in
    `destroyAlongCylinder` finds it), `CanTouch=false`, `CastShadow=false`, palette wall
    colour, tag `NoCSG` + `FacadeRunProxy`.
  - It doubles as the **far LOD**: clients set `LocalTransparencyModifier=1` on it while the
    detailed run is built.
- Optionally keep the vehicle `GarageApproachRamp` wedges server-side. There are few of them,
  and they need server collision for vehicles.

**Client (`GroundFacadeBuilder.luau`, modeled on `FacadeRenderer`):**
- Track buildings by a CollectionService tag (`GroundFacadeRecipe`), not
  `workspace.Buildings:GetChildren()`. This keeps it streaming-safe.
- Work queue: runs within **R_build = 450** studs of the camera, nearest first. Drop at **R_drop = 550**.
  - Average ~30 parts per run. The budget is `GlassConfig.FrameBudget` (2 ms) plus a cap of ~8 runs per frame.
  - Set Parent last.
  - Reuse `release`/`acquire` pooling.
  - Start with R_build=450 for buildings ~300 parts each [est]. Tune with the MicroProfiler.
- Build by calling the existing pure `Kit.BuildRun(folder, width, key, profile, frame, opts)`
  with the recipe's opts, then the footing/step rows.
- Parent into `workspace.ClientFacades[buildingId]`, a client-created folder, so it is never
  streamed out with the server Model. Force flags on every part: `CanQuery=false`,
  `CanTouch=false`, `CastShadow=false` for parts under ~4 studs. Keep `CanCollide=true` on
  walkable parts: the local character is client-simulated, so local collision works for
  each player.
- **Interiors:** `GroundFacadeInteriors` registers bays from the builder's build and drop
  callbacks instead of the `FacadeInteriorBay` tag. `usable()` checks the damage capsules
  instead of pane `GlassState` attributes.

**Destruction (hits must still remove facade glass and parts):**
- In `HitHandler.destroyAlongCylinder`, a hit `FacadeRunProxy` takes a new branch instead of `Destroy()`:
  1. Append the capsule `{s=startPos, e=endPos, r=radius, t=hitGeneration}` to the building's
     `FacadeDamage` attribute (JSON array). Cap it at 32 entries; when full, merge into a
     `FacadeDamageAll` flag that drops the run's detail entirely.
  2. If the capsule passes within `r` of the proxy centre-line, also delete or shrink the
     proxy so the server collision gap matches what players see.
- The client applies the **same predicate HitHandler uses today**:
  `distanceToSegment(part.Position, s, e) <= r + part.Size.Magnitude*0.5`, plus
  `GlassConfig.DestructionClearance`.
  - On a live hit: destroy the matching built parts, emit `GlassShards` for glass rows,
    and mark rows within `r + DestructionCrackBand` as cracked via `GlassVisual`.
  - On every later build: filter rows through all capsules first.
  - Late joiners and streamed-in areas get identical damage for free, because the data is a few
    hundred bytes on the building.
- Glass damage from non-hit attacks (`GlassDamageService`): ground panes become logical
  cells keyed `runKey/bayN/paneM`, the same page scheme already used for upper floors.
  `physicalPanes()` then finds nothing for converted buildings, which is intended.
- Structural CSG (slabs, core) is unchanged.

**Edit-time and Team Create:**
- `GroundFacadePilot.Upsert` gains a `materialize=false` mode: it runs placement, fit and
  validation as today, using transient geometry built into a scratch folder that is
  destroyed at the end of each batch. It then writes the recipe and proxies, and calls
  `ChangeHistoryService:ResetWaypoints()`.
- Audits (blockers, SAT, surface) run per batch against transient geometry.
- A preview command `GroundFacadePreview.Show(center, radius)` builds into
  `workspace.__FacadePreview` with `Archivable=false`, and `.Hide()` destroys it.
  - Archivable=false is commonly relied on to keep instances out of saves. **Verify** with
    one save plus a reopen before relying on it, and always `Hide()` before saving.
  - In Team Create the preview replicates to collaborators and to the edit server, so keep
    the radius under ~300 studs.
- Migration per 50-building batch:
  1. Write recipes from the existing manifest rows and reports. No re-solve is needed:
     `r.faces` already has the resolved frame, outset and types.
  2. Check parity in Play: per-run part count and part-name multiset equal to the saved run.
  3. Export the batch's `GroundFacadePilot` folders to a local `.rbxm`
     (outside the place; record SHA in the ledger), then replace them with proxies.
  4. Run `ResetWaypoints`, save, and grep the log for the save confirmation.
  - Rollback: re-import the `.rbxm`, or materialize server-side with the same `Kit.BuildRun`.
- Known pitfall: `PlanRun` vetoes must round-trip with numeric keys. The Studio copy of
  `GroundFacadeKit` has to be synced first; see the 10/18 bug note.

### 3.2 Top change 2: take archives and backups out of the place

- Candidates, from the ProjectFiles notes:

  | Folder | Top-level parts |
  |---|---|
  | `GroundFacadePilotArchive` | ~118k |
  | `GroundFacadeDraftArchive` | ~31k |
  | `FacadeSharedSurfaceBackup_*` | ~8k |
  | `FacadePerPaneInteriorBackup_v2` | ~0.5k |

  - Already preflighted: 0 source-building parts, 0 external references.
  - The Station, Core, LegacyCore and CoreClearance archives (~60k) are the second tier.
  - Keep the registries and manifests, which hold small strings.
- Procedure, one folder at a time, owner-approved:
  1. In Studio, use "Save to File..." on the folder to export a `.rbxm` to
     `assets/archives/<name>_<date>.rbxm`. Keep it out of git or in a Release, like the place files.
  2. Record the size and SHA256 in `FACADE_CLOUD_SAVE_LEDGER.md`.
  3. Leave a `StringValue` stub in ServerStorage with the file name and hash.
  4. Delete the geometry with the existing `tools/cleanup_facade_archive_geometry.luau`.
  5. Run `ResetWaypoints`, then do a verified save.
- Going forward, default `keepReplacedGeometry=false` (already used in rev 11). Archives
  should be recipes plus `.rbxm` exports, never live parts.
- Impact: ServerStorage is never replicated to clients, so this helps Studio, edit-server
  and live-server memory and save size. It does nothing for client FPS.

### 3.3 Top change 3: upper-floor facades never become saved parts

- Use the existing client path: `Geometry.Strips(model)` from `SourceSlicePlan` and
  `FacadeRenderer.BuildInto/BuildFarInto` from shared modules, with damage in
  `GlassDamageService` pages. Turn on `GeneratedUpperEnabled` per building family. The
  server stores **zero** upper facade parts.
- Flat (non-parallax) representation, per face, per storey band:
  - **Beyond DetailRadius (220), undamaged:** 1 Part per face band with one `Texture`
    (window-grid image from a small shared atlas of ~5-8 families, 512x512 or smaller):
    - `StudsPerTileU` = bay width
    - `StudsPerTileV` = floor-to-floor height
    - `OffsetStudsV` aligned to the slab top
    - CastShadow false, CanQuery/CanTouch false
    - ~2 instances per face band instead of ~2 per window.
    Textures batch poorly, so cap texture-banded faces by distance (for example ≤ 700)
    and use the plain coloured `BuildFarInto` beyond that.
  - **Within DetailRadius, or any run with damage:** the existing `Geometry.Split` cells, so
    each pane is addressable and holes are real.
  - Prefer `Texture` over MaterialVariant, because Texture has per-instance tiling offsets for
    bay alignment. MaterialVariant tiling cannot be offset per part [doc gap; verify].
- Destruction: HitHandler (or GlassDamageService) maps the hit capsule to cell keys
  `storey/piece/run:cell` and writes state 4. Clients rebuild that run as cells and drop the
  textured band for the run. That code path already exists (`damagedRuns`).
- Team Create: nothing to save except plan attributes and family choice. Preview in Edit
  with the same `Archivable=false` preview folder.
- Gate before rollout (from `UPPER_FACADE_APPROACH.md`): measure client part count, build
  ms per frame and burst cost on 3 buildings.

### 3.4 Change 4 details (if the owner approves streaming)

- `Workspace` settings:
  - `StreamingEnabled=true`
  - `ModelStreamingBehavior=Improved`
  - `StreamOutBehavior=Opportunistic`
  - `StreamingMinRadius=128`
  - `StreamingTargetRadius=1024` (try 1536)
  - `StreamingIntegrityMode=MinimumRadiusPause` or `Disabled`, to avoid pause modals at WalkSpeed 256
- Leave buildings Nonatomic; they are large and partially destroyable. Keep the HitTarget
  dummy's model Atomic.
- In `HitHandler`, on hit: `player:AddReplicationFocus(dummyRoot)` for each player, and
  remove it at recovery. Do not insert `RequestStreamAroundAsync` before `PivotTo`, because
  it yields and would break the 0.04 s `YIELD_MASK_DELAY` illusion.
- Client modules must be tag-signal driven: `FacadeRenderer` already uses tags partly;
  check its `workspace.Buildings` scans.
- Server memory is unaffected (see 1.1), so streaming is not a substitute for #1 and #2.

---

## 4. Uncertainties to verify in-engine

- GeometryService `SubtractAsync` on MeshParts (docs say yes; CLAUDE.md says no).
- Whether `Archivable=false` instances are excluded from Team Create cloud saves, and whether they replicate to collaborators.
- Whether `Model.LevelOfDetail` can be switched to Disabled at runtime after a hit.
- The real upload-time serialized size versus the `.rbxl` (staff-acknowledged discrepancy).
- Edit-server memory cap: not documented. Use the Output disconnect reason and timing as a proxy.
- Per-part memory numbers here come from Studio, which inflates them. Re-measure on a live server with `Stats`.
