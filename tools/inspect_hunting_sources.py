"""Inspect downloaded artwork with embedded file scripts disabled."""
import bpy, json, pathlib
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
for relative in ['3d models/free_wildlife/crocodile/crocodile.blend','3d models/free_wildlife/boar/Boar.blend']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/relative),load_ui=False,use_scripts=False)
    print('SOURCE',relative)
    for ob in bpy.data.objects:
        if ob.type not in {'MESH','ARMATURE'}:continue
        print('OBJECT',ob.name,ob.type,'hide',ob.hide_render,'scale',list(ob.scale),'location',list(ob.location),
              'triangles',sum(len(p.vertices)-2 for p in ob.data.polygons) if ob.type=='MESH' else '',
              'bones',[(b.name,list(b.head_local),list(b.tail_local)) for b in ob.data.bones] if ob.type=='ARMATURE' else '')
        if ob.type=='MESH':print('MATERIALS',[(m.name,[(n.name,n.image.filepath if n.image else '') for n in m.node_tree.nodes if n.type=='TEX_IMAGE'] if m.use_nodes else '') for m in ob.data.materials if m])
    print('ACTIONS',[(a.name, list(a.frame_range)) for a in bpy.data.actions])
    print('IMAGES',[(i.name,i.filepath,bool(i.packed_file)) for i in bpy.data.images])
