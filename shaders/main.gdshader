shader_type spatial;
render_mode unshaded, cull_disabled;

// ============================================================
// OCEAN — time-of-day responsive water (deep open ocean look)
// Driven per-frame by ocean.gd (uniforms below are pushed from
// the Sky3D sun/moon state). The wave VERTEX formula below is
// mirrored EXACTLY by Ocean.get_height() so the raft/debris/
// player buoyancy rides the same visible waves.
//
// Palette note: uniforms are NOT source_color — ocean.gd pushes
// TRUE LINEAR HDR values (source_color would silently convert
// them sRGB->linear). The scene uses ACES tonemapping (mode 3,
// tonemap_white 6.0). Values were calibrated by rendering the
// real pipeline and reading back displayed colors, targeting
// the reference: medium cobalt at the horizon, deep navy in the
// foreground/troughs, blue-cyan lit crests and white foam.
// ============================================================

// --- time-of-day state (ocean.gd) ---
uniform vec3 water_day_color = vec3(0.024, 0.20, 0.42);
uniform vec3 water_twilight_color = vec3(0.02, 0.15, 0.34);
uniform vec3 water_night_color = vec3(0.014, 0.08, 0.20);
uniform vec3 water_deep_color = vec3(0.012, 0.09, 0.20);
uniform vec3 water_horizon_color = vec3(0.05, 0.44, 0.66);
uniform vec3 water_crest_color = vec3(0.21, 0.52, 0.65);
uniform vec3 water_foam_color = vec3(1.0, 1.12, 1.32);
uniform vec3 water_haze_color = vec3(0.5, 0.66, 0.82);
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform float twilight_factor : hint_range(0.0, 1.0) = 0.0;
uniform float moon_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -0.5, -0.8);
uniform vec3 sun_glint_color = vec3(1.0, 0.95, 0.85);
uniform vec3 moon_glint_color = vec3(0.72, 0.82, 1.0);
uniform float sparkle_strength : hint_range(0.0, 4.0) = 0.35;
// 0..1 pushed from RainSystem (via ocean.gd): storm state roughens the
// surface, adds rain-churn speckle and darkens the water body.
uniform float rain_strength : hint_range(0.0, 1.0) = 0.0;

// --- waves (geometry shared with Ocean.get_height()) ---
uniform float wave_height = 0.32;
uniform float wave_speed = 0.45;

// --- island interaction (pushed by island_generator.gd at runtime) ---
// Mirrors the BASE radial profile of IslandGenerator.terrain_height_local
// (closed-form math only — CPU/GPU identical). Gives the water the real
// seabed depth: turquoise shallows, sand glow, surf lines on the coast.
uniform vec2 island_center = vec2(0.0);
uniform float shore_radius = 32.0;
uniform float outer_radius = 68.0;
uniform float deep_depth = 12.0;
uniform float beach_height = 2.6;
uniform float island_active = 0.0;
uniform vec2 foam_rocks[16]; // world XZ of the half-submerged shore rocks
uniform int foam_rock_count = 0;

// Wave crest level (-1 trough .. +1 crest) interpolated to the fragment
// so the surface can shade rolling wave bands + crest foam.
varying float wave_crest;
varying vec3 world_pos;
varying vec3 wnormal;  // world-space wave normal (cheaper than INV_VIEW_MATRIX per fragment)

