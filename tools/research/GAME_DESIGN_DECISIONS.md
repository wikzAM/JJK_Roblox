# Game design decisions: combat, motion, destruction, rendering (living doc)

This document collects what the owner and Claude agreed on 2026-10-19. Supporting research lives in this folder:
- `SCOPED_PLAN.md`
- `AAA_OPEN_WORLD_TECHNIQUES.md`
- `ROBLOX_ENGINE_SCOPING.md`
- `SPEED_SKYLINE_STREAMING.md`
- `COMBAT_MOTION_DESTRUCTION_SYNC.md`

Status: **design agreed in discussion. Not implemented** except where a line says otherwise.

## Pillars

1. **Smoke and mirrors.** Roblox physics stays off by default. It is switched on only at chosen moments: the final tumble, some debris, a chosen hand-off.
2. **Multiplayer first.** The dummy is a stand-in for real players and bots. Every system must handle many attackers and many victims at once, with consistent timing for every viewer.
3. **Design for the strongest players.** Top players have every ability unlocked, so victims can redirect and influence their own flight.
4. **Laptop-friendly PC first, maybe console.** Mobile would be a separate, smaller-scope version.
5. **The skyline must always be present.** The city never collapses to an empty skybox.

## Motion tiers (victims are players and bots)

| Tier | Used by | Mechanism | Physics |
|---|---|---|---|
| A. Kinematic vector path | Most hits | Server-planned segments: launch vector, gravity, drag, spherecast collisions (wall slam, ground slide), server-clock start time | Off |
| B. Teleport fake | Only the highest-level physical hits (map-crossing, "Mach" speeds) | The current HitHandler teleport, masked by hitstop and dust | Off |
| C. Physics hand-off | Chosen moments | Short physics window, then freeze or stand up. Ragdolls are custom and triggered on purpose. | On, briefly |

- **Victim influence (owner, 2026-10-19).** Strong players can redirect mid-flight. Pure server-anchored playback is therefore not enough. The planned model:
  - The server sends the planned path and its timeline.
  - The victim's client plays the path and may apply bounded steering inputs.
  - The server validates each input (speed and angle caps, cooldowns), then re-broadcasts the corrected path, so other clients follow the server's version.
  - Exact authority split: still open. It must stay exploit-resistant.
- **Player character:** automatic ragdoll states are disabled (`src/client/PlayerMovement.luau`, implemented). Gameplay triggers ragdolls on purpose.
- **Dummy:** an always-on-top marker, and key G summons it in front of the player (`src/client/DummyTracker.luau`, implemented).

## Destruction: three core types

1. **Physical attack.** A CSG carve plus spawned debris and dust; some debris may use physics briefly. Today's HitHandler cylinder is a first version.
2. **Beam.** Pure CSG carving with no physical debris. Examples: Hollow Purple, a perfect-sphere erase, Jogo's head beam, lasers.
3. **Slice (Sukuna-style).** A plane cut, which is also a building block for other destruction:
   - **Making collapses look right.**
   - **Dropping a target through floors.** A "destruction actor" slices the floor under the target so it falls through by the time the hit delay ends.

### Slice collapse sequence (simplified)

1. A plane cut splits the building into an upper and a lower half.
2. The upper half follows a vector with mimicked gravity. No Roblox physics is involved.
3. When it meets the lower half, its collision turns off and it keeps moving along its path, slowing down. It passes through the lower half.
4. Its path ends when the top of the upper half drops below the top of the lower half.
5. Throughout, debris and dust spawn everywhere.
6. At set points, whole levels of the upper half are deleted until it is gone. Only the generated debris remains.
7. Realistically, the top of the lower half also takes CSG or destruction damage.

### Structure

- Each building has a logical cell grid: floors × footprint cells, plus the core.
- After any cut, a support check runs. Sections no longer connected to the ground fall as seeded, vector-driven events.
- A core-capacity check decides when a whole building collapses. No collapse is triggered just because one beam is gone.

## Multiplayer timing

- **One server timeline per hit,** sent on one reliable remote with sequence numbers. It holds:
  - the victim's path segments, timed with `workspace:GetServerTimeNow()`;
  - the time each wall or floor breaks;
  - the debris seed;
  - collapse and slice events.
