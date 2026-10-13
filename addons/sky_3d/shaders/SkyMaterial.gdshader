// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type sky;
render_mode use_debanding;
uniform bool fast_radiance_enabled = false;

group_uniforms general;
uniform bool sky_visible = true;
uniform vec2 color_correction = vec2(0.0, 1.0);
uniform vec4 ground_color: source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float horizon_offset = 0.0;

// Original sunset panorama blended by the existing celestial clock.
// A single filtered sky sample retains detailed cloud rims on phone profiles.
group_uniforms evening;
uniform sampler2D evening_panorama: source_color, filter_linear_mipmap, repeat_enable;
uniform float evening_blend: hint_range(0.0, 1.0) = 0.0;
uniform float evening_rotation = 0.0;
uniform vec2 panorama_cloud_position = vec2(0.0);

group_uniforms calm_night;
uniform bool calm_night_enabled = false;
uniform sampler2D night_clouds: source_color, filter_linear_mipmap, repeat_enable;
uniform float night_cloud_opacity: hint_range(0.0, 1.0) = 0.35;
uniform float night_cloud_coverage: hint_range(0.0, 1.0) = 0.35;

group_uniforms reference_day;
uniform sampler2D morning_panorama: source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D afternoon_panorama: source_color, filter_linear_mipmap, repeat_enable;
uniform float daylight_panorama_blend: hint_range(0.0, 1.0) = 0.0;
uniform float morning_panorama_blend: hint_range(0.0, 1.0) = 0.0;

group_uniforms atmosphere;
uniform float atm_darkness = 0.5;
uniform float atm_sun_intensity = 18.0;
uniform vec4 atm_day_tint: source_color = vec4(0.808, 0.91, 1.0, 1.0);
uniform vec4 atm_horizon_light_tint: source_color = vec4(0.98, 0.635, 0.463, 1.0);
uniform vec4 atm_night_tint: source_color = vec4 (0.041, 0.049, 0.061, 0.245);
uniform vec3 atm_level_params = vec3(1.0, 0.0, 0.0);
uniform float atm_thickness = 0.7;
uniform vec3 atm_beta_ray = vec3(0.00001, 0.00001, 0.00003);
uniform vec3 atm_beta_mie = vec3(0.00000003038); // Value computed by multiplying Mie, turbidity, and 0.000434.

group_uniforms sun_disk;
uniform vec4 sun_light_color: source_color = vec4(1.0);
uniform vec4 sun_disk_color: source_color = vec4(0.996, 0.541, 0.14, 1.0);
uniform float sun_disk_intensity = 2.0;
uniform float sun_disk_size = 0.015;

group_uniforms sun_mie;
uniform vec4 atm_sun_mie_tint: source_color = vec4(1.0);
uniform float atm_sun_mie_intensity = 1.0;
uniform vec3 atm_sun_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms moon;
uniform vec4 moon_color: source_color = vec4(1.0);
uniform float moon_intensity = 1.0;
uniform float moon_glow_intensity = 1.0;
uniform sampler2D moon_texture: source_color, repeat_disable;
uniform vec3 moon_texture_alignment = vec3(7.0, 1.4, 4.8);
uniform bool moon_texture_flip_u;
uniform bool moon_texture_flip_v;
uniform float moon_size = 0.07;
// Project night presentation is driven by the existing celestial clock.
uniform float night_moon_visibility = 1.0;

group_uniforms moon_mie;
uniform vec4 atm_moon_mie_tint: source_color = vec4(0.137, 0.184, 0.292, 1.0);
uniform float atm_moon_mie_intensity = 0.17152;
uniform vec3 atm_moon_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms star_map;
uniform vec4 starmap_color: source_color = vec4(0.71, 0.71, 0.71, 0.855);
uniform sampler2D starmap_texture: source_color;
uniform bool starmap_flip_u = false;
uniform bool starmap_flip_v = false;
uniform vec3 starmap_alignment = vec3(2.68288, -0.25891, 0.40101);
uniform float star_rotation_offset = 9.38899;
uniform float star_rotation = 0.0; // For simulating Earth rotation.
uniform float star_tilt = 0.0; // For tilting the sky according to observer latitude in radians. (90° - latitude)

group_uniforms star_field;
uniform vec4 star_field_color: source_color = vec4(1.0);
uniform sampler2D star_field_texture: source_color;
uniform float star_scintillation = 0.75;
uniform float star_scintillation_speed = 0.01;
uniform sampler2D noise_tex: source_color;
uniform bool shooting_stars_enabled = true;
// Negative uses normal shader time. Isolated previews can freeze a streak.
uniform float shooting_star_preview_time = -1.0;

/* Sky alignment values for a star map that is in galactic coordinates. Works for most star maps.
X: 2.6555
Y: -0.23935
Z: 0.4505

These alignment values are consistent with a sky view from the North Pole (latitude zero)
at midnight. The positions of Polaris, Vega, Rigel, and Alpha Centauri confirmed
through various sources and calculations.
*/

