shader_type spatial;
render_mode unshaded, cull_disabled;

// E06 - water. Visual only: it is never walkable and never scores, and no water is drawn
// inside the cavity under dry land or under either moving opening.

uniform vec2 water_corner = vec2(-9.0, 8.0);
uniform vec2 land_half_size = vec2(22.0, 18.0);
uniform vec4 hole_a = vec4(0.0);
uniform vec4 hole_b = vec4(0.0);
uniform vec3 deep_color = vec3(.085, .315, .415);
uniform vec3 light_color = vec3(.290, .620, .670);
// World XZ is carried in a private varying. In Compatibility an unshaded shader does not
// generate the engine's own world-position varying, so writing it here is required.
varying vec3 v_world_xz;

float segdist(vec2 p, vec2 a, vec2 b) { vec2 d = b - a; return length(p - a - d * clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0)); }

void vertex() { v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = v_world_xz.xz;
	// No hidden water plane under dry land, and none inside the hole cavity.
	bool in_rectangle = abs(p.x) <= land_half_size.x && abs(p.y) <= land_half_size.y;
	bool in_inlet = p.x < water_corner.x && p.y > water_corner.y;
	if (in_rectangle && !in_inlet) { discard; }
	if (hole_a.w > 0.5 && distance(p, hole_a.xy) < hole_a.z) { discard; }
	if (hole_b.w > 0.5 && distance(p, hole_b.xy) < hole_b.z) { discard; }

	float wave = sin(p.x * 1.8 + p.y * .52 + TIME * .9) * sin(p.y * 2.1 - TIME * .65);
	float ripple = sin(p.x * 4.6 - TIME * 1.7 + p.y * 3.1) * 0.5 + 0.5;
	float line = smoothstep(.78, .96, wave);

	// Shore contact: a brighter band of shallow water plus a restrained foam edge, which
	// stops the quay from looking like a slab floating in a flat colour field.
	// Distance is positive on water. Signed rectangle distance was negative offshore,
	// incorrectly spreading shallow water and full-strength foam across the whole sea.
	vec2 h = land_half_size;
	float shore = min(segdist(p,vec2(-h.x,-h.y),vec2(h.x,-h.y)),segdist(p,vec2(h.x,-h.y),h));
	shore = min(shore,segdist(p,h,vec2(water_corner.x,h.y)));
	shore = min(shore,segdist(p,vec2(water_corner.x,h.y),water_corner));
	shore = min(shore,segdist(p,water_corner,vec2(-h.x,water_corner.y)));
	shore = min(shore,segdist(p,vec2(-h.x,water_corner.y),-h));
	float shallow = 1.0 - smoothstep(0.0, 2.6, shore);
	float foam = (1.0 - smoothstep(0.05, 0.55, shore)) * (0.55 + 0.45 * ripple);

	vec3 deep = deep_color;
	vec3 light_water = light_color;
	vec3 col = mix(deep, light_water, .30 + wave * .13 + line * .16);
	col = mix(col, vec3(.360, .700, .720), shallow * 0.55);
	col = mix(col, vec3(.880, .940, .945), foam * 0.55);

	ALBEDO = col;
}
