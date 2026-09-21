"""Gate the swept plans, then cut them into chunks the Studio applier can pull.

`source_slice_sweep.py` produces one big batch. `SourceSliceSweepApply.Run` wants
a self-contained unit of work: the plans, their parapets and their crown
triangles in one document, small enough for HttpService to fetch in one call.

  python tools/source_slice_chunks.py --gate 0.95 --size 25

Order is deliberate:

  1. DROP anything under the fidelity gate. The three buildings refused in the
     sector runs were refused on exactly this number, and one of them was
     offered twice.
  2. Chunk what survives, GEOGRAPHICALLY -- a chunk is a neighbourhood, so a
     preview screenshot shows one contiguous piece of city instead of buildings
     scattered across Shibuya.
  3. Attach each building's parapet or crown triangles to its own chunk.

Nothing is applied here. The chunks are served to Studio by source_slice_sink.py.
"""
from pathlib import Path
import argparse
import json
import math

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
SWEEP = DATA / "sweep"
CHUNKS = SWEEP / "chunks"


def load_plans(plans_dir):
    return {p["id"]: p for p in
            (json.loads(f.read_text()) for f in sorted(plans_dir.glob("*.json")))}


def gate(plans, rows_path, threshold, spill):
    """Keep a plan only if it reproduces the FBX section it was sliced from."""
    if not rows_path.exists():
        raise SystemExit(f"run source_slice_pokeout.py --json={rows_path} first")
    rows = {r["id"]: r for r in json.loads(rows_path.read_text())}
    kept, dropped, unmeasured = {}, [], []
    for pid, plan in plans.items():
        row = rows.get(pid)
        if row is None:
            # KEEP, do not drop. The gate cannot measure a plan whose levels all
            # sit where the FBX has holes, and "unmeasured" is not "bad": of the
            # 123 plans the sector runs produced, 5 were unmeasured and all 5
            # were SHIPPED. Dropping them would refuse ~45 buildings the hand
            # runs would have applied. They are listed for eyes instead.
            unmeasured.append(pid)
            kept[pid] = plan
            continue
        if row["iou"] < threshold:
            dropped.append((pid, f"IoU {row['iou']:.3f} < {threshold}"))
            continue
        if row["outside"] > spill:
            dropped.append((pid, f"{row['outside'] * 100:.1f}% outside the FBX"))
            continue
        kept[pid] = plan
    return kept, dropped, unmeasured


def chunk_order(plans, size):
    """Neighbourhood-sized chunks, nearest-neighbour from the south-west.

    Sorting by id would scatter each chunk across the map, and a chunk is the
    unit a human previews before trusting it.
    """
    left = {pid: (p["origin"]["x"], p["origin"]["z"]) for pid, p in plans.items()}
    out = []
    while left:
        cx, cz = min(left.values(), key=lambda c: (c[0] + c[1]))
        group = sorted(left, key=lambda pid: (left[pid][0] - cx) ** 2 + (left[pid][1] - cz) ** 2)
        group = group[:size]
        out.append(group)
        for pid in group:
            del left[pid]
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--plans", default=str(DATA / "plans_all_remaining"))
    parser.add_argument("--rows", default=str(SWEEP / "gate.json"))
    parser.add_argument("--parapets", default=str(SWEEP / "parapets.json"))
    parser.add_argument("--crowns", default=str(SWEEP / "crowns.json"))
    parser.add_argument("--gate", type=float, default=0.95, help="minimum mean IoU")
    # OFF by default, and it must stay off unless someone re-derives it. pokeout's
    # `outside` is the WORST SINGLE LEVEL's spill, not the building's: the applied
    # Cerulean Tower (fbx_4_-9770_4222_-4948) scores 97.8% on it while its mean
    # IoU is 0.977. A 5% spill gate would have refused a building the map owner
    # approved by eye. Mean IoU is what the sector runs actually gated on.
    parser.add_argument("--spill", type=float, default=1.01,
                        help="max worst-level share outside the FBX; off by default")
    parser.add_argument("--size", type=int, default=25, help="buildings per chunk")
    args = parser.parse_args()

    plans = load_plans(Path(args.plans))
    kept, dropped, unmeasured = gate(plans, Path(args.rows), args.gate, args.spill)
    print(f"{len(plans)} plans -> {len(kept)} pass the gate, {len(dropped)} dropped, "
          f"{len(unmeasured)} kept but UNMEASURED (the FBX has holes where their levels sit)")
    (SWEEP / "unmeasured.txt").write_text("\n".join(sorted(unmeasured)) + "\n")
    for pid, why in dropped[:20]:
        print(f"  DROP {pid}: {why}")
    if len(dropped) > 20:
        print(f"  ... and {len(dropped) - 20} more")

    parapets = json.loads(Path(args.parapets).read_text()) if Path(args.parapets).exists() else {}
    crowns = json.loads(Path(args.crowns).read_text()) if Path(args.crowns).exists() else {}
    print(f"crown data: {len(parapets)} classified, {len(crowns)} with triangles")

    CHUNKS.mkdir(parents=True, exist_ok=True)
    for stale in CHUNKS.glob("*.json"):
        stale.unlink()

    groups = chunk_order(kept, args.size)
    width = max(2, len(str(len(groups))))
    manifest = []
    for index, ids in enumerate(groups, start=1):
        name = f"chunk_{index:0{width}d}"
        doc = {
            "name": name,
            "plans": [kept[pid] for pid in ids],
            "parapets": {pid: parapets[pid] for pid in ids if pid in parapets},
            "crowns": {pid: crowns[pid] for pid in ids if pid in crowns
                       and parapets.get(pid, {}).get("interesting")},
        }
        path = CHUNKS / f"{name}.json"
        path.write_text(json.dumps(doc))
        greys = sum(len(kept[pid]["sourceInfo"]["replaces"]) for pid in ids)
        shells = len(doc["crowns"])
        manifest.append({"name": name, "buildings": len(ids), "greys": greys,
                         "shells": shells, "kb": round(path.stat().st_size / 1024)})
        print(f"  {name}: {len(ids)} buildings, {greys} greys, {shells} shell crowns, "
              f"{manifest[-1]['kb']} KB")

    (SWEEP / "manifest.json").write_text(json.dumps(manifest, indent=1))
    total = sum(m["greys"] for m in manifest)
    print(f"\n{len(manifest)} chunks -> {CHUNKS}")
    print(f"{sum(m['buildings'] for m in manifest)} buildings replacing {total} greys")
    print(f"largest chunk {max(m['kb'] for m in manifest)} KB")


if __name__ == "__main__":
    main()
