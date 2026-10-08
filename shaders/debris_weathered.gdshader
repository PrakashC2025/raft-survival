shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.5,0.4,0.3,1.0);
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D timber_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform int surface_kind = 0;
uniform float detail_scale = 1.0;
uniform bool horizontal_wood = false;
uniform bool timber_atlas = false;
uniform bool barrel = false;
varying vec3 local_position;
float hash(vec3 p) { p=fract(p*0.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z); }
float noise(vec3 p) {
	vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { local_position=VERTEX*detail_scale; }
void fragment() {
	vec3 p=local_position;
	float broad=noise(p*12.0),fine=noise(p*155.0);
	vec3 color=base_color.rgb*COLOR.rgb;
	if (has_texture) color*=texture(source_texture,UV).rgb;
	int kind=surface_kind;
	if (barrel && has_texture && max(color.r,max(color.g,color.b))-min(color.r,min(color.g,color.b))<0.12 && color.r>0.35) kind=1;
	float relief=fine*0.25;
	float rough=0.78,metal=0.0;
	if (kind==0) {
		if (timber_atlas) {
			float along=horizontal_wood?p.z:p.y;
			float around=horizontal_wood?atan(p.y,p.x):atan(p.z,p.x);
			color=texture(timber_texture,vec2(along*0.9,(2.08+fract(around/6.2831853)*0.80)*0.25),0.3).rgb*0.78;
		}
		float grain=noise(p*(horizontal_wood ? vec3(90.0,65.0,4.0) : vec3(90.0,4.0,65.0)));
		float cracks=pow(abs(sin(p.x*210.0+grain*6.0)),24.0)*smoothstep(0.35,0.75,broad);
		color*=0.70+grain*0.38+fine*0.13;
		color=mix(color,vec3(0.32,0.28,0.22),smoothstep(0.58,0.85,broad)*0.3);
		color*=1.0-cracks*0.3;relief=grain+cracks*0.4;rough=0.82;
		if (horizontal_wood && abs(NORMAL.z)>0.75) {
			float rings=sin(length(p.xy)*420.0+grain*2.0)*0.5+0.5;
			color*=0.84+rings*0.18;
		}
	} else if (kind==1) {
		float rust=smoothstep(0.35,0.74,broad);
		color=mix(color*(0.8+fine*0.35),vec3(0.27,0.075,0.018)*(0.8+fine*0.5),rust*0.8);
		metal=0.75*(1.0-rust);rough=0.38+rust*0.5;relief=fine*0.5;
	} else if (kind==2) {
		color*=0.65+broad*0.5+fine*0.25;relief=broad+fine;rough=0.9;
	} else if (kind==3) {
		float weave=sin(p.x*570.0)*sin(p.y*570.0);
		float resolved=1.0-smoothstep(0.4,1.4,length(fwidth(p.xy*570.0)));
		color*=0.75+broad*0.25+weave*0.06*resolved;relief=weave*resolved*0.2;rough=0.95;
		float fibres=sin((p.x+p.z)*260.0+p.y*75.0)*sin(p.y*190.0);
		color*=0.94+fibres*0.06;relief+=fibres*0.12;
	} else {
		float scratches=smoothstep(0.8,0.96,noise(p*vec3(8.0,185.0,70.0)));
		color=mix(color*(0.83+broad*0.24),vec3(0.67,0.67,0.57),scratches*0.35);
		rough=0.45+broad*0.25;relief=scratches*0.3;
	}
	// Damp lower surfaces and salt bleaching break up uniform toy-like colors.
	float damp=1.0-smoothstep(-0.10,0.13,p.y);
	ALBEDO=color*(1.0-damp*0.13);
	ROUGHNESS=clamp(rough-damp*0.12,0.2,0.98);METALLIC=metal;SPECULAR=0.35;
	NORMAL_MAP=normalize(vec3(-dFdx(relief)*0.2,-dFdy(relief)*0.2,1.0))*0.5+0.5;
	NORMAL_MAP_DEPTH=0.2;
}
