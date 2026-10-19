# Speed, skyline and streaming: keeping a distant Shibuya on screen at extreme speed (2026-10-19)

Research only. This document changes no code, place or Studio settings. It does not repeat
`ROBLOX_ENGINE_SCOPING.md`, `AAA_OPEN_WORLD_TECHNIQUES.md` or `OPTIMIZATION_RESEARCH.md`.

Tags: **[doc]** Creator Hub, **[staff]** Roblox employee, **[community]** non-staff report,
**[analysis]** frame or tech analysis, **[est]** my inference, still to be tested.

---

## 0. Diagnosis for this place

`workspace.StreamingEnabled` is **false** (`tools/SHIBUYA_LIVE_STATE.md`). Every part is
already on the client, so streaming is not why the skyline disappears. The cause is the
**client's quality-dependent draw distance**, which the engine shrinks when there are too many
visible objects or the frame rate is low. Measured resident sets are about 10.8k parts within
500 studs and 27.3k within 1,000. On a laptop running Automatic graphics, that density alone is
probably enough to pull the draw distance in to a few hundred studs **[est]**.

---

## 1. Why distant Roblox parts vanish

**What is documented:**

- **QualityLevel [doc]:** "As QualityLevel increases, Roblox rendering engine increases the
  rendering distance…", and on low levels "objects that are far away will not be rendered".
  The doc also says these effects "are platform- and device-specific and can not be relied
  upon". No studs-per-level table is published.
- **The frame rate manager (FRM) scales draw distance dynamically [doc].** The
  `FramerateManagerMode` enum says FRM scales "view distance, block count, and quality level" to
  meet frame-rate targets.
- **Draw distance also drops when frame rate drops [doc].** The Frustum Streaming page says:
  "If graphics quality drops or frame rate is low, the engine reduces draw distance."
- **Hard far plane:** raised from about 5k to **100k studs** in Dec 2017 **[community]**.
  stravant, who has since joined Roblox staff, explained in 2020 that depth-buffer precision is
  the reason for the cap.

**The mechanism, from community reports (no staff confirmation):**

- **It is a visible-object budget, not a fixed radius.**
  - Wingboy0 (Apr 2025) found that at graphics level 1, about **50 basic blocks** are enough to
    hit an internal "FRM Blocks/Visible" limit. The draw distance then drops to about
    **200 studs**, whatever the triangle count or draw-call count.
  - Developers who need long sightlines say over half of their players can't see distant
    objects, and they ask players to raise their graphics setting.
  - No staff member replied in that thread.
- **Part size appears to matter.**
  - A 2017 report says the cull "prioritizes large parts and close parts" and that large parts
    stay visible at every quality level.
  - A 2024 thread fixed parts that vanished below level 10 by making the parts bigger.
  - Treat both as plausible but unverified.
- **The fandom wiki's ~500/700/900/1000-stud figures for levels 1-4** are old and unverified. Do not
  design to them.

**Other factors:**

- **MeshPart vs Part.**
  - Meshes also change detail level with distance (`RenderFidelity`).
  - Occlusion culling rejects small on-screen parts as occluders early. It is a heuristic that
    may not cull, and it works less well when the camera is far away **[staff, ProgramDude,
    Apr 2025]**.
  - I found nothing showing that MeshParts get a longer draw distance than Parts of the same size.
- **Model.LevelOfDetail (StreamingMesh, SLIM)** applies only when streaming is on, and only to
  models that are **streamed out**.
  - StreamingMesh: an untextured, voxel-looking impostor, "designed to be seen at a distance
    (1024 studs away)", with no live in-game updates **[staff, 2020]**.
  - SLIM: higher-quality composites, static models only **[doc]**.
  - Neither one is documented to override the quality-level draw distance. One community member
    *claims* the StreamingMesh impostor "make[s] it visible from far away" **[community,
    unverified]**.
- **Terrain** uses its own level-of-detail system. One report describes "only simplified
  terrain" still showing past the point where parts disappear **[community]**. That suggests
  terrain outlasts parts, but this is unverified.
- **Atmosphere and fog** do not cull anything. They are the tool for hiding the cutoff: tune
  Density and Haze so geometry fades into the horizon colour before the draw distance ends. The
  Duvall Drive showcase masks pop-in with "oversized sky models" (already cited).