group_uniforms clouds;
uniform vec4 clouds_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);

group_uniforms cirrus_clouds;
uniform bool cirrus_visible = true;
uniform float cirrus_intensity = 2.0;
uniform float cirrus_coverage = 0.5;
uniform float cirrus_thickness = 10.0;
uniform float cirrus_absorption = 2.0;
uniform float cirrus_sky_tint_fade = 0.5;
uniform float cirrus_size = 1.0;
uniform vec2 cirrus_uv = vec2(0.16, 0.11);
uniform vec2 cirrus_position1 = vec2(0.0);
uniform vec2 cirrus_position2 = vec2(0.0);
uniform sampler2D cirrus_texture;

group_uniforms cumulus_clouds;
uniform bool cumulus_visible = true;
uniform float cumulus_intensity = 0.6;
uniform float cumulus_coverage = 0.55;
uniform float cumulus_thickness = 0.0243;
uniform float cumulus_absorption = 2.0;
uniform float cumulus_noise_freq = 2.7;
uniform float cumulus_sky_tint_fade = 0.0;
uniform float cumulus_size = 0.5;
uniform vec2 cumulus_position = vec2(0.0);
uniform sampler2D cumulus_texture;
uniform vec3 cumulus_partial_mie_phase = vec3(0.95756, 1.04244, 0.412);
uniform float cumulus_mie_intensity = 1.0;

group_uniforms overlays;
uniform bool show_azimuthal_grid = false;
uniform vec4 azimuthal_grid_color : source_color = vec4(.871, .722, .529, 1.);
uniform float azimuthal_grid_rotation_offset = 0.03;
uniform bool show_equatorial_grid = false;
uniform vec4 equatorial_grid_color : source_color = vec4(0., .75, 1., 1.);
uniform float equatorial_grid_rotation_offset = 0.03;

group_uniforms transform_matrices;
uniform mat3 moon_matrix; // Calculated externally via GDScript.

#include "Common.gdshaderinc"

// Provides a transformation matrix when passed a vec3.
mat3 create_rotation_matrix(vec3 r) {
	float c1 = cos(r.x), s1 = sin(r.x);
	float c2 = cos(r.y), s2 = sin(r.y);
	float c3 = cos(r.z), s3 = sin(r.z);

	mat3 rotX = mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, c1, -s1),
		vec3(0.0, s1, c1)
	);

	mat3 rotY = mat3(
		vec3(c2, 0.0, s2),
		vec3(0.0, 1.0, 0.0),
		vec3(-s2, 0.0, c2)
	);

	mat3 rotZ = mat3(
		vec3(c3, -s3, 0.0),
		vec3(s3, c3, 0.0),
		vec3(0.0, 0.0, 1.0)
	);

	return rotZ * rotY * rotX; // Combine rotations in ZYX order
}

vec2 calc_equirect_uv(vec3 norm) {
	float flipu = starmap_flip_u ? -1.0 : 1.0;
	float flipv = starmap_flip_v ? -1.0 : 1.0;
	float u = flipu * ((atan(norm.y, norm.x) + PI) * INV_TAU); // 0 to 1 horizontally
	float v = -flipv * (acos(norm.z) * INV_PI); // 0 (north pole) to 1 (south pole)
	return vec2(u, v);
}

vec3 sample_moon_texture(vec3 dir) {
	dir = moon_matrix * dir * create_rotation_matrix(moon_texture_alignment);
	dir.x = -dir.x;
	dir.z = -dir.z;
	float flipu = moon_texture_flip_u ? 1.0 : -1.0;
	float flipv = moon_texture_flip_v ? 1.0 : -1.0;
	float u = 0.5 + flipu * atan(dir.z, dir.x) * INV_TAU; // Longitude
	float v = 0.5 + flipv * asin(dir.y) * INV_PI; // Latitude
	return texture(moon_texture, vec2(u, v)).rgb;
}

float calc_disk_mask(vec3 norm, vec3 coords, lowp float size) {
	float dist = length(norm - coords);
	return 1.0 - step(size, dist);
}

float map_range(float value, float from_min, float from_max, float to_min, float to_max) {
	return to_min + (value - from_min) * (to_max - to_min) / (from_max - from_min);
}

bool ray_sphere_intersect(float r, vec3 origin, vec3 dir, out float t, out vec3 nrm) {
	origin += vec3(0.0, 450.0, 0.0);
	float a = dot(dir, dir);
	float b = 2.0 * dot(origin, dir);
	float c = dot(origin, origin) - r * r;
	float d = b * b - 4.0 * a * c;
	float valid = step(0.0, d); // 1.0 if d >= 0.0, else 0.0
	d = sqrt(max(d, 0.0)); // Prevent sqrt of negative numbers
	a *= 2.0;
	float t1 = 0.5 * (-b + d);
	float t2 = 0.5 * (-b - d);
	float t_min = min(t1, t2); // Select the smallest intersection
	t = mix(t2, t1, step(t2, t1) * step(0.0, t1)); // Use t1 if t2 < t1 and t1 >= 0, else t2
	t = mix(0.0, t, step(0.0, t) * valid); // Invalidate if t < 0 or d < 0
	nrm = mix(vec3(0.0), origin + t * dir, step(0.0, t) * valid); // Set nrm only if valid
	return bool(step(0.0, t) * valid);
}

