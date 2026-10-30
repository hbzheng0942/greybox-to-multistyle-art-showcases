shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Analytic 2D sprite: alpha-tested faces stay outside the playable circular mouth.
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 ink : source_color = vec4(0.045,0.05,0.10,1.0);
uniform int feature = 0; // eye, cheek, star, horn
uniform vec2 gaze = vec2(0.0);
uniform float blink = 0.0;
uniform float happy = 0.0;
float ellipse(vec2 p, vec2 r){return length(p/r)-1.0;}
void fragment(){
 vec2 p=UV*2.0-1.0;
 float shape=ellipse(p,vec2(.91,.94));
 vec3 col=tint.rgb;
 if(feature==0){
  // Broad ivory shape and one readable pupil; no tiny lines at G0.
  float pupil=ellipse(p-vec2(.07,-.04)-gaze,vec2(.45,.57));
  col=mix(col,ink.rgb,1.0-smoothstep(-.015,.035,pupil));
  float glint=ellipse(p-vec2(-.08,-.29)-gaze,vec2(.14,.14));
  col=mix(col,vec3(1.0),1.0-smoothstep(-.02,.05,glint));
  if(blink>.5){
   float arc=abs(p.y-(.06-.24*cos(p.x*2.8)))-.10;
   col=mix(tint.rgb,ink.rgb,(1.0-smoothstep(-.01,.025,arc))*(1.0-smoothstep(.58,.74,abs(p.x))));
  }
  col*=.93+.07*(1.0-clamp(length(p),0.0,1.0));
 }else if(feature==1){shape=ellipse(p,vec2(.93,.55));}
 else if(feature==2){
  float angle=atan(p.x,-p.y);
  float outline=.67+.20*cos(5.0*angle);
  shape=length(p)-outline;
  col*=.86+.14*clamp(1.0-p.y,0.0,1.0);
 }else{shape=max(abs(p.x)-(.55-.30*(-p.y)),abs(p.y)-.86);}
 float coverage=1.0-smoothstep(-.025,.025,shape);
 if(coverage<.5)discard;
 ALBEDO=col;
 ALPHA=coverage;
 ALPHA_SCISSOR_THRESHOLD=.5;
 ROUGHNESS=1.0;
}
