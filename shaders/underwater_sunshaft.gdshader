shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float daylight = 1.0;
uniform float phase = 0.0;
varying vec3 sea_point;
void vertex(){
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
	sea_point=(inverse(VIEW_MATRIX)*MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
	float edge = pow(max(0.0,1.0-abs(UV.x-.5)*2.0),3.0);
	float ends = smoothstep(0.0,.25,UV.y)*(1.0-smoothstep(.65,1.0,UV.y));
	float shimmer = .85+.15*sin(TIME*.6+phase+UV.y*7.0);
	float submerged = smoothstep(.1,1.2,-CAMERA_POSITION_WORLD.y) * smoothstep(1.0,3.0,-sea_point.y);
	float fade = 1.0-smoothstep(30.0,75.0,distance(CAMERA_POSITION_WORLD,sea_point));
	ALBEDO=vec3(.40,.66,.62);
	ALPHA=edge*ends*shimmer*daylight*submerged*fade*.035;
}
