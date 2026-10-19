# R3: Offline place pipeline (research, 2026-10-19)

Research only. No game code, Studio session or commit was touched. Read with `GAME_DESIGN_DECISIONS.md`, `R2_CITY_INVENTORY.md`, `R2_FACADE_BAKING_PIPELINE.md` and `R2_SKYLINE_HORIZON_RENDERING.md`.

Tags: **[doc]** official Roblox or tool docs, **[staff]** Roblox staff post, **[community]** forum or third-party report, **[est]** my estimate or inference, **[measured]** measured in this repo during this research (read-only, on the local recovery file).

## Executive summary

1. **Do the migration as a file-to-file transform, not inside Studio.** Use Lune (`@lune/roblox`) to read and write `.rbxl`, Python for the geometry maths and mesh generation, and Studio only at the end to review, playtest and publish.
2. **Lune can do the edit, but loading the full 1.14M-instance place is the one step that might not fit in 16 GB.** Nobody publishes scale figures. My estimate is 4–12 GB for the full DOM **[est]**. Measure it first. The repo already has a cheap fallback: the Python binary reader in `tools/inspect_place_recovery.py` decompresses the whole 73 MB recovery file in under a second **[measured]**, so data extraction never needs the full DOM.
3. **Round-tripping through Lune/rbx-dom is close to lossless for this place, with one known gap.** Every property type in the file is supported except type `0x23` on `Terrain.VoxelGridAssetContentMap`. rbx_binary skips that property with a warning **[doc: source]**. It is 42 bytes and probably empty, but verify it.
4. **Most of today's instance count is bookkeeping, not geometry.** In the Oct 17 recovery file **[measured]**:
   - **550,519 `ObjectValue`s**, about 32% of all instances. Most are `OriginalParent` undo registries from `SourceSliceReplacement` and `GroundFacadeSurfaceResolver`.
   - **6,660 unions**. All of them are furniture: chairs, printers, PCs, keyboards.

   Neither belongs in the lean place. Archive them to side files.
5. **Uploading meshes is less restricted than `R2_ENGINE_TESTS` says.** The current Open Cloud usage guide lists daily caps only for Audio and Video, not for Model **[doc]**. The "20 Model uploads per day" note appears to be the Video cap. One Model upload (FBX/glTF/GLB, up to 20 MB) can carry many meshes. The 150–250 stand-ins and 28 backdrops therefore fit in roughly 10 uploads.
6. **Build MeshParts from templates, not from a bare `MeshId`.** MeshId is effectively plugin/import-only, and physics data must match the mesh **[doc]**. Download the uploaded Model asset as `.rbxm`, then let Lune clone its MeshParts.
7. **Keep the place ID by publishing the lean file over the existing place.** Two routes:
   - Studio's "Publish to Roblox As…" onto the existing place.
   - Open Cloud `POST /universes/v1/{u}/places/{p}/versions?versionType=Published` **[doc]**. That API "doesn't update … PartOperation, SurfaceAppearance" **[doc]**, so if any unions or SurfaceAppearances remain, publish from Studio.
8. **Pilot: 10 buildings in one block, plus that block's stand-in mesh.** It is written as a separate pilot place, never over the live place. Details are in section 6.

## 1. Lune and `@lune/roblox`

**Status (October 2026).**
- The latest release is **0.11.0, released 11 Oct** **[doc: GitHub releases]**. The release page omits the year; from the ordering after 0.10.4 (Oct 2025) and 0.10.5 (Jul), it is 2026 **[est]**.
- Recent changes to the Roblox library:
  - 0.10.5 refactored it into **multiple independent DOMs with stable instance references**, so files with colliding referents can be loaded together. That is exactly what merging a base place with generated models needs. It also added `QueryDescendants` and `registerClass`/`registerService`, and fixed Tags deserialization.
  - 0.10.4 relaxed attribute-name validation and refreshed the reflection database.
  - 0.10.2 added `UniqueId`.
  - 0.11.0 fixed CFrame orientation errors and Enum identity **[doc: releases]**.
