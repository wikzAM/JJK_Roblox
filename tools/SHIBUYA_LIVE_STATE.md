# Shibuya live state — snapshot, September 20 2026

**Read this before opening Studio.** It is a full census of the live place taken at the end of the
crown work, so a fresh session can plan without spending MCP calls re-deriving it. Numbers here are
measured, not estimated.

> **THE MAP IS UNSAVED.** Everything below is in the open Studio session only. Press **Ctrl+S**.
> If Studio was closed without saving, the applied buildings are gone and the greys come back from
> the archives listed below — re-run the pipeline from *Rebuilding from scratch*.

> **UPDATE Sept 21 (overnight):** the map now covers **86.5%** of the FBX's building footprint
> (was 49.8%): **1,998 source-slice buildings, 352 greys**. 626 buildings the map never had were added
> from roofs (Shibuya PARCO = `orph_703_1736`), 155 had their floors rebuilt, every roof carries a rim
> parapet. Section 1 below is the older Sept 20 census. Full account: handoff, "ROOF ENVELOPE +
> ORPHANS". **Save the place** -- none of this is saved until you press Ctrl+S.

---

## 1. Census

```
workspace parts            219,300
  WedgePart                113,492      Part            96,627
  UnionOperation             7,348      MeshPart         1,020
  Seat                         811      SpawnLocation        1

BuildingSourceSlice          122 models, 22,289 parts, 559 storeys
BuildingSmooth (grey)      3,030 models, 162,232 parts
Building1 (Shibuya Sky)        1 model,  29,907 parts, furnished — DO NOT TOUCH

crown parts                9,485
  CrownParapet                 857   (100 buildings, ~8.6 each)
  ShellWedge                 8,628   ( 22 buildings, ~392 each)

memory (Studio tags)  PhysicsParts 496 MB · Instances 577 · GraphicsParts 208 · SpatialHash 34
                      = 1,315 MB over 219,300 parts ≈ 6.2 KB/part (Studio inflates this)

workspace.StreamingEnabled = FALSE   ← the single biggest open performance decision
workspace.Shibuya           MOVED to ServerStorage.Shibuya (16 MeshParts, intact)
```

## 2. Attributes and tags in use

| on | meaning |
|---|---|
| `CrownParapet` (part) | part of a default parapet crown |
| `ShellWedge` (part) | part of a filled wedge crown on an interesting building |
| `CrownInteresting` (model) | building keeps a detailed crown; value is the reason |
| `CrownSealed`, `CrownBoxed` (model) | leftovers from superseded passes; ignore |
| `NoCSG` (tag) | every crown part — HitHandler deletes rather than carves |
| `SourceSlicePlan` (model) | marks a source-slice building for `Builder.Audit` |

## 3. Sectors applied

| sector | `--near` | applied | greys | archive |
|---|---|---|---|---|
| 1 Cerulean | `387 -894 500` | 24 | 35 | `…_0a6b883f` (35) |
| 2 | `387 -194 450` | 27 | 33 | `…_b81a036d` (33) |
| 3 | `1165 -116 450` | 35 | 46 | `…_e9df643a` (46) |
| 4 | `-313 -894 450` | 33 | 43 | `…_8b701c88` (43) |
| first test | — | 2 | 3 | `…_122c0a0c` (2), `…_af0a689b` (1) |

Full archive names live in `ServerStorage`; prefix is `ShibuyaBeforeSourceSlice_`.

**Dropped on the fidelity gate and NOT shipped** — their greys are untouched and still live:
`fbx_14_-77_855_-813` (77.3% outside), `fbx_14_2621_2300_317` (74.1%),
`fbx_6_705_2489_-10277` (80.8%, offered twice, refused twice).

**Two unapplied stages are parked in ServerStorage from earlier sessions** and are not mine:
`SourceSliceStage_e948c30c…` (55 models) and `…_be08b4e3…` (1). Leave or clean up deliberately.

## 4. The 22 buildings with detailed crowns

`CrownInteresting` is set on each, with the reason as its value.

