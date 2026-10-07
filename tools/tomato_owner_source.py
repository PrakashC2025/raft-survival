"""
Realistic procedural tomato plant for Blender (3.x / 4.x / 5.x, Cycles).

HOW TO USE
1. Open Blender -> Scripting workspace -> Open this file -> Run Script (Alt+P).
2. Switch viewport to Rendered mode (Cycles) or press F12 to render.
   Everything is procedural (no image textures needed).

Set RENDER_PREVIEW_PATH below to auto-render a PNG when running headless:
    blender -b -P tomato_plant.py
"""
import bpy
import bmesh
import math
import random
from mathutils import Vector, noise

SEED = 11
RENDER_PREVIEW_PATH = ""      # e.g. "/tmp/tomato.png" to render automatically
SAMPLES = 128

random.seed(SEED)

# --------------------------------------------------------------------------
# Scene reset
# --------------------------------------------------------------------------
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras):
    for blk in list(coll):
        coll.remove(blk)

SCENE = bpy.context.scene
COL = SCENE.collection


def link(ob):
    COL.objects.link(ob)
    return ob


# --------------------------------------------------------------------------
# Shader helpers
# --------------------------------------------------------------------------
def P(bsdf, **kw):
    """Set Principled inputs, tolerant of 3.x vs 4.x socket names."""
    alias = {
        'Subsurface Weight': ['Subsurface Weight', 'Subsurface'],
        'Coat Weight': ['Coat Weight', 'Clearcoat'],
        'Coat Roughness': ['Coat Roughness', 'Clearcoat Roughness'],
        'Specular IOR Level': ['Specular IOR Level', 'Specular'],
        'Sheen Weight': ['Sheen Weight', 'Sheen'],
    }
    for k, v in kw.items():
        for name in alias.get(k, [k]):
            if name in bsdf.inputs:
                bsdf.inputs[name].default_value = v
                break


def new_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes
    l = m.node_tree.links
    return m, n, l, n['Principled BSDF'], n['Material Output']


def ramp(nodes, stops):
    """Colour ramp from sorted [(pos, (r,g,b,a)), ...]."""
    r = nodes.new('ShaderNodeValToRGB')
    el = r.color_ramp.elements
    el[0].position = stops[0][0]
    el[1].position = stops[-1][0]
    for p, _ in stops[1:-1]:
        el.new(p)
    for e, (_, c) in zip(el, stops):
        e.color = c
    return r


def noise_node(nodes, scale, detail=6.0, rough=0.55, distortion=0.0):
    nd = nodes.new('ShaderNodeTexNoise')
    nd.inputs['Scale'].default_value = scale
    nd.inputs['Detail'].default_value = detail
    nd.inputs['Roughness'].default_value = rough
    if 'Distortion' in nd.inputs:
        nd.inputs['Distortion'].default_value = distortion
    return nd


def math_node(nodes, op, a=None, b=None):
    m = nodes.new('ShaderNodeMath')
    m.operation = op
    if a is not None:
        m.inputs[0].default_value = a
    if b is not None:
        m.inputs[1].default_value = b
    return m


