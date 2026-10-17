# Shared facade surfaces and clearer inlet glass

October 17, 2026. Applied in TestJJK through Studio MCP. No computer control, source structure edits or additional city rollout.

## Cause and correction

The reported jagged wall was two different source slices generating nearly coplanar walls at different elevations. Example: BuildingSourceSlice_fbx_4_-527_1223_-7154 piece2 and BuildingSourceSlice_fbx_4_-692_1435_-6828 piece1. Their matching boundaries differ vertically by1.4studs. Increasing the outward offset would only conceal one duplicate.

GroundFacadeSurfaceResolver assigns deterministic ownership to overlapping same-facing boundaries, prioritizing existing entrances, then glazing, then lower elevation and stable identity. It trims the lower-priority generated parts to the uncovered rectangular regions. It preserves the source floors, cores and building models. It handles aligned native boxes; unsupported partial cuts fail before changing that run. Opposite-facing surfaces and unrelated/merely adjacent boundaries are excluded.

Applied285 shared boundary pairs across91 buildings, trimming275 lower-priority runs.3542 original generated parts remain intact in ServerStorage.FacadeSharedSurfaceBackup_656f3476-2f2f-4bf9-953b-09ebebe771be.2825 replacement fragments retain the uncovered regions. Backup holders include OriginalParent and Replacement references. Do not delete this exact rollback archive as part of the earlier101-copy cleanup.

The original screenshot area was reviewed through MCP before and after: the serrated color flicker is gone. Full-city pane checks still cover17029 panes/153261 visibility rays, with zero blocked bays and unresolved identities. The stored surface masks contain zero remaining generated parts.11121 original source parts compared exactly unchanged in CFrame/size/color. Replay of a repaired run produced zero additional changes. Rectangle subtraction area conservation passed.

## Interior glass

GlassVisual.SetInteriorView enables65% transparency and at most.02 reflectance only while a real shallow inlet exists. It saves the exterior baseline and restores it when a dynamic client room is removed. It never resets shattered glass to visible. Normal panes without inlets retain their existing tint/backing. Existing44 static panes were updated;13 additional bounded inlets were added on the adjacent BuildingSourceSlice_fbx_4_-938_1632_-6299, including all five bookshop panes facing the photographed street.57 static inlets now exist across seven explicit trial models. This is still a small interior trial.

Native checks found zero intersections between the new bookshop cells. A cloned colliding window passed states2/3/1/4:collision retained for intact/cracked, invisible and noncolliding with all overlays hidden in state3, restored clear-inlet appearance in state1, and deletion in state4. MCP close view BookshopClearGlassInlets shows the tapered depth and existing shelf dressing through the glass. Full Play/performance remains pending.

## Current records and replay

Current1066 installed roots contain289082 owned BaseParts,17029 panes and57 static inlets. tools/reconcile_ground_facade_records.luau refreshed the root recipes/reports and all1066 committed journal entries with actual geometry counts. Earlier v10 audit totals and1063-journal descriptions are historical. Read GroundFacadeRegistry.ReadLatest for coherent current records. Persistent summaries:GroundFacadePilotManifest.SharedSurfaceAuditSummary and SurfaceRepairCurrentTotals.

After rebuilding installed facades, run require(game.ServerScriptService.Server.GroundFacadeSurfaceResolver).ApplyInstalled() in Edit, then the reconciliation tool. ApplyInstalled yields between runs; for a connected city session prefer the same bounded synchronous25-run calls used here rather than an unattended mass mutation. VerifyInstalled checks persisted masks without relying on session globals. Rebuilding from an untrimmed recipe alone can reintroduce the duplicate surfaces; the shared-surface pass is required after replacements. It is not run at game startup.

Restore(backupFolder) returns exact original generated parts and removes their replacement fragments, provided the original parent objects still exist. Reconcile records afterwards. This rollback deliberately restores the old overlap as well. The masks and original geometry are kept separately from source buildings and from the protected station/core backups.

Rojo build and whitespace validation passed. Explicit manual Save to Roblox and persistence of this new correction through another reopen remain unconfirmed. The prior road-frontage changes already survived reopening. Git contains source/replay documentation, not complete live city geometry.
