shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx;
uniform vec4 glass_color:source_color=vec4(.7,.22,.035,1.);
uniform float interior_light=.65;
void fragment(){
 vec2 p=UV;
 float pane=floor(p.x*6.);
 float ripple=sin(p.x*79.+sin(p.y*18.)*.8)*sin(p.y*52.)*.018;
 float edge=smoothstep(0.,.085,min(min(p.x,1.-p.x),min(p.y,1.-p.y)));
 float glow=pow(max(0.,1.-abs(p.y-.28)*1.15),1.5);
 float variation=.78+.22*sin(pane*2.7+1.2);
 vec3 tinted=glass_color.rgb*(.45+.55*glow)*variation;
 ALBEDO=tinted*.32+vec3(.012,.009,.023);ROUGHNESS=.48+ripple;METALLIC=.0;SPECULAR=.24;
 EMISSION=tinted*interior_light*mix(.38,1.,edge);
}
