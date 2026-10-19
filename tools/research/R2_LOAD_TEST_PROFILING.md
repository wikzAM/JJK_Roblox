# R2: load testing and profiling methodology (2026-10-19)

Research only. No code, place or Studio changes. Builds on `GAME_DESIGN_DECISIONS.md`,
`ROBLOX_ENGINE_SCOPING.md` and `tools/OPTIMIZATION_RESEARCH.md`.

Tags: **[doc]** Creator Hub, **[staff]** Roblox staff DevForum post, **[community]** non-staff,
**[est]** my inference, to verify in engine.

---

## 1. Executive summary

1. **Measure counts, not just times.** Draw calls, triangles, instance count, memory in MB and
   network KB/s are the same on any hardware. Frame times are not. All of these are now readable
   from scripts (`Stats.SceneDrawcallCount`, `RenderGPUFrameTime`, `FrameTime`,
   `GetTotalMemoryUsageMb`, `DataReceiveKbps`, `HeartbeatTime`). A harness can log them every
   second on the server and on every client without anyone opening a profiler.
2. **The Studio local server cannot load-test this place.** Studio allows at most 8 clients,
   each one a full Studio process. ProjectFiles records about 20.7 GB of Studio commit for one
   fresh load on this 16 GB machine, so even two clients would run out of memory. Load tests must
   run on **live private servers of a separate test place**.
3. **Bots stand in for player load only on the server.** Server-driven bot characters
   reproduce CPU, physics, CSG and the replication each real client receives. They do not
   reproduce per-player memory, client→server input traffic or per-client send cost. So: run
   20+ bots plus every real client available (1–3), then extrapolate per-client send cost.
   Schedule one real 20-player session per major milestone.
4. **This dev box cannot become an iGPU laptop.** It has an RX 7700 XT (roughly 17–20× the
   FP32 throughput of an Iris Xe), an i5-12600KF with no iGPU, and 16 GB. Use **count budgets**
   plus a "low-proxy" config (forced low quality, 60 FPS cap, limited CPU). Before launch, buy or
   borrow one real Iris Xe / 8 GB laptop as the final gate.
5. **Headline budgets:**
   - **Server:** heartbeat ≥ 55 Hz at p95 under combat; memory ≤ 3 GB (Roblox guidance); no
     frame over 100 ms in destruction bursts.
   - **Client receive:** ≤ 50 KB/s average.
   - **Low tier:** ≤ 500 draw calls, ≤ 500k triangles, ≤ 1.5 GB client memory.
   - **Hit-to-launch:** ≤ 150 ms.
6. **Automate it.** A `PerfMode` flag runs a seeded scenario playlist in a private server and
   writes results to a DataStore. A Python script pulls them through Open Cloud and diffs them
   against budgets and the last milestone. An Open Cloud Luau Execution task is a headless smoke
   gate on every publish.

---

## 2. Findings with sources

### 2.1 Profiling tools (state in Oct 2026)

**MicroProfiler** **[doc]** <https://create.roblox.com/docs/studio/microprofiler>
- **Client:** Ctrl+F6; Ctrl+P pauses on a spike. The Dump menu writes
  `microprofile-<date>-<time>.html` to `%LOCALAPPDATA%\Roblox\logs`.
- **Server:** in a live game you can edit, open the Developer Console (F9) and go to
  MicroProfiler → Server. Set frames (**max 60**) and a start delay (max 4 s), then "Begin
  server recording". The dump goes to the same folder.
- **Custom labels:** wrap code in `debug.profilebegin("Name")`/`debug.profileend()`. Do this
  around `destroyAlongCylinder`, timeline dispatch, debris spawn and bot ticks.
- **Comparing and memory** **[staff, 2024-10-24]**
  <https://devforum.roblox.com/t/3226801>:
  - X-Ray memory mode (X key; C shows bytes).
  - CPU and memory flame graphs under Export.
  - Diff two dumps: drag the second HTML into the first, then click "Combine & Compare".
    Values are per-frame averages, so milestone dumps of different lengths are comparable.
