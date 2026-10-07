shader_type spatial;
render_mode cull_disabled;
uniform bool photographic_hemp = false;
uniform sampler2D hemp_atlas : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
	float strand = sin(UV.x * 18.84956 + UV.y * 85.0);
	float fibre = sin(UV.x * 94.24778 - UV.y * 210.0) * 0.04;
	ALBEDO = mix(vec3(0.22, 0.13, 0.055), vec3(0.68, 0.51, 0.29), smoothstep(-0.9, 0.65, strand)) + fibre;
	ROUGHNESS = 0.88;
	if (photographic_hemp) {
		ALBEDO = texture(hemp_atlas,vec2(UV.x*3.0,0.77+fract(UV.y*2.0)*0.21)).rgb;
	}
}
