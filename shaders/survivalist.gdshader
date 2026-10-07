shader_type spatial;
// Existing skinned normals/proportions and linear vertex colours are preserved.
// A tiny shared weave provides worn canvas/denim/leather surface detail.
uniform sampler2D weave : source_color, filter_linear_mipmap, repeat_enable;
void fragment() {
	float fabric = texture(weave, UV * 2.0).r;
	ALBEDO = COLOR.rgb * mix(0.87, 1.07, fabric);
	ROUGHNESS = 0.84;
	SPECULAR = 0.25;
	NORMAL_MAP = normalize(vec3(-dFdx(fabric)*0.14,-dFdy(fabric)*0.14,1.0))*0.5+0.5;
	NORMAL_MAP_DEPTH = 0.16;
}
