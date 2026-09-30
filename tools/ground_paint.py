"""Paint map for the ground: which terrain columns are street, pavement or
under a building, from the LIVE ground-floor footprints.

In Shibuya almost all open ground between buildings is paved street, so open
ground is Asphalt, a SIDEWALK-wide band along every building is Pavement, and
columns under a footprint are left alone. The road PARTS sit on top of this;
wherever they cannot go (a pinch, a plaza, a gap) the ground is still road.

One file per GroundTerrain chunk (same 512-stud grid), 128 rows of 128 chars:
  a = asphalt, s = pavement, b = under a building, - = outside the city
  python tools/ground_paint.py   -> source_slices/ground/paint/chunk_i_k.txt
"""
import json
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

D = ROOT / "source_slices" / "ground"
SIDEWALK = 8.0      # studs of pavement along every building (road_fit keeps MARGIN 2 + SIDEWALK_BAND 6 clear)
CITY_MARGIN = 150.0


def main():
    lf = np.load(D / "live_footprints.npz")
    M, x0, z0, c = lf["mask"], float(lf["x0"]), float(lf["z0"]), float(lf["cell"])
    dist = ndimage.distance_transform_edt(~M) * c
    city = dist <= CITY_MARGIN
    out = D / "paint"
    out.mkdir(exist_ok=True)
    index = json.loads((D / "terrain" / "index.json").read_text())
    counts = {"a": 0, "s": 0, "b": 0, "-": 0}
    for name in index:
        ch = json.loads((D / "terrain" / f"{name}.json").read_text())
        rows = []
        for i in range(ch["nx"]):
            x = ch["x0"] + (i + 0.5) * 4
            row = []
            for k in range(ch["nz"]):
                z = ch["z0"] + (k + 0.5) * 4
                mi, mj = int((x - x0) / c), int((z - z0) / c)
                if not (0 <= mi < M.shape[0] and 0 <= mj < M.shape[1]) or not city[mi, mj]:
                    v = "-"
                elif M[mi, mj]:
                    v = "b"
                elif dist[mi, mj] <= SIDEWALK:
                    v = "s"
                else:
                    v = "a"
                row.append(v)
                counts[v] += 1
            rows.append("".join(row))
        (out / f"{name}.txt").write_text("\n".join(rows))
    tot = sum(counts.values())
    print(f"{len(index)} chunks: asphalt {counts['a']/tot:.0%}, pavement {counts['s']/tot:.0%}, "
          f"under buildings {counts['b']/tot:.0%}, outside {counts['-']/tot:.0%}")


if __name__ == "__main__":
    main()
