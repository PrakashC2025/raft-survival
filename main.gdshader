shader_type spatial;
render_mode unshaded;

// ============================================================
// OCEAN — time-of-day responsive water
// Driven per-frame by ocean.gd (uniforms below are pushed from
// the Sky3D sun/moon state). The wave VERTEX formula is the
// original — only the shading is time-aware.
//
// Palette note: uniforms are NOT source_color — ocean.gd pushes
// TRUE LINEAR HDR values (source_color would silently convert
// them sRGB->linear and darken the water ~3x). The scene uses
// ACES tonemapping (mode 3), which lifts mid-tones. The colors
// below are the LINEAR inputs; the FINAL displayed ocean is a
// bright Raft-style blue:
//   day (0.05, 0.18, 0.40) -> ~sRGB (0.23, 0.55, 0.76) blue
//   night (0.012, 0.04, 0.12) -> ~sRGB (0.06, 0.20, 0.44) navy
// Verified empirically against the real ACES+sRGB pipeline.
// ============================================================

// --- time-of-day state (ocean.gd) ---
uniform vec3 water_day_color = vec3(0.05, 0.22, 0.46);
uniform vec3 water_twilight_color = vec3(0.06, 0.07, 0.22);
uniform vec3 water_night_color = vec3(0.012, 0.04, 0.12);
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform float twilight_factor : hint_range(0.0, 1.0) = 0.0;
uniform float moon_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -0.5, -0.8);
uniform vec3 sun_glint_color = vec3(1.0, 0.95, 0.85);
uniform vec3 moon_glint_color = vec3(0.62, 0.78, 0.95);
uniform float sparkle_strength : hint_range(0.0, 4.0) = 1.0;

// --- waves (identical geometry to the original) ---
uniform float wave_height = 0.4;
uniform float wave_speed = 1.2;

// Wave crest level (-1 trough .. +1 crest) interpolated to the fragment
// so the surface can shade rolling wave bands + crest foam.
varying float wave_crest;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = sin(wp.x * 0.4 + TIME * wave_speed)
		+ sin(wp.z * 0.3 + TIME * wave_speed * 0.8)
		+ 0.5 * sin((wp.x + wp.z) * 0.7 + TIME * 1.7);
	VERTEX.y += h * wave_height * 0.33;
	// Normalized crest level for the fragment shader (raw sum ~ -2.5..+2.5).
	wave_crest = clamp(h / 2.2, -1.0, 1.0);
	// Per-vertex wave normal from the analytic slope of the same formula so
	// glints follow the wave shapes (never a flat dark plane at night).
	float amp = wave_height * 0.33;
	float dhdx = amp * (0.4 * cos(wp.x * 0.4 + TIME * wave_speed)
		+ 0.35 * cos((wp.x + wp.z) * 0.7 + TIME * 1.7));
	float dhdz = amp * (0.3 * cos(wp.z * 0.3 + TIME * wave_speed * 0.8)
		+ 0.35 * cos((wp.x + wp.z) * 0.7 + TIME * 1.7));
	NORMAL = normalize(vec3(-dhdx, 1.0, -dhdz));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(-VIEW);
	float ndv = max(dot(n, v), 0.0);

	// Base water color: day -> twilight -> deep navy night, always tinted.
	vec3 base = mix(water_day_color, water_twilight_color, twilight_factor);
	base = mix(base, water_night_color, night_factor);

	// Fresnel: looking straight down shows the base; grazing angles (distant
	// ocean from a low camera) mix toward a slightly lighter sky-blue tint so
	// the horizon reads like real water reflecting the sky — never toward
	// white, so the ocean can't wash out.
	float fres = pow(1.0 - ndv, 2.0);
	// Horizon tint = slightly LIGHTER blue than the base (low red so it can
	// never wash toward grey/white): distant water brightens naturally like
	// real sky reflection while staying saturated.
	vec3 sky_ref = mix(vec3(0.05, 0.30, 0.56), vec3(0.12, 0.14, 0.24), twilight_factor);
	sky_ref = mix(sky_ref, vec3(0.012, 0.045, 0.14), night_factor);
	base = mix(base, sky_ref, fres * 0.5);

	// Wave-band shading: rolling crests catch the light (lighter blue), deep
	// troughs fall darker — this is what makes the surface read as waves like
	// the reference, instead of a flat tint.
	float crest = wave_crest;
	vec3 wave_shade = mix(vec3(0.6, 0.85, 1.0), vec3(1.0, 0.9, 0.7), twilight_factor * 0.5);
	wave_shade = mix(wave_shade, vec3(0.18, 0.3, 0.5), night_factor);
	// Lit crest faces (day only — night keeps only a subtle moonlit roll).
	float lit = smoothstep(0.3, 1.0, crest);
	base += wave_shade * lit * vec3(0.13, 0.19, 0.20) * (1.0 - night_factor);
	// Troughs darken for depth and wave contrast.
	base *= 1.0 - 0.32 * smoothstep(-1.0, -0.15, -crest) * (1.0 - night_factor * 0.5);

	// Specular: sun sparkle by day/twilight, moon shimmer by night. Both are
	// sharp, narrow highlights — never a broad bright wash.
	vec3 r = reflect(-v, n);
	float sun_spark = pow(max(dot(r, normalize(sun_dir)), 0.0), 110.0)
		* sparkle_strength * (1.0 - night_factor) * 1.3;
	float moon_spark = pow(max(dot(r, normalize(moon_dir)), 0.0), 55.0)
		* sparkle_strength * 0.9 * moon_factor;
	vec3 light_add = sun_spark * sun_glint_color + moon_spark * moon_glint_color;

	// Broad soft sheen toward each light so wave faces read as rolling shapes
	// even in deep night. Kept SMALL: ACES lifts mid-tones hard, so a broad
	// white sheen desaturates the whole surface (the old washed-out look) and
	// an over-strong moon sheen makes night as bright as day.
	float sun_sheen = pow(max(dot(n, normalize(sun_dir)), 0.0), 9.0) * 0.035 * (1.0 - night_factor);
	float moon_sheen = pow(max(dot(n, normalize(moon_dir)), 0.0), 7.0) * 0.055 * moon_factor;
	light_add += sun_sheen * sun_glint_color + moon_sheen * moon_glint_color;

	// Small white-blue crest foam caps on the highest wave tops — day only.
	float foam = smoothstep(0.7, 1.0, crest);
	light_add += foam * mix(vec3(0.7, 0.85, 0.95), vec3(0.18, 0.28, 0.45), night_factor)
		* vec3(0.09, 0.11, 0.12) * (1.0 - night_factor * 0.9);

	// Never-black floor keeps the water reading as water even in deep night.
	vec3 col = max(base + light_add, vec3(0.008, 0.022, 0.06));
	ALBEDO = col;
}
