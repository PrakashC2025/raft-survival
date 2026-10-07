"""Original atlas and a clothed derivative of the existing CC0 survivor.

Preserves the original skeleton, skin weights, normals and animation library.
No new downloaded assets. Run from the project root with Python/Pillow/numpy.
"""
from pathlib import Path
import struct
import numpy as np
from PIL import Image
from bake_palette_glb import _read_glb, _accessor_start, _read_vec3_accessor, _encode_glb

ROOT = Path(__file__).resolve().parents[1]
output = ROOT / 'textures/construction'
output.mkdir(exist_ok=True, parents=True)
rng = np.random.default_rng(20261007)
y, x = np.mgrid[:2048,:2048].astype(np.float32)
warp = y + 9*np.sin(x*.007) + 4*np.sin(x*.03 + y*.006)
grain = .07*np.sin(warp*.7) + .035*np.sin(warp*2.7) + .025*rng.normal(size=x.shape)
grain += .04*np.sin(x*.017+y*.12) + .06*np.sin(warp*.055)
palette = [(139,111,71),(160,130,109),(62,39,35),(177,151,106)]
atlas = np.empty((2048,2048,3),np.uint8)
for index, color in enumerate(palette):
    sl = slice(index*512,(index+1)*512)
    for c in range(3):
        atlas[sl,:,c] = np.clip(color[c]*(1+grain[sl]*1.2),0,255)
Image.fromarray(atlas).save(output/'timber_atlas.png')
# A small neutral weave atlas; vertex colours supply canvas, denim and leather.
y,x=np.mgrid[:512,:1024].astype(np.float32)
weave=.93+.035*np.sin(x*np.pi/2)*np.sin(y*np.pi/2)
weave+=.025*np.sin(x*.045+y*.023)+rng.normal(0,.012,x.shape)
cloth=np.repeat(np.clip(weave*255,0,255)[:,:,None],3,axis=2).astype(np.uint8)
Image.fromarray(cloth).save(output/'survivalist_weave.png')
d,b,extra=_read_glb(ROOT/'models/beach_survivor.glb')
binary=bytearray(b)

def append_accessor(values, components, kind):
    while len(binary)%4: binary.append(0)
    offset=len(binary)
    for value in values: binary.extend(struct.pack('<'+'f'*components,*value))
    view=len(d['bufferViews'])
    d['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset})
    accessor=len(d['accessors'])
    d['accessors'].append({'bufferView':view,'componentType':5126,'count':len(values),'type':kind})
    return accessor

def linear(color):
    return tuple(((v/255+.055)/1.055)**2.4 if v/255>.04045 else v/255/12.92 for v in color)+(1.0,)

for mesh in d['meshes']:
    for primitive in mesh['primitives']:
        attr=primitive['attributes']
        positions=_read_vec3_accessor(d,b,attr['POSITION'])
        acc,view,start,stride=_accessor_start(d,attr['COLOR_0'])
        colors=[];uv=[]
        for index,(px,py,pz) in enumerate(positions):
            color=struct.unpack_from('<4f',b,start+index*(stride or 16))
            height=pz/.0187765
            if height<.115:
                color=linear((79,49,32))
            elif height<.50:
                color=linear((62,77,87))
            elif height<.79 and abs(px)<.0062:
                color=linear((164,148,113))
            colors.append(color)
            uv.append((px*160+py*70,pz*130))
        attr['COLOR_0']=append_accessor(colors,4,'VEC4')
        attr['TEXCOORD_0']=append_accessor(uv,2,'VEC2')
d['asset']['extras']={'derivative':'Original canvas/denim/boot colours and weave UVs; existing CC0 rig retained.'}
d['buffers'][0]['byteLength']=len(binary)
(ROOT/'models/survivalist.glb').write_bytes(_encode_glb(d,bytes(binary),extra))
print('Prepared 2048px shared timber atlas, 1024px weave and rigged survivalist.')
