"""Prepare openly licensed artist models; never execute embedded source scripts."""
import bpy, pathlib, math, json, hashlib, bmesh, numpy as np, sys
from mathutils import Vector, Matrix
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
OUT=ROOT/'models'

def scanned_head(body,rig):
    # Replace the old low-poly head and mane with the CC-BY taxidermy scan.
    bm=bmesh.new();bm.from_mesh(body.data)
    head_indices={body.vertex_groups[n].index for n in ['head','neck']}
    remove=[]
    for vertex in body.data.vertices:
        if any(g.group in head_indices and g.weight>.25 for g in vertex.groups):remove.append(vertex.index)
    bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.verts[i] for i in remove],context='VERTS')
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index in [1,2]],context='FACES')
    bm.to_mesh(body.data);bm.free()
    original=set(bpy.data.objects);bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'3d models/free_wildlife/sketchfab/wild_boar_textured.glb'));bpy.context.view_layer.update()
    parts=[o for o in bpy.data.objects if o not in original and o.type=='MESH']
    # Selected from the source's inspected upright orientation; no build-cache dependency.
    basis=Matrix(((.9588727918,-.2602758642,.1132229823),(.2587159233,.9655323344,.0285198556),(-.1167434805,.0019456748,.9931601956))).to_4x4()
    for ob in parts:
        transform=basis@ob.matrix_world;ob.parent=None;ob.matrix_world=Matrix.Identity(4);ob.data.transform(transform)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:ob.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();parts=[bpy.context.object]
    bm=bmesh.new();bm.from_mesh(parts[0].data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bm.to_mesh(parts[0].data);bm.free()
    coords=np.array([v.co[:] for ob in parts for v in ob.data.vertices]);lo=coords.min(0);hi=coords.max(0);center=(lo+hi)*.5
    factor=.90/(hi[0]-lo[0])
    for ob in parts:
        for v in ob.data.vertices:
            t=(v.co.y-lo[1])/(hi[1]-lo[1]);u=max(0,min(1,(t-.5)*2));z=(v.co.z-lo[2])*factor+.36
            v.co=Vector(((v.co.x-center[0])*factor*(1-.28*t)*(1-.5*u),(v.co.y-lo[1])*factor-1.35,z*(1-u*.70)+.80*u*.70))
        bpy.context.view_layer.objects.active=ob
        dec=ob.modifiers.new('Scan silhouette preservation','DECIMATE');dec.ratio=.02
        bpy.ops.object.modifier_apply(modifier=dec.name)
        for poly in ob.data.polygons:poly.use_smooth=True
        group=ob.vertex_groups.new(name='head');group.add(list(range(len(ob.data.vertices))),1.0,'REPLACE')
        armature=ob.modifiers.new('Follow original head pose','ARMATURE');armature.object=rig;ob.parent=rig
        ob.name='PhotographedBoarHead'
        for mat in ob.data.materials:
            for node in mat.node_tree.nodes:
                if node.type=='BSDF_PRINCIPLED':node.inputs['Base Color'].default_value=(.56,.44,.33,1);node.inputs['Roughness'].default_value=.97
    for ob in list(bpy.data.objects):
        if ob not in original and ob not in parts:bpy.data.objects.remove(ob,do_unlink=True)
    return parts

def material(name, color=(.4,.35,.25,1), image=None, normal=None, rough=.85):
    m=bpy.data.materials.new(name);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=color;bs.inputs['Roughness'].default_value=rough
    if image:
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
        multiply=m.node_tree.nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1;multiply.inputs[2].default_value=(.22,.17,.13,1)
        m.node_tree.links.new(tex.outputs['Color'],multiply.inputs[1]);m.node_tree.links.new(multiply.outputs[0],bs.inputs['Base Color'])
    if normal:
        normal.colorspace_settings.name='Non-Color'
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=normal
        node=m.node_tree.nodes.new('ShaderNodeNormalMap');node.inputs['Strength'].default_value=.55
        m.node_tree.links.new(tex.outputs['Color'],node.inputs['Color']);m.node_tree.links.new(node.outputs['Normal'],bs.inputs['Normal'])
    return m

def export_animal(kind, relative, mesh_name, rig_name, length, clips):
    source=ROOT/relative;bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
    def reveal(layer):
        layer.exclude=False;layer.hide_viewport=False;layer.collection.hide_viewport=False;layer.collection.hide_render=False
        for child in layer.children:reveal(child)
    reveal(bpy.context.view_layer.layer_collection)
    mesh=bpy.data.objects[mesh_name];rig=bpy.data.objects[rig_name]
    keep={mesh,rig}
    for ob in list(bpy.data.objects):
        if ob not in keep:bpy.data.objects.remove(ob,do_unlink=True)
    bpy.context.view_layer.objects.active=mesh
    for ob in [mesh,rig]:ob.hide_set(False);ob.hide_viewport=False;ob.hide_render=False
    if kind=='Crocodile':
        diffuse=bpy.data.images.load(str(source.parent/'croc_diffuse.png'),check_existing=True)
        normal=bpy.data.images.load(str(source.parent/'croc_normal.png'),check_existing=True)
        mesh.data.materials.clear();mesh.data.materials.append(material('Crocodile_original_skin',image=diffuse,normal=normal))
    else:
        photo=bpy.data.images.get('nowa textura pras.000')
        for index, old in enumerate(list(mesh.data.materials)):
            name=old.name if old else ''
            if name.startswith('Fur'):new=material('Boar_original_photograph',image=photo,rough=.98)
            elif name.startswith('Mane'):new=material('Bristles',(.085,.062,.04,1),rough=.98)
            else:new=material('Tusks',(.61,.56,.40,1))
            mesh.data.materials[index]=new
    head_parts=scanned_head(mesh,rig) if kind=='Boar' else []
    # Subdivision softens the full-body silhouette; the photographed head keeps its own topology.
    sub=mesh.modifiers.new('Smooth_authored_anatomy','SUBSURF');sub.levels=2;sub.render_levels=sub.levels
    # Put subdivision ahead of armature, retaining the supplied skin weights and mirrored side.
    bpy.context.view_layer.objects.active=mesh
    while list(mesh.modifiers).index(sub)>0 and mesh.modifiers[list(mesh.modifiers).index(sub)-1].type=='ARMATURE':
        bpy.ops.object.modifier_move_up(modifier=sub.name)
    for polygon in mesh.data.polygons:polygon.use_smooth=True
    for track in list(rig.animation_data.nla_tracks) if rig.animation_data else []:rig.animation_data.nla_tracks.remove(track)
    selected=[]
    for src,dst in clips:
        action=bpy.data.actions.get(src)
        if action:action.name=dst;action.use_fake_user=True;selected.append(action)
    if rig.animation_data:rig.animation_data.action=selected[0] if selected else None
    for action in list(bpy.data.actions):
        if action not in selected:bpy.data.actions.remove(action,do_unlink=True)
    bpy.context.scene.frame_set(int(selected[0].frame_range[0]) if selected else 1)
    bpy.context.view_layer.update()
    if head_parts:
        return export_custom_boar(mesh,rig,head_parts,source)
    evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points=[mesh.matrix_world@Vector(p) for p in evaluated.bound_box]
    for part in head_parts:
        baked=part.evaluated_get(bpy.context.evaluated_depsgraph_get())
        points.extend([part.matrix_world@Vector(p) for p in baked.bound_box])
    low=Vector([min(p[i] for p in points) for i in range(3)]);high=Vector([max(p[i] for p in points) for i in range(3)])
    factor=length/(high.y-low.y)
    root=bpy.data.objects.new(kind+'_metre_scale',None);bpy.context.collection.objects.link(root)
    # Source faces -Y; glTF's -Z is Blender +Y.
    for ob in [rig,mesh]:
        if ob.parent not in keep:
            matrix=ob.matrix_world.copy();ob.parent=root;ob.matrix_world=matrix
    root.rotation_euler.z=math.pi;root.scale=(factor,)*3;root.location.z=-low.z*factor
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [root,rig,mesh]+head_parts:ob.select_set(True)
    file=OUT/('hunting_'+kind.lower()+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_apply=True,
        export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,
        export_skins=True,
        export_extras=False,export_image_format='AUTO')
    print('PREPARED',kind,'original_bounds',list(high-low),'factor',factor,'animations',[(a.name,[s.identifier for s in a.slots]) for a in selected],flush=True)
    return {'kind':kind,'source':relative,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'geometry_license':'CC0-1.0' if kind=='Crocodile' else 'CC-BY-SA-4.0',
            'geometry_author':'br-n518' if kind=='Crocodile' else 'Danimal, Myname and Clint Bellanger',
            'surface_credit':'Siamese crocodile skin by sarvesh777, CC-BY-4.0; ASSET_CREDITS.md' if kind=='Crocodile' else 'ASSET_CREDITS.md',
            'file':file.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),
            'source_length_m':high.y-low.y,'length_m':length,'animations':[a.name for a in selected]}