- Install it the same way as Rojo: add `lune = "lune-org/lune@0.11.0"` to `aftman.toml`. Pin the exact version **[est]**.

**What it can do** **[doc: API reference, API status, examples]**
- `roblox.deserializePlace(contents)` and `serializePlace(dataModel, xml?)`. The default output is binary. They take the file *contents* (`fs.readFile`), not a path.
- `deserializeModel` and `serializeModel` for `.rbxm` files.
- `Instance.new` (without the parent argument), `Clone`, `Destroy`, `GetChildren`, `GetDescendants`, `FindFirstChild*`.
- Attributes: `GetAttribute`, `GetAttributes`, `SetAttribute`.
- Tags: `AddTag`, `GetTags`, `HasTag`, `RemoveTag`.
- `DataModel:GetService` / `FindService`.
- Datatypes include CFrame, Vector3, Color3, BrickColor, PhysicalProperties, Font, NumberSequence and others.
- `getReflectionDatabase()`, plus `implementProperty` and `implementMethod` to add missing APIs.
- The official examples include "anchor every part in a place file", "save each Workspace child as its own model" and "build a new place from scratch". Together those are the whole toolkit this migration needs.

**What it cannot do** **[doc/est]**
- **No engine.** There is no physics, rendering, `GeometryService` CSG, `GetPartsInPart`, `Terrain:ReadVoxels`/`WriteVoxels`, `HttpService` or `task` scheduler. Use `@lune/serde` for JSON.
- **Union geometry cannot be computed.** It can only be copied: `AssetId`, `MeshData2`, `ChildData2` and `PhysicalConfigData` are opaque blobs that survive copy and clone.
- **Terrain is a blob.** `SmoothGrid` (8.7 MB here) is a BinaryString, so you can keep it or drop it, not edit it.
- **No asset upload.** Use Open Cloud for that.
- **No packages.** A `PackageLink` is only data; nothing resolves or updates.
- **`MeshPart.MeshId` can be written in the file, but nothing computes `InitialSize` or collision data for it.** See section 3.
- **The repo's shared Luau modules (`GroundFacadeKit`, `BuildingGenerator`) will not `require` unchanged.** They call `game:GetService`, `HttpService` and engine-only APIs. Port the pure maths (rectangle decomposition, layout) into Lune or Python behind a small shim **[est]**.

**Fidelity on this place** **[measured + doc]**
- I listed every binary property type present in the Oct 17 recovery file (122 classes, 2,341 PROP chunks).
- All of them are in rbx_binary's type table except **`0x23`**, used only by `Terrain.VoxelGridAssetContentMap`.
- rbx_binary's deserializer logs `warn` and skips properties whose type byte it does not know. Properties missing from the reflection database are **kept under their raw name** if the type is known **[doc: rbx_binary source]**.
- So expect exactly one dropped property. Its chunk is 42 bytes raw, so it is probably an empty map **[est]**. The pilot must confirm that Terrain still loads in Studio.
- rbx_binary does not support `Vector2int16`, `Region3` or `Region3int16`, but none of them appear in this file.
- The rbx_binary docs warn that a stale reflection database causes "mostly harmless" wrong defaults or names. Newer types need a crate update **[doc]**.

**Scale, memory and time**
- **No published benchmarks.**
- Raw property data is **916 MB uncompressed** (72 MB compressed) for 1.73M instances **[measured]**. The current place is about 1.14M instances, so roughly 600 MB.
- In rbx_dom_weak, each instance keeps a hash map of every serialized property. A Part has about 70 of them (I counted the property chunks on MeshPart and UnionOperation).
- At roughly 60–120 bytes per property entry, that is about 4–8 KB per Part. **The full place would need about 4–12 GB of RAM** and probably 30 s to a few minutes to parse **[est]**.
- That probably fits on a 16 GB machine with Studio closed, but it is the first thing to measure. Run `lune run` under Task Manager or `Measure-Command` and record the peak working set.
- Avoid `game:GetDescendants()` over the whole place. Walk `Workspace.Buildings` building by building.

