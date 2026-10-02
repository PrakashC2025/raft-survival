shader_type spatial;
uniform vec3 bark_color : source_color = vec3(0.43, 0.34, 0.23);
varying vec3 bark_position;

void vertex() {
	bark_position = VERTEX;
}

void fragment() {
	float rings = sin(bark_position.y * 110.0 + sin(bark_position.x * 25.0) * 0.6);
	float fibers = sin(atan(bark_position.z, bark_position.x) * 38.0 + bark_position.y * 5.0);
	ALBEDO = bark_color * (0.82 + 0.10 * rings + 0.08 * fibers);
	ROUGHNESS = 0.94;
	SPECULAR = 0.15;
}
