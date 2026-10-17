import bpy,pathlib,numpy as np
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
for filename in ['crocodile_siamese_crocodile.glb','wild_boar_textured.glb','wooden_workbench_-_free.glb','victorian_row_boat.glb']:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(ROOT/'3d models/free_wildlife/sketchfab'/filename));bpy.context.view_layer.update()
 print('ASSET',filename,flush=True)
 for ob in bpy.data.objects:
  if ob.type=='MESH':
   co=np.array([v.co[:] for v in ob.data.vertices]);print('MESH',ob.name,'parent',ob.parent.name if ob.parent else '', 'LOCAL',co.min(0).tolist(),co.max(0).tolist(),'MATRIX', [list(r) for r in ob.matrix_world],flush=True)
  elif ob.parent is None:print('ROOT',ob.name,list(ob.rotation_euler),list(ob.scale),flush=True)
