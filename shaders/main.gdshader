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
uniform vec3 water_day_color = vec3(0.035, 0.28, 0.58);
uniform vec3 water_twilight_color = vec3(0.035, 0.16, 0.33);
uniform vec3 water_night_color = vec3(0.022, 0.078, 0.17);
uniform vec3 water_deep_color = vec3(0.012, 0.10, 0.22);
uniform vec3 water_horizon_color = vec3(0.04, 0.45, 0.72);
uniform vec3 water_crest_color = vec3(0.10, 0.38, 0.54);
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
uniform float surface_detail : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D wave_normals : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 island_shores[7];
uniform sampler2D shore_height_0 : filter_linear, repeat_disable;
uniform sampler2D shore_height_1 : filter_linear, repeat_disable;
uniform sampler2D shore_height_2 : filter_linear, repeat_disable;
uniform sampler2D shore_height_3 : filter_linear, repeat_disable;
uniform sampler2D shore_height_4 : filter_linear, repeat_disable;
uniform sampler2D shore_height_5 : filter_linear, repeat_disable;
uniform sampler2D shore_height_6 : filter_linear, repeat_disable;

float coastal_depth(vec3 position_value) {
	for (int index = 0; index < 7; index++) {
		vec4 zone = island_shores[index];
		if (zone.z < 1.0) { continue; }
		vec2 uv = (position_value.xz - zone.xy) / (zone.zw * 2.0) + 0.5;
		if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) { continue; }
		float ground = -20.0;
		if (index == 0) { ground = texture(shore_height_0, uv).r; }
		else if (index == 1) { ground = texture(shore_height_1, uv).r; }
		else if (index == 2) { ground = texture(shore_height_2, uv).r; }
		else if (index == 3) { ground = texture(shore_height_3, uv).r; }
		else if (index == 4) { ground = texture(shore_height_4, uv).r; }
		else if (index == 5) { ground = texture(shore_height_5, uv).r; }
		else { ground = texture(shore_height_6, uv).r; }
		float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
		float padding_depth = (1.0 - smoothstep(0.0, 0.13, edge)) * 12.0;
		return position_value.y - ground + padding_depth;
	}
	return 20.0;
}

// --- waves (geometry shared with Ocean.get_height()) ---
uniform float wave_height = 0.68;
uniform float wave_speed = 0.52;
uniform float wave_time = 0.0;
uniform bool raft_displacement = false;
uniform mat4 world_to_raft;
uniform sampler2D raft_deck : filter_nearest, repeat_disable;

// Wave crest level (-1 trough .. +1 crest) interpolated to the fragment
// so the surface can shade rolling wave bands + crest foam.
varying float wave_crest;
varying vec3 world_pos;
varying vec3 wnormal;  // world-space wave normal (cheaper than INV_VIEW_MATRIX per fragment)

// Wave-field constants (keep in sync with ocean.gd _WAVES + raft_foam.gdshader).
// Tuned for a SMOOTH, realistic sea: two long rolling swells dominate and the
// fine chop is kept tiny, so the surface breathes instead of jittering.
//   dir, freq, amp, time_speed
const vec2 L1_DIR = vec2(1.0, 0.15);
const vec2 L2_DIR = vec2(-0.4, 0.92);
const vec2 L3_DIR = vec2(0.8, -0.5);
const vec2 L4_DIR = vec2(-0.75, -0.65);
const float L1_F = 0.18;
const float L2_F = 0.33;
const float L3_F = 0.59;
const float L4_F = 0.95;
const float L1_A = 1.0;
const float L2_A = 0.75;
const float L3_A = 0.38;
const float L4_A = 0.13;
const float L1_S = 0.80;
const float L2_S = 1.10;
const float L3_S = 1.55;
const float L4_S = 1.90;
const float WAVE_SUM = 2.26;

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

