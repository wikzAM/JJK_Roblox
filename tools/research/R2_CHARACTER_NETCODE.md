# Character netcode: movement, knockback steering, hit detection (2026-10-19)

Research only. No code, Studio or place changes. This builds on `GAME_DESIGN_DECISIONS.md` (motion
tiers A/B/C, streaming off, server owns movement and hits) and `COMBAT_MOTION_DESTRUCTION_SYNC.md`
(anchored victim + analytic `path(t)` + one server timeline). It answers the open question there:
**the authority split for victim steering.**

Tags: **[doc]** Creator Hub, **[staff]** Roblox staff post, **[community]** DevForum non-staff or
GitHub, **[ext]** non-Roblox source, **[est]** my inference; verify by measurement.

---

## Executive summary

1. **Do not adopt Chickynoid or Roblox Server Authority (SA) wholesale.** Chickynoid is the best
   reference design but is unmaintained (last push 2024-05-27). SA forces `StreamingEnabled`, which
   the design currently rejects. Its rollback also costs about 6.25x the simulation at 100 ms ping,
   and its remote events sit 40-50 ms off its timeline.
2. **Use a "Chickynoid-lite" for the airborne state first.** Once launched, a victim enters a
   server-authoritative **kinematic path controller** (anchored root, analytic segments). Grounded
   locomotion starts on the stock client-owned Humanoid with server speed and teleport checks.
   That falls short of the owner's "server owns movement"; the same controller can extend to
   ground movement later if checks prove insufficient.
3. **Steering is input-based, not state-based.** The victim sends only quantized, server-time
   stamped stick directions. The server integrates them under hard caps; the client predicts the
   same maths and replays unacked inputs. Exploiters can't exceed the caps, by construction.
4. **Three tiers of influence, borrowed from fighting games.** First, a Smash-style **DI angle
   tweak** read once at hitstop end (±10-18°). Second, **continuous bounded steering** after a
   short lock. Third, a meter- or cooldown-gated **redirect** for top players, like Guilty Gear's
   Burst.
5. **Hits are server-side, with rewind.** Clients send stamped attack intent; the server rewinds
   targets up to 200 ms and tests swept-capsule maths, not engine queries (which see only the
   present). Popular hitbox modules don't lag-compensate.
6. **Budgets.** About **30-50 KB/s receive per client** (community figure; none official).
   Steering costs under 10 KB/s. Start with **10-20 fighting bots** beside 20 players, then measure.

---

## 1. Server-authoritative character controllers

### Chickynoid (MrChickenRocket and Brooke, MIT)

**How it works** [community, GitHub README and commit log]:
- **Replaces the Humanoid** ("a platforming character with a gun and not much else").
- **Inputs only.** The client sends commands (move direction, buttons, bounded delta time), one
  per frame. The server runs the same simulation per player and is the truth.
- **Reconciliation.** On a mispredict the client resets to the last server state and **replays
  all unconfirmed commands**; a failed replay feels like a "tug". The server inserts fake commands
  for clients that fall behind.
- **Custom collision** (own maths plus shapecasts; parts, terrain, convex-hull meshes), required
  for rollback. The character is a fixed box.
- **Extras:** lag-compensated server hit detection, bots, selective replication, and a
  command-stream time budget that catches speed hacks.
- **V2 beta (2024-01-02):** unreliable remotes, buffer-packed delta snapshots, **20 Hz**
  reconcile, and a 3x faster server ("we can finally handle 100 players"). Parallel Luau was
  dropped: "live servers only give you 1 extra core, 2 at most".

**Status in 2025-2026:**
- GitHub `pushed_at` is **2024-05-27**, with 265 stars and 17 open issues. A DevForum reply
  (2025-04-17) calls it "discontinued" [community].
- **High-speed behaviour:** its collision is a swept shapecast, so speed alone doesn't tunnel. But
  every step costs Luau maths per player, and a teleport is just a state write.
