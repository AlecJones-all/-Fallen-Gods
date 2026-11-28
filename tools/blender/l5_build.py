"""第5关「沉没大教堂」资产重建 v2 —— 对齐概念图

结构性重建 + 程序化做旧材质烘焙成贴图 + 概念图同款光照。
用法: blender -b -P tools/blender/l5_build.py -- nave|altar|cage|choir

约定: 底面中心为原点、正面朝 +X、单位米、Z 向上（导出转 Y-up）。
产出: art/environments/<名称>/<名称>.glb + 模型预览.png
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix, Euler

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_ROOT = os.path.join(ROOT, "art", "environments")
TAU = math.pi * 2.0


# ================================================================ 基础

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def bsdf_of(mat):
    for n in mat.node_tree.nodes:
        if n.bl_idname == "ShaderNodeBsdfPrincipled":
            return n
    return None


def obj_from_bm(bm, name, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if material:
        ob.data.materials.append(material)
    return ob


def box(name, material, center, size, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
    if rot is not None:
        m = rot.to_matrix().to_4x4() @ m
    m = Matrix.Translation(Vector(center)) @ m
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return obj_from_bm(bm, name, material)


def cyl(name, material, a, b, r0, r1=None, seg=16, smooth=True):
    if r1 is None:
        r1 = r0
    a = Vector(a)
    b = Vector(b)
    d = b - a
    L = d.length
    if L < 1e-6:
        return None
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r0, radius2=r1, depth=L)
    z = d.normalized()
    up = Vector((0, 0, 1))
    if abs(z.dot(up)) > 0.999:
        R = Matrix.Identity(4)
    else:
        axis = up.cross(z).normalized()
        ang = math.acos(max(-1.0, min(1.0, up.dot(z))))
        R = Matrix.Rotation(ang, 4, axis)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ R, verts=bm.verts)
    ob = obj_from_bm(bm, name, material)
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    return ob


def torus(name, material, center, axis, R, r, seg_major=20, seg_minor=8):
    bm = bmesh.new()
    ax = Vector(axis).normalized()
    up = Vector((0, 0, 1))
    if abs(ax.dot(up)) > 0.999:
        rot = Matrix.Identity(3)
    else:
        a = up.cross(ax).normalized()
        rot = Matrix.Rotation(math.acos(max(-1.0, min(1.0, up.dot(ax)))), 3, a)
    rings = []
    for i in range(seg_major):
        t = TAU * i / seg_major
        c = Vector((math.cos(t) * R, math.sin(t) * R, 0.0))
        rad = Vector((math.cos(t), math.sin(t), 0.0))
        ring = []
        for j in range(seg_minor):
            p = TAU * j / seg_minor
            v = c + rad * (math.cos(p) * r) + Vector((0, 0, math.sin(p) * r))
            ring.append(bm.verts.new(rot @ v + Vector(center)))
        rings.append(ring)
    for i in range(seg_major):
        r0 = rings[i]
        r1 = rings[(i + 1) % seg_major]
        for j in range(seg_minor):
            j2 = (j + 1) % seg_minor
            bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))
    bm.normal_update()
    ob = obj_from_bm(bm, name, material)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def ico(name, material, center, radius, scale=(1, 1, 1), rot_z=0.0, subdiv=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot_z, 4, 'Z') @ \
        Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0)))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return obj_from_bm(bm, name, material)


def lancet_points(span, spring, apex_scale=1.0, steps=26):
    """等边尖拱中心线 (u, z)；左半圆心 +span/2，右半圆心 -span/2"""
    half = span * 0.5
    R = span
    n = max(steps // 2, 6)
    pts = []
    for i in range(n + 1):
        ang = math.radians(180.0 - 60.0 * i / n)
        pts.append((half + R * math.cos(ang), spring + R * math.sin(ang) * apex_scale))
    for i in range(1, n + 1):
        ang = math.radians(60.0 - 60.0 * i / n)
        pts.append((-half + R * math.cos(ang), spring + R * math.sin(ang) * apex_scale))
    return pts


def lancet_poly(center, span, spring, bottom, scale=1.0):
    pts = [(center - span * 0.5, bottom), (center - span * 0.5, spring)]
    for u, z in lancet_points(span, spring, scale):
        pts.append((center + u, z))
    pts.append((center + span * 0.5, spring))
    pts.append((center + span * 0.5, bottom))
    out = []
    for p in pts:
        if not out or (abs(out[-1][0] - p[0]) > 1e-5 or abs(out[-1][1] - p[1]) > 1e-5):
            out.append(p)
    return out


def sweep_rect(name, material, pts, plane_normal, u_half, w_half, cap=True,
               u_offset=0.0, smooth=True):
    n = Vector(plane_normal).normalized()
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            t = Vector(pts[1]) - Vector(pts[0])
        elif i == len(pts) - 1:
            t = Vector(pts[-1]) - Vector(pts[-2])
        else:
            t = Vector(pts[i + 1]) - Vector(pts[i - 1])
        t = t.normalized()
        r = t.cross(n).normalized()
        c = Vector(p) + r * u_offset
        rings.append([
            bm.verts.new(c + r * (-u_half) + n * (-w_half)),
            bm.verts.new(c + r * (u_half) + n * (-w_half)),
            bm.verts.new(c + r * (u_half) + n * (w_half)),
            bm.verts.new(c + r * (-u_half) + n * (w_half)),
        ])
    for i in range(len(rings) - 1):
        a = rings[i]
        b = rings[i + 1]
        for j in range(4):
            j2 = (j + 1) % 4
            bm.faces.new((a[j], a[j2], b[j2], b[j]))
    if cap:
        bm.faces.new(tuple(reversed(rings[0])))
        bm.faces.new(tuple(rings[-1]))
    bm.normal_update()
    ob = obj_from_bm(bm, name, material)
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    return ob


def prism_yz(name, material, poly_yz, x0, x1):
    bm = bmesh.new()
    a = [bm.verts.new(Vector((x0, p[0], p[1]))) for p in poly_yz]
    b = [bm.verts.new(Vector((x1, p[0], p[1]))) for p in poly_yz]
    bm.faces.new(a)
    bm.faces.new(tuple(reversed(b)))
    n = len(poly_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.normal_update()
    return obj_from_bm(bm, name, material)


def prism_xz(name, material, poly_xz, y0, y1):
    bm = bmesh.new()
    a = [bm.verts.new(Vector((p[0], y0, p[1]))) for p in poly_xz]
    b = [bm.verts.new(Vector((p[0], y1, p[1]))) for p in poly_xz]
    bm.faces.new(a)
    bm.faces.new(tuple(reversed(b)))
    n = len(poly_xz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.normal_update()
    return obj_from_bm(bm, name, material)


def bevel(ob, width=0.012, segments=2, limit_angle=42.0):
    m = ob.modifiers.new("bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(limit_angle)
    return m


def boolean_cut(target, cutter):
    m = target.modifiers.new("bool", 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.object = cutter
    m.solver = 'EXACT'
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def apply_all(ob):
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError:
            ob.modifiers.remove(m)


def join_objects(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def cloth(name, material, top_center, half_w, drop, drift, thick, nu=9, nv=16):
    bm = bmesh.new()
    top = Vector(top_center)
    grid = []
    for j in range(nv + 1):
        t = j / nv
        row = []
        for i in range(nu + 1):
            u = i / nu - 0.5
            x = top.x + u * 2 * half_w + math.sin(t * 3.0) * drift * 0.5
            y = top.y + t * drift
            z = top.z - t * drop
            wob = math.sin(u * 7.0 + t * 5.0) * 0.030 * t + math.sin(t * 11.0) * 0.010
            edge = 1.0 if abs(u) < 0.34 else 1.0 - (t * 0.55 * (abs(u) - 0.34) * 3.0)
            row.append(bm.verts.new(Vector((x, y + wob, z + (1.0 - edge) * 0.30))))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bm.normal_update()
    ob = obj_from_bm(bm, name, material)
    m = ob.modifiers.new("solid", 'SOLIDIFY')
    m.thickness = thick
    m.offset = 0.0
    return ob


def scene_bounds(objs=None):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in (objs or [o for o in bpy.data.objects if o.type == 'MESH']):
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


# ================================================================ 材质（程序化 → 烘焙）

def make_stone(name, dark, mid, light, moss, grain=7.0, lichen=14.0, damp=True):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = bsdf_of(m)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    _link(nt, tc.outputs["Object"], mp.inputs["Vector"])

    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = grain
    n1.inputs["Detail"].default_value = 10.0
    n1.inputs["Roughness"].default_value = 0.62
    _link(nt, mp.outputs["Vector"], n1.inputs["Vector"])
    r1 = nt.nodes.new("ShaderNodeValToRGB")
    r1.color_ramp.elements[0].position = 0.34
    r1.color_ramp.elements[0].color = (dark[0], dark[1], dark[2], 1)
    e = r1.color_ramp.elements[1]
    e.position = 0.72
    e.color = (light[0], light[1], light[2], 1)
    e2 = r1.color_ramp.elements.new(0.53)
    e2.color = (mid[0], mid[1], mid[2], 1)
    _link(nt, n1.outputs["Fac"], r1.inputs["Fac"])

    v1 = nt.nodes.new("ShaderNodeTexVoronoi")
    v1.feature = 'F1'
    v1.inputs["Scale"].default_value = lichen
    _link(nt, mp.outputs["Vector"], v1.inputs["Vector"])
    r2 = nt.nodes.new("ShaderNodeValToRGB")
    r2.color_ramp.elements[0].position = 0.50
    r2.color_ramp.elements[0].color = (0, 0, 0, 1)
    r2.color_ramp.elements[1].position = 0.78
    r2.color_ramp.elements[1].color = (1, 1, 1, 1)
    _link(nt, v1.outputs["Distance"], r2.inputs["Fac"])
    mix1 = nt.nodes.new("ShaderNodeMixRGB")
    mix1.blend_type = 'MIX'
    mix1.inputs["Fac"].default_value = 0.0
    _link(nt, r2.outputs["Color"], mix1.inputs["Fac"])
    mix1.inputs["Fac"].default_value = 0.22
    _link(nt, r1.outputs["Color"], mix1.inputs["Color1"])
    mix1.inputs["Color2"].default_value = (moss[0], moss[1], moss[2], 1)

    # 暖色旧渍：低频、黄褐
    n3 = nt.nodes.new("ShaderNodeTexNoise")
    n3.inputs["Scale"].default_value = 1.7
    n3.inputs["Detail"].default_value = 5.0
    _link(nt, mp.outputs["Vector"], n3.inputs["Vector"])
    r4 = nt.nodes.new("ShaderNodeValToRGB")
    r4.color_ramp.elements[0].position = 0.46
    r4.color_ramp.elements[0].color = (0, 0, 0, 1)
    r4.color_ramp.elements[1].position = 0.78
    r4.color_ramp.elements[1].color = (1, 1, 1, 1)
    _link(nt, n3.outputs["Fac"], r4.inputs["Fac"])
    mix0 = nt.nodes.new("ShaderNodeMixRGB")
    mix0.blend_type = 'MIX'
    _link(nt, r4.outputs["Color"], mix0.inputs["Fac"])
    _link(nt, mix1.outputs["Color"], mix0.inputs["Color1"])
    mix0.inputs["Color2"].default_value = (0.255, 0.205, 0.150, 1)

    v2 = nt.nodes.new("ShaderNodeTexVoronoi")
    v2.feature = 'DISTANCE_TO_EDGE'
    v2.inputs["Scale"].default_value = 9.0
    _link(nt, mp.outputs["Vector"], v2.inputs["Vector"])
    r3 = nt.nodes.new("ShaderNodeValToRGB")
    r3.color_ramp.elements[0].position = 0.0
    r3.color_ramp.elements[0].color = (0, 0, 0, 1)
    r3.color_ramp.elements[1].position = 0.010
    r3.color_ramp.elements[1].color = (1, 1, 1, 1)
    _link(nt, v2.outputs["Distance"], r3.inputs["Fac"])
    mix2 = nt.nodes.new("ShaderNodeMixRGB")
    mix2.blend_type = 'MIX'
    mix2.inputs["Fac"].default_value = 0.55
    _link(nt, r3.outputs["Color"], mix2.inputs["Fac"])
    _link(nt, mix0.outputs["Color"], mix2.inputs["Color1"])
    mix2.inputs["Color2"].default_value = (0.055, 0.055, 0.052, 1)

    out = mix2.outputs["Color"]
    if damp:
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        _link(nt, tc.outputs["Object"], sep.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.0
        mr.inputs["From Max"].default_value = 0.85
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.0
        _link(nt, sep.outputs["Z"], mr.inputs["Value"])
        mix3 = nt.nodes.new("ShaderNodeMixRGB")
        mix3.blend_type = 'MIX'
        _link(nt, mr.outputs["Result"], mix3.inputs["Fac"])
        _link(nt, out, mix3.inputs["Color1"])
        mix3.inputs["Color2"].default_value = (0.075, 0.085, 0.062, 1)
        out = mix3.outputs["Color"]

    _link(nt, out, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.86
    bsdf.inputs["Metallic"].default_value = 0.0
    return m


def make_metal(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = bsdf_of(m)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    _link(nt, tc.outputs["Object"], mp.inputs["Vector"])
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 26.0
    n1.inputs["Detail"].default_value = 8.0
    _link(nt, mp.outputs["Vector"], n1.inputs["Vector"])
    r1 = nt.nodes.new("ShaderNodeValToRGB")
    r1.color_ramp.elements[0].position = 0.42
    r1.color_ramp.elements[0].color = (0.055, 0.060, 0.070, 1)
    r1.color_ramp.elements[1].position = 0.60
    r1.color_ramp.elements[1].color = (0.205, 0.220, 0.232, 1)
    e = r1.color_ramp.elements.new(0.80)
    e.color = (0.28, 0.145, 0.065, 1)
    _link(nt, n1.outputs["Fac"], r1.inputs["Fac"])
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 4.0
    n2.inputs["Detail"].default_value = 6.0
    _link(nt, mp.outputs["Vector"], n2.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = 'MULTIPLY'
    mix.inputs["Fac"].default_value = 0.35
    _link(nt, n2.outputs["Fac"], mix.inputs["Fac"])
    _link(nt, r1.outputs["Color"], mix.inputs["Color1"])
    mix.inputs["Color2"].default_value = (0.55, 0.55, 0.55, 1)
    _link(nt, mix.outputs["Color"], bsdf.inputs["Base Color"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["To Min"].default_value = 0.34
    mr.inputs["To Max"].default_value = 0.72
    _link(nt, n1.outputs["Fac"], mr.inputs["Value"])
    _link(nt, mr.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.45
    return m


def make_wood(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = bsdf_of(m)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    _link(nt, tc.outputs["Object"], mp.inputs["Vector"])
    w = nt.nodes.new("ShaderNodeTexWave")
    w.inputs["Scale"].default_value = 5.0
    w.inputs["Distortion"].default_value = 7.0
    w.inputs["Detail"].default_value = 4.0
    _link(nt, mp.outputs["Vector"], w.inputs["Vector"])
    r1 = nt.nodes.new("ShaderNodeValToRGB")
    r1.color_ramp.elements[0].position = 0.28
    r1.color_ramp.elements[0].color = (0.042, 0.032, 0.024, 1)
    r1.color_ramp.elements[1].position = 0.74
    r1.color_ramp.elements[1].color = (0.145, 0.108, 0.074, 1)
    _link(nt, w.outputs["Fac"], r1.inputs["Fac"])
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 30.0
    _link(nt, mp.outputs["Vector"], n1.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = 'MULTIPLY'
    mix.inputs["Fac"].default_value = 0.4
    _link(nt, n1.outputs["Fac"], mix.inputs["Fac"])
    _link(nt, r1.outputs["Color"], mix.inputs["Color1"])
    mix.inputs["Color2"].default_value = (0.70, 0.70, 0.70, 1)
    _link(nt, mix.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    return m


def make_flat(name, color, rough=0.6, metal=0.0, alpha=1.0, scale_noise=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = bsdf_of(m)
    if scale_noise > 0.0:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        n1 = nt.nodes.new("ShaderNodeTexNoise")
        n1.inputs["Scale"].default_value = scale_noise
        n1.inputs["Detail"].default_value = 6.0
        _link(nt, tc.outputs["Object"], n1.inputs["Vector"])
        r1 = nt.nodes.new("ShaderNodeValToRGB")
        r1.color_ramp.elements[0].position = 0.34
        r1.color_ramp.elements[0].color = (color[0] * 0.80, color[1] * 0.80, color[2] * 0.80, 1)
        r1.color_ramp.elements[1].position = 0.70
        r1.color_ramp.elements[1].color = (color[0], color[1], color[2], 1)
        _link(nt, n1.outputs["Fac"], r1.inputs["Fac"])
        _link(nt, r1.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        for attr, val in (("blend_method", 'BLEND'), ("surface_render_method", 'BLENDED')):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    return m


def _link(nt, a, b):
    nt.links.new(a, b)


def build_materials():
    return {
        "stone": make_stone("stone", (0.150, 0.134, 0.110), (0.300, 0.283, 0.240),
                            (0.505, 0.478, 0.412), (0.235, 0.252, 0.152), 9.0, 22.0),
        "stone_light": make_stone("stone_light", (0.310, 0.305, 0.268), (0.510, 0.500, 0.448),
                                  (0.735, 0.725, 0.650), (0.340, 0.365, 0.262), 10.0, 24.0),
        "stone_dark": make_stone("stone_dark", (0.108, 0.100, 0.092), (0.230, 0.220, 0.205),
                                 (0.410, 0.392, 0.355), (0.190, 0.196, 0.150), 11.0, 20.0,
                                 damp=False),
        "stone_soot": make_stone("stone_soot", (0.060, 0.056, 0.052), (0.140, 0.133, 0.122),
                                 (0.300, 0.285, 0.258), (0.150, 0.160, 0.115), 13.0, 17.0,
                                 damp=False),
        "iron": make_metal("iron"),
        "wood": make_wood("wood"),
        "wax": make_flat("wax", (0.86, 0.75, 0.53), 0.40, 0.0, 1.0, 18.0),
        "water": make_flat("water", (0.045, 0.085, 0.085), 0.08, 0.15, 1.0, 3.0),
        "cloth": make_flat("cloth", (0.62, 0.60, 0.54), 0.88, 0.0, 0.42, 40.0),
    }


# ================================================================ UV + 烘焙

def uv_bake(ob, size=2048):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.004)
    bpy.ops.object.mode_set(mode='OBJECT')

    bpy.ops.object.material_slot_remove_unused()
    img = bpy.data.images.new("atlas_" + ob.name, size, size, alpha=False)
    for slot in ob.material_slots:
        mat = slot.material
        if mat is None:
            continue
        nt = mat.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.location = (-1200, 400)
        for n in nt.nodes:
            n.select = False
        tex.select = True
        nt.nodes.active = tex

    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 4
    sc.render.bake.margin = 8
    sc.render.bake.use_clear = True
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    bpy.ops.object.bake(type='DIFFUSE')

    for slot in ob.material_slots:
        mat = slot.material
        if mat is None:
            continue
        nt = mat.node_tree
        bsdf = bsdf_of(mat)
        for n in nt.nodes:
            if n.bl_idname == "ShaderNodeTexImage":
                nt.links.new(n.outputs["Color"], bsdf.inputs["Base Color"])
                break
    return img


# ================================================================ 渲染（对齐概念图）

def setup_render(bg=(0.232, 0.238, 0.246), samples=48, res=1024):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.85

    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    nt = world.node_tree
    bgn = [n for n in nt.nodes if n.bl_idname == "ShaderNodeBackground"][0]
    lin = tuple(((c / 12.92) if c <= 0.04045 else (((c + 0.055) / 1.055) ** 2.4)) for c in bg)
    bgn.inputs[0].default_value = (lin[0], lin[1], lin[2], 1.0)
    bgn.inputs[1].default_value = 1.0
    sc.world = world


def add_lights():
    key = bpy.data.lights.new("key", 'SUN')
    key.energy = 3.4
    key.angle = math.radians(22.0)
    key.color = (1.0, 0.97, 0.93)
    ko = bpy.data.objects.new("key", key)
    bpy.context.collection.objects.link(ko)
    ko.rotation_euler = Euler((math.radians(52), 0.0, math.radians(-125)), 'XYZ')

    fill = bpy.data.lights.new("fill", 'SUN')
    fill.energy = 0.55
    fill.angle = math.radians(45.0)
    fill.color = (0.74, 0.82, 0.95)
    fo = bpy.data.objects.new("fill", fill)
    bpy.context.collection.objects.link(fo)
    fo.rotation_euler = Euler((math.radians(66), 0.0, math.radians(58)), 'XYZ')

    bounce = bpy.data.lights.new("bounce", 'SUN')
    bounce.energy = 0.30
    bounce.angle = math.radians(60.0)
    bounce.color = (0.80, 0.84, 0.90)
    bo = bpy.data.objects.new("bounce", bounce)
    bpy.context.collection.objects.link(bo)
    bo.rotation_euler = Euler((math.radians(-105), 0.0, math.radians(40)), 'XYZ')


def add_camera(center, margin=1.08, yaw=42.0, pitch=38.0):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = 'ORTHO'
    cam_data.clip_start = 0.1
    cam_data.clip_end = 2000.0
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    yr = math.radians(yaw)
    pr = math.radians(pitch)
    d = Vector((math.cos(pr) * math.cos(yr), math.cos(pr) * math.sin(yr), math.sin(pr)))
    cam.location = Vector(center) + d * 80.0
    cam.rotation_euler = (Vector(center) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    hx = hy = 0.0
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        for corner in o.bound_box:
            p = inv @ (o.matrix_world @ Vector(corner))
            hx = max(hx, abs(p.x))
            hy = max(hy, abs(p.y))
    cam_data.ortho_scale = 2.0 * max(hx, hy) * margin
    bpy.context.scene.camera = cam
    return cam


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.context.scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)


def apply_all(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError:
            ob.modifiers.remove(m)


def bv(ob, w=0.012, seg=2, ang=42.0):
    """倒角并立刻应用（join 会丢掉非活动物体的修改器）"""
    if ob is None:
        return None
    bevel(ob, w, seg, ang)
    apply_all(ob)
    return ob


# ================================================================ 1. 中殿（方形拱廊亭）

def build_nave(M):
    S = M["stone"]
    FD = M["stone_dark"]
    parts = []
    SIDE = 4.10
    SPRING = 4.56
    APEX_SC = 0.62
    SPAN = 3.30

    # 地台：三层收分 + 铺装
    parts.append(bv(box("plat_a", S, (0, 0, -0.20), (9.15, 9.15, 0.07)), 0.014))
    parts.append(bv(box("plat_b", S, (0, 0, -0.125), (8.95, 8.95, 0.075)), 0.012))
    parts.append(bv(box("plat_c", FD, (0, 0, -0.02), (8.72, 8.72, 0.06)), 0.010))
    tile = 1.02
    for ix in range(8):
        for iy in range(8):
            tx = -SIDE + 0.51 + ix * tile
            ty = -SIDE + 0.51 + iy * tile
            if abs(tx) > SIDE - 0.2 or abs(ty) > SIDE - 0.2:
                continue
            parts.append(bv(box("tile", FD, (tx, ty, 0.011),
                                (tile - 0.032, tile - 0.032, 0.022)), 0.006))

    # 八根束柱：加粗一档
    supports = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            supports.append((sx * SIDE, sy * SIDE))
    supports += [(0.0, -SIDE), (0.0, SIDE), (-SIDE, 0.0), (SIDE, 0.0)]

    for (px, py) in supports:
        parts.append(bv(box("pier_plinth", S, (px, py, 0.18), (1.18, 1.18, 0.36)), 0.022))
        parts.append(bv(box("pier_base2", S, (px, py, 0.45), (1.00, 1.00, 0.18)), 0.016))
        parts.append(bv(box("pier_base3", S, (px, py, 0.56), (0.88, 0.88, 0.06)), 0.012))
        parts.append(bv(cyl("pier_core", S, (px, py, 0.59), (px, py, SPRING - 0.28), 0.340, 0.322, 22), 0.0))
        for k in range(4):
            ang = TAU * k / 4.0 + math.pi * 0.25
            ox = math.cos(ang) * 0.318
            oy = math.sin(ang) * 0.318
            parts.append(bv(cyl("pier_shaft", S, (px + ox, py + oy, 0.59),
                                (px + ox, py + oy, SPRING - 0.26), 0.158, 0.146, 16), 0.0))
        parts.append(bv(torus("pier_ring1", S, (px, py, SPRING - 0.32), (0, 0, 1), 0.340, 0.050, 26, 10), 0.0))
        parts.append(bv(torus("pier_ring2", S, (px, py, SPRING - 0.17), (0, 0, 1), 0.352, 0.042, 26, 10), 0.0))
        parts.append(bv(box("pier_cap", S, (px, py, SPRING - 0.06), (0.98, 0.98, 0.13)), 0.016))
        parts.append(bv(box("pier_abacus", S, (px, py, SPRING + 0.04), (0.90, 0.90, 0.10)), 0.014))

    # 八道尖拱：两层券（外券 + 内券）
    def arch(side, c0, c1):
        n = {'x+': (1, 0, 0), 'x-': (1, 0, 0), 'y+': (0, 1, 0), 'y-': (0, 1, 0)}[side]
        fixed = SIDE if side[1] == '+' else -SIDE
        mid = (c0 + c1) * 0.5
        pts = []
        for u, z in lancet_points(SPAN, SPRING, APEX_SC):
            c = mid + u
            pts.append(Vector((fixed, c, z)) if side[0] == 'x' else Vector((c, fixed, z)))
        outer = sweep_rect("arch_out", S, pts, n, 0.24, 0.40)
        inner = sweep_rect("arch_in", S, pts, n, 0.11, 0.30, u_offset=-0.155)
        return [outer, inner]

    sides = [('x+', -SIDE, 0.0), ('x+', 0.0, SIDE), ('x-', -SIDE, 0.0), ('x-', 0.0, SIDE),
             ('y+', -SIDE, 0.0), ('y+', 0.0, SIDE), ('y-', -SIDE, 0.0), ('y-', 0.0, SIDE)]
    broken_arches = {('y-', 0.0, SIDE), ('x-', 0.0, SIDE)}
    for side, c0, c1 in sides:
        obs = arch(side, c0, c1)
        if (side, c0, c1) in broken_arches:
            continue
        for ob in obs:
            parts.append(bv(ob, 0.010))

    # 四分交叉拱：z = min(h(x), h(y))，对角线自然形成拱棱
    apex_z = SPRING + 0.866 * SPAN * APEX_SC
    edge_z = apex_z + 0.06
    boss_z = edge_z + 1.18
    boss = Vector((0, 0, boss_z))

    def h_of(t):
        return boss_z - (boss_z - edge_z) * (t * t)

    def groin_web(sx, sy, n=15):
        bm = bmesh.new()
        grid = []
        for i in range(n + 1):
            row = []
            for j in range(n + 1):
                x = sx * (0.02 + (SIDE - 0.02) * (i / n))
                y = sy * (0.02 + (SIDE - 0.02) * (j / n))
                z = min(h_of(abs(x) / SIDE), h_of(abs(y) / SIDE))
                row.append(bm.verts.new(Vector((x, y, z))))
            grid.append(row)
        for i in range(n):
            for j in range(n):
                # 东南象限开破口
                if sx > 0 and sy < 0 and 5 <= i <= 9 and 4 <= j <= 8:
                    continue
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
        bm.normal_update()
        ob = obj_from_bm(bm, "web", S)
        m = ob.modifiers.new("solid", 'SOLIDIFY')
        m.thickness = 0.18
        m.offset = 0.0
        apply_all(ob)
        return ob

    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(groin_web(sx, sy))

    # 对角拱肋：贴着拱棱
    for (cx, cy) in [(-SIDE, -SIDE), (SIDE, -SIDE), (SIDE, SIDE), (-SIDE, SIDE)]:
        pts = []
        for k in range(13):
            t = 1.0 - k / 12.0
            pts.append(Vector((cx * t, cy * t, boss_z - (boss_z - edge_z) * (t * t) - 0.34)))
        nrm = Vector((-cy, cx, 0)).normalized()
        parts.append(bv(sweep_rect("rib", S, pts, nrm, 0.195, 0.230), 0.008))

    # 宝顶
    parts.append(bv(cyl("boss", S, (0, 0, boss_z - 0.12), (0, 0, boss_z + 0.16), 0.34, 0.24, 18), 0.012))
    parts.append(bv(torus("boss_ring", S, (0, 0, boss_z - 0.02), (0, 0, 1), 0.30, 0.055, 22, 10), 0.0))

    # 断裂落石
    for i in range(9):
        t = i / 9.0
        px = -SIDE + 0.6 + 1.5 * math.sin(t * 5.7)
        py = -SIDE + 0.6 + 1.5 * math.cos(t * 4.3)
        s = 0.14 + 0.10 * (0.5 + 0.5 * math.sin(t * 6.1))
        parts.append(bv(ico("rubble", S, (px, py, s * 0.55), s, (1.5, 1.2, 0.9), t * 2.2, 1), 0.0))
    for i in range(4):
        px = -SIDE + 0.4 + 1.2 * math.sin(i * 2.4)
        py = SIDE - 0.6 - 0.9 * math.cos(i * 1.7)
        parts.append(bv(ico("rubble2", S, (px, py, 0.10), 0.16, (1.2, 1.4, 0.6), i * 1.3, 1), 0.0))

    # 积水
    for i in range(5):
        px = -2.2 + 1.1 * math.sin(i * 2.1)
        py = -2.0 + 1.3 * math.cos(i * 1.4)
        parts.append(box("puddle", M["water"], (px, py, 0.020),
                         (0.80 + 0.45 * math.sin(i), 0.70 + 0.40 * math.cos(i), 0.008)))

    ob = join_objects(parts, "沉没大教堂中殿")
    return ob


# ================================================================ 2. 主教祭坛

def build_altar(M):
    S = M["stone_dark"]
    SO = M["stone_soot"]
    W = M["wax"]
    parts = []
    HALF_X = 1.14
    HALF_Y = 0.82

    # 基座：三级同心收分（四面都有踏面）
    parts.append(bv(box("step_low", SO, (0, 0, 0.055), (3.42, 2.62, 0.11)), 0.014))
    parts.append(bv(box("step_mid", SO, (0, 0, 0.165), (3.28, 2.48, 0.11)), 0.014))
    parts.append(bv(box("plinth", SO, (0, 0, 0.295), (3.12, 2.32, 0.15)), 0.016))

    # 四根方墩
    for sx in (-1, 1):
        for sy in (-1, 1):
            px = sx * HALF_X
            py = sy * HALF_Y
            pier = box("pier", S, (px, py, 0.90), (0.40, 0.40, 1.02))
            boolean_cut(pier, prism_yz("cx", None, lancet_poly(py, 0.25, 1.00, 0.50, 0.78),
                                       px + sx * 0.18, px + sx * 0.31))
            boolean_cut(pier, prism_xz("cy", None, lancet_poly(px, 0.25, 1.00, 0.50, 0.78),
                                       py + sy * 0.18, py + sy * 0.31))
            parts.append(bv(pier, 0.010))
            parts.append(bv(box("pier_foot", S, (px, py, 0.44), (0.46, 0.46, 0.12)), 0.010))
            parts.append(bv(box("pier_cap", S, (px, py, 1.35), (0.48, 0.48, 0.12)), 0.010))

    # 托板 + 倒棱 + 台面（台面与托板用烟熏石）
    parts.append(bv(box("corbel", SO, (0, 0, 1.455), (2.64, 1.88, 0.11)), 0.012))
    parts.append(bv(box("chamfer", SO, (0, 0, 1.525), (2.78, 2.00, 0.055)), 0.012))
    mensa = box("mensa", SO, (0, 0, 1.635), (2.90, 2.10, 0.20))
    # 台面裂纹
    for i in range(7):
        boolean_cut(mensa, box("cr", None,
                               (-0.95 + i * 0.32, 0.22 * math.sin(i * 1.9), 1.76),
                               (0.013, 1.75, 0.02)))
    boolean_cut(mensa, box("cr2", None, (0.12, 0.15, 1.76), (1.70, 0.013, 0.02)))
    # 底面凿痕：沿边缘啃掉不规则小块
    chips = [
        (1.30, -0.55, 0.10, 0.07), (1.34, 0.10, 0.09, 0.06), (1.28, 0.62, 0.12, 0.08),
        (-1.31, -0.30, 0.10, 0.07), (-1.27, 0.45, 0.11, 0.06),
        (0.15, 1.02, 0.09, 0.10), (-0.55, -1.01, 0.10, 0.09), (0.72, -1.02, 0.08, 0.08),
    ]
    for (cxp, cyp, cw, cd) in chips:
        boolean_cut(mensa, box("chip", None, (cxp, cyp, 1.535),
                               (cw, cd, 0.055), rot=Euler((0, 0, cxp * 1.7))))
    # 台面边缘磕损
    for i in range(5):
        boolean_cut(mensa, box("chip2", None,
                               (-1.45 + 0.72 * i, (-1.05 if i % 2 else 1.05), 1.70),
                               (0.14, 0.10, 0.06), rot=Euler((0, 0, 0.6 * i))))
    parts.append(bv(mensa, 0.010))

    # 蜡泪：上厚下细，中段带垂坠鼓包
    edges = [
        ("x", 1.445, -1.04, 1.04, 12),
        ("x", -1.445, -1.04, 1.04, 9),
        ("y", 1.04, -1.44, 1.44, 10),
        ("y", -1.04, -1.44, 1.44, 9),
    ]
    idx = 0
    for kind, fix, a0, a1, cnt in edges:
        for k in range(cnt):
            t = (k + 0.5) / cnt
            c = a0 + (a1 - a0) * t
            pos = (fix, c) if kind == "x" else (c, fix)
            ln = 0.22 + 0.42 * (0.5 + 0.5 * math.sin(idx * 2.9 + 0.7))
            r = 0.010 + 0.009 * (0.5 + 0.5 * math.cos(idx * 1.9))
            x, y = pos
            z0 = 1.535
            # 根部挂瘤
            parts.append(cyl("wax_root", W, (x, y, z0 + 0.05), (x, y, z0 - 0.03),
                             r * 2.0, r * 1.45, 7))
            # 上段（粗）
            parts.append(cyl("wax_a", W, (x, y, z0 - 0.02), (x, y, z0 - ln * 0.34),
                             r * 1.35, r * 1.05, 7))
            # 中段鼓包
            parts.append(cyl("wax_b", W, (x, y, z0 - ln * 0.34), (x, y, z0 - ln * 0.56),
                             r * 1.05, r * 1.14, 7))
            # 下段细尾
            parts.append(cyl("wax_c", W, (x, y, z0 - ln * 0.56), (x, y, z0 - ln * 0.94),
                             r * 1.14, r * 0.28, 7))
            # 圆头收尾
            parts.append(ico("wax_tip", W, (x, y, z0 - ln * 0.97), r * 0.42, (1, 1, 1.5), 0, 1))
            idx += 1
    ob = join_objects(parts, "主教祭坛")
    return ob


# ================================================================ 3. 悬挂圣徒铁笼

def build_cage(M):
    I = M["iron"]
    parts = []
    half = 0.575
    body_top = 2.35
    dome_top = 3.28
    corners = [(-half, -half), (half, -half), (half, half), (-half, half)]

    # 底框 + 脚
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        parts.append(bv(box("frame", I, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.06),
                         (abs(b[0] - a[0]) + 0.12, abs(b[1] - a[1]) + 0.12, 0.12)), 0.008))
        parts.append(bv(box("foot", I, (a[0], a[1], 0.02), (0.15, 0.15, 0.04)), 0.006))
    for i in range(4):
        y = -half + 0.23 * i
        parts.append(bv(box("grate", I, (0, y, 0.10), (2 * half - 0.04, 0.030, 0.030)), 0.004))

    # 竖条与横箍
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        parts.append(cyl("post", I, (a[0], a[1], 0.12), (a[0], a[1], body_top), 0.040, 0.038, 12))
        for k in range(1, 5):
            t = k / 5.0
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            parts.append(cyl("bar", I, (x, y, 0.12), (x, y, body_top), 0.024, 0.023, 10))
    for z in (0.72, 1.42, 2.10):
        for i in range(4):
            a = corners[i]
            b = corners[(i + 1) % 4]
            parts.append(bv(box("rail", I, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, z),
                             (abs(b[0] - a[0]) + 0.075, abs(b[1] - a[1]) + 0.075, 0.048)), 0.006))
    # 顶部方框
    for i in range(4):
        a = corners[i]
        b = corners[(i + 1) % 4]
        parts.append(bv(box("toprail", I, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, body_top + 0.04),
                         (abs(b[0] - a[0]) + 0.13, abs(b[1] - a[1]) + 0.13, 0.09)), 0.008))

    # 穹顶：8 根拱肋 + 两圈箍
    apex = Vector((0, 0, dome_top))
    base_pts = []
    for i in range(4):
        a = Vector((corners[i][0], corners[i][1], body_top + 0.08))
        b = Vector((corners[(i + 1) % 4][0], corners[(i + 1) % 4][1], body_top + 0.08))
        base_pts.append(a)
        base_pts.append((a + b) * 0.5)
    levels = []
    for p in base_pts:
        out = Vector((p.x, p.y, 0)).normalized()
        nrm = Vector((-p.y, p.x, 0)).normalized()
        pts = []
        for k in range(8):
            t = k / 7.0
            q = p.lerp(apex, t) + out * (math.sin(t * math.pi) * 0.155)
            pts.append(q)
        parts.append(sweep_rect("dome_rib", I, pts, nrm, 0.030, 0.030, True))
        levels.append(pts)
    for frac in (2, 4):
        for i in range(8):
            p0 = levels[i][frac]
            p1 = levels[(i + 1) % 8][frac]
            parts.append(cyl("dome_ring", I, p0, p1, 0.026, 0.026, 8))

    # 顶饰 + 吊环 + 锁链
    parts.append(cyl("finial", I, (0, 0, dome_top - 0.02), (0, 0, dome_top + 0.12), 0.055, 0.035, 12))
    parts.append(torus("finial_ring", I, (0, 0, dome_top + 0.20), (0, 1, 0), 0.065, 0.020, 14, 8))
    for i in range(6):
        z = dome_top + 0.24 + 0.098 * i
        link = torus("chain", I, (0, 0, z), (0, 1, 0) if i % 2 else (1, 0, 0), 0.058, 0.018, 12, 8)
        link.scale = (1.0, 1.0, 1.22)
        parts.append(link)
    parts.append(torus("big_ring", I, (0, 0, dome_top + 0.90), (0, 1, 0), 0.175, 0.028, 24, 10))
    # 侧挂锁链（从顶框垂到中部）
    for i in range(5):
        z = body_top - 0.10 - 0.13 * i
        link = torus("sidechain", I, (half - 0.02 - 0.02 * i, -0.28 - 0.03 * i, z),
                     (0, 1, 0) if i % 2 else (1, 0, 0), 0.055, 0.018, 10, 6)
        link.scale = (1.0, 1.0, 1.25)
        parts.append(link)
    # 门扣
    parts.append(torus("latch", I, (half + 0.03, 0.02, 1.05), (1, 0, 0), 0.075, 0.017, 16, 8))
    parts.append(bv(box("latch_plate", I, (half + 0.01, 0.02, 1.05), (0.045, 0.14, 0.20)), 0.006))

    # 纱幔：从穹顶右前方垂下，盖过笼体
    parts.append(cloth("veil", M["cloth"], (0.46, 0.30, 3.10), 0.26, 2.55, 0.34, 0.012))

    ob = join_objects(parts, "悬挂圣徒铁笼")
    return ob


# ================================================================ 4. 唱诗班楼上层

def build_choir(M):
    S = M["stone_light"]
    W = M["wood"]
    parts = []
    WID = 3.30
    LEN = 6.70
    deck_top = 0.55
    front_x = WID * 0.5 - 0.22
    back_x = -WID * 0.5 + 0.28

    # 楼板 + 基座
    parts.append(bv(box("deck_base", S, (0, 0, 0.09), (WID + 0.16, LEN + 0.16, 0.18)), 0.014))
    parts.append(bv(box("deck", S, (0, 0, 0.40), (WID, LEN, 0.44)), 0.012))
    parts.append(bv(box("deck_edge", S, (0, 0, 0.55), (WID + 0.10, LEN + 0.10, 0.06)), 0.010))

    # 栏杆（正面 + 两端）
    rail_base = deck_top + 0.14
    bal_h = 0.86
    cap_z = rail_base + bal_h + 0.14

    def balustrade(cx, cy, length, along_y=True):
        # 下槛
        if along_y:
            parts.append(bv(box("rail_bot", S, (cx, cy, rail_base), (0.34, length, 0.16)), 0.010))
            parts.append(bv(box("rail_cap", S, (cx, cy, cap_z), (0.40, length, 0.22)), 0.012))
        else:
            parts.append(bv(box("rail_bot", S, (cx, cy, rail_base), (length, 0.34, 0.16)), 0.010))
            parts.append(bv(box("rail_cap", S, (cx, cy, cap_z), (length, 0.40, 0.22)), 0.012))
        n = max(int(length / 0.46), 3)
        pitch = length / n
        for i in range(n + 1):
            off = -length * 0.5 + pitch * i
            px, py = (cx, cy + off) if along_y else (cx + off, cy)
            parts.append(bv(cyl("bal_col", S, (px, py, rail_base + 0.08), (px, py, cap_z - 0.13),
                                0.055, 0.048, 12), 0.0))
            parts.append(bv(torus("bal_ring", S, (px, py, rail_base + 0.16), (0, 0, 1), 0.052, 0.016, 10, 6), 0.0))
            parts.append(bv(box("bal_foot", S, (px, py, rail_base + 0.10), (0.15, 0.15, 0.05)), 0.006))
        for i in range(n):
            off = -length * 0.5 + pitch * (i + 0.5)
            sp = pitch * 0.92
            base = rail_base + 0.18
            pts = []
            for u, z in lancet_points(sp, base, 0.62):
                p = Vector((cx, cy + off + u, z)) if along_y else Vector((cx + off + u, cy, z))
                pts.append(p)
            nrm = (1, 0, 0) if along_y else (0, 1, 0)
            parts.append(bv(sweep_rect("bal_arch", S, pts, nrm, 0.035, 0.09), 0.0))

    balustrade(front_x, 0, LEN - 0.30, True)
    for sy in (-1, 1):
        balustrade(0, sy * (LEN * 0.5 - 0.20), WID - 0.34, False)

    # 后墙：三段盲拱 + 四叶饰带
    wall_h = 2.80
    wall = box("wall", S, (back_x, 0, deck_top + wall_h * 0.5), (0.56, LEN, wall_h))
    bay = LEN / 3.0
    for b in range(3):
        yc = -LEN * 0.5 + bay * (b + 0.5)
        poly = lancet_poly(yc, bay * 0.62, deck_top + 1.55, deck_top + 0.42, 0.86)
        boolean_cut(wall, prism_yz("cut", None, poly, back_x + 0.22, back_x + 0.40))
    parts.append(bv(wall, 0.010))
    # 墙角柱
    for sy in (-1, 1):
        parts.append(bv(box("wall_pilaster", S, (back_x, sy * (LEN * 0.5 - 0.14),
                          deck_top + wall_h * 0.5), (0.68, 0.36, wall_h)), 0.010))
    # 四叶饰带
    band_z = deck_top + wall_h - 0.28
    parts.append(bv(box("frieze", S, (back_x + 0.26, 0, band_z), (0.10, LEN - 0.1, 0.30)), 0.008))
    for i in range(11):
        yc = -LEN * 0.46 + (LEN * 0.92 / 10.0) * i
        for k in range(4):
            ang = TAU * k / 4.0
            parts.append(bv(torus("quatrefoil", S,
                                  (back_x + 0.32, yc + math.cos(ang) * 0.045, band_z + math.sin(ang) * 0.045),
                                  (0, 1, 0), 0.058, 0.014, 10, 6), 0.0))
    parts.append(bv(box("wall_cap", S, (back_x, 0, deck_top + wall_h + 0.06), (0.72, LEN + 0.10, 0.16)), 0.012))

    # 墙顶木唱诗席（带尖顶罩棚）
    seat_z = deck_top + wall_h + 0.14
    for i in range(4):
        yc = -LEN * 0.36 + (LEN * 0.72 / 3.0) * i
        parts.append(bv(box("stall_seat", W, (back_x + 0.10, yc, seat_z + 0.06), (0.72, 1.05, 0.10)), 0.008))
        parts.append(bv(box("stall_back", W, (back_x - 0.20, yc, seat_z + 0.55), (0.10, 1.05, 1.00)), 0.008))
        # 尖顶罩棚：三根细尖柱
        for k in (-1, 0, 1):
            px = back_x - 0.02 + 0.24 * k
            parts.append(bv(box("pinnacle", W, (px, yc + 0.42 * k, seat_z + 0.85),
                                (0.085, 0.085, 0.72)), 0.005))
            parts.append(bv(cyl("pinnacle_tip", W, (px, yc + 0.42 * k, seat_z + 1.20),
                                (px, yc + 0.42 * k, seat_z + 1.92), 0.070, 0.004, 6, smooth=False), 0.0))
            for kk in (-1, 1):
                parts.append(bv(cyl("crocket", W, (px + 0.05 * kk, yc + 0.42 * k, seat_z + 1.45),
                                    (px + 0.11 * kk, yc + 0.42 * k, seat_z + 1.52), 0.020, 0.004, 5,
                                    smooth=False), 0.0))
        parts.append(bv(box("canopy_rail", W, (back_x + 0.02, yc, seat_z + 1.30), (0.26, 1.02, 0.06)), 0.005))

    ob = join_objects(parts, "唱诗班楼上层")
    return ob


# ================================================================ 主流程

BUILDERS = {
    "nave": (build_nave, "沉没大教堂中殿"),
    "altar": (build_altar, "主教祭坛"),
    "cage": (build_cage, "悬挂圣徒铁笼"),
    "choir": (build_choir, "唱诗班楼上层"),
}


def main():
    argv = sys.argv
    key = "altar"
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if rest:
            key = rest[0]

    clear_scene()
    M = build_materials()
    fn, cn = BUILDERS[key]
    bpy.context.scene.unit_settings.system = 'METRIC'
    ob = fn(M)
    apply_all(ob)

    # 底面落到 z=0
    lo, hi = scene_bounds([ob])
    ob.location.z -= lo.z
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    lo, hi = scene_bounds([ob])
    print("BOUNDS", [round(v, 3) for v in lo], [round(v, 3) for v in hi])

    size = 2048 if key in ("nave", "choir") else 1024
    uv_bake(ob, size)

    dir_path = os.path.join(OUT_ROOT, cn)
    os.makedirs(dir_path, exist_ok=True)
    glb = os.path.join(dir_path, cn + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("EXPORT", glb, "tris=", tris)

    center = (lo + hi) * 0.5
    setup_render()
    add_lights()
    add_camera(center)
    render_to(os.path.join(dir_path, "模型预览.png"))
    print("DONE", cn)


main()
