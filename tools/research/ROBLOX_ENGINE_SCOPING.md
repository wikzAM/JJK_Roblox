# Roblox engine scoping: what the engine gives us for a dense, destructible Shibuya (2026-10-19)

Research only. No code, place or Studio changes. This builds on
`tools/OPTIMIZATION_RESEARCH.md`, which covers memory, place size, streaming settings, SLIM,
EditableMesh and the hit-latency measurements. It is not repeated here except where new
sources change a conclusion.

Tags: **[doc]** Creator Hub docs (fetched 2026-10-19), **[staff]** Roblox staff DevForum
post, **[community]** non-staff report, **[est]** my inference, still to be verified in engine.

---

## (a) Executive summary

1. **The engine already culls what the camera cannot see.** Frustum culling has always been
   there. Automatic **occlusion culling** reached Studio Beta on 2024-11-07 and is now on by
   default ("skips draw calls for parts, meshes, and terrain occluded from view").
   - That removes the *rendering* reason for tearing facades down and rebuilding them as the camera turns.
   - It does not remove the *memory and instance-count* reason.
   - So: build per building with wide hysteresis, keep what is built, and let the engine cull each frame.
2. **Draw calls depend on asset reuse, not part count.** Meshes share a draw call when the
   mesh and texture/SurfaceAppearance (or material) match. Colour, size and CFrame are
   per-instance data. Transparency, decals on transparent parts, SurfaceGuis and particles
   add draw calls. A staff-category guest article budgets about 500 draw calls and 500k
   triangles per scene.
3. **SLIM and LOD do not fit destructible buildings.** SLIM covers static models only. Any
   runtime part add or remove "prevents SLIM from rendering the model correctly".
   `LevelOfDetail` looks edit-time only (capability `PluginOrOpenCloud`).
4. **Streaming never reduces server or Studio memory, and it fights fast movement.** It is
   also a hard requirement for Server Authority (full release 2026-07-09). That makes it a
   strategic decision for the owner, not a quick fix.
5. **Physics: "off by default, on at the moment" is native Roblox.**
   - Anchored parts and sleeping assemblies are not simulated.
   - `Humanoid.EvaluateStateMachine = false` "disable[s] the internal physics and state
     machine". That is the clean way to own the dummy completely.
   - Build the ragdoll from BallSocketConstraints only when needed, and anchor debris once it settles.
6. **Spatial queries got much faster in April 2026.** The new `IncludeInstances` and
   `ExcludeInstances` filters use log(n) lookups. The 2.2 s per-hit `GetDescendants` scan is
   self-inflicted. Use folder Include, `CanQuery=false` on facades, and bounds queries first.
7. **CSG:** GeometryService is fully released (2025-11-12) and runs in LocalScripts.
   - The reference page now lists MeshParts as inputs, but the staff release post listed
     MeshPart booleans as future work. Test before relying on it.
   - Each result is a new mesh that replicates. Reducing that bandwidth is also future work.

---

## (b) Findings by topic

### 1. Rendering and culling

- **Occlusion culling** **[staff]**: Studio Beta on 2024-11-07, now listed as default behaviour
  **[doc]**.
  - Automatic, no setup. Culls parts and meshes.
  - First-version exclusions: avatars, terrain (also "not used as an occluder yet"), lights,
    VFX, UI, animated objects and FastClusters.
  - The pass "tries to dynamically adjust itself to never be the bottleneck".
  - Biggest gains in dense, occluded scenes. That describes Shibuya streets.
  - No script API exposes occlusion state.
  - Sources: <https://devforum.roblox.com/t/studio-beta-introducing-occlusion-culling/3250604>,
    <https://create.roblox.com/docs/performance-optimization/improve>
  - **Unknown:** what counts as an occluder; staff didn't answer when asked. Assume Glass,
    transparent and thin facade parts don't occlude, and solid slabs and cores do **[est]**.
- **Instancing** **[doc]**:
  - Meshes with the same MeshContent share a draw call when their SurfaceAppearance, else their
    TextureContent, else their Material matches.
  - Upload each mesh once and duplicate it.
  - Per the 2017 staff post, size, CFrame and colour are per-instance data, and "same shape of
    a basic part" was an instancing goal.
    <https://devforum.roblox.com/t/rendering-updates-september-2017/54148>
  - Primitive-Part batching is undocumented today. Verify with the Ctrl+Shift+F2 draw-call count **[est]**.
