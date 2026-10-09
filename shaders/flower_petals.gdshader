shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
varying vec3 plant_position;
void vertex() {
	plant_position=VERTEX;
	float breeze=sin(TIME*1.15+MODEL_MATRIX[3].x*.43+MODEL_MATRIX[3].z*.31);
	VERTEX.x+=breeze*VERTEX.y*VERTEX.y*.09;
}
void fragment() {
	float veins=pow(abs(sin(UV.y*37.0+UV.x*11.0)),10.0);
	float centre=1.0-smoothstep(.0,.38,UV.x);
	vec3 petals=COLOR.rgb*(.89+.11*sin(UV.x*3.14159)-veins*.045);
	petals=mix(petals,vec3(.95,.66,.18),centre*.24);
	ALBEDO=mix(COLOR.rgb,petals,COLOR.a);
	ROUGHNESS=.71;SPECULAR=.25;
	BACKLIGHT=COLOR.rgb*.18;
}
