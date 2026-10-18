# Verified manual Studio save checkpoints

October 17, 2026. The owner explicitly authorized computer control after requesting frequent saves. Each entry below means Studio's Output showed `Saved new changes in "TestJJK" to Roblox.` after File → Save to Roblox. Generation was paused for each save. These are observed save confirmations, distinct from a later reopen census or public game publishing.

- 19:51:15.577 invoked; 19:51:38.805 confirmed. Current connected census: 2,212 buildings and 1,513 facade roots. Approved archive cleanup had already survived reopening.
- 19:58:43.636 invoked; 19:59:17.567 confirmed. Current connected census: 2,212 buildings and 1,613 facade roots, zero pending v2 roots. All 100 additions in this cycle had glass/bay preparation.
- Next cycle reached 1,713 roots/pending v2 zero, then paused. File Save was attempted, but Studio disconnected at 20:03:10 before a new `Saving to Roblox...` or completion line appeared. **This checkpoint has no manual cloud-save confirmation.** Its 1,713-root level is preserved in the separately verified public recovery file; verify the actual next reopened cloud census.
- Reopened cloud session `3f82725b-683e-4e74-bc56-c484b6ea6bf7`: connected, 2,212 buildings and **1,613 facade roots**. This independently confirms the preceding manual save persisted; the following 100 additions were absent. Client Stats reported approximately 6,472 MB; this does not reveal the remote editing server's memory or establish the shutdown cause.
- Fresh queue added 50 roots and paused at **1,663**, zero pending v2. File Save started at 20:12:26.765; Output then showed a disconnect at 20:12:41.594, without a completion line. Expansion held pending a bounded instance-reduction fixture/pilot. Existing automatic recovery written 20:13:16 was copied locally to `assets/TestJJK_StudioRecovery_2026-10-17_201316.rbxl`: 72,833,279 bytes, SHA-256 `68c7c363eb5892bad6b1e3df3231a2a63e5ca28628983bf52eb52dcc8f786cea`. Binary census confirms 2,212 buildings/1,663 roots/zero approved snapshot parts; receipt `TestJJK_recovery_2026-10-17_201316.json`. This newest local file has not been publicly uploaded.

Reduce future cycles to roughly 50 new buildings, then pause for a verified save, and save after final repairs/verification. Preserve the owner's concurrent deletions. Do not mistake local batch success, a source Git push, a recovery file or `Saving to Roblox...` alone for a confirmed cloud save.

The separate public recovery checkpoint containing 1,713 roots predates this save cycle and includes 200 additions that were lost from the earlier cloud session. See `PLACE_RECOVERY_2026_10_17.md`. Remaining work must use the actual current live place, not restore its removed buildings.

## 20:31 check (Claude Code takeover)

Studio `3f82725b-683e-4e74-bc56-c484b6ea6bf7` is still open, but Team Create is disconnected (Output ends with `Internal server error.`; no ClientReplicator). The local view shows 2,212 buildings and 1,663 roots. The only AutoRecovery file is the 20:13:16 one already banked above. No save was attempted and nothing was mutated. Computer-use tools were not available to this session, so reconnecting needs the owner, either in the Studio UI or by reopening TestJJK.

Instance-budget census of the open view: ServerStorage holds 59 `SourceSliceStage_*` folders with 549,287 instances (529,671 ObjectValue rollback bindings, 488,253 of them nil). That is roughly 32% of the place, compared with about 2% for the full `GroundFacadeCompact` pass. See the 20:31 entry in `src/client/ProjectFiles.luau`.
