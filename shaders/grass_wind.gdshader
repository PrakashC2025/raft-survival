// Wind-sway grass shader for the REALISTIC clump field.
// Source mesh: grass/baked/grass_clump.tres (baked from
// models/realistics_grass_10.glb — base plane re-pivoted to y = 0).
// The clump has no vertex-color wind mask, so the mask is derived from
// the local height: 0 at the planted base, ~1 at the blade tips.
// Per-clump variation comes from INSTANCE_CUSTOM (set by island_grass.gd:
//   x = wind phase offset, y = random 0.8..1.2 strength factor), so every
// clump sways slightly out of sync. Works fine with all-zero custom data.
shader_type spatial;
render_mode cull_disabled; // grass blades are double-sided quads

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.92, 1.0, 0.82); // subtle match to terrain grass
// 0.26 (was 0.42): the atlas is VRAM-compressed + mipmapped, so MINIFIED mips
// average the sparse blade alpha down to ~0.35 — at the old 0.42 threshold
// Godot's alpha-scissor distance fade erased EVERY blade beyond a few meters
// (the field was invisible from gameplay distance while probes 3 m away
// looked fine). A low threshold + alpha boost in fragment() keeps blades
// solid near the camera AND alive at distance.
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.26;
uniform float height_scale : hint_range(0.0, 6.0) = 1.15; // mask normalize for the ~1 m real clump (mask hits 1 near the blade tips)
uniform vec3 wind_direction = vec3(-0.707, 0.0, 0.707); // matches Sky3D wind_direction = 2.356 rad
uniform float wind_strength = 0.10; // max sideways bend in meters at the tips (1 m blades)
uniform float wind_speed = 1.5;      // sway cycles per second
uniform float wind_gustiness = 0.5;  // how much strength varies over time

varying float v_mask;
varying float v_tint; // per-clump tint variation (from INSTANCE_CUSTOM.z)

void vertex() {
	// 0 at the planted base -> 1 at the tips (clump base baked at y = 0)
	v_mask = clamp(VERTEX.y * height_scale, 0.0, 1.0);
	v_tint = INSTANCE_CUSTOM.z;

	// Per-clump desync from MultiMesh custom data
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	float rand = mix(0.8, 1.2, INSTANCE_CUSTOM.y);

	// Slow global gust so clumps breathe together, plus per-clump phase
	float gust = sin(TIME * wind_speed * 0.35) * 0.5 + 0.5;
	float amp = wind_strength * rand * (1.0 + wind_gustiness * gust);

	float wave = sin(TIME * wind_speed + phase + v_mask * 1.5);
	// Quadratic falloff: base planted, tips move fully
	VERTEX += wind_direction * (wave * amp * v_mask * v_mask);
	// A touch of vertical bob so the clump "breathes" (real grass flattens)
	VERTEX.y -= abs(wave) * amp * 0.18 * v_mask * v_mask;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// Alpha boost counteracts VRAM-compression + mip attenuation (see
	// alpha_cut comment): full-res alpha is ~binary, so near the camera this
	// only firms up semi-transparent edge texels; at distance it keeps the
	// minified blade alpha ABOVE the scissor threshold so blades survive.
	// Per-clump tint variation (INSTANCE_CUSTOM.z -> v_tint, read in vertex()):
	// lush deep green <-> dry yellow-green patches, so the field breaks up
	// instead of reading as one uniform carpet.
	float tv = v_tint;
	vec3 tinted = tint * mix(0.82, 1.12, tv);
	tinted = mix(tinted, tinted * vec3(1.14, 1.03, 0.76), tv * 0.4); // dry patches
	ALBEDO = tex.rgb * tinted * 0.92; // trim: moonlit grass stays green at night
	// Double-sided blades: flip the normal for back faces so lit blades read
	// green from both sides instead of near-black on the shaded side
	// (cull_disabled renders back faces; without the flip their lighting
	// used the mirrored normal).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALPHA = clamp(tex.a * 1.35, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.92;
	SPECULAR = 0.05; // matte blades: no sheen to blow out under the moon
}
