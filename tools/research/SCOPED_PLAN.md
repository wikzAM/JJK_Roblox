# Scoped plan: AAA techniques → Roblox → this game (2026-10-19, discussion draft)

This draft synthesizes two research files: `AAA_OPEN_WORLD_TECHNIQUES.md` and `ROBLOX_ENGINE_SCOPING.md`. No code has been changed for this plan.

## What we got wrong

The facade system acted like a streaming engine on top of Roblox. It created and destroyed detail around the camera. AAA games never do that: every building keeps a permanent cheap version, and detail is layered on or swapped with hysteresis and fades. Roblox already provides native occlusion culling and draw batching. Rebuilding geometry as the camera moves gives no rendering benefit. It only causes the popping and the hitches the owner sees.

## Principles for this game (fast, destructible, smoke and mirrors)

1. **The static city is permanent.** No script-driven creation or destruction tied to camera distance. Parts stay put and Roblox culls what is hidden.
2. **Detail lives in materials and textures, not part counts.** Upper floors use tiled window textures on a few large face parts, one per facade face or floor band, in Tokyo-style variants. Interiors are faked, not built.
3. **Merge per building or per block.** Fewer, larger, reused shapes batch well. Thousands of trim pieces do not.
4. **Kinematic by default; physics visits.**
   - Buildings stay anchored forever.
   - The dummy follows a scripted path; physics switches on only for the final tumble, using our own ragdoll (`EvaluateStateMachine=false` plus a BallSocket ragdoll on demand).
   - Debris is spawned on the client and anchored once it settles.
5. **The hit path is O(nearby), never O(map).**
   - Spatial queries use folder or Include filters.
   - Decorative parts get `CanQuery=false`.
   - Launch happens first; destruction is budgeted over frames behind the dust.
6. **Think about speed.** We know the landing point when the hit fires, so we prepare there and keep the far skyline cheap but always present.
7. **Destruction is local and stays visible.** A carved building never reverts. That rules out Roblox's SLIM LOD for anything that can be hit.

## Roadmap (each step measured before the next)

| Phase | Work | Effort | Effect |
|---|---|---|---|
| 1 | Hit path. A: folder-scoped queries, no whole-map scans. B: launch first, budgeted destruction. | hours | Hits go from about 6 s back to about 0.1–0.3 s perceived |
| 1 | Stop the facade churn: upper renderer builds once per session with very wide hysteresis, or is paused | hour | No popping or rebuild hitches |
| 2 | Prototype the textured facade shell on about 10 buildings: one textured part per face or band, 3–4 Tokyo styles, measured | days | Permanent upper facades at a tiny fraction of today's parts |
| 2 | Dummy: kinematic flight plus a custom ragdoll only at the end | days | Removes physics fights and stalls |
| 3 | Ground floors: keep street-level detail, but merge trim, set `CanQuery=false`, and consider shared textured bands | 1–2 weeks | 650k facade parts reduced substantially; Studio memory and save risk drop |
| later | Decide on streaming (owner call; it does not reduce server memory) | — | — |

## Open questions for the owner

1. Is the target PC only, or mobile too?
2. What is the player's top travel speed (studs/s)?
3. Which matters more: skyline completeness or close-up detail?
4. Is it acceptable for the hole to finish forming about 0.1–0.3 s after impact, under the dust?

## Update after round 2 (owner answers + research)

Owner answers:
- **Platform:** PC that runs on ordinary laptops, maybe console. Mobile would be a separate, smaller version.
- **Speed:** top players cross the map end to end in seconds.
- **Skyline:** must always be present.
- **Holes:** may finish forming a few tenths of a second after impact, provided multiplayer timing stays consistent.
- **Attacks:** most move victims in real time along vector paths. Only the strongest use the teleport fake.
- **Players:** victims are players and bots; the dummy is a stand-in for them.
- **Collapse:** structural collapse should be faked.

Research files: `SPEED_SKYLINE_STREAMING.md` and `COMBAT_MOTION_DESTRUCTION_SYNC.md`.

### Why the skyline disappears (root cause)

`StreamingEnabled` is already off, so streaming is not the cause. Roblox's client shortens its draw distance on its own when the frame is too busy or the frame rate is low. Developers cannot change a player's quality level or view distance. With about 1.1M instances, ordinary laptops hit that limit, so the far city disappears.

The part count is therefore the skyline problem, not only a performance problem. The research's laptop budget is about 10–25 visible parts per building and about 60k parts map-wide. That is roughly 10 to 20 times fewer than now.

### Revised architecture

- **Horizon:** paint a Tokyo skyline into the skybox, ring the map edge with 20–40 large backdrop meshes, and tune the haze so the city fades out.
- **Skyline stand-ins:** one merged mesh per block, 150–250 meshes, at most about 250k triangles, kept on each client. Each stand-in sits 1–2 studs inside its real buildings. The real geometry hides it up close; where the real geometry has been culled, the stand-in shows. A damaged block swaps its mesh for per-building boxes.
- **Near detail:** keep streaming off; it cannot refill at these speeds, and frustum streaming disables itself on low-end machines. Bring each building down to about 10–25 parts by moving facade detail into textures and shared materials, and hide small decoration above about 300 studs/s.
- **Victim motion:** the server anchors the victim and plans kinematic segments (fly, slide, wall pin, teleport fake) with spherecasts. Each segment carries a server-clock start time, and every client evaluates the same function. A 60–120 ms hitstop hides latency. Physics is handed back only at the end.
- **Hit timeline:** one per hit, sent on a reliable, sequenced remote. It holds the path, the time each wall breaks, and the debris seed. Clients open walls locally at the break time, and the server's carve replaces the local version when it arrives.
- **Structure:** a logical cell grid per building. Unsupported sections fall, and a core-capacity check decides collapse. Collapses are seeded, vector-driven events.
- **Security:** clients send attack intent only. The server does hit detection; today's `HitEvent` trusts the client.

### First step

Spend one evening testing a live client at several quality levels. Record which part sizes and types survive the draw-distance cut, and what the part count per building has to be on a laptop. Every later budget depends on this measurement.