// For rendering the moon. This function courtesy of Kelvin van Hoorn.
// https://kelvinvanhoorn.com/2024/12/07/skybox-tutorial-godot/
float simple_sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius) {
	vec3 oc = -sphere_pos;
	float b = dot(oc, ray_dir);
	float c = dot(oc, oc) - radius * radius;
	float h = b * b - c;
	float valid = step(0.0, h); // 1.0 if h >= 0.0, else 0.0
	h = sqrt(max(h, 0.0)); // Ensure sqrt is non-negative
	return mix(-1.0, -b - h, valid);
}

// Atmosphere
//------------------------------------------------------------------------------

vec3 calc_atmospheric_scatter(float sr, float sm, vec2 mu, vec3 mult) {
	vec3 beta_mie = atm_beta_mie;
	vec3 beta_ray = atm_beta_ray * atm_thickness;

	vec3 extc_factor = clamp_rgb_to_unit(exp(-(beta_ray * sr + beta_mie * sm)));

	float extc_ff = mix(clamp_to_unit(atm_thickness * 0.5), 1.0, mult.x);
	vec3 final_extc_factor = mix(1.0 - extc_factor, (1.0 - extc_factor) * extc_factor, extc_ff);
	float rayleigh_phase = calc_rayleigh_phase(mu.x);
	vec3 BRT = beta_ray * rayleigh_phase;
	vec3 BMT = beta_mie * calc_mie_phase(mu.x, atm_sun_partial_mie_phase);
	BMT *= atm_sun_mie_intensity * atm_sun_mie_tint.rgb;

	vec3 BRMT = (BRT + BMT) / (beta_ray + beta_mie);
	vec3 scatter = atm_sun_intensity * (BRMT * final_extc_factor) * atm_day_tint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extc_factor), atm_darkness);

	vec3 lcol =  mix(atm_day_tint.rgb, atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extc_factor) * atm_night_tint.rgb;
	nscatter += calc_mie_phase(mu.y, atm_moon_partial_mie_phase) *
		atm_moon_mie_tint.rgb * atm_moon_mie_intensity * 0.005;

	return (scatter * lcol) + nscatter;
}

// Clouds
//------------------------------------------------------------------------------
const int CUMULUS_STEP = 10;

float sample_cirrus_noise(vec2 coords) {
	float a = textureLod(cirrus_texture, coords.xy * cirrus_uv + cirrus_position1, 0.0).r;
	float b = textureLod(cirrus_texture, coords.xy * cirrus_uv + cirrus_position2, 0.0).r;
	return ((a + b) * 0.5);
}

float sample_cumulus_noise(vec3 p) {
	vec3 pos = vec3(p * 0.01);
	pos.z *= 256.0;
	vec2 offset = vec2(0.317, 0.123);
	vec4 uv = vec4(0.0);
	uv.xy = pos.xy + offset * floor(pos.z);
	uv.zw = uv.xy + offset;
	float x1 = textureLod(cumulus_texture, uv.xy, 0.0).r;
	float x2 = textureLod(cumulus_texture, uv.zw, 0.0).r;
	return mix(x1, x2, fract(pos.z));
}

float calc_cumulus_fbm(vec3 p, float l) {
	float ret;
	ret = 0.51749673 * sample_cumulus_noise(p);
	p *= l;
	ret += 0.25584929 * sample_cumulus_noise(p);
	p *= l;
	ret += 0.12527603 * sample_cumulus_noise(p);
	p *= l;
	ret += 0.06255931 * sample_cumulus_noise(p);
	return ret;
}

float calc_cirrus_density(vec2 p) {
	float d = sample_cirrus_noise(p);
	float c = 1.0 - cirrus_coverage;
	d = d - c;
	return clamp_to_unit(d);
}

float calc_cumulus_density(vec3 p, vec3 offset, float t) {
	vec3 pos = p * 0.0212242 - offset;
	float dens = calc_cumulus_fbm(pos, cumulus_noise_freq);
	dens += dens;

	float cov = 1.0 - cumulus_coverage;
	cov = smoothstep(0.00, (cov * 3.5) + t, dens);
	dens *= cov;
	dens = map_range(dens, 1.0 - cov, 1.0, 0.0, 1.0);

	return clamp_to_unit(dens);
}

vec4 render_cirrus_clouds(vec3 pos) {
	pos.xy = pos.xz / pos.y;
	pos *= cirrus_size;
	float density = calc_cirrus_density(pos.xy);
	float sh = clamp_to_unit(exp(-cirrus_absorption * density));
	float a = clamp_to_unit(density * cirrus_thickness);
	return vec4(vec3(density*sh) * cirrus_intensity, a);
}