def export_custom_boar(body,old_rig,parts,source):
    # Bake the source body into a clean metre-space bind pose. Its legacy global
    # bone scale must not deform the scanned head a second time.
    graph=bpy.context.evaluated_depsgraph_get();evaluated=body.evaluated_get(graph)
    baked=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=graph)
    baked.transform(body.matrix_world)
    new=bpy.data.objects.new('SmoothFullBoarBody',baked);bpy.context.collection.objects.link(new)
    for part in parts:
        part.modifiers.clear();part.parent=None;part.matrix_world=Matrix.Identity(4)
    for ob in list(bpy.data.objects):
        if ob not in [new]+parts:bpy.data.objects.remove(ob,do_unlink=True)
    objects=[new]+parts
    for action in list(bpy.data.actions):bpy.data.actions.remove(action,do_unlink=True)
    coords=np.array([v.co[:] for ob in objects for v in ob.data.vertices]);lo=coords.min(0);hi=coords.max(0);factor=1.85/(hi[1]-lo[1]);center=(lo+hi)*.5
    for ob in objects:
        for v in ob.data.vertices:v.co=Vector((-(v.co.x-center[0])*factor,-(v.co.y-center[1])*factor,(v.co.z-lo[2])*factor))
    arm=bpy.data.armatures.new('FullBoarOriginalRig');rig=bpy.data.objects.new('FullBoarRig',arm);bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    specs={'Body':((0,-.3,.65),(0,.3,.7),None),'Head':((0,.27,.65),(0,.8,.6),'Body'),'Tail1':((0,-.65,.7),(0,-.86,.7),'Body')}
    for side,sign in [('L',1),('R',-1)]:
        for end,y in [('Front',.25),('Back',-.5)]:
            specs[end+side]=((sign*.18,y,.65),(sign*.18,y,.32),'Body')
            specs[end+side+'Foot']=((sign*.18,y,.32),(sign*.18,y+.05,.035),end+side)
    for name,(head,tail,parent) in specs.items():
        bone=arm.edit_bones.new(name);bone.head=head;bone.tail=tail
        if parent:bone.parent=arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for ob in objects:
        ob.vertex_groups.clear();groups={name:ob.vertex_groups.new(name=name) for name in specs}
        for v in ob.data.vertices:
            x,y,z=v.co;weights={'Body':1.0}
            if ob in parts:weights={'Head':1.0}
            elif z<.68 and abs(x)>.10:
                end='Front' if y>-.10 else 'Back';side='L' if x>0 else 'R';w=max(0,min(1,(.68-z)/.20));foot=max(0,min(1,(.36-z)/.17))
                weights={'Body':1-w,end+side:w*(1-foot),end+side+'Foot':w*foot}
            for name,w in weights.items():
                if w>.001:groups[name].add([v.index],w,'REPLACE')
        mod=ob.modifiers.new('Full body gait','ARMATURE');mod.object=rig;ob.parent=rig
    import importlib.util
    spec=importlib.util.spec_from_file_location('model_prep',ROOT/'tools/prepare_sketchfab_models.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.animate(rig)
    bpy.ops.object.select_all(action='SELECT');file=OUT/'hunting_boar.glb'
    bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_apply=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_skins=True,export_image_format='AUTO')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'3d models/free_wildlife/sketchfab/hunting_boar.glb.blend'),check_existing=False)
    record={'kind':'Boar','source':str(source.relative_to(ROOT)),'scanned_head':'https://sketchfab.com/3d-models/wild-boar-textured-80e5db899a484938b88b9e16251bb5a0','body_author':'Danimal, Myname and Clint Bellanger','head_author':'aellis43','license':'CC-BY-SA-4.0 derivative; scanned head CC-BY-4.0','file':'models/hunting_boar.glb','sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'length_m':1.85,'animations':[a.name for a in bpy.data.actions]}
    print('PREPARED',record,flush=True);return record

records=[]
if '--boar-only' not in sys.argv:
    records.append(export_animal('Crocodile','3d models/free_wildlife/crocodile/crocodile.blend','Crocodile','Armature',3.5,
        [('idle-loop','Idle'),('walk-loop','Walk'),('attack','Attack')]))
if '--croc-only' not in sys.argv:
    records.append(export_animal('Boar','3d models/free_wildlife/boar/Boar.blend','Boar','Boar skeleton',1.85,
        [('Idle','Idle'),('Walk','Walk'),('Attack','Attack')]))
(OUT/'hunting_animals.source.json').write_text(json.dumps(records,indent=2))
