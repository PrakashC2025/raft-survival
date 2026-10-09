shader_type spatial;
render_mode cull_back;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool masonry=false;
varying vec3 sea_point;
void vertex(){sea_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
	vec2 p=sea_point.xz;
	vec3 scan=texture(surface_texture,p*.28).rgb;
	float ripple=sin(p.x*14.0+sin(p.y*.45)*4.0)*.5+.5;
	vec3 stone=texture(surface_texture,vec2(sea_point.x+sea_point.z,sea_point.y)*.40).rgb;
	vec3 base=masonry?stone*vec3(.34,.47,.42):scan*vec3(.52,.64,.55)*(.92+ripple*.06);
	float caustic=pow(max(0.0,sin(p.x*.72+TIME*.9+sin(p.y*.51-TIME*.55))*sin(p.y*.64+TIME*.7+sin(p.x*.41))),10.0);
	float distant=smoothstep(25.0,150.0,distance(CAMERA_POSITION_WORLD,sea_point));
	ALBEDO=mix(base,vec3(.025,.095,.12),distant*.8);
	EMISSION=base*.08+vec3(.05,.11,.12)*caustic;
	NORMAL_MAP=texture(surface_normal,p*.28).rgb;NORMAL_MAP_DEPTH=.5;
	ROUGHNESS=.88;
}
