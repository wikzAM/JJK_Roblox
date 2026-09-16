# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## IMPORTANT: Read ProjectFiles.luau First

Before planning or editing anything in this repo, read `src/client/ProjectFiles.luau`. It is the authoritative developer handoff document: current state, architecture, tunables, known bugs, and next steps. This rule is especially important for tasks touching hit/destruction/VFX/debris/terrain.

## Toolchain & Commands

**Install tools** (requires [Aftman](https://github.com/LPGhatguy/aftman)):
```bash
aftman install
```

**Build the place file** (outputs `JJK_Roblox.rbxlx`, open in Roblox Studio):
```bash
rojo build -o "JJK_Roblox.rbxlx"
```

**Start the Rojo sync server** (live-sync `src/` scripts into an open Studio session):
```bash
rojo serve
```

There are no automated tests. Verification is done by playtesting in Roblox Studio.

## Architecture

This is a Roblox game using [Rojo](https://rojo.space/docs) to sync Luau source files into Studio. The project structure maps to Roblox services via `default.project.json`:

| Source path | Roblox location |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |
| `assets/R15Dummy.rbxm` | `ServerStorage.R15Dummy` |

### Module pattern
Both server and client use a simple `Module.Init()` pattern. Entry points (`init.server.luau`, `init.client.luau`) require sibling modules and call `Init()` on each.

### Key modules

**`src/server/HitHandler.luau`** — Core hit system. When a player clicks the dummy:
1. Server receives `HitEvent` (client → server: `targetModel, hitDirection`)
2. Computes endpoint: `distance = STRENGTH / DRAG_COEFFICIENT` (~200 studs)
3. Fires `DustEvent` to all clients at hit origin and building intersection points
4. Spawns CSG destruction (`destroyAlongCylinder`) asynchronously
5. Waits `YIELD_MASK_DELAY` (0.04s) for dust to mask the teleport
6. Sets Humanoid to `Physics` state while anchored, then `PivotTo(endPos)`
7. Unanchors, waits 0.05s, applies `AssemblyLinearVelocity` + spin to all parts
8. Spawns `trackGroundContacts` loop — handles brace animation, ground trench, debris spawn, and recovery

**`src/server/BuildingGenerator.luau`** — Edit-time tool (NOT required by `init.server.luau`). Run from the Studio command bar: `require(game.ServerScriptService.Server.BuildingGenerator).GenerateAll()`. Pass an optional exact floor count — `.GenerateAll(nil, 47)` or `.Generate(model, 47)` — to force that many uniform floors (the slab stays fixed at 1.5 m and the floor-to-ceiling clear is what gives, down to a 2 m minimum); omit it for height-driven floors at the preset 3.5 m clear. Converts shell Models in `Workspace.Buildings` into destructible interiors (floors, core, deco from `ServerStorage.CoreDeco`, furniture from `ServerStorage.Furniture`). It samples the model's **solid volume floor-by-floor** with `GetPartsInPart` (true collision geometry), so a shell of any solid primitives — blocks, wedges, cylinders, unions, rotated parts — generates an interior that follows the real silhouette (wedges taper, cylinders read round, height steps drop away; curves come out lightly stepped to the sample grid). The shell must be **solid** — a hollow box of thin wall parts samples empty and generates nothing. **`KEEP_SHELL` defaults true**: the original shell part(s) are left untouched (easy undo / move / re-run; `.Regenerate` re-samples the still-present shell). A retained solid shell occludes the interior and is a CSG target on hits — hide it or set `KEEP_SHELL = false` for a clean playtest. Each floor's occupancy is rectangle-decomposed into a few slab/carpet parts. Furniture/deco/carpet/light parts are tagged **`NoCSG`** so HitHandler deletes them on hit instead of carving (only structural slabs/walls/core get CSG). Every building gets a core in the largest solid rectangle of its ground floor — core walls are tagged `BuildingCore` and the model gets `CoreCFrame`/`CoreSize` attributes for future collapse scripts. Idempotent — skips buildings with an `Interior` child; the sampled grid is stored as the `InteriorGrid` attribute so `.Regenerate` rebuilds without re-sampling. See the implementation notes in `ProjectFiles.luau`.

**`src/server/WorldSetup.luau`** — Generates the test scene at startup: two procedural buildings (`Building1`, `Building2`), a `TestBuilding` cloned from `ServerStorage`, and the R15 dummy tagged `"HitTarget"`.

**`src/client/ClickInput.luau`** — Raycasts from camera through mouse. If a `"HitTarget"`-tagged Model is hit, fires `HitEvent` to server. Also listens on `DustEvent` to render dust clouds client-side.

### Remote events (auto-created by HitHandler on first run)
- `HitEvent` — client → server: `(targetModel: Model, hitDirection: Vector3)`
- `DustEvent` — server → all clients: `(position: Vector3, scale: number)`

## Critical Design Constraints

**Teleport-based hit system** — Do NOT physically move targets at high velocity. The system fakes fast movement: anchor → Physics state → `PivotTo` → unanchor → apply velocity. `YIELD_MASK_DELAY` is load-bearing; removing it breaks the illusion.

**CSG only works on primitive Parts and Unions** — `SubtractAsync` fails on MeshParts. All destructible building structure must use `Part` or `PartOperation` (Union). The Shibuya FBX MeshParts are visual reference only and cannot be carved. On hit, `destroyAlongCylinder` **deletes** (does not CSG) any MeshPart or any part tagged `NoCSG` (BuildingGenerator tags furniture/deco/carpet/lights/OfficeWall partitions this way) — only structural slabs and core walls are carved. It also **broad-phase culls** its fallback part scan using each building's cached `InteriorBBoxCFrame`/`InteriorBBoxSize` attributes, so hits stay cheap at hundreds of buildings. These keep hit times low; see `shouldDeleteNotCarve()` and `buildingNearSegment()`. (Deliberately no range-based streaming — it would hitch under fast/large movement.)

**Building naming convention** — `HitHandler.isBuildingPart()` filters by checking if any ancestor Model name matches `^Building`. Any model intended to be destructible must be named with a `Building` prefix.

**Client-side VFX only** — `ParticleEmitter:Emit()` from the server does not reliably replicate. All dust VFX must go through `DustEvent:FireAllClients()` and render in `ClickInput.luau`. The `spawnDustCloud` function in `HitHandler.luau` is dead code (do not use it).

**Hit generation counter** — `hitGeneration` is incremented on every hit and checked in `trackGroundContacts`. Do not remove this check; it cancels stale ground-tracking loops when the dummy is re-hit mid-flight.

**Rojo + Studio terrain** — `$ignoreUnknownInstances: true` on Workspace tells Rojo to leave Terrain, hand-placed buildings, and the Baseplate alone. Build the map in Studio; sync only scripts via Rojo.

## Terrain & Debris Color Matching

Debris uses `Enum.Material.Concrete` with color `RGB(163, 162, 165)` (#A3A2A5). Set Studio terrain `MaterialColors → Concrete` to the same value to match. Use `Terrain.MaterialColors:GetMaterialColor(material)` — bracket syntax (`MaterialColors[Enum.Material.Concrete]`) errors at runtime.

## Key Tunables (top of HitHandler.luau)

| Variable | Value | Effect |
|---|---|---|
| `STRENGTH` | 2000 | Hit energy |
| `DRAG_COEFFICIENT` | 10 | Higher = shorter travel |
| `HOLE_RADIUS` | 15 | CSG cutter radius (studs) |
| `RESIDUAL_VELOCITY` | 200 | studs/sec after teleport |
| `BRACE_DELAY` | 0.75 | Seconds of ground contact before brace |
| `DEBRIS_SIZE_SCALE` | 0.8 | Uniform debris size scale |