def mix_rgb(nodes, fac=0.5, blend='MIX'):
    m = nodes.new('ShaderNodeMixRGB')
    m.blend_type = blend
    m.inputs['Fac'].default_value = fac
    return m


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------
def leaf_material():
    m, n, l, b, out = new_mat('TomatoLeaf')
    tc = n.new('ShaderNodeTexCoord')

    # leaf vein network (small veins) + midrib, built on the leaf UVs
    vor = n.new('ShaderNodeTexVoronoi')
    vor.feature = 'DISTANCE_TO_EDGE'
    vor.inputs['Scale'].default_value = 15
    l.new(tc.outputs['UV'], vor.inputs['Vector'])
    vr = ramp(n, [(0.0, (1, 1, 1, 1)), (0.07, (0, 0, 0, 1))])
    l.new(vor.outputs['Distance'], vr.inputs['Fac'])

    sep = n.new('ShaderNodeSeparateXYZ')
    l.new(tc.outputs['UV'], sep.inputs['Vector'])
    sub = math_node(n, 'SUBTRACT', b=0.5)
    l.new(sep.outputs['X'], sub.inputs[0])
    ab = math_node(n, 'ABSOLUTE')
    l.new(sub.outputs['Value'], ab.inputs[0])
    mr = ramp(n, [(0.0, (1, 1, 1, 1)), (0.03, (0, 0, 0, 1))])
    l.new(ab.outputs['Value'], mr.inputs['Fac'])

    veins = math_node(n, 'MAXIMUM')
    l.new(vr.outputs['Color'], veins.inputs[0])
    l.new(mr.outputs['Color'], veins.inputs[1])

    # colour variation
    nz = noise_node(n, 9, 8, 0.6, 0.4)
    l.new(tc.outputs['UV'], nz.inputs['Vector'])
    cr = ramp(n, [(0.25, (0.020, 0.095, 0.015, 1)), (0.75, (0.055, 0.210, 0.030, 1))])
    l.new(nz.outputs['Fac'], cr.inputs['Fac'])
    mix = mix_rgb(n, 0.0)
    mix.inputs['Color2'].default_value = (0.13, 0.33, 0.06, 1)
    vscale = math_node(n, 'MULTIPLY', b=0.55)
    l.new(veins.outputs['Value'], vscale.inputs[0])
    l.new(vscale.outputs['Value'], mix.inputs['Fac'])
    l.new(cr.outputs['Color'], mix.inputs['Color1'])

    # bump: sunken veins + rugose surface
    nzs = noise_node(n, 60, 4, 0.5)
    l.new(tc.outputs['UV'], nzs.inputs['Vector'])
    ns = math_node(n, 'MULTIPLY', b=0.3)
    l.new(nzs.outputs['Fac'], ns.inputs[0])
    h = math_node(n, 'ADD')
    l.new(veins.outputs['Value'], h.inputs[0])
    l.new(ns.outputs['Value'], h.inputs[1])
    bump = n.new('ShaderNodeBump')
    bump.invert = True
    bump.inputs['Strength'].default_value = 0.7
    bump.inputs['Distance'].default_value = 0.004
    l.new(h.outputs['Value'], bump.inputs['Height'])

    l.new(mix.outputs['Color'], b.inputs['Base Color'])
    l.new(bump.outputs['Normal'], b.inputs['Normal'])
    P(b, **{'Roughness': 0.48, 'Subsurface Weight': 0.12, 'Specular IOR Level': 0.45,
            'Sheen Weight': 0.25})

    # thin-leaf light transmission
    tr = n.new('ShaderNodeBsdfTranslucent')
    tr.inputs['Color'].default_value = (0.18, 0.45, 0.05, 1)
    l.new(bump.outputs['Normal'], tr.inputs['Normal'])
    ms = n.new('ShaderNodeMixShader')
    ms.inputs['Fac'].default_value = 0.28
    l.new(b.outputs['BSDF'], ms.inputs[1])
    l.new(tr.outputs['BSDF'], ms.inputs[2])
    l.new(ms.outputs['Shader'], out.inputs['Surface'])
    return m


def stem_material():
    m, n, l, b, out = new_mat('TomatoStem')
    tc = n.new('ShaderNodeTexCoord')
    nz = noise_node(n, 18, 8, 0.6, 0.2)
    l.new(tc.outputs['Object'], nz.inputs['Vector'])
    cr = ramp(n, [(0.3, (0.030, 0.12, 0.02, 1)), (0.7, (0.12, 0.24, 0.05, 1))])
    l.new(nz.outputs['Fac'], cr.inputs['Fac'])
    fine = noise_node(n, 400, 3, 0.5)
    l.new(tc.outputs['Object'], fine.inputs['Vector'])
    bump = n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.6
    bump.inputs['Distance'].default_value = 0.0015
    l.new(fine.outputs['Fac'], bump.inputs['Height'])
    l.new(cr.outputs['Color'], b.inputs['Base Color'])
    l.new(bump.outputs['Normal'], b.inputs['Normal'])
    # sheen fakes the fine hairs (trichomes) that tomato stems have
    P(b, **{'Roughness': 0.55, 'Sheen Weight': 0.9, 'Subsurface Weight': 0.08})
    return m