float water_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Value noise plus its analytic gradient: no extra texture/pass or expensive
// finite-difference samples. Irregular slopes break up the old sine-wave grid.
vec3 water_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = water_hash(cell);
	float b = water_hash(cell + vec2(1.0, 0.0));
	float c = water_hash(cell + vec2(0.0, 1.0));
	float d = water_hash(cell + vec2(1.0, 1.0));
	float k = a - b - c + d;
	return vec3(a + (b-a)*u.x + (c-a)*u.y + k*u.x*u.y,
		du.x * (b-a+k*u.y), du.y * (c-a+k*u.x));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = wp;
	vec2 p = wp.xz;
	float t = wave_time * wave_speed;
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
		+ L4_A * sin(dot(L4_DIR, pw) * L4_F + t * L4_S));
	VERTEX.y += h * wave_height * 0.33;
	world_pos.y += h * wave_height * 0.33;
	wave_crest = clamp(h / (WAVE_SUM * max(env, 0.3)), -1.0, 1.0);
	// Per-vertex wave normal from the analytic slope of the same formula so
	// glints follow the wave shapes (never a flat dark plane). The envelope
	// and meander vary far more slowly than the waves, so the slope keeps the
	// plain plane-wave derivative evaluated at the warped position.
	float amp = wave_height * 0.33;
	float dhdx = amp * env * (L1_A * L1_F * L1_DIR.x * cos(dot(L1_DIR, pw) * L1_F + t * L1_S)
		+ L2_A * L2_F * L2_DIR.x * cos(dot(L2_DIR, pw) * L2_F + t * L2_S)
		+ L3_A * L3_F * L3_DIR.x * cos(dot(L3_DIR, pw) * L3_F + t * L3_S)
		+ L4_A * L4_F * L4_DIR.x * cos(dot(L4_DIR, pw) * L4_F + t * L4_S));
	float dhdz = amp * env * (L1_A * L1_F * L1_DIR.y * cos(dot(L1_DIR, pw) * L1_F + t * L1_S)
		+ L2_A * L2_F * L2_DIR.y * cos(dot(L2_DIR, pw) * L2_F + t * L2_S)
		+ L3_A * L3_F * L3_DIR.y * cos(dot(L3_DIR, pw) * L3_F + t * L3_S)
		+ L4_A * L4_F * L4_DIR.y * cos(dot(L4_DIR, pw) * L4_F + t * L4_S));
	vec3 local_n = normalize(vec3(-dhdx, 1.0, -dhdz));
	NORMAL = local_n;
	wnormal = normalize((MODEL_MATRIX * vec4(local_n, 0.0)).xyz);
}

