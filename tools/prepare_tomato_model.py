"""Explicitly run the inspected owner generator in isolated Blender; export crops.
Use --background --factory-startup --disable-autoexec --python this_file.
"""
import bpy, bmesh, math, random, pathlib, json
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
source=(ROOT/'tools/tomato_owner_source.py').read_text()
source=source.replace('nv, nu = 30, 10','nv, nu = 10, 4').replace('u_segments=56, v_segments=32','u_segments=20, v_segments=12')
source=source.replace('cu.bevel_resolution = res','cu.bevel_resolution = 1\n    cu.resolution_u = 3')
exec(compile(source,'reviewed_owner_tomato_generator','exec'))
# Bake the source's procedural leaf veins to maps that glTF/Godot can use.
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.mesh.primitive_plane_add(size=1)
plane=bpy.context.object; plane.data.materials.append(MAT_LEAF)
SCENE.render.engine='CYCLES'; SCENE.cycles.samples=1
SCENE.render.bake.use_pass_direct=False; SCENE.render.bake.use_pass_indirect=False
SCENE.render.bake.use_pass_color=True
maps={}
for kind in ['DIFFUSE','NORMAL']:
    im=bpy.data.images.new('CropLeaf_'+kind,512,512)
    if kind=='NORMAL':im.colorspace_settings.name='Non-Color'
    node=MAT_LEAF.node_tree.nodes.new('ShaderNodeTexImage');node.image=im
    MAT_LEAF.node_tree.nodes.active=node
    bpy.ops.object.bake(type=kind)
    im.pack(); maps[kind]=im
bpy.data.objects.remove(plane,do_unlink=True)
n=MAT_LEAF.node_tree.nodes; l=MAT_LEAF.node_tree.links; b=n.get('Principled BSDF')
for socket in [b.inputs['Base Color'],b.inputs['Normal']]:
    for edge in list(socket.links):l.remove(edge)
tex=n.new('ShaderNodeTexImage');tex.image=maps['DIFFUSE'];l.new(tex.outputs['Color'],b.inputs['Base Color'])
tex=n.new('ShaderNodeTexImage');tex.image=maps['NORMAL']
normal=n.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.45
l.new(tex.outputs['Color'],normal.inputs['Color']);l.new(normal.outputs['Normal'],b.inputs['Normal'])
b.inputs['Roughness'].default_value=.72
out=n.get('Material Output')
for edge in list(out.inputs['Surface'].links):l.remove(edge)
l.new(b.outputs['BSDF'],out.inputs['Surface']);MAT_LEAF.use_backface_culling=False
palette={'TomatoStem':(.065,.20,.032,1),'Flower':(.9,.55,.01,1),'Tomato_Red':(.52,.021,.009,1),'Tomato_Orange':(.66,.14,.012,1),'Tomato_Breaker':(.32,.20,.023,1),'Tomato_Green':(.085,.23,.025,1)}
for name,col in palette.items():
    mat=bpy.data.materials.get(name)
    if not mat:continue
    bs=mat.node_tree.nodes.get('Principled BSDF')
    for socket in [bs.inputs['Base Color'],bs.inputs['Normal']]:
        for edge in list(socket.links):mat.node_tree.links.remove(edge)
    bs.inputs['Base Color'].default_value=col
    bs.inputs['Roughness'].default_value=.46 if name.startswith('Tomato_') else .75
    bs.inputs['Coat Weight'].default_value=.12
def export_groups(objects,filename,base_z,ratio=.35):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.convert(target='MESH')
    groups={}
    for ob in list(bpy.context.selected_objects):
        groups.setdefault(ob.data.materials[0].name if ob.data.materials else 'Stem',[]).append(ob)
    result=[]
    for name,group in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in group:ob.select_set(True)
        bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join()
        ob=bpy.context.object;ob.name=name
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        for v in ob.data.vertices:v.co.z-=base_z
        if len(ob.data.polygons)>500:
            dec=ob.modifiers.new('Mobile reduction','DECIMATE');dec.ratio=ratio
            bpy.ops.object.modifier_apply(modifier=dec.name)
        result.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in result:ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'models'/filename),export_format='GLB',use_selection=True,export_apply=True)
    triangles=sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in result)
    print('CROP_EXPORT',filename,triangles,'triangles',len(result),'surfaces',flush=True)
    return {'triangles':triangles,'surfaces':len(result)}
