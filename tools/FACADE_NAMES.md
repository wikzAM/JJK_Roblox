# Ground facade sign identities — October 10, 2026

`src/shared/GroundFacadeNames.luau` supplies **79 curated Japanese labelings and
32 fictional name stems**, giving **2,528 distinct Japanese stem/label pairings**.
This is the vocabulary pool size, not a claim that every facade can use every
pairing or that every seed produces a different name. Labels describe food,
groceries, local shops, services, office buildings, residences, hotels and parking.
The three fixed fictional chains sit outside this count.

The module only returns text/data. It creates no Parts, tags, textures, remotes,
lights or physics objects. More identities therefore do not require another
physical facade model for each business.

## Composition and compatibility

Each labeling declares a category list, a narrower business tag, and whether the
label goes before or after the name. For example, `麺処 青葉`, `青葉青果店` and
`なぎ美容室` use one name and one deliberate business noun. The generator never
joins a random chain of Japanese words.

Broad categories are `food`, `retail`, `service`, `office`, `entry`, `residential`,
`hotel`, `parking`, and `chains`. A physical feature narrows the eligible pool:
ramen fronts receive ramen labels, a florist receives flower-shop labels, and a
laundry receives laundry/cleaner labels. Existing coffee and salon templates were
classified as retail; their specific feature takes precedence over that broad
family. New features `laundry`, `bicycle`, `florist`, `clinic`, `bookshop`, `soba`,
`bathhouse` and `timberHouse` have explicit mappings.

Quiet walls should **not call the naming module**. A rear door is not a tenant
entrance merely because it can physically support a sign. Parking names are
available for an accessible actual parking use, not for a core-blocked wall.
Facade exposure/clearance policy must decide that use before generating signs.

`fastFood`, `kingBurger` and `coffeeChain` keep **McDooDoo's**, **SMASH KING** and
**STARBOYS** respectively. Their default identities do not vary with the seed.
An explicit caller `brandOverride` remains available for intentional authoring.

## Independent, repeatable names

```lua
local N = require(game.ReplicatedStorage.Shared.GroundFacadeNames)
local name = N.Generate("retail", "building-17/piece-2/run-4/tenant-1", {
    feature = "florist",
    nameSeed = "tenant-identity-204", -- optional; independent of physical seed
})
print(name.brand, name.subtitle, name.identityKey)

local exact = N.Generate("food", "review", {
    feature = "noren", labelId = "ramen", stemId = "aoba",
})
assert(exact.japanese == "麺処 青葉")
```

`Generate(category, keyOrSeed, options)` returns `brand`, `japanese`, `romanized`,
`label`, `subtitle`, `category`, `labelId`, `stemId`, `identityKey`, and `nameSeed`.
`brand` is Japanese plus the ASCII sign line, separated by ` / `. `romanized`
is the romanized proper name followed by the English business description;
`Labelings[].romanized` separately records the business noun's reading. An
override changes `brand`, retaining the underlying generated identity metadata.

`nameSeed` replaces `keyOrSeed` for name choices only. Give it a stable tenant
identity. Do not use moving world coordinates, child order or a geometry revision
counter. The module uses separate local seeded random streams for stem and
label choice; it never consumes global random state or the kit's geometry RNG.
Changing the name seed must leave door/window placement, palettes, props and
ad placement unchanged. Conversely, changing height/width should not rename a
tenant whose identity key remains stable. `identityKey` describes the resulting
label/stem pairing; it is not a globally unique tenant ID.

`labelId` and `stemId` select exact curated records. Unknown or incompatible IDs
raise an error instead of silently substituting another business. `options.tag`
can explicitly select a narrow pool for new facade features. Avoid inventing
new tags without corresponding curated label records. Pool ordering/version is
part of the seeded contract; append/update intentionally, not during runtime.

## Verification and language limits

An offline source-data check found **79 distinct labeling IDs, 79 distinct
Japanese label nouns, 32 distinct stems, and 2,528 distinct composed Japanese
strings**. Runtime integration should also check:

- Repeating a category/key/options returns the same brand and identity.
- At least 50 labeling records remain and every category has eligible records.
- Every new feature only yields the intended business tag.
- All fixed chain features retain their identities across 100 varied seeds.
- Unknown `labelId`/`stemId` and incompatible label choices raise errors.
- Changing `nameSeed` changes only sign text and identity metadata; compare the
  kit layout excluding text fields to detect accidental geometry reseeding.
- Two builds with different physical seeds and one stable `nameSeed` retain
  the same business name.

The Japanese words/readings were curated using internal linguistic judgment,
not a native professional copy editor. Proper-name romanizations and English
business lines are intentional draft sign choices. These are fictional generated
identities, not a directory of current Shibuya tenants. Incidental overlap with
real businesses is possible; no claim of trademark uniqueness is made. Review
the final selected signs as art before release, including line length/font
legibility on narrow panels. Long names should wrap or shrink text within the
existing sign panel rather than widening the architecture.