- **Transparency and Glass:**
  - Layered transparency forces overdraw **[doc]**.
  - `Part.Transparency` "can cause unexpected extra drawcalls" **[staff-category guest
    article, MrChickenRocket, 2024-08-20]** <https://devforum.roblox.com/t/3127146>.
  - Glass refracts only at high quality levels, and "non-opaque objects aren't visible through
    glass", a limit set to avoid refraction cost **[staff, 2017]**.
    <https://devforum.roblox.com/t/introducing-new-material-glass/64231>
  - Treat every pane as a transparent, non-batching, non-occluding draw **[est]**.
- **CastShadow and RenderFidelity** **[doc]**:
  - Turn shadows off on small, distant or moving parts (FPS only).
  - Use Automatic or Performance mesh fidelity, not Precise in bulk.
- **SLIM** **[doc]**, announced Dec 2025.
  <https://create.roblox.com/docs/workspace/streaming/slim>,
  <https://about.roblox.com/newsroom/2025/12/introducing-roblox-slim-scalable-lightweight-interactive-models>
  - Needs StreamingEnabled, a cloud-saved place and Team Create.
  - Static only: "Adding or removing parts … at runtime prevents SLIM from rendering the model correctly."
  - Unions may misrender. Models with a Humanoid are excluded.
  - Dynamic SLIM is a future goal.
  - `Model.LevelOfDetail` has capability `PluginOrOpenCloud`, so it is probably not
    script-settable **[doc metadata; verify]**.

### 2. Streaming

- **Behaviour** **[doc]** <https://create.roblox.com/docs/workspace/streaming>
  - Anchored assemblies stream per part.
  - MinRadius (default 64) never streams out. TargetRadius (default 1024) is the maximum stream-in distance.
  - Streamed-out instances are parented to nil.
  - Client-created instances are exempt unless parented under server instances.
  - **Client physics only runs in streamed areas.**
  - Each extra replication focus costs about as much as another player.
  - `ModelStreamingMode` may be changed from server Scripts, "never in LocalScripts".
- **Fast movement** **[community]**: flight and racing reports of chunks loading too late and
  players falling through.
  <https://devforum.roblox.com/t/streaming-enabled-w-aircrafts/321769>
  - Mitigations: a large MinRadius, `AddReplicationFocus` on the dummy, and
    `RequestStreamAroundAsync`. It yields, so never inside the 0.04 s mask.
- **Duvall Drive** (Roblox showcase): default streaming, with pop-in hidden by level design
  (winding paths, tree lines, oversized sky models).
  <https://create.roblox.com/docs/resources/the-mystery-of-duvall-drive/stream-in-immersion>
- **Server Authority** **[staff]** (full release 2026-07-09, opt-in):
  - `AuthorityMode=Server` forces StreamingEnabled, NextGenerationReplication, Deferred
    signals, fixed simulation and InputActions.
  - Higher server CPU.
  - <https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993>
- **Pros for us:** client memory and join time, SLIM for static set pieces, and a path to
  Server Authority.
- **Cons for us:**
  - Zero server or Studio memory relief, which is the binding limit.
  - A 600 studs/s target outruns it.
  - Every `workspace.Buildings` scan must become tag/signal driven.

### 3. Memory and replication

- Server budget is **6.25 GiB + 100 MiB per player**. Most servers stay under about 1M
  instances. See `OPTIMIZATION_RESEARCH.md` §1.1.
- "Creating and destroying large instance hierarchies like maps at runtime can be very network
  intensive". Chunk them across frames. Keep VFX on the client and send only positions. Tween
  on the client **[doc, improve page]**.
- Physics replication was rebuilt in June 2026 (`ImprovedPhysicsReplication`) with
  "eventual consistency": parts come to rest in the same place on every client.
  <https://devforum.roblox.com/t/upcoming-improvements-to-physics-replication/4675512> **[staff]**
