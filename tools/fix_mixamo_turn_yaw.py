"""Remove duplicate actor yaw from imported turn hips, preserving limb motion."""
from pathlib import Path
import json
import math
import struct
import hashlib

root = Path(__file__).resolve().parents[1]
path = root / "models/mixamo_survivor.glb"
data = bytearray(path.read_bytes())
length = struct.unpack_from("<I", data, 12)[0]
doc = json.loads(data[20:20 + length])
binary_start = 28 + length

def multiply(a, b):
    x, y, z, w = a
    X, Y, Z, W = b
    return (w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
            w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z)

for clip in doc["animations"]:
    if clip["name"] not in ("TurnLeft", "TurnRight"): continue
    for channel in clip["channels"]:
        node = doc["nodes"][channel["target"]["node"]]
        if node.get("name") != "Hips" or channel["target"]["path"] != "rotation": continue
        rest = tuple(node.get("rotation", (0, 0, 0, 1)))
        inverse = (-rest[0], -rest[1], -rest[2], rest[3])
        accessor = doc["accessors"][clip["samplers"][channel["sampler"]]["output"]]
        view = doc["bufferViews"][accessor["bufferView"]]
        start = binary_start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        for key in range(accessor["count"]):
            offset = start + key * view.get("byteStride", 16)
            pose = struct.unpack_from("<4f", data, offset)
            relative = multiply(pose, inverse)
            norm = math.hypot(relative[1], relative[3])
            twist_inverse = (0, -relative[1]/norm, 0, relative[3]/norm)
            corrected = multiply(multiply(twist_inverse, relative), rest)
            struct.pack_into("<4f", data, offset, *corrected)
        print("Removed duplicate hip yaw:", clip["name"], accessor["count"], "keys")
path.write_bytes(data)
manifest_path = root / "models/mixamo_survivor.source.json"
manifest = json.loads(manifest_path.read_text())
manifest["turn_root_yaw"] = "Removed Y-axis twist from turn hips; gameplay owns yaw; limb clips retained."
manifest["runtime_sha256"] = hashlib.sha256(data).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