def tomato_material(name, bottom, top, rough=0.27):
    m, n, l, b, out = new_mat(name)
    tc = n.new('ShaderNodeTexCoord')
    # darker/greener shoulders, richer colour at the bottom
    cr = ramp(n, [(0.25, bottom), (0.95, top)])
    sep = n.new('ShaderNodeSeparateXYZ')
    l.new(tc.outputs['Generated'], sep.inputs['Vector'])
    l.new(sep.outputs['Z'], cr.inputs['Fac'])

    nz = noise_node(n, 7, 6, 0.6, 0.5)
    l.new(tc.outputs['Generated'], nz.inputs['Vector'])
    var = ramp(n, [(0.3, (0.82, 0.82, 0.82, 1)), (0.7, (1.0, 1.0, 1.0, 1))])
    l.new(nz.outputs['Fac'], var.inputs['Fac'])
    mul = mix_rgb(n, 1.0, 'MULTIPLY')
    l.new(cr.outputs['Color'], mul.inputs['Color1'])
    l.new(var.outputs['Color'], mul.inputs['Color2'])

    fine = noise_node(n, 220, 3, 0.5)
    l.new(tc.outputs['Generated'], fine.inputs['Vector'])
    bump = n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.08
    bump.inputs['Distance'].default_value = 0.0008
    l.new(fine.outputs['Fac'], bump.inputs['Height'])

    l.new(mul.outputs['Color'], b.inputs['Base Color'])
    l.new(bump.outputs['Normal'], b.inputs['Normal'])
    P(b, **{'Roughness': rough, 'Coat Weight': 0.55, 'Coat Roughness': 0.08,
            'Subsurface Weight': 0.25, 'Specular IOR Level': 0.55})
    if 'Subsurface Scale' in b.inputs:
        b.inputs['Subsurface Scale'].default_value = 0.012
    if 'Subsurface Radius' in b.inputs:
        b.inputs['Subsurface Radius'].default_value = (1.0, 0.25, 0.12)
    return m


def flat_mat(name, color, rough=0.5):
    m, n, l, b, out = new_mat(name)
    b.inputs['Base Color'].default_value = color
    P(b, Roughness=rough)
    return m


def terracotta_material():
    m, n, l, b, out = new_mat('Terracotta')
    tc = n.new('ShaderNodeTexCoord')
    nz = noise_node(n, 5, 8, 0.65, 0.3)
    l.new(tc.outputs['Object'], nz.inputs['Vector'])
    cr = ramp(n, [(0.3, (0.40, 0.115, 0.045, 1)), (0.7, (0.55, 0.20, 0.09, 1))])
    l.new(nz.outputs['Fac'], cr.inputs['Fac'])
    # whitish mineral bloom
    bl = noise_node(n, 3.5, 5, 0.6, 0.6)
    l.new(tc.outputs['Object'], bl.inputs['Vector'])
    blr = ramp(n, [(0.55, (0, 0, 0, 1)), (0.8, (0.45, 0.45, 0.45, 1))])
    l.new(bl.outputs['Fac'], blr.inputs['Fac'])
    mix = mix_rgb(n, 0.35)
    mix.inputs['Color2'].default_value = (0.65, 0.58, 0.5, 1)
    l.new(blr.outputs['Color'], mix.inputs['Fac'])
    l.new(cr.outputs['Color'], mix.inputs['Color1'])
    fine = noise_node(n, 250, 6, 0.6)
    l.new(tc.outputs['Object'], fine.inputs['Vector'])
    bump = n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.5
    bump.inputs['Distance'].default_value = 0.002
    l.new(fine.outputs['Fac'], bump.inputs['Height'])
    l.new(mix.outputs['Color'], b.inputs['Base Color'])
    l.new(bump.outputs['Normal'], b.inputs['Normal'])
    P(b, Roughness=0.82)
    return m


def soil_material():
    m, n, l, b, out = new_mat('Soil')
    tc = n.new('ShaderNodeTexCoord')
    grain = noise_node(n, 350, 5, 0.65)
    l.new(tc.outputs['Object'], grain.inputs['Vector'])
    vor = n.new('ShaderNodeTexVoronoi')
    vor.inputs['Scale'].default_value = 140
    l.new(tc.outputs['Object'], vor.inputs['Vector'])
    cr = ramp(n, [(0.25, (0.012, 0.007, 0.004, 1)), (0.75, (0.06, 0.037, 0.02, 1))])
    l.new(grain.outputs['Fac'], cr.inputs['Fac'])
    h = math_node(n, 'ADD')
    l.new(grain.outputs['Fac'], h.inputs[0])
    l.new(vor.outputs['Distance'], h.inputs[1])
    bump = n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 1.0
    bump.inputs['Distance'].default_value = 0.01
    l.new(h.outputs['Value'], bump.inputs['Height'])
    l.new(cr.outputs['Color'], b.inputs['Base Color'])
    l.new(bump.outputs['Normal'], b.inputs['Normal'])
    P(b, Roughness=0.95)
    return m


