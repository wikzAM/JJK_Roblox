# Shibuya whole-map sweep — runbook

**What this is.** The four hand-driven sectors converted 160 greys into 122 buildings. This is the
same pipeline aimed at everything that is left, in one offline pass, cut into chunks that Studio
applies one call at a time.

Read `SHIBUYA_LIVE_STATE.md` for the live census and `SHIBUYA_SOURCE_SLICE_HANDOFF.md` for why the
pipeline looks the way it does. This file is only the procedure.

---

## 0. Before anything

- **Save the map** (Ctrl+S). Everything the sector work applied is still unsaved.
- Studio must be in **Edit**, not a playtest.
- `python tools/source_slice_sink.py` must be running — the applier pulls each chunk over HTTP
  because a chunk with its crowns is megabytes and will not fit in an `execute_luau` call.

### The MCP plugin dials a hardcoded port, and stale servers steal it

`MCPPlugin.rbxmx` probes `localhost:58741..58745` and takes the first server reporting
`mcpServerActive` with `pluginConnected:false`. Community servers launched with `--port 58741` do
**not** exit when the port is taken — they silently fall back to 58742, 58743, … So a server left
running by an earlier session holds 58741 and the plugin attaches to a server no live session is
talking to.

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -ge 58740 -and $_.LocalPort -le 58750 }
Get-CimInstance Win32_Process -Filter "Name='node.exe'"   # map PIDs to servers
taskkill /PID <stale pid> /T /F                            # kill every server but this session's
```

`curl -s http://localhost:58741/status` tells you which server answers and whether a plugin is on
it. If this session's server is not on 58741 and Studio cannot be restarted (unsaved map), proxy the
port instead of restarting anything — run `python tools/mcp_port_proxy.py 58741 <live port>`; listen on
**both** IPv4 and IPv6, because Windows resolves `localhost` to `::1` first and an IPv4-only proxy is
invisible to the plugin while `curl` finds it fine.

---

## 1. Offline: generate everything

```bash
python tools/source_slice_sweep.py --workers 12      # plans, tile by tile, in parallel
python tools/source_slice_finish.py --workers 12     # gate, classify, crowns, chunks
```

`sweep` partitions the map into 600-stud tiles and runs `source_slice_plan_builder.py --box` on each.
Boxes **tile**; `--near` circles overlap, which is why the sector runs kept re-offering buildings
that were already live. Both steps are resumable: a tile with a `.done` marker is skipped, and each
`finish` step skips itself if its output exists (`--force` to redo).

`finish` writes:

| file | what |
|---|---|
| `sweep/gate.json` | `source_slice_pokeout.py` per plan: mean IoU vs the FBX section |
| `sweep/parapets.json` | every crown classified; dull ones carry their parapet outline |
| `sweep/crowns.json` | sealed crown triangles, **only** for the interesting ones |
| `sweep/chunks/chunk_NN.json` | a neighbourhood of ~25 buildings plus its crown data |
| `sweep/manifest.json` | chunk sizes, for planning the Studio session |

### The gate is mean IoU, and only mean IoU

`pokeout`'s `outside` column is the **worst single level's** spill, not the building's. The applied
Cerulean Tower scores **97.8% outside** on it while its mean IoU is 0.977. Gating on spill would
refuse buildings the map owner approved by eye. `source_slice_chunks.py --gate 0.95` is the gate the
sector runs actually used; `--spill` exists but defaults to off. Do not turn it on without
re-deriving it against a known-good control first.

---

## 2. In Studio: apply a chunk

`SourceSliceSweepApply` is the sector procedure with the two rules from the near-miss built in: the
**lock folder is the first statement** (so an `execute_luau` replay returns the first run's summary
instead of building a second stage), and the **stage is never found by searching** (`StagePlans`
returns the folder and that handle is held; counts are asserted before anything is bound or moved).

