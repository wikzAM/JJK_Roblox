"""Read-only hierarchy census of an existing Studio binary recovery file.

Format reference: https://github.com/rojo-rbx/rbx-dom/blob/master/docs/binary.md
Install zstandard in your environment, or .tools/backup_reader. This is a
limited structural census, not a full place validator or a Studio open test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".tools/backup_reader"))
import zstandard


def string(data, offset):
    n = struct.unpack_from("<I", data, offset)[0]
    end = offset + 4 + n
    assert end <= len(data)
    return data[offset + 4:end].decode("utf-8", errors="strict"), end


def refs(data, count):
    assert len(data) == count * 4
    previous = 0
    out = []
    for i in range(count):
        number = (data[i] << 24) | (data[count+i] << 16) | (data[2*count+i] << 8) | data[3*count+i]
        previous += (number >> 1) ^ -(number & 1)
        out.append(previous)
    return out


def lz4(data, expected):
    # Raw LZ4 block fallback; Studio currently emits Zstandard chunks here.
    out = bytearray()
    i = 0
    while i < len(data):
        token = data[i]
        i += 1
        literal = token >> 4
        if literal == 15:
            while True:
                b = data[i]; i += 1; literal += b
                if b != 255: break
        out.extend(data[i:i+literal]); i += literal
        if i == len(data): break
        distance = int.from_bytes(data[i:i+2], "little"); i += 2
        assert 0 < distance <= len(out)
        length = (token & 15) + 4
        if (token & 15) == 15:
            while True:
                b = data[i]; i += 1; length += b
                if b != 255: break
        for _ in range(length): out.append(out[-distance])
    assert len(out) == expected
    return bytes(out)


def inspect(path):
    classes, names, parents = {}, {}, {}
    wanted = {"Model", "Folder", "Workspace", "ServerStorage"}
    chunks = 0
    with path.open("rb") as stream:
        header = stream.read(32)
        assert header[:14] == b"<roblox!\x89\xff\r\n\x1a\n"
        assert struct.unpack_from("<H", header, 14)[0] == 0
        class_count, instance_count = struct.unpack_from("<II", header, 16)
        while True:
            raw = stream.read(16)
            assert len(raw) == 16, "Missing final chunk"
            kind, compressed, uncompressed, reserved = struct.unpack("<4sIII", raw)
            payload = stream.read(compressed or uncompressed)
            assert len(payload) == (compressed or uncompressed)
            chunks += 1
            if kind not in {b"INST", b"PROP", b"PRNT"}:
                if kind.startswith(b"END"): break
                continue
            if compressed:
                payload = (zstandard.ZstdDecompressor().decompress(payload, max_output_size=uncompressed)
                           if payload.startswith(b"\x28\xb5\x2f\xfd") else lz4(payload, uncompressed))
            assert len(payload) == uncompressed
            if kind == b"INST":
                ident = struct.unpack_from("<I", payload)[0]
                name, pos = string(payload, 4)
                count = struct.unpack_from("<I", payload, pos+1)[0]
                members = refs(payload[pos+5:pos+5+count*4], count) if name in wanted else None
                assert ident not in classes
                classes[ident] = (name, count, members)
            elif kind == b"PROP":
                ident = struct.unpack_from("<I", payload)[0]
                prop, pos = string(payload, 4)
                name, count, members = classes[ident]
                if prop == "Name" and name in wanted:
                    assert payload[pos] == 1
                    pos += 1
                    for referent in members:
                        value, pos = string(payload, pos)
                        names[referent] = value
            elif kind == b"PRNT":
                assert payload[0] == 0
                count = struct.unpack_from("<I", payload, 1)[0]
                assert count == instance_count
                children = refs(payload[5:5+count*4], count)
                owners = refs(payload[5+count*4:], count)
                parents = dict(zip(children, owners))
        assert len(classes) == class_count
        assert sum(c[1] for c in classes.values()) == instance_count
        assert len(parents) == instance_count
    buildings = {r for r, name in names.items() if name == "Buildings" and names.get(parents.get(r)) == "Workspace"}
    models = {r for r, name in names.items() if name.startswith("Building") and parents.get(r) in buildings}
    facades = [r for r, name in names.items() if name == "GroundFacadePilot" and parents.get(r) in models]
    return {"file": str(path), "bytes": path.stat().st_size,
            "sha256": hashlib.file_digest(path.open("rb"), "sha256").hexdigest(),
            "instances": instance_count, "classes": class_count, "chunks": chunks,
            "workspaceBuildingModels": len(models), "liveGroundFacadeRoots": len(facades),
            "scope": "Hierarchy census only; no Studio reopening, geometry or script validation"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("place", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = inspect(args.place)
    encoded = json.dumps(result, indent=2)
    if args.output: args.output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
