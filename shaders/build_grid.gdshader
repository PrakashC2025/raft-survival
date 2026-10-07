shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// One plane, anti-aliased metre grid. Fade the boundary instead of hard clipping.
varying vec2 grid_position;
void vertex() { grid_position = VERTEX.xz; }
void fragment() {
	vec2 p = grid_position / 2.0;
	vec2 distance_to_line = abs(fract(p) - 0.5) / max(fwidth(p), vec2(0.001));
	float line = 1.0 - min(min(distance_to_line.x, distance_to_line.y), 1.0);
	float fade = 1.0 - smoothstep(5.0, 8.0, length(grid_position));
	ALBEDO = vec3(0.16, 0.65, 1.0);
	ALPHA = line * fade * 0.32;
}
