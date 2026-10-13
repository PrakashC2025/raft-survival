shader_type canvas_item;
uniform vec4 top_col : source_color = vec4(0.0);
uniform vec4 bottom_col : source_color = vec4(0.0);
void fragment() {
	COLOR = mix(top_col, bottom_col, UV.y);
}