```lua
local Sweep = require(game.ServerScriptService.Server.SourceSliceSweepApply)

Sweep.Preview("chunk_01")   -- stages, binds, shows it. Nothing is replaced.
-- look at it
Sweep.Commit("chunk_01")    -- restores the preview, applies, then crowns
-- or
Sweep.Discard("chunk_01")   -- restore, destroy the stage, drop the lock

Sweep.Run("chunk_02")       -- preview-free: stage, bind, apply, crown in one call
Sweep.Status()              -- every lock and its summary
```

**Preview the first few chunks by eye.** After that `Run` is the cheap path. Each chunk archives the
greys it replaces to `ServerStorage.ShibuyaBeforeSourceSlice_<guid>`, so a chunk is individually
reversible; nothing is deleted.

`require()` caches for the Studio session, so an edited module never reloads — clone it into a folder
and require the clone, or restart Studio (**not** while the map is unsaved).

---

## 2b. What is in the batch (measured, September 20)

| | |
|---|---|
| plans generated | **1,287** over 1,834 grey groups |
| passed the gate (mean IoU >= 0.95) | **1,254**, replacing **2,136 greys** |
| dropped under 0.95 | 33 |
| kept but UNMEASURED | 46 — listed in `sweep/unmeasured.txt` |
| chunks | **51**, largest 216 KB |
| median mean-IoU vs the FBX | **0.997** (1,208 of 1,241 measurable at or above 0.95) |
| levels | 6,312 |

**Unmeasured is not bad.** The gate cannot score a plan whose levels all sit where the FBX has
holes. Of the 123 plans the sector runs produced, 5 were unmeasured and **all 5 were shipped**, so
the sweep keeps them and names them rather than refusing 46 buildings the hand runs would have
applied. Preview a chunk that contains one.

**The gate reproduces the sector decisions exactly.** Re-run over the 123 shipped plans: 117 of 118
measurable at or above 0.95, and the single plan below it (IoU 0.595) is `fbx_6_705_2489_-10277` —
the one that was offered twice and refused twice.

**Every chunk passed `tools/source_slice_chunk_check.py`**: levels ascend, pieces inside a level do
not overlap, every core lies inside every level, no grey is claimed twice across 51 chunks, and
every claimed grey is live and unreplaced.

### Part budget — read before applying all 51 chunks

| | parts |
|---|---|
| structure, 6,312 levels at 25.3 per storey | ~159,700 |
| 1,053 parapets at ~8.6 | ~9,100 |
| **201 filled shell crowns, 38,552 triangles x2 wedges** | **~77,100** |
| greys removed, 2,136 at ~53.8 | −114,900 |
| **net on today's 219,300** | **~+131,000 → ~350,000** |

The shell crowns are **31% of everything the sweep adds**, on 16% of the buildings. Tightening the
interesting rule to `slopeShare >= 0.25 or bandHeight >= 55` — the alternative already measured in
the live-state notes — leaves 134 shells and saves ~24,300 parts. Change those two constants in
`source_slice_crown_parapets.py`, re-run it and `source_slice_chunks.py`; nothing else changes.
Chunks are individually reversible, so this can also be decided after looking at a few.

## 3. What to watch while it runs

- **Part count.** A source-slice building is ~183 parts; a grey is ~54. Converting a chunk of 25
  buildings over ~40 greys is roughly **+2,400 parts**. Check `workspace:GetDescendants()` counts
  every few chunks rather than at the end.
- **`Builder.Audit` fails on any building with a crown** — it asserts every BasePart belongs to a
  declared floor and `CrownParapet` / `ShellWedge` parts do not. Audit before crowning, or teach it
  the two attributes.
- **Crown failures are per building, not per chunk.** The summary reports them; a bare roof is not a
  reason to roll a chunk back.

## 4. The decision this sweep forces

`workspace.StreamingEnabled` is **false**. Measured resident sets around one point: r500 = 10,799
parts, r1000 = 27,281. The whole converted map is not a thing a client should hold at once. Nothing
in the sweep changes that, and it is the call that decides console viability — it needs a playtest,
not more geometry.
