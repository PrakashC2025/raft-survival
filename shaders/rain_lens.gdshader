shader_type canvas_item;
render_mode unshaded;
uniform float exposure : hint_range(0.0,1.0) = 0.0;
uniform float light_level = 1.0;
void fragment() {
	// Small moving beads at the margins leave the aim and controls clear.
	float beads = 0.0;
	float rim = 0.0;
	if (exposure > 0.001 && (UV.x < 0.08 || UV.x > 0.92)) {
	for (int i=0; i<12; i++) {
		float seed = float(i);
		float side = mod(seed,2.0);
		vec2 centre = vec2(mix(0.025,0.975,side) + sin(seed*7.1)*0.018,
			fract(seed*0.173 + TIME*(0.025+seed*0.001)));
		vec2 offset = (UV-centre)*vec2(1.78,0.72);
		float radius = length(offset);
		beads += (1.0-smoothstep(0.009,0.014,radius))*0.10;
		rim += (smoothstep(0.008,0.011,radius)-smoothstep(0.011,0.014,radius))*0.22;
	}
	}
	COLOR = vec4(vec3(0.66,0.76,0.84)*light_level, clamp(beads+rim,0.0,0.32)*exposure);
}
