"""Build a small, modular chapel nave wall segment as a standalone GLB."""
from __future__ import annotations

import json
import math
import os
import struct
import zlib


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "environment")
OUT_FILE = os.path.join(OUT_DIR, "chapel_nave_module.glb")

MATERIALS = [
    ("Aged pale limestone", (0.66, 0.61, 0.52, 1.0), 0.0, 0.92),
    ("Carved stone highlights", (0.78, 0.73, 0.63, 1.0), 0.0, 0.86),
    ("Stone shadow", (0.31, 0.29, 0.26, 1.0), 0.0, 0.95),
    ("Oxidized iron", (0.19, 0.17, 0.15, 1.0), 0.62, 0.48),
    ("Deep ruby glass", (0.35, 0.055, 0.075, 1.0), 0.18, 0.25),
    ("Muted amber glass", (0.76, 0.42, 0.12, 1.0), 0.16, 0.24),
    ("Smoky blue glass", (0.12, 0.25, 0.34, 1.0), 0.18, 0.28),
]
BUCKETS: list[list[tuple[tuple[float, float, float], tuple[float, float, float]]]] = [
    [] for _ in MATERIALS
]


def add_face(material: int, points: list[tuple[float, float, float]]) -> None:
    if len(points) < 3:
        return
    a, b, c = points[:3]
    ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
    length = math.sqrt(sum(v * v for v in n)) or 1.0
    normal = (n[0] / length, n[1] / length, n[2] / length)
    for i in range(1, len(points) - 1):
        for p in (points[0], points[i], points[i + 1]):
            BUCKETS[material].append((p, normal))


def box(cx: float, cy: float, cz: float, sx: float, sy: float, sz: float, mat: int) -> None:
    x0, x1 = cx - sx / 2, cx + sx / 2
    y0, y1 = cy - sy / 2, cy + sy / 2
    z0, z1 = cz - sz / 2, cz + sz / 2
    faces = [
        [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)],
        [(x0, y0, z1), (x0, y0, z0), (x0, y1, z0), (x0, y1, z1)],
        [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)],
        [(x0, y0, z1), (x1, y0, z1), (x1, y0, z0), (x0, y0, z0)],
        [(x1, y0, z1), (x0, y0, z1), (x0, y1, z1), (x1, y1, z1)],
        [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)],
    ]
    for f in faces:
        add_face(mat, f)


def cylinder_y(cx: float, cz: float, y0: float, y1: float, radius: float, mat: int, sides: int = 10) -> None:
    ring0, ring1 = [], []
    for i in range(sides):
        t = 2 * math.pi * i / sides
        ring0.append((cx + math.cos(t) * radius, y0, cz + math.sin(t) * radius))
        ring1.append((cx + math.cos(t) * radius, y1, cz + math.sin(t) * radius))
    for i in range(sides):
        j = (i + 1) % sides
        add_face(mat, [ring0[i], ring0[j], ring1[j], ring1[i]])
        add_face(mat, [(cx, y0, cz), ring0[j], ring0[i]])
        add_face(mat, [(cx, y1, cz), ring1[i], ring1[j]])


def arch_points(center_z: float, half_width: float, spring_y: float, peak_y: float, steps: int = 12):
    # Two quadratic Bezier curves meet at the pointed apex.
    left, right = [], []
    rise = peak_y - spring_y
    for i in range(steps + 1):
        t = i / steps
        u = 1.0 - t
        # The control point near the spring gives the profile its Gothic curve.
        zl = center_z + u * u * -half_width + 2.0 * u * t * -half_width * 0.10
        zr = center_z + u * u * half_width + 2.0 * u * t * half_width * 0.10
        y = u * u * spring_y + 2.0 * u * t * (spring_y + rise * 0.12) + t * t * peak_y
        left.append((zl, y))
        right.append((zr, y))
    return left, right


def arch_band(center_z: float, inner_half: float, outer_half: float, spring: float,
              inner_peak: float, outer_peak: float, front_x: float, back_x: float,
              mat: int, steps: int = 12) -> None:
    il, ir = arch_points(center_z, inner_half, spring, inner_peak, steps)
    ol, or_ = arch_points(center_z, outer_half, spring, outer_peak, steps)
    for side_inner, side_outer in ((il, ol), (ir, or_)):
        for i in range(steps):
            zi, yi = side_inner[i]
            zj, yj = side_inner[i + 1]
            zo, yo = side_outer[i]
            zp, yp = side_outer[i + 1]
            quad = [(front_x, yo, zo), (front_x, yp, zp), (front_x, yj, zj), (front_x, yi, zi)]
            add_face(mat, quad)
            add_face(mat, [(back_x, yo, zo), (back_x, yi, zi), (back_x, yj, zj), (back_x, yp, zp)])
            add_face(mat, [(front_x, yo, zo), (back_x, yo, zo), (back_x, yp, zp), (front_x, yp, zp)])
            add_face(mat, [(front_x, yj, zj), (back_x, yj, zj), (back_x, yi, zi), (front_x, yi, zi)])


