# Combat motion, destruction and multiplayer sync (2026-10-19)

Research only. No code, Studio or place changes. This builds on `ROBLOX_ENGINE_SCOPING.md`
(physics: "off by default, on at the moment") and `SCOPED_PLAN.md`. Today's hit path in
`src/server/HitHandler.luau` anchors the victim, waits `YIELD_MASK_DELAY`, calls `PivotTo` to the
endpoint, unanchors, sets velocity, and runs CSG along a 600-stud cylinder. It also trusts the
client's `HitEvent(targetModel, direction)` without checks.

Tags: **[doc]** Creator Hub, **[staff]** Roblox staff post, **[community]** DevForum non-staff,
**[ext]** non-Roblox studio/talk, **[est]** my inference, verify in engine.

Coverage gap: none of the named Roblox titles (The Strongest Battlegrounds, Jujutsu Shenanigans,
Heroes Battlegrounds, Blox Fruits, Deepwoken) publish technical devlogs about knockback or
destruction. I found only community guesses, such as "TSB uses BodyVelocity on the server"
(unverified). Below, the Roblox evidence is the DevForum consensus plus the docs.

---

## 1. How Roblox combat games do knockback, and the ownership problem

**The core fact.** Players own their character's physics. The server owns a part by default,
but the engine hands unanchored parts near a character to that client [doc]. So a server-side
`LinearVelocity`/`ApplyImpulse`/`AssemblyLinearVelocity` on another player's root either does
nothing or looks laggy. "The client has authority over its own character", per a DevForum
answer [community].

The community uses three patterns [community, threads 2545817, 4736134, 3936670, 3738501]:

| Pattern | How | Result |
|---|---|---|
| Client applies the mover | Server fires the victim a remote; the victim's client adds `LinearVelocity` to itself | Smooth for the victim. Others see it through two network hops (victim to server to them). Easy to exploit: the victim can simply ignore it. |
| Server takes ownership | `SetNetworkOwner(nil)` on the victim, apply force, hand ownership back | Others see server-interpolated motion. The victim sees themselves one RTT late. Flipping ownership back and forth looks "glitchy / laggy" from the enemy's view. Docs warn `SetNetworkOwner(nil)` "can cause jittery physics" for clients. |
| Server `LinearVelocity`, NPCs only | Bots are server-owned, so forces work | Fine for dummies. With `math.huge` force, wall hits fling the target, so use a large finite force. |

No pattern makes the motion deterministic or wall-aware. Each is a force run through the
solver, which is exactly what the owner wants to avoid.

**Server Authority** (full release 2026-07-09) [staff/doc] makes the server the source of
truth, with client prediction and rollback. It requires `StreamingEnabled`, deferred signals,
`UseFixedSimulation`, InputActions, and logic in `RunService:BindToSimulation()` modules that
run on both sides. The release post gives no knockback guidance. It does say server-only
effects (for example "a stun ability") cause client mispredictions, and that **remote events are
not on the shared timeline**, being off by roughly 40-50 ms. Early adopters report rollback bugs.
**Recommendation: don't adopt it now.** Write the motion code as pure functions so it can move
into `BindToSimulation` later [est].

**What fits this game best: anchored, server-scheduled kinematic paths [est].** During
knockback the victim has no control, so nothing needs predicting:

1. The server anchors the victim's `HumanoidRootPart`. Anchored parts are always server-owned
   [doc], so the victim client can't fight or exploit it, because local unanchoring does not
   replicate.
2. The server computes a **path** (section 2) and broadcasts it with a server-time start `t0`.
3. **Every client, the victim included, renders the victim's root at `path(GetServerTimeNow()-t0)`
   every `PreRender`.** That overrides the jerky replicated CFrame of the anchored part. Local
   writes to a server-owned part show until the next replication, and the per-frame override
   wins [est, verify].
4. The server never needs per-frame motion. Hit checks, collateral and AI read the same analytic
   `path(t)`. It writes the real CFrame at low rate (around 10 Hz) and at the end.
5. **Hand-off:** at path end, set the final CFrame and unanchor. Then `SetNetworkOwner(player)`
   for players, or keep `nil` for bots. Set `AssemblyLinearVelocity` to the path's exit velocity
   if a physics tumble is wanted.

