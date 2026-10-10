shader_type spatial;
render_mode cull_disabled;
uniform float daylight = 1.0;
varying vec3 sea_point;
void vertex() { sea_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float pores = sin(sea_point.x*57.0)*sin(sea_point.y*61.0)*sin(sea_point.z*49.0);
	vec3 pigment = COLOR.rgb * (0.88 + pores*.08);
	float depth = max(0.0,-sea_point.y);
	vec3 haze = mix(vec3(.055,.24,.27),vec3(.012,.055,.095),smoothstep(8.0,65.0,depth));
	float distance_fade = 1.0-exp(-distance(CAMERA_POSITION_WORLD,sea_point)*.021);
	ALBEDO = mix(pigment, haze, distance_fade*.88);
	ROUGHNESS = .86;
	EMISSION = haze*distance_fade*.10 + pigment*.035*daylight*exp(-depth*.035);
}
