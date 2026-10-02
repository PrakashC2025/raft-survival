// MOBILE TERRAIN SHADER — compile-light clone of terrain_sand.gdshader.
//
// WHY THIS EXISTS: the desktop beach shader runs ~20 fbm calls per pixel
// (3 octaves each ≈ 600+ hash ops). PCs handle it, but several phone GPUs
// (Mali/Adreno) exceed their per-pixel ALU/compile budget and the terrain
// pipeline fails to build — the WHOLE ISLAND goes invisible while the sky
// and ocean (cheaper shaders) still draw. The 27th-pass `high_detail` cut
// was not enough on every device, so mobile gets a DEDICATED shader with
// the same masks and color stops but ~1/10 of the noise work:
//   - value noise only, 1-2 octaves (no 3-octave fbm loops)
//   - one shared noise domain per frequency band (results reused)
//   - ripple/foam/grain micro-detail collapsed to single harmonics
//   - mountain mineral layers dropped (vertex paint already carries the
//     rock/soil hue) — PASS 32: a cheap ANALYTIC bump was RESTORED (see
//     the bottom of fragment()): the flat normal read as painted plastic
//     on phones. Desktop-calibrated strengths, 4 extra vnoise calls.
// LOOK parity with the desktop shader: golden sand + wet gradient, foam
// wash lines, grass/rock vertex-paint blends, grass mottle, steep-face
// soil tint. Masks/thresholds are IDENTICAL — only the micro texture is
// simplified. island_generator picks this file automatically on mobile
// builds and sets the same uniforms (high_detail is declared for API
// compatibility and intentionally unused).
shader_type spatial;
render_mode cull_back;

uniform float high_detail = 0.0; // set by island_generator; unused here (mobile is always low-detail)

// ---- precision-safe noise (same hash as terrain_sand.gdshader) ----
float hash21(highp vec2 c) {
	c = mod(c, 1024.0);
	highp vec3 p3 = fract(vec3(c.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x),
		f.y
	);
}

// Two octaves only — the mobile replacement for the desktop fbm (3 octaves).
float fbm2(highp vec2 p) {
	return vnoise(p) * 0.6667 + vnoise(p * 2.13 + vec2(7.7, 3.9)) * 0.3333;
}