- MrChickenRocket's bandwidth budget: about 50 KB/s client receive, and **0.4-0.9 KB/s per
  moving physics assembly**, so about 40-60 moving assemblies **[staff-category guest article]**.
  Server-simulated debris is therefore expensive. Client-simulated, event-spawned debris is not.
- **Huge static city practice:** reuse a small mesh kit (one baked townhouse went from 12
  draw calls and 100 instances to 6 and 6). See §6 for the zone and culling patterns.
  EditableMesh is ruled out (earlier doc §1.6).

### 4. Physics

- **Sleep** **[doc]**:
  - Assemblies below 0.33 studs/s linear (0.42 rotational) sleep and are not simulated.
  - They wake on contact faster than 1 stud/s, or on Anchored, CanCollide or velocity writes.
  - <https://create.roblox.com/docs/physics/sleep-system>
- **Adaptive stepping** **[doc]**:
  - Solver islands run at 240, 120 and 60 Hz. Up to 2.5x faster than Fixed.
  - The docs suggest Fixed for "destruction" games. Keep Adaptive while live assemblies are few.
  - <https://create.roblox.com/docs/physics/adaptive-timestepping>
- **Network ownership** **[doc]**:
  - Anchored parts are always server-owned.
  - Unanchoring reverts ownership to automatic, so a nearby client can grab the dummy mid-flight.
  - Use `SetNetworkOwner(nil)` for a server-authored launch.
  - <https://create.roblox.com/docs/physics/network-ownership>
- **Collision** **[doc]**:
  - CanCollide, CanTouch and CanQuery are separate.
  - Collision geometry stays in memory regardless, which matches our 0.0 MB CanTouch result.
  - Box fidelity is cheapest; it applies to meshes and unions only.
  - One collision group per part, **32 groups max**.
  - <https://create.roblox.com/docs/workspace/collisions>
- **Humanoid** **[doc]**:
  - `EvaluateStateMachine` is "used to disable the internal physics and state machine".
  - The `Physics` state "doesn't apply any force … and will not automatically transition".
  - `Ragdoll` is deprecated. `FallingDown` auto-recovers through GettingUp.
  - `SetStateEnabled` "does not replicate".
  - `BreakJointsOnDeath` and `RequiresNeck` keep rigs intact.
  - Use an AnimationController for static NPCs.
  - <https://create.roblox.com/docs/reference/engine/classes/Humanoid.md>,
    <https://create.roblox.com/docs/reference/engine/enums/HumanoidStateType.md>
- **Custom ragdoll** **[community]**:
  - Attachments at each Motor6D's C0 and C1, plus a limited BallSocketConstraint.
  - `Motor6D.Enabled=false`; don't destroy motors.
  - Physics state with GettingUp disabled.
  - Toggle HumanoidRootPart.CanCollide.
  - Docs: "limit self-collision in ragdolls".
  - <https://devforum.roblox.com/t/how-do-i-remove-falling-down-and-ragdoll-humanoid-state-from-characters/866363>
- **Kinematic motion:**
  - Anchored CFrame, `PivotTo` or `workspace:BulkMoveTo` (batched).
  - Use Motor6D.Transform, not C0/C1, for procedural poses **[doc]**.
  - AlignPosition and AlignOrientation act only on unanchored, awake assemblies **[est]**.
  - The Character Controller Library (replacing "rigid Humanoid state machines") is still
    Beta. <https://create.roblox.com/docs/physics/character-controllers>

### 5. Spatial queries and CSG

- **New filters** **[staff]** (2026-04-07, Physics team):
  - `IncludeInstances` and `ExcludeInstances` give "log(n) lookups". Raycasts are "much faster
    … when you have a large filter list".
  - The speedup was back-ported to FilterDescendantsInstances.
  - Tag filters and batched raycasts are coming.
  - Building lists from `GetTagged`/`GetDescendants` remains the costly part.
  - <https://devforum.roblox.com/t/new-spatial-query-filters/4563575>
