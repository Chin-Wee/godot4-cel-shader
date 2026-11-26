#!/usr/bin/env python3
"""Audit live thruster hardpoints against the MechAsset GLB bind-pose mesh.

The mount arrays are parsed from demo/aerial/aerial_mech.gd. The audit uses
GLB node transforms for bind-pose mesh vertices and GLB skin weights only to
restrict each search to triangles influenced by the intended mounting bone.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GLB_PATH = ROOT / "demo/models/MechAsset/MechAsset.glb"
SOURCE_PATH = ROOT / "demo/aerial/aerial_mech.gd"
V3_CONSTANTS = {
    "RIGHT": (1.0, 0.0, 0.0), "LEFT": (-1.0, 0.0, 0.0),
    "UP": (0.0, 1.0, 0.0), "DOWN": (0.0, -1.0, 0.0),
    "FORWARD": (0.0, 0.0, -1.0), "BACK": (0.0, 0.0, 1.0),
}
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
              5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def mul(a, s): return tuple(x * s for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def length(a): return math.sqrt(dot(a, a))


def normalize(a):
    n = length(a)
    return mul(a, 1.0/n) if n > 1e-12 else (0.0, 0.0, 0.0)


def identity():
    return [[1.0 if r == c else 0.0 for c in range(4)] for r in range(4)]


def mat_mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def transform_point(m, p):
    v = (p[0], p[1], p[2], 1.0)
    out = tuple(sum(m[r][c] * v[c] for c in range(4)) for r in range(4))
    if abs(out[3]) > 1e-12 and abs(out[3] - 1.0) > 1e-12:
        return tuple(out[i] / out[3] for i in range(3))
    return out[:3]


def transform_direction(m, d):
    return normalize(tuple(sum(m[r][c] * d[c] for c in range(3)) for r in range(3)))


def inverse4(m):
    ident = identity()
    a = [list(m[r]) + ident[r] for r in range(4)]
    for col in range(4):
        pivot = max(range(col, 4), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) < 1e-12:
            raise ValueError("Singular bone transform")
        a[col], a[pivot] = a[pivot], a[col]
        scale = a[col][col]
        a[col] = [v / scale for v in a[col]]
        for r in range(4):
            if r == col:
                continue
            factor = a[r][col]
            a[r] = [a[r][c] - factor * a[col][c] for c in range(8)]
    return [row[4:] for row in a]


def transform_normal_inverse(inv, n):
    return normalize(tuple(sum(inv[c][r] * n[c] for c in range(3)) for r in range(3)))


def gltf_matrix(values):
    return [[float(values[c*4+r]) for c in range(4)] for r in range(4)]


def node_local_matrix(node):
    if "matrix" in node:
        return gltf_matrix(node["matrix"])
    t = node.get("translation", (0.0, 0.0, 0.0))
    x, y, z, w = node.get("rotation", (0.0, 0.0, 0.0, 1.0))
    sx, sy, sz = node.get("scale", (1.0, 1.0, 1.0))
    r = [
        [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
        [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)],
    ]
    m = identity()
    for row in range(3):
        for col in range(3):
            m[row][col] = r[row][col] * (sx, sy, sz)[col]
        m[row][3] = t[row]
    return m


def read_glb(path):
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF":
        raise ValueError(f"Not a GLB file: {path}")
    version, declared = struct.unpack_from("<II", raw, 4)
    if version != 2 or declared != len(raw):
        raise ValueError("Unexpected GLB version/length")
    offset, doc, binary = 12, None, None
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        offset += 8
        chunk = raw[offset:offset+size]
        offset += size
        if kind == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\0"))
        elif kind == 0x004E4942:
            binary = chunk
    if doc is None or binary is None:
        raise ValueError("GLB must contain JSON and BIN chunks")
    return doc, binary, raw


def read_accessor(doc, binary, index):
    acc = doc["accessors"][index]
    if "sparse" in acc:
        raise ValueError(f"Sparse accessor {index} is not supported")
    component, component_size = COMPONENTS[acc["componentType"]]
    width = WIDTHS[acc["type"]]
    view = doc["bufferViews"][acc["bufferView"]]
    stride = view.get("byteStride", component_size * width)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = "<" + component * width
    rows = []
    for i in range(acc["count"]):
        values = struct.unpack_from(fmt, binary, start + i * stride)
        if acc.get("normalized") and acc["componentType"] != 5126:
            if acc["componentType"] in (5121, 5123, 5125):
                maximum = {5121: 255.0, 5123: 65535.0, 5125: 4294967295.0}[acc["componentType"]]
                values = tuple(v / maximum for v in values)
            else:
                maximum = {5120: 127.0, 5122: 32767.0}[acc["componentType"]]
                values = tuple(max(-1.0, v / maximum) for v in values)
        rows.append(values[0] if width == 1 else tuple(values))
    return rows


def parse_mounts(source):
    text = source.read_text()
    row_re = re.compile(
        r'\["(?P<name>[^"]+)",\s*&"(?P<bone>[^"]+)",\s*'
        r'Vector3\((?P<position>[^)]*)\),\s*(?P<direction>Vector3\.[A-Z]+|Vector3\([^)]*\))\s*\]'
    )
    result = {}
    for array_name in ("MOUNTS", "COLD_MOUNTS"):
        start = text.find(f"const {array_name} := [")
        end = text.find("\n]", start)
        if start < 0 or end < 0:
            raise ValueError(f"Missing or unterminated {array_name}")
        rows = []
        for match in row_re.finditer(text[start:end]):
            pos = tuple(float(v.strip()) for v in match.group("position").split(","))
            direction_text = match.group("direction")
            direction = (V3_CONSTANTS[direction_text.split(".", 1)[1]]
                         if direction_text.startswith("Vector3.")
                         else tuple(float(v.strip()) for v in direction_text[8:-1].split(",")))
            if len(pos) != 3 or len(direction) != 3:
                raise ValueError("Mount vector must have three components")
            rows.append({"kind": "main" if array_name == "MOUNTS" else "cold",
                         "name": match.group("name"), "bone": match.group("bone"),
                         "position": pos, "direction": normalize(direction)})
        if not rows:
            raise ValueError(f"No mounts parsed from {array_name}")
        result[array_name] = rows
    return result


def build_node_transforms(doc):
    parents = {}
    for parent, node in enumerate(doc.get("nodes", [])):
        for child in node.get("children", []):
            if child in parents:
                raise ValueError(f"glTF node {child} has multiple parents")
            parents[child] = parent
    local = [node_local_matrix(n) for n in doc.get("nodes", [])]
    cache = {}

    def global_matrix(index):
        if index not in cache:
            parent = parents.get(index)
            cache[index] = mat_mul(global_matrix(parent), local[index]) if parent is not None else local[index]
        return cache[index]

    return [global_matrix(i) for i in range(len(local))]


def mesh_triangles(doc, binary, globals_):
    node_names = {n.get("name", f"node_{i}"): i for i, n in enumerate(doc.get("nodes", []))}
    triangles, all_points, mesh_nodes, mesh_details = [], [], [], []
    parents = {child: parent for parent, node in enumerate(doc.get("nodes", [])) for child in node.get("children", [])}
    for node_index, node in enumerate(doc.get("nodes", [])):
        if "mesh" not in node:
            continue
        mesh_name = node.get("name", f"mesh_node_{node_index}")
        mesh_nodes.append(mesh_name)
        parent_index = parents.get(node_index)
        parent_name = doc["nodes"][parent_index].get("name") if parent_index is not None else None
        skin = doc.get("skins", [])[node["skin"]] if "skin" in node else None
        mesh_points, joint_weight_sums, node_triangle_count, node_vertex_count = [], {}, 0, 0
        joint_names = [doc["nodes"][j].get("name", f"node_{j}") for j in skin.get("joints", [])] if skin else []
        for primitive_index, primitive in enumerate(doc["meshes"][node["mesh"]].get("primitives", [])):
            if "KHR_draco_mesh_compression" in primitive.get("extensions", {}):
                raise ValueError("Draco-compressed primitive needs a decoder")
            attrs = primitive["attributes"]
            positions = read_accessor(doc, binary, attrs["POSITION"])
            normals = read_accessor(doc, binary, attrs["NORMAL"]) if "NORMAL" in attrs else None
            inverse_mesh_transform = inverse4(globals_[node_index]) if normals else None
            world_positions = [transform_point(globals_[node_index], p) for p in positions]
            mesh_points.extend(world_positions)
            node_vertex_count += len(world_positions)
            world_normals = ([transform_normal_inverse(inverse_mesh_transform, n) for n in normals]
                             if normals else None)
            joints0 = read_accessor(doc, binary, attrs["JOINTS_0"]) if "JOINTS_0" in attrs else None
            weights0 = read_accessor(doc, binary, attrs["WEIGHTS_0"]) if "WEIGHTS_0" in attrs else None
            joints1 = read_accessor(doc, binary, attrs["JOINTS_1"]) if "JOINTS_1" in attrs else None
            weights1 = read_accessor(doc, binary, attrs["WEIGHTS_1"]) if "WEIGHTS_1" in attrs else None
            per_vertex_weights = []
            for vertex in range(len(positions)):
                influences = {}
                if joints0 is not None and weights0 is not None:
                    pairs = list(zip(joints0[vertex], weights0[vertex]))
                    if joints1 is not None and weights1 is not None:
                        pairs.extend(zip(joints1[vertex], weights1[vertex]))
                    total = sum(float(w) for _, w in pairs)
                    if total > 1e-12:
                        for slot, weight in pairs:
                            if weight > 0 and int(slot) < len(joint_names):
                                name = joint_names[int(slot)]
                                influences[name] = influences.get(name, 0.0) + float(weight) / total
                if skin is None and parent_name:
                    influences[parent_name] = 1.0
                per_vertex_weights.append(influences)
                for name, weight in influences.items():
                    joint_weight_sums[name] = joint_weight_sums.get(name, 0.0) + weight
            indices = ([int(v) for v in read_accessor(doc, binary, primitive["indices"])]
                       if "indices" in primitive else list(range(len(positions))))
            mode = primitive.get("mode", 4)
            if mode == 4:
                index_tris = [indices[i:i+3] for i in range(0, len(indices)-2, 3)]
            elif mode == 5:
                index_tris = [[indices[i], indices[i+1], indices[i+2]] if i % 2 == 0
                              else [indices[i+1], indices[i], indices[i+2]]
                              for i in range(len(indices)-2)]
            elif mode == 6:
                index_tris = [[indices[0], indices[i], indices[i+1]] for i in range(1, len(indices)-1)]
            else:
                continue
            for tri in index_tris:
                if len(tri) != 3:
                    continue
                a, b, c = (world_positions[k] for k in tri)
                geometric_normal = normalize(cross(sub(b, a), sub(c, a)))
                if length(geometric_normal) < 1e-10:
                    continue
                if world_normals:
                    normal = normalize(add(add(world_normals[tri[0]], world_normals[tri[1]]), world_normals[tri[2]]))
                    if dot(normal, geometric_normal) < 0.0:
                        normal = mul(normal, -1.0)
                    if length(normal) < 1e-10:
                        normal = geometric_normal
                else:
                    normal = geometric_normal
                bone_weights = {}
                for vertex in tri:
                    for name, weight in per_vertex_weights[vertex].items():
                        bone_weights[name] = bone_weights.get(name, 0.0) + weight / 3.0
                triangles.append({"a": a, "b": b, "c": c, "normal": normal,
                                  "mesh": mesh_name, "primitive": primitive_index,
                                  "bone_weights": bone_weights})
                node_triangle_count += 1
                all_points.extend((a, b, c))
        if mesh_points:
            mesh_details.append({
                "name": mesh_name, "parent": parent_name, "skin": node.get("skin"),
                "mesh_resource": doc["meshes"][node["mesh"]].get("name"),
                "vertices": node_vertex_count, "triangles": node_triangle_count,
                "bounds_min": [round(min(p[i] for p in mesh_points), 5) for i in range(3)],
                "bounds_max": [round(max(p[i] for p in mesh_points), 5) for i in range(3)],
                "dominant_bones": [{"name": name, "weight_sum": round(weight, 2)}
                                   for name, weight in sorted(joint_weight_sums.items(), key=lambda item: item[1], reverse=True)[:8]]
            })
    if not triangles:
        raise ValueError("No triangle primitives found in GLB")
    center = tuple(sum(p[i] for p in all_points) / len(all_points) for i in range(3))
    return node_names, triangles, center, mesh_nodes, mesh_details


def closest_on_triangle(p, a, b, c):
    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0.0 and d2 <= 0.0:
        return a
    bp = sub(p, b)
    d3, d4 = dot(ab, bp), dot(ac, bp)
    if d3 >= 0.0 and d4 <= d3:
        return b
    vc = d1*d4 - d3*d2
    if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
        return add(a, mul(ab, d1/(d1-d3)))
    cp = sub(p, c)
    d5, d6 = dot(ab, cp), dot(ac, cp)
    if d6 >= 0.0 and d5 <= d6:
        return c
    vb = d5*d2 - d1*d6
    if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
        return add(a, mul(ac, d2/(d2-d6)))
    va = d3*d6 - d5*d4
    if va <= 0.0 and (d4-d3) >= 0.0 and (d5-d6) >= 0.0:
        return add(b, mul(sub(c, b), (d4-d3)/((d4-d3)+(d5-d6))))
    inv = 1.0/(va+vb+vc)
    return add(add(a, mul(ab, vb*inv)), mul(ac, vc*inv))


def nearest_surface(candidate, candidates, center, bone_name):
    best = None
    for tri in candidates:
        point = closest_on_triangle(candidate, tri["a"], tri["b"], tri["c"])
        delta = sub(candidate, point)
        d2 = dot(delta, delta)
        if best is None or d2 < best[0]:
            best = (d2, point, tri)
    d2, nearest, tri = best
    normal = tri["normal"]
    if dot(normal, sub(nearest, center)) < 0.0:
        normal = mul(normal, -1.0)
    return {"mesh": tri["mesh"], "primitive": tri["primitive"], "nearest": nearest,
            "distance": math.sqrt(d2), "normal": normal,
            "signed_offset": dot(sub(candidate, nearest), normal),
            "bone_weight": tri["bone_weights"].get(bone_name, 0.0)}


def ray_segment_hit(start, end, tri):
    direction = sub(end, start)
    edge1, edge2 = sub(tri["b"], tri["a"]), sub(tri["c"], tri["a"])
    pvec = cross(direction, edge2)
    determinant = dot(edge1, pvec)
    if abs(determinant) < 1e-10:
        return None
    inverse = 1.0 / determinant
    tvec = sub(start, tri["a"])
    u = dot(tvec, pvec) * inverse
    if u < 0.0 or u > 1.0:
        return None
    qvec = cross(tvec, edge1)
    v = dot(direction, qvec) * inverse
    if v < 0.0 or u + v > 1.0:
        return None
    t = dot(edge2, qvec) * inverse
    if t <= 1e-5 or t >= 1.0 - 1e-5:
        return None
    return t * length(direction)


def nozzle_clearance(candidate, axis, radius, triangles):
    reference = (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)
    tangent_a = normalize(cross(axis, reference))
    tangent_b = normalize(cross(axis, tangent_a))
    # The rendered cylinder extends to 1.25 radii from the mount. Probe its
    # outer housing section, beyond the intentionally seated spherical collar.
    offsets = [(0.0, 0.0), (0.75, 0.0), (-0.75, 0.0), (0.0, 0.75), (0.0, -0.75)]
    hits = []
    for ray_index, (u, v) in enumerate(offsets):
        offset = add(mul(tangent_a, u * radius), mul(tangent_b, v * radius))
        start = add(add(candidate, mul(axis, radius * 0.55)), offset)
        end = add(add(candidate, mul(axis, radius * 1.30)), offset)
        best = None
        for tri in triangles:
            distance = ray_segment_hit(start, end, tri)
            if distance is not None and (best is None or distance < best[0]):
                best = (distance, tri["mesh"])
        if best:
            hits.append({"ray": ray_index, "mesh": best[1], "distance": round(best[0], 5)})
    return hits


def audit_mount(mount, node_names, globals_, triangles, center):
    if mount["bone"] not in node_names:
        raise ValueError(f"{mount['name']}: missing GLB bone {mount['bone']}")
    bone_matrix = globals_[node_names[mount["bone"]]]
    candidate = transform_point(bone_matrix, mount["position"])
    axis = transform_direction(bone_matrix, mount["direction"])
    candidates = [t for t in triangles if t["bone_weights"].get(mount["bone"], 0.0) >= 0.05]
    scope = "bone-weighted"
    if not candidates:
        candidates, scope = triangles, "whole-mesh fallback"
    local = nearest_surface(candidate, candidates, center, mount["bone"])
    whole = nearest_surface(candidate, triangles, center, mount["bone"])
    nozzle_radius = 0.085 if mount["kind"] == "cold" else 0.18
    clearance_hits = nozzle_clearance(candidate, axis, nozzle_radius, triangles)
    return {"kind": mount["kind"], "name": mount["name"], "bone": mount["bone"], "scope": scope,
            "mesh": local["mesh"], "primitive": local["primitive"],
            "nozzle_radius": nozzle_radius, "clearance_hits": clearance_hits,
            "bone_weight": round(local["bone_weight"], 4),
            "position_bone_local": [round(v, 6) for v in mount["position"]],
            "position_world": [round(v, 6) for v in candidate],
            "nearest_world": [round(v, 6) for v in local["nearest"]],
            "distance": round(local["distance"], 6),
            "signed_offset": round(local["signed_offset"], 6),
            "axis_world": [round(v, 6) for v in axis],
            "surface_normal_world": [round(v, 6) for v in local["normal"]],
            "normal_alignment": round(dot(axis, local["normal"]), 6),
            "nearest_any_mesh": whole["mesh"],
            "nearest_any_world": [round(v, 6) for v in whole["nearest"]],
            "distance_any": round(whole["distance"], 6),
            "normal_any_world": [round(v, 6) for v in whole["normal"]],
            "normal_alignment_any": round(dot(axis, whole["normal"]), 6)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--max-distance", type=float, default=0.25)
    parser.add_argument("--min-normal-dot", type=float, default=0.55)
    args = parser.parse_args()
    doc, binary, raw = read_glb(GLB_PATH)
    globals_ = build_node_transforms(doc)
    mounts = parse_mounts(SOURCE_PATH)
    node_names, triangles, center, mesh_nodes, mesh_details = mesh_triangles(doc, binary, globals_)
    results = [audit_mount(m, node_names, globals_, triangles, center)
               for group in ("MOUNTS", "COLD_MOUNTS") for m in mounts[group]]
    failures = [r for r in results if r["distance"] > args.max_distance or
                r["normal_alignment"] < args.min_normal_dot or r["clearance_hits"]]
    parent_map = {child: parent for parent, node in enumerate(doc.get("nodes", [])) for child in node.get("children", [])}
    relevant_bones = ["PelvisBase", "Low_Waist", "Torso_WaistConnect", "Torso",
                      "Shoulder.L", "Shoulder.R", "Thigh.L", "Thigh.R",
                      "Shin.L", "Shin.R", "Feet.L", "Feet.R"]
    bone_details = []
    for name in relevant_bones:
        if name not in node_names:
            bone_details.append({"name": name, "missing": True})
            continue
        index = node_names[name]
        parent = parent_map.get(index)
        bone_details.append({"name": name,
                             "parent": doc["nodes"][parent].get("name") if parent is not None else None,
                             "global_origin": [round(globals_[index][i][3], 5) for i in range(3)]})
    relevant_meshes = [m for m in mesh_details if any(term in m["name"].lower()
                       for term in ["armor", "waist", "cube", "thigh", "shin", "feet", "shoulder"])]
    summary = {"glb": str(GLB_PATH.relative_to(ROOT)), "glb_bytes": len(raw),
               "glb_sha256": hashlib.sha256(raw).hexdigest(), "nodes": len(doc.get("nodes", [])),
               "skins": len(doc.get("skins", [])), "mesh_nodes": mesh_nodes, "triangles": len(triangles),
               "relevant_mesh_details": relevant_meshes, "bone_details": bone_details,

               "main_mounts": len(mounts["MOUNTS"]), "cold_mounts": len(mounts["COLD_MOUNTS"]),
               "thresholds": {"max_distance": args.max_distance, "min_normal_dot": args.min_normal_dot},
               "failing_mounts": [r["name"] for r in failures], "mounts": results}
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(f"GLB: {summary['glb']} ({len(raw)} bytes, {len(triangles)} triangles)")
        for r in results:
            print(f"{r['kind']:4} {r['name']:16} bone={r['bone']:12} d={r['distance']:.4f} "
                  f"signed={r['signed_offset']:+.4f} normal_dot={r['normal_alignment']:+.3f} "
                  f"mesh={r['mesh']} [{r['scope']}]")
        print(f"main={summary['main_mounts']} cold={summary['cold_mounts']} failures={len(failures)}")
    if args.strict and failures:
        print("Mesh audit failed: " + ", ".join(r["name"] for r in failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"mesh audit error: {exc}", file=sys.stderr)
        sys.exit(2)