- **Knockback is a known pain point.** In thread 3218386 (2024-10 to 2025-04), launching a
  character from a weapon caused continuous rollbacks. The fix was to put the velocity change
  **and the cooldown** inside `simulation.state`. **Any state touched outside the shared
  simulation desyncs.** That lesson applies to anything we build.

**How it could host our features:**
- **Knockback:** a "launched" move type inside the simulation.
- **Steering:** the victim's own commands drive that move type.
- **Teleports:** a server state write with a flag, so the client snaps instead of smoothing.

**Recommendation: copy the design (input commands, replay-reconcile, fake commands, time budget),
not the library**, which would mean replacing the Humanoid for every player and owning
unmaintained netcode.

### Roblox Server Authority (full release 2026-07-09) [staff, doc]

**Requirements.** Setting `AuthorityMode = Server` forces five settings:
- `NextGenerationReplication`
- `PlayerScriptsUseInputActionSystem`
- `SignalBehavior = Deferred`
- **`StreamingEnabled`** (the FAQ says it is used "in part for its Auto Prediction system")
- `UseFixedSimulation`

**Programming model.** Logic lives in `RunService:BindToSimulation()` modules that run on both
client and server. Gameplay inputs must be InputActions. Custom data goes in attributes:
- only the first 64 attributes per instance replicate;
- names are capped at 50 characters, and string values at 50 characters;
- any attribute mismatch triggers a full rollback.

**Limits:**
- 8 playing animation tracks per Animator.
- `time()` is synchronized, but `tick()` and `os.clock()` are not.
- **Remote events are not on the shared timeline** and are about 40-50 ms off. The staff deep
  dive (2026-05-08) says a 100 ms correction means resimulating 100 ms, "6.25x the simulation
  load".
- Other players are *not* predicted by default, so they render in the past.

**Support for our features:** dashes and boosts work if scripted on both sides. Knockback on other
players is **not documented**. Early reports (July 2026) describe prediction modes reverting and
custom-controller conflicts [community]. Staff say SA "isn't the right decision for all games".

**Fit:** its prediction is input-based and per-player, which is the right shape. But the
`StreamingEnabled` requirement collides with "streaming stays off". The design doc keeps streaming
as a fallback, pending the measurement pass. **Recommendation:** keep motion maths pure and
fixed-step, so it could later move into `BindToSimulation` if streaming is ever adopted.

### Other projects

- **Character Controller Library** (beta) [doc]: rollback-aware ability tables built for SA.
- **FPX** (2026-02, v1.1 2026-07) [community]: an SA first-person controller; early mispredict
  reports.
- **Chrono** (2025-08) [community]: custom character/NPC replication with a dynamic interpolation
  buffer and snapshot history. It claims stock NPC replication costs about 10x receive. A good
  reference for our snapshots.
- **Kinematic Character Controller ports:** I found no maintained Roblox port. Chickynoid's
  collision module is the de-facto Luau equivalent [est].

---

## 2. Prediction and reconciliation over Roblox remotes

**Patterns:**

| Pattern | Use here |
|---|---|
| **Client prediction plus replay** (Gambetta II; Chickynoid) | The victim's own steering |
| **Entity interpolation**: render others about 100 ms in the past (Gambetta III; Valve `cl_interp` 0.1 s default) | Other players on stock replication |
| **Dead reckoning on analytic segments** | Third-party view of airborne victims. Extrapolation is *exact* between steering updates because the path is closed-form. |
| **Server rewind / lag compensation**: command time ≈ server time − latency − interp (Valve, Gambetta IV) | Hit detection |

**Roblox specifics:**
- `GetServerTimeNow()` is monotonic and drifts under 0.6% from the local clock [doc]. Use it to
  stamp every command and timeline event.
- Stock physics replication is about **15-20 Hz** with an adaptive, non-configurable
  interpolation delay [community]. `ImprovedPhysicsReplication` (rollout 2026-06-15) publishes no
  rates [staff].
