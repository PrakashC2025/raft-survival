shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Shared 1K CC0 scan, projected in world space without stretched cliff UVs.
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 0.48;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 wn = normalize(world_normal);
	vec3 weights = pow(abs(wn), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.001);
	vec3 p = world_pos * texture_scale;
	vec3 colour = texture(rock_albedo, p.zy).rgb * weights.x
		+ texture(rock_albedo, p.xz).rgb * weights.y
		+ texture(rock_albedo, p.xy).rgb * weights.z;
	vec3 arm = texture(rock_arm, p.zy).rgb * weights.x
		+ texture(rock_arm, p.xz).rgb * weights.y
		+ texture(rock_arm, p.xy).rgb * weights.z;
	vec3 nx = texture(rock_normal, p.zy).xyz * 2.0 - 1.0;
	vec3 ny = texture(rock_normal, p.xz).xyz * 2.0 - 1.0;
	vec3 nz = texture(rock_normal, p.xy).xyz * 2.0 - 1.0;
	vec3 detail = normalize(vec3(nx.z * sign(wn.x), nx.y, nx.x) * weights.x
		+ vec3(ny.x, ny.z * sign(wn.y), ny.y) * weights.y
		+ vec3(nz.x, nz.y, nz.z * sign(wn.z)) * weights.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(wn, detail, 0.48)), 0.0)).xyz);
	float moss = smoothstep(0.38, 0.86, wn.y)
		* smoothstep(0.15, 0.82, sin(world_pos.x * 0.8 + sin(world_pos.z * 1.1)) * 0.5 + 0.5);
	float wet = 1.0 - smoothstep(-0.3, 0.85, world_pos.y);
	// Desaturate the mineral orange; sunset supplies the warm edges.
	float grey = dot(colour, vec3(0.3, 0.59, 0.11));
	colour = mix(vec3(grey) * vec3(0.93, 0.96, 0.98), colour, 0.35);
	ALBEDO = mix(colour, colour * vec3(0.45, 0.62, 0.26), moss * 0.50) * mix(0.90, 0.58, wet);
	AO = mix(0.65, 1.0, arm.r);
	ROUGHNESS = mix(clamp(arm.g, 0.72, 0.98), 0.48, wet);
	SPECULAR = 0.25;
}