shader_type spatial;
render_mode cull_disabled;
uniform vec4 paint : source_color=vec4(0.5,0.2,0.4,1.0);
uniform float glow=0.0;
uniform float city_surface_light=0.0;
uniform float masonry=0.0;
uniform float graphic=0.0;
uniform float brush_mark=0.0;
uniform float surface_kind=0.0;
uniform sampler2D paint_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_mode=0.0;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}

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
 vec2 c=abs(wn.y)>0.65?wp.xz:(abs(wn.x)>abs(wn.z)?wp.zy:wp.xy);
 vec3 color=paint.rgb;
 float broad=noise(c*vec2(0.22,0.34));float brush=noise(c*vec2(1.1,4.5));
 color*=mix(0.78,1.12,smoothstep(0.2,0.8,broad));
 color=mix(color,color*vec3(1.13,0.82,0.91),step(0.68,brush)*0.25);
 if(masonry>0.5){
  float row=floor(c.y/1.2);vec2 grid=vec2(c.x/2.5+mod(row,2.0)*0.5,c.y/1.2);vec2 f=fract(grid);
  float mortar=(1.0-smoothstep(0.018,0.045,f.x))+(1.0-smoothstep(0.025,0.060,f.y));
  color*=mix(0.81,1.1,hash(floor(grid)));
  color=mix(color,color*0.24,clamp(mortar,0.0,1.0)*0.7);
  float edge=step(0.91,hash(floor(c*vec2(2.1,0.7))))*step(0.7,broad);color=mix(color,color*1.4,edge*0.35);
 }
 if(surface_kind>0.5&&surface_kind<1.5){float row=floor(c.y/1.25);vec2 f=fract(vec2(c.x/1.7+mod(row,2.0)*0.5,c.y/1.25));color*=mix(0.56,1.1,smoothstep(0.02,0.11,f.y));color*=mix(0.7,1.0,step(0.035,f.x));}
 if(texture_mode>0.5){
  vec2 tex_uv=texture_mode>1.5?UV:c/15.0;
  vec3 painted=texture(paint_texture,tex_uv).rgb;
  // Preserve the broad authored strokes; gentle palette variation is local to native masonry.
  vec3 tint=mix(vec3(1.0),paint.rgb/max(max(paint.r,paint.g),paint.b),0.23);
  vec3 palette=paint.rgb*mix(0.88,1.16,smoothstep(0.18,0.82,noise(c*0.075)));
  // A broad paint glaze softens black micro-cracks without blurring or replacing the authored brush strokes.
  color=mix(painted*tint*1.14,palette,0.29);
  color*=mix(0.94,1.07,smoothstep(0.3,0.7,noise(c*vec2(0.06,0.19))));
 }
 if(surface_kind>3.5){
  float broad_wear=noise(c*vec2(0.11,0.75));
  color*=mix(0.72,1.2,smoothstep(0.22,0.80,broad_wear));
  color=mix(color,vec3(0.27,0.17,0.19),smoothstep(0.68,0.90,broad_wear)*0.19);
 }
 if(brush_mark>0.5){
  float fibers=noise(vec2(UV.x*31.0,UV.y*3.0));
  if((UV.x<0.18||UV.x>0.82)&&fibers<0.43)discard;
  float split_a=abs(UV.x-0.29+sin(UV.y*14.0)*0.014);
  float split_b=abs(UV.x-0.69+sin(UV.y*18.0)*0.012);
  if((split_a<0.013&&UV.y>0.12&&UV.y<0.73)||(split_b<0.012&&UV.y>0.34&&UV.y<0.94))discard;
  color*=mix(0.74,1.16,smoothstep(0.15,0.8,fibers));
 }
 if(graphic>0.5){
  // Tall full-body wall paint with a torn hem and dry-brushed side edges; no rectangular sign background.
  vec2 p=vec2((UV.x-0.5)*2.0,UV.y);
  float wobble=sin(p.y*28.0)*0.018+sin(p.y*63.0)*0.008;
  float head=length(vec2(p.x/0.53,(p.y-0.25)/0.22));
  float torso=abs(p.x+wobble)/(0.49+0.07*sin(p.y*8.0));
  float body=max(1.0-smoothstep(0.96,1.0,head),(1.0-smoothstep(0.96,1.0,torso))*step(0.22,p.y)*step(p.y,0.91+0.065*sin(p.x*19.0)+0.025*sin(p.x*41.0)));
  if(body<0.5)discard;
  float eyes=(1.0-smoothstep(0.8,1.0,length((p-vec2(-0.19,0.25))/vec2(0.075,0.051))))+(1.0-smoothstep(0.8,1.0,length((p-vec2(0.19,0.25))/vec2(0.075,0.051))));
  float mouth=1.0-smoothstep(0.8,1.0,length((p-vec2(0.02,0.41))/vec2(0.075,0.067)));
  color=mix(vec3(0.43,0.40,0.32),vec3(0.035,0.018,0.047),clamp(eyes+mouth,0.0,1.0));
  color*=mix(0.89,1.04,noise(c*vec2(0.9,3.0)));
 }
 ALBEDO=color;ROUGHNESS=surface_kind>3.5?0.35:0.88;SPECULAR=0.55;EMISSION=color*glow;
 if(city_surface_light>0.0){EMISSION+=city_irradiance(wp,wn,color)*city_surface_light;}
}
void light(){float ndl=dot(NORMAL,LIGHT)+(noise(wp.xz*0.19)-0.5)*0.07;float band=mix(0.10,0.58,smoothstep(-0.04,0.08,ndl));band=mix(band,1.0,smoothstep(0.43,0.57,ndl));band*=smoothstep(0.0,0.12,max(dot(NORMAL,LIGHT),0.0));DIFFUSE_LIGHT+=LIGHT_COLOR*band*ATTENUATION/PI;if(surface_kind>3.5){vec3 h=normalize(LIGHT+VIEW);SPECULAR_LIGHT+=LIGHT_COLOR*pow(max(0.0,dot(NORMAL,h)),32.0)*ATTENUATION*0.32;}}
