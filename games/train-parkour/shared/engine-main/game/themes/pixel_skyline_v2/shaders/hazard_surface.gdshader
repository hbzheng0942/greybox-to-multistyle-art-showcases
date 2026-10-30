shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 warning_color : source_color = vec3(0.58,0.095,0.055);
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
    local_position=VERTEX;
    local_normal=NORMAL;
}
void fragment() {
    vec3 an=abs(local_normal);
    vec2 p=local_position.xy+vec2(0.5);
    if(an.x>an.z && an.x>an.y) {p=local_position.zy+vec2(0.5);}
    else if(an.y>an.z) {p=local_position.xz+vec2(0.5);}
    vec2 edge=min(p,1.0-p);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float detail=1.0-smoothstep(0.025,0.11,footprint);
    float border=1.0-smoothstep(0.035,0.055,min(edge.x,edge.y));
    vec3 color=mix(warning_color,vec3(0.19,0.23,0.29),border);
    float band=step(0.075,p.y)*(1.0-step(0.225,p.y));
    float chevron=step(0.48,fract(p.x*5.0+p.y*4.0));
    color=mix(color,mix(vec3(0.15,0.18,0.23),vec3(1.0,0.73,0.36),chevron*detail+0.5*(1.0-detail)),band);
    float center_panel=step(0.13,p.x)*step(p.x,0.87)*step(0.30,p.y)*step(p.y,0.88);
    color*=1.0-center_panel*0.26;
    float door_seam=(1.0-smoothstep(0.008,0.015,abs(p.x-0.5)))*center_panel;
    color=mix(color,vec3(0.16,0.19,0.23),door_seam*detail*0.7);
    float vent_zone=step(0.23,p.x)*step(p.x,0.77)*step(0.33,p.y)*step(p.y,0.52);
    float vents=(1.0-smoothstep(0.08,0.16,abs(fract(p.y*28.0)-0.5)))*vent_zone;
    color=mix(color,color*0.38,vents*detail);
    float handle=step(0.79,p.x)*step(p.x,0.84)*step(0.47,p.y)*step(p.y,0.59);
    color=mix(color,vec3(0.12,0.15,0.19),handle*detail);
    float bolt=1.0-smoothstep(0.012,0.025,length(edge-vec2(0.075)));
    color=mix(color,vec3(0.68,0.71,0.74),bolt*detail);
    float white_bar=step(0.31,p.x)*step(p.x,0.69)*step(0.63,p.y)*step(p.y,0.69);
    color=mix(color,vec3(1.0,0.86,0.73),white_bar);
    ALBEDO=color;
    ROUGHNESS=0.82;
    METALLIC=0.12;
    SPECULAR=0.20;
    EMISSION=warning_color*0.12+white_bar*vec3(0.12,0.09,0.04);
}
