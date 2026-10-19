# Night lighting, glow, glass and sign costs (research wave 3, 2026-10-19)

> **Measured correction (`R2_ENGINE_TESTS.md` T8):** hiding all 47k glass panes changed draw calls by at most 2. The 2018 "one draw call per transparent part" claim below does not hold today. Glass costs render CPU (up to about 7.5 ms from the air) and hides particles, beams and GUIs behind it. Those reasons still support baking distant glass.

Scope: how to make night-time Shibuya (Halloween 2018) look lit and dense on an Intel Iris Xe / 8 GB laptop, with streaming off and a low-tier target of **≤ 500 draw calls**. This builds on `GAME_DESIGN_DECISIONS.md`, `R2_TOKYO_FACADE_ART_DIRECTION.md` (night look: "the anime reads Shibuya through its lights, not its walls"), `R2_SKYLINE_HORIZON_RENDERING.md` (lighting recipe) and `R2_FACADE_BAKING_PIPELINE.md` (alpha section). Research only; no game code was changed.

Tags: **[doc]** Creator Hub, **[staff]** Roblox staff post, **[community]** non-staff DevForum report, **[est]** my estimate or inference, **[local]** measured or read in this repo.

## Summary

1. **Glass is the biggest problem, not lights.** The city has 46,128 `GlassPane` parts ([`R2_CITY_INVENTORY.md`]) **[local]**. They use `Material.Glass` with `Transparency` 0.10–0.20 (`src/shared/FacadeLayout.luau` lines 38–43) **[local]**. Roblox staff have said that each transparent part is drawn in its own draw call ("force a single instance per draw call for each transparent part") **[staff, 2018]**. A few thousand panes on screen can therefore use up the whole 500 draw-call budget by themselves. Glass also hides every transparent thing behind it: dust particles, beams, world GUIs, and other transparent parts **[staff]**. **Recommendation:** make all distant glass opaque by baking it into the facade skin. Keep real transparent glass only on the near, damaged, or occupied building.
2. **Lit windows and signs at a distance should come from emissive surfaces, not lights.** Emissive masks went live on 2026-02-12 for `SurfaceAppearance`, `MaterialVariant` and `TerrainDetail`. Staff say they "appear at all quality levels" and "won't fade out in far distances" **[staff]**. `Decal` and `Texture` still have no emissive *mask* **[doc]**. A probe in this repo found an undocumented `Texture.EmissiveStrength` property **[local]**, which needs a visual test.
3. **Local lights are for the street near the player only.** Use about 40–60 static, unshadowed lights within roughly 220 studs, with range 24 studs or less. Use 0–2 shadowed lights, and only in the Realistic style. A light only lights nearby surfaces, so a distant light adds nothing to the skyline anyway.
4. **Sign GUIs cost more than they look.** Each SurfaceGui/BillboardGui is a full UI container, and staff call SurfaceGuis "more costly to render" than decals **[staff]**. Signs beyond the near ring should be cheap opaque Neon blocks or emissive sign cards, not GUIs.
5. **The place currently uses `LightingStyle = Soft`, `PrioritizeLightingQuality = false`** (`R2_ENGINE_TESTS.md` T6) **[local]**. That is the old Voxel mode, which is the cheapest and has the softest light pools. Whether to move to Realistic is a measurement question (§7).

---

## 1. Light sources (PointLight, SpotLight, SurfaceLight)

### How the lighting styles map to the old engines
- In Unified Lighting (live July 2025), `Technology` is replaced by `LightingStyle` (Realistic or Soft) and `PrioritizeLightingQuality`. Neither can be set from a script. Old settings migrate as Future → Realistic + Enabled, ShadowMap → Soft + Enabled, and Voxel → Soft + Disabled. Realistic + Disabled is described as Future with a "shorter shading distance". With Disabled, lighting quality is lowered first "to preserve the quality of other aspects… such as draw distance" ([Unified Lighting](https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512)) **[staff]**.
- Staff gave no light-count numbers. They said only that "performance will not degrade" after the switch (same post) **[staff]**.

