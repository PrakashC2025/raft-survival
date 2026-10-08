shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int produce_kind = 0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
	vec2 grid = UV*vec2(68.0,42.0);
	float grain = hash(floor(grid));
	float spots = (1.0-smoothstep(0.02,0.15,length(fract(grid)-vec2(0.5))))*step(0.94,grain);
	float broad = sin(UV.x*31.0+sin(UV.y*18.0))*sin(UV.y*23.0)*0.5+0.5;
	if (produce_kind == 0) {
		ALBEDO = mix(vec3(0.24,0.125,0.044),vec3(0.53,0.34,0.15),broad*0.5+grain*0.5);
		ALBEDO *= 1.0-spots*0.65;
		ROUGHNESS = 0.86;
	} else if (produce_kind == 1) {
		ALBEDO = mix(vec3(0.28,0.009,0.003),vec3(0.70,0.045,0.012),0.6+broad*0.3);
		ALBEDO *= 0.94+grain*0.06;
		ROUGHNESS = 0.32;
	} else {
		float rib = pow(abs(sin(UV.x*3.14159265*6.0)),12.0);
		ALBEDO = mix(vec3(0.55,0.31,0.026),vec3(0.90,0.70,0.10),0.55+broad*0.3);
		ALBEDO *= 1.0-spots*0.8-rib*0.08;
		ROUGHNESS = 0.6;
	}
	SPECULAR = 0.25;
}
