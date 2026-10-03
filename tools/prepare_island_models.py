#!/usr/bin/env python3
"""Prepare game-ready GLB assets from '3d models/realistic_grass.glb' and '3d models/coconut_palm (1).glb'.

1. Builds 'models/realistic_grass.glb' (and updates '3d models/realistic_grass.glb'):
   - Extracts a 6-ribbon (12-quad, 24-triangle, 72-face-vertex) intersecting 3D grass tuft
     from mesh[4] ('grass_close2') of the raw SketchUp grass model.
   - Converts coordinates to Y-up, centers XZ at 0, grounds base at y=0, normalizes height
     to 0.38 m, normalizes UVs to [0.02..0.98, 0.0..0.89], and bakes a 0..1 vertical COLOR_0
     wind mask so roots stay planted while tips sway in grass_wind.gdshader.
   - Embeds the 512x256 RGBA grass-blade texture (image[1]) with MASK alpha cutout.

2. Builds 'models/coconut_palm.glb' (and updates '3d models/coconut_palm (1).glb'):
   - Bakes the root FBX/Sketchfab transform into vertex positions and normalizes local
     height to 1.45 m so existing 2.0x-2.4x PalmTree transforms in scenes/main.tscn
     produce ~3.2-3.5 m island palms.
   - Names the main trunk node 'Tree_0_Trunk' and names canopy/frond nodes with 'leaf'
     ('leafs' for the main frond mesh) so IslandSetup only collides with the trunk and
     VEGETATION_VISUAL.apply_palm animates the textured fronds.
"""

from __future__ import annotations

import copy
import json
import math
import shutil
import struct
from pathlib import Path

GLB_MAGIC = b"glTF"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def align4(n: int) -> int:
    return (n + 3) & ~3


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != GLB_MAGIC:
        raise ValueError(f"{path} is not a valid GLB")
    json_len, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != JSON_CHUNK:
        raise ValueError(f"{path} missing JSON chunk")
    doc = json.loads(data[20 : 20 + json_len].decode("utf-8").rstrip(" \t\r\n\0"))
    bin_offset = 20 + json_len
    bin_data = b""
    if bin_offset + 8 <= len(data):
        bin_len, bin_type = struct.unpack_from("<II", data, bin_offset)
        if bin_type == BIN_CHUNK:
            bin_data = data[bin_offset + 8 : bin_offset + 8 + bin_len]
    return doc, bin_data


def write_glb(path: Path, doc: dict, bin_data: bytes) -> None:
    json_bytes = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * (align4(len(json_bytes)) - len(json_bytes))
    padded_bin = bytearray(bin_data)
    while len(padded_bin) % 4:
        padded_bin.append(0)
    if doc.get("buffers"):
        doc["buffers"][0]["byteLength"] = len(padded_bin)
        json_bytes = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        json_bytes += b" " * (align4(len(json_bytes)) - len(json_bytes))
    body = (
        struct.pack("<II", len(json_bytes), JSON_CHUNK)
        + json_bytes
        + struct.pack("<II", len(padded_bin), BIN_CHUNK)
        + bytes(padded_bin)
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack("<4sII", GLB_MAGIC, 2, 12 + len(body)) + body)


