shader_type spatial;
render_mode cull_disabled;
uniform sampler2D skin_photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D source_details : source_color, filter_linear_mipmap_anisotropic;
varying vec3 skin_position;
varying vec3 skin_normal;
void vertex(){skin_position=VERTEX;skin_normal=NORMAL;}
vec3 scales(vec2 p){
	vec2 tiled=1.0-abs(mod(p,2.0)-1.0);
	return texture(skin_photo,vec2(.35,.22)+tiled*vec2(.17,.075)).rgb;
}
void fragment(){
	vec3 n=normalize(skin_normal);vec3 w=pow(abs(n),vec3(5.0));w/=max(dot(w,vec3(1.0)),.001);
	vec3 p=skin_position*3.0;
	vec3 scan=scales(p.zy)*w.x+scales(p.zx)*w.y+scales(p.xy)*w.z;
	vec3 details=texture(source_details,UV).rgb;
	float belly=smoothstep(.1,.8,-n.y)*.7;
	ALBEDO=mix(scan*vec3(.78,.82,.71),vec3(.40,.37,.25),belly);
	// Preserve the source eyes, nostrils, teeth and open mouth in the original UV map.
	float dark=1.0-smoothstep(.06,.16,max(details.r,max(details.g,details.b)));
	ALBEDO=mix(ALBEDO,details,dark*.92);
	ROUGHNESS=.78;SPECULAR=.32;
}
