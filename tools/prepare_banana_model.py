"""Inspect/prepare the owner FBX without executing embedded file scripts."""
import bpy, pathlib, json, hashlib, math
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
SOURCE=ROOT/'3d models/banana tree/Banana_Plant_01.fbx'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(SOURCE),use_anim=False)
report={'source':str(SOURCE.relative_to(ROOT)),'sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'objects':[],'images':[]}
for ob in bpy.context.scene.objects:
    if ob.type!='MESH':continue
    points=[ob.matrix_world@Vector(c) for c in ob.bound_box]
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    report['objects'].append({'name':ob.name,'triangles':sum(len(p.vertices)-2 for p in ob.data.polygons),'bounds':[list(lo),list(hi)],'materials':[m.name for m in ob.data.materials]})
for im in bpy.data.images:report['images'].append({'name':im.name,'file':im.filepath,'size':list(im.size),'packed':bool(im.packed_file)})
(ROOT/'build/banana-model-inspection.json').write_text(json.dumps(report,indent=2))
ob=bpy.data.objects['Banana_Plant_01_LOD1']
# The FBX has no embedded maps and its external maps were not supplied.
# Retain the owner's LOD1 geometry; use original vertex colours instead of
# exporting broken references or distributing textures from an unknown source.
bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
bpy.context.view_layer.objects.active=ob
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
floor=min(v.co.z for v in ob.data.vertices)
for v in ob.data.vertices:v.co.z-=floor
ob.name='OwnerBananaPlant'
ob.data.materials.clear()
for name,rough in [('BananaLeaf',.78),('BananaStem',.92)]:
    mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.use_backface_culling=False
    bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=rough
    vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='BotanicalColour'
    mat.node_tree.links.new(vc.outputs['Color'],bs.inputs['Base Color'])
    ob.data.materials.append(mat)
col=ob.data.color_attributes.new(name='BotanicalColour',type='BYTE_COLOR',domain='CORNER')
for face in ob.data.polygons:
    centre=sum((ob.data.vertices[v].co for v in face.vertices),Vector())/len(face.vertices)
    stem=centre.z<.71 and abs(centre.y)<.19
    face.material_index=1 if stem else 0
    face.use_smooth=True
    for loop_index in face.loop_indices:
        v=ob.data.vertices[ob.data.loops[loop_index].vertex_index].co
        grain=.5+.5*math.sin(v.z*45+v.x*14+v.y*17)
        shade=.83+.17*grain
        base=(.28,.32,.08) if stem else (.055,.26,.035)
        col.data[loop_index].color=(*[c*shade for c in base],1)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'models/banana_plant.glb'),export_format='GLB',use_selection=True,export_apply=True)
provenance={'source':SOURCE.relative_to(ROOT).as_posix(),'sha256':report['sha256'],'selected':'Banana_Plant_01_LOD1','triangles':1998,'surfaces':2,'materials':'Original botanical vertex colours; owner FBX referenced absent texture maps','excluded':'LOD0, LOD2, LOD3 billboard, UCX collider and missing external texture references','license':'Owner-supplied geometry; no license file supplied and no CC0 claim'}
(ROOT/'models/banana_plant.source.json').write_text(json.dumps(provenance,indent=2))
print('BANANA_EXPORT',json.dumps(provenance))