- **LibMP** **[staff]** <https://devforum.roblox.com/t/4703136>:
  - A Luau MicroProfiler API (Studio beta June 2026). Its October 2026 update says it is
    "enabled in all live games, with no opt-in required".
  - It can capture snapshots on clients and servers, send server snapshots out via HttpService,
    and analyse them offline with Lute.
  - `SetMemTargetMB()` bounds its overhead.
  - Use: automatic server snapshot when a budget is breached.
- **Tags to read** **[doc]**
  <https://create.roblox.com/docs/performance-optimization/microprofiler/tag-table>:

| Area | Tags | Meaning for us |
|---|---|---|
| Physics | `Simulation/physicsStepped`, `worldStep/stepContacts`, `stepWorldThrottled`, `assemble`, `SpatialFilter/filterStep`, `handleFallenParts` | Debris contacts, ragdoll joint churn, ownership flips. `Throttled` means overload |
| Render (client) | `Prepare/updateInstancedClusters`, `updateInvalidatedFastClusters`, `Perform/Scene/Shadows`, `ShadowMapSystem`, `Present/waitUntilCompleted` (GPU wait) | CFrame/Size churn on parts, shadows, GPU-bound frames |
| Replication | `Net PacketReceive`, `deserializePacket`, `Replicator/ProcessPackets`, `Dispatch Data Senders`, `ModelCompleteness Mega Job` (server) | CSG mesh replication, instance add/remove bursts |
| Scripts | `Heartbeat`, `WaitingHybridScriptJob`, `GC`, `RenderStepped` | Our Luau. GC spikes come from table churn |
| CSG | No dedicated tag is documented | Wrap GeometryService calls in `debug.profilebegin` ourselves |

**ScriptProfiler** **[doc]** <https://create.roblox.com/docs/studio/optimization/scriptprofiler>
- Developer Console tab: per-function CPU time on the client or the server, exportable as JSON.
- `ScriptProfilerService` (ClientStart/ServerStart/ServerRequestData/OnNewData/DeserializeJSON)
  is **plugin security**, so a game script cannot automate it. It is a manual tool.

**Developer Console memory** **[doc]** <https://create.roblox.com/docs/studio/optimization/memory-usage>
- Client/Server toggle: CoreMemory, PlaceMemory, PlaceScriptMemory, UntrackedMemory.
- **LuauHeap** snapshots can be compared. Its Unique References/Unparented Instances view finds
  destroyed buildings still held by tables. Label memory with `debug.setmemorycategory`.
- The console's Network tab covers **HTTP calls only**. Replication bandwidth comes from Stats
  or Shift+F3.

**Stats service, readable from scripts** **[doc]** <https://create.roblox.com/docs/reference/engine/classes/Stats>
- `FrameTime` is in seconds, client only.
- `HeartbeatTime` (seconds) and `PhysicsStepTime` replace the deprecated `HeartbeatTimeMs` and
  `PhysicsStepTimeMs`.
- `InstanceCount`, `PrimitivesCount`, `MovingPrimitivesCount`, `ContactsCount`.
- `DataReceiveKbps`/`DataSendKbps`: on the server these sum all clients.
  `PhysicsReceiveKbps`/`PhysicsSendKbps`.
- **New render counters:** `SceneDrawcallCount`, `SceneTriangleCount`, `ShadowsDrawcallCount`,
  `RenderCPUFrameTime`, `RenderGPUFrameTime`. Draw-call budgets become scriptable. The time units
  are undocumented, so calibrate them against the MicroProfiler.
- `GetTotalMemoryUsageMb()` is OS-level. `GetMemoryUsageMbForTag` returns 0 unless
  `MemoryTrackingEnabled`. The tags that matter are `Instances`, `BaseParts`, `PhysicsCollision`,
  `GeometryCSG`, `GraphicsParts`, `GraphicsSolidModels`, `LuaHeap` and `Signals`.
  <https://create.roblox.com/docs/reference/engine/enums/DeveloperMemoryTag>

