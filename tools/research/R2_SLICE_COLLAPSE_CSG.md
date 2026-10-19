# Slice, collapse and CSG: research round 2 (2026-10-19)

Research only. No code, Studio or place changes. Builds on `GAME_DESIGN_DECISIONS.md` (the three
destruction types and the slice-collapse sequence) and `COMBAT_MOTION_DESTRUCTION_SYNC.md` (server
timelines, local execution at `tBreak`, seeded kinematic debris, the logical cell grid).

Tags: **[doc]** Creator Hub, **[staff]** Roblox staff post, **[community]** DevForum non-staff,
**[ext]** other engines and studios, **[2nd]** third-party summary, **[est]** my inference, which
needs measuring in engine.

## Executive summary

1. **The slice type can avoid CSG entirely.** Our structure is thin prisms (slabs as Parts or
   right-triangle WedgeParts, 1.5 studs thick, and thin core walls). A plane cut becomes a **2D
   half-plane clip of the cross-section, then re-extrusion**: at most 4 primitives per cut
   rectangle and 6 per cut triangle. `PolygonSlab`/`TriangleShell` already decompose polygons.
   The cost is Luau arithmetic and a few `Instance.new` calls, with no mesh replication.
2. **Exactness trick:** snap the slice plane to **contain a building horizontal axis**. Every
   axis-aligned box is then cut exactly. Footprint wedges use the thin-slab approximation, with
   an error of at most `(t/2)·tan φ` (0.75 studs at 45°), hidden under dust.
3. **GeometryService in 2026:** booleans are fully released (2025-11-12), async, and work in
   LocalScripts. Watertight-MeshPart CSG, `FragmentAsync` and `SweepPartAsync` are live since
   2026-07-07. Our own engine tests (`R2_ENGINE_TESTS.md`) measured **3–11 ms per small cut**
   after a ~65 ms warm-up, and ~10 ms on a watertight MeshPart. Keep CSG for the **beam** type.
4. **EditableMesh:** not worth it. Client-only cosmetics, 20k-triangle cap, strict memory budget,
   and collision updates only via `CreateMeshPartAsync`.
5. **Structure:** a Blast-style support graph with BFS islands, a cantilever limit and a core
   threshold. A slice defines its falling set, so the graph runs only on the lower half.
6. **Collapse:** clients move the upper half with `BulkMoveTo` along a closed-form path (slide
   down the cut, then a decelerating sink) and delete levels at analytic times, with per-level
   seeded debris. The server flips collision, builds lower pieces and deletes levels on schedule.

---

## 1. Analytic plane slicing without CSG

**Algorithm.** A plane `n·x = d` cut of a convex polygon is Sutherland–Hodgman against one
half-plane, run twice (once per side). Walk the edges, keep vertices with `s = n·v − d ≥ −ε`,
and emit the intersection `v_i + (v_j − v_i)·s_i/(s_i − s_j)` on each sign change (Sutherland and
Hodgman, "Reentrant Polygon Clipping", CACM 1974; Ericson, *Real-Time Collision Detection* §8.3,
"splitting polygons against a plane"; the `split-polygon` npm package implements the same
routine). Convex input gives convex output on both sides.

**Why our parts reduce to 2D.**

- **Prism along an axis the plane contains:** if `n·a = 0` for the prism axis `a`, the cut is
  exactly a 2D line clip of the cross-section, with no approximation.
- **Thin prism, any plane:** intersect the plane with the prism's mid-plane, clip the 2D
  footprint by that line, and re-extrude. The true cut face is tilted, so the error is at most
  `(t/2)·tan φ`, where `φ` is the angle between the cut plane and the prism axis. If
  `|n·a| ≈ 1` (a plane parallel to the slab), assign the whole part to the side of its centre.
- **General thick box:** an arbitrary cut gives polyhedra of up to 7 faces, which Parts and
  WedgeParts cannot express exactly. Use the snapping trick or CSG. We have no thick structural
  boxes once shells are hidden.

