shader_type spatial;
render_mode cull_disabled;
uniform vec4 accent : source_color = vec4(.54,.50,.87,1.0);
uniform float growth01 = 0.0;
uniform float bite_pulse = 0.0;
uniform float alive = 1.0;
void fragment(){
 ALBEDO=accent.rgb*(1.0+bite_pulse*.06)*(alive>.5?1.0:.55);
 ROUGHNESS=.86;
 SPECULAR=.12;
}
