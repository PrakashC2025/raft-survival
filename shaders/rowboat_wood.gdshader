shader_type spatial;
render_mode cull_disabled;
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 base_color : source_color = vec4(.84,.81,.74,1.0);
varying vec3 timber_position;
varying vec3 timber_normal;
void vertex(){timber_position=VERTEX;timber_normal=NORMAL;}
vec3 grain(vec2 uv){
	vec2 repeated=1.0-abs(mod(uv,2.0)-1.0);
	return texture(material_atlas,vec2(.502)+repeated*.496).rgb;
}
void fragment(){
	vec3 weight=pow(abs(normalize(timber_normal)),vec3(8.0));weight/=max(dot(weight,vec3(1.0)),.001);
	vec3 p=timber_position;
	vec3 wood=grain(vec2(p.z*.65,p.y*3.2))*weight.x+grain(vec2(p.z*.65,p.x*3.2))*weight.y+grain(vec2(p.x*.65,p.y*3.2))*weight.z;
	// Preserve aged grain while distant mip levels remove subpixel salt/bristle noise.
	ALBEDO=mix(vec3(.33,.29,.23),wood,.78)*base_color.rgb;
	ROUGHNESS=.88;
}