def ground_material():
    m, n, l, b, out = new_mat('Ground')
    tc = n.new('ShaderNodeTexCoord')
    nz = noise_node(n, 2.0, 8, 0.6, 0.2)
    l.new(tc.outputs['Object'], nz.inputs['Vector'])
    cr = ramp(n, [(0.3, (0.17, 0.15, 0.13, 1)), (0.7, (0.27, 0.24, 0.21, 1))])
    l.new(nz.outputs['Fac'], cr.inputs['Fac'])
    fine = noise_node(n, 120, 6, 0.6)
    l.new(tc.outputs['Object'], fine.inputs['Vector'])
    bump = n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.3
    bump.inputs['Distance'].default_value = 0.004
    l.new(fine.outputs['Fac'], bump.inputs['Height'])
    l.new(cr.outputs['Color'], b.inputs['Base Color'])
    l.new(bump.outputs['Normal'], b.inputs['Normal'])
    P(b, Roughness=0.75)
    return m


MAT_LEAF = leaf_material()
MAT_STEM = stem_material()
MAT_SOIL = soil_material()
MAT_POT = terracotta_material()
MAT_GROUND = ground_material()
MAT_FLOWER = flat_mat('Flower', (0.90, 0.55, 0.01, 1), 0.4)
# ripeness: green -> breaker -> orange -> red
MAT_T_GREEN = tomato_material('Tomato_Green', (0.10, 0.30, 0.04, 1), (0.05, 0.17, 0.025, 1))
MAT_T_BREAK = tomato_material('Tomato_Breaker', (0.60, 0.13, 0.02, 1), (0.25, 0.22, 0.03, 1))
MAT_T_ORANGE = tomato_material('Tomato_Orange', (0.70, 0.14, 0.01, 1), (0.40, 0.12, 0.01, 1))
MAT_T_RED = tomato_material('Tomato_Red', (0.62, 0.015, 0.008, 1), (0.30, 0.04, 0.008, 1))
RIPENESS = [MAT_T_RED, MAT_T_RED, MAT_T_ORANGE, MAT_T_BREAK, MAT_T_GREEN]


# --------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------
def make_curve(name, pts, r0, r1, material, res=5):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = 1.0
    cu.bevel_resolution = res
    cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(len(pts) - 1)
    for i, (bp, p) in enumerate(zip(sp.bezier_points, pts)):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
        bp.radius = r0 + (r1 - r0) * i / max(1, len(pts) - 1)
    cu.materials.append(material)
    return link(bpy.data.objects.new(name, cu))


def leaf_mesh(name, length=0.14, width=0.07, lobes=9, seed=0, fold=0.35, droop=0.18,
              serration=0.10):
    """Ovate, serrated, V-folded leaflet. Local +Y = tip, UVs fill 0..1."""
    nv, nu = 30, 10
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    grid = []
    for i in range(nv + 1):
        v = i / nv
        prof = math.sin(math.pi * (v ** 0.75)) ** 0.9
        serr = 1.0 + serration * abs(math.sin(v * math.pi * lobes + seed))
        w = width * prof * serr
        row = []
        for j in range(nu + 1):
            u = -1 + 2 * j / nu
            x = u * w
            y = v * length
            z = (-abs(u) * w * fold
                 - (v ** 2) * length * droop
                 + 0.0035 * math.sin(v * 22 + u * 3 + seed) * prof)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for i in range(nv):
        for j in range(nu):
            f = bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
            for lp, (a, c) in zip(f.loops, ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j))):
                lp[uvl].uv = (c / nu, a / nv)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(MAT_LEAF)
    return me


LEAF_VARIANTS = [
    leaf_mesh('leaflet_a', 0.150, 0.072, 9, 0.0),
    leaf_mesh('leaflet_b', 0.140, 0.066, 8, 1.7),
    leaf_mesh('leaflet_c', 0.160, 0.078, 10, 3.1),
]
SEPAL_MESH = leaf_mesh('sepal', 0.050, 0.009, 1, 0.0, fold=0.2, droop=0.25, serration=0.0)
SEPAL_MESH.materials.clear()
SEPAL_MESH.materials.append(MAT_LEAF)


