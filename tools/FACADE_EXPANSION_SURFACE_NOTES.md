# Expansion surface and bay integration — October 17, 2026

This source correction subsequently compiled and ran in the reopened TestJJK. The catch-up pass preserved507 originals/inserted320 fragments; final exterior verification checked310maskedruns/3557parts withzero remaining intersections. All affected room recipes were prepared again; the city room audit foundzero overlaps. See `FACADE_GLASS_CATCHUP_2026_10_17.md` for the exact current baseline and archives. A fresh reopen/manual Roblox save of this pass remains unconfirmed.

`GroundFacadeSurfaceResolver` consistently excludes generated whole-bay preview parts from run extent/pane counts, clipping, and mask verification. Identification requires all three existing attributes: `FacadeBayInteriorPart=true`, `FacadeLayer="interior"`, and `FacadePieceKind="preview"`. These recessed parts intentionally occupy a different depth from exterior shared surfaces; their wedges and angled sides must never be passed to the exterior rectangle fragmenter.

When an exterior repair stages at least one actual replacement, it invalidates all existing bay recipes in the affected facade root. Each old recipe's attributes and bay ObjectValue are retained under a `BayInteriorInvalidation` holder inside the owned surface archive. Exact existing Edit preview folders are moved there intact. Bay tags and recipe attributes are cleared; both root and building completion markers are cleared, allowing `PrepareNextBatch()` to fully replan. Repeated runs in the same root do not add redundant snapshots after its recipes are already invalidated. A no-op run performs no invalidation or metadata change.

Surviving glazing returns to its captured exterior transparency/reflectance and flat backing. Damaged glass remains hidden. Staged replacement panes receive this normalization separately, so the pre-trim original panes and attached pieces remain exact inside their usual `OriginalPart` archive holders. Surface restore retains recipe snapshots, invalidates any subsequently prepared rooms, restores exterior geometry, and leaves the normal preparation/overlap pipeline responsible for enabling fresh interiors.

The archive is additive: existing facade, station, core and surface backups are not deleted. Unexpected native preview ownership/version fails preflight before moving live geometry.

After reconnecting, sync fresh module instances and complete this acceptance order:

1. Finish expansion and the two explicitly identified box repairs. Preserve original source geometry and exact repair backups.
2. Plan/apply global exterior surface ownership with this corrected resolver; run `VerifyInstalled()`.
3. Run bounded bay preparation until no roots remain pending. Check prepared plus fallback counts against every glazed bay.
4. Run `verify_bay_interior_geometry.luau` and `verify_bay_interior_city.luau`; resolve all city overlaps with the existing safe shortening/flat fallback path.
5. Clear `_G.FacadeV9BlockerOptions` and run the full blocker collector. Persist targeted `bayRoles[index]="blind"` vetoes and use ordinary owned upserts only where needed. Every such rebuild repeats surface ownership, bay preparation and overlap acceptance.
6. Reconcile actual root records/journal, then run visibility, frontage and support/perimeter audits. Clear `_G.FrontageV10Expected` so its survey includes new roots, and provide current audit helpers/manifests.
7. Playtest nearby, far, corner, glass damage/reset and performance behavior; obtain actual save/reopen evidence before claiming Roblox persistence.

Reconciliation must compare actual mask JSON, not merely a surface revision/count: changed masks can retain identical part totals. The coordinating parent corrected this separately in `reconcile_ground_facade_records.luau`.
