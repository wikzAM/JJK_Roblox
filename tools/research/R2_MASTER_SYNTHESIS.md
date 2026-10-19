# Master synthesis: research waves 1–2 into one plan (2026-10-19)

This is research only. No game code changed. It ties together every file in `tools/research/` into one architecture and a phased plan with gates. For the reasoning and sources, read the linked docs; this file gives only the conclusions.

**Status key:**
- **Agreed** — the owner agreed in discussion.
- **Proposed** — research recommends it; the owner has not decided.
- **Measure** — needs an in-engine number before we commit.

---

## 1. The one-paragraph answer

The place is too big for every machine it touches:
- **About 1.14M instances**, of which roughly 75% are ground facades and about 16% are slab wedges.
- **The live server** needs about 7 GB at about 6.4 KB per part. The limit is 6.25 GiB plus 100 MiB per player. This is the likely cause of the error-288 shutdowns.
- **Studio** needs about 20.7 GB on a 16 GB PC.
- **Laptops** shorten draw distance, so the skyline vanishes.

Every pillar the owner set needs a **lean, permanent map**:
- about 60k parts;
- 10–25 parts per building;
- facade detail in baked textures;
- one stand-in mesh per block for the skyline;
- a painted horizon.

Destruction and combat run on **server timelines**, carried out the same way on every client. Most destruction needs no CSG:
- **Slices** are analytic 2D cuts.
- **Physical holes** can be built from primitives.
- **CSG is kept** for beams and glass-pane holes.

Victims fly on **anchored kinematic paths** that they can steer with capped inputs. Hits are checked on the server with rewind. Everything is checked on **live private servers of a test place with bots**, because Studio cannot load-test this place.

---

## 2. Hard facts that drive everything

| Fact | Source | Consequence |
|---|---|---|
| Live server memory limit is 6.25 GiB + 100 MiB × peak players; about 6.4 KB per part | `../OPTIMIZATION_RESEARCH.md` §1.1 | 1.14M instances is at or over the limit. **The lean map is required, not optional.** |
| Roblox shortens draw distance on its own under load; developers can't override it | `SPEED_SKYLINE_STREAMING.md`, `R2_SKYLINE_HORIZON_RENDERING.md` | The skyline needs few, large objects plus a skybox |
| `PrioritizeLightingQuality = Disabled` lowers lighting first "to preserve draw distance" | `R2_SKYLINE_HORIZON_RENDERING.md` §1 [staff] | Free lever. Set it in the lean place (**Proposed**) |
| SLIM, StreamingMesh and Server Authority all require streaming | R2 skyline, R2 netcode | None apply while streaming is off |
| CSG: 3–11 ms per small cut after a ~65 ms warm-up; Textures are not carried over; interior holes keep bounds | `R2_ENGINE_TESTS.md` T1 | Pane holes on textured skins are viable, with a clone and offset-fix helper |
| Watertight MeshParts are carvable; EditableMesh content doesn't replicate or persist | `R2_ENGINE_TESTS.md` T2 | Meshes must be **uploaded** assets. Uploads are capped at about 20 Models per day, so use a small reusable set |
| Transparent objects behind Glass aren't drawn; per-object transparent sorting | `R2_FACADE_BAKING_PIPELINE.md` §3 | No alpha skins. The building you're inside uses its Part version |
| Studio local server can't load-test (20.7 GB per client) | `R2_LOAD_TEST_PROFILING.md` | Load tests run on live private servers of a separate test place |
| Ground facades are 607k parts (~70%); slab wedges are 140k (~13.4 per level) | `R2_CITY_INVENTORY.md` | Baking ground facades and merging slabs are the two biggest levers |
| Studio ignores quality-level draw distance | R2 skyline | Skyline checks must use the live player |

---

## 3. Architecture by layer

### 3.1 The city (rendering and memory)

