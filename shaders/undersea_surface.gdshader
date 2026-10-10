shader_type spatial;
render_mode cull_back;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_arm : filter_linear_mipmap, repeat_enable;
uniform bool masonry = false;
uniform float daylight = 1.0;
uniform float sea_clock = 0.0;
uniform vec2 stream_center = vec2(0.0);
uniform float stream_cut = 0.0;
varying vec3 sea_point;
varying vec3 sea_normal;
void vertex() {
 sea_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 sea_normal = normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 if(stream_cut>0.0 && distance(sea_point.xz,stream_center)<stream_cut) { discard; }
 vec3 weights = pow(abs(sea_normal),vec3(4.0));
 weights /= max(dot(weights,vec3(1.0)),.001);
 vec2 xy = sea_point.xy*.32;
 vec2 yz = sea_point.zy*.32;
 vec2 xz = sea_point.xz*.32;
 vec3 base = texture(surface_texture,xz).rgb;
 vec3 arm = texture(surface_arm,xz).rgb;
 vec3 bump = texture(surface_normal,xz).rgb*2.0-1.0;
 vec3 world_bump = vec3(bump.x,bump.z,bump.y);
 if(masonry) {
  base = texture(surface_texture,yz).rgb*weights.x + texture(surface_texture,xz).rgb*weights.y + texture(surface_texture,xy).rgb*weights.z;
  arm = texture(surface_arm,yz).rgb*weights.x + texture(surface_arm,xz).rgb*weights.y + texture(surface_arm,xy).rgb*weights.z;
  vec3 nx = texture(surface_normal,yz).rgb*2.0-1.0;
  vec3 nz = texture(surface_normal,xy).rgb*2.0-1.0;
  world_bump = vec3(nx.z*sign(sea_normal.x),nx.y,nx.x)*weights.x + world_bump*weights.y + vec3(nz.x,nz.y,nz.z*sign(sea_normal.z))*weights.z;
  float algae = smoothstep(.05,.9,sea_normal.y) * (.4+.6*sin(sea_point.x*.7)*sin(sea_point.z*.6));
  base *= mix(vec3(.15,.23,.21),vec3(.11,.21,.12),algae*.55);
 } else {
  float ripples = sin(sea_point.x*4.2+sin(sea_point.z*.64)*2.2);
  base *= vec3(1.05,1.00,.86) * (.96+ripples*.035);
 }
 float depth = max(0.0,-sea_point.y);
 float attenuation = exp(-depth*.029)*daylight;
 vec2 p = sea_point.xz*.52;
 float warp = sea_clock*.26;
 float web_a = sin(p.x+sin(p.y*.86+warp)*1.9);
 float web_b = cos(p.y*1.13+sin(p.x*.75-warp)*1.7);
 float web = pow(1.0-abs(web_a*web_b),18.0);
 float caustic = web*attenuation*(masonry?.15:.30);
 vec3 haze = mix(vec3(.055,.24,.27),vec3(.012,.055,.095),smoothstep(8.0,65.0,depth));
 float distance_fade = 1.0-exp(-distance(CAMERA_POSITION_WORLD,sea_point)*mix(.018,.034,smoothstep(15.0,65.0,depth)));
 vec3 depth_tint = mix(vec3(.98,1.0,.88),vec3(.12,.32,.43),smoothstep(8.0,65.0,depth));
 ALBEDO = mix(base*depth_tint,haze,distance_fade*.90);
 EMISSION = base*(.10*attenuation+caustic)*(1.0-distance_fade) + haze*distance_fade*.12;
 NORMAL = normalize(mat3(VIEW_MATRIX)*normalize(mix(sea_normal,world_bump,.28)));
 ROUGHNESS = clamp(arm.g,.70,1.0); AO = arm.r;
}
