// Realistic rock shader — cheap procedural granite for the island's
// displaced-sphere rocks.
//
// FIXED v3: object-space positions are passed from the vertex shader via
// varyings, so the procedural noise is truly "painted on" the rock and
// never shifts/swims as the camera moves. The old fragment-shader
// (MODEL_MATRIX * VERTEX) computed view-space positions that drifted
// with camera movement.
//
// NIGHT-SAFE: rock albedo stays in the 0.15-0.32 range so direct moonlight
// cannot clip it to white (the "white rock at night" bug).
shader_type spatial;

uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float seed = 0.0;

varying highp vec3 obj_pos;
varying highp vec3 obj_normal;

float hash21(highp vec2 c) {
	// PRECISION-SAFE hash (ocean/terrain fix): fract(sin(dot)) degenerates at
	// world scale — correlated diagonal bands render as rectangle patches on
	// the rock faces. Wrap coords + sine-free mix; the uniform seed still
	// varies per rock.
	c = mod(c, 1024.0);
	highp vec3 p3 = fract(vec3(c.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z + seed * 17.13);
}
float vnoise(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}
float fbm2(highp vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.3 + 11.3) * 0.35;
}

// Triplanar blend by normal weight — stable from every angle.
float tri_fbm2(highp vec3 p, highp vec3 n, float scale) {
	highp vec3 an = abs(n);
	highp vec3 w3 = an * an * an;
	float wt = w3.x + w3.y + w3.z;
	w3 /= max(wt, 0.001);
	return fbm2(p.xy * scale) * w3.z
		 + fbm2(p.yz * scale) * w3.x
		 + fbm2(p.xz * scale) * w3.y;
}
float tri_vnoise(highp vec3 p, highp vec3 n, float scale) {
	highp vec3 an = abs(n);
	highp vec3 w3 = an * an * an;
	float wt = w3.x + w3.y + w3.z;
	w3 /= max(wt, 0.001);
	return vnoise(p.xy * scale) * w3.z
		 + vnoise(p.yz * scale) * w3.x
		 + vnoise(p.xz * scale) * w3.y;
}

void vertex() {
	// Object-space position and normal — computed once per vertex, fully
	// stable regardless of camera movement.
	obj_pos = VERTEX;
	obj_normal = normalize(NORMAL);
}

void fragment() {
	highp vec3 wp = obj_pos;
	highp vec3 wn = obj_normal;

	// sediment strata: HORIZONTAL height bands (geological layering)
	float strata = fbm2(vec2(wp.y * 2.1, wp.x * 0.25 + seed * 0.01));
	// medium mineral mottle
	float med = tri_fbm2(wp, wn, 1.6);
	// fine grain
	float fine = tri_vnoise(wp, wn, 6.0);

	// base granite: dark slate <-> pale quartz, with a large-scale warm/cool
	// zoning so a boulder never wears one uniform tone (real stone drifts
	// between blue-gray granite and warm weathered patches).
	float zone = fbm2(vec2(wp.x * 0.12 + seed * 0.01, wp.z * 0.12 - wp.y * 0.05));
	vec3 cool = vec3(0.155, 0.16, 0.175);
	vec3 warm = vec3(0.34, 0.30, 0.25);
	vec3 col = mix(mix(vec3(0.17, 0.16, 0.15), vec3(0.31, 0.29, 0.26), strata), mix(cool, warm, zone), 0.55);
	// iron-oxide staining
	float stain = smoothstep(0.52, 0.8, tri_fbm2(wp, wn, 0.4));
	col = mix(col, vec3(0.30, 0.22, 0.14), stain * 0.5);
	// mottle + subtle speckle
	col *= 0.84 + 0.32 * med;
	col -= (fine - 0.5) * 0.07;
	// lichen/moss on up-facing spots: greens toward the sheltered damp side,
	// crawling up from the base (height gradient like real colonizing moss).
	float up = clamp(wn.y, 0.0, 1.0);
	float low_k = 1.0 - smoothstep(0.0, 0.9, wp.y + 1.0); // stronger near the base
	float lichen = smoothstep(0.55, 0.8, med) * smoothstep(0.6, 0.9, up);
	col = mix(col, vec3(0.17, 0.21, 0.12), lichen * (0.45 + 0.25 * low_k));
	// crevice darkening
	col *= 0.76 + 0.24 * smoothstep(0.2, 0.65, med);

	ALBEDO = clamp(col * tint, vec3(0.0), vec3(0.55));
	ROUGHNESS = 1.0;
	SPECULAR = 0.02;
	METALLIC = 0.0;
	AO = 0.78 + 0.22 * smoothstep(0.2, 0.65, med);
	AO_LIGHT_AFFECT = 0.5;
	NORMAL_MAP = normalize(vec3((med - 0.5) * 1.2, (fine - 0.5) * 0.5, 1.0));
	NORMAL_MAP_DEPTH = 0.4;
}
