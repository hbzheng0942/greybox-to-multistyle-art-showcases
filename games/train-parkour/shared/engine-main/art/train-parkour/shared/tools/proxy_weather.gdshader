shader_type spatial;
render_mode cull_back;
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float metalness = 0.0;
uniform float rough = 0.6;
uniform bool coarse = false;
uniform bool emissive = false;
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898,78.233,37.719))) * 43758.5453); }
void fragment() {
	float patch = hash(floor(world * (coarse ? 1.4 : 4.0)));
	float stain = hash(floor(world * vec3(0.55, 0.10, 0.55)));
	float value = coarse ? (0.86 + step(0.76, patch) * 0.2) : (0.76 + patch * 0.16 + stain * 0.18);
	ALBEDO = base_color.rgb * value;
	METALLIC = metalness;
	ROUGHNESS = rough;
	if (emissive) { EMISSION = base_color.rgb * 0.8; }
}