- **Developers cannot set QualityLevel or the draw distance.** Both are user settings.
  `UserGameSettings.SavedQualityLevel` can be read, so the game can detect a low setting and
  prompt the player.
- **The only representation guaranteed at every quality level is the skybox.** A custom `Sky`
  is never culled.
- **Studio is misleading here.** In Studio, quality settings currently do not shorten the draw
  distance (bug thread, Jul 2026). Judge the skyline only in the live client, at graphics 1, 3,
  5 and Automatic.

---

## 2. Speed games: what is publicly known

- **Flashpoint:**
  - The game is **FLASHPOINT⚡ (formerly "Flashpoint: Worlds Collide") by Varis Studios**
    (founder LTMB_Dygital). It is a Flash-style speedster game set in "Central City" with races,
    and it ships on desktop, mobile, tablet and console.
  - Fan wikis cite a Speed Force threshold of about **10,000 studs/s**. Fan sites also say the
    map is crossed "in seconds" at top speed and that players clip into "unrendered zones" at
    extreme speeds. All of this is **[community, low reliability]**.
  - **No devlog, DevForum post or developer tweet about its streaming or LOD was found.**
  - My inference **[est]**:
    - At about 10k studs/s no streamer can keep up (Insomniac's Spider-Man loads one 128 m
      tile per second).
    - So Flashpoint must keep its whole city resident on the client, with streaming off or
      Persistent.
    - The city is probably made of few, large, simple shapes and meshes, which is what a
      visible-object budget rewards.
    - The skybox and atmosphere probably cover the horizon.
  - **How to check this in their game:**
    - Open F9 → Memory and run across the map. A constant client instance count means the map
      is not streaming.
    - Shift+F2 shows draw calls and triangles.
    - Drop to graphics 1 and see whether their skyline survives. If it does, it is built from
      large objects or the skybox.
- **The Strongest Battlegrounds, Jujutsu Shenanigans, Heroes Battlegrounds:** I found no
  technical write-ups. These games use **small bounded arenas**, so the whole map sits inside
  the draw distance **[est]**. That is the usual Roblox answer to "fast and always loaded".
- **Speed Simulator, Legends of Speed, Jailbreak:** I found no first-party technical sources.
  Community threads on big maps describe custom chunk loaders or StreamingEnabled with foci.
  Claims about Jailbreak's custom LOD remain **unverified** (as in the earlier document).
- **Takeaway:** the successful games are fast because they **don't stream what the player can
  see**. They keep a cheap world resident and small enough to fit the budget.

---

## 3. GTA V view-dependent streaming vs Roblox

**What GTA V actually does:**

- **A permanent low-detail world.**
  - Districts collapse into single low-poly meshes. Vinewood Hills becomes 2,500 triangles and
    one draw call **[analysis, Courrèges]**.
  - The LOD/SLOD parents have very large `LodDist` values and cover huge extents, so the
    skyline is effectively always resident **[community]**.
  - Distant lights are batched 32×32 quads, so "all the little lights… are real".
- **Position-driven HD streaming.**
  - Each map file has streaming extents (AABBs) that are tested against a focus point by the
    `fwBoxStreamer`. Too many overlapping extents makes parts of the map unload
    **[community]**.
  - The script natives show that the focus has a velocity term (`SET_FOCUS_POS_AND_VEL`), and
    that cutscenes pre-load a scene from a position plus a direction and a radius
    (`NEW_LOAD_SCENE_START`, radius 3-7,000) **[community, decompiled scripts]**.
  - Prioritising in-frustum requests is plausible, but Rockstar has not documented it
    **[est]**. The owner's "frustum plus a few tiles behind" description is a reasonable mental
    model, not a confirmed mechanism.
- **Lower detail at speed, on purpose.**
  - Planes are slowed relative to real-world speeds, and flying uses lower LODs. Pop-in still
    happens.
  - The PC version has a "High Detail Streaming While Flying" option.
  - A character switch takes about 5 s to stream, which is hidden behind a camera animation
    **[analysis]**.

**Roblox equivalents (all require StreamingEnabled):**

