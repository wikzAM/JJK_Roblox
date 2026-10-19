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
  - The documented cap is **20 Model uploads per day**, for ID-verified users aged 13+. **Disputed by `R3_OFFLINE_PLACE_PIPELINE.md`:** current docs cap only Audio and Video, and batched GLB uploads would cover about 280 meshes in about 10 calls. Verify with one test upload.
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

## T6: Texture PBR, emissive and lighting properties (Edit, read-only probe)

- **`Texture` exposes PBR maps:** `ColorMapContent`, `NormalMapContent`, `RoughnessMapContent` and `MetalnessMapContent`, plus older string forms such as `NormalMap`.
  - Writing `NormalMapContent` from the MCP (plugin) context **works**.
  - The docs tag Normal, Roughness and Metalness as **Plugin Security** ([Decal docs](https://create.roblox.com/docs/reference/engine/classes/Decal)). Bakes can therefore apply them at edit time, but runtime game scripts cannot change them. That is fine for the bake pipeline, since maps are set once per skin.
  - `ColorMapContent` is script-writable, but tagged "Not Replicated". A server-side runtime change would not reach clients, so set colour maps at edit time too.
  - `TexturePackContent` cannot be written ("lacking capability RobloxEngine").
- **`Texture.EmissiveStrength` exists (default 1), with no emissive map property.** It is not documented on the Decal page. It may be an unreleased decal-glow feature, which would replace the separate night bakes (risk 11 in the baking doc). Visual test pending, with the Studio window focused.
- **`SurfaceAppearance`** has `EmissiveMaskContent`, `EmissiveStrength` (script-writable) and `EmissiveTint`. Stand-in meshes and hero MeshParts can glow at night without Neon parts.
- **Current place lighting:** `LightingStyle = Soft`, `PrioritizeLightingQuality = false`. **The draw-distance lever recommended in `R2_SKYLINE_HORIZON_RENDERING.md` is already set.** The skyline loss happens even with it, which confirms that instance count is the main driver. The remaining choice is Soft versus Realistic.

## T7: Render baseline from five vantage points (Edit, window focused, 2026-10-19 overnight)

**Method:**
- Dev PC: i5-12600KF with an RX 7700 XT, running Studio's editor quality, so there is no draw-distance cut.
- `Stats` render counters work in Edit, **but only while the Studio window is focused**. When it's unfocused, the values freeze.
- For each view: 30 frames of settling, then the median of 15 frames.
- Ground at the map centre (40, 414) is at Y ≈ 63.
- The editor's render-CPU floor (looking at empty sky): **about 11 ms, 4 draw calls**.

| View | Draw calls | Triangles | Render CPU | Render GPU |
|---|---|---|---|---|
| Street, eye height, looking along X | 374–431 | 0.71–0.79M | 27–29 ms | 0.5 ms |
| 300 up, 45° down | 655 | 0.90M | 20–21 ms | 0.7 ms |
| Corner of map, 600 up, looking across | 341–454 | 1.9–2.1M | 60 ms | 1.1 ms |
| 1,200 up, looking down at the centre | 570–783 | 2.0–2.2M | 34–36 ms | 1.1 ms |
| 4,500 out, looking at the skyline | 252–258 | 1.56M | 52–58 ms | 0.6 ms |

- **Rendering is CPU-bound, not GPU-bound.** The GPU uses about 1 ms. Render CPU is 20–60 ms, so 17–50 FPS in the editor on a fast desktop CPU, and worst for wide views of the whole city.
- A laptop CPU would be slower still, and Roblox would cut its draw distance. This matches the skyline loss.
- Draw calls are already **above the 500 low-tier budget** from the air.

## T8: What glass panes and ground facades cost (hidden locally with `LocalTransparencyModifier`, then restored)

**Glass (47,464 `GlassPane` parts in Workspace):**

| View | Draw calls with → without | Triangles | Render CPU |
|---|---|---|---|
| Street | 374 → 372 | 0.71 → 0.66M | 26.5 → 26.3 ms |
| 300 up | 655 → 653 | 0.90 → 0.81M | 21.2 → 18.4 ms |
| 1,200 up | 783 → 783 | 2.22 → 2.07M | 35.2 → 27.7 ms |

- **Correction to `R3_NIGHT_LIGHTING_TRANSPARENCY_COST.md` §Summary 1.** The 2018 staff claim, "one draw call per transparent part", does **not** hold in 2026: hiding all panes changed draw calls by at most 2.
- Glass costs **render CPU** (up to about 7.5 ms from high up), not draw calls.
- Its other problems still stand: it hides particles, beams and GUIs behind it.

**Ground facades (653,704 BaseParts under `GroundFacadePilot`):**

| View | Draw calls full → no facades | Triangles | Render CPU |
|---|---|---|---|
| Street | 374 → 202 | 0.71 → 0.32M | 28.8 → 23.7 ms |
| 300 up | 656 → 151 | 0.90 → 0.32M | 21.3 → 16.7 ms |
| Corner across | 341 → 283 | 1.93 → 1.35M | 60.0 → 30.3 ms |
| 1,200 up | 747 → 419 | 2.18 → 0.95M | 36.4 → 24.0 ms |
| Skyline from outside | 258 → 254 | 1.57 → 1.32M | 58.2 → 29.0 ms |

- **Above the editor's floor of about 11 ms, the ground facades are about 60% of the render CPU on wide views.**
  - Corner view: 49 ms of scene cost falls to 19 ms.
  - Skyline view: 47 ms falls to 18 ms.
- **The facades are also 45–77% of the draw calls** at street level and from the air.
- These parts were only hidden, not removed, so the engine may still walk them. Removing them should save at least this much.
- **This is the first direct measurement behind the plan:** baking ground facades to textures is the biggest single render lever, as `R2_CITY_INVENTORY.md` predicted from part counts.
- With facades hidden, 18–19 ms of scene cost remains for wide views. That comes from slabs, cores, crowns and terrain, about 480k parts. Merging slabs is the second lever.

## T9: Serialized size of a carved part (proxy for replication bytes)

`SerializationService:SerializeInstancesAsync({part})` produces the binary model format, the same format the engine replicates. The numbers include a fixed file header of about 2 KB.

| Part (100×100×1.5 slab) | Triangles | Serialized bytes |
|---|---|---|
| Plain Part | — | 2,633 |
| One 3×4×3 box hole | 32 | 8,041 |
| One r20 cylinder hole | 112 | 10,156 |
| One r20 sphere hole | 256 | 14,680 (14,528 with Box collision) |
| 15 sphere holes | 714 | 53,480 |

- **A carved part costs roughly 5–12 KB more than a plain part for one hole, growing to about 50 KB after many holes.** Collision fidelity barely changes this.
- This confirms the estimate in `R3_DESTRUCTION_REPLICATION_COST.md` (6–25 KB per carved part, sent to every client).
- A hit that carves 20 slabs and walls is therefore about **150–300 KB per client**, against a budget of 30–50 KB/s.
- **Server-side CSG on structural parts can't be the default for frequent hits.** Use the "deterministic mirror" instead: the server sends an event of a few hundred bytes, and server and clients run the same analytic primitive splitting. Client-side CSG is optional and cosmetic.
- Network compression may shrink these numbers. Measure in Play (M-tests in the R3 replication doc).

## T10: Does `Texture.EmissiveStrength` glow? (visual, window focused)

**Setup:** four dark SmoothPlastic panels with the same Front Texture (`SpawnLocation.png`), with `EmissiveStrength` set to 0, 1, 5 and 20, in front of a black backdrop at Y=23000 in daylight.

**Result:** the four panels render **identically and dim**. The property has no visible effect today; it is probably a placeholder for the planned decal-emissive feature.
- **Night lit windows can't rely on Texture emissive yet.**
- Use SurfaceAppearance or MaterialVariant emissive masks (live since 2026-02), opaque Neon, or separate night bakes. Re-check after future engine releases.

The probe was deleted and `ResetWaypoints` called.

## T11: Render cost by category, cumulative hide (Edit, window focused)

**Method:** same views and method as T7. Each stage hides one more category locally with `LocalTransparencyModifier` (restored afterwards; 862,621 parts checked back to 0). Cells show draw calls / triangles / render CPU.

**Categories:**
- 140,776 slab WedgeParts under `Interior`;
- 45,152 other Interior parts (cores, slab Parts, furniture);
- 22,989 Crown and ParapetRim parts;
- 653,704 ground-facade parts.

| Stage | Street | 300 up | Corner across | Skyline |
|---|---|---|---|---|
| Full | 418 / 0.77M / 29.1 | 657 / 0.90M / 20.8 | 342 / 1.93M / 60.7 | 252 / 1.56M / 57.0 |
| − slab wedges | 227 / 0.30M / 30.2 | 580 / 0.69M / 20.3 | 344 / 1.07M / 55.5 | 252 / 0.84M / 53.6 |
| − all interior | 340 / 0.60M / 30.5 | 875 / 1.11M / 21.4 | 349 / 1.06M / 55.0 | 250 / 0.80M / 53.4 |
| − crowns and rims | 379 / 0.58M / 29.6 | 878 / 1.12M / 21.2 | 349 / 0.92M / 53.2 | 250 / 0.65M / 51.5 |
| − ground facades (only shells, terrain, roads left) | 208 / 0.21M / 22.4 | 152 / 0.15M / 15.0 | 278 / 0.18M / 25.9 | 246 / 0.14M / 24.7 |

**Findings:**
1. **Render CPU grows roughly linearly with the number of parts in the scene, at about 35–45 ns per part on this desktop CPU.**
   - Hiding 654k facade parts saved about 27 ms on wide views, about 41 ns per part.
   - Hiding 141k wedges saved about 5 ms, about 36 ns per part.
   - **At this rate, a 60k-part map costs about 2.5 ms of scene CPU here**, against about 45 ms now. A laptop CPU might be 1.5–2.5× slower.
   - **[est] This is the strongest evidence yet that part count, not triangles or draw calls, drives the frame time and with it Roblox's draw-distance cut.**
2. **Slab wedges are mostly a triangle cost:** they make up 45–60% of triangles at wide views, but only about 5 ms of CPU. Merging slabs matters for triangles and the part count. Facades matter most for CPU.
3. **Interior parts act as occluders.** Hiding them *raised* draw calls from the 300-up view (580 → 875) because more things behind became visible. Lean buildings still need opaque slabs and core walls to keep occlusion culling effective.
4. **The floor without buildings** (shells, terrain, roads; editor floor about 11 ms) is 15–26 ms. Shells and terrain still cost 4–15 ms above the editor floor. Worth a separate look at terrain and road geometry later.

**Addendum to T11 (Workspace census):**
- With all four categories hidden, only about 3.4k other building parts (shells, upper facades) and about 5.8k loose parts remain:
  - `GroundFacadeDraftGallery`: 4,755 parts;
  - `Thin Skyscraper 7`: 455;
  - `TestBuilding`: 427.
- So the 4–15 ms that remains above the editor floor is mostly **terrain**, plus possibly SurfaceGuis whose host parts were hidden.
- `Buildings` holds 146k non-part instances: Textures, SurfaceGuis, values.
- **Candidate cleanup (needs owner approval):** move `GroundFacadeDraftGallery` (4,755 parts, a design gallery) out of Workspace into ServerStorage.

## T12: Lean-building mockup (210 buildings × 18 parts, textured skins)

**Setup:** at Y=25000, a 14 × 15 grid of buildings on a 130-stud pitch, each 40–90 studs wide and 4–25 floors tall (12.5-stud storeys). Each building had:
- 4 face skins, each one Part with one Front `Texture` (one shared image, tiled per bay);
- 8 slab bands, 4 corner piers, 1 roof and 1 roof box.

Total: 3,780 parts. Creating them in Edit took 4.0 s, mostly parenting under change history. The mockup was deleted and `ResetWaypoints` called.

| View | Lean city (draw calls / triangles / render CPU) | Same view, mockup hidden |
|---|---|---|
| Corner, 400 up, whole grid in view | **7 / 21k / 15.1 ms** | 19 / 2k / 11.5 ms |
| Street level inside the grid | **7 / 5k / 11.7 ms** | 93 / 1k / 11.3 ms |
| Corner view without Textures | 5 / 20k / 14.8 ms | — |

- **The whole 210-building lean district renders in about 7 draw calls.**
  - Parts with the same material batch together, and the shared Texture adds about 2 draw calls.
  - It costs 0.4–3.6 ms of render CPU above an empty view, against 20–60 ms for today's city from comparable views (T7).
  - "Empty" shows more draw calls than "lean" because the lean buildings occlude the terrain and sky behind them.
- **Extrapolation [est]:** a full lean city of about 1,941 buildings and about 35–50k parts should cost tens of draw calls for the shells plus the street-level near set, and well under 10 ms of editor render CPU. That is consistent with T11's 40 ns per part.
- **Caveats:**
  - There was one shared texture. Real bakes use many unique images, so expect up to 1 draw call per unique texture in view.
  - The test omitted ground-floor detail, signs and lights.
  - Measure with ~300 unique textures next (`R2_FACADE_BAKING_PIPELINE.md` key count).
- **Conclusion:** the lean-map budget (10–25 parts per building) is validated on the render side. The cost driver is the number of unique textures, not parts.