**Decomposing the clipped polygons (exact, in the part's local frame):**

| Input | Line crosses | Side A | Side B | Total |
|---|---|---|---|---|
| Rectangle | two adjacent edges (corner cut) | right triangle: 1 WedgePart | pentagon: 2 Parts + 1 WedgePart | 4 |
| Rectangle | two opposite edges | right trapezoid: 1 Part + 1 WedgePart | the same | 4 |
| Right-triangle wedge | any two edges | triangle: 1–2 WedgeParts | quadrilateral: 2 triangles, 2–4 WedgeParts | ≤ 6 |

- A WedgePart is the right triangle `(−Y,−Z),(−Y,+Z),(+Y,+Z)` (half-sizes) in local YZ, extruded
  along X (`PartExtents.WEDGE_YZ`; `PolygonSlab` puts thickness on X). 90° turns about X move the
  right angle to any corner. A non-right triangle is two wedges split at the foot of the
  perpendicular from the vertex opposite the longest edge (EgoMoose "3D triangles";
  `TriangleShell.wedgesFor`).
- **Reuse:** `clip(footprint) → PolygonSlab.Build(...)`, in the wall's own frame for core walls.
  Later, add a plan-only variant returning `{class, cframe, size}` rows, so server and client run
  the identical function.
- Copy `Material`, `MaterialVariant`, `Color` and tags. Re-clone `Texture` children and shift
  `OffsetStudsU/V` by the piece offset. The engine tests found CSG also drops Texture children, so
  both paths need this helper. Drop slivers under `PolygonSlab.MIN_SIZE = 0.05`.

**Sketch (Luau-style):**

```lua
-- Plane in the building frame; quantized by the server before sending.
local function slicePrism(row, plane)          -- row: {class, cframe, size, poly2D, axis}
  local a  = row.cframe:VectorToWorldSpace(row.axis)
  local nA = plane.n:Dot(a)
  if math.abs(nA) > 0.995 then                 -- plane parallel to the slab
    return sideOf(row.cframe.Position, plane), nil
  end
  -- line = plane ∩ mid-plane, expressed in the row's local 2D coordinates
  local n2, d2 = projectPlaneToLocal2D(row, plane)
  local above, below = clipHalf(row.poly2D, n2, d2, 1e-4), clipHalf(row.poly2D, -n2, -d2, 1e-4)
  return planPieces(above, row), planPieces(below, row)  -- PolygonSlab plan rows
end
```

**Cost compared with CSG.**

- **Analytic:** per cut part, about 20 dot products, one clip, and 2–6 `Instance.new` calls
  **[est: ≈0.05–0.2 ms in Luau, measure]**. A diagonal slice through a 30-floor tower with 1–5
  rects per floor and a 6-wall core crosses about 50–150 parts, so about 200–600 new primitives.
  They are instanceable, batch well, and replicate as small property sets.
- **CSG:** each op yields and returns a unique mesh. Our tests measured 3–11 ms per small cut on
  a textured skin (65 ms first call) and 5–23 ms on a watertight MeshPart **[local test]**. One
  DevForum report: ~1.5 s for one subtract over ~475 bricks **[community]**. A plane split
  costs two ops per part (intersect and subtract against a half-space box), so a 100-part slice
  is roughly 1–2 s of async CSG, plus 200 replicated meshes.
- **Verdict:** yes, the whole slice type can run without CSG. The only exception is a cut
  through a part that is *already* a carved PartOperation. Assign it whole to one side by
  centroid (under dust), or run one `IntersectAsync` per side against a half-space box.

**Roblox prior art [community]:** "Slice a Block like a lightsaber" (2019) used wedge splitting
with CSG fallback. No maintained runtime plane-slicer module exists.

## 2. GeometryService in 2024–2026

| Topic | Finding |
|---|---|
| Release | Fully released 2025-11-12; also `FragmentAsync`, `GenerateFragmentSites`, `SweepPartAsync`. BasePart CSG is legacy **[staff/doc]**. No published triangle or op limits. |
| Async | Yields. Ops "run asynchronously and don't block the main thread" **[staff, beta post]**. Results are unparented; you parent them and destroy the originals. Wrap every call in `pcall`. |
| Client | "Already works in LocalScripts" **[staff]**. Client results don't replicate, which suits cosmetic stand-ins. |
| Options | `CollisionFidelity`, `RenderFidelity`, `FluidFidelity`, `SplitApart` (default true: disconnected pieces come back as separate parts, a free island split). `Default` collision uses an exact-collision algorithm in most cases and is "significantly faster" than `PreciseConvexDecomposition`, which is "very slow" **[staff]**. Use `Box`/`Hull` for debris. |
| MeshParts | Beta from 2026-03-12; live in published games since **2026-07-07**. Inputs must be **watertight** (keep under ~20k faces); Part + MeshPart → MeshPart **[staff]**. Confirmed locally: an EditableMesh-built box carves in ~10 ms and stays a MeshPart, while our FBX scan mesh fails with "Non-manifold mesh part (error -33)" **[local test]**. |
| Fragment | Voronoi split into MeshParts. `GenerateFragmentSites` is "partially random", so for multiplayer pass **your own seeded sites** **[doc]**. Each fragment is a simulated Instance. Report: explosions calling fracture 50–100 times take "many seconds" **[community, 2026-06]**. |
| Replication | No official size numbers. Developers report CSG dominating replication time. Staff are working on serving only a render-optimized mesh **[staff]**. Third-party coverage says delta replication cut CSG bandwidth "up to 90%" around April 2026 **[2nd, unverified]**. |

**Throttling patterns:** greedy-merge parts before carving; start at hit time and parent at
`tBreak`; cap at ≤ 8 starts per frame and ≤ 16 in flight, nearest-first **[est]**; delete rather
than carve `NoCSG` parts; on `pcall` failure delete and spawn debris; if replication measures
badly, carve cosmetically on clients over simplified server collision.

## 3. EditableMesh for destruction

- **Limits [doc]:** 60k vertices and 20k triangles per mesh; "strict client-side memory budgets"
  with no published figure (one user hit it at 8 meshes **[community]**); off in published games
  until **Enable Mesh / Image APIs** is on. Collision updates only after `CreateMeshPartAsync` and
  `ApplyMesh`. Undestroyed meshes leak fast **[community]**.
- **One real use:** EditableMesh can author *watertight* MeshParts that CSG carves (~10 ms per cut
  in our test). Runtime-made meshes don't persist, so production meshes must be uploaded assets.
- **Fit:** client-only cosmetics (dents, a glowing cut face, or merging a falling upper half into
  one mesh, about 3–7k triangles, so each frame is one CFrame write). It gives the server no
  collision, so gameplay cuts would need a second representation. **Skip it** unless `BulkMoveTo`
  of upper halves measures too slow.
- Voxel modules (VoxelDestruct 2.1: greedy meshing, 10k-part pool, `OnClient` mode) find part
  count, not geometry, to be the real cost **[community]**.

## 4. Structural integrity for slab + core buildings

**What the references do:**

- **NVIDIA Blast:** support graph of chunks and bonds; world bonds mark anchored chunks. After
  damage, **island detection** finds connected groups, and islands not bound to the world become
  dynamic. An optional stress solver pushes gravity loads through bonds **[ext, doc]**.
- **Unreal Chaos:** nearest-neighbour connection graph whose links carry strain; anchor fields pin
  pieces **[ext, doc]**.
- **The Finals:** GDC 2024 "Engineering Mayhem" covers connection-graph construction and debris
  replication for server-side destruction of Houdini-prefractured buildings **[ext, abstract only]**.
- **Red Faction: Guerrilla:** pre-broken meshes plus real-time stress; weakened supports topple
  structures **[ext, press]**. **Battlefield 2.0:** collapse after a scripted damage threshold
  **[ext, wiki]**. **Teardown:** connectivity only **[ext, unverified]**.

**Adapted model (cheap and deterministic):**

```
StructureGraph (per building, server, built once from InteriorGrid / rects)
  cells[f][i]   : uint8 flags  PRESENT | CORE | PERIM | GROUNDED
  coreHealth[f] : number        -- intact core wall area at floor f
  coreInit[f]   : number
Edges are implicit: 4-neighbour within a floor, plus vertical when both cells are CORE or PERIM.
```

1. **Connectivity (Blast/Teardown):** BFS from GROUNDED cells (floor 0). Unreached cells fall.
2. **Cantilever (cheap stress stand-in):** BFS distance from the nearest supported CORE or PERIM
   cell is above `Lmax` (3–4 cells), so the cell falls. This also trims the overhangs a diagonal
   slice leaves.
3. **Core capacity (RF:G/Battlefield thresholds):** if `coreHealth[k]/coreInit[k] < τ(floorsAbove)`,
   everything above `k` becomes a collapse event, leaning toward the centroid of the lost core.
4. **Slices:** the plane defines the upper half. Run 1 and 2 only on the lower half's top 1–3
   floors, in ≤ 1 ms server time-slices (8k cells for 40 floors is a few ms total).

## 5. Collapse choreography

**Path of the upper half `U`** (closed form, evaluated identically everywhere):

- **Phase S (slide):** direction `ŝ = normalize(g − (g·n)n)`, the gravity projected onto the cut
  plane, so it slides down the cleave. `x(t) = ½·a_s·t²` with `a_s = g·sin θ·k` (`k≈0.6` for
  "heavy" feel), until `T_s`, when `U`'s centre of mass passes the edge of the lower half's cut
  face. That is computed analytically from the footprint.
- **Phase C (crush through):** `U` is `CanCollide=false` from `t=0`. From `T_s`, vertical motion uses constant
  deceleration from the entry speed `v_c` to rest over depth `D = top(U) − top(L)`:
  `a_c = v_c²/(2D)` and `y(t) = v_c·t − ½·a_c·t²`. A small seeded tilt `θ(t)` leans away from
  the cut, up to about 5°.
- **Level deletion:** level `k` (bottom `y_k` in `U`) is deleted at the analytic time its top
  sinks below `top(L) + margin`, hidden inside `L` and dust, so levels vanish without a visible
  pop. The server solves each quadratic once.
- **Lower-half damage (step 7):** at the moment `U`'s base passes each of `L`'s top floors, delete
  their `NoCSG` contents and remove the cells under `U`'s footprint (analytic rect-minus-rect,
  1–4 Parts). No CSG.

