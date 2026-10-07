shader_type spatial;
render_mode cull_disabled;
// Geometry supplies three twisted strands; this adds dry hemp fibres.
void fragment() {
 float phase = UV.x * 680.0 + UV.y * 25.13274;
 float filtering = 1.0 - smoothstep(0.8,3.0,fwidth(phase));
 float fibre = sin(phase) * filtering * 0.07;
 float weave = sin(UV.x * 36.0 - UV.y * 12.56637) * 0.04;
 ALBEDO = vec3(0.44,0.31,0.17) * (1.0+fibre+weave);
 ROUGHNESS = 0.96;
 SPECULAR = 0.16;
 NORMAL_MAP = normalize(vec3(cos(phase)*filtering*0.16,0.0,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH = 0.25;
}
