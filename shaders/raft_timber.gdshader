shader_type spatial;
uniform sampler2D wood_texture : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 local_pos;
varying vec3 local_normal;
void vertex() { local_pos = VERTEX; local_normal = NORMAL; }
void fragment() {
	vec3 timber = texture(wood_texture,vec2(UV.y * 0.85,0.02+UV.x * 0.21)).rgb;
	if(abs(local_normal.y) > 0.8) {
		float radius = length(local_pos.xz);
		float rings = sin(radius*320.0 + sin(atan(local_pos.z,local_pos.x)*4.0)*1.4)*0.5+0.5;
		timber = mix(vec3(0.25,0.19,0.12),vec3(0.47,0.36,0.22),rings*0.45+0.25);
	}
	ALBEDO = timber*vec3(0.82,0.79,0.74);
	ROUGHNESS = 0.92;
	SPECULAR = 0.16;
	float height = dot(timber,vec3(0.30,0.59,0.11));
	NORMAL_MAP = normalize(vec3(-dFdx(height)*0.4,-dFdy(height)*0.4,1.0))*0.5+0.5;
	NORMAL_MAP_DEPTH = 0.4;
}