| Layer | What | Budget (low-end laptop) | Status |
|---|---|---|---|
| Horizon | Day and night skyboxes at 1,024 px with a painted Tokyo band aligned to real bearings; Atmosphere haze tuned to the skybox horizon colour | 0 draw calls of geometry; about 48 MB textures | Proposed (recipe in R2 skyline) |
| Edge ring | 28 uploaded MeshParts 400–1,500 studs past the edge, plus a ground skirt | about 30 draw calls; about 120k triangles | Proposed |
| Block stand-ins | At most 250 uploaded meshes, one per block, inset 1.5 studs. Hidden within 300 studs of the camera and shown again beyond 400 (a visibility flag, never rebuilt). Damage hides the stand-in and shows a 1–4 Part box kit. | about 250 draw calls; ≤250k triangles | Proposed; **Measure** whether they survive graphics level 1 |
| Buildings | 4–6 textured skin Parts, 4–8 slab and pier Parts, 1–3 sign columns, 1–3 roof clutter Parts | 10–25 parts each; about 60k map-wide | Agreed target |
| Street level | The Part version of ground facades only within about 150 studs, for the occupied building, and for damaged bays (one way). Hysteresis 150 in / 210 out, a speed gate, pooled templates, instant swap. | ≤200 draw calls for the near city | Proposed; see the conflict note in §6 |
| Interiors | Pseudo-3D bay rooms for Part-version zones only | — | Existing system, kept |

**Lighting (Proposed):** LightingStyle Realistic, PrioritizeLightingQuality Disabled, Ambient (90, 92, 98) as the floor already shipped in WorldSetup. Night values are in R2 skyline. Night signage cost is being researched (wave 3).

### 3.2 Facades: one design source, two outputs

- **Source of truth:** the existing Part kits (`GroundFacadeKit`, `UpperFacadeKit`) plus the new Tokyo style kit.
- **The new Tokyo style kit** (`R2_TOKYO_FACADE_ART_DIRECTION.md`):
  - 12 families plus a 2018 construction overlay;
  - district weights;
  - neighbour-difference rules;
  - tint jitter and phase offsets;
  - night lit masks;
  - hand-built heroes: 109, Q-Front, Hikarie, the Scramble Square construction frame, Mark City, the station.
- **The bake pipeline** (`R2_FACADE_BAKING_PIPELINE.md`):
  - Build each key in a bake place.
  - Capture tiles with `StudioCaptureService` at FOV 1, 2× and downsampled.
  - Post-process in Python: calibration, normal, roughness and night masks.
  - Upload via Open Cloud.
  - Apply one opaque skin Part per bay, with one Texture and its PBR maps.
  - Gate: about 1,000 keys or fewer.
- **Glass:** each pane is logical.
  - Intact: the pane is only in the texture.
  - Cracked: an opaque overlay Part.
  - Broken: one batched `SubtractAsync` per bay per event, plus a Texture clone and offset fix.
  - The existing `GlassDamageService` stays and becomes logical-first.
- **Upper floors:** the client `UpperFacadeRenderer` (tear-down/rebuild) is retired. Its kit becomes a bake source.

### 3.3 Destruction: three types, mostly no CSG

| Type | Server | Clients | CSG? | Source |
|---|---|---|---|---|
| Physical hit | Plan the capsule; delete `NoCSG` contents; carve structural parts. Option: octagon holes built from about 8 primitives instead of CSG. | Seeded kinematic debris (≤250 active, pooled), dust | Optional (**Measure**: CSG ms vs primitive count) | `COMBAT_MOTION_DESTRUCTION_SYNC.md`, `R2_SLICE_COLLAPSE_CSG.md` |
| Beam | `SubtractAsync`; ≤8 starts per frame, ≤16 in flight | Glowing beam VFX (large, always visible) | Yes | same |
| Slice | Snap the plane to a building axis. 2D Sutherland–Hodgman clip, then re-extrude: ≤4 pieces per rectangle, ≤6 per triangle. Flip collision at `tSlice`. Delete levels on schedule. | Same plan-only slicer. `BulkMoveTo` the upper half along a closed-form slide-then-sink path. Hide levels at analytic times; seeded debris per level. | **No** | `R2_SLICE_COLLAPSE_CSG.md` §1, §5, §7 |

- **Structure:** a per-building cell graph built from `InteriorGrid`:
  - BFS from grounded cells, so unreached cells fall;
  - a cantilever limit of 3–4 cells;
  - a core-capacity threshold triggers collapse.
- **Slice event message:** about 200 bytes. Requires a stable per-part `idx` attribute written at generation time, so no `GetDescendants` scans are needed.

### 3.4 Combat motion and netcode

The design is in `R2_CHARACTER_NETCODE.md`:

- **Grounded:** the stock client Humanoid, with server speed and teleport checks. It could later move to a Chickynoid-lite controller if needed.
- **Airborne victims:** an anchored root and analytic segments planned by the server with spherecasts. Each segment has a server-clock start time.
- **Teleport fake (tier B):** a `Hidden` segment; clients snap under dust.
- **Steering is input-based:**
  - The client sends `{stamp, angle u8, mag u4}` at 30 Hz, unreliable, ×3 redundant.
  - The server integrates the inputs under hard caps; the client predicts and replays.
  - Influence tiers:
    - DI read once at hitstop end (±12° base);
    - a lock for 150–200 ms;
    - perpendicular steering (`a ≤ k·g`, total deviation ≤ 35°);
    - a meter- or cooldown-gated redirect.
