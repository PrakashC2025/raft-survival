"""Inspect supplied low-poly plant FBX without executing embedded scripts."""
import bpy, pathlib, json, hashlib, struct, tempfile, numpy as np
from mathutils import Vector
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
SOURCE=ROOT/'3d models/lopoly_plants/shapespark-low-poly-plants-kit.fbx'
tempfile.tempdir=str(ROOT/'build/blender-plant-temp')
pathlib.Path(tempfile.tempdir).mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(SOURCE),use_image_search=False)
report={'source':SOURCE.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'objects':[],'images':[]}
for ob in bpy.context.scene.objects:
    if ob.type not in {'MESH','CURVE','EMPTY'}:continue
    pts=[ob.matrix_world@Vector(c) for c in ob.bound_box]
    report['objects'].append({'name':ob.name,'type':ob.type,'parent':ob.parent.name if ob.parent else None,'faces':len(ob.data.polygons) if ob.type=='MESH' else 0,'bounds':[[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]],'materials':[{'name':m.name,'color':list(m.diffuse_color),'images':[n.image.name for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]} for m in ob.data.materials if m] if ob.type!='EMPTY' else [],'uv_bounds':[[min(v.uv[i] for v in ob.data.uv_layers.active.data),max(v.uv[i] for v in ob.data.uv_layers.active.data)] for i in range(2)] if ob.type=='MESH' and ob.data.uv_layers.active else []})