def lancet_glass(center_z: float, half_width: float, spring: float, peak: float, x: float, mat: int) -> None:
    left, right = arch_points(center_z, half_width, spring, peak, 10)
    outline = left + list(reversed(right[:-1]))
    # Colored triangular glass panes fill the pointed opening.
    apex = (x, peak, center_z)
    for i in range(len(outline) - 1):
        p, q = outline[i], outline[i + 1]
        add_face(mat, [(x, p[1], p[0]), (x, q[1], q[0]), apex])


def build_geometry() -> None:
    # Module bounds: 8.4 wide (Z), 6.0 high (Y), 0.62 deep (X).
    # Origin is bottom center; the exposed front is +X.
    box(-0.02, 3.0, 0.0, 0.64, 6.0, 8.4, 0)
    # Side returns and a low string course give the segment readable modular edges.
    for z in (-4.04, 4.04):
        box(0.02, 3.0, z, 0.78, 6.0, 0.32, 0)
        box(0.45, 3.06, z, 0.10, 6.16, 0.38, 1)
        box(0.44, 0.42, z, 0.14, 0.30, 0.42, 1)
        box(0.44, 5.72, z, 0.14, 0.44, 0.42, 1)
    # Courses across the wall face.
    for y in (0.72, 1.62, 2.52, 3.42, 4.32, 5.22):
        box(0.314, y, 0.0, 0.045, 0.035, 7.78, 1 if int(y * 10) % 2 else 2)
    # Two bays with pilasters, simple capitals, bases, and carved pointed arches.
    bay_centers = (-1.88, 1.88)
    for z in (-3.76, 0.0, 3.76):
        box(0.39, 2.90, z, 0.44, 5.50, 0.42, 0)
        box(0.48, 0.33, z, 0.66, 0.46, 0.66, 1)
        box(0.48, 5.62, z, 0.62, 0.28, 0.62, 1)
        box(0.46, 4.48, z, 0.60, 0.22, 0.58, 1)
        cylinder_y(0.48, z, 0.56, 4.38, 0.23, 1, 10)
    for z in bay_centers:
        arch_band(z, 1.40, 1.66, 3.62, 5.12, 5.48, 0.56, 0.22, 1, 16)
        # Stained glass in narrow twin lancets, set into a dark recessed field.
        add_face(2, [(0.37, 3.62, z - 1.32), (0.37, 3.62, z + 1.32), (0.37, 5.08, z)])
        for dz, color in ((-0.48, 4), (0.0, 5), (0.48, 6)):
            lancet_glass(z + dz, 0.23, 3.63, 4.82, 0.40, color)
            # Vertical iron mullions and a horizontal divider.
            box(0.51, 3.98, z + dz, 0.06, 1.72, 0.05, 3)
            box(0.51, 3.94, z + dz, 0.07, 0.055, 0.46, 3)
        # A slim pointed stone hood echoes the larger arch.
        arch_band(z, 0.94, 1.03, 3.68, 4.52, 4.68, 0.60, 0.38, 0, 10)
    # Upper cornice and simple crenellated coping, kept below a tall vault silhouette.
    box(0.0, 5.92, 0.0, 0.90, 0.16, 8.60, 1)
    for z in (-3.0, -1.0, 1.0, 3.0):
        box(0.0, 6.04, z, 0.84, 0.08, 0.32, 0)