vec4 render_cumulus_clouds(vec3 ro, vec3 rd, float am, vec3 sun_pos, vec3 moon_pos) {
	vec4 ret = vec4(0.);
	vec3 wind = -vec3(cumulus_position.x, 0.0, cumulus_position.y);
	float a = 0.0;

	// n and tt doesnt need to be initialized since it would be set by ray_sphere_intersect
	vec3 n; float tt;
	if (ray_sphere_intersect(500., ro, rd, tt, n)) {
		float march_step = float(CUMULUS_STEP) * cumulus_thickness;
		// Bound grazing rays so the horizon does not develop marching bands.
		vec3 dir_step = rd / max(rd.y, 0.08) * march_step;
		vec3 pos = n * cumulus_size;

		vec2 mu = vec2(dot(sun_pos, rd), dot(moon_pos, rd));
		vec3 mph = ((calc_mie_phase(mu.x, cumulus_partial_mie_phase) * atm_sun_mie_tint.rgb) +
			calc_mie_phase(mu.y, cumulus_partial_mie_phase) * am);

		vec4 t = vec4(1.0);
		t.rgb += (mph.rgb * cumulus_mie_intensity);

		for(int i = 0; i < CUMULUS_STEP; i++) {
			float h = float(i) * 0.1; // / float(kCLOUDS_STEP);
			float density = calc_cumulus_density(pos, wind, h);
			float sh = clamp_to_unit(exp(-cumulus_absorption * density * march_step));
			t *= sh;
			ret += (t * (exp(h) * 0.571428571) * density * march_step);
			a += (1.0 - sh) * (1.0 - a);
			pos += dir_step;
		}
		return vec4(ret.rgb * cumulus_intensity, a);
	}
	return vec4(ret.rgb * cumulus_intensity, a);
}

// Main
//------------------------------------------------------------------------------

float night_star_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 sparse_night_stars(vec2 uv, float sky_time) {
	// A few tiny, steady points instead of either dense galaxy photograph.
	vec2 grid = fract(uv) * vec2(180.0, 90.0);
	vec2 cell = floor(grid);
	float seed = night_star_hash(cell);
	vec2 centre = 0.15 + vec2(night_star_hash(cell + 7.3), night_star_hash(cell + 23.1)) * 0.7;
	float distance_to_star = length(fract(grid) - centre);
	float aa = max(length(fwidth(grid)) * 0.5, 0.004);
	float point = 1.0 - smoothstep(0.035 - aa, 0.035 + aa, distance_to_star);
	float twinkle = 0.94 + 0.06 * sin(sky_time * 0.35 + seed * TAU);
	return vec3(0.40, 0.44, 0.50) * point * step(0.983, seed) * twinkle;
}

vec3 shooting_stars(vec3 direction, float sky_time) {
	vec3 light = vec3(0.0);
	if (!shooting_stars_enabled || night_moon_visibility < 0.01) {
		return light;
	}
	// A rare brief meteor roughly every ninety seconds keeps nights calm.
	// Inactive events skip the trail math; no emitters or extra sky pass.
	for (int meteor = 0; meteor < 2; meteor++) {
		float event_time = sky_time + float(meteor) * 90.0;
		float event_index = floor(event_time / 180.0);
		float age = mod(event_time, 180.0);
		if (age > 1.35) {
			continue;
		}
		float seed = event_index * 7.13 + float(meteor) * 19.7;
		float azimuth = fract(sin(seed * 1.71) * 43758.5453) * TAU;
		vec3 start = normalize(vec3(-0.65, 0.70, -0.50));
		start = create_rotation_matrix(vec3(0.0, azimuth, 0.0)) * start;
		vec3 tangent = normalize(cross(start, vec3(0.0, 1.0, 0.0)) * 0.9 - (vec3(0.0, 1.0, 0.0) - start * start.y) * 0.45);
		vec3 side = normalize(cross(start, tangent));
		float along = atan(dot(direction, tangent), dot(direction, start));
		float across = asin(clamp(dot(direction, side), -1.0, 1.0));
		float head = age * 0.31;
		float behind = head - along;
		float width = max(fwidth(across), 0.00065);
		float trail = (1.0 - smoothstep(width * 0.5, width * 1.7, abs(across))) * exp(-max(behind, 0.0) * 27.0);
		trail *= step(0.0, behind) * (1.0 - smoothstep(0.12, 0.19, behind));
		float glow = exp2(-pow((along - head) / (width * 2.2), 2.0) - pow(across / (width * 2.2), 2.0));
		float fade = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.95, 1.35, age));
		light += (vec3(0.68, 0.83, 1.0) * trail * 1.7 + vec3(1.0, 0.95, 0.84) * glow * 3.0) * fade;
	}
	return light;
}