for im in bpy.data.images:report['images'].append({'name':im.name,'file':im.filepath,'size':list(im.size),'packed':bool(im.packed_file)})
(ROOT/'build/island-plants-inspection.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'objects':len(report['objects']),'textures':len(report['images'])}))

SELECTION=[('Tree-02-1','CanopyA',4.4),('Tree-03-4','CanopyB',3.9),('Bush-03','ShrubA',.78),('Bush-04','ShrubB',.7),('Grass-02','TallGrass',.64),('Flowers-02','WildFlowers',.58),('Clover-01','CloverA',.72),('Clover-03','CloverB',.68)]
images={}
for source_name,_,_ in SELECTION:
    for material in bpy.data.objects[source_name].data.materials:
        if material and not material.name.startswith('trunk'):
            im=next(n.image for n in material.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
            images.setdefault(pathlib.Path(im.filepath).name,im)
assert len(images)<=16
atlas_pixels=np.zeros((2048,2048,4),dtype=np.float32)
tiles={}
for index,(key,im) in enumerate(images.items()):
    copy=im.copy();copy.scale(496,496)
    pixels=np.array(copy.pixels[:],dtype=np.float32).reshape(496,496,4)
    cell=np.pad(pixels,((8,8),(8,8),(0,0)),mode='edge')
    x=index%4*512;y=index//4*512;atlas_pixels[y:y+512,x:x+512]=cell
    tiles[key]=(x+8,y+8);bpy.data.images.remove(copy)
atlas=bpy.data.images.new('OwnerLowpolyLeafAtlas',width=2048,height=2048,alpha=True)
atlas.pixels.foreach_set(atlas_pixels.ravel());atlas.pack()
leaf=bpy.data.materials.new('OwnerLowpolyLeaves');leaf.use_nodes=True;leaf.use_backface_culling=False
leaf_bs=leaf.node_tree.nodes.get('Principled BSDF');leaf_bs.inputs['Roughness'].default_value=.88
leaf_tex=leaf.node_tree.nodes.new('ShaderNodeTexImage');leaf_tex.image=atlas
leaf.node_tree.links.new(leaf_tex.outputs['Color'],leaf_bs.inputs['Base Color']);leaf.node_tree.links.new(leaf_tex.outputs['Alpha'],leaf_bs.inputs['Alpha'])
bark_image=bpy.data.images['bark.jpg'].copy();bark_image.scale(512,512);bark_image.pack()
bark=bpy.data.materials.new('OwnerLowpolyBark');bark.use_nodes=True
bark_bs=bark.node_tree.nodes.get('Principled BSDF');bark_bs.inputs['Roughness'].default_value=.94
bark_tex=bark.node_tree.nodes.new('ShaderNodeTexImage');bark_tex.image=bark_image;bark.node_tree.links.new(bark_tex.outputs['Color'],bark_bs.inputs['Base Color'])
prepared=[];exports=[]
for source_name,label,target_size in SELECTION:
    original=bpy.data.objects[source_name]
    ob=original.copy();ob.data=original.data.copy();bpy.context.scene.collection.objects.link(ob);ob.name=label
    ob.animation_data_clear();world=original.matrix_world.copy();ob.parent=None;ob.matrix_world=world
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    vertices=[v.co.copy() for v in ob.data.vertices];floor=min(v.z for v in vertices)
    if label.startswith('Canopy'):
        trunk_vertices={v for face in ob.data.polygons if ob.data.materials[face.material_index].name.startswith('trunk') for v in face.vertices}
        bottom=[ob.data.vertices[v].co for v in trunk_vertices if ob.data.vertices[v].co.z<floor+.15]
        center=sum(bottom,Vector())/len(bottom)
    else:center=Vector(((min(v.x for v in vertices)+max(v.x for v in vertices))*.5,(min(v.y for v in vertices)+max(v.y for v in vertices))*.5,0))
    offset=Vector((center.x,center.y,floor))
    span=max(v.z for v in vertices)-floor if not label.startswith('Clover') else max(max(v.x for v in vertices)-min(v.x for v in vertices),max(v.y for v in vertices)-min(v.y for v in vertices))
    for vertex in ob.data.vertices:vertex.co=(vertex.co-offset)*(target_size/span)
    old_materials=list(ob.data.materials)
    for face in ob.data.polygons:
        original_material=old_materials[face.material_index]
        is_bark=original_material.name.startswith('trunk')
        if not is_bark:
            im=next(n.image for n in original_material.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
            ox,oy=tiles[pathlib.Path(im.filepath).name]
            for loop_index in face.loop_indices:
                uv=ob.data.uv_layers.active.data[loop_index].uv
                uv.x=(ox+max(0,min(1,uv.x))*496)/2048;uv.y=(oy+max(0,min(1,uv.y))*496)/2048
        face.material_index=1 if is_bark else 0
    # Clearing the slots resets polygon indices, so retain assignments first.
    assignments=[face.material_index for face in ob.data.polygons]
    ob.data.materials.clear();ob.data.materials.append(leaf)
    if label.startswith('Canopy'):ob.data.materials.append(bark)
    for face,index in zip(ob.data.polygons,assignments):face.material_index=index
    prepared.append(ob);exports.append({'source_object':source_name,'node':label,'triangles':sum(len(face.vertices)-2 for face in ob.data.polygons),'surfaces':len(ob.data.materials)})
bpy.ops.object.select_all(action='DESELECT')
for ob in prepared:ob.select_set(True)
destination=ROOT/'models/island_lowpoly_plants.glb'
bpy.ops.export_scene.gltf(filepath=str(destination),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
# Alpha cutout prevents rectangular leaf cards and transparent sorting artifacts.
raw=destination.read_bytes();json_size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+json_size])
for material in doc['materials']:
    if material['name']=='OwnerLowpolyLeaves':material.update(alphaMode='MASK',alphaCutoff=.45,doubleSided=True)
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=raw[20+json_size:];destination.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
provenance={'source':report['source'],'sha256':report['sha256'],'exports':exports,'textures':'Owner embedded textures consolidated into one 2048 RGBA leaf atlas with gutters, plus 512 bark; alpha MASK .45','license':'Owner supplied FBX; no license file supplied and no CC0 claim','excluded':'Unused display variants and source layout offsets; no source script executed'}
(ROOT/'models/island_lowpoly_plants.source.json').write_text(json.dumps(provenance,indent=2))
print('ISLAND_PLANTS_EXPORT',json.dumps(provenance))