def place(mesh, loc, yaw, pitch=0.0, roll=0.0, scale=1.0, name='obj'):
    ob = bpy.data.objects.new(name, mesh)
    ob.location = loc
    ob.rotation_euler = (pitch, roll, yaw)
    ob.scale = (scale, scale, scale)
    return link(ob)


def tomato_mesh(name, radius):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=56, v_segments=32, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        rho = math.hypot(x, y)
        ang = math.atan2(y, x)
        lobe = 1.0 + 0.035 * math.cos(5 * ang) * (1 - abs(z)) # faint ribbing
        x *= lobe
        y *= lobe
        z *= 0.84
        # stem-end dimple and blossom-end nub
        if z > 0:
            z -= 0.20 * math.exp(-(rho * rho) / 0.035) * min(1.0, z * 2.0)
        else:
            z += 0.04 * math.exp(-(rho * rho) / 0.01)
        v.co = Vector((x, y, z)) * radius
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return me


def make_tomato(center, radius, material, idx):
    me = tomato_mesh('tomato_%d' % idx, radius)
    me.materials.append(material)
    ob = link(bpy.data.objects.new('Tomato_%d' % idx, me))
    ob.location = center
    ob.rotation_euler = (random.uniform(-0.06, 0.06), random.uniform(-0.06, 0.06),
                         random.uniform(0, 6.28))
    top = center + Vector((0, 0, radius * 0.66))
    # calyx: star of sepals + tiny hub
    n = 5
    off = random.uniform(0, 6.28)
    for k in range(n):
        place(SEPAL_MESH, top, off + k * 2 * math.pi / n,
              pitch=-random.uniform(0.15, 0.4), scale=radius / 0.045,
              name='Sepal')
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius * 0.13, segments=16, ring_count=8,
                                         location=top + Vector((0, 0, radius * 0.04)))
    hub = bpy.context.object
    hub.data.materials.append(MAT_STEM)
    for p in hub.data.polygons:
        p.use_smooth = True
    # remove from wherever ops put it and keep in our collection
    for c in list(hub.users_collection):
        c.objects.unlink(hub)
    link(hub)
    return top


# --------------------------------------------------------------------------
# Pot, soil, ground
# --------------------------------------------------------------------------
BASE_Z = 0.02
POT_H = 0.32
SOIL_Z = BASE_Z + POT_H - 0.04

bpy.ops.mesh.primitive_cone_add(vertices=72, radius1=0.15, radius2=0.205, depth=POT_H,
                                location=(0, 0, BASE_Z + POT_H / 2))
pot = bpy.context.object
pot.name = 'Pot'
bm = bmesh.new()
bm.from_mesh(pot.data)
top_faces = [f for f in bm.faces if f.normal.z > 0.9]
bmesh.ops.delete(bm, geom=top_faces, context='FACES')
bm.to_mesh(pot.data)
bm.free()
sol = pot.modifiers.new('Solidify', 'SOLIDIFY')
sol.thickness = 0.014
sol.offset = -1
bev = pot.modifiers.new('Bevel', 'BEVEL')
bev.width = 0.004
bev.segments = 2
pot.modifiers.new('Subsurf', 'SUBSURF').levels = 1
for p in pot.data.polygons:
    p.use_smooth = True
pot.data.materials.append(MAT_POT)

bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.017, major_segments=72,
                                 minor_segments=20, location=(0, 0, BASE_Z + POT_H - 0.005))
rim = bpy.context.object
rim.name = 'PotRim'
for p in rim.data.polygons:
    p.use_smooth = True
rim.data.materials.append(MAT_POT)

bpy.ops.mesh.primitive_cylinder_add(vertices=72, radius=0.19, depth=0.02,
                                    location=(0, 0, BASE_Z / 2))
saucer = bpy.context.object
saucer.name = 'Saucer'
saucer.data.materials.append(MAT_POT)
saucer.modifiers.new('Bevel', 'BEVEL').width = 0.004

# soil with real displaced geometry
bm = bmesh.new()
bmesh.ops.create_circle(bm, cap_ends=True, cap_tris=False, segments=96, radius=0.19)
bmesh.ops.triangulate(bm, faces=bm.faces[:])
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=5, use_grid_fill=True)
for v in bm.verts:
    p = v.co.copy()
    d = 0.012 * noise.noise(p * 45) + 0.02 * noise.noise(p * 14 + Vector((5, 5, 5)))
    v.co.z = SOIL_Z + d + 0.015 * (1 - min(1.0, p.length / 0.19)) ** 0.5
