# Current persistence blocker

Roblox editing server shut down again (Studio log reason288). MCP studio306c9fc1-fc6b-40ba-b868-6d91965dfdac reports cached Edit mode but execute bridge is unreachable. Owner was asked to reopen TestJJK; no computer control used.

After the FIRST restart, only the three selected v10 roots persisted. Therefore the earlier932-building background completion below was LOCAL evidence, NOT persisted cloud completion. A SECOND pass rebuilt ALL1063 other roots in synchronous batches of25, each returning successfully, with committed CommitJournal entries and one reused archive. All1063 batch updates completed. Server shut down during final aggregate consolidation; persistence of this second pass remains UNVERIFIED until place reopens. Do not claim all1066 are saved.

Pilot.Upsert now supports incremental=true and a reused owned archive for small synchronous calls. CommitJournal is authoritative between checkpoints. Registry.ReadLatest folds checkpoint plus committed journal WITHOUT writing giant aggregate properties; use it for live audits/markers. No empty-list consolidation is needed to obtain coherent live readback. Root ManifestRow/ReportRow and journal can recover latest per-building work even if aggregate Report is older. Source code is in Git; new ReadLatest consumer changes still need syncing to Studio after reconnect.

The first-pass validation and selected fixes below remain useful evidence, but final whole-city occlusion and orientation checks must be rerun against reopened state. The initial prepared17 repairs were not confirmed applied. Recollect blockers using the updated own-bay trim exemptions and repair only actual neighboring obstructions; resurvey closed public fronts if any remain. Restore shallow inlet trial only on its explicit six model IDs after replacing their roots; the garage orientation note below applies.

# Verified-road frontage correction - October 16, 2026

Owner request:three selected buildings had entrances facing between buildings and plain walls facing the road. Correct this rule everywhere already installed. Do not expand the city or touch terrain/source structure. No computer control.

Selected source IDs:orph_-933_-739,orph_-1033_-842,fbx_4_-10904_1766_-9267. Their verified street is OSM way56753499. Temporary RoadClass=inferred / RoadWay=0 strips had been counted as streets; whole-run elevation rejection also blanked real street faces. The real Terrain rises at the selected frontage were3.2-4.9studs below the first floor, so the bounded pedestrian rise is now5.5studs; vehicle rise remains4 with slope/support checks.

## Applied

- Frontage.Index and Ground exclude temporary inferred road pieces. Only positive OSM RoadWay or explicit FacadePublicApproach counts as a public approach. Road/terrain Instances remain unchanged.
- Front classification requires verified road evidence and usable clearance. Unproved gaps under18studs are blind; open secondary faces get quiet windows. Whole-face elevation suppression now requires uniformly unusable height; every actual doorway still checks its own approach.
- Added street profile excludes closed shutters/security grilles, sparse and parking-only styles. New surveys use it; cached pre-policy manifests are re-surveyed by Section.SelectCity.
- Three selected buildings rebuilt:19 entrance portals, all facing verified roads; internal sides have zero portals. MCP screenshot SelectedRoadFacingFixed reviewed.
- All1066 installed buildings surveyed.932 others required rebuilding,131 already had correct orientation.932 completed with zero Upsert errors; no new building targets were added.
- Fresh orientation audit:1066 buildings/10061 runs,1502 expected public road fronts,1639 portals on verified approaches,zero quiet-side portals,zero missing runs/errors,zero original-part changes.
- 516 public-facing runs have no portal:179 too narrow,7 unsupported heights,172 neighbor obstructions,75 local elevation failures,54 excessive rises,19 core-space/clearance failures,1 building-blocked approach,8 closed-style cases needing a final targeted pass. A frontage label does not override physical access constraints.

## Final checks in progress

Exact visibility scan:1066 buildings,17057 panes,153273 rays;36 flagged bays in27 buildings,zero unresolved IDs. Several flags were intentional same-bay SmashBrickButtress/security grille masks. Collector now exempts only those trims WITHIN their own bay; they remain blockers of every other bay. Other neighboring wall occlusions are real.17 targeted building repairs were prepared, combining those neighbor vetoes and8 closed-style public fronts. Studio disconnected during the request starting that pass; its completion must be checked after reconnect. Main932-building orientation correction had completed before that disconnect.

39 shallow inlets were reapplied to their six explicit trial models after orientation changes. The former garage trial sides no longer contain accepted parking portals under the verified-road rule; their old geometry remains in the owned facade archive. Do not restore car entrances on internal sides simply to keep an old example count. New road-facing garages can be deliberately selected where existing floor/core clearance allows them.

Full city rollout to2091 targets and full Play/performance testing remain separate pending work. Save-only via MCP is unsupported in plugin context; no native save is authorized while computer control is prohibited. Team Create persistence should be checked after reconnect. Use GroundFacadeRegistry.Read/Write for manifests and roots.
