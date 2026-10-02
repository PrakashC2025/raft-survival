import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'C:/GodotProjects/raft-survival/tools/asset_downloads/survivors/Animations/idle.fbx')
for o in bpy.data.objects: print('OBJECT',o.name,o.type,tuple(o.rotation_euler))
for a in bpy.data.actions: print('ACTION',a.name,a.frame_range[:])
