shader_type spatial;
varying vec3 p;
void vertex() {p=VERTEX;}
float h(vec3 v) {return fract(sin(dot(v,vec3(127.1,311.7,74.7)))*43758.5453);}
void fragment() {
    vec3 q=p*90.0, cell=floor(q),f=fract(q);
    float hole=1.0;
    for(int z=-1;z<=1;z++) for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec3 d=vec3(float(x),float(y),float(z));
        vec3 at=vec3(h(cell+d),h(cell+d+17.0),h(cell+d+39.0));
        hole=min(hole,length(d+at-f));
    }
    float pore=smoothstep(0.09,0.34,hole);
    ALBEDO=mix(vec3(0.12,0.07,0.018),vec3(0.57,0.39,0.10),pore);
    ROUGHNESS=0.99; SPECULAR=0.12; AO=0.35+pore*0.65;
}
