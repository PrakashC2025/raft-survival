// Wind-sway grass shader (Part 8 of the island guide).
// Reads the black->white vertex-paint (COLOR_0) baked into grass_blade.glb:
//   black base = planted, white tip = sways the most.
// Per-blade variation comes from INSTANCE_CUSTOM (set by island_grass.gd:
//   x = wind phase offset, y = random 0.8..1.2 strength factor), so every
//   blade sways slightly out of sync. Works fine with all-zero custom data too.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 grass_color : source_color = vec3(0.30, 0.55, 0.20);
uniform vec3 tip_color : source_color = vec3(0.45, 0.66, 0.24);
uniform vec3 wind_direction = vec3(-0.707, 0.0, 0.707); // matches Sky3D wind_direction = 2.356 rad (135 deg)
uniform float wind_strength = 0.14;   // max sideways bend in meters at the tip (0.35 m blades)
uniform float wind_speed = 1.6;       // sway cycles per second
uniform float wind_gustiness = 0.5;   // how much strength varies over time

varying float v_mask;

void vertex() {
    // 0 at the planted base, 1 at the whip end (Blender COLOR_0, black->white)
    v_mask = COLOR.r;

    // Per-blade desync from MultiMesh custom data
    float phase = INSTANCE_CUSTOM.x * 6.2831853;
    float rand = mix(0.8, 1.2, INSTANCE_CUSTOM.y);

    // Slow global gust so clumps breathe together, plus per-blade phase
    float gust = sin(TIME * wind_speed * 0.35) * 0.5 + 0.5;
    float amp = wind_strength * rand * (1.0 + wind_gustiness * gust);

    float wave = sin(TIME * wind_speed + phase + v_mask * 1.5);
    // Quadratic falloff: base barely moves, tip moves fully
    VERTEX += wind_direction * (wave * amp * v_mask * v_mask);
}

void fragment() {
    ALBEDO = mix(grass_color, tip_color, v_mask * 0.6);
    ROUGHNESS = 0.85;
}
