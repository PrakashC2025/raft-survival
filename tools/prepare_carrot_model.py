"""Prepare owner carrot geometry with embedded Blender scripts disabled."""
import bpy, pathlib, json, hashlib
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
SOURCE=ROOT/'3d models/carrot/carrot_plant.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),load_ui=False,use_scripts=False)
report={'source':SOURCE.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'objects':[],'images':[],'texts':[]}
for ob in bpy.context.scene.objects:
    if ob.type not in {'MESH','CURVE'}:continue
    pts=[ob.matrix_world@Vector(c) for c in ob.bound_box]
    report['objects'].append({'name':ob.name,'type':ob.type,'faces':len(ob.data.polygons) if ob.type=='MESH' else 0,'bounds':[[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]],'materials':[m.name for m in ob.data.materials]})
for im in bpy.data.images:report['images'].append({'name':im.name,'file':im.filepath,'size':list(im.size),'packed':bool(im.packed_file)})
for txt in bpy.data.texts:
    report['texts'].append({'name':txt.name,'length':len(txt.as_string())})
    (ROOT/'build'/('carrot-inspect-'+pathlib.Path(txt.name).name+'.txt')).write_text(txt.as_string())
(ROOT/'build/carrot-model-inspection.json').write_text(json.dumps(report,indent=2))
stage=bpy.data.objects['STAGE_5_ROOT']
objects=[ob for ob in stage.children_recursive if ob.type in {'MESH','CURVE'} and not ob.name.startswith('Preview_Soil')]
root=next(ob for ob in objects if ob.name.startswith('Carrot_Root_Stage'))
# This source's display offset is baked into vertices as well as its parent.
# Centre the actual root geometry, rather than subtracting only the parent.
points=[root.matrix_world@Vector(corner) for corner in root.bound_box]
offset=Vector(((min(p.x for p in points)+max(p.x for p in points))*.5,(min(p.y for p in points)+max(p.y for p in points))*.5,0))
for ob in objects:
    ob.animation_data_clear();ob.hide_viewport=False;ob.hide_render=False;ob.hide_set(False)
    world=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=world
    if ob.type=='CURVE':ob.data.bevel_resolution=1;ob.data.resolution_u=3
bpy.ops.object.select_all(action='DESELECT')
for ob in objects:ob.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.object.convert(target='MESH')
bpy.ops.object.join();plant=bpy.context.object;plant.name='OwnerCarrotPlant'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
for vertex in plant.data.vertices:vertex.co-=offset
dec=plant.modifiers.new('Mobile foliage reduction','DECIMATE');dec.ratio=.23
bpy.ops.object.modifier_apply(modifier=dec.name)
for material in plant.data.materials:
    if material:material.use_backface_culling=False
bpy.ops.export_scene.gltf(filepath=str(ROOT/'models/carrot_plant.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
provenance={'source':SOURCE.relative_to(ROOT).as_posix(),'sha256':report['sha256'],'selected':'STAGE_5_ROOT botanical foliage and underground carrot; continuously scaled at runtime','triangles':sum(len(face.vertices)-2 for face in plant.data.polygons),'surfaces':len(plant.data.materials),'materials':'Owner supplied flat botanical colours retained','excluded':'Preview soil, presentation lights/camera, earlier duplicate stage geometry and source animation','license':'Owner supplied blend; no license supplied and no CC0 claim','security':'Embedded text was inspected but never executed'}
(ROOT/'models/carrot_plant.source.json').write_text(json.dumps(provenance,indent=2))
print('CARROT_EXPORT',json.dumps(provenance))
