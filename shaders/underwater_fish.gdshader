shader_type spatial;
uniform sampler2D fish_skin : source_color, filter_linear_mipmap;
uniform bool textured = false;
uniform vec4 body_colour : source_color = vec4(.57,.65,.63,1.0);
varying vec3 sea_point;
void vertex(){
	float tail = smoothstep(-.1,.7,VERTEX.z);
	VERTEX.x += sin(TIME*4.8+float(INSTANCE_ID)*.73-VERTEX.z*7.0)*tail*.022;
	sea_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
	vec3 skin = textured?texture(fish_skin,UV).rgb:body_colour.rgb;
	float distance_fade=1.0-exp(-distance(CAMERA_POSITION_WORLD,sea_point)*.025);
	float depth=max(0.0,-sea_point.y);
	vec3 haze=mix(vec3(.055,.24,.27),vec3(.012,.055,.095),smoothstep(8.0,65.0,depth));
	ALBEDO=mix(skin*COLOR.rgb,haze,distance_fade*.88);
	ROUGHNESS=.46;METALLIC=.12;EMISSION=haze*distance_fade*.1;
}
