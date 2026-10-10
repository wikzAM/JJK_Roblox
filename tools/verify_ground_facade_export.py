"""Verify the library through both XML export and the built Rojo preview place.

Checks asset contracts against the Studio snapshot, including round columns,
Japanese text, baseline pivots, attributes, part flags and NoCSG tags.
Run after export_ground_facade_library.py and the facade preview Rojo build.
"""
import base64
from collections import Counter
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def prop(item, name):
    return next((p for p in item.find("Properties") if p.get("name") == name), None)


def attrs(item):
    node = prop(item, "AttributesSerialize")
    raw = memoryview(base64.b64decode(node.text or "")) if node is not None else memoryview(b"")
    if not raw:
        return {}
    offset = 0

    def read(fmt):
        nonlocal offset
        value = struct.unpack_from(fmt, raw, offset)[0]
        offset += struct.calcsize(fmt)
        return value

    def string():
        nonlocal offset
        size = read("<I")
        text = bytes(raw[offset:offset + size]).decode("utf-8")
        offset += size
        return text

    out = {}
    for _ in range(read("<I")):
        key, kind = string(), read("<B")
        if kind == 2:
            out[key] = string()
        elif kind == 3:
            out[key] = bool(read("<B"))
        elif kind == 6:
            out[key] = read("<d")
        else:
            raise AssertionError(f"Unsupported export attribute type {kind}")
    assert offset == len(raw)
    return out


def descendants(row):
    for child in row.get("children", []):
        yield child
        yield from descendants(child)


def numbers(node):
    return tuple(float(p.text) for p in node)


def source_shape(row):
    return (row["name"], tuple(row["size"]), tuple(row["cframe"]), row["shape"], row["material"])


def exported_shape(item):
    return (prop(item, "Name").text, numbers(prop(item, "size")),
            numbers(prop(item, "CFrame")), int(prop(item, "shape").text),
            int(prop(item, "Material").text))


def verify(path, source):
    tree = ET.parse(path)
    library = next(i for i in tree.iter("Item")
                   if prop(i, "Name") is not None and prop(i, "Name").text == source["name"])
    assert attrs(library) == source["attributes"]
    models = {prop(i, "Name").text: i for i in library.findall("Item")}
    assert len(models) == len(source["children"]) == 53
    total = columns = 0
    for row in source["children"]:
        model = models[row["name"]]
        assert attrs(model) == row["attributes"], row["name"]
        pivot = prop(model, "WorldPivotData")
        assert numbers(pivot.find("CFrame")) == tuple(row["pivot"]), row["name"]
        expected = [r for r in descendants(row) if r["class"] == "Part"]
        actual = [i for i in model.iter("Item") if i.get("class") == "Part"]
        assert len(expected) == len(actual), row["name"]
        # Rojo normalises numeric XML to float32; compare with a small tolerance
        # rather than quantising across a rounding boundary.
        for a, b in zip(sorted(map(source_shape, expected)), sorted(map(exported_shape, actual))):
            assert (a[0], a[3], a[4]) == (b[0], b[3], b[4]), row["name"]
            assert all(abs(x-y) < .0001 for x, y in zip(a[1]+a[2], b[1]+b[2])), row["name"]
        for part in actual:
            assert prop(part, "Anchored").text == "true"
            assert prop(part, "CanQuery").text == "true" or prop(part,"Name").text == "PrivacyFilm" or attrs(part).get("GlassAttachedOverlay")
            assert prop(part, "CanTouch").text == "false"
            assert b"NoCSG" in base64.b64decode(prop(part, "Tags").text)
            assert "FacadePieceKind" in attrs(part)
            if "GlassPaneId" in attrs(part):
                assert b"GlassPane" in base64.b64decode(prop(part,"Tags").text)
                assert attrs(part)["GlassState"] == 1
                assert "GlassBaseTransparency" in attrs(part)
            if prop(part, "Name").text in {"RoundPilotis", "RoundEntryColumn"}:
                assert int(prop(part, "shape").text) != 1
                columns += 1
        expected_text = Counter(r["Text"] for r in descendants(row) if r["class"] == "TextLabel")
        actual_text = Counter(prop(i, "Text").text for i in model.iter("Item") if i.get("class") == "TextLabel")
        assert actual_text == expected_text, row["name"]
        total += len(actual)
    expected_total=sum(1 for r in descendants(source) if r["class"]=="Part")
    assert total == expected_total and columns == 4
    print(f"{path.name}: 53 templates, {total} parts, {columns} round columns; geometry/text/pivots/tags retained")


if __name__ == "__main__":
    source = json.loads((ROOT / "tools/source_slices/ground_facade_library.json").read_text(encoding="utf-8"))
    for name in ("GroundFacadeDraftLibrary.rbxmx", "GroundFacadeDraftsPreview.rbxlx"):
        verify(ROOT / "assets" / name, source)
