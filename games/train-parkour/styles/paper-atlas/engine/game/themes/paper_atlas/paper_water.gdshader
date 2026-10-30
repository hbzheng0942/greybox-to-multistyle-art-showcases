shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Opaque dyed paper: no screen refraction, mirror highlights or alpha planes.
uniform vec4 tint : source_color = vec4(0.25, 0.66, 0.72, 1.0);
uniform bool waterfall = false;
uniform bool world_flow = false;
uniform bool layer_colors = false;
uniform float motion_strength : hint_range(0.0, 1.0) = 0.22;
varying vec3 world_p;

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 paper = tint.rgb;
	float fiber = sin(world_p.x * 5.1 + sin(world_p.z * 3.7))
		* sin(world_p.z * 7.3 + world_p.y * 3.2);
	float fiber_fade = 1.0 - smoothstep(0.025, 0.22, length(fwidth(world_p)));
	if (layer_colors) {
		paper *= COLOR.rgb;
	}
	if (waterfall) {
		// UV.x is across the actual folded ribbons, UV.y is downward distance.
		float across = world_flow ? (world_p.x + world_p.z * 0.27) * 0.12 : UV.x;
		float down = world_flow ? -world_p.y : UV.y;
		float pleat = 0.5 + 0.5 * cos(across * 31.4159);
		float flow = sin(down * 0.32 - TIME * 0.55);
		paper = mix(paper, vec3(0.77, 0.93, 0.91), pleat * 0.42);
		paper *= 1.0 + flow * motion_strength * 0.035;
	} else {
		// Quiet dyed-paper variation; local irregular sheets supply cut edges.
		float band = sin((world_p.z + world_p.x * 0.16) * 0.027);
		paper *= 0.985 + 0.015 * band;
		float slow = sin(world_p.z * 0.11 + world_p.x * 0.018 - TIME * 0.12);
		paper *= 1.0 + slow * motion_strength * 0.018;
	}
	ALBEDO = paper * (1.0 + fiber * fiber_fade * 0.018);
	ROUGHNESS = 0.97;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