**Debris and dust budgets** (consistent with the combat doc):

| Item | Budget |
|---|---|
| Debris per slice event | ≤ 60 pieces per client, ≤ 12 per deleted level, spawned over 3–5 frames |
| Active debris per client | ≤ 250, pooled; kinematic `p0+v·t+½g·t²` to a precomputed ground height, then anchored |
| Dust | ≤ 8 emitters per event (cut line, each level deletion, base ring), ≤ 400 live particles |
| Far clients (> ~1,500 studs) | Rigid `U` motion, level deletions, dust only; no chunks |

**Seeds.** Use per-level sub-seeds, `Random.new(hash(seed, levelIndex))`, so debris never depends
on frame timing. Distance LOD takes a prefix of the same seeded list. The cut path uses only dot
products and division on quantized inputs (normal int16/32767, offset 1/64 stud, epsilon `1e-4`),
so vertex signs match on server and client **[est]**. Any divergence affects only lower-half
stand-ins, which the server's pieces replace. No showcase found publishes a scripted "slide then
sink" sequence; this design is our own.

## 6. Pre-fractured libraries versus runtime cutting

| Type | Recommended technique | Why |
|---|---|---|
| **Physical** | **Analytic holes plus prefractured debris templates.** Slab or wall minus an **octagon aligned to the part's axes** = 4 band Parts + 4 corner WedgeParts (8 primitives), with a jagged look from debris. Pooled, seeded chunk templates (a few dozen shapes, shared MeshIds or Parts) for rubble. CSG only for irregular ground or already-carved unions. | Holes are covered by dust and debris; exact round edges aren't readable. Primitives instance and replicate cheaply. Matches Red Faction moving from runtime CSG to pre-broken pieces. |
| **Beam** | **GeometryService CSG** (sphere or capsule; `SweepPartAsync` for curved beams). Server copy started at hit time, parented at `tBreak`; client cosmetic CSG at `tBreak`; `Default` fidelity; capped concurrency; analytic octagon when over budget or far. Warm up once at server start (first cut ~65 ms). | The smooth erased volume is Hollow Purple's signature, and 3–11 ms per cut is affordable for a handful of slabs. |
| **Slice** | **Fully analytic** (sections 1 and 5). No CSG and no fragmenting. Optional: one `FragmentAsync` with seeded sites for a hero chunk on the cut face, client-side and near camera only. | Exact, cheap and deterministic. It also powers "drop the target through the floor" (rect-minus-rect hole under the target at `tBreak`). |

