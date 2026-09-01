shader_type spatial;
uniform vec3 water_color : source_color = vec3(0.05, 0.30, 0.50);
uniform float wave_height = 0.6;
uniform float wave_speed = 1.2;
void vertex() {
vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
float h = sin(wp.x * 0.4 + TIME * wave_speed)
+ sin(wp.z * 0.3 + TIME * wave_speed * 0.8)
+ 0.5 * sin((wp.x + wp.z) * 0.7 + TIME * 1.7);
VERTEX.y += h * wave_height * 0.33;
}
void fragment() {
ALBEDO = water_color;
ROUGHNESS = 0.05;
METALLIC = 0.3;
SPECULAR = 0.7;
}