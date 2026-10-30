shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec4 tint : source_color = vec4(0.96, 0.96, 0.90, 1.0);
uniform float drift_amplitude : hint_range(0.0, 1.0) = 0.12;
varying vec3 world_p;

void vertex() {
	// Bounded drift under 12 cm for low clouds, with no camera-dependent scaling.
	VERTEX.x += sin(TIME * 0.035 + VERTEX.z * 0.009) * drift_amplitude;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fiber = sin(world_p.x * 3.8 + sin(world_p.y * 5.2))
		* sin(world_p.z * 4.1 + world_p.y * 2.4);
	float fade = 1.0 - smoothstep(0.03, 0.25, length(fwidth(world_p)));
	ALBEDO = tint.rgb * COLOR.rgb * (1.0 + fiber * fade * 0.012);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
