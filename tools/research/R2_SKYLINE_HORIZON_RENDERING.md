# R2: Skyline and horizon rendering for a laptop Shibuya (2026-10-19)

Research only. No code, place or Studio changes. Builds on `SPEED_SKYLINE_STREAMING.md` and
`GAME_DESIGN_DECISIONS.md` and does not repeat them. It also uses facts from `R2_ENGINE_TESTS.md`.

Tags: **[doc]** Creator Hub, **[staff]** Roblox employee, **[community]** non-staff report,
**[est]** my inference, still to be tested.

---

## Executive summary

1. **New lever: `Lighting.PrioritizeLightingQuality = Disabled`.**
   - The July 2025 Unified Lighting announcement says that with this setting, the engine lowers
     lighting quality first "to preserve the quality of other aspects… such as draw distance"
     **[staff]**.
   - This is the only documented setting that trades something else for draw distance.
   - Recommended: `LightingStyle = Realistic` with `PrioritizeLightingQuality = Disabled`. It
     keeps Future lighting near the player with a shorter shading distance.
2. **The draw-distance cut is still undocumented.** It behaves like a visible-object budget.
   - Reports from 2025 say 50–100 parts are enough to cut graphics level 1 to about 200 studs.
   - No staff member has answered.
   - Meshes are reportedly culled by their bounding box, and the cut reportedly centres on
     `Camera.Focus` **[community]**.
   - Big, few objects remain the best bet, but it is unproven.
3. **SLIM and StreamingMesh do not apply.** Both need `StreamingEnabled` **[doc]**, which stays
   off.
4. **Build stand-ins offline, not at runtime.**
   - Runtime EditableMesh has strict client memory budgets. One report saw a limit at about 8
     meshes.
   - `CreateMeshPartAsync` blocks the main thread for about 22 ms per call.
   - EditableMesh is capped at 20k triangles **[doc]**.
   - Per `R2_ENGINE_TESTS.md`, meshes made with EditableMesh do not persist, so stand-ins must
     be uploaded assets.
5. **On damage, don't edit the mesh.** Hide the block's stand-in and show per-building boxes
   made from plain Parts. Parts that differ only in size or colour batch into one draw call
   **[staff]**.
6. **The skybox is the only thing guaranteed at every quality level.** At 1,024 px per face,
   real Tokyo towers 4 km away are only about 40 px tall. The skybox carries the far haze and
   faint towers; the edge meshes and stand-ins carry the actual skyline.
7. **Biggest new risk: the stand-in shows through transparent glass and through damage holes.**
   Hide stand-ins within about 300 studs of the camera.

---

## 1. How the client picks draw distance and culls (2024–2026)

- **Quality level and FRM.**
  - The docs say lower quality reduces render distance. FRM scales "view distance, block count
    and quality level" **[doc]**.
  - No per-level stud table exists.
  - Wingboy0's thread (Apr 2025 to Dec 2025, 100+ likes) has no staff reply. It reports:
    - "50–100 parts… gets reduced to 200 studs at lower settings";
    - at level 1, under 100 studs;
    - an "FRM Blocks/Visible" counter;
    - meshes "culled away based on their bounding box";
    - distance measured from `Camera.Focus` (Nov 2025) **[community]**.
  - Streaming settings do not change render distance (same thread).
- **Unified Lighting (live 23 Jul 2025) [staff].** `Technology` is replaced by
  `LightingStyle` (Realistic/Soft) and `PrioritizeLightingQuality` (not scriptable). Migration:
  Future → Realistic + Enabled, ShadowMap → Soft + Enabled, Voxel → Soft + Disabled. Disabled
  lowers lighting first to keep "draw distance"; Realistic + Disabled is "Future… with a shorter
  shading distance".
  - **Check that this place is not still on Enabled (the Future → Realistic + Enabled
    default).**
- **Occlusion culling [staff, ProgramDude, Apr 2025].**
  - It is software-only and conservative.
  - "Parts that are small on the screen are rejected as occluders early on."
  - Results are not guaranteed, and the heuristics may change.
  - A wall of small parts occludes up close but not far away.
- **Parts vs MeshParts.**
  - No source shows MeshParts outliving Parts of the same size.
  - Two reports say bigger parts survive longer, and the bounding-box claim says the same
    **[community]**.
  - **Studio ignores the quality-level draw distance** since the smooth-camera beta (Jul 2026,
    Studio only). Test only in the live player.