- **Hits:**
  - Clients send stamped attack intent.
  - The server rewinds up to 200 ms (clamped to the measured RTT) using a one-second position history, and tests with capsule maths.
  - Today's client-trusted `HitEvent` is replaced.
- **Timelines:** one reliable, sequenced `WorldTimeline` remote carrying:
  - path segments;
  - break times;
  - seeds;
  - slice and collapse events.
  
  A 60–120 ms hitstop hides latency. Event detail can be cut by sector for far clients (same timeline, less rendering).
- **Bots:** a kinematic ground controller, AI at 5–10 Hz, and the same victim service when hit. Start with 10–20 bots.
- **Budget:** about 30–50 KB/s received per client; steering is under 10 KB/s.

### 3.5 Measurement and load testing

Details are in `R2_LOAD_TEST_PROFILING.md`:

- **Where:** a separate test place with a `PerfMode` flag. It runs a seeded scenario playlist (S0–S8) on live private servers, writes results to a DataStore, and a Python script pulls them and diffs against budgets.
- **Server budgets:**
  - heartbeat p95 ≥ 58 Hz;
  - memory ≤ 2.5 GB (fail above 3 GB);
  - hit-to-launch ≤ 100 ms (fail above 150);
  - receive ≤ 40 KB/s per client.
- **Client low tier:**
  - ≤350 draw calls;
  - ≤500k triangles;
  - ≤1.5 GB memory;
  - 60 FPS on a real Iris Xe laptop, which is the final gate before launch.
- **Bot limits:** bots reproduce server load, not per-client memory. Validate with one real 20-player night per milestone.

---

## 4. Phased plan (each phase gated by measurement)

Nothing here is authorized yet unless marked. "Owner OK" means the step needs a yes before work starts.

### Phase 0: Quick wins on the current place (hours; owner called A/B "good starts", not yet authorized to implement)

1. **Fix A:** hit-path queries scoped to nearby folders; no whole-map `GetDescendants` (2.2 s today).
2. **Fix B:** launch the victim first, then budget destruction per frame behind dust.
3. Pause the `UpperFacadeRenderer` churn (build once, or off).
4. Set `PrioritizeLightingQuality = Disabled` (one Studio property; reversible).

**Gate:** hit-to-launch under 150 ms in Studio Play; no facade pop.

### Phase 1: Measurement pass (one evening; **owner-approved**)

1. Live client at graphics levels 1/3/5/10 and Automatic: which part sizes and counts survive the draw-distance cut, with PrioritizeLightingQuality on and off.
2. A streaming test in a copy of the place (persistent stand-ins, 1,000–1,500 stud radius, top speeds, teleports with and without pre-loading). This is the fallback check only.
3. Replication bytes per new primitive versus per CSG union (wave 3 research feeds the method).
4. `BulkMoveTo` cost for 300/600 anchored parts; `slicePrism` Luau cost.

**Gate:** decide the final per-building budget and whether stand-ins survive level 1.

### Phase 2: Three-building comparison (days; owner OK)

Build the same three buildings (a zakkyo F1, a tile mansion F4, a curtain-wall tower F6) three ways:
- (a) today's Part facades;
- (b) a lean shell with baked skins;
- (c) b plus the street-level Part swap.

Measure parts, draw calls, memory and visual match at 100/150/300 studs.

**Gate:** owner visual sign-off on (b) and (c).

### Phase 3: Pipelines (1–2 weeks)

1. **Bake pipeline:** `tools/facade_bake/`, `FacadeBakeManifest`. Start with F1, F4 and F9.
2. **Offline place pipeline:** wave 3 is researching Lune and rbx-dom for building the lean place without loading 20 GB into Studio.
3. **Stand-in and edge-mesh generation and upload:** 5-block pilot first.
4. **Per-part `idx` attributes and the structure graph** in BuildingGenerator.

### Phase 4: Lean map migration (weeks)

1. Generate the lean place district by district: station core first, Center Gai second.
2. Keep the old place untouched until the lean one passes S1–S3.
3. Retire `FacadeRenderer` (v1), `UpperFacadeRenderer`, `GroundFacadeCompact` and the snapshot cleanup tools.

**Gate:** S1/S2 pass on the L-proxy; skyline visible at level 1; server memory ≤ 2.5 GB.

