shader_type sky;
render_mode use_debanding;
float hash(vec3 p){p=fract(p*.3183099+vec3(.1,.2,.3));p*=17.;return fract(p.x*p.y*p.z*(p.x+p.y+p.z));}
float noise(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void sky(){
 vec3 d=normalize(EYEDIR);
 float horizon=pow(1.-max(d.y,0.),3.);
 vec3 blue=mix(vec3(.10,.32,.64),vec3(.42,.66,.86),horizon);
 vec3 p=d*9.+vec3(2.7,.7,1.8);
 float a=noise(p),b=noise(p*2.2),c=noise(p*4.6);
 float field=a*.66+b*.24+c*.10;
 float band=smoothstep(.005,.085,d.y)*(1.-smoothstep(.4,.75,d.y));
 float cloud=smoothstep(.67,.77,field)*band*.025;
 vec3 cloud_color=mix(vec3(.52,.59,.71),vec3(1.10,1.03,.91),smoothstep(.60,.74,field));
 COLOR=mix(blue,cloud_color,cloud);
 if(d.y<0.)COLOR=mix(vec3(.42,.58,.67),vec3(.24,.17,.12),smoothstep(0.,.5,-d.y));
}
