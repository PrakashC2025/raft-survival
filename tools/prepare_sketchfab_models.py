"""Prepare licensed source geometry; never execute scripts embedded in asset files."""
import bpy, pathlib, math, json, hashlib, numpy as np, bmesh, sys
from mathutils import Vector, Matrix
ROOT=pathlib.Path(r'C:\GodotProjects\raft-survival')
SOURCE=ROOT/'3d models/free_wildlife/sketchfab';OUT=ROOT/'models'
records=[]
def load(file):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE/file));bpy.context.view_layer.update()
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    names={ob:ob.parent.name if ob.parent else ob.name for ob in meshes}
    for ob in meshes:
        world=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=Matrix.Identity(4);ob.data.transform(world)
    for ob in list(bpy.data.objects):
        if ob.type!='MESH':bpy.data.objects.remove(ob,do_unlink=True)
    for ob,name in names.items():ob.name=name
    return meshes
def bounds(meshes):
    co=np.array([v.co[:] for ob in meshes for v in ob.data.vertices])
    return co.min(0),co.max(0)
def empty(name,parent=None,position=(0,0,0)):
    ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob);ob.parent=parent;ob.location=position;return ob
def reduce(ob,ratio):
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('Mobile silhouette budget','DECIMATE');mod.ratio=ratio
    bpy.ops.object.modifier_apply(modifier=mod.name)
def weld_parts(parts):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:ob.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();ob=bpy.context.object
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001);bm.to_mesh(ob.data);bm.free()
    return ob
def textures(maximum=2048):
    for img in bpy.data.images:
        if img.size[0]>maximum or img.size[1]>maximum:
            factor=maximum/max(img.size);img.scale(round(img.size[0]*factor),round(img.size[1]*factor))
def export(file,source,title,author,url,license='CC-BY-4.0',changes=''):
    textures();bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/file),export_format='GLB',use_selection=True,export_apply=True,
      export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_skins=True,
      export_extras=False,export_image_format='AUTO')
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    records.append({'title':title,'author':author,'source_url':url,'license':license,'changes':changes,
      'source':str((SOURCE/source).relative_to(ROOT)),'source_sha256':hashlib.sha256((SOURCE/source).read_bytes()).hexdigest(),
      'file':f'models/{file}','sha256':hashlib.sha256((OUT/file).read_bytes()).hexdigest(),
      'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),
      'bounds':[a.tolist() for a in bounds(meshes)],'clips':[a.name for a in bpy.data.actions]})
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(file+'.blend')),check_existing=False)
    print('PREPARED',records[-1],flush=True)
def boat():
    src='victorian_row_boat.glb';meshes=load(src)
    root=empty('VictorianRowboat');groups={name:empty(name,root) for name in ['Hull','Interior','Seats','Oars']}
    # Match the existing metre-scale hull, waterline, seating and collision envelope.
    factor=3.6/1.85555
    for ob in meshes:
        for v in ob.data.vertices:v.co=Vector((v.co.x*factor,-v.co.y*factor,v.co.z*factor+.40))
        ob.data.update()
        if ob.name=='oar_low':continue
        if ob.name=='chest_low':bpy.data.objects.remove(ob,do_unlink=True);continue
        group='Seats' if ob.name in ['benches_low','rearbench_low','rearbraces_low'] else 'Interior' if ob.name in ['braces_low','bottomboards_low','pegs_low'] else 'Hull'
        ob.parent=groups[group]
    oar=next(o for o in meshes if o.name=='oar_low')
    # Reuse the authored oar UVs on two real working oars. The original points along Y.
    coords=np.array([v.co[:] for v in oar.data.vertices]);low,high=coords.min(0),coords.max(0)
    for side,label in [(-1,'OarLeft'),(1,'OarRight')]:
        # Blender +Y becomes game -Z, and Blender Z becomes game Y.
        pivot=empty(label,groups['Oars'],(side*.65,-.36,.43))
        part=bpy.data.objects.new('TexturedOakOar',oar.data.copy());bpy.context.collection.objects.link(part);part.parent=pivot
        for v in part.data.vertices:
            t=1-(v.co.y-low[1])/(high[1]-low[1])
            # Small end is the handle; the wide end is the spoon blade.
            v.co=Vector((side*(-.36+t*1.85),-(v.co.x-(low[0]+high[0])*.5)*1.1+t*-.30,
                         (v.co.z-(low[2]+high[2])*.5)+.04-t*.40))
    bpy.data.objects.remove(oar,do_unlink=True)
    export('hunting_rowboat.glb',src,'Victorian Row Boat','Ashley Aslett',
      'https://sketchfab.com/3d-models/victorian-row-boat-3e9093b6f0ce474da4d8cfea7e01f420',changes='Metre scale, waterline fit, staged construction groups, removed loose chest, paired pivoted source oars, 2K PBR maps retained.')
