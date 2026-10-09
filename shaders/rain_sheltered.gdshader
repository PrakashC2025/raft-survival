shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float intensity = 0.0;
uniform vec3 drop_color : source_color = vec3(0.27,0.52,0.76);
uniform float drop_opacity = 0.42;
uniform bool align_to_velocity = true;
uniform mat4 world_to_raft;
uniform int cover_count = 0;
uniform vec4 cover_boxes[64]; // centre XZ, half-size XZ
uniform vec4 cover_levels[64]; // top, bottom, sin(yaw), cos(yaw)
uniform sampler2D roof_heights : filter_nearest, repeat_disable;
uniform vec2 roof_map_origin;
uniform bool roof_map_enabled = false;
varying vec3 rain_world;
void vertex() {
	vec3 up = align_to_velocity ? normalize(MODEL_MATRIX[1].xyz) : normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up,INV_VIEW_MATRIX[2].xyz));
	rain_world = MODEL_MATRIX[3].xyz + right * VERTEX.x + up * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(rain_world,1.0);
}
void fragment() {
	vec3 p = (world_to_raft * vec4(rain_world,1.0)).xyz;
	vec2 roof_uv = (p.xz - roof_map_origin) / 32.0;
	if (roof_map_enabled && all(greaterThanEqual(roof_uv,vec2(0.0))) && all(lessThan(roof_uv,vec2(1.0)))) {
		if (p.y < texture(roof_heights,roof_uv).r) discard;
	}
	for (int i=0;i<cover_count;i++) {
		vec4 b=cover_boxes[i];
		vec4 level=cover_levels[i];
		vec2 offset=p.xz-b.xy;
		vec2 local=vec2(offset.x*level.w-offset.y*level.z,offset.x*level.z+offset.y*level.w);
		if (p.y<level.x && p.y>level.y && all(lessThan(abs(local),b.zw))) discard;
	}
	float soft_edge = smoothstep(0.0,0.18,UV.x)*smoothstep(0.0,0.18,1.0-UV.x);
	ALBEDO=drop_color;
	ALPHA=intensity*drop_opacity*soft_edge;
}