def export_glb() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    binary = bytearray()
    buffer_views = []
    accessors = []
    meshes = []
    nodes = []

    def append_accessor(raw: bytes, component_type: int, count: int, typ: str, bounds=None):
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        binary.extend(raw)
        view_i = len(buffer_views)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw), "target": 34962})
        acc = {"bufferView": view_i, "componentType": component_type, "count": count, "type": typ}
        if bounds:
            acc.update(bounds)
        accessors.append(acc)
        return len(accessors) - 1

    for material_i, bucket in enumerate(BUCKETS):
        if not bucket:
            continue
        positions = [v for p, _ in bucket for v in p]
        normals = [v for _, n in bucket for v in n]
        count = len(bucket)
        xs = positions[0::3]
        ys = positions[1::3]
        zs = positions[2::3]
        pos_accessor = append_accessor(struct.pack("<%sf" % len(positions), *positions), 5126, count, "VEC3", {
            "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]
        })
        norm_accessor = append_accessor(struct.pack("<%sf" % len(normals), *normals), 5126, count, "VEC3")
        mesh_i = len(meshes)
        name = MATERIALS[material_i][0]
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": pos_accessor, "NORMAL": norm_accessor}, "material": material_i, "mode": 4}]})
        nodes.append({"name": name, "mesh": mesh_i})

    materials = []
    for name, color, metallic, roughness in MATERIALS:
        materials.append({"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": list(color), "metallicFactor": metallic, "roughnessFactor": roughness
        }, "doubleSided": True})

    while len(binary) % 4:
        binary.append(0)
    gltf = {
        "asset": {"version": "2.0", "generator": "Codex procedural chapel module builder"},
        "scene": 0,
        "scenes": [{"name": "Chapel Nave Module", "nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(binary)}],
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_bytes = bytes(binary)
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    with open(OUT_FILE, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
        f.write(json_bytes)
        f.write(struct.pack("<I4s", len(bin_bytes), b"BIN\x00"))
        f.write(bin_bytes)
    print(f"Wrote {OUT_FILE} ({os.path.getsize(OUT_FILE)} bytes)")
    print(f"Mesh groups: {len(meshes)}; triangles: {sum(len(b) // 3 for b in BUCKETS)}")


def write_png(path: str, width: int, height: int, pixels: bytearray) -> None:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    rows = b"".join(b"\x00" + bytes(pixels[y * width * 3:(y + 1) * width * 3]) for y in range(height))
    payload = b"\x89PNG\r\n\x1a\n"
    payload += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    payload += chunk(b"IDAT", zlib.compress(rows, 7))
    payload += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(payload)


def render_preview() -> None:
    """Render a dependency-free orthographic preview of the exported triangles."""
    width, height = 1280, 960
    background = (37, 34, 31)
    pixels = bytearray(background * (width * height))
    zbuffer = [float("inf")] * (width * height)
    target = (0.0, 3.0, 0.0)
    eye = (13.0, 10.0, 13.0)

    def sub(a, b): return tuple(a[i] - b[i] for i in range(3))
    def dot(a, b): return sum(a[i] * b[i] for i in range(3))
    def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
    def norm(a):
        m = math.sqrt(dot(a, a)) or 1.0
        return tuple(v / m for v in a)

    forward = norm(sub(target, eye))
    right = norm(cross(forward, (0.0, 1.0, 0.0)))
    up = norm(cross(right, forward))
    light = norm((-0.45, 0.82, 0.48))
    scale = 105.0
    mat_colors = [tuple(int(c * 255) for c in m[1][:3]) for m in MATERIALS]

    def project(p):
        rel = sub(p, target)
        sx = width * 0.5 + dot(rel, right) * scale
        sy = height * 0.5 - dot(rel, up) * scale
        depth = dot(sub(p, eye), forward)
        return sx, sy, depth

    for material_i, bucket in enumerate(BUCKETS):
        base = mat_colors[material_i]
        for i in range(0, len(bucket), 3):
            tri = bucket[i:i + 3]
            if len(tri) != 3:
                continue
            normal = tri[0][1]
            illumination = 0.67 + 0.33 * max(0.0, dot(normal, light))
            color = tuple(max(0, min(255, int(c * illumination))) for c in base)
            pts = [project(t[0]) for t in tri]
            min_x = max(0, int(min(p[0] for p in pts)))
            max_x = min(width - 1, int(max(p[0] for p in pts)) + 1)
            min_y = max(0, int(min(p[1] for p in pts)))
            max_y = min(height - 1, int(max(p[1] for p in pts)) + 1)
            x0, y0, d0 = pts[0]
            x1, y1, d1 = pts[1]
            x2, y2, d2 = pts[2]
            area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
            if abs(area) < 1e-8:
                continue
            for py in range(min_y, max_y + 1):
                cy = py + 0.5
                for px in range(min_x, max_x + 1):
                    cx = px + 0.5
                    w0 = ((x1 - cx) * (y2 - cy) - (y1 - cy) * (x2 - cx)) / area
                    w1 = ((x2 - cx) * (y0 - cy) - (y2 - cy) * (x0 - cx)) / area
                    w2 = 1.0 - w0 - w1
                    if w0 >= -1e-6 and w1 >= -1e-6 and w2 >= -1e-6:
                        depth = w0 * d0 + w1 * d1 + w2 * d2
                        idx = py * width + px
                        if depth < zbuffer[idx]:
                            zbuffer[idx] = depth
                            off = idx * 3
                            pixels[off:off + 3] = bytes(color)

    preview_path = os.path.join(ROOT, "art", "previews", "chapel_nave_module.png")
    os.makedirs(os.path.dirname(preview_path), exist_ok=True)
    write_png(preview_path, width, height, pixels)
    print(f"Preview: {preview_path}")


if __name__ == "__main__":
    build_geometry()
    export_glb()
    render_preview()