- **Query tips:**
  - Folder Include cost 0 ms against 52 ms for 866k explicit parts **[local, earlier doc §6]**.
  - `CanQuery=false` removes parts from queries. `RespectCanCollide` swaps the test to CanCollide.
  - `MaxParts` caps results. `BruteForceAllSlow` "should not be used in live experiences".
  - `params.CollisionGroup` filters queries too.
  - Bounds queries (`GetPartBoundsInBox`/`InRadius`) are a cheaper broad phase than exact
    `GetPartsInPart` **[est]**.
  - <https://create.roblox.com/docs/reference/engine/datatypes/OverlapParams.md>
- **CSG** **[staff]** (full release 2025-11-12):
  - Faster, fewer crashes, works in LocalScripts.
  - `CollisionFidelity.Default` is "significantly faster" than Precise.
  - Future work: replication bandwidth, MeshPart booleans, fracture and sweep.
  - <https://devforum.roblox.com/t/full-release-improved-constructive-solid-geometry-csg-apis/4065505>
  - The reference page now lists MeshPart inputs and `FragmentAsync` (Voronoi).
    <https://create.roblox.com/docs/reference/engine/classes/GeometryService.md>
  - Solid modeling needs watertight meshes, and our Shibuya scan meshes aren't
    (ProjectFiles 2026-09-18). They stay uncarvable either way **[est]**.

### 6. Patterns from large experiences

- **MrChickenRocket (2024-08-20, staff category)** **[staff-category]**:
  - per-zone budgets of 40k triangles and 40 draw calls
  - precomputed visibility, with client-side parent=nil for hidden zones
  - tagged small-detail distance culling, time-sliced
  - event-spawned client physics pickups that get **anchored once settled**
  - spatial-hash grids for proximity
  - client-computed pets that skip `PivotTo` when unchanged
  - BulkMoveTo for mass motion
  - <https://devforum.roblox.com/t/3127146>
- **Duvall Drive / Beyond the Dark (Roblox showcases)**:
  - Duvall Drive: default streaming with occluding set dressing.
  - Beyond the Dark was re-uploaded "optimized using SLIM", which fits because it is static.
  - <https://create.roblox.com/docs/resources/the-mystery-of-duvall-drive>
- **Jailbreak, Frontlines, Doors:** I found no first-party technical write-ups. Community
  threads on large city maps either use custom chunk or zone loaders (for control) or
  StreamingEnabled with ReplicationFocus.
  <https://devforum.roblox.com/t/how-to-optimize-a-huge-map/4159874>. Common claims about
  these games (Doors rooms generated ahead and deleted behind, Jailbreak custom LOD) are
  **unverified**.

---

## (c) Roblox-native levers