The slice is also the right primitive for scripted collapses. A core-capacity failure at level `k`
is a horizontal or near-horizontal slice at `k` with lean `θ`.

## 7. Collapse pipeline design

**Data (server, shared by id with clients):**

```
BuildingRecord { id, frame: CFrame (yaw-only), levels: {LevelRecord}, core: {PartRow},
                 graph: StructureGraph, generation }
LevelRecord    { index, yBottom, yTop, rows: {PartRow} }        -- sorted, stable order
PartRow        { idx: uint16, class, cframe, size, poly2D, axis, noCSG }
SliceEvent     { seq, eventId, generation, buildingId, tSlice,
                 plane = { n: int16x3, d: int32 /64 },
                 slide = { dir: int16x3, a_s, T_s }, crush = { v_c, a_c, D },
                 levelDeleteAt: {[k]=t}, lowerDamage: {[floor]=t},
                 seed: uint32, debrisCap }                      -- about 150–250 bytes
```

`PartRow.idx` is a stable per-building index attribute written by BuildingGenerator, so timelines
name parts without `GetDescendants` scans.

**Server flow.**

1. **Plan** (≤ 2 ms): snap the plane to a building axis; classify rows as above, below or cut
   (only levels straddling the plane need per-row tests); compute `T_s`, `D`, `levelDeleteAt`
   and `lowerDamage`; send one `WorldTimeline` message.
