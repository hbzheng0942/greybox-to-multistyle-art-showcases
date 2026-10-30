shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Material-only bands on the original frozen body mesh; pivot and silhouette stay intact.
uniform vec4 ivory : source_color = vec4(0.97, 0.80, 0.74, 1.0);
uniform vec4 coral : source_color = vec4(0.93, 0.31, 0.29, 1.0);
uniform vec4 underbody : source_color = vec4(0.15, 0.19, 0.28, 1.0);
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 paint = mix(coral.rgb, ivory.rgb, step(-0.12, local_position.y));
	paint = mix(underbody.rgb, paint, step(-1.02, local_position.y));
	ALBEDO = paint;
	METALLIC = 0.12;
	ROUGHNESS = 0.74;
}
