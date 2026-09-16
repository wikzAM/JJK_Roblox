# Clean box pass

Status: first live batch applied and Rojo build checked. Desktop control recovered
after resetting its session. 80 boxes, 641 floors, 4,567 structural Parts; all
levels verified to have one full slab, all buildings have cores. One example was
visually inspected. The 1,989 old auto sections are recoverable in
ServerStorage.ShibuyaPreviousGeneration_1789340420.
Three original buildings remain, for 83 total in Workspace.Buildings.

In Studio edit mode, after syncing scripts:

```lua
local boxes = require(game.ServerScriptService.Server.ShibuyaBoxBuilder)
local report = boxes.Preview(game.ServerStorage.Shibuya)
-- Inspect report.plans and report.rejected before building.
local stage = boxes.Build(report)
-- This asserts that the complete stage succeeded, then archives old auto models.
local archive = boxes.Apply(stage)
```

`Preview` requires five supported slices close to the same rotated rectangle, checks
terrain/baseplate support, and excludes overlapping footprints. It accepts minor
facade recesses (at least 93% rectangular area), but defers major inlets, wedges,
height setbacks, multiple contours and holes. Ground checks are conservative and
may defer valid buildings over unmodeled terrain or elevated slabs. Counts are
not forced toward 800 or any other target. A seam fallback requires 97% measured
wall coverage on all four sides, with little interior edge length. Accepted boxes
are extended to level terrain while retaining roof elevations, by at most 125
studs and no more than their source height. SourceBaseY/GroundAdjustment record
this simplification; counts remain estimates. Most source geometry is deferred.

`Build` puts results in ServerStorage, leaving the live scene unchanged. `Apply`
archives only models with the previous importer attributes, preserving manual
buildings and the source mesh. Previous generated geometry remains recoverable in
`ServerStorage.ShibuyaPreviousGeneration_*`; archived geometry costs storage but
does not render or replicate to clients. Save a new full Studio place after visual
inspection; a Rojo build contains scripts, not the hand-built map.

Run `tools/VerifyBoxGeneration.luau` from the Studio command bar for synthetic
rotation, incomplete-facade, triangle and slab-count checks. It destroys only its
own temporary unparented model. These checks passed in Studio, including after
the facade-seam fallback was added.

## Furniture later

ServerStorage.BuildingFurniturePreview is a successful furnished three-floor
copy with 564 NoCSG pieces, using the user's existing templates.

The boxes use the existing generator, retaining InteriorGrid, oriented bounds,
core tags and deterministic room layout. Start with a few reviewed buildings:
set StructuralOnly=false and regenerate to use ServerStorage.Furniture/CoreDeco.
This rebuilds the interior, so save first and do not use it on hand-edited rooms.
Do not move a stored-grid building before regeneration: the saved frame is still
world-space. A later furniture-only pass should stage Decoration per floor,
preserve structural slabs/cores, check template footprints and door clearance,
keep the existing NoCSG tagging and enforce a per-building object budget.

## Angled shells next

Keep visible floor boundaries separate from the occupancy grid. Slice simple
solid shell Parts/WedgeParts at each slab elevation, combine coplanar footprints,
preserve inlets/holes, and triangulate the resulting polygons. Emit rectangular
Parts where possible and horizontally oriented WedgeParts along diagonal edges.
True tapering across slab thickness needs clipped solid geometry, not a flat
extrusion that protrudes through the slope. The grid can still guide furniture
and core placement; it must no longer define visible silhouette edges. Curved
landmark facades need a separate reviewed representation. None of this angled
pipeline is claimed implemented by this box pass.