void fragment() {
	// Solid deck volume displaces water; crests cannot flood through timber.
	// This single compact mask also follows expansions, removal and raft yaw.
	if (raft_displacement) {
		vec3 raft_local = (world_to_raft*vec4(world_pos,1.0)).xyz;
		vec2 cell = floor((raft_local.xz+vec2(1.0))/2.0)+vec2(64.0);
		if (raft_local.y > -0.15 && all(greaterThanEqual(cell,vec2(0.0))) && all(lessThan(cell,vec2(128.0)))
			&& texture(raft_deck,(cell+vec2(0.5))/128.0).r>0.5) discard;
	}
	// ---- Underside (swimming below the surface) ----
	// With cull_disabled the plane renders from both sides. From below, shade
	// the surface as a dim water ceiling that glows toward the sun/moon, so
	// the player never sees through the ocean into the sky while swimming.
	// Camera height is consistent across drivers; face winding can differ for
	// the two-sided displaced ocean on the Compatibility path.
	if (CAMERA_POSITION_WORLD.y < world_pos.y - 0.04) {
		float under_time = wave_time * wave_speed;
		vec2 ripple_u = texture(wave_normals,world_pos.xz*.042+vec2(under_time*.003,-under_time*.002)).xy*2.0-1.0;
		vec2 ripple_v = texture(wave_normals,world_pos.zx*.081-vec2(under_time*.005,under_time*.003)).xy*2.0-1.0;
		vec3 under_base = mix(water_deep_color, water_day_color, 0.35);
		under_base = mix(under_base, water_night_color, night_factor);
		under_base = mix(under_base, water_twilight_color, twilight_factor * 0.5);
		// Sun/moon light filtering down through the surface: a soft bright patch
		// in the direction of the light, dimmed at night.
		vec3 to_cam_u = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 ripple_view = normalize(-to_cam_u+vec3(ripple_u.x+ripple_v.x,0.0,ripple_u.y+ripple_v.y)*.12);
		float sun_through = pow(max(dot(ripple_view, normalize(sun_dir)), 0.0), 6.0);
		float moon_through = pow(max(dot(-to_cam_u, normalize(moon_dir)), 0.0), 8.0);
		under_base += sun_through * sun_glint_color * 0.22 * (1.0 - night_factor);
		under_base += vec3(.045,.14,.15)*(1.0-night_factor)*(1.0+dot(ripple_u,ripple_v)*.35);
		under_base += moon_through * moon_glint_color * 0.12 * moon_factor;
		// Grazing angles (looking sideways along the surface) darken with depth
		// fog so the underside never reads as a thin bright film.
		float grazu = 1.0 - clamp(-to_cam_u.y, 0.0, 1.0);
		under_base *= 1.0 - grazu * 0.45;
		ALBEDO = clamp(under_base, vec3(0.012, 0.03, 0.09), vec3(1.0));
		EMISSION = under_base*(1.4-.9*night_factor)+sun_through*vec3(.40,.50,.46)*(1.0-night_factor);
		// This unshaded palette is linear. Compatibility writes display-space
		// colour directly, while Mobile performs the linear output conversion.
		if (OUTPUT_IS_SRGB) { ALBEDO = pow(ALBEDO,vec3(1.0/2.2)); }
	} else {
	// Everything below is computed in WORLD space (wave normal passed from the
	// vertex stage; the view vector is built from world positions) so fresnel,
	// face lighting and glitter track the true sun/moon directions regardless
	// of camera pitch.
	vec3 n = normalize(wnormal);
	vec3 tocam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float ndv = max(dot(n, tocam), 0.0);  // 1 = looking straight down, 0 = grazing
	vec2 p = world_pos.xz + v_warp;  // warped like the vertex waves: fine detail bends with the swells
	float t = wave_time * wave_speed;

	// Fragment-scale micro ripples (finer than the mesh can displace): three
	// incommensurate directional lobes so the near field reads as irregular
	// moving chop rather than a repeating pattern. Fades out with distance so
	// distant water smooths into atmospheric cobalt.
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float fine = 1.0 - smoothstep(35.0, 170.0, dist);
	// Coarse horizon triangles must not interpolate large near-wave normals
	// into kilometre-long reflection bands. Near waves/CPU buoyancy are intact.
	n=normalize(mix(n,vec3(0.0,1.0,0.0),smoothstep(180.0,600.0,dist)));
	// Filtered moving normals replace the three regular crossed sine bands.
	// Their screen footprint suppresses distant glitter without extra passes.
	float detail_lod = 1.0-smoothstep(0.06,0.45,length(fwidth(p*0.8)));
	vec3 ripple = water_noise(p * 1.7 + vec2(t * 0.24, -t * 0.18));
	vec2 normal_a = texture(wave_normals, p * 0.028 + vec2(t * 0.003,-t * 0.002)).xy * 2.0 - 1.0;
	vec2 normal_b = texture(wave_normals, vec2(p.y,-p.x) * 0.085 + vec2(-t * 0.007,t * 0.006)).xy * 2.0 - 1.0;
	vec2 ripple_slope = normal_a * 0.19 + normal_b * 0.075;
	// Broader, irregular wave faces survive farther into the sea. Pixel-footprint
	// filtering removes distant glitter aliasing without flattening nearby swells.
	vec2 swell_uv = p*0.19+vec2(-t*0.10,t*0.07);
	vec3 surface_swell = water_noise(swell_uv);
	float swell_lod = 1.0-smoothstep(0.04,0.7,length(fwidth(swell_uv)));
	ripple_slope += surface_swell.yz*0.065*swell_lod;
	if (surface_detail > 0.6) {
		vec3 small_ripple = water_noise(p * 4.3 + vec2(-t * 0.35, t * 0.29));
		ripple_slope += small_ripple.yz * 0.018 * detail_lod;
	}
	n = normalize(vec3(n.x - ripple_slope.x*mix(0.12,0.85,fine)*detail_lod,
		n.y, n.z - ripple_slope.y*mix(0.12,0.85,fine)*detail_lod));
	ndv = max(dot(n, tocam), 0.0);
	float micro_w = (ripple.x - 0.5) * fine * 0.20;

	// Irregular high-frequency breakup shared by glitter and whitecaps. It is a
	// product of two moving directional waves, stretched into lazy broken
	// streaks along the swell — lower frequency than before so the glitter
	// reads as long silk streaks, never confetti.
	float chop = mix(0.40, 1.0, ripple.x);

	// ---- Base color: day -> twilight -> night ----
	vec3 base = mix(water_day_color, water_twilight_color, twilight_factor);
	base = mix(base, water_night_color, night_factor);

	// ---- Sky tone reflected by the surface (per time of day) ----
	// Day: pale blue dome. Twilight (dawn/dusk): warm pale glow near the
	// horizon (the real reason a morning sea reads as a sea, not a dark flat
	// sheet). Night: faint navy. Used by the horizon, fresnel sheen and the
	// sky-mirror band shading so surface structure tracks the actual sky.
	vec3 sky_tone = mix(vec3(0.10, 0.25, 0.36), vec3(0.13, 0.23, 0.32), twilight_factor);
	sky_tone = mix(sky_tone, vec3(0.040, 0.10, 0.18), night_factor);

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
	vec3 deep_body = mix(water_deep_color, water_night_color * 0.72, night_factor);
	base = mix(base, deep_body, near_steep * 0.92);
	base = mix(base, hz, horizon_k * 0.85);

	// ---- Fresnel sheen toward the sky tone (subtle) ----
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	// ---- Wave-band shading: rolling crest faces catch light, troughs darken ----
	float crest = wave_crest;
	float trough = smoothstep(-1.0, -0.08, -crest);
	base *= 1.0 - trough * 0.24 * (1.0 - horizon_k * 0.75) * (1.0-night_factor*0.55);
	// Neutral wave-band contrast (works at any time of day, incl. night): rolling
	// crests lift and troughs fall so wave bands stay visible even without sun.
	base *= 1.0 + crest * 0.16 * (1.0 - horizon_k * 0.75);
	// At night crests pick up a faint cool lift so the far dark side still shows
	// moving swell structure instead of a uniform navy sheet.
	// Only lift moonlit crests. Subtracting this in troughs made black bands
	// that looked like cloud shadows even with the reflection disabled.
	base += max(crest,0.0) * vec3(0.008, 0.02, 0.035) * night_factor * (1.0 - horizon_k * 0.9);
	// Fragment-scale ripple shading: micro crests catch a little light, micro
	// troughs fall darker — this is what makes the near field read as moving
	// chop instead of a flat tint between the coarse mesh waves.
	base *= 1.0 + micro_w * 0.20;

	// ---- Sky-mirror wave bands (light-independent) ----
	// Wave facets that tilt up enough to reflect the sky dome lift toward the
	// sky tone; facets that reflect other water stay in the deep sea body. The
	// reflection elevation swings with every wave slope, so rolling bands read
	// from ANY viewing azimuth — the side opposite the sun/moon no longer looks
	// flat. Subtle, sea-blue, never white.
	vec3 r = reflect(-tocam, n);
	// A mobile-friendly sky reflection, strongest at grazing angles. This is
	// an analytic sky approximation rather than screen-space scene reflection.
	vec3 reflected_horizon = mix(vec3(0.22, 0.35, 0.43), vec3(0.30, 0.23, 0.20), twilight_factor);
	vec3 reflected_zenith = mix(vec3(0.045, 0.16, 0.27), vec3(0.07, 0.11, 0.22), twilight_factor);
	// Clear moonlit blue bounce at night: do not mirror a black cloud ceiling.
	reflected_horizon = mix(reflected_horizon, vec3(0.065, 0.13, 0.20), night_factor);
	reflected_zenith = mix(reflected_zenith, vec3(0.040, 0.085, 0.15), night_factor);
	vec3 reflection = mix(reflected_horizon, reflected_zenith, smoothstep(0.02, 0.85, max(r.y, 0.0)));
	float cloud = water_noise(r.xz / max(r.y + 0.4, 0.2) * 2.2 + vec2(t * 0.012, 0.0)).x;
	reflection += smoothstep(0.48, 0.78, cloud) * vec3(0.14, 0.15, 0.14) * (1.0 - night_factor);
	base = mix(base, reflection, (0.08 + fres * 0.38) * mix(1.0,0.35,night_factor));
	// Dark troughs retain depth beneath brighter moving reflective facets.
	base *= mix(0.82,1.03,smoothstep(-0.7,0.6,crest));
	float refl_up = r.y;
	float mir_k = smoothstep(-0.14, 0.28, refl_up);
	mir_k *= 1.0 - near_steep * 0.7;  // weakest looking straight down
	base = mix(base, sky_tone * 1.1, mir_k * 0.16);
	base *= 1.0 - (1.0 - mir_k) * 0.06 * (1.0-night_factor);

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
	base *= mix(1.0, 0.98, night_factor);

	// ---- Specular: broken sun glitter by day, moon shimmer by night ----
	// Highlights only land on crest bands, break into elongated streaks via
	// chop, and fade out with distance — no round dots, no far-field grid.
	float sdot = max(dot(r, sun_n), 0.0);
	float glitter_dist = 1.0 - smoothstep(30.0, 120.0, dist);
	float glitter = (pow(sdot, 28.0) * 0.20 + pow(sdot, mix(70.0,150.0,detail_lod)) * 0.85) * chop
		* mix(0.55, 1.0, glitter_dist)
		* sparkle_strength * (1.0 - night_factor);
	// Moon path: wider lobe + stronger so the shimmer visibly tracks the swell
	// lines at night (the “path of moonlight on water”).
	// A continuous broken silver path reaches the horizon. The old 120 m
	// daytime glitter cutoff erased the distant moon reflection completely.
	float moon_alignment = max(dot(r, normalize(moon_dir)),0.0);
	float moon_distance = 1.0-smoothstep(80.0,420.0,dist);
	float moon_spark = (pow(moon_alignment,32.0)*0.20+pow(moon_alignment,110.0)*0.65)
		* mix(0.22,chop,0.78)*moon_distance*moon_factor*sparkle_strength*0.32;
	vec3 light_add = glitter * sun_glint_color + moon_spark * moon_glint_color;

	// Soft broad sheen on wave faces facing each light (kept small).
	float sun_sheen = pow(face_lit, 3.0) * crest_up * 0.05 * (1.0 - night_factor);
	float moon_sheen = pow(max(dot(n, normalize(moon_dir)), 0.0), 8.0) * 0.10 * moon_factor;
	light_add += sun_sheen * sun_glint_color + moon_sheen * moon_glint_color;

	// ---- Whitecaps: sparse, broken, only on genuinely steep micro-crest
	// facets near the camera. No thresholded blobs, no far-field foam — chop
	// breaks the gate into flecks so it reads as churning foam, not circles.
	float steep = 1.0 - n.y;
	float cap = smoothstep(0.48, 0.86, surface_swell.x) * smoothstep(0.66, 0.9, ripple.x)
		* smoothstep(0.025, 0.10, steep) * smoothstep(0.42,0.82,crest) * chop;
	cap *= 1.0 - smoothstep(12.0, 70.0, dist);
	// Whitecaps stay blue-white at night (moonlit foam, not gray flecks).
	vec3 foam_col = mix(water_foam_color * 0.9, vec3(0.30, 0.40, 0.52), night_factor);
	foam_col = mix(foam_col, water_foam_color * 0.5, twilight_factor * 0.6);
	light_add += cap * foam_col * 0.12 * (1.0 - night_factor * 0.45);

	// ---- Atmospheric haze at the very far field ----
	float haze = smoothstep(90.0, 380.0, dist);
	vec3 haze_col = mix(water_haze_color, water_night_color * 1.3, night_factor);
	haze_col = mix(haze_col, reflected_horizon, twilight_factor * 0.55);
	base = mix(base, haze_col, haze * 0.24);
	// Actual terrain-height masks keep shallows and foam at the beach instead
	// of drawing an arbitrary circular ring. The ocean remains one opaque pass.
	float shore_depth = coastal_depth(world_pos);
	float shallow = (1.0 - smoothstep(0.25, 2.2, max(shore_depth, 0.0)));
	vec3 shallow_colour = mix(vec3(0.018,0.19,0.24), vec3(0.014,0.10,0.15), night_factor);
	base = mix(base, shallow_colour, shallow * 0.60);
	float shore_foam = 1.0 - smoothstep(0.03, 0.24, abs(shore_depth));
	shore_foam *= smoothstep(0.22, 0.72, ripple.x + sin(t * 0.9) * 0.13);
	light_add += foam_col * shore_foam * 0.38;

	// Never-black floor keeps the water reading as water even in deep night.
	// A small additive night fill retains wave/reflection contrast. A large
	// channel-wise minimum flattened most night pixels to one solid blue.
	vec3 col = max(base + light_add + vec3(0.002,0.004,0.009)*night_factor, vec3(0.001,0.002,0.004));
	// Sparse plankton follows moving wave crests, fading beyond the near water.
	vec2 plankton_cell = floor(world_pos.xz * 1.8);
	float plankton_seed = fract(sin(dot(plankton_cell,vec2(127.1,311.7)))*43758.5453);
	vec2 plankton_local = fract(world_pos.xz * 1.8) - vec2(0.2+plankton_seed*0.6,0.2+fract(plankton_seed*19.7)*0.6);
	float plankton = exp(-dot(plankton_local,plankton_local)*150.0)*step(0.92,plankton_seed)*smoothstep(0.25,0.8,crest);
	col += vec3(0.004,0.07,0.055)*plankton*night_factor*(1.0-smoothstep(12.0,40.0,dist))*surface_detail;
	ALBEDO = col;
	// Compatibility outputs unshaded ALBEDO directly in display space. The
	// shared linear palette needs the same conversion already used below water.
	// Without it, the surface becomes almost black on the fallback renderer.
	if (OUTPUT_IS_SRGB) { ALBEDO = pow(max(ALBEDO, vec3(0.0)), vec3(1.0 / 2.2)); }
	}
}
