shader_type spatial;

// Photographic, mipmapped salvaged wood for joined rounded timbers and frames.
// Authored longitudinal UVs follow individual logs; legacy box pieces retain
// the original object-axis procedural fallback. Physics boxes never render.

uniform vec3 base_color : source_color = vec3(0.62, 0.43, 0.22);
uniform vec3 seam_color : source_color = vec3(0.30, 0.20, 0.11);
uniform float half_x = 1.0;    // local half-extents (meters) of this piece
uniform float half_y = 1.25;
uniform float half_z = 1.0;
uniform float plank_width = 0.25;  // width of one board in meters
uniform float seam_width = 0.006;  // width of the dark board seam in meters
uniform float grain_strength = 0.16;
uniform float tint_variation = 0.07;
uniform bool horizontal_boards = false;
uniform bool solid_timber = false;
uniform float moss_amount = 0.0;
uniform bool photographic_wood = false;
uniform bool authored_timber_uv = false;
uniform float atlas_strip = 0.0;
uniform float wood_darkening = 1.0;
uniform sampler2D wood_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 v_pos;    // object-space vertex position (meters, centered)
varying vec3 v_normal; // object-space face normal
// Per-instance randomness must not interpolate: tiny perspective rounding in
// the hash input otherwise moves the photographed grain between nearby pixels.
varying flat float piece_seed;

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
	piece_seed = INSTANCE_CUSTOM.r;
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
		along = horizontal_boards ? v_pos.x : v_pos.y;
		across = horizontal_boards ? v_pos.y + half_y : v_pos.x + half_x;
	} else {
		// Thin end face (or wall oriented along Z).
		along = v_pos.y;
		across = v_pos.z + half_z;
	}

	// Board seams: dark line at the start of every plank.
	float wp = across / plank_width;
	if (solid_timber) {
		float span = (an.y > an.x && an.y > an.z) ? half_z*2.0 : ((an.z >= an.x) ? (horizontal_boards ? half_y*2.0 : half_x*2.0) : half_z*2.0);
		wp = across/max(span,0.001);
	}
	float f = fract(wp);
	if (authored_timber_uv) {
		along = UV.x;
		f = fract(UV.y);
	}
	float edge_aa = max(fwidth(wp), 0.0002);
	float line_weight = 1.0 - smoothstep(0.0, seam_width / plank_width + edge_aa, min(f, 1.0-f));
	if (solid_timber) { line_weight = 0.0; }
	float board_id = floor(wp);
	if (authored_timber_uv) { board_id = floor(UV.x*0.01+UV.y); }

	// Subtle per-board brightness variation.
	float board_shade = 1.0 + tint_variation * (hash12(vec2(mod(board_id, 64.0)+piece_seed*67.0, 7.7)) - 0.5) * 2.0;

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
	if (photographic_wood) {
		// Four species share one mipmapped atlas. Sample inside strip margins
		// so lower mip levels never bleed adjacent species into the seams.
		vec2 timber_uv = vec2(along*0.45 + hash12(vec2(board_id+piece_seed*41.0,2.0))*0.8, (atlas_strip + 0.08 + f*0.80) * 0.25);
		// Ordinary mip sampling is stable on both Mobile and Forward+. Explicit
		// textureGrad produced severe grain speckling in the D3D12 Mobile preview.
		vec3 timber = texture(wood_texture,timber_uv,0.3).rgb * board_shade;
		albedo = mix(seam_color*0.65,timber,1.0-line_weight);
		grain = dot(timber,vec3(0.3,0.59,0.11));
		albedo *= (0.72 + piece_seed*0.12)*wood_darkening;
	}

	ALBEDO = albedo;
	// Moss gathers only in damp joints; seam darkening supplies baked-style AO
	// on Mobile where screen-space AO is unavailable.
	ALBEDO = mix(ALBEDO, vec3(0.16,0.22,0.09), moss_amount * line_weight * weather);
	AO = 1.0 - line_weight * 0.32;
	ROUGHNESS = 0.78 + grain * 0.16;
	SPECULAR = 0.18;
	if (photographic_wood) {
		float damp = smoothstep(0.72,0.9,vnoise(v_pos.xz*1.7+vec2(piece_seed*9.0,3.1)));
		ALBEDO *= mix(1.0,0.76,damp);
		ROUGHNESS = mix(0.88,0.52,damp);
		SPECULAR = mix(0.20,0.35,damp);
	}
	// Real rounded geometry supplies relief; retain its interpolated normals.
	// Screen derivative normal maps shimmer on the long grazing deck surfaces.
}