- **Ordering:** RemoteEvents are reliable and ordered per remote. UnreliableRemoteEvents are
  unordered, drop payloads over **1000 bytes**, and are never resent. Client → server is capped at
  about **500 requests/s per client per remote type** [doc]. Property replication is not ordered
  against remotes [doc].

**Input buffering and tick:**
- Simulate paths at a fixed **60 Hz** on the server, the same as SA's fixed step.
- The client sends steering commands at **30 Hz**. Each packet is unreliable and **carries the
  last 3 commands redundantly**, so one lost packet costs nothing; this is a Quake/Overwatch habit
  [ext].
- The server keeps a small per-victim jitter buffer and processes commands in order by stamp.
- **Time-budget rule** (Chickynoid): the summed command time can't exceed elapsed server time plus
  about 50 ms.

**Handling 100-250 ms RTT:**
- **Own steering:** predicted locally (zero input latency). Corrections arrive one RTT later and
  blend over about 100 ms (the SA docs use SmoothDamp 0.07 s).
- **Launch:** the 60-120 ms hitstop hides the first RTT/2; beyond that the client fast-forwards
  under impact VFX.
- **Other players** see steering changes up to about 250 ms late, smoothed. That is acceptable
  because the path is ballistic in between.

---

## 3. Knockback with victim steering

### Fighting-game precedents [ext]

- **Smash DI** (ssbwiki). The stick is read **once, on the last frame of hitlag**. It rotates the
  launch angle up to about **18° (Melee/Brawl)** or **9.74° (Smash 4/Ultimate)**. It is strongest
  perpendicular to the launch and zero parallel to it.
  - **LSI** scales launch speed ×1.095 (up) to ×0.92 (down).
  - **SDI** nudges position during hitlag.
  - After hitstun, ordinary air drift returns.
- **Guilty Gear Strive** (Dustloop) has no trajectory DI. Victim agency comes from:
  - **Psych Burst**, a meter-gated combo breaker;
  - recovery choices, for example wall-stick recovery up, neutral or forward;
  - drift during the attacker's Red Roman Cancel, which steers the launch.
- **Tekken:** essentially no trajectory influence. Agency is in tech rolls and recovery timing
  [ext, general knowledge].
- **Source/Quake air control:** air wish-speed is capped (30 u/s in Source), so players curve
  their arc but can't add much speed [ext, general knowledge].

**Lesson:** influence is **bounded, perpendicular-biased and time-windowed**; large influence is
**resource-gated**.

### Proposed influence model [est]

