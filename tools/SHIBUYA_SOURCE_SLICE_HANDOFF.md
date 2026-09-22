# Shibuya source-slice reconstruction handoff

> **START HERE: `tools/SHIBUYA_LIVE_STATE.md`** — a measured census of the live place (part counts,
> archives, the 22 detailed crowns, the rebuild commands, the Studio gotchas). It exists so a fresh
> session can plan without spending MCP calls re-deriving state. This file is the *reasoning*
> record: what was measured, what was tried, and what was rejected and why.
>
> **THE MAP IS UNSAVED.**

Updated **September 17, 2026, 07:00**. Isolated resume file. Read `src/client/ProjectFiles.luau`
first, then this file.

## FLOATING, PARTIAL, ROADS Sept 22 (overnight) — the owner's "I-beam / missing / rotated" photos

The owner photographed three kinds of wrong building and asked for them fixed automatically, and
for the big roads and viaducts (not buildings) to go. `tools/source_slice_diagnose.py` finds them
(FLOATING, ROAD, ROTATED) and writes `sweep/diagnose.json`.

**Floating stubs, the I-beam.** When a roof is its own mesh piece, not welded to the walls, the
roof alone was generated: two floors hanging 90-130 studs up. `tools/source_slice_extend_floating.py`
extends those down to where the FBX walls under the footprint end. It does this only where the
walls exist; a bridge has none. It stacks down from the stub at a steady storey pitch, and the ground
storey takes the remainder (up to 1.66 storeys: a tall lobby, not a gap). A building below, such as
a podium, stops the extension at its roof, and the referee refuses any extension that spills.
13 buildings (`rebuild_floating3_01`).

**Storeys missing mid-building, a second I-beam.** `Planner.plan` used to `continue` past a level
whose rings failed to convert, leaving floors, then bare core, then a roof slab (`part_1898_-1335`:
floors to 35.7, next at 125). It now fills the missing storeys with copies of the next good level
ABOVE, which lies inside every floor beneath it because slices only shrink going up.
`tools/source_slice_gapfill.py` did the same for the 4 live plans (`rebuild_gapfill_01`). 78
one-storey greys (27-36 studs, floor slab + roof slab + core) read the same way; each got a
mid-height slab cloned from its roof slab (`GreyMidSlab` attribute, 412 parts).

**Missing and "rotated" buildings.** The orphan pass skips an FBX building that live buildings cover
more than 20%. A small or turned live building on one corner of a large FBX building therefore hid
the rest of it, and it read as rotated. The screenshot's rotated candidate
(`fbx_5_11404_945_7873`) is aligned; the fault was coverage. `tools/source_slice_partial.py` plans
each partly covered FBX building whole, using the orphan planner, now refactored into
`building_groups()` and `Planner` in `source_slice_orphans.py`. It replaces live buildings that
lie >= 60% inside the building's outline and keeps clear of neighbours. It accepts only if coverage
gains >= 15%, or a building > 2 storeys short gains >= a storey; it never accepts a lower building
or more spill. **Protected**: `sweep/protected_live.txt` (22 hand-approved shell crowns + 1
manual-design crown, the Cerulean among them). The first trial read the Cerulean as "85 studs too
tall": the 95th-percentile roof over a grown footprint misreads a tower. 56 plans replaced 57 live
buildings (`partial_partial_01..03` + `partial_partialretry_01`, applied by the new
`Sweep.Replace`); 2 had failed triangulation until `buildable_fix` ran. `current_plans()` follows
partial chunks in write order.

**Roads.** 5 more elevated roads and ramps were removed to `ServerStorage.RemovedInfrastructure`
(7 models there now). Three of them were viaducts removed before and re-added by the level-curve
orphan pass under the same ids (Route 246 expressway deck, 1,300 x 117 studs). `orphans.REMOVED`
now lists every one: `current_plans()` drops them and the orphan planner skips them.

Also: `orph_1840_1137` was never in the map (native slab overlap in Studio), so it was re-added
with rings simplified 1 stud (`orphans_lc_retry_01`). `Sweep.Rebuild` now carries `SweepOrphan`
and `SweepPartial`. Map and repo agree: 2,069 source-slice buildings, 298 greys.

| (same audit as below) | before tonight | now |
|---|---|---|
| median top vs FBX roof | -14.8 studs | -14.7 |
| > one storey short | 916 | 906 |
| > two storeys short | 191 | 172 |
| a floor > 10% / > 30% outside the FBX | 108 / 55 | 106 / 55 |
| storeys missing mid-building | 6 | 0 (4 tall lobbies) |

Still open: about 900 buildings more than a storey short, mostly by the storey grid (the
top-snap was disabled for floating boxes; see clean_tops). One idea: stretch the storey pitch per
building so the last floor meets the roof, instead of adding a slab.

## LEVEL CURVES Sept 21 (day) — every floor is the building's filled slice, up to its real roof

The map owner's framing: treat a building's FBX shape as a 3-D function; each floor is its level
curve -- the slice at that height, bounded by the perimeter and FILLED inside it. Measured faults it
fixes: PARCO's floors were split by 3.28-stud roof seams into 2-7 pieces; wall cuts stopped where the
export's walls open (fbx_9_-10581 floored to Y 160 of a 372 roof); a fixed storey grid left the top
slab up to a storey under the roof; unchecked wall cuts spilled outside the building.

**`source_slice_roofs.slice_at`** closes roof seams up to 6 studs and fills the inside; specks under
3% of a floor are dropped (PARCO gets 8-stud seams, per the owner). **Section builder**: a wall cut
is kept only if >= 60% of it lies inside the building's own slice, and is clipped to it; floors
continue up the slice past the last wall cut, each inside the floor below (without that, a taller
NEIGHBOUR's roof edge stacked two storeys on the control building); the top slab is added or lifted
onto the main roof, and a lifted top floor shrinks to the part under that roof (lifting the whole
outline was the worst floor in 403 spilling buildings). Core minimum gets 0.001 studs of margin
(a 4.00-stud core rounded to 3.9999 and failed).

**The wall-cut gate is the wrong referee for this.** It refused 488 of 1,218 changed plans, largely
for floors reaching heights where the walls stop. `tools/source_slice_referee.py` scores old vs new
against the FBX ROOF ENVELOPE instead (height to the roof, worst-floor spill with a one-cell edge
tolerance -- a 2-stud grid otherwise reads ~20% spill on a small building) and accepted 375 of them
(median height error 30 -> 5 studs, spill 21% -> 12%). `tools/source_slice_buildable_fix.py` checks
EVERY ring against the triangulator's full budget before Studio does (small degenerate rings
failed after 6 search states): the next 1,105 rebuilds had **zero** Studio rejections.

Applied IN PLACE (no rollback copies; the place is backed up as GitHub release
`place-files-2026-09-21` and in Roblox version history, and every plan is in the repo): 1,102
rebuilt, 699 orphans re-added, then 100 top-floor fixes and 82 orphan fixes. Old archives deleted
from the live session (193,026 parts); the older-generation `ShibuyaBefore{Smooth,Residual,
GridSplit}_*` archives (~150k parts) were NOT -- they were not in scope of the owner's answer.

| (fair metric, same 2-stud grid) | before level curves | now |
|---|---|---|
| median top vs FBX roof | -20.8 studs | **-5.5** |
| > one storey short | 1,161 | **511** |
| > two storeys short | 422 | **130** |
| a floor > 10% outside the FBX | 260 | **140** |
| a floor > 30% outside the FBX | 98 | **70** |

Still open: 511 buildings more than a storey short (the 122 sector buildings were never
regenerated; 113 kept old versions on the referee; those need a look), floors under overhangs and
bridges (the envelope fills the passage beneath), viaduct decks.

## ROOF ENVELOPE + ORPHANS Sept 21 (overnight) — coverage 49.8% -> 86.5%. UNSAVED at time of writing.

The map owner's red-FBX screenshots showed the real problem: whole buildings missing (Shibuya PARCO
among them) and floors that did not follow the FBX. Two causes, both measured.

**1. The pipeline was GREY-DRIVEN.** It only ever sliced the FBX under an existing grey. PARCO never
had a grey, so it was never considered. Measured coverage of the FBX's building footprint by the map
at the start of the night: **49.8%**.

**2. Wall cuts need closed walls, and PLATEAU does not have them.** The export is PLATEAU
(`surfaceMember` meshes; walls and roofs are separate surfaces). At PARCO the horizontal cut at Y 250
crosses 17 triangles, 411 studs of wall, every end open -- zero outlines at every height 150-350, and
a morphological close of up to 24 studs finds nothing. Where a wall cut failed mid-building, the
section builder COPIED ITS BAND's shape, which is where the pinches, mushroom caps and wrong outlines
came from.

### Roofs survive where walls do not -- `tools/source_slice_roofs.py`

A building's plate at height y is the union of every roof face above y. Plates made this way are
MONOTONE (a roof above y is above every lower level), so a plate can never be larger than the one
below it: no mushroom caps, no pinches by construction. Its one blind spot is an overhang. Plates are
built from the roof TRIANGLES, not a raster -- a 1-stud raster gave PARCO 150-207 vertices a ring
(~150 wedges a floor); the faces give 8 on the tower floors.

**Validated blind against the hand-tuned Cerulean** (fbx_6_4510_4915_-8852): base lands at Y 95.48
against the tuned 95.5, tower floors agree at median IoU 0.923. Real-world scale checked against
published figures: PARCO 99.9 m / 19 floors, Cerulean 184 m / 47 floors -- the map's 5 m storey
gives fewer, taller floors, a design constant.

### Section builder: wall cut -> roof envelope -> band (was wall cut -> band)

`source_slice_plan_builder.py` now falls back to the roof envelope, clipped to the building's own
region + 6 studs, before the band. Only ABOVE the lowest closed section: below it the band is
deliberately extended to the ground (ANCHOR THE BASE), and on the Cerulean the roof envelope there
changed 10 of 41 floors. **Both controls regenerate byte-identically** (Cerulean and
fbx_4_-1164_1279_-9107): neither needs the fallback. Full re-sweep on ONE worker (69 min; see
memory below): 176 live buildings changed, 166 pass the gate, 155 rebuilt live (11 refused by the
Studio triangulator, kept as they were).

Also in the builder: **pinch repair** (a storey < 25% of both neighbours takes the floor below --
31,809 / 766 / 31,805 on consecutive floors is a scan hole) and **stalk trim** (trailing storeys
< 15% of the WIDEST floor are dropped -- compared to the floor directly below, a 3-storey mast of
equal tiny plates passed). An upper-bound "trust" check (plate > 2.5x its band) was tried and
REJECTED: it threw away a correct 31,806 plate and fixed 1 building of 4.

### Orphans -- `tools/source_slice_orphans.py`

Every building the FBX has that the map does not. **Identity from mesh connectivity**: PLATEAU
buildings are welded to themselves, not their neighbours (PARCO is one component). A roof height map
was tried first and cannot separate touching buildings: unbridged it split PARCO into 9, bridged it
fused whole blocks into one 864,793 sq stud "building". Components STACKED in plan are merged, judged
on an outline of roof faces PLUS wall lines with holes filled -- PARCO's tower top is its own
roof-only component, and its podium roof is a ring; without the walls and the fill they never
overlap. Ground faces are excluded from outlines: PLATEAU draws them wider than the building and they
merged PARCO with covered neighbours. Geometry is every roof face inside the outline. Buildings keep
clear of live buildings and of each other (largest first).

2,689 FBX buildings; 1,366 already covered; **634 planned, 598 + 28 (triangulation-repaired) = 626
added live**, 514 + 30 greys archived. **PARCO = orph_703_1736, 23 levels.**

### Infrastructure is not a building

Six results were > 1,000 studs long and 2-5 levels -- elevated expressway / rail viaducts. The roof
envelope assumes a building standing on the ground, so it floored the space UNDER the deck and walled
off the street. Four were live and are removed to `ServerStorage.RemovedInfrastructure` (their two
displaced greys restored); the other two had been refused by the triangulator. **Next: build these
as a deck slab only.**

### Result

| | start of night | now |
|---|---|---|
| FBX building footprint covered | 49.8% | **86.5%** |
| source-slice buildings | 1,376 | **1,998** |
| greys | 894 | **352** |
| >4x area jump between floors | 83 of 1,254 (6.6%) | 67 of 2,004 (3.3%) |
| pinched floors | many | 2 |

Still open: 85 buildings with a floor > 1.5x the one below (mostly older wall-cut plans; some may be
real overhangs); 8 orphans unbuilt on overlap edge cases; viaduct decks; single-storey buildings
(< ~7 m) are below the two-level minimum by design.

### Memory is the binding constraint now

Studio holds ~14 GB for this place: 219k-289k workspace parts plus **306k parts in ServerStorage**
(the rollback archives), ~26 KB a part. A plan-builder worker peaks at 1.03 GB. Twelve workers plus
Studio exhausted the 40 GB commit limit and crashed Claude Code (ENOMEM); run the sweep with Studio
CLOSED (8 workers, 11 min) or with ONE worker while it is open. `ChangeHistoryService:ResetWaypoints()`
frees nothing measurable. Deleting archives would -- that is the owner's call.

### Studio screenshots need the display on

`capture_screenshot` times out once the monitor sleeps, even with Studio in front. A hidden keeper
holding `SetThreadExecutionState(CONTINUOUS|SYSTEM|DISPLAY)` plus a 1-pixel mouse nudge brought it
back.

## WHOLE-MAP SWEEP Sept 20 — 1,133 plans generated offline for every remaining grey. UNSAVED.

The four sectors were hand-driven, one neighbourhood per session, and at ~30 buildings a sector the
~2,900 remaining greys were another 70 sessions. This is the same pipeline aimed at all of it at
once. **Nothing is applied** — Studio's plugin never reconnected this session (see below), so this
entry is offline work only: plans, gate, crowns, and the chunks Studio applies.

| | |
|---|---|
| remaining greys | 3,030 in 1,834 groups |
| plans generated | **1,287**, claiming **2,182 greys** |
| through the gate, chunked | **1,254** buildings over **2,136 greys**, 51 chunks |
| median mean-IoU vs the FBX | **0.997**; 1,208 of 1,241 measurable at or above 0.95 |
| levels | 6,497, median 4, max 33 |
| wall clock | **10.7 min** on 12 workers, plus 4 min for gate and crowns |

### `--box` instead of `--near`: circles overlap, boxes tile

`--near X Z R` selects a disc, and two disc sectors 700 studs apart with radii 500 and 450 share
ground — which is why sectors 2, 3 and 4 each re-offered buildings that were already live and had to
be filtered by hand. `--box X0 Z0 X1 Z1` is half-open on its max edges, so a grid of them partitions
the map: a group's centre falls in exactly ONE tile, no tile can claim another tile's greys, and the
tiles are independent processes. `tools/source_slice_sweep.py` drives 89 tiles of 600 studs over 12
workers and merges with the builder's own `deduplicate` so plans either side of a tile edge are
folded exactly as they would have been inside one run.

`--skip-names FILE` drops greys that are already replaced before grouping, so the sweep never
re-plans ground that is done. `applied_greys.txt` / `applied_ids.txt` hold the 160 greys and 122
buildings the sectors shipped — derived from the plan directories, minus `fbx_6_705_2489_-10277`,
which has a plan on disk but was refused on the gate twice and never applied.

**Control, run before trusting any of it**: `--key 4_-1164_1279_-9107` regenerates a shipped plan
**byte-identically**. The patch changes selection only.

### The gate is mean IoU. `outside` is not a gate and never was.

`source_slice_pokeout.py`'s `outside` column is the **worst single level's** spill, not the
building's. The applied Cerulean Tower scores **97.8% outside** while its mean IoU is **0.977**. A
5% spill gate — which is how the column reads if you take it at face value — would have refused a
building the map owner approved by eye. The sector runs gated on mean IoU >= 0.95 and so does
`source_slice_chunks.py`; `--spill` exists, defaults to off, and should stay off unless someone
re-derives it against a control.

