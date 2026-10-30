shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
uniform int role=0; // 0 obstacle cabinet, 1 advance-warning plate, 2 no-entry sign
uniform vec3 mesh_size=vec3(1.0);
uniform vec3 red : source_color=vec3(.78,.17,.14);
uniform vec3 dark : source_color=vec3(.055,.075,.13);
uniform vec3 cream : source_color=vec3(1.0,.83,.59);
varying vec3 p;
varying vec3 n;
void vertex(){p=VERTEX/mesh_size;n=NORMAL;}
float box(vec2 q,vec2 size,float aa){vec2 d=abs(q)-size;return 1.0-smoothstep(-aa,aa,max(d.x,d.y));}
void fragment(){
    vec3 an=abs(n);
    vec2 q=an.y>an.x&&an.y>an.z?p.xz:(an.x>an.z?p.zy:p.xy);
    float aa=clamp(max(length(dFdx(q)),length(dFdy(q)))*.65,.003,.06);
    float detail=1.0-smoothstep(.03,.10,aa);
    vec2 edge=.5-abs(q);
    float border=1.0-smoothstep(.035,.055,min(edge.x,edge.y));
    vec3 color=mix(red,dark,border);
    float lip=(1.0-smoothstep(.065,.085,edge.y))*(1.0-border);
    color=mix(color,cream,lip*.28);
    float symbol=0.0;
    if(role==1){
        // Non-directional lane-closed cross, never a boost/receive arrow.
        float cross_mark=1.0-smoothstep(.048,.048+aa,abs(abs(q.x)-abs(q.y)));
        color=mix(color,dark,cross_mark*box(q,vec2(.34),aa)*.88);
        float bolt=box(abs(q)-vec2(.39),vec2(.018),aa)*detail;
        color=mix(color,cream,bolt*.55);
    }else if(role==2){
        // The frozen raised white bar is retained on top of this rimmed sign.
        color=mix(color,red*.72,box(q,vec2(.37,.32),aa)*.38);
    }else{
        float panel=box(q-vec2(0.,.05),vec2(.35,.33),aa);
        color=mix(color,red*.66,panel);
        float band=box(q-vec2(0.,-.34),vec2(.40,.055),aa);
        float stripes=smoothstep(.46,.54,fract(q.x*4.+q.y*3.));
        color=mix(color,mix(dark,cream,stripes*detail),band);
        symbol=box(q-vec2(0.,.19),vec2(.18,.038),aa);
        color=mix(color,cream,symbol);
        float seam=box(q-vec2(0.,-.08),vec2(.008,.15),aa)*detail;
        float handle=box(q-vec2(.245,-.045),vec2(.025,.055),aa)*detail;
        color=mix(color,dark,max(seam,handle));
        float foot=box(q-vec2(0.,-.455),vec2(.48,.03),aa);
        color=mix(color,dark,foot);
    }
    ALBEDO=color;ROUGHNESS=1.0;METALLIC=0.0;
    EMISSION=color*.40+cream*symbol*.12;
}
void light(){
    float n_dot=max(dot(NORMAL,LIGHT),0.0);
    float w=clamp(fwidth(n_dot),.025,.1);
    float bands=.25+.4*smoothstep(.25-w,.25+w,n_dot)+.35*smoothstep(.65-w,.65+w,n_dot);
    DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*bands*.8/PI;
}
