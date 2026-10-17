shader_type spatial;
render_mode cull_disabled;
// Original generated albedo atlas; object-space projection keeps detail in metres.
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 tile = vec2(0.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float texture_scale = 2.0;
uniform float surface_roughness = 0.88;
uniform float belly_light = 0.0;
varying vec3 material_position;
varying vec3 material_normal;
void vertex(){material_position=VERTEX;material_normal=NORMAL;}
vec3 scan(vec2 uv){
	// Mirroring avoids a hard repeated seam; inset protects neighbouring atlas tiles.
	vec2 repeated=1.0-abs(mod(uv,2.0)-1.0);
	return texture(material_atlas,tile+vec2(.002)+repeated*.496).rgb;
}
void fragment(){
	vec3 weight=pow(abs(normalize(material_normal)),vec3(6.0));
	weight/=max(dot(weight,vec3(1.0)),.001);
	vec3 p=material_position*texture_scale;
	vec3 color=scan(p.zy)*weight.x+scan(p.xz)*weight.y+scan(p.xy)*weight.z;
	color=mix(color,vec3(.40,.37,.26),belly_light*smoothstep(.15,.75,-material_normal.y));
	ALBEDO=color*tint.rgb;
	ROUGHNESS=surface_roughness;
}
