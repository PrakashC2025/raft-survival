import bpy,math,pathlib,sys
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
for kind in ['crocodile','boar','rowboat','workbench']:
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(ROOT/'models'/f'hunting_{kind}.glb'));bpy.context.view_layer.update()
    points=[o.matrix_world@Vector(v) for o in bpy.context.scene.objects if o.type=='MESH' for v in o.bound_box]
    lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)]);size=hi-lo;center=(lo+hi)/2
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,lo.z-.02));floor=bpy.context.object;mat=bpy.data.materials.new('StudioFloor');mat.diffuse_color=(.2,.22,.24,1);floor.data.materials.append(mat)
    bpy.ops.object.camera_add(location=center+Vector((size.length,size.length,size.length*.55)));cam=bpy.context.object
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=max(size)*1.4;bpy.context.scene.camera=cam
    bpy.ops.object.light_add(type='AREA',location=center+Vector((2,-3,5)));light=bpy.context.object;light.data.energy=1000;light.data.size=5;light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
    scene=bpy.context.scene;scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.3,.3,.3,1)
    scene.render.engine='CYCLES';scene.cycles.samples=12;scene.cycles.use_denoising=True
    scene.render.resolution_x=1000;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX';scene.render.filepath=str(ROOT/'build'/f'prepared-{kind}.png');bpy.ops.render.render(write_still=True)
