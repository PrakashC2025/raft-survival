shader_type spatial;

// Procedural plank-wood for build pieces (roofs, walls, ...).
// Generates plank boards + long wood-grain streaks entirely in-shader from the
// piece's LOCAL axes (per-face, using the object-space normal), so every 2x2 /
// 2x2.5 box tiles cleanly with no texture files. Board seams align to the
// piece edges, matching the roof's physical seam strips.
//
// Per-face layout chosen by face normal:
//   horizontal faces (+Y/-Y): boards run along local X, stack along Z
//   vertical faces facing Z : boards run vertical (Y), stack along X
//   vertical faces facing X : boards run vertical (Y), stack along Z (thin)

uniform vec3 base_color : source_color = vec3(0.62, 0.43, 0.22);
uniform vec3 seam_color : source_color = vec3(0.30, 0.20, 0.11);
uniform float half_x = 1.0;    // local half-extents (meters) of this piece
uniform float half_y = 1.25;
uniform float half_z = 1.0;
uniform float plank_width = 0.25;  // width of one board in meters
uniform float seam_width = 0.006;  // width of the dark board seam in meters
uniform float grain_strength = 0.16;
uniform float tint_variation = 0.07;

varying vec3 v_pos;    // object-space vertex position (meters, centered)
varying vec3 v_normal; // object-space face normal

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_pos = VERTEX;
	v_normal = NORMAL;
}

void fragment() {
	vec3 an = abs(v_normal);
	float along = 0.0;  // meters along the board's length
	float across = 0.0; // meters across the board stack, 0 at the face edge
	if (an.y > an.x && an.y > an.z) {
		// Horizontal surface (roof/deck top, box top/bottom).
		along = v_pos.x;
		across = v_pos.z + half_z;
	} else if (an.z >= an.x) {
		// Wall face with its wide dimension along X.
		along = v_pos.y;
		across = v_pos.x + half_x;
	} else {
		// Thin end face (or wall oriented along Z).
		along = v_pos.y;
		across = v_pos.z + half_z;
	}

	// Board seams: dark line at the start of every plank.
	float wp = across / plank_width;
	float f = fract(wp);
	float edge_aa = max(fwidth(wp), 0.0002);
	float line_weight = 1.0 - smoothstep(0.0, seam_width / plank_width + edge_aa, min(f, 1.0-f));
	float board_id = floor(wp);

	// Subtle per-board brightness variation.
	float board_shade = 1.0 + tint_variation * (hash12(vec2(mod(board_id, 64.0), 7.7)) - 0.5) * 2.0;

	// Wood grain: long streaks along the board, tight variation across it.
	float streak = vnoise(vec2(along * 0.8, across * 80.0));
	float streak2 = vnoise(vec2(along * 2.4 + 17.0, across * 40.0));
	float grain = mix(streak, streak2, 0.5);
	// Broad tonal wave so planks don't read as flat stripes.
	grain += 0.35 * vnoise(vec2(along * 0.35, floor(across / plank_width) * 3.1 + 5.0));

	float shade = board_shade * (1.0 + grain_strength * (grain - 0.5) * 2.0);
	vec3 albedo = base_color * shade;
	// Subtle knot rings and weather bleaching.
	float knot_x = (hash12(vec2(board_id, 19.0)) - 0.5) * 1.3;
	float knot_radius = length(vec2((along - knot_x) * 1.8, (f - 0.5) * 0.8));
	float knot = (sin(knot_radius * 65.0 + grain * 2.0) * 0.5 + 0.5) * (1.0 - smoothstep(0.02, 0.18, knot_radius));
	albedo *= 1.0 - knot * 0.18;
	float weather = vnoise(vec2(along * 1.5, across * 3.0));
	albedo = mix(albedo, vec3(dot(albedo, vec3(0.30,0.59,0.11))), weather * 0.16);
	albedo = mix(seam_color, albedo, 1.0 - line_weight);

	ALBEDO = albedo;
	ROUGHNESS = 0.78 + grain * 0.16;
	SPECULAR = 0.25;
	float relief = grain - line_weight * 0.8;
	NORMAL_MAP = normalize(vec3(-dFdx(relief) * 0.4, -dFdy(relief) * 0.4, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
}