`--json=FILE` was added to pokeout so a thousand plans can be gated without a human reading a table.

### What the sweep CANNOT convert, and why that is probably correct

848 greys (28% of what remains) produce no plan, after the core bug below was fixed. The reasons,
aggregated over all 89 tiles:

| groups | greys | reason |
|---|---|---|
| 387 | 587 | FBX band shorter than 2 storeys (35.7 studs) |
| 51 | 99 | no FBX section over the grey footprint at all |
| 31 | 88 | bands share no common area for a core |
| 15 | 18 | only 1 usable storey |
| 9 | 17 | no band survived the minimum thickness |

The 31 core-intersection failures are the one class that may be a rule rather than the data: the
builder's contract requires a single core inside EVERY level, which a genuine setback tower cannot
always satisfy. Worth 88 greys, and it changes a Luau invariant, so it is the owner's call.

Measured, so the call can be made on numbers: of the 31, **21 have at least one section that is
several disjoint polygons** — two wings, or a courtyard — and only **10 are single-piece all the way
up**, i.e. a genuine shift or setback. So most of this class is the intersection being taken across
wings that do not line up, not a tower that leans. A per-component core would recover most of it and
a core-free building would recover the rest; both change what `SourceSliceBuilder` guarantees, and
the core is what the future collapse work is supposed to hang off. Do not change it casually.

**These are not all small buildings.** Of the band-too-short groups, 186 (355 greys) have a live grey
at least 36 studs tall, and the extreme case is a **362-stud grey over a 14-stud FBX band**. That is
not a rule to relax: it means the scan recorded almost nothing at that footprint, and flooring it
would be inventing 20 storeys from 14 studs of evidence — the same mistake as the four failed crown
fitters, which is documented below as caused by the data and not the algorithm. Left grey is the
honest outcome; a low-rise or fabricated-storey pass is a decision for the map owner, not a bug fix.

### BUG FOUND BY THE SWEEP: 166 groups were rejected by float rounding, not geometry

The second-largest rejection class was `core would fill the footprint`. It is unreachable by the
numbers: the guard needs `4*hx*hz / fbx > 0.6` and `fbx` is already known to be at least the
400 sq stud `MIN_FOOTPRINT`, so a 4-stud core is 4% of the smallest plate allowed.

The shrink step is why. It solves for the scale that puts the core **exactly** on
`MAX_CORE_SHARE`, so `4*hx*hz/fbx` comes back as 0.6 by construction and the re-test
`> MAX_CORE_SHARE` is decided by whether that division rounds to 0.5999999999 or
0.6000000000001. Measured on two rejected groups: shares of **0.744 and 0.996 before the shrink,
0.600000000000001 after it**. A coin flip refused **166 groups / 228 greys**.

The guard's real job is the case where `max(2.0, hx * scale)` clamped the shrink, so only that
should fail: the re-test now carries `+ 1e-9`. Both sample groups build immediately afterwards
(4 levels and 3 levels), and the shipped-plan control still regenerates **byte-identically**, so
nothing already applied is affected.

### Applying: `src/server/SourceSliceSweepApply.luau`

The sector applies were ad-hoc `execute_luau`, and that is how a stage was once mislabelled and
nearly replaced the wrong 46 greys. 1,133 buildings cannot be done that way. The module is the same
sequence with the two rules from that near-miss built in: **the lock folder is the first statement**
(a replayed call returns the first run's summary instead of building a second stage) and **the stage
is never found by searching** (`StagePlans` returns the folder; counts are asserted before anything
is bound or moved). `Preview` / `Commit` / `Discard` / `Run` / `Status`; chunks arrive over the sink
because a chunk with its crowns is megabytes.

### MCP: the plugin scans 58741-58745 and takes the first FREE server

Studio has been open since Sept 17 and the map is still unsaved, so restarting it was not an option.
The plugin had attached to a **stale server from Sept 17** holding 58741; this session's server had
fallen back to 58742. Reading the plugin settled how it picks: `discoverPort()` probes 58741..58745
and takes the first that reports `mcpServerActive` with `pluginConnected:false`. Fix without
restarting Studio: kill every stale node server so only this session's remains, and proxy 58741 to
it. **The proxy must listen on IPv6 as well as IPv4** — Windows resolves `localhost` to `::1` first,
so an IPv4-only proxy is invisible to the plugin while `curl` finds it. Even so the plugin attached
once and dropped; it never came back this session, so nothing was applied.

## CROWNS FINAL Sept 19 — parapet by default, FILLED wedge shell where earned. UNSAVED.

The 22 interesting crowns are back on the **sealed wedge shell** -- the version the map owner
approved by eye ("the geometry looks really on point") -- but **filled instead of hollow**.

### `fillToward` in TriangleShell

A WedgePart is centred on its triangle, so simply raising the thickness bulges half of it OUTWARD
and fattens the building. `options.fillToward = Vector3` slides each wedge so its **outer face stays
on the triangle** and the thickness grows **inward**, towards the crown's own centre of mass. The
silhouette is unchanged; the interior fills in.

Inward is decided per triangle by `dot(fillToward - triangleCentroid, normal)`, not by winding --
this scan's winding is not consistent enough to trust (the same reason `source_slice_crown_seal`
walks boundaries undirected).

Thickness **10 studs**, chosen by eye against 4: at 4 the individual faces still read separately, at
10 they merge into one mass. 0 triangles skipped at either.

### Live totals

| | |
|---|---|
| crown parts | **9,485** = 857 parapet + 8,628 filled wedge |
| 100 dull buildings | parapet, ~8.6 parts each |
| 22 interesting buildings | filled shell, ~392 parts each |
| workspace | 219,300 parts, 1,315 MB |
| per source-slice building | 183 parts |

Still 3.5x below the 33,356-part wedge-shell peak, because the cost now lands only on the 18% of
buildings that earn it. The heaviest are `fbx_6_2510_2462_-12844` (1,272 parts, 234x338 studs) and
`fbx_4_-2192_1412_-10100` (950) -- worth checking by eye before scaling to more sectors.

## CROWNS: PARAPET BY DEFAULT, DETAIL WHERE IT IS EARNED. Sept 19. UNSAVED.

Four attempts at reconstructing rooftop detail from the scan all failed, each differently:

| attempt | failed as |
|---|---|
| wedge shell, every triangle -> 2 wedges | fans of plates at every corner |
| slices grouped into plateaus, intersected | wiped roof clutter; 25 crowns -> 1 box |
| slices -> per-level rectangles, merged up | **floating slabs** (MIN_SIDE applied to height) |
| per-object box-or-prism | terraced again; 17 prisms of exactly 4 studs on Cerulean |

**The reason is the data, not the algorithm.** The median crown component keeps only **0.38** of a
closed box's surface area -- the scan saw a roof's top and one or two sides and nothing else. There
is no solid in there to recover; every fitter was inventing the missing half, and inventing it
differently each time is what produced the artefacts. The FBX itself is clean: the Cerulean crown is
89 triangles over 100 vertices with **zero** slivers.

### The split

* **DULL -> parapet.** The top floor's OWN outline, extruded 2-8 studs, through `PolygonSlab`. It
  invents nothing: those polygons are already validated by `SourceSliceBuilder`.
  `tools/source_slice_crown_parapets.py` + `src/server/CrownParapet.luau`.
* **INTERESTING -> left alone and marked** `CrownInteresting` with the reason, for detailed or hand
  work. Domes, billboards, big stepped crowns.

### What counts as interesting, measured over 181 distinct crowns

Two signals separate cleanly; nothing else did.

| | median | p75 | p90 |
|---|---|---|---|
| sloped share of surface area | **0.00** | 0.05 | 0.17 |
| band height (studs) | 24 | 28 | 47 |

`slopeShare >= 0.20 or bandHeight >= 50` selects **25 of 181 (14%)** -- the Cerulean Tower among
them. Loosening to 0.15/45 gives 31; tightening to 0.25/55 gives 15. **Rejected**: a taper test
(bottom-third vs top-third footprint IoU) comes out bimodal at exactly 0.00 or 1.00 because one
footprint is usually empty, so it carries no information.

### Live

**22 of 122** buildings flagged interesting and keeping their box crowns; **100** now carry a
parapet. Crown parts **1,501 -> 1,335** (857 parapet + 478 box), from 33,356 at the wedge-shell
peak. Zero piece failures. Workspace 211,150 parts. A source-slice building is **116 parts**.

Next per the map owner: a script to scatter AC units and roof clutter procedurally, rather than
trying to recover them from a scan that never recorded them.

## BOX FITTER BUG Sept 19 — I shipped floating slabs. Root cause and fix. UNSAVED.

The owner photographed crowns as plates hanging in mid-air with gaps under them. **My bug.**

`MIN_SIDE = 3.0` guards the minimum box dimension, and I applied it to **height** as well as to the
plan dimensions. Slices were `STEP = 2` studs apart, so **any box existing for a single slice was 2
studs tall, failed the 3-stud test, and was deleted**. Measured on the shipped data: **622
overlapping box pairs across 47 crowns had air between them**. MIN_SIDE now guards plan dimensions
only; height floors at `STEP * 0.9`.

**I had checked the wrong thing.** Before rolling out I verified box tops reached the building top
and box bottoms started at the band, reported both clean, and never looked at the middle. The check
that would have caught this is a voxel comparison, which now runs every build.

### The verification that now runs on every build

Boxes are rasterised back onto the same grid the slices came from, and four numbers come out:

| | meaning | now |
|---|---|---|
| `cover` | of the sliced solid, how much got boxed | median **95-97%**, worst 81% |
| `over` | box sitting where the FBX had nothing | **0.0% everywhere** |
| `drop` | box with SOLID below that we failed to box — **the bug** | median **0.0%**, worst **2.4%** |
| `float` | box with EMPTY below — a real canopy or ledge | median 0.0%, worst 8.4% |

Splitting `drop` from `float` is the point. A box over empty FBX is a real overhang and correct; a
box over solid FBX we simply failed to cover is the defect. A single "floating" number conflates
them and would have hidden the bug again.

**An earlier pairwise gap check was wrong and must not be reused**: it flagged any two boxes
overlapping in plan with air between them, which a third box may legitimately fill.

### Two decompositions tried before this one

* **Canonical row-runs** (contiguous z-runs per row, merged across rows). Perfectly stable between
  heights, but fragments on ROTATED shapes where every edge is a diagonal staircase: 294 boxes per
  building for full coverage, or **19% coverage on the Cerulean n-gon** once strips under MIN_SIDE
  were dropped.
* **Greedy largest-rectangle** is unstable -- a one-cell change reshuffles the partition, so
  rectangles rarely recur and the vertical merge rarely fires (median box exactly one slice tall,
  569 boxes for sector 2 alone). But that is a PART COUNT problem, not a correctness one.

Greedy on a **coarse grid** wins: `CELL = 4`, `STEP = 4`, `MIN_SIDE = 4`. 94-97% coverage, 0%
overhang, ~8 boxes per building. The missing few percent is sub-4-stud detail, deliberately left
out -- the owner asked for rooftops not to be overkill.

**Live: 957 boxes + 544 wedges on the 4 buildings that fit no box = 1,501 crown parts**, from
33,356. Workspace 211,316 parts. A source-slice building is 117 parts, down from 439.

## CROWNS AS SOLID BOXES Sept 19 — the shell was the wrong representation. UNSAVED.

The map owner reported fan-shaped clusters of thin plates at rooftop corners, "like 20 vertices per
corner, which isn't true in Blender", and asked for solid geometry and a box fitter.

### The FBX is clean. Every artefact was mine.

Measured on the raw `world_triangles.npz` in the Cerulean crown box: **89 triangles over 100
distinct vertices** (identical at 0.001 and 1.0 stud weld tolerance, so no near-duplicates),
**0 duplicate faces**, **0% sliver triangles**, median face **533 sq studs**, smallest **63**.
The owner was right — there is nothing wrong with the source.

Two things in my pipeline manufactured the mess:

1. **Clipping to the crown band makes slivers.** 9.7% of clipped triangles have a shortest altitude
   under 1 stud, with aspect ratios to **9,085:1**. `clip_band` fan-triangulates each clipped
   polygon and `MIN_TRI_AREA = 0.05` lets needles through. Sealing and dilation *reduce* this
   (9.7% -> 9.1% -> 4.6%), so they were never the cause.
2. **A thin feature shelled becomes a fan.** A mast, a fin or a sign has two surfaces a few studs
   apart. Rendered as two 0.6-stud plates they overlap and splay at every corner. That is the fan.

### `tools/source_slice_crown_boxes.py` + `src/server/CrownBoxes.luau`

A box is **one part, solid, seamless, sliver-free**, and roof clutter is overwhelmingly boxy. So the
crown is no longer a surface at all:

1. Slice the crown band every `STEP` (2) studs — the same proven machinery the floors use. Each
   slice is a SOLID footprint, not a surface.
2. Group consecutive slices into plateaus by IoU (`PLATEAU_IOU = 0.80`).
3. Per plateau take the **intersection** of its slices, so a box can never overhang what was there,
   and greedily cut it into maximal rectangles (histogram method, `CELL = 2` studs).
4. Emit one `Part` per rectangle spanning the plateau's height.

All of it runs in the **building's own yaw frame** — only 3.2% of vertical crown faces are
world-axis-aligned, so a world-axis fitter would find almost nothing. Local (x,z) in the payload are
the same (a,b) coordinates the plan's level pieces use, so the Luau side reuses that mapping.

**APPLIED to all 122 buildings.** Crown parts **33,356 -> 1,458** (684 boxes + 774 wedges kept on
the 5 buildings the fitter could not fit) = **23x fewer**. A source-slice building is now **117
parts, down from 439**. Workspace **243,171 -> 211,273**. Cerulean Tower: **416 wedges -> 18 boxes**.

Memory only moved 1,298 -> 1,289 MB in the same session, well short of the ~200 MB the part count
implies. Studio does not reclaim the tags promptly, so **trust the part count, not that figure**,
until it is measured in a fresh session.

Coverage was checked before rolling out, not assumed: boxes start at the band (median gap 0.0
studs), and the box top falls more than 8 studs below the building's own top on only **8 of 118** --
thin masts and spires the fitter correctly declines to model. One building (`fbx_16_6924_1163_-3075`)
fits no box at all; 5 in total keep their wedge shell rather than be left with a bare roof.

### Slopes are OFF by default

`--wedges` emits the genuinely sloped FBX faces (|normal.y| between 0.15 and 0.92, at least 25 sq
studs) alongside the boxes, with thickness scaled by triangle size so a big plane reads as a ramp
rather than paper. **Tried and turned off**: the box stack already expresses Cerulean's sloped roof
as steps, so the slope plate just floats above them as a blade, and it overhangs the boxes by 38
studs. Boxes alone look right. Turn it on per building where a signature slope matters.

## CROWNS BOUNDED Sept 19 — two defects found by eye, both mine, both measured. UNSAVED.

The user's screenshots showed giant diagonal sails and slabs floating around small buildings. Two
separate causes, both in code I wrote.

### 1. The crown band reached 140 studs up regardless of the building

`MAX_CROWN = 140.0` plus `OUTLINE_PAD = 14.0` let a neighbouring tower inside the band. Measured:
**92 of 123 crowns reached above their own building's top**, and the mean crown was **1.24x the
height of the building under it**. `fbx_16_13294_1839_-3533` is a 23-stud building whose own FBX
stops at 171.6 and whose grey stops at 211 — its crown ran to **304**.

Fix: ceiling at the building's OWN top, which the plan already records.
`ceiling = max(sourceInfo.fbxTop, sourceInfo.greyTop) + CROWN_HEADROOM(10)`. `MAX_CROWN` is now only
a backstop for a plan with no recorded top.