| Lever | Control | Limits at our speeds |
|---|---|---|
| `Player.FrustumStreaming` = Automatic/Enabled **[doc]** | Server-only. Automatic turns on for "high velocity while looking in the direction of movement". | Depth is capped at the **client draw distance**. It is **auto-disabled when draw distance ≤ StreamingTargetRadius**, which is exactly the low-end laptop case. No occlusion. Restreams from the centre on fast camera turns. |
| `PredictiveStreamingMode` = Enabled **[doc]** | Prefetches along velocity and heading | Predictions "expire… and are skipped on resource-constrained clients". No speed guarantee. |
| `RequestStreamAroundAsync` / `AddReplicationFocus` | Server-side prefetch of a known destination (the hit landing point) | Yields. Each focus costs about as much as another player. |
| `StreamingIntegrityMode` | Pause, MinimumRadiusPause or Disabled | At thousands of studs/s, the pause mode would freeze players constantly. |
| `ModelStreamingMode` Persistent | Model never streams out | "Overuse may negatively impact performance". Right for one small skyline model only. |
| `LevelOfDetail` StreamingMesh/SLIM | Engine impostors for streamed-out models | Static only, so they break on destruction. Not shown to beat the draw-distance cap. |

**How much control developers really have:** they choose what is resident and add hints. They
**cannot** set the client's draw distance, its visible-object budget or its quality level.
That is why GTA-style "stream what's in view" doesn't help on Roblox at this speed: on a weak
laptop, what's in view is decided by the FRM budget, not by the streamer.

---

## 4. Recommendation for this game

**The principle: three layers that never stream during play.** Draw-distance culling then only
ever removes detail, and the skyline is never left empty.

### Layer A: horizon (guaranteed at every quality level, zero runtime cost)

- Use a custom **Sky** with a Tokyo panorama baked in: the Shinjuku and Roppongi towers beyond
  the map edge, and haze.
- Add a static **backdrop ring** of about 20-40 large MeshParts just outside the map edge. These
  are never destroyed.
- Tune **Atmosphere** so geometry reaches the horizon colour before the expected low-end draw
  distance. Start with Density 0.3-0.4 and Haze 1-2, and match its colour to the skybox horizon.
  The effect: wherever the draw distance falls, the city fades into haze instead of stopping at
  a hard edge.

### Layer B: skyline proxies (client-only and permanent)

- Clone from ReplicatedStorage into a client folder. Client-created instances are exempt from
  streaming, so this stays valid if streaming is enabled later.
- Use one **merged, untextured, roof-stepped silhouette MeshPart per city block**. GTA's
  Little Seoul works the same way.
- **Budget:**
  - **150-250 meshes** for about 2,000 buildings
  - **300-1,500 triangles each**, so **≤250k triangles** in total
  - **≤150 draw calls**, which is part of the roughly 500-draw-call scene budget
- **Every proxy part:**
  - one vertex colour or material per block
  - `CastShadow=false`
  - `CanCollide`, `CanQuery` and `CanTouch` all false
  - Box collision fidelity
  - Anchored
- **Inset each proxy 1-2 studs inside the real building shells.** Wherever the real building
  renders, it hides the proxy automatically through the depth buffer. Wherever the FRM has
  culled the real building, the proxy shows. No swap logic or fades are needed.
- **Destruction:**
  - A carved building would show its proxy through the hole.
  - Fix: on a `DustEvent`, the client hides that block's merged proxy.
  - It then shows per-building **instanced boxes** for the block's surviving buildings: a kit
    of about 4 shared box or tower meshes, scaled per building, so it stays a few draw calls.
- Proxies are never regenerated at runtime. Damage only ever lowers the proxy level.
- **Why large and few:** every report points to the cull being a budget of visible objects,
  weighted by size. A couple of hundred big objects is the shape most likely to survive it
  **[est, must test]**.

### Layer C: near detail, always resident, culled by the engine

- Keep streaming **off** for now, or on with Persistent buildings.
  - At 600 studs/s from a hit, and several thousand studs/s for top players, a 1,024-stud
    target radius refills in about 0.2-1.5 s. That is too slow.
  - FrustumStreaming switches itself off on exactly the laptops we target.
- The win comes from cutting **visible object count**, which is what drives the FRM:
  - textured facade shells (SCOPED_PLAN phase 2)
  - fewer trim parts
  - `CanQuery=false` on dressing
- **Target:** about **10-25 parts per building, ≤60k parts client-wide**. Today there are 27k
  within 1,000 studs.