me = bpy.data.meshes.new('SoilMesh')
bm.to_mesh(me)
bm.free()
for p in me.polygons:
    p.use_smooth = True
me.materials.append(MAT_SOIL)
link(bpy.data.objects.new('Soil', me))

bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
ground = bpy.context.object
ground.name = 'Ground'
ground.data.materials.append(MAT_GROUND)

# --------------------------------------------------------------------------
# The plant
# --------------------------------------------------------------------------
STEM_BASE = Vector((0.0, 0.0, SOIL_Z + 0.02))
H = 1.35
N = 9
stem_pts = []
for i in range(N):
    t = i / (N - 1)
    stem_pts.append(STEM_BASE + Vector((0.035 * math.sin(t * 5.0 + 0.4),
                                         0.030 * math.cos(t * 4.0),
                                         H * t)))
make_curve('MainStem', stem_pts, 0.0125, 0.0055, MAT_STEM, res=6)


def stem_at(t):
    f = max(0.0, min(0.999, t)) * (N - 1)
    i = int(f)
    return stem_pts[i].lerp(stem_pts[i + 1], f - i)


def compound_leaf(origin, yaw, scale=1.0, pitch=0.25, droop=0.3):
    """Pinnate leaf: rachis + side leaflet pairs + terminal leaflet."""
    L = 0.46 * scale
    d = Vector((-math.sin(yaw), math.cos(yaw), 0))

    def rachis_pos(t):
        return origin + d * (L * t) + Vector((0, 0, L * t * math.sin(pitch) - droop * L * t * t))

    pts = [rachis_pos(i / 5) for i in range(6)]
    make_curve('Rachis', pts, 0.0045 * scale, 0.0018 * scale, MAT_STEM, res=4)
    pairs = [0.34, 0.52, 0.70, 0.86]
    for k, t in enumerate(pairs):
        s = scale * (1.05 - 0.45 * t)
        for side in (-1, 1):
            m = random.choice(LEAF_VARIANTS)
            place(m, rachis_pos(t), yaw + side * random.uniform(1.0, 1.25),
                  pitch=random.uniform(0.0, 0.25) - 0.1 * t, roll=side * random.uniform(0.0, 0.2),
                  scale=s * random.uniform(0.9, 1.1), name='Leaflet')
        # tiny interstitial leaflet between pairs
        if k < len(pairs) - 1:
            tt = (t + pairs[k + 1]) / 2
            for side in (-1, 1):
                place(LEAF_VARIANTS[1], rachis_pos(tt), yaw + side * 1.2, pitch=0.1,
                      scale=s * 0.38, name='LeafletSmall')
    place(random.choice(LEAF_VARIANTS), rachis_pos(1.0), yaw + random.uniform(-0.2, 0.2),
          pitch=-0.05, scale=scale * 0.85, name='Terminal')


# leaves spiral up the stem (golden angle), bigger and drooping at the bottom
N_LEAVES = 11
leaf_yaws = []
for k in range(N_LEAVES):
    t = 0.14 + 0.86 * k / (N_LEAVES - 1)
    yaw = k * 2.4 + random.uniform(-0.15, 0.15)
    leaf_yaws.append((t, yaw))
    sc = 1.15 - 0.55 * t
    compound_leaf(stem_at(t), yaw, scale=sc,
                  pitch=0.55 - 0.45 * (1 - t) + random.uniform(-0.1, 0.1),
                  droop=0.25 + 0.6 * (1 - t))

# growing tip
tip = stem_pts[-1]
for k in range(4):
    compound_leaf(tip, k * 1.7, scale=0.28, pitch=0.9, droop=0.1)

# --------------------------------------------------------------------------
# Fruit trusses (and a flower truss at the top)
# --------------------------------------------------------------------------
tomato_idx = 0