2. **Pre-build** before `tSlice` (≤ 2 ms per frame): lower-side pieces of cut rows, unparented.
3. **At `tSlice`:** parent the lower pieces and destroy the cut originals. Set upper rows
   `CanCollide=false, CanTouch=false`. Players standing on `U` fall under their own physics, or
   get collateral paths.
4. **At each `levelDeleteAt[k]` and `lowerDamage` time:** destroy those parts, ≤ 60 per frame.
5. **Afterwards:** time-sliced support check on `L`, a rubble pile part, bump `generation`.

**Client flow.**

1. **On receipt** (inside the 60–120 ms hitstop): run the same plan-only slicer; build local
   upper pieces and lower stand-ins, unparented; gather the upper parts list. These are the
   server's anchored originals, and local CFrame writes persist because the server never moves
   them.
2. **At `tSlice`:** hide the cut originals locally (`LocalTransparencyModifier=1`,
   `CanCollide=false`) and parent the local pieces.
3. **Each `PreRender`:** `workspace:BulkMoveTo(upperParts, path(now − tSlice) cframes,
   Enum.BulkMoveMode.FireCFrameChanged)`, ≤ about 600 parts **[est ≤ 1 ms]**, with per-level lag
   offsets for pancaking.
4. **At `levelDeleteAt[k]`:** drop that level from the move list, hide it locally (the server's
   destroy follows), and spawn its seeded debris and dust.
5. **Cleanup:** delete stand-ins when server pieces tagged `SliceId` arrive. A late joiner or late
   packet evaluates at `now − tSlice` and skips finished deletions.

**Per-frame budgets (60 fps):**

| Work | Server | Client |
|---|---|---|
| Slice planning and pieces | ≤ 2 ms | ≤ 2 ms (≤ 50 instances created per frame) |
| Upper-half motion | none (static) | ≤ 1 ms (`BulkMoveTo`) |
| Level or part deletion | ≤ 60 destroys per frame | ≤ 60 hides per frame |
| Support check | ≤ 1 ms time-slice | none |
| CSG (beam only) | ≤ 8 starts per frame, ≤ 16 in flight | cosmetic, ≤ 4 in flight |
| Debris | none (damage is analytic) | ≤ 15 spawns per frame, ≤ 250 active |
| Network per slice | 1 timeline message (~200 B) + replicated lower pieces (~100–200 parts) | none |

**Open measurements** (owner-approved measurement pass):

