shader_type spatial;
render_mode diffuse_burley;
uniform vec4 earth_color : source_color = vec4(0.29,0.20,0.12,1.0);
uniform float moisture = 0.75;
uniform sampler2D earth_grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 p;
float hash(vec2 v) { return fract(sin(dot(v,vec2(127.1,311.7)))*43758.5453); }
float grains(vec2 v) {
    vec2 cell=floor(v),f=fract(v);
    float nearest=1.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 at=vec2(float(x),float(y));
        vec2 offset=vec2(hash(cell+at),hash(cell+at+19.4));
        nearest=min(nearest,length(at+offset-f));
    }
    return nearest;
}
void vertex() { p=VERTEX; }
void fragment() {
    float clod=grains(p.xz*110.0);
    float fine=hash(floor(p.xz*480.0));
    float pore=smoothstep(0.18,0.46,clod);
    float resolved=1.0-smoothstep(0.3,1.5,length(fwidth(p.xz*110.0)));
    vec3 grain=texture(earth_grain,p.xz*3.0).rgb;
    float photographic=dot(grain,vec3(0.33));
    float relief=mix(0.5,pore,resolved)*0.20+photographic*0.80;
    vec3 dry=earth_color.rgb*COLOR.rgb*(0.79+photographic*0.55+(pore-0.5)*0.09+fine*0.035);
    ALBEDO=dry*mix(1.10,0.78,moisture);
    ROUGHNESS=mix(0.99,0.88,moisture);
    SPECULAR=0.18;
    AO=mix(0.86,1.0,relief);
    // Screen-space height gradient perturbs the actual surface normal.
    vec3 dpdx=dFdx(VERTEX),dpdy=dFdy(VERTEX);
    vec3 r1=cross(dpdy,NORMAL),r2=cross(NORMAL,dpdx);
    float determinant=dot(dpdx,r1);
    vec3 gradient=sign(determinant)*(dFdx(relief)*r1+dFdy(relief)*r2);
    NORMAL=normalize(abs(determinant)*NORMAL-gradient*0.0015);
}