vec3 render_sky(vec3 world_pos, vec3 clouds_pos, vec3 sun_pos, vec3 moon_pos, float p_time) {
	vec3 col = vec3(0.0);

	vec4 angle_mult;
	angle_mult.x = clamp_to_unit(1.0 - sun_pos.y);
	angle_mult.y = clamp_to_unit(sun_pos.y + 0.45);
	angle_mult.z = clamp_to_unit(-sun_pos.y + 0.30);
	angle_mult.w = clamp_to_unit(-sun_pos.y + 0.60);

	// Atmosphere
	vec2 mu = vec2(dot(sun_pos, world_pos), dot(moon_pos, world_pos));
	float sr, sm;
	calc_simple_optical_depth(world_pos.y + atm_level_params.z - horizon_offset, sr, sm, atm_level_params.xy);

	world_pos.y -= horizon_offset;
	float horizonBlend = clamp_to_unit((world_pos.y - 0.03) * 3.0);
	float horizonBlendCumulus = clamp_to_unit((world_pos.y + 0.01) * 50.0);

	vec3 scatter = calc_atmospheric_scatter(sr, sm, mu.xy, angle_mult.xyz);
	col.rgb += scatter.rgb;
	// Minimum night glow (project addition): once the sun is well below the
	// horizon the sky keeps a faint deep-blue ambient so dusk/night never
	// read as a pure black void and the horizon stays visible.
	float night_lift = 1.0 - smoothstep(-0.30, -0.02, sun_pos.y);
	col.rgb += vec3(0.016, 0.024, 0.055) * night_lift;

	if (daylight_panorama_blend > 0.001) {
		vec2 day_uv = vec2(fract(0.5 + atan(world_pos.z, world_pos.x) * INV_TAU + evening_rotation + panorama_cloud_position.x * 0.045), acos(clamp(world_pos.y, -1.0, 1.0)) * INV_PI);
		vec3 day_photo = texture(afternoon_panorama, day_uv).rgb;
		if (morning_panorama_blend > 0.001) {
			day_photo = mix(day_photo, texture(morning_panorama, day_uv).rgb, morning_panorama_blend);
		}
		float edge = min(day_uv.x, 1.0 - day_uv.x);
		if (edge < 0.018) {
			vec2 other_uv = vec2(1.0 - day_uv.x, day_uv.y);
			vec3 other_edge = texture(afternoon_panorama, other_uv).rgb;
			if (morning_panorama_blend > 0.001) {
				other_edge = mix(other_edge, texture(morning_panorama, other_uv).rgb, morning_panorama_blend);
			}
			day_photo = mix(day_photo, other_edge, 0.5 * (1.0 - smoothstep(0.0, 0.018, edge)));
		}
		col = mix(col, day_photo, daylight_panorama_blend * smoothstep(-0.1, 0.015, world_pos.y));
	}

	// Sun remains live, independent of all cloud photographs.
	vec3 sun_disk = calc_disk_mask(world_pos, sun_pos, sun_disk_size) * sun_disk_color.rgb * scatter.rgb;
	sun_disk *= sun_disk_intensity;

	// Moon
	float moon_intersect = simple_sphere_intersect(world_pos, moon_pos, moon_size);
	float moon_edge = length(cross(world_pos, moon_pos));
	float moon_aa = max(fwidth(moon_edge), 0.00015);
	float moon_mask = (1.0 - smoothstep(moon_size - moon_aa, moon_size + moon_aa, moon_edge)) * step(0.0, dot(world_pos, moon_pos));
	vec3 moon_normal = normalize(world_pos * moon_intersect - moon_pos);

	float moon_ndotl = clamp(dot(moon_normal, sun_pos), 0.0, 1.0);
	if (calm_night_enabled) {
		// The requested bright full moon retains crater detail and soft limbs.
		float limb = sqrt(max(0.0, 1.0 - pow(clamp(moon_edge / moon_size, 0.0, 1.0), 2.0)));
		moon_ndotl = mix(moon_ndotl, 0.45 + limb * 0.55, night_moon_visibility);
	}
	vec3 moon_tex = sample_moon_texture(moon_normal);
	vec3 moon_output = moon_mask * moon_ndotl * exp2(1.0) * moon_tex * moon_color.rgb;
	moon_output *= moon_intensity;
	// Soft luminous halo around the moon so it reads as a bright, attractive
	// disc against the night sky (added uniformly by the project for feel).
	float moon_ang = max(0.0, 1.0 - dot(moon_pos, world_pos));
	float halo = exp2(-moon_ang / max(moon_size * moon_size * 3.0, 1e-4));
	moon_output += moon_color.rgb * (moon_intensity * moon_glow_intensity) * halo * 0.1 * (1.0 - moon_mask);
	moon_output *= night_moon_visibility;
	// Thin the sky clouds around the moon, keeping its surface readable on
	// all profiles without a second pass, fog or extra particle effects.
	float night_cloud_visibility = mix(1.0, 0.72, night_moon_visibility) * (1.0 - halo * night_moon_visibility * 0.95);
	float moonMask = (1.0 - moon_mask);

	// Deep space

	// Tilt the sky along the X-axis.
	mat3 tilt = create_rotation_matrix(vec3(star_tilt, 0.0, 0.0));

	// Rotation around Y-axis. For simulating Earth's rotation.
	mat3 rotation = create_rotation_matrix(vec3(0.0, star_rotation + star_rotation_offset, 0.0));

	// Initial XYZ rotation for alignment.
	mat3 alignment_xyz = create_rotation_matrix(starmap_alignment);

	// Combine everything together to get the desired alignment.
	vec3 final_alignment = normalize(alignment_xyz * rotation * tilt * world_pos);

	// Now generate UV coordinates for the texture.
	vec2 deep_space_uv = calc_equirect_uv(normalize(final_alignment));

	float calm_night = calm_night_enabled ? night_moon_visibility : 0.0;
	vec2 night_uv = vec2(fract(0.5 + atan(world_pos.z, world_pos.x) * INV_TAU + 0.18), acos(clamp(world_pos.y, -1.0, 1.0)) * INV_PI);
	vec3 deep_space;
	if (calm_night_enabled) {
		// Soft navy with a slightly lighter sea horizon; no Milky Way layer.
		vec3 navy = mix(vec3(0.014, 0.024, 0.045), vec3(0.004, 0.009, 0.021), smoothstep(0.0, 0.85, world_pos.y));
		col = mix(col, navy, calm_night);
		deep_space = sparse_night_stars(deep_space_uv, p_time) * calm_night * moonMask;
	} else {
		// Preserve the addon's original star presentation for other users.
		vec3 background = textureLod(starmap_texture, deep_space_uv, 0.0).rgb * starmap_color.rgb;
		background = adjust_contrast(background, starmap_color.a);
		float scint = textureLod(noise_tex, deep_space_uv + p_time * star_scintillation_speed, 0.0).r;
		scint = mix(1.0, scint * 1.5, star_scintillation);
		vec3 field = textureLod(star_field_texture, deep_space_uv, 0.0).rgb * star_field_color.rgb;
		field = clamp_rgb_to_unit(mix(field, field * scint, star_scintillation));
		deep_space = (background + field * 1.5) * moonMask * angle_mult.z;
	}
	col.rgb += sun_disk.rgb + deep_space.rgb * horizonBlend;
	// The star field fades near the horizon; the moon keeps its full disc.
	col.rgb += moon_output * smoothstep(0.02, 0.10, world_pos.y);
	float meteor_time = shooting_star_preview_time < 0.0 ? p_time : shooting_star_preview_time;
	col.rgb += shooting_stars(world_pos, meteor_time) * night_moon_visibility * horizonBlend;

	// Clouds
	float procedural_clouds = (1.0 - calm_night) * (1.0 - daylight_panorama_blend);
	if (cirrus_visible && procedural_clouds > 0.001) {
		vec4 cirrus_clouds = render_cirrus_clouds(clouds_pos);
		cirrus_clouds.a = clamp_to_unit(cirrus_clouds.a) * night_cloud_visibility * procedural_clouds;
		vec3 cloud_tint = sun_light_color.rgb;
		cloud_tint = mix(cloud_tint, clouds_night_color.rgb, angle_mult.w);
		cirrus_clouds.rgb *= cloud_tint * cirrus_intensity;
		cirrus_clouds.a = mix(0.0, cirrus_clouds.a, horizonBlend);
		col.rgb = mix(col.rgb, cirrus_clouds.rgb + mix(vec3(0.0), scatter, cirrus_sky_tint_fade), cirrus_clouds.a);
	}

	if (cumulus_visible && procedural_clouds > 0.001) {
		vec4 cumulus_clouds = render_cumulus_clouds(vec3(0.0), clouds_pos, angle_mult.z, sun_pos, moon_pos);
		cumulus_clouds.a = clamp_to_unit(cumulus_clouds.a) * night_cloud_visibility * procedural_clouds;
		vec3 cloud_tint = sun_light_color.rgb;
		cloud_tint = mix(cloud_tint, clouds_night_color.rgb, angle_mult.w);
		cumulus_clouds.rgb *= cloud_tint * cumulus_intensity;
		// Low cumulus remains visible near the sea horizon. The cirrus fade
		// above erases almost all cloud volume in a normal gameplay view.
		cumulus_clouds.a = mix(0.0, cumulus_clouds.a, horizonBlendCumulus);
		col.rgb = mix(col.rgb, cumulus_clouds.rgb + mix(vec3(0.0), scatter, cumulus_sky_tint_fade), cumulus_clouds.a);
	} else if (cirrus_visible && world_pos.y > 0.0 && procedural_clouds > 0.001) {
		// Two filtered samples retain soft low clouds on phone profiles without
		// the volumetric march. This is sky colour only, never screen fog.
		vec2 uv = world_pos.xz / max(world_pos.y + 0.22,0.22);
		float broad = texture(cirrus_texture,uv*0.12+cirrus_position1*0.35).r;
		float detail = texture(cirrus_texture,uv*0.31+cirrus_position2*0.55).r;
		float threshold=mix(0.67,0.30,cumulus_coverage);
		float density = smoothstep(threshold,threshold+0.23,broad*0.76+detail*0.24);
		vec3 tint = mix(vec3(0.62,0.66,0.69),vec3(0.018,0.028,0.05),angle_mult.w);
		tint = mix(tint,scatter,0.35);
		col.rgb = mix(col.rgb,tint,density*0.56*horizonBlendCumulus*night_cloud_visibility*procedural_clouds);
	}
	if (calm_night > 0.001 && world_pos.y > 0.0) {
		// Soft moonlit clouds drift independently over the simple navy sky.
		vec2 cloud_uv = vec2(fract(night_uv.x + panorama_cloud_position.x * 0.030), night_uv.y);
		vec4 cloud_layer = texture(night_clouds, cloud_uv);
		float edge = min(cloud_uv.x, 1.0 - cloud_uv.x);
		if (edge < 0.018) {
			cloud_layer = mix(cloud_layer, texture(night_clouds, vec2(1.0 - cloud_uv.x, cloud_uv.y)),
				0.5 * (1.0 - smoothstep(0.0, 0.018, edge)));
		}
		vec3 cloud_light = cloud_layer.rgb * mix(0.28, 0.65, pow(max(dot(world_pos, moon_pos), 0.0), 4.0));
		// Thin the photograph into a few feathered patches, keeping most sky
		// clear. The coverage mask travels with the same cloud wind offset.
		float cloud_noise = texture(cirrus_texture, fract(cloud_uv * vec2(4.0, 2.0))).r;
		float cloud_threshold = mix(0.78, 0.28, night_cloud_coverage);
		float sparse_clouds = smoothstep(cloud_threshold, cloud_threshold + 0.20, cloud_noise);
		float opacity = cloud_layer.a * sparse_clouds * calm_night * horizonBlendCumulus * (1.0 - halo * 0.85);
		col = mix(col, cloud_light, opacity * night_cloud_opacity);
	}

	col.rgb = mix(col.rgb, ground_color.rgb * scatter, clamp_to_unit((-world_pos.y - atm_level_params.z) * 100.0));
	col.rgb = apply_photo_tonemap(col.rgb, color_correction.y, color_correction.x);
	return col;
}

