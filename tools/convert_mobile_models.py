import bpy, os, json
from pathlib import Path
root=Path(r'C:/GodotProjects/raft-survival')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(root/'tools/asset_downloads/survivors/Model/characterMedium.fbx'))
print('BASE',[(o.name,o.type,tuple(o.dimensions)) for o in bpy.data.objects])
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
base=set(bpy.data.objects)
rig.animation_data_clear()
for name in ['idle','run','jump']:
    before=set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=str(root/f'tools/asset_downloads/survivors/Animations/{name}.fbx'))
    imported_rig=next(o for o in bpy.data.objects if o not in base and o.type=='ARMATURE')
    actions=[a for a in set(bpy.data.actions)-before if name.lower() in a.name.lower()]
    for action in actions:
        action.name=name
        action.use_fake_user=True
        rig.animation_data_create()
        track=rig.animation_data.nla_tracks.new()
        track.name=name
        strip=track.strips.new(name,0,action)
        if action.slots: strip.action_slot=action.slots[0]
    for o in list(bpy.data.objects):
        if o not in base: bpy.data.objects.remove(o,do_unlink=True)
mat=bpy.data.materials.new('Survivor_Skin')
mat.use_nodes=True
tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
tex.image=bpy.data.images.load(str(root/'tools/asset_downloads/survivors/Skins/survivorMaleB.png'))
mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
for obj in base:
    if obj.type=='MESH':
        obj.data.materials.clear(); obj.data.materials.append(mat)
rig.animation_data.action=None
bpy.ops.export_scene.gltf(filepath=str(root/'assets/mobile/survivor.glb'),export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS')
bpy.ops.wm.open_mainfile(filepath=str(root/'tools/asset_downloads/boar.blend'),load_ui=False)
for o in list(bpy.data.objects):
    if o.type not in {'MESH','ARMATURE'}: bpy.data.objects.remove(o,do_unlink=True)
for obj in bpy.data.objects:
    if obj.type=='MESH':
        print('BOAR',obj.name,len(obj.data.polygons),tuple(obj.dimensions))
        if len(obj.data.polygons)>6000:
            mod=obj.modifiers.new('Mobile budget','DECIMATE'); mod.ratio=6000/len(obj.data.polygons)
        mat=bpy.data.materials.new('Boar_Brown'); mat.diffuse_color=(0.23,0.12,0.06,1); mat.use_nodes=True
        mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(0.23,0.12,0.06,1)
        obj.data.materials.clear(); obj.data.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=str(root/'assets/mobile/boar.glb'),export_format='GLB',export_apply=True)
print('CONVERSION COMPLETE')



