shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;
uniform vec4 hole_a = vec4(0.0);
uniform vec4 hole_b = vec4(0.0);
uniform vec2 land_half_size = vec2(22.0,18.0);
uniform vec2 water_corner = vec2(-9.0,8.0);
uniform bool show_grid = false;
uniform float shore_margin = 0.18;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float rectmask(vec2 p,vec2 c,vec2 h){vec2 q=abs(p-c)-h;return 1.0-smoothstep(0.0,0.045,max(q.x,q.y));}
float segdist(vec2 p,vec2 a,vec2 b){vec2 d=b-a;return length(p-a-d*clamp(dot(p-a,d)/dot(d,d),0.0,1.0));}
void fragment(){
 vec2 p=world_position.xz;
 if(p.x<water_corner.x && p.y>water_corner.y){discard;}
 if(hole_a.w>0.5 && distance(p,hole_a.xy)<hole_a.z){discard;}
 if(hole_b.w>0.5 && distance(p,hole_b.xy)<hole_b.z){discard;}
 // Warm slate pavement, darker asphalt. No whitewashed slabs.
 vec3 sidewalk=vec3(0.43,0.46,0.46);
 vec3 asphalt=vec3(0.25,0.30,0.36);
 vec3 paving=vec3(0.49,0.50,0.43);
 float plaza=1.0-smoothstep(4.55,4.65,length(p-vec2(0.0,-3.0)));
 float ring=1.0-smoothstep(1.45,1.52,abs(length(p-vec2(0.0,-3.0))-6.30));
 float road=max(ring,rectmask(p,vec2(0.0,4.30),vec2(19.7,1.50)));
 road=max(road,rectmask(p,vec2(-7.30,-9.8),vec2(1.45,7.8)));
 road=max(road,rectmask(p,vec2(6.5,8.9),vec2(1.45,8.8)));
 vec3 color=mix(sidewalk,paving,plaza);
 color=mix(color,asphalt,road);
 vec2 tile=abs(fract(p*1.1)-.5);
 float seam=smoothstep(.470,.492,max(tile.x,tile.y));
 color*=1.0-seam*.075*(1.0-road);
 float dash=step(.40,fract(p.x*.40));
 float lane=(1.0-smoothstep(.018,.045,abs(p.y-4.3)))*dash*rectmask(p,vec2(0.,4.3),vec2(19.0,1.0));
 color=mix(color,vec3(.76,.65,.39),lane*.65);
 // Four readable crossings, drawn into the SAME hole-aware surface.
 float crossing=max(rectmask(p,vec2(-8.8,4.3),vec2(.9,1.36)),rectmask(p,vec2(8.0,4.3),vec2(.9,1.36)));
 crossing=max(crossing,rectmask(p,vec2(-7.3,-3.2),vec2(1.35,.85)));
 color=mix(color,vec3(.72,.72,.63),crossing*step(.43,fract(p.y*1.5))*.78);
 if(show_grid){
   vec2 cell=abs(fract(p-.5)-.5);vec2 aa=max(fwidth(p),vec2(.005));
   float grid=1.0-min(smoothstep(0.,aa.x,cell.x),smoothstep(0.,aa.y,cell.y));
   color=mix(color,vec3(.65,.75,.72),grid*.18);
   float dist=min(min(land_half_size.x-abs(p.x),p.y+land_half_size.y),land_half_size.y-p.y);
   dist=min(dist,segdist(p,vec2(-22.,8.),water_corner));
   dist=min(dist,segdist(p,water_corner,vec2(-9.,18.)));
   float safe=1.0-smoothstep(.035,.075,abs(dist-hole_a.z-shore_margin));
   color=mix(color,vec3(.3,.9,.8),safe*.9);
 }
 ALBEDO=color;EMISSION=color*.42;ROUGHNESS=1.;SPECULAR=0.;
}
void light(){DIFFUSE_LIGHT+=vec3(max(dot(NORMAL,LIGHT),0.)*ATTENUATION*.58);}
