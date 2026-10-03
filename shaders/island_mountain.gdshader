shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 rock_paint;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash31(i);
	float b = hash31(i + vec3(1.0, 0.0, 0.0));
	float c = hash31(i + vec3(0.0, 1.0, 0.0));
	float d = hash31(i + vec3(1.0, 1.0, 0.0));
	float e = hash31(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash31(i + vec3(1.0, 0.0, 1.0));
	float g = hash31(i + vec3(0.0, 1.0, 1.0));
	float h = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
		mix(mix(e, f1, f.x), mix(g, h, f.x), f.y), f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	rock_paint = COLOR;
}

void fragment() {
	vec3 p = world_pos * vec3(2.1, 2.8, 2.1);
	float coarse = noise3(p * 0.34);
	float grit = noise3(p * 2.8);
	float fine = noise3(p * 12.0);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	// Broken sediment bands follow the mountain's height, softened by stone noise.
	float strata = smoothstep(0.66, 0.94,
		0.5 + 0.5 * sin(world_pos.y * 7.5 + coarse * 3.0 + grit * 1.4));
	vec3 stone = rock_paint.rgb * (0.76 + coarse * 0.30);
	stone *= 0.88 + grit * 0.20;
	stone *= 0.92 + fine * 0.13;
	stone = mix(stone, stone * vec3(0.68, 0.74, 0.79), strata * 0.32);
	// The shallow gullies hold a cooler shadow tint; exposed ridges stay warm.
	float ridge = smoothstep(0.42, 0.88, fine + grit * 0.28);
	stone = mix(stone * vec3(0.68, 0.73, 0.78), stone * 1.08, ridge);
	ALBEDO = stone;
	ROUGHNESS = 0.94;
	SPECULAR = mix(0.16, 0.28, slope);
}
