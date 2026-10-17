# Studio recovery backup — October 17, 2026

This backup preserves the existing Studio auto-recovery file written at **4:05:33 PM America/Indianapolis** (20:05:33 UTC). It was copied to the project before automatic reconnection could discard it. It was not exported from Studio through MCP, and neither the original recovery file nor any live geometry was deleted.

File: `TestJJK_StudioRecovery_2026-10-17_160533.rbxl`.

Size: 70,205,942 bytes. SHA-256: `544c278fb7bb1ecb8ce5e9dfeaa64b011f3e916ccb4c1948d8479438c16a6496`.

The read-only binary hierarchy census found 2,219 direct building models and **1,352 live ground-facade roots**, preserving all 130 additions from this pass. The file has 1,824,384 instances in 122 classes. This is a hierarchy/integrity check, not an actual Studio open, Play, or full geometry verification. The receipt is `TestJJK_recovery_2026-10-17_160533.json`; the reader is `inspect_place_recovery.py`.

The separate cloud session reopened with **1,272 roots** and no pending bay preparation, so only 50 of this pass's 130 additions survived there. Its city room audit found 5,110 safe room recipes and zero room overlaps. The recovery file preserves 80 additional facade sets beyond that cloud copy. It has not received the final neighborhood surface/blocker/performance checks and is not the completed rollout. Approximately 734 safe targets remain from this recovery, versus 814 from the cloud copy; always survey the actual opened place afresh.

Use the recovery file as a local Studio backup when continuing elsewhere. It includes obsolete facade archive copies; the proposed additional cleanup remains unapproved and unperformed. Source, station, landmark and owner-removal safeguards remain applicable. Read `ProjectFiles.luau`, `FACADE_EXPANSION_HANDOFF.md`, and `FACADE_ARCHIVE_CLEANUP_REVIEW.md` before resuming. Sync current source through Rojo; do not rebuild a fresh empty place over this map.

This repository distributes full place snapshots as GitHub Release assets instead of committing large binaries to Git. The original local copy is ignored under `assets/`.
