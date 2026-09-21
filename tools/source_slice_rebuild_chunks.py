"""Turn a regenerated sweep into REBUILD chunks for buildings already live.

After a plan-builder fix, `source_slice_sweep.py --force` rewrites every plan,
but most buildings come out identical and only some are live. This finds the
ones that are both LIVE (they appear in an applied chunk) and CHANGED, gates the
changed plans, and writes `sweep/chunks/rebuild_NN.json` for
`SourceSliceSweepApply.Rebuild`.

  python tools/source_slice_rebuild_chunks.py [--size 25] [--gate 0.95]

The applied chunk files are the source of truth for what is in the map; they are
read, never rewritten, because live locks refer to them by name.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
SWEEP = DATA / "sweep"
CHUNKS = SWEEP / "chunks"
PLANS = DATA / "plans_all_remaining"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, default=25)
    parser.add_argument("--gate", type=float, default=0.95)
    parser.add_argument("--tag", required=True,
                        help="names this batch rebuild_<tag>_NN. Every Rebuild takes a lock by "
                             "chunk name, so reusing a name would make Studio return REPLAY and "
                             "silently do nothing -- each round of fixes needs its own tag")
    args = parser.parse_args()

    # What is LIVE is the applied chunk plans, overlaid by every rebuild already
    # applied since (rebuild files are history and are never deleted). Diffing
    # against the original chunks alone re-flags every building rebuilt before.
    live = {}
    for path in sorted(CHUNKS.glob("chunk_*.json")):
        for plan in json.loads(path.read_text())["plans"]:
            live[plan["id"]] = plan
    for path in sorted(CHUNKS.glob("rebuild_*.json")):
        for plan in json.loads(path.read_text())["plans"]:
            live[plan["id"]] = plan
    fresh = {p.stem: json.loads(p.read_text()) for p in PLANS.glob("*.json")}

    changed, vanished = [], []
    for pid, old in live.items():
        new = fresh.get(pid)
        if new is None:
            vanished.append(pid)          # the fixed builder no longer plans it
        elif new["levels"] != old["levels"] or new["core"] != old["core"]:
            changed.append(pid)
    print(f"{len(live)} live sweep buildings: {len(changed)} changed, "
          f"{len(live) - len(changed) - len(vanished)} identical, {len(vanished)} no longer planned")

    # Gate the changed plans with the same tool and threshold as the sweep.
    shard = SWEEP / "rebuild_gate"
    if shard.exists():
        shutil.rmtree(shard)
    shard.mkdir(parents=True)
    for pid in changed:
        (shard / f"{pid}.json").write_text(json.dumps(fresh[pid]))
    rows_path = SWEEP / "rebuild_gate.json"
    subprocess.run([sys.executable, "-u", str(ROOT / "source_slice_pokeout.py"), str(shard),
                    f"--json={rows_path}"], check=True, capture_output=True)
    rows = {r["id"]: r for r in json.loads(rows_path.read_text())}
    passing, refused = [], []
    for pid in changed:
        row = rows.get(pid)
        # Unmeasured is kept, exactly as in the sweep: 5 of the 123 shipped sector
        # plans were unmeasured and all 5 were applied.
        if row is None or row["iou"] >= args.gate:
            passing.append(pid)
        else:
            refused.append((pid, row["iou"]))
    for pid, iou in refused:
        print(f"  KEEP OLD {pid}: regenerated plan scores IoU {iou:.3f} < {args.gate}")

    prefix = f"rebuild_{args.tag}_"
    if any(CHUNKS.glob(prefix + "*.json")):
        raise SystemExit(f"{prefix}* already exists -- pick a new --tag; applied rebuilds are history")
    groups = [passing[i:i + args.size] for i in range(0, len(passing), args.size)]
    for index, ids in enumerate(groups, start=1):
        name = f"{prefix}{index:02d}"
        (CHUNKS / f"{name}.json").write_text(json.dumps(
            {"name": name, "plans": [fresh[pid] for pid in ids], "parapets": {}, "crowns": {}}))
    print(f"{len(passing)} rebuilds in {len(groups)} chunks -> {CHUNKS}/{prefix}NN.json")
    if vanished:
        print(f"{len(vanished)} live buildings the fixed builder no longer plans (left as they are): "
              + ", ".join(vanished[:8]) + (" ..." if len(vanished) > 8 else ""))


if __name__ == "__main__":
    main()
