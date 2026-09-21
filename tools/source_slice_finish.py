"""Everything between a finished sweep and chunks Studio can apply.

  python tools/source_slice_finish.py --workers 12

Steps, in order, each resumable (delete its output to redo it):

  1. GATE    source_slice_pokeout.py over the merged batch, split across
             processes because one run of a thousand plans is an hour.
             Writes sweep/gate.json.
  2. CLASSIFY source_slice_crown_parapets.py: every crown is measured, the dull
             ones (86% of them) get a parapet built from the top floor's own
             outline, the rest are marked interesting. Writes sweep/parapets.json.
  3. CROWNS  source_slice_crowns_batch.py, but ONLY over the interesting ones.
             Crown extraction is the expensive half of the pipeline and 82% of
             buildings do not need it. Writes sweep/crowns.json.
  4. CHUNKS  source_slice_chunks.py: gate, cut into neighbourhoods, attach each
             building's crown data. Writes sweep/chunks/*.json.

Offline throughout. Applying is still a reviewed step in Studio.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
SWEEP = DATA / "sweep"
PLANS = DATA / "plans_all_remaining"
PYTHON = sys.executable


def run(cmd, log):
    started = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    Path(log).write_text(proc.stdout + proc.stderr)
    if proc.returncode != 0:
        print(proc.stdout[-3000:])
        print(proc.stderr[-3000:])
        raise SystemExit(f"FAILED ({proc.returncode}): {' '.join(str(c) for c in cmd)}")
    return time.time() - started, proc.stdout


def step_gate(workers, force):
    out = SWEEP / "gate.json"
    if out.exists() and not force:
        print(f"gate: {len(json.loads(out.read_text()))} rows already measured")
        return
    plans = sorted(PLANS.glob("*.json"))
    shards = SWEEP / "gate_shards"
    if shards.exists():
        shutil.rmtree(shards)
    # Round-robin, so every shard holds a mix of cheap and expensive plans and
    # no worker draws only the towers.
    buckets = [[] for _ in range(workers)]
    for index, path in enumerate(plans):
        buckets[index % workers].append(path)
    jobs = []
    for index, bucket in enumerate(buckets):
        if not bucket:
            continue
        d = shards / f"s{index:02d}"
        d.mkdir(parents=True)
        for path in bucket:
            shutil.copy(path, d / path.name)
        jobs.append((d, shards / f"s{index:02d}.json"))

    print(f"gate: {len(plans)} plans over {len(jobs)} shards")
    started = time.time()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(run, [PYTHON, "-u", str(ROOT / "source_slice_pokeout.py"),
                                     str(d), f"--json={j}"], shards / f"{d.name}.log"): d
                   for d, j in jobs}
        for future in futures:
            future.result()
    rows = []
    for _, j in jobs:
        rows.extend(json.loads(Path(j).read_text()))
    out.write_text(json.dumps(rows, indent=1))
    ious = sorted(r["iou"] for r in rows)
    print(f"gate: {len(rows)} measured in {(time.time() - started) / 60:.1f} min; "
          f"median IoU {ious[len(ious) // 2]:.3f}, "
          f"{sum(1 for v in ious if v >= 0.95)} at or above 0.95")


def step_classify(force):
    out = SWEEP / "parapets.json"
    if out.exists() and not force:
        print(f"classify: {len(json.loads(out.read_text()))} crowns already classified")
        return
    took, stdout = run([PYTHON, "-u", str(ROOT / "source_slice_crown_parapets.py"),
                        str(PLANS), str(out)], SWEEP / "parapets.log")
    print(f"classify: {took:.0f}s")
    for line in stdout.splitlines()[:3]:
        print("  " + line)


def step_crowns(workers, force):
    out = SWEEP / "crowns.json"
    if out.exists() and not force:
        print(f"crowns: {len(json.loads(out.read_text()))} already extracted")
        return
    parapets = json.loads((SWEEP / "parapets.json").read_text())
    interesting = [pid for pid, e in parapets.items() if e.get("interesting")]
    print(f"crowns: {len(interesting)} of {len(parapets)} buildings earned a detailed crown")
    shards = SWEEP / "crown_shards"
    if shards.exists():
        shutil.rmtree(shards)
    buckets = [[] for _ in range(workers)]
    for index, pid in enumerate(sorted(interesting)):
        buckets[index % workers].append(pid)
    jobs = []
    for index, bucket in enumerate(buckets):
        if not bucket:
            continue
        d = shards / f"s{index:02d}"
        d.mkdir(parents=True)
        for pid in bucket:
            shutil.copy(PLANS / f"{pid}.json", d / f"{pid}.json")
        jobs.append((d, shards / f"s{index:02d}.json"))

    started = time.time()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(run, [PYTHON, "-u", str(ROOT / "source_slice_crowns_batch.py"),
                                     str(d), str(j)], shards / f"{d.name}.log")
                   for d, j in jobs]
        for future in futures:
            future.result()
    merged = {}
    for _, j in jobs:
        merged.update(json.loads(Path(j).read_text()))
    out.write_text(json.dumps(merged))
    tris = sum(len(v) for v in merged.values() if isinstance(v, list))
    print(f"crowns: {len(merged)} extracted ({tris} triangles) in "
          f"{(time.time() - started) / 60:.1f} min")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--size", type=int, default=25, help="buildings per chunk")
    parser.add_argument("--gate-iou", type=float, default=0.95)
    args = parser.parse_args()

    assert PLANS.exists(), "run tools/source_slice_sweep.py first"
    SWEEP.mkdir(parents=True, exist_ok=True)
    step_gate(args.workers, args.force)
    step_classify(args.force)
    step_crowns(args.workers, args.force)
    took, stdout = run([PYTHON, "-u", str(ROOT / "source_slice_chunks.py"),
                        "--size", str(args.size), "--gate", str(args.gate_iou)],
                       SWEEP / "chunks.log")
    print(f"\nchunks: {took:.0f}s")
    print("\n".join(stdout.splitlines()[-6:]))


if __name__ == "__main__":
    main()
