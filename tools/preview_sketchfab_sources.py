import bpy, pathlib, numpy as np, math, json
from mathutils import Vector, Matrix
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
ASSETS=[('boat','victorian_row_boat.glb',3.6),('crocodile','crocodile_siamese_crocodile.glb',3.5),('boar','wild_boar_textured.glb',1.85),('workbench','wooden_workbench_-_free.glb',1.8)]
records={}
for kind,filename,length in ASSETS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'3d models/free_wildlife/sketchfab'/filename))
    bpy.context.view_layer.update()
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    coords=[]
    for ob in meshes:
        world=ob.matrix_world.copy(); ob.parent=None; ob.matrix_world=world
        bpy.context.view_layer.objects.active=ob; ob.select_set(True)
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True); ob.select_set(False)
        coords.extend([v.co[:] for v in ob.data.vertices][::max(1,len(ob.data.vertices)//18000)])
    points=np.asarray(coords)
    if kind in ['boar','crocodile']:
        values,vectors=np.linalg.eigh(np.cov(points.T))
        forward=vectors[:,2]
        up=vectors[:,1 if kind=='boar' else 0]
        # Preliminary signs are inspected in the generated source previews.
        if up[2]<0:up=-up
        right=np.cross(forward,up); right/=np.linalg.norm(right)
        up=np.cross(right,forward)
        basis=np.asarray([right,forward,up])
    else:basis=np.eye(3)
    oriented=points@basis.T
    lo=oriented.min(axis=0); hi=oriented.max(axis=0)
    axis=1 if kind!='workbench' else 0
    scale=length/(hi[axis]-lo[axis]); center=(lo+hi)*.5; center[2]=lo[2]
    transform=Matrix.Translation(Vector(-center*scale))@Matrix.Diagonal((scale,scale,scale,1))@Matrix(basis.tolist()).to_4x4()
    for ob in meshes:ob.data.transform(transform)
    bpy.context.view_layer.update()
    print('SOURCE',kind,'basis',basis.tolist(),'size',((hi-lo)*scale).tolist(),flush=True)
    print('PARTS',kind,[(o.name,o.data.name) for o in meshes],flush=True)
    # Preserve the baked original UVs and material graphs.
    for material in bpy.data.materials:
        if material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type=='BSDF_PRINCIPLED':
                    node.inputs['Metallic'].default_value=0 if kind in ['boar','crocodile'] else node.inputs['Metallic'].default_value
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.01));floor=bpy.context.object
    mat=bpy.data.materials.new('StudioGround');mat.diffuse_color=(.16,.19,.21,1);floor.data.materials.append(mat)
    bpy.ops.object.camera_add(location=(length*1.0,-length*1.15,length*.8));cam=bpy.context.object
    target=Vector((0,0,length*.16));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=length*1.25;bpy.context.scene.camera=cam
    for location,energy,size in [((2,-3,5),900,5),((-4,1,3),650,4)]:
        bpy.ops.object.light_add(type='AREA',location=location);light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=size
        light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
    scene=bpy.context.scene;scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.25,.29,.33,1)
    scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
    scene.render.resolution_x=900;scene.render.resolution_y=700;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.render.filepath=str(ROOT/'build'/f'source-{kind}.png')
    bpy.ops.render.render(write_still=True)
    records[kind]={'file':filename,'basis':basis.tolist(),'center':center.tolist(),'scale':float(scale),'size':((hi-lo)*scale).tolist()}
(ROOT/'build/sketchfab-normalization.json').write_text(json.dumps(records,indent=2))