def build_realistic_grass_tuft(source_glb: Path, output_glb: Path) -> dict:
    doc, bin_data = read_glb(source_glb)
    # If already converted by this script, just copy if needed
    if doc.get("asset", {}).get("generator") == "raft-survival prepare_island_models.py":
        if source_glb.resolve() != output_glb.resolve():
            shutil.copy2(source_glb, output_glb)
        return {"status": "already_prepared", "triangles": 24}

    # Extract image[1] (512x256 RGBA PNG grass blade sheet)
    img_entry = doc["images"][1]
    img_bv = doc["bufferViews"][img_entry["bufferView"]]
    png_bytes = bin_data[img_bv["byteOffset"] : img_bv["byteOffset"] + img_bv["byteLength"]]

    # Extract Quad 0..5 (3 double-sided ribbons = 6 quads = 24 vertices) from mesh[4]
    prim = doc["meshes"][4]["primitives"][0]
    pos_acc = doc["accessors"][prim["attributes"]["POSITION"]]
    nrm_acc = doc["accessors"][prim["attributes"]["NORMAL"]]
    uv_acc = doc["accessors"][prim["attributes"]["TEXCOORD_0"]]

    pos_off = doc["bufferViews"][pos_acc["bufferView"]].get("byteOffset", 0) + pos_acc.get("byteOffset", 0)
    nrm_off = doc["bufferViews"][nrm_acc["bufferView"]].get("byteOffset", 0) + nrm_acc.get("byteOffset", 0)
    uv_off = doc["bufferViews"][uv_acc["bufferView"]].get("byteOffset", 0) + uv_acc.get("byteOffset", 0)

    raw_verts = []
    for i in range(24):
        rx, ry, rz = struct.unpack_from("<3f", bin_data, pos_off + i * 12)
        nx, ny, nz = struct.unpack_from("<3f", bin_data, nrm_off + i * 12)
        u, v = struct.unpack_from("<2f", bin_data, uv_off + i * 8)
        # Convert SketchUp Z-up (rx, ry, rz) to Godot Y-up (x, y, z) = (rx, rz, -ry)
        raw_verts.append(((rx, rz, -ry), (nx, nz, -ny), (u, v)))

    xs = [p[0][0] for p in raw_verts]
    ys = [p[0][1] for p in raw_verts]
    zs = [p[0][2] for p in raw_verts]
    us = [p[2][0] for p in raw_verts]

    cx = 0.5 * (min(xs) + max(xs))
    cz = 0.5 * (min(zs) + max(zs))
    min_y = min(ys)
    span_y = max(max(ys) - min_y, 1e-5)
    span_xz = max(math.hypot(max(xs) - min(xs), max(zs) - min(zs)), 1e-5)
    min_u, max_u = min(us), max(us)
    span_u = max(max_u - min_u, 1e-5)

    target_height = 0.38
    target_width = 0.36
    scale_y = target_height / span_y
    scale_xz = target_width / span_xz

    # Build 2 intersecting 3-ribbon sheaves (0 deg and 90 deg around Y) -> 12 quads = 24 triangles = 72 face vertices
    final_positions: list[tuple[float, float, float]] = []
    final_normals: list[tuple[float, float, float]] = []
    final_uvs: list[tuple[float, float]] = []
    final_colors: list[tuple[float, float, float, float]] = []
    final_indices: list[int] = []

    for rot_idx in range(2):
        angle = rot_idx * (math.pi * 0.5)
        ca, sa = math.cos(angle), math.sin(angle)
        base_v = len(final_positions)
        for (px, py, pz), (nx, ny, nz), (u, v) in raw_verts:
            lx = (px - cx) * scale_xz
            ly = (py - min_y) * scale_y
            lz = (pz - cz) * scale_xz
            rx = lx * ca - lz * sa
            rz = lx * sa + lz * ca

            rnx = nx * ca - nz * sa
            rnz = nx * sa + nz * ca
            nlen = max(math.sqrt(rnx * rnx + ny * ny + rnz * rnz), 1e-6)
            rnx, rny, rnz = rnx / nlen, ny / nlen, rnz / nlen

            nu = 0.02 + 0.96 * ((u - min_u) / span_u)
            nv = max(0.0, min(1.0, v))
            h = max(0.0, min(1.0, ly / target_height))

            final_positions.append((rx, ly, rz))
            final_normals.append((rnx, rny, rnz))
            final_uvs.append((nu, nv))
            final_colors.append((h, h, h, 1.0))

        for q in range(6):
            v0 = base_v + q * 4
            final_indices.extend([v0, v0 + 1, v0 + 2, v0 + 1, v0 + 0, v0 + 3])

    pos_bytes = b"".join(struct.pack("<3f", *p) for p in final_positions)
    nrm_bytes = b"".join(struct.pack("<3f", *n) for n in final_normals)
    uv_bytes = b"".join(struct.pack("<2f", *uv) for uv in final_uvs)
    col_bytes = b"".join(struct.pack("<4f", *c) for c in final_colors)
    idx_bytes = b"".join(struct.pack("<H", idx) for idx in final_indices)

    out_bin = bytearray()
    views = []

    def add_view(chunk: bytes, target: int | None = None) -> int:
        while len(out_bin) % 4:
            out_bin.append(0)
        off = len(out_bin)
        out_bin.extend(chunk)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(chunk)}
        if target is not None:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    bv_pos = add_view(pos_bytes, 34962)
    bv_nrm = add_view(nrm_bytes, 34962)
    bv_uv = add_view(uv_bytes, 34962)
    bv_col = add_view(col_bytes, 34962)
    bv_idx = add_view(idx_bytes, 34963)
    bv_img = add_view(png_bytes, None)

    fxs = [p[0] for p in final_positions]
    fys = [p[1] for p in final_positions]
    fzs = [p[2] for p in final_positions]
    v_count = len(final_positions)

    out_doc = {
        "asset": {
            "version": "2.0",
            "generator": "raft-survival prepare_island_models.py",
            "extras": doc.get("asset", {}).get("extras", {}),
        },
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "RealisticGrassTuft", "mesh": 0}],
        "meshes": [
            {
                "name": "RealisticGrassTuft",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 0,
                            "NORMAL": 1,
                            "TEXCOORD_0": 2,
                            "COLOR_0": 3,
                        },
                        "indices": 4,
                        "material": 0,
                        "mode": 4,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": "grass_close2",
                "alphaMode": "MASK",
                "alphaCutoff": 0.35,
                "doubleSided": True,
                "pbrMetallicRoughness": {
                    "baseColorTexture": {"index": 0},
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.86,
                },
            }
        ],
        "textures": [{"sampler": 0, "source": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 33071}],
        "images": [{"bufferView": bv_img, "mimeType": "image/png", "name": "realistic_grass_blades"}],
        "accessors": [
            {
                "bufferView": bv_pos,
                "componentType": 5126,
                "count": v_count,
                "type": "VEC3",
                "min": [min(fxs), min(fys), min(fzs)],
                "max": [max(fxs), max(fys), max(fzs)],
            },
            {"bufferView": bv_nrm, "componentType": 5126, "count": v_count, "type": "VEC3"},
            {"bufferView": bv_uv, "componentType": 5126, "count": v_count, "type": "VEC2"},
            {"bufferView": bv_col, "componentType": 5126, "count": v_count, "type": "VEC4"},
            {"bufferView": bv_idx, "componentType": 5123, "count": len(final_indices), "type": "SCALAR"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(out_bin)}],
    }

    write_glb(output_glb, out_doc, out_bin)
    return {
        "output": str(output_glb),
        "vertices": v_count,
        "triangles": len(final_indices) // 3,
        "faces_array_size": len(final_indices),
        "size_bytes": output_glb.stat().st_size,
    }