**Overlays** **[doc]** <https://create.roblox.com/docs/performance-optimization/identify>:
Shift+F5, Shift+Ctrl+F1–F5, Shift+F3 (network), Ctrl+Alt+F7. "Studio's performance stats are
skewed", so measure on the client. Server heartbeat caps at 60 (Server Jobs → Heartbeat).

**Creator Dashboard Performance** **[doc]** <https://create.roblox.com/docs/production/analytics/performance>
- Live client and server FPS, CPU and memory (including OOM exits and memory by server age),
  with percentiles per place version.
- Needs ≥ 100 DAU, so it only helps after launch.

### 2.2 Load testing on Roblox

- **Studio Server & Clients** **[doc]** <https://create.roblox.com/docs/studio/testing-modes>:
  at most **8 clients**, each a separate Studio session. `StudioTestService:ExecuteMultiplayerTestAsync`
  scripts this from a plugin. Fine for small test places, infeasible with this map.
- **Network Simulator** (Studio beta) **[doc]** <https://create.roblox.com/docs/studio/network-simulator>:
  0–1000 ms latency and jitter, 0–0.5% loss, **no bandwidth cap**. Use it for timeline
  consistency on a small place.
- **Bots** **[community]** <https://devforum.roblox.com/t/stress-testing-tools/32413>: there is no
  official load-test framework or headless client. In-server bots are the standard workaround.
  The server still replicates bot motion and CSG to each real client, so receive cost *is*
  exercised.
- **Multiple clients on one PC:** community multi-instance tricks have been patched
  **[community]** <https://devforum.roblox.com/t/4346863>. Real-client counts need devices,
  friends or group testers.
- **Open Cloud Luau Execution** **[doc]** <https://create.roblox.com/docs/cloud/reference/features/luau-execution>
  - Runs a script headlessly against a place or a specific place version.
  - **Tasks run at most 5 minutes**, with 10 concurrent per place. Task creation is limited to
    5 per minute per key owner.
  - Logs and return values come back via polling.
  - The reference CI is <https://github.com/Roblox/place-ci-cd-demo> (archived 2024; it
    assumes a fully Rojo-managed place). Our map is not in Rojo, so tasks target the
    **published test place version**.
  - **There are no players**, and whether Heartbeat or physics advance is undocumented
    **[verify]**. Use it as a server-only smoke gate: load memory, InstanceCount, scripted hit costs.
- **Server memory ceiling** **[doc]**:
  - The limit is `6.25 GiB + 100 MiB × peak connected players`; memory does not fall when
    players leave. Keep it below 50%.
  - The Performance dashboard adds "under about 3 GB as a general guideline".
  - **Bots earn no per-player allowance.** A server that has only ever had 1–3 real players
    sits near 6.35–6.55 GiB, so test against the base figure.
  - The current place's projection is about 7 GB (1.1M parts × 6.4 KB/part, ProjectFiles
    2026-09-18). That is **already over the hard limit with zero load**. The design target of
    60k parts gives about 0.4 GB.

### 2.3 Emulating low-end hardware

- **Quality levels** **[doc/community]**:
  - Internal levels are 1–21; the in-game slider runs 1–10. Low levels drop post effects and
    "objects that are far away will not be rendered".
  - Per-level effects are "platform- and device-specific and can not be relied upon".
  - To force a level: the manual in-game Graphics Quality slider, Studio Settings → Rendering,
    or the allowlisted client FFlag `DFIntDebugFRMQualityLevelOverride` (allowlist of
    2025-09-29, which also allows `DFIntTextureQualityOverride` and a graphics-API preference)
    <https://devforum.roblox.com/t/3966569>. FPS-uncap flags are not allowlisted.
- **Frame cap:** the default is 60; Windows can raise it to 240 in Settings **[doc]**. Measure
  the low proxy at 60 and the high tier at the 240 cap.
- **Device Simulator** emulates "screen dimensions, pixel density, on-screen keyboard, and touch
  input". It does **not** emulate performance **[doc]**.