objects=[o for o in SCENE.objects if o.type in {'MESH','CURVE'} and o.name not in {'Pot','PotRim','Saucer','Soil','Ground'}]
tomato_report=export_groups(objects,'tomato_plant.glb',STEM_BASE.z)
for ob in list(SCENE.objects):bpy.data.objects.remove(ob,do_unlink=True)
# Original potato geometry, based on the owner's botanical reference.
MAT_WHITE=flat_mat('PotatoFlower',(.87,.86,.80,1),.8)
MAT_ROOT=flat_mat('PotatoRoot',(.16,.092,.028,1),.97)
MAT_TUBER=flat_mat('PotatoTuber',(.34,.23,.105,1),.95)
random.seed(47)
leaf=leaf_mesh('PotatoOvalLeaf',.12,.048,3,1.1,fold=.22,droop=.08,serration=.018)
for stem in range(3):
    yaw=stem*2.4; h=.74-stem*.10
    base=Vector((math.sin(yaw)*.027,math.cos(yaw)*.027,0))
    points=[base+Vector((math.sin(yaw)*.09*t*t,math.cos(yaw)*.09*t*t,h*t)) for t in [0,.25,.5,.75,1]]
    make_curve('PotatoStem',points,.006,.002,MAT_STEM,res=1)
    for k in range(5):
        t=.21+k*.17;origin=points[0].lerp(points[-1],t);angle=yaw+k*2.4
        d=Vector((-math.sin(angle),math.cos(angle),.18));length=.21*(1.1-.4*t)
        make_curve('PotatoBranch',[origin,origin+d*length*.5,origin+d*length],.002,.0009,MAT_STEM,res=1)
        for u in [.32,.62,.86]:
            for side in [-1,1]:place(leaf,origin+d*length*u,angle+side*1.1,pitch=.15,roll=side*.14,scale=.9-.2*t,name='PotatoLeaf')
        place(leaf,origin+d*length,angle,pitch=.1,scale=.78,name='PotatoLeaf')
    for flower in range(2 if stem==0 else 1):
        center=points[-1]+Vector((flower*.035,flower*.025,.04))
        make_curve('FlowerStalk',[points[-1],center],.001,.0006,MAT_STEM,res=1)
        petal=leaf_mesh('PotatoPetal',.028,.013,1,0,fold=.15,droop=.16,serration=0)
        petal.materials.clear();petal.materials.append(MAT_WHITE)
        for p in range(5):place(petal,center,p*math.tau/5,pitch=.25,name='WhiteFlower')
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=.005,location=center+Vector((0,0,.004)))
        bpy.context.object.data.materials.append(bpy.data.materials['Flower'])
for root in range(14):
    angle=root*2.4
    end=Vector((math.sin(angle)*random.uniform(.05,.16),math.cos(angle)*random.uniform(.05,.16),random.uniform(-.19,-.07)))
    make_curve('FibrousRoot',[Vector((0,0,0)),end*.5+Vector((.02,0,-.035)),end],.0018,.0004,MAT_ROOT,res=1)
    if root<11:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,radius=random.uniform(.027,.044),location=end)
        tuber=bpy.context.object;tuber.name='UndergroundPotato'
        tuber.scale=(random.uniform(.85,1.1),random.uniform(.9,1.1),random.uniform(1.1,1.6))
        for v in tuber.data.vertices:v.co*=1+.045*math.sin(v.co.x*250+v.co.y*175)
        for p in tuber.data.polygons:p.use_smooth=True
        tuber.data.materials.append(MAT_TUBER)
        for eye in range(3):
            bpy.ops.mesh.primitive_uv_sphere_add(segments=6,ring_count=4,radius=.0017,location=end+Vector((.014*math.cos(eye*2.1),.014*math.sin(eye*2.1),.025)))
            bpy.context.object.data.materials.append(MAT_ROOT)
potato_report=export_groups([o for o in SCENE.objects if o.type in {'MESH','CURVE'}],'potato_plant.glb',0,.75)
(ROOT/'models/crop_models.source.json').write_text(json.dumps({'tomato':{'source':'Owner supplied tomato_plant.py.blend1 inspected embedded generator','budget':tomato_report},'potato':{'source':'Original procedural geometry from owner visual reference','budget':potato_report},'materials':'Owner leaf colour and veins baked to embedded 512px colour/normal maps','excluded':'Source presentation pot, soil, ground, cameras, lights'},indent=2))