vec4 create_axis_angle_quat(vec3 axis, float angle) {
	float s = sin(angle * 0.5);
	return vec4(axis * s, cos(angle * 0.5));
}

vec3 rotate_vector_by_quat(vec3 v, vec4 q) {
	vec3 t = 2.0 * cross(q.xyz, v);
	return v + q.w * t + cross(q.xyz, t);
}

vec3 align_and_rotate_vector(vec3 dir, vec3 target, float rotation_angle) {
	vec3 z_axis = vec3(0.0, 0.0, 1.0); // Original grid alignment

	// First, align Z-axis with target (Polaris)
	target = normalize(target);
	vec3 axis = cross(z_axis, target);
	float angle = acos(dot(z_axis, target));
	float valid = step(0.0001, length(axis)); // 1.0 if length(axis) >= 0.0001
	axis = normalize(axis);
	vec4 align_quat = create_axis_angle_quat(axis, angle);
	dir = mix(dir, rotate_vector_by_quat(dir, align_quat), valid);
	vec4 rot_quat = create_axis_angle_quat(vec3(0.0, 0.0, 1.0), rotation_angle);
	dir = mix(dir, rotate_vector_by_quat(dir, rot_quat), valid);
	return dir;
}

void render_grid(vec3 dir, vec3 pole_dir, float rotation_angle, vec4 line_color, float grid_spacing, float line_thickness, inout vec3 color) {
	float spacing = max(grid_spacing, 0.001);
	float thickness = max(line_thickness, 0.0001);

	// Rotate dir with sidereal motion and align with pole_dir
	dir = align_and_rotate_vector(dir, pole_dir, rotation_angle);

	// Latitude / Circles / Theta Spherical coordinates
	float theta = acos(dir.z);
	float theta_deriv = fwidth(theta);
	float circle_thickness = max(thickness, theta_deriv);
	float circle = mod(theta, spacing);
	float circle_line = 1.0 - smoothstep(0.0, circle_thickness * 1.5, abs(circle - circle_thickness * 0.5));
	circle_line *= clamp_to_unit(thickness / circle_thickness);

	// Add poles
	float pole_thickness = circle_thickness;
	float north_pole = 1.0 - smoothstep(0.0, pole_thickness, theta);
	float south_pole = 1.0 - smoothstep(0.0, pole_thickness, abs(theta - PI));
	circle_line = max(circle_line, max(north_pole, south_pole));

	// Darken Lat at poles
	float circle_adjust = sin(theta);
	circle_line *= clamp(circle_adjust, 0.2, 1.0);

	// Longitude / Radial lines / Phi Spherical coordinates
	float phi = atan(dir.y, dir.x);
	float phi_deriv = fwidth(phi);
	float radial_thickness = max(thickness, phi_deriv);
	float radial = mod(phi + PI, spacing); // PI w/ less precision to remove moire
	float radial_line = 1.0 - smoothstep(0.0, radial_thickness * 1.5, abs(radial - radial_thickness));
	radial_line *= clamp_to_unit(thickness / radial_thickness);

	float grid = max(radial_line, circle_line);
	color += line_color.rgb * line_color.a * grid;
}