- **Clients apply visual changes at the scheduled times.** The server's collision changes land at the same scheduled times, so no player sees a ghost wall or passes through an unopened one. Debris looks identical everywhere because of the shared seed.
- **A 60–120 ms hitstop hides latency.** It replaces the current `YIELD_MASK_DELAY` trick.
- **Holes may finish forming a few tenths of a second after impact**, but only consistently for all viewers. The owner's example: two other players fighting inside a building in the path must see the same timing.
- **Security:** clients send only their attack intent. The server does hit detection and validation. Today's `HitEvent` trusts the client (to fix).

## Rendering and performance

- **Never tear down and rebuild detail around the camera.** The current client upper-facade renderer does this, and it causes jank and lag. To be replaced.
- **Root cause of the missing skyline:**
  - Roblox shortens draw distance on its own when a frame is busy, and developers cannot override it.
  - At about 1.1M instances, laptops cull the far city.
  - Budget target: about 10–25 parts per building near the player, and about 60k parts map-wide.
- **Layers:**
  - **Horizon:** painted skybox skyline, 20–40 edge backdrop meshes, haze.
  - **Block stand-ins:** one merged mesh per block, kept on each client, tucked 1–2 studs inside the real buildings. Damaged blocks swap in damaged stand-ins.
  - **Near buildings:** few parts, with facade detail in textures and shared materials.
- **Streaming stays off.** It cannot refill fast enough at top speeds, and it does not reduce server memory.
- **Hit path cost must depend on nearby geometry only.**
  - The whole-map `GetDescendants` scan costs 2.2 s and must go.
  - Spatial queries use folder Include filters.
  - The dummy launches first; destruction is budgeted per frame.
- **Reference: Flashpoint (Varis Studios).** It reaches extreme speeds over a simple, sparse map of large shapes, and its very top speeds are a different mode. Our equivalent: Mach-level travel uses the teleport fake.

## Open questions

- The authority split for victim steering: exploit-proof, but smooth.
- How cross-map events reach distant players: see the discussion of 2026-10-19 (answer below).
- The visual target for Tokyo upper floors: textures and a reference board first.

## Cross-map events (answer 2026-10-19)

- **Everyone receives every event.** Streaming is off, so the whole world replicates to every client, and timelines go to all clients with FireAllClients. Delivery is about one network round-trip, roughly 50–150 ms, regardless of distance.
- **The hard part is visibility, not data.** Roblox may cull the distant attacker and the buildings. Fixes:
  - Big attacks render as large always-visible effects (a beam is one long glowing part or Beam, not culled the way small parts are).
  - The block stand-ins must show damage, so distant destruction stays visible on the skyline.
- **Reaction time comes from design.** A map-crossing attack needs a wind-up and telegraph: a charge flash visible map-wide, an audio cue, and a HUD direction indicator for incoming threats aimed at you. Hits faster than human reaction must be telegraphed, or they will feel unfair.
- **Cost scales with distance.** Far clients get the same timeline but render reduced effects: fewer debris pieces and no small chunks.
- **Open risk:** server CSG results replicate to every client, including far ones, as mesh data. With many simultaneous fights this needs measuring. Fallbacks: cosmetic CSG on clients plus simplified collision on the server, or a cap on concurrent carving.

## Owner clarifications (2026-10-19, later)

- **Feel:** the game should feel like the anime (the chaos of the Shibuya Incident and the Culling Game) and much faster-paced than other battlegrounds games. A top-tier player can expect to be anywhere on the map, fighting, within about 20 seconds.
- **Teleports:** they come from physical attacks and also from real teleport abilities. Both can arrive anywhere with no warning.
- **Telegraphs:** no long, readable telegraphs for fairness. Balance comes from the natural JJK power system. Hollow Purple and Fuga are effectively undodgeable, with invincibility during their wind-up, as in other JJK games. Characters do not wait for each other's wind-ups. The earlier "telegraph and HUD warning" suggestion is withdrawn.
- **Weaker hardware:** players on weaker hardware must not be trapped at lower levels. Gameplay must never depend on client load speed, and the server owns movement, collision and hits.
- **Measurement pass:** owner-approved. It covers graphics quality levels (which part sizes and counts survive the draw-distance cut) and a test of streaming in a copy of the place: persistent stand-ins, about a 1,000–1,500 stud radius, top speeds, and teleports with and without pre-loading.
- **Working conclusion:** with arrival anywhere at any moment, the whole map must be ready on every client at all times. The preferred route is a lean map (about 60k parts) that fits low-end clients without streaming. Streaming is the fallback if measurement shows memory still too high. Event detail is sent by sector: full timelines near the action, compact ones far away.