- **`Model.LevelOfDetail` [doc].**
  - Automatic = Disabled.
  - StreamingMesh and SLIM work only with instance streaming. SLIM requires StreamingEnabled
    and suits static models only.
  - With streaming off they do nothing. Skip them.

## 2. Making block stand-in meshes

| Route | Verdict |
|---|---|
| **Offline Blender** (export block Parts → boolean-union or voxel-remesh → decimate → FBX/glTF → importer) | **Recommended for bulk.** The importer does not de-duplicate meshes **[doc]**. The per-mesh limit is 20k triangles **[doc]**. |
| **Studio command bar → EditableMesh → `AssetService:CreateAssetAsync`** (beta, Plugin/Open Cloud context **[doc]**) | Good for exact alignment: geometry comes straight from live Parts, and the result is an uploaded asset. Upload rate limits are unknown, and Open Cloud allows about 20 per day (`R2_ENGINE_TESTS`). Pilot it on 5 blocks. |
| **Runtime EditableMesh on the client** | **Rejected.** Reasons below the table. |
| **Union → mesh in Studio** | No native feature. Use Export Selection (OBJ) and re-import **[community]**. Part colours are lost. |

Why runtime EditableMesh is rejected:

- It has "strict client-side memory budgets" **[doc]**. One user hit a wall at 8 meshes
  **[community, Apr 2026]**.
- `CreateMeshPartAsync` costs about 22 ms plus 0.27 ms per 1k triangles. Baking with
  `CreateDataModelContentAsync` costs about 7 ms plus 3.6 ms per 1k triangles. Both run on the
  main thread **[community, Jul–Sep 2026]**.
- Published games need the Mesh/Image API toggle, and the owner must be ID-verified **[doc]**.
- The meshes do not persist (`R2_ENGINE_TESTS`).

**Budget.**

- Aim for 300–1,500 triangles per block and at most 250 blocks, so about 250k triangles total.
- Each unique MeshId is its own draw call. Plan for 150–250 draw calls.
- The doc says triangle count matters "less than draw call count".

**Updating a stand-in after damage. Order of preference:**

1. **Hide and replace (recommended).**
   - Set the block stand-in's `LocalTransparencyModifier` to 1.
   - Show per-building boxes: plain `Part`s, all SmoothPlastic, colours varied.
   - Part instancing batches parts that differ only in Color or Size, up to about 512 per
     draw call **[staff, zeuxcg 2018]**.
   - Transparency and different Materials break batches.
2. **Pre-made damaged variant.** Use a second uploaded mesh per block for scripted big events
   such as a collapse.
3. **GeometryService carve.** Watertight MeshParts can be carved in about 10 ms per cut
   (`R2_ENGINE_TESTS`). Possible for a few carves, but the per-cut cost adds up during big
   fights.
4. **EditableMesh vertex edits.** Rejected (fixed-size, memory budget, no persistence).

## 3. Custom skyline skybox

- **Faces [doc].** `SkyboxBk/Dn/Ft/Lf/Rt/Up` must fold seamlessly into a cube.
- **Workflow [community, "Custom Skyboxes 101"].** 2:1 equirectangular panorama → cubemap
  tool; pz→Bk, nz→Ft, nx→Lf, px→Rt; rotate Dn 90° CCW and Up 90° CW; bulk-upload via Asset
  Manager.
- **Resolution.**
  - Texture memory scales with pixels **[doc]**.
  - Sources disagree on the maximum upload size. Use 1,024 px per face: about 4 MB each, about
    24 MB for the set.
- **Alignment.**
  - `SkyboxOrientation` is a Vector3 in degrees: Y first, then X, then Z. It is "low-cost" and
    works at every quality level **[doc]**.
  - Set Y once to point the painted landmarks at their true bearings.
  - **The map is mirrored and rotated** (`tile_georef.py`: rotation 181.17°, `mirror_y` true).
    Compute bearings in map space and mirror the panorama to match.
