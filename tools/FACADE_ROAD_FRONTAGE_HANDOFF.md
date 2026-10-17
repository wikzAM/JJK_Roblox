# Ground facade road-frontage correction v10

October17 follow-up:see FACADE_SHARED_SURFACE_HANDOFF.md for the coplanar-wall repair and clearer3D inlet glass. Current actual totals are289082 parts/17029 panes/57 static inlets;all1066 committed journal entries were reconciled. Road classification is unchanged. Counts below describe the preceding v10 acceptance snapshot.

October 17,2026 reconnect and approved cleanup: TestJJK reopened successfully. All1066 installed roots still carry frontageRevision10;1063 committed journal entries and the final audit summary persisted. The owner explicitly approved deleting the previously blocked101 archived facade copies while retaining recipes. The inventory matched exactly101 roots/35527 BaseParts. Small synchronous batches preserved and read-verified each complete ArchivedManifestRow/ArchivedReportRow pair before deleting its generated geometry. Final verification found101 retained recipe pairs and zero remaining geometry roots in that approved scope. The1066 live facade sets,12884 station archive parts and both core backup roots remain present. Summary is stored in GroundFacadePilotManifest.ApprovedArchiveCleanupSummary. This confirms the frontage correction survived reopening; persistence of this new cleanup has not yet been tested through another reopen. Explicit manual Save to Roblox remains unconfirmed. No computer control was used.

October 16,2026. Current Edit correction is complete across all1066 INSTALLED buildings. This is not the separate2091-building expansion target. No Windows/browser control was used. Explicit final manual Save to Roblox remains unconfirmed; Studio MCP plugin-context save is unsupported.

## Result

Three owner-selected IDs:orph_-933_-739,orph_-1033_-842,fbx_4_-10904_1766_-9267. Their real frontage follows OSM way56753499. The selected fixes provide19 entrance portals on verified road faces and none on internal sides. MCP screenshot SelectedRoadFacingFixed reviewed.

Final whole-installed-city audit:1066 buildings,10061 complete ground runs,1502 verified road-front candidates,1636 entrance portals on public approaches,8559 quiet runs with ZERO entrance portals.518 public-facing runs retain quiet treatments because of width, height, core/neighbor obstructions or unusable local elevation; do not force fake entries through those constraints. There are no unexplained closed-style exceptions after the final pass.

Exact visibility/own-source scan covered17029 panes and153261 rays:ZERO blocked bays and ZERO unresolved identities. Intentional same-bay SmashBrickButtress/security-grille masks are exempt only for their own bay; they still block other bays. Static inlet dressing is nonqueryable.44 shallow inlet cells were reapplied to the original six explicit trial models after replacement. Current coherent totals:289682 owned BaseParts,17029 panes. These counts include inlet additions. Older359743-part/24365-pane v9 counts are historical.

No terrain, road, floor, core or building-generator edits were made by this correction. A first local full-pass audit compared the original-part snapshot and found zero changes before a reconnect discarded that in-memory snapshot. Do not claim retrospective original-part proof from later absent baselines. Upper glass/far proxies remain disabled. Full Play/performance testing is separate and pending; Edit geometry acceptance is not a frame-rate promise.

## Rule changes

Temporary RoadClass=inferred / RoadWay=0 strips no longer establish a public street or influence the doorway ground probe. Positive OSM RoadWay or explicit FacadePublicApproach is required. Road/terrain Instances were retained untouched. Internal unproved gaps under18studs are blind; open secondary faces use quiet windows. Front classification additionally requires safe clearance. One uneven sample no longer blanks an entire public-facing run: uniform elevation can veto a face, and each actual doorway still checks approach occupancy, ground and rise.

Pedestrian stair rise is bounded5.5studs, allowing the selected road faces whose existing floors sit3.2-4.9studs above Terrain. Vehicle ramps retain a4stud rise cap, maximum.25 slope and exact toe/support checks. No source floor was moved to produce a door.

The street profile excludes closed shutters/security grilles, sparse walls and parking-only types. This keeps public shop fronts entrance-capable. Explicit parking profiles/types remain available for verified native voids. The former five garage trial cells faced inferred/internal approaches under the old survey; their portals were removed by the corrected orientation policy. Their old geometry remains in pre-existing archives. Do not restore an internal-side car entrance simply to preserve an obsolete example count; author future garage examples on public approaches with enough real floor/core space.

Section.SelectCity re-surveys cached rows whose frontageRevision differs from Frontage.REVISION. Preserve wall/tenant seed intent; do not reuse stale quiet-side bay decisions when promoting a real road frontage.

## Persistence and batching

Two earlier passes appeared locally complete but Roblox shut down its editing server (log reason288). After reopening, only103 v10 roots were present. The FINAL963 replacements used synchronous25-building calls, checking ClientReplicator before each batch and retaining committed per-building journal records. All1066 actual roots now carry frontageRevision10; Studio remained connected at final readback.

To avoid creating more heavy geometry backups, these final replacements used Pilot.Upsert(rows,freshScene,{city=true,incremental=true,archive=reusedOwnedArchive,keepReplacedGeometry=false}). This option replaces only the current live owned facade, retaining an exact rollback handle until commit and then storing its old manifest/report recipe rather than another geometry copy. It NEVER deletes pre-existing archived backups. Automatic review initially rejected a separate proposed cleanup of101 existing archived roots/35527 parts because recipes might not reproduce exact old geometry. On October17 the owner explicitly approved that exact cleanup while retaining recipes; it is now complete as recorded above. These recipes are rebuild inputs, not exact geometry snapshots. Other archived originals and backups remain protected.

GroundFacadeRegistry.ReadLatest(reg,'Manifest'/'Report') folds the atomic checkpoint and committed CommitJournal without rewriting giant aggregate strings. Raw aggregate Report/Manifest can be older between consolidations; use ReadLatest for current figures and audits.1063 committed journal entries plus the saved three-building checkpoint describe the final set. Do not discard that journal merely because registry State is ready. No giant final consolidation is needed for coherent readback.

Persistent audit summary:ServerStorage.GroundFacadePilotManifest.FrontageV10AuditSummary; FrontagePolicyRevision10,State ready. Helpers and committed root ManifestRow/ReportRow records are in Studio. Source and this handoff are backed up in Git; Git does not contain the complete live map geometry. A fresh Rojo build is not a substitute for opening TestJJK.

## Verification/replay

Run tools/verify_ground_frontage_v10.luau for fresh read-only orientation checks; it can build expected rows if the prior globals were lost. Use tools/scan_facade_v9_blockers.luau for final-neighborhood visibility, with ReadLatest-aware registry access. Rebuild only identified bays/buildings and rerun the full scan. Keep the station archive, >15-story/large/landmark protections and the existing installed scope unchanged.