- Luau cost per `slicePrism` and per `Instance.new`.
- `BulkMoveTo` cost for 300 and 600 anchored parts on a laptop.
- Replication bytes per new primitive versus per CSG result.
- `SubtractAsync` ms for one slab with a sphere and with a capsule, on server and on client.
- `FragmentAsync` determinism with fixed sites.

---

## Sources

- GeometryService reference [doc]: https://create.roblox.com/docs/reference/engine/classes/GeometryService
- CSG full release, 2025-11-12, and replies through 2026-07 [staff/community]: https://devforum.roblox.com/t/full-release-improved-constructive-solid-geometry-csg-apis/4065505 (page 2: `?page=2`)
- Studio Beta: Solid Modeling on Meshes and Fragment/Sweep APIs, 2026-03-12, update 2026-07-07 [staff]: https://devforum.roblox.com/t/4515374
- Third-party summaries [2nd]: https://www.creation.dev/learn/roblox-solid-modeling-meshpart-support-geometry-service , https://www.creation.dev/learn/roblox-csg-solid-modeling-delta-updates-performance
- SubtractAsync lag report (≈1.5 s for 475 bricks) [community]: https://devforum.roblox.com/t/need-help-finding-what-is-causing-lag-spikes/3987926
- EditableMesh reference [doc]: https://create.roblox.com/docs/reference/engine/classes/EditableMesh
- EditableMesh restrictions, leak and budget reports [community]: https://devforum.roblox.com/t/editablemesh-restrictions/4566101 , https://devforum.roblox.com/t/editablemesh-fails-to-destroy/4203502
- Slice a Block like a lightsaber [community]: https://devforum.roblox.com/t/slice-a-block-like-a-lightsaber/357505
- Is slicing parts possible now? [community]: https://devforum.roblox.com/t/is-slicing-parts-possible-now/227604
- SliceAsync stray part [community]: https://devforum.roblox.com/t/sliceasync-creates-a-floating-invisible-microscopic-part-im-going-insane/3195565
- EgoMoose, 3D triangles with WedgeParts: https://github.com/EgoMoose/Articles (folder "3d triangles")
- VoxelDestruct 2.1 [community]: https://devforum.roblox.com/t/voxeldestruct-21-voxelated-destruction-physics-with-greedy-meshing-hitboxes-and-more/3044264
- Non-destructive voxel engine [community]: https://devforum.roblox.com/t/my-non-destructive-voxel-destruction-engine/3980658
- Sutherland and Hodgman, "Reentrant Polygon Clipping", CACM 17(1), 1974; Ericson, *Real-Time Collision Detection* (2005), §8.3; split-polygon: https://www.npmjs.com/package/split-polygon
- NVIDIA Blast support graph, islands and stress [ext]: https://docs.nvidia.com/gameworks/content/gameworkslibrary/blast/1.1/api_docs/files/pageintroduction.html , https://docs.nvidia.com/gameworks/content/gameworkslibrary/blast/1.1/api_docs/files/pageextstress.html
- Unreal Chaos destruction overview [ext]: https://dev.epicgames.com/documentation/en-us/unreal-engine/destruction-overview
- The Finals, GDC 2024 "Engineering Mayhem" [ext]: https://gdcvault.com/play/1034280/Engineering-Mayhem-Technical-Deep-Dive ; Houdini buildings: https://www.sidefx.com/community/making-the-procedural-buildings-of-the-finals-using-houdini/
- Red Faction: Guerrilla Geo-Mod 2.0 [ext]: https://www.redfactionwiki.com/wiki/GeoMod_2.0 , https://www.thesixthaxis.com/?p=10391
- Frostbite destruction (Kihl, SIGGRAPH 2010) [ext]: https://www.advances.realtimerendering.com/s2010/Kihl-Destruction%20in%20Frostbite(SIGGRAPH%202010%20Advanced%20RealTime%20Rendering%20Course).pdf ; Battlefield destruction wiki: https://battlefield.fandom.com/wiki/Destruction
- Local engine tests (CSG timings, MeshPart carving, Texture loss): `tools/research/R2_ENGINE_TESTS.md`
- Repo: `src/server/PolygonSlab.luau`, `src/server/TriangleShell.luau`, `src/server/PartExtents.luau`, `src/server/HitHandler.luau`
