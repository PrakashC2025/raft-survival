shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength=1.0;
void vertex(){
	float h=1.0-UV.y;
	VERTEX.x+=sin(TIME*1.3+h*5.0)*h*.028;
}
void fragment(){
	float h=1.0-UV.y;
	float centre=.5+sin(h*8.0-TIME*1.6)*.12*h;
	float width=.11+h*.22;
	float edge=1.0-smoothstep(width*.25,width,abs(UV.x-centre));
	float wisps=.55+.45*sin(h*23.0-TIME*3.5+sin(UV.x*8.0+TIME)*2.0);
	ALBEDO=vec3(.80,.85,.86);
	ALPHA=edge*smoothstep(0.0,.22,h)*(1.0-smoothstep(.45,1.0,h))*wisps*.12*strength;
}