def truss(t, yaw, count, size, ripe_bias):
    global tomato_idx
    s = stem_at(t)
    d = Vector((-math.sin(yaw), math.cos(yaw), 0))
    branch = []
    for i in range(7):
        u = i / 6
        branch.append(s + d * (0.22 * u) + Vector((0, 0, 0.05 * math.sin(u * 2.4) - 0.10 * u * u)))
    make_curve('TrussStem', branch, 0.0055, 0.0028, MAT_STEM, res=5)
    for k in range(count):
        u = 0.45 + 0.55 * k / max(1, count - 1)
        i = min(5, int(u * 6))
        p = branch[i].lerp(branch[i + 1], u * 6 - i)
        r = size * random.uniform(0.85, 1.12)
        sideways = Vector((-d.y, d.x, 0)) * random.uniform(-0.05, 0.05)
        c = p + sideways + Vector((0, 0, -0.045 - r))
        ripe = RIPENESS[max(0, min(len(RIPENESS) - 1, int(ripe_bias + random.uniform(-1.2, 1.2))))]
        top = make_tomato(c, r, ripe, tomato_idx)
        tomato_idx += 1
        make_curve('Pedicel', [p, p.lerp(top, 0.5) + Vector((0, 0, 0.004)), top],
                   0.0028, 0.0024, MAT_STEM, res=4)


truss(0.30, leaf_yaws[2][1] + 1.2, 4, 0.047, 0.2)    # ripe, low truss
truss(0.46, leaf_yaws[5][1] + 1.3, 3, 0.043, 1.6)
truss(0.62, leaf_yaws[7][1] - 1.2, 4, 0.040, 3.0)    # greener, higher truss

# a few flowers near the top
for k in range(3):
    t = 0.88 + 0.04 * k
    yaw = leaf_yaws[-1][1] + 1.0 + k * 1.9
    s = stem_at(t)
    d = Vector((-math.sin(yaw), math.cos(yaw), 0))
    p0 = s + d * 0.10 + Vector((0, 0, 0.03))
    make_curve('FlowerStem', [s, s + d * 0.05 + Vector((0, 0, 0.04)), p0], 0.003, 0.002,
               MAT_STEM, res=4)
    petal = leaf_mesh('petal', 0.028, 0.0065, 1, 0.0, fold=0.1, droop=0.25, serration=0.0)
    petal.materials.clear()
    petal.materials.append(MAT_FLOWER)
    for i in range(6):
        place(petal, p0, yaw + i * math.pi / 3, pitch=-0.5, name='Petal')
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.006, radius2=0.002, depth=0.018,
                                    location=p0 + Vector((0, 0, 0.004)))
    cone = bpy.context.object
    cone.data.materials.append(MAT_FLOWER)

# --------------------------------------------------------------------------
# World, camera, render settings
# --------------------------------------------------------------------------
world = bpy.data.worlds.new('Sky')
world.use_nodes = True
SCENE.world = world
wn = world.node_tree.nodes
wl = world.node_tree.links
bg = wn['Background']
sky = wn.new('ShaderNodeTexSky')
for kind in ('MULTIPLE_SCATTERING', 'SINGLE_SCATTERING', 'NISHITA'):
    try:
        sky.sky_type = kind
        break
    except TypeError:
        continue
sky.sun_elevation = math.radians(32)
sky.sun_rotation = math.radians(35)
if hasattr(sky, 'sun_size'):
    sky.sun_size = math.radians(0.6)
wl.new(sky.outputs['Color'], bg.inputs['Color'])
bg.inputs['Strength'].default_value = 1.0

target = link(bpy.data.objects.new('CamTarget', None))
target.location = (0, 0, 0.85)

cam_data = bpy.data.cameras.new('Camera')
cam_data.lens = 50
cam_data.dof.use_dof = True
cam_data.dof.focus_object = target
cam_data.dof.aperture_fstop = 6.3
cam = link(bpy.data.objects.new('Camera', cam_data))
cam.location = (2.4, -3.4, 1.15)
trk = cam.constraints.new('TRACK_TO')
trk.target = target
trk.track_axis = 'TRACK_NEGATIVE_Z'
trk.up_axis = 'UP_Y'
SCENE.camera = cam

SCENE.render.engine = 'CYCLES'
SCENE.cycles.samples = SAMPLES
SCENE.cycles.use_denoising = True
SCENE.render.resolution_x = 1600
SCENE.render.resolution_y = 2000
for vt in ('AgX', 'Filmic'):
    try:
        SCENE.view_settings.view_transform = vt
        break
    except TypeError:
        continue
SCENE.render.film_transparent = False

print("Tomato plant built: %d tomatoes." % tomato_idx)

if RENDER_PREVIEW_PATH:
    SCENE.render.filepath = RENDER_PREVIEW_PATH
    bpy.ops.render.render(write_still=True)