| Phase | Window | Effect | Cap |
|---|---|---|---|
| **DI** | Read once at hitstop end (server accepts the victim's stamped input up to 150 ms late) | Rotate launch vector | ±12° base, scaled by victim tier |
| **Steer lock** | First 150-200 ms of flight | None | Also lets high-ping inputs arrive |
| **Steer** | Rest of flight | Perpendicular acceleration toward stick direction | `a_perp ≤ k·g` (k about 0.3-0.6 by tier); speed never rises; cumulative deviation ≤ θmax (for example 35°) |
| **Redirect** | Any time after lock; cooldown or meter | New launch vector from the current position (Burst-like) | Speed ≤ current; server validates resource |
| **Brace/tech** | On wall or ground contact | Choose recovery direction (GG wall-recovery style) | Discrete options |

### Networking it: input-based, not state-based

- **State-based** (client sends position): the server must accept anything within a tolerance,
  so exploiters always steer to the tolerance.
- **Input-based** (client sends `{stamp, angle:u8, mag:u4}`): the server computes the effect with
  the same pure function, so caps can't be exceeded, and reconciliation is exact replay.

**Recommendation: input-based.** It is Chickynoid's model, applied only while airborne.

**Authority split:**
- **Server:** owns the anchored root, path planning (spherecasts, walls, breakthrough events) and
  all caps. It applies inputs in stamp order and re-plans from `path(now)` with `gen+1`.
- **Victim client:** predicts with the shared `MotionPath` plus the same steering function and
  the same collision casts against local geometry. It renders its own root every `PreRender` and
  reconciles on each server ack by replaying unacked inputs. A wall the server sees but the client
  doesn't simply yields a correction.
- **Third parties:** evaluate the latest server segment and blend corrections.

---

## 4. Hit detection for fast combat

**Engine queries** [doc]:
- `GetPartBoundsInBox`/`Radius` and `GetPartsInPart` are overlap tests on the **current** world.
- `Blockcast`/`Spherecast`/`Shapecast` sweep, but miss parts already intersecting at the start.
  They are capped at 256 radius and 1024 distance.
- `Touched` is unreliable for CFrame-moved or anchored parts.

**Popular modules** [community]:

| Module | Method | Trade-off |
|---|---|---|
| **RaycastHitboxV4** (TeamSwordphin; V4.01, 2021-09) | Per-frame rays between attachment points on a weapon | Great for swords. Poor for AoE or bodies. Old. |
| **MuchachoHitbox** (SushiManster) and forks (Goofy Hitboxes, HitboxClass) | Per-frame box or sphere overlap, optional velocity prediction | Easy and popular in battlegrounds games. Misses fast movers between frames; velocity prediction overshoots on direction flips. |
| **ShapecastHitbox** | Sweeps the shape between frames | No tunnelling, but has the initial-overlap blind spot. |

**None of them rewinds time.** Battlegrounds games often run them on the attacker's client for
responsiveness, then trust a remote, which is exactly today's `HitEvent` hole.

**Recommendation [est]:**
1. The client sends `AttackIntent{seq, attackId, aimDir, stamp}`. It plays wind-up and swing VFX
   immediately; impact VFX are optional and predicted.
2. The server validates state, cooldown and range, then computes the rewind time
   `t = clamp(stamp, now − 200 ms, now)`, plus the attacker's interpolation delay for stock
   characters.
3. **Target positions at `t`:**
   - victims on paths: `path(t)`, exact and free;
   - everyone else: a ring buffer of root CFrames written every Heartbeat (about 1 s × 60 entries
     per character).
4. **Test with maths, not engine queries.** Characters are capsules; attacks are swept shapes
   over the frame; use segment-to-segment closest points. That costs microseconds at 30-40
   characters, can't tunnel on map-crossing dashes, and makes rewind free because no parts move.
5. **Use engine queries only for world geometry** (wall slams, destruction), with `Include`
   folder filters.
6. **Scale the margin with speed:** about `speed × 0.05 s`, capped.
7. **Favour the shooter only within 200 ms;** beyond that, high-ping attackers miss. That bounds
   "hit behind cover" (Gambetta IV).

---

## 5. Bots and NPCs at scale

**Stock Humanoids are expensive.** The docs say a Humanoid "comes with a significant computation
cost". They recommend client-side NPC animation, a custom movement controller with an
AnimationController, disabled unused states, and pooling [doc]. Community data points: 250 moving
Humanoid NPCs ran at about 27 FPS (35 with 13 states disabled); problems start "over 50 NPCs";
Chickynoid v2 handles about 100 simulated characters per server [community].

**Recommendation [est]:**
- Bots use the **same path controller** when launched, and otherwise a cheap ground controller
  (one down-ray plus one spherecast per tick, anchored root, `EvaluateStateMachine = false`,
  client-side animation). AI decides at 5-10 Hz, staggered.
- **Budget:** about 30-60 µs per bot-tick, so 20 bots at 60 Hz ≈ 1 ms per frame. Start at **10-20
  fighting bots** with 20 players. Gate spawning on the server Heartbeat staying ≥ 55 FPS.
- Remember the server has 1-2 usable cores (Chickynoid's finding), so Parallel Luau gains are
  limited.
- **Replicate bots like victims.** Clients render from path segments and 10-20 Hz snapshots, not
  from 60 Hz anchored CFrame property writes, which replicate per change. Chrono claims about 10x
  receive savings over stock NPC replication.

---

## 6. Bandwidth budgets

**Official limits** [doc]: unreliable payload ≤ 1000 bytes; about 500 client→server requests/s
per remote type; send less, less often, on change; avoid server tweens and instance churn.

**No official per-player KB/s figure exists.** The "50 KB/s" number comes from a since-removed
remote-event article and DevForum lore, described as a throttle point [community]. **Target ≤
30-50 KB/s steady receive per client, and ≤ 5 KB/s send.**

**Costs [community/est]:** per-call overhead is non-trivial (one test found 100 separate remotes
cheaper than one remote carrying an ID). A number argument costs about 9 bytes, so pack with
`buffer`. Each attribute change replicates name plus value, so never write attributes per frame.

**Estimated load at 20 players + 15 bots:**

| Stream | Rate | Size | Per client |
|---|---|---|---|
| Stock character replication (20 players) | ~20 Hz | ~30-50 B | ~12-20 KB/s |
| Bot snapshots (15) | 15 Hz | ~24 B | ~5 KB/s |
| Airborne victim steering acks (≤10 concurrent) | 20 Hz | ~32 B (pos i16×3 rel, vel i16×3, stamp, gen, seq) | ~6 KB/s |
| Hit timelines (reliable) | ~10 hits/s server-wide | 150-400 B | ~3 KB/s |
| Steering inputs (victim → server) | 30 Hz | ~12 B (3 redundant cmds) | 0.4 KB/s send |

That totals about **26-34 KB/s, before CSG union replication**, which is still the largest
unmeasured cost (see the earlier doc).

---

## Recommended architecture

```
shared/MotionPath     pure: segments, steering integrator, caps, encode/decode (fixed 60 Hz step)
shared/HitShapes      capsule/swept-shape maths; rewind helpers
server/CombatService  AttackIntent -> validate -> rewind (≤200 ms) -> math hit test -> tier
server/PathPlanner    spherecast planning; re-plan on input/redirect/world change (gen++)
server/VictimService  anchor root; per-victim command buffer, time budget, caps; hand-off
server/PosHistory     1 s ring buffer of root CFrames per character
server/BotService     kinematic ground controller + AI @5-10 Hz; uses VictimService when hit
client/VictimRender   others: evaluate latest segment + blend; self: predict + replay-reconcile
client/SteerInput     30 Hz unreliable {stamp, angle u8, mag u4} ×3 redundant
Remotes: WorldTimeline (reliable, seq), SteerCmd (unreliable c->s),
         SteerAck/BotSnap (unreliable s->c, batched), AttackIntent (reliable c->s)
```

**Authority split:**

| State | Owner | Notes |
|---|---|---|
| Grounded locomotion | Client (stock Humanoid) | Server checks speed and position delta; teleport abilities are server-executed and stamped |
| Launch, flight path, walls, landing | Server | Anchored root; analytic segments |
| Steering and redirect inputs | Client proposes, server disposes | Input-based, capped, stamp-ordered |
| Hits and damage | Server | Intent plus rewind |
| Cosmetic VFX | Each client | From timeline stamps |

**Teleport tier (B):** a `Hidden` segment. The server writes the root CFrame once and stamps it,
and clients snap (no smoothing) under dust. Teleport abilities use the same path. Steering is
disabled inside `Hidden`.

---

## Risks

1. **Local geometry divergence.** The victim predicts against its local world, so expect
   corrections near walls before scheduled destruction lands. Apply `tBreak` locally on schedule
   and blend.
2. **Shared-code discipline.** As Chickynoid's knockback thread showed, steering state kept outside
   the pure step (cooldowns, meter) desyncs.
3. **High-ping fairness.** At 250 ms, DI and steering are accepted later; the lock and grace
   window only partly help.
4. **Rewind abuse.** Forged stamps claim maximum rewind. Clamp to 200 ms and to measured RTT.
5. **Anchored-root edge cases.** Death, respawn or leaving mid-path; a script error stops the
   `PreRender` override (snap to the 10 Hz CFrame).
6. **SA migration cost.** If streaming is adopted later, moving to SA means an InputActions and
   `BindToSimulation` rewrite, and a 6.25x resim cost on laptops.
7. **Unmeasured numbers.** There is no official KB/s ceiling, CSG replication may dominate, and
   bot cost is extrapolated. Measure on a 20-player test (Shift+F5, MicroProfiler).

---

## Sources

- Chickynoid repo: https://github.com/easy-games/chickynoid (API: pushed_at 2024-05-27; v2 commit 2024-01-02)
- Chickynoid knockback thread (2024-10 to 2025-04): https://devforum.roblox.com/t/chickynoid-networking-help/3218386
- SA full release (2026-07-09): https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993
- SA docs: https://create.roblox.com/docs/en-us/projects/server-authority ; techniques: https://create.roblox.com/docs/en-us/projects/server-authority/techniques
- SA tech deep dive (2026-05-08): https://devforum.roblox.com/t/server-authority-tech-deep-dive-engineering-insights/4624565
- SA issues (2026-07): https://devforum.roblox.com/t/server-authority-barely-works-many-issues/4732583 ; https://devforum.roblox.com/t/trying-to-understand-the-architecture-behind-server-authority/4731659
- Character Controller Library (beta): https://create.roblox.com/docs/characters/character-controller-library
- FPX: https://devforum.roblox.com/t/free-server-authority-fpx-%E2%80%93-lightweight-playermodule-replacement-for-first-person/4409000
- Chrono (2025-08): https://devforum.roblox.com/t/chrono-drop-in-custom-physics-replication-library/3873294
- Reconcile thread (2025-08): https://devforum.roblox.com/t/help-how-to-reconcile-player-movement-server-authoritative-movement/3888657
- Physics replication: https://devforum.roblox.com/t/upcoming-improvements-to-physics-replication/4675512 ; https://devforum.roblox.com/t/interpolation-throttling-update/1534800 ; https://devforum.roblox.com/t/allow-game-developers-to-configure-the-physics-replication-rate-for-their-games/4005498
- UnreliableRemoteEvent: https://create.roblox.com/docs/en-us/reference/engine/classes/UnreliableRemoteEvent.md
- Performance (network, Humanoids): https://create.roblox.com/docs/performance-optimization/improve
- Bandwidth lore: https://devforum.roblox.com/t/remote-event-limitations/3882204 ; https://devforum.roblox.com/t/i-have-question/3397777 ; https://devforum.roblox.com/t/ore-one-remote-event/569721
- NPC counts: https://devforum.roblox.com/t/reducing-humanoid-lag/1837265 ; https://devforum.roblox.com/t/mass-humanoids-question/1071947 ; https://devforum.roblox.com/t/are-humanoids-laggy/2979226
- Hitbox modules: https://devforum.roblox.com/t/374482 (RaycastHitbox V4) ; https://devforum.roblox.com/t/goofy-hitboxs-v101/3090420 (Muchacho-derived) ; https://devforum.roblox.com/t/hitboxclass-v20-a-powerful-oop-based-hitbox-module/3929512 ; https://devforum.roblox.com/t/introducing-shapecasts/2320655
- Gambetta, Fast-Paced Multiplayer I-IV: https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html ; https://www.gabrielgambetta.com/entity-interpolation.html ; https://www.gabrielgambetta.com/lag-compensation.html
- Valve Source networking (cl_interp, lag compensation): https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking
- Smash DI: https://www.ssbwiki.com/Directional_influence
- Guilty Gear Strive mechanics: https://www.dustloop.com/w/GGST/Mechanics
