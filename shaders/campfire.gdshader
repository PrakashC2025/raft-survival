shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float flame_phase = 0.0;
// Torch-only readability: the bonfire retains its existing size and shading.
uniform float torch_readability = 0.0;
uniform vec2 torch_flame_size = vec2(0.145, 0.27);
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
varying vec4 flame_anchor;
varying float flame_anchor_depth;
void vertex(){
	// An upright camera-facing fire never becomes edge-on when the player turns.
	// Hold a small bright signal across the sea without adding distant lights.
	float depth = max(-NODE_POSITION_VIEW.z, 0.01);
	float world_scale = max(length(MODEL_MATRIX[0].xyz), 0.001);
	float projected_width = torch_flame_size.x * world_scale * abs(PROJECTION_MATRIX[0][0]) * VIEWPORT_SIZE.x / (2.0 * depth);
	float projected_height = torch_flame_size.y * world_scale * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y / (2.0 * depth);
	float width_boost = clamp(10.0 / max(projected_width, 0.001), 1.0, 64.0);
	float height_boost = clamp(14.0 / max(projected_height, 0.001), 1.0, 48.0);
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX,1.0);
	vec4 anchor_view = MODELVIEW_MATRIX * vec4(0.0,0.0,0.0,1.0);
	flame_anchor = PROJECTION_MATRIX * anchor_view;
	flame_anchor_depth = -anchor_view.z;
	if(torch_readability > 0.5){
		vec3 base = (MODEL_MATRIX * vec4(0.0,-torch_flame_size.y * 0.5,0.0,1.0)).xyz;
		vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 up = vec3(0.0,1.0,0.0);
		vec3 world_vertex = base + right * VERTEX.x * world_scale * width_boost + up * (VERTEX.y + torch_flame_size.y * 0.5) * world_scale * height_boost;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_vertex,1.0);
	}
}
float flame_noise(vec2 p){
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	vec4 n=fract(sin(vec4(dot(i,vec2(127.1,311.7)),dot(i+vec2(1,0),vec2(127.1,311.7)),dot(i+vec2(0,1),vec2(127.1,311.7)),dot(i+vec2(1,1),vec2(127.1,311.7))))*43758.5453);
	return mix(mix(n.x,n.y,f.x),mix(n.z,n.w,f.x),f.y);
}
void fragment(){
	// Test the actual fire's depth, so a readable distant flame cannot stretch
	// over an opaque wall/roof hiding its source. Reconstruct Godot reverse-Z.
	if(torch_readability > 0.5 && flame_anchor_depth > 8.0){
		vec2 anchor_uv = flame_anchor.xy / flame_anchor.w * 0.5 + 0.5;
		float opaque_depth = textureLod(scene_depth,anchor_uv,0.0).r;
		#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(anchor_uv,opaque_depth) * 2.0 - 1.0;
		#else
		vec3 ndc = vec3(anchor_uv * 2.0 - 1.0,opaque_depth);
		#endif
		vec4 opaque_view = INV_PROJECTION_MATRIX * vec4(ndc,1.0);
		if(-opaque_view.z / opaque_view.w + 0.12 < flame_anchor_depth){discard;}
	}
	float h=1.0-UV.y;
	float t=TIME+flame_phase;
	float turbulence=flame_noise(vec2(UV.x*6.0+flame_phase,h*7.0-t*2.7));
	float detail=flame_noise(vec2(UV.x*14.0,h*13.0-t*4.3));
	float centre=.5+sin(h*8.0-t*2.1)*h*.08+(turbulence-.5)*h*.12;
	float width=(.36*(1.0-h)+.015)*(.55+turbulence*.65);
	float body=1.0-smoothstep(width*.35,width,abs(UV.x-centre));
	float height_fade=1.0-smoothstep(.55+turbulence*.20,.96,h);
	float core=pow(body,3.0)*(1.0-h)*(.7+detail*.3);
	vec3 orange=mix(vec3(.84,.055,.003),vec3(1.0,.43,.04),core);
	orange=mix(orange,vec3(1.0,.83,.40),smoothstep(.6,.95,core));
	ALBEDO=orange*(1.0+core*.7);
	EMISSION=orange*torch_readability*3.2;
	float opacity=mix(.40+detail*.42,.78+detail*.20,torch_readability);
	ALPHA=body*height_fade*smoothstep(0.0,.07,h)*opacity;
	if(ALPHA < 0.02){discard;}
}
