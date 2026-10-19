# R3: What destruction costs on the network (2026-10-19)

Research only. No game code, Studio state or commits were changed.

Tags: **[doc]** Creator Hub; **[staff]** post by Roblox staff; **[community]** DevForum, GitHub or wiki; **[est]** my own inference, to be measured.

Context: streaming is off, so every client receives every replicated change on the map. The per-client receive budget is about **30–50 KB/s** ([R2_CHARACTER_NETCODE.md](R2_CHARACTER_NETCODE.md)), and characters, bots and timelines already use about **26–34 KB/s** of it. Destruction therefore has roughly **5–20 KB/s average per client** to spend, with short bursts allowed.

---

## Summary

1. **A server CSG result is mesh data sent inline to every client.** It is not an uploaded asset and is not recomputed on the client.
   - A typical carved part probably costs **about 6–25 KB per client** [est].
   - One physical hit that carves 20 slabs and walls is therefore **about 120–500 KB to every client**. That is 3–10 seconds of the whole budget.
   - Roblox shipped "delta" CSG replication in April 2026 and then switched it off two weeks later. Its current status is unknown.
2. **New primitive Parts are cheap but not free:** probably **about 150–350 bytes each** [est]. A destroy is probably about **5–10 bytes** [est]. An anchored CFrame write is probably **about 20–35 bytes per part per change** [est].
3. **Client-side GeometryService works,** with two limits [staff]:
   - it can only operate on primitives or on unions the client made itself;
   - nothing it makes replicates.

   Nobody has promised that it gives identical results on different machines. Use it only for looks.
4. **Destruction games keep network cost down by sending events, not geometry:**
   - Shatterbox and voxel systems run the same destruction on server and clients;
   - JJS keeps server debris inside a container that does not replicate and streams compact CFrames;
   - battlegrounds rock and crater modules are client-only;
   - maps are reset on a timer or on request.
5. **Recommendation: a "deterministic mirror".**
   - The server sends one small event of about 200–500 bytes.
   - The server and every client run the same analytic code on primitive parts to get the collision pieces.
   - Clients optionally carve cosmetic CSG near the camera.
   - Estimated cost: **about 1 KB per hit, 1 KB per beam and 3–5 KB per slice**. Five busy fights come to **about 3–5 KB/s per client**, against about 400–1,700 KB/s for naive server CSG.
   - Section 5 has an 8-test measurement plan for approval.

---

## 1. How a server CSG result replicates

### What is sent