| sloped ≥ 20% | tall ≥ 50 studs |
|---|---|
| `fbx_6_4125_1771_-11600` 43% | `fbx_6_2510_2462_-12844` 88 |
| `fbx_16_8787_1956_-4372` 29% | `fbx_4_-2192_1412_-10100` 69 |
| `fbx_6_4510_4915_-8852` 27% (Cerulean) | `fbx_6_5706_1800_-12229` 69 |
| `fbx_14_4610_1234_-617` 25% | `fbx_4_-1982_1316_-9445` 66 |
| `fbx_14_5223_1224_-658` 24% | `fbx_16_13294_1839_-3533` 59 |
| `fbx_16_7018_1383_-4192` 24% | `fbx_16_4653_1225_-3292` 58 |
| `fbx_16_7376_1371_-4412` 24% | `fbx_16_9556_1800_-4394` 58 |
| `fbx_4_-4353_1130_-8788` 24% | `fbx_4_-340_1440_-6069` 57 |
| `fbx_11_15140_1502_1489` 21% | `fbx_16_14352_1848_-4149` 54 |
| `fbx_14_1718_1726_-875` 21% | `fbx_5_10677_1681_2148` 52 |
| `fbx_6_7740_1620_-11913` 21% | `fbx_16_5801_1092_-2190` 51 |

**Worth eyeballing before scaling**: `fbx_6_2510_2462_-12844` is 1,272 parts over 234×338 studs and
`fbx_4_-2192_1412_-10100` is 950. Both qualified on height alone. Tightening the rule to
`slopeShare >= 0.25 or bandHeight >= 55` drops the set from 25 to 15 and excludes both.

## 5. Rebuilding from scratch

Run in this order. Every step is offline except the last.

```bash
# 1. plans for a sector (PROTECTED fences Shibuya Sky automatically)
python tools/source_slice_plan_builder.py --near X Z R --min-members 1 --limit 90 \
    --out tools/source_slices/plans_sectorN

# 2. DROP any plan whose id is already a live BuildingSourceSlice — sectors overlap
#    (5, 2 and 3 duplicates came back on sectors 2, 3 and 4)

# 3. fidelity gate; drop anything under IoU 0.95
python tools/source_slice_pokeout.py tools/source_slices/plans_sectorN

# 4. crowns: classify, parapet the dull ones
python tools/source_slice_crown_parapets.py tools/source_slices/plans_sectorN \
    tools/source_slices/parapets_sectorN.json

# 5. crowns: sealed triangles for the interesting ones
python tools/source_slice_crowns_batch.py tools/source_slices/plans_sectorN \
    tools/source_slices/crowns_sectorN.json

# 6. serve to Studio, then apply (see below)
python tools/source_slice_sink.py
```

**In Studio**, per sector: `Builder.StagePlans(plans)` → `Replacement.Capture(stage, sources)` →
`Replacement.Apply(stage)`. Then build crowns: `CrownParapet.Build` for the dull, `TriangleShell.Build`
with `thickness = 10, fillToward = <crown centre of mass>` for the interesting.

## 6. Studio gotchas that cost real time

- **`execute_luau` REPLAYS.** It ran a staging call ~3× and mislabelled a stage, which would have
  replaced the wrong 46 greys. Take a lock folder as the **first** statement, and never identify a
  new stage by searching — `Builder.StagePlans` returns the folder, hold that handle. Assert
  `#children == #plans` and `outputs == #plans` before Apply.
- **`require()` caches for the session.** An edited module never loads. Clone it into a folder and
  require the clone.
- **The edit camera reverts rotation.** `CurrentCamera.CFrame` accepts position but silently
  restores rotation; screenshots then look wrong in ways that read as broken geometry. Set
  `CameraType = Enum.CameraType.Scriptable` first.
- **Memory tags do not reclaim promptly.** Removing 32,000 parts moved them by ~9 MB in-session.
  Trust part counts; re-measure memory in a fresh session.
- **To keep MCP cost down**: `tools/source_slice_sink.py` serves `GET /get/<repo path>` and accepts
  `POST` to write files, so payloads move over HTTP instead of inside calls. Batch every census into
  one `execute_luau` that returns a single formatted string.

## 6b. A whole-map batch is generated and waiting (Sept 20)

Offline only — the Studio plugin never reconnected this session, so **nothing below is live**.

```
tools/source_slices/plans_all_remaining/   1,287 plans, 2,182 greys, 6,497 levels
tools/source_slices/sweep/chunks/          51 chunks of ~25 buildings, what Studio applies
tools/source_slices/sweep/manifest.json    chunk sizes
tools/source_slices/sweep/unmeasured.txt   45 plans the gate could not score; kept, not dropped
tools/SHIBUYA_SWEEP_RUNBOOK.md             the procedure, start there
```

