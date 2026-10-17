import bpy,pathlib,json
from mathutils import Vector
root=pathlib.Path(r'C:\GodotProjects\raft-survival')
for filename in ['victorian_row_boat.glb','crocodile_siamese_crocodile.glb','wild_boar_textured.glb']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(root/'3d models/free_wildlife/sketchfab'/filename))
    bpy.context.view_layer.update()
    print('ASSET',filename,flush=True)
    for ob in bpy.data.objects:
        if ob.type!='MESH':continue
        points=[ob.matrix_world@Vector(p) for p in ob.bound_box]
        lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
        print('MESH',ob.name,'tris',sum(len(p.vertices)-2 for p in ob.data.polygons),'bounds',lo,hi,'materials',[m.name for m in ob.data.materials if m],flush=True)
    print('MATERIALS',[(m.name,[(n.image.name,list(n.image.size)) for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]) for m in bpy.data.materials],flush=True)
    print('ANIMATIONS',[a.name for a in bpy.data.actions],flush=True)
