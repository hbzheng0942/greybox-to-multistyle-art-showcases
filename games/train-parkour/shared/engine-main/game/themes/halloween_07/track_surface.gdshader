shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx;
// Rough ballast, creosoted sleepers and worn steel have separate responses.
uniform int finish=0;
varying vec3 wp;
varying vec3 wn;
varying vec3 ln;
void vertex(){ln=NORMAL;wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 vec2 p=abs(wn.y)>.65?wp.xz:(abs(wn.x)>abs(wn.z)?wp.zy:wp.xy);float broad=noise(p*.36);
 if(finish==0){
  vec2 cell=p*5.0;vec2 f=fract(cell);vec2 i=floor(cell);
  float nearest=8.;float second=8.;float seed=0.;
  for(int y=-1;y<=1;y++){for(int x=-1;x<=1;x++){
   vec2 g=vec2(float(x),float(y));vec2 offset=vec2(hash(i+g),hash(i+g+vec2(13.7,8.3)));
   float d=length(g+offset-f);
   if(d<nearest){second=nearest;nearest=d;seed=hash(i+g+4.2);}else{second=min(second,d);}
  }}
  float pebble=(1.-smoothstep(.22,.48,nearest))*smoothstep(.015,.05,second-nearest);
  float aa=1.-smoothstep(.3,1.,max(fwidth(cell.x),fwidth(cell.y)));
  vec3 c=mix(vec3(.055,.039,.067),vec3(.13,.085,.073),broad);
  ALBEDO=c*mix(1.,mix(.82,1.18,seed)*mix(.78,1.12,pebble),aa*.65);
  ROUGHNESS=.94;SPECULAR=.16;
 }else if(finish==1){
  float grain=noise(p*vec2(.65,20.));float cut=smoothstep(.72,.88,grain);
  ALBEDO=mix(vec3(.095,.052,.038),vec3(.23,.13,.077),broad)*mix(.8,1.2,grain)*(1.-cut*.28);
  ROUGHNESS=.82;SPECULAR=.22;
 }else{
  float worn=smoothstep(.35,.8,abs(ln.y));
  float scratches=noise(p*vec2(32.,.75));
  ALBEDO=mix(vec3(.10,.043,.026),vec3(.55,.60,.67),worn)*mix(.88,1.12,scratches);
  METALLIC=mix(.30,.50,worn);ROUGHNESS=mix(.72,.33,worn)+scratches*.09;SPECULAR=.5;
 }
}