- **Scale (real numbers).**
  - 1 stud = 0.2391 m.
  - The Shinjuku and Roppongi towers are about 240 m tall (about 1,000 studs) and 3.5–4.5 km
    away (15–19k studs). That puts them about 3–4° above the horizon, roughly 35–45 px on a
    1,024 face (about 11.4 px per degree).
  - The skybox horizon sits at the vertical centre of the side faces.
  - Paint the city base 0–20 px below centre and keep skyline detail in the band −2° to +6°.
  - Above that, use Tokyo haze or overcast.
- **Night.**
  - The Sky has no day/night pair. Swap Sky instances by reparenting them, on the client.
  - For a hidden crossfade, a fading dome mesh needs Atmosphere Offset 0 **[community, Jul 2026]**.
  - For the night face, paint lit window dots and red aircraft lights, and lower the haze.
- **Atmosphere [doc].**
  - Properties: Density (particles), Offset (low blends into the sky, high gives a silhouette),
    Haze (horizon and distance), Color, Glare (needs Haze above 0), Decay (needs Glare and
    Haze).
  - "Fog properties are hidden when Lighting contains an Atmosphere."
  - Offset too low causes "ghosting": the sky shows through objects. Offset too high exposes LOD
    popping.
- **Examples.** Duvall Drive hides sightlines and its sky event behind a storm **[doc]**.
  MrChickenRocket's "Modern City Optimized": streaming off, blocker occlusion, distance fades,
  tree impostors, 3–4× fewer triangles. No speed-game write-up was found.

## 4. Backdrop and impostor techniques

| Technique | Cost | Fit |
|---|---|---|
| **Edge backdrop MeshParts** (unique, low-poly) | 1 draw call each, 2–8k triangles. 2,048-stud size cap per axis **[community]** | **Use: 24–32 of them.** |
| Large Part with a skyline `Decal` or `Texture` (alpha card) | Each transparent part gets its own draw call **[staff]**. Overdraw. Unlit look | A second ring only. Must be at least 1,500 studs out. |
| BillboardGui / SurfaceGui images | GUI pass, unlit, sorting problems. No measurements exist | Not for the skyline. Whether the FRM culls them is unknown, so test before use. |
| ViewportFrame "3D skybox" | Own render target per frame. Users report lag at scale. "No longer works (for a number of reasons)" **[community, Sep 2024]** | **Reject.** |
| Terrain silhouettes | Own LOD system, reportedly outlasts parts **[community]** | A cheap fallback for low ridges only. |

## 5. Low-end GPU friendliness

- **Draw calls dominate [doc].** Batching rules **[staff, zeuxcg 2018]**:
  - Parts batch across Color and Size.
  - They split on Material, TextureId and Transparency. Transparent parts each get their own
    draw call.
  - Turning on Outlines disables part instancing.
- **MeshParts batch** when they share a MeshId and texture or SurfaceAppearance. Colour does not
  break batching **[doc]**.
- **Materials.** Far layers: one material (SmoothPlastic). Textures ≤512, mostly ≤256 **[doc]**.
- **Shadows.**
  - `CastShadow = false` on stand-ins, backdrops, dressing and small parts **[doc]**; shadows
    are off below quality 4 anyway.
- **RenderFidelity.**
  - From memory of the docs (verify): Automatic drops mesh detail at about 250 and 500 studs.
  - Stand-ins live past 500 studs and are already low-poly, so set them to **Precise**. That is
    safe at 250 meshes. The doc's warning is about using Precise on too many meshes.
- **Lighting technology.**
  - Voxel is "the best performing option on low end" **[staff, 2020]**.
  - Future falls back to ShadowMap, then Voxel, on devices that lack support **[staff]**.
  - Recommended: **Realistic + `PrioritizeLightingQuality = Disabled`**. If profiling on an
    Iris Xe laptop shows lighting is expensive, use **Soft + Disabled** (the old Voxel setting).
- **Indoor ambient [doc + community].**
  - `Ambient` lights areas hidden from the sky. While every channel of Ambient stays at or below
    OutdoorAmbient, it affects only those occluded areas.
  - Interiors (the generated floors, fights inside buildings) need Ambient around 85–100 grey,
    not black.
  - Brighten with ExposureCompensation, not Brightness.
  - Walls should be at least 1 stud thick to stop light leaks.

---

## Recipe for this map

**Lighting (set in Studio; these properties are not scriptable)**

- LightingStyle = Realistic, PrioritizeLightingQuality = **Disabled**, GlobalShadows = true.
- Ambient = (90, 92, 98), OutdoorAmbient = (128, 130, 138).
- EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.5, ExposureCompensation = 0.2.
- Day: ClockTime 14.5. Night: 21.0.