// --- gradient noise (for rain / storm texture) ----------------------------
// TWO lattice rules learned the hard way:
// 1. sin(a)*sin(b) products form egg-crate dot lattices — never use them.
// 2. plain VALUE noise interpolates hashed CELL CORNERS, so its bumps sit ON
//    a visible square lattice: "boxy" cells across the sea and rain flecks
//    popping one-per-cell in perfect rows (user screenshots 2026-09-15).
// GRADIENT noise hashes a random DIRECTION per corner and interpolates dot
// products — bumps land INSIDE cells at random offsets, no readable grid.
// The input is pre-rotated so even the underlying lattice has no world-axis
// alignment.
float hash21_o(vec2 c) {
	// PRECISION-SAFE hash. The old fract(sin(dot(c, vec2(127.1,311.7)))*43758)
	// degenerates at world scale: positions reach ±250 m and the highest octave
	// multiplies by 2.6, so sin() got ~200,000-radian arguments and float32
	// quantized its output into correlated diagonal bands — every noise cell
	// rendered as a straight-edged RECTANGLE patch (the persistent "box grid"
	// screenshots). Wrapping the cell index keeps the hash input tiny and the
	// sine-free Hoskins mix keeps full float precision: no correlated bands.
	c = mod(c, 1024.0);  // 500 m plane * 2.73 max octave = 682 < 1024: no seam in view
	vec3 p3 = fract(vec3(c.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 gdir_o(float h) {
	// cheap hashed unit direction (no trig)
	return normalize(vec2(h - 0.5, fract(h * 7.31) - 0.5) + vec2(0.023, 0.031));
}
float gnoise_o(vec2 p) {
	p = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p;  // ~37° rotation: no axis-aligned cells
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float va = dot(gdir_o(hash21_o(i)), f);
	float vb = dot(gdir_o(hash21_o(i + vec2(1, 0))), f - vec2(1, 0));
	float vc = dot(gdir_o(hash21_o(i + vec2(0, 1))), f - vec2(0, 1));
	float vd = dot(gdir_o(hash21_o(i + vec2(1, 1))), f - vec2(1, 1));
	// gradient noise spans ~[-0.7, 0.7]; remap to full [0, 1] so downstream
	// amplitudes/thresholds behave like before.
	return clamp(0.5 + mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y) * 0.72, 0.0, 1.0);
}

// Wave-field constants (keep in sync with ocean.gd _WAVES + raft_foam.gdshader).
// Tuned for a SMOOTH, realistic sea: two long rolling swells dominate and the
// fine chop is kept tiny, so the surface breathes instead of jittering.
//   dir, freq, amp, time_speed
const vec2 L1_DIR = vec2(1.0, 0.15);
const vec2 L2_DIR = vec2(-0.4, 0.92);
const vec2 L3_DIR = vec2(0.8, -0.5);
const vec2 L4_DIR = vec2(-0.75, -0.65);
const float L1_F = 0.055;
const float L2_F = 0.115;
const float L3_F = 0.24;
const float L4_F = 0.50;
const float L1_A = 1.0;
const float L2_A = 0.75;
const float L3_A = 0.38;
const float L4_A = 0.13;
const float L1_S = 0.45;
const float L2_S = 0.7;
const float L3_S = 1.05;
const float L4_S = 1.45;
// CROSS-SWELL: two extra incommensurate mid-frequency waves from unrelated
// directions. Four aligned harmonics made the sea read as regular parallel
// bands; two cross components scramble the interference into the random-looking
// amplitude mixing of a real sea (keep in sync with ocean.gd _WAVES).
const vec2 L5_DIR = vec2(0.33, 0.94);
const vec2 L6_DIR = vec2(-0.95, 0.05);
const float L5_F = 0.163;
const float L6_F = 0.317;
const float L5_A = 0.27;
const float L6_A = 0.16;
const float L5_S = 0.87;
const float L6_S = 1.23;
const float WAVE_SUM = 2.69;

// Organic-field constants: a slow 2D "meander" that warps the wave sampling
// position (bending/breaking every crest line so no straight parallel rows
// exist) and a slow "swell envelope" that makes wave sets arrive unevenly
// (bigger swells followed by calmer patches — real open ocean, never a
// repeating pattern). Mirrored exactly in Ocean.get_height().
const vec2 M1_DIR = vec2(0.21, 0.98);
const vec2 M2_DIR = vec2(0.85, -0.53);
const float M1_F = 0.020;
const float M2_F = 0.048;
const float M1_S = 0.10;
const float M2_S = 0.16;
const float M_AMP = 6.0;
const float M_AMP2 = 3.2;
const vec2 E1_DIR = vec2(-0.31, 0.95);
const vec2 E2_DIR = vec2(0.90, -0.44);
const float E1_F = 0.011;
const float E2_F = 0.026;
const float E1_S = 0.06;
const float E2_S = 0.10;

varying vec2 v_warp;  // meander offset, shared by the fragment fine-detail layers

// Island seabed height at q (island-local XZ, r = length(q)).
// KEEP-IN-SYNC with island_generator.gd terrain_height_local() BASE section:
// coast_wobble + lagoon_mask + radial profile. Closed-form math only.
float island_base(vec2 q, float r) {
	float wobble = sin(q.x * 0.052 + 1.3) * cos(q.y * 0.047 + 0.7)
		+ 0.6 * sin((q.x + q.y) * 0.031 + 2.1);
	float r_eff = r + wobble * 5.0;
	float base;
	if (r_eff <= shore_radius) {
		base = beach_height * 0.5 * (1.0 + cos(3.14159 * r_eff / shore_radius));
	} else {
		float d = clamp((r_eff - shore_radius) / (outer_radius - shore_radius), 0.0, 1.0);
		base = -deep_depth * (d * d * (3.0 - 2.0 * d));
	}
	if (base < 0.0) {
		float lmask = (r > 0.001) ? clamp((q.x * 0.6216 + q.y * 0.7833) / r, 0.0, 1.0) : 0.0;
		float floor_depth = -(0.4 + 2.6 * smoothstep(26.0, 48.0, r));
		base = mix(base, floor_depth, lmask);
	}
	return base;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = wp;
	vec2 p = wp.xz;
	float t = TIME * wave_speed;
	vec2 warp = vec2(
		M_AMP * sin(dot(M1_DIR, p) * M1_F + t * M1_S) + M_AMP2 * sin(dot(M2_DIR, p) * M2_F + t * M2_S),
		M_AMP * sin(dot(M1_DIR, p) * M1_F + t * M1_S + 2.1) + M_AMP2 * sin(dot(M2_DIR, p) * M2_F + t * M2_S + 4.2));
	v_warp = warp;
	vec2 pw = p + warp;
	float env = 0.75 + 0.25 * sin(dot(E1_DIR, pw) * E1_F + t * E1_S)
		* sin(dot(E2_DIR, pw) * E2_F + t * E2_S);
	float h = env * (L1_A * sin(dot(L1_DIR, pw) * L1_F + t * L1_S)
		+ L2_A * sin(dot(L2_DIR, pw) * L2_F + t * L2_S)
		+ L3_A * sin(dot(L3_DIR, pw) * L3_F + t * L3_S)
		+ L4_A * sin(dot(L4_DIR, pw) * L4_F + t * L4_S)
		+ L5_A * sin(dot(L5_DIR, pw) * L5_F + t * L5_S)
		+ L6_A * sin(dot(L6_DIR, pw) * L6_F + t * L6_S));
	VERTEX.y += h * wave_height * 0.33;
	wave_crest = clamp(h / (WAVE_SUM * max(env, 0.3)), -1.0, 1.0);
	// Per-vertex wave normal from the analytic slope of the same formula so
	// glints follow the wave shapes (never a flat dark plane). The envelope
	// and meander vary far more slowly than the waves, so the slope keeps the
	// plain plane-wave derivative evaluated at the warped position.
	float amp = wave_height * 0.33;
	float dhdx = amp * env * (L1_A * L1_F * L1_DIR.x * cos(dot(L1_DIR, pw) * L1_F + t * L1_S)
		+ L2_A * L2_F * L2_DIR.x * cos(dot(L2_DIR, pw) * L2_F + t * L2_S)
		+ L3_A * L3_F * L3_DIR.x * cos(dot(L3_DIR, pw) * L3_F + t * L3_S)
		+ L4_A * L4_F * L4_DIR.x * cos(dot(L4_DIR, pw) * L4_F + t * L4_S)
		+ L5_A * L5_F * L5_DIR.x * cos(dot(L5_DIR, pw) * L5_F + t * L5_S)
		+ L6_A * L6_F * L6_DIR.x * cos(dot(L6_DIR, pw) * L6_F + t * L6_S));
	float dhdz = amp * env * (L1_A * L1_F * L1_DIR.y * cos(dot(L1_DIR, pw) * L1_F + t * L1_S)
		+ L2_A * L2_F * L2_DIR.y * cos(dot(L2_DIR, pw) * L2_F + t * L2_S)
		+ L3_A * L3_F * L3_DIR.y * cos(dot(L3_DIR, pw) * L3_F + t * L3_S)
		+ L4_A * L4_F * L4_DIR.y * cos(dot(L4_DIR, pw) * L4_F + t * L4_S)
		+ L5_A * L5_F * L5_DIR.y * cos(dot(L5_DIR, pw) * L5_F + t * L5_S)
		+ L6_A * L6_F * L6_DIR.y * cos(dot(L6_DIR, pw) * L6_F + t * L6_S));
	vec3 local_n = normalize(vec3(-dhdx, 1.0, -dhdz));
	NORMAL = local_n;
	wnormal = normalize((MODEL_MATRIX * vec4(local_n, 0.0)).xyz);
}

void fragment() {
	// ---- Underside (swimming below the surface) ----
	// With cull_disabled the plane renders from both sides. From below, shade
	// the surface as a dim water ceiling that glows toward the sun/moon, so
	// the player never sees through the ocean into the sky while swimming.
	if (!FRONT_FACING) {
		vec3 under_base = mix(water_deep_color, water_day_color, 0.35);
		under_base = mix(under_base, water_night_color, night_factor);
		under_base = mix(under_base, water_twilight_color, twilight_factor * 0.5);
		// Sun/moon light filtering down through the surface: a soft bright patch
		// in the direction of the light, dimmed at night.
		vec3 to_cam_u = normalize(CAMERA_POSITION_WORLD - world_pos);
		float sun_through = pow(max(dot(-to_cam_u, normalize(sun_dir)), 0.0), 6.0);
		float moon_through = pow(max(dot(-to_cam_u, normalize(moon_dir)), 0.0), 8.0);
		under_base += sun_through * sun_glint_color * 0.22 * (1.0 - night_factor);
		under_base += moon_through * moon_glint_color * 0.12 * moon_factor;
		// Grazing angles (looking sideways along the surface) darken with depth
		// fog so the underside never reads as a thin bright film.
		float grazu = 1.0 - clamp(-to_cam_u.y, 0.0, 1.0);
		under_base *= 1.0 - grazu * 0.45;
		ALBEDO = clamp(under_base, vec3(0.012, 0.03, 0.09), vec3(1.0));
	} else {
	// Everything below is computed in WORLD space (wave normal passed from the
	// vertex stage; the view vector is built from world positions) so fresnel,
	// face lighting and glitter track the true sun/moon directions regardless
	// of camera pitch.
	vec3 n = normalize(wnormal);
	vec3 tocam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float ndv = max(dot(n, tocam), 0.0);  // 1 = looking straight down, 0 = grazing
	vec2 p = world_pos.xz + v_warp;  // warped like the vertex waves: fine detail bends with the swells
	float t = TIME * wave_speed;

	// Fragment-scale micro ripples (finer than the mesh can displace):
	// VALUE-NOISE based — the old sum of 3 plane waves formed a regular
	// hexagonal dot lattice over the whole sea (the screenshot bug). Noise
	// gives unstructured chop; gradients come from forward differences.
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float fine = smoothstep(120.0, 18.0, dist);
	vec2 nq = p * 1.05;
	float mh = (gnoise_o(nq + vec2(t * 1.1, t * 0.7)) - 0.5) * 0.50
		+ (gnoise_o(nq * 2.6 + vec2(-t * 1.5, t * 1.1)) - 0.5) * 0.28;
	float ne = 0.10;
	float mh_x = (gnoise_o((p + vec2(ne, 0.0)) * 1.05 + vec2(t * 1.1, t * 0.7)) - 0.5) * 0.50
		+ (gnoise_o((p + vec2(ne, 0.0)) * 2.6 + vec2(-t * 1.5, t * 1.1)) - 0.5) * 0.28;
	float mh_z = (gnoise_o((p + vec2(0.0, ne)) * 1.05 + vec2(t * 1.1, t * 0.7)) - 0.5) * 0.50
		+ (gnoise_o((p + vec2(0.0, ne)) * 2.6 + vec2(-t * 1.5, t * 1.1)) - 0.5) * 0.28;
	float mgx = (mh_x - mh) / ne;
	float mgz = (mh_z - mh) / ne;
	n = normalize(vec3(n.x - mgx * fine * 0.20, n.y, n.z - mgz * fine * 0.20));
	ndv = max(dot(n, tocam), 0.0);
	float micro_w = mh * fine;  // unstructured ripple level near the camera

	// ---- RAIN: a storm boils the surface ----
	// NOISE-driven roughening: two scrolling value-noise octaves (different
	// scales/speeds/directions) = hundreds of tiny random impacts. The old
	// sine sums made visible parallel wave lines across the whole sea.
	float rain = clamp(rain_strength, 0.0, 1.0);
	if (rain > 0.001) {
		vec2 rp = world_pos.xz;
		float rx = (gnoise_o(rp * 0.9 + vec2(t * 2.6, t * 1.9)) - 0.5)
			+ (gnoise_o(rp * 2.3 - vec2(t * 3.4, t * 2.1)) - 0.5) * 0.6;
		float rz = (gnoise_o(rp * 0.9 + vec2(t * 2.2, -t * 2.8) + 19.7) - 0.5)
			+ (gnoise_o(rp * 2.3 + vec2(-t * 1.7, t * 3.1) + 7.3) - 0.5) * 0.6;
		n = normalize(vec3(n.x + rx * 0.30 * rain, n.y, n.z + rz * 0.30 * rain));
		ndv = max(dot(n, tocam), 0.0);
	}

	// Irregular high-frequency breakup shared by glitter and whitecaps.
	// Anisotropically-stretched VALUE NOISE = lazy broken streaks along the
	// swell with zero preferred axis alignment (the sine product made a
	// visible diagonal lattice in the glitter path).
	vec2 cs = vec2(p.x * 0.42 - p.y * 0.25, p.x * 0.22 + p.y * 0.95);
	float chop = clamp(0.5 + (gnoise_o(cs * 1.15 + vec2(t * 0.7, -t * 0.5)) - 0.5) * 1.6, 0.0, 1.0);

	// ---- Base color: day -> twilight -> night ----
	vec3 base = mix(water_day_color, water_twilight_color, twilight_factor);
	base = mix(base, water_night_color, night_factor);

	// ---- Sky tone reflected by the surface (per time of day) ----
	// Day: pale blue dome. Twilight (dawn/dusk): warm pale glow near the
	// horizon (the real reason a morning sea reads as a sea, not a dark flat
	// sheet). Night: faint navy. Used by the horizon, fresnel sheen and the
	// sky-mirror band shading so surface structure tracks the actual sky.
	vec3 sky_tone = mix(vec3(0.09, 0.40, 0.68), vec3(0.12, 0.30, 0.50), twilight_factor);
	sky_tone = mix(sky_tone, vec3(0.016, 0.06, 0.14), night_factor);

	// ---- Near/steep = deep navy; far/grazing = lighter cobalt horizon ----
	// Looking almost straight down at close water you see through to the deep
	// column (dark navy like the reference foreground). Toward the horizon the
	// water gains aerial light (medium cobalt, never pale).
	// Far sea brightens toward cobalt over 10-140 m; the steepest close water
	// (viewed almost straight down) darkens to the deep navy foreground.
	float horizon_k = smoothstep(8.0, 150.0, dist);
	// At dawn/dusk the far band catches the pale glow of the bright horizon
	// (lighter + faintly warm), which is what makes a morning sea read as a
	// morning sea instead of a dark flat sheet.
	vec3 hz = mix(water_horizon_color, water_twilight_color * 1.0, twilight_factor);
	hz = mix(hz, sky_tone * 1.35, twilight_factor * 0.6);
	hz = mix(hz, water_night_color * 1.5, night_factor);
	float near_steep = (1.0 - horizon_k) * smoothstep(0.5, 0.95, ndv);
	base = mix(base, water_deep_color, near_steep * 0.92);
	base = mix(base, hz, horizon_k * 0.85);

	// ---- ISLAND: depth-aware shallows + surf (mirrors the real seabed) ----
	float shore_foam = 0.0;
	if (island_active > 0.5) {
		vec2 li = world_pos.xz - island_center;
		float lr = length(li);
		if (lr < outer_radius * 1.05) {
			float tb = island_base(li, lr);
			float depth = max(-tb, 0.0);
			// Turquoise shallow body; sunlit sand glows through near the shore.
			float shallow_k = 1.0 - smoothstep(0.3, 7.0, depth);
			vec3 sand_glow = vec3(0.50, 0.44, 0.28);
			vec3 lagoon_col = vec3(0.05, 0.36, 0.38);
			vec3 shallow_body = mix(lagoon_col, sand_glow, smoothstep(2.8, 0.15, depth) * 0.9);
			shallow_body = mix(shallow_body, vec3(0.012, 0.10, 0.22), night_factor * 0.75);
			base = mix(base, shallow_body, shallow_k * shallow_k * 0.9);
			// Rolling breaker lines: bands collapsing shoreward (depth-based so
			// they follow the exact coastline shape, lagoon curve included),
			// broken into flecks so they never read as perfect rings.
			float t2 = TIME * wave_speed;
			float breaker_band = smoothstep(0.70, 0.96, sin(depth * 1.9 - t2 * 1.1 + sin(lr * 0.35) * 1.2));
			// Breakup MUST NOT be axis-aligned: sin(x)*sin(z) paints an invisible
			// world-axis GRID of foam strength that shows on the glowing submerged
			// sand. Two rotated, incommensurate waves have no preferred direction
			// and cannot tile into visible rows/columns.
			vec2 bdir1 = vec2(0.809, 0.588);  // ~36°
			vec2 bdir2 = vec2(-0.423, 0.906); // ~115° (not perpendicular to bdir1)
			float breakup = 0.5 + 0.5 * sin(dot(bdir1, world_pos.xz) * 1.05 + t2 * 1.3)
				* sin(dot(bdir2, world_pos.xz) * 0.83 - t2 * 0.9);
			float depth_band = smoothstep(0.12, 0.45, depth) * (1.0 - smoothstep(2.0, 3.4, depth));
			shore_foam = breaker_band * breakup * depth_band;
			// Thin wash line hugging the waterline, breathing with the swell.
			shore_foam += smoothstep(0.22, 0.02, depth) * (0.45 + 0.30 * sin(t2 * 1.5 + lr * 0.8));
			// Foam collar around the half-submerged shore rocks.
			for (int i = 0; i < 16; i++) {
				if (i >= foam_rock_count) { break; }
				float fr = distance(world_pos.xz, foam_rocks[i]);
				float ring = smoothstep(2.3, 0.5, fr);
				float churn = 0.55 + 0.45 * sin(fr * 5.0 - t2 * 2.2 + float(i) * 2.7);
				shore_foam += ring * churn * 0.8;
			}
			shore_foam *= 1.0 - night_factor * 0.45;
		}
	}

	// ---- Fresnel sheen toward the sky tone (subtle) ----
	float fres = pow(1.0 - ndv, 3.0);
	base = mix(base, sky_tone, fres * 0.08);

	// ---- Wave-band shading: rolling crest faces catch light, troughs darken ----
	float crest = wave_crest;
	float trough = smoothstep(-1.0, -0.08, -crest);
	base *= 1.0 - trough * 0.35 * (1.0 - horizon_k * 0.75);
	// Neutral wave-band contrast (works at any time of day, incl. night): rolling
	// crests lift and troughs fall so wave bands stay visible even without sun.
	base *= 1.0 + crest * 0.16 * (1.0 - horizon_k * 0.75);
	// At night crests pick up a faint cool lift so the far dark side still shows
	// moving swell structure instead of a uniform navy sheet.
	base += crest * vec3(0.02, 0.05, 0.10) * night_factor * (1.0 - horizon_k * 0.9);
	// Fragment-scale ripple shading: micro crests catch a little light, micro
	// troughs fall darker — this is what makes the near field read as moving
	// chop instead of a flat tint between the coarse mesh waves.
	base *= 1.0 + micro_w * 0.55;

	// ---- Sky-mirror wave bands (light-independent) ----
	// Wave facets that tilt up enough to reflect the sky dome lift toward the
	// sky tone; facets that reflect other water stay in the deep sea body. The
	// reflection elevation swings with every wave slope, so rolling bands read
	// from ANY viewing azimuth — the side opposite the sun/moon no longer looks
	// flat. Subtle, sea-blue, never white.
	vec3 r = reflect(-tocam, n);
	float refl_up = r.y;
	float mir_k = smoothstep(-0.14, 0.28, refl_up);
	mir_k *= 1.0 - near_steep * 0.7;  // weakest looking straight down
	base = mix(base, sky_tone * 1.1, mir_k * 0.16);
	base *= 1.0 - (1.0 - mir_k) * 0.06;  // facets hiding the sky sit slightly darker

	// Lit wave faces: only faces tilted toward the light on rising crests get the
	// blue-cyan lift (reference crest fronts). Faces away from the sun stay in
	// the deep navy body, so the near field keeps its dark character.
	// Night keeps the blue body: crest faces dim toward a deep sea blue
	// instead of gray, so moonlit waves stay alive (never a gray slab).
	vec3 crest_col = mix(water_crest_color, water_crest_color * vec3(0.30, 0.42, 0.62), night_factor);
	// At dawn/dusk lit crest faces catch the warm horizon glow (kept subtle,
	// still blue-green, never orange water).
	crest_col = mix(crest_col, sky_tone * 1.3, twilight_factor * 0.45);
	vec3 sun_n = normalize(sun_dir);
	float face_lit = pow(max(dot(n, sun_n), 0.0), 2.5);
	float crest_up = smoothstep(0.05, 0.9, crest);
	float face_mix = face_lit * crest_up * (1.0 - horizon_k);
	// Sun by day, moon by night — rising wave fronts facing the active light
	// still catch the crest color after dark (moonlit faces).
	float moon_face = pow(max(dot(n, normalize(moon_dir)), 0.0), 2.5);
	face_mix *= mix(face_lit, moon_face, night_factor) * mix(1.0, 0.55, night_factor);
	// Steep near views look into the water column: less face lighting, more body.
	face_mix *= 1.0 - near_steep * 0.55;
	base = mix(base, crest_col, face_mix * 0.28);

	// Night dims the whole water body only gently (the deep/horizon mixes above
	// are day-scaled); moon glitter is added afterwards so it still reads.
	base *= mix(1.0, 0.80, night_factor);
	// Rain darkens + desaturates the body (overcast storm light).
	base *= 1.0 - rain * 0.14;

	// ---- Specular: broken sun glitter by day, moon shimmer by night ----
	// Highlights only land on crest bands, break into elongated streaks via
	// chop, and fade out with distance — no round dots, no far-field grid.
	float sdot = max(dot(r, sun_n), 0.0);
	float glitter_dist = smoothstep(120.0, 30.0, dist);
	float glitter = (pow(sdot, 26.0) * 0.05 + pow(sdot, 110.0) * 0.22) * chop
		* (0.30 + 0.70 * crest_up) * glitter_dist
		* sparkle_strength * 0.40 * (1.0 - night_factor);
	// Moon path: wider lobe + stronger so the shimmer visibly tracks the swell
	// lines at night (the “path of moonlight on water”).
	float moon_spark = pow(max(dot(r, normalize(moon_dir)), 0.0), 60.0) * chop
		* glitter_dist * 0.35 * moon_factor * sparkle_strength * 0.40;
	vec3 light_add = glitter * sun_glint_color + moon_spark * moon_glint_color;

	// Soft broad sheen on wave faces facing each light (kept small).
	float sun_sheen = pow(face_lit, 3.0) * crest_up * 0.05 * (1.0 - night_factor);
	float moon_sheen = pow(max(dot(n, normalize(moon_dir)), 0.0), 8.0) * 0.10 * moon_factor;
	light_add += sun_sheen * sun_glint_color + moon_sheen * moon_glint_color;

	// ---- Whitecaps: sparse, broken, only on genuinely steep micro-crest
	// facets near the camera. No thresholded blobs, no far-field foam — chop
	// breaks the gate into flecks so it reads as churning foam, not circles.
	float steep = 1.0 - n.y;
	float cap = smoothstep(0.22, 0.44, steep) * smoothstep(0.28, 0.5, mh) * chop;
	cap *= 1.0 - smoothstep(12.0, 70.0, dist);
	// Whitecaps stay blue-white at night (moonlit foam, not gray flecks).
	vec3 foam_col = mix(water_foam_color * 0.9, vec3(0.30, 0.40, 0.52), night_factor);
	foam_col = mix(foam_col, water_foam_color * 0.5, twilight_factor * 0.6);
	light_add += cap * foam_col * 0.20 * (1.0 - night_factor * 0.45);

	// Shore surf: breaker lines, waterline wash and rock collars computed above.
	light_add += shore_foam * foam_col * 0.75;

	// ---- Rain churn: random bright impact glints across the near field.
	// MUST be hash noise — the old product-of-sines painted a perfect
	// egg-crate DOT GRID over the whole ocean (the screenshot bug).
	if (rain > 0.001) {
		float flicker = gnoise_o(world_pos.xz * 1.7 - vec2(t * 1.1, t * 0.7));
		float fleck = smoothstep(0.78, 0.95, flicker) * (0.6 + 0.4 * sin(t * 23.0 + flicker * 40.0));
		light_add += fleck * foam_col * 0.30 * rain * (1.0 - smoothstep(20.0, 45.0, dist));
	}

	// ---- Atmospheric haze at the very far field ----
	float haze = smoothstep(90.0, 380.0, dist);
	vec3 haze_col = mix(water_haze_color, water_night_color * 1.3, night_factor);
	base = mix(base, haze_col, haze * 0.5);

	// Never-black floor keeps the water reading as water even in deep night.
	vec3 col = max(base + light_add, vec3(0.012, 0.03, 0.09));
	ALBEDO = col;
	}
}
