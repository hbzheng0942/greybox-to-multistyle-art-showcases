shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 base_color : source_color = vec3(0.23, 0.29, 0.40);
uniform vec2 panel_size = vec2(3.2, 5.0);
uniform bool industrial = false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
float hash_cell(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
    vec3 an=abs(world_normal);
    vec2 p=world_position.xz;
    if (an.x > an.y && an.x > an.z) { p=world_position.zy; }
    else if (an.z > an.y) { p=world_position.xy; }
    vec2 cell=floor(p/panel_size);
    vec2 within=fract(p/panel_size)*panel_size;
    vec2 edge=min(within,panel_size-within);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float detail=1.0-smoothstep(0.15,0.65,footprint);
    float seam=1.0-smoothstep(0.05,0.13,min(edge.x,edge.y));
    float band=step(0.88,hash_cell(cell))*0.06;
    vec3 color=base_color*(0.94+floor(hash_cell(cell+13.0)*3.0)*0.045);
    color=mix(color,base_color*0.40,seam*(1.0-smoothstep(0.35,1.2,footprint)));
    float fastener=1.0-smoothstep(0.065,0.12,length(edge-vec2(0.23)));
    color=mix(color,base_color*1.6,fastener*detail*0.7);
    if (industrial) {
        float inset=step(0.48,within.x)*step(0.48,panel_size.x-within.x)
          *step(0.70,within.y)*step(0.70,panel_size.y-within.y);
        color*=1.0-inset*band;
        float vent=step(0.82,hash_cell(cell+7.0))*inset
          *(1.0-smoothstep(0.03,0.10,abs(fract(within.y/0.6)-0.5)));
        color=mix(color,color*0.58,vent*detail);
    }
    ALBEDO=color;
    ROUGHNESS=0.86;
    METALLIC=0.12;
    SPECULAR=0.22;
}
