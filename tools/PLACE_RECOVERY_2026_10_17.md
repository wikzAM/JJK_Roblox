# Studio recovery backup — October 17, 2026

## Latest checkpoint: cleanup and 445 additions

The existing Studio recovery written at 7:44:07 PM was copied locally before reconnection to `assets/TestJJK_StudioRecovery_2026-10-17_postcleanup.rbxl`. Size: 73,039,975 bytes. SHA-256: `70c90e865165ba29fe317cdd11f9defa012a442d1c57fd42dbf4138ca8a082b3`.

Read-only binary census: 2,212 building models, **1,713 live facade roots**, 1,726,876 instances, and zero BaseParts in both approved cleaned snapshots. This preserves all 445 additions from the post-cleanup pass. It includes the owner's current deletions. Final surface/blocker/SAT verification is still pending. Receipt: `TestJJK_recovery_2026-10-17_postcleanup.json`.

The subsequently reconnected cloud session independently reports 2,212 buildings and **1,513 facade roots**, with one embedded registry child remaining in each cleaned snapshot. Thus cleanup persisted, but only 245 of the 445 additions persisted in that cloud copy. The recovery contains 200 more facade sets. Always resurvey the actual opened place; never restore owner-deleted buildings from either file.

Automatic approval review rejected uploading this newer full-place payload under the older file's approval. The owner then explicitly answered **"Approve public upload of the newer checkpoint"**. Upload succeeded and GitHub verified exact size and SHA-256: [download newer checkpoint](https://github.com/wikzAM/JJK_Roblox/releases/download/place-files-2026-10-17/TestJJK_StudioRecovery_2026-10-17_postcleanup.rbxl).

The owner requests frequent saves. Connected MCP has no supported File → Save to Roblox action; computer control remains prohibited. Preserve newly written automatic recovery checkpoints frequently during the remaining rollout and verify their census. A local checkpoint, code push or successful batch is not evidence of a cloud save.

## Earlier checkpoint, before approved cleanup

This backup preserves the existing Studio auto-recovery file written at **4:05:33 PM America/Indianapolis** (20:05:33 UTC). It was copied to the project before automatic reconnection could discard it. It was not exported from Studio through MCP, and neither the original recovery file nor any live geometry was deleted.

File: `TestJJK_StudioRecovery_2026-10-17_160533.rbxl`.

Size: 70,205,942 bytes. SHA-256: `544c278fb7bb1ecb8ce5e9dfeaa64b011f3e916ccb4c1948d8479438c16a6496`.

The read-only binary hierarchy census found 2,219 direct building models and **1,352 live ground-facade roots**, preserving all 130 additions from this pass. The file has 1,824,384 instances in 122 classes. This is a hierarchy/integrity check, not an actual Studio open, Play, or full geometry verification. The receipt is `TestJJK_recovery_2026-10-17_160533.json`; the reader is `inspect_place_recovery.py`.

The separate cloud session reopened with **1,272 roots** and no pending bay preparation, so only 50 of this pass's 130 additions survived there. Its city room audit found 5,110 safe room recipes and zero room overlaps. The recovery file preserves 80 additional facade sets beyond that cloud copy. It has not received the final neighborhood surface/blocker/performance checks and is not the completed rollout. Approximately 734 safe targets remain from this recovery, versus 814 from the cloud copy; always survey the actual opened place afresh.

This older file includes obsolete facade archive copies from before the later approved cleanup. Source, station, landmark and owner-removal safeguards remain applicable. Prefer the newer checkpoint above when continuing elsewhere. Read `ProjectFiles.luau`, `FACADE_EXPANSION_HANDOFF.md`, and `FACADE_ARCHIVE_CLEANUP_REVIEW.md` before resuming. Sync current source through Rojo; do not rebuild a fresh empty place over this map.

This repository distributes full place snapshots as GitHub Release assets instead of committing large binaries to Git. The original local copy is ignored under `assets/`.

Upload authorization: automatic approval review initially rejected the full-file upload. After confirming that `wikzAM/JJK_Roblox` is public, the owner explicitly answered **"Approve public recovery-file upload"** on October 17, 2026. The release upload is authorized. This backup is incomplete work; its preserved geometry is separate from the lower cloud-persisted count described above.

Earlier upload completed: [place-files-2026-10-17](https://github.com/wikzAM/JJK_Roblox/releases/tag/place-files-2026-10-17). GitHub reports the exact 70,205,942-byte size and matching SHA-256 digest above. That older file preserves the original archive copies; the newer file above reflects their approved cleanup.