Result: **92 -> 0** crowns above their own top. Median crown height **52 -> 27 studs**, max 163 -> 88.

### 2. The seal threw membranes across open sky

`fill_loop` filled ANY boundary loop, including a crown's genuine outer boundary, producing one
enormous triangle. Measured against the raw soup: the seal made the largest triangle bigger on
**24 of 123 crowns**; on `fbx_4_-9770_4222_-4948` it went **2,450 -> 22,380 sq studs**. One live
wedge was **0.6 x 92 x 90 studs** — the sail in the screenshot.

Fix: `MAX_GAP` in the sealer. A crack is narrow by definition, so a fill triangle whose **shortest
altitude** (`width()` = 2*Area/longest edge) exceeds the cap is not closing a crack. Rejection is
per triangle, not per loop, so a loop that is a thin crack at one end and a real opening at the
other gets zipped where it is thin and left open where it is not.

**Tuned by sweep, not guessed.** Over 123 crowns (10,910 raw triangles, raw largest 4,074 sq studs):

| cap | 4 | 8 | 12 | **16** | 24 | 40 | none |
|---|---|---|---|---|---|---|---|
| cracks closed | 18% | 39% | 54% | **65%** | 75% | 81% | 83% |
| wedges | 26k | 30k | 32k | **33k** | 34k | 35k | 35k |
| largest triangle | 4,180 | 4,180 | 4,180 | **4,180** | 4,180 | 4,180 | **26,444** |
| triangles > 2,000 | 29 | 29 | 29 | **29** | 34 | 45 | 95 |

The sail is an *uncapped* problem: any cap at all kills it. **At any cap up to 16 the seal adds
nothing bigger than the FBX already had**, so 16 is the largest safe cap and buys the most closure
for no new large geometry. `MAX_GAP = 16.0`.

### Live after both fixes

Crown wedges **37,982 -> 33,356 (12% fewer)** at the tuned cap, 273 per building (was 311), with
crack closure back to **60-72% per sector**. Largest crown wedge face **3,246 sq studs**, 17 over
2,000 -- all of them real roof planes the FBX already had, none added by the seal. Workspace
243,171 parts, 1,298 MB. The worst offender `fbx_16_13294_1839_-3533` now has a **61-stud crown on
its 23-stud structure, down from 143**.

### Why crowns are expensive, in one line

**Floors pay per storey; crowns pay per triangle.** One slab Part covers a whole storey at any size,
but every crown triangle is 2 WedgeParts and the FBX hands over a scan-resolution soup — a plain box
(an AC unit) arrives as 12 triangles = **24 WedgeParts** where Roblox has a Part primitive that
would do it in **1**. Crown cost is also nearly FLAT with building height: 200 wedges on a building
under 60 studs vs 286 at 100-150. **72% of buildings are under 100 studs and carry 61% of all crown
wedges.**

### NOTE: Workspace.Shibuya was moved to ServerStorage

The FBX reference model is now `ServerStorage.Shibuya` (16 MeshParts, intact) — not deleted. Scripts
must not assume `workspace.Shibuya` exists.

## SECTORS 2-4 APPLIED Sept 18 — 122 source-slice buildings live, all with crowns. UNSAVED.

| sector | `--near` | applied | greys | crowns | gate |
|---|---|---|---|---|---|
| 1 Cerulean | `387 -894 500` | 24 | 35 | 9,126 w | IoU 0.998 |
| 2 | `387 -194 450` | 27 | 33 | 7,572 w | IoU 0.996, 27/29 |
| 3 | `1165 -116 450` | 35 | 46 | 11,066 w | IoU 0.998, **34/34** |
| 4 | `-313 -894 450` | 33 | 43 | 8,306 w | IoU 0.998, 32/33 |

Archives: `…_0a6b883f` (35), `…_b81a036d` (33), `…_e9df643a` (46), and sector 4's. The two
buildings from the very first test finally have crowns too (`fbx_4_-9770_4222_-4948` 1,686 wedges,
`fbx_4_-10904_1766_-9267` 226). **0 of 122 buildings are now crownless.**

Live: **3,030 greys + 122 BuildingSourceSlice**, 247,813 parts, 1,521 MB part memory
(**6.3 KB/part**, stable across every measurement). Source-slice: 50,786 parts over 559 storeys,
**37,982 crown wedges = 75% of them**.

Dropped on the gate and NOT shipped: `fbx_14_-77_855_-813` (77.3% out), `fbx_14_2621_2300_317`
(74.1%), `fbx_6_705_2489_-10277` (80.8%, offered again by sector 4 and refused again).

### Sectors overlap — filter before staging

A 500 and a 450 radius 700 studs apart share ground. Sector 2 offered 5 plans for buildings already
live, sector 3 offered 2, sector 4 offered 3. **Drop any plan whose `id` is already a live
`BuildingSourceSlice_*` before staging**, or `Capture` binds a grey that no longer exists.

### execute_luau REPLAYS — this nearly applied the wrong greys

The staging call ran ~3 times. It created duplicate stages **and mislabelled one**: a stage holding
sector 3's 35 models came back tagged `sector4`, because the second copy searched for "the stage
without a `Sector` attribute" and found the first copy's stage before it had been tagged. Applying
that would have replaced the wrong 46 greys. Caught because `Capture` reported 33 outputs for a
35-plan bundle. Nothing was applied; five stages were destroyed and the work redone.

Two rules that make this safe, both now used:
1. **Take a lock folder as the FIRST statement**, before any HTTP or building, not at the end.
2. **Never identify a new stage by searching.** `Builder.StagePlans(plans)` returns the folder —
   hold that reference. Then `assert(#stage:GetChildren() == #plans)` and
   `assert(r.outputs == #plans)` before Apply.

## SECTOR 2 APPLIED Sept 18 — 54 source-slice buildings live. PERFORMANCE MEASURED. UNSAVED.

**Archive `ShibuyaBeforeSourceSlice_b81a036d-50b1-4d80-9d42-b47293247c11` (33 originals).**
Sector = `--near 387 -194 450`. 34 plans, 5 dropped as already live (sectors 1 and 2 overlap — a
500 and a 450 radius 700 studs apart do), 2 dropped on the gate, **27 applied, 33 greys replaced**,
27 sealed crowns / 7,572 wedges. Gate: median IoU **0.996**, p10 0.972, 27/29 >= 0.95. The two
failures were `fbx_14_-77_855_-813` (77.3% out) and `fbx_14_2621_2300_317` (74.1%).

Live: **3,119 greys + 54 BuildingSourceSlice + Building1/2/3**, 226,352 BaseParts.

### PROTECTED zones — Shibuya Sky is fenced off in code, not by a flag

`PROTECTED` in `source_slice_plan_builder.py` rejects any group with a **member** inside the circle
(testing the group centre alone would let a group with one foot in the zone through). Currently
`(-630, 48, r=260)` — **Workspace.Buildings.Building1, "Shibuya Sky"**: measured X -793..-468,
Z -120..217, Y 57..967, **29,907 parts with a furnished interior**, the tallest thing on the map.
It is not a `BuildingSmooth_*` grey so it was never a candidate, but the fence also stops a
generated neighbour landing on it. `--exclude X Z RADIUS` adds more, repeatable.

### PERFORMANCE — measured in this place, not estimated

| | greys (3,119) | source-slice (54) |
|---|---|---|
| parts / building | 53.8 | **439** |
| structural parts / storey | 14.8 | **25.3** (1.7x) |
| crown wedges / building | 0 | **309** |
| crown share of the building | — | **70%** |

Memory by `Stats:GetMemoryUsageMbForTag`, 226,352 parts: PhysicsParts **617 MB**, Instances
**589 MB**, GraphicsParts **202 MB**, GraphicsSpatialHash 35 MB = **1.44 GB, ~6.4 KB per part**.
Studio edit mode inflates this, so treat 6.4 KB as an upper bound.

**`workspace.StreamingEnabled` is FALSE.** For a map this size that is the single decision that
decides whether the whole thing is viable. Measured resident sets around one point: r500 = 10,799
parts, r1000 = 27,281. With streaming a client holds tens of thousands of parts, not the map.

Whole-map projection (3,190 greys -> ~2,530 buildings at the measured 1.26 greys/building,
~12,600 storeys): structure ~319k parts + crowns ~782k = **~1.1M parts, ~7 GB unstreamed**.
**Crowns are 71% of that.** PC is fine with streaming; console needs streaming; mobile is out.

**Hit cost does NOT regress** — this was the real worry and it is measured. Parts inside the
`destroyAlongCylinder` volume (r15, 200 studs): converted sectors 129 and 16 to carve; untouched
greys 105 and 146. Crowns are tagged `NoCSG` so they are deleted, not carved.

**Crown reduction headroom** (8,371 crown triangles over 54 buildings): 59% vertical faces,
29% horizontal, 11.5% sloped; **43% are right-angled**, i.e. half of a rectangle. A rectangle is
2 triangles = **4 wedges** today but **1 thin Part**; a closed box (an AC unit) is 12 triangles =
**24 wedges** but **1 Part**. Only 3.2% of vertical faces are world-axis-aligned, so any box fit
must work in the **building's own yaw frame**, not world axes. Coplanar merging alone is weak:
3,809 distinct planes for 8,371 triangles, only 2.2 triangles per plane.

**Measured and rejected:** setting `CanTouch = false` on all 16,698 crown wedges moved
PhysicsParts / Instances / GraphicsParts by **0.0 MB**. Do not claim it as a memory win.

## CROWNS SEALED Sept 18 — the FBX is a scan and its crowns had holes. 9,126 wedges live. UNSAVED.

The user reported "uneven gaps ... we need a way to fill these in so it is one unified mesh", and
added the reason: the FBX came from drone/photogrammetry scanning, so it is not going to be a
perfectly closed model. That is exactly what the measurements say.

**The raw soup across 25 crowns carries 1,770 crack edges** — edges with only one triangle on them
that are not a legitimate top or bottom rim. **82% of them sit within 3 studs of another crack
edge**, i.e. they are the two sides of a slit, not a surface that merely ends. On the Cerulean
Tower they are ~2 studs wide, which is precisely the dark vertical slot in the user's screenshot.

**Welding does not fix it.** At a 0.25-stud tolerance the Cerulean crown goes 131 -> 130 vertices.
The vertices are already shared; the faces are simply absent. The repair has to *add* geometry.

### `tools/source_slice_crown_seal.py` — what it does and why

1. Drop slivers `TriangleShell` would refuse anyway (under the 0.05 stud minimum). Doing it in
   Python rather than at build time means the hole they leave gets filled by step 4 instead of
   silently staying open. 59 triangles across the sector.
2. Weld near-coincident vertices so boundary edges pair up.
3. Walk the boundary into closed loops, **undirected**. A scan soup's winding is not consistent
   enough to follow half-edge direction; doing so drops whole loops on the floor.
4. **Fill each loop by minimum-area triangulation** (the standard Barequet/Liepa O(n^3) DP). A
   slit's boundary runs up one side and back down the other, so filling the loop *is* zipping the
   slit — no pairwise edge matching, and no gores left at the ends of a slit.
5. **Dilate each triangle in its own plane.** A 0.6-stud shell centred on the surface leaves a V
   notch of depth ~t/2*tan(a/2) on the outside of every convex fold; the dilation laps over the
   neighbour instead. This closed a visible hairline the seal alone left.

Left open on purpose: the **bottom rim** (buried in the floors below) and a **flat loop at the very
top** — the Cerulean helipad is genuinely open in the FBX and the user wants to model it by hand.
`--cap-top` fills those too.

| | raw | sealed |
|---|---|---|
| triangles | 2,924 | 4,585 |
| wedges | 5,730 | **9,126** |
| crack edges | 1,772 | **360 (80% closed)** |
| crack *length* | 45,810 studs | **8,628 studs (81% closed)** |
| Cerulean Tower | 72 cracks | **2** |

**Measured, not assumed**: the sealed mesh's bounding box grows by at most **1.0 stud**, so nothing
the fill added reaches outside the building. A/B screenshots from one camera confirmed the three
vertical slits on Cerulean's crown are gone.

### Two traps hit while doing this — both cost a rebuild

- **The crack metric is meaningless after dilation.** Dilation detaches every triangle on purpose,
  so every edge reads as a crack: 1,770 -> 11,204. Always count cracks *before* dilating.
  `seal()` does this and reports `stats["cracks"]` from the undilated mesh.
- **Uncapped dilation throws needles.** Offsetting a triangle's edges outward moves each corner
  along its bisector by `pad/sin(half-angle)`, which is enormous at the tip of a sliver. The first
  build grew visible spikes off the Cerulean rim. The fix is to cap the step by the triangle's own
  **inradius** (`2*Area/perimeter`) — that is its own thickness, so a sliver barely moves while a
  healthy triangle grows the full pad. A flat `MAX_PAD_STEP` alone does not work.

### Studio's edit camera fights you — and the screenshot follows it

`workspace.CurrentCamera.CFrame` in edit mode **accepts position and silently reverts rotation**;
writing an identical CFrame is fine, writing a new rotation snaps back. Screenshots then look wrong
in a way that is easy to misread as broken geometry. **Set `cam.CameraType =
Enum.CameraType.Scriptable` first** and the rotation sticks. To inspect built geometry alone, hide
the FBX (`workspace.Shibuya` parts to `Transparency = 1`) and put it back to **0.12** afterwards.

### The sink now serves GETs

`tools/source_slice_sink.py` gained `GET /get/<repo-relative-path>`, so Studio can pull a payload
too big to paste into an `execute_luau` call:

```lua
HttpService:JSONDecode(HttpService:GetAsync(
    "http://127.0.0.1:58999/get/src/server/SourceSliceCrowns.json"))
```

Paths are resolved under the repo root and refused if they escape it.

### Rollback

The pre-seal crowns were **not kept in the place** — 5,730 orphan parts in `ServerStorage` would
have been saved along with everything else. They are reproducible exactly:

```
python tools/source_slice_crowns_batch.py tools/source_slices/plans_sector2 --no-seal
```

then rebuild the crowns in Studio. Models carry a `CrownSealed` attribute so a rebuild is resumable
and idempotent.

## SECTOR APPLIED Sept 18 — 24 buildings + 25 crowns around the Cerulean Tower. UNSAVED.

**Archive `ShibuyaBeforeSourceSlice_0a6b883f-ef70-4397-bbf0-6541f33410dc` (35 originals).**

Live now: **3,152 `BuildingSmooth_*` + 27 `BuildingSourceSlice_*` + Building1/2/3 = 3,182**
(was 3,193; 35 greys consolidated into 24 buildings is the difference).

| | |
|---|---|
| sector | `--near 387 -894 500`, the Cerulean Tower neighbourhood |
| groups in radius | 34 |
| plans generated | 26 |
| applied | **24** (1 dropped on the gate, 1 already applied earlier) |
| greys replaced | 35 |
| levels / parts | 178 / ~structural |
| **crowns attached** | **25 buildings, 9,126 wedges** (sealed; was 5,730 raw) |

Gate before applying (`source_slice_pokeout.py`): median IoU **0.998**, p10 0.990, **22 of 23 plans
>= 0.95**. The one failure, `fbx_6_705_2489_-10277` (80.8% outside, IoU 0.595), was **dropped rather
than shipped** — its greys are untouched and still live.

### New in the pipeline

- **`--near X Z RADIUS`** — spatial selection, so one contiguous neighbourhood can be replaced and
  reviewed together instead of scattered seeds. This is how to scale: sector by sector.
- **Core shrink-to-fit.** `MAX_CORE_SHARE` used to reject a building outright when the largest core
  exceeded 60% of the plate; it now scales the core down and only rejects if even the 4-stud minimum
  will not fit. On the first sector run **6 of 10 skips were this one guard**; after the fix the
  sector went from 15 plans to 26, and 11 of them have `coreShrunkToFit = true`.
