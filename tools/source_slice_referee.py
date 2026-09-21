"""Old vs new for regenerated plans, judged against the FBX ROOF ENVELOPE.

The wall-cut gate (source_slice_pokeout.py) scores a floor against the FBX's
wall cut at that height -- the very data that is patchy in this PLATEAU export.
Once floors follow the building's level curve up to its real roof, the gate
refused 488 of 1,218 changed plans, largely for reaching heights where the walls
stop. This referee scores both versions of a building against the envelope
instead:

  height  -- the plan's top against the FBX roof over its footprint (95th pct);
  spill   -- the worst floor's share lying where no FBX roof stands above it,
             with a one-cell edge tolerance (a 2-stud grid otherwise reads ~20%
             "spill" on a small building from rounding alone).

A new plan is accepted if it gets closer to the roof without spilling more, or
spills clearly less without losing height.

  python tools/source_slice_referee.py <newPlansDir> --tag NAME [--ids FILE]

Writes sweep/chunks/rebuild_<NAME>_NN.json for SourceSliceSweepApply.Rebuild.
"""
from pathlib import Path
import argparse
import glob
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
CHUNKS = DATA / "sweep" / "chunks"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
import scipy.ndimage as nd  # noqa: E402
from shapely import contains_xy, prepare  # noqa: E402
import source_slice_orphans as O  # noqa: E402
from source_slice_roofs import roof_triangles  # noqa: E402
from source_slice_heightmap import rasterise  # noqa: E402

CELL = 2.0


class Envelope:
    def __init__(self):
        tri = np.load(DATA / "world_triangles.npz")["triangles"]
        self.x0 = math.floor(tri[:, :, 0].min()) - 8
        self.z0 = math.floor(tri[:, :, 2].min()) - 8
        self.nx = int((tri[:, :, 0].max() + 8 - self.x0) / CELL) + 1
        self.nz = int((tri[:, :, 2].max() + 8 - self.z0) / CELL) + 1
        self.H = rasterise(roof_triangles(tri), self.x0, self.z0, self.nx, self.nz, CELL)

    def score(self, plan):
        """(height error in studs, worst-floor spill share)."""
        o = plan["origin"]
        levels = list(O.world_levels(plan))
        foot = levels[0]
        bx0, bz0, bx1, bz1 = foot.bounds
        i0 = max(0, int((bx0 - self.x0) / CELL)); i1 = min(self.nx - 1, int((bx1 - self.x0) / CELL) + 1)
        j0 = max(0, int((bz0 - self.z0) / CELL)); j1 = min(self.nz - 1, int((bz1 - self.z0) / CELL) + 1)
        PX, PZ = np.meshgrid(self.x0 + (np.arange(i0, i1 + 1) + .5) * CELL,
                             self.z0 + (np.arange(j0, j1 + 1) + .5) * CELL, indexing="ij")
        sub = self.H[i0:i1 + 1, j0:j1 + 1]
        prepare(foot)
        hs = sub[contains_xy(foot, PX, PZ) & np.isfinite(sub)]
        fbx_top = float(np.percentile(hs, 95)) if len(hs) else float("nan")
        last = plan["levels"][-1]
        top = o["y"] + last["y"] + last["thickness"]
        spill = 0.0
        for lv, poly in zip(plan["levels"], levels):
            prepare(poly)
            m = contains_xy(poly, PX, PZ)
            if m.sum() < 10:
                continue
            y = o["y"] + lv["y"] + lv["thickness"]
            inside = nd.binary_dilation(sub > y - 2.0, iterations=1)
            spill = max(spill, float((m & ~inside).sum() / m.sum()))
        return top - fbx_top, spill


def live_plans():
    """What is in the map: sector plans, sweep chunks overlaid by every rebuild,
    plus the current orphan set."""
    plans = O.live_plans()
    for f in sorted(glob.glob(str(CHUNKS / "orphans_lc_*.json"))):
        for p in json.loads(Path(f).read_text())["plans"]:
            plans[p["id"]] = p
    return plans


def accept(old, new):
    (dh_o, sp_o), (dh_n, sp_n) = old, new
    closer = abs(dh_n) < abs(dh_o) - 4.0 and sp_n <= sp_o + 0.02
    cleaner = sp_n < sp_o - 0.05 and abs(dh_n) <= abs(dh_o) + 4.0
    return closer or cleaner


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("plans")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--size", type=int, default=25)
    args = parser.parse_args()
    prefix = f"rebuild_{args.tag}_"
    if any(CHUNKS.glob(prefix + "*.json")):
        raise SystemExit(f"{prefix}* already exists -- pick a new --tag")

    env = Envelope()
    live = live_plans()
    new_plans = [json.loads(p.read_text()) for p in sorted(Path(args.plans).glob("*.json"))]
    take, rows = [], []
    for new in new_plans:
        old = live.get(new["id"])
        if old is None:
            continue
        so, sn = env.score(old), env.score(new)
        ok = accept(so, sn)
        rows.append((new["id"], so, sn, ok))
        if ok:
            take.append(new)
    for n in range(0, len(take), args.size):
        name = f"{prefix}{n // args.size + 1:02d}"
        (CHUNKS / f"{name}.json").write_text(json.dumps(
            {"name": name, "plans": take[n:n + args.size], "parapets": {}, "crowns": {}}))
    acc = [r for r in rows if r[3]]
    print(f"{len(rows)} regenerated plans compared: {len(acc)} better against the FBX envelope, "
          f"{len(rows) - len(acc)} kept as they are")
    if acc:
        print("  accepted: median |height error| %.0f -> %.0f studs, median worst spill %.0f%% -> %.0f%%" % (
            np.median([abs(r[1][0]) for r in acc]), np.median([abs(r[2][0]) for r in acc]),
            100 * np.median([r[1][1] for r in acc]), 100 * np.median([r[2][1] for r in acc])))
    print(f"  -> {math.ceil(len(take) / args.size)} chunks {prefix}NN")


if __name__ == "__main__":
    main()
