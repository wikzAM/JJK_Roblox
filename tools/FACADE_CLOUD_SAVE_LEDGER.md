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

## 22:10 approved stage-folder deletion

The owner explicitly approved deleting all 59 `ServerStorage.SourceSliceStage_*` folders. The owner closed and reopened TestJJK. The new Studio is `2acaf4c1-6678-4895-a58c-f4b836d3ebc0`, connected, PlaceVersion 625, with 2,212 buildings and 1,613 roots. That census matches the last confirmed cloud save. A preflight scan found zero references from outside the stages into them. Folders were destroyed one at a time, 1.5 s apart, with the ClientReplicator checked after each one. The session stayed connected throughout.

Removed 549,287 instances in total. Each entry is a GUID suffix followed by the instance count:
- Trial batch: be08b4e3=100 (unapplied FBX sample), 1d3017d7=845, 8b35902b=3837.
- a23ef8f1=3983, de05053d=5503, f9560124=5601, fc7b8a3c=5641, b486468d=5753, 05b53068=5799, 807f84bd=6601, fa10b947=6783, 471be245=7049, f3bbdd98=7057, e0cc33f0=7131, 8cd558b0=7885, 7851feaf=7887, f6d55196=7915, 5012d1c2=8289.
- d6dff438=8617, 470028a2=8711, 2d2385a0=8835, a04db857=8937, e0ed5feb=8955, 2455cfad=9001, e3afbd07=9223, 2e601c0a=9241, 08894eb9=9463, 4f82c720=9515, 251660aa=9539, 521111ee=9693, 53a678e4=9809, d84f5a70=9827, 57dc4ac1=9897, cba4e066=9925, eb4c235e=9997, c3ebd640=10059, 513a872e=10095, b969a645=10201.
- 13f67a9e=10273, 5d0bedfd=10373, 87499fd8=10543, 6dd8a6e5=10639, 556bee08=10689, 2238bbab=10771, 9a2f9425=10939, 547ca2d8=11327, 7e42c1ce=11929, e948c30c=11944 (unapplied v8 stage, 55 models), 6ce449f4=12125, 176caf77=12131, da0060f9=12441, a5c1bc51=12457, 1bf10b36=12561, f004d50b=12647, 6143222e=12859, 17718ca9=14179, e60fd247=14183, b4e8ddb8=15351, c786ff8a=15727.

Post-check: 2,212 buildings and 1,613 roots. ServerStorage is down to 289,707 instances and Workspace is at 848,039. All protected archives are present. **Cloud save of this deletion is not yet confirmed.**

## 22:11 – 22:24 save-verified cycles (Studio 2acaf4c1)

Save confirmations below come from the `[FLog::CreatorOutput]` lines in `%LOCALAPPDATA%\Roblox\logs\*Studio*_last.log`. LogService and the MCP console tool never show them.

- 22:11:14 Saving, then 22:11:43 **Saved**. This captures the 59-stage-folder deletion at 1,613 roots.
- Fresh Prepare: alias `_Save50_`, archive `Expansion_b7fcc541-4dc0-4497-8210-470082f715bb`. Scope: 2,082 eligible, 130 held, 1,612 installed, 468 queued, plus 2 extra height holds. BATCH_SIZE was set to 25 at runtime. The first two Steps added 50 roots (1,663) with immediate v2 interiors (196 prepared bays, 17 flat-backed, 821 panes) and zero errors.
- 22:16:50 Saving, then 22:17:12 **Saved** at **1,663 roots**.
- The next two Steps added 50 more (1,713), with 278 prepared bays, 16 flat-backed, 1,158 panes and zero errors. 368 targets remain queued. Studio memory rose from about 3.1 GB to 4.0 GB over these four Steps. Save of 1,713 is pending.
- 22:21:24 Saving, then 22:21:53 **Saved** at **1,713 roots**.
- The next two Steps (finished 22:23:20) added 50 roots (1,763), with 228 prepared bays, 11 flat-backed, 910 panes and zero errors. 318 remain queued. Memory was about 4.4 GB. Save of 1,763 is pending.
- 23:16:02 Saving, then 23:16:43 **Saved** at **1,763 roots** (41 s).
- The next two Steps (finished 23:18:21) added 50 roots (1,813), with 198 prepared bays, 13 flat-backed, 724 panes and zero errors. 268 remain queued. Memory was about 4.3 GB. Save of 1,813 is pending.
- 23:20:08 Saving, then 23:20:38 **Saved** at **1,813 roots**.
- The next two Steps (finished 23:21:28) added 50 roots (1,863), with 210 prepared bays, 10 flat-backed, 737 panes and zero errors. 218 remain queued. Memory was about 4.1 GB. Save of 1,863 is pending.
