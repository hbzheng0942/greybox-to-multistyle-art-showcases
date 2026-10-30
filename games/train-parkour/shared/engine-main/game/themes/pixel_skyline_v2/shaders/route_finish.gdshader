shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
// Unit-box MultiMesh coordinates follow each frozen support frame, even in a loop.
uniform vec3 base_color : source_color = vec3(.08,.12,.21);
uniform vec3 light_color : source_color = vec3(.38,.52,.70);
uniform int role = 0; // 0 deck, 1 rail, 2 structural steel
varying vec3 local_position;
varying vec3 local_normal;
varying flat vec3 instance_size;
void vertex() {
    local_position=VERTEX;
    local_normal=NORMAL;
    instance_size=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
}
float rect(vec2 p, vec2 half_size, float aa) {
    vec2 d=abs(p)-half_size;
    return 1.0-smoothstep(-aa,aa,max(d.x,d.y));
}
void fragment() {
    vec3 color=base_color;
    vec3 m=local_position*instance_size;
    float emissive=0.0;
    if(role==0) {
        vec2 p=m.xz;
        float footprint=max(length(dFdx(p)),length(dFdy(p)));
        float aa=clamp(footprint*.6,.015,.18);
        float detail=1.0-smoothstep(.22,.9,footprint);
        float lane=abs(mod(m.x+2.2,4.4)-2.2);
        // Deep running channels, broad quiet paving between them.
        float trough=1.0-smoothstep(.83-aa,.83+aa,lane);
        color=mix(base_color,base_color*.43,trough);
        float shoulder=smoothstep(1.00-aa,1.00+aa,lane)*(1.0-smoothstep(1.12-aa,1.12+aa,lane));
        color=mix(color,light_color,shoulder*.23*detail);
        float end=(.5-abs(local_position.z))*instance_size.z;
        float seam=1.0-smoothstep(.045,.045+aa,end);
        color=mix(color,base_color*.40,seam*.45*detail);
        float lip=smoothstep(.07,.07+aa,end)*(1.0-smoothstep(.14,.14+aa,end));
        color=mix(color,light_color,lip*.16*detail*(1.0-trough));
        // A single broad inspection plate in each inter-lane sheet.
        float plate=rect(vec2(lane-1.63,m.z),vec2(.31,min(.65,instance_size.z*.22)),aa);
        color=mix(color,base_color*.72,plate*.55*detail);
        float socket=rect(vec2(lane-1.63,abs(m.z)-.48),vec2(.09,.055),aa);
        color=mix(color,light_color,socket*.28*detail);
        color*=mix(.52,1.0,step(.5,local_normal.y));
    } else if(role==1) {
        float top=step(.5,local_normal.y);
        color=base_color*mix(.35,.86,top);
        float edge=1.0-smoothstep(.18,.45,abs(local_position.x));
        color=mix(color,light_color,edge*top*.58);
        // Hardware remains blue/gold at every distance; no dark signal gaps.
        float joint=step(.475,abs(local_position.z));
        color=mix(color,base_color*.60,joint*.38);
        emissive=.10*top;
    } else {
        vec3 a=abs(local_normal);
        vec2 p=a.x>a.z?m.zy:m.xy;
        vec2 size=a.x>a.z?instance_size.zy:instance_size.xy;
        float aa=clamp(max(length(dFdx(p)),length(dFdy(p)))*.5,.02,.24);
        vec2 edge=size*.5-abs(p);
        float border=1.0-smoothstep(.14,.14+aa,min(edge.x,edge.y));
        color=mix(base_color,light_color,border*.32);
        float shoe=1.0-smoothstep(.65,.65+aa,edge.y);
        color=mix(color,base_color*.45,shoe*.72);
        float plate=rect(vec2(p.x,p.y+size.y*.22),vec2(size.x*.27,min(1.15,size.y*.16)),aa);
        color=mix(color,base_color*.72,plate*.60);
    }
    ALBEDO=color;ROUGHNESS=1.0;METALLIC=0.0;
    EMISSION=color*vec3(.32,.37,.52)+color*emissive;
}
void light() {
    float n=max(dot(NORMAL,LIGHT),0.0);
    float w=clamp(fwidth(n),.025,.10);
    float bands=.24+.38*smoothstep(.28-w,.28+w,n)+.38*smoothstep(.68-w,.68+w,n);
    DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*bands*.85/PI;
}
