shader_type spatial;
render_mode cull_disabled;

void fragment() {
	float strand = sin(UV.x * 18.84956 + UV.y * 85.0);
	float fibre = sin(UV.x * 94.24778 - UV.y * 210.0) * 0.04;
	ALBEDO = mix(vec3(0.22, 0.13, 0.055), vec3(0.68, 0.51, 0.29), smoothstep(-0.9, 0.65, strand)) + fibre;
	ROUGHNESS = 0.88;
}