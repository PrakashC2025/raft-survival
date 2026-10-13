// Three shared 1K maps, sampled once each on the dominant object-space face.
uniform bool photo_surface = false;
uniform sampler2D photo_diff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D photo_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D photo_arm : filter_linear_mipmap, repeat_enable;
uniform float photo_scale = 2.0;
varying vec3 photo_local_normal;

void sample_salvage_photo(vec3 point, out vec3 colour, out vec3 arm, out vec3 local_bump) {
    vec3 n = normalize(photo_local_normal);
    vec3 a = abs(n);
    vec2 uv;
    vec3 tangent;
    vec3 bitangent;
    vec3 face;
    if (a.y >= a.x && a.y >= a.z) {
        uv = point.xz * photo_scale;
        tangent = vec3(1,0,0);
        bitangent = vec3(0,0,1);
        face = vec3(0,sign(n.y),0);
    } else if (a.x > a.z) {
        uv = point.zy * photo_scale;
        tangent = vec3(0,0,1);
        bitangent = vec3(0,1,0);
        face = vec3(sign(n.x),0,0);
    } else {
        uv = point.xy * photo_scale;
        tangent = vec3(1,0,0);
        bitangent = vec3(0,1,0);
        face = vec3(0,0,sign(n.z));
    }
    colour = texture(photo_diff, uv).rgb;
    arm = texture(photo_arm, uv).rgb;
    // Normal compression can discard blue; reconstruct it from red/green.
    vec2 rg = texture(photo_normal, uv).rg * 2.0 - 1.0;
    float blue = sqrt(max(0.0, 1.0 - dot(rg, rg)));
    local_bump = normalize(tangent * rg.x + bitangent * rg.y + face * blue);
}
