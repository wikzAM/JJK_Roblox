# Glass texture assets — October 8, 2026

Original RGBA images generated with the built-in OpenAI image generation tool
using the owner's glass references as art direction. Generated originals remain
in `C:/Users/anubh/.codex/generated_images/01a114f0-ef40-74b1-8f43-09e546c5a2cd/`.
Copies below are project assets; Roblox uploads succeeded in TestJJK.

- `GlassCracksTile_v1.png` → `rbxassetid://91345378258372`. Fine cool-white
  fractures, transparent interstices. Repeats every 12 studs on both pane faces.
  Generation brief: original square, uniform sparse-to-moderate architectural
  glass fracture network; no tinted fill, background, reflections or lettering;
  transparent background, suitable for a repeated overlay. This is a draft tile;
  its exact seam quality has not been certified as mathematically seamless.
- `GlassShatteredEdges_v1.png` → `rbxassetid://118715470275244`. Thin jagged
  perimeter with a large genuinely transparent centre. Generation brief:
  original square broken pane edge, almost all glass missing, thin irregular
  retained rim, at least 80% empty centre; no checkerboard, intact pane, text,
  scenery or opaque background. Drawn with cropped borders and corners at a
  fixed physical thickness, rather than stretching one square onto a long pane.
- `GlassShardSprite_v1.png` → `rbxassetid://95153642216404`. One translucent
  angular shard for brief client particle bursts. Prompt used:

  > Create one original game VFX particle sprite: a SINGLE isolated irregular
  > triangular shard of broken architectural glass, centered with plenty of empty
  > transparent padding, 1024x1024 square RGBA transparent background. Sharp angular
  > polygon silhouette, translucent almost colorless cool grey-blue interior, razor
  > thin silver-white luminous edges, one small white specular glint at a corner.
  > Front orthographic flat view, crisp clean anime-inspired glass shard as falling
  > particle, restrained subtle highlights. This is ONE shard, NOT a pane, NOT a
  > ring, NOT a cluster, NOT cracks, NOT photorealistic scene. No background, no
  > checkerboard, no text, no cast shadow, no glow outside the shard. All outside
  > pixels transparent; interior semitransparent so it reads as glass over a dark scene.

All three generated originals are 1254 × 1254 RGBA despite the requested 1024
size. The uploaded shattered image rendered correctly with **1024-pixel crop
coordinates** in Studio; 1254 coordinates produced wrong edge samples. Runtime
uses 1024/155 pixels for image size/border. Verify this if replacing the image.
PNG originals are preserved, with no post-generation image editing.

The owner's existing `assets/CrackedGlass.png` is preserved untouched. Its bytes
are an RGB AVIF image, despite the `.png` name, and have no alpha channel. The
supplied fully broken reference has a baked checkerboard; the generated images
avoid both issues. The requested Creator Store backup ID `111911787795227` is
recorded in GlassConfig, but is not used because the original uploads succeeded.

See `tools/GLASS_SYSTEM_HANDOFF.md` for behaviour, performance, testing and APIs.
