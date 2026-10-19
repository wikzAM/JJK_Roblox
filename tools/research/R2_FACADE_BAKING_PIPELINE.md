# R2: Facade baking pipeline (research, 2026-10-19)

Research only; no game code was changed. Context: `GAME_DESIGN_DECISIONS.md`, `SCOPED_PLAN.md`. In-engine probe results are in `R2_ENGINE_TESTS.md` (T1, T2) and are folded in below.

**Scale** (from the `ProjectFiles.luau` audits):
- About 11,000 glazed ground bays and about 41,000 panes.
- 50+ designs and 17 palettes, with variable widths.
- Signs are `SurfaceGui` text (`MaxDistance=220`).

**(unverified)** marks claims I could not confirm from a current source; test them in-engine.

## Executive summary

1. **Capture in Studio with `StudioCaptureService`. It is plugin-only.**
   - It captures a region of the 3D viewport.
   - `StudioScreenshotCapture:GetBuffer()` returns raw RGBA8 (or PNG) bytes, with optional resampling.
   - Bytes can be uploaded straight from a local plugin (`EditableImage` → `AssetService:CreateAssetAsync(img, Enum.AssetType.Image)`), or written to disk and uploaded through Open Cloud (120 creates per minute).
   - Roblox has no orthographic camera. Use FOV 1° and capture in tiles.
