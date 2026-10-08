"""Prepare owner onion growth models and food art with embedded scripts disabled."""
import bpy, pathlib, json, hashlib
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
SOURCE=ROOT/'3d models/Onion/real_onion_plant.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),load_ui=False,use_scripts=False)
report={'source':SOURCE.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'objects':[],'images':[],'texts':[]}
for ob in bpy.context.scene.objects:
    if ob.type not in {'MESH','CURVE','EMPTY'}:continue
    pts=[ob.matrix_world@Vector(c) for c in ob.bound_box]
    report['objects'].append({'name':ob.name,'type':ob.type,'parent':ob.parent.name if ob.parent else None,'faces':len(ob.data.polygons) if ob.type=='MESH' else 0,'bounds':[[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]],'materials':[m.name for m in ob.data.materials] if ob.type!='EMPTY' else []})
for im in bpy.data.images:report['images'].append({'name':im.name,'file':im.filepath,'size':list(im.size),'packed':bool(im.packed_file)})
for txt in bpy.data.texts:
    report['texts'].append({'name':txt.name,'length':len(txt.as_string())})
    (ROOT/'build'/('onion-inspect-'+pathlib.Path(txt.name).name+'.txt')).write_text(txt.as_string())
(ROOT/'build/onion-model-inspection.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'objects':len(report['objects']),'images':report['images'],'texts':report['texts'],'roots':[{'name':ob.name,'type':ob.type,'children':len(ob.children),'at':list(ob.location)} for ob in bpy.context.scene.objects if ob.parent is None]},indent=2))

exports=[]
for stage_number,filename in [(1,'onion_sprout'),(3,'onion_young'),(5,'onion_growing'),(6,'onion_plant'),(6,'onion_bulb')]:
    stage=bpy.data.objects['ONION_STAGE_'+str(stage_number)]
    originals=[ob for ob in stage.children_recursive if ob.type in {'MESH','CURVE'} and not ob.name.startswith('Preview_Soil')]
    anchor=next((ob for ob in originals if ob.name.startswith('Onion_Bulb')), originals[0])
    points=[anchor.matrix_world@Vector(c) for c in anchor.bound_box]
    offset=Vector(((min(p.x for p in points)+max(p.x for p in points))*.5,(min(p.y for p in points)+max(p.y for p in points))*.5,0))
    if filename=='onion_bulb':originals=[ob for ob in originals if ob.name.startswith(('Onion_Bulb','Dry_Onion_Neck'))]
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    for original in originals:
        ob=original.copy();ob.data=original.data.copy();bpy.context.scene.collection.objects.link(ob)
        ob.animation_data_clear();ob.hide_viewport=False;ob.hide_render=False;ob.hide_set(False)
        world=original.matrix_world.copy();ob.parent=None;ob.matrix_world=world
        if ob.type=='CURVE':ob.data.bevel_resolution=1;ob.data.resolution_u=3
        ob.select_set(True);copies.append(ob)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
    plant=bpy.context.object;plant.name='Owner'+filename.title().replace('_','')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for vertex in plant.data.vertices:vertex.co-=offset
    if filename!='onion_bulb':
        # Shared mature-height reference: runtime's continuous growth scale
        # controls size while the supplied stages supply changing leaf/bulb form.
        height=max(vertex.co.z for vertex in plant.data.vertices)
        for vertex in plant.data.vertices:vertex.co*=.7/max(height,.001)
    dec=plant.modifiers.new('Mobile foliage reduction','DECIMATE');dec.ratio=.65
    bpy.ops.object.modifier_apply(modifier=dec.name)
    for material in plant.data.materials:
        if material:material.use_backface_culling=False
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'models'/(filename+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    exports.append({'file':filename+'.glb','source_stage':stage_number,'triangles':sum(len(face.vertices)-2 for face in plant.data.polygons),'surfaces':len(plant.data.materials)})
    if filename=='onion_bulb':
        # Inventory art is a transparent render of this same supplied bulb.
        # Hide the side-by-side source display without modifying its geometry.
        for ob in bpy.context.scene.objects:ob.hide_render=ob!=plant
        scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24
        scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
        scene.render.film_transparent=True
        scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.35
        camera_data=bpy.data.cameras.new('OnionIconCamera');camera=bpy.data.objects.new('OnionIconCamera',camera_data);scene.collection.objects.link(camera)
        camera.location=(.45,-1.4,.6);target=Vector((0,0,.015));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        camera_data.type='ORTHO';camera_data.ortho_scale=.54;scene.camera=camera
        for index,location in enumerate([(1,-1,1.6),(-1,-.5,.6)]):
            light_data=bpy.data.lights.new('OnionIconLight'+str(index),'AREA');light_data.energy=70 if index==0 else 35;light_data.shape='DISK';light_data.size=1.2
            light=bpy.data.objects.new(light_data.name,light_data);scene.collection.objects.link(light);light.location=location;light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(ROOT/'textures/ui/advanced_onion.png');scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(plant,do_unlink=True)
provenance={'source':report['source'],'sha256':report['sha256'],'exports':exports,'materials':'Owner supplied botanical green leaves and golden onion skins retained','excluded':'Preview soil, presentation camera/lights, source animation','license':'Owner supplied blend; no license supplied and no CC0 claim','security':'Embedded text inspected but never executed'}
(ROOT/'models/onion_plant.source.json').write_text(json.dumps(provenance,indent=2))
print('ONION_EXPORT',json.dumps(provenance))
