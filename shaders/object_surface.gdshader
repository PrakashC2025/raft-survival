shader_type spatial;
render_mode diffuse_burley;

// Original inexpensive surface detail, shared by small props and equipment.
uniform vec4 base_color : source_color = vec4(0.5, 0.4, 0.3, 1.0);
uniform float surface_roughness = 0.8;
uniform float surface_metallic = 0.0;
uniform int surface_kind = 0; // wood, metal, stone, cloth, plastic, skin, food, soil
varying vec3 local_position;

float hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float noise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
                   mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                   mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { local_position = VERTEX; }
void fragment() {
    vec3 p = local_position;
    float broad = noise(p * 12.0);
    float fine = noise(p * 95.0);
    float relief = fine * 0.35;
    vec3 color = base_color.rgb * COLOR.rgb;
    float rough = surface_roughness;
    float metal = surface_metallic;
    if (surface_kind == 0) {
        float grain = noise(p * vec3(75.0, 2.0, 75.0));
        color *= 0.78 + grain * 0.33 + broad * 0.12;
        relief = grain;
    } else if (surface_kind == 1) {
        float brushed = noise(p * vec3(100.0, 3.0, 3.0));
        float patina = smoothstep(0.68, 0.90, broad);
        color = mix(color * (0.86 + brushed * 0.24), vec3(0.20, 0.10, 0.045), patina * 0.32);
        rough = clamp(rough + patina * 0.28 + fine * 0.06, 0.16, 0.95);
        metal *= 1.0 - patina * 0.45;
    } else if (surface_kind == 2 || surface_kind == 7) {
        color *= 0.70 + broad * 0.45 + fine * 0.12;
        relief = fine + broad * 0.3;
    } else if (surface_kind == 3) {
        float weave = sin(p.x * 440.0) * sin(p.y * 440.0);
        float resolved = 1.0 - smoothstep(0.3, 1.3, length(fwidth(p.xy * 440.0)));
        color *= 0.88 + broad * 0.16 + weave * 0.035 * resolved;
        relief = weave * resolved * 0.3;
    } else if (surface_kind == 4) {
        color *= 0.94 + broad * 0.08;
        rough += fine * 0.07;
    } else if (surface_kind == 5) {
        color *= 0.92 + broad * 0.09 + fine * 0.025;
        rough = max(rough, 0.7);
        relief *= 0.12;
    } else {
        color *= 0.82 + broad * 0.22 + fine * 0.07;
    }
    ALBEDO = color;
    ROUGHNESS = clamp(rough, 0.05, 1.0);
    METALLIC = metal;
    SPECULAR = 0.35;
    NORMAL_MAP = normalize(vec3(-dFdx(relief) * 0.25, -dFdy(relief) * 0.25, 1.0)) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 0.3;
}
