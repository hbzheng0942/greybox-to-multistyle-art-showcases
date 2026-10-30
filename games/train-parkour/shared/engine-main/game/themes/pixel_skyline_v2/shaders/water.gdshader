shader_type spatial;
render_mode unshaded;
uniform vec3 deep : source_color = vec3(.08,.135,.25);
uniform vec3 blue : source_color = vec3(.145,.23,.36);
uniform vec3 violet : source_color = vec3(.28,.24,.40);
uniform vec3 sunset : source_color = vec3(.90,.43,.34);
uniform vec3 gold : source_color = vec3(1.0,.69,.39);
uniform bool calm_groups=false;
varying vec3 world_position;
float hash2(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 // Small separated wavelets with quiet negative space; fixed world cells.
 vec2 p=world_position.xz;
 vec2 grid=calm_groups?vec2(12.,5.2):vec2(3.6,1.8);
 float row=floor(p.y/grid.y);
 p.x+=hash2(vec2(row,11.0))*2.7;
 vec2 cell=floor(p/grid);
 vec2 inside=mod(p,grid)-grid*.5;
 float h=hash2(cell);
 float footprint=max(length(dFdx(world_position.xz)),length(dFdy(world_position.xz)));
 float aa=clamp(footprint*.5,.035,.3);
 float extent=calm_groups?1.8+2.8*h:.65+h;
 float thickness=calm_groups?.24:.13;
 float streak=(1.0-smoothstep(extent-aa,extent+aa,abs(inside.x)))
   *(1.0-smoothstep(thickness-aa,thickness+aa,abs(inside.y)))*step(calm_groups?.79:.67,h);
 streak*=1.0-smoothstep(.4,1.8,footprint);
 vec3 view_dir=normalize(world_position-INV_VIEW_MATRIX[3].xyz);
 float towards=dot(normalize(view_dir.xz),normalize(vec2(-.56,-.825)));
 float path=pow(max(towards,0.0),14.0);
 if(calm_groups){streak*=.35+.65*path;}
 vec3 wave=mix(blue,violet,step(.88,h));
 wave=mix(wave,sunset,path*.80);
 wave=mix(wave,gold,path*step(.94,h)*.80);
 ALBEDO=mix(deep,deep+violet*.075,path)+streak*(wave-deep);
}
