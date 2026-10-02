shader_type spatial;
render_mode cull_back;

// Mobile cut: island_generator sets this to 0.0 on Android/iOS builds.
// The gated blocks (mountain mineral detail, close-range grain bump,
// seabed bump) are the most expensive per-pixel work; mobile keeps the
// vertex-paint colors + grass mottle so the island still reads richly,
// but the terrain shader stays well inside phone-GPU budgets (the full
// version failed to compile/run on Mali & Adreno -> the WHOLE ISLAND
// went invisible on phones while PCs rendered it fine).
uniform float high_detail = 1.0;

// ============================================================
// REALISTIC BEACH TERRAIN — vertex-colored island terrain
// (sand / grass / rock / wet bands) with physically-plausible
// beach look: wet/dry sand zones, sand grain sparkle, shoreline
// foam wash, and detailed bump mapping.
// ============================================================

// ---- noise helpers ----
float hash21(highp vec2 c) {
	// PRECISION-SAFE hash (same fix as the ocean's hash21_o): the old
	// fract(sin(dot(c, vec2(127.1,311.7)))*43758.5453) degenerated at world
	// scale — grain_noise feeds floor(uv*24) up to ~3,400 into sin() as
	// ~1,000,000-radian arguments, float32 quantized the output into
	// correlated diagonal bands, and every noise cell rendered as a
	// straight-edged RECTANGLE patch (the persistent "grid sand"). Wrapping
	// the cell coords keeps the input tiny; the sine-free Hoskins mix keeps
	// full precision.
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

float fbm(highp vec2 p) {
	// 3 octaves (was 5): every octave is 4 hash21 calls, and the terrain
	// fragment shader runs fbm ~20x per pixel — 5 octaves was ~400 hash ops,
	// which exceeds mobile-GPU (Mali/Adreno) per-pixel ALU budgets and made
	// the whole island fail to render on phones while PCs were fine. Three
	// octaves keep all the large/medium detail; the dropped finest octave
	// was sub-pixel shimmer at gameplay distances.
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.13;
		a *= 0.5;
	}
	return v;
}