varying highp vec3 v_world_pos;
varying highp vec3 v_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// COLOR arrives in LINEAR space; masks were calibrated against sRGB —
	// sqrt-encode for masks, keep the linear copy for albedo mixes.
	// (Identical to terrain_sand.gdshader.)
	highp vec3 vert_col = sqrt(COLOR.rgb);
	highp vec3 vcol_lin = COLOR.rgb;
	highp vec2 uv = v_world_pos.xz;
	highp float h = v_world_pos.y;
	highp vec3 wp = v_world_pos;

	// ---- terrain type masks (identical thresholds to desktop) ----
	float brightness = dot(vert_col, vec3(0.299, 0.587, 0.114));
	float greenness = vert_col.g - (vert_col.r + vert_col.b) * 0.5;
	float sand_mask = smoothstep(0.28, 0.42, brightness) * (1.0 - smoothstep(0.05, 0.15, greenness));

	// ---- wet zones (single-octave warp instead of 3-octave fbm) ----
	float wet_warp = (vnoise(uv * 0.35) - 0.5) * 0.22;
	float wet_zone = 1.0 - smoothstep(-0.15, 1.05, h + wet_warp);
	float foam_zone = smoothstep(0.25, -0.05, h);

	// ---- sand color gradient (identical stops) ----
	vec3 dry_sand = vec3(0.70, 0.60, 0.42);
	vec3 damp_sand = vec3(0.54, 0.45, 0.30);
	vec3 wet_sand = vec3(0.34, 0.27, 0.17);
	vec3 saturated_sand = vec3(0.27, 0.23, 0.18);
	vec3 sand_color = mix(dry_sand, damp_sand, smoothstep(0.2, 0.6, wet_zone));
	sand_color = mix(sand_color, wet_sand, smoothstep(0.55, 0.85, wet_zone));
	sand_color = mix(sand_color, saturated_sand, smoothstep(0.8, 1.0, wet_zone));

	// ---- foam wash lines: 2 lines through the rotated coordinate ----
	float t = TIME;
	vec2 fuv = vec2(uv.x * 0.866 - uv.y * 0.5, uv.x * 0.5 + uv.y * 0.866); // 30°
	float fw = vnoise(uv * 0.25);
	float foam_line1 = smoothstep(0.02, 0.0, abs(h - 0.08 - 0.12 * sin(t * 0.9 + fuv.x * 0.4 + fw * 3.0)));
	float foam_line2 = smoothstep(0.015, 0.0, abs(h + 0.05 - 0.08 * sin(t * 1.3 + fuv.y * 0.5 + 1.7 + fw * 2.2)));
	float foam_lines = max(foam_line1, foam_line2 * 0.7) * foam_zone;
	float foam_breakup = 0.5 + 0.5 * sin(fuv.x * 3.9 + t * 1.8) * sin(fuv.y * 3.1 - t * 1.1 + fw * 4.0);
	foam_lines *= smoothstep(0.2, 0.6, foam_breakup);

	// ---- albedo ----
	vec3 albedo = sand_color;
	// Large-scale mottle: one multiplicative hue patch (the desktop adds a
	// streak layer on top — invisible at arm's length, dropped here).
	float patch = fbm2(uv * 0.55 + vec2(7.0, 2.0)) - 0.5;
	albedo *= vec3(1.0) + patch * vec3(0.12, 0.05, 0.14) * sand_mask;
	// Ripples: single harmonic, distance-scaled (second harmonic dropped).
	float cam_dist = distance(v_world_pos, CAMERA_POSITION_WORLD);
	float close_k = smoothstep(26.0, 5.0, cam_dist);
	float ripple = sin(fuv.x * 1.9 + fuv.y * 0.8 + fw * 5.0);
	albedo += ripple * mix(0.02, 0.07, close_k) * sand_mask;
	// Wet sky sheen
	vec3 sky_reflect = vec3(0.12, 0.18, 0.28);
	albedo = mix(albedo, albedo + sky_reflect * 0.15, wet_zone * wet_zone * sand_mask);

	// Grass/rock blends (identical rule to desktop — KEEP IN SYNC with
	// _terrain_paint's grass_k).
	float j2 = vnoise(uv * 0.9 + vec2(11.7, 63.1)) - 0.5;
	float gk_raw = smoothstep(2.2 + j2 * 2.0 - (vnoise(uv * 0.22) - 0.5) * 2.0,
		4.4 + j2 * 2.0 - (vnoise(uv * 0.22) - 0.5) * 2.0, h)
		* smoothstep(0.62, 0.86, dot(v_normal, vec3(0, 1, 0)));
	float grass_k = smoothstep(0.3, 0.7, gk_raw + j2 * 0.5);
	float rock_k = max(smoothstep(0.80, 0.58, dot(v_normal, vec3(0, 1, 0))),
		smoothstep(0.55, 0.25, dot(v_normal, vec3(0, 1, 0))) * 0.6);
	albedo = mix(albedo, vcol_lin * 0.85, 1.0 - sand_mask);

	// ---- grass-ground texture: blade mottle + dry patches (soil
	// show-through dropped — needs a 3rd noise domain) ----
	float grass_mask = (1.0 - sand_mask) * grass_k * (1.0 - rock_k);
	if (grass_mask > 0.003) {
		float g1 = vnoise(uv * 5.5);
		albedo *= 1.0 + (g1 - 0.5) * 0.18 * grass_mask;
		float drypatch = smoothstep(0.42, 0.62, fbm2(uv * 0.35 + vec2(41.0, 11.0)));
		albedo = mix(albedo, albedo * vec3(1.18, 1.02, 0.62), drypatch * 0.35 * grass_mask);
	}

	// ---- mountain: soil/rock tint on steep faces (vertex paint carries
	// the hue; strata/stain/speckle/lichen layers dropped) ----
	float slope = 1.0 - dot(v_normal, vec3(0, 1, 0));
	float mountain = clamp(smoothstep(0.18, 0.42, slope)
		+ smoothstep(7.0, 11.5, h) * smoothstep(0.35, 0.55, slope), 0.0, 1.0)
		* (1.0 - sand_mask);
	if (mountain > 0.001) {
		float med_m = fbm2(wp.xz * 1.4 + vec2(7.7, 3.1));
		albedo = mix(albedo, vcol_lin * (0.8 + 0.4 * med_m), mountain);
	}

	// ---- foam wash ----
	albedo = mix(albedo, vec3(0.92, 0.95, 0.98), foam_lines * sand_mask);
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));

	// ---- roughness (no grain terms) ----
	float roughness = mix(0.92, 0.38, wet_zone * sand_mask);
	roughness += (patch - 0.5) * 0.08 * (1.0 - wet_zone);
	ROUGHNESS = clamp(roughness, 0.28, 0.95);
	ROUGHNESS = mix(ROUGHNESS, 0.22, foam_lines * sand_mask);

	// ============================================
	// NORMAL / BUMP MAP (pass 32): the flat normal made the ground read as
	// PAINTED PLASTIC on phones — surface realism is light RELIEF (normal
	// shading), which no amount of albedo noise replaces. Restored the
	// desktop's bump STRUCTURE at phone cost: same strengths (calibrated
	// on desktop), each desktop fbm() sample swapped for ONE vnoise()
	// call, and the two mountain samples share one coordinate pair.
	// ============================================
	float n1 = vnoise(uv * 1.2);
	float n2 = vnoise(uv * 1.2 + vec2(3.7, 1.9));
	// Dry sand: coarse ripple bumps
	vec3 bump_dry = normalize(vec3((n1 - 0.5) * 2.0, 1.0, (n2 - 0.5) * 2.0));
	// Wet sand: finer, more pronounced ripples (water-packed)
	float w1 = vnoise(uv * 2.8);
	float w2 = vnoise(uv * 2.8 + vec2(5.1, 2.3));
	vec3 bump_wet = normalize(vec3((w1 - 0.5) * 3.5, 1.0, (w2 - 0.5) * 3.5));
	vec3 bump = mix(bump_dry, bump_wet, wet_zone);
	// CLOSE-RANGE GRAIN: the beach visibly grits under a low sun up close
	// (the desktop grain_noise is itself ~1 octave — same call count here).
	float g1 = vnoise(uv * 9.0);
	float g2 = vnoise(uv * 9.0 + vec2(4.7, 9.3));
	vec3 bump_grain = normalize(vec3((g1 - 0.5) * 2.6, 1.0, (g2 - 0.5) * 2.6));
	bump = normalize(mix(bump, bump_grain, close_k * (1.0 - wet_zone) * sand_mask * 0.65));
	float bump_strength = mix(0.15, 0.28, sand_mask);
	bump_strength += close_k * sand_mask * 0.30; // deeper ripple/grain relief up close
	// Mountain bump: coarser, craggier relief on the rock/soil slopes
	// (1.0x + 2.6x of one coordinate pair = 2 extra vnoise calls total)
	if (mountain > 0.001) {
		float m1 = vnoise(wp.xz * 2.2 + wp.y * 0.8);
		float m2 = vnoise(wp.xz * 5.7 + vec2(4.4, 9.1));
		float bump_amp = 3.2 * (1.0 - slope * 0.75); // smooth steep faces too
		vec3 bump_m = normalize(vec3((m1 - 0.5) * bump_amp, 1.0, (m2 - 0.5) * bump_amp));
		bump = normalize(mix(bump, bump_m, mountain * 0.8));
		bump_strength = max(bump_strength, 0.34 * mountain);
	}
	NORMAL_MAP = mix(vec3(0, 0, 1), bump, bump_strength);
	NORMAL_MAP_DEPTH = 1.0;
	METALLIC = 0.0;
	AO = 0.95 - wet_zone * 0.06;
	AO_LIGHT_AFFECT = 0.4;
}
