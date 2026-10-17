# Ground facade presentation v9

October 16, 2026. Visual-only change; the 53 physical templates, openings,
mounting, hit system and glass state behavior are unchanged.

`GroundFacadeNames.Generate` preserves the existing label/stem/identity streams.
An independent deterministic language stream now uses Japanese-only main signs
for 8 of 10 language buckets and bilingual signs for 2. Named fictional chains
retain McDooDoo's, SMASH KING and STARBOYS. `options.language` accepts `japanese`
or `bilingual` for art direction. Explicit `brandOverride` still wins.

`GroundFacadeCatalog.PALETTE_ORDER` is the stable selection order of 17 building
palettes: the existing eight and porcelain, warm grey, cool grey, sand, slate,
umber, dusty rose, sage and navy tile. Select once per building so all perimeter
walls and support parts agree; the presentation pass never changes wall tone.

`GroundFacadePresentation.Apply(layout, spec, options)` is a pure post-layout
pass. Tenant identity seeds separately choose 12 sign/awning colors, six wood
tones, five muted glass tints, trim variation and six display font choices.
Chain identifiers keep their recognizable colors. Small notices use plain
Source Sans Semibold. Japanese glyphs use Roblox's font fallback where needed;
Latin font family differences may be more apparent than Japanese differences.
No external font asset IDs or texture imports are required.

The pass translates common secondary signs and removes bilingual suffixes when
the retained first portion contains Japanese. Unsupported English text is kept
readable rather than incorrectly translated. This is a Japanese-majority street,
not a guarantee that every sign is Japanese-only. Signless templates stay signless.

## Integration

1. Require `GroundFacadePresentation` from `GroundFacadeKit`.
2. Return `Presentation.Apply(Mount.Layout(rawLayout(id,options),options), Catalog.Get(id), options)` from `Kit.Layout`.
3. In `addText`, assign `label.Font=row.font or Enum.Font.SourceSansSemibold`.
4. City palette selection should use `Catalog.PALETTE_ORDER`, once per building.
5. Include the new presentation module in isolated Studio helper clones and any
   explicit Rojo tool project that enumerates Shared dependencies.

Optional model attributes `FacadeLanguage=layout.language`,
`FacadeDisplayFont=layout.displayFont`, and
`FacadePresentationSeed=layout.presentationSeed` help a read-only audit.

## Read-only verification

In Studio, require current modules from a fresh helper clone (old require caches
can retain older source). Generate names for 1,000 tenant keys and count language
values; ensure most are Japanese and repeat keys reproduce identical strings.
Generate all 53 layouts twice with the same seeds and palette. Check all part
names, CFrames, sizes, collision roles and portal data are identical; every
text row has an Enum.Font value. Check more than one font, wood tone and sign
color appear across tenant seeds. Compare default vs `language="bilingual"`
layouts to confirm all physical geometry stays identical.

Live installation and visual checks are handled by the main v9 rollout; this
note does not claim that a particular installed Studio state has been verified.
