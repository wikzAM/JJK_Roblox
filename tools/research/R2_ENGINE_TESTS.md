# In-engine tests run during research (2026-10-19)

Throwaway probes ran far above the map (Y=20000) in Edit. Every probe part was deleted afterwards and the map was left untouched.

## T1: CSG pane holes in a textured skin

Setup:
- A 40×30×0.6 skin Part with a Front Texture (StudsPerTile 4).
- 12 sequential `GeometryService:SubtractAsync` cuts with 2.5×3 pane-sized boxes, CollisionFidelity Box, SplitApart false.

Results:
- **Cost:** the first cut took about 65 ms (warm-up). Cuts 2–12 took **3–11 ms each**. Repeated small pane holes on one skin are cheap.
- **Texture children are NOT carried over** to the resulting UnionOperation (`tex=false` on every cut). The caller must clone the Texture onto the result. This works: the final union keeps one Texture.
- **Alignment:** with holes inside the face, the union keeps exactly the original Size and Position (24×18×0.6 at the same spot). The copied Texture (same StudsPerTile and Offset) therefore tiles identically, and holes stay registered to the painted windows.
  - **Edge case:** a cut touching the skin's border shrinks the union's bounds and would shift the tiling. Compensate by adjusting `OffsetStudsU/V` by the change in bounds.
- **Visual confirmation is still pending.** `screen_capture` timed out while the owner was away; the Studio window is probably not rendering while unfocused. Re-check with a screenshot when the window is active.

## Implications

- The "logical pane, texture until damaged, CSG hole on break" glass plan is technically viable and cheap per pane.
- The glass service needs a small helper that copies the Textures and fixes their offsets after each subtract.
- Batch cuts: one SubtractAsync with several pane boxes is cheaper than many separate calls when a hit removes many panes.

## Still to test in-engine

- Does a Texture with alpha on a Transparency=1 part render from both sides, and what does the transparent pass cost at city scale? (See R2_FACADE_BAKING_PIPELINE.md.)
- Which part sizes and counts survive Roblox's draw-distance reduction at each quality level? (Measurement pass.)
- Can GeometryService carve MeshParts?
- How large is the replicated data of a carved skin compared with a carved slab?

## T2: Can CSG carve MeshParts? (yes, if the mesh is watertight)

- **A real scanned MeshPart** (TestBuilding window mesh, cloned to Y=21000) was rejected by `GeometryService:SubtractAsync` with `CSG: Non-manifold mesh part (error -33)`. The API accepts MeshParts, so the class is not the problem; non-watertight geometry is. Our FBX scan meshes are non-manifold, so they stay uncarvable.
- **A closed box mesh** built with `AssetService:CreateEditableMesh` and then `CreateMeshPartAsync`:
  - Creating it took about 8 ms.
  - SubtractAsync took about **10 ms**, and the result is still a **MeshPart**.
  - Four sequential cuts on a 30×20×1 mesh took 23 / 8 / 5 / 6 ms, and each result was a MeshPart.
