shader_type spatial;
render_mode cull_back;
varying vec3 point;
void vertex(){point=VERTEX;}
float noise(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float smooth_noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(noise(i),noise(i+vec2(1,0)),f.x),mix(noise(i+vec2(0,1)),noise(i+vec2(1,1)),f.x),f.y);}
void fragment(){
	vec2 p=point.xz*.75+vec2(TIME*.035,TIME*-.022);
	float flow=smooth_noise(p*1.7+smooth_noise(p*.6));
	float crust=smoothstep(.44,.62,flow);
	float crack=1.0-smoothstep(.025,.095,abs(flow-.48));
	vec3 hot=mix(vec3(.48,.022,.002),vec3(.95,.20,.012),crack);
	ALBEDO=mix(hot*.35,vec3(.025,.018,.014),crust);
	EMISSION=hot*(1.0-crust)*1.2+hot*crack*.45;
	ROUGHNESS=.88;
}