After the gate: **1,254 buildings replacing 2,136 greys**, median mean-IoU **0.997**, 33 dropped
under 0.95. All 51 chunks pass `tools/source_slice_chunk_check.py`. The gate was validated against the 123 shipped plans and reproduces their decisions
exactly — 117/118 measurable pass, and the one failure (0.595) is the plan refused twice.

Regenerate with `python tools/source_slice_sweep.py --workers 12` (10.9 min) then
`python tools/source_slice_finish.py --workers 12`. Apply in Studio with
`SourceSliceSweepApply.Preview / Commit / Run`, one chunk per call, with
`tools/source_slice_sink.py` running.

1,074 greys (35%) produced no plan and stay grey: the FBX has under two storeys of section over
their footprint, or none. 186 of those groups have a tall live grey — one is 362 studs over a
14-stud band — so flooring them would be inventing storeys the scan never recorded. See the handoff.

**Budget if all 51 chunks are applied**: structure ~159,700 + parapets ~9,100 + shell crowns
~77,100, less ~114,900 of removed greys = **about +131,000 parts, taking 219,300 to ~350,000**.
The 201 shell crowns are 31% of everything added on 16% of the buildings; the tighter interesting
rule (`slopeShare >= 0.25 or bandHeight >= 55`) leaves 134 of them and saves ~24,300 parts.

## 6c. MCP: the plugin takes the first FREE server on 58741-58745

`discoverPort()` in `MCPPlugin.rbxmx` probes 58741..58745 and picks the first reporting
`mcpServerActive` with `pluginConnected:false`. Community servers launched with `--port 58741` do
not exit when it is taken — they fall back silently — so a server left behind by an earlier session
owns 58741 and the plugin attaches to a server no live session is using. Four had accumulated.

Kill every stale node server so only the live session's remains; if that one is not on 58741 and
Studio cannot be restarted (unsaved map), proxy 58741 to it, **listening on IPv6 as well as IPv4** —
Windows resolves `localhost` to `::1` first, so an IPv4-only proxy is invisible to the plugin while
`curl` finds it. Even then the plugin attached once and dropped, and never came back.

## 7. Open items

1. **Save the map.** Nothing below matters until Ctrl+S.
2. **`StreamingEnabled = false`.** This decides console viability more than any geometry work.
   Measured resident sets: r500 = 10,799 parts, r1000 = 27,281. Needs a playtest — CSG is
   server-side so the hit system should be compatible, but that is reasoning, not a test.
3. ~~**`Builder.Audit` fails on any building with a crown**~~ — **FIXED Sept 20, not yet run live.**
   It asserted every BasePart belongs to a declared floor, and crown parts are parented to the
   building beside `Interior`. It now audits them against the crown contract instead: a part outside
   the floors must carry `CrownParapet` or `ShellWedge` **and** be tagged `NoCSG`, which also makes
   the audit check the HitHandler contract it never did before. Reported as `crownParts`.
4. **Procedural rooftop clutter** — the owner's call, and the right one: the scan never recorded
   AC units, so generate them rather than try to recover them.
5. **~2,900 greys remain** — a batch for 2,136 of them is generated and gated, see 6b. Apply it
   chunk by chunk; the 848 that produce no plan stay grey deliberately.
6. **Nothing is committed to git.** 50+ changed or new paths.

## 8. Why the crown pipeline looks the way it does

Four attempts at reconstructing rooftop detail from the scan failed, each differently: wedge shells
fanned at corners; slice-and-intersect wiped roof clutter; slice-and-merge left floating slabs;
per-object prisms terraced. **The cause is the data.** The median crown component retains only
**0.38** of a closed box's surface area — the scan saw a roof's top and one or two sides and nothing
else. There was never a solid in there to fit, and each algorithm invented the missing half
differently.

The FBX itself is clean: the Cerulean crown is 89 triangles over 100 distinct vertices with **zero**
slivers and a 533 sq stud median face. Do not go looking for a mesh problem to fix.

See `SHIBUYA_SOURCE_SLICE_HANDOFF.md` for the full record of what was measured and rejected.
