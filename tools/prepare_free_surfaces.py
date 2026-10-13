"""Prepare public CC0 surface downloads; never included in the runtime."""
from pathlib import Path
import hashlib
import json
import struct
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "tools/asset_downloads/surface-refresh/Metal038"
OUT = ROOT / "textures/salvage"
OUT.mkdir(exist_ok=True)
for channel, source in (("diff", "Color"), ("nor_gl", "NormalGL")):
    Image.open(RAW / f"Metal038_1K-JPG_{source}.jpg").save(OUT / f"steel_{channel}.jpg", quality=92)
roughness = Image.open(RAW / "Metal038_1K-JPG_Roughness.jpg").convert("L")
metalness = Image.open(RAW / "Metal038_1K-JPG_Metalness.jpg").convert("L")
Image.merge("RGB", (Image.new("L", roughness.size, 255), roughness, metalness)).save(OUT / "steel_arm.jpg", quality=95)
records = []
for folder, prefix, source in ((OUT, "steel", "https://ambientcg.com/view?id=Metal038"),
                               (OUT, "rust", "https://polyhaven.com/a/rusty_metal_02"),
                               (ROOT / "textures/underwater", "coast", "https://polyhaven.com/a/coast_sand_01")):
    for suffix in ("diff", "nor_gl", "arm"):
        path = folder / f"{prefix}_{suffix}.jpg"
        records.append({"file": str(path.relative_to(ROOT)).replace("\\", "/"),
                        "source": source, "license": "CC0-1.0",
                        "dimensions": list(Image.open(path).size),
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT / "source_manifest.json").write_text(json.dumps({"prepared": "2026-10-13", "maps": records}, indent=2) + "\n")
print("Prepared nine 1024px CC0 maps; packed steel AO/roughness/metalness.")

# Inspect hip motion before choosing any runtime animation correction.
data = (ROOT / "models/mixamo_survivor.glb").read_bytes()
json_size = struct.unpack_from("<I", data, 12)[0]
doc = json.loads(data[20:20 + json_size])
binary = data[28 + json_size:]
for clip in doc["animations"]:
    if clip["name"] not in ("TurnLeft", "TurnRight"): continue
    for channel in clip["channels"]:
        target = channel["target"]
        if doc["nodes"][target["node"]].get("name") != "Hips" or target["path"] != "rotation": continue
        accessor = doc["accessors"][clip["samplers"][channel["sampler"]]["output"]]
        view = doc["bufferViews"][accessor["bufferView"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        first = struct.unpack_from("<4f", binary, offset)
        last = struct.unpack_from("<4f", binary, offset + (accessor["count"] - 1) * view.get("byteStride", 16))
        print(clip["name"], "hip rotation first/last", first, last)