- **Throttling this PC** (system or driver settings, so the owner applies them):
  - **CPU:** set the power plan's "Maximum processor state" to about 60% to approximate
    U-series sustained clocks **[est]**; `start /affinity F` limits Roblox to 4 logical cores.
  - **GPU:** an Adrenalin power or clock limit removes perhaps 30–50%, nowhere near the 17–20×
    FP32 gap (35 vs about 2 TFLOPS) or the shared-DDR4 bandwidth gap
    **[community; est]** <https://technical.city/en/gpu/Iris-Xe-Graphics-G7-vs-Radeon-RX-7700-XT>.
  - **RAM:** a memory hog such as Sysinternals Testlimit can mimic 8 GB paging. It needs a download.

**What these can and cannot tell you:**

| Inference | Valid? |
|---|---|
| Draw calls, triangles, instance and memory MB, KB/s | **Yes**: hardware-independent |
| What survives the draw-distance cut at level N | **Mostly**: depends on the device, so confirm on the real laptop |
| CPU ms scaled 1.5–2× for a laptop main thread | **Rough** **[est]** |
| GPU ms on Iris Xe | **No**: different bandwidth, driver, tiling and thermals |
| 8 GB paging behaviour, thermal throttling after 10+ min | **No**: needs real hardware |

### 2.4 Budgets from shipped Roblox work

- **MrChickenRocket** (staff-category guest article, 2024-08-20) **[staff-category]**
  <https://devforum.roblox.com/t/3127146>:
  - **500 draw calls and 500k triangles** "in scene", **< 1.3 GB client memory** and
    **< 50 KB/s client receive**.
  - Physics throttles above about 40 KB/s, at **0.4–0.9 KB/s per moving assembly**.
  - His shipped game, Cardboard Box Simulator, budgeted 300 draws / 300k triangles for the map
    plus 200 / 200k flexible. A typical view measured about 100 draws / 150k triangles.
- **Remotes** **[doc]**: about 500 requests/s per client; unreliable payloads over 1000 bytes
  are dropped. The "50 KB/s remote limit" is folklore **[community]**.
- **Instances:** staff say most servers run "fewer than about 1 million instances" (earlier doc §1.1).
- **Named shipped games:** I found **no first-party published part counts or KB/s** for
  battlegrounds or city games (Jailbreak, TSB, etc.). Any numbers floating around are unverified.

---

## 3. Test harness design

### 3.1 Modules (proposed paths; not implemented)

| Module | Side | Job |
|---|---|---|
| `src/shared/Perf/PerfConfig.luau` | shared | Budgets, scenario playlist, seeds, sample rates |
| `src/server/Perf/PerfDirector.luau` | server | Runs only if the place attribute `PerfMode=true` **and** it is a private server of the test place **and** an allowlisted admin is present. Runs the scenario phases on a `GetServerTimeNow()` schedule and broadcasts the phase to clients |
| `src/server/Perf/BotSpawner.luau` / `BotBrain.luau` | server | Seeded bot rigs and behaviours (below). Bots call the **same internal attack-intent function** as the player remote, so HitHandler, timelines, CSG and debris run the real code path |
| `src/server/Perf/ServerSampler.luau` | server | 1 Hz: HeartbeatTime (p50/p95/max over the second via a Heartbeat ring buffer), PhysicsStepTime, InstanceCount, Primitives/Moving/Contacts, Data/Physics Send and Receive Kbps, GetTotalMemoryUsageMb, tags (Instances, BaseParts, PhysicsCollision, GeometryCSG, LuaHeap, Signals) |
| `src/server/Perf/HitTiming.luau` | server | Per hit: intent→launch ms, CSG ms, parts carved or deleted, debris spawned. Wraps each in `debug.profilebegin` |
| `src/client/Perf/ClientSampler.luau` | client | Per frame: FrameTime ring buffer. Each second: p50/p95/p99/max, frames > 50 ms and > 100 ms, SceneDrawcall/Triangle and Shadows counts, RenderCPU/GPU, GetTotalMemoryUsageMb plus graphics tags, DataReceiveKbps, ping, quality level, viewport. Reports to the server every 5 s on one RemoteEvent |
| `src/client/Perf/BenchCamera.luau` | client | Deterministic camera and character routes: a city loop at top speed plus teleport hops, so runs are repeatable |
| `src/server/Perf/PerfReport.luau` | server | Aggregates per scenario and per client tier. Writes `PerfRuns/<milestone>/<runId>` to a DataStore (under 4 MB, chunked). Prints one JSON line per scenario. On a budget breach, triggers a LibMP server snapshot (or prompts a manual server MicroProfiler dump) |
| `tools/perf/run_gate.py` | dev PC | Open Cloud Luau Execution smoke gate against the test place version |
| `tools/perf/fetch_report.py` | dev PC | Pulls DataStore entries through Open Cloud. Renders a pass/fail table against `PerfConfig` budgets and the previous milestone, flagging >10% regressions |

