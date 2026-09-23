"""JGD2011 / Japan Plane Rectangular CS IX (EPSG:6677) <-> latitude/longitude.

The PLATEAU tiles the map was built from are in this projection, so the exact
georeference runs through it. Transverse Mercator on GRS80, origin 36 N,
139 deg 50' E, scale factor 0.9999 (pyproj is not installed here; these are the
standard series, good to millimetres over Tokyo).
"""
import math

A = 6378137.0                      # GRS80
F = 1 / 298.257222101
E2 = F * (2 - F)
K0 = 0.9999
LAT0 = math.radians(36.0)
LON0 = math.radians(139 + 50 / 60)


def _meridian_arc(lat):
    e2 = E2
    A0 = 1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256
    A2 = 3 / 8 * (e2 + e2 ** 2 / 4 + 15 * e2 ** 3 / 128)
    A4 = 15 / 256 * (e2 ** 2 + 3 * e2 ** 3 / 4)
    A6 = 35 * e2 ** 3 / 3072
    return A * (A0 * lat - A2 * math.sin(2 * lat) + A4 * math.sin(4 * lat) - A6 * math.sin(6 * lat))


def to_xy(lat_deg, lon_deg):
    """(lat, lon) -> (easting, northing) metres in CS IX."""
    lat, lon = math.radians(lat_deg), math.radians(lon_deg)
    n = A / math.sqrt(1 - E2 * math.sin(lat) ** 2)
    t = math.tan(lat)
    eta2 = (E2 / (1 - E2)) * math.cos(lat) ** 2
    dl = lon - LON0
    c = math.cos(lat)
    x = K0 * (_meridian_arc(lat) - _meridian_arc(LAT0)
              + n * c ** 2 * t * dl ** 2 / 2
              + n * c ** 4 * t * (5 - t ** 2 + 9 * eta2 + 4 * eta2 ** 2) * dl ** 4 / 24
              + n * c ** 6 * t * (61 - 58 * t ** 2 + t ** 4 + 270 * eta2 - 330 * t ** 2 * eta2) * dl ** 6 / 720)
    y = K0 * (n * c * dl
              + n * c ** 3 * (1 - t ** 2 + eta2) * dl ** 3 / 6
              + n * c ** 5 * (5 - 18 * t ** 2 + t ** 4 + 14 * eta2 - 58 * t ** 2 * eta2) * dl ** 5 / 120)
    return y, x                     # easting, northing


def to_latlon(easting, northing, iterations=6):
    """Inverse, by iterating to_xy (the area is small; this converges at once)."""
    lat, lon = 35.66, 139.70
    for _ in range(iterations):
        e, n = to_xy(lat, lon)
        de, dn = easting - e, northing - n
        lat += dn / 110900.0
        lon += de / (111320.0 * math.cos(math.radians(lat)))
    return lat, lon


if __name__ == "__main__":
    # tile 53393586's south-west corner, from its mesh code
    lat, lon = 35.65, 139.70
    print("tile 53393586 SW corner", lat, lon, "->", [round(v, 1) for v in to_xy(lat, lon)], "m (CS IX)")
    print("round trip:", [round(v, 6) for v in to_latlon(*to_xy(lat, lon))])
