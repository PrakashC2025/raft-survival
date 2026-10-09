shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float cooked : hint_range(0.0,1.0) = 1.0;
varying vec3 food_position;
void vertex(){food_position=VERTEX;}
void fragment(){
	float grain=fract(sin(dot(floor(food_position*950.0),vec3(12.3,43.7,29.1)))*43758.5);
	float edge=pow(abs(sin(food_position.x*75.0+food_position.z*31.0)),14.0);
	vec3 toasted=mix(COLOR.rgb,COLOR.rgb*vec3(.72,.61,.43),cooked*(.18+edge*.32));
	ALBEDO=toasted*(.94+grain*.09);ROUGHNESS=.43+grain*.10;SPECULAR=.35;
}
