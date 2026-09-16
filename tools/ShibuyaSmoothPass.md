# Smooth Shibuya interiors

## September 14, 2026 checkpoint

The live map now contains **797 smooth generated sections**, with **3,106
occupied floors, 797 roofs, and 44,624 structural parts, including 25,755
WedgeParts**. The full structural audit reported **zero bad smooth models**.
These are reconstructed mesh sections, not 797 independently identified real
buildings. A real building can comprise more than one source section.

At this checkpoint, **1,159 legacy `BuildingAuto_*` sections remain**. Some are
useful existing structures; others are incomplete, disconnected, very short,
or still jagged. Final visual review of severe fragments is pending. The three
original authored buildings remain separate from these counts.

**Studio save target:** `D:\GameDownloads\JJK_Roblox\Shibuya_SmoothInteriors.rbxl`.
Saving this final checkpoint has not yet been confirmed in this document.
Save the actual live place through Studio. `rojo build` produces the
source-controlled scene and scripts, not a backup of the hand-built live map.

## What caused the old result

The old generator turned each mesh cross-section into occupied square cells
and assembled those cells into rectangular slabs. A straight facade that did
not align with the chosen grid became a staircase. Increasing resolution
would make smaller steps without providing an actual straight edge.

The imported mesh also has open seams, disconnected pieces, roof equipment,
and geometry that does not reliably describe a closed solid. Sampling every
floor independently allowed those defects to produce missing regions,
floating snippets, changing footprints, and cores that stopped below upper
floors. A mesh component is only a starting point for identifying a building.

## Replacement methods

`ShibuyaMassing` first reconstructs horizontal facade contours at several
heights. It keeps repeated, simplified outlines, retains meaningful recesses
and supported setbacks, and repairs measured small seams. Current defaults
weld within 0.6 studs and limit straight gaps, corner gaps, and corner
extensions to 3 studs. Corner repairs follow intersecting facade tangents;
they do not draw arbitrary long closing edges.

When repeated closed contours are unavailable, the **roof fallback** can use
the boundary of a broad planar roof. Shared triangle edges are removed,
including edges split at T junctions. The candidate must be supported by
matching facade evidence at multiple heights. A complete measured roof can
supply one missing facade; large roof openings, several missing sides,
disconnected roofs, and incompatible lower geometry remain deferred. This
method does not use a convex hull to fill unknown space.

`ShibuyaGridMassing` supplies a second fallback from the **saved legacy floor
masks**. It traces repeated usable floor plates and converts their boundaries
to simplified polygons. This is a deliberate approximation of existing
evidence, not recovery of geometry already lost during sampling. It requires
substantial footprint and height coverage. Bounded cleanup can remove tiny
islands while retaining at least 95% of occupied area, and fill isolated
one-cell holes within strict size and total-area limits. Meaningful secondary
bodies and courtyards remain rejected. Diagnostics report the removed and
filled areas.

`PolygonSlab` builds the final boundary with actual Parts and WedgeParts.
Rectangles use one Part. Other polygons are triangulated while retaining
concave notches and straight angled edges. Alternative internal diagonals or
interior subdivision handle difficult triangles without changing the authored
outline. A shape that cannot meet Roblox's minimum primitive size fails
instead of silently growing an edge.

`SmoothBuildingBuilder` repeats complete floor outlines at a uniform fitted
pitch, snaps supported setbacks to slab levels, and puts a continuous core
inside every occupied floor. Its grid is used for core placement; visible
slab edges come from the polygon. Bulk output is structural only. Floor counts
are height estimates using the project's spacing convention, not verified
counts for individual addresses.

## Incremental workflow

Run in Studio **Edit** mode after Rojo sync. The red reference MeshParts are
preserved in `ServerStorage.Shibuya`.

```lua
local server = game.ServerScriptService.Server
local components = require(server.ShibuyaGeometry).Scan(game.ServerStorage.Shibuya)
local report = require(server.ShibuyaMassing).Preview(components)
local stage, failures = require(server.SmoothBuildingBuilder).Build(report)
```

Preview is read-only. Build creates complete replacements in ServerStorage.
Inspect failures and representative buildings before applying. Failed builds
retain their original live models.

For remaining legacy sections, the saved-grid fallback uses the same builder:

```lua
local server = game.ServerScriptService.Server
local gridReport = require(server.ShibuyaGridMassing).Preview(workspace.Buildings)
local gridStage, gridFailures = require(server.SmoothBuildingBuilder).Build(gridReport)
```

Compare staged examples at their actual locations:

```lua
local review = require(game.ServerScriptService.Server.SmoothBuildingReview)
review.Show(stage, 1, "before", 0.7)
review.Show(stage, 1, "after", 0.7)
review.Restore()
local archive = require(game.ServerScriptService.Server.SmoothBuildingBuilder).Apply(stage)
```

**Restore the review before applying or saving.** Review temporarily stores
the original in `ServerStorage.SmoothReviewOriginal` and displays a disposable
clone. Apply checks the exact original object and unchanged placement, then
archives only matched legacy models. It does not replace the entire city.

Reimporting the source can change MeshPart order. The massing preview first
matches the full source key. Its fallback requires an exact XYZ key suffix
that is unique on both sides, plus agreement with the old stored source
envelope. It does not use fuzzy nearest-building matching.

Studio caches required modules. After editing source during a session, use a
fresh module copy with the correct dependencies or reopen the saved place
before testing new behavior. Rojo synchronization alone does not invalidate
an already returned module table.

## Recovery and further cleanup

Replaced originals remain in `ServerStorage.ShibuyaBeforeSmooth_*` archives.
Each smooth replacement retains its exact `ReplacementSource` link. To undo
one replacement, preserve its smooth model separately and restore that linked
original. Do not restore every archive into Workspace at once; that would
duplicate already replaced geometry.

The earlier 92-model box/manual pass remains in
`ServerStorage.ShibuyaManualAndBoxPass_20260913`. The previously removed 33
small legacy sections remain in `ServerStorage.ShibuyaSmallFragments_20260913`.
The original source meshes and earlier place checkpoints are also retained.

`ShibuyaIncompleteAudit.Preview(workspace.Buildings)` is a **read-only screening
tool**, not a deletion command. It flags severe legacy snippets, including
sections whose floors never fill more than 25% of their source envelope, or
tall sections with no connected floor body reaching 150 square studs. It
skips protected models, invalid data, and sections with fewer than three
planned floors.

Visually compare flagged objects with the reference before archiving exact
confirmed fragments. A large courtyard, thin real building, or low-rise
structure can be legitimate. Neither a low hollow-shell part volume nor
height above the current terrain alone proves that a section is debris.

Useful read-only diagnostics:

- `ShibuyaMassing.Diagnose(component)` — slice failures, endpoint positions,
  facade tangents, small-gap evidence, and repeated-outline support.
- `ShibuyaMassing.DiagnoseRoof(component)` — roof boundary, coverage, and
  multi-height facade failures.
- `ShibuyaGridMassing.Diagnose(model)` — floor topology and bounded cleanup.
- `SmoothBuildingAudit.Run(workspace.Buildings)` — all live smooth structures.

## Regeneration and furniture

`BuildingGenerator.Regenerate(smoothBuilding[, floorCount])` uses the saved
polygon massing, including after moving the building. Keep its existing
Interior until regeneration; the previous interior is archived.

For a manually authored outline,
`SmoothBuildingBuilder.StagePlan(name, plan, floors)` accepts an upright
CFrame, height, and local X/Z Vector2 polygon. Optional contiguous tiers have
`bottom`, `top`, and `points`. Each upper tier must fit inside the tier below.
It returns a complete unparented Model.

Furniture templates already exist in ServerStorage, but furnishing this bulk
pass is deferred. A later pass should place furniture inside each floor's
actual polygon, keep the common core and circulation clear, and tag furniture
and decoration `NoCSG`. The common-core placement grid does not represent all
furnishable space in a larger podium. Exterior faces, entrances, circulation,
terrain alignment, and detailed landmark adjustments still require work.

## Verification completed in Studio

- `PolygonSlabVerification`: 12 fixtures, 3,586 collision probes, and five
  invalid-input rejections. Includes rotated rectangles, concave outlines,
  acute/obtuse and thin wedges, preserved boundary vertices, and gap/overlap
  checks.
- `ShibuyaMassingVerification`: 18 checks covering identity matching, seam
  repairs, persistent outlines, roof recovery, setbacks, and rejection of
  ambiguous geometry.
- `ShibuyaGridMassingVerification`: 13 fixtures covering accepted repeated
  massing, bounded tiny-island/hole cleanup, rejected incomplete or ambiguous
  shapes, and protected models.
- `SmoothBuildingVerification`: three complete-building fixtures, including
  regeneration after movement and actual WedgePart CSG subtraction.
- Full live smooth-structure audit: 797 sections, 3,106 populated floors,
  797 roofs, 44,624 structural parts, 25,755 wedges, and zero bad models.

These checks establish generated structural consistency and representative
collision behavior. They do not certify every real-world outline, floor
count, terrain contact, or a full-city combat playtest. The remaining legacy
sections have not been declared repaired.