`GetServerTimeNow()` is "monotonic" and "moves at the same rate as the local clock to within
0.6%" [doc], so it is a usable shared clock.

**Latency mask = hitstop [est].** Start every path with a 60-120 ms freeze (fighting-game
hitstop). A client receives the event about half an RTT late. If that is inside the hitstop, it
sees no skip. If it arrives later, the client fast-forwards (evaluates at the true elapsed time),
and the jump is hidden by impact VFX. This is the same role `YIELD_MASK_DELAY` plays today.

**Exploit stance.** Clients send *attack intent* (attack id, aim), never "I hit X". The server
runs hitboxes against server-known positions, with a small rewind tolerance for the attacker's
ping (Halo Reach and Overwatch both favour the shooter within bounds [ext]). It also checks
cooldowns and range. Today's `HitEvent` would let any client launch any target from anywhere.

## 2. Kinematic "vector math" motion for victims and bots

**Representation.** The server plans; clients only evaluate. A path is a short list of
**segments**, each closed-form:

- `Ballistic`: `p = p0 + v0·t + ½·a·t²`, where `a` is gravity plus an optional constant drag decel.
- `Slide`: horizontal, decelerating at `μ·g`, with `y` snapped to the ground height.
- `Pinned`: stuck in a wall crater for N ms.
- `Hidden`: the current teleport fake, a zero-length jump inside a dust mask.

Each segment ends in an **event**: `WallImpact`, `Breakthrough(buildingId)`, `GroundBounce`,
`Stop`, or `PhysicsHandoff`. Clients evaluate polynomials, so **floating-point determinism is
not needed**: we sync results, not inputs. That is Gaffer's "state synchronization" rather than
"deterministic lockstep", which is hard because exact determinism is fragile [ext]. A typical
flight is 2-6 segments, so one message is a few hundred bytes.

**Planning loop (server, fixed dt about 1/60):**

- `workspace:Spherecast(pos, r≈2, v·dt, params)` per step, with
  `RaycastParams.FilterType = Include` set to {Buildings folder, Terrain, ground}. Exclude
  characters and debris.
- Spherecast "does not detect parts that initially intersect the shape" [doc]. Back the cast up
  slightly at the start, or do a `GetPartBoundsInRadius` check at `t=0`. Limits: radius ≤ 256,
  distance ≤ 1024 per cast [doc], so chunk long casts.
- One downward ray per step finds ground. Below a landing angle or speed, switch
  `Ballistic`→`Slide`. Otherwise reflect: `v' = v − (1+e)(v·n)n` with `e≈0.2`.
- **Wall rule:** if `speed > breakSpeed(wall)` and the wall is destructible, it is a
  `Breakthrough`: speed drops by the wall's toughness and a destruction event is scheduled at
  that time. Otherwise it is `WallImpact`, either `Pinned` (crater) or a bounce.
