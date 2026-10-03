shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 sand_color : source_color = vec4(0.73, 0.57, 0.34, 1.0);
uniform float grain_scale = 34.0;
uniform float grain_strength = 0.22;

varying vec3 local_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos.xz * grain_scale + local_pos.xy * grain_scale * 0.31;
	float broad = value_noise(p * 0.16) * 0.58 + value_noise(p * 0.43 + 8.7) * 0.42;
	float grain = hash21(floor(p * 2.2));
	float fleck = smoothstep(0.78, 0.97, grain);
	ALBEDO = sand_color.rgb * (0.84 + broad * grain_strength + fleck * 0.12);
	ROUGHNESS = 0.97;
	SPECULAR = 0.18;
}
