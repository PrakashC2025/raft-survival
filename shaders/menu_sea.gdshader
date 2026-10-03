shader_type canvas_item;
render_mode unshaded;
// Single backdrop draw; no 3D scene, blur or full-screen reflection pass.
float noise(vec2 p) {
    // Continuous waves keep this lightweight backdrop free of visible noise
    // cell boundaries on the Mobile canvas renderer.
    return 0.5 + 0.22 * sin(p.x * 1.3 + sin(p.y * 0.8))
               + 0.18 * sin(p.y * 1.1 + sin(p.x * 0.7));
}
void fragment() {
    vec2 uv = UV;
    float horizon = 0.48;
    float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    vec2 sun = vec2((uv.x - 0.76) * aspect, uv.y - 0.39);
    vec3 sky = mix(vec3(0.085,0.15,0.20), vec3(0.65,0.47,0.29), pow(clamp(uv.y / horizon, 0.0, 1.0), 2.4));
    float cloud = noise(vec2(uv.x * 5.0 + TIME * 0.006, uv.y * 21.0));
    sky += vec3(0.15,0.14,0.12) * smoothstep(0.54,0.79,cloud) * 0.4;
    sky += vec3(0.63,0.32,0.13) * exp(-length(sun) * 10.0);
    sky = mix(sky, vec3(1.0,0.82,0.56), 1.0 - smoothstep(0.028,0.031,length(sun)));
    vec3 color = sky;
    if (uv.y > horizon) {
        float depth = uv.y - horizon;
        vec2 sea_uv = vec2((uv.x - 0.5) * 2.5 / (depth + 0.025), 0.5 / (depth + 0.025));
        float swell = noise(sea_uv * vec2(1.8,3.0) + vec2(TIME * 0.045, TIME * 0.12));
        float ripples = sin(sea_uv.y * 8.0 + swell * 5.0 + TIME * 0.7) * 0.5 + 0.5;
        float reflection = exp(-pow((uv.x - 0.76) * (10.0 - depth * 10.0), 2.0));
        color = mix(vec3(0.20,0.29,0.29), vec3(0.015,0.095,0.12), smoothstep(0.0,0.4,depth));
        color += vec3(0.10,0.14,0.13) * swell;
        color += vec3(0.55,0.32,0.13) * reflection * pow(ripples,5.0) * smoothstep(0.0,0.05,depth);
    }
    float vignette = 1.0 - smoothstep(0.35,0.85,length((uv-0.5) * vec2(0.9,1.0)));
    COLOR = vec4(color * (0.55 + 0.45 * vignette), 1.0);
}