// Fine grain noise for sand sparkle
float grain_noise(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1, 0));
	float c = hash21(i + vec2(0, 1));
	float d = hash21(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

varying highp vec3 v_world_pos;
varying highp vec3 v_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// COLOR arrives in LINEAR space (Godot 4 auto-converts authored sRGB
	// vertex colors before upload). Every mask below (brightness/greenness
	// thresholds) was calibrated against the sRGB paint values, and the
	// ALBEDO mixes must reproduce the authored paint hues — so convert back
	// to sRGB-encoded values first (fast pure-linearization approximation,
	// max error ~0.03 in [0,1]). The old code fed raw linear COLOR into the
	// masks: sand's linear luma (~0.36) fell below the 0.45 threshold, so
	// sand_mask = 0 everywhere and the whole golden-sand pipeline (wet
	// gradient, grain, ripples, foam) was silently skipped — the beach
	// rendered as flat washed-out raw vertex paint.
	highp vec3 scol = COLOR.rgb;
	highp vec3 vert_col = sqrt(scol); // sRGB-encoded: for MASKS only
	highp vec3 vcol_lin = COLOR.rgb; // linear: for ALBEDO mixes
	highp vec2 uv = v_world_pos.xz;
	highp float h = v_world_pos.y;
	highp vec3 wp = v_world_pos; // world-space position (rock/soil noise domain)

	// ============================================
	// TERRAIN TYPE MASKS
	// ============================================
	float brightness = dot(vert_col, vec3(0.299, 0.587, 0.114));
	float greenness = vert_col.g - (vert_col.r + vert_col.b) * 0.5;
	// Thresholds lowered to fit the v4 GOLDEN sand paint: its sRGB luma is
	// ~0.51 (authored 0.61,0.54,0.40), which landed mid-way in the old
	// 0.45-0.60 ramp -> sand_mask ~0.37 -> the beach rendered as muddy olive
	// instead of feeding the golden-sand pipeline. Wet sand (luma ~0.30)
	// still gets partial grain; pure grass green stays excluded.
	float sand_mask = smoothstep(0.28, 0.42, brightness) * (1.0 - smoothstep(0.05, 0.15, greenness));

	// ============================================
	// WET SAND ZONES — continuous gradient from waterline
	// ============================================
	// zone: 0 = bone dry (high beach), 0.5 = damp packed, 1.0 = saturated (waterline)
	// Noise-warp the height BEFORE the smoothstep so the wet band's edge is
	// ragged like real sand — but keep the warp SMALL and the gradient TIGHT:
	// a ±0.25 m warp flooded damp blotches halfway up the dry beach (the
	// white/gray camo look). Real damp sand hugs the waterline.
	float wet_warp = (fbm(uv * 0.35) - 0.5) * 0.22;
	float wet_zone = 1.0 - smoothstep(-0.15, 1.05, h + wet_warp);
	// Foam wash zone: very close to waterline, waves actively lap
	float foam_zone = smoothstep(0.25, -0.05, h);
	// SUBMERGENCE — drives the underwater seabed detail: 0 at/above the
	// waterline, 1 fully submerged. Geometric (no time-of-day uniform needed:
	// the terrain shader runs un-driven by the sky state).
	float subm = smoothstep(0.15, -0.5, h);
	// Light still reaches the floor in the shallows; detail dapple dies deep.
	float light_dapple = subm * (1.0 - smoothstep(3.0, 7.0, -h));

	// Animated foam wash: thin white lines that slide up the beach
	// and recede, simulating wave swash/backwash.
	// All line phases run through a ROTATED, domain-warped coordinate (30°
	// rotation + fbm warp) — independent sin(uv.x)/sin(uv.y) terms cross-hatch
	// into a faint grid on the wet sand.
	float t = TIME;
	vec2 fuv = vec2(uv.x * 0.866 - uv.y * 0.5, uv.x * 0.5 + uv.y * 0.866); // 30°
	float fw = fbm(uv * 0.25);
	float foam_line1 = smoothstep(0.02, 0.0, abs(h - 0.08 - 0.12 * sin(t * 0.9 + fuv.x * 0.4 + fw * 3.0)));
	float foam_line2 = smoothstep(0.015, 0.0, abs(h + 0.05 - 0.08 * sin(t * 1.3 + fuv.y * 0.5 + 1.7 + fw * 2.2)));
	float foam_line3 = smoothstep(0.025, 0.0, abs(h - 0.22 + 0.10 * sin(t * 0.7 - fuv.x * 0.3 + 3.1 + fw * 2.6)));
	// Combine foam lines — they animate at different speeds
	float foam_lines = max(max(foam_line1, foam_line2 * 0.7), foam_line3 * 0.5);
	// Foam fades with distance from water
	foam_lines *= foam_zone;
	// Broken foam: rotated diagonal waves + warp — never parallel to either
	// world axis, so the gaps cannot read as rows/columns.
	float foam_breakup = 0.5 + 0.5 * sin(fuv.x * 3.9 + t * 1.8) * sin(fuv.y * 3.1 - t * 1.1 + fw * 4.0);
	foam_lines *= smoothstep(0.2, 0.6, foam_breakup);

	// ============================================
	// SAND COLOR — realistic wet/dry gradient
	// ============================================
	// Dry sand: warm golden tan. LINEAR values — the old (0.82, 0.74, 0.56)
	// displays as ~sRGB(233,224,195) and clips to snow-white under ACES. Real
	// sunlit beach sand reads ~sRGB(215,200,170) at the brightest.
	vec3 dry_sand = vec3(0.70, 0.60, 0.42);
	// Damp packed sand: darker, more golden-brown
	vec3 damp_sand = vec3(0.54, 0.45, 0.30);
	// Saturated sand: dark brown-amber (real wet beach sand)
	vec3 wet_sand = vec3(0.34, 0.27, 0.17);
	// Very wet / just-washed: dark with slight blue-grey sheen from water film
	vec3 saturated_sand = vec3(0.27, 0.23, 0.18);

	vec3 sand_color = mix(dry_sand, damp_sand, smoothstep(0.2, 0.6, wet_zone));
	sand_color = mix(sand_color, wet_sand, smoothstep(0.55, 0.85, wet_zone));
	sand_color = mix(sand_color, saturated_sand, smoothstep(0.8, 1.0, wet_zone));

	// ============================================
	// SAND GRAIN DETAIL
	// ============================================
	// Detail is DISTANCE-SCALED: full grit under ~5 m from the camera,
	// fading to a calm base by ~26 m. High-frequency grain at range is pure
	// shimmer/aliasing, so the far field gets LESS micro noise while the
	// near field reads as real granular, rippled sand.
	float cam_dist = distance(v_world_pos, CAMERA_POSITION_WORLD);
	float close_k = smoothstep(26.0, 5.0, cam_dist);

	// Multi-scale grain: fine sparkle + micro glitter. LARGE-scale variation
	// is the warm/cool patch tint in the ALBEDO section (multiplicative,
	// subtle) — the old dark subtract-cloud at uv*0.6 read as camo blotches.
	float grain_fine = grain_noise(uv * 8.0) * mix(0.04, 0.12, close_k);
	float grain_micro = grain_noise(uv * 24.0) * mix(0.015, 0.09, close_k);

	// Ripple patterns: wind-formed ridges on dry beach, water-formed on wet.
	// Run along the rotated fuv axes (diagonal to the world grid) so the
	// ridges never align into axis-parallel rows; the fbm warp bends them.
	// A second harmonic (2x frequency, scaled warp) sharpens the ridge
	// crests — real ripples have crisp asymmetric crests, a lone sine just
	// reads as soft water. Amplitude is distance-scaled like the grain.
	// Ripple FIELDS are patchy: wind and water only ripple PARTS of a beach.
	// A very-low-frequency mask picks roughly half the sand for ripples; the
	// rest stays smooth — uniform ripples everywhere look stamped/artificial.
	float rip_field = smoothstep(0.40, 0.62, fbm(uv * 0.07 + vec2(13.0, 5.0)));
	// The two warp fbms are each used twice (same args) — compute once.
	float rip_warp1 = fbm(uv * 0.15);
	float rip_warp2 = fbm(uv * 0.3);
	float ripple_dry = sin(fuv.x * 1.9 + fuv.y * 0.8 + rip_warp1 * 5.0);
	ripple_dry += 0.35 * sin(fuv.x * 3.8 + fuv.y * 1.6 + rip_warp1 * 10.0 + 1.3);
	ripple_dry *= mix(0.035, 0.09, close_k) * rip_field;
	float ripple_wet = sin(fuv.x * 2.2 - fuv.y * 2.8 + rip_warp2 * 3.0);
	ripple_wet += 0.4 * sin(fuv.x * 4.4 - fuv.y * 5.6 + rip_warp2 * 6.0 + 2.1);
	ripple_wet *= mix(0.04, 0.11, close_k) * rip_field;

	// ============================================
	// ALBEDO
	// ============================================
	vec3 albedo = sand_color;

	// Large-scale sand mottle: warm/dry vs cool/damp patches — MULTIPLICATIVE
	// and subtle (±6%) so brightness never swings. Dark subtract-clouds read
	// as snow-camo blotches; real beaches vary in HUE, not brightness.
	float patch = fbm(uv * 0.55 + vec2(7.0, 2.0)) - 0.5;
	albedo *= vec3(1.0) + patch * vec3(0.12, 0.05, 0.14) * sand_mask;
	// Wind-blown aeolian streaks: long soft bands across the beach (rotated
	// fuv, elongated 4:1, multiplicative ±3%) — the large-scale flow texture
	// real sand shows between ripple fields. Multiplicative = no camo risk.
	float streak = fbm(vec2(fuv.x * 0.35, fuv.y * 1.4) + vec2(3.0, 8.0));
	albedo *= 1.0 + (streak - 0.5) * 0.06 * sand_mask;
	// Fine grain adds sparkle; ripples shade the ripple-field patches
	albedo += grain_fine * sand_mask;
	albedo += ripple_dry * (1.0 - wet_zone) * sand_mask;
	albedo += ripple_wet * wet_zone * sand_mask;

	// Wet sand reflects sky color slightly (water film)
	vec3 sky_reflect = vec3(0.12, 0.18, 0.28);
	albedo = mix(albedo, albedo + sky_reflect * 0.15, wet_zone * wet_zone * sand_mask);

	// ============================================
	// UNDERWATER SEABED DETAIL
	// ============================================
	// Wave-formed ripples on the submerged sand (medium wavelength, crisp
	// 2-harmonic crests like the wet beach ripples), through the same
	// rotated/warped fuv as every other sand pattern. Fades out naturally
	// with depth as the vertex paint darkens (sand_mask drops) and the
	// light dies.
	float sea_warp = fbm(uv * 0.22 + vec2(9.1, 3.7));
	float seabed_ripple = sin(fuv.x * 1.6 + fuv.y * 1.1 + sea_warp * 4.0);
	seabed_ripple += 0.35 * sin(fuv.x * 3.2 - fuv.y * 1.4 + sea_warp * 8.0 + 1.9);
	albedo += seabed_ripple * 0.045 * subm * sand_mask;
	// Shallow-water light dapple: slowly shifting brightness mottle — the
	// caustic shimmer sunlight throws on a sandy floor. Strongest at 0.5-3 m.
	float dapple = fbm(uv * 2.6 + vec2(TIME * 0.10, TIME * 0.07));
	albedo += (dapple - 0.5) * 0.07 * light_dapple * sand_mask;

	// Grass/rock blend (original logic)
	albedo = mix(vcol_lin, albedo, sand_mask);
	// Blend remaining terrain types
	// MIRRORED from island_generator._terrain_paint `grass_k` (keep in sync!):
	// golden-sand band up to ~2.2 m, grass ramps over 2.2 m, high-freq noise
	// dithers the edge into tufty sand/green patches (no uniform olive band).
	float bnd_h = h;
	float j2 = vnoise(uv * 0.9 + vec2(11.7, 63.1)) - 0.5;
	float gk_raw = smoothstep(2.2 + j2 * 2.0 - (vnoise(uv * 0.22) - 0.5) * 2.0, 4.4 + j2 * 2.0 - (vnoise(uv * 0.22) - 0.5) * 2.0, bnd_h) * smoothstep(0.62, 0.86, dot(v_normal, vec3(0, 1, 0)));
	float grass_k = smoothstep(0.3, 0.7, gk_raw + j2 * 0.5);
	float rock_k = max(smoothstep(0.80, 0.58, dot(v_normal, vec3(0, 1, 0))), smoothstep(0.55, 0.25, dot(v_normal, vec3(0, 1, 0))) * 0.6);
	albedo = mix(albedo, vcol_lin * 0.85, 1.0 - sand_mask);

	// ============================================
	// GRASS-GROUND TEXTURE — the flat vertex-green read as a painted
	// plastic lawn. Real turf = blade-scale value variation, dry/healthy
	// hue mottling and soil showing through sparse spots.
	// ============================================
	float grass_mask = (1.0 - sand_mask) * grass_k * (1.0 - rock_k);
	if (grass_mask > 0.003) {
		// Blade-scale brightness mottle (two octaves, ±12%) — turf seen
		// from anywhere is never one flat green.
		float g1 = vnoise(uv * 5.5);
		float g2 = vnoise(uv * 13.0 + vec2(31.0, 7.0));
		albedo *= 1.0 + (g1 * 0.6 + g2 * 0.4 - 0.5) * 0.24 * grass_mask;
		// Dry/healthy patches: hue drift toward olive-yellow, not brightness.
		float drypatch = smoothstep(0.42, 0.62, fbm(uv * 0.35 + vec2(41.0, 11.0)));
		albedo = mix(albedo, albedo * vec3(1.18, 1.02, 0.62), drypatch * 0.35 * grass_mask);
		// Sparse-turf soil show-through: ragged dirt spots where grass is thin.
		float sparse = smoothstep(0.62, 0.78, fbm(uv * 0.9 + vec2(3.0, 27.0)));
		albedo = mix(albedo, vec3(0.26, 0.19, 0.11), sparse * 0.45 * grass_mask);
	}
	// RAGGED SAND/GRASS BOUNDARY: now carried entirely by the v4 vertex
	// paint (golden band + high-freq dither, mirrored in _terrain_paint) —
	// the old extra `sand_edge` mix re-buried the golden beach under raw
	// olive vertex color wherever the new (2.2 m) grass ramp sat mid-way,
	// rendering the beach neutral gray again. Do NOT re-blend here.

	// ============================================
	// MOUNTAIN — rock & soil detail above the grass line
	// ============================================
	// The baked soil/rock tint on the slopes gets real mineral breakup:
	// strata banding, iron staining, scree speckle and crevice shading
	// (same noise family as rock_triplanar.gdshader so they read as one
	// material system).
	float slope = 1.0 - dot(v_normal, vec3(0, 1, 0));
	// MIRRORED from island_generator._terrain_paint `alpine_k` (keep in
	// sync!): rocky/soil breakup ONLY on STEEP faces — cliff scree gets
	// mineral detail, while the whole summit and gentle high meadows stay
	// grass green (the v3 bare-summit term bleached the peak white).
	float mountain = smoothstep(0.18, 0.42, slope)
		+ smoothstep(7.0, 11.5, h) * smoothstep(0.35, 0.55, slope);
	mountain = clamp(mountain, 0.0, 1.0) * (1.0 - sand_mask);
	if (mountain > 0.001 && high_detail > 0.5) {
		vec3 mp = wp * vec3(1.0, 0.45, 1.0);
		// Steep faces smear planar noise into vertical streaks (noise value
		// barely changes as you slide ALONG the slope). Ease every layer
		// toward a constant on steep ground and use HORIZONTAL strata (bands
		// that vary with height only) — geological layering, never smeared.
		// (steep_m is the `slope` variable already computed above.)
		float steep_m = slope;
		float strata_m = fbm(vec2(mp.x * 0.5 + mp.z * 0.2, wp.y * 2.2));
		float med_m = mix(fbm(wp.xz * 1.4 + vec2(7.7, 3.1) + wp.y * 0.35), 0.5, steep_m * 0.7);
		float speck = mix(grain_noise(wp.xz * 18.0 + wp.y * 5.0), 0.5, steep_m * 0.6);
		vec3 rock_col_m = mix(vec3(0.30, 0.28, 0.25), vec3(0.48, 0.44, 0.38), strata_m);
		float stain_m = smoothstep(0.55, 0.8, fbm(wp.xz * 0.35 + vec2(21.0, 13.0)));
		rock_col_m = mix(rock_col_m, vec3(0.45, 0.33, 0.21), stain_m * 0.5);
		rock_col_m *= 0.8 + 0.4 * med_m;
		rock_col_m -= (speck - 0.5) * 0.10;
		vec3 soil_col_m = vcol_lin * (0.8 + 0.4 * med_m); // keeps the baked soil hue
		float rockiness = smoothstep(0.22, 0.48, slope); // bare rock starts lower: less orange soil, more stone
		vec3 mtn_col = mix(soil_col_m, rock_col_m, rockiness);
		// GEOLOGICAL ZONING: large-scale tint drift between cool gray granite
		// and warm iron-weathered stone — real cliff faces never wear one
		// uniform color (multiplicative, subtle).
		float zone = fbm(wp.xz * 0.05 + vec2(31.0, 17.0));
		mtn_col *= mix(vec3(0.90, 0.88, 0.94), vec3(1.12, 1.00, 0.86), zone);
		// Lichen/moss patches on damp gentle up-faces (ties the mountain to
		// the same material family as the prop rocks' lichen).
		float lichen_m = smoothstep(0.55, 0.8, med_m)
			* smoothstep(0.55, 0.75, dot(v_normal, vec3(0, 1, 0)))
			* (1.0 - sand_mask);
		mtn_col = mix(mtn_col, vec3(0.20, 0.26, 0.14), lichen_m * 0.35);
		albedo = mix(albedo, mtn_col, mountain);
	}

	// ---- Foam wash lines: bright white at the waterline ----
	vec3 foam_color = vec3(0.92, 0.95, 0.98);
	albedo = mix(albedo, foam_color, foam_lines * sand_mask);

	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));

	// ============================================
	// ROUGHNESS — wet = glossy, dry = matte
	// ============================================
	float roughness = mix(0.92, 0.38, wet_zone * sand_mask);
	// Wet sand micro-roughness: water film smooths grain
	roughness -= grain_micro * wet_zone * 0.5;
	// Dry sand has more roughness variation
	roughness += (fbm(uv * 2.5) - 0.5) * 0.08 * (1.0 - wet_zone);
	// Near-field grain sparkle: high-frequency roughness breakup so close
	// highlights glint off individual grains instead of a uniform sheen.
	roughness += (grain_noise(uv * 14.0) - 0.5) * 0.16 * close_k * sand_mask;
	ROUGHNESS = clamp(roughness, 0.28, 0.95);

	// Foam wash is glossy (wet surface)
	ROUGHNESS = mix(ROUGHNESS, 0.22, foam_lines * sand_mask);

	// ============================================
	// NORMAL / BUMP MAP
	// ============================================
	float n1 = fbm(uv * 1.2);
	float n2 = fbm(uv * 1.2 + vec2(3.7, 1.9));
	// Dry sand: coarse ripple bumps
	vec3 bump_dry = normalize(vec3((n1 - 0.5) * 2.0, 1.0, (n2 - 0.5) * 2.0));
	// Wet sand: finer, more pronounced ripples (water-packed)
	float w1 = fbm(uv * 2.8);
	float w2 = fbm(uv * 2.8 + vec2(5.1, 2.3));
	vec3 bump_wet = normalize(vec3((w1 - 0.5) * 3.5, 1.0, (w2 - 0.5) * 3.5));
	vec3 bump = mix(bump_dry, bump_wet, wet_zone);
	// SEABED RIPPLE BUMP: real relief on the submerged sand — wave-formed
	// ripple ridges that catch the filtered light. Fades with depth (the
	// smoothstep) and sits only on sandy floor.
	// SEABED RIPPLE BUMP: real relief on the submerged sand — wave-formed
	// ripple ridges that catch the filtered light. Fades with depth (the
	// smoothstep) and sits only on sandy floor. (Mobile: skipped.)
	if (high_detail > 0.5) {
		float s1 = fbm(uv * 2.1 + vec2(3.3, 8.8));
		float s2 = fbm(uv * 2.1 + vec2(7.2, 2.9));
		vec3 bump_sea = normalize(vec3((s1 - 0.5) * 3.0, 1.0, (s2 - 0.5) * 3.0));
		bump = normalize(mix(bump, bump_sea, subm * sand_mask * 0.55));
	}
	// CLOSE-RANGE GRAIN BUMP: a high-frequency granular layer fades in near
	// the camera (and out on saturated sand, which packs smooth) so the
	// beach visibly grits under a low sun up close. (Mobile: skipped.)
	if (high_detail > 0.5) {
		float g1 = grain_noise(uv * 9.0);
		float g2 = grain_noise(uv * 9.0 + vec2(4.7, 9.3));
		vec3 bump_grain = normalize(vec3((g1 - 0.5) * 2.6, 1.0, (g2 - 0.5) * 2.6));
		bump = normalize(mix(bump, bump_grain, close_k * (1.0 - wet_zone) * sand_mask * 0.65));
	}
	float bump_strength = mix(0.15, 0.28, sand_mask);
	bump_strength += close_k * sand_mask * 0.30; // deeper ripple/grain relief up close
	bump_strength += 0.12 * subm * sand_mask; // crisp relief on the seabed too
	// Mountain bump: coarser, craggier relief on the rock/soil slopes
	if (mountain > 0.001 && high_detail > 0.5) {
		float bump_amp = 3.2 * (1.0 - slope * 0.75); // smooth steep faces too
		float m1 = mix(fbm(wp.xz * 2.2 + wp.y * 0.8), 0.5, (1.0 - slope) * 0.7);
		float m2 = mix(fbm(wp.xz * 5.5 + vec2(4.4, 9.1)), 0.5, (1.0 - slope) * 0.7);
		vec3 bump_m = normalize(vec3((m1 - 0.5) * bump_amp, 1.0, (m2 - 0.5) * bump_amp));
		bump = normalize(mix(bump, bump_m, mountain * 0.8));
		bump_strength = max(bump_strength, 0.34 * mountain);
	}
	NORMAL_MAP = mix(vec3(0, 0, 1), bump, bump_strength);
	NORMAL_MAP_DEPTH = 1.0;

	// ============================================
	// METALLIC — 0 for all terrain
	// ============================================
	METALLIC = 0.0;

	// ============================================
	// AMBIENT OCCLUSION — grain cavity darkening
	// ============================================
	float ao_base = 0.92 + fbm(uv * 3.0) * 0.08;
	// Wet sand packs tighter = slightly more AO
	ao_base -= wet_zone * 0.06;
	AO = ao_base;
	AO_LIGHT_AFFECT = 0.4;
}
