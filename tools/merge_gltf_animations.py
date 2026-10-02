#!/usr/bin/env python3
"""Merge a compatible animation-only GLB into a character GLB.

The source animation file must use the same node indices and names for every
animated node. The source's animation buffer views/accessors are appended to
the character's embedded buffer and the animation samplers are remapped.

Usage:
    python tools/merge_gltf_animations.py character.glb anim-men.glb output.glb
"""

from __future__ import annotations

import copy
import json
import struct
import sys
from pathlib import Path
from typing import Any

GLB_MAGIC = b"glTF"
GLB_VERSION = 2
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def _align4(value: int) -> int:
    return (value + 3) & ~3


def _read_glb(path: Path) -> tuple[dict[str, Any], bytes, list[tuple[int, bytes]]]:
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError(f"{path}: file is too short to be a GLB")
    magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    if magic != GLB_MAGIC or version != GLB_VERSION or total_length != len(data):
        raise ValueError(f"{path}: expected a valid GLB 2.0 file")

    document: dict[str, Any] | None = None
    binary: bytes | None = None
    extra_chunks: list[tuple[int, bytes]] = []
    offset = 12
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError(f"{path}: truncated chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        end = offset + chunk_length
        if end > len(data):
            raise ValueError(f"{path}: truncated chunk payload")
        chunk = data[offset:end]
        offset = end
        if chunk_type == JSON_CHUNK:
            if document is not None:
                raise ValueError(f"{path}: multiple JSON chunks")
            document = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\0"))
        elif chunk_type == BIN_CHUNK:
            if binary is not None:
                raise ValueError(f"{path}: multiple BIN chunks")
            binary = chunk
        else:
            extra_chunks.append((chunk_type, chunk))

    if document is None or binary is None:
        raise ValueError(f"{path}: GLB requires JSON and BIN chunks")
    return document, binary, extra_chunks


def _embedded_buffer_length(document: dict[str, Any], binary: bytes, path: Path) -> int:
    buffers = document.get("buffers", [])
    if len(buffers) != 1 or buffers[0].get("uri"):
        raise ValueError(f"{path}: expected one embedded GLB buffer")
    length = int(buffers[0].get("byteLength", -1))
    if length < 0 or length > len(binary):
        raise ValueError(f"{path}: declared buffer length exceeds its BIN chunk")
    return length


def _encode_glb(
    document: dict[str, Any], binary: bytes, extra_chunks: list[tuple[int, bytes]]
) -> bytes:
    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * (_align4(len(json_bytes)) - len(json_bytes))
    binary += b"\0" * (_align4(len(binary)) - len(binary))

    chunks = [(JSON_CHUNK, json_bytes), (BIN_CHUNK, binary), *extra_chunks]
    body = bytearray()
    for chunk_type, chunk in chunks:
        body += struct.pack("<II", len(chunk), chunk_type)
        body += chunk
    return struct.pack("<4sII", GLB_MAGIC, GLB_VERSION, 12 + len(body)) + body


def merge(character_path: Path, animation_path: Path, output_path: Path) -> list[str]:
    character, character_binary, character_extras = _read_glb(character_path)
    animations, animation_binary, _animation_extras = _read_glb(animation_path)
    character_length = _embedded_buffer_length(character, character_binary, character_path)
    animation_length = _embedded_buffer_length(animations, animation_binary, animation_path)
    character_binary = character_binary[:character_length]
    animation_binary = animation_binary[:animation_length]

    character_nodes = character.get("nodes", [])
    animation_nodes = animations.get("nodes", [])
    if len(animation_nodes) > len(character_nodes):
        raise ValueError("animation rig has more nodes than the character")
    for index, animation_node in enumerate(animation_nodes):
        character_name = character_nodes[index].get("name")
        animation_name = animation_node.get("name")
        if character_name != animation_name:
            raise ValueError(
                f"animation rig mismatch at node {index}: "
                f"character={character_name!r}, animation={animation_name!r}"
            )

    source_animations = animations.get("animations", [])
    if not source_animations:
        raise ValueError(f"{animation_path}: no animations found")
    existing_names = {item.get("name", "") for item in character.get("animations", [])}
    for animation in source_animations:
        if animation.get("name", "") in existing_names:
            raise ValueError(f"duplicate animation name: {animation.get('name', '')}")
        for channel in animation.get("channels", []):
            target_node = channel.get("target", {}).get("node")
            if target_node is not None and not 0 <= int(target_node) < len(character_nodes):
                raise ValueError(f"animation targets missing character node {target_node}")

    character_views = character.setdefault("bufferViews", [])
    source_views = animations.get("bufferViews", [])
    view_offset = len(character_views)
    for source_view in source_views:
        if source_view.get("buffer", 0) != 0:
            raise ValueError("only embedded animation buffer 0 is supported")
        start = int(source_view.get("byteOffset", 0))
        length = int(source_view["byteLength"])
        end = start + length
        if start < 0 or end > len(animation_binary):
            raise ValueError("animation bufferView points outside its BIN chunk")
        character_binary += b"\0" * (_align4(len(character_binary)) - len(character_binary))
        target_view = copy.deepcopy(source_view)
        target_view["buffer"] = 0
        target_view["byteOffset"] = len(character_binary)
        character_binary += animation_binary[start:end]
        character_views.append(target_view)

    character_accessors = character.setdefault("accessors", [])
    source_accessors = copy.deepcopy(animations.get("accessors", []))
    accessor_offset = len(character_accessors)
    for accessor in source_accessors:
        if "bufferView" in accessor:
            accessor["bufferView"] += view_offset
        sparse = accessor.get("sparse")
        if sparse is not None:
            for field in ("indices", "values"):
                if "bufferView" in sparse[field]:
                    sparse[field]["bufferView"] += view_offset
    character_accessors.extend(source_accessors)

    merged_animations = copy.deepcopy(source_animations)
    for animation in merged_animations:
        for sampler in animation.get("samplers", []):
            sampler["input"] += accessor_offset
            sampler["output"] += accessor_offset
    character.setdefault("animations", []).extend(merged_animations)
    character["buffers"][0]["byteLength"] = len(character_binary)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(_encode_glb(character, character_binary, character_extras))
    return [str(item.get("name", "")) for item in source_animations]


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    character_path, animation_path, output_path = map(Path, sys.argv[1:])
    try:
        names = merge(character_path, animation_path, output_path)
    except (OSError, ValueError, KeyError, IndexError, struct.error, json.JSONDecodeError) as exc:
        print(f"animation merge failed: {exc}", file=sys.stderr)
        return 1
    print(f"merged {len(names)} animation(s) {names}: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