- **`tools/source_slice_crowns_batch.py`** — one crown per plan, bounded by that building's OWN top
  outline (buffered 14 studs), never a bounding box. In a dense sector a box pad reaches into the
  neighbours and drags their crowns in.

### Crown behaviour decisions made here — change them if wrong

- Crown wedges are tagged **`NoCSG`**, so `HitHandler` deletes them on a hit rather than carving.
  They are 0.6-stud shells; carving would leave slivers and cost a lot of CSG.
- Thickness **0.6 studs**, default concrete colour so they read as part of the building.
- **`Builder.Audit` will now fail on any building with a crown**, because it asserts every BasePart
  in the model belongs to a declared floor (`"Structural part outside declared floors"`). Audit
  before attaching crowns, or teach the audit to allow `ShellWedge`-attributed parts.

### Known gap

The two buildings applied earlier (`fbx_4_-9770_4222_-4948`, `fbx_4_-10904_1766_-9267`) have **no
crown** — they predate the crown work and are outside this sector's extraction.

## CROWN SHELL (Sept 18) — geometry above the last floor, as wedges. PROTOTYPE, not applied.

The user's idea: everything above a building's last floor -- stepped tops, ledges, parapets, plant --
should be *modelled*, not floored. It needs no storey layout, so it needs no slicing: **the FBX
already describes it, so render those triangles directly.**

- `src/server/TriangleShell.luau` — `Build(parent, triangles, options)`. Any triangle is two right
  triangles joined at the foot of the altitude from the vertex opposite the longest edge, and a
  Roblox `WedgePart` **is** a right-triangular prism. So one triangle costs two wedges **at any
  orientation**, including vertical. Degenerate triangles are skipped and counted, never clamped —
  clamping would push the shell outward, which is the failure mode this project keeps hitting.
- `tools/source_slice_crown.py <greyKey> <fromY> <toY> [pad]` — pulls the FBX triangles for that
  band into `src/server/SourceSliceCrowns.json`, which Rojo syncs as a ModuleScript.

**Prototype on `6_4510_4915_-8852`, Y 815–872:** 132 clipped triangles -> **250 wedges**, built in
**4 ms**. Measured `PartExtents`: Y **814.7–872.3**, extent 189 × 168 — sitting exactly on the tower
(which ends at 815.1) and correctly narrower than its 224 × 212. Live in
`Workspace.CrownPreview`; **not attached to any building.**

### Two things measurement corrected

1. **The crown is not a slope.** The shrinking sections (21,313 -> 10,806) read like a ramp, but the
   triangles are **37 horizontal, 95 vertical, ZERO sloped**. It is a stepped/terraced top. The
   wedge shell reproduces it exactly either way, but do not describe it as a sloped roof.
2. **Triangles must be CLIPPED to the band, not selected by it.** Selecting triangles that merely
   intersect `[y_from, y_to]` keeps them whole, so a wall triangle spanning the building drags the
   shell down with it — the first run produced a crown spanning Y 434–906 for a band of 815–872.
   `_clip_band()` now Sutherland-Hodgman clips against both planes and re-fans.

**And once more: measure wedges with `PartExtents`.** An ad-hoc 8-corner check reported the
clipped crown as Y 785.7–905.8 when every triangle vertex was provably inside 815.00–872.00. Same
trap as ever.

### To attach a crown to a building

Not done yet. It needs the shell parented into the building's Model (alongside `Interior`) and a
decision on whether the wedges are CSG targets or `NoCSG` for HitHandler.

## APPLIED Sept 18 — three buildings LIVE. Map is UNSAVED.## APPLIED Sept 18 — three buildings LIVE. Map is UNSAVED.

### MISIDENTIFICATION — read before trusting any "Cerulean Tower" reference

The first apply targeted **`4_-9770_4222_-4948`** believing it was the Cerulean Tower. **It is not
the building the user meant.** The user's actual target is **`6_4510_4915_-8852`**, confirmed by
raycasting from their own camera. The two are easy to confuse and the distinction is sharp:

| | `6_4510_4915_-8852` (the real target) | `4_-9770_4222_-4948` (misidentified) |
|---|---|---|
| height | 189.4 m | 185.6 m |
| tower section | 22,297, **26-31 verts** (n-gonal all the way up) | 52,302, **5 verts** (pentagon) |
| crown | smooth taper 21,313 -> 10,806 over Y 815-870 | short ragged band |

**Identify a building by raycasting from the user's camera**
(`workspace.CurrentCamera.CFrame`), not by height plus a vertex count. Height alone put two towers
within 4 m of each other.

`4_-9770_4222_-4948` is still applied. Its replacement is a genuine improvement on its own terms and
was left in place; roll it back from `ShibuyaBeforeSourceSlice_122c0a0c-…` if it is unwanted.

### `6_4510_4915_-8852` — the real target, applied

Archive **`ShibuyaBeforeSourceSlice_af0a689b-bd57-4d90-9008-d18e6a0300af`**. 41 levels, 2,128 parts.

| | old grey | new slice |
|---|---|---|
| Y extent | 95.5–887.6 (**189.3 m**) | **95.5–815.1 (172.0 m)** |
| footprint extent | 196 × 172 | **224 × 212** |
| floors / parts | 45 / 2,334 | 41 / 2,128 |

Its crown is a real sloped roof, measured under the centre:

| Y | 815 | 825 | 835 | 845 | 855 | 865 | 870 |
|---|---|---|---|---|---|---|---|
| section | 21,313 | 19,673 | 17,144 | 13,729 | 12,950 | 10,806 | gone |

`crownTrimmed = 50` studs. **Y 815–870 (172–186 m) is now EMPTY** — floors correctly stop where the
slope starts, and the crown itself is not modelled. That zone is the target for the wedge shell.

### Pipeline bug fixed on the way

`source_slice_pipeline.sections()` crashed with `IndexError: index out of range` on this building:
`union_all(..., grid_size=.05)` can emit empty parts, and `line.coords[0]` on one killed the whole
run. Empty parts are now filtered before the seam-repair endpoint scan.

## APPLIED Sept 18 — first two buildings (see misidentification above). Map is UNSAVED.

**Archive: `ShibuyaBeforeSourceSlice_122c0a0c-6697-4e2f-8dab-c69b61dfe9c7`** (ServerStorage, holds
both originals). **The map has NOT been saved — press Ctrl+S in Studio to keep this, or close
without saving to discard it.**

Live count: **3,188 `BuildingSmooth_*` + 2 `BuildingSourceSlice_*` + Building1/2/3 = 3,193.**

| | replaced | with | result |
|---|---|---|---|
| **Cerulean Tower** | `BuildingSmooth_4_-9770_4222_-4948` | `BuildingSourceSlice_fbx_4_-9770_4222_-4948` | 42 floors, 946 parts |
| Tapering 10-gon | `BuildingSmooth_4_-10904_1766_-9267` | `BuildingSourceSlice_fbx_4_-10904_1766_-9267` | 13 floors, 262 parts |

Measured before/after (`PartExtents`, wedge-aware):

| Cerulean | old grey | new slice |
|---|---|---|
| Y extent | 34.0–810.3 (185.6 m) | **34.0–789.4 (180.5 m)** |
| footprint extent | 347 × 320 | **440 × 371** |
| parts | 522 | 946 |

Both user complaints are addressed. The grey stopped at 185.6 m with a **flat roof and storeys inside
the crown**; the slice stops at 180.5 m, below the crown. The grey's base was **347 × 320 against the
FBX podium's real 440 × 371** — it was under-covering by ~25% per side, which is the "not shape
matching properly".

**The sloped crown itself is still not modelled.** `PolygonSlab` emits horizontal plates only; a
slope needs vertically-oriented wedges, which is a new capability. Nothing is built up there now,
which is strictly better than a flat roof with floors, but the crown is absent rather than sloped.

### Cerulean Tower, measured (`4_-9770_4222_-4948`)

Height 776 studs = **186 m** (real Cerulean Tower is 184.3 m — the FBX→Roblox factor is 4.1828
studs/m, which is how it was identified).

| Y | metres | section | verts | |
|---|---|---|---|---|
| 57–141 | 5–26 | 70,870 | **24** | n-gonal podium |
| 159–177 | 30–34 | sliver / ~20,000 | — | podium→tower neck, **mesh hole** |
| 197–783 | 39–179 | 52,303 | **5** | pentagon tower |
| 786–795 | 180–182 | 12,598–18,813 | 33/23/17/14 | **sloped crown** (horizontal cuts through a slope) |
| 798–804 | 183–184 | 43,422 | 5 | crown top |

### Three builder fixes this seed forced

1. **Floors stop at the last STABLE band**, not the last height with any geometry. Crown bands are
   short and ragged, `bands()` drops them, but `top` used to point past them so the floor loop kept
   going and handed each crown level the *tower's* plate. That is precisely how a tapering building
   gets a flat roof with storeys in it. (`crownTrimmed`)
2. **`BAND_TRUST_SHARE = 0.4`** — a per-floor section under 40% of its own band is a slicing
   artifact, not a storey. Cerulean's podium→tower neck yields a **1,259 sq stud sliver** between a
   72,420 floor and a 58,309 floor; because the builder requires one core inside *every* level, that
   single sliver drove the intersection to zero and **rejected the entire 43-storey building**.
3. **Best probe, not first** — take the largest section in the probe window, since the nearest slice
   at a transition can be a sliver while a real section sits a stud away.

### Known imperfection in the applied Cerulean

One level of 43 (Y 159, the podium→tower neck) has a plate materially larger than the FBX geometry
at that height, because the FBX has only a 1,259 sq stud sliver there — a hole in the mesh. The
building needs a floor at that height regardless, so the plate is deliberate. Mean IoU over the
43 levels is **0.977**; the second building is **0.996**.

### `plans_v8` IS NOW STALE — regenerate before scaling

The three fixes above (stable-band clamp, `BAND_TRUST_SHARE`, best-probe selection) landed **after**
`plans_v8` was generated. Every plan in `plans_v8/` therefore predates them, and the crown fix in
particular is the one that stops a tapering building getting a flat roof full of storeys — the exact
defect the user reported. `plans_v8` also still carries the 2 plans that spill and any crown floors.

**Do not scale from `plans_v8`.** Regenerate (`--from-survey --limit 83 --out plans_v9`), re-gate
with `source_slice_pokeout.py`, and re-stage. Expect it to be at least as good, plus correct crowns.
The v8 stage in ServerStorage (`SourceSliceStage_e948c30c-…`) is likewise stale and can be dropped.

Note the two APPLIED buildings were built with the fixes and are not affected by this.

### Rollback

Move the two models out of `Workspace.Buildings`, move the two originals back from
`ShibuyaBeforeSourceSlice_122c0a0c-…`, or simply close Studio without saving.

## START HERE

Several sessions of this project ran on a premise that is now **measured and false**. Read, in order:

1. **THE GOAL** — what the user actually asked for, and the A/B that settled the strategy.
2. **plans_v5** — the current best batch and the numbers it passes on.
3. **Sept 17 — fifth metric error** — why the "under-coverage tail" was never real.
4. **Sept 17 04:00-07:00** — how the footprint premise died and how the plan builder was fixed.

Everything dated **September 16** below, plus the `MEASUREMENT WARNING` and `FBX triangle survey`
sections, is **superseded**. Their `fill` numbers, "933 greys oversized", and the 2.00x / 1.79x /
1.0001x oversize factors are all withdrawn. They are kept only so the reasoning can be audited.

**Three things that will save the next session:**

- **Never judge fit by extent or by a bounding box.** A WedgePart fills half its `Size` box,
  `Model:GetBoundingBox()` is pivot-oriented, and a rotated rectangle has the same extent as its own
  AABB. Four separate metrics were wrong for four different reasons. Use `PartExtents` for anything
  live and `tools/source_slice_pokeout.py` for anything against the FBX.
- **Validate a new metric on a known-good control before believing it.** The pokeout tool reported a
  37.9% median until it was checked against the hand-authored seed (0.0%, IOU 1.000) and taught to
  tell a hole in the mesh from a misplaced plate. It then read 2.0%.
- **The Shibuya export is not watertight.** Sections vanish at scattered heights. That single fact
  caused the band detection failure, the "unexplained" overlay overhang, and two bad metrics.

**Live map:** TestJJK, Studio ID `ef23da77-5868-44cf-b310-e9d5ec4e0817`, Edit. **3,190
`BuildingSmooth_*`** plus `Building1`/`Building2`/`Building3` (3,193 models), **0
`BuildingSourceSlice_*` live**, 49 `Shibuya*` archives in ServerStorage. Shibuya FBX = 16 MeshParts,
currently in **Workspace** where the user put it for comparison — leave it there.

**Nothing has ever been applied.** No `ShibuyaBeforeSourceSlice_*` archive exists. The map has not
been saved by any of this work. Everything in ServerStorage named `SourceSliceStage_*` is disposable.

| Piece | State |
|---|---|
| `PartExtents` / `SourceSliceLiveExtents` | **Written, run live.** The measurement infrastructure. |
| `SourceSliceBuilder` / `Replacement` / `Verification` | Written, tested. Overlap tolerance raised 0.1 -> 0.5, see below. |
| `SourceSliceFbxSample` (seed `16_7714`) | **Staged and measured live.** Confirms there is no footprint win at that seed. Do not Apply. |
| `plans_v4` (52 plans, 191 greys) | **Generated, gated, staged live: 50 good / 1 bad.** Never previewed by the user, never applied. |
| Live buildings | **Unchanged. Not saved.** |

## plans_v5 — the current best. Floors follow the FBX to a median IoU of 0.997.

`python tools/source_slice_plan_builder.py --from-survey --limit 83 --out tools/source_slices/plans_v5`

**Offline gate** (`source_slice_pokeout.py`, selection matching the builder):

| | v5 |
|---|---|
| plans / greys consolidated | **56 / 205** |
| median mean-IoU vs the FBX section | **0.997** |
| p10 | **0.991** |
| worst plan | **0.923** |
| plans at IoU >= 0.95 | **54 / 56** |
| under-coverage | median 0.3%, max 23.0% |
| plans >5% spill | 2 / 56 (`250_79` 61.1%, `130_8` 6.3%) |

**Staged live** (`SourceSliceStage_cdc30897-…`): **53 of 56 built, 51 good, 2 bad.**
327 levels, 7,748 slab parts (7,746 of them wedges), 9,404 structural parts.
389 levels across the batch carry 452 pieces — 49 levels are genuinely multi-piece.

### Both remaining defect classes are now diagnosed and fixed

**1. "Slab protrudes beyond its source polygon" (`250_25`, `410_28`) — FIXED, audit now 53/53.**
Measured rather than assumed: the maximum corner displacement is **0.0024 and 0.0027 studs**, across
212 and 314 slabs. That is float32, not geometry — `slabShape` round-trips every corner through
WORLD space and Roblox stores CFrames as float32, so at |x| ~ 3000 a corner moves by thousandths.
The audit compared **areas** against a flat 0.01 sq stud floor, and a displaced edge costs area in
proportion to its **length**: a 400-stud perimeter turns 0.003 studs into ~1.2 sq studs, so any large
plate failed for free. The tolerance is now `max(0.05, area*2e-5, perimeter*0.01)`, which tracks the
mechanism and still catches a real protrusion (studs wide, not thousandths).
**Re-audited live: 53 good, 0 bad, 353 levels, 10,074 structural parts.**

**2. "No exact native-size triangulation" (`130_14`, `170_2`, `250_79`) — cause found, was NOT what
the message says.** The error blames a 0.05-stud minimum. The outlines that fail have **minimum edge
0.92–2.06 studs and minimum angle 47–68 degrees** — they are perfectly well conditioned. The real
cause is `PolygonSlab.triangulate` exhausting its **2048-state backtracking budget** on 18–32 vertex
rings. Do not go looking for slivers.

