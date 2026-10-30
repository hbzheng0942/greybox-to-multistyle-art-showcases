shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color:source_color=vec4(0.5,0.45,0.35,1.0);
uniform float metalness=0.0;
uniform bool floor_surface=false;
uniform bool striped=false;
uniform sampler2D cardboard_tex:source_color,repeat_enable;
uniform bool textured_cardboard=false;
varying vec3 world;
varying vec3 world_normal;
float h(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 block=floor(world*1.15);
 float broad=h(block);
 float patch=step(0.76,broad)*step(0.35,h(floor(world*3.5)));
 vec3 col=base_color.rgb*(0.90+0.17*broad);
 col=mix(col,col*0.62,patch*0.42);
 if(textured_cardboard){
  vec3 w=pow(abs(normalize(world_normal)),vec3(5.0));w/=max(w.x+w.y+w.z,.001);
  vec3 tex=texture(cardboard_tex,world.yz*.24).rgb*w.x+texture(cardboard_tex,world.xz*.24).rgb*w.y+texture(cardboard_tex,world.xy*.24).rgb*w.z;
  float marks=dot(tex,vec3(.299,.587,.114));
  col=mix(col,col*(.55+marks*.85),.78);
 }
 if(floor_surface){
  vec2 cell=fract(world.xz/4.2);
  float seam=step(0.985,cell.x)+step(0.986,cell.y);
  col*=1.0-min(seam,1.0)*0.18;
  col*=0.91+0.13*h(floor(world/4.2));
 }
 if(striped){float band=step(0.52,fract((world.x+world.z+world.y)*0.30));col=mix(col,vec3(.055,.065,.056),band*.87);}
 ALBEDO=col;
 METALLIC=metalness;
 ROUGHNESS=clamp(0.88-metalness*0.5+patch*0.13,0.25,1.0);
}