**Atmosphere (day; starting values, tune live)**

- Density 0.33, Offset 0.15, Haze 1.8, Glare 0.3.
- Color = the sampled skybox horizon pixel (about 199, 205, 214, a grey-blue Tokyo haze).
- Decay = (106, 112, 125).
- Target: the stand-ins at the map edge are about 70–80% hazed, so they merge into the skybox
  band.

**Atmosphere (night)**

- Density 0.38, Haze 1.0, Glare 0.
- Color = (40, 44, 60).
- Use the night Sky, with OutdoorAmbient lowered to about 70.

**Skybox**

- 6 faces at 1,024 px; day and night sets.
- Skyline band from −2° to +6° (about 23 px below centre to 68 px above).
- Real-bearing landmarks: Shinjuku, Roppongi Hills, Tokyo Tower.
- `SkyboxOrientation.Y` aligns the skybox to the georeferenced map, with the mirror applied.
- `CelestialBodiesShown`: true by day, with SunAngularSize 11. Moon only at night.

**Edge backdrop ring**

- 28 MeshParts, 400–1,500 studs beyond the playable edge.
- Each 600–1,600 studs wide (under 2,048 on every axis), 60–450 studs tall.
- 2–6k triangles each, about 120k in total.
- Vertex-coloured or one shared 1,024 atlas, with darker tones lower down. No lights.
- Set every one: `CastShadow`, `CanCollide`, `CanQuery` and `CanTouch` all false; Anchored;
  `CollisionFidelity = Box`; `RenderFidelity = Precise`.
- Add a ground "skirt" ring at street height that extends 1,500 studs outward, so airborne
  players don't see the ground end.

**Block stand-ins**

- At most 250 meshes, 300–1,500 triangles each, at most 250k triangles in total.
- Uploaded assets (FBX/glTF), kept in ReplicatedStorage and cloned into a client folder.
- Same flags as the backdrops, with one colour per block.
- Inset 1.5 studs inside the shells. Roofs 1.5 studs lower.
- Keep normals outward and `DoubleSided` off. From inside a building, the back faces are culled,
  so a player in a room can't see their own block's stand-in **[est, verify]**.
- **Near-hide:** every 0.25 s and on every teleport, set `LocalTransparencyModifier = 1` on the
  stand-ins for blocks whose AABB is within **300 studs** of the camera, and show them again
  beyond **400 studs**.
  - This touches at most a few dozen parts per tick.
  - Nothing is destroyed or rebuilt, so it does not break the no-teardown rule.
  - It fixes stand-ins showing through glass.
- **Damage:** on the first `DustEvent` that hits a block, hide its stand-in and spawn its
  per-building box kit: plain Parts, SmoothPlastic, about 1–4 per building. Damage never makes a
  stand-in more detailed; it only steps down a level.

**Budgets (low-end laptop, all layers)**

| Layer | Draw calls |
|---|---|
| Edge backdrops | ~30 |
| Block stand-ins | ~250 |
| Box kits | ≤20 |
| Near city | ≤200 |
| **Total** | **≤500** |

- Far layers under about 400k triangles. Skyboxes about 48 MB for both sets.

**Camera**

- At high speed, keep `Camera.Focus` on the character. Don't let it lag behind, since the cut may
  centre on Focus **[community]**.

---

## Risks to test (live player only; Studio ignores quality-level draw distance)

1. **Do the stand-ins survive the cut?**
   - Place 250 stand-ins plus the 27k near parts.
   - Record the furthest stand-in still visible at graphics 1, 3, 5 and 10 and at Automatic,
     once with `PrioritizeLightingQuality` Enabled and once with it Disabled.
   - If they don't survive at level 1, only the skybox and haze are left. The fallback is a
     prompt to raise the graphics setting.
2. **Glass see-through and damage holes.** Check the near-hide radius against the facade
   glass, and make sure the box kits line up with the carved buildings.
3. **Skybox horizon mismatch for airborne players** at 300–800 studs up: the ground edge,
   the skirt and the painted base.
4. **Atmosphere ghosting** at Offset 0.15: does the sky show through the stand-ins? The Haze
   colour must match the skybox, both by day and at night.
