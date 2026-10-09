shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
float flame_noise(vec2 p){
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	vec4 n=fract(sin(vec4(dot(i,vec2(127.1,311.7)),dot(i+vec2(1,0),vec2(127.1,311.7)),dot(i+vec2(0,1),vec2(127.1,311.7)),dot(i+vec2(1,1),vec2(127.1,311.7))))*43758.5453);
	return mix(mix(n.x,n.y,f.x),mix(n.z,n.w,f.x),f.y);
}
void fragment(){
	float h=1.0-UV.y;
	float turbulence=flame_noise(vec2(UV.x*6.0,h*7.0-TIME*3.8));
	float detail=flame_noise(vec2(UV.x*14.0,h*13.0-TIME*6.1));
	float centre=.5+sin(h*8.0-TIME*2.8)*h*.08;
	float width=(.36*(1.0-h)+.015)*(.55+turbulence*.65);
	float body=1.0-smoothstep(width*.35,width,abs(UV.x-centre));
	float height_fade=1.0-smoothstep(.55+turbulence*.20,.96,h);
	float core=pow(body,3.0)*(1.0-h)*(.7+detail*.3);
	vec3 orange=mix(vec3(1.0,.095,.008),vec3(1.0,.58,.09),core);
	ALBEDO=orange*(1.0+core*.55);
	ALPHA=body*height_fade*smoothstep(0.0,.07,h)*(.48+detail*.43);
}
