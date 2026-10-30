shader_type spatial;
render_mode unshaded,cull_front;
uniform float thickness=0.035;
void vertex(){VERTEX+=NORMAL*thickness;}
void fragment(){ALBEDO=vec3(0.018,0.009,0.045);}
