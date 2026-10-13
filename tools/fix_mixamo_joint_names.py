"""Restore the game's dotted joint names after Godot's GLB export."""
from pathlib import Path
import json
import struct

path = Path(__file__).resolve().parents[1] / "models/mixamo_survivor.glb"
data = path.read_bytes()
json_length = struct.unpack_from("<I", data, 12)[0]
document = json.loads(data[20:20 + json_length])
for skin in document.get("skins", []):
    for joint in skin["joints"]:
        node = document["nodes"][joint]
        name = node.get("name", "")
        if name.endswith(("_L", "_R")):
            node["name"] = name[:-2] + "." + name[-1]
encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
encoded += b" " * (-len(encoded) % 4)
rest = data[20 + json_length:]
path.write_bytes(struct.pack("<III", 0x46546C67, 2, 20 + len(encoded) + len(rest))
                 + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + rest)
print("Restored dotted left/right joint names; geometry and motion data preserved.")
