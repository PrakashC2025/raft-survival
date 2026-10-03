shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded;

uniform vec4 impression_color : source_color = vec4(0.30, 0.205, 0.105, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 0.0;

float ellipse_sd(vec2 p, vec2 center, vec2 radius) {
	vec2 q = (p - center) / radius;
	return (length(q) - 1.0) * min(radius.x, radius.y);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	// Heel, arch and ball form one soft shoe-shaped depression.
	float d = ellipse_sd(p, vec2(0.0, -0.49), vec2(0.265, 0.34));
	d = min(d, ellipse_sd(p, vec2(0.0, -0.05), vec2(0.235, 0.39)));
	d = min(d, ellipse_sd(p, vec2(0.0, 0.34), vec2(0.365, 0.30)));
	// Five toe pads make the front of the print read as a footprint, not a blob.
	for (int i = 0; i < 5; i++) {
		float x = (float(i) - 2.0) * 0.145;
		float toe_scale = 1.0 - abs(float(i) - 2.0) * 0.105;
		d = min(d, ellipse_sd(p, vec2(x, 0.665 - abs(float(i) - 2.0) * 0.035),
			vec2(0.09 * toe_scale, 0.12 * toe_scale)));
	}
	float edge = 1.0 - smoothstep(-0.018, 0.055, d);
	float grain = hash21(floor(p * 118.0));
	float pressed_grain = 0.82 + grain * 0.18;
	// A thin raised rim catches warm sand light around the compressed center.
	float rim = (1.0 - smoothstep(0.008, 0.045, abs(d - 0.015))) * 0.14;
	ALBEDO = mix(impression_color.rgb, vec3(0.72, 0.55, 0.34), rim);
	ALPHA = fade * edge * pressed_grain * 0.72;
}