Fix, without touching load-bearing Luau: `tools/polygon_slab_sim.py` is a Python replica of that
triangulator (it reproduces the three live failures exactly), and the plan builder now walks
`SIMPLIFY_LADDER = (0.9, 1.4, 2.0, 3.0, 4.5)`, keeping the first tolerance whose ring provably
triangulates. Fidelity is surrendered one step at a time and only where it is the price of building
at all. Reported as `sourceInfo.simplifyEscalated` and `ringsDropped`.

### Part budget — decide before scaling to the whole map

56 buildings cost **9,404 parts**, about 168 each, and 99.97% of slab parts are wedges (a floor of N
vertices needs ~N-2). The live map currently carries 174,531 structural parts across 3,190 greys.
Consolidating ~3,190 greys into roughly 1,300-1,600 real buildings at this fidelity lands in the
same order of magnitude, but it should be measured on a bigger sample before committing, and
`SIMPLIFY` is the knob (0.9 -> 0.3 buys p05 IoU 0.9890 -> 0.9967 for ~8% more parts).

### Rooftop clutter trimming — my first setting was too aggressive. Measure before trusting it.

The user asked for signs and AC units to be left out. Implemented as: cut a trailing run of sections
below `ROOF_MIN_SHARE` of the body's median area, when that run is shorter than `ROOF_MAX_RUN`.

**At 0.25 / 36 studs it fired on 25 of 55 plans and removed real building**, up to two storeys:

| plan | trimmed | v6 levels | v5 levels | grey top | v6 top | v5 top |
|---|---|---|---|---|---|---|
| `fbx_poly_170_6` | 34.0 | 4 | 6 | 229.3 | **194.5** | 228.5 |
| `fbx_poly_170_2` | 30.0 | 7 | 9 | 281.2 | **250.0** | 280.0 |
| `fbx_poly_290_26` | 28.0 | 9 | 11 | 318.4 | **290.1** | 318.1 |
| `fbx_poly_330_7` | 28.0 | 6 | 8 | 401.6 | **373.2** | 401.2 |

v5 (no trimming) matched the live grey tops to under a stud in every one of those. Half the map is
not rooftop clutter, and cutting two storeys off a tower is the opposite of "floors should follow the
geometry very well".

**Now 0.15 / 24 studs, plus a hard floor: the trim can never take the roof more than one storey
(`PITCH`) below the live greys' own measured top.** A slim genuine crown therefore survives.

**This still needs eyes before it is trusted.** The only real discriminator between a parapet and a
narrow top floor is what it looks like. Check `sourceInfo.roofClutterTrimmed` per plan and confirm it
is 0 on buildings with real setbacks. If in doubt, set `ROOF_MIN_SHARE = 0` to disable it entirely —
nothing else depends on it.

### Which batch to use

**`plans_v8` — 55 plans / 201 greys. Clean on every axis.**

Staged live as `SourceSliceStage_e948c30c-…`: **55 of 55 built, 55 good, 0 bad.**
377 levels, 9,524 slab parts (9,522 wedges), 1,932 core parts, **11,456 structural parts = 208 per
building.**

| gate (`source_slice_pokeout.py`) | v7 | **v8** |
|---|---|---|
| median mean-IoU vs the FBX section | 0.996 | **0.997** |
| p10 | 0.991 | 0.991 |
| **worst plan** | 0.923 | **0.989** |
| plans at IoU >= 0.95 | 52 / 54 | **54 / 54** |
| plans >5% spill | 2 | **0** |
| worst spill | 61.1% | **3.4%** |
| worst under-coverage | 23.0% | **1.8%** |
| levels using their own height's section | 329/377 (87.3%) | **336/377 (89.1%)** |

Both v7 outliers are gone: `fbx_poly_250_79` (61.1% spill, the tapering-top defect) and
`fbx_poly_170_65` (23% under-coverage). **Every plan in the batch is now at or above 0.989 IoU.**

| older batch | why not |
|---|---|
| `plans_v7` | 55/55 built and good, but 2 plans over 5% spill (worst 61.1%). Superseded by v8. |
| `plans_v6` | Over-aggressive rooftop trimming. **Do not use.** |
| `plans_v5` | 3 triangulation build failures. Superseded. |

**Still unverified by eye, and it needs to be before any Apply:**
- Rooftop trimming on 17 plans (max 18 studs, <=1 storey each) — only a picture separates a parapet
  from a narrow top floor. `sourceInfo.roofClutterTrimmed` names them; `ROOF_MIN_SHARE = 0` disables.
- 21 levels across 10 plans sit where the FBX has no geometry at all (mesh holes). Flooring them is
  almost certainly right, but it is an assumption.
- The gate confirms a plate reproduces the section the builder **selected**; nothing independently
  confirms the builder selects the right polygons for a building.

**Generation is slow (tens of minutes) and the cause is NOT the triangulation checks.** Capping the
replica's search from 2048 to 300 states made individual verdicts instant (0.01s) and barely moved
total runtime. The real cost is the per-floor `slicer.at()` calls introduced in v4: each floor asks
for a section at its own height, which is off the `STEP` cache grid, so every one is a fresh
`sections()` over the local triangles. If this needs to scale to the whole map, that is the thing to
optimise — cache by rounded height, or sample sections once on a fine ladder and interpolate.

**Performance warning on the buildability ladder.** The first attempt had no guard and effectively
hung: the replica triangulator is cheap on a ring it *can* tile and burns the full 2048-state budget
on one it cannot, and the Python port is far slower than the Luau original. It now only runs on
rings with **>= 14 vertices** (every observed failure had >= 18) and memoises results. If a future
run stalls, that is the first place to look.

### Not yet in v5

Rooftop clutter trimming (`ROOF_MIN_SHARE` / `ROOF_MAX_RUN`, reported as
`sourceInfo.roofClutterTrimmed`) was added **after** v5 was generated. It cuts a trailing run of
sections under 25% of the body area when that run is shorter than 36 studs, so signs and plant go
while real setbacks stay. **Regenerate to pick it up, and check `roofClutterTrimmed` is 0 on
buildings with genuine setbacks before trusting it.**

## Sept 17 — fifth metric error, and the under-coverage "tail" was never real

`plans_v5` (56 plans, 205 greys) scored a median mean-IoU of 0.993 but a long tail: 20 of 56 plans
under 0.95, worst under-coverage 89%. That tail was **the gate, not the plans.**

`source_slice_pokeout.py` selected "this building's section" with `intersection(region) >= 300`,
where `region` is the union of the greys' **axis-aligned** rectangles. Shibuya is dense, so that
always catches a neighbour clipping the corner of the box — and the plate is then scored as failing
to cover a building it was never meant to cover. Measured on the two worst plans:

| plan / level | plate | builder's own rule | **miss** | loose rule | miss |
|---|---|---|---|---|---|
| `130_43` L0 | 9,503 | 9,480 | **0.2%** | 18,450 (3 polys) | 48.7% |
| `130_43` L5 | 4,114 | 4,141 | **0.9%** | 16,515 | 75.2% |
| `170_56` L1 | 3,431 | 3,428 | **0.1%** | 32,293 (a neighbour) | 89.4% |

**The plates reproduce their sections to 0.1–0.9%.** The gate now applies the builder's exact rule
(`area >= 400`, `intersection >= 300`, `intersection/area >= 0.35`).

**Read this before quoting the new gate.** Aligning the gate to the builder makes it answer "does the
emitted plate faithfully reproduce the section the builder selected" — which it does, very well. It
no longer independently checks **whether the builder selected the right polygons**. That second
question is currently supported only indirectly (the selected sections strictly contain the grey
fragments they replace — the A/B shows greys missing 9–78% of the section, never the reverse) and by
eye. A genuinely independent identity check is still missing.

Also note the multi-piece change (returning every qualifying polygon rather than the largest) did
**not** move the tail, because the tail was measurement. It is still correct and worth keeping —
`SourceSliceBuilder` accepts a list of pieces per level — but do not credit it with a fix it did not
make.

## THE GOAL (user, Sept 17) and what the measurements say about it

> "the goal is to have accurate buildings. I can do building facades separately, but the buildings
> generated should follow the geometry very well. Obviously things like rooftop signs or ac units
> etc don't need to be modeled, but the floors should follow the geometry very well."

So the deliverable is **floor plates whose outline matches the FBX cross-section at that floor's
height**. Facades are out of scope. Rooftop clutter is out of scope.

**The strategy question is settled: slice the FBX. Do not merge the greys.**

A/B, same building, same height, same metric (`tools/source_slice_ab.py`), over the 51 fragmented
groups the plans target:

| | generated slice | live grey fragments |
|---|---|---|
| median IoU vs FBX | **0.994** | **0.462** |
| IoU >= 0.95 | **40 / 51** | **0 / 51** |
| strictly better | **51 / 51 plans** | — |

Grey fragments miss 9–78% of each floor. Merging them cannot fix that — the geometry is not there to
merge. Slicing is the only route that yields complete floors for the **56% of the map that is
fragmented**.

**Important qualification to the earlier "greys already match the FBX" finding.** That was an *area*
comparison, and equal area does not mean equal shape. Measured properly by IoU
(`tools/source_slice_shape_survey.py`, 147 live floors):

- **Solo** greys are genuinely good: median IoU **0.996**, 84% at >= 0.95, spill p95 only 1.1%.
- Their failure mode is under-coverage, not bloat: miss p95 **24%**.
- So roughly 44% of the map (the solo greys) is already close, and 56% (the fragments) is not.

Slicing everything is still the right call — it fixes the fragments and the ~15% of solo greys that
under-cover, and gives one consistent pipeline.

### The fidelity knobs, measured

- **`SIMPLIFY = 0.9` is not costing fidelity.** Sweeping it over 54 real sections: median IoU 0.9988
  (p05 0.9890) against 1.0000 unsimplified, while halving vertices (14.1 -> 6.1 mean). Tightening to
  0.3 buys p05 0.9967 for ~8% more parts. Leave it, or go to 0.3 if the tail matters.
- **Vertices drive part count**: a floor of N vertices needs ~N-2 wedges; one Part only for an exact
  rectangle. Budget accordingly before slicing all 3,190.
- **Rooftop clutter** is already partly excluded by `MIN_FOOTPRINT = 400`, which drops sections under
  400 sq studs. Signs/parapets larger than that are not yet trimmed — an explicit rule (stop where
  the section collapses below some fraction of the main body) is still to be written.

## What this sample is testing (important)

This overlay **copies the live ExactPolygon hull** (grey `BuildingSmooth_*`): same yawed rectangle, same live slab Ys, truncated before roof-equipment holes. It proves the builder can emit 0-wedge plates that coincide with grey.

It does **not** improve FBX fit. **Grey already fits the FBX better than orange.** User confirmed that on the last overlay. Copying SmoothMassing cannot beat the live hull. The next agent must slice `tools/source_slices/world_triangles.npz`, not clone live slabs.

Do **not** Apply this sample as a replacement. Grey is the keeper until a real FBX plan exists.

## First sample — what went wrong

Live building: ExactPolygon yawed rectangle **156.43 × 181.69**, **22 floors + roof**, base **Y 118.70**, top **Y 522.73**, 0 wedges. Key `ShibuyaSourceKey=1_-21438_3207_4019`. Camera around `(-2172, 321, 430)`. SmoothFrame Right ≈ `(-0.805, 0, -0.592)`.

Closed FBX slices for this prism are solid from **Y 247.6–475.1**. Holes (roof equipment) **Y 477.6–512.6**. Neighbors sit ~Y 131–170, not on Studio terrain (terrain here is Y 36). User rejected a floating overlay that started at Y 248: the grey live tower (and the FBX when dragged in) go down to the neighborhood base.

Failed overlays:

1. World-XZ parallelogram from Y 248, 12 floors, **52 wedges**. Floated in the upper half.
2. Cached v1 after height rewrite: still 12 floors, wedges, Y 239+. Screenshot ~21:07.
3. Height-correct overlay (~19 floors, 0 wedges, base Y 118.7) with **identity origin** `[x,y,z,1,0,0,0,1,0,0,0,1]`. Orange was a world-axis diamond; grey/FBX stay yawed. Plates poked out of the red FBX. Cause: Builder used `CFrame.new(x,y,z)` only (yaw ignored and/or Studio Builder stale). Preview Floor1 size matched; rotation did not.

Fix now: `SourceSliceBuilder.compile` uses `CFrame.new(x,y,z,r00…r22)` when those keys are present, else yaw. Canonical origin always stores `r00–r22`. `SourceSliceFirstSample.Plan` copies `SmoothFrame:GetComponents()` with Y=`SourceBaseY`. `Show` asserts Floor1 slab RightVectors match (dot > 0.999) and preview base matches live base.

**Restaged overlay (21:25):** origin CFrame is SmoothFrame with Y=118.70, not identity. Orange plates follow the same yaw as grey/FBX. They still occupy the live ExactPolygon, so they will not fit the FBX *better* than grey. That is the end of this builder-copy test.

## How to hide / re-show the overlay (Command Bar, Edit)

`.Hide()` removes `Workspace.SourceSliceReview_FirstSample` only. The unused ServerStorage stage can be destroyed the same way as any other unused stage; it is not live.

To rebuild the overlay after a script change, wait for Rojo, then (Command Bar — MCP cannot parent clones into Server):

```lua
local s=game.ServerScriptService.Server
local f=Instance.new("Folder"); f.Name="SourceSliceFresh"; f.Parent=s
s.PolygonSlab:Clone().Parent=f
s.PartExtents:Clone().Parent=f
s.SourceSliceBuilder:Clone().Parent=f
local m=s.SourceSliceFirstSample:Clone(); m.Parent=f
local ok,r=pcall(function() return require(m).Stage() end)
f:Destroy()
if not ok then error(r) end
return r
```

Success must print `wedges:0`, `previewBottom` ≈ `liveBottom` ≈ 118.70, `floors` ≈ 19, and the yaw assert must not fire. Orange plates should **coincide** with grey (same diamond/yaw), not sit as a world-axis box. Top live floors (equipment) stay grey. `.Hide()` removes the overlay. **Do not Apply.**

If orange now matches grey and still pokes the FBX the same way grey does, that is expected. Stop copying live massing; switch to FBX triangles.

If Shibuya is in Workspace for comparison, do not destroy it. Only `Workspace.SourceSliceReview_FirstSample` is disposable.

### What is sitting in the open Studio session right now

Nothing live was touched and nothing was saved. All of this is disposable.

- `Workspace.SourceSliceReview_Batch` — one orange preview of **`fbx_poly_130_11`** (4 bands,
  7 levels, replaces 4 greys), camera already framed on it. This is a v4 building with a real
  setback; compare it against the red FBX and the grey it replaces. **This is the thing to look at
  first.**
- `Workspace.SourceSliceReview_FbxSample` and `SourceSliceReview_FirstSample` — older overlays from
  the dead-end seeds. Safe to delete.
- `ServerStorage.SourceSliceStage_c7d23427-…` — the 51-building v4 stage (50 good / 1 bad).
  Four other `SourceSliceStage_*` are older and can go.
- Screenshots stopped working around 07:00 (`capture_screenshot` timing out) once the machine
  locked — the viewport cannot render. Reconnect and it should work again.

To re-preview more of the batch:
`require(...SourceSlicePlanStage).Preview("SourceSliceStage_c7d23427-…", {"fbx_poly_130_11", …})`,
`.Hide()` to clear.

## Sept 17 06:00-07:00 — plans_v4 passes every gate. Start here.

### The headline: greys already reproduce the FBX footprint. Measured, map-wide.

