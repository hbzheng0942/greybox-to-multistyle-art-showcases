shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx;
// T2 only: original textured paint with a bounded, train-local visibility floor.
uniform sampler2D albedo_texture : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D metallic_roughness : filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 albedo_factor : source_color=vec4(1.0);
uniform float metallic_factor=1.0;
uniform float roughness_factor=1.0;
uniform mat4 mesh_to_train;
uniform vec3 train_size=vec3(2.65,2.784,10.452);
varying vec3 train_p;
varying vec3 train_n;
void vertex(){
 train_p=(mesh_to_train*vec4(VERTEX,1.0)).xyz;
 train_n=normalize(mat3(mesh_to_train)*NORMAL);
}
void fragment(){
 vec3 paint=texture(albedo_texture,UV).rgb*albedo_factor.rgb;
 vec3 mr=texture(metallic_roughness,UV).rgb;
 ALBEDO=paint;
 METALLIC=mr.b*metallic_factor;
 ROUGHNESS=clamp(mr.g*roughness_factor,0.45,1.0);
 // End-local and achromatic: white cloth emits softly; dark mouth and pupils stay dark.
 float end=smoothstep(0.405,0.455,abs(train_p.z)/train_size.z);
 float cloth=smoothstep(0.22,0.58,min(paint.r,min(paint.g,paint.b)));
 float face=end*cloth*(1.0-smoothstep(0.81,0.91,train_p.y/train_size.y));
 float iris=end*smoothstep(1.12,1.65,paint.g/max(paint.r,0.015))*smoothstep(0.12,0.38,paint.g);
 // A low cool bounce on the upper body preserves paint and surface shading.
 float upper=smoothstep(0.36,0.72,train_p.y/train_size.y);
 float sky=max(train_n.y,0.0)*0.75+abs(train_n.x)*0.20;
 EMISSION=paint*(vec3(0.12)+vec3(0.22,0.30,0.42)*upper*sky);
 EMISSION+=paint*vec3(0.62,0.84,0.90)*face;
 EMISSION+=paint*vec3(0.40,0.90,0.65)*iris;
}
void light(){
 float ndl=dot(NORMAL,LIGHT);
 float band=mix(0.12,0.57,smoothstep(-0.04,0.11,ndl));
 band=mix(band,1.0,smoothstep(0.46,0.61,ndl));
 band*=smoothstep(0.0,0.12,max(ndl,0.0));
 DIFFUSE_LIGHT+=LIGHT_COLOR*band*ATTENUATION/PI;
 vec3 half_vector=normalize(LIGHT+VIEW);
 SPECULAR_LIGHT+=LIGHT_COLOR*pow(max(0.0,dot(NORMAL,half_vector)),20.0)*ATTENUATION*0.09;
}
