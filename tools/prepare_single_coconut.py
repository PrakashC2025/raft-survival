"""Keep one complete palm from the owner's two-stem GLB, preserving its artwork.

Run from the project root. Uses only Python's standard library; regeneration
never edits the supplied original. Connected parts are assigned to the closest
trunk crown, including complete fronds rather than clipping their triangles.
"""
import collections
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "models/coconut_palm.glb"
OUTPUT = ROOT / "models/coconut_palm_single.glb"
source_bytes = SOURCE.read_bytes()
json_size = struct.unpack_from("<I", source_bytes, 12)[0]
document = json.loads(source_bytes[20:20 + json_size])
source_binary = source_bytes[28 + json_size:]
formats = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}
dimensions = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    fmt = "<" + formats[accessor["componentType"]] * dimensions[accessor["type"]]
    stride = view.get("byteStride", struct.calcsize(fmt))
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return [struct.unpack_from(fmt, source_binary, offset + i * stride)
            for i in range(accessor["count"])]


def connected_parts(positions, indices):
    parents = list(range(len(positions)))

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def merge(left, right):
        parents[find(left)] = find(right)

    welded = {}
    for index, position in enumerate(positions):
        key = tuple(round(value, 5) for value in position)
        if key in welded:
            merge(index, welded[key])
        else:
            welded[key] = index
    for index in range(0, len(indices), 3):
        merge(indices[index], indices[index + 1])
        merge(indices[index], indices[index + 2])
    parts = collections.defaultdict(list)
    for index in sorted(set(indices)):
        parts[find(index)].append(index)
    return list(parts.values())


trunk = document["meshes"][0]["primitives"][0]
trunk_positions = read_accessor(trunk["attributes"]["POSITION"])
trunk_parts = connected_parts(trunk_positions, [p[0] for p in read_accessor(trunk["indices"])])
assert len(trunk_parts) == 2, "Source must contain the owner's two separate stems"
crowns = []
for part in trunk_parts:
    top = max(trunk_positions[index][1] for index in part)
    points = [trunk_positions[index] for index in part if trunk_positions[index][1] > top - 0.01]
    crowns.append(tuple(sum(point[axis] for point in points) / len(points) for axis in range(3)))
chosen = max(range(len(crowns)), key=lambda index: crowns[index][1])
binary = bytearray()
views, accessors, report = [], [], {}


def write_accessor(values, original, target):
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    fmt = "<" + formats[original["componentType"]] * dimensions[original["type"]]
    for value in values:
        binary.extend(struct.pack(fmt, *value))
    views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset, "target": target})
    accessor = {"bufferView": len(views) - 1, "componentType": original["componentType"],
                "count": len(values), "type": original["type"]}
    if original.get("normalized"):
        accessor["normalized"] = True
    if "min" in original or "max" in original:
        accessor["min"] = [min(value[axis] for value in values) for axis in range(len(values[0]))]
        accessor["max"] = [max(value[axis] for value in values) for axis in range(len(values[0]))]
    accessors.append(accessor)
    return len(accessors) - 1


for mesh in document["meshes"]:
    for primitive in mesh["primitives"]:
        positions = read_accessor(primitive["attributes"]["POSITION"])
        indices = [p[0] for p in read_accessor(primitive["indices"])]
        parts = connected_parts(positions, indices)
        kept = set()
        kept_count = 0
        for part in parts:
            distances = [min(sum((positions[index][axis] - crown[axis]) ** 2 for axis in range(3))
                             for index in part) for crown in crowns]
            if min(range(len(crowns)), key=lambda index: distances[index]) == chosen:
                kept.update(part)
                kept_count += 1
        assert kept, f"Missing retained geometry in {mesh['name']}"
        used = sorted(kept)
        remap = {old: new for new, old in enumerate(used)}
        kept_indices = [(remap[index],) for index in indices if index in kept]
        assert len(kept_indices) % 3 == 0
        for name, old_index in list(primitive["attributes"].items()):
            values = read_accessor(old_index)
            primitive["attributes"][name] = write_accessor([values[index] for index in used],
                                                          document["accessors"][old_index], 34962)
        primitive["indices"] = write_accessor(kept_indices, document["accessors"][primitive["indices"]], 34963)
        report[mesh["name"]] = {"parts": kept_count, "triangles": len(kept_indices) // 3}
assert report["Tree_0_Trunk"]["parts"] == 1
for index, image in enumerate(document.get("images", [])):
    # Reuse the canonical imported textures, avoiding a second GPU texture set
    # when an island's original palm and a planted palm are visible together.
    texture = ROOT / f"models/coconut_palm_{index}.png"
    assert texture.is_file(), f"Import the supplied original first: missing {texture}"
    image.clear()
    image["uri"] = texture.name
document["accessors"], document["bufferViews"] = accessors, views
document["buffers"] = [{"byteLength": len(binary)}]
while len(binary) % 4:
    binary.append(0)
encoded = json.dumps(document, separators=(",", ":")).encode()
encoded += b" " * (-len(encoded) % 4)
OUTPUT.write_bytes(struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
                   + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
                   + struct.pack("<II", len(binary), 0x004E4942) + binary)
record = {"source": "Owner-supplied models/coconut_palm.glb",
          "source_sha256": hashlib.sha256(source_bytes).hexdigest(),
          "change": "Retain taller stem and only its complete collar, fronds, leaf stems and crown; textures unchanged",
          "rights": "Inherits the supplied asset's rights; no new external asset or license claim",
          "generator": "tools/prepare_single_coconut.py", "geometry": report}
OUTPUT.with_suffix(".source.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report))
