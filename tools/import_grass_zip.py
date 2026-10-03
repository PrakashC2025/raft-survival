#!/usr/bin/env python3
"""Unpack and convert a downloaded grass archive (e.g. realistic_grass.zip) into models/realistic_grass.glb.

Supports:
- Sketchfab glTF zip archives (scene.gltf + scene.bin + textures/* + license.txt)
- Sketchfab GLB archives or standalone .glb files
- Sketchfab Original-format zips (including nested source/*.zip) with .glb, .gltf, or .obj
- Wavefront .obj files (converted to binary GLB 2.0 with a 0..1 vertical COLOR_0 wind mask)

Usage:
    python tools/import_grass_zip.py path/to/realistic_grass.zip [--wire-scene]
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import shutil
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

GLB_MAGIC = b"glTF"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def align4(value: int) -> int:
    return (value + 3) & ~3


def extract_zip_recursive(zip_path: Path, dest_dir: Path) -> None:
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(dest_dir)
    for nested in list(dest_dir.rglob("*.zip")):
        nested_dir = nested.parent / nested.stem
        nested_dir.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(nested, "r") as nzf:
                nzf.extractall(nested_dir)
        except zipfile.BadZipFile:
            pass


def pack_gltf_to_glb(gltf_path: Path, output_glb: Path, models_dir: Path) -> dict:
    doc = json.loads(gltf_path.read_text(encoding="utf-8"))
    base_dir = gltf_path.parent
    bin_data = bytearray()

    buffers = doc.get("buffers", [])
    buffer_Views = doc.setdefault("bufferViews", [])

    if buffers:
        uri = buffers[0].get("uri", "")
        if uri.startswith("data:"):
            _, b64 = uri.split(",", 1)
            bin_data.extend(base64.b64decode(b64))
        elif uri:
            bin_file = base_dir / uri
            if bin_file.exists():
                bin_data.extend(bin_file.read_bytes())
        buffers[0].pop("uri", None)
    else:
        buffers.append({"byteLength": 0})

    while len(bin_data) % 4:
        bin_data.append(0)

    # Embed external images into bufferViews and copy companion textures to models/
    copied_textures: list[str] = []
    for img in doc.get("images", []):
        uri = img.get("uri", "")
        if not uri or uri.startswith("data:"):
            continue
        img_path = base_dir / uri
        if not img_path.exists():
            # Search by filename anywhere in extracted archive
            matches = list(base_dir.rglob(Path(uri).name))
            if matches:
                img_path = matches[0]
        if img_path.exists():
            raw = img_path.read_bytes()
            offset = len(bin_data)
            bin_data.extend(raw)
            while len(bin_data) % 4:
                bin_data.append(0)
            bv_index = len(buffer_Views)
            buffer_Views.append(
                {
                    "buffer": 0,
                    "byteOffset": offset,
                    "byteLength": len(raw),
                }
            )
            mime, _ = mimetypes.guess_type(img_path.name)
            img.pop("uri", None)
            img["bufferView"] = bv_index
            img["mimeType"] = mime or "image/png"
            dest_tex = models_dir / f"realistic_grass_{img_path.name}"
            shutil.copy2(img_path, dest_tex)
            copied_textures.append(dest_tex.name)

    buffers[0]["byteLength"] = len(bin_data)
    json_bytes = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * (align4(len(json_bytes)) - len(json_bytes))

    body = bytearray()
    body += struct.pack("<II", len(json_bytes), JSON_CHUNK) + json_bytes
    if bin_data:
        body += struct.pack("<II", len(bin_data), BIN_CHUNK) + bin_data

    output_glb.parent.mkdir(parents=True, exist_ok=True)
    output_glb.write_bytes(struct.pack("<4sII", GLB_MAGIC, 2, 12 + len(body)) + body)
    return {
        "format": "gltf->glb",
        "meshes": len(doc.get("meshes", [])),
        "textures": copied_textures,
    }


def convert_obj_to_glb(obj_path: Path, output_glb: Path, models_dir: Path) -> dict:
    positions: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    normals: list[tuple[float, float, float]] = []
    vertices: list[tuple[tuple[float, float, float], tuple[float, float], tuple[float, float, float]]] = []
    vert_map: dict[tuple[int, int, int], int] = {}
    indices: list[int] = []

    for raw_line in obj_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        cmd = parts[0]
        if cmd == "v" and len(parts) >= 4:
            positions.append((float(parts[1]), float(parts[2]), float(parts[3])))
        elif cmd == "vt" and len(parts) >= 3:
            uvs.append((float(parts[1]), 1.0 - float(parts[2])))
        elif cmd == "vn" and len(parts) >= 4:
            normals.append((float(parts[1]), float(parts[2]), float(parts[3])))
        elif cmd == "f" and len(parts) >= 4:
            face_idxs: list[int] = []
            for token in parts[1:]:
                vals = token.split("/")
                vi = int(vals[0]) - 1 if vals[0] else 0
                ti = int(vals[1]) - 1 if len(vals) > 1 and vals[1] else -1
                ni = int(vals[2]) - 1 if len(vals) > 2 and vals[2] else -1
                key = (vi, ti, ni)
                if key not in vert_map:
                    pos = positions[vi] if 0 <= vi < len(positions) else (0.0, 0.0, 0.0)
                    uv = uvs[ti] if 0 <= ti < len(uvs) else (0.0, 0.0)
                    nrm = normals[ni] if 0 <= ni < len(normals) else (0.0, 1.0, 0.0)
                    vert_map[key] = len(vertices)
                    vertices.append((pos, uv, nrm))
                face_idxs.append(vert_map[key])
            for i in range(1, len(face_idxs) - 1):
                indices.extend([face_idxs[0], face_idxs[i], face_idxs[i + 1]])

    if not vertices or not indices:
        raise ValueError(f"No valid geometry found in {obj_path.name}")

    xs = [v[0][0] for v in vertices]
    ys = [v[0][1] for v in vertices]
    zs = [v[0][2] for v in vertices]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    min_z, max_z = min(zs), max(zs)
    span_y = max(max_y - min_y, 1e-5)

    pos_bytes = bytearray()
    nrm_bytes = bytearray()
    uv_bytes = bytearray()
    col_bytes = bytearray()
    for pos, uv, nrm in vertices:
        pos_bytes += struct.pack("<3f", *pos)
        nrm_bytes += struct.pack("<3f", *nrm)
        uv_bytes += struct.pack("<2f", *uv)
        h = max(0.0, min(1.0, (pos[1] - min_y) / span_y))
        col_bytes += struct.pack("<4f", h, h, h, 1.0)

    idx_bytes = bytearray()
    for idx in indices:
        idx_bytes += struct.pack("<I", idx)

    bin_data = bytearray()
    views = []

    def add_view(data: bytes, target: int | None = None) -> int:
        while len(bin_data) % 4:
            bin_data.append(0)
        offset = len(bin_data)
        bin_data.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        views.append(view)
        return len(views) - 1

    bv_pos = add_view(pos_bytes, 34962)
    bv_nrm = add_view(nrm_bytes, 34962)
    bv_uv = add_view(uv_bytes, 34962)
    bv_col = add_view(col_bytes, 34962)
    bv_idx = add_view(idx_bytes, 34963)
    while len(bin_data) % 4:
        bin_data.append(0)

    v_count = len(vertices)
    doc = {
        "asset": {"version": "2.0", "generator": "raft-survival import_grass_zip.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "RealisticGrass", "mesh": 0}],
        "meshes": [
            {
                "name": "RealisticGrass",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 0,
                            "NORMAL": 1,
                            "TEXCOORD_0": 2,
                            "COLOR_0": 3,
                        },
                        "indices": 4,
                        "mode": 4,
                    }
                ],
            }
        ],
        "accessors": [
            {
                "bufferView": bv_pos,
                "componentType": 5126,
                "count": v_count,
                "type": "VEC3",
                "min": [min_x, min_y, min_z],
                "max": [max_x, max_y, max_z],
            },
            {"bufferView": bv_nrm, "componentType": 5126, "count": v_count, "type": "VEC3"},
            {"bufferView": bv_uv, "componentType": 5126, "count": v_count, "type": "VEC2"},
            {"bufferView": bv_col, "componentType": 5126, "count": v_count, "type": "VEC4"},
            {"bufferView": bv_idx, "componentType": 5125, "count": len(indices), "type": "SCALAR"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_data)}],
    }

    json_bytes = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * (align4(len(json_bytes)) - len(json_bytes))
    body = (
        struct.pack("<II", len(json_bytes), JSON_CHUNK)
        + json_bytes
        + struct.pack("<II", len(bin_data), BIN_CHUNK)
        + bin_data
    )
    output_glb.parent.mkdir(parents=True, exist_ok=True)
    output_glb.write_bytes(struct.pack("<4sII", GLB_MAGIC, 2, 12 + len(body)) + body)
    return {
        "format": "obj->glb",
        "vertices": v_count,
        "triangles": len(indices) // 3,
    }


def inspect_glb_triangles(glb_path: Path) -> int:
    data = glb_path.read_bytes()
    if len(data) < 20 or data[:4] != GLB_MAGIC:
        return 0
    length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != JSON_CHUNK:
        return 0
    doc = json.loads(data[20 : 20 + length].decode("utf-8").rstrip(" \t\r\n\0"))
    accessors = doc.get("accessors", [])
    triangles = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" in prim and prim["indices"] < len(accessors):
                triangles += accessors[prim["indices"]].get("count", 0) // 3
            else:
                pos_idx = prim.get("attributes", {}).get("POSITION")
                if pos_idx is not None and pos_idx < len(accessors):
                    triangles += accessors[pos_idx].get("count", 0) // 3
    return triangles


def import_grass_source(source: Path, repo_root: Path, wire_scene: bool = False) -> dict:
    models_dir = repo_root / "models"
    output_glb = models_dir / "realistic_grass.glb"

    with tempfile.TemporaryDirectory() as tmp:
        work_dir = Path(tmp)
        if source.is_file() and source.suffix.lower() == ".zip":
            extract_zip_recursive(source, work_dir)
        elif source.is_file():
            shutil.copy2(source, work_dir / source.name)
        elif source.is_dir():
            shutil.copytree(source, work_dir / "src", dirs_exist_ok=True)
        else:
            raise FileNotFoundError(f"Source not found: {source}")

        licenses = [p.read_text(encoding="utf-8", errors="ignore").strip() for p in work_dir.rglob("*license*.txt")]
        glbs = sorted(work_dir.rglob("*.glb"))
        gltfs = sorted(work_dir.rglob("*.gltf"))
        objs = sorted(work_dir.rglob("*.obj"))

        if glbs:
            shutil.copy2(glbs[0], output_glb)
            copied_tex = []
            for ext in ("*.png", "*.jpg", "*.jpeg", "*.webp"):
                for tex in work_dir.rglob(ext):
                    dest = models_dir / f"realistic_grass_{tex.name}"
                    shutil.copy2(tex, dest)
                    copied_tex.append(dest.name)
            info = {"format": "glb", "source_file": glbs[0].name, "textures": copied_tex}
        elif gltfs:
            info = pack_gltf_to_glb(gltfs[0], output_glb, models_dir)
            info["source_file"] = gltfs[0].name
        elif objs:
            info = convert_obj_to_glb(objs[0], output_glb, models_dir)
            info["source_file"] = objs[0].name
        else:
            all_files = [str(p.relative_to(work_dir)) for p in work_dir.rglob("*") if p.is_file()]
            raise ValueError(
                "No .glb, .gltf, or .obj found in archive. "
                f"Files found: {', '.join(all_files) or 'none'}. "
                "If this is a .blend or .fbx archive, open it in Blender and export as glTF 2.0 (.glb)."
            )

        info["output_glb"] = str(output_glb.relative_to(repo_root))
        info["triangles"] = inspect_glb_triangles(output_glb)
        if licenses:
            info["license"] = licenses[0]

        if wire_scene:
            main_tscn = repo_root / "scenes" / "main.tscn"
            if main_tscn.exists():
                text = main_tscn.read_text(encoding="utf-8")
                marker = '[node name="IslandGrass" type="Node3D" parent="Island" unique_id=555555555]\n'
                prop_line = 'sketchfab_grass_model = "res://models/realistic_grass.glb"\n'
                if marker in text and 'sketchfab_grass_model =' not in text:
                    text = text.replace(marker, marker + prop_line, 1)
                    main_tscn.write_text(text, encoding="utf-8")
                    info["wired_main_tscn"] = True

        return info


def main() -> int:
    parser = argparse.ArgumentParser(description="Import realistic_grass.zip into models/realistic_grass.glb")
    parser.add_argument("source", type=Path, help="Path to realistic_grass.zip, .glb, .gltf, or folder")
    parser.add_argument("--wire-scene", action="store_true", help="Assign res://models/realistic_grass.glb on IslandGrass in scenes/main.tscn")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    try:
        info = import_grass_source(args.source, repo_root, wire_scene=args.wire_scene)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(info, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