### What a light costs
- **Voxel grid (all styles, and the only local lighting in Soft).** Lights are written into a 4×4×4-stud voxel grid on the CPU. That is why Soft-mode light pools look blocky and leak through walls thinner than one voxel ([wiki summary](https://roblox.fandom.com/wiki/Future_Is_Bright), [GDC 2020, zeux](https://zeux.io/data/gdc2020_pvr.pdf)) **[community]**.
  - The voxel cost of one light grows roughly with the cube of its range. A static light costs little once it has been written into the grid; moving or flickering lights cost more ([range thread, posts 199/202](https://devforum.roblox.com/t/increase-range-limit-of-lights/68336?page=10)) **[community]**.
  - So in Soft mode, **range is the cost driver, not count**. Halving the range costs about one-eighth as much **[est]**.
- **Per-pixel lights (Realistic only).** Near the camera, Future/Realistic shades local lights per pixel. "Per-pixel lighting distance depends on the current quality level" ([FIB Phase 3](https://devforum.roblox.com/t/future-is-bright-phase-3-released/878634)) **[staff]**.
  - Per-pixel lights and shadowed lights are both capped per frame. Staff's rule of thumb: "have as few local lights as possible" (same post) **[staff]**.
- **Shadows.** Shadowed lights cost much more than unshadowed ones.
  - Cheapest to most expensive: a narrow spot light (under 120°), then a surface light, then a point light, which is the most expensive "by a margin" (FIB Phase 3) **[staff]**.
  - Creator Hub: shadow casting is expensive, so use fewer lights, limit range and angle, turn off `Light.Shadows`, and "disable lights outside a given range" ([Improve performance](https://create.roblox.com/docs/performance-optimization/improve)) **[doc]**.
  - **Shadows are disabled entirely below quality level 4** (same page) **[doc]**. Below level 4, the engine falls back to voxel shadows ([wiki](https://roblox.fandom.com/wiki/Future_Is_Bright)) **[community]**.
- **Range cap.** The range cap was raised from 60 to 120 studs in September 2025 ([weekly recap](https://devforum.roblox.com/t/weekly-recap-september-22-26-2025/3961633)) **[staff]**. Do not use 120 in Soft mode, because of the cubic voxel cost **[est]**.

### Culling and distance
- No documented distance at which lights stop drawing. Quality level scales "rendering distance, shading quality…" and individual feature behaviour "can not be relied upon" ([QualityLevel](https://developer.roblox.com/api-reference/enum/QualityLevel)) **[doc]**.
- **Open engine bug (July 2026, backlogged September 2026):** lights vanish or flicker when their *parent part* leaves the camera frustum. The light seems to be culled by its parent's bounding box, not by its own range. Workaround: parent the light to an invisible part about the size of the light's range. A 16-stud parent kept a floor lit where a 0.5-stud parent did not ([bug thread](https://devforum.roblox.com/t/spotlights-pointlights-disappear-or-flicker-based-on-camera-orientation/4750431)) **[community; staff acknowledged]**. This matters for small lamp-head parts.
- The MicroProfiler labels to watch are `computeLightingPerform`, `LightGridCPU` and `ShadowMapSystem` ([Improve performance](https://create.roblox.com/docs/performance-optimization/improve)) **[doc]**.

### Iris Xe class GPUs
- I found no Roblox benchmark for Iris Xe. Community reports show slowdowns above about 50 lights in one area, even on a GTX 1050 Ti ([search summary of DevForum reports](https://devforum.roblox.com/t/lighting-optimizations/1073832)) **[community]**.
- Integrated GPUs are usually limited by how many pixels they fill. Per-pixel lights and shadow maps scale with screen area, so expect Realistic to cost noticeably more than Soft on Iris Xe at 1080p **[est]**.
- With `PrioritizeLightingQuality = Disabled` (already set), low quality levels give up lighting first. Laptops in Automatic quality will often sit at level 3–6, so shadows are off and light shading is short-range **[est]**.

**Affordable counts (to verify in §7):** in Soft mode, about 40–60 static unshadowed lights in view with range ≤ 24. In Realistic mode, the same plus 0–2 shadowed narrow spot lights, and only for short-lived attack flashes **[est]**.

## 2. Neon and emissive options

| Option | Status in 2026 | Cost | Survives low quality? | Good for |
|---|---|---|---|---|
| **Neon material Part** (opaque) | Live | An ordinary opaque part. Material is a batching key; colour is not ([Part Instancing](https://devforum.roblox.com/t/part-instancing-pre-release-announcement/130333)) **[staff]**. So many same-shaped Neon parts in different colours batch together. | Full-bright colour shows at all levels. The glow comes from bloom. Staff traded off "black neon glow" so that low-end devices see neon ([poll](https://devforum.roblox.com/t/unified-neon-and-bloom-poll/180359/31)) **[community]** | Near and mid signs as flat glowing colour, tube lettering, lit-window bands |
| Transparent Neon | Live | Moves the part into the transparent pass (its own draw call), and the glow fades as transparency rises ([glowing windows](https://devforum.roblox.com/t/is-it-possible-to-recreate-glowing-windows-from-old-roblox/3924198)) **[community]** | — | Avoid |
| **SurfaceAppearance emissive** (`EmissiveMaskContent`/`Strength`/`Tint`) | Live 2026-02-12 ([emissives](https://devforum.roblox.com/t/on-hold-emissives/4034414)) **[staff]** | Adds nothing to the mesh's draw calls; the mask is one channel to save memory (same post) **[staff]**. MeshPart only. The mask can be set only at edit time or via `CreateSurfaceAppearance` ([doc](https://create.roblox.com/docs/en-us/reference/engine/classes/SurfaceAppearance.md)) **[doc]** | "Appear at all quality levels", "won't fade out in far distances" **[staff]** | Skyline stand-ins, option-B facade skins, sign cards |
| **MaterialVariant emissive** | Live (same release) | Batches like any material. The tiling origin cannot be controlled (`R2_FACADE_BAKING_PIPELINE.md`) **[doc]** | Same as above **[est]** | Upper-floor window grids where exact alignment does not matter, and thin "glow card" parts |
| Texture/Decal emissive | Not documented. Decal emissive is "planned" alongside PBR decals **[staff]**. `Texture.EmissiveStrength` exists with no mask (T6) **[local]** | — | Unknown | Test only (§7, test E) |
| **SurfaceGui, `LightInfluence = 0` + `Brightness`** | Live. Brightness (0–1000) only works when LightInfluence < 1 ([SurfaceGui](https://create.roblox.com/docs/en-us/reference/engine/classes/SurfaceGui.md)) **[doc]**. Staff tutorial: higher Brightness gives more bloom ([neon signs](https://devforum.roblox.com/t/how-to-create-neon-signs-using-an-image-or-text-label/2910923)) **[staff]** | A full GUI container per sign (§4) | Yes, but hidden behind any Glass **[staff]** | Readable hero signs and screens near the player |
| Beams | Live | Transparent, so hidden behind Glass. They don't cast shadows. There is an undocumented cap on how many draw, which depends on device and quality ([beams](https://devforum.roblox.com/t/do-beams-create-lag/675990)) **[community]** | Partly | A few long light strips (train line, crown edges) |

**Cheapest for thousands of lit windows and signs at a distance:** emissive in the material the building already draws with. This means a stand-in mesh with a SurfaceAppearance emissive mask, which adds **zero** draw calls. Next cheapest: opaque Neon parts in a few shared shapes, which batch with each other. GUIs and beams do not scale to thousands **[est]**.

A Texture drawn on top of a Neon part hides the glow ([glowing windows](https://devforum.roblox.com/t/is-it-possible-to-recreate-glowing-windows-from-old-roblox/3924198)) **[community]**. So "Neon box plus a baked sign texture" does not glow. Use a plain Neon colour, or an emissive SurfaceAppearance.

## 3. Transparency and glass

- **Draw calls.** "We have to force a single instance per draw call for each transparent part". Decal transparency is exempt. Switching a part between zero and non-zero transparency also creates and destroys internal graphics objects ([Part Instancing, zeuxcg](https://devforum.roblox.com/t/part-instancing-pre-release-announcement/130333)) **[staff, 2018]**. A 2024 fix stopped *fully invisible* parts from adding render entities ([thread](https://devforum.roblox.com/t/transparent-parts-increase-render-entities-and-ruins-instancing/2673266)) **[staff]**. Partly transparent parts are still the worst case **[est]**.
- **Overdraw.** Docs say to avoid transparency values "other than 0 (visible) and 1 (invisible)" ([Design for performance](https://create.roblox.com/docs/performance-optimization/design)), because overlapping transparent pixels are drawn several times ([Optimize your experience](https://create.roblox.com/docs/tutorials/curriculums/environmental-art/optimize-your-experience)) **[doc]**. A street of glass shopfronts seen at an angle is exactly this case.
- **Glass material.** Glass uses a multiply blend and refracts only at high quality levels.
  - "Non-opaque objects" are not visible through Glass. These include transparent parts, decals on transparent parts, particles, and world-space GUIs.
  - The rule exists "so refraction wouldn't have a large performance impact".
  - At Transparency 0, Glass is "completely opaque" ([Glass](https://devforum.roblox.com/t/introducing-new-material-glass/64231/1)) **[staff]**.
  - **Consequences for this game:** a hit seen through a window loses its dust (`DustEvent` particles), beams and signs **[est]**.
- **How many transparent parts are affordable:** no official number exists. Treat each visible transparent part as one draw call. Then the low tier can afford about **50–150** in view, after opaque geometry, characters and VFX **[est]**.
- **Convert the 41–46k panes? Yes.**
  - At night, a window is either dark (reflection) or lit (emission). Seeing through it adds little.
  - Bake intact panes into the opaque skin: albedo plus a low-roughness, slightly metallic area in the roughness and metalness maps, so they pick up sky and environment highlights.
  - Lit panes come from the emissive layer.
  - This matches the existing plan in `R2_FACADE_BAKING_PIPELINE.md` §3/§6: intact panes exist only in the texture; a damaged pane gets an opaque overlay; a shattered pane gets a CSG hole plus shards.
  - Keep live Glass parts only for the building the player is inside and its immediate neighbours (no more than about 150 panes) **[est]**.
  - Caveat: in Soft (Voxel) mode, roughness and metalness maps may give weak highlights. Check how they look in test G **[est]**.
- **Cheap middle option if baking is delayed:** set existing panes to `Transparency = 0` (opaque Glass), or SmoothPlastic in the same colour. This takes them out of the transparent pass immediately. Whether opaque Glass still costs extra for refraction or blending is unknown; test G compares it with SmoothPlastic **[est]**.

## 4. SurfaceGui, BillboardGui, Decal and Texture costs

- **Staff position:** SurfaceGuis carry the full UI system and are "more costly to render" than decals. For static images, decals "come with much better performance" ([MaxDistance announcement, 2023](https://devforum.roblox.com/t/new-surfaceguimaxdistance-property/2574715)) **[staff]**.
  - `MaxDistance` (default 1000 for new GUIs; 0 means unlimited) stops rendering beyond that distance and also reduces text flicker.
- **Hidden GUIs used to cost frame time.** With "a few thousand" SurfaceGuis, FPS fell to 10–20 even with a low MaxDistance. `StandardAdorns` and `UpdateUILayouts` dominated the profile.
  - Staff shipped layout skipping for hidden and out-of-range GUIs, rolled out everywhere on **2026-03-17** ([thread](https://devforum.roblox.com/t/surfaceguis-still-consume-a-lot-of-frame-time-even-when-outside-of-maximum-render-distance-or-when-disabled/4289170)) **[staff]**.
  - So `MaxDistance = 220` (current `GroundFacadeKit.luau` line 260) now saves layout work as well as drawing. Bookkeeping per instance and memory per instance remain **[est]**.
- **BillboardGuis:** community tests show 240 FPS dropping to 90–150 FPS, and 120 FPS to 35 FPS, with many billboards on. One reporter said each GUI took one draw call ([search summary](https://devforum.roblox.com/t/whats-the-practical-limit-for-billboardguis-how-many-can-there-be-in-a-scene-before-i-have-to-worry/3958385)) **[community]**. Do not use billboards for signage.
- **Text vs. baked image:** no measurements exist. A TextLabel needs glyph shaping and atlas work. A baked ImageLabel or texture needs one image fetch. Sign text never changes, so bake it **[est]**.
  - Keep TextLabels only where text is dynamic (screens, a score ticker).
- **Decals and Textures:** "don't batch well and introduce additional draw calls" ([Improve performance](https://create.roblox.com/docs/performance-optimization/improve)) **[doc]**. Count about one extra draw call per decal or texture face **[community/est]**.
  - Never stack UV-offset decals on one face: staff explained that each one redraws the whole host surface ([UV offset thread, 2026-09-01](https://devforum.roblox.com/t/decal-uvoffset-uvscale-causes-significant-performance-impact/4802916)) **[staff]**.

**Practical cap:** about 60 sign GUIs active within 220 studs, and a few hundred SurfaceGui instances in the whole place. Everything else is a baked texture or emissive card **[est]**.

## 5. Night recipes from other projects

- **Roblox night city builds** usually use many small Neon "window" parts. Reviewers of a 50k-part, *Akira*-style Roblox night city said it was over-bright and laggy. They suggested glowing gradient textures instead, and fewer lit windows (not every floor) ([feedback thread](https://devforum.roblox.com/t/quick-feedback-on-nighttime-city-build/3108430)) **[community]**. The lesson: light sparsely; real night skylines are mostly dark.
- **Neon tuning:** lower the Neon colour's value, raise its weaker colour channels, and use BloomEffect to shape the glow ([Fix Neon Parts, 2026](https://devforum.roblox.com/t/fix-neon-parts-to-look-amazing-and-realistic/4526920)) **[community]**.
  - That tutorial also fakes light-in-haze with a BillboardGui sprite. It calls this "negligible" in cost next to volumetric fog. That is only safe for a few hero lights.
- **Script toggles:** classic games switch window parts between Glass and Neon by `ClockTime` ([example](https://devforum.roblox.com/t/script-wont-disable-light-with-nightday-cycle/2309678)) **[community]**. The match is set at night, so make these static.
- **AAA:** Spider-Man fakes rooms behind windows with interior-mapping shaders ([Automaton](https://automaton-media.com/en/news/20231201-23558/)), and Yakuza tuned its engine for neon and animated signs (see the R2 art doc). Roblox has no custom shaders. Its equivalent is baked lit-window variants in emissive masks, with two or three lit patterns per facade family, as the R2 art doc already plans **[est]**.
- **Post-processing costs:** Bloom and ColorCorrection are full-screen passes with a roughly fixed cost per frame, whatever the scene holds **[est]**. Docs say some post effects "work differently or not at all" at low quality, and SunRays may not render on low-end devices ([post-processing](https://create.roblox.com/docs/environment/post-processing-effects)) **[doc]**.
  - Skip DepthOfField and Blur; both cost a lot on integrated GPUs **[est]**.
  - Atmosphere is already in the recipe and also hides far detail.

## 6. Recommended scheme and budgets

**Global (Studio, not scriptable):**
- Keep `PrioritizeLightingQuality = Disabled`.
- Start with `LightingStyle = Soft`. Move to Realistic only if test A shows it costs ≤ 1.5 ms more on Iris Xe at quality 5.
- `ClockTime` about 21.5. `Brightness` about 0.5. `Ambient` about (18, 20, 30). `OutdoorAmbient` about (55, 58, 75). `ExposureCompensation` 0 to +0.3. `EnvironmentSpecularScale` about 0.6, so baked glass picks up highlights.
- `BloomEffect`: Intensity 0.6–1.0, Size 24–40, Threshold 0.9–1.2, so only Neon and emissive bloom.
- `ColorCorrectionEffect`: Contrast 0.1, Saturation 0.05–0.1, slightly cool tint.
- Night Atmosphere per the R2 skyline doc. No SunRays, DepthOfField or Blur.
- All of these are **[est]** starting values; tune them live.

| Layer | Distance | Lights | Glow | Signs | Glass | Draw-call share (of 500) |
|---|---|---|---|---|---|---|
| **Near street** | 0–220 studs | ≤ 48 static PointLights/SpotLights, **unshadowed**, range ≤ 24, each parented to a range-sized invisible host part (culling bug). Realistic only: ≤ 2 shadowed narrow spot lights for attack flashes, short-lived. Optionally enable lamp lights by grid cell around the camera (toggle `Enabled` only, with hysteresis; never create or destroy) | Neon tube lettering and lit shopfront cards (opaque) | ≤ 60 SurfaceGuis (ImageLabel of baked text, `LightInfluence 0`, Brightness 2–5, MaxDistance 150–220), ≤ 6 animated screens | Real Glass only on the occupied building and its neighbours: ≤ 150 panes | about 120 (signs and GUIs about 60, glass at most about 50) |
| **Mid** | 220–1,000 studs | None. A light only lights surfaces within its range, so it is invisible here. Paint lamp pools into a night road texture instead | Lit-window bands as opaque Neon strips (≤ 2 per facade side, shared shapes) or MaterialVariant emissive glow cards | Flat Neon rectangles in sign colours, ≤ 3 per building (text cannot be read at this range anyway) | Opaque: baked into the skin | about 60 for the whole glow layer (batches) |
| **Far / skyline** | 1,000+ studs | None | Stand-in meshes with SurfaceAppearance emissive masks (2–3 lit patterns per family); red aircraft lights in the mask or as tiny Neon parts on the 20 tallest towers | Inside the emissive mask | None | about 0 extra (part of the stand-ins) |
| Characters, VFX, opaque world | — | — | — | — | — | about 320 |

Rules:
- **No transparent sign or glow parts anywhere.**
- **Anything that must stay visible through a window must be opaque.** This keeps the Glass hiding rule from hurting.
- **Emissive and Neon at night, plain albedo by day.** The skins swap to the night masks on the client.

## 7. In-engine measurement plan (for owner approval)

Run all tests in a **copy** of the place (`NightBench`), at 1080p on the Iris Xe laptop and on the dev PC. Quality levels 1, 3, 5, 8 and 10. Collect for each run:
- `Shift+F2` render stats: draw calls and triangles;
- MicroProfiler dumps: `computeLightingPerform`, `LightGridCPU`, `ShadowMapSystem`, `StandardAdorns`, `UpdateUILayouts`, and total GPU and CPU ms;
- Developer Console memory: `GraphicsTexture` and `Gui`.

Use 30-second camera fly-through paths that are the same for every run.

| # | Test | Variants | Pass criterion |
|---|---|---|---|
| A | Light count and style | 0/50/100/200 static unshadowed PointLights in view; range 16/32/60; Soft vs Realistic (both with Disabled) | Choose the style and cap so that lighting costs ≤ 1.5 ms at quality 5 on Iris Xe |
| B | Shadowed lights | 0/2/4/8 shadowed spot lights (60°) vs point lights; Realistic only | Confirm the ≤ 2 cap; check whether they are dropped at quality 3 or below |
| C | Light culling bug | Lamp light parented to a 0.5-stud part vs a range-sized host, turning the camera | Host part prevents pop-out |
| D | Glass | 500/2,000/10,000 panes in view as Glass T=0.15, Glass T=0, SmoothPlastic T=0, and baked skin; also dust particles behind a pane | Count draw calls; confirm particles are hidden behind T>0 Glass |
| E | Emissive | SurfaceAppearance emissive on a stand-in at 300/1,500/3,000 studs with night Atmosphere; `Texture.EmissiveStrength` on a skin; MaterialVariant glow-card alignment on Parts | Visible at quality 1; is the Texture property real? Is alignment usable? |
| F | Neon and bloom at low quality | A Neon sign wall at quality 1/3/10, with and without BloomEffect | Signs still read without glow |
| G | Baked glass look | Roughness and metalness glass in the skin, Soft vs Realistic | The facade does not look "painted" at 60 studs |
| H | Signs | 0/100/300/1,000 SurfaceGuis (TextLabel vs ImageLabel), MaxDistance 220, vs Neon rectangles vs SurfaceAppearance sign cards | Frame ms and memory per 100 signs; set the cap |
| I | Post stack | Bloom, ColorCorrection and Atmosphere on vs off | Under 1 ms total on Iris Xe |
| J | Full scene | The recommended scheme at the Scramble, the busiest view | ≤ 500 draw calls and ≤ 16.7 ms at the chosen low-tier quality |

Estimated effort: about one day to build the bench and run tests A–J, using the existing load-test tooling in `R2_LOAD_TEST_PROFILING.md`.

## Open risks

- Emissive and Neon inside Atmosphere haze: does the haze fade distant emissive and Neon too much? Test E.
- `LightingStyle` is set for the whole place, not per device. The low tier relies on quality levels to scale it down.
- The light-culling bug is still open, so recheck after each Roblox update.
- Pre-made art sources: the 20-per-day mesh upload limit affects the sign-card and stand-in mesh libraries; plan the uploads.

## Sources

- Unified Lighting is fully live (staff, 2025): https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512
- Future Is Bright Phase 3 released / beta (staff): https://devforum.roblox.com/t/future-is-bright-phase-3-released/878634 ; https://devforum.roblox.com/t/future-is-bright-phase-3-studio-beta/639903
- Future Is Bright overview: https://roblox.github.io/future-is-bright/ ; wiki https://roblox.fandom.com/wiki/Future_Is_Bright
- GDC 2020 Roblox rendering talk (zeux): https://zeux.io/data/gdc2020_pvr.pdf
- Light range thread (voxel cost is cubic): https://devforum.roblox.com/t/increase-range-limit-of-lights/68336?page=10
- Light range 60 → 120 (staff recap, Sept 2025): https://devforum.roblox.com/t/weekly-recap-september-22-26-2025/3961633
- Lights culled by parent bounds (bug, 2026): https://devforum.roblox.com/t/spotlights-pointlights-disappear-or-flicker-based-on-camera-orientation/4750431
- Lighting optimizations thread: https://devforum.roblox.com/t/lighting-optimizations/1073832
- Improve performance (docs): https://create.roblox.com/docs/performance-optimization/improve
- Design for performance (docs): https://create.roblox.com/docs/performance-optimization/design
- Optimize your experience (docs): https://create.roblox.com/docs/tutorials/curriculums/environmental-art/optimize-your-experience
- QualityLevel (docs): https://developer.roblox.com/api-reference/enum/QualityLevel
- Light sources (docs): https://create.roblox.com/docs/effects/light-sources
- Emissives (staff, live 2026-02-12): https://devforum.roblox.com/t/on-hold-emissives/4034414 ; Creator Roadmap 2026 Spring: https://devforum.roblox.com/t/creator-roadmap-2026-spring-update/4625473
- SurfaceAppearance: https://create.roblox.com/docs/en-us/reference/engine/classes/SurfaceAppearance.md ; MaterialVariant: https://create.roblox.com/docs/en-us/reference/engine/classes/MaterialVariant.md ; Decal: https://create.roblox.com/docs/en-us/reference/engine/classes/Decal.md
- Part Instancing pre-release (staff, 2018): https://devforum.roblox.com/t/part-instancing-pre-release-announcement/130333
- Transparent parts and render entities (fixed 2024): https://devforum.roblox.com/t/transparent-parts-increase-render-entities-and-ruins-instancing/2673266
- Introducing Glass (staff): https://devforum.roblox.com/t/introducing-new-material-glass/64231/1
- SurfaceGui MaxDistance (staff, 2023): https://devforum.roblox.com/t/new-surfaceguimaxdistance-property/2574715
- Hidden SurfaceGui cost, fixed 2026-03-17: https://devforum.roblox.com/t/surfaceguis-still-consume-a-lot-of-frame-time-even-when-outside-of-maximum-render-distance-or-when-disabled/4289170
- SurfaceGui (Brightness/LightInfluence): https://create.roblox.com/docs/en-us/reference/engine/classes/SurfaceGui.md
- BillboardGui limits thread: https://devforum.roblox.com/t/whats-the-practical-limit-for-billboardguis-how-many-can-there-be-in-a-scene-before-i-have-to-worry/3958385
- SurfaceGui vs Textures thread: https://devforum.roblox.com/t/which-is-less-laggy-surfacegui-or-textures/3982685
- Decal UVOffset overdraw (2026): https://devforum.roblox.com/t/decal-uvoffset-uvscale-causes-significant-performance-impact/4802916
- Neon signs from Image/TextLabel (staff tutorial, 2024): https://devforum.roblox.com/t/how-to-create-neon-signs-using-an-image-or-text-label/2910923
- Fix Neon Parts (2026 tutorial): https://devforum.roblox.com/t/fix-neon-parts-to-look-amazing-and-realistic/4526920
- Unified Neon and Bloom poll: https://devforum.roblox.com/t/unified-neon-and-bloom-poll/180359/31
- Glowing windows thread (2025): https://devforum.roblox.com/t/is-it-possible-to-recreate-glowing-windows-from-old-roblox/3924198
- Night city build feedback: https://devforum.roblox.com/t/quick-feedback-on-nighttime-city-build/3108430
- Day/night window toggle: https://devforum.roblox.com/t/script-wont-disable-light-with-nightday-cycle/2309678
- Beams cost thread: https://devforum.roblox.com/t/do-beams-create-lag/675990
- Post-processing (docs): https://create.roblox.com/docs/environment/post-processing-effects
- Spider-Man windows (interior mapping): https://automaton-media.com/en/news/20231201-23558/
- Repo: `src/shared/FacadeLayout.luau`, `src/shared/GroundFacadeKit.luau`, `src/shared/GlassVisual.luau`, `tools/research/R2_CITY_INVENTORY.md`, `tools/research/R2_ENGINE_TESTS.md`