**Fallback if Lune OOMs**
- Extraction does not need Lune. The in-repo reader already parses the INST/PROP/PRNT chunks, and decompression is fast: under 1 s for the whole recovery file **[measured]**.
- Extend it to decode CFrame, Size, Color, attributes and tags (numpy for the interleaved arrays), and write a columnar table.
- Then build the *base* place another way. Two options:
  - Load once on a bigger machine.
  - Run an Open Cloud **Luau Execution** task (section 4) that deletes the heavy folders and saves a copy.

## 2. Other parsers, and exporting geometry to Blender

| Tool | Status | Use here |
|---|---|---|
| **rbx-dom** (`rbx_dom_weak`, `rbx_binary`, `rbx_xml`, `rbx_types`, `rbx_reflection`; also `rbx_util`, a convert/debug CLI) | Active; the engine under both Lune and Rojo **[doc]** | Only if a custom Rust tool is needed. `rbx_util` converts binary↔XML so small pilot outputs can be diffed |
| **remodel** (rojo-rbx) | Legacy Lua 5.3 tool; Lune's docs include a "Migrating from Remodel" guide **[doc]** | Don't start new work on it |
| **In-repo Python reader** (`tools/inspect_place_recovery.py`, zstd + LZ4) | Ours, read-only | Census, validation and fast columnar extraction |
| **MaximumADHD Roblox-File-Format** (C#) | Third-party **[community]** | Not needed |

**Getting geometry out**
- Studio's **Export Selection** writes OBJ. That needs Studio and the heavy place, and it loses part colours **[community, R2 skyline doc]**.
- No maintained Blender add-on imports `.rbxl` primitives. I found only character/`.rbxm` converters of uneven quality **[community]**.
- **Recommended:**
  1. Lune or Python writes per-building JSON: class, `Shape`, CFrame (position plus 3×3), Size, Color, Material, tags.
  2. A Python script builds the triangles analytically:
     - **Block (Part):** an 8-vertex box (`trimesh.creation.box(extents, transform)`).
     - **WedgePart:** a 6-vertex triangular prism. Sloped face toward −Z (front), tall face at +Z, so the top edge runs along the back **[est: verify against one Studio OBJ export]**.
     - **CornerWedgePart:** a 5-vertex pyramid. Verify the apex corner the same way.
     - **Cylinder:** axis along **local X**, not Y. `trimesh.creation.cylinder` builds along Z, so rotate it.
     - **Ball:** an icosphere sized to the minimum axis.
  3. Primitives converted this way are exact and watertight by construction.
- **Wedges are a trap for footprint maths.** `tools/wedge_box_check.py` shows that a slab WedgePart's Size box is not its geometry; the fourth corner is empty.
- **Do not try to merge the 140k slab wedges geometrically.** Rebuild slabs from the source footprint data instead (section 5).

## 3. Meshes offline: stand-ins, backdrops and upload

**Generation (Python)**
- `numpy` and `shapely` are already in `tools/python_deps`. Add **trimesh** and **manifold3d**.
- **Block stand-in recipe:**
  1. Take every building in a block as an extruded footprint: shell boxes, or the `InteriorBBox*` attributes for a coarse version.
  2. Inset each 1–2 studs, per the skyline doc.
  3. `trimesh.boolean.union(meshes, engine="manifold")`. Manifold3D returns manifold, watertight output by design **[doc: trimesh]**.
  4. Simplify to 300–1,500 triangles. Use `simplify_quadric_decimation`, or Blender's Decimate in background mode.
  5. Check `is_watertight` and `is_winding_consistent`, plus a non-zero `volume` assertion. Watertightness is what GeometryService needs to carve a MeshPart; the T2 test showed the FBX scans failing as "non-manifold".
- Roblox rules **[doc]**:
  - At most **20,000 triangles** per mesh.
  - Meshes must be "watertight without exposed holes or backfaces" and have real volume.
  - Part size is capped at 2,048 studs per axis, which limits backdrop length **[community, skyline doc]**.
- **Export the mesh at its final world scale, with the pivot at the mesh centre.** In the place, keep `Size == InitialSize` so the file never asks Roblox to rescale collision data **[est]**.
- **Backdrops:** 28 low-poly ring segments of 2–8k triangles each, made the same way.
- **Skin box:** one shared watertight box mesh, scaled per bay (Option B in the facade doc).

**Upload options**

| Route | Limits | Verdict |
|---|---|---|
| **Open Cloud Assets API**, `assetType=Model` | `.fbx`, `.gltf`, `.glb`, `.rbxm`, `.rbxmx`; up to 20 MB per call; result is a Model of MeshParts that becomes a package. The guide lists daily or monthly caps only for Audio and Video **[doc]**. Image create is about 120/min per the R2 facade doc. An older version of the page listed only FBX, so test GLB first and fall back to FBX through Blender **[doc, inconsistent]** | **Default.** Group about 25 stand-ins per GLB, so roughly 10 calls cover everything |
| Studio **3D Importer** | Multi-file import queue. "Import Only As Model" off makes each child its own asset; "Upload to Roblox" puts them in the inventory **[doc]**. No de-duplication **[doc via skyline doc]** | Good fallback. Run it from the *lean* place, not the heavy one |
| `AssetService:CreateAssetAsync(EditableMesh, AssetType.Mesh)` | Local plugin, command bar, or Open Cloud Luau Execution; beta; 30 requests/min at launch **[doc + staff, Dec 2024]** | Only if geometry has to come from live parts |
| Open Cloud `assetType=Mesh` | Accepts only content downloaded from Asset Delivery **[doc]** | Not for new meshes |
| Official **Roblox Blender plugin** | Uploads selected objects or collections as packages through Open Cloud; Blender 3.2+; a "reference implementation" that takes bug fixes only **[doc]** | Fine for hand-made backdrops |

**Referencing the IDs from Lune**
1. After each Model upload, poll the operation and read the `assetId`.
2. Fetch the asset with `GET /asset-delivery-api/v1/assetId/{id}`. It needs scope `legacy-asset:manage`; the response gives a temporary `location` URL to a gzip `.rbxm` **[doc]**. A forum reply says that scope is not available on group-owned keys **[community]**.
3. `roblox.deserializeModel` the file. Each MeshPart inside already has a valid `MeshId`, `InitialSize`, `PhysicalConfigData` and `PhysicsData`.
4. **Clone** those templates into the place and set only CFrame, Color, Material, `CastShadow=false`, `CanCollide`/`CanQuery`/`CanTouch=false` and `RenderFidelity`.

Why not set `MeshId` directly:
- The docs say MeshId can't change at runtime because collision can't be recomputed, and that mesh and physics data must be updated together **[doc: MeshPart]**.
- Forum reports of "Failed to load mesh physics data" come from mismatched data **[community]**.
- Keep a `mesh_manifest.json` mapping `blockId → assetId, meshId, tris, sha`.

## 4. Reducing Studio memory, and replacing the place

**Why Studio OOMs.** 20.7 GB for about 1.14M instances is roughly 18 KB per instance **[est]**. Studio holds the whole DataModel plus render, physics and undo state. Instance streaming does not reduce Studio or server edit memory **[doc, OPTIMIZATION_RESEARCH]**. The only real fix is fewer instances.

**Short-term mitigations** (for the few Studio sessions still needed before migration)
- **Disable Script Analysis before launch.** A July 2026 bug report, confirmed by several users, shows a leak of about 1 GB/min while idle with Script Analysis on. Turning it off mid-session did not help **[community]**.
- **Switch the place to the old Luau type solver.** Staff: it "does use less memory", and the solver is now a per-place setting **[staff]**.
- **Open the local file rather than a Team Create session**, since collaboration adds draft and sync overhead **[est]**. Other 2026 threads report 14–25 GB growth after load from the same causes **[community]**.
- Studio has a documented CLI: `--task EditFile --localPlaceFile`, and `--task RunScript --runScriptFile … --outputFile … --quitAfterExecution` **[doc]**. Use it later to run a validation script against the *lean* file without manual clicks.

**Splitting**
- **Packages** do not help memory. A package is still fully instantiated in the DataModel when the place is open **[est]**.
- **Separate places** help only for authoring, for example one district per work place. The game needs one connected city, so the lean single place is the target.
- **Keep the heavy data as side files instead.** Write each district's removed detail (old facades, archives, furniture unions) to `.rbxm` files and store them as GitHub Release assets, like the recovery checkpoints. Nothing is lost, and nothing loads.

**Studio cannot open a place without loading Workspace.** I found no such feature. Roblox ran a limited "place open improvements" test aimed at hangs and load time, but it does not skip Workspace **[staff/community]**.

**Cloud-side option: Open Cloud Luau Execution** **[doc]**
- It runs a script headlessly against a chosen **place version**: 5 min limit, 10 concurrent tasks per place, 5 task creates/min.
- Binary input up to 100 MiB and binary output up to 256 MiB.
- `SerializationService:SerializeInstancesAsync` and `DeserializeInstancesAsync` work there, converting `.rbxm` buffers.
- `AssetService:SavePlaceAsync` can save. It needs the place API setting enabled, and "an active Team Create session in Studio blocks all saves".
- Uses here:
  - Export Terrain as a `TerrainRegion` `.rbxm`.
  - Export per-building data as JSON from the *actual cloud version* when no local copy is current.
- Server memory for a 1.14M-instance place is unknown. It is probably far below Studio, because a server does not render **[est]**.

**Replacing the place but keeping its ID** (place 99539622209675, per `FACADE_SECTION_HANDOFF.md`)
- **Studio:** open the lean `.rbxl`, then File → Publish to Roblox As → pick the existing experience and place, which overwrites it. Version history keeps the old version for rollback **[doc/est]**.
  - Close all Team Create sessions first. Collaborators are disconnected and their unsaved drafts are lost **[est]**.
- **Open Cloud:** `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published` with the `.rbxl` as `application/octet-stream`, using the `universe-places` write permission **[doc]**.
  - The guide says it doesn't update PartOperation, SurfaceAppearance, EditableMesh/Image or BaseWrap instances.
  - The lean place has no unions in Workspace, but `ServerStorage.Furniture` probably still holds union furniture and the place has 9 SurfaceAppearances **[measured]**. So **publish from Studio** unless those move to side files.
- **Size limit:** places over 100 MB may fail to save or publish **[doc]**. The lean place should be under 15 MB, most of it terrain **[est]**.
- **Before any overwrite,** download the current cloud version (Asset Delivery, legacy scope) and keep it with its SHA-256. The cloud and local copies have diverged before (`PLACE_RECOVERY_2026_10_17.md`).

## 5. Recommended pipeline for this repo

New folder: `tools/offline/`. Lune scripts are `.luau`, run with `lune run`. Python runs with `-I`, using `tools/python_deps`. Every step writes a JSON receipt (inputs' SHA, counts, timings, peak RAM), following the house style.

| # | Step | Tool | Output |
|---|---|---|---|
| 0 | **Freeze map edits.** The owner agrees that no Studio or MCP map edits happen from download until publish | — | Note in `SHIBUYA_LIVE_STATE.md` |
| 1 | **Acquire the source.** Download the latest cloud version, or use the newest checkpoint the owner names. Run the census (`inspect_place_recovery.py`, extended with class counts) | Python / Open Cloud | `source.rbxl`, `source_census.json` |
| 2 | **Round-trip test.** Lune read, then write unchanged. Diff per-class instance and property-chunk counts between input and output; expect only the `0x23` drop. Record time and peak RAM | Lune + Python | `roundtrip_report.json` |
| 3 | **Extract.** Per building: name, pivot, attributes (`InteriorGrid`, `InteriorBBoxCFrame/Size`, `CoreCFrame/Size`, `GeneratedFloors`, `FootprintMode`, `SourceSliceId`), tags, shell and slab part rows, crown rows. Also the facade manifest (`ServerStorage.GroundFacadePilotManifest`, read through the same `Registry` StringValue chunking), roads and landmarks | `extract.luau` (or the Python fallback) | `city_extract/*.json` |
| 4 | **Make the base place.** Delete `Workspace.Buildings` children, the SourceSlice and facade archives, the `OriginalParent` registries, Building1 furniture and preview galleries. **First** write each removed subtree to `archive/<district>.rbxm` | Lune | `base.rbxl` (terrain, roads, lighting, services), archives |
| 5 | **Compute lean buildings.** Per floor, 1–3 rectangles from rectangle-decomposing `InteriorGrid` (the same algorithm as BuildingGenerator, ported). Core walls (6). Skin Parts per face, 4–8, with `Texture` IDs from the facade bake manifest, or a flat palette colour until the bake exists. Crowns merged to 1–2 boxes. Towers use floor-band skins plus every-Nth-floor slabs. Target 10–25 parts each; flag anything above 40 | Python | `lean_buildings.json` |
| 6 | **Meshes.** Block stand-ins (150–250) and 28 backdrops. Run watertight and triangle checks, export GLB in batches, upload, fetch the `.rbxm` templates | Python + Open Cloud | `meshes/*.glb`, `mesh_manifest.json`, `templates/*.rbxm` |
| 7 | **Write.** Load `base.rbxl` and build `Workspace.Buildings/Building*` Models from `lean_buildings.json`. Keep the `Building` name prefix and the attributes HitHandler depends on. Tag `BuildingCore` and `NoCSG` as today. Clone stand-in templates into `ReplicatedStorage.CityStandIns` | Lune | `lean.rbxl` |
| 8 | **Validate offline.** Instance count of about 60–80k. Parts-per-building histogram. Each building's AABB within ±1 stud of the original. Required attributes present. No `UnionOperation` or `ObjectValue` under Workspace. File size. A top-down PNG overlay of old and new footprints (reusing the `tools/preview` matplotlib style) | Python | `validation.json`, `preview/*.png` |
| 9 | **Studio.** Open `lean.rbxl` with Script Analysis off and record memory. Rojo-sync scripts. Walk the city. Playtest hits: CSG on slabs and core, broad-phase attributes, glass. Then Publish As over the place | Studio (owner) | Publish receipt (Output save line, per the memory note) |

**Code that must change alongside**, from the R2 inventory table: `GroundFacadePilot` and `UpperFacadeRenderer` expect part facades and registries, and `FacadeRenderer` is retired. Without these, the lean place runs old scripts against missing data. Plan them as a separate, reviewed code change gated on the pilot.

**What still needs Studio**
- Facade texture capture: `StudioCaptureService` is plugin-only (R2 facade doc).
- Visual review and playtests.
- The final publish (unions and SurfaceAppearance).
- Any terrain sculpting.
- Optionally the 3D Importer upload.
- Place settings: type solver, Mesh/Image API toggle if ever needed.

**Risks**
1. **Lune peak RAM on the full place.** Measured in step 2. If it is too high, use the fallback in section 1.
2. **The dropped `VoxelGridAssetContentMap` property.** The pilot opens the result in Studio and checks that terrain renders.
3. **Attribute types.** CFrame-typed attributes (`InteriorBBoxCFrame`, `CoreCFrame`) must round-trip in Lune 0.11. Assert this in step 2 **[est]**.
4. **Clones copying `UniqueId`/`HistoryId`.** Studio may regenerate them, and duplicates could confuse collaboration history **[est]**. Set fresh ones, or strip them if Lune allows.
5. **ObjectValue references** into deleted subtrees become nil. Scan for refs that cross the delete boundary before deleting.
6. **Mesh moderation and processing delays** are unknown **[doc: no figure]**. Stand-ins are untextured grey geometry, so the risk is low.
7. **Cloud and local divergence.** Always work from a freshly downloaded or owner-named version, and never restore owner-deleted buildings (the house rule).
8. **Rollback.** Keep `source.rbxl` and every archive `.rbxm` as Release assets. Roblox version history is the second safety net.

## 6. Pilot proposal (for owner approval)

**Scope**
- Ten buildings in **one block**, chosen to cover the hard cases:
  - 2 plain box mid-rises.
  - 2 towers with more than 1,000 slab wedges each (from the R2 "heaviest 50" list).
  - 2 irregular or wedge-heavy footprints.
  - 2 with main-street ground facades.
  - 1 with a crown.
  - 1 setback building.
- `Building1` is excluded.

**Deliverables**
- `tools/offline/` scripts for steps 1–8, run on the full source but **writing only `pilot.rbxl`**. That file is the base place plus the 10 lean buildings, plus one uploaded stand-in mesh for the block, plus the untouched originals of those 10 buildings offset 300 studs away for side-by-side comparison.
- Never publish over the live place during the pilot.

**Acceptance criteria**
- Step 2 round-trip report: RAM, time, and only the expected property drop.
- At most 25 parts per pilot building; towers at most 40.
- Footprint AABB within 1 stud of the original.
- Terrain intact in Studio.
- Studio opens `pilot.rbxl` under 4 GB **[est target]**.
- In Play, a dummy hit carves a lean slab and core wall. A `NoCSG` skin is deleted or carved per the facade decision.
- The stand-in mesh carves with GeometryService, which checks watertightness.

**Decisions the owner must approve before the pilot**
1. Add Lune to `aftman.toml`.
2. Create an Open Cloud API key with asset read/write and `legacy-asset:manage` for this account only.
3. Choose the source place version.
4. Upload one test Model for the stand-in.

## Sources

- Lune releases (0.11.0, 0.10.5, 0.10.4, 0.10.2): https://github.com/lune-org/lune/releases
- Lune `@lune/roblox` API reference: https://lune-org.github.io/docs/api-reference/roblox
- Lune Roblox API status: https://lune-org.github.io/docs/roblox/4-api-status
- Lune Roblox examples: https://lune-org.github.io/docs/roblox/2-examples ; introduction: https://lune-org.github.io/docs/roblox/1-introduction
- rbx-dom repository and type coverage table: https://github.com/rojo-rbx/rbx-dom
- rbx-dom binary format spec: https://github.com/rojo-rbx/rbx-dom/blob/master/docs/binary.md
- rbx_binary type IDs: https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_binary/src/types.rs ; unknown-type and unknown-property handling: https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_binary/src/deserializer/state.rs
- rbx_binary docs (stale reflection database caveats): https://docs.rs/crate/rbx_binary/latest
- remodel releases: https://github.com/rojo-rbx/remodel/releases
- Terrain export with Remodel (SmoothGrid as BinaryString): https://devforum.roblox.com/t/terrain-export-with-remodel/1492714
- Open Cloud assets usage guide (formats, 20 MB, caps): https://create.roblox.com/docs/en-us/cloud/guides/usage-assets
- Open Cloud assets reference (asset delivery, `legacy-asset:manage`): https://create.roblox.com/docs/en-us/cloud/reference/features/assets.md ; place download thread: https://devforum.roblox.com/t/downloading-place-file-with-api/3762171
- Place publishing via Open Cloud: https://create.roblox.com/docs/cloud/guides/usage-place-publishing
- Luau Execution API: https://create.roblox.com/docs/en-us/cloud/reference/features/luau-execution.md
- SerializationService: https://create.roblox.com/docs/en-us/reference/engine/classes/SerializationService.md
- AssetService (SavePlaceAsync, CreateAssetAsync): https://create.roblox.com/docs/reference/engine/classes/AssetService.md
- CreateAssetAsync beta announcement: https://devforum.roblox.com/t/beta-lua-asset-creation-for-creator-tooling-with-createassetasync/3294134/1
- 3D Importer: https://create.roblox.com/docs/art/modeling/3d-importer
- Mesh specifications (20k triangles, watertight): https://create.roblox.com/docs/art/modeling/specifications
- MeshPart reference: https://create.roblox.com/docs/en-us/reference/engine/classes/MeshPart.md ; CreateMeshPartAsync: https://create.roblox.com/docs/reference/engine/classes/InsertService/CreateMeshPartAsync ; physics-data error: https://devforum.roblox.com/t/issue-with-mesh-physics-data/2882291
- Roblox Blender plugin: https://github.com/Roblox/roblox-blender-plugin
- Studio CLI: https://create.roblox.com/docs/en-us/studio/command-line-interface.md
- Place files and the 100 MB limit: https://create.roblox.com/docs/projects/place-files
- Studio memory threads: https://devforum.roblox.com/t/studio-leaks-1-gbmin-of-memory-while-idle-when-script-analysis-is-enabled-grows-to-100-gb-then-crashes/4743637 ; https://devforum.roblox.com/t/studio-using-way-more-ram-than-it-should-be-25-gb/4845166 ; https://devforum.roblox.com/t/roblox-studio-using-40gb-of-memory/3975130 ; https://devforum.roblox.com/t/studio-panics-with-failed-to-spawn-a-fiber-rsl-panic-02f8dfb-kernel1409-memory-climbs-38gb-to-15gb-after-place-finishes-loading/4742463 ; place-open test: https://devforum.roblox.com/t/place-open-improvements-test/3086811 ; slow large-place loads: https://devforum.roblox.com/t/studio-taking-5min-on-average-to-start-a-playtest-in-large-places/4049685
- trimesh boolean engines (manifold3d): https://tessl.io/registry/tessl/pypi-trimesh/files/docs/mesh-processing.md
- In-repo: `tools/inspect_place_recovery.py`, `tools/wedge_box_check.py`, `tools/PLACE_RECOVERY_2026_10_17.md`, `tools/OPTIMIZATION_RESEARCH.md`, `tools/research/R2_ENGINE_TESTS.md`, `src/server/BuildingGenerator.luau`, `src/server/GroundFacadePilot.luau`, `src/server/SourceSliceReplacement.luau`, `src/server/GroundFacadeSurfaceResolver.luau`.
- Measurements in this note: read-only Python scans of `assets/TestJJK_StudioRecovery_2026-10-17_postcleanup.rbxl` (class counts, property type IDs, ObjectValue and union parents). Scratch scripts only; nothing was written into the repo besides this file.


## Addendum: live-place check (2026-10-19 overnight, read-only Studio census)

The current place has **14,759 `ObjectValue`s**, not 550k. The large registries in the Oct 17 recovery file have since been cleaned up.
- 14,672 are in ServerStorage and 87 in Workspace.
- By name: 14,416 `Target` (mostly under `CoreWall*`/`CoreDivider*` and `fbx_*` parts), 282 `ReplacementSource`, 57 `Pane`.

The instance total is 1,134,764 across Workspace, ServerStorage, ReplicatedStorage and Lighting. The "archive registries to side files" step is therefore small. Instance reduction must come from the facade and slab geometry, as in `R2_CITY_INVENTORY.md`.
