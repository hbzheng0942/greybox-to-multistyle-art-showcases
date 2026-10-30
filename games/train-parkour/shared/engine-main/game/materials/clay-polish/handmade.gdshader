shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 clay_color : source_color = vec4(.8,.6,.45,1);
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
uniform sampler2D source_albedo : source_color, filter_linear_mipmap;
uniform sampler2D contact_map : filter_linear_mipmap, repeat_disable;
uniform sampler2D roughness_map : filter_linear_mipmap;
uniform sampler2D metal_map : filter_linear_mipmap;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform bool mapped_roughness = false;
uniform bool mapped_metal = false;
uniform bool mapped_normal = false;
uniform bool contact_uv2 = false;
uniform vec4 roughness_channel = vec4(0,1,0,0);
uniform vec4 metal_channel = vec4(0,0,1,0);
uniform vec4 contact_channel = vec4(1,0,0,0);
uniform vec2 source_uv_scale = vec2(1);
uniform vec2 source_uv_offset = vec2(0);
uniform float normal_strength = 1.0;
uniform float pigment_variation = 1.0;
uniform bool baked_contact = false;
uniform bool textured = false;
uniform bool remap_texture = false;
uniform bool stone = false;
uniform bool foliage = false;
uniform float roughness_value = .78;
uniform float roughness_floor = .15;
uniform float specular_strength = .45;
uniform float relief = .035;
uniform float coat = 0.0;
uniform float metal = 0.0;
uniform float emission_value = 0.0;
uniform float tiled = 0.0;
uniform int architecture_band = 0;
uniform vec4 terracotta_color : source_color = vec4(.9,.45,.25,1);
varying vec3 model_pos;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex(){
    model_pos=VERTEX;
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
float trinoise(vec3 p,vec3 w){
    return texture(grain,p.yz).r*w.x+texture(grain,p.xz).r*w.y+texture(grain,p.xy).r*w.z;
}
void fragment(){
    vec2 source_uv=UV*source_uv_scale+source_uv_offset;
    vec3 wn=normalize(world_normal);
    vec3 w=pow(abs(wn),vec3(5));w/=max(dot(w,vec3(1)),.0001);
    // Meter-based, shared across imported meshes and spline-generated track.
    float broad=trinoise(world_pos*.012,w);
    float press=trinoise(world_pos*.080,w);
    float fine=trinoise(world_pos*.47,w);
    float fade=1.-smoothstep(35.,150.,length(VERTEX));
    float pores=1.-smoothstep(.27,.40,fine);
    float tooling=1.-smoothstep(.025,.14,abs(press-.46));
    float seams=0.;
    if(tiled>.5){
        vec2 q=UV/vec2(2.2,3.2);q.x+=mod(floor(q.y),2.)*.5;
        vec2 edge=min(fract(q),1.-fract(q));
        float aa=max(fwidth(q.x),fwidth(q.y));
        seams=1.-smoothstep(.004,.016+aa,min(edge.x,edge.y));
    }
    float h=((broad-.5)*.85+(press-.5)*.7-(tooling*.1+pores*.15)*fade)*relief-seams*.024;
    vec3 dx=dFdx(world_pos),dy=dFdy(world_pos);
    vec3 r1=cross(dy,wn),r2=cross(wn,dx);float det=dot(dx,r1);
    vec3 grad=sign(det)*(dFdx(h)*r1+dFdy(h)*r2);
    NORMAL=normalize(mat3(VIEW_MATRIX)*normalize(max(abs(det),.000001)*wn-grad));
    if(mapped_normal){
        NORMAL_MAP=texture(normal_map,source_uv).rgb;
        NORMAL_MAP_DEPTH=normal_strength;
    }
    vec3 base=clay_color.rgb*COLOR.rgb;
    if(architecture_band>0){
        float paint=step(1.45,model_pos.y)*(1.-step(9.6,model_pos.y));
        if(architecture_band==2)paint*=step(24.5,abs(model_pos.x));
        base=mix(base,terracotta_color.rgb,paint);
    }
    if(textured){
        vec3 source=texture(source_albedo,source_uv).rgb;
        if(foliage)source=source*vec3(.82,1.16,.95)+vec3(.008,.022,.012);
        base*=remap_texture?vec3(mix(.83,1.12,dot(source,vec3(.333)))):source;
    }
    float contact=baked_contact?clamp(dot(texture(contact_map,contact_uv2?UV2:source_uv),contact_channel),.22,1.):1.;
    float mottling=mix(1.,mix(.87,1.08,broad)*mix(.97,1.03,press),pigment_variation);
    // Occlusion is independent of the pigment; no baked directional lighting.
    ALBEDO=base*mottling*(1.-pores*.025*fade)*(1.-seams*.12);
    float rough=roughness_value*(mapped_roughness?dot(texture(roughness_map,source_uv),roughness_channel):1.);
    ROUGHNESS=clamp(rough+(press-.5)*(mapped_roughness?.045:.18),roughness_floor,.98);
    SPECULAR=specular_strength;METALLIC=metal*(mapped_metal?dot(texture(metal_map,source_uv),metal_channel):1.);
    CLEARCOAT=coat;CLEARCOAT_ROUGHNESS=.35;
    AO=contact*(1.-pores*.12*fade-seams*.26);AO_LIGHT_AFFECT=.32;
    EMISSION=clay_color.rgb*emission_value;
}
