shader_type spatial;
render_mode cull_back;
varying vec3 body_point;
void vertex() { body_point=VERTEX; }
void fragment() {
	float pores=fract(sin(dot(floor(body_point*250.0),vec3(12.9898,78.233,39.43)))*43758.5453);
	float belly=1.0-smoothstep(-0.10,0.19,body_point.y);
	vec3 skin=mix(vec3(.065,.115,.145),vec3(.48,.57,.59),belly);
	float flecks=sin(body_point.z*24.0+sin(body_point.x*19.0))*sin(body_point.y*31.0);
	ALBEDO=skin*(.95+pores*.07+flecks*.025);
	if(dot(COLOR.rgb,vec3(.333))<.065) ALBEDO=COLOR.rgb;
	ROUGHNESS=.48; SPECULAR=.28;
}
