# Additional facade archive cleanup review

October 17, 2026. **New human approval is pending. No cleanup has been performed under this plan.** The earlier approval for 101 archived copies/35,527 parts applied to a different set and has already been completed.

The current native `ServerStorage.GroundFacadePilotArchive` contains 322,411 BaseParts. Its two largest reviewed snapshots are:

- `BeforePerimeter_1791668032`: 200 generated root copies, 100,117 BaseParts. Embedded original registry has 200 Manifest rows and 200 Report rows.
- `BeforePerimeter_1791668306`: 200 generated root copies, 93,642 BaseParts. Embedded original registry has 200 Manifest rows and 200 Report rows.

Native inspection found zero BaseParts outside the generated roots in these two snapshots. All 400 copied roots carry Owner `2026-10-08-ground-pilot`, and their names match their embedded Manifest identities. The snapshot parent folders do not carry an Owner attribute; their structure also matches the old `GroundFacadePilot.Apply` snapshot code. Each embedded registry is a separate retained child.

The proposed additional cleanup removes ONLY these 400 obsolete generated facade root copies (193,759 parts) and retains both embedded registries byte-for-byte, including recipes/reports. Exact old facade geometry will no longer be recoverable. The remaining roughly 128,652 Pilot archive parts are outside this proposed scope. Live facades, source buildings, station geometry, core backups, surface backups and old per-pane previews are outside the scope.

`ObsoleteFacadeSnapshotCleanup` is an explicit edit-only helper. Requiring it does nothing. `Prepare()` is read-only and requires the reviewed exact initial counts and ownership. The operator must record a new explicit human approval through `Approve(ctx, authorization)` before `Step(ctx)` can remove anything. Each Step processes at most 1,000 queued parts, deepest-first, verifies recipes remain identical and validates original direct parentage of registries and roots. It rechecks protected tags and refuses unexpected descendant geometry before destruction. The final step verifies zero remaining parts, removes only the reviewed empty root containers, and retains both registry children. A changed count/moved target/changed registry stops the helper. A disconnect requires inspection of remaining geometry before preparing a new plan. Prior unrelated cleanup approval does not qualify.

Roblox documents cloud autosaving in collaborative sessions, but the exact cause of this place's repeated shutdowns is not established. Archived instance load is being investigated; this proposal is not proof that removing it will fix the server. Source build checks are not native cleanup verification.
