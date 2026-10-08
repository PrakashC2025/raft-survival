"""Prepare the owner's electronic tools and record source provenance."""
import bpy,pathlib,json,hashlib,tempfile
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
SOURCE=ROOT/'3d models/Electronic_tools/tools+vol+2.glb'
tempfile.tempdir=str(ROOT/'build/blender-plant-temp')
pathlib.Path(tempfile.tempdir).mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
print('ELECTRONIC_OBJECTS',json.dumps([{'name':o.name,'faces':len(o.data.polygons),'bounds':[list(o.matrix_world@Vector(o.bound_box[0])),list(o.matrix_world@Vector(o.bound_box[6]))]} for o in objects]))
if '--inspect' in __import__('sys').argv:
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=8
    scene.world.color=(.45,.45,.45)
    bpy.ops.object.light_add(type='AREA',location=(0,-3,5));bpy.context.object.data.energy=500;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=5
    bpy.ops.object.camera_add(location=(0,-8,1.95));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,1.95))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=5.4;scene.camera=camera
    scene.render.resolution_x=1100;scene.render.resolution_y=620;scene.render.resolution_percentage=100
    scene.render.filepath=str(ROOT/'build/electronics-source-preview.png');bpy.ops.render.render(write_still=True)
    raise SystemExit

exports=[];prepared=[]
for source_name,label,size in [('3','SolarTorch',.34),('1','Binoculars',.28),('5','WalkieTalkie',.30)]:
    ob=bpy.data.objects[source_name];ob.name=label
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    points=[v.co for v in ob.data.vertices];low=Vector([min(p[i] for p in points) for i in range(3)]);high=Vector([max(p[i] for p in points) for i in range(3)])
    center=(low+high)*.5;factor=size/max(high-low)
    for vertex in ob.data.vertices:vertex.co=(vertex.co-center)*factor
    # Flashlight lens points along Godot -Z while held; imported source points down.
    if label=='SolarTorch':
        from mathutils import Matrix
        for vertex in ob.data.vertices:vertex.co=Matrix.Rotation(__import__('math').pi/2,4,'X')@vertex.co
    for material in ob.data.materials:
        material.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.65
        for node in material.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image and max(node.image.size)>1024:node.image.scale(1024,1024);node.image.pack()
    exports.append({'node':label,'source_node':source_name,'triangles':sum(len(f.vertices)-2 for f in ob.data.polygons)})
    prepared.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for ob in prepared:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'models/portable_electronics.glb'),export_format='GLB',use_selection=True,export_animations=False,export_apply=True)
record={'source':SOURCE.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'exports':exports,'textures':'Original owner atlas textures resized to 1024; materials preserved','license':'Owner supplied model; no license file supplied; no CC0 claim'}
(ROOT/'models/portable_electronics.source.json').write_text(json.dumps(record,indent=2))
print('ELECTRONICS_EXPORT',json.dumps(record))