`tools/source_slice_fit_survey.py` is the honest replacement for `fill_survey`'s `fill`. It compares
a grey's **material** footprint area (summed `SlabFootprintArea`, via `PartExtents`) against the FBX
section under its own centre at its own mid-height — like with like. 200 sampled single-member greys:

| p05 | p25 | **median** | p75 | p95 |
|---|---|---|---|---|
| 0.74 | 0.99 | **1.00** | 1.00 | 1.01 |

- **83% (160/192) are within ±10% of the FBX.**
- **More than 25% larger: 1 of 192.** Against the retracted "933 greys >20% oversized".
- 13 of 192 are >25% *smaller* — those are the fragments, i.e. the identity problem again.

**Re-slicing the FBX cannot improve footprints. There is no footprint problem.** Combined with the
boxiness histogram (only 21 of 3,193 greys are boxes at all), the premise this project ran on for
several sessions is finished. What remains is identity, cores, overlaps — and outlines, which nobody
has measured.

### `plans_v4` — every fix, and it is strictly better than the original batch

`python tools/source_slice_plan_builder.py --from-survey --limit 83 --out tools/source_slices/plans_v4`

| | original 48 | **v4** |
|---|---|---|
| plans / greys consolidated | 48 / 186 | **52 / 191** |
| median plate outside FBX | 2.0% | **0.3%** |
| p90 | 54.7% | **0.6%** |
| plans >5% outside | 21 / 48 (44%) | **2 / 52 (4%)** |
| levels using their own height's section | n/a | **301 / 349 (86%)** |
| plans needing a base extension | 0 (it floated) | 26, max 64 studs |

Rejections fell from 41 to 23, and **"no 4-stud core fits every level" went 19 -> 0** once the core
search was allowed to sit off-centre.

Staged live as `SourceSliceStage_c7d23427-…` (51 of 52 built): **50 good, 1 bad**, 330 levels,
9,256 structural parts. Mean height retained vs greys **0.934**, base within 2 studs on 45 of 51.

The two plans still worth looking at before any Apply:
- `fbx_poly_250_79` — 61.1% of one plate outside the FBX. The only remaining bad plan.
- `fbx_poly_250_25` — the single audit failure, and it is a **real** one:
  `Slab protrudes beyond its source polygon` (a PolygonSlab native-size issue, not a tolerance).

### Validator change — read this, it loosens a check

`SourceSliceBuilder.auditModel`'s native-slab overlap floor was raised **0.1 -> 0.5 sq studs**.
Measured justification: staging 6,258 slab parts produced float32 overlaps up to 0.243 sq studs and
failed 6 of 51 geometrically correct buildings. 0.5 sq studs is a 0.7-stud square against plates of
thousands. It did **not** mask anything — after the change 5 of the 6 pass and the 6th surfaces a
genuinely different, real error. Revert if a true double slab ever slips through.

### What is NOT fixed

- **Outlines are unmeasured.** The user's complaint list was identity, outlines, overlapping
  sections, duplicate cores. Three are addressable; nobody has quantified the fourth, and it is the
  only one re-slicing uniquely improves.
- 23 of 51 staged buildings are >10% shorter than the greys they replace. Expected where grey's top
  is invented, but unverified per building.
- 20 levels across 9 plans sit where the FBX has no geometry at all (mesh holes). Flooring them is
  almost certainly right, but it is an assumption.

## Sept 17 05:00-06:00 — the generated plans were never close; root cause found and fixed

### The plans' floor plates hang outside the FBX. Always did.

New `tools/source_slice_pokeout.py` compares each level's plate against the FBX section **at that
level's own height**, in world coordinates.

**Control first** (the lesson of the three retracted metrics): the hand-authored `16_7714` MAIN plate
scores **0.0% outside at every height, IOU 1.000**. The metric is sound.

| batch | median % of plate outside FBX | plans >5% outside |
|---|---|---|
| `plans/` (the original 48) | **2.0%**, p90 **54.7%** | **21 / 48 (44%)** |

**CORRECTION (06:40).** The first run of this metric reported a 37.9% median for the original 48.
That number was wrong and is withdrawn — the metric itself had the same flaw it was hunting. A
level whose FBX section is simply **missing** (the export is not watertight) scored as "100%
outside", which is a hole in the source, not a defect in the plan. `fbx_poly_130_1` scored 100% at
one storey while the identical plate one storey above and below scored 0.2%. The tool now separates
"the plate sits outside a section that IS there" from "there is no FBX here at all" and reports the
latter as a count. **Every figure in this section is the decomposed metric, applied to both sides.**
The severity of the original batch is real but it lives in the tail, not the median: p90 of 54.7%
and 44% of plans failing, not a typical plan being 38% wrong.

**This is pre-existing, not a regression from this session's changes.** The batch the handoff
described as "all 48 re-validate from disk against the Luau contract with zero failures" was
measuring *contract compliance* — level counts, piece simplicity, core containment — and never
geometric fidelity to the FBX. Those are different things and only one of them was ever checked.

### Root cause: intermittent sections, then `MIN_BAND` deletes the whole upper building

Traced on `fbx_poly_250_80`, whose section really is 11,49x up to Y ~221 then a 6,81x tower then
5,62x above that. `bands()` correctly saw all of it — **and then it was thrown away**:

```
split at 225.8  band 163.8..225.8  area 11491   <- podium, 62 studs, KEPT
split at 233.8  band 231.8..233.8  area  4512   <- 2 studs, dropped
split at 241.8  band 235.8..241.8  area  6812   <- 6 studs, dropped
split at 257.8  band 247.8..257.8  area  6811   <- 10 studs, dropped
split at 265.8  band 261.8..265.8  area  6813   <- 4 studs, dropped
split at 275.8  band 269.8..275.8  area  5620   <- 6 studs, dropped
after MIN_BAND>=12: [('163.8','225.8')]
```

The Shibuya export is **not watertight**, so `sections()` returns nothing at scattered heights —
here at 5 separate bands between Y 223 and 269. Every dropout ended a band, so one solid ~35-stud
tower became five 2–10 stud slivers and `MIN_BAND = 12` deleted all five. Only the podium survived,
and all seven floors inherited its 11,487 plate — **41% of the top floors' area hanging in mid-air.**

`fbx_poly_130_36` fails a second way: it **tapers** (5,965 → 5,036 → 4,212). A tapering building has
no prismatic band at all, so every band is thin and all of them are dropped.

### Fixes

1. **`bands()` bridges gaps instead of splitting on them**, and ignores a single disagreeing sample
   between two matching ones (a half-closed contour is an artifact, not a storey). `250_80` now
   yields 2 bands — podium 11,492 and tower 6,812 — instead of 1.
2. **A floor takes the section at its own height**, falling back to its band only inside a gap or
   below the FBX in the base extension. This removes the band abstraction from plate selection
   entirely, which is the only thing that can handle a taper. Reported as `sourceInfo.exactLevels`.

### `plans_v2` measured live (41 staged, `SourceSliceStage_2836b0ea-…`)

Audit: **37 good, 4 bad**. All four bad are `native slab pieces overlap` by 0.13–0.18 sq studs
against a 0.10 tolerance — float32 accumulation at Shibuya-scale coordinates, not a geometry error.
Consider raising that tolerance rather than chasing it.

| metric | v2 |
|---|---|
| mean height retained vs greys | **0.941** (worst review6 seeds were 0.38–0.48) |
| base within 2 studs of grey base | **37 / 41** |
| mean extent vs greys | 1.286 |

Extent > 1 is **not** by itself a defect: the greys are fragments, so a correct slice should exceed
them. Use `source_slice_pokeout.py` against the FBX, never extent against grey, to judge fit.

### Two operational notes that cost time

- **MCP `execute_luau` can run the same code more than once.** Cleanup found 8 duplicate sets of the
  `SSX_*` dump values and 3 identical 41-model stages. An earlier run reported `staged:0,
  badBuildings:31` purely because a concurrent copy destroyed the stage mid-audit. **Write every
  `execute_luau` script to be idempotent**, and never have one delete by a tag it is about to set.
- **Bulk data out of Studio: POST it, do not return it.** `tools/…/sink.py` style local HTTP sink on
  127.0.0.1:58999 + `HttpService:RequestAsync` moved 231 KB straight to disk in one call. Returning
  it through `execute_luau` would have taken 6 reads and a large amount of context.

## Sept 17 04:00-05:00 — THE FOOTPRINT PREMISE IS DEAD. Read this before any more seed work.

Studio was reachable this session (community plugin). Everything below is measured live, not argued.

### 1. Greys are not oversized boxes. Only 21 of 3,193 are boxes at all.

`SourceSliceLiveExtents.Dump()` measured every building with `PartExtents`, then
`extent area / material area` was histogrammed. A world-axis box scores 1.00; a 21.5-degree yawed
rectangle scores 1.68; anything concave scores higher.

| ratio | greys | |
|---|---|---|
| 1.00–1.05 | **21** (0.7%) | genuinely axis-aligned boxes |
| 1.05–1.20 | 193 | |
| 1.20–1.50 | 490 | |
| 1.50–1.80 | 821 | about a yawed rectangle |
| 1.80–2.50 | **1,421** | yawed *and* concave |
| 2.50+ | 247 | |

**Median 1.82** — the typical grey fills 55% of its own bounding box. The greys follow real outlines,
because they were derived from this same FBX in the first place.

`fill_survey` divided FBX polygon area by grey **bounding box** area, so a perfectly-fitting grey
scores ≈0.55 there and reads as "45% oversized". Its median fill of 0.689 is that artifact, nothing
more. **"933 greys >20% oversized" is now positively disproved, not merely unsupported.** Do not
rebuild that metric; rebuild the question.

At seed `16_7714` specifically, measured like-for-like: grey's widest storey covers **19,158.8** sq
studs against the FBX section's **19,154.3** — **0.02% apart**, same centre to 0.024 studs, same yaw.
Grey's Floor1 is 4 WedgeParts tiling exactly the polygon the slice would emit. There is **no
footprint win at that seed**, and the earlier "194.9 x 195.9 world-axis box" was `size.Y` (the
height, 194.949) misread as a horizontal dimension, because the model's pivot is not upright.

### 2. The identity problem is real and roughly 6x bigger than recorded

Grouping by `ShibuyaSourceKey`: **562 multi-member groups covering 1,796 greys** — 56% of the map.
Group sizes: 1,397 singletons, 268 pairs, 137 triples, 57 fours, 42 fives, 25 sixes, 18 sevens,
9 eights, 2 nines, 2 tens, one twelve, one thirteen (largest: `BuildingSmooth_3_257_1726_15414`).

That is a **lower bound** — key-grouping splits `16_7714`'s five greys into two groups, as already
noted. The earlier figure ("83 polygons owning 291 greys") counted only what the flawed survey
surfaced.

**This, not footprint size, is the thing worth fixing.** It is also exactly what the user asked for:
identity, outlines, overlapping sections, duplicate cores.

### 3. `plans_review6` staged clean and is still NOT usable

`SourceSliceStage_c1d99ab4-3c60-4ee8-89a2-b75427b66999`: 6 staged, 0 failed, **0 badBuildings**,
33 levels, 644 slab parts (all wedges), 162 core parts. The builder contract passes. The geometry
does not:

| plan | greys | grey Y | slice Y | height lost | extent ratio |
|---|---|---|---|---|---|
| `fbx_poly_170_0` | 8 | 121–233 | 169–211 | **70 (62%)** | 1.03 |
| `fbx_poly_170_2` | 6 | 120–281 | 166–243 | **84 (52%)** | 1.16 |
| `fbx_poly_170_6` | 5 | 121–229 | 121–179 | 50 | 1.12 |
| `fbx_poly_130_47` | 5 | 76–206 | 76–171 | 35 | 1.09 |
| `fbx_poly_130_1` | 6 | 69–196 | 69–181 | 15 | 1.17 |
| `fbx_poly_130_52` | 8 | 99–240 | 99–229 | 11 | 1.19 |

**Every slice is shorter than what it replaces**, two of them start ~46 studs above the grey base
(they float), and **every slice is LARGER in extent** (1.02–1.19x), so it pokes out — visible in the
preview as orange slabs through the red FBX face, the same defect as the very first sample.

### 4. Why — and it is mostly not a bug

The FBX is **genuinely hollow** below roughly Y 170 at these footprints. At `fbx_poly_170_0` no
selector finds a section under the greys below Y 173; at `fbx_poly_170_2`, below Y 168. The live
greys run down to the neighbourhood ground because **grey's base is invented**, which is the same
thing the first seed showed (`FBX empty below Y 245.27, grey base 118.70 invented`) and which the
user explicitly wants kept.

`SourceSliceFbxSample` anchors to the live base for exactly this reason. **The generalised plan
builder did not, so it started buildings in mid-air.** That single omission is worth 48–52 studs on
these seeds and is the dominant defect.

Two genuine bugs sit underneath it:

- **`Slicer.at()` tested `polygon.contains(centre)`**, where the centre is the *mean of the
  fragments' box centres*. For fragment groups that mean lands in a courtyard: measured **37.9 studs**
  outside the nearest section on `170_0` and **67.6** on `170_2`.
- **`edge()` bisected** for the band limits, which assumes one contiguous Y interval. Real towers go
  YES/no/YES on the way up (`170_0` at Y 206/212/218), so bisection stopped at the first gap.

### 5. Fixes applied to `tools/source_slice_plan_builder.py`

1. **Base anchoring.** The lowest band is extruded down to the greys' measured base; never raised
   above the FBX. Reported as `sourceInfo.baseExtension` — non-zero is normal and intended.
2. **Scan, not bisect,** over the greys' measured Y range at `STEP`.
3. **Region-based section selection** (`MIN_SECTION_OVERLAP`, `MIN_SECTION_INSIDE`) against the union
   of the greys' measured rectangles, falling back to the old point test. Recovered 20 extra studs at
   the top of `130_47`.
4. **`load()` prefers `live_extents.csv`** over `live_buildings.json`, whose `cf`/`size` is
   pivot-oriented — it reports `170_0` as Y 101.6–206.7 where the truth is 121–233.

Regenerated into `tools/source_slices/plans_v2/`; originals kept in `plans/` for comparison.
**Not yet staged or measured live.** Extent ratio > 1 is NOT addressed by any of this — see below.

### 6. Still open, and it matters

**The slices are larger than the greys they replace (1.02–1.19x) and poke through the FBX face.**
Nothing above fixes that. Candidate causes, untested: `SIMPLIFY = 0.9` expanding the ring outward,
`snap_rectangle` growing a nearly-rectangular outline to its minimum rotated rectangle, or the
section being taken at a band's widest Y and applied to the whole band. Measure before guessing —
that is the lesson of the three retracted metrics.

## LIVE RUN Sept 17 03:33 — both fixes confirmed; grey is the section's bounding box

Command Bar, Edit. `SOURCE_SLICES_STAGED 1 ready 0 failed
SourceSliceStage_be08b4e3-5ed2-48ac-9561-dfd6f6678f70`, `badBuildings:0`.
`Workspace.SourceSliceReview_FbxSample` holds the orange overlay. **Nothing applied, nothing saved.**

| Field | Value | Meaning |
|---|---|---|
| `measuredSizeX` / `predictedSizeX` | **181.3097 / 181.3097** | identical — open item 2 closed live |
| `measuredSizeZ` / `predictedSizeZ` | **177.7015 / 177.7015** | identical |
| `elevations` | `BuildingSmooth_16_7714_2072_-5958` | open item 1 closed live — no longer `"uniform"` |
| `baseDrift` | **0** | the base-assert mystery is gone too |
| `wedges` | 16 | the setback roof only; ten `MAIN` floors are single Parts |
| `floors` / `levels` | 10 / 11 | as planned |
| `slabParts` / `coreParts` / `structuralParts` | 26 / 60 / 86 | matches the offline replication exactly |
| `previewBottom` / `previewTop` | 109.691 / 301.857 | inside the closed FBX band |

