shader_type spatial;
uniform sampler2D wood_texture : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 local_pos;
varying vec3 local_normal;
void vertex() { local_pos = VERTEX; local_normal = NORMAL; }
void fragment() {
	vec3 timber = texture(wood_texture,vec2(UV.y * 0.85,UV.x * 0.32)).rgb;
	if(abs(local_normal.y) > 0.8) {
		float radius = length(local_pos.xz);
		float rings = sin(radius*320.0 + sin(atan(local_pos.z,local_pos.x)*4.0)*1.4)*0.5+0.5;
		timber = mix(vec3(0.25,0.19,0.12),vec3(0.47,0.36,0.22),rings*0.45+0.25);
	}
	ALBEDO = timber*vec3(0.48,0.43,0.36);
	ROUGHNESS = 0.92;
	SPECULAR = 0.16;
	NORMAL_MAP = vec3(0.5,0.5,1.0);
	NORMAL_MAP_DEPTH = 0.0;
}
