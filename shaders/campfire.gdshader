shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float h = 1.0 - UV.y;
	float sway = sin(h * 9.0 - TIME * 4.0) * 0.06 + sin(h * 19.0 - TIME * 7.0) * 0.035;
	float width = mix(0.44, 0.015, pow(h, 0.65));
	float flame = 1.0 - smoothstep(width * 0.35, width, abs(UV.x - 0.5 - sway * h));
	float flicker = 0.76 + 0.24 * sin(TIME * 11.0 + h * 12.0);
	ALBEDO = mix(vec3(1.0, 0.18, 0.025), vec3(1.0, 0.72, 0.20), pow(1.0 - h, 2.0));
	ALPHA = flame * (1.0 - smoothstep(0.80, 1.0, h)) * smoothstep(0.0, 0.08, h) * flicker;
}
