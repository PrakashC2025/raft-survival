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
    float horizon = 0.46;
    float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    vec2 sun = vec2((uv.x - 0.77) * aspect, uv.y - 0.365);
    vec3 sky = mix(vec3(0.13,0.38,0.55), vec3(0.80,0.81,0.70), pow(clamp(uv.y / horizon, 0.0, 1.0), 1.6));
    float cloud = noise(vec2(uv.x * 5.0 + TIME * 0.006, uv.y * 21.0));
    sky += vec3(0.19,0.20,0.18) * smoothstep(0.54,0.79,cloud) * 0.55;
    sky += vec3(0.35,0.20,0.09) * exp(-length(sun) * 9.0);
    sky = mix(sky, vec3(1.0,0.93,0.75), 1.0 - smoothstep(0.026,0.030,length(sun)));
    vec3 color = sky;
    if (uv.y > horizon) {
        float depth = uv.y - horizon;
        vec2 sea_uv = vec2((uv.x - 0.5) * 2.5 / (depth + 0.025), 0.5 / (depth + 0.025));
        float swell = noise(sea_uv * vec2(1.8,3.0) + vec2(TIME * 0.045, TIME * 0.12));
        float ripples = sin(sea_uv.y * 8.0 + swell * 5.0 + TIME * 0.7) * 0.5 + 0.5;
        float reflection = exp(-pow((uv.x - 0.77) * (12.0 - depth * 10.0), 2.0));
        color = mix(vec3(0.20,0.48,0.56), vec3(0.018,0.19,0.27), smoothstep(0.0,0.5,depth));
        color += vec3(0.08,0.15,0.17) * swell;
        color += vec3(0.70,0.56,0.30) * reflection * pow(ripples,5.0) * smoothstep(0.0,0.05,depth);
        color += vec3(0.11,0.26,0.28) * smoothstep(0.82,0.99,ripples) * depth * 0.45;
    }
    float vignette = 1.0 - smoothstep(0.35,0.85,length((uv-0.5) * vec2(0.9,1.0)));
    // Keep the sea open on the right; a navy gradient makes menu text legible.
    float left_shade = 1.0-smoothstep(0.16,0.70,uv.x);
    color=mix(color,vec3(0.018,0.075,0.115),left_shade*0.70);
    COLOR = vec4(color * (0.78 + 0.22 * vignette), 1.0);
}
