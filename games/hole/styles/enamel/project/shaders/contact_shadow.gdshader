shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 shadow_color : source_color = vec4(0.20, 0.23, 0.36, 1.0);
uniform float strength = 0.18;
uniform vec4 hole_a = vec4(0.0);
uniform vec4 hole_b = vec4(0.0);
uniform vec2 land_half_size = vec2(22.0, 18.0);
uniform vec2 water_corner = vec2(-9.0, 8.0);
varying vec2 world_xz;
varying float weight;
void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	weight = INSTANCE_CUSTOM.r;
}
void fragment() {
	if (abs(world_xz.x) > land_half_size.x || abs(world_xz.y) > land_half_size.y) { discard; }
	if (world_xz.x < water_corner.x && world_xz.y > water_corner.y) { discard; }
	if (hole_a.w > 0.5 && distance(world_xz, hole_a.xy) < hole_a.z) { discard; }
	if (hole_b.w > 0.5 && distance(world_xz, hole_b.xy) < hole_b.z) { discard; }
	vec2 q = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.24, 1.0, length(q));
	ALBEDO = shadow_color.rgb;
	ALPHA = edge * edge * strength * weight;
}
