shader_type spatial;
render_mode unshaded,cull_front;
uniform float thickness=0.035;
// CUSTOM0.xyz is the unnormalized original instance basis * source NORMAL.
// The merged cell node has identity basis, so local extrusion remains equal.
void vertex(){VERTEX+=CUSTOM0.xyz*thickness;}
void fragment(){ALBEDO=vec3(0.018,0.009,0.045);}