def prepare_coconut_palm(source_glb: Path, output_glb: Path) -> dict:
    doc, bin_data = read_glb(source_glb)
    if doc.get("asset", {}).get("generator") == "raft-survival prepare_island_models.py":
        if source_glb.resolve() != output_glb.resolve():
            shutil.copy2(source_glb, output_glb)
        return {"status": "already_prepared"}

    mutable_bin = bytearray(bin_data)
    # Raw FBX coordinates in mesh[0..4] have height 628.39227; scale to 1.45 m local height
    scale = 1.45 / 628.3922729492188

    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            pos_idx = prim.get("attributes", {}).get("POSITION")
            if pos_idx is None:
                continue
            acc = doc["accessors"][pos_idx]
            bv = doc["bufferViews"][acc["bufferView"]]
            base_off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = bv.get("byteStride", 12)
            xs, ys, zs = [], [], []
            for i in range(acc["count"]):
                off = base_off + i * stride
                x, y, z = struct.unpack_from("<3f", mutable_bin, off)
                nx, ny, nz = x * scale, y * scale, z * scale
                struct.pack_into("<3f", mutable_bin, off, nx, ny, nz)
                xs.append(nx)
                ys.append(ny)
                zs.append(nz)
            acc["min"] = [min(xs), min(ys), min(zs)]
            acc["max"] = [max(xs), max(ys), max(zs)]

    # Clear root node matrices now that scale/orientation is baked into POSITION
    for node in doc.get("nodes", []):
        node.pop("matrix", None)

    # Rename nodes so IslandSetup only collides with the trunk and VEGETATION_VISUAL animates 'leafs'
    node_renames = {
        "Tree_0_Tree_0Mat_0": "Tree_0_Trunk",
        "Tree_1_Tree_1Mat_0": "Tree_1_leaf_collar",
        "Tree_2_Tree_2Mat_0": "leafs",
        "Tree_3_Tree_3Mat_0": "Tree_3_leaf_stems",
        "Tree_4_Tree_4Mat_0": "Tree_4_leaf_crown",
    }
    for node in doc.get("nodes", []):
        old_name = node.get("name", "")
        if old_name in node_renames:
            node["name"] = node_renames[old_name]
    for mesh in doc.get("meshes", []):
        old_name = mesh.get("name", "")
        if old_name in node_renames:
            mesh["name"] = node_renames[old_name]

    doc.setdefault("asset", {})["generator"] = "raft-survival prepare_island_models.py"
    write_glb(output_glb, doc, mutable_bin)
    return {
        "output": str(output_glb),
        "local_height_m": 1.45,
        "size_bytes": output_glb.stat().st_size,
    }


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    raw_grass = repo / "3d models" / "realistic_grass.glb"
    out_grass = repo / "models" / "realistic_grass.glb"
    raw_palm = repo / "3d models" / "coconut_palm (1).glb"
    out_palm = repo / "models" / "coconut_palm.glb"

    grass_info = build_realistic_grass_tuft(raw_grass, out_grass)
    shutil.copy2(out_grass, raw_grass)

    palm_info = prepare_coconut_palm(raw_palm, out_palm)
    shutil.copy2(out_palm, raw_palm)

    print(json.dumps({"grass": grass_info, "palm": palm_info}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
