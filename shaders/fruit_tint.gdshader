// Ripening tint for REAL baked fruit meshes (apple scan, king-coconut bunch).
// Renders the fruit with its FULL material — albedo, NORMAL and ROUGHNESS
// maps — so it shades like real fruit instead of a flat colored ball.
// Unripe fruit mixes toward leaf-green by `ripeness`; fully ripe shows the
// pure texture with a faint warm glow.
//
// `unlit` mode (coconut bunches): scanned husk textures bake in their own
// shading and the PBR light stack + normal-map cavities turned them into
// dark balls with emission patches. Hue-preserving COLOR brightening with
// no normal map reads as natural husk under any daylight.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : filter_linear_mipmap, repeat_enable;
uniform float ripeness : hint_range(0.0, 1.0) = 1.0;
uniform float unlit : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 unripe = vec3(0.40, 0.60, 0.20); // leaf green
	vec3 base = mix(unripe, tex.rgb, ripeness);
	if (unlit > 0.5) {
		// Hue-preserving lift toward white; no normal map, soft matte.
		// (No `return` here — Godot forbids it inside fragment().)
		float lum = max(max(base.r, base.g), base.b);
		ALBEDO = base + (vec3(1.0) - base) * (1.0 - lum) * 0.35;
		ROUGHNESS = 0.85;
		SPECULAR = 0.2;
		METALLIC = 0.0;
		EMISSION = vec3(0.0);
	} else {
		ALBEDO = base;
		if (tex.a < 0.999) { // be safe if the fruit mesh ever gains alpha edges
			ALPHA = tex.a;
			ALPHA_SCISSOR_THRESHOLD = 0.5;
		}
		// Real surface relief + waxy sheen from the scanned maps.
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.8;
		ROUGHNESS = clamp(texture(roughness_tex, UV).r, 0.15, 1.0) * 0.85;
		SPECULAR = 0.35; // waxy apple skin catches a visible highlight
		METALLIC = 0.0;
		EMISSION = tex.rgb * 0.22 * ripeness; // ripe apples glow very slightly
	}
}
