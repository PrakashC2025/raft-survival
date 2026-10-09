shader_type spatial;
render_mode cull_disabled;
uniform vec4 leaf_colour : source_color = vec4(.08,.26,.16,1.0);
uniform sampler2D leaf_texture : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 plant_point;
void vertex(){plant_point=VERTEX;float bend=sin(TIME*.8+MODEL_MATRIX[3].x*.7+VERTEX.y*1.2);VERTEX.x+=bend*VERTEX.y*.075;VERTEX.z+=cos(TIME*.65+MODEL_MATRIX[3].z*.6)*VERTEX.y*.045;}
void fragment(){vec3 leaf=texture(leaf_texture,UV).rgb;float vein=sin(UV.y*190.0+sin(UV.x*30.0))*.035;ALBEDO=leaf*vec3(.60,.83,.64)*(.94+vein);ROUGHNESS=.68;SPECULAR=.25;BACKLIGHT=leaf*.12;NORMAL_MAP=vec3(.5+vein,.5,.97);NORMAL_MAP_DEPTH=.18;}