**Rules:** gate the harness on the test place ID; samplers use preallocated ring buffers so
they do not distort GC; discard the first 60 s of each scenario.

### 3.2 Bot behaviours

The rig is R15 built from a HumanoidDescription, so animation and replication cost match a
player. `EvaluateStateMachine=false` while kinematic (Tier A/B), matching the planned victim
motion. Each bot gets a seeded RNG.

| Behaviour | Does | Stresses |
|---|---|---|
| Roamer | Walks and sprints along road splines; idles at corners | Baseline humanoid replication |
| Duelist pair | Closes in, trades light attacks every 0.5–2 s, ~1 launch per 10 s | Hit validation, timelines, Tier A paths |
| Launcher | Tier B Mach hit through a district | Teleport fake, cylinder CSG, debris |
| Beamer | Beam or sphere erase every 8–15 s | Pure CSG, mesh replication |
| Slicer | Plane cut and collapse sequence (when built) | Collapse timeline, bulk deletes |
| Teleporter | Teleports to random districts every 2–5 s | Arrival anywhere; far-event fan-out |
| Corpse | Ragdolls, lies, recovers | Physics hand-off (Tier C), contacts |

### 3.3 Client tiers

| Tier | Machine | Settings |
|---|---|---|
| **H** (high) | Dev PC | Quality Automatic, FPS cap 240 |
| **L-proxy** | Dev PC | Quality forced to 1 and to 4 (two runs), FPS cap 60, 4-core affinity, CPU max state about 60%, GPU power limit at minimum, 1366×768 window |
| **L-real** | Iris Xe / UHD laptop with 8 GB (to acquire) | Quality Automatic, battery saver off, plugged in |
| **Far observer** | Any | Parked 2,000+ studs from the action, to measure what far clients pay for remote events |

---

## 4. Test matrix

Each scenario runs for 3 to 5 minutes after warmup, three times. Report the median of the
p95 values across the three runs. "R" is the number of real clients, B the number of bots.

| ID | Scenario | R / B | Server focus | Client focus |
|---|---|---|---|---|
| S0 | Empty-map control (no buildings) | 1 / 0 | Floor costs | Floor costs |
| S1 | **Idle full city** | 1–3 / 0 | Memory after load, InstanceCount | Memory, draws/tris at 6 fixed vantage points, skyline presence |
| S2 | **Traversal at top speed**: BenchCamera loop at 600 studs/s plus Mach legs | 1–3 / 0 | Heartbeat during motion | Frame p99, hitches, draw-distance pop (screenshot every 2 s) |
| S3 | **20 bots fighting**: 4 clusters × 5 in different districts | 1–3 / 20 | Heartbeat, physics, send KB/s | Receive KB/s near and far |
| S4 | **Simultaneous big hits**: 4, then 8 Launcher/Beamer hits in the same frame across districts, every 3 s for 2 min | 1–3 / 8 | CSG ms, GeometryCSG MB, max frame, hit→launch | Receive burst, `ProcessPackets` ms, hitch count |
| S5 | **Teleport storm**: all bots plus the observer teleport every 1–3 s | 1–3 / 20 | Heartbeat | Frame spikes after arrival, memory |
| S6 | **Soak**: S3 + S4 + S5 mixed, 45 min | 1–3 / 24 | Memory slope, InstanceCount slope, debris cleanup | Memory slope (leaks), GC |
| S7 | **Join under load**: a new client joins mid-S4 | +1 | Join send burst | Time to playable, peak memory |
| S8 | **Real-player night**: S3/S4 with 15–25 humans | 20+ / 10 | Validates the bot extrapolation | Spread across real devices |
| G0 | **Headless gate** (Luau Execution, every publish) | 0 / 0 | Load memory, InstanceCount, 20 scripted hits: CSG ms, parts touched | n/a |