def workbench():
    src='wooden_workbench_-_free.glb';meshes=load(src)
    # Long side becomes X, height 95cm; place base at the existing build socket.
    root=empty('BoatwrightWorkbench')
    for ob in meshes:
        for v in ob.data.vertices:v.co=Vector((v.co.y*1.28,-v.co.x*1.20,v.co.z*.78-.46))
        ob.parent=root
    export('hunting_workbench.glb',src,'Wooden Workbench - FREE','volvor',
      'https://sketchfab.com/3d-models/wooden-workbench-free-30c3115341f342718e8245ea0b941348',changes='Fits original workshop footprint and socket, original separate vise/tools/boxes retained, textures resized to 2K.')
def rig_croc(meshes):
    arm=bpy.data.armatures.new('CrocodileOriginalRig');rig=bpy.data.objects.new('CrocodileRig',arm);bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    # Simple authored quadruped skeleton, in Blender +Y forward.
    specs={'Body':((0,0,.30),(0,.5,.30),None),'Head':((0,.55,.30),(0,1.1,.27),'Body'),
      'Jaw':((0,.72,.23),(0,1.28,.16),'Head'),'Tail1':((0,-.38,.30),(0,-.85,.26),'Body'),
      'Tail2':((0,-.85,.26),(0,-1.25,.22),'Tail1'),'Tail3':((0,-1.25,.22),(0,-1.65,.16),'Tail2')}
    for side,sign in [('L',1),('R',-1)]:
        for end,y in [('Front',.45),('Back',-.30)]:
            specs[f'{end}{side}']=((sign*.20,y,.28),(sign*.42,y-.12,.13),'Body')
            specs[f'{end}{side}Foot']=((sign*.42,y-.12,.13),(sign*.55,y+.03,.07),f'{end}{side}')
    for name,(head,tail,parent) in specs.items():
        bone=arm.edit_bones.new(name);bone.head=head;bone.tail=tail
        if parent:bone.parent=arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT');rig.select_set(False)
    for ob in meshes:
        groups={name:ob.vertex_groups.new(name=name) for name in specs}
        for v in ob.data.vertices:
            x,y,z=v.co;weights={'Body':1.0}
            if y<-.4:
                t=max(0,min(2.9,(-y-.4)/.45));i=int(t);a=min(i+1,3);b=min(i+2,3)
                weights={f'Tail{a}':1-(t-i),f'Tail{b}':t-i} if a!=b else {f'Tail{a}':1.0}
            elif y>.55:
                head=max(0,min(1,(y-.55)/.25));weights={'Body':1-head,'Head':head}
                if 'lower_teeth' in ob.name or (z<.16 and y>.82):weights={'Jaw':1.0}
            # Limbs are below the trunk; blend only at the anatomical shoulder/hip.
            elif abs(x)>.23 and z<.30:
                end='Front' if y>.10 else 'Back';side='L' if x>0 else 'R';w=max(0,min(1,(abs(x)-.23)/.11))
                foot=max(0,min(1,(abs(x)-.38)/.10));weights={'Body':1-w,end+side:w*(1-foot),end+side+'Foot':w*foot}
            for name,w in weights.items():
                if w>.001:groups[name].add([v.index],w,'REPLACE')
        mod=ob.modifiers.new('Smooth authored motion','ARMATURE');mod.object=rig;ob.parent=rig
    animate(rig)
def animate(rig):
    rig.animation_data_create();scene=bpy.context.scene;scene.render.fps=30
    for clip in ['Idle','Walk','Attack','Swim']:
        action=bpy.data.actions.new(clip);action.use_fake_user=True;rig.animation_data.action=action
        end=30 if clip!='Attack' else 18
        for f in range(1,end+1,2):
            phase=(f-1)/max(1,end-1)*math.tau;scene.frame_set(f)
            for bone in rig.pose.bones:
                bone.rotation_mode='XYZ';bone.rotation_euler=(0,0,0);bone.location=(0,0,0)
                name=bone.name
                if name.startswith('Tail'):
                    index=int(name[-1]);bone.rotation_euler.z=math.sin(phase-index*.65)*(.18 if clip=='Swim' else .055)
                if clip=='Walk' and name.startswith(('Front','Back')):
                    diagonal=0 if name.startswith('FrontL') or name.startswith('BackR') else math.pi
                    bone.rotation_euler.x=math.sin(phase+diagonal)*(.3 if name.endswith('Foot') else .20)
                    bone.rotation_euler.z=math.cos(phase+diagonal)*.08
                if clip=='Swim' and name.startswith(('Front','Back')):bone.rotation_euler.x=-.22
                if name=='Body':bone.location.z=math.sin(phase)*(.003 if clip=='Idle' else .007)
                if name=='Head':bone.rotation_euler.x=math.sin(phase)*.015
                if name=='Jaw' and clip=='Attack':bone.rotation_euler.x=math.sin((f-1)/(end-1)*math.pi)*.32
                bone.keyframe_insert(data_path='rotation_euler',frame=f);bone.keyframe_insert(data_path='location',frame=f)
        # The last frame exactly matches the first for continuous locomotion.
        if clip!='Attack':
            scene.frame_set(1)
            for bone in rig.pose.bones:
                for prop in ['rotation_euler','location']:bone.keyframe_insert(data_path=prop,frame=end)
    rig.animation_data.action=bpy.data.actions['Idle'];scene.frame_set(1)
