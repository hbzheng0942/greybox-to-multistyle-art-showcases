shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx;
uniform sampler2D albedo_texture : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D metallic_roughness : filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 albedo_factor : source_color=vec4(1.0);
uniform float metallic_factor=1.0;
uniform float roughness_factor=1.0;
uniform float warm_emission=0.0;
uniform float city_surface_light=0.0;
uniform float readability_emission=0.0;
uniform float hazard_pink_emission=0.0;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}

vec3 city_irradiance(vec3 p,vec3 n,vec3 base){
 float region=smoothstep(430.0,580.0,p.z)*(1.0-smoothstep(1600.0,1780.0,p.z));
 float low=1.0-smoothstep(28.0,126.0,p.y);
 float side=1.0-smoothstep(0.10,0.62,n.y);
 float facing=0.30+0.70*max(0.0,dot(n,normalize(vec3(-p.x,22.0-p.y,20.0))));
 float district=0.65+0.35*pow(0.5+0.5*sin(p.z*0.031+p.x*0.017),2.0);
 float street=1.0-smoothstep(150.0,300.0,abs(p.x));
 float value=dot(base,vec3(0.2126,0.7152,0.0722));
 vec3 diffuse=mix(base,vec3(value),0.70);
 vec3 hue=mix(vec3(6.5,1.25,0.30),vec3(5.2,0.60,3.1),smoothstep(24.0,80.0,p.y));
 return diffuse*hue*low*side*facing*district*region*street;
}

void fragment(){
 vec4 paint=texture(albedo_texture,UV)*albedo_factor;
 vec3 mr=texture(metallic_roughness,UV).rgb;
 ALBEDO=paint.rgb;
 METALLIC=mr.b*metallic_factor;
 ROUGHNESS=clamp(mr.g*roughness_factor,0.45,1.0);
 // Orange window pixels gain warm spill without replacing the painted albedo or its detail.
 float mask=smoothstep(1.35,1.9,paint.r/max(paint.g,0.015))*smoothstep(1.2,1.8,paint.g/max(paint.b,0.015))*smoothstep(0.35,0.65,paint.r);
 float pink=smoothstep(2.0,4.0,paint.r/max(paint.g,0.008))*smoothstep(1.8,3.0,paint.b/max(paint.g,0.008))*smoothstep(0.05,0.16,max(paint.r,paint.b));
 EMISSION=paint.rgb*(mask*warm_emission+readability_emission+pink*hazard_pink_emission);
 if(city_surface_light>0.0){EMISSION+=city_irradiance(wp,wn,paint.rgb)*city_surface_light;}
}

void light(){
 float stroke=sin(wp.x*0.31+sin(wp.y*0.23))*sin(wp.z*0.19+wp.y*0.27)*0.025;
 float ndl=dot(NORMAL,LIGHT)+stroke;
 float band=mix(0.12,0.57,smoothstep(-0.04,0.11,ndl));
 band=mix(band,1.0,smoothstep(0.46,0.61,ndl));
 band*=smoothstep(0.0,0.12,max(dot(NORMAL,LIGHT),0.0));
 DIFFUSE_LIGHT+=LIGHT_COLOR*band*ATTENUATION/PI;
 vec3 half_vector=normalize(LIGHT+VIEW);
 SPECULAR_LIGHT+=LIGHT_COLOR*pow(max(0.0,dot(NORMAL,half_vector)),20.0)*ATTENUATION*0.09;
}
