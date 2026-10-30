shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D sprite_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float blink = 0.0;
uniform float bite_pulse = 0.0;
uniform vec2 gaze = vec2(0.0);
uniform bool face = false;
uniform float mouth_ratio = .95;
varying vec2 plane;
void vertex(){plane=VERTEX.xy;}
void fragment(){
 float radius=length(plane);
 // Keep the complete functional mouth uncapped. Flatten the source's elliptical
 // painted opening onto the same exact circle as the floor cut and swallow fit.
 if(!face && (radius<mouth_ratio || radius>1.235))discard;
 vec2 direction=vec2(plane.x,-plane.y)/radius;
 vec2 inner=vec2(625.0,648.0)+direction*vec2(409.0,366.0);
 vec2 outer=vec2(625.0,632.0)+direction*vec2(516.0,516.0);
 float t=(radius-mouth_ratio)/(1.225-mouth_ratio);
 vec2 pixel=face?mix(vec2(503.0,148.0),vec2(752.0,284.0),UV):mix(inner,outer,t);
 vec4 col=texture(sprite_texture,pixel/1254.0);
 if(col.a<.5)discard;
 // Only the illustrated eyes animate. The center remains actual visible depth.
 vec2 eye0=(pixel-vec2(562.0,215.0))/vec2(50.0,58.0);
 vec2 eye1=(pixel-vec2(692.0,215.0))/vec2(50.0,58.0);
 vec2 eye=length(eye0)<length(eye1)?eye0:eye1;
 if(!face && length(eye)<1.10){
  vec3 upper=texture(sprite_texture,vec2(pixel.x,140.0)/1254.0).rgb;
  vec3 lower=texture(sprite_texture,vec2(pixel.x,279.0)/1254.0).rgb;
  col.rgb=mix(upper,lower,clamp((pixel.y-140.0)/139.0,0.0,1.0));
 }
 if(face){
  if(length(eye)>1.01)discard;
 }
 if(face && blink>.5){
  float arc=abs(eye.y-(.1-.24*eye.x*eye.x));
  float ink=(1.0-smoothstep(.07,.13,arc))*(1.0-smoothstep(.72,.84,abs(eye.x)));
  if(ink<.5)discard;
  col.rgb=vec3(.15,.09,.23);
 }
 float luma=dot(col.rgb,vec3(.2126,.7152,.0722));
 ALBEDO=mix(vec3(luma),col.rgb,.86)*(1.0+bite_pulse*.035);
 ALPHA=col.a;
 ALPHA_SCISSOR_THRESHOLD=.5;
}