- Plan the whole flight at hit time; it is cheap at 1/60 steps × a few seconds. If the world
  changes mid-flight (a re-hit or someone else's collapse), **re-plan from `path(now)`** and send
  a new path with an incremented generation. Keep the `hitGeneration` idea.
- **Collateral:** sample `path(t)` against other characters' server positions. Anyone within
  radius at time `t` gets their own secondary path starting at `t`.

**Humanoid during a path.**

- Bots: `EvaluateStateMachine = false` (it "disable[s] the internal physics and state machine"
  [doc]), `AutoRotate = false`, root anchored, and a "launched" animation on the Animator.
- Players: `SetStateEnabled` "does not replicate" [doc], so state changes (`Physics`, disable
  `FallingDown`/`Ragdoll`/`GettingUp`) must run **on the victim's client** from the path event.
  Anchoring is the server-side guarantee.
- Community warnings: toggling `EvaluateStateMachine` on players can break death handling, and
  repeated LinearVelocity knockbacks caused tripping [community]. Anchoring avoids both.
- Move the character with root CFrame or `PivotTo`. `BulkMoveTo` is for many parts, such as
  debris; the docs say plain CFrame sets are "fast enough in the majority of cases".

**When physics turns on:** only at `PhysicsHandoff`. Use it for low-speed endings where a tumble
looks better than a slide, and for the BallSocket ragdoll already planned in `SCOPED_PLAN.md`.
Weak attacks can skip paths entirely: a 0.3 s `Slide` segment is enough.

## 3. Multiplayer-consistent destruction

**What the AAA references do:**

- *The Finals:* movement, physics and destruction run on Embark's servers so every player sees
  the same result [ext; no technical talk is public].
- *Battlefield 6:* "prioritization and culling of part destruction and debris spawning" keeps 64
  players in sync. Destruction persists. Part-based destruction is "systemic and controlled" and
  can damage "players beneath destroyed buildings" [ext].
- *Teardown multiplayer (2026):* sending voxel data "completely choked the connection", so
  destruction became a **reliable, ordered command stream** ("cut hole in this shape at x,y,z")
  that every peer replays deterministically, in fixed-point math. Bodies use unreliable state
  sync with corrections, under a per-client priority budget of about 1 Mbit. Late joiners replay
  the commands [ext].

**The Roblox-specific trap.** Roblox does **not** guarantee ordering between instance or
property replication and RemoteEvents [doc, Properties & attributes]. A server CSG union
therefore appears on each client at "carve time + that client's latency + mesh size"; CSG
results are new meshes that replicate [staff]. If the victim's motion is client-timed but the
hole arrives by replication, they will disagree: the victim visibly flies through an intact wall,
or the wall vanishes early. Also, because **each player simulates their own character against
their local copy of the geometry**, the *client's* collision decides whether someone falls
through a floor or gets stuck in a ghost wall. The server's copy does not.

**Fix: one server timeline and local execution [est].**

1. On a hit, the server builds a `HitTimeline`: the victim path plus destruction events
   `{eventId, tBreak, cutter (start, end, radius), seed, buildingIds}`. `tBreak` is the time the
   path reaches each wall, so ordering ("wall opens before the victim reaches it") holds by
   construction on every machine, since all evaluate the same server-time timeline.
2. Send it on **one reliable RemoteEvent** with a sequence number; clients buffer by sequence.
   Ordering between remotes is not documented as guaranteed, so don't depend on it.
   `UnreliableRemoteEvent` is explicitly unordered and suits cosmetic-only puffs [doc].
3. **Server at `tBreak`:** swap in the carved union for collision, bots and queries. Start the
   CSG *at hit time* (it yields), hold the result unparented, and parent it at `tBreak`.
4. **Each client at `tBreak`:** locally hide the original part and turn off its collision,
   `Transparency=1, CanCollide=false`. Local, not replicated. Then show a local stand-in: a
   client-side `GeometryService` carve (works in LocalScripts [staff]) or pre-cut chunks. When the
   server's union replicates (tag it with `DestructionId`), delete the stand-in. The two are
   visually alike and the swap happens under dust.
5. **Late arrival:** if `now > tBreak`, apply immediately and spawn debris already advanced to
   `now − tBreak`.

**Debris determinism.** `Random.new(seed)` gives every client the same chunk sizes, directions
and spin. Move gameplay-irrelevant debris **kinematically** (`p0 + v·t + ½g·t²` until a
precomputed ground height), so all clients see the same pile without the solver. A few
near-camera pieces may use real physics. They will diverge per client, so they must be
cosmetic-only: their own CollisionGroup that does not collide with characters, anchored when
asleep, pooled. Debris that *damages* must be server-computed from the same analytic motion
(Battlefield-style damage under collapses).

**Your scenario (a strong hit passes through a building where A and B are fighting):**

- A and B receive the timeline about one RTT/2 after the hit. With hitstop and a launch distance
  before the wall, `tBreak` is usually still in their future, so the hole opens on schedule.
- Their floor or wall collision vanishes locally at `tBreak`, which is the same moment the server
  removes it. If they stood on removed slab cells, they fall naturally under their own physics,
  with no ghost floor.
- If the victim's path crosses them, the server issues collateral paths with `t0` equal to the
  crossing time.
- On third-party screens, A and B are shown about 100 ms in the past [est]. They may appear to
  hover over the new hole briefly; dust hides it.
- **Stuck prevention:** moving collapse pieces are `CanCollide=false` and gain collision only
  where they settle. At settle, check `GetPartsInPart` against characters and push overlapped
  players up or out.

## 4. Structural integrity and faked collapse

**References:** Red Faction: Guerrilla used pre-broken meshes with a stress model, so removing
supports shifts weight until a structure fails [ext]. DevForum attempts converge on
**flood-fill from grounded parts**, sometimes with integrity that decays with distance. They
reject per-weld force maths as slow, since Roblox doesn't expose constraint forces [community].

**Cheap model for our slab + core buildings [est].** BuildingGenerator already stores
`InteriorGrid`, `CoreCFrame`/`CoreSize` and tagged `BuildingCore` walls. Keep a **logical grid**
per building on the server: `floors × cells` (about 4-8 stud cells) with flags
`present / core / perimeter`. Destruction first clears cells the cutter intersects. That logical
pass is cheap and comes before any CSG.

1. **Island check (per damaged floor):** BFS from support cells. A support cell is a core or
   perimeter cell whose matching cell on the floor below is present. Unreached cells are
   floating and fall.
2. **Cantilever limit:** BFS depth from support > `Lmax` (about 3 cells) also falls. This is the
   DevForum "integrity decays with distance".
3. **Global collapse:** for each level `k`, `capacity_k = intactCoreCells_k + 0.5·intactPerimeter_k`
   and `load_k = floors above k`. If `capacity_k / initial_k < threshold(load_k)`, everything
   above `k` collapses. Lean direction is the unit vector from the building centre toward the
   centroid of the lost supports at level `k`.

The cost is a few thousand cells per building. Run it time-sliced after the hit
(`task.defer`); only damaged floors and the levels below them need checking.

**Faked collapse is all vectors and all events:**

- *Floating islands:* rectangle-merge the fallen cells into a few chunks (reuse the generator's
  decomposition). Each chunk follows `Ballistic` down with a small seeded tilt to the floor
  below. There it becomes a rubble slab or breaks into seeded debris.
- *Building collapse:* send `CollapseEvent{buildingId, tStart, seed, leanDir, level}`.
  - At `tStart`, server and clients set the building's parts `CanCollide=false`.
  - **Stage 1** (0-0.4 s): tremor jitter and dust ring at base.
  - **Stage 2:** floors above `k` drop as groups with `BulkMoveTo`. Each floor starts
    `Δ≈0.12 s` after the one below (progressive pancake), plus lean `θ(t)` about `leanDir`.
  - **Stage 3:** big smoke, then swap the shell for a **rubble pile** sized to the footprint,
    which is collidable and server-replicated.
  - Clients animate locally from the event; the server only applies the end state and damages
    characters inside the footprint.

**Budgets [est]:**

- Debris parts per client: ≤ 250 active, ≤ 60 per event, distance-scaled. Far clients get only
  smoke and the rubble swap.
- Server: ≤ 1 building collapse starting per ~2 s, and ≤ about 8 CSG ops started per frame.
- Network: ≤ 1 timeline message per hit plus replicated unions. Unions are the big cost, so
  prefer delete-only (cells or tiles) where carving isn't visible.

## 5. Recommended architecture for this game

```
shared/MotionPath     pure: segments -> pos/vel at t; encode/decode   (no Instances)
shared/Timeline       server-clock helpers, event buffer, fast-forward, seq ordering
server/CombatService  attack intent -> server hitbox/validation -> strength tier
server/PathPlanner    spherecast planner -> segments + Breakthrough/collateral events
server/VictimService  anchor/ownership/handoff for players & bots; low-rate CFrame writes
server/StructureGrid  logical cells, island/cantilever/collapse checks (time-sliced)
server/Destruction    schedules CSG (precompute, parent at tBreak), rubble, damage
client/VictimRender   PreRender: every active victim's root = path(serverNow - t0)
client/DestructionFX  local hide at tBreak, stand-ins, seeded debris, smoke, collapse anim
Remotes: WorldTimeline (reliable, seq#), CosmeticFX (unreliable), AttackIntent (client->server)
```

**Data flow (strong hit):** the client sends `AttackIntent`. `CombatService` validates and picks
the tier. `PathPlanner` produces segments and `tBreak`s. `Destruction` starts the CSG
immediately and updates `StructureGrid`. One `WorldTimeline` message carries the path, the
breaks, and any collapse/fall events, each with server times and seeds. All machines execute at
those times. The strongest tier is the same path with a `Hidden` (teleport) segment inside the
dust, so it uses the same pipeline.

**Pitfalls:**

1. Ownership ping-pong on players: hand back once, at path end.
2. Humanoid state calls don't replicate, so player-side state goes in the client handler.
3. If the per-frame client override stops (for example on a script error), the victim snaps to
   the 10 Hz server CFrame; log it.
4. Touched-based hitboxes are unreliable on CFrame-moved or anchored parts; use queries.
5. CSG not ready by `tBreak` means the server collision lags. Clients are already open, so only
   bots notice; plan a lead of about the measured CSG time.
6. Re-hit mid-flight: generation counters on paths **and** destruction events.
7. If streaming is turned on later, events must reference buildings by id and no-op when the
   building isn't streamed in.
8. Death, respawn or leaving mid-path: `VictimService` must release anchors.
9. Don't let cosmetic physics debris collide with characters; it diverges per client.
10. `CharacterWalkSpeed = 128` in the project means positions on other screens lag about 13
    studs per 100 ms, so collateral and rewind tolerances must scale with speed.

---

## Sources

- Network ownership: https://create.roblox.com/docs/physics/network-ownership
- WorldRoot (Blockcast/Spherecast/Shapecast/BulkMoveTo): https://create.roblox.com/docs/reference/engine/classes/WorldRoot.md
- Workspace:GetServerTimeNow: https://create.roblox.com/docs/reference/engine/classes/Workspace.md
- Replication order (properties vs remotes): https://create.roblox.com/docs/en-us/scripting/attributes
- UnreliableRemoteEvent ordering: https://create.roblox.com/docs/en-us/reference/engine/classes/UnreliableRemoteEvent.md
- Server Authority docs: https://create.roblox.com/docs/en-us/projects/server-authority.md
- Server Authority full release [staff]: https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993
- Shapecasts announcement [staff]: https://devforum.roblox.com/t/introducing-shapecasts/2320655
- CSG full release [staff]: https://devforum.roblox.com/t/full-release-improved-constructive-solid-geometry-csg-apis/4065505
- Knockback threads [community]: https://devforum.roblox.com/t/2545817 ,
  https://devforum.roblox.com/t/trying-to-find-a-way-to-do-smooth-knockback-correctly/4736134 ,
  https://devforum.roblox.com/t/laggy-knockback-linear-velocity/2950780 ,
  https://devforum.roblox.com/t/should-i-handle-knockback-on-the-server-or-client/3738501 ,
  https://devforum.roblox.com/t/knockback-humanoid-state-help/3318715
- Remote ordering discussion [community]: https://devforum.roblox.com/t/remote-event-ordering/4555628
- Structural integrity threads [community]: https://devforum.roblox.com/t/advanced-question-involving-structural-integrity-linkage-calculation/3744790 ,
  https://devforum.roblox.com/t/roblox-destruction-collateral-damage/4077115
- Teardown multiplayer: https://blog.voxagon.se/2026/03/13/teardown-multiplayer.html
- Battlefield 6 destruction: https://www.ea.com/en/news/how-battlefield-6-redefined-destruction
- The Finals server-side destruction (press): https://seasonedgaming.com/2022/09/27/embark-studios-emphasizes-destruction-and-chaos-in-the-finals/
- Red Faction: Guerrilla Geo-Mod 2.0: https://www.redfactionwiki.com/wiki/GeoMod_2.0
- Gaffer on Games, networked physics: https://gafferongames.com/categories/game-networking/
- Overwatch GDC 2017: https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and
- Halo: Reach GDC 2011 (secondary summary): https://edgegap.com/blog/game-backend-deep-dive-halo-reach-netcode-host-migration
- Rocket League GDC 2018: https://www.rocketleague.com/news/rocket-league-at-gdc-2018
