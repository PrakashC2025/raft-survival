shader_type spatial;
render_mode cull_disabled;
varying vec3 leaf_point;
varying vec3 leaf_normal;
void vertex(){
	leaf_point=VERTEX;leaf_normal=NORMAL;
	VERTEX.x+=sin(TIME*.65+VERTEX.y*.80+MODEL_MATRIX[3].x)*min(VERTEX.y*.008,.07);
}
void fragment(){
	float grain=fract(sin(dot(leaf_point,vec3(17.3,28.9,13.7)))*13758.5453);
	float snow=smoothstep(.40,.78,leaf_normal.y)*smoothstep(.18,.48,grain);
	ALBEDO=mix(mix(vec3(.035,.12,.08),vec3(.11,.21,.15),grain),vec3(.79,.89,.96),snow);
	ROUGHNESS=.95;
}
