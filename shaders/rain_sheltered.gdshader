shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float intensity = 0.0;
uniform mat4 world_to_raft;
uniform int cover_count = 0;
uniform vec4 cover_boxes[64]; // centre XZ, half-size XZ
uniform vec4 cover_levels[64]; // top, bottom, sin(yaw), cos(yaw)
varying vec3 rain_world;
void vertex() {
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 right = normalize(cross(up,INV_VIEW_MATRIX[2].xyz));
	rain_world = MODEL_MATRIX[3].xyz + right * VERTEX.x + up * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(rain_world,1.0);
}
void fragment() {
	vec3 p = (world_to_raft * vec4(rain_world,1.0)).xyz;
	for (int i=0;i<cover_count;i++) {
		vec4 b=cover_boxes[i];
		vec4 level=cover_levels[i];
		vec2 offset=p.xz-b.xy;
		vec2 local=vec2(offset.x*level.w-offset.y*level.z,offset.x*level.z+offset.y*level.w);
		if (p.y<level.x && p.y>level.y && all(lessThan(abs(local),b.zw))) discard;
	}
	float soft_edge = smoothstep(0.0,0.18,UV.x)*smoothstep(0.0,0.18,1.0-UV.x);
	ALBEDO=vec3(0.65,0.75,0.84);
	ALPHA=intensity*0.42*soft_edge;
}