5. **Back-face culling from inside buildings**, and any z-fighting between the 1.5-stud inset and
   thin wedge crowns.
6. **Interior brightness** at Ambient 90 with Realistic and with Soft, on an Iris Xe laptop:
   FPS and Shift+F2 draw calls.
7. **The `CreateAssetAsync` pipeline:** rate limits, ID verification, and whether the uploaded
   meshes replicate and persist.

---

## Sources

- Unified Lighting live (staff, 2025): https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512
- Technology enum (deprecated): https://create.roblox.com/docs/reference/engine/enums/Technology.md
- Low-graphics render distance thread: https://devforum.roblox.com/t/improve-or-prioritize-render-distance-at-low-graphics-levels/3596299 (and `?page=2`)
- Occlusion heuristics (staff): https://devforum.roblox.com/t/robloxs-occlusion-culling-fails-if-the-camera-is-further-away/3599699
- Studio ignores quality distance (2026): https://devforum.roblox.com/t/infinite-rendering-distance-regardless-of-set-quality-level-in-both-edit-and-playtest-mode/4764473
- ModelLevelOfDetail: https://create.roblox.com/docs/reference/engine/enums/ModelLevelOfDetail.md
- SLIM: https://create.roblox.com/docs/workspace/streaming/slim ; https://about.roblox.com/newsroom/2025/12/introducing-roblox-slim-scalable-lightweight-interactive-models
- EditableMesh: https://create.roblox.com/docs/en-us/reference/engine/classes/EditableMesh.md
- EditableMesh client budget: https://devforum.roblox.com/t/editablemesh-restrictions/4566101
- CreateMeshPartAsync cost: https://devforum.roblox.com/t/allow-applying-baked-mesh-content-to-a-meshpart-without-a-lag-spike/4752538
- CreateAssetAsync: https://create.roblox.com/docs/reference/engine/classes/AssetService ; https://devforum.roblox.com/t/beta-lua-asset-creation-for-creator-tooling-with-createassetasync/3294134
- Mesh specs (20k triangles): https://create.roblox.com/docs/art/modeling/specifications
- Union → mesh: https://devforum.roblox.com/t/union-mesh-conversion-feature/209825 ; https://devforum.roblox.com/t/how-to-optimize-25k-unions/3596452
- Performance (draw calls, instancing, shadows, textures): https://create.roblox.com/docs/performance-optimization/improve
- Part Instancing (zeuxcg 2018): https://devforum.roblox.com/t/130333
- Rendering Updates 2017 (clusters): https://devforum.roblox.com/t/rendering-updates-september-2017/54148
- Mesh instancing Q&A: https://devforum.roblox.com/t/does-roblox-use-mesh-instancing/399564
- Skybox: https://create.roblox.com/docs/environment/skybox ; Custom Skyboxes 101: https://devforum.roblox.com/t/custom-skyboxes-101/2849003
- Skybox transition: https://devforum.roblox.com/t/skybox-transition-module/4751749 ; fake skyboxes: https://devforum.roblox.com/t/how-can-i-make-fake-skyboxes/3167434 ; 3D skybox module: https://devforum.roblox.com/t/a-free-dynamic-3d-skybox-module/789302
- Atmosphere: https://create.roblox.com/docs/reference/engine/classes/Atmosphere.md ; https://create.roblox.com/docs/environment/atmosphere
- Lighting / indoor: https://create.roblox.com/docs/environment/lighting ; https://create.roblox.com/docs/tutorials/building/environments/enhancing-indoor-environments ; https://devforum.roblox.com/t/large-scale-lighting-is-inconsistent/4231644
- Future fallback / Voxel on low end (staff): https://devforum.roblox.com/t/future-is-bright-phase-3-released/878634 ; https://devforum.roblox.com/t/an-update-on-future-is-bright
- Billboards vs meshes: https://devforum.roblox.com/t/low-poly-model-vs-billboard-gui/3099387 ; ViewportFrame cost: https://devforum.roblox.com/t/how-much-do-viewport-frames-affect-performance/376225
- Texture specs: https://create.roblox.com/docs/art/modeling/texture-specifications
- Duvall Drive: https://create.roblox.com/docs/resources/the-mystery-of-duvall-drive/construct-the-house
- Modern City Optimized (Vis Tools): https://www.roblox.com/games/13642139821
