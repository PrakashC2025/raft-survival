#!/usr/bin/env python3
"""Bake the Quaternius Beach Character's _PALETTE slots into standard glTF COLOR_0.

The packed source uses a custom scalar vertex attribute called ``_PALETTE``. Godot
can import ordinary glTF vertex colors directly, so this small conversion keeps
the skinned mesh/skeleton intact while making the material palette portable.

Usage:
    python tools/bake_palette_glb.py input.glb output.glb

Palette values are the sRGB colors in H3-Teamy's CC0 Beach Character manifest.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path
from typing import Any

GLB_MAGIC = b"glTF"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

# public/arena/characters/manifest.json, model "beach-man", field "colours".
BEACH_MAN_PALETTE_SRGB = (
    12229753,
    7414318,
    12229753,
    7414318,
    10724259,
    8880758,
    12229753,
    3616292,
    2891800,
    4270356,
    10385985,
)


def _align4(value: int) -> int:
    return (value + 3) & ~3


def _srgb_to_linear(value: int) -> float:
    channel = value / 255.0
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def _palette_color(slot: int) -> tuple[float, float, float, float]:
    if slot < 0 or slot >= len(BEACH_MAN_PALETTE_SRGB):
        raise ValueError(f"palette slot {slot} is outside the Beach Character palette")
    color = BEACH_MAN_PALETTE_SRGB[slot]
    red = (color >> 16) & 0xFF
    green = (color >> 8) & 0xFF
    blue = color & 0xFF
    return (
        _srgb_to_linear(red),
        _srgb_to_linear(green),
        _srgb_to_linear(blue),
        1.0,
    )


def _read_glb(path: Path) -> tuple[dict[str, Any], bytes, list[tuple[int, bytes]]]:
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError("input is too short to be a GLB")
    magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    if magic != GLB_MAGIC or version != 2 or total_length != len(data):
        raise ValueError("input is not a valid GLB 2.0 file")

    offset = 12
    document: dict[str, Any] | None = None
    binary: bytes | None = None
    extra_chunks: list[tuple[int, bytes]] = []
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_length]
        if len(chunk) != chunk_length:
            raise ValueError("truncated GLB chunk")
        offset += chunk_length
        if chunk_type == JSON_CHUNK:
            document = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\0"))
        elif chunk_type == BIN_CHUNK:
            binary = chunk
        else:
            extra_chunks.append((chunk_type, chunk))

    if document is None or binary is None:
        raise ValueError("GLB must contain JSON and BIN chunks")
    return document, binary, extra_chunks


def _accessor_start(document: dict[str, Any], accessor_index: int) -> tuple[dict[str, Any], dict[str, Any], int, int]:
    accessor = document["accessors"][accessor_index]
    if "sparse" in accessor:
        raise ValueError("sparse accessors are not supported")
    view = document["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return accessor, view, start, view.get("byteStride", 0)


def _palette_values(document: dict[str, Any], binary: bytes, accessor_index: int) -> list[int]:
    accessor, view, start, stride = _accessor_start(document, accessor_index)
    if accessor.get("componentType") != 5121 or accessor.get("type") != "SCALAR":
        raise ValueError("_PALETTE must be an UNSIGNED_BYTE SCALAR accessor")
    stride = stride or 1
    if stride < 1:
        raise ValueError("invalid _PALETTE byte stride")
    count = accessor["count"]
    end = start + (count - 1) * stride + 1 if count else start
    if end > len(binary):
        raise ValueError("_PALETTE accessor extends past the GLB buffer")
    return [binary[start + index * stride] for index in range(count)]


def _read_vec3_accessor(document: dict[str, Any], binary: bytes, accessor_index: int) -> list[tuple[float, float, float]]:
    accessor, view, start, stride = _accessor_start(document, accessor_index)
    if accessor.get("componentType") != 5126 or accessor.get("type") != "VEC3":
        raise ValueError("POSITION must be a FLOAT VEC3 accessor")
    stride = stride or 12
    count = accessor["count"]
    if start + (count - 1) * stride + 12 > len(binary):
        raise ValueError("POSITION accessor extends past the GLB buffer")
    return [struct.unpack_from("<3f", binary, start + index * stride) for index in range(count)]


def _read_indices(document: dict[str, Any], binary: bytes, accessor_index: int) -> list[int]:
    accessor, view, start, stride = _accessor_start(document, accessor_index)
    if accessor.get("type") != "SCALAR":
        raise ValueError("mesh indices must be a SCALAR accessor")
    component_format = {5121: ("<B", 1), 5123: ("<H", 2), 5125: ("<I", 4)}.get(accessor.get("componentType"))
    if component_format is None:
        raise ValueError("unsupported mesh index component type")
    fmt, element_size = component_format
    stride = stride or element_size
    count = accessor["count"]
    if start + (count - 1) * stride + element_size > len(binary):
        raise ValueError("index accessor extends past the GLB buffer")
    return [struct.unpack_from(fmt, binary, start + index * stride)[0] for index in range(count)]


def _vertex_normals(positions: list[tuple[float, float, float]], indices: list[int]) -> list[tuple[float, float, float]]:
    if len(indices) % 3:
        raise ValueError("triangle index count is not divisible by three")
    accumulators = [[0.0, 0.0, 0.0] for _ in positions]
    for offset in range(0, len(indices), 3):
        ia, ib, ic = indices[offset : offset + 3]
        ax, ay, az = positions[ia]
        bx, by, bz = positions[ib]
        cx, cy, cz = positions[ic]
        ab = (bx - ax, by - ay, bz - az)
        ac = (cx - ax, cy - ay, cz - az)
        face = (
            ab[1] * ac[2] - ab[2] * ac[1],
            ab[2] * ac[0] - ab[0] * ac[2],
            ab[0] * ac[1] - ab[1] * ac[0],
        )
        for vertex in (ia, ib, ic):
            accumulators[vertex][0] += face[0]
            accumulators[vertex][1] += face[1]
            accumulators[vertex][2] += face[2]
    normals = []
    for x, y, z in accumulators:
        length = math.sqrt(x * x + y * y + z * z)
        normals.append((x / length, y / length, z / length) if length > 1e-20 else (0.0, 1.0, 0.0))
    return normals


def _encode_glb(document: dict[str, Any], binary: bytes, extra_chunks: list[tuple[int, bytes]]) -> bytes:
    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * (_align4(len(json_bytes)) - len(json_bytes))
    binary += b"\0" * (_align4(len(binary)) - len(binary))

    chunks = [(JSON_CHUNK, json_bytes), (BIN_CHUNK, binary), *extra_chunks]
    body = bytearray()
    for chunk_type, chunk_bytes in chunks:
        body += struct.pack("<II", len(chunk_bytes), chunk_type)
        body += chunk_bytes
    total_length = 12 + len(body)
    return struct.pack("<4sII", GLB_MAGIC, 2, total_length) + body


def bake(input_path: Path, output_path: Path) -> int:
    document, binary_chunk, extra_chunks = _read_glb(input_path)
    buffers = document.get("buffers", [])
    if len(buffers) != 1 or buffers[0].get("uri"):
        raise ValueError("expected one embedded GLB buffer")
    old_buffer_length = buffers[0]["byteLength"]
    if old_buffer_length > len(binary_chunk):
        raise ValueError("GLB buffer is shorter than its declared byteLength")

    converted = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            attributes = primitive.get("attributes", {})
            palette_index = attributes.get("_PALETTE")
            if palette_index is None:
                continue
            if "COLOR_0" in attributes:
                raise ValueError("mesh already contains COLOR_0")

            slots = _palette_values(document, binary_chunk, palette_index)
            positions_index = attributes.get("POSITION")
            if positions_index is None or document["accessors"][positions_index]["count"] != len(slots):
                raise ValueError("_PALETTE and POSITION vertex counts do not match")

            colors = [_palette_color(slot) for slot in slots]
            color_bytes = b"".join(struct.pack("<4f", *color) for color in colors)
            positions = _read_vec3_accessor(document, binary_chunk, positions_index)
            if "indices" not in primitive:
                raise ValueError("expected an indexed character mesh")
            indices = _read_indices(document, binary_chunk, primitive["indices"])
            normals = _vertex_normals(positions, indices)
            normal_bytes = b"".join(struct.pack("<3f", *normal) for normal in normals)

            color_offset = _align4(old_buffer_length)
            if color_offset > old_buffer_length:
                binary_chunk = binary_chunk[:old_buffer_length] + b"\0" * (color_offset - old_buffer_length)
            else:
                binary_chunk = binary_chunk[:old_buffer_length]
            binary_chunk += color_bytes
            normal_offset = color_offset + len(color_bytes)
            binary_chunk += normal_bytes

            buffer_views = document.setdefault("bufferViews", [])
            accessors = document.setdefault("accessors", [])
            color_view_index = len(buffer_views)
            buffer_views.append(
                {
                    "buffer": 0,
                    "byteOffset": color_offset,
                    "byteLength": len(color_bytes),
                    "target": 34962,
                }
            )
            color_accessor_index = len(accessors)
            color_min = [min(color[channel] for color in colors) for channel in range(4)]
            color_max = [max(color[channel] for color in colors) for channel in range(4)]
            accessors.append(
                {
                    "bufferView": color_view_index,
                    "componentType": 5126,
                    "count": len(colors),
                    "type": "VEC4",
                    "min": color_min,
                    "max": color_max,
                }
            )
            normal_view_index = len(buffer_views)
            buffer_views.append(
                {
                    "buffer": 0,
                    "byteOffset": normal_offset,
                    "byteLength": len(normal_bytes),
                    "target": 34962,
                }
            )
            normal_accessor_index = len(accessors)
            normal_min = [min(normal[channel] for normal in normals) for channel in range(3)]
            normal_max = [max(normal[channel] for normal in normals) for channel in range(3)]
            accessors.append(
                {
                    "bufferView": normal_view_index,
                    "componentType": 5126,
                    "count": len(normals),
                    "type": "VEC3",
                    "min": normal_min,
                    "max": normal_max,
                }
            )
            attributes["COLOR_0"] = color_accessor_index
            attributes["NORMAL"] = normal_accessor_index
            del attributes["_PALETTE"]
            buffers[0]["byteLength"] = normal_offset + len(normal_bytes)
            old_buffer_length = buffers[0]["byteLength"]
            converted += 1

    if converted == 0:
        raise ValueError("no _PALETTE attributes were found")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(_encode_glb(document, binary_chunk, extra_chunks))
    return converted


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    try:
        converted = bake(source, destination)
    except (OSError, ValueError, KeyError, IndexError, struct.error, json.JSONDecodeError) as exc:
        print(f"palette bake failed: {exc}", file=sys.stderr)
        return 1
    print(f"baked {converted} primitive(s): {source} -> {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
