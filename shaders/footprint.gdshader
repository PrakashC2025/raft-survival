shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_draw_never, shadows_disabled, vertex_lighting;
// ============================================================
// FOOTPRINT DECAL — multiplies the sand beneath it with a pressed
// sole shape: a darker heel lobe + ball/toe lobe with a slight arch
// between (reads as a real bare footpress, wetter prints darkest).
// Per-instance COLOR (MultiMesh instance color):
//   G = wetness (0 dry beach .. 1 waterline), A = fade (1 fresh .. 0 gone).
// R/B unused (kept at 1). Soft edges: no visible quad border.
// ============================================================

uniform float print_strength : hint_range(0.0, 1.0) = 0.55; // dry print darkness

void fragment() {
	// Quad-local coordinates via UV (0..1).
	vec2 uv = UV;
	vec2 p = uv - vec2(0.5); // -0.5..0.5, y+ = toe direction

	// ---- Sole mask: realistic bare foot shape ----
	// Heel lobe — round, slightly wider
	float heel = 1.0 - smoothstep(0.16, 0.28, length((p - vec2(0.0, -0.22)) * vec2(1.0, 1.35)));
	// Ball of foot — wider, slightly flatter
	float ball = 1.0 - smoothstep(0.15, 0.26, length((p - vec2(0.0, 0.24)) * vec2(1.25, 1.0)));
	// 5 toe bumps — organic, slightly asymmetric
	float toes = 0.0;
	for (int i = 0; i < 5; i++) {
		float fx = -0.30 + 0.15 * float(i);
		vec2 tp = p - vec2(fx, 0.34);
		// Slightly different sizes per toe
		float tsize = mix(0.035, 0.065, 1.0 - abs(float(i) - 2.0) / 2.0);
		toes = max(toes, 1.0 - smoothstep(tsize * 0.6, tsize, length(tp)));
	}
	// Arch — thin connecting bar between heel and ball
	float arch = (1.0 - smoothstep(0.05, 0.16, abs(p.x)))
		* (1.0 - smoothstep(0.02, 0.20, abs(p.y - 0.02)));
	// Side edge of foot — slight lateral bump
	float edge = (1.0 - smoothstep(0.22, 0.30, abs(p.x)))
		* (1.0 - smoothstep(0.08, 0.28, abs(p.y - 0.0)));

	float sole = clamp(max(max(heel, ball + toes * 0.8), max(arch * 0.55, edge * 0.35)), 0.0, 1.0);
	if (sole <= 0.003) {
		discard;
	}

	float wet = clamp(COLOR.g, 0.0, 1.0);
	float fade = clamp(COLOR.a, 0.0, 1.0);

	// ---- Edge disturbance — natural sand displacement ----
	// Organic noise so prints aren't machine-perfect ovals
	float rough = fract(sin(dot(floor(uv * 28.0), vec2(12.9898, 78.233))) * 43758.5453);
	float rough2 = fract(sin(dot(floor(uv * 16.0), vec2(63.7264, 10.873))) * 17562.917);
	sole *= 0.82 + 0.28 * rough + 0.15 * rough2;

	// ---- Depth: wet prints press much darker ----
	float depth = mix(print_strength * 0.45, 0.78, wet);
	// Toe impressions are slightly deeper (toes push harder)
	float toe_depth = mix(depth * 0.9, depth * 1.15, toes * 0.6);

	// ---- Heel-only deep impression (first contact) ----
	float heel_depth = depth * mix(1.0, 1.2, heel);

	float total_depth = max(heel_depth, toe_depth);

	// ---- Final color: dark pressed sand ----
	// Wet prints: darker, slightly bluer (water in the impression)
	vec3 dry_print_col = vec3(1.0 - sole * total_depth * fade);
	vec3 wet_print_col = vec3(1.0 - sole * total_depth * fade * 1.15);
	ALBEDO = mix(dry_print_col, wet_print_col, wet);
}
