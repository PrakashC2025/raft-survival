shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D original_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool textured = false;
uniform vec4 original_color : source_color = vec4(1.0);
uniform float original_metallic = 0.0;
varying vec3 surface_point;
float hash(vec3 p) { p=fract(p*0.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }
float noise(vec3 p) {
    vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1)),f.x),f.y),f.z);
}
void vertex() { surface_point=VERTEX; }
void fragment() {
    vec3 p=surface_point;
    vec3 colour=original_color.rgb*COLOR.rgb;
    if (textured) colour*=texture(original_texture,UV).rgb;
    float grime=smoothstep(0.40,0.76,noise(p*46.0+vec3(7.4)));
    float faded=noise(p*18.0);
    float scratch=(1.0-smoothstep(0.015,0.055,abs(sin(p.x*310.0+p.y*49.0))))*smoothstep(0.45,0.70,noise(p*92.0));
    scratch*=1.0-smoothstep(0.5,1.5,fwidth(p.x*310.0+p.y*49.0));
    colour=mix(colour*(0.84+faded*0.16),vec3(0.18,0.135,0.075),grime*0.43);
    colour=mix(colour,mix(colour*1.25+vec3(0.025),vec3(0.28,0.25,0.20),original_metallic),scratch*0.30);
    ALBEDO=colour;
    ROUGHNESS=0.78+grime*0.17;
    METALLIC=original_metallic*(1.0-grime*0.8);
    SPECULAR=0.28;
}