### `greyOversizeFactor: 1.0001` does NOT mean grey is correctly sized

That metric was added earlier in this same session and it is **blind to the claim it was meant to
test**. Measured wedge-aware, the grey union AABB is **181.327 × 177.706** and the slice AABB is
**181.310 × 177.702** — **0.017 studs apart in X, 0.005 in Z**. That near-exact agreement is the
*signature of grey being precisely the bounding box of the yawed FBX section*, and a rotated
rectangle and its own bounding box have the **same extent by construction**. So an extent ratio is
pinned at 1.0 no matter how much extra material grey carries. It measured the right kind of
quantity and still answered the wrong question.

**Three metrics have now been wrong in three different ways. Do not add a fourth without stating
what would falsify it:**

1. `2.00×` — rotated rectangle ÷ axis-aligned box. Mixed quantities.
2. `1.79×` — both sides AABB, but eight-corner, so both inflated by their wedges.
3. `1.0001×` — both sides AABB and wedge-aware, but extent cannot see inside a bounding box.

### The measurement that can actually answer it

**Material footprint area**, storey by storey. `PolygonSlab` stamps `SlabFootprintArea` on every
part it builds, so grey's true covered area is readable directly rather than inferred.
`PartExtents.SlabArea` / `PartExtents.Storeys` do this, and `Compare()` now reports
**`greyAreaFactor`** = widest grey storey area ÷ FBX section area.

Bounds to judge the next run against:

- FBX section polygon (141.632 × 135.24 yawed) = **19,154 sq studs**.
- Grey's own bounding box = 181.33 × 177.71 = **32,223 sq studs**.
- So `greyAreaFactor` must land in **1.00 – 1.68**. At **1.68** grey is a solid world-axis box and
  the footprint win is the full 40%. At **1.00** grey already follows the yawed outline and there is
  **no footprint win at this seed** — the win is purely identity (5 models → 1) and the setback.
- Grey has wedges, so it is *not* a plain rectangle; expect something strictly between.
- Check `greyEstimatedParts` is **0**. Non-zero means areas were inferred rather than read.

Until that number exists, **no footprint claim for this seed is supported**. The identity
consolidation (`replacesLiveModels: 5`) and the setback are real and unaffected either way.

## RESOLVED Sept 17 — both open items were the same measurement bug (wedge boxes)

Found offline by replicating `PolygonSlab`'s triangulator in Python
(`tools/wedge_box_check.py`). No Studio needed; the numbers reproduce exactly.

**A WedgePart fills only HALF of its `Size` box.** `PolygonSlab.addWedge` builds the box as the
rectangle spanned by the triangle's two legs, so the box's fourth corner — the mirror of the right
angle — is empty space that can sit well outside the floor outline. Any measurement that transforms
**all eight corners** of every part therefore reports a footprint the building does not have.
`Model:GetBoundingBox()` does the same thing, and is pivot-oriented on top of that.

### Open item 2 — the "unexplained" 20-stud overhang is not real

Replicating the build of `SourceSliceFbxSample` (10 `MAIN` rectangle slabs + a 10-gon setback roof
+ 60 core parts = **86 parts**, matching the live run exactly):

| Measurement | X × Z |
|---|---|
| `MAIN` under the origin yaw (what the plan predicts) | **181.31 × 177.70** |
| True geometry, polygons only | **181.31 × 177.70** |
| Setback polygon alone | 176.90 × 162.30 |
| Setback **wedge boxes** alone (16 wedges) | 201.77 × 185.52 |
| Whole model measured 8-corner (what the session measured) | **201.77 × 187.12** |

The session measured **201.7 × 187.1**. The replication gives **201.77 × 187.12** — the same number
to the reported precision, and the wedge count (16) matches too. **The overlay's real footprint is
exactly what `MAIN` predicts. There is no excess and nothing to explain.** Open item 2 is closed.

This also means the corrected `1.79×` grey-vs-overlay factor is still wrong: the overlay side was
inflated (`37,755` should be `181.31 × 177.70 = 32,219`), and the grey side is inflated too, by an
unknown amount, because `BuildingSmooth_*` massing is mostly wedges (101,782 map-wide). **Do not
quote 1.79× either.** The real factor needs a live re-measure.

### Open item 1 — `elevations` fell back to "uniform" for the same reason

Not a naming problem. `Interior` floor parts **are** named `Slab` (`SmoothBuildingBuilder` passes
`"Slab"` straight to `polygon.Build`), so the earlier "widen the match" guess was wrong — do not
spend time on it.

`liveSlabs` read `part.Position.Y - part.Size.Y/2` and `part.Size.Y` as the thickness. That assumes
the thickness axis is world Y. **`PolygonSlab` puts a wedge's thickness on LOCAL X** — its CFrame's
`RightVector` is the vertical one (which is exactly what `SourceSliceBuilder.auditModel` asserts:
`part:IsA("WedgePart") and math.abs(relative.RightVector.Y)`). On a mostly-wedge grey floor the old
code therefore read a *triangle's height* as its thickness and placed the storey hundreds of studs
below the FBX band. Every row failed the `row.bottom >= FBX_BOTTOM - 1` filter, fewer than two
survived, and `Plan()` fell back to synthetic pitch without saying why.

**Still to confirm live:** that the rewritten `liveSlabs` returns `elevations = FLOOR_SOURCE` and a
plausible storey ladder. The mechanism is certain; the live row count is not.

### The fix, and what now depends on it

New `src/server/PartExtents.luau` — `Corners` / `Box` / `Footprint`. It uses the same wedge corner
convention as `SourceSliceBuilder.slabShape` (`(-Y,-Z)`, `(-Y,+Z)`, `(+Y,+Z)`; `(+Y,-Z)` is not
material), which is the one the live audit already validated. **Measure with this, never with
`GetBoundingBox` and never with eight corners.**

Applied to `SourceSliceFbxSample`: `liveSlabs` now measures real corners, `Compare()` measures grey
with `PartExtents` instead of `GetBoundingBox` and compares **AABB against AABB**, and `Show()`
reports `measuredSizeX/Z` beside `predictedSizeX/Z` so the two can disagree visibly instead of
silently. `greyOversizeFactor` is now a like-for-like ratio and is safe to quote; the old
polygon-vs-AABB ratio is still reported but is labelled `greyAreaOverPolygonArea` and is **not** an
oversize factor.

`fill_survey.json` **cannot be rebuilt offline** — `live_buildings.json` stores only model-level
pivot-oriented `cf`/`size` from `GetBoundingBox`, i.e. precisely the confounded quantity. Rebuilding
it requires a fresh live dump of per-part extents through `PartExtents`. Until then the survey's
`fill` numbers and every "oversized" count derived from them stay retracted.

## MEASUREMENT WARNING — the `fill` metric is confounded (found Sept 17 03:20)

> **SUPERSEDED Sept 17 07:00.** The suspicion here was right but understated: the `fill` metric
> is not merely confounded, it is disproved. Measured properly, the median grey matches the FBX
> footprint at a ratio of 1.00 and only 1 in 192 is more than 25% oversized. Kept for the reasoning.


**Do not trust `fill_survey.json`'s numbers, or any "oversized" claim derived from them, until this
is redone.** They compare a *tight, rotated* rectangle against an *axis-aligned* box, which are not
the same kind of quantity.

- `fill = FBX section area / grey footprint bbox area`, where the FBX side is the polygon's
  **minimum-area (rotated) rectangle** and the grey side is a **bounding box**.
- A rotated rectangle's own AABB is larger than itself by 1.00× at 0°, **1.68× at 21.5°**, 2.00× at
  45°. For arbitrary yaw the mean is ≈1.5.
- The reported **median fill of 0.689 ≈ 1/1.45** sits squarely inside that artifact range, so most
  of the apparent "oversizing" may be rotation, not real. **"933 greys >20% oversized" is not
  established.** The multi-owner counts (one polygon covering several grey centres) are unaffected —
  those come from point-in-polygon tests, not areas.
- Worse, grey `size`/`GetBoundingBox` is **pivot-oriented**, and these models' pivots are not upright:
  `BuildingSmooth_16_7714_2072_-5958` has `RightVector = (0.000, 0.907, 0.420)`. Its `size.X * size.Z`
  is not a horizontal area at all, so the offline data alone cannot give a footprint.
- **The fix:** compare like with like — measure the world-space AABB of the actual parts (iterate
  `GetDescendants()`, transform all 8 corners of each part, take min/max). That is what produced the
  trustworthy 1.79× above. Rebuild the survey on that basis before using it to pick seeds.

## FBX triangle survey — where slicing actually beats grey (September 16, 22:00)

> **SUPERSEDED Sept 17 07:00.** Every `fill` figure below is withdrawn — it divided FBX polygon
> area by grey BOUNDING BOX area, and greys are not boxes. The multi-owner (identity) counts survive
> in direction but are a large undercount: the real figure is 562 groups covering 1,796 greys.


**Read the measurement warning directly above before using any number in this section.**

Measured directly from `world_triangles.npz` with `source_slice_pipeline.sections()`, not from
live attributes. Scripts are throwaway; the numbers are the deliverable.

**Why the first sample was a no-op.** Sliced at the first seed's footprint, the FBX section is a
19-vertex ring, but all the extra vertices are collinear export T-junctions: simplified it is a
**4-gon of 156.43 × 181.69**, filling **100.0%** of the live grey rectangle. Grey and the FBX agree
exactly there. Slicing that seed can never improve it. The FBX is also **empty below Y 245.27** at
that footprint — grey's base Y 118.70 is invented, and the user wants it kept, so the only real
difference available was the roof-equipment band. Confirms "do not Apply".

**City-wide.** Reproduce with `python tools/source_slice_fill_survey.py`; it writes
`tools/source_slices/fill_survey.json`. Numbers below are that tool's (sections every 40 studs,
Y 130–560, polygons over 200 sq studs). 1,725 of 3,190 greys have an FBX section under their centre.
`fill = FBX section area / grey footprint bbox area`:

| p5 | p10 | p25 | p50 | p75 | p90 | p95 |
|---|---|---|---|---|---|---|
| 0.196 | 0.241 | 0.360 | **0.689** | 1.538 | 3.500 | 5.743 |

- **933** greys have `fill < 0.80` — the grey box is far larger than the real envelope.
- **590** have `fill > 1.10` — one FBX polygon is *bigger* than the grey box, i.e. one physical
  building was split into several greys.
- **83 FBX polygons own ≥ 3 grey centres, covering 291 greys.** Their members share one
  `ShibuyaSourceKey` and differ only by `Body0n` / `Residual_*` suffix, so the split came from the
  residual/body passes. In most of them `sum(grey footprints) > polygon area`, which is the
  overlapping-sections complaint.

That last count is a **lower bound that grows with sampling density** — a denser 20-stud ladder over
Y 140–420 found 126 such polygons. Tighten `LEVELS` in the tool before trusting it as a total.

So the identity problem is real and measurable, and the fix is to merge same-key `Body*`/`Residual*`
greys under one sliced polygon. The first seed was simply an unlucky pick.

## Second sample — first real FBX seed (`16_7714`)

Chosen because it demonstrates both wins at once and stays geometrically trivial.

- **Live:** five greys, `BuildingSmooth_16_7714_2072_-5958` plus `_3083_-5951_Body01..04`.
- **FBX:** one closed polygon under their shared centre from **Y 109.70 to Y 311.70**.
  Main prism Y 109.70–~296.5 is a **4-vertex 141.63 × 135.24 rectangle yawed −158.53°**
  (area 19,098). Above that, an L-shaped **10-vertex setback** (area 15,610) to Y 311.70.
- **The win, corrected by measurement (Sept 17 03:16).** Measured world-space AABB over every part:
  grey **259.8 × 259.9 = 67,549** (104 parts), overlay **201.7 × 187.1 = 37,755** (86 parts) —
  grey is **1.79× the footprint**. Grey also has no setback; the four `Body0n` slivers are the roof
  equipment the FBX resolves properly.
  **The earlier "exactly 2.00×" was arrived at wrongly** — see the measurement warning below. It was
  close to the truth by luck, not by method. Do not quote `greyOversizeFactor` from `Compare()`.
- **Why it looks like there is no overhang.** Grey's extra ~29 studs per side is a large flat roof
  slab rendered in the same grey as the Studio terrain, so from above it reads as ground. Judging
  this seed by eye is unreliable; measure part extents instead.
- Grey base **109.34** vs FBX **109.70** — the base already agrees, so nothing has to be invented
  here (unlike the first seed).
- Frame is fitted to the section's **minimum-area rectangle**, not copied from any live model.
- Plan JSON: `tools/source_slices/fbx_sample_16_7714.json`.

**Offline verification:** both polygons simple and valid; core ±26 lies inside `MAIN ∩ SETBACK`
(largest centred rectangle that fits is 76 × 118); 10 storeys + setback roof = **11 levels**, zero
`MIN_CLEAR` violations; model spans Y 109.70–301.86, inside the FBX band.

**First live run, Sept 17 03:00 (Command Bar).** Staged clean: `SOURCE_SLICES_STAGED 1 ready 0
failed`, `badBuildings:0`, 11 levels, 10 floors, 116 structural parts, 60 core parts. **The plan
contract, core containment and level clearances all pass in the real builder** — that was the part
offline validation could not confirm. Two defects found:

1. **`wedges:56`, not 0.** `PolygonSlab.Build` emits a single Part only when `isRectangle(points,
   eps)` passes — *four sides is not sufficient, the corners must agree*. The measured ring's corners
   differed by up to 0.7 studs (`-70.714` vs `-70.816`, `70.816` vs `70.128`), so all 11 floors
   triangulated. `MAIN` is now snapped to the section's minimum-area rectangle (±70.816, ±67.620;
   0.3% area change). **Do not assume a 4-gon means zero wedges.**
2. **The base assert aborted the preview** and discarded the numbers needed to diagnose it. It is now
   a `warn` plus `baseDrift` / `planOriginY` / `firstLevelY` / `elevations` in the returned table, so
   a mismatched base still renders the overlay and reports by how much. Root cause not yet known:
   `PolygonSlab.Build` treats `yBottom` as the slab bottom (`midY = yBottom + thickness/2`), and the
   first level's `y` is 0 by construction, so the bottom *should* equal `origin.y`. Re-run and read
   the warn line.

Wedge expectations, measured across the generated batch: only **19 of 348** floor pieces are
four-sided at all and just **3 of 48** plans are rectangle-only. Median footprint is **14 vertices**.
Real Shibuya footprints are not rectangles, so **wedges are inherent to this approach, not a bug** —
roughly 4,350 triangles, order 4k–9k slab parts across all 48. The snap only rescues the genuinely
rectangular seeds; it is not a general wedge fix.

### To stage it (Command Bar, Edit, after Rojo syncs)

```lua
local s=game.ServerScriptService.Server
local f=Instance.new("Folder"); f.Name="SourceSliceFresh"; f.Parent=s
s.PolygonSlab:Clone().Parent=f
s.PartExtents:Clone().Parent=f
s.SourceSliceBuilder:Clone().Parent=f
local m=s.SourceSliceFbxSample:Clone(); m.Parent=f
local ok,r=pcall(function() return require(m).Stage() end)
f:Destroy()
if not ok then error(r) end
return r
```

Expect `wedges:0`, `floors` ≈ 10, `previewBottom` ≈ 109.70, `previewTop` ≈ 301.86,
`greyOversizeFactor` ≈ 2.0, `replacesLiveModels:5`. `.Hide()` removes
`Workspace.SourceSliceReview_FbxSample`. `.Compare()` prints the grey-vs-FBX footprint table
without building anything.

