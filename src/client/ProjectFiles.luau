--!nonstrict
--[[
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
    - Units: 1 stud = 0.28 m. Floor-to-ceiling clear = 3.5 m; slab = 1.5 m.
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
