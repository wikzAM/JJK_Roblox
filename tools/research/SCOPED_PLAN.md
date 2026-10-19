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