def croc():
    src='crocodile_siamese_crocodile.glb';meshes=load(src)
    body=[o for o in meshes if o.name.startswith('polySurface7')]
    meshes=[o for o in meshes if o not in body]+[weld_parts(body)]
    # The source is pitched; derive its ground plane from its four named claws.
    feet=[]
    for ob in meshes:
        if 'leg_nails' in ob.name:feet.append(np.mean([v.co[:] for v in ob.data.vertices],axis=0))
    feet=np.array(feet);a,b,c=np.linalg.lstsq(np.column_stack([feet[:,0],feet[:,1],np.ones(len(feet))]),feet[:,2],rcond=None)[0]
    print('FOOTPLANE',feet.tolist(),a,b,c,flush=True)
    up=Vector((-a,-b,1)).normalized();forward=Vector((0,-1,-b)).normalized();right=forward.cross(up).normalized();forward=up.cross(right)
    basis=Matrix((right,forward,up)).to_4x4()
    for ob in meshes:ob.data.transform(basis)
    lo,hi=bounds(meshes);factor=3.5/(hi[1]-lo[1]);center=(lo+hi)*.5
    # Centre mass between hips/shoulders, and feet at the ground.
    foot_up=np.mean([(basis@Vector(p)).z for p in feet]);nose=hi[1]
    for ob in meshes:
        for v in ob.data.vertices:v.co=Vector(((v.co.x-center[0])*factor,(v.co.y-(nose-1.35/factor))*factor,(v.co.z-foot_up)*factor+.07))
    # Straighten the arched static display pose into a low centreline before skinning.
    points=np.array([v.co[:] for ob in meshes if ob.name.startswith('polySurface7') for v in ob.data.vertices])
    ys=np.linspace(points[:,1].min(),points[:,1].max(),60);profile=[]
    for y in ys:
        section=points[(abs(points[:,1]-y)<.09)&(abs(points[:,0])<.30)]
        if not len(section):section=points[abs(points[:,1]-y)<.12]
        profile.append(float(np.median(section[:,2])) if len(section) else (profile[-1] if profile else 0))
    profile=np.convolve(np.pad(profile,(3,3),mode='edge'),np.ones(7)/7,mode='valid')
    for ob in meshes:
        for v in ob.data.vertices:
            x,y,z=v.co;mid=float(np.interp(y,ys,profile));target=.28 if y>-.55 else max(.08,.28+(y+.55)*.14)
            v.co=Vector((x*.61,y,(z-mid)*.55+target))
    feet_new=[v.co.z for ob in meshes if 'leg_nails' in ob.name for v in ob.data.vertices]
    offset=min(feet_new)-.025
    for ob in meshes:
        for v in ob.data.vertices:
            v.co.z=(v.co.z-offset)*.25+.24
            # Splayed feet stay on the shore while the trunk clears the ground.
            if abs(v.co.x)>.27 and -.65<v.co.y<.65:
                v.co.z-=min(1,(abs(v.co.x)-.27)/.16)*.22
            v.co.z=max(.018,v.co.z)
        reduce(ob,.34 if 'polySurface7' in ob.name else .18)
        for polygon in ob.data.polygons:polygon.use_smooth=True
    rig_croc(meshes)
    export('hunting_crocodile.glb',src,'Crocodile (Siamese crocodile)','sarvesh777 (sarvesh903)',
      'https://sketchfab.com/3d-models/crocodile-siamese-crocodile-10704d6d49c449d8b4ab69e924f1b9d3',changes='Static free model reduced for mobile; original UVs and PBR retained at 2K; original quadruped/tail/jaw rig and Idle/Walk/Attack/Swim clips, metre scale and ground-plane correction.')
if __name__=='__main__':
    # Runtime animals are prepared by prepare_hunting_models.py. The downloaded
    # Siamese display mesh above is retained only as a source-material experiment.
    boat();workbench()
    skin=OUT/'hunting_crocodile_Image_7.png'
    records.append({'title':'Crocodile (Siamese crocodile) skin detail','author':'sarvesh777 (sarvesh903)',
      'source_url':'https://sketchfab.com/3d-models/crocodile-siamese-crocodile-10704d6d49c449d8b4ab69e924f1b9d3',
      'license':'CC-BY-4.0','file':'models/hunting_crocodile_Image_7.png',
      'sha256':hashlib.sha256(skin.read_bytes()).hexdigest(),
      'changes':'2K skin surface projected over the separately credited CC0 animated crocodile; the source display mesh is not active.'})
    (OUT/'sketchfab_hunting.source.json').write_text(json.dumps(records,indent=2))
