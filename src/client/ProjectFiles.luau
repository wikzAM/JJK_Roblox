--!nonstrict
--[[
START HERE: tools/SHIBUYA_LIVE_STATE.md — measured census of the live place,
  the rebuild commands, and the Studio gotchas. Written so a fresh session needs
  no MCP calls to know where things stand. Then tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md
  for the reasoning record. THE MAP IS UNSAVED.

September 22, 2026 — FLOATING, PARTIAL, ROADS (the owner's I-beam photos).
  Floating roof-only stubs extended to where the FBX walls end
  (tools/source_slice_extend_floating.py, 13). Storeys missing mid-building are
  filled with the next level above (Planner in source_slice_orphans.py, and
  tools/source_slice_gapfill.py); 78 one-storey greys got a mid slab.
  tools/source_slice_partial.py plans FBX buildings that live buildings only
  partly covered (the "missing / rotated" ones) whole: 56 replaced 57 live, via
  Sweep.Replace. NEVER touches tools/source_slices/sweep/protected_live.txt (the
  22 shell crowns + Cerulean). 5 more roads to RemovedInfrastructure;
  orphans.REMOVED lists them all. Live: 2,069 buildings, 298 greys.
  Details: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md, "FLOATING, PARTIAL, ROADS".

September 21, 2026 — ROOF ENVELOPE + ORPHANS. FBX coverage 49.8% -> 86.5%.
  The pipeline was GREY-DRIVEN (only sliced the FBX under an existing grey), so
  buildings with no grey -- Shibuya PARCO among them -- were never generated, and
  wall cuts fail on this PLATEAU export (walls and roofs are separate surfaces,
  whole wall runs missing: PARCO's cut at Y 250 is 17 triangles, all open ends).
  NEW tools/source_slice_roofs.py: a plate at height y = union of roof faces
  above y. Monotone -- no mushrooms, no pinches by construction. Built from the
  roof TRIANGLES, not a raster (raster: 150-207 verts a ring; faces: 8).
  Section builder fallback is now wall cut -> roof envelope -> band (only above
  the lowest closed section). Cerulean + control regenerate byte-identically.
  NEW tools/source_slice_orphans.py: identity from mesh connectivity (PLATEAU
  buildings weld to themselves, not neighbours), stacked components merged on
  roof+wall outlines with holes filled. 626 buildings added (PARCO =
  orph_703_1736, 23 levels), 155 rebuilt. 4 elevated viaducts removed to
  ServerStorage.RemovedInfrastructure -- the envelope floored the space under
  the deck. Live: 1,998 buildings, 352 greys.
  MEMORY: Studio ~14 GB (306k parts in ServerStorage archives). One plan worker
  = 1.03 GB. 12 workers + Studio crashed Claude Code (ENOMEM).
  Details: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md, "ROOF ENVELOPE + ORPHANS".

September 20, 2026 — WHOLE-MAP SWEEP GENERATED (offline). Nothing applied.
  The four sectors were hand-driven at ~30 buildings each; the ~2,900 remaining
  greys were another 70 sessions at that rate. tools/source_slice_sweep.py now
  plans the whole remainder in one pass: 89 tiles of 600 studs, 12 processes,
  10.7 min wall clock (107 CPU-min) -> 1,287 plans claiming 2,182 greys over
  6,497 levels. After the gate: 1,254 buildings over 2,136 greys in 51 chunks,
  median mean-IoU 0.997, 33 dropped under 0.95, 46 kept but unmeasurable.
  BUG THE SWEEP FOUND: the core guard's shrink solves for the scale that lands
  the core EXACTLY on MAX_CORE_SHARE, so re-testing `> MAX_CORE_SHARE` was
  decided by float rounding -- 0.600000000000001 vs 0.6. It refused 166 groups
  / 228 greys whose shares before the shrink were 0.744 and 0.996, i.e. real
  buildings. The re-test now carries +1e-9; the guard still catches the case it
  was written for (the max(2.0,...) clamp stopping the shrink). The shipped-plan
  control still regenerates byte-identically, and the fix recovered 154
  buildings.
  Budget if all 51 chunks are applied: structure ~159,700 + parapets ~9,100 +
  shell crowns ~77,100 - ~114,900 of removed greys = about +131,000 parts,
  taking 219,300 to ~350,000. The 201 shell crowns are 31% of everything added
  on 16% of the buildings; the tighter rule (slope>=0.25 or band>=55) leaves 134
  and saves ~24,300.
  --box REPLACES --near FOR SWEEPS. A --near disc overlaps its neighbours, which
  is why sectors 2/3/4 each re-offered buildings that were already live. --box is
  half-open on its max edges, so a grid of boxes PARTITIONS the map: one tile per
  group, no tile can claim another's greys, tiles are independent processes. The
  builder's own deduplicate() runs globally after the merge for plans that fall
  either side of a tile edge. --skip-names drops already-replaced greys first.
  CONTROL: --key 4_-1164_1279_-9107 regenerates a SHIPPED plan byte-identically,
  so the patch changes selection only.
  THE GATE IS MEAN IoU, NOT `outside`. pokeout's `outside` column is the WORST
  SINGLE LEVEL's spill, not the building's: the applied Cerulean Tower scores
  97.8% outside with a mean IoU of 0.977. A 5% spill gate would refuse a building
  the owner approved by eye. source_slice_chunks.py gates on IoU >= 0.95 (what
  the sectors actually used); --spill exists and defaults to OFF.
  1,074 greys (35%) produce no plan: under two storeys of FBX section over their
  footprint, or none at all. NOT all small -- 186 of those groups have a live
  grey over 36 studs and one is 362 studs over a 14-stud band. Flooring those
  would invent storeys the scan never recorded, which is the same mistake as the
  four failed crown fitters. Left grey is the honest outcome; a low-rise pass is
  the owner's call.
  APPLYING: src/server/SourceSliceSweepApply.luau. Preview/Commit/Discard/Run/
  Status, one chunk (~25 buildings) per call, pulled over the sink because a
  chunk with its crowns is megabytes. The lock folder is the FIRST statement
  (execute_luau replays) and the stage is never found by searching -- the two
  rules from the near-miss that almost replaced the wrong 46 greys.
  MCP: MCPPlugin.rbxmx discoverPort() probes 58741..58745 and takes the first
  server reporting mcpServerActive with pluginConnected:false. Community servers
  launched with --port 58741 do not exit when it is taken, so a STALE server from
  a previous session owns 58741 and the plugin attaches to a server no live
  session is talking to. Kill every stale node server; if the live one is not on
  58741 and Studio cannot be restarted (unsaved map), proxy the port -- and
  listen on IPv6 as well as IPv4, because Windows resolves localhost to ::1 first
  and an IPv4-only proxy is invisible to the plugin while curl finds it.
  Read tools/SHIBUYA_SWEEP_RUNBOOK.md before opening Studio.

September 19, 2026 — CROWNS FINAL: parapet default, FILLED shell where earned.
  The 22 interesting crowns are back on the sealed wedge shell the owner
  approved by eye, but FILLED rather than hollow.
  TriangleShell gained options.fillToward (Vector3). A WedgePart is centred on
  its triangle, so just raising thickness bulges half of it OUTWARD and fattens
  the building. fillToward slides each wedge so its OUTER FACE STAYS ON THE
  TRIANGLE and the thickness grows INWARD, towards the crown's centre of mass --
  silhouette unchanged, interior filled. Inward is decided per triangle by
  dot(fillToward - triCentroid, normal), NOT by winding: this scan's winding is
  not consistent (same reason the sealer walks boundaries undirected).
  Thickness 10, picked by eye against 4 -- at 4 the faces still read separately,
  at 10 they merge into one mass. 0 triangles skipped either way.
  LIVE: crown = 857 parapet + 8,628 filled wedge = 9,485 parts. 100 dull
  buildings ~8.6 parts each; 22 interesting ~392 each. Workspace 219,300 parts,
  1,315 MB, 183 parts per source-slice building. Still 3.5x under the 33,356
  wedge-shell peak because the cost lands only where it is earned.
  Heaviest to eyeball before scaling: fbx_6_2510_2462_-12844 (1,272 parts,
  234x338 studs) and fbx_4_-2192_1412_-10100 (950).

September 19, 2026 — CROWNS: PARAPET BY DEFAULT, DETAIL WHERE EARNED. UNSAVED.
  FOUR attempts at reconstructing rooftop detail from the scan all failed:
  wedge shells fanned at corners; slice+plateau-intersect wiped roof clutter
  (25 crowns -> 1 box); slice+per-level rectangles gave FLOATING SLABS (MIN_SIDE
  applied to height); per-object box-or-prism terraced again (17 prisms of
  exactly 4 studs on Cerulean).
  THE REASON IS THE DATA. The median crown component keeps only 0.38 of a closed
  box's surface area -- the scan saw a roof's top and one or two sides, nothing
  else. There is no solid to recover; every fitter invented the missing half,
  differently each time. The FBX itself is clean: Cerulean's crown is 89
  triangles over 100 vertices with ZERO slivers.
  SPLIT: dull crown -> PARAPET, the top floor's own (already validated) outline
  extruded 2-8 studs via PolygonSlab, inventing nothing. Interesting crown ->
  left alone and marked CrownInteresting with the reason, for hand work.
  tools/source_slice_crown_parapets.py + src/server/CrownParapet.luau.
  INTERESTING, measured over 181 crowns: sloped share of surface area has median
  0.00 / p90 0.17, band height median 24 / p90 47. slopeShare>=0.20 OR
  bandHeight>=50 picks 25 of 181 (14%), Cerulean included. REJECTED: a taper
  test (bottom vs top third footprint IoU) is bimodal at exactly 0.00 or 1.00
  because one footprint is usually empty -- no information.
  LIVE: 22 of 122 flagged interesting (keeping box crowns), 100 with parapets.
  Crown parts 1,501 -> 1,335 (857 parapet + 478 box), from 33,356 at the
  wedge-shell peak. Workspace 211,150. A source-slice building is 116 parts.
  NEXT (owner's call): scatter AC units and roof clutter procedurally instead of
  recovering them from a scan that never recorded them.
  STUDIO GOTCHA: require() caches modules for the session, so an edited module
  never loads. Clone it into a folder and require the clone.

September 19, 2026 — BOX FITTER BUG FIXED. I shipped floating slabs. UNSAVED.
  MIN_SIDE=3.0 guards the minimum box dimension and I applied it to HEIGHT too.
  Slices were STEP=2 apart, so any box existing for a single slice was 2 studs
  tall, failed the test, and was DELETED -- punching air through the stacks.
  622 overlapping box pairs across 47 crowns had gaps. MIN_SIDE now guards plan
  dimensions only; height floors at STEP*0.9.
  I HAD CHECKED THE WRONG THING: I verified box tops reached the building top
  and bottoms started at the band, called it clean, and never looked at the
  middle. Every build now runs a VOXEL check instead -- boxes rasterised back
  onto the slice grid, yielding four numbers:
    cover  of the sliced solid that got boxed      median 95-97%, worst 81%
    over   box where the FBX had nothing           0.0% everywhere
    drop   box with SOLID below we failed to box   median 0.0%, worst 2.4%  <-- the bug
    float  box with EMPTY below (real canopy)      median 0.0%, worst 8.4%
  Splitting drop from float is the point: a box over empty FBX is a real
  overhang and correct; one over solid FBX is the defect. A single "floating"
  number conflates them and would hide it again.
  DO NOT REUSE the earlier pairwise gap check -- it flagged any two boxes
  overlapping in plan with air between, which a third box may legitimately fill.
  DECOMPOSITIONS TRIED: canonical row-runs are stable between heights but
  fragment on ROTATED shapes (every edge a diagonal staircase) -- 294 boxes per
  building, or 19% coverage on the Cerulean n-gon. Greedy largest-rectangle is
  unstable (median box one slice tall, 569 boxes for sector 2) but that is a
  PART COUNT problem, not correctness. Greedy on a COARSE grid wins:
  CELL=4, STEP=4, MIN_SIDE=4.
  Live: 957 boxes + 544 wedges (4 buildings fit no box) = 1,501 crown parts,
  from 33,356. Workspace 211,316. A source-slice building is 117 parts (was 439).

September 19, 2026 — CROWNS ARE SOLID BOXES NOW. 33,356 -> 1,458 parts. UNSAVED.
  The owner saw fans of thin plates at rooftop corners and said the FBX looks
  clean in Blender. They were right. Measured on the raw npz at the Cerulean
  crown: 89 triangles, 100 distinct vertices (same at 0.001 and 1.0 stud weld),
  0 duplicate faces, 0% slivers, median face 533 sq studs. Every artefact was
  MINE:
   (1) clip_band manufactures slivers -- 9.7% of clipped triangles have a
       shortest altitude under 1 stud, aspect ratios to 9,085:1. Sealing and
       dilation REDUCE this (9.7 -> 9.1 -> 4.6%), so they were never the cause.
   (2) a thin feature (mast, fin, sign) has two surfaces a few studs apart; as
       two 0.6-stud plates they overlap and splay at every corner. That is the
       fan. It is what you get drawing a SOLID as a SURFACE.
  FIX: tools/source_slice_crown_boxes.py + src/server/CrownBoxes.luau. Slice the
  crown band every 2 studs (the proven floor machinery; each slice is a SOLID
  footprint), cut every slice into maximal rectangles on ONE SHARED grid, merge
  a rectangle with the identical rectangle above it into a box, emit one Part
  per box. All in the BUILDING'S OWN yaw frame -- only 3.2% of vertical crown
  faces are world-axis-aligned, so a world-axis fitter finds nothing. Local
  (x,z) in the payload are the plan's own (a,b) piece coordinates.
  Crown parts 33,356 -> 1,458 (684 boxes + 774 wedges kept on 5 buildings that
  fit no box). A source-slice building is 117 parts, down from 439. Workspace
  243,171 -> 211,273. Cerulean 416 wedges -> 18 boxes.
  MEMORY CAVEAT: only moved 1,298 -> 1,289 MB in-session, far less than the part
  count implies. Studio does not reclaim the tags promptly. Trust the part count
  until it is remeasured in a fresh session.
  TRIED AND REJECTED (1): grouping slices into plateaus and intersecting them.
  It keeps only what runs a plateau's full height -- collapsed 25 of 120 crowns
  to ONE box and wiped the roof clutter that is most of what a crown is.
  TRIED AND REJECTED (2): slope wedges on the boxes (--wedges still does it).
  The box stack already expresses Cerulean's sloped roof as steps, so the plate
  floats above them as a blade and overhangs the boxes by 38 studs.
  Coverage checked before rollout: boxes start at the band (median gap 0.0), and
  the top falls >8 studs short on only 8 of 118 -- thin masts, correctly skipped.

September 19, 2026 — CROWNS BOUNDED. Two defects, both mine, both measured.
  The user saw giant diagonal sails around small buildings. Two causes:
  (1) CROWN BAND REACHED 140 STUDS UP REGARDLESS OF THE BUILDING. MAX_CROWN=140
  plus OUTLINE_PAD=14 let a neighbouring tower into the band. 92 of 123 crowns
  reached above their OWN building's top; the mean crown was 1.24x the height of
  the building under it. fbx_16_13294_1839_-3533 is a 23-stud building whose FBX
  stops at 171.6 and whose crown ran to 304. Fix: ceiling at the building's own
  top, which the plan already records -- max(fbxTop, greyTop) + 10. Result 92->0,
  median crown height 52 -> 27 studs.
  (2) THE SEAL THREW MEMBRANES ACROSS OPEN SKY. fill_loop filled ANY boundary
  loop including a crown's genuine outer edge. The seal made the largest triangle
  bigger on 24 of 123 crowns; one went 2,450 -> 22,380 sq studs and shipped as a
  0.6 x 92 x 90 stud wedge. Fix: MAX_GAP=8 in the sealer -- a fill triangle whose
  SHORTEST ALTITUDE (2*Area/longest edge) exceeds 8 studs is not closing a crack,
  exceeds the cap is not closing a crack. Rejected per triangle, not per loop.
  TUNED BY SWEEP over 123 crowns (raw largest triangle 4,074 sq studs):
    cap     4    8   12   16   24   40  none
    closed 18%  39%  54%  65%  75%  81%  83%
    maxTri 4180 4180 4180 4180 4180 4180 26444   <- the sail, uncapped only
    >2000    29   29   29   29   34   45    95
  Any cap kills the sail; at any cap up to 16 the seal adds NOTHING bigger than
  the FBX already had, so MAX_GAP=16 is the largest safe cap.
  Live: crown wedges 37,982 -> 33,356 (12% fewer), 273/building, closure 60-72%
  per sector. 243,171 parts. Worst offender fbx_16_13294 now has a 61-stud crown
  on its 23-stud structure, down from 143.
  WHY CROWNS COST SO MUCH: floors pay per STOREY, crowns pay per TRIANGLE. One
  slab Part covers a whole storey at any size; every crown triangle is 2
  WedgeParts, and a plain box arrives as 12 triangles = 24 wedges where a Roblox
  Part would do it in 1. Crown cost is nearly FLAT with height (200 wedges under
  60 studs vs 286 at 100-150), and 72% of buildings are under 100 studs but carry
  61% of all crown wedges.
  Workspace.Shibuya was MOVED to ServerStorage.Shibuya (intact, 16 MeshParts).
  Do not assume workspace.Shibuya exists.

September 18, 2026 — SECTORS 2-4 APPLIED. 122 buildings, all crowned. UNSAVED.
  sector 1 --near 387 -894 500 : 24 applied, 35 greys, 9,126 crown wedges
  sector 2 --near 387 -194 450 : 27 applied, 33 greys, 7,572
  sector 3 --near 1165 -116 450: 35 applied, 46 greys, 11,066  (gate 34/34)
  sector 4 --near -313 -894 450: 33 applied, 43 greys, 8,306
  The two first-test buildings finally have crowns; 0 of 122 are crownless.
  Live: 3,030 greys + 122 BuildingSourceSlice = 247,813 parts, 1,521 MB
  (6.3 KB/part, stable across every measurement). Source-slice is 50,786 parts
  over 559 storeys, of which 37,982 are crown wedges = 75%.
  SECTORS OVERLAP: drop any plan whose id is already a live BuildingSourceSlice
  before staging, or Capture binds a grey that no longer exists (5+2+3 so far).
  EXECUTE_LUAU REPLAYS AND IT NEARLY APPLIED THE WRONG GREYS: the staging call
  ran ~3x, made duplicate stages and MISLABELLED one -- a stage holding sector
  3's 35 models came back tagged sector4, because copy 2 searched for "the stage
  with no Sector attribute" and found copy 1's before it was tagged. Rules now:
  (1) take a lock folder as the FIRST statement, before any HTTP or building;
  (2) never find a new stage by searching -- Builder.StagePlans returns the
  folder, hold that handle, then assert #children == #plans and outputs ==
  #plans before Apply. The mismatch (33 outputs for 35 plans) is what caught it.

September 18, 2026 — SECTOR 2 APPLIED + PERFORMANCE MEASURED. MAP UNSAVED.
  Archive ShibuyaBeforeSourceSlice_b81a036d-50b1-4d80-9d42-b47293247c11 (33).
  --near 387 -194 450: 27 applied, 33 greys replaced, 27 sealed crowns / 7,572
  wedges. Gate median IoU 0.996, 27/29 >= 0.95. Sectors overlap, so filter plans
  whose id is already a live BuildingSourceSlice before staging (5 were).
  Live: 3,119 greys + 54 BuildingSourceSlice + Building1/2/3 = 226,352 parts.
  SHIBUYA SKY IS FENCED IN CODE: PROTECTED in source_slice_plan_builder.py,
  (-630, 48, r260) = Workspace.Buildings.Building1, 29,907 parts with furniture,
  measured X -793..-468 Z -120..217 Y 57..967. A group is rejected if ANY member
  is inside. --exclude X Z RADIUS adds more zones.
  PERFORMANCE (measured, not estimated): source-slice = 439 parts/building vs
  53.8 for a grey; 25.3 structural parts/storey vs 14.8; 309 crown wedges per
  building = 70% of the building. Memory 6.4 KB/part (PhysicsParts 617MB +
  Instances 589MB + GraphicsParts 202MB over 226k parts; Studio inflates this).
  workspace.StreamingEnabled is FALSE -- that is the decision that matters.
  Resident sets: r500 = 10,799 parts, r1000 = 27,281. Whole-map projection is
  ~1.1M parts / ~7 GB unstreamed, and CROWNS ARE 71% OF IT.
  Hit cost does NOT regress: parts in the destroyAlongCylinder volume are 129
  and 16 in converted sectors vs 105 and 146 in greys (crowns are NoCSG, so
  deleted not carved).
  Crown headroom: 43% of crown triangles are right-angled. A rectangle = 2 tris
  = 4 wedges today but 1 thin Part; a closed box = 24 wedges but 1 Part. Only
  3.2% of vertical faces are world-axis-aligned, so box fitting must run in the
  building's own yaw frame. Coplanar merge alone is weak (2.2 tris/plane).
  MEASURED AND REJECTED: CanTouch=false on all 16,698 crown wedges moved memory
  by 0.0 MB. Not a memory win.

September 18, 2026 — CROWNS SEALED. 9,126 wedges live. MAP UNSAVED.
  The Shibuya FBX is a drone/photogrammetry scan and is NOT watertight, so the
  crowns rendered with slits you could see through. Measured: 1,770 crack edges
  across 25 crowns (boundary edges that are not a legitimate rim), 82% of them
  within 3 studs of another crack edge -- two sides of a slit, not a surface that
  ends. Welding does not help (Cerulean 131 -> 130 verts); the faces are absent,
  so the repair has to ADD geometry.
  tools/source_slice_crown_seal.py: drop slivers -> weld -> walk the boundary
  into loops (UNDIRECTED; scan winding is not consistent) -> fill each loop by
  minimum-area triangulation (Barequet/Liepa DP -- a slit loop runs up one side
  and back down the other, so filling the loop IS zipping the slit) -> dilate
  each triangle in its own plane to cover the V notch a 0.6-stud shell leaves at
  every convex fold. Bottom rim and a flat top loop stay open on purpose (the
  Cerulean helipad); --cap-top fills them.
  Result: crack edges 1,772 -> 360 (80%), crack length 45,810 -> 8,628 studs
  (81%), Cerulean 72 -> 2. Bounding box grows at most 1.0 stud, so no fill
  reaches outside the building.
  TRAPS: (1) the crack metric is meaningless AFTER dilation -- it detaches every
  triangle by design, 1,770 -> 11,204. Count before dilating. (2) Uncapped
  dilation throws needles: the corner step is pad/sin(half-angle), enormous at a
  sliver's tip. Cap it by the triangle's own inradius (2*Area/perimeter); a flat
  ceiling alone is not enough.
  STUDIO: workspace.CurrentCamera in edit mode takes position but silently
  REVERTS rotation -- set CameraType = Scriptable first or screenshots mislead.
  tools/source_slice_sink.py now serves GET /get/<repo path> so Studio can pull
  payloads too big to paste into execute_luau.
  Rollback: crowns_batch.py ... --no-seal reproduces the raw soup exactly; the
  old crowns were NOT kept in the place (5,730 orphan parts would have saved).

September 18, 2026 — SECTOR APPLIED: 24 buildings + 25 crowns. MAP UNSAVED.
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. Archive
  ShibuyaBeforeSourceSlice_0a6b883f-ef70-4397-bbf0-6541f33410dc (35 originals).
  Live: 3,152 BuildingSmooth + 27 BuildingSourceSlice + Building1/2/3 = 3,182.
  PRESS CTRL+S TO KEEP THIS.
  Sector = --near 387 -894 500 (the Cerulean Tower neighbourhood): 34 groups ->
  26 plans -> 24 applied (1 dropped on the gate, 1 already live). 35 greys
  consolidated. Gate before applying: median IoU 0.998, p10 0.990, 22/23 >= 0.95;
  fbx_6_705_2489_-10277 failed at 80.8% outside and was DROPPED, not shipped.
  CROWNS: 25 buildings carry a TriangleShell crown, 9,126 wedges (sealed). FBX
  triangles above the last floor are clipped to the band and rendered directly as
  WedgePairs -- no slicing, no storeys. Crown wedges are tagged NoCSG (HitHandler
  deletes rather than carves a 0.6-stud shell) at 0.6 thickness.
  CAVEAT: Builder.Audit now FAILS on any building with a crown, because it asserts
  every BasePart belongs to a declared floor. Audit before attaching crowns, or
  teach it to allow ShellWedge parts.
  New: --near X Z RADIUS spatial selection (this is how to scale -- sector by
  sector); core shrink-to-fit instead of rejecting (6 of 10 first-run skips were
  that one guard; sector went 15 -> 26 plans, 11 with coreShrunkToFit);
  tools/source_slice_crowns_batch.py bounds each crown by its own building's top
  outline, never a bbox, or neighbours' crowns come along in a dense sector.
  Also fixed: source_slice_pipeline.sections() crashed with IndexError when
  union_all emitted empty parts.

September 18, 2026 — FIRST APPLY. Two buildings live. MAP UNSAVED.
  Archive: ShibuyaBeforeSourceSlice_122c0a0c-6697-4e2f-8dab-c69b61dfe9c7.
  Live: 3,188 BuildingSmooth + 2 BuildingSourceSlice + Building1/2/3 = 3,193.
  PRESS CTRL+S IN STUDIO TO KEEP THIS, or close without saving to discard.
  Replaced BuildingSmooth_4_-9770_4222_-4948 (Cerulean Tower, 186 m -- matched by
  the 4.1828 studs/m FBX factor against the real 184.3 m) and
  BuildingSmooth_4_-10904_1766_-9267 (tapering 10-gon).
  Cerulean before/after, measured with PartExtents: Y 34.0-810.3 (185.6 m) ->
  34.0-789.4 (180.5 m); footprint extent 347x320 -> 440x371; 522 -> 946 parts.
  Both complaints addressed: the grey had a FLAT ROOF WITH STOREYS INSIDE THE
  CROWN and a base 25% per side SMALLER than the FBX podium (real podium is
  440x371, a 24-vertex n-gon). The sloped crown itself is still not modelled --
  PolygonSlab emits horizontal plates only, so a slope needs vertical wedges,
  a new capability. Nothing is built up there now, which beats a flat roof.
  Three builder fixes this seed forced: floors now stop at the last STABLE band
  rather than the last height with any geometry (that is exactly what put storeys
  in a crown); BAND_TRUST_SHARE=0.4 rejects a per-floor section under 40% of its
  own band as an artifact (Cerulean has a 1,259 sq stud sliver at the podium->
  tower neck that drove the core intersection to zero and rejected the whole
  43-storey building); and the probe window now takes the LARGEST section, not
  the first hit.
  Known imperfection: 1 level of 43 (Y 159, the neck) has a plate bigger than the
  FBX there, because the FBX has only a sliver -- a mesh hole. Mean IoU 0.977 for
  Cerulean, 0.996 for the second building.
  PLANS_V8 IS NOW STALE: all three fixes landed after it was generated, and the
  crown fix is the one that stops a tapering building getting a flat roof full of
  storeys. Do not scale from plans_v8 -- regenerate to plans_v9, re-gate, re-stage.
  The two APPLIED buildings were built WITH the fixes and are unaffected.

September 17, 2026 — plans_v8 is clean on every axis; this is the batch to use
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md (START HERE).
  55 plans consolidating 201 greys. Staged live as SourceSliceStage_e948c30c-...:
  55 of 55 BUILT, 55 GOOD, 0 BAD, 377 levels, 11,456 structural parts (208 per
  building, 9,522 of 9,524 slab parts wedges).
  Gate: median mean-IoU vs the FBX section 0.997, p10 0.991, WORST PLAN 0.989,
  54/54 at >= 0.95, ZERO plans over 5% spill, worst spill 3.4%, worst
  under-coverage 1.8%, 336/377 levels (89.1%) using their own height's section.
  Both v7 outliers gone: fbx_poly_250_79 (61.1% spill, tapering top) and
  fbx_poly_170_65 (23% under-coverage). Every plan is now >= 0.989 IoU.
  NOTHING APPLIED. Live map unchanged: 3,190 BuildingSmooth + Building1/2/3,
  49 Shibuya archives, FBX still in Workspace.
  Three things still need human eyes before any Apply: the rooftop trimming on
  17 plans (<=1 storey each; only a picture separates a parapet from a narrow top
  floor), the 21 levels sitting where the FBX has no geometry (mesh holes), and
  an orange building compared against the red FBX.

September 17, 2026 — last real defect fixed (tapering tops); v8 regenerating
  fbx_poly_250_79 had put 61.1% of one plate outside the FBX and had survived
  v4/v5/v7 unchanged. Cause, once measured per level: levels 0-13 matched their
  sections to 0.0-0.2%, but levels 14 and 15 both carried a 39,336 plate --
  identical to level 10's, ten storeys down -- while the real sections there are
  26,299 and 15,559. The building tapers at the top and those floors were using a
  BAND plate. The per-floor lookup called slicer.at(middle) once, at exactly that
  height; the non-watertight export drops sections at scattered levels, so a
  single miss fell back to the band, which is badly wrong on a taper.
  SECTION_PROBES now tries 0, +/-0.6, +/-1.2, +/-2.0 first. On that seed:
  exactLevels 13/16 -> 15/16 and 61.1% outside / IoU 0.934 -> 0.3% outside,
  0.1% under-coverage, IoU 0.998. Verified in isolation.
  plans_v8 (v7 + this fix) was STILL GENERATING at hand-off -- not gated, not
  staged. plans_v7 remains the validated batch: 55/55 built, 55 good, 0 bad,
  median IoU 0.996, staged as SourceSliceStage_afefdba8-...
  Nothing applied; live map unchanged at 3,190 greys + Building1/2/3.

September 17, 2026 — plans_v7: 55/55 build, 55 good, 0 bad, median IoU 0.996
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md (START HERE). plans_v7 is the
  batch to use: 55 plans consolidating 201 greys, staged live as
  SourceSliceStage_afefdba8-... with 55 of 55 built, 55 good, 0 bad, 377 levels,
  11,406 structural parts (207 per building, 9,472 of 9,474 slab parts wedges).
  Gate: median mean-IoU vs the FBX section 0.996, p10 0.991, worst plan 0.923,
  52/54 at >= 0.95, under-coverage median 0.3%. Fidelity is unchanged from v5 --
  the fixes bought buildability, not accuracy, and cost none. NOTHING APPLIED;
  live map still 3,190 greys + Building1/2/3, 49 archives, FBX in Workspace.
  ROOFTOP TRIMMING: implemented as asked, then MEASURED AND WALKED BACK. At
  0.25/36 studs it fired on 25 of 55 plans and removed up to TWO real storeys
  (fbx_poly_170_6 lost 34 studs where the live greys reach 229.3, and v5 had
  matched that top to under a stud). Now 0.15/24 with a hard floor that never
  cuts more than one storey below the live building's own top: 17 plans, max 18
  studs, 7 levels total. Still NOT verified by eye -- only a picture separates a
  parapet from a narrow top floor. ROOF_MIN_SHARE = 0 disables it.
  Remaining real defect: fbx_poly_250_79 puts 61.1% of one plate outside the FBX
  and has survived v4/v5/v7 unchanged. fbx_poly_130_8 (6.3%) is the only other
  plan over 5%. Everything else is at or above 0.95 IoU.
  Generation is slow (tens of minutes) and the cause is the per-floor slicer.at()
  calls added in v4, NOT the triangulation checks -- capping the replica search
  from 2048 to 300 states made verdicts instant and barely moved runtime. Cache
  sections by rounded height before scaling this to the whole map.

September 17, 2026 — both PolygonSlab defect classes diagnosed and fixed
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. The v5 stage now audits
  53 good / 0 bad (was 51/2) after one measured tolerance fix, and the three
  build failures have a fix awaiting a v6 run.
  1. "Slab protrudes beyond its source polygon": measured, not assumed -- max
     corner displacement 0.0024 and 0.0027 studs across 212 and 314 slabs. That
     is float32 (slabShape round-trips corners through WORLD space; Roblox stores
     CFrames as float32, and |x| reaches ~3000 here). The audit compared AREAS
     against a flat 0.01 sq stud floor, but a displaced edge costs area in
     proportion to its LENGTH, so a 400-stud perimeter turns 0.003 studs into
     ~1.2 sq studs and any large plate failed for free. Tolerance is now
     max(0.05, area*2e-5, perimeter*0.01). Re-audited live: 53 good, 0 bad.
  2. "No exact native-size triangulation (0.05 stud minimum)": the message is
     MISLEADING. The failing outlines have minimum edge 0.92-2.06 studs and
     minimum angle 47-68 degrees -- they are well conditioned. The real cause is
     PolygonSlab.triangulate exhausting its 2048-state backtracking budget on
     18-32 vertex rings. Do not hunt for slivers.
     Fixed without touching load-bearing Luau: tools/polygon_slab_sim.py is a
     Python replica of that triangulator (it reproduces the three live failures
     exactly), and the plan builder now walks SIMPLIFY_LADDER (0.9, 1.4, 2.0,
     3.0, 4.5), keeping the first tolerance whose ring provably triangulates.
     The check only runs on rings with >= 14 vertices and is memoised -- without
     that guard the run effectively hangs, because the replica burns the full
     budget on every ring it cannot tile.

September 17, 2026 — plans_v5: floors now follow the FBX to a median IoU of 0.997
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md (START HERE section).
  56 plans consolidating 205 greys. Offline gate: median mean-IoU vs the FBX
  section 0.997, p10 0.991, worst plan 0.923, 54/56 at >= 0.95, under-coverage
  median 0.3%. Staged live: 53 of 56 built, 51 good, 2 bad, 327 levels,
  7,748 slab parts (7,746 wedges), 9,404 structural parts. NOTHING APPLIED.
  FIFTH metric error, caught and corrected: the "under-coverage tail" (20 of 56
  plans below 0.95) was the GATE, not the plans. It selected the building's
  section with intersection>=300 against the greys' AXIS-ALIGNED region, which in
  a city this dense always catches a neighbour; the plate was then scored as
  failing to cover a building it never targeted. fbx_poly_170_56 read as 89%
  under-covering while actually matching its own section to 0.1%. The gate now
  uses the builder's exact rule. CAVEAT: that makes the gate answer "does the
  plate reproduce the section the builder chose" -- it no longer independently
  checks that the builder chose the right polygons. That check is still missing.
  The multi-piece change (emit every qualifying polygon, not just the largest)
  did NOT move the tail, because the tail was measurement. Keep it anyway; it is
  correct and 49 levels are genuinely multi-piece.
  EVERY remaining defect is in PolygonSlab, not the slicing: 3 plans fail to
  build with "No exact native-size triangulation (0.05 stud minimum)" because the
  sliced outline has slivers under Roblox's minimum part size, and 2 fail the
  audit with "Slab protrudes beyond its source polygon". Fix by conditioning the
  ring before PolygonSlab.Build. Highest-value remaining task.
  Rooftop clutter trimming is implemented but was added AFTER v5 was generated --
  regenerate to pick it up, and verify roofClutterTrimmed is 0 on real setbacks.
  Part budget: 168 parts per building at this fidelity; measure on a larger
  sample before scaling to the whole map.

September 17, 2026 — GOAL CLARIFIED: floors must follow the FBX geometry closely
  User: facades are handled separately, rooftop signs/AC need not be modelled,
  but the generated floors "should follow the geometry very well".
  STRATEGY SETTLED BY MEASUREMENT: slice the FBX, do not merge the greys.
  A/B over the 51 fragmented groups, same building, same height, same metric
  (tools/source_slice_ab.py): median IoU vs the FBX section is 0.994 for the
  generated slice against 0.462 for the live grey fragments; IoU >= 0.95 on
  40/51 vs 0/51; the slice wins on 51 of 51 plans. Grey fragments miss 9-78% of
  each floor, so there is nothing to merge.
  QUALIFICATION to the earlier "greys already match the FBX": that compared
  AREAS, and equal area is not equal shape. By IoU (source_slice_shape_survey.py,
  147 live floors) SOLO greys are genuinely good -- median IoU 0.996, 84% at
  >= 0.95, spill p95 only 1.1% -- and their failure mode is under-coverage
  (miss p95 24%). So ~44% of the map is already close and the fragmented 56% is
  not. Slicing everything fixes both and keeps one pipeline.
  Fidelity knobs measured: SIMPLIFY=0.9 costs almost nothing (median IoU 0.9988,
  p05 0.9890, vs 1.0 unsimplified) while halving vertices, so it is NOT the
  bottleneck; courtyard holes are negligible (2 of 68 sections, 0.1% of area).
  The real limiter was under-coverage: Slicer.at() returned only the single
  largest polygon, so buildings whose section is several disjoint pieces lost
  everything else -- worst plans covered 11-56% of their own floor while
  spilling only ~0.5%. Now returns all qualifying pieces; the builder already
  accepted a list of pieces per level.
  New offline tools: source_slice_pokeout.py (now reports IoU, spill AND
  under-coverage, and separates real defects from holes in the non-watertight
  export), source_slice_shape_survey.py, source_slice_ab.py, source_slice_sink.py.

September 17, 2026 overnight — Studio reached; the whole footprint premise is dead
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. Community MCP plugin connected
  (Plugins tab -> "MCP Integration" -> "MCP Server"; the official Roblox MCP is a
  DIFFERENT plugin and connecting it does nothing for these tools). Nothing was
  applied and nothing live changed: still 3,190 BuildingSmooth + Building1/2/3,
  49 Shibuya archives intact, Shibuya FBX left in Workspace where the user put it.

  1. GREYS ARE NOT OVERSIZED BOXES. Measured every building with PartExtents:
     extent area / material area is 1.00 for a box, 1.68 for a 21.5deg yawed
     rectangle. Only 21 of 3,193 greys are under 1.05. Median is 1.82 -- the
     typical grey fills 55% of its own bounding box. fill_survey divided FBX
     polygon area by grey BOUNDING BOX area, so a perfect grey scores ~0.55 and
     reads as "45% oversized". "933 greys oversized" is now positively DISPROVED.
     At seed 16_7714 grey's widest storey is 19,158.8 sq studs vs the FBX section's
     19,154.3 -- 0.02% apart, same centre, same yaw. No footprint win exists there.
     The old "194.9 x 195.9 box" was size.Y (the height) misread as horizontal,
     because that model's pivot is not upright.
  2. THE IDENTITY PROBLEM IS ~6x BIGGER THAN RECORDED and is the real target:
     562 multi-member groups covering 1,796 greys (56% of the map), largest 13.
     That is a lower bound; key-grouping splits 16_7714's five greys into two.
  3. THE GENERATED PLANS WERE NEVER CLOSE. New tools/source_slice_pokeout.py
     measures each floor plate against the FBX section at its own height
     (validated on the hand seed: 0.0% outside, IOU 1.000). The original 48 plans
     put a MEDIAN 37.9% of plate area outside the FBX, 33 of 48 over 5%. The
     "all 48 validate with zero failures" claim was contract compliance only --
     level counts, core containment -- never geometric fit.
     Root cause: the export is not watertight, so sections drop out at scattered
     heights; every dropout ended a band, a solid 35-stud tower became five
     2-10 stud slivers, and MIN_BAND=12 deleted all of them, so every floor
     inherited the podium plate. Tapering buildings fail the same way.
  4. FIXED in tools/source_slice_plan_builder.py: bands() now bridges gaps and
     ignores single-sample artifacts; each floor takes the section at its OWN
     height; the lowest band is extruded down to the greys' measured base (the
     FBX is hollow below ~Y 170 at many footprints and grey's base is invented,
     which the user wants kept); load() prefers measured live_extents.csv over
     pivot-oriented live_buildings.json. Measured live on 41 v2 plans: mean
     height retained 0.941 (was 0.38-0.48 on the worst seeds), base correct on
     37/41, audit 37 good / 4 bad (all four are 0.13-0.18 sq stud float32
     overlap against a 0.10 tolerance, not geometry).
  5. New src/server/PartExtents.luau and SourceSliceLiveExtents.luau are the
     measurement infrastructure; tools/source_slice_sink.py POSTs bulk dumps
     from Studio straight to disk. NOTE: execute_luau can run the same code more
     than once -- make every script idempotent.

September 17, 2026 — the "unexplained" overlay overhang was a measurement bug
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. No Studio work: the community
  MCP plugin (Plugins tab -> "MCP Integration" -> "MCP Server", dials
  localhost:58741) was never connected. Ports were clean this time -- one server,
  holding 58741 -- so it is the plugin, not the stale-port pileup. The official
  Roblox MCP plugin is a DIFFERENT plugin and connecting it does nothing for us.
  Both remaining open items turned out to be one root cause, found offline and
  reproduced exactly by tools/wedge_box_check.py: a WedgePart fills only HALF of
  its Size box. PolygonSlab builds that box as the rectangle spanned by the
  triangle's two legs, so the mirror corner is empty space outside the outline.
  - The "20 studs of unexplained excess in X" is not real. Measuring all eight
    corners gives 201.77 x 187.12; the session measured 201.7 x 187.1. Real
    footprint is exactly MAIN's 181.31 x 177.70. Nothing to explain.
  - elevations falling back to "uniform" was NOT a naming problem -- floor parts
    really are named Slab. liveSlabs read part.Size.Y as thickness, but a wedge's
    thickness is on LOCAL X, so mostly-wedge grey floors landed hundreds of studs
    below the FBX band and were filtered out.
  Consequence: 1.79x is withdrawn along with 2.00x. The overlay side was inflated
  too (32,219, not 37,755) and grey is mostly wedges. The grey oversize factor is
  currently UNKNOWN and Compare() will measure it on the next live run.
  New src/server/PartExtents.luau (Corners/Box/Footprint) is the wedge-aware
  measurement; use it instead of GetBoundingBox, which is also pivot-oriented.
  SourceSliceFbxSample now measures with it and reports measuredSizeX/Z beside
  predictedSizeX/Z. fill_survey.json still cannot be rebuilt offline -- it needs a
  live per-part dump. Nothing staged, previewed or applied; nothing live changed.
  NOTE: every Command Bar clone snippet must now also clone PartExtents.

September 17, 2026 late — first FBX overlay built live; fill metric retracted
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. SourceSliceFbxSample staged
  and previewed via Command Bar: builder accepted the plan (badBuildings 0,
  11 levels, base exact), floors build as single Parts after snapping MAIN to a
  true rectangle, 16 wedges are the setback roof only.
  RETRACTION: the "grey is 2.00x too big" claim compared a tight rotated
  rectangle against an axis-aligned box — a 1.68x artifact at this yaw. Measured
  properly (world AABB over real parts) grey is 259.8x259.9 and the overlay
  201.7x187.1, so grey is 1.79x — directionally right, wrongly derived. The
  whole fill_survey metric shares that flaw; median fill 0.689 is inside the
  artifact range, so "933 greys oversized" is NOT established. Multi-owner
  counts are unaffected. Rebuild the survey on measured part extents.
  Open: elevations fell back to "uniform" (liveSlabs wants a part named exactly
  "Slab"); overlay AABB is ~20 studs wider in X than MAIN predicts.

September 17, 2026 — FBX slicing generalised; Studio still never reached
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. No Studio work happened this
  session either: the MCP plugin dials a hardcoded localhost:58741, and four
  stale robloxstudio-mcp servers had accumulated, with a Sept 14 zombie holding
  that port while the live server sat on 58744. All were killed; every port is
  now free. A newly added MCP server does not hot-load, so the official
  Roblox_Studio entry needs a Claude Code restart before its tools exist.
  Studio was restarted 02:33, so the first-sample overlay and stage folder are
  gone (both disposable, nothing live lost).
  New tools/source_slice_plan_builder.py generalises SourceSliceFbxSample: it
  emits builder-ready plans for many seeds, revalidating each against the Luau
  contract. 48 plans generated, all re-validating from disk with 0 failures;
  186 greys consolidate into 48 buildings, each grey claimed exactly once.
  SourceSlicePlanStage.luau feeds that JSON into Builder.StagePlans (which only
  takes Lua tables). Nothing staged, previewed or applied — candidates only.
  Correction to earlier advice: group by FBX polygon ownership, NOT by
  ShibuyaSourceKey — the 16_7714 seed's five greys span two keys.

September 16, 2026 night — first real FBX seed written, not yet staged
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. Measured the FBX triangles
  directly instead of guessing. At the first seed the FBX footprint IS grey's
  rectangle (100% fill), so that sample was a dead end, not a near miss.
  City-wide, median fill is 0.689: 933 greys are >20% oversized and at least 83
  FBX polygons own 3+ greys each (same ShibuyaSourceKey, split by the residual/
  body passes) — identity and overlap complaints are real and now quantified.
  Reproduce with tools/source_slice_fill_survey.py.
  New SourceSliceFbxSample targets seed 16_7714: five greys are one building,
  and the big grey is a world-axis box exactly 2.00x the real yawed footprint.
  Plan verified offline (11 levels, 0 clearance violations, core inside every
  level). NOT staged — no Studio plugin was connected. Nothing live changed.

September 16, 2026 night — source-slice overlay copies live hull, not FBX
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. Orange overlay is a builder
  reconstruction of the live ExactPolygon (grey), truncated below roof equipment.
  Re-staged: 19 floors, 0 wedges, base Y 118.70, Floor1 yaw matches live
  (Right ≈ -0.805,0,-0.592). Grey still fits the FBX better. Do not Apply.
  Next agent: real FBX triangle slices from world_triangles.npz.

September 16, 2026 night — source-slice sample overlay misaligned, not applied
  Resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. Fixtures passed; first live
  sample overlay was a cached 12-floor wedge float. Rebuild copies live slab
  Ys from the base; re-stage with a cloned require. Do not Apply yet.

September 16, 2026 evening — source-slice fixtures tested, nothing applied
  Operational resume: tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md. Builder/replacement
  Command Bar fixtures passed; no BuildingSourceSlice_* is live; map not saved
  by this work. Next: one source-envelope parallelogram sample, then setback
  and compound ownership, staged before any Apply.

September 16, 2026 — zero live jagged autos
  Latest user direction supersedes the earlier keep-live rule: remove all jagged
  BuildingAuto_* models from the live map, accept robust smooth approximations
  for difficult sources, and refine individual buildings later when needed.

  ShibuyaFinalSmoothPass completes that migration. It first decomposes valid
  InteriorGrid data into non-overlapping vertical segments and builds a convex
  hull for each segment. Sources with invalid grids, no usable segments, or too
  many fragments fall back to a single source-envelope box. The fallback is
  intentionally conservative and visually simple; exact archived originals can
  support later case-by-case refinement. Three final core-incompatible sources
  used widened 50-stud rectangular rescue footprints.

  Live Studio migration started at 2,167 BuildingSmooth_* / 638 BuildingAuto_*
  and ended at 3,190 BuildingSmooth_* / ZERO BuildingAuto_*. This pass archived
  all 638 remaining autos and generated 1,023 smooth bodies across eleven
  ShibuyaBeforeGridSplit_* archives. The jagged originals remain invisible in
  ServerStorage as reference/rollback material; none remain in Workspace.
  Final direct audit: 3,190 smooth buildings, 174,531 structural parts including
  101,782 wedges, zero bad smooth buildings, and no review/preview residue.
  Workspace.Buildings still contains the three intentional procedural/reference
  models Building1, Building2, and Building3. Press Ctrl+S before closing Studio.

September 15, 2026 — guarded grid recovery and disconnected-body splitting
  IMPORTANT: MCP cannot invoke Studio's Save to Roblox/File action. The live
  DataModel changes below are currently in the open TestJJK session; press
  Ctrl+S (or File -> Save to Roblox) before closing Studio.
  Global cross-component reconstruction resumed after a Studio restart. Multi-loop
  slices now retain independent closed contours while ignoring unrelated open
  fragments and classifying courtyard holes. ShibuyaGlobalFootprint tracks those
  contours vertically by absolute height, measures coverage against every floor
  of saved InteriorGrid occupancy, binds every overlapping live BuildingAuto, and
  rejects any candidate overlapping an existing BuildingSmooth. Its Stage/Apply
  path supports several tracks sharing the same complete source set and archives
  every source atomically. Synthetic slice and volumetric fixtures pass.

  Three visually reviewed global-track recoveries were applied in this continuation,
  moving the live count from 1,488 smooth / 685 legacy to 1,491 smooth / 682 legacy.
  Full originals are retained in ShibuyaBeforeGridSplit_a11cce3f-...,
  ShibuyaBeforeGridSplit_96996c59-..., and ShibuyaBeforeGridSplit_fdd09c25-....
  The first rejected subset and a five-track stage overlapping four existing smooth
  buildings were restored/discarded. This smooth-overlap guard is load-bearing:
  global source loops include buildings already replaced in earlier passes.

  Residual-preserving continuation: ShibuyaResidualSplitPass now decomposes each
  saved InteriorGrid into non-overlapping vertical chains, smooths every chain
  that independently passes ShibuyaGridMassing, and regenerates every unaccepted
  occupied cell as a live BuildingAuto_* residual. Apply archives the complete
  original and installs all smooth/residual outputs atomically, so partial
  progress never deletes unresolved geometry. An end-to-end synthetic fixture
  verifies 256 accepted cells plus 25 retained residual cells through staging,
  apply, archive, and cleanup.

  Ten reviewed residual batches replaced 385 legacy source generations: 44 were
  completed outright and 341 retained smaller residual autos. They added 676
  smooth buildings, moving the live scene from 1,491 smooth / 682 autos to
  2,167 BuildingSmooth_* / 638 BuildingAuto_*. Of the remaining autos, 341 are
  reduced residuals and 297 are untouched. Final audit: 118,775 smooth parts and
  27,027 residual parts, zero bad smooth buildings, zero invalid residual parts,
  no workspace review residue. All originals are retained across ten
  ShibuyaBeforeResidual_* archives. Extractions below 20% were deliberately left
  live to avoid sparse/core-like slivers. Press Ctrl+S before closing Studio.

  Studio MCP edit session started at 914 smooth / 1,042 legacy models and ended
  at 1,488 BuildingSmooth_* / 685 BuildingAuto_* / 3 preserved original models.
  This session replaced 357 legacy source models with 574 smooth models. The
  higher output count is deliberate: 112 compound legacy sources were separated
  into 329 independently validated bodies/vertical segments instead of merging
  neighboring buildings. Another 245 sources used one-to-one smooth replacement.
  All 1,488 live smooth buildings passed a final direct audit: 85,260 BaseParts,
  zero unanchored/noncollidable/sub-0.05 parts, zero missing Interior or CoreSize.
  ServerStorage now retains 1,159 originals across 15 ShibuyaBeforeSmooth_*
  archives and 112 compound originals across 5 ShibuyaBeforeGridSplit_* archives.
  No review folders or nonempty staging folders remained after the final audit.

  ShibuyaGridMassing is the conservative fallback for source-mesh rejects. It
  traces saved InteriorGrid floor plates into real simplified polygons, requiring
  complete topology and repeated support; courtyards and meaningful detached
  bodies are rejected. Strict, low-rise, bounded 70% envelope, and 67% vertical
  coverage batches were staged, audited, and applied separately.
  ShibuyaGridSplitPass handles legacy models containing several substantial
  bodies. Preview tracks connected occupancy through floors, crops each body to
  its own frame, and accepts a source only when EVERY substantial body validates.
  PreviewSegments additionally partitions podium/tower forks into non-overlapping
  vertical chains. Stage isolates failures by source; Apply atomically archives
  each original once and installs every staged body. Synthetic two-body, branch,
  tiny-island, staging, and structural fixtures pass (5 segment bodies tested).
  Do not weaken this into dominant-body deletion: rejected secondary geometry
  must remain live unless a complete decomposition validates.

  The 6%-height sparse source profile was explicitly rejected after viewport
  review: it produced a core-like sliver and a visually merged footprint. Its
  24-model stage was restored and destroyed; none were applied. The moderate
  two-slice 10%-height source profile and bounded grid profiles passed review.
  Remaining 685 autos are mostly ambiguous disconnected/branching topology,
  low-envelope fragments, courtyards, or source groups with a failed body/core.
  Keep them intact until a stronger complete reconstruction is available.

September 14, 2026 — exact polygon floors, first two live batches
  Latest user direction: replace jagged/incomplete sections with simplified,
  complete massing and clean angled boundaries; retain recoverable originals.
  720 matched BuildingAuto sections replaced in Studio with BuildingSmooth_*:
  2,700 floors, 37,656 structural parts. First batch: 599; second batch: 121.
  Original 599 models: ServerStorage.ShibuyaBeforeSmooth_30db07da-4f2a-4e77-83f4-1899af3c2b08.
  Original next 121: ServerStorage.ShibuyaBeforeSmooth_1e181d82-3f87-4c17-93ce-f859ffaff19f.
  First full local checkpoint: Shibuya_Smooth_First599.rbxl (4,830,670 bytes).
  Saved TestJJK to Roblox September 14 at 11:47 Studio log time.
  This is an incremental pass, not a complete reconstruction of all buildings.
  PolygonSlab builds exact rectangle/concave polygon floors from Parts/Wedges.
  ShibuyaMassing finds persistent footprints at multiple source heights, trims
  roof equipment and preserves supported nested setbacks. It rejects ambiguous
  missing walls, disconnected bodies and courtyards rather than inventing them.
  SmoothBuildingBuilder.Build(report) stages in ServerStorage; Apply(stage)
  archives only exact matched originals. Do not rerun the legacy full-map pass.
  SmoothBuildingPass.RunNext({BatchSize=100}) is the guarded incremental entry:
  it ranks remaining accepted matches by confidence, stages them, runs the
  structural audit, then applies only a failure-free batch. StageOnly=true
  stops before live changes. Every replaced BuildingAuto remains recoverable
  in a new ServerStorage.ShibuyaBeforeSmooth_* archive; none are deleted.
  SmoothBuildingReview.Show(stage,index,"before"/"after",angle) is temporary:
  ALWAYS call Restore() before Apply or saving, to return the hidden original.
  SmoothMassing/SmoothFrame attributes preserve polygon geometry for Regenerate.
  BuildingGenerator.Regenerate routes these buildings through the smooth builder.
  InteriorGrid is used for core placement, NOT visible floor boundaries.
  Live verification: 9 polygon fixtures, 2,699 collision probes, 5 invalid rings;
  3 complete-building fixtures, regeneration after movement, actual wedge CSG.
  All 720 buildings passed anchored/collidable/min-size and continuous-core
  checks. Visual before/after checks passed on tall and recessed examples.
  Floor counts remain height estimates; no unverified landmark identity applied.
  Bulk interiors remain StructuralOnly; furniture templates are available for
  a later layout pass. Source seam-repair improvements are being investigated.

September 13, 2026 — full jagged map restored (current working base)
  USER DIRECTION: work from the full jagged generation; keep the newer sparse
  box/manual version for later. This supersedes the clean-box priority below.
  Restored all 1,989 BuildingAuto sections, then conservatively archived 33 tiny
  short floating sections after Studio close-up checks of representative scraps.
  Workspace.Buildings now has 1,956 auto sections + the 3 original buildings.
  Remaining auto structure: 133,717 BaseParts; verified anchored, collidable,
  positive dimensions. This is an edit-time check, not a combat playtest.
  ServerStorage.ShibuyaManualAndBoxPass_20260913 preserves 92 alternate models
  (78 clean boxes + 14 manually measured buildings). Two previously rejected
  clean-box fragments remain in ServerStorage.ManualVisualRejectedFragments.
  ServerStorage.ShibuyaSmallFragments_20260913 preserves the 33 removed sections.
  The 16 red reference MeshParts are in ServerStorage.Shibuya.
  ShibuyaFragmentCleanup.Preview is read-only; Apply archives exact candidates.
  This pass used default thresholds, then restricted to measuredFloors <= 2,
  height <= 60 studs, and terrain clearance >= 40 studs. Re-preview with Explicit
  exact models before Apply. Never delete solely on low hollow-shell part volume
  or terrain clearance: much of the imported map is above the flat terrain.
  Jagged edges, larger fragmented sections and terrain alignment remain pending.
  Do not bulk replace this full base with ShibuyaBoxBuilder. Angle/wedge work
  should be incremental. ManualShellBuilder and ManualSurvey remain available
  for later; manual estimates are not surveyed real-world building identities.

September 13, 2026 — clean box revision (first live batch complete)
  Desktop control recovered after resetting its session and reacquiring Studio.
  Generated 80 clean box buildings: 641 floors, 4,567 structural Parts.
  Archived 1,989 prior auto sections in ServerStorage folder
  ShibuyaPreviousGeneration_1789340420.
  Workspace.Buildings contains 83 models including the 3 preserved originals.
  Every new level has exactly one full rectangular slab; all parts anchored and
  collidable; all 80 buildings have core metadata. Synthetic rotated-box,
  open-facade and triangular-prism checks passed; one live example inspected.
  Furnished 3-floor copy in ServerStorage.BuildingFurniturePreview works with
  current templates: 564 NoCSG pieces. Bulk structures remain StructuralOnly.
  Complete map checkpoint intended as Shibuya_CleanBoxes.rbxl.
  User moved the Shibuya reference into ServerStorage and reported fractured,
  floating and jagged output from the previous 1,989-component reconstruction.
  That count was mesh sections, NOT verified buildings; do not optimize coverage
  by reproducing it. Prioritize complete simple buildings and defer complex ones.
  ShibuyaGeometry.Scan(source) now supports the reference in ServerStorage.
  BuildingGenerator now bypasses collision sampling for single upright blocks
  and exposes GenerateBox(model, cf, size[, floors]): exactly one rectangular
  slab per level, while retaining the grid for core/furniture layout only.
  ShibuyaBoxBuilder adds conservative closed-contour rectangle classification,
  five-height footprint consistency, ground support and rotated overlap checks.
  A seam fallback requires 97% measured coverage on all four facade sides and
  rejects substantial internal edges. Grounding preserves the imported roof but
  extends the base to current terrain (max 125 studs and no more than source
  height); checks center and corners for level support. GroundAdjustment and
  SourceBaseY record the change. These remain estimated simplified buildings.
  Preview -> Build (ServerStorage staging) -> Apply (archive previous auto models).
  Manual buildings and source references remain untouched; failed stages cannot
  replace the live scene. See tools/ShibuyaBoxPass.md and VerifyBoxGeneration.luau.
  This is deliberately sparse: most disconnected/complex/small source geometry
  is deferred. Do not call it a complete map reconstruction. Browser reference
  access timed out on app approval; no PLATEAU/Maps match was established.
  True polygon/wedge floor boundaries for complex shells remain future work.

September 13, 2026 — automated Shibuya reconstruction
  Live command-bar run generated 1,989 additional BuildingAuto_* sections,
  9,005 height-estimated floors, 134,113 primitive structural parts; 0 failures.
  Preserved existing Building1/2/3 and all 16 Shibuya reference MeshParts.
  Full Studio map copy: Shibuya_Interiors.rbxl (NOT the Rojo scripts-only build).
  Checkpoint with the first three new samples: Shibuya_InteriorCheckpoint.rbxl.
  Reopened saved map: counts unchanged; all 134,113 parts are anchored,
  collidable primitive Parts with positive dimensions. 1,726 sections have
  core metadata; 263 have floors only. Regenerate passed on a disposable clone.
  Studio's viewport/ribbon stopped drawing reliably; restart did not restore
  3D rendering, so comprehensive visual/playtest validation is still pending.

  New edit-time modules: ShibuyaGeometry and ShibuyaAutoBuilder. Geometry reads
  EditableMesh triangles, welds coincident positions, and separates connected
  components. AutoBuilder slices those components at floor/ceiling heights and
  requires enclosed crossings in both horizontal axes. Cell corners and centre
  must fit; detached facades and small fragments are rejected. Rotated frames
  follow the longest horizontal mesh edge. It never uses city-block collision
  hulls as building footprints. 3,224 size-filtered components produced 1,989
  plans after enclosure filtering and excluding the three existing buildings.

  Re-run in EDIT mode after Rojo sync:
    local a = require(game.ServerScriptService.Server.ShibuyaAutoBuilder)
    local plans = a.Preview(a.Scan())
    a.Generate(plans)
  Source keys prevent repeating existing sections. These are mesh components,
  not verified cadastral buildings: wings can be separate, touching bodies can
  be merged. Curves/tapers follow a conservative, lightly stepped sample grid.
  Open geometry, very small structures and oversized connected blocks remain
  reference-only. Floor counts are estimates at the existing 5 m floor pitch;
  no real-world landmark identification was applied automatically.

  StructuralOnly=true generates slabs and core walls without the expensive
  furniture/carpet/lighting layer. Some stepped/tapered structures lose their
  ground-positioned core on upper floors; core continuity needs later review.
  GeneratedFloors records the planned floor count. InteriorGrid is the source
  for these shell-free interiors; Regenerate now preserves it when no shell
  remains. Resampling is needed to change their floor count. Do not move them
  then regenerate using the original world-space bbox attributes.

  GenerateAll now supports nested grouping folders, RequestedFloors per-model,
  SkipGeneration, dry-run argument #3, per-building failure isolation, yields,
  and a returned status report. Existing interiors remain skipped.

  Research references (above-ground floors; match identity before applying):
    Scramble Square east: 47, about 230 m
      https://www.shibuya-scramble-square.com/en/index.html
    Hikarie: floors through 34
      https://www.hikarie.jp/floorguide/
    Mark City east / Excel Hotel: 25
      https://www.tokyuhotels.co.jp/en/shibuya-e/facility/index.html

================================================================================
  JJK Roblox Game — Developer Handoff Document
  Last updated: June 2026 (building interior generation system plan added)
================================================================================

  PROJECT GOAL
  A Jujutsu Kaisen-themed Roblox combat game focused on making players feel
  powerful, fast, and intense — true to the anime's speed and scale. The core
  philosophy is to fake physics at mach-equivalent speeds using deterministic
  math + teleportation, then dress the result with VFX so it looks real. This
  avoids Roblox's engine breaking at extreme velocities (tunneling, network
  ownership bugs, ragdoll explosions).

  The game is set in a 1:1 recreation of central Shibuya, Tokyo. Buildings must
  feel like real structures — not hollow boxes — so that when characters punch
  through them, the destruction reads as visceral and weighty. Every building
  needs a destructible interior with floors, pillars, office furniture, and a
  hollow core, all built from primitive Parts so CSG SubtractAsync works
  reliably at runtime.

--------------------------------------------------------------------------------
  CURRENT STATE: DESTRUCTION SANDBOX + MAP BUILD
--------------------------------------------------------------------------------
  The demo isolates and tests the destruction + hit system. A player clicks an
  NPC dummy, which gets punched through one or two buildings along the camera's
  look direction, carving a ground trench with debris as it slides.

  The map is being actively built. A 1:1 FBX import of central Shibuya provides
  the visual reference (16 MeshParts covering the city blocks). The owner is
  manually constructing building exteriors (glass walls, rooftop accessories)
  on top of procedurally generated interiors.

  WHAT IS WORKING:
    - Kinematic endpoint calculation (strength / drag = travel distance)
    - STRENGTH is currently 2000 → ~200 stud travel at DRAG 10
    - Floor Y clamp with horizontal redirect when trajectory goes underground
    - CSG subtraction (SubtractAsync) carving a cylindrical hole through
      building walls (filter: parent model name starts with "Building")
    - R15 dummy rig cloned from ServerStorage, tagged "HitTarget"
    - Dummy teleports to computed endpoint via PivotTo (while anchored)
    - Dummy faces the attacker on teleport: CFrame.lookAt(endPos, endPos - direction)
    - Humanoid Physics blocker (FIXED — was the #1 blocker):
        PlatformStand = true during ragdoll/brace
        SetStateEnabled(false) on Running, RunningNoPhysics, Landed
        Re-enabled in recoverDummy() before GettingUp
    - Hit generation counter cancels stale ground-tracking loops on re-hit
    - Full-rig anchor → Physics state → PivotTo → unanchor → velocity apply
    - Per-part AssemblyLinearVelocity + AssemblyAngularVelocity after 0.05s wait
    - RESIDUAL_VELOCITY derived from STRENGTH / DRAG (currently 200 studs/sec)
    - Client-side dust clouds via DustEvent RemoteEvent (server fires,
      ClickInput.client renders locally)
    - Dust at hit origin, at each building surface intersection, and during
      ground slide (every GROUND_DUST_COOLDOWN)
    - Timing logs: per-CSG-op ms in Output, total handler ms
    - AlignOrientation brace recovery (SlideSled system REMOVED):
        After BRACE_DELAY of ground contact, braceDummy() plays custom animation
        and applies AlignOrientation to keep dummy upright while sliding
        Brace animation: rbxassetid://76152813518702, loops seconds 5–8 via
        TimePosition reset in trackGroundContacts
        recoverDummy() when speed drops below STAND_SPEED
    - Re-hit cleanup: old AlignOrientation, attachment, and brace animation
      track are destroyed when a new hit arrives
    - Continuous ground trench carving on Terrain via FillBlock (fast)
    - Continuous trench segments drawn between lastCraterPos and current ground
      raycast hit every GROUND_DUST_COOLDOWN (0.3s)
    - Airborne detection: lastCraterPos reset when dummy >4 studs above ground
      (prevents trench through air on bounce)
    - Shallow rectangular trench: 4 wide × 3 deep studs, offset 1 stud below surface
    - CSG SubtractAsync for non-terrain ground parts (building floors, etc.)
    - DEBRIS SYSTEM (COMPLETE — see DEBRIS SYSTEM section below):
        Spawn along trench during slide; cleanup + union after slide ends
        80% wedges, 20% flat block variants; DEBRIS_SIZE_SCALE = 0.8
        Enum.Material.Concrete + terrain MaterialColors sampled per segment (pre-carve)
        Color stored on attributes; re-applied after Parent, cleanup, and UnionAsync
        Trail-relative cleanup drops only isolated high floaters; dense piles kept
    - Rojo preserves Studio Terrain/custom map via $ignoreUnknownInstances on Workspace
    - CharacterWalkSpeed = 128 (4× default) in default.project.json
    - Shibuya FBX reference model imported (16 MeshParts, city-block scale)
    - Test buildings (TestBuilding, Thin Skyscraper 7) at Y≈2000-2400 for CSG testing
    - Raised terrain plateau in center area (Y≈100-350, Plastic material)
    - Flat ground terrain at Y≈34 (Concrete material) around the perimeter

  WHAT IS BROKEN / NEEDS FIXING:
    - Client dust VFX in ClickInput.luau is still the older smaller preset;
      server-side spawnDustCloud in HitHandler exists but is unused (dust must
      stay client-rendered). Buffing dust requires updating ClickInput, not server.
    - CSG SubtractAsync fails on MeshParts (complex mesh geometry exceeds engine
      limits). This is why building interiors MUST be built from primitive Parts —
      only Parts and Unions (PartOperations) are reliable for CSG destruction.
      The Shibuya FBX MeshParts are visual reference only; they cannot be carved.

  WHAT IS NOT DONE YET (planned next):
    - Building interior generation system (see BUILDING INTERIOR GENERATION section)
    - Jagged/irregular tunnel shape (currently a clean cylinder; premade mesh
      upgrade planned)
    - True ragdoll (BallSocketConstraints replacing Motor6Ds; currently uses
      PlatformStand + Physics state, not joint constraints)
    - Camera shake on impact
    - Sound design
    - Scorch decals + edge debris at hole rim
    - Real player-vs-player combat (attacker character, hit detection,
      input system)
    - Strength → hole radius scaling (currently hardcoded)
    - Custom building exteriors in Studio (glass walls, rooftop accessories)
    - Road system (Roads folder exists but is empty)

--------------------------------------------------------------------------------
  SHIBUYA MAP REFERENCE
--------------------------------------------------------------------------------
  The Workspace contains a 1:1 FBX import of central Shibuya as 16 MeshParts
  inside the "Shibuya" model. These MeshParts are city-block scale (each
  1000-2000 studs across) and contain multiple buildings merged into a single
  mesh per block. They serve as a visual and spatial reference for placing
  hand-built destructible buildings on top.

  IMPORTANT: These MeshParts CANNOT be used for CSG destruction. SubtractAsync
  fails on complex MeshParts due to triangle count and collision fidelity limits.
  The HitHandler already warns about this at runtime. All destructible building
  structure must be built from primitive Parts (or Unions of Parts).

  MAP LAYOUT:
    - Ground terrain: Y≈34, Concrete material (flat perimeter)
    - Raised terrain: Y≈100-350, Plastic material (center Shibuya district)
    - Shibuya MeshParts: Y≈0-1000, sitting on/above the raised terrain
    - Test buildings (TestBuilding, Thin Skyscraper 7): Y≈2000-2400
      (separate test area for CSG development, not part of final map)
    - SpawnLocation: Y≈1340 (between test area and Shibuya area)
    - Roads folder: empty (reserved for road system)

  SHELL APPROXIMATION FROM FBX:
  The owner will manually create building "shells" — simple Part enclosures
  that define each building's interior volume (width × depth × height). These
  shells are the input for the interior generation script. The script reads
  each shell's bounding dimensions, generates floors and interior structure,
  then deletes the shell.

  Semi-automated shell creation (possible future workflow):
    - Raycast downward from above each Shibuya MeshPart to find roof surfaces
    - Use the MeshPart's bounding box as a rough XZ footprint
    - Manually adjust each shell's dimensions to match the visible building
      outline in the FBX reference
    - This gives a reasonable starting point but will always need manual
      correction because the MeshParts merge multiple buildings together
      and their bounding boxes don't represent individual building footprints

  BOTTOM LINE: Shell creation is manual. The FBX reference shows where buildings
  go and roughly how tall/wide they are, but each shell must be placed and
  sized by hand to match the reference. The generation script handles
  everything INSIDE the shell automatically.

--------------------------------------------------------------------------------
  BUILDING INTERIOR GENERATION SYSTEM  (IMPLEMENTED — June 2026)
--------------------------------------------------------------------------------
  IMPLEMENTED as src/server/BuildingGenerator.luau (edit-time tool, run from
  the Studio command bar):
    require(game.ServerScriptService.Server.BuildingGenerator).GenerateAll()
    -- optional floor count (exact): .GenerateAll(nil, 47) or .Generate(model, 47)

  Implementation notes (supersede the planning spec below where they differ):
    - Input: Models inside Workspace.Buildings (named "Building*"). The WHOLE
      model space is used, not individual parts: the generator SAMPLES the
      model's solid volume floor-by-floor with WorldRoot:GetPartsInPart (true
      collision geometry), so the shell can be any mix of SOLID primitives —
      blocks, wedges, cylinders, unions, rotated parts — and the interior
      follows the real silhouette (wedges taper floor by floor, cylinders
      read round, height steps drop away). Curves/diagonals are approximated
      to the sample grid (GRID_MIN / MAX_CELLS_AXIS) so they come out lightly
      stepped. NOTE: the shell must be SOLID (a filled mass); a hollow box of
      6 thin wall parts has no volume to sample and generates nothing (warns).
    - ORIENTED FRAME: generation does NOT use Model:GetBoundingBox() (that returns
      the loose WORLD-AXIS AABB when the model has no PrimaryPart). Instead
      computeOrientedBox() boxes the shell in the largest part's YAW frame, so a
      shell Part rotated about Y (even by a small unintended amount) still gets
      an interior whose walls/slabs line up with its real faces. Without this a
      rotated prism shows a protrusion that grows steadily along the face (the
      axis-aligned interior cutting diagonally across the angled wall). The shell
      itself is left untouched — buildings may sit at any Y rotation.
    - TAPER HANDLING (two occupancy layers): each cell is probed at TWO heights
      per floor — just above the floor (LOOSE) and just below the ceiling. A
      cell is TIGHT only if solid at both. Flat things (slabs, carpet, core
      placement) use LOOSE; full-height things (office walls, furniture, ceiling
      lights, core column coverage) use TIGHT, so nothing pokes out higher up a
      face that leans inward (e.g. Shibuya Sky's sloped massing). The slab
      ceiling-cap also uses the lower floor's TIGHT footprint so cap ledges
      don't overhang the taper.
    - Per floor the occupancy grid is rectangle-decomposed (greedy maximal
      rectangles) into a small number of slab/carpet parts. Slab at a floor
      line covers floor k (loose) UNION the floor below (tight), so height steps
      automatically get a ceiling cap where the footprint shrinks.
    - SHELL IS RETAINED: KEEP_SHELL = true (default) leaves the original shell
      part(s) completely UNTOUCHED after generating — so you can undo / move
      parts / re-run the script without rebuilding the shell, and .Regenerate
      re-samples the still-present shell. Set KEEP_SHELL = false to carve the
      model down to just its interior (old behaviour). NOTE: a retained solid
      shell occludes the interior and is itself a CSG target on hits — hide it
      or set KEEP_SHELL = false for a clean playtest.
    - Idempotent: skips buildings that already have an "Interior" Model child.
      Delete the Interior (or call .Regenerate(model[, floors])) to redo. The
      sampled grid is stored as the InteriorGrid attribute, so regeneration
      rebuilds WITHOUT re-sampling, even after the shell is gone. Regenerate
      BEFORE moving a generated building (stored grid is world-space).
    - Units: the storey grid is authored as "metres / 0.28" — clear 3.5 m =
      12.5 studs, slab 1.5 m = 5.36 studs. Treat those as STUD constants that
      were tuned by eye, not as a scale conversion: the imported Shibuya
      geometry is really 4.182937 studs/m (0.2391 m per stud), measured against
      the original PLATEAU tiles (tools/tile_georef.py) and confirmed to four
      decimals by sweep/alignment.json. So a "5 m" storey is actually 4.27 m.
      That is fine for looks and MUST NOT be changed (it would rebuild every
      building), but anything georeferenced — roads, OSM, real coordinates —
      has to use 4.182937, never 1/0.28. Pinning fits to 0.28 was a 17% error
      and the root cause of every failed road alignment.
      FLOOR COUNT: pass an exact floor count (e.g. .Generate(model, 47)) and it
      makes exactly that many uniform floors — the SLAB stays fixed and the
      floor-to-ceiling height is what gives (shrinks, down to MIN_FLOOR_CLEAR
      = 2 m, then it drops floors and warns). With no count it is height-driven
      at the preset clear, ground floor absorbing excess height.
    - Core: EVERY building gets one (collapse-script anchor). Placed in the
      largest solid rectangle of the ground floor, spanning every floor whose
      footprint still covers it. ~40% of that rectangle (CORE_RATIO), but SMALL
      buildings — both shell axes under SMALL_BUILDING_MAX (150 studs) — use
      SMALL_CORE_RATIO (~70%) for a much bigger core. Office ring depth clamped
      to MAX_RING_DEPTH (10 m). Office walls/furniture MARCH the grid
      outward from the core, so they stop at the silhouette (short on a
      wedge's sloped side, etc.). Core wall parts carry the CollectionService
      tag "BuildingCore"; the building gets CoreCFrame / CoreSize attributes.
    - CoreDeco (ServerStorage.CoreDeco: CoreDoor, ElevatorDoor, ExitSignDoor,
      InteriorGlass): fixed set per floor — EXACTLY two ElevatorDoors side by
      side (rolled ELEVATOR_ROLL = 180 — they import upside down), centred on the
      long core wall; ExitSignDoor opposite (placed with roll EXIT_SIGN_ROLL = +90
      to stand upright); CoreDoors on the others; InteriorGlass fills the
      non-elevator walls. NON-OVERLAP: every placed deco records its along-span
      (+DECO_GAP) per wall side; later deco skip if they'd overlap (placeOnWall
      returns false), and office dividing walls skip any along-offset that hits a
      reserved span — so deco never intersect each other OR a wall. The bay in
      front of the elevators is also RESERVED: no dividing wall splits the doors
      and it's kept open as a small lobby (maybe
      one plant). Models measured at runtime via GetBoundingBox.
    - Furniture (ServerStorage.Furniture: ConferenceTable, GroupOffice,
      LowPolyPlant, OfficePrinter, Trashcan): placed in bays between thin
      dividing walls STUCK TO THE CORE (inner end flush with the core face, no
      gap). Wall/bay depth is pulled back one sample cell so nothing pokes out
      past a sloped/curved silhouette. Per-bay fill mix: BAY_EMPTY_CHANCE empty,
      BAY_PROP_CHANCE a single prop, the rest a 50/50 GroupOffice vs
      ConferenceTable. FIT TEST uses the piece's ACTUAL bbox-axis footprint at
      yaw 0 and yaw 90 (computed via footprintAABB) — NOT a raw size.X-vs-bayW
      compare, because lookAt(-faceNormal) maps the template's X axis to bbox X on
      an X-normal wall but to bbox Z on a Z-normal wall, so the naive compare was
      wrong on half the walls (the "offices never spawn" bug). Whichever yaw fits
      is used, so a long table can lie along the bay's DEEP axis. A bay's WIDTH =
      its core-wall segment length, DEPTH = the ring depth. SMALL buildings
      (smallBuilding flag) SKIP the empty/prop rolls AND may shrink an office down
      to MIN_FURNITURE_SCALE (placeClone supports a scale arg, Model:ScaleTo) to
      make it fit a tight bay. LIVE-SIZED SPACING: every generation measures the
      ConferenceTable/GroupOffice footprints and derives slotSpacing (bay width
      along the core wall) and maxRingDepth (bay depth, and the core-sizing term)
      from them — so resizing the office models in ServerStorage automatically
      widens the bays / ring / core to fit them at FULL size, instead of the old
      fixed PROTRUDE_SLOT/MAX_RING_DEPTH silently scaling the bigger model back
      down. OFFICE_TARGET_LONG (studs, optional): set it to force both offices to
      an exact longest-edge size at generation (uniform scale, proportions kept),
      so you control real size in studs instead of guessing Model:ScaleTo factors;
      bays/ring/core follow. placeClone's scale arg is RELATIVE (multiplies the
      model's current GetScale), so it composes with whatever the template was
      scaled to in Studio. The summary print reports the measured footprints, the
      target, and the derived slot/ringMax. Capped per floor
      (MAX_FURNITURE_PER_FLOOR). Per-model roll for tipped imports lives in
      FURNITURE_ROLL (Trashcan = -90; the exit sign uses EXIT_SIGN_ROLL = +90 —
      they do NOT share a convention). placeClone lifts a clone by its ROTATED
      bbox height, so a rolled piece still rests its bottom on the floor.
    - PERF / HITS: furniture, deco, carpet, lights AND the thin OfficeWall
      partitions are tagged "NoCSG"; HitHandler DELETES tagged parts (and all
      MeshParts) on hit instead of carving — only structural slabs and the core
      walls get CSG. HitHandler also broad-phase culls its fallback part scan by
      each building's cached InteriorBBox attributes, so hits stay cheap with
      hundreds of buildings. The fallback scan now only considers CanQuery=false
      parts (the only ones GetPartsInPart can miss; all generated parts are
      CanQuery=true and already returned), so it no longer re-walks the thousands
      of parts on a tall tower. (No range-based streaming — it would hitch under
      this game's fast/large movement.)
    - Carpet: thin full-floor part per floor (MaterialService "Carpet" variant
      if present, else Fabric). Ceiling: MaterialService "Ceiling" variant
      applied to slabs (top face hidden under carpet).
    - Lighting: Neon strips + SurfaceLight on a ~10 m grid, Shadows=false. Two
      guards keep a strip inside the walls: (1) gate on occGetTight (cell solid at
      the ceiling) so a genuinely tapered/stepped top drops its edge strips, and
      NOT inside the core; (2) CLAMP each strip's draw position to the box
      (±size/2 − strip half − inset). The clamp is the load-bearing one: the
      occupancy grid overshoots the real box on the far side (nx*cell > sx, plus
      the probe's own width), so a boundary cell centre can sit at/over the wall
      and an unclamped strip hangs out — and a per-corner occupancy test can't
      catch it because at cell ~10 studs the corners fall in the SAME cell. For a
      perfect rectangular prism the box edge IS the wall, so the clamp alone
      guarantees no protrusion. (TIGHT is sampled at 0.95 of the clear height with
      a thin probe right under the ceiling.)
    - Deterministic seed from building position → stable regeneration.
    - DECO_YAW_OFFSET / FURNITURE_YAW_OFFSET configs fix model facing globally
      if assets come in rotated.

  Original planning spec follows (kept for reference):

  A script that takes
  manually placed building "shell" Models and replaces them with fully
  destructible interiors built from primitive Parts.

  INPUT: Building shell Models
    - Each shell is a Model named starting with "Building" (matches the CSG
      filter in HitHandler's isBuildingPart)
    - The shell contains a few Parts that together define the interior volume
      (e.g. a single box Part, or 6 wall/ceiling/floor Parts)
    - The script reads the shell's bounding box to determine:
      width (X), depth (Z), height (Y), and base position
    - After generating the interior, the original shell Parts are deleted

  OUTPUT: Destructible interior structure
    All generated Parts are parented to the building Model so they inherit
    the "Building" name prefix → CSG destruction works automatically.

  FLOOR GENERATION:
    - Average floor height: 4.2 meters (≈15 studs at Roblox scale: 1m ≈ 3.57 studs)
    - Floors generated top-down from the building's total height
    - First floor (ground level) gets the tallest height — absorbs any remainder
      from dividing total height by floor height (e.g. if building is 67.2m tall
      with 4.2m floors, ground floor might be 5.5m while upper floors are 4.2m)
    - Each floor is a horizontal Part (or thin slab) spanning the building's
      full XZ footprint
    - Floor Parts are Anchored, CanCollide = true

  INTERIOR LAYOUT (per floor):
    The interior is divided into two zones:

    1. OFFICE RING (outer 60% of building depth from each edge)
       - A ring of office space running around the perimeter of each floor
       - Contains procedurally generated low-poly office furniture:
         * Cubicle partitions (thin vertical Part walls + desk surface Parts)
         * Pseudohallways (narrow corridors between cubicle clusters)
         * Pillars at structural grid intersections (matching the building's
           structural column grid — typically every 6-8 meters)
       - Furniture is made from Parts (not MeshParts) for CSG compatibility
       - Furniture is Anchored, CanCollide = true (so CSG carves through it)

    2. HOLLOW CORE (inner 40% of building footprint)
       - A square/rectangular void in the center of every floor
       - Extends from the bottom to the top of the building (open atrium)
       - Two perpendicular wall Parts divide the core into 4 equal sections
       - These core walls run the full height of the building
       - The core represents elevator shafts, stairwells, and utility chases

  CROSS-SECTION DIAGRAM (top-down view of one floor):

    ┌─────────────────────────────────────────┐
    │  OFFICE  │  OFFICE  │  OFFICE  │OFFICE │
    │  (ring)  │  (ring)  │  (ring)  │(ring) │
    ├──────────┼────┬─────┼────┬─────┼───────┤
    │  OFFICE  │CORE│CORE │CORE│CORE │OFFICE │
    │  (ring)  │ 1  │  2  │  3  │  4  │(ring) │
    ├──────────┼────┴─────┼────┴─────┼───────┤
    │  OFFICE  │  OFFICE  │  OFFICE  │OFFICE │
    │  (ring)  │  (ring)  │  (ring)  │(ring) │
    └─────────────────────────────────────────┘

    Outer ring = 60% depth from each edge (office + furniture)
    Inner core = 40% of footprint (hollow, divided into 4 sections)

  PILLAR PLACEMENT:
    - Pillars are placed at regular grid intervals along the office ring
    - Grid spacing: ~6-8 meters (configurable)
    - Pillars align across floors (structural continuity)
    - Pillar size: ~0.8m × 0.8m cross-section, full floor-to-ceiling height
    - Made from Parts, Anchored, CanCollide = true

  PROCEDURAL FURNITURE RULES:
    - Cubicle clusters: groups of 2-4 workstations separated by partition walls
    - Partition walls: thin Parts (0.15m thick), ~1.2m tall, ~1.5-2m wide
    - Desk surfaces: flat Parts at ~0.75m height, ~1.2m × 0.6m
    - Pseudohallways: 1.2-1.5m wide clear paths between clusters
    - Random variation in cluster size, orientation, and spacing per floor
    - Same seed per building for consistency; different seed per floor for variety
    - All furniture Parts: Anchored = true, CanCollide = true
    - Material: Concrete or SmoothPlastic (for CSG reliability)

  SHELL DELETION:
    - After all floors, core walls, pillars, and furniture are generated,
      the original shell Parts are removed from the building Model
    - The building Model itself remains (named starting with "Building")
    - The owner then manually adds exterior glass walls, rooftop accessories
      (fans, HVAC units, helipads), and any other cosmetic elements

  CONFIGURATION CONSTANTS (planned, top of BuildingGenerator script):
    FLOOR_HEIGHT          = 15      -- studs (≈4.2 meters)
    OFFICE_RING_RATIO     = 0.6     -- fraction of depth from edge for office ring
    CORE_RATIO            = 0.4     -- fraction of footprint for hollow core
    PILLAR_SPACING        = 24      -- studs between pillars (≈6.7 meters)
    PILLAR_SIZE           = 2.8     -- studs cross-section (≈0.8 meters)
    PARTITION_THICKNESS   = 0.5     -- studs (≈0.15 meters)
    PARTITION_HEIGHT      = 4.3     -- studs (≈1.2 meters)
    DESK_HEIGHT           = 2.7     -- studs (≈0.75 meters)
    HALLWAY_WIDTH         = 5.0     -- studs (≈1.4 meters)
    CUBICLE_CLUSTER_MIN   = 2       -- minimum workstations per cluster
    CUBICLE_CLUSTER_MAX   = 4       -- maximum workstations per cluster
    FLOOR_THICKNESS       = 1.0     -- studs (structural slab)
    CORE_WALL_THICKNESS   = 1.0     -- studs
    INTERIOR_MATERIAL     = Enum.Material.Concrete
    INTERIOR_COLOR        = Color3.fromRGB(200, 200, 200)  -- light grey

  WORKFLOW FOR THE OWNER:
    1. Place a building shell Model in Workspace, name it starting with "Building"
    2. Size the shell Parts to match the FBX reference building's footprint
    3. Run the BuildingGenerator script (Studio command bar or play test)
    4. Script generates floors, core, pillars, furniture inside the shell
    5. Script deletes the shell Parts
    6. Owner manually adds exterior glass, walls, rooftop accessories
    7. Repeat for each building in the Shibuya map

  PERFORMANCE CONSIDERATIONS:
    - Hundreds of buildings × dozens of floors × dozens of furniture Parts each
      = potentially tens of thousands of Parts total
    - All Parts are Anchored (no physics cost when stationary)
    - CanCollide = true on structural elements (floors, pillars, core walls)
    - CanCollide = false on small furniture (reduces collision overhead)
    - Consider streaming: ModelStreamingMode.Persistent for buildings near spawn
    - Furniture could be grouped into per-floor Models for organization
    - UnionAsync on furniture clusters could reduce part count (but CSG on
      Unions is less reliable than on primitive Parts — tradeoff)

  OPEN QUESTIONS (need owner input before implementation):
    1. Should furniture be CanCollide = true or false?
       - True: CSG carves through furniture (more satisfying destruction)
       - False: less collision overhead, but furniture clips through holes
    2. Should the script run at edit-time (command bar) or play-time?
       - Edit-time: generates once, saves to place file, no runtime cost
       - Play-time: generates every session, more flexible but slower startup
    3. What material/color scheme for interiors?
       - Concrete (matches debris system) vs SmoothPlastic (cleaner look)
    4. Should the hollow core have floor openings (elevator shaft gaps)?
       - Yes: more realistic, characters could fall through
       - No: simpler generation, each floor is a complete slab
    5. How much random variation between floors of the same building?
       - High variation: more natural but harder to debug
       - Low variation: more uniform, easier to predict part counts

--------------------------------------------------------------------------------
  ROJO + STUDIO TERRAIN
--------------------------------------------------------------------------------
  default.project.json Workspace section:

    "Workspace": {
      "$properties": { "FilteringEnabled": true },
      "$ignoreUnknownInstances": true
    }

  $ignoreUnknownInstances tells Rojo to leave alone any Workspace children it
  doesn't own — including Terrain, hand-placed buildings, and the Baseplate.
  Rojo only syncs Workspace properties, not children. Build your map in Studio;
  sync scripts via Rojo without losing terrain.

  Walk speed is set in default.project.json under StarterPlayer:
    CharacterWalkSpeed: 128
  Requires respawn/rejoin after sync to take effect.

  TERRAIN ↔ DEBRIS COLOR MATCHING (IMPORTANT)
  Debris uses BasePart Material.Concrete for the pitted part texture. Terrain
  and parts use different default color systems — paint terrain to match parts.

    Debris (code)                    Terrain MaterialColors → Concrete
    ─────────────────────────────────────────────────────────────────
    Material: Enum.Material.Concrete   Paint material: Concrete
    Fallback color: RGB(163,162,165)   Set to: RGB(163, 162, 165)  #A3A2A5
    Hex: #A3A2A5                       (default Part / Medium stone grey)

  Reference defaults (do not mix these up):
    Part fallback in HitHandler        RGB(163, 162, 165)  #A3A2A5  ← use this
    Roblox material-table Concrete     RGB(152, 152, 152)  #989898
    Terrain MaterialColors default     RGB(127, 102, 63)   #7F663F  (brown — wrong)

  In Studio: Workspace → Terrain → MaterialColors → Concrete → 163, 162, 165.
  Debris color is sampled via GetMaterialColor(groundHit.Material) once per
  trench segment BEFORE FillBlock (post-carve raycasts miss and fall back to grey).
  Do NOT use Terrain.MaterialColors[Enum.Material.Concrete] bracket syntax — it
  errors and kills debris spawn. Use GetMaterialColor() only.

--------------------------------------------------------------------------------
  FILE STRUCTURE (ROJO)
--------------------------------------------------------------------------------
  src/
    server/
      init.server.luau       -- requires HitHandler + WorldSetup, calls Init()
      HitHandler.luau        -- hit logic, CSG, teleport, brace, trench, debris
      WorldSetup.luau        -- generates buildings + dummy at game start
    client/
      init.client.luau       -- requires ClickInput, calls Init()
      ClickInput.luau        -- raycast click, fires HitEvent, renders dust
      ProjectFiles.luau      -- this handoff document (not loaded at runtime)
    shared/
      Hello.luau             -- placeholder
  assets/
    R15Dummy.rbxm            -- R15 rig in ServerStorage via default.project.json

  REMOTE EVENTS (auto-created in ReplicatedStorage by HitHandler on first run):
    HitEvent  — client → server:  (targetModel: Model, hitDirection: Vector3)
    DustEvent — server → all clients: (position: Vector3, scale: number)

  NPC RIG: ServerStorage.R15Dummy (standard R15 Humanoid rig; PrimaryPart should
  be HumanoidRootPart)

  BUILDINGS: Workspace models whose name starts with "Building" — CSG filter
  matches via name:match("^Building"). WorldSetup still generates test buildings;
  the BuildingGenerator script (planned) will handle interior generation for
  hand-placed shell Models. Custom Studio buildings work the same way if named
  correctly. The owner manually adds exteriors after generation.

--------------------------------------------------------------------------------
  KEY DESIGN DECISIONS
--------------------------------------------------------------------------------

  HIT + TELEPORT SYSTEM
  When a hit lands, the game does NOT physically move the target at high
  velocity. Instead:
    1. Increment hitGeneration (cancels any stale ground-tracking loop)
    2. Clean up previous brace state (AlignOrientation, animation track)
    3. Anchor all parts (freezes Humanoid, prevents position fighting)
    4. Compute endpoint: distance = STRENGTH / DRAG_COEFFICIENT
    5. Optionally redirect along the floor if trajectory goes below FLOOR_Y
    6. Spawn dust at origin (masks disappearance)
    7. Fire dust at each building intersection along the path
    8. Spawn CSG destruction async in background
    9. task.wait(YIELD_MASK_DELAY) — lets dust thicken while CSG runs
   10. PlatformStand + disable Running/Landed states
   11. ChangeState(Physics) WHILE STILL ANCHORED
   12. PivotTo(endPos) facing attacker — CFrame.lookAt(endPos, endPos - direction)
   13. Unanchor all parts
   14. task.wait(0.05) — physics commit step
   15. Apply velocity + spin to all BaseParts
   16. Spawn trackGroundContacts loop with current hitGeneration

  The dust cloud window (0.04s) hides both the teleport seam and the CSG yield.
  Do NOT remove YIELD_MASK_DELAY — it is load-bearing for the illusion.

  HIT GENERATION (re-hit safety)
  Each hit increments hitGeneration. trackGroundContacts checks it every 0.1s
  iteration and exits immediately if a newer hit started. Prevents stale loops
  from calling recoverDummy mid-flight.

  CSG DESTRUCTION (buildings)
  part:SubtractAsync({cutterClone}) per overlapping building part. Each op runs
  in its own task.spawn. Cutter is a Cylinder Part oriented along trajectory.

  CSG limitation: only parts whose parent model name starts with "Building".
  Update destroyAlongCylinder filter if building naming changes.

  BRACE & RECOVERY (replaces removed SlideSled system)
  trackGroundContacts runs every 0.1s after hit:

  Phase 1 — Ragdoll (pre-brace):
    - Raycast down from HRP, exclude dummy
    - If within 4 studs of ground: dust + createGroundCrater segments, track
      firstGroundContactTime
    - If >4 studs or no hit: reset lastCraterPos (airborne — no trench in air)
    - After BRACE_DELAY (1s) from first ground contact: braceDummy()
    - If speed < VELOCITY_THRESHOLD before brace: recoverDummy + union debris

  Phase 2 — Brace (isBraced):
    - Play brace animation, AlignOrientation keeps dummy upright facing attacker
      (horizontalDir = -velocity, fallback -LookVector)
    - Loop animation TimePosition 5–8 while sliding
    - Continue dust + continuous trench/debris every GROUND_DUST_COOLDOWN
    - When speed < STAND_SPEED: final crater segment, recoverDummy, unionDebris

  recoverDummy():
    - Remove AlignOrientation + attachment
    - Stop brace animation track
    - PlatformStand = false, re-enable Running/Landed states
    - ChangeState(GettingUp)

  CLIENT-SIDE PARTICLES
  ParticleEmitter:Emit() from server does not reliably replicate. All VFX must
  go through DustEvent:FireAllClients() and render in ClickInput.luau.

--------------------------------------------------------------------------------
  GROUND TRENCH + DEBRIS SPAWN (createGroundCrater)
--------------------------------------------------------------------------------
  Called with (startPos, endPos, velocity, groundPart, debrisList).
  Positions flattened to min Y of segment so carving stays on surface.

  Trench carving:
    - FillBlock on Workspace.Terrain (Material.Air)
    - SubtractAsync on non-terrain BaseParts (async, dust masks delay)
    - Block: 4 wide × 3 deep × (segment length + 2) studs
    - CFrame offset 1 stud below surface center

  Debris spawn (per segment between startPos and endPos):
    - Stations every ~3.5 studs along trench (spacing unchanged by size scale)
    - 3–5 pieces per side per station (both sides of trench)
    - Type 6 Wedge: 80% spawn rate (majority)
    - Types 1–5: horizontal prisms (remaining 20%; Y is thin axis ~50–68% of base)
    - Base size ~1.45–2.55 studs × DEBRIS_SIZE_SCALE (0.8) → ~1.16–2.04 effective
    - Material: Enum.Material.Concrete (part pitted texture; always)
    - Color: getDebrisColorFromGround() — one raycast at segment center BEFORE
      FillBlock carve; Terrain.MaterialColors:GetMaterialColor(groundHit.Material)
    - Fallback if sample fails: Color3.fromRGB(163, 162, 165) (#A3A2A5)
    - storeDebrisColor / readDebrisColor attributes preserve tint through cleanup
    - applyDebrisAppearance() sets Material + Color AFTER Parent (UnionAsync resets)
    - Side offset: trenchWidth/2 + 1.5–3.5 studs outward + forward jitter
    - Raycast down from spawn XZ to snap to terrain surface (filtered)
    - World Y-up orientation (not terrain normal — prevents tilt into air)
    - Slight embed: surfaceY + sizeY*0.5 - 0.15
    - Yaw jitter ±18° (blocks ±20°)
    - Anchored = true, CanCollide = false at spawn
    - SpawnGroundY attribute stored on each piece
    - Collected in slideDebris table for later union; otherwise Debris 10s

--------------------------------------------------------------------------------
  DEBRIS SYSTEM — CLEANUP & UNION (COMPLETE)
--------------------------------------------------------------------------------
  After slide ends, unionDebris(slideDebris) waits 3 seconds then runs
  cleanupDebrisBeforeUnion() before UnionAsync.

  BEHAVIOR:
    1. Compute trailGroundY = lowest debris bottom across the whole slide
    2. Keep all pieces whose bottom is within DEBRIS_TRAIL_HEIGHT_DROP (3.5 studs)
       of that floor — including stacked / overlapping piles
    3. Above that height: drop ONLY if the piece does not overlap any other debris
       (isolated floaters sink through ground and are deleted)
    4. No intersection culling — overlapping ground pieces are kept for density
    5. Union result CanCollide = true; fallback Model parts also collidable
    6. applyDebrisAppearance re-applied on union result using readDebrisColor
       from firstPart (saved before UnionAsync destroys source parts)

  APPEARANCE HELPERS (HitHandler.luau):
    DEBRIS_MATERIAL           Enum.Material.Concrete
    DEBRIS_COLOR_FALLBACK     Color3.fromRGB(163, 162, 165)
    getDebrisColorFromGround  Pre-carve terrain sample (GetMaterialColor)
    storeDebrisColor          Attributes DebrisColorR/G/B on each part
    readDebrisColor           Reads attributes; falls back to DEBRIS_COLOR_FALLBACK
    applyDebrisAppearance     Material + Color after Parent

  KEY TUNABLES (HitHandler.luau):
    DEBRIS_SIZE_SCALE         = 0.8   Uniform debris size scale (proportions unchanged)
    DEBRIS_TRAIL_HEIGHT_DROP  = 3.5   Blanket height above trail floor
    DEBRIS_OVERLAP_SHRINK     = 0.75  AABB shrink for pile-support test
    DEBRIS_DROP_SPEED         = 160
    DEBRIS_SETTLE_TIME        = 0.8

  Console log to watch:
    [HitHandler] Debris cleanup: dropped N isolated high | kept M for union

--------------------------------------------------------------------------------
  TUNABLES (top of HitHandler.luau)
  Use the values already in game — do not override from this doc without reason.
    Variable                        Value   Effect
    STRENGTH                        2000    Hit energy magnitude
    DRAG_COEFFICIENT                10      Higher = shorter travel
    HOLE_RADIUS                     5       Cylinder cutter radius (studs)
    RESIDUAL_VELOCITY               200     studs/sec after teleport (= STR/DRAG)
    YIELD_MASK_DELAY                0.04    Dust cover before teleport (seconds)
    DUST_LIFETIME                   10      Server dead-code dust lifetime
    FLOOR_Y                         0       Y level for trajectory redirect
    GROUND_DUST_COOLDOWN            0.3     Seconds between ground dust/trench
    VELOCITY_THRESHOLD              1       Pre-brace stop speed (studs/sec)
    BRACE_DELAY                     1       Seconds ground contact before brace
    STAND_SPEED                     8       Brace end → stand speed (studs/sec)
    DEBRIS_SIZE_SCALE               0.8     Uniform debris size scale
    DEBRIS_MATERIAL                 Concrete  Part material (always)
    DEBRIS_COLOR_FALLBACK           163,162,165  #A3A2A5 if ground sample fails
    DEBRIS_TRAIL_HEIGHT_DROP        3.5     Blanket height above trail floor (studs)
    DEBRIS_OVERLAP_SHRINK           0.75    AABB shrink for pile-support overlap test
    DEBRIS_DROP_SPEED               160     Floater fall speed (studs/sec)
    DEBRIS_SETTLE_TIME              0.8     Max seconds to wait for floaters
    DEBRIS_GROUND_PENETRATION       0.25    Delete floaters this far below ground
    BRACE_ANIM_ID                   rbxassetid://76152813518702

  default.project.json:
    StarterPlayer.CharacterWalkSpeed = 128

--------------------------------------------------------------------------------
  IMMEDIATE NEXT STEPS (suggested priority order)
--------------------------------------------------------------------------------
  1. Building interior generation system — implement BuildingGenerator script
     that takes shell Models and produces destructible interiors. See the
     BUILDING INTERIOR GENERATION section above for full spec. Owner needs to
     answer the OPEN QUESTIONS before implementation begins.

  2. Shell placement workflow — owner places building shells in Studio matching
     the Shibuya FBX reference. Semi-automated shell approximation is possible
     (raycast from above MeshParts, use bounding boxes) but will always need
     manual correction since MeshParts merge multiple buildings.

  3. Sync client dust VFX — if denser/larger dust is desired, update
     spawnDustCloud in ClickInput.luau (not server).

  4. Custom building exteriors — after interiors are generated, owner adds
     glass walls, rooftop accessories (fans, HVAC, helipads) by hand.

  5. Road system — the Roads folder is empty; needs road Part placement.

  6. Jagged cutter mesh — replace cylinder cutter in destroyAlongCylinder with
     premade irregular MeshPart from ServerStorage.

  7. True ragdoll — BallSocketConstraints on hit, restore Motor6Ds on reset.

  8. Camera shake — client-side on DustEvent or dedicated ShakeEvent.

  9. Sound — SoundEvent RemoteEvent, client plays at world position.

  10. Combat system — attacker character, input, hit detection → HitEvent flow.
================================================================================
]]

return nil
