# Whole-bay trapezoidal interiors v2

October17,2026. This supersedes the per-window inlet interpretation in FACADE_INTERIOR_TRIAL.md and the57-cell portion of FACADE_SHARED_SURFACE_HANDOFF.md. The owner means ONE continuous pseudo-interior behind each whole facade/tenant bay, shared by all windows and doors. Only the bay ends taper. Mullions do not create separate rooms.

## Current installed scope

Prepared all1066 existing owned ground-facade buildings. No expansion to buildings without installed facades, upper floors, landmarks, stations or tall buildings.4147 safe shared bay recipes serve16378 panes with65% glass transparency and at most.02 reflectance.197 of4344 glazed bays retain their original flat treatment because native structure or irregular neighboring bay geometry leaves no safe recess.

All57 obsolete per-window cells were removed from the live city. Their513 original parts remain intact in ServerStorage.FacadePerPaneInteriorBackup_v2 with pane references. The earlier7 review buildings have78 whole-bay Edit previews/702 native parts; each shared room has9 parts regardless of how many windows it spans. Bookshop BuildingSourceSlice_fbx_4_-938_1632_-6299 has ONE rear wall and shared recess behind all five panes, verified by MCP street screenshot WholeBaySharedInterior.

Before Play,actual ground geometry was1066 roots/289271 owned BaseParts. Final resident geometry is1065 roots/289209 owned BaseParts,17029 physical panes, zero old per-pane cells,4147 prepared bays and78 Edit previews. Registry records and1066 committed journal entries (including one removal record) were reconciled. Use Registry.ReadLatest; prior raw summaries are historical. Live summary:GroundFacadePilotManifest.BayInteriorV2AuditSummary. No source terrain/floor/core/generator edits were made by the interior preparation.

After Play,BuildingSourceSlice_fbx_12_24502_3155_-12717 was found unparented with all98 parts intact,including62 owned facade parts and no glass. Its disappearance was not caused by an intentional deletion in the interior helpers;the actual cause is unknown. It was not reinserted,as that could undo an intended scene edit. The exact model and prior journal entry are preserved in ServerStorage.FacadeDetachedBuildingRecovery_2026_10_17,with OriginalParent=Workspace.Buildings. Room/pane totals and overlap results are unaffected. Reparent the saved model only if restoring it is desired,then run reconciliation;that tool handles a restored building's prior removal journal entry.

## Geometry and safety

GroundFacadeInteriorGeometry.PlanBay sizes the room from FacadeWidth/FacadeHeight and the bay pivot, aggregating glazing only to locate the front plane. It normally uses45-degree end tapers, up to3studs depth. Adjacent finite facade planes constrain both front and rear endpoints by a shared signed-distance bisector, which also supports acute corners. Opposed wings limit depth. A collapsed rear or insufficient width rejects the room.

GroundFacadeBayInteriors checks the ENTIRE trapezoid using exact native box/wedge volumes against existing colliding structure, including neighboring buildings. It tries depths3,2,1,.6,.4 without moving/carving anything. Accepted peer room recipes are also checked by convex-volume overlap. Initial independent whole-city checking found79 conflicts in irregular/non-manifold building outlines;75 rooms needed a flat fallback and4 conflicts cleared through those same removals. None could be safely repaired by depth reduction. Final independent SAT audit reports ZERO overlapping room volumes across all4147 recipes. Existing garage openings/deep garage geometry are preserved; the glass-room helper does not invent car access through structure.

## Runtime cost and glass

The map stores small recipes on each bay with the FacadeInteriorBay tag. GroundFacadeInteriors builds whole-bay detail CLIENT-SIDE:at most48 active rooms/432 room parts, two construction attempts per.3seconds, enter110/drop135studs. Candidate discovery scans at most64 entries/.75ms per heartbeat. Static Edit previews are reused locally and hidden outside range, so they do not add duplicate client rooms. Fallback flat backings cover distant bays; glass tint remains consistent across distance. Backings hide only when shared 3D detail exists.

This caps added near-detail geometry; original facade geometry and the78 Edit previews remain replicated. It is not complete city geometry streaming or a target-device frame-rate guarantee. Flat backings can still be used where a pseudo-interior cannot safely fit.

Shared recesses are independent of any one window. GlassVisual.RefreshBayInterior keeps the shared shell while at least one pane remains intact/cracked; it hides the shell when the final pane shatters/removes. A state3 base pane stays fully invisible/noncolliding. Resetting a surviving pane restores the common recess. The server/client implementation uses the same rules. GroundFacadeInteriorTrial.Apply is now a compatibility wrapper for whole-bay preparation and cannot rebuild per-window cells.

## Verification and replay

Native disposable tests passed:90-degree and60-degree corners, straight tenant joins and.35stud offset corners;400 positive volume/floor occupancy samples,80 exterior exclusion samples,6 shared-room glass visibility checks, and identical bay-sized plans from multiple panes. Test fixtures clean themselves up. Run tools/verify_bay_interior_geometry.luau after syncing G/V.

tools/verify_bay_interior_city.luau checks every prepared recipe independently using convex polygon separation with vertical intervals. Final result4147 rooms/16378 panes/78 previews/ZERO overlaps. The earlier surface-flicker repair still passes all275 stored masks with zero remaining fragments. No per-window cells remain in live owned facade roots.

Actual Studio Play passed:all4147 bay tags reached the client without streaming; at the bookshop camera, all13 eligible nearby bays produced13 shared rooms/117 visible parts (7 dynamically built,6 reused previews). Moving the camera far away left ZERO visible rooms and ZERO dynamic rooms. No related client errors were logged. This is a functional Play check, not a broad performance benchmark.

To prepare after facade replacement, sync modules, then call require(game.ServerScriptService.Server.GroundFacadeBayInteriors).PrepareNextBatch() repeatedly in Edit. Each call handles at most25 unfinished installed buildings, with a completion marker on the specific facade root, so it can resume after reconnect. The helper skips already prepared bays. Run the city overlap audit after a batch series; if unusual outlines produce conflicts, use ConflictContext and ResolveConflictBatch in bounded groups, then re-audit. Reconcile metadata using tools/reconcile_ground_facade_records.luau. Do not automatically run city preparation at server startup.

Git contains source and replay tools, not the full city geometry. Explicit manual Save to Roblox and a fresh reopen of this v2 rollout remain unconfirmed. Prior road-frontage work already survived reopening. No computer/browser controls were used.