**Cadence:**
- G0 runs on every publish to the test place.
- S1–S7 run per milestone, at about 90 minutes each.
- S8 runs once per major milestone and before launch.
- L-real runs before any public release.

---

## 5. Proposed budgets

Each line gives a target, then a fail threshold. The headroom covers effects not captured:
real players, live-server variance and laptop thermals.

### Server (live private server, S3–S6)

| Metric | Target | Fail |
|---|---|---|
| Heartbeat rate (1/HeartbeatTime) | p95 ≥ 58 Hz | p95 < 50 Hz or any 1 s window < 30 Hz |
| Single-frame spike in S4 | ≤ 50 ms | > 100 ms |
| Hit intent → victim launch | ≤ 100 ms | > 150 ms |
| PhysicsStepTime | p95 ≤ 3 ms | > 6 ms |
| Total memory (GetTotalMemoryUsageMb) | ≤ 2.5 GB | > 3.0 GB (Roblox guidance), with 6.35 GiB as the hard ceiling |
| Memory slope in S6 after 10 min | ≤ 20 MB / 10 min | > 50 MB / 10 min |
| GeometryCSG tag | ≤ 150 MB | > 300 MB |
| InstanceCount growth over S6 | ≤ +5% | > +15% (debris not reclaimed) |
| Server-simulated moving assemblies | ≤ 40 | > 60 (0.4–0.9 KB/s each) |
| DataSendKbps ÷ real clients | ≤ 40 KB/s per client average | > 50 KB/s average, or > 150 KB/s for > 2 s |

### Client

| Metric | H (dev PC) | L-proxy (dev PC throttled) | L-real (laptop) |
|---|---|---|---|
| Frame p95 | ≤ 8.3 ms (120 FPS) | ≤ 12 ms CPU-side ((FrameTime − GPU wait) × 1.5 ≤ 16.7) **[est]** | ≤ 16.7 ms (60 FPS); ≥ 45 FPS p5 in S4 |
| Hitches > 100 ms | 0 per scenario | ≤ 1 per minute | ≤ 2 per minute |
| SceneDrawcallCount p95 | ≤ 500 | ≤ 350 at level 1–4 | ≤ 350 |
| SceneTriangleCount p95 | ≤ 800k | ≤ 500k | ≤ 500k |
| Client memory | ≤ 2.5 GB | ≤ 1.5 GB | ≤ 1.5 GB; OS free RAM never < 500 MB |
| DataReceiveKbps | ≤ 40 average | same | same; ≤ 120 burst |
| Far observer in S4 | Receive ≤ 60% of a near client's; no hitch | same | same |
| Skyline check (S1/S2 screenshots) | City silhouette visible to 3,000+ studs | Silhouette visible at level 1 | Same |

**Map guardrail:** about 60k parts map-wide is about 0.4 GB at 6.4 KB/part, leaving the rest of
the 3 GB for players, CSG, debris and scripts.

---

## 6. Running a milestone

1. Publish to the test place, then run `run_gate.py` (G0); stop on failure.
2. Start a `PerfMode` private server. Join as H, rejoin as L-proxy, and use a second device as
   the far observer. The director advances the playlist on its own.
3. Run `fetch_report.py`. On any failure, take a server MicroProfiler dump and "Combine &
   Compare" it with the last passing milestone's dump.

## 7. Verify in engine

- The units of the RenderCPU/GPU times.
- Whether `SceneDrawcallCount` matches the overlay.
- Whether Luau Execution tasks run Heartbeat and physics.
- Whether LibMP works in our private servers, and what it costs.
- How AMD level 1–4 culling compares with Intel iGPU culling.
- Whether server send per client stays linear from 1 to 3 real clients; if not, run S8 sooner.
