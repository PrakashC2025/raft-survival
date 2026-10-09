shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int produce_kind = 0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec2 grid = UV*vec2(68.0,42.0);
	float grain = noise(grid*3.0);
	float spots = (1.0-smoothstep(0.02,0.15,length(fract(grid)-vec2(0.5))))*step(0.94,grain);
	float broad = noise(UV*vec2(9.0,7.0));
	if (produce_kind == 0) {
		float eye = 1.0-smoothstep(0.045,0.19,length(fract(grid)-vec2(0.5)));
		eye *= step(0.91,hash(floor(grid)));
		ALBEDO = mix(vec3(0.30,0.17,0.073),vec3(0.60,0.43,0.23),broad*0.65+grain*0.35);
		ALBEDO *= 1.0-eye*0.52;
		ROUGHNESS = 0.86;
	} else if (produce_kind == 1) {
		ALBEDO = mix(vec3(0.28,0.009,0.003),vec3(0.70,0.045,0.012),0.6+broad*0.3);
		ALBEDO *= 0.94+grain*0.06;
		ROUGHNESS = 0.34+grain*0.09;
	} else {
		float rib = pow(abs(sin(UV.x*3.14159265*6.0)),12.0);
		ALBEDO = mix(vec3(0.55,0.31,0.026),vec3(0.90,0.70,0.10),0.55+broad*0.3);
		float ends = 1.0-smoothstep(0.015,0.09,min(UV.y,1.0-UV.y));
		ALBEDO *= 1.0-spots*0.65-rib*0.07;
		ALBEDO = mix(ALBEDO,vec3(0.12,0.065,0.018),ends*0.85);
		ROUGHNESS = 0.6;
	}
	SPECULAR = 0.25;
}
