import bpy,pathlib
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'3d models/free_wildlife/boar/Boar.blend'),load_ui=False,use_scripts=False)
for name in ['Boar','Boar skeleton']:
 ob=bpy.data.objects[name];print('OBJECT',name,'matrix',[list(r) for r in ob.matrix_world],flush=True)
 if ob.type=='ARMATURE':
  for b in ob.data.bones:print('BONE',b.name,'head',list(b.head_local),'tail',list(b.tail_local),flush=True)
 else:
  print('GROUPS',[(g.index,g.name) for g in ob.vertex_groups],flush=True)
  for i,m in enumerate(ob.data.materials):print('MAT',i,m.name,flush=True)
  print('BOUNDS',list(ob.dimensions),list(ob.location),flush=True)