- **Lower detail at speed (the GTA flying rule):** above about 300 studs/s, small dressing
  (`NoCSG` decoration) is set to `LocalTransparencyModifier=1` with wide hysteresis. Nothing is
  destroyed or rebuilt.
- For the hit, prefetch the known landing point **[already planned]**.

### Test before building (one evening, live client, not Studio)

Place 200 large boxes and 200 matching MeshParts 1-4 km away. Add a terrain block tower and one
SLIM model, with streaming on in a copy of the place. Then:

1. Record the maximum visible distance at graphics 1, 3, 5, 10 and Automatic.
2. Repeat with about 25k small parts near the camera.
3. On one Intel Iris Xe or UHD laptop, record FPS and Shift+F2 draw calls and triangles.

This settles whether part size, mesh type or terrain beats the budget, and how many proxies fit.

**Unverified, so test before relying on it:**

- whether `LevelOfDetail` is script-writable
- the ~20k triangle per-mesh limit
- the 2,048-stud part size cap
- the "stretched mesh bounds" trick (one community member says enlarging a mesh's bounds keeps
  it inside the draw distance, and warns it may break raycasts and physics)
- a terrain-silhouette fallback

---

## Sources

- QualityLevel enum: https://create.roblox.com/docs/reference/engine/enums/QualityLevel.md
- FramerateManagerMode: https://robloxapi.github.io/ref/enum/FramerateManagerMode.html
- Frustum Streaming: https://create.roblox.com/docs/workspace/streaming/frustum
- Instance streaming: https://create.roblox.com/docs/workspace/streaming
- Streaming techniques: https://create.roblox.com/docs/workspace/streaming/techniques
- PredictiveStreamingMode: https://create.roblox.com/docs/reference/engine/enums/PredictiveStreamingMode.md
- ModelLevelOfDetail: https://create.roblox.com/docs/reference/engine/enums/ModelLevelOfDetail.md
- SLIM: https://create.roblox.com/docs/workspace/streaming/slim
- LevelOfDetail beta (meshadapt, 2020): https://devforum.roblox.com/t/662464
- Updates to Streaming Enabled (2023): https://devforum.roblox.com/t/updates-to-streaming-enabled/2391960
- Low-graphics render distance (Wingboy0, 2025): https://devforum.roblox.com/t/improve-or-prioritize-render-distance-at-low-graphics-levels/3596299
- Occlusion heuristics (ProgramDude, staff, 2025): https://devforum.roblox.com/t/robloxs-occlusion-culling-fails-if-the-camera-is-further-away/3599699
- Far-plane cap (stravant, 2020): https://devforum.roblox.com/t/remove-arbitrary-draw-distance-limit/484282
- Size and distance culling (2017): https://devforum.roblox.com/t/things-far-away-not-loading/64088
- Bigger parts survive (2024): https://devforum.roblox.com/t/parts-disappearing-when-graphics-lower-than-10/3182825
- Render distance and StreamingMesh (2023-25): https://devforum.roblox.com/t/how-do-you-increase-render-distance/2517020
- Studio ignores quality distance (2026): https://devforum.roblox.com/t/infinite-rendering-distance-regardless-of-set-quality-level-in-both-edit-and-playtest-mode/4764473
- Simplified terrain at distance: https://devforum.roblox.com/t/nothing-renders-from-a-distance-in-game-or-in-test-mode/3948840
- Flashpoint: https://www.roblox.com/games/13796645198/FLASHPOINT, https://flashpoint.wiki/exploration/roblox-map-size/, https://www.pockettactics.com/flashpoint-worlds-collide/codes
- GTA V Graphics Study pt. 2: https://www.adriancourreges.com/blog/2015/11/02/gta-v-graphics-study-part-2/
- GTA natives: https://github.com/citizenfx/natives/blob/master/STREAMING/SetFocusPosAndVel.md, https://github.com/citizenfx/natives/blob/master/STREAMING/NewLoadSceneStart.md
- fwBoxStreamer extents: https://www.gta5-mods.com/tools/ymap-load-list-extent-limit-fix-fwboxstreamervariable-patch, https://forum.cfx.re/t/lod-slod-texture-issues/5074672?page=2
- RDC 2025 roadmap (SLIM, 64K terrain): https://devforum.roblox.com/t/creator-roadmap-2025-rdc-update/3961527
