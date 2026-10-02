#!/usr/bin/env python3
"""Recolor Kenney's CC0 Nature Kit grass-topped rock as a neutral stone pickup.

Only glTF material factors are changed. Usage:
    python tools/recolor_kenney_rock.py input.glb output.glb
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

GLB_MAGIC = b"glTF"
JSON_CHUNK = 0x4E4F534A
MATERIAL_COLORS = {
    "grass": (0.18, 0.20, 0.20, 1.0),
    "dirt": (0.28, 0.29, 0.31, 1.0),
}


def align4(value: int) -> int:
    return (value + 3) & ~3


def recolor(source: Path, destination: Path) -> int:
    data = source.read_bytes()
    if len(data) < 12:
        raise ValueError("input is too short to be a GLB")
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    if magic != GLB_MAGIC or version != 2 or total != len(data):
        raise ValueError("input is not a valid GLB 2.0 file")

    offset = 12
    document = None
    remaining_chunks: list[tuple[int, bytes]] = []
    while offset < len(data):
        length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + length]
        if len(chunk) != length:
            raise ValueError("truncated GLB chunk")
        offset += length
        if chunk_type == JSON_CHUNK:
            document = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\0"))
        else:
            remaining_chunks.append((chunk_type, chunk))
    if document is None:
        raise ValueError("GLB is missing its JSON chunk")

    changed = 0
    for material in document.get("materials", []):
        name = material.get("name", "").lower()
        color = next((rgba for token, rgba in MATERIAL_COLORS.items() if token in name), None)
        if color is None:
            continue
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["baseColorFactor"] = list(color)
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.96
        changed += 1
    if changed == 0:
        raise ValueError("no known rock materials were found")

    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * (align4(len(json_bytes)) - len(json_bytes))
    chunks = [(JSON_CHUNK, json_bytes), *remaining_chunks]
    body = bytearray()
    for chunk_type, chunk in chunks:
        if len(chunk) % 4:
            chunk += b"\0" * (align4(len(chunk)) - len(chunk))
        body += struct.pack("<II", len(chunk), chunk_type)
        body += chunk
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(struct.pack("<4sII", GLB_MAGIC, 2, 12 + len(body)) + body)
    return changed


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        count = recolor(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, KeyError, json.JSONDecodeError, struct.error) as exc:
        print(f"rock recolor failed: {exc}", file=sys.stderr)
        return 1
    print(f"recolored {count} rock material(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
