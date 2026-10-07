shader_type spatial;

// ============================================================
// ISLAND TERRAIN — realistic grass + sand material
// The imported island_terrain.glb only carries near-white
// baseColorFactors (Blender vertex-paint workflow), so without
// this material the island renders as pale plastic.
//
// Vertex colors (COLOR_0), decoded from the actual glb:
//   IslandGrass surface = literal painted albedo (green on the
//     plateau, sandy tan toward the shore edge);
//   Sand surface = plain white (1,1,1).
// So COLOR.rgb is used as a per-vertex paint multiplier and the
// material's base_color carries the tint: the grass material
// multiplies by white (paint shows through), the sand material
// multiplies by the sand color.
// Per-pixel fbm noise breaks up flat bands so transitions look
// organic, steep faces read as rock/soil, and sand/grass darken
// smoothly when wet near the live water line (no hard band).
// ============================================================

uniform vec3 base_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float paint_boost = 1.18;     // vertex paint reads darker in linear; lift a touch
uniform float detail_scale = 22.0;    // per-pixel noise scale
uniform float detail_strength = 0.16; // how much the noise modulates albedo
uniform float sand_glint = 0.25;      // sparkle on dry sand grain peaks
uniform vec3 rock_color : source_color = vec3(0.24, 0.21, 0.18);
uniform float rock_start = 0.30;      // slope where rock blending starts
uniform float rock_full = 0.60;       // slope where rock is fully blended
uniform float wetness_depth = 0.30;   // how far below the surface the "wet" darkening starts
uniform float wetness_fade = 0.25;    // vertical fade range of the wet band (m above water)
uniform float water_line = 0.0;       // current water Y, pushed every frame by island_setup.gd
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D scan_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_scan_texture = false;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec3 v_paint;

// Cheap 3-octave value noise (no textures — mobile friendly).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep interpolation
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.7) * 0.28 + vnoise(p * 4.7 + 3.1) * 0.17;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_paint = COLOR.rgb;
}

void fragment() {
	// Photographic maps provide fine detail without unfiltered hash-grain shimmer.
	float n1 = fbm(v_world.xz * 0.30);
	float n2 = 0.5;
	float n3 = 0.5;

	// Painted albedo (vertex paint) with organic color variation and fine grain.
	vec2 sand_uv = v_world.xz * 0.22;
	vec3 sand_tex = texture(sand_albedo, sand_uv).rgb;
	vec3 sand_properties = texture(sand_arm, sand_uv).rgb;
	vec3 col = base_color * v_paint * paint_boost * sand_tex * 1.28;
	if (use_scan_texture) {
		// Keep the original scan grain while restoring pale dry coastal sand.
		col = mix(texture(scan_albedo, UV).rgb * 1.65, sand_tex * 1.20, 0.62) * base_color;
	}
	col *= 1.0 + (n1 - 0.5) * 2.0 * detail_strength;
	col *= 0.90 + 0.12 * n2 + 0.08 * n3;
	col = clamp(col, vec3(0.0), vec3(1.0));

	// Steep faces read as wet rock/soil (world-space normal, paint-independent).
	float slope = 1.0 - clamp(v_wnormal.y, 0.0, 1.0);
	float rock_k = smoothstep(rock_start, rock_full, slope);
	col = mix(col, rock_color * (0.85 + 0.3 * n1), rock_k * 0.85);
	// Weathered sediment seams break up the exposed steep faces without
	// replacing the glb's original vertex paint or imported scan textures.
	float strata = smoothstep(0.68, 0.94,
		0.5 + 0.5 * sin(v_world.y * 8.0 + n1 * 4.0 + n2 * 1.3));
	col = mix(col, col * vec3(0.69, 0.74, 0.78), strata * rock_k * 0.42);
	// Shallow wind ripples show on broad sand flats, fading away on grass/rock.
	float ripple = 0.97 + 0.03 * sin((v_world.x + v_world.z * 0.37) * 5.0 + n1 * 3.0);
	col *= mix(0.94 + 0.12 * n3, ripple * (0.96 + 0.08 * n2),
		(1.0 - rock_k) * (1.0 - clamp(v_paint.g - v_paint.r, 0.0, 1.0) * 0.65));
	// The painted inland surface must give way to exposed sandy approaches.
	float beach = (1.0 - smoothstep(0.75, 1.65, v_world.y - water_line))
		* (1.0 - smoothstep(0.55, 0.85, slope));
	col = mix(col, sand_tex * vec3(1.22,1.16,1.05), beach);

	// Wet look near the water line: smooth darkening + glossier surface.
	float band = 1.0 - smoothstep(0.0, wetness_fade, v_world.y - water_line);
	float depth_k = clamp((water_line - v_world.y) / max(wetness_depth, 0.01), 0.0, 1.0);
	float wet = clamp(band + depth_k, 0.0, 1.0) * (1.0 - rock_k * 0.4);
	col *= 1.0 - wet * 0.55;
	// Submerged ground gets a faint algae/biofilm tint so shallows read as
	// real underwater ground instead of painted mud.
	col = mix(col, col * vec3(0.55, 0.95, 0.65), clamp(depth_k * 0.8, 0.0, 0.5));

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.45, wet);
	// Subtle sparkle only on dry fine-grain peaks (sand shimmer).
	SPECULAR = 0.22 + wet * 0.12;
	AO = mix(0.75, 1.0, sand_properties.r);
	vec3 detail = texture(sand_normal, sand_uv).xyz * 2.0 - 1.0;
	vec3 wn = normalize(v_wnormal);
	vec3 mapped = normalize(wn + vec3(detail.x, 0.0, detail.y) * 0.28 * (1.0 - rock_k));
	NORMAL = normalize((VIEW_MATRIX * vec4(mapped, 0.0)).xyz);
}
