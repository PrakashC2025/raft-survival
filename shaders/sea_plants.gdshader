shader_type spatial;
render_mode cull_disabled;
uniform vec4 leaf_colour : source_color = vec4(.55,.68,.40,1.0);
uniform sampler2D leaf_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 current = vec2(.8,.3);
uniform float daylight = 1.0;
varying vec3 sea_point;
void vertex(){
 float height = max(VERTEX.y,0.0);
 float phase = MODEL_MATRIX[3].x*.43 + MODEL_MATRIX[3].z*.61;
 float bend = sin(TIME*.48+phase+height*.35);
 VERTEX.xz += (current*bend + vec2(cos(TIME*.37+phase),sin(TIME*.32+phase))*.22)*height*.045;
 sea_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 vec3 leaf = texture(leaf_texture,UV).rgb*leaf_colour.rgb*COLOR.rgb;
 float vein = sin(UV.y*190.0+sin(UV.x*30.0))*.035;
 float depth = max(0.0,-sea_point.y);
 vec3 haze = mix(vec3(.055,.24,.27),vec3(.012,.055,.095),smoothstep(8.0,65.0,depth));
 float fade = 1.0-exp(-distance(CAMERA_POSITION_WORLD,sea_point)*.021);
 ALBEDO = mix(leaf*(.96+vein),haze,fade*.86);
 EMISSION = leaf*.08*daylight*exp(-depth*.032)*(1.0-fade)+haze*fade*.10;
 ROUGHNESS=.79; SPECULAR=.2; BACKLIGHT=leaf*.18;
 NORMAL_MAP=vec3(.5+vein,.5,.97); NORMAL_MAP_DEPTH=.18;
}
