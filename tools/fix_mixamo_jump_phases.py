"""Trim the existing recorded jump to flight/landing; preserve geometry and other clips."""
from pathlib import Path
import bisect
import hashlib
import json
import math
import struct

root = Path(__file__).resolve().parents[1]
path = root / "models/mixamo_survivor.glb"
data = path.read_bytes()
json_size = struct.unpack_from("<I", data, 12)[0]
doc = json.loads(data[20:20 + json_size])
bin_size = struct.unpack_from("<I", data, 20 + json_size)[0]
binary = bytearray(data[28 + json_size:28 + json_size + bin_size])
source_jump = next(clip for clip in doc["animations"] if clip["name"] == "Jump")
root_curve = json.loads((root / "build/mixamo-jump-root.json").read_text())

def read(index):
    a = doc["accessors"][index]
    view = doc["bufferViews"][a["bufferView"]]
    components = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
    assert a["componentType"] == 5126
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", components * 4)
    return [struct.unpack_from("<" + "f" * components, binary, start + key * stride)
            for key in range(a["count"])]

def add(rows, kind):
    binary.extend(b"\0" * (-len(binary) % 4))
    offset = len(binary)
    for row in rows: binary.extend(struct.pack("<" + "f" * len(row), *row))
    view_index = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset})
    index = len(doc["accessors"])
    entry = {"bufferView": view_index, "componentType": 5126, "count": len(rows), "type": kind}
    if kind == "SCALAR": entry.update(min=[rows[0][0]], max=[rows[-1][0]])
    doc["accessors"].append(entry)
    return index

def multiply(a, b):
    x, y, z, w = a; X, Y, Z, W = b
    return (w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
            w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z)

def interpolate(times, rows, time, rotation=False):
    if len(times) == 1: return rows[0]
    left = max(0, min(len(times) - 2, bisect.bisect_right(times, time) - 1))
    weight = max(0, min(1, (time - times[left]) / (times[left+1] - times[left])))
    a, b = rows[left], rows[left+1]
    if rotation:
        dot = sum(x*y for x, y in zip(a, b))
        if dot < 0: b = tuple(-x for x in b); dot = -dot
        if dot < .9995:
            angle = math.acos(min(1, dot)); denom = math.sin(angle)
            wa = math.sin((1-weight)*angle)/denom; wb = math.sin(weight*angle)/denom
            return tuple(wa*x+wb*y for x, y in zip(a, b))
    result = tuple((1-weight)*x+weight*y for x, y in zip(a, b))
    if rotation:
        norm = math.sqrt(sum(x*x for x in result)); result = tuple(x/norm for x in result)
    return result

source_seconds = read(source_jump["samplers"][0]["input"])[-1][0]
if source_seconds < 2:
    raise SystemExit("Jump already trimmed; rebake original assets before repeating this repair.")
windows = {"Jump": (.57, 1.27), "Land": (1.27, 2.10)}
for name, (start, end) in windows.items():
    duration = end - start
    times = [key/30 for key in range(math.ceil(duration*30))] + [duration]
    input_index = add([(time,) for time in times], "SCALAR")
    output_clip = {"name": name, "channels": [], "samplers": []}
    for channel in source_jump["channels"]:
        target = channel["target"]; sampler = source_jump["samplers"][channel["sampler"]]
        source_times = [row[0] for row in read(sampler["input"])]
        source_rows = read(sampler["output"])
        rotation = target["path"] == "rotation"
        node = doc["nodes"][target["node"]]
        values = []
        for time in times:
            value = interpolate(source_times, source_rows, start + time, rotation)
            if node.get("name") == "Hips":
                if rotation:
                    rest = node.get("rotation", (0, 0, 0, 1))
                    inverse = (-rest[0], -rest[1], -rest[2], rest[3])
                    relative = multiply(value, inverse)
                    norm = math.hypot(relative[1], relative[3])
                    value = multiply(multiply((0,-relative[1]/norm,0,relative[3]/norm), relative), rest)
                elif name == "Land" and target["path"] == "translation":
                    original_y = interpolate([row[0] for row in root_curve],
                                             [tuple(row[1:]) for row in root_curve], start + time)[1]
                    value = (value[0], original_y, value[2])
            values.append(value)
        output_index = add(values, "VEC4" if rotation else "VEC3")
        output_clip["channels"].append({"sampler": len(output_clip["samplers"]), "target": target.copy()})
        output_clip["samplers"].append({"input": input_index, "output": output_index, "interpolation": "LINEAR"})
    index = next(i for i, clip in enumerate(doc["animations"]) if clip["name"] == name)
    doc["animations"][index] = output_clip
    print(name, "uses original", start, "to", end, "seconds; actor owns height/yaw.")

doc["buffers"][0]["byteLength"] = len(binary)
binary.extend(b"\0" * (-len(binary) % 4))
encoded = json.dumps(doc, separators=(",", ":")).encode()
encoded += b" " * (-len(encoded) % 4)
result = (struct.pack("<III", 0x46546C67, 2, 28+len(encoded)+len(binary))
          + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
          + struct.pack("<II", len(binary), 0x004E4942) + binary)
path.write_bytes(result)
manifest_path = root / "models/mixamo_survivor.source.json"
manifest = json.loads(manifest_path.read_text())
for clip in manifest["clips"]:
    if clip["name"] in windows:
        start, end = windows[clip["name"]]
        clip.update(seconds=end-start, source_window_seconds=[start,end], hip_yaw_removed=True)
manifest["jump_landing_repair"] = "Flight and grounded recovery separated; landing retains original vertical crouch."
manifest["runtime_sha256"] = hashlib.sha256(result).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
