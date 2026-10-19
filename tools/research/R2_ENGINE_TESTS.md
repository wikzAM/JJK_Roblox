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
