"""Plan the WHOLE remaining map, tile by tile, in parallel.

The sector runs (`--near X Z R`) were hand-driven one neighbourhood at a time,
which is right for reviewing 30 buildings by eye and wrong for the ~1,800 grey
groups that are left: circles overlap, so the same group gets planned twice and
has to be filtered out afterwards, and one process plans everything serially.

This drives `source_slice_plan_builder.py --box`, which partitions instead of
overlapping: a group's mean centre falls in exactly ONE tile, so no group is
planned twice and no two tiles can claim the same grey. Tiles are independent
processes, so the sweep runs at whatever the machine has cores for.

  python tools/source_slice_sweep.py --workers 12
  python tools/source_slice_sweep.py --merge-only

Resumable: a tile whose output directory carries a `.done` marker is skipped, so
the sweep can be stopped and restarted without losing work.

Nothing here touches Studio. It writes plans; applying them is still a manual,
reviewed step (`Builder.StagePlans` -> `Replacement.Capture` -> `Apply`).
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
SWEEP = DATA / "sweep"
TILES = SWEEP / "tiles"
BUILDER = ROOT / "source_slice_plan_builder.py"
PYTHON = sys.executable

TILE = 600.0          # studs; ~20 groups per tile, so one tile is ~1 minute
MIN_MEMBERS = 1       # the sectors used 1: a single grey is still a building
LIMIT = 400           # per tile; far above the busiest tile's group count


def source_key(name):
    """Mirror of the builder's own key derivation, for counting only."""
    stem = name[len("BuildingSmooth_"):]
    stem = re.sub(r"_Residual_[0-9a-f]+_Body\d+$", "", stem)
    stem = re.sub(r"_ResidualBody\d+$", "", stem)
    stem = re.sub(r"_Residual$", "", stem)
    stem = re.sub(r"_Body\d+$", "", stem)
    return stem


def remaining_groups(applied):
    live = [b for b in json.loads((DATA / "live_buildings.json").read_text())
            if b["name"].startswith("BuildingSmooth") and b["name"] not in applied]
    groups = {}
    for b in live:
        groups.setdefault(source_key(b["name"]), []).append(b)
    return live, groups


def tile_of(cx, cz):
    return int(cx // TILE), int(cz // TILE)


def plan_tiles(groups):
    counts = Counter()
    for members in groups.values():
        cx = sum(b["cf"][0] for b in members) / len(members)
        cz = sum(b["cf"][2] for b in members) / len(members)
        counts[tile_of(cx, cz)] += 1
    # Busiest first: the long pole finishes while short tiles fill the workers.
    return [t for t, _ in counts.most_common()], counts


def run_tile(tile, applied_file, force):
    tx, tz = tile
    out = TILES / f"{tx}_{tz}"
    marker = out / ".done"
    if marker.exists() and not force:
        return tile, "skip", 0.0, len(list(out.glob("*.json")))
    out.mkdir(parents=True, exist_ok=True)
    cmd = [PYTHON, "-u", str(BUILDER),
           "--box", str(tx * TILE), str(tz * TILE), str((tx + 1) * TILE), str((tz + 1) * TILE),
           "--min-members", str(MIN_MEMBERS), "--limit", str(LIMIT),
           "--skip-names", str(applied_file), "--out", str(out)]
    started = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    (out / "build.log").write_text(proc.stdout + proc.stderr)
    took = time.time() - started
    if proc.returncode != 0:
        return tile, "fail", took, 0
    marker.write_text(f"{time.strftime('%Y-%m-%d %H:%M:%S')}  {took:.1f}s\n")
    return tile, "ok", took, len(list(out.glob("*.json")))


def merge(applied, applied_ids):
    """Fold every tile's plans into one batch, with the builder's own dedupe.

    Tiles cannot claim the same grey, but two groups either side of a tile edge
    can still describe one building at nearly the same origin -- inside a single
    run `deduplicate` would have folded them. Run it globally so the edge case
    is handled the same way everywhere.
    """
    sys.path.insert(0, str(ROOT))
    from source_slice_plan_builder import deduplicate  # noqa: E402

    plans, seen = [], {}
    for path in sorted(TILES.glob("*/*.json")):
        if path.name in ("build.log",):
            continue
        plan = json.loads(path.read_text())
        if plan["id"] in applied_ids:
            continue                      # already a live BuildingSourceSlice
        if plan["id"] in seen:
            continue
        seen[plan["id"]] = path
        plan["sourceInfo"]["replaces"] = [n for n in plan["sourceInfo"]["replaces"]
                                          if n not in applied]
        if plan["sourceInfo"]["replaces"]:
            plans.append(plan)

    final = deduplicate(plans)
    out = DATA / "plans_all_remaining"
    out.mkdir(parents=True, exist_ok=True)
    for stale in out.glob("*.json"):
        stale.unlink()
    for plan in final:
        (out / f"{plan['id']}.json").write_text(json.dumps(plan, indent=1))

    claimed = [n for p in final for n in p["sourceInfo"]["replaces"]]
    assert len(claimed) == len(set(claimed)), "a grey is claimed twice"
    assert not (set(claimed) & applied), "a plan claims an already-replaced grey"
    levels = sum(len(p["levels"]) for p in final)
    print(f"\nmerged {len(plans)} tile plans -> {len(final)} after global dedupe")
    print(f"  {len(claimed)} greys claimed, each exactly once")
    print(f"  {levels} levels, {levels / max(1, len(final)):.1f} per building")
    print(f"  -> {out}")
    return final


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--force", action="store_true", help="re-run finished tiles")
    parser.add_argument("--merge-only", action="store_true")
    parser.add_argument("--limit-tiles", type=int, help="stop after this many tiles (smoke test)")
    args = parser.parse_args()

    applied_file = DATA / "applied_greys.txt"
    applied = {n.strip() for n in applied_file.read_text().splitlines() if n.strip()}
    applied_ids = {n.strip() for n in (DATA / "applied_ids.txt").read_text().splitlines()
                   if n.strip()}
    live, groups = remaining_groups(applied)
    tiles, counts = plan_tiles(groups)
    print(f"{len(live)} greys remain in {len(groups)} groups over {len(tiles)} tiles "
          f"of {TILE:.0f} studs; {len(applied_ids)} buildings already live")

    if not args.merge_only:
        if args.limit_tiles:
            tiles = tiles[:args.limit_tiles]
        SWEEP.mkdir(parents=True, exist_ok=True)
        started, done = time.time(), 0
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(run_tile, t, applied_file, args.force) for t in tiles]
            for future in futures:
                tile, status, took, made = future.result()
                done += 1
                print(f"  [{done}/{len(tiles)}] tile {tile[0]}_{tile[1]} "
                      f"({counts[tile]} groups) {status} {took:.0f}s -> {made} plans",
                      flush=True)
        print(f"\nsweep finished in {(time.time() - started) / 60:.1f} min")

    merge(applied, applied_ids)


if __name__ == "__main__":
    main()