2. **Use one opaque skin Part per bay, with one `Texture` that is exactly one tile** (`StudsPerTileU/V` = the bay's width and height).
   - `Texture` inherits Decal's PBR maps (normal, roughness and metalness).
   - Texture streaming covers Texture, Decal, MaterialVariant and SurfaceAppearance, and trims resolution per device automatically.
   - About 8 px per stud is enough beyond the Part-swap radius.
3. **Skins must not be alpha-transparent.**
   - Behind a Glass-material pane, Roblox does not draw transparent objects, including decals on transparent parts.
   - Transparent sorting is per object.
   - The building the player is inside uses its full Part version instead, so seeing out needs no alpha.
4. **Glass damage works as planned. Measured in-engine (T1):**
   - **Cost:** after a first-call warm-up of about 65 ms, each small `GeometryService:SubtractAsync` pane cut on a textured skin costs **3–11 ms**.
   - **Texture loss:** the Texture is **not** carried over to the result; the helper must clone it.
   - **Alignment:**
     - Interior holes keep the union's size and position exactly, so the cloned Texture stays registered to the painted windows.
     - Cuts that touch an edge need an `OffsetStudsU/V` correction.
   - **Cracked panes** get a small opaque overlay Part.
   - **No UV-offset decals on skins.** Roblox staff confirm that each one redraws the whole host face.
5. **The Part swap conflicts with the rule "never tear down and rebuild detail around the camera."** Keep it small:
   - Street level only, within about 150 studs.
   - Wide hysteresis and a speed gate.
   - Pooled templates and no fades.
   - Hide the skin, never destroy it.

## 1. Capturing images

| Option | Verdict |
|---|---|
| **`StudioCaptureService:CaptureScreenshot{Position, CaptureSize, OutputSize, ResampleMode, Format, UICaptureMode}`** | **Best.** PluginSecurity; Studio only. Returns a `StudioScreenshotCapture`: wait for `BufferStatus` Ready, then `GetBuffer()` (RGBA8 by default, or PNG). `ScaleAsync` resamples (bilinear or nearest). Needs a one-time `RequestScreenshotPermissionAsync`. The capture fails rather than clipping if the region leaves the view. `CapturePluginGui()` also exists. [StudioCaptureService](https://create.roblox.com/docs/en-us/reference/engine/classes/StudioCaptureService.md), [StudioScreenshotCapture](https://create.roblox.com/docs/en-us/reference/engine/classes/StudioScreenshotCapture.md) |
| `CaptureService` (CaptureScreenshot / TakeScreenshotCaptureAsync) | Client-side, full screen. Returns a temporary contentId that lasts one session and can't go through `UploadCaptureAsync`. Unusable for a pipeline. [CaptureService](https://create.roblox.com/docs/en-us/reference/engine/classes/CaptureService.md), [Captures thread](https://devforum.roblox.com/t/captures-apis-are-now-available/2838188) |
| ViewportFrame + low-FOV camera | Lighting is simple to control (Ambient, LightColor, LightDirection), but the pixels can only be read through a capture. Quality is reduced, and lights and **SurfaceGui text don't render** inside it (unverified for SurfaceGui). Reject it, because our signs are SurfaceGuis. [thread](https://devforum.roblox.com/t/viewport-camera-issues/4754173) |
| `EditableImage` | A pixel container, not a renderer. `Read/WritePixelsBuffer` uses RGBA at 4 bytes per pixel. `CreateEditableImage{Size}` defaults to 512² and returns nil once the device's editable memory budget is used up. **It can be published:** `CreateAssetAsync` accepts `AssetType.Image` with an EditableImage root, "only in locally loaded plugins", with no prompt. [AssetService](https://create.roblox.com/docs/en-us/reference/engine/classes/AssetService.md), [EditableImage](https://create.roblox.com/docs/reference/engine/classes/EditableImage) |
| External rasterizer (Python) or Blender from `Kit.Layout()` JSON | True orthographic view, with exact alpha, depth, normals and emissive masks. It loses Roblox material textures and SurfaceGui text unless they are re-implemented. Best for the **auxiliary maps**, not the colour map. |

**Orthographic workaround**
- Roblox has no orthographic projection; a Sept 2025 feature request is still open ([FR](https://devforum.roblox.com/t/orthographic-camera-projection-for-experiences-and-studio/3932266)).
- The known workaround is `FieldOfView=1` with the camera far away ([thread](https://devforum.roblox.com/t/create-an-orthographic-view/1300021)).
- Parallax at a tile's edge ≈ relief depth × tan(half the horizontal FOV). For a canopy that sticks out 3.4 studs that is about 0.05 studs, under 1 px at 16 px per stud, at any distance.
- So capture **tiles** about 12–16 studs wide from about 400 studs away. A single shot from about 2,000 studs risks having small distant parts culled.
- Set the editor quality level to maximum.

**Neutral lighting (calibrate it; not verified)**
- Do the bake in a separate bake place.
- Lighting settings:
  - `GlobalShadows=false`
  - `EnvironmentDiffuseScale=0` and `EnvironmentSpecularScale=0`
  - grey Ambient and OutdoorAmbient
- Remove the Sky, Atmosphere and post-effects.
- `LightingStyle` and `PrioritizeLightingQuality` replace `Technology` ([Lighting](https://create.roblox.com/docs/en-us/environment/lighting)).
- Tone mapping can't be confirmed off, so put a **calibration strip** in every capture: black, 25/50/75% grey, white and #A3A2A5. Fit a per-channel lookup table so the chips read back their true values.

**Alpha**
- Viewport captures carry no alpha.
- Rasterize the mask offline from the layout's pane, door and opening rows. It is exact, and it matches the per-pane data.

## 2. Uploading and using textures at scale

**Open Cloud Assets API**
- Accepts png, jpeg, bmp and tga, under 8000×8000 and up to 20 MB per call.
- **Image assets cannot be updated**, so every re-bake produces a new ID. [Usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets)
- Create Asset is rate-limited to **120 per minute per API-key owner**; polling the operation is limited to 300 per minute.
- Scopes: `asset:read` and `asset:write`.
- Results include `moderationResult.moderationState`. [Reference](https://create.roblox.com/docs/cloud/reference/features/assets.md)
- There is no published figure for moderation time. Japanese sign text could be flagged (unknown).

**Resolution and memory**
- 4K rendering is live (2026-01-30). Uploads up to 8K are stored and served at 4K ([4K post](https://devforum.roblox.com/t/studio-beta-4k-texture-rendering/4144950)).
- Texture streaming covers **Texture, Decal, MaterialVariant**, SurfaceAppearance and MeshPart, plus base materials on parts and unions ([streaming](https://devforum.roblox.com/t/introducing-texture-streaming/4144855)):
  - It sets a texture budget every frame from device memory.
  - It loads mips according to distance and screen coverage.
  - 4K is disabled on low-end Android (under 3.5 GB).
  - In Roblox's Modern City demo, texture memory fell from 280 MB to 155 MB.

**Pixel density**
- The Part version takes over inside about 150 studs.
- At 150 studs, 1080p and 70° FOV, the screen shows about 5 px per stud, so **8 px per stud** is enough. Test 12 for rooftop views.
- A 36×12.5 bay at 8 px per stud is 288×100, about 115 KB as raw RGBA and roughly 20–30 KB compressed (compression format unverified).
- **1,000 unique bakes come to roughly 30–60 MB before streaming.**
- The real cost driver is the number of unique bake keys.

**Which instance to use**

| Instance | Use | Why |
|---|---|---|
| **Texture** | **Default** | Per-face `StudsPerTileU/V` and `OffsetStudsU/V`. Inherits `NormalMapContent`, `RoughnessMapContent`, `MetalnessMapContent` and `Color3` from Decal. No emissive yet. Works on unions. [Texture](https://create.roblox.com/docs/en-us/reference/engine/classes/Texture.md), [Decal](https://create.roblox.com/docs/en-us/reference/engine/classes/Decal.md) |
| Decal with `UVOffset`/`UVScale` | **Not on skins** | Staff: each one makes the host surface render again ("40 layers"), which is about 20 FPS with 40 of them ([thread](https://devforum.roblox.com/t/decal-uvoffset-uvscale-causes-significant-performance-impact/4802916)). Stacking Textures on one big face has the same overdraw problem. |
| MaterialVariant | Upper-floor tiling only | Full PBR plus `EmissiveMaskContent`/`Strength`/`Tint`, live 2026-02-12 ([emissives](https://devforum.roblox.com/t/on-hold-emissives/4034414)). Batches well. **The UV origin can't be controlled**, so it can't line up with bay edges ([thread](https://devforum.roblox.com/t/how-to-use-materials-in-roblox/3366579), [MaterialVariant](https://create.roblox.com/docs/en-us/reference/engine/classes/MaterialVariant.md)). |
| MeshPart + SurfaceAppearance | Option B | Exact 0..1 UVs, PBR, emissive, and `AlphaMode.Transparency` cut-out on a part at Transparency 0 ([SurfaceAppearance](https://create.roblox.com/docs/en-us/reference/engine/classes/SurfaceAppearance.md)). **T2:** GeometryService carves *watertight* MeshParts in about 10 ms and the result stays a MeshPart. Our FBX scan meshes fail with "non-manifold". Code-built (EditableMesh) meshes don't replicate or persist, so the skin must be an **uploaded** watertight box mesh. One shared mesh is enough, because it is scaled per bay. Most SurfaceAppearance properties can't be changed by script at runtime. |

**Atlasing**
- A Texture can show one atlas cell: set `StudsPerTile` to the atlas size and `OffsetStuds` to minus the cell's origin.
- Roblox advises **unique textures over atlases** unless the parts batch, because streaming loads the whole atlas at the resolution its most important user needs ([guide](https://create.roblox.com/docs/en-us/parts/textures-decals.md)). Mips also bleed between cells.
- So don't atlas bays. Use the crop trick only to reuse a bay's own image on overlays.

**Bake keys**
- One bake per (design, role, palette, width bucket of 2 studs, height bucket, 1–2 seed variants).
- Step 1 is to count the unique keys. Target 300–1,000.

## 3. Alpha and transparency

- **Glass hides transparent objects.**
  - Not drawn behind Glass: transparent parts, "decals on transparent parts", particles and world GUIs ([Glass](https://devforum.roblox.com/t/introducing-new-material-glass/64231/1)).
  - So a Transparency=1 skin with an alpha texture would vanish when seen through any Glass window.
  - **Keep skins opaque.**
- **Sorting.**
  - Transparent faces sort by the centre of their object, so large overlapping transparent skins will flicker ([thread](https://devforum.roblox.com/t/decaltexturegui-clipping/43275)).
  - Transparent texels still cost shading across the whole face (staff, in the UV-offset thread).
- **Sides.**
  - Decals draw only on the outward side of their face (unverified for current builds).
  - Looking from behind, a Transparency=1 part with a front decal is see-through ([thread](https://devforum.roblox.com/t/any-tips-for-one-way-glass/250644)).
  - An interior view would need a second, mirrored bake. That is avoided because the occupied building uses Parts.
- **`LocalTransparencyModifier`.**
  - On a part, the client sees `1-((1-T)(1-LTM))` ([BasePart](https://create.roblox.com/docs/en-us/reference/engine/classes/BasePart.md)).
  - Decals and Textures have their **own** hidden LTM ([thread](https://devforum.roblox.com/t/head-shadow-not-showing-in-first-person/4032892)), so set both.
  - `GroundFacadeInteriors.luau` currently sets the part's LTM only.
- **Glass cost.**
  - Refraction appears only at high quality.
  - Glass uses a multiply blend.
  - Panes baked into the skin cost nothing; keep the Glass material only on live Part-version panes.

## 4. Lighting consistency

- **Bake albedo only** (flat and calibrated), and let the engine light the opaque skin.
  - Skin and Parts then get the same sun, shadow and ambient. Only the relief's self-shadowing is lost.
- **Depth cues, computed offline from the layout:**
  - depth → **normal map** in `Texture.NormalMapContent` (OpenGL tangent space);
  - **AO and contact shadow** under canopies, baked into albedo at about 30–50%, because live lighting adds more;
  - a **roughness map** (glass low, concrete high) so windows catch highlights.
  - Decal and Texture PBR maps are packed into an engine-managed `TexturePackContent`. Set them at edit time and verify they survive publishing.
- **Relief:**
  - Keep 1–2 permanent relief Parts per bay (canopy slab, large blade sign). Flat skins read as painted mostly at grazing angles.
  - There are no custom shaders, so no parallax or interior mapping.
- **Night.** Texture and Decal have no emissive yet; Roblox plans it alongside PBR decals. Options:
  - (a) Swap the ColorMap to a lit-window night bake on the client. This adds images only for lit designs.
  - (b) Option B skins with SurfaceAppearance emissive.
  - (c) MaterialVariant emissive on upper floors.
  - In every case, rasterize the emissive mask from `kind=="light"` and Neon rows.

## 5. Swapping without popping

- **Same frame of reference.**
  - The bake rectangle equals the skin's front face: bay width × clear height, at the kit pivot (bay centre, slab top Y=0, exterior −Z = `NormalId.Front`).
  - Put the skin's front plane on the wall plane the camera focused on.
  - Set `StudsPerTileU=w`, `StudsPerTileV=h`, offsets 0. The image then fills the face whatever the tiling origin.
  - Verify that U isn't mirrored.
- **Hysteresis and gating.**
  - Swap in at about 150 studs and out at about 210, with a minimum dwell of about 2 s.
  - Start no new swaps above about 150–300 studs/s of camera speed.
  - Swap only at street level, inside the occupied building, and on damaged bays (one way).
- **Fades.**
  - There is no dithered fade.
  - Tweening part transparency drops the parts into the sorted transparent pass and hides them behind Glass.
  - **Swap instantly in one frame:** show the Parts, then set the skin's part and Texture LTM to 1. At 150 studs, aligned images differ by under a pixel.
- **Pooling.**
  - Keep an edit-time template Model per key in ReplicatedStorage.
  - The client clones a small pool on first need, reuses it with `PivotTo` and parks it instead of destroying it.
  - Builds stay within a per-frame budget (`GlassConfig.FrameBudget` already exists).
  - Measure hitches against the rule about not rebuilding detail around the camera.

## 6. Glass overlay and CSG holes on a textured skin (now measured)

**Measured (T1):** 40×30×0.6 skin, Front Texture, 12 cuts of 2.5×3 boxes, `CollisionFidelity=Box`, `SplitApart=false`.
- The first cut took about 65 ms (warm-up). Every cut after that took **3–11 ms**.
- **Texture children are not carried over.** Docs agree: `BasePart:SubtractAsync` copies no properties and GeometryService documents no child retention ([BasePart](https://create.roblox.com/docs/en-us/reference/engine/classes/BasePart.md), [GeometryService](https://create.roblox.com/docs/en-us/reference/engine/classes/GeometryService.md)).
  - The helper must clone every Texture onto the result.
  - Cloning works.
- **Alignment holds for interior holes.**
  - The union keeps its exact size and position.
  - PartOperations are box-mapped ([solid modeling](https://create.roblox.com/docs/parts/solid-modeling)), so the same `StudsPerTile` and `Offset` tile identically.
  - A cut touching the border shrinks the bounds. Shift `OffsetStudsU/V` by the change in bounds.
- The hole's inner sides show the skin's part Color and Material, so set them to a reveal or frame colour.

**Recommended glass flow**
1. **Intact:** the pane exists only in the texture. The manifest stores each pane's rectangle in stud space.
2. **Cracked:** add an opaque overlay Part 0.02–0.05 studs in front of the pane rectangle. It carries the bay image cropped by `OffsetStuds` (with `StudsPerTile` = bay size), plus `GlassConfig.CrackImage`.
   - Opaque means no transparent pass and nothing hidden behind Glass.
   - Overdraw is limited to the pane's area.
3. **Shattered / removed:** cut a server-side `GeometryService:SubtractAsync(skin, {all newly broken pane boxes})`.
   - Make **one call per bay per event**, with cutters padded by about 0.02 studs.
   - Clone the Textures, correct the offsets, delete the overlay, and spawn shards (the existing `GlassShards` path).
   - The skin then shows the backing or interior through the hole.
- **Remaining CSG risks:**
  - Results are capped at 20k triangles.
  - Roblox advises against rapid chains of calls.
  - **Each result replicates new mesh data to all clients**; size not yet measured.
- **Fallback if replication is heavy:** on first damage, swap the bay once for a pre-baked **split skin**: 3–6 bands plus one tile per pane, all cropping the same image. Breaking a pane then just deletes its tile. No CSG; it costs 4–8 more parts on damaged bays only.

## Recommended end-to-end pipeline

**Files:**
- `tools/facade_bake/` holds the Luau bake script, the Python post-process, `layouts/*.json` and `out/<key>/{albedo,normal,rough,mask,night}.png`.
- `src/shared/FacadeBakeManifest.luau` maps each key to its asset IDs, w, h, px/stud, pane rectangles and version.

1. **Count keys** (Studio MCP `execute_luau`, read-only). Read the facade manifest, compute the bake keys and count bays per key. Gate: about 1,000 or fewer.
2. **Export geometry** (MCP). Serialize `Kit.Layout(id, options)` rows, pane rectangles and light rows to JSON, returned in chunks.
3. **Capture colour** (in a separate bake place, MCP-driven):
   - neutral lighting and the calibration strip;
   - `Kit.Build` at the origin;
   - FOV 1 tiles through `StudioCaptureService`, captured at 2× and downsampled (`OutputSize`, bilinear) for antialiasing.
   - The owner clicks the screenshot permission prompt once.
4. **Export the bytes:**
   - (a) **Preferred:** base64 chunks via MCP, or an `HttpService` POST to a localhost Python receiver, which writes the PNGs. This gives versioned masters.
   - (b) Alternatively, upload with `CreateAssetAsync(EditableImage, AssetType.Image)` from the plugin.
5. **Post-process** (Python, numpy and Pillow, run with `-I`):
   - apply the calibration LUT;
   - orthographic raster of the layout → depth, normal, AO, mask, roughness and night emissive;
   - partial AO into albedo;
   - downsample to 8 px per stud, padded to a multiple of 4.
6. **Upload** with Open Cloud `POST /assets/v1/assets`, throttled to about 100/min, using an owner-created API key. Poll, then record IDs and moderation state in the manifest. Keys stay in a local env var, never in MCP or chat.
7. **Apply** (MCP edit-time batches):
   - one skin Part per bay, with its Texture and PBR maps and optional relief parts, tagged `FacadeSkin`;
   - move the Part facade into per-key templates.
8. **Runtime:**
   - client swap controller (hysteresis, speed gate, pool, LTM on part and Texture);
   - server glass service (overlay → batched CSG + Texture clone/offset fix, with the split skin as fallback).
9. **QA:** render the Part and skin versions from the same camera at 100/150/300 studs and compare pixels per key.

**The Studio MCP can automate** steps 1–3, 4a, 7 and the QA renders. The owner still has to grant the screenshot permission, create the API key and do visual sign-off.

## Risks and unknowns to test in-engine

1. Does `StudioCaptureService` work under the MCP plugin's security context? Also check the largest `CaptureSize` (it's limited to the viewport), tone-mapping error after calibration, and whether capture works while Studio is unfocused (T1's `screen_capture` timed out while the window was inactive).
2. Does `CreateAssetAsync` accept an EditableImage from the MCP context? Do the Mesh & Image API settings or ID verification apply?
3. Is the Texture mirrored on `NormalId.Front`, and where does `OffsetStuds` start? The crop trick depends on both being pixel-exact.
4. Can Texture PBR maps be set by script in edit mode, do they survive publishing (`TexturePackContent`), and what do they cost per part?
5. **Replicated size and time of a carved skin** (union mesh data) versus the split-skin swap, with many fights at once. Also get the visual confirmation of T1 that is still pending.
6. Option B: carve an **uploaded** watertight box MeshPart that has a SurfaceAppearance, and confirm UVs, re-attachment and replication in Play. Model uploads are capped at 20 per day, but one shared mesh is enough.
7. Moderation of images with Japanese and English sign text, and how long it takes.
8. Texture memory with 300 and 1,000 keys on a low-end laptop (GraphicsTexture in the Developer Console), and whether far skins stay legible on the skyline.
9. Swap pop: flat-baked albedo under live light versus real Parts, at noon and dusk.
10. Do NPOT textures compress and mip cleanly?
11. Watch for Decal/Texture emissive support, which would remove the night bakes.
12. The conflict with the "never tear down and rebuild around the camera" rule: keep the swap radius small and measure hitches.
