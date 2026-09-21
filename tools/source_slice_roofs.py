"""Floor plates from ROOF faces: shared by the section builder and the height map.

A building's plate at height y is everywhere some roof sits above y. This needs
no closed walls, which this PLATEAU export often lacks, and it is monotone: a
roof above y is above every lower level too, so a plate from here can never be
larger than the one beneath it -- no mushroom caps, no pinched storeys.

Its one blind spot is an overhang: a flared crown projects over the shaft below
it. That is why wall sections stay first choice wherever they close, and the
roof envelope is the fallback.
"""
import numpy as np
from shapely.geometry import Polygon
from shapely.ops import unary_union

ROOF_NY = 0.5   # |normal.y| above this is a roof (ground faces sit below every plate)


def roof_triangles(triangles):
    n = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    mag = np.linalg.norm(n, axis=1)
    ny = np.abs(n[:, 1]) / np.maximum(mag, 1e-12)
    # The scan's winding is not consistent (see the crown work), so take |ny|.
    return triangles[(ny > ROOF_NY) & (mag > 1e-9)]


def clip_above(tri, yc):
    """XZ polygon of the part of a triangle at or above height yc, or None."""
    out = []
    for k in range(3):
        a, b = tri[k], tri[(k + 1) % 3]
        ina, inb = a[1] >= yc, b[1] >= yc
        if ina:
            out.append((a[0], a[2]))
        if ina != inb:
            t = (yc - a[1]) / (b[1] - a[1])
            out.append((a[0] + t * (b[0] - a[0]), a[2] + t * (b[2] - a[2])))
    if len(out) < 3:
        return None
    poly = Polygon(out)
    return poly.buffer(0) if poly.area > 1e-6 else None


def roof_plate(roofs, yc):
    """EXACT plate at height yc: the union of every roof face above it.

    Uses the building's own edges, so a diagonal wall stays one straight edge
    rather than the 1-stud staircase a raster gives (150-207 vertices per ring
    on PARCO, ~150 wedges a floor)."""
    pieces = [c for c in (clip_above(t, yc) for t in roofs) if c is not None]
    if not pieces:
        return None
    # Faces of one roof meet edge to edge; a hair of buffer closes float seams so
    # the union is one polygon rather than a mosaic of slivers.
    plate = unary_union([q.buffer(0.05, join_style=2) for q in pieces]).buffer(-0.05, join_style=2)
    # A union of hundreds of faces can come back topologically invalid, and the
    # next intersection then throws GEOSException (non-noded intersection) --
    # it stopped the first orphan pass. Snap to a 0.01-stud grid and repair.
    from shapely import make_valid, set_precision, union_all
    fixed = polygons(make_valid(set_precision(make_valid(plate), 0.01)))
    return union_all(fixed, grid_size=0.01) if fixed else None


def roofs_in(triangles, region):
    """Roof faces whose centre lies inside a (world XZ) region polygon."""
    roofs = roof_triangles(triangles)
    if region is None or region.is_empty or not len(roofs):
        return roofs
    from shapely import contains_xy, prepare
    prepare(region)
    centres = roofs.mean(axis=1)
    return roofs[contains_xy(region, centres[:, 0], centres[:, 2])]


def solid(geometry):
    """Holes filled. The builder takes exterior rings only, so a courtyard with a
    part inside it would emit an island inside its surround -- overlapping
    pieces. Courtyards were measured at 0.1% of plate area."""
    if geometry is None or geometry.is_empty:
        return geometry
    from shapely import make_valid, union_all
    filled = [make_valid(Polygon(p.exterior)) for p in polygons(geometry)]
    parts = [q for f in filled for q in polygons(f)]
    # grid_size keeps the union robust: an exterior ring off a repaired plate can
    # self-touch, and a plain union then throws "side location conflict".
    return union_all(parts, grid_size=0.01) if parts else None


def polygons(geometry):
    """The polygonal parts of any geometry. make_valid can hand back a
    GeometryCollection with stray lines or points, which the builder cannot use."""
    if geometry is None or geometry.is_empty:
        return []
    kind = geometry.geom_type
    if kind == "Polygon":
        return [geometry]
    if kind in ("MultiPolygon", "GeometryCollection"):
        return [q for g in geometry.geoms for q in polygons(g)]
    return []


# --------------------------------------------------------------------------
# LEVEL CURVES. The map owner's framing: treat a building's FBX shape as a
# 3-D function; each floor is its level curve -- the slice of the building at
# that height, bounded by its perimeter and FILLED inside it. The roof envelope
# is that slice (everywhere a roof sits above y), but PLATEAU's roof faces stop
# at seams and wall lines, which cut a slice into pieces: PARCO's tower floors
# were two plates 3.28 studs apart at every level, its podium up to seven.
# `slice_at` closes seams that narrow and fills the inside, so a floor is one
# shape per real mass. Real separations (a street, a courtyard wider than the
# seam) are left alone.

SEAM = 2.0   # studs: close gaps up to 2 x SEAM wide between roof faces


def slice_at(roofs, y, reach=None, seam=SEAM):
    """The building's level curve at height y, filled; None if empty."""
    plate = roof_plate(roofs, y)
    if plate is None or plate.is_empty:
        return None
    from shapely import union_all
    if reach is not None:
        parts = polygons(plate.intersection(reach, grid_size=0.01))
        if not parts:
            return None
        plate = union_all(parts, grid_size=0.01)
    closed = plate.buffer(seam, join_style=2).buffer(-seam, join_style=2)
    filled = solid(closed)
    if filled is None or filled.is_empty:
        return None
    if reach is not None:
        parts = polygons(filled.intersection(reach, grid_size=0.01))
        filled = union_all(parts, grid_size=0.01) if parts else None
    return filled


def main_roof(roofs, plate, low, high, reach=None, share=0.5, steps=24):
    """Height of the roof over most of `plate`: the highest y whose slice still
    covers `share` of it. Used to put a building's top slab AT its roof -- on a
    fixed storey grid the top slab otherwise lands up to a storey below it, and
    the median building came out 20.8 studs short of the FBX."""
    if plate is None or plate.is_empty or high <= low:
        return low
    need = share * plate.area
    for _ in range(steps):
        mid = (low + high) / 2
        s = slice_at(roofs, mid, reach)
        covered = s.intersection(plate).area if s is not None else 0.0
        if covered >= need:
            low = mid
        else:
            high = mid
    return low