### Phase 5: Combat core (weeks, in parallel with phase 4 once phase 0 lands)

1. `MotionPath`, `PathPlanner`, `VictimService`, `PosHistory`, `CombatService` with rewind, `WorldTimeline`.
2. Slice destruction (no CSG) plus the collapse choreography; then beams; then physical holes.
3. Bots (`BotService`).

**Gate:** S3/S4 on a live private server: heartbeat, receive KB/s, hit-to-launch.

### Phase 6: Night look and art pass

Tokyo kit families F1–F12, night masks, signage rules, hero landmarks, street clutter (near only). Lighting cost comes from wave 3.

---

## 5. Decisions still open for the owner

1. **Stand-in fallback.** If stand-ins don't survive graphics level 1, accept skybox-only at level 1 with a prompt to raise graphics, or reduce the stand-ins further?
2. **Physical holes.** CSG cylinders (look better, more replicated data) or 8-primitive octagons (cheap, faceted)? Decide after the phase 1 bytes measurement.
3. **Grounded movement authority.** Stock Humanoid with checks (cheap, proposed) or a full custom controller (exploit-proof, much more work)?
4. **Reference board.** About 30 Shibuya photos plus about 20 anime frames per district, before authoring textures. Does the owner want to gather these, or should Claude compile links?
5. **Hero landmarks.** Build by hand (owner or a commissioned modeller) or kit-based approximations first?
6. **Account steps only the owner can do:**
   - Open Cloud API key (kept in a local env var);
   - ID verification for asset and mesh uploads;
   - one-time screenshot permission in Studio;
   - a separate test place.

---

## 6. Tensions and how they resolve

| Tension | Resolution |
|---|---|
| "Never tear down or rebuild detail around the camera" vs the street-level Part swap | The swap only **shows and hides** pooled, pre-built Parts (`LocalTransparencyModifier`). Small radius, wide hysteresis, a speed gate, and nothing destroyed. Stand-in near-hide uses the same rule. If hitches show in measurement, drop to "Part version only for damaged bays and the occupied building". |
| Whole map on every client vs memory | The lean map (≈0.4 GB at 60k parts) makes this possible. Streaming stays the measured fallback. |
| Victim steering vs exploit resistance | Input-based steering: the server computes, the client predicts. Caps hold by construction. |
| Identical holes for all viewers vs CSG being async | The server timeline schedules break times. Clients hide or show at `tBreak`; the server's carved result replaces local stand-ins when it arrives. Slices are deterministic from quantized inputs. |
| Bakes look flat | PBR normal and roughness maps; 1–2 relief Parts per bay (canopies, blade signs); the Part version at street level. |
| Upload caps (20 Models a day) | A small reusable mesh set: one shared watertight box for skins if option B is used, about 250 stand-ins over about two weeks, or the Studio bulk importer. |

---

## 7. Research index

| File | Topic |
|---|---|
| `AAA_OPEN_WORLD_TECHNIQUES.md` | GTA, Spider-Man, etc.: permanent cheap layers, HLOD, no camera rebuilds |
| `ROBLOX_ENGINE_SCOPING.md` | Engine limits, culling, batching, memory |
| `SPEED_SKYLINE_STREAMING.md` | Why the skyline disappears; why streaming stays off |
| `COMBAT_MOTION_DESTRUCTION_SYNC.md` | Timelines, kinematic victims, seeded debris |
| `GAME_DESIGN_DECISIONS.md` | Living design doc (agreed decisions) |
| `SCOPED_PLAN.md` | First roadmap (superseded in detail by this file) |
| `R2_CHARACTER_NETCODE.md` | Steering authority, rewind hits, bots, bandwidth |
| `R2_LOAD_TEST_PROFILING.md` | Test harness, scenarios, budgets |
| `R2_CITY_INVENTORY.md` | Where the 1.14M instances are |
| `R2_ENGINE_TESTS.md` | In-engine CSG probes (T1, T2) |
| `R2_TOKYO_FACADE_ART_DIRECTION.md` | Tokyo style kit, districts, signage rules |
| `R2_SLICE_COLLAPSE_CSG.md` | Analytic slicing, structure graph, collapse pipeline |
| `R2_FACADE_BAKING_PIPELINE.md` | Capture, upload, skins, glass on skins, swap rules |
| `R2_SKYLINE_HORIZON_RENDERING.md` | Skybox, edge ring, stand-ins, lighting recipe |
| `R3_*` (wave 3, in progress) | Replication cost, night lighting, offline pipeline, competitor analysis |
