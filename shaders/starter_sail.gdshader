shader_type spatial;
render_mode cull_disabled;
void vertex() { VERTEX.z += sin(UV.x*6.0+TIME*1.6)*0.025*(1.0-UV.y); }
void fragment() {
	float weave = sin(UV.x*230.0)*sin(UV.y*190.0)*0.035;
	float stain = sin(UV.x*15.0+UV.y*9.0)*0.04;
	ALBEDO = vec3(0.52,0.48,0.37)+weave+stain;
	ROUGHNESS = 0.95;
}
