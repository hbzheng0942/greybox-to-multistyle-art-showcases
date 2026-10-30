shader_type spatial;
uniform float review_time = -1.0;
render_mode unshaded,cull_disabled;
uniform vec4 accent:source_color=vec4(.15,.77,.92,1.);
void fragment(){
 vec2 p=(UV-.5)*2.;float r=length(p);if(r>.96){discard;}
 float angle=atan(p.y,p.x);
 float swirl=.5+.5*sin(angle*3.0+r*14.0-(review_time >= 0.0 ? review_time : TIME)*1.7);
 vec3 base=mix(vec3(.016,.026,.07),vec3(.055,.035,.16),r);
 base+=accent.rgb*.075*pow(swirl,5.)*smoothstep(.35,.95,r);
 // Small, planar mischievous eyes below the opening. No opaque disk across the rim.
 vec2 l=(p-vec2(-.26,-.06))/vec2(.15,.12);vec2 q=(p-vec2(.26,-.06))/vec2(.15,.12);
 float eyes=1.-smoothstep(.85,1.,min(length(l),length(q)));
 float brow=step(-.05+abs(p.x)*.25,p.y);
 eyes*=brow;
 base=mix(base,vec3(.78,.9,.96),eyes);
 float pupils=1.-smoothstep(.045,.062,min(length(p-vec2(-.23,.01)),length(p-vec2(.23,.01))));
 base=mix(base,vec3(.015,.035,.08),pupils);
 float smile=(1.-smoothstep(.014,.030,abs(length(p-vec2(0.,.1))-.30)))*step(.24,p.y)*step(abs(p.x),.27);
 base=mix(base,vec3(.35,.55,.84),smile);
 ALBEDO=base;
}
