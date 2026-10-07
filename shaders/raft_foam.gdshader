shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// ============================================================
// RAFT FOAM — subtle churning foam where the raft hull meets the
// water. A thin vertical skirt + top collar around the hull that
// lights up when the (identical) ocean wave field rises against
// the hull bottom and fades as the water drops. Animated along
// the perimeter so the foam streams around the raft.
// ============================================================

uniform float plane_y = 0.0;      // world Y of the hull-bottom contact line
uniform float night_factor = 0.0;
uniform float twilight_factor = 0.0;
uniform float wave_height = 0.68; // kept in sync with the ocean material
uniform float wave_speed = 0.52;
uniform float wave_time = 0.0;

varying vec2 fo_uv;   // u = around perimeter (0..1), v = height (0 bottom..1 top)
varying vec3 f_wp;    // world position

// Wave-field constants — MUST match main.gdshader / ocean.gd _WAVES.
const vec2 L1_DIR = vec2(1.0, 0.15);
const vec2 L2_DIR = vec2(-0.4, 0.92);
const vec2 L3_DIR = vec2(0.8, -0.5);
const vec2 L4_DIR = vec2(-0.75, -0.65);
// Synced with main.gdshader / ocean.gd _WAVES (smooth-sea tuning).
const float L1_F = 0.18;
const float L2_F = 0.33;
const float L3_F = 0.59;
const float L4_F = 0.95;
const float L1_A = 1.0;
const float L2_A = 0.75;
const float L3_A = 0.38;
const float L4_A = 0.13;
const float L1_S = 0.80;
const float L2_S = 1.10;
const float L3_S = 1.55;
const float L4_S = 1.90;

void vertex() {
	f_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	fo_uv = UV;
}

void fragment() {
	// Water surface height at this point — the same field the ocean shader
	// displaces and get_height() feeds to buoyancy.
	vec2 p = f_wp.xz;
	float t = wave_time * wave_speed;
	vec2 warp=vec2(
 6.0*sin(dot(p,vec2(0.21,0.98))*0.020+t*0.10)+3.2*sin(dot(p,vec2(0.85,-0.53))*0.048+t*0.16),
 6.0*sin(dot(p,vec2(0.21,0.98))*0.020+t*0.10+2.1)+3.2*sin(dot(p,vec2(0.85,-0.53))*0.048+t*0.16+4.2));
 p+=warp;
 float envelope=0.75+0.25*sin(dot(p,vec2(-0.31,0.95))*0.011+t*0.06)*sin(dot(p,vec2(0.90,-0.44))*0.026+t*0.10);
	float h = L1_A * sin(dot(L1_DIR, p) * L1_F + t * L1_S)
		+ L2_A * sin(dot(L2_DIR, p) * L2_F + t * L2_S)
		+ L3_A * sin(dot(L3_DIR, p) * L3_F + t * L3_S)
		+ L4_A * sin(dot(L4_DIR, p) * L4_F + t * L4_S);
	float water_y = h * envelope * wave_height * 0.33;

	// How far the wave surface is from the hull-bottom contact line:
	// foam swells as water rises into the band under the hull and fades out
	// as it drops away (subtle, no mid-air foam).
	float contact = water_y - plane_y;
	float lapping = smoothstep(-0.5, 0.05, contact);

	// Churn: several animated noise octaves along the perimeter, streaming
	// tangentially (u scrolls with time) so the foam looks like water
	// flowing around the hull.
	float u = fo_uv.x;
	float v = fo_uv.y;
	float n1 = 0.5 + 0.5 * sin(u * TAU * 3.0 + TIME * 1.7 + sin(v * TAU) * 0.9);
	float n2 = 0.5 + 0.5 * sin(u * TAU * 7.0 - TIME * 2.5 + v * 12.0);
	float n3 = 0.5 + 0.5 * sin(u * TAU * 1.0 + TIME * 0.55);
	float noise = n1 * n2 * 0.75 + n3 * 0.25;
	float foam = lapping * pow(max(noise, 0.0), 1.6);

	// Brightest at the top edge where the hull meets the water, fading with
	// depth below the hull (the deep foam is barely visible).
	foam *= 0.25 + 0.75 * v;

	// Day/twilight/night foam color — dims to a cool dark blue at night.
	vec3 foam_col = mix(vec3(0.86, 0.95, 1.0), vec3(0.13, 0.16, 0.24), night_factor);
	foam_col = mix(foam_col, vec3(0.6, 0.68, 0.78), twilight_factor * 0.35);

	float alpha = clamp(foam, 0.0, 1.0) * 0.85 * (1.0 - night_factor * 0.55);
	ALBEDO = foam_col * (0.9 + 0.1 * noise);
	ALPHA = alpha;
}
