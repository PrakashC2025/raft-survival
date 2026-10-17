import bpy,json,pathlib
from mathutils import Vector
root=pathlib.Path(r'C:\GodotProjects\raft-survival')
bpy.ops.wm.open_mainfile(filepath=str(root/'build/asset-sources/hunting/woodBoat.blend'),load_ui=False,use_scripts=False)
for ob in bpy.data.objects:
    if ob.type!='MESH':continue
    print('BOAT_SOURCE',ob.name,'loc',list(ob.location),'rotation',list(ob.rotation_euler),'scale',list(ob.scale),
        'bounds',[list(Vector(p)) for p in [ob.bound_box[0],ob.bound_box[6]]],
        'polygons',len(ob.data.polygons),'materials',[m.name for m in ob.data.materials if m],
        'modifiers',[(m.name,m.type) for m in ob.modifiers],
        'vertices',[list(v.co) for v in ob.data.vertices][:20],flush=True)