| Lever | What it does | Cost | When to use | Gotchas (destruction / fast movement) |
|---|---|---|---|---|
| Native occlusion and frustum culling | Skips draws of hidden parts and meshes | Free | Always (on by default) | No memory or CPU saving per instance. Glass and transparency probably don't occlude. No script API. |
| Asset reuse (one MeshId or shape, varied colour) | Instanced draws | Authoring | Facade kits, debris | Unique unions and CSG results never instance. Transparency and decals or textures add draw calls. |
| `CastShadow=false` | Removes the part from the shadow pass | 1 property | Trim, glass, small, moving, debris | Visual artifacts. FPS only, no memory gain. |
| Opaque materials over Glass/Transparency | Avoids overdraw and extra draws | Look | Far facades | Glass refraction hides non-opaque objects behind it. |
| Anchored by default | No simulation, server-owned | None | Everything static, plus debris after settling | Unanchoring hands ownership back to automatic. Call `SetNetworkOwner(nil)` for the dummy. |
| Sleep system | Resting assemblies cost nothing | Automatic | Debris piles | Woken by any >1 stud/s contact or property write. Anchor settled debris. |
| `Humanoid.EvaluateStateMachine=false` | Removes Humanoid physics and states entirely | 1 property | Dummy in flight, ragdoll, scripted poses | You own everything, including standing up again. Re-enable before recovery. Test replication to clients. |
| `SetStateEnabled` (FallingDown, Ragdoll, GettingUp, Climbing…) | Stops auto-tripping | Per Humanoid | Players at WalkSpeed 128+ | Doesn't replicate: call it on the owner (client for players). Ragdoll is deprecated. |
| BallSocket ragdoll on demand | Real limbs only during the hit | ~15 constraints per hit | Hit to recovery | Disable Motor6Ds; don't destroy them. Limit self-collision. Watch the 240 Hz island at high speed. |
| Anchored CFrame/`BulkMoveTo` | Kinematic motion with no solver | Cheap | Scripted flight, client cosmetic motion | Server CFrame writes replicate. Do the flight visuals on the client where possible. |
| `CanQuery/CanTouch=false` | Removes parts from queries and touch | Free | All facades and decoration | Hit code must then find facades from data, not queries. No memory saving. |
| CollisionFidelity Box/Hull | Cheaper collision memory and compute | Free | CSG fragments, debris unions | Meshes and unions only. Box on concave carved slabs is wrong. |
| Collision groups | Pairwise collide matrix, also filters queries | 32 groups max | Debris vs players, dummy vs facades | One group per part. |
| `IncludeInstances` on folders | log(n) filtered queries | Free | Every hit query | Never rebuild filter lists from GetDescendants. |
| `GetPartBoundsInBox` → `GetPartsInPart` | Cheap broad phase, then exact narrow phase | Low | Hit volume | Keep MaxParts in mind. |
| GeometryService CSG (server or client) | Carving, fracture, sweep | ms to s per op, plus mesh replication | Structural slabs only | Results don't instance and don't stay SLIM. Use Default, not Precise. Run client-only CSG for cosmetic damage. |
| StreamingEnabled plus foci | Client memory and join time | Big refactor | If client RAM becomes the limit, or for Server Authority | Does nothing for server or Studio memory. Outruns 600 studs/s. Client scripts must use tag signals. |
| SLIM `LevelOfDetail` | Composite far LOD | Edit-time setting | Only never-destroyed set pieces | Breaks on runtime part add or remove. Likely not script-settable. |
| Server Authority | Server-authoritative prediction and rollback | Higher server CPU, forced streaming | PvP fairness, later | Opt-in. Forces Deferred signals and streaming. |

---

## (d) Don't fight / Must do yourself

**What Roblox already does for you (don't fight it):**

- **Per-frame visibility.** Occlusion and frustum culling are on. Tearing down and rebuilding
  facades as the camera moves duplicates the engine and adds instance churn and hitches.
  Instead, keep each built building with wide hysteresis (build at R, drop at about 1.5R),
  rebuild only when damage changes it, and let the engine skip what the streets hide.
- **Resting physics is free.** Sleeping assemblies and anchored parts are not simulated.
- **Replication consistency.** Since June 2026, resting parts converge on every client.
- **Query acceleration.** Queries are broad-phased internally and filters are log(n). Pass a folder.
- **Mesh fallback.** `RenderFidelity` Automatic handles distance detail for meshes.

**What you must do yourself:**

- **Memory.** Keep decorative geometry out of the saved place (client recipes); streaming and
  culling don't help server or Studio memory. Remove whole-map `GetDescendants` and
  filter-building from hits.
- **Distance LOD for parts.** Parts and unions get no automatic LOD (SLIM is static only). Use
  far proxies, banded textures and tagged detail culling, time-sliced.
- **Batching discipline.** A small kit of shared meshes and shapes, little Glass or
  transparency beyond the near radius, and no per-pane Decals.
- **The "physics on at the right moment" switch.** Anchored or asleep by default. On a hit:
  `EvaluateStateMachine=false`, then BallSockets on and Motor6Ds off, then
  `SetNetworkOwner(nil)`, then apply velocity. Reverse these steps on recovery.
- **Debris lifecycle.** Spawn on clients from events, or keep server debris counts small. Use
  Box fidelity and a CollisionGroup, anchor pieces once asleep, then pool them with a lifetime.
- **Streaming-proofing, if streaming is ever enabled.** Make code tag/signal driven, put a
  focus on the dummy before launch (no yielding call inside the mask delay), and hide pop-in
  with level design.
- **CSG hygiene.** Carve only primitive structural parts and delete NoCSG parts. Consider
  client-only cosmetic carving backed by server-side logical damage.

**Verify in engine:** which parts act as occluders (Glass, thin, transparent); draw-call
batching of primitive Parts (performance overlay); `EvaluateStateMachine` replication to
clients; GeometryService on MeshParts today; whether LevelOfDetail is script-writable.
