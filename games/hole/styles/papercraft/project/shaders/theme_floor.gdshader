shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform vec4 hole_a=vec4(0.0);
uniform vec4 hole_b=vec4(0.0);
uniform vec2 land_half_size=vec2(22.0,18.0);
uniform vec2 water_corner=vec2(-9.0,8.0);
uniform bool show_grid=false;
uniform vec3 walkway_color=vec3(.85,.82,.72);
uniform vec3 paving_color=vec3(.92,.89,.79);
uniform vec3 asphalt_color=vec3(.30,.46,.51);
uniform vec3 kerb_color=vec3(.75,.73,.61);
uniform float surface_style=0.0;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float rectmask(vec2 p,vec2 c,vec2 h){vec2 q=abs(p-c)-h;return 1.0-smoothstep(0.0,.045,max(q.x,q.y));}
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
 vec2 p=world_position.xz;
 if(p.x<water_corner.x&&p.y>water_corner.y){discard;}
 if(hole_a.w>.5&&distance(p,hole_a.xy)<hole_a.z){discard;}
 if(hole_b.w>.5&&distance(p,hole_b.xy)<hole_b.z){discard;}
 float plaza=1.0-smoothstep(4.55,4.65,length(p-vec2(0.,-3.)));
 float ring=1.0-smoothstep(1.45,1.52,abs(length(p-vec2(0.,-3.))-6.30));
 float road=max(ring,rectmask(p,vec2(0.,4.30),vec2(19.7,1.50)));
 road=max(road,rectmask(p,vec2(-7.30,-9.8),vec2(1.45,7.8)));
 road=max(road,rectmask(p,vec2(6.5,8.9),vec2(1.45,8.8)));
 vec3 color=mix(mix(walkway_color,paving_color,plaza),asphalt_color,road);
 // Staggered broad blocks retain the exact walkable surface and opening masks.
 vec2 q=p*vec2(.72,.92);q.x+=step(.5,fract(floor(q.y)*.5))*.5;
 vec2 cell=floor(q);vec2 local=fract(q);
 float d=min(min(local.x,1.-local.x),min(local.y,1.-local.y));
 float aa=max(fwidth(q.x),fwidth(q.y));
 float seam=1.-smoothstep(.008,.016+aa,d);
 float variance=(hash21(cell)-.5)*.075;
 if(surface_style<.5){
   color*=1.+variance;
   color=mix(color,kerb_color*.79,seam*.32);
   float moss=step(.78,hash21(cell+19.))*seam;
   color=mix(color,vec3(.39,.47,.30),moss*.25*(1.-road));
 }else if(surface_style<1.5){
   color*=1.+variance*.42;
   color=mix(color,kerb_color*.64,seam*.55);
   float notch=rectmask(local,vec2(.16,.10),vec2(.11,.018));
   color=mix(color,paving_color,notch*.16);
 }else if(surface_style<2.5){
   color*=1.+variance*.48;
   color=mix(color,kerb_color,seam*.36);
 }else{
   color*=1.+variance*.23;
   color=mix(color,paving_color,seam*.48);
 }
 float inner=1.-smoothstep(.025,.07,abs(length(p-vec2(0.,-3.))-4.48));
 color=mix(color,kerb_color,inner*.7);
 if(show_grid){vec2 g=abs(fract(p)-.5);color=mix(color,vec3(.65,.8,.8),smoothstep(.485,.50,max(g.x,g.y))*.3);}
 ALBEDO=color;
 ROUGHNESS=.94;
 SPECULAR=.10;
}
