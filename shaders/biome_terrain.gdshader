shader_type spatial;
render_mode cull_back;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap, repeat_enable;
uniform bool winter = false;
uniform bool spring = false;
varying vec3 local_point;
varying vec3 local_normal;
void vertex() { local_point=VERTEX; local_normal=NORMAL; }
void fragment() {
	vec3 weights=pow(abs(normalize(local_normal)),vec3(5.0));weights/=max(dot(weights,vec3(1.0)),0.001);
	vec3 p=local_point*0.24;
	vec3 rock=texture(rock_albedo,p.yz).rgb*weights.x+texture(rock_albedo,p.xz).rgb*weights.y+texture(rock_albedo,p.xy).rgb*weights.z;
	float grain=texture(rock_arm,p.xz*3.7).r;
	float wet=1.0-smoothstep(0.0,2.1,local_point.y);
	float tone=dot(rock,vec3(.2126,.7152,.0722));
	vec3 colour=vec3(.050,.057,.065)*(.65+tone*1.7)*(1.0-wet*.4);
	float snow=0.0;
	if(spring){
		float grass=smoothstep(1.5,3.1,local_point.y)*smoothstep(.65,.9,normalize(local_normal).y);
		colour=mix(rock*vec3(.65,.59,.38),mix(vec3(.055,.16,.028),vec3(.15,.28,.055),grain),grass);
	}
	if(winter){
		snow=smoothstep(.76,.96,normalize(local_normal).y)*smoothstep(.5,2.0,local_point.y);
		float scoured=.5+.5*sin(local_point.x*.43+sin(local_point.z*.32));
		snow*=smoothstep(.10,.38,grain*.4+scoured*.4);
		colour=mix(rock*vec3(.19,.24,.29),mix(vec3(.34,.48,.60),vec3(.62,.71,.80),grain),snow);
	}
	ALBEDO=colour;
	ROUGHNESS=mix(.93,.44,wet)*(1.0-snow*.08);
	NORMAL_MAP=texture(rock_normal,p.xz).rgb;NORMAL_MAP_DEPTH=mix(.50,.10,snow);
	AO=mix(.75,1.0,grain);
}
