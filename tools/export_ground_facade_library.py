"""Convert the Studio-exported draft library JSON into a draggable .rbxmx.

Run: python tools/export_ground_facade_library.py
Only serialises the classes/properties used by this facade kit. Not a map exporter.
"""
import base64
import json
import pathlib
import struct
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tools/source_slices/ground_facade_library.json"
TARGET = ROOT / "assets/GroundFacadeDraftLibrary.rbxmx"


def attribute_bytes(attrs):
    def string(value):
        encoded = value.encode("utf-8")
        return struct.pack("<I", len(encoded)) + encoded

    data = struct.pack("<I", len(attrs))
    for key, value in sorted(attrs.items()):
        data += string(key)
        if isinstance(value, bool):
            data += bytes((3, int(value)))
        elif isinstance(value, (int, float)):
            data += bytes((6,)) + struct.pack("<d", value)
        elif isinstance(value, str):
            data += bytes((2,)) + string(value)
        else:
            raise ValueError(f"Unsupported attribute {key}: {value!r}")
    return base64.b64encode(data).decode("ascii")


def scalar(props, kind, name, value):
    node = ET.SubElement(props, kind, name=name)
    node.text = str(value).lower() if isinstance(value, bool) else str(value)


def vector(props, name, value):
    node = ET.SubElement(props, "Vector3", name=name)
    for key, v in zip(("X", "Y", "Z"), value):
        ET.SubElement(node, key).text = str(v)


def cframe(props, name, value, optional=False):
    node = ET.SubElement(props, "OptionalCoordinateFrame" if optional else "CoordinateFrame", name=name)
    if optional:
        node = ET.SubElement(node, "CFrame")
    for key, v in zip(("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"), value):
        ET.SubElement(node, key).text = str(v)


def udim(props, name, value):
    node = ET.SubElement(props, "UDim", name=name)
    for key, v in zip(("S", "O"), value):
        ET.SubElement(node, key).text = str(v)


def write_item(parent, row, counter):
    counter[0] += 1
    item = ET.SubElement(parent, "Item", {"class": row["class"], "referent": f"RBX{counter[0]}"})
    props = ET.SubElement(item, "Properties")
    scalar(props, "string", "Name", row["name"])
    if row.get("attributes"):
        scalar(props, "BinaryString", "AttributesSerialize", attribute_bytes(row["attributes"]))
    if row["class"] == "Model":
        cframe(props, "WorldPivotData", row["pivot"], optional=True)
    elif row["class"] == "Part":
        cframe(props, "CFrame", row["cframe"])
        vector(props, "size", row["size"])
        r, g, b = row["color"]
        scalar(props, "Color3uint8", "Color3uint8", (255 << 24) | (r << 16) | (g << 8) | b)
        for name in ("Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow"):
            scalar(props, "bool", name, row[name])
        for name in ("Transparency", "Reflectance"):
            scalar(props, "float", name, row[name])
        scalar(props, "token", "Material", row["material"])
        scalar(props, "token", "shape", row.get("shape", 1))
        scalar(props, "token", "TopSurface", 0)
        scalar(props, "token", "BottomSurface", 0)
        scalar(props, "BinaryString", "Tags", base64.b64encode("\0".join(row.get("tags", ["NoCSG"])).encode()).decode())
    elif row["class"] == "SurfaceGui":
        for name in ("Face", "SizingMode"):
            scalar(props, "token", name, row[name])
        for name in ("PixelsPerStud", "LightInfluence", "MaxDistance"):
            scalar(props, "float", name, row[name])
        scalar(props, "bool", "AlwaysOnTop", False)
    elif row["class"] == "TextLabel":
        scalar(props, "string", "Text", row["Text"])
        scalar(props, "token", "Font", row["Font"])
        for name in ("TextScaled", "TextWrapped"):
            scalar(props, "bool", name, row[name])
        scalar(props, "float", "BackgroundTransparency", 1)
        size = ET.SubElement(props, "UDim2", name="Size")
        for key, value in (("XS", 1), ("XO", 0), ("YS", 1), ("YO", 0)):
            ET.SubElement(size, key).text = str(value)
        color = ET.SubElement(props, "Color3", name="TextColor3")
        for key, value in zip(("R", "G", "B"), row["TextColor3"]):
            ET.SubElement(color, key).text = str(value)
    elif row["class"] == "UIPadding":
        for name in ("PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom"):
            udim(props, name, row[name])
    elif row["class"] != "Folder":
        raise ValueError(f"Unsupported facade class: {row['class']}")
    for child in row.get("children", []):
        write_item(item, child, counter)


def main():
    row = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert row["name"] == "GroundFacadeDraftLibrary"
    count = len(row["children"])
    assert count == 53
    root = ET.Element("roblox", {"version": "4"})
    counter = [0]
    write_item(root, row, counter)
    ET.indent(root)
    ET.ElementTree(root).write(TARGET, encoding="utf-8", xml_declaration=True)
    print(f"Saved {TARGET.name}: {count} templates, {counter[0]} instances")


if __name__ == "__main__":
    main()
