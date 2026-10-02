// Sway shader for the REAL coconut palm's foliage surface
// (baked palm_island.tres, the alpha-scissor Tree_2 surface: fronds +
// hanging coconut cluster). Trunk/nut cap surfaces keep their imported
// materials untouched — only this surface overrides into the shader.
// The sway ramp is keyed on model-space height: the coconut cluster
// (y ~ 2.0-3.4) barely moves, the free frond tips (y ~ 4.5-6.3) move most.
//
// NIGHT-SAFE SHADING: fronds are near-horizontal blades, so a low moon
// lights them at full dot(N, L) and ACES clips them to flat white. The
// fragment stage therefore keeps albedo in check (soft multiplier, dark
// undersides, near-zero specular, high roughness) so moonlit fronds read
// as pale sage green instead of glowing white.
shader_type spatial;
render_mode cull_disabled; // fronds are single-sided blades

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform vec3 wind_dir = vec3(0.707, 0.0, 0.707); // world-space, matches Sky3D 2.356 rad
uniform float wind_speed : hint_range(0.0, 4.0) = 1.0; // sway cycles per second
uniform float sway_strength : hint_range(0.0, 1.0) = 1.0;
// Height band where sway ramps 0 -> 1, in MODEL space. Defaults match the
// full-size island palm; planted growth variants set these to their own
// (smaller) crown band so young trees sway gently too.
uniform float sway_start = 3.0;
uniform float sway_span : hint_range(0.1, 8.0) = 2.5;

void vertex() {
	// wind_dir is WORLD-space; the sway is applied to LOCAL VERTEX, so
	// transform the wind into the tree's local frame (inverse model).
	// This keeps ALL palms bending with the same world wind regardless
	// of their individual lean/rotation/scale.
	vec3 wdir = (inverse(MODEL_MATRIX) * vec4(wind_dir, 0.0)).xyz;
	wdir.y = 0.0;
	if (length(wdir) < 0.001) { wdir = vec3(1.0, 0.0, 0.0); }
	wdir = normalize(wdir);

	float sway_k = clamp((VERTEX.y - sway_start) / sway_span, 0.0, 1.0);
	float t = TIME * wind_speed;
	float gust = 0.75 + 0.25 * sin(VERTEX.y * 0.5 + t * 0.45); // slow shared breathing
	float w = sin(t * 1.05 + VERTEX.y * 1.45 + (MODEL_MATRIX * vec4(VERTEX, 1.0)).x * 0.35) * gust;
	VERTEX += wdir * (w * 0.06 * sway_strength * sway_k * sway_k);
}

void fragment() {
	// double-sided blades: light backfaces with the flipped normal
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 tex = texture(albedo_tex, UV);
	vec3 col = tex.rgb;

	// Undersides (backfaces) are darker — light passes through a leaf,
	// it does not reflect at full strength.
	if (!FRONT_FACING) {
		col *= 0.55;
	}
	// Overall albedo trim: keeps strong direct light (low sun/moon) from
	// clipping the whole frond to white under ACES.
	ALBEDO = col * 0.88;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// Waxy matte leaf: no broad sheen to blow out, no velvet-white rim.
	ROUGHNESS = 0.92;
	SPECULAR = 0.04;
}
