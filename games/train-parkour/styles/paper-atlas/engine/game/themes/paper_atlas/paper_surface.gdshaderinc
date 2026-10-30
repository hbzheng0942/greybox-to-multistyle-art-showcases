// Metre-scaled paper shared by tiny source GLBs and large procedural carriers.
varying vec3 paper_world;
float paper_hash(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7)))*43758.5453); }
float paper_noise(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(paper_hash(i),paper_hash(i+vec3(1,0,0)),f.x),mix(paper_hash(i+vec3(0,1,0)),paper_hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(paper_hash(i+vec3(0,0,1)),paper_hash(i+vec3(1,0,1)),f.x),mix(paper_hash(i+vec3(0,1,1)),paper_hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
vec2 paper_relief(vec3 p) {
 float footprint=length(fwidth(p));
 float pulp=(paper_noise(p*1.7)-0.5)/(1.0+footprint*2.0);
 float fibre=(paper_noise(p*vec3(11.0,3.0,9.0))-0.5)/(1.0+footprint*18.0);
 return vec2(pulp*0.075+fibre*0.045,pulp*0.028+fibre*0.006);
}
vec3 paper_normal(vec3 position,vec3 n,float height) {
 vec3 dpdx=dFdx(position),dpdy=dFdy(position);
 vec3 rx=cross(dpdy,n),ry=cross(n,dpdx);
 float determinant=dot(dpdx,rx);
 vec3 gradient=sign(determinant)*(dFdx(height)*rx+dFdy(height)*ry);
 return normalize(max(abs(determinant),0.000001)*n-gradient);
}
