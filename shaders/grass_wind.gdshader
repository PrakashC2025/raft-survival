// Wind-sway grass shader (Part 8 of the island guide).
// Reads the black->white vertex-paint (COLOR_0) baked into grass_blade.glb:
//   black base = planted, white tip = sways the most.
// Per-blade variation comes from INSTANCE_CUSTOM (set by island_grass.gd:
//   x = wind phase offset, y = random 0.8..1.2 strength factor), so every
//   blade sways slightly out of sync. Works fine with all-zero custom data too.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 grass_color : source_color = vec3(0.23, 0.36, 0.12);
uniform vec3 tip_color : source_color = vec3(0.48, 0.55, 0.25);
uniform vec3 dry_color : source_color = vec3(0.49, 0.43, 0.24);
uniform vec3 wind_direction = vec3(-0.707, 0.0, 0.707); // matches Sky3D wind_direction = 2.356 rad (135 deg)
uniform float wind_strength = 0.07;   // keep 0.35 m grass rooted during gusts
uniform float wind_speed = 1.6;       // sway cycles per second
uniform float wind_gustiness = 0.5;   // how much strength varies over time

varying float v_mask;
varying float v_tint;
varying float v_dry;

void vertex() {
    // 0 at the planted base, 1 at the whip end (Blender COLOR_0, black->white)
    v_mask = COLOR.r;
    v_tint = INSTANCE_CUSTOM.z;
    v_dry = INSTANCE_CUSTOM.w;

    // Per-blade desync from MultiMesh custom data
    float phase = INSTANCE_CUSTOM.x * 6.2831853;
    float rand = mix(0.8, 1.2, INSTANCE_CUSTOM.y);

    // Slow global gust so clumps breathe together, plus per-blade phase
    vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float distance_fade = 1.0 - smoothstep(55.0, 95.0, distance(wp, CAMERA_POSITION_WORLD));
    VERTEX *= distance_fade;
    // Traveling gusts cross the field; individual blades flutter behind them.
    float gust = sin(TIME * 0.55 - dot(wp.xz, vec2(-0.10, 0.10))) * 0.5 + 0.5;
    float amp = wind_strength * rand * (1.0 + wind_gustiness * gust);

    float wave = sin(TIME * wind_speed + phase + v_mask * 1.5);
    // Quadratic falloff: base barely moves, tip moves fully
    VERTEX += wind_direction * (wave * amp * v_mask * v_mask) * distance_fade;
    VERTEX.y -= abs(wave) * amp * 0.12 * v_mask * distance_fade;
}

void fragment() {
    vec3 green = mix(grass_color, tip_color, v_mask * 0.72);
    ALBEDO = mix(green, dry_color, smoothstep(0.78, 1.0, v_dry) * 0.55);
    ALBEDO *= mix(0.83, 1.12, v_tint);
    ALBEDO *= 0.92 + 0.08 * sin(UV.x * 3.14159);
    NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
    ROUGHNESS = 0.86;
    SPECULAR = 0.22;
    BACKLIGHT = ALBEDO * 0.45 * v_mask;
    AO = mix(0.68, 1.0, v_mask);
}
