# Ground facade expansion driver

October 17, 2026. This is the explicit expansion stage after whole-bay trapezoidal interiors v2. Read FACADE_BAY_INTERIORS_HANDOFF.md and FACADE_ROAD_FRONTAGE_HANDOFF.md for interior/frontage rules. Requiring GroundFacadeExpansionRollout does nothing to the scene. No runtime startup hook or automatic regeneration is installed.

## Scope and exclusions

The owner authorized reaching the majority of eligible ordinary buildings, approximately 15 stories and below. Fresh selection keeps StructuralOnly, valid canonical or verified legacy plans, exact native floor-count agreement and the 30,000-square-stud footprint limit. Station, landmark, crown and explicit exclusions remain protected. Crossing disk: X/Z (11,572), radius500. 109 district disk: (683,596), radius275; explicit109 ID fbx_5_6952_1857_6146. Existing selector exclusions retain PARCO/Cerulean/station identities; the driver additionally records both PARCO703 and706 aliases conservatively.

The intentionally removed fbx_12_24502_3155_-12717 must NEVER be automatically restored from FacadeDetachedBuildingRecovery_2026_10_17. Its owner reports it was wrongly generated inside another building. Missing live targets are skipped; archived models are not enumerated. Oversized ground-storey runs above24studs are held rather than producing a wall across a malformed building's whole height. Current holds: orph_-134_2379 and fbx_14_2530_1780_-1082 (the latter already has an earlier facade and is not rebuilt by this driver).

Selected fbx_6_16012_2445_-12199 and fbx_11_13048_1764_5668 require later reviewed rectangular-box replacement, floors, roof, core and facades. This driver only records that deferred request; it never rebuilds source structure. Terrain and roads remain untouched.

## Current persistence caveat

The preceding fresh survey found2090eligible/132held,1065resident facade roots and1024safe missing targets, plus one oversized-ground-storey hold. A first200new roots were built locally before Team Create disconnected. Reopening confirmed those200 did NOT persist:1065 roots remained. The whole-bay v2 work DID persist,with4147 recipe tags/all1065 prepared roots. The intentionally removed building remained out.

A second pass used this guarded driver,default10 buildings per Step,and completed at least350 additions locally before another editing-server shutdown. Reopening confirmed1125 resident roots:60 additions survived from that second pass. Local logs say reason288/server shut down;they do not establish an out-of-memory cause.

A third pass used Studio6af0e574-e878-4f0f-bc09-fb86d08427b9 and fresh helper GroundFacadeExpansionRollout_Cooldown_20261017. The fresh survey found2090eligible/132held,1124 already-installed eligible targets,964 missing safe targets and two oversized-ground-storey holds (one already installed). Native total1125 includes that pre-existing oversized hold. Archive: GroundFacadePilotArchive.Expansion_67388b5a-aace-49fe-801a-958e84f8718d. Twenty-six separate synchronous10-building calls committed260 additions LOCALLY with zero errors,leaving704 queued. Every successful call checked connection after geometry and metadata. Step27 lost ClientReplicator during its cooldown and failed its PRE-BUILD guard;no27th batch ran. Final expected local total1385 is NOT a saved/reopened count. Persistence of these260 additions is unknown.

After that disconnect,list_roblox_studios returned only unnamed placeholder aa055548-566b-48e7-a455-e84b1294ccf6;the old6af0 Studio was no longer connected,so a final native census could not run. All mutations stopped. Reopen TestJJK,inspect actual roots and call Prepare fresh rather than reuse _G.FacadeExpansionContext. No further geometry cleanup,interior/surface pass or box repair was performed during the third expansion pass.

Subsequent reopening on aa055548-566b-48e7-a455-e84b1294ccf6 confirmed1225native roots:100 of the third pass's260 additions persisted. Fresh fourth-pass scope was2090eligible/132held,1224already-installed eligible,864missing and the same two height holds. Fresh helper GroundFacadeExpansionRollout_Pass4_20261017 committed only its first10-root batch locally before the next call lost connection during cooldown and stopped before building. Fourth-pass archive Expansion_b487b1ea-3255-4e17-a838-9baafe2fda52;those10 additions are not reopen-confirmed. The next unnamed Studio placeholder was f2457d66-85b5-4e0a-a115-a468b0c3bb94. Logs suggest automatic reconnects;no manual reopening or native computer control was performed by this driver. Source cooldown was increased to30seconds for subsequent fresh helpers as an experimental replication interval,with no claim that this establishes or fixes the shutdown cause.

Automatic review also rejected subsequent repeated requests as allegedly overlapping prior work. Read-only checks established native State=ready/Completed=Expected and a connected ClientReplicator before continuation;the source driver adds its own mutex. No rejected concurrent mutation was forced through. The remaining blocker is the unavailable editing session,not authorization to expand.

## Bounded API

Sync the source and require ONE module instance, then call Prepare:

```lua
local D=require(game.ServerScriptService.Server.GroundFacadeExpansionRollout)
local ctx,scope=D.Prepare()
```

Prepare performs a fresh city survey and filters to MISSING GroundFacadePilot roots only. It preserves existing corrected facades and rooms, checks tag protections and holds oversized ground stories. It writes ExpansionScope/ExpansionProgress through the bounded Registry chunk store to GroundFacadePilotManifest and a new owned Expansion archive folder. The folder does not clone the giant existing registry or other geometry.

Invoke exactly ONE synchronous call per MCP request:

```lua
return D.Step(ctx)
```

Each call currently scans/builds at most10 missing roots (within the25-building maximum). A module-local mutex rejects overlapping Prepare/Step calls and always releases after errors. A minimum30seconds now elapses from the previous completed Step before another build;the wait stays inside the mutex and checks connection before and after. Third/fourth-pass helpers used the former10seconds,so sync a fresh helper to adopt30. Step rechecks live targets and eligibility,uses incremental Upsert,and retains per-building committed journal records. No task.spawn or unattended mutation loop is used. Existing archived station/core/shared-surface backups remain untouched. Replaced live geometry would retain recipes under the normal Pilot contract,although already-installed targets are skipped here.

The driver requires ClientReplicator before/after the work. A disconnected context cannot run again. Reopen TestJJK and call Prepare with a fresh module/context; never trust old _G queues after reconnection. Inspect progress errors before issuing the next Step. A batch with errors keeps its cursor so retries skip successful native roots. New source edits during the run warrant a fresh Prepare/survey. Local ready/complete state is not proof of Roblox cloud persistence or manual Save.

## Required completion work

After expansion, run bounded GroundFacadeSurfaceResolver repairs so newly adjacent source slices do not introduce coplanar flicker. Prepare whole-bay interiors with GroundFacadeBayInteriors.PrepareNextBatch until no unprepared roots remain; each new root naturally lacks the completion marker. Run independent room SAT/overlap audit and bounded conflict resolution, full pane blockers/frontage checks and metadata reconciliation. Review streets and corners through MCP screenshots and Play. Preserve existing glass state3 invisibility/state4 removal behavior and bounded client interior geometry. Only then report final actual installed/eligible/held counts. Saving source to GitHub does not save the map geometry; manual Roblox save and fresh reopen need independent confirmation.