- **Caveat on persistence and replication:**
  - Code-built meshes are backed by an in-memory object (`MeshContent.SourceType = Object`), not an uploaded asset. After a cut, the result has no MeshId.
  - Community and DevForum reports, plus Roblox's GenerationService docs, say EditableMesh content does not replicate to other clients (they see a placeholder) and does not persist past the session. [DevForum: EditableMesh restrictions](https://devforum.roblox.com/t/editablemesh-restrictions/4566101), [GenerationService docs](https://create.roblox.com/docs/reference/engine/classes/GenerationService)
  - In published games, EditableMesh also requires the "Allow Mesh & Image APIs" setting plus age or ID verification. [EditableMesh docs](https://create.roblox.com/docs/en-us/reference/engine/classes/EditableMesh.md)
- **Implication:** watertight MeshParts are a real option for richer geometry per part, such as facade faces with recessed windows or merged per-floor slabs, that is still destructible. To persist and replicate, the meshes must be **uploaded assets**: generated offline as watertight OBJ or FBX, then imported or uploaded. The next test is to carve an *uploaded* watertight mesh and check that the carved result replicates to clients in Play.
- **Upload route for meshes:**
  - Open Cloud's Assets API accepts **FBX or glTF/GLB** Model uploads, which arrive as a Model containing MeshParts. OBJ is not in the official list.
  - The documented cap is **20 Model uploads per day**, for ID-verified users aged 13+.
  - Larger batches go through Studio's 3D Importer or Asset Manager bulk import.
  - Sources: [Usage guide for assets](https://create.roblox.com/docs/en-us/cloud/guides/usage-assets), [Open Cloud upload support for more asset types](https://devforum.roblox.com/t/open-cloud-upload-support-for-more-asset-types/4022082)
  - Implication: a mesh-based facade library has to be a **small reusable set**, for example a few dozen modules per style, tiled and instanced. Not one unique mesh per building.

## T3: Moving anchored parts and making slice pieces (Edit, 2026-10-19 overnight)

These are Edit-datamodel numbers on the dev PC (i5-12600KF). Edit adds change-history overhead, so treat them as upper bounds for a client `PreRender`. All probe parts were destroyed and `ResetWaypoints` was called.

**`workspace:BulkMoveTo` after warm-up** (60 frames, median / p90):

| Parts | FireCFrameChanged | FireAllEvents |
|---|---|---|
| 100 | 0.17 / 0.21 ms | — |
| 300 | 0.49 / 0.79 ms | 0.92 / 1.05 ms |
| 600 | 0.95 / 1.30 ms | 1.98 / 2.39 ms |

- That is about **1.6 µs per part** with FireCFrameChanged.
- **Moving the upper half of a collapse (≤600 parts) fits the ≤1 ms per frame client budget** in `R2_SLICE_COLLAPSE_CSG.md`. Use `FireCFrameChanged`, which is twice as fast as FireAllEvents.
- The first, cold run was 3–5 ms. Warm the path once (for example during hitstop).
- A plain per-part `.CFrame =` loop over 600 parts took about 2.2 ms, so BulkMoveTo is about 2× faster.

**Creating slice pieces:**
- Cloning 100 Parts and setting their properties took 2.7 ms.
- Parenting that 100-part folder into Workspace took 18.8 ms in Edit. (Parenting 600 parts took 207 ms in Edit on this huge place, mostly change history.)
- Destroying 700 parts took 18 ms.
- **Conclusion:** build pieces unparented ahead of `tSlice` (inside the hitstop) as planned. Parent in small batches and measure parenting again in Play, where change history doesn't apply.

**Analytic clip maths:** 10,000 pairs of Sutherland–Hodgman half-plane clips on a quad took **11.8 ms**, about 0.6 µs per clip. Slicing maths is effectively free; instance creation dominates.

## T4: CSG cost and triangle counts on a structural slab

One 100×100×1.5 Concrete slab, one cutter, `CollisionFidelity.Default`, `SplitApart=false`.

| Cutter | Time | Result triangles |
|---|---|---|
| Box 10³ (first call, warm-up) | 13.0 ms | 32 |
| Vertical cylinder r50 | 10.2 ms | 112 |
| Vertical cylinder r20 | 15.9 ms | 112 |
| Sphere r20 | 10.1 ms | 256 |
| Sphere r50 at the edge | 9.9 ms | 158 |
| Pane box 3×4×3 | 9.3 ms | 32 |

- The result is a `UnionOperation` with the slab's original bounds.
- Building an 8-part octagon ring out of primitives instead took **3.0 ms**, plus one Destroy.

## T5: Repeated hits on one slab, and batched cutters

A 200×200×1.5 slab hit by 15 random spheres (r 8–25) in sequence; each result replaced the previous one.

| Cut | 1 | 2 | 3 | 4 | 5 | 8 | 10 | 15 |
|---|---|---|---|---|---|---|---|---|
| Time (ms) | 6.3 | 6.2 | 6.3 | 7.3 | 12.9 | 26.0 | 13.0 | 19.6 |
| Triangles | 256 | 408 | 652 | 896 | 1,004 | 1,678 | 1,902 | 2,154 |

- Triangles grow by about 150–250 per sphere hole and level off near 2,000 as holes overlap. That is well under the 20k cap.
- The time per cut roughly doubles once the union holds about 1,000 triangles, and peaks at 26 ms.
- **Six spheres in one `SubtractAsync` call** took 20.7 ms (1,176 triangles), against roughly 6 × 7 ≈ 45 ms sequentially. **Batch the cutters per part per event.**

**Implications:**
- Sphere holes produce about 2–8× more triangles than cylinders. Prefer cylinder or capsule-like cutters for physical hits, and spheres only for beams that need a round look.
- A heavily damaged slab stays around 2k triangles. The replication cost per carved part still needs measuring in Play (wave 3, `R3_DESTRUCTION_REPLICATION_COST.md`).
- Server budget: at about 10–20 ms per cut, the "≤8 starts per frame" rule should be read as **CSG wall-time per frame**, not a count. Cap it at about 4 ms of starts per frame and let the rest queue. CSG is async, so measure in Play whether it blocks Heartbeat.