- **The geometry travels inline over the network as data properties.**
  - A `PartOperation` stores its render mesh in `MeshData` and its collision in `PhysicsData`. Both are binary blobs: `CSGMDL` versions 2, 4 and 5 for render, and `CSGPHS` versions 3 to 8 for physics ([rbx_mesh](https://github.com/krakow10/rbx_mesh), [Research on CSG](https://devforum.roblox.com/t/research-on-csg/3554504)) [community].
  - Unions made in Studio point at an uploaded asset through `AssetId` (`PartOperationAsset`, "used to save/load solid models onto the Roblox cloud"). The rbx_mesh README notes that the mesh "is sourced from the associated AssetId" in saved files ([PartOperationAsset](https://developer.roblox.com/api-reference/class/PartOperationAsset)) [doc][community].
  - A runtime `GeometryService` result has no uploaded asset, so its data must ride in the replication stream [est, strongly implied].
- **The wire format, as decoded from the protocol** ([roblox-dissector source](https://github.com/Arisstath/roblox-dissector), `peer/BitstreamPropertyTypes.go` and `ExtendedReader.go`) [community]:
  - A SharedString property is sent as a **16-byte MD5 hash**.
  - Its full content follows in the same packet the first time a client sees that hash, and is cached by hash afterwards.
  - So identical meshes are deduplicated per connection. Every unique carve result is sent in full to every client.
  - Caveat: the dissector dates from about 2019–2021, so the current protocol may differ.
- **Clients do not recompute the geometry.** Staff say client CSG "can't do a CSG Operation on server and continue it on client" ([2024 beta thread, p.2](https://devforum.roblox.com/t/in-experience-constructive-solid-geometry-csg-apis-now-available-in-published-experiences-beta/2944380?page=2)) [staff].
  - The April 2026 delta system has clients apply server-made changes to their existing mesh ([announcement](https://devforum.roblox.com/t/blisteringly-fast-solid-modeling-csg-replication-with-delta-updates/4554628)) [staff].

### How big it is

- **Per vertex and per triangle.** The current render format, CSGMDL5, stores for each vertex ([v5.rs](https://github.com/krakow10/rbx_mesh/blob/master/src/union_graphics/v5.rs)) [community]:
  - position: 12 bytes
  - quantized normal: 6 bytes
  - colour: 4 bytes
  - face ID: 1 byte
  - UV: 8 bytes
  - quantized tangent: 6 bytes

  That totals **about 37 bytes per vertex**. Triangle indices are delta-encoded at **about 3–9 bytes per triangle**.
  - Physics data (CSGPHS v8) is compressed with Edgebreaker plus convex hulls.
- **Real sample files** in the rbx_mesh test set [community]:
  - Union render meshes: 4.3, 5.4, 6.0, 8.7, 44, 49 and 72 KB.
  - Physics blobs: 1.3–25.5 KB.
- **Estimate for our carves.** A slab or wall carved by our 50-stud cylinder gives roughly 100–400 vertices. That is about **4–15 KB render plus 2–10 KB physics**, so **about 6–25 KB per carved part** [est].
  - Any extra data, such as the operand history in `ChildData`, would add to this.
  - Staff have said they are "working on serving only a render-optimized mesh in-experience" so that PartOperations carry no extra cost. That implies more than the render mesh is sent today ([full-release thread](https://devforum.roblox.com/t/full-release-improved-constructive-solid-geometry-csg-apis/4065505)) [staff].
  - A developer in the same thread says replication time in their game is "dominated" by CSG models [community].
- **Clients must also receive collision data.** Each client simulates its own character against the world, so the physics data cannot simply be dropped [est].

### Delta updates

- **Announced on 2026-04-02:** only the changes after each operation are sent. It was on by default for GeometryService and promised for the BasePart APIs "over the next few weeks" [staff].
  - Charts showed large drops in the p99 time for new PartOperations to reach clients on a simulated 400 kbps link, but the post gave no figures.
  - CSG data uses **a separate replication pipe**, so large updates "shouldn't stall gameplay" [staff].
- **Switched off on 2026-04-16** ("we are seeing some issues with this feature… temporarily turned off") [staff]. I found no re-enable notice.
  - A second-hand article claims "up to 90%" savings ([creation.dev](https://www.creation.dev/learn/roblox-csg-solid-modeling-delta-updates-performance)) [community, unverified].
- **Even when on, deltas only help the second and later cuts of the same part** [est]. Our hits mostly carve fresh parts.

### Delay and pop

- **A short window is likely in which the old part is gone but the new mesh has not arrived** [est]. Two things point to it:
  - the separate CSG pipe;
  - the history of "union invisible on one client" bugs. Delaying parenting "gives the client time to download the rendered mesh" ([2021 thread](https://devforum.roblox.com/t/unions-rendering-strangely-csg-api/1010347); [2020 bug](https://devforum.roblox.com/t/in-game-csg-unreliable-excessive-waiting-times/614909)) [community].
- **Related reports:**
  - In 2024, flicker fixes were rolled back because of "asset-loading failures" [staff].
  - In-game CSG felt slower than in Studio, and staff said it "looks… like there is some replication delay" ([2024 thread, p.3](https://devforum.roblox.com/t/in-experience-constructive-solid-geometry-csg-apis-now-available-in-published-experiences-beta/2944380?page=3)) [staff].
- **Docs:** they warn against "a large series of calls… in quick succession" and cap results at 20,000 triangles ([Solid modeling](https://create.roblox.com/docs/parts/solid-modeling)) [doc].

---

## 2. What primitive Parts cost on the network

**No official per-Part byte figures exist.** The best evidence is the protocol layout plus community measurements.

- **Creating a Part** sends one "new instance" item with these fields ([dissector](https://github.com/Arisstath/roblox-dissector/wiki/Packet-types)) [community]:
  - network ID;
  - class index (2 bytes);
  - one byte per property index, plus the value;
  - parent reference.
- **Estimated Part size.** A Part has about 40–60 replicated properties. Typical value sizes are a CFrame at 14–20 bytes, a Vector3 at about 13, an enum at 2–4 and a bool at 2 ([ffrostfall's size table](https://devforum.roblox.com/t/in-depth-information-about-robloxs-remoteevents-instance-replication-and-physics-replication-w-sources/1847340)) [community].
  - Estimate: **about 150–350 bytes per new Part** [est]. Attributes and tags add their names and values.
- **Set properties before parenting.** Every change after parenting is a separate property item. A deprecated `Instance.new` argument was dropped "for this very reason" [community].
  - Today's `safeSubtractAsync` already does this correctly.
- **Destroy:** one delete item with a reference, so **about 5–10 bytes** [est].
  - Destroying a Folder probably removes its whole subtree in one message [est, to measure]. If so, a whole level can be deleted cheaply.
- **Anchored CFrame writes on the server:** each changed part replicates its latest value, so **about 20–35 bytes per part per change** [est].
  - BulkMoveTo makes the moves cheaper on the CPU, but the docs say nothing about network savings ([WorldRoot](https://create.roblox.com/docs/en-us/reference/engine/classes/WorldRoot.md)) [doc].
  - Moving 600 upper-half parts at 60 Hz on the server would cost about 1 MB/s. **Large-scale motion must stay client-side.**
  - The docs also warn that a server-side tween "is replicated to each client every frame" ([Improve performance](https://create.roblox.com/docs/performance-optimization/improve)) [doc].
- **Measured system totals from others** [community]:
  - stock Humanoid NPCs: about 4 KB/s for 5, 17 KB/s for 25 and 40 KB/s for 75 ([Downrest, 2025-12](https://devforum.roblox.com/t/performance-tips-network-bandwidth-client-framerate-etc-for-custom-npc-replication/4202236));
  - "2,000 parts with 10 kB/s" when using buffer remotes.
- **The docs' own warning:** "creating and destroying large instance hierarchies… can be very network intensive" [doc].
- **Physics replication is being replaced.** It is moving to "Instance State Replication" (ISR, rolling out from June 2026), and the old physics network stats "will drop to 0 KB/s" ([Khanovich](https://devforum.roblox.com/t/upcoming-improvements-to-physics-replication/4675512)) [staff]. Read the ISR stats too when measuring.

---

## 3. Client-side CSG as a cosmetic layer

- **It works in LocalScripts** ("already works in LocalScripts") [staff], with two caveats [staff, quoted in [Oct 2024 post](https://devforum.roblox.com/t/improved-performance-for-geometryservice-csg-apis/3217048)]:
  - "They can only be called on primitives or on PartOperations that were created on client";
  - "No replication back to server or other clients".

  The docs agree ([Solid modeling](https://create.roblox.com/docs/parts/solid-modeling)) [doc].
- **So the server must never turn structure into unions** if clients are to carve it. Server parts must stay primitives, and each client carves its own local copies.
- **The server overwrites client edits.** Staff confirmed that a client-side hole "disappearing is actually expected behavior", because the server "is not aware" of it and overwrites the object ([2025 bug thread](https://devforum.roblox.com/t/csg-collisions-not-updating-on-client-in-experience-and-csg-operations-being-slower-in-experience/3953352)) [staff].
  - The same thread shows client collision holes appearing inconsistently, which staff call a known bug.
  - Fix: cosmetic results use `CanCollide=false` and `CanQuery=false`, and never stand in for collision.
- **Cost:**
  - Our server-side Studio test measured 3–11 ms per small cut, with 65 ms for the first call ([R2_ENGINE_TESTS.md](R2_ENGINE_TESTS.md)) [local test].
  - Staff say the calls run asynchronously.
  - Laptop clients are probably 1.5–3× slower [est]. Cap at 4 cuts in flight and only carve within about 300 studs of the camera [est].
- **Determinism:**
  - **I found no statement that the same subtract gives identical triangles on two machines.**
  - `GenerateFragmentSites` is documented as "partially random" ([GeometryService](https://create.roblox.com/docs/en-us/reference/engine/classes/GeometryService.md)) [doc].
  - Treat client CSG as non-deterministic. Small visual differences between clients are fine; collision differences are not.
- **Who does this:** the same pattern appears in the community.
  - The Shatterbox author: the server sends only the original parts, then "Client performs the same destruction… this ensures the server and each client remain in sync" ([thread](https://devforum.roblox.com/t/voxel-destruction-help-me-optimise-network-usage/4047764)) [community].
  - Another developer moved destruction to clients plus a seed and reported "network usage is unaffected by the destruction now" [community].
  - I found no shipped Roblox game that documents client CSG over server collision.

---

## 4. How Roblox destruction games keep network cost down

- **Jujutsu Shenanigans (JJS)** [community]:
  - Debris is server-simulated but parented to the server's `workspace.CurrentCamera`, which "doesn't replicate to the client".
  - The server sends CFrames at about 20 Hz, and clients tween anchored copies. A "Destruction Interpolation" setting turns this smoothing off ([Shatterbox thread p.5](https://devforum.roblox.com/t/shatterbox-client-server-voxel-destruction-simple-and-optimized-release-77/3674163?page=5)).
  - Private servers have "Destruction" and "Destruction Respawns" toggles, so destroyed blocks respawn by default ([JJS wiki](https://jujutsu-shenanigans.fandom.com/wiki/Private_Servers)).
- **Shatterbox** (Release 8, Feb 2026) [community]:
  - Clients "copy the map before the server breaks it", then run the same destruction.
  - Server results are not replicated, and late joiners get "fresh parts".
  - `Reset` restores everything.
  - It uses Blink buffer networking and is limited to static maps ([release thread](https://devforum.roblox.com/t/shatterbox-client-server-voxel-destruction-simple-and-optimized-release-8/3674163)).
- **VoxelDestruct 2.1** [community]:
  - An `OnClient` mode offloads destruction to clients.
  - `RecordDestruction` replays the history for late joiners.
  - A part cache avoids the cost of creating instances ([thread](https://devforum.roblox.com/t/voxeldestruct-21-voxelated-destruction-physics-with-greedy-meshing-hitboxes-and-more/3044264)).
  - VoxBreaker is open source and octree-based ([GitHub](https://github.com/Bartokens/VoxBreaker)).
- **Battlegrounds rock and crater modules (TSB-style)** [community]: client-only. Authors write "this is normal and please use it on the client", and to fire a RemoteEvent if everyone should see it ([Rock Module](https://devforum.roblox.com/t/rock-module-v10-craters-explosions-and-more-effects/3041562), [TSB punch rocks](https://devforum.roblox.com/t/punch-rock-module-inspired-by-tsb/3171422)).
- **Demolition sims** reset buildings on a timer ("regenerates every 5 minutes") or with regen buttons, to limit lag [community, game descriptions].
- **Outside Roblox:**
  - *The Finals* replicates server destruction of pre-fractured buildings (GDC 2024).
  - Red Faction moved from runtime CSG to pre-broken pieces ([R2_SLICE_COLLAPSE_CSG.md](R2_SLICE_COLLAPSE_CSG.md)) [ext].

**The common pattern:** send *what happened* (shape, position, seed, time), not *the result*. Keep authority on the server. Rebuild results on each client. Reset the map regularly so state and late-join history stay small.

---

## 5. Recommended scheme and budget

### The scheme: "deterministic mirror"

1. **The server never runs CSG on replicated structure.** Every building part stays a primitive (`Part` or `WedgePart`).
2. **Every destruction becomes one reliable event** of about 200–500 bytes, packed in a buffer. It contains:
   - `seq`, `buildingId` and the building's generation;
   - the cutter shape: a capsule, sphere or plane, quantized to 1/64 stud;
   - `tBreak`, the seed and a debris cap.

   Parts are named by the stable per-building index (`PartRow.idx`, see R2_SLICE).
3. **The server and every client run the same analytic Luau code.**
   - Part fully inside the cutter: delete it.
   - Part partly cut: replace it with primitive pieces. For a hole, a slab or wall becomes an octagon frame of 8 primitives. A plane cut becomes prism pieces.
   - Use only `+ - * /` and `sqrt`. These are correctly rounded in IEEE-754, so results match across machines [est; test M8]. No trig at run time.
4. **Server pieces live in a container that does not replicate** (the server's Camera, as JJS and Shatterbox do).
   - They still give the server collision for bots, spherecasts and victim paths.
   - The server `Destroy()`s each original, at about 10 bytes per part.
   - Clients build identical pieces locally at `tBreak` and hide the originals before the server's destroy arrives.
5. **Clients add the cosmetic layer.** Within about 300 studs of the camera, they:
   - optionally run client CSG on local copies for round edges (no collision);
   - spawn seeded debris and dust.

   Far clients apply only the analytic pieces, time-sliced over about 1 s.
6. **Late joiners and recovery.**
   - The server keeps an event log per building, about 15 KB at most for 50 events. New clients replay it.
   - Clients report a per-building hash of the pieces now and then. On a mismatch, the server resends that building's log.
   - **A map reset loop** caps log size and damage, for example rebuilding any building idle for N minutes behind dust.
7. **Fallback** (if M8 shows that determinism fails): send that event's pieces as replicated primitives, 150–350 bytes each.
8. **Facades:** the split-skin swap from R2_FACADE section 6, not server CSG on pane holes.

### Budget per client

Assumptions [est]:
- A physical hit carves 20 parts and deletes 30 decoration parts.
- A beam splits 30 parts and deletes 60.
- A slice cuts 120 parts into about 400 lower pieces and later deletes about 500.
- Each fight produces 0.5 building hits per second, one beam every 15 s and one slice every 45 s.

| Event | A: server CSG (today's direction) | B: replicated analytic primitives | **C: deterministic mirror** |
|---|---|---|---|
| Physical hit | 120–500 KB | 25–50 KB | **≈1 KB** |
| Beam | 180–750 KB | 40–75 KB | **≈1 KB** |
| Sukuna slice | (not CSG) | 60–140 KB | **≈3–5 KB** (mostly destroys) |
| One fight, average | 70–280 KB/s | 15–30 KB/s | **≈0.7 KB/s** |
| **5 fights, average** | **350–1,400 KB/s** | **75–150 KB/s** | **≈3–5 KB/s** |
| Fits a 5–20 KB/s share? | No, by 20–100× | No, about 5× over | **Yes** |

Notes on the table:
- Burst limits:
  - Option B's slice burst of 60–140 KB would take 1–3 s to drain at the budget, and every client feels it, near or far.
  - Option A has the same problem on every hit.
- Option C's remaining cost is mostly `Destroy()` messages. If test M4 shows that a destroy message covers its whole subtree, group pieces per level in Folders.

### Measurement plan (for owner approval)

**Setup.**
- Use a throwaway copy of the place, with the test rig far above the map.
- Run Studio "Start Server + 2 Clients". This is local loopback, so there is no bandwidth cap and the byte counts are clean.
- Repeat key tests on a published private server with two real clients, for delivery time.

**Probe script (client).**
- Each Heartbeat, add `Stats.DataReceiveKbps × dt` and `PhysicsReceiveKbps × dt`. Units are approximate KB/s, and the two must be summed to match the Shift+F3 "Recv" figure ([thread](https://devforum.roblox.com/t/statsdatareceivekbps-is-reporting-lower-values-than-in-game-performance-stats/443815)).
- Subtract a 30-second idle baseline. Divide by N.
- On the server, also log `Stats.DataSendKbps ÷ clients`.
- Read the new ISR stats in Shift+F3.
- Record the MicroProfiler scopes `Replicator/ProcessPackets` (client) and `Allocate Bandwidth and Run Senders` (server).
- Every test runs 3 times, and we report the median.

| # | Test | Output |
|---|---|---|
| M1 | Server creates 1,000 slab-like Parts (properties set, then parented) in one frame, then in batches of 50 | bytes per Part; burst duration |
| M2 | The same 1,000 Parts with Color changed after parenting; with 1 / 5 attributes; with tags | bytes per property change and per attribute |
| M3 | Anchored CFrame on 600 parts: one write each; then server `BulkMoveTo` at 60 Hz for 5 s | bytes per part per update |
| M4 | Destroy 1,000 loose Parts, compared with 1 Folder holding 1,000 | bytes per destroy; is a subtree one message? |
| M5 | Server `GeometryService:SubtractAsync` using today's 50-stud cylinder on 20 different slabs and walls (log `TriangleCount`); then re-carve one part 5 times | **bytes per carve compared with triangles; whether delta updates are on** (2nd+ carve much smaller); delay between server parent and client `ChildAdded` (timestamp attribute vs `GetServerTimeNow`) |
| M6 | A textured skin with 12 pane holes, each a separate carve, compared with one batched carve | bytes per pane hole |
| M7 | Client CSG on local primitive copies, same cuts as M5, on the laptop | ms per op; frame-time spikes; `TriangleCount`/`Size`/`Mass` fingerprints compared between two clients (determinism hint) |
| M8 | Analytic hole and slice code run on the server and on two clients (Windows PC, plus a Mac or phone if available) | per-building hash of the `%.6f` CFrames and Sizes; must match exactly |
| M9 | Scenario: 5 bot fights for 5 minutes, scheme B compared with scheme C | per-client receive p50 / p95 / max, ping, `ProcessPackets` ms |

**Pass lines:**
- Destruction share **at or below 20 KB/s p95** per client with 5 fights.
- Total receive **at or below 50 KB/s** on average, and never above 150 KB/s for more than 2 s.
- M8 hashes identical on 100% of 1,000 random cuts.

Estimated time: about one day of scripting and running, using throwaway probes only.

---

## Open risks

- The byte sizes here are estimates from protocol layout. M1–M6 replace them with measurements.
- Delta CSG replication may be switched back on, which would lower option A's cost for repeated carves only.
- The server Camera trick for unreplicated parts is community practice, not documented behaviour. Check that bots and spherecasts collide with Camera children on the server, as part of M8.
- Deterministic replay needs strict event order: one reliable remote with `seq`, and buffering on any gap.

---

## Sources

**Roblox official [doc] and staff [staff]**
- Blisteringly fast Solid Modeling (CSG) Replication with Delta Updates (2026-04-02, disabled 04-16): https://devforum.roblox.com/t/blisteringly-fast-solid-modeling-csg-replication-with-delta-updates/4554628 , page 2: `?page=2`
- Full release: improved CSG APIs (2025-11-12, "render-optimized mesh", LocalScripts): https://devforum.roblox.com/t/full-release-improved-constructive-solid-geometry-csg-apis/4065505
- In-experience CSG beta (2024-04-24, pages 1–4): https://devforum.roblox.com/t/in-experience-constructive-solid-geometry-csg-apis-now-available-in-published-experiences-beta/2944380
- Improved performance for GeometryService CSG APIs (2024-10-16, client caveats): https://devforum.roblox.com/t/improved-performance-for-geometryservice-csg-apis/3217048
- CSG collisions not updating on client (2025-09/10, staff replies): https://devforum.roblox.com/t/csg-collisions-not-updating-on-client-in-experience-and-csg-operations-being-slower-in-experience/3953352
- Upcoming Improvements to Physics Replication / ISR (2026-06/07): https://devforum.roblox.com/t/upcoming-improvements-to-physics-replication/4675512
- Solid modeling: https://create.roblox.com/docs/parts/solid-modeling
- GeometryService: https://create.roblox.com/docs/en-us/reference/engine/classes/GeometryService.md
- PartOperationAsset: https://developer.roblox.com/api-reference/class/PartOperationAsset
- Stats (DataReceiveKbps and related): https://create.roblox.com/docs/en-us/reference/engine/classes/Stats.md
- WorldRoot (BulkMoveTo): https://create.roblox.com/docs/en-us/reference/engine/classes/WorldRoot.md
- Improve performance (networking): https://create.roblox.com/docs/performance-optimization/improve

**Community [community]**
- rbx_mesh (CSGMDL and CSGPHS formats, sample sizes): https://github.com/krakow10/rbx_mesh
- Research on CSG (CSGv2/v3, obfuscation): https://devforum.roblox.com/t/research-on-csg/3554504
- roblox-dissector (packet types, SharedString, instance serialization): https://github.com/Arisstath/roblox-dissector , https://github.com/Arisstath/roblox-dissector/wiki/Packet-types
- In-depth RemoteEvents and replication (ffrostfall, 2022–23): https://devforum.roblox.com/t/in-depth-information-about-robloxs-remoteevents-instance-replication-and-physics-replication-w-sources/1847340
- Network Optimization 2019/2020 (Hexcede): https://devforum.roblox.com/t/network-optimization-2019-2020-preventing-high-latency-reducing-lag/475052
- Custom NPC replication performance tips (2025-12): https://devforum.roblox.com/t/performance-tips-network-bandwidth-client-framerate-etc-for-custom-npc-replication/4202236
- DataReceiveKbps vs the Performance Stats UI: https://devforum.roblox.com/t/statsdatareceivekbps-is-reporting-lower-values-than-in-game-performance-stats/443815
- Unions rendering strangely (2021): https://devforum.roblox.com/t/unions-rendering-strangely-csg-api/1010347
- In-game CSG unreliable (2020): https://devforum.roblox.com/t/in-game-csg-unreliable-excessive-waiting-times/614909
- Voxel destruction network usage (Shatterbox author's algorithm): https://devforum.roblox.com/t/voxel-destruction-help-me-optimise-network-usage/4047764
- Shatterbox Release 8: https://devforum.roblox.com/t/shatterbox-client-server-voxel-destruction-simple-and-optimized-release-8/3674163 ; JJS debris discussion, page 5: https://devforum.roblox.com/t/shatterbox-client-server-voxel-destruction-simple-and-optimized-release-77/3674163?page=5 ; GitHub: https://github.com/azavier-a/Shatterbox
- VoxelDestruct 2.1: https://devforum.roblox.com/t/voxeldestruct-21-voxelated-destruction-physics-with-greedy-meshing-hitboxes-and-more/3044264
- VoxBreaker: https://github.com/Bartokens/VoxBreaker
- Rock Module V1.0: https://devforum.roblox.com/t/rock-module-v10-craters-explosions-and-more-effects/3041562 ; TSB-style punch rocks: https://devforum.roblox.com/t/punch-rock-module-inspired-by-tsb/3171422
- JJS private server settings (wiki): https://jujutsu-shenanigans.fandom.com/wiki/Private_Servers
- creation.dev delta-update summary (second-hand): https://www.creation.dev/learn/roblox-csg-solid-modeling-delta-updates-performance

**Internal**
- `R2_CHARACTER_NETCODE.md`, `R2_SLICE_COLLAPSE_CSG.md`, `R2_FACADE_BAKING_PIPELINE.md`, `R2_ENGINE_TESTS.md`, `R2_LOAD_TEST_PROFILING.md`, `GAME_DESIGN_DECISIONS.md`
