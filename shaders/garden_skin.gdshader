shader_type spatial;
render_mode cull_disabled;
uniform vec4 skin_color : source_color = vec4(.7,.18,.035,1);
uniform int kind = 0;
uniform bool leaf = false;
uniform bool pulp = false;
uniform bool wet = false;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
    vec2 p=UV;
    float grain=hash(floor(p*vec2(160.,120.)));
    vec3 color=skin_color.rgb;
    float rough=.53;
    if (leaf) {
        float mid=1.-smoothstep(.012,.035,abs(p.x-.5));
        float ribs=1.-smoothstep(.035,.09,abs(sin(p.y*38.+abs(p.x-.5)*20.)));
        float edge=smoothstep(0.,.16,p.x)*smoothstep(0.,.16,1.-p.x);
        color*=.70+edge*.20+grain*.08;
        color=mix(color,color*1.30+vec3(.03,.045,.012),mid*.45+ribs*.16);
        rough=.87;
    } else {
        color*=.86+grain*.16+.07*sin(p.x*38.+p.y*9.);
        if(kind==2) color*=.85+.15*sin(p.x*48.);
        if(kind==3) {
            vec2 cell=fract(p*vec2(13.,17.))-.5;
            float seed=1.-smoothstep(.11,.18,length(cell*vec2(1.,.6)));
            color=mix(color,vec3(.64,.40,.11),seed*.8);
        }
        if(kind==4) {
            vec2 cell=fract(p*vec2(12.,20.));
            float groove=smoothstep(.03,.12,cell.x)*smoothstep(.03,.12,cell.y);
            color*=.72+.28*groove;
        }
        if(pulp) { color=mix(color,skin_color.rgb*1.18,.65); rough=.36; }
        if(wet) rough=.22;
    }
    ALBEDO=color;
    ROUGHNESS=rough;
    SPECULAR=.34;
}