void sky() {
	if (AT_CUBEMAP_PASS && fast_radiance_enabled) {
		// Ambient/reflection maps need broad sky light, not stars, moon textures
		// and a second cloud march across all six faces every moving-cloud frame.
		// The moon may take directional-light slot zero at night.
		float daylight = 1.0-clamp(night_moon_visibility,0.0,1.0);
		float elevation = smoothstep(0.0,0.80,EYEDIR.y);
		vec3 day = mix(vec3(0.58,0.72,0.88),vec3(0.22,0.45,0.76),elevation) * atm_day_tint.rgb;
		vec3 night = mix(vec3(0.016,0.028,0.052),vec3(0.005,0.011,0.024),elevation);
		vec3 light = mix(night,day,daylight);
		float dusk = (1.0-smoothstep(0.0,0.32,abs(LIGHT0_DIRECTION.y))) * (1.0-elevation);
		light = mix(light,atm_horizon_light_tint.rgb * 0.45,dusk * 0.35);
		COLOR = mix(light,ground_color.rgb * light * 0.5,smoothstep(0.0,0.12,-EYEDIR.y));
	} else {
	float current_time = TIME;
	vec3 col = vec3(0.0); // Set up the initial sky color which will be added to later to produce the final result.
	vec3 world_pos = EYEDIR; // Original shader set this up in the vertex() function. For sky shaders the overall equivalent is EYEDIR.
	vec3 clouds_pos = EYEDIR; // The same is used for cloud rendering.
	vec3 sun_pos = LIGHT0_DIRECTION; // Redefined from now-deprecated _sun_direction.
	// The moon must not depend on the directional-light slot: when its light
	// has zero energy, another light can occupy that slot on Mobile.
	vec3 moon_pos = normalize(transpose(moon_matrix) * vec3(0.0, 0.0, 1.0));

	if (sky_visible) {
		col = render_sky(world_pos, clouds_pos, sun_pos, moon_pos, current_time);
		if (evening_blend > 0.001) {
			vec2 evening_uv = vec2(0.5 + atan(world_pos.z, world_pos.x) * INV_TAU + evening_rotation,
				acos(clamp(world_pos.y, -1.0, 1.0)) * INV_PI);
			// SkyDome's unwrapped cloud offset avoids a visible jump when its
			// wrapped cirrus UVs or shader TIME restart.
			evening_uv.x += panorama_cloud_position.x * 0.045;
			evening_uv.x = fract(evening_uv.x);
			vec3 golden_sky = texture(evening_panorama, evening_uv).rgb;
			float seam_distance = min(evening_uv.x, 1.0 - evening_uv.x);
			if (seam_distance < 0.018) {
				// Soften the generated panorama's edge into one continuous sky.
				vec3 opposite_edge = texture(evening_panorama, vec2(1.0 - evening_uv.x, evening_uv.y)).rgb;
				golden_sky = mix(golden_sky, opposite_edge, 0.5 * (1.0 - smoothstep(0.0, 0.018, seam_distance)));
			}
			// Fade around the lower hemisphere so terrain/ocean reflections keep
			// the existing atmospheric ground rather than a hard orange seam.
			float sky_mask = smoothstep(-0.10, 0.015, world_pos.y);
			col = mix(col, golden_sky, evening_blend * sky_mask);
		}
	}

	// Draw overlay grids
	{
		float grid_thickness = 0.0002;
		float grid_spacing = 0.261799; // 15 degrees
		vec3 zenith_dir = vec3(0.0, 1.0, 0.0); // Y-axis aligned azimuthal
		vec3 north_celestial_pole = create_rotation_matrix(vec3(star_tilt, 0.0, 0.0)) * zenith_dir;
		float rotation_angle = star_rotation + star_rotation_offset;
		if (show_azimuthal_grid) {
			render_grid(EYEDIR, zenith_dir, azimuthal_grid_rotation_offset, azimuthal_grid_color, grid_spacing, grid_thickness, col);
		}
		if (show_equatorial_grid) {
			render_grid(EYEDIR, north_celestial_pole, rotation_angle + equatorial_grid_rotation_offset, equatorial_grid_color, grid_spacing, grid_thickness, col);
		}
	}

	COLOR = col.rgb;
	}
}
