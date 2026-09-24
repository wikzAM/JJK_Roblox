# Facades and glass — roadmap

Sept 24. Builds on the facade subagent's design (client-side facades, capsule damage log,
LOD, streaming). What is **built and tested**, what is **next**, and the **decisions that are
yours**. Every number here was measured on this map, not assumed.

## Where it stands

**Built (v1), tested in a Play session, committed:**

| piece | file | what it does |
|---|---|---|
| layout | `src/shared/FacadeLayout.luau` | plan → glass strips, piers, parapets; styles |
| renderer | `src/client/FacadeRenderer.luau` | builds near the camera, pools, breaks glass |
| hit hook | `src/server/HitHandler.luau` | fires `FacadeHitEvent(start, end, radius)` beside the CSG |

- **The look:** the slabs' edges already read as spandrel bands, so a facade is one glass strip per
  wall run per storey, set 0.6 studs back between the slabs. Runs under 6 studs become opaque piers.
  Where the storey above sets back, the run becomes a 3.5-stud parapet instead of open-topped
  glass. Six tinted styles (blue-grey, green-grey, bronze, dark, silver, blue), chosen by a hash of
  the building id, so every client agrees.
- **Cost:** 2,231 buildings, 4.6 storeys each, 13.3 wall runs per storey → **~109k strips
  map-wide**. The renderer builds only within 700 studs (drops past 850): **87 buildings / 5,624
  parts at the Scramble Crossing, built in under 5 s**, on a 2 ms/frame budget, paused above
  400 studs/s. **Zero parts are saved into the place.**
- **Glass breaking:** the server fires the same capsule the CSG carves. Each client splits the
  strips it touches into ~12-stud panes: removed inside the radius (with 3 local shards each, gone
  after 4 s), cracked (whitened, more transparent) in the next 6 studs, intact beyond. A client
  re-applies its earlier hits when a building re-enters range. Tested: one hit cracked 9 panes and
  threw 16 shards; no console errors.

**Where I departed from the subagent's plan, and why:**

- **No per-run "backing" part and no spandrel texture.** Its strategy B was about 70 parts per building.
  Our slabs already draw the spandrels, so glass-only is ~28 per building (median) and looks
  right up close.
- **Material, not Textures, for glass.** Textures need uploaded image assets (mullions, cracks).
  `Glass` material with tint and reflectance needs none and reads well. Textures are a later polish
  step (see decision 2).
- **Four glass states became three** (intact, cracked, gone). "Broken but present" and "cracked"
  look the same without a crack texture.

## Next, in order

1. ~~**Far shells.**~~ **DONE Sept 24.** `FacadeLayout.BuildFarCoarse`: storeys in 5-storey bands,
   each band one ring of tall panels from its bottom floor's outline (edges merged up to 15°, runs
   under 8 studs dropped), opaque SmoothPlastic in the building's tint (Glass is the costly material
   to render). **22,201 parts for the whole map, ~11 per building**, built once at startup under the
   frame budget, never unloaded, hidden while a building's near facade is up. Tested in Play: near
   106 buildings / 6,271 parts, far 1,963 / 20,954, none shown twice, no errors. (Merging the near
   strips exactly where a run repeats kept 87% of them -- level-curve outlines shift every floor --
   hence the coarse bands.)
2. **Late joiners see old damage.** Right now each client only knows hits it saw. The server keeps a
   capped log per building (the subagent's `FacadeHits` attribute: start, end and radius, ~32 events,
   merged beyond). The client replays it on build. About a day's work, and no new parts.
3. **Collapse compatibility.** Facades are client-only, so when the server changes a building (the
   collapse system, a `Regenerate`), clients must drop and rebuild that building's facade. The simplest
   hook: a `FacadeVersion` attribute the server bumps, which the renderer watches. Do this before the
   collapse system lands, not after.
4. **More things that break glass.** Only the main hit capsule breaks glass today. The flung
   body's ground-skid and wall impacts (`trackGroundContacts`) should fire small capsules too.
5. **Storefront ground floors.** Unblocked (Sept 24): the ground now sits a median 1.9 studs under
   the ground-floor slab tops (it was 9.3 -- the terrain had never been rewritten after the part
   ground went). It rises above a slab top on 4% of edge samples: the uphill side of buildings on
   slopes. The subagent's plan fits as-is: glass sill at slab top + 2, a buried kickplate below it,
   and a per-run sill raise where the ground is higher.
6. **Performance pass.** Measure client memory with and without facades on a real client, not
   Studio. Studio's 3.5 GB includes the server. Tune `BUILD_RADIUS` against it.
7. **Streaming** (the subagent's section 3) stays deferred. `StreamingEnabled` is still off. Revisit
   only if client memory forces it; the far shells in step 1 are the precondition anyway.

## Decisions that are yours

1. **Glass sound.** Shattering is silent. It needs a sound asset: one from the Creator Store, or your
   own upload. I can search the Creator Store for candidates if you want.
2. **Textures.** Mullion lines, reflections, and a proper cracked-glass look need 2–3 uploaded image
   assets. They're worth it for close-up fights, and not needed for the city at a distance.
3. **Landmarks.** Right now *every* source-slice building gets generic glass, the Cerulean included.
   Should hand-designed landmarks be excluded (a `Landmark` tag) and get bespoke facades later?
4. **Can players stand on the facade?** Glass collides for the local player today, so you can't walk
   through windows. If traversal should pass through buildings freely, set `CanCollide = false` on
   facade parts. That's one line in `FacadeRenderer.acquire`.

## Related optimisation, for scale

- **Ring simplification** (`tools/source_slice_simplify.py`, gated, not applied) saves **~33,200
  slab parts, about 11.5% of the map**, and needs a rebuild of every building. That's the biggest
  single part cut still on the table. (An earlier note said 15%; that counted perimeter walls, which
  don't exist.)
- Roads are now **3,590 parts** (from 8,305). Nothing more to win there.
