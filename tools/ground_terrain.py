"""The ground as Roblox TERRAIN: zero parts, smooth slopes.

Studio's smooth terrain stores an occupancy per 4-stud voxel, and the mesher
places the surface INSIDE a voxel by it -- so a height field written as
fractional occupancy gives a smooth, sub-voxel ground, not 4-stud stairs (the
failed import never used that). The part-built TIN of the same surface was
50-97k wedges; this is none.

Surface per voxel column (heights at the voxel centre):
  * inside a grounded building's footprint: its floor-1 top less UNDER studs
    (hidden inside the floor slab, which is 5.36 thick);
  * elsewhere the STREET surface: the pinned height field blurred by
    STREET_SIGMA and capped by a cone of CONE studs per stud above every nearby
    floor, so the street eases to a lower building instead of burying it.

  python tools/ground_terrain.py   -> source_slices/ground/terrain/chunk_I_J.json + index.json
Built by src/server/GroundTerrain.luau (WriteVoxels, one chunk per call).
"""
from pathlib import Path
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices" / "ground"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

VOXEL = 4.0
CHUNK = 128          # voxels per chunk side (512 studs)
STREET_SIGMA = 32.0
CONE = 0.5
UNDER = 1.0          # studs under a floor top inside its footprint (pins are already floor - 0.1)
DEPTH = 12.0         # studs of solid terrain below the lowest surface in a chunk


def main():
    d = np.load(DATA / "heights.npz")
    H, known, hx0, hz0, cell = d["H"], d["known"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    floors = np.where(known, H, np.inf)
    street = ndimage.gaussian_filter(H, STREET_SIGMA / cell, mode="nearest")
    U = floors.copy()
    step, diag = CONE * cell, CONE * cell * 2 ** 0.5
    for _ in range(400):
        p = np.pad(U, 1, mode="edge")
        new = np.minimum.reduce([U, p[:-2, 1:-1] + step, p[2:, 1:-1] + step, p[1:-1, :-2] + step, p[1:-1, 2:] + step,
                                 p[:-2, :-2] + diag, p[:-2, 2:] + diag, p[2:, :-2] + diag, p[2:, 2:] + diag])
        if np.array_equal(new, U):
            break
        U = new
    street = np.minimum(street, U)
    street = np.minimum(ndimage.gaussian_filter(street, 2.0, mode="nearest"), U)
    S = np.where(known, H - (UNDER - 0.1), street)

    # voxel columns, aligned to the 4-stud terrain grid
    vx0 = math.ceil(hx0 / VOXEL) * VOXEL
    vz0 = math.ceil(hz0 / VOXEL) * VOXEL
    vx1 = math.floor((hx0 + (H.shape[0] - 1) * cell) / VOXEL) * VOXEL
    vz1 = math.floor((hz0 + (H.shape[1] - 1) * cell) / VOXEL) * VOXEL
    nx, nz = int((vx1 - vx0) / VOXEL), int((vz1 - vz0) / VOXEL)
    cx = vx0 + (np.arange(nx) + 0.5) * VOXEL
    cz = vz0 + (np.arange(nz) + 0.5) * VOXEL
    fi = (cx - hx0) / cell
    fj = (cz - hz0) / cell
    I, J = np.meshgrid(fi, fj, indexing="ij")
    top = ndimage.map_coordinates(S, [I, J], order=1, mode="nearest")
    out = DATA / "terrain"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.json"):
        f.unlink()
    names = []
    for a in range(0, nx, CHUNK):
        for b in range(0, nz, CHUNK):
            t = top[a:a + CHUNK, b:b + CHUNK]
            y0 = math.floor((t.min() - DEPTH) / VOXEL) * VOXEL
            name = f"chunk_{a // CHUNK}_{b // CHUNK}"
            (out / f"{name}.json").write_text(json.dumps({
                "name": name, "x0": vx0 + a * VOXEL, "z0": vz0 + b * VOXEL, "y0": y0,
                "nx": int(t.shape[0]), "nz": int(t.shape[1]),
                # column-major: heights[i * nz + k]
                "h": [round(float(v), 2) for v in t.reshape(-1)]}))
            names.append(name)
    (out / "index.json").write_text(json.dumps(names))
    gx, gz = np.gradient(top, VOXEL)
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    print(f"{nx} x {nz} voxel columns, x {vx0:.0f}..{vx1:.0f} z {vz0:.0f}..{vz1:.0f}; "
          f"surface {top.min():.1f}..{top.max():.1f}; slope median {np.median(slope):.1f}, "
          f"p95 {np.percentile(slope, 95):.1f} deg -> {len(names)} chunks in {out}")


if __name__ == "__main__":
    main()
