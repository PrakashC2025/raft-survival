shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 leaf_color : source_color = vec3(0.20, 0.34, 0.12);
uniform vec3 leaf_tip_color : source_color = vec3(0.30, 0.40, 0.17);
uniform bool use_albedo_texture = false;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.26;
uniform float leaf_radius = 0.52;
uniform float wind_strength = 0.035;
varying vec3 leaf_position;
varying float leaf_tip;

void vertex() {
	leaf_position = VERTEX;
	leaf_tip = smoothstep(0.03, leaf_radius, length(VERTEX.xz));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(NODE_POSITION_WORLD.xz, vec2(0.37, 0.19));
	float gust = 0.65 + 0.35 * sin(TIME * 0.43 + dot(wp.xz, vec2(0.08, 0.06)));
	float bend = sin(TIME * 1.45 + phase + length(VERTEX.xz) * 5.0);
	VERTEX += vec3(-0.707, 0.2, 0.707) * bend * wind_strength * gust * leaf_tip * leaf_tip;
	VERTEX.y += sin(TIME * 3.1 + phase + VERTEX.x * 12.0) * 0.009 * leaf_tip;
}

void fragment() {
	// Fine cross-veins, waxy cuticle sheen, and rich sunlight transmission through frond surfaces.
	float radius = length(leaf_position.xz);
	float veins = sin(radius * 165.0 + leaf_position.y * 22.0);
	float mottling = sin(leaf_position.x * 19.0) * sin(leaf_position.z * 25.0);
	if (use_albedo_texture) {
		vec4 tex = texture(albedo_texture, UV);
		if (tex.a < alpha_scissor_threshold) {
			discard;
		}
		// Natural tropical vibrancy with subtle sun-warmed highlights
		ALBEDO = tex.rgb * vec3(0.88, 0.96, 0.82);
	} else {
		ALBEDO = mix(leaf_color, leaf_tip_color, leaf_tip * 0.45);
		ALBEDO *= 0.94 + 0.04 * veins + 0.03 * mottling;
	}
	// Micro-grooved leaf veins catching sunlight
	vec3 vein_normal = vec3(veins * 0.08, 1.0, mottling * 0.06);
	NORMAL = FRONT_FACING ? normalize(NORMAL + vein_normal * 0.25) : -NORMAL;
	// Waxy tropical leaf sheen with higher specular glint on sunlit angles
	ROUGHNESS = mix(0.40, 0.65, leaf_tip * 0.7);
	SPECULAR = 0.42;
	// Radiant subsurface chlorophyll transmission when backlit by the sky/sun
	BACKLIGHT = ALBEDO * 0.48;
}