**This module has never been executed** — the Studio plugin was not connected when it was written.
Treat the first run as a test, not a confirmation. If `Plan()` fails on floor elevations it falls
back to uniform storeys at the builder's own pitch; the assert to watch is the roof-clearance trim.

## Generated plan batch (September 17) — 48 plans, none staged

`python tools/source_slice_plan_builder.py --from-survey --limit 83` over the 83 multi-owner groups:
**58 valid, 10 folded as duplicates, 25 rejected → 48 plans** in `tools/source_slices/plans/`.
All 48 re-validate from disk against the Luau contract with **zero failures**.

- **186 greys consolidate into 48 buildings** (3.9:1), each grey claimed **exactly once** (asserted).
- Levels: min 3, median 7, max 17 (348 total). Vertices per piece: min 4, median 14, max 38.
  Bands: median 2, max 5.
- `greyOversizeFactor` median 0.79 — 35 plans where the FBX polygon is larger than the biggest grey
  (identity splits), 13 where grey is the oversized box (like the `16_7714` seed).

Bundles for staging: `plans_batch.json` (all 48, 126 KB — too large for a Command Bar paste, use the
StringValue route) and `plans_review6.json` (6 clearest seeds, 12 KB).

**These are candidates, not verified geometry.** Nothing has been staged, previewed or applied, and
no plan has ever been through `SourceSliceBuilder` in a live session. Treat the first stage as a test.

### Staging a batch

`src/server/SourceSlicePlanStage.luau` decodes plan JSON and hands it to `Builder.StagePlans`
(which takes Lua tables, not JSON — that was the missing link). Stage only, no Apply path.

```lua
-- paste the smaller batch directly
local s=game.ServerScriptService.Server
local f=Instance.new("Folder"); f.Name="SourceSliceFresh"; f.Parent=s
s.PolygonSlab:Clone().Parent=f
s.PartExtents:Clone().Parent=f
s.SourceSliceBuilder:Clone().Parent=f
local m=s.SourceSlicePlanStage:Clone(); m.Parent=f
local ok,r=pcall(function() return require(m).Stage([[<contents of plans_review6.json>]]) end)
f:Destroy(); if not ok then error(r) end; return r
```

For all 48, put the contents of `plans_batch.json` in a `StringValue` named `SourceSlicePlansJson`
under `ServerStorage` and call `.StageFromStorage()`. Then `.Preview(stageName)` copies the staged
buildings into `Workspace.SourceSliceReview_Batch` in orange; `.Hide()` removes them.
Review against the red FBX and the grey live models **before** considering any Apply.

## Tools

Workspace: `D:\GameDownloads\JJK_Roblox`. Official Roblox MCP only (`list_roblox_studios` first). `execute_luau` must `return` a compact table; `_G` is nil.

**MCP, Sept 17 03:40 — TWO different plugins, do not confuse them again.** Ports were clean this
time (one server, holding 58741); the failure was entirely plugin-side.

- **Community** `robloxstudio` (root scope, `npx robloxstudio-mcp --port 58741`) drives the
  `mcp__robloxstudio__*` tools. Its Studio plugin is `MCPPlugin.rbxmx`, reached at
  **Plugins tab → "MCP Integration" toolbar → "MCP Server"** button. Health check:
  `curl -s http://localhost:58741/status` → look for `"pluginConnected":true`.
  `get_connected_instances` returning `count:0` means the **plugin**, not the server, is down.
- **Official** `Roblox_Studio` (project scope, `cmd /c … mcp.bat`) is a *different* plugin, built
  into Studio: Assistant Settings → MCP Servers → "Enable Studio as MCP server", with Quick-connect
  toggles per client. Turning that on does **nothing** for the community tools. Note its
  "Claude Code CLI" row has no toggle.
- `claude mcp list` reporting **both ✔ Connected is not sufficient** — it only proves the CLI can
  reach them. Claude Code binds MCP servers **at session start**, so a server added mid-session is
  healthy at the CLI and still has no tools. Confirm with an actual tool call, not the list.
- **No bash command fixes a mid-session binding.** Restart Claude Code.

**MCP troubleshooting (cost a full session on Sept 17 — read before retrying tools).** Two servers
are registered in `~/.claude.json`: `robloxstudio` (root scope, community, `npx robloxstudio-mcp@latest
--port 58741`) and `Roblox_Studio` (project scope, official, `cmd /c … mcp.bat`). Symptom was
`get_connected_instances` answering `{"instances":[],"count":0}` while every `execute_luau` timed out
— i.e. the **server** was alive but no **plugin** was attached.

- The Studio plugin (`%LOCALAPPDATA%\Roblox\Plugins\MCPPlugin.rbxmx`) dials a **hardcoded
  `http://localhost:58741`**. Confirm with `grep -ao "localhost:[0-9]*" MCPPlugin.rbxmx`.
- Every community server launches with `--port 58741`, but **they do not exit on conflict** — they
  silently fall back to 58742/58743/58744 and also bind **3002**. Four had accumulated across days.
  A stale one held 58741, so the newest server (the one this session talked to) was unreachable by
  the plugin no matter how often the plugin was toggled.
- Check with `Get-NetTCPConnection -LocalPort 58741`, and map servers to ports via
  `Get-CimInstance Win32_Process -Filter "Name='node.exe'"` + `-OwningProcess`.
- Fix: kill **all** `robloxstudio-mcp` node trees and stray `StudioMCP.exe` processes so 58741 is
  free, then start one server and toggle the plugin. `taskkill /PID <npx pid> /T /F`.
- **A newly added MCP server does not hot-load.** Claude Code binds MCP servers at session start;
  `claude mcp add` requires a restart before its tools exist.
- `mcp.bat` has a cmd syntax bug (`else` on its own line after the closing paren). Harmless — the
  `if exist` branch runs `StudioMCP.exe` fine — but it prints two stray errors at shutdown.

Python: `C:\Users\anubh\miniconda3\python.exe` (3.13) + `tools/python_deps_py313`. 3.12 wheels: `tools/python_deps`. Blender: `D:\Blender\blender.exe`. FBX: `C:\Users\anubh\Downloads\Shibuya.fbx`. GUI Blender can stay closed. Background export:

```powershell
& 'D:\Blender\blender.exe' --background --python 'D:\GameDownloads\JJK_Roblox\tools\export_shibuya_fbx.py'
```

## Files

- `tools/source_slices/fbx_raw.npz`, `fbx_summary.json`, `live_meshes.json`, `live_buildings.json` (3193 records, matches live), `live_vertex_samples.json`, `alignment.json`, `world_triangles.npz` (174613 triangles).
- Transform: FBX `(x,y,z)` → Roblox `(-x,z,y) * 4.182817489324327 + (117.42021163650827,-4.628656099976979,253.12012546710255)`. 174 vertices, max error 0.00067947. **Do not scale chunks to Roblox bboxes separately.**
- `tools/source_slice_pipeline.py`, `source_slice_candidates.py`, `source_slice_sample.py`: exploratory polygonization, not certified plans.
- `tools/source_slice_fill_survey.py`: grey-vs-FBX fill and multi-owner survey, writes
  `source_slices/fill_survey.json`. Offline only. Note `STRtree.query(point, predicate="within")` —
  `"contains"` evaluates `point.contains(polygon)` and silently matches nothing.
- `tools/source_slice_plan_builder.py`: the generalisation of `SourceSliceFbxSample`. Slices the FBX
  under a group's shared centre, detects constant-section bands, fits the frame to the section's
  minimum-area rectangle, floors at the builder's pitch, picks the largest core inside the
  intersection of every band, and writes builder-ready plans to `source_slices/plans/*.json`.
  Re-validates each plan against the Luau contract (level count, piece simplicity and overlap, core
  containment, `MIN_CLEAR`) and reports rather than writes on failure. `--from-survey` groups by FBX
  polygon ownership; `--key` does one group. Cross-checked against the hand-authored seed: it
  independently produced 11 levels, 4 vertices, oversize 1.999 (hand value 2.00).
  Guards worth knowing: plans are rejected when the section is under 400 sq studs, when the greys are
  more than 8x the section (a rooftop fragment rather than the building), or when the core would fill
  over 60% of the plate. Without these it proposed a 23 x 11 sliver to replace four real buildings.
  Floors falling in a gap between surviving bands take the nearest band — earlier they were skipped,
  which left towers mostly unfloored (a 128-stud building got 3 levels instead of 7).
- `src/server/SourceSliceBuilder.luau`: origin `{x,y,z,yaw?,r00…r22?}`. Full rotation matrix preferred. Last level is Roof. Core is outer wall bounds.
- `src/server/SourceSliceReplacement.luau`: explicit sources only. Restore before Apply/save. **Tested** on fixtures, never used on the live sample.
- `src/server/SourceSliceVerification.luau`: Command Bar fixtures.
- `src/server/SourceSliceFirstSample.luau`: this sample only. Copies live hull. Never Apply.
- `src/server/SourceSliceFbxSample.luau`: seed `16_7714`, footprint sliced from the FBX. Polygons
  are embedded constants; floor elevations are read from the live tallest member with a uniform
  fallback. `Plan` / `Compare` / `Show` / `Hide` / `Stage`. No Apply path.
  Fixed Sept 17 before ever running: it derived level elevations as `row.bottom - FBX_BOTTOM`, but
  the live slabs start at 109.34, *below* the band's 109.70, so the first level took a negative `y`
  and the base assert would have fired immediately. The base is now the lowest kept storey.
- `src/server/SourceSlicePlanStage.luau`: decodes generated plan JSON and stages it through
  `Builder.StagePlans`, which only accepts Lua tables. `Stage(json)` / `StageFromStorage(name)` /
  `Preview(stage, ids?)` / `Hide()`. Stage only, no Apply.
- `tools/source_slices/fbx_sample_16_7714.json`: that seed's polygons, bands and core.
- `src/server/PolygonSlab.luau`: native Part/Wedge slabs. Reuse it. **A wedge's thickness is on
  LOCAL X, not Y**, and its `Size` box is twice its geometry.
- `src/server/PartExtents.luau`: `Corners` / `Box` / `Footprint`. World-space extents of REAL part
  geometry, wedge-aware. **Use this for every footprint measurement.** Never `GetBoundingBox`
  (pivot-oriented) and never all eight corners of a wedge.
- `tools/wedge_box_check.py`: offline replication of the triangulator that proved the point. Throwaway.
- `src/server/SourceSliceLiveExtents.luau`: `Dump()` / `Clear()`. Read-only live dump of measured
  per-building extent AND material footprint area to `ServerStorage.SourceSliceExtents_*`
  StringValues (CSV, 180 KB chunks, plus a `_Manifest`). **This is the missing input for rebuilding
  `fill_survey.json`** — the survey cannot be fixed offline. Use column `fa` (material area), not
  `ax`/`az` (extent), for any oversize question.
- `rojo build` is scripts-only, not a map backup. `ServerStorage.ShibuyaBefore*` archives are older generations; do not bulk delete.

## Builder / replacement contracts

Plan: `{id, origin={x,y,z,yaw?,r00…r22?}, levels={{y,thickness,pieces={{{x,z}...}}...}}, core={minX,minZ,maxX,maxZ}, sourceInfo?}`. Level `y` is relative to `origin.y`. Pieces must not overlap. Core must lie in every level union. `StagePlans` → ServerStorage. `Capture(stage, {explicit models})` / `Preview` / **`Restore` before Apply or save** / `Apply` archives to `ShibuyaBeforeSourceSlice_<guid>`.

## Open items from the Sept 17 live runs

1. ~~`elevations` fell back to `"uniform"`~~ — **cause found, fix written, not yet run live.**
   It was not naming; floor parts really are called `Slab`. `liveSlabs` mis-measured WedgeParts.
   See "RESOLVED Sept 17" above. Confirm live that `elevations` now reports `FLOOR_SOURCE`.
2. ~~Unexplained overlay extent~~ — **closed.** It was the eight-corner measurement counting the
   empty half of each wedge box. Real footprint is exactly the predicted 181.31 × 177.70.
   Reproduce with `python tools/wedge_box_check.py`.
3. Wedge counts behave: after snapping `MAIN` to a true rectangle the ten floors build as single
   Parts and the only 16 wedges are the genuinely 10-sided setback roof.
4. **The grey oversize factor is STILL unmeasured** after the 03:33 run. 2.00×, 1.79× and 1.0001×
   are all withdrawn, for three different reasons — see the live-run section. The replacement is
   `greyAreaFactor` (material area, not extent); it must come back between 1.00 and 1.68, and
   `greyEstimatedParts` must be 0. **Re-run `.Stage()` to get it.**
5. **NEW — `fill_survey.json` needs a live dump to rebuild.** It cannot be fixed offline;
   `live_buildings.json` carries only pivot-oriented model `GetBoundingBox` data. Dump per-building
   `PartExtents.Footprint` from Studio, then re-run the survey against that.

## Required next work — REWRITTEN Sept 17 06:00, the old list was built on a dead premise

Read the three Sept 17 sections above first. Everything below follows from measurements, and the
measurements say the project was aimed at the wrong problem.

### A decision only the user can make

**The greys' footprints are already right.** At `16_7714` grey matches the FBX section to 0.02%, and
map-wide only 21 of 3,193 greys are boxes at all. Meanwhile re-slicing fights a **non-watertight
export** whose sections drop out at scattered heights, which is what put a median 38% of the
original batch's plate area outside the building.

That opens a cheaper route to what the user actually asked for:

1. **Merge the existing grey fragments** — one `Building` per group, one core, fragments' geometry
   combined. Fixes identity, duplicate cores and overlapping sections while keeping footprints that
   are already accurate, and never touches the FBX.
2. **Keep re-slicing the FBX** — truer outlines in principle, but it has to beat a mesh that will not
   polygonise cleanly, and each plan needs `source_slice_pokeout.py` to prove it.

The user's complaint list was "identity, outlines, overlapping sections, duplicate cores". Route 1
fixes three of the four outright. Route 2 is the only one that improves **outlines** — so the real
question to put to them is *how bad are the outlines actually*, which nobody has measured.
**Ask before building either.**

### If continuing with FBX slicing

1. Regenerate with the fixed builder (`plans_v3`) and run
   `python tools/source_slice_pokeout.py tools/source_slices/plans_v3`.
   **Gate: median outside must be near 0% and no plan above ~5%.** The control (hand seed) proves
   0.0% is achievable. Do not stage a batch that fails this gate — the old one passed the Luau
   contract and was still 38% wrong.
2. Then stage, and measure live: height ratio vs greys (target ~1.0), base within 2 studs, and
   `Builder.Audit` clean. Raise the `noOverlaps` native tolerance from 0.1 if the only failures are
   0.13–0.18 sq stud float32 accumulation.
3. Only then preview and get the user's eyes on orange-vs-red before any Apply.

### Regardless of route

4. **Do not rebuild `fill_survey`'s `fill` metric.** It is disproved, not merely unreliable. If
   seed selection needs a signal, use group membership (identity) and `source_slice_pokeout.py`.
5. **Never judge fit by extent.** Extent cannot see inside a bounding box, and a correct slice is
   legitimately *larger* than the fragments it replaces. Material area or pokeout, nothing else.
6. Coverage regressed with the fixes: 48 plans / 186 greys -> 41 / 148. The dropped groups were not
   diagnosed (the run's stdout was lost to buffering). Re-run capturing output and check the SKIP
   reasons before treating 41 as the real number.
7. `Apply` still has never been run on anything. No `ShibuyaBeforeSourceSlice_*` archive exists.

## Constraints

`Building` name prefix is load-bearing for HitHandler. Structure = Part/Wedge/Union, never the FBX MeshParts. Keep Building1/2/3, Shibuya meshes, furniture, archives. Do not change combat, movement, or terrain unless a compatibility fix is explained. Do not ground every building to flat Y 36 terrain; this sample uses **neighborhood/live base Y 118.7**, not Studio terrain.
