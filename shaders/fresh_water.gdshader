shader_type spatial;
render_mode cull_back, depth_draw_always, blend_mix;

// ============================================================
// FRESHWATER POND — the island's inland pool.
// Visually OPPOSITE to the ocean: clear, calm, green-tinted
// spring water where you can see the pond floor through it.
// Day/night factors are synced from the ocean's material by
// island_generator.gd (same Sky3D system), so the pool darkens
// and stops sparkling at night like the sea does.
//
// REALISM v2:
//  - Rain = hundreds of tiny expanding ring ripples (analytic
//    cell-ring trick, scrolled cell hash so rings appear, grow
//    and fade — never a repeating dot grid). The surface also
//    roughens + darkens slightly while it rains, like real
//    rain-pounded water.
//  - Normal-map detail in TANGENT space so the reflection of
//    the sun/sky glides over real moving water.
// ============================================================

uniform vec3 sun_dir = vec3(0.35, 0.9, 0.2);
uniform vec3 moon_dir = vec3(-0.25, 0.7, -0.6);
uniform float night_factor = 0.0;
uniform float twilight_factor = 0.0;
// 0..1 pushed from RainSystem via island_generator (intensity while it rains)
uniform float rain_strength = 0.0;
// Pure water: clear spring-green, NOT the ocean's blue
uniform vec4 shallow_col : source_color = vec4(0.36, 0.60, 0.52, 1.0);
uniform vec4 deep_col : source_color = vec4(0.08, 0.23, 0.20, 1.0);
uniform float pond_r = 4.3;

float hash21(vec2 c) {
	// PRECISION-SAFE hash (same fix as ocean/terrain shaders).
	c = mod(c, 1024.0);
	vec3 p3 = fract(vec3(c.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

// --- rain ripple ring field ------------------------------------------------
// Each 0.5 m cell spawns one ring at a hashed offset, expanding + fading on a
// hashed phase. Two layers at different scales/speeds overlap so the pattern
// never reads as a stamped grid of dots.
float rain_ring(vec2 p, float t, float cell, float speed) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash21(id);
	// each cell's ring: lifetime 1.0, looping phase from the hash
	float ph = fract(h * 7.31 + t * speed);
	float r = length(f + (vec2(hash21(id + 3.1), hash21(id + 7.7)) - 0.5) * 0.5);
	// expanding thin ring: bright crest at radius = ph * 0.45, fading with age
	float ring = smoothstep(0.035, 0.0, abs(r - ph * 0.42)) * (1.0 - ph);
	return ring;
}

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
	// barely-there calm-water swell (a pond, not the sea); rain adds chop
	float swell = (sin(VERTEX.x * 4.1 + TIME * 1.4) + sin(VERTEX.z * 3.3 + TIME * 1.8)) * 0.008;
	VERTEX.y += swell + rain_strength * sin(VERTEX.x * 7.3 + TIME * 6.0) * 0.006;
}

void fragment() {
	vec2 p = v_local.xz;
	// gentle concentric-ish ripple normal (calm pond)
	float n1 = vnoise(p * 3.0 + TIME * 0.33);
	float n2 = vnoise(p * 5.5 - TIME * 0.27);
	vec3 calm_n = normalize(vec3((n1 - 0.5) * 1.6, 1.0, (n2 - 0.5) * 1.6));

	// rain ring normals: gradients of the two ring fields (cheap forward diff)
	float t = TIME;
	float e = 0.06;
	float r0 = rain_ring(p, t, 0.55, 1.4) + rain_ring(p, t, 0.32, 2.1) * 0.7;
	float rx = rain_ring(p + vec2(e, 0.0), t, 0.55, 1.4) + rain_ring(p + vec2(e, 0.0), t, 0.32, 2.1) * 0.7;
	float rz = rain_ring(p + vec2(0.0, e), t, 0.55, 1.4) + rain_ring(p + vec2(0.0, e), t, 0.32, 2.1) * 0.7;
	vec3 rain_n = normalize(vec3((r0 - rx) * 2.4, 1.0, (r0 - rz) * 2.4));

	// rain roughens the surface: calm dimples -> busy rain rings
	vec3 n = normalize(mix(calm_n, rain_n, clamp(rain_strength, 0.0, 1.0) * 0.85));
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.5;

	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = pow(1.0 - clamp(V.y, 0.0, 1.0), 3.0);
	float depth_f = clamp(length(p) / pond_r, 0.0, 1.0);

	vec3 col = mix(deep_col.rgb, shallow_col.rgb, 1.0 - depth_f * 0.7);
	col *= 1.0 - night_factor * 0.30;
	// rain-pounded water darkens and muddies slightly (sediment stirred up)
	col *= 1.0 - rain_strength * 0.12;
	ALBEDO = col;
	// clear water: the pond floor shows through; rain hides it (surface churn)
	float alpha = clamp(0.40 + fres * 0.42, 0.0, 0.85);
	alpha += rain_strength * 0.15;
	ALPHA = clamp(alpha * (1.0 - night_factor * 0.12), 0.0, 0.95);
	ROUGHNESS = mix(0.05, 0.22, rain_strength); // rain breaks the mirror sheen
	SPECULAR = 0.60;
	METALLIC = 0.0;
	// thin pale rim where the water meets the stone bank
	float rim = smoothstep(0.84, 1.0, depth_f);
	ALBEDO = mix(ALBEDO, vec3(0.80, 0.88, 0.84) * (1.0 - night_factor * 0.5), rim * 0.30);

	// --- real specular sun/moon glint on the rippled surface ---------------
	// Tangent-space normal -> world normal. The pond disc is flat and
	// world-aligned, so map-space slopes map straight onto world xz.
	vec3 wn = normalize(vec3(n.x, 1.0, n.z));
	vec3 L = mix(sun_dir, moon_dir, night_factor);
	vec3 H = normalize(L + V);
	float spec = pow(clamp(dot(wn, H), 0.0, 1.0), 90.0);
	vec3 spec_col = mix(vec3(1.0, 0.95, 0.82), vec3(0.75, 0.82, 1.0), night_factor);
	// rain shatters the glint into sparkle instead of one clean spot
	spec *= mix(1.0, 0.35 + 0.65 * r0, rain_strength);
	EMISSION += spec_col * spec * 1.6 * (1.0 - night_factor * 0.75) * (1.0 + twilight_factor);
}
