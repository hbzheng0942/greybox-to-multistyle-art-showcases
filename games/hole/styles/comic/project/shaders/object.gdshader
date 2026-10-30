shader_type spatial;
render_mode cull_back, ambient_light_disabled, diffuse_lambert;

// Toy Downtown Waterfront surface shader.
// Two jobs, deliberately kept separate:
//   1. gameplay-critical clipping (moving hole openings, depth darkening, building cutaway);
//   2. the matte, clear-colour-block toy look from the frozen concept.
// A single material serves a whole logical unit; the palette rides in vertex colours,
// so a landmark still costs one material slot.

uniform vec4 body_color : source_color = vec4(0.80, 0.48, 0.22, 1.0);
uniform bool use_vertex_color = false;
uniform bool enable_hole_clip = true;
uniform float surface_roughness = 0.88;
uniform float matte_mix = 0.86;
uniform float emissive_strength = 0.16;
uniform float glow_scale = 1.0;
uniform float wrap_light = 0.42;
// Chosen from two rounds of tests/tone_sweep.gd, scored with tools/tone_report.py.
// Round 1 ("fill heavy") reached p99 0.827 but drove max to 1.000, i.e. it did blow pale surfaces
// out, which the brief forbids. These values keep the best highlight reach of the second round
// (p99 0.811) while capping at 0.966, and they cut crushed blacks from 2.6% to 0.6% versus the
// pre-pass build -- a strict improvement in both directions.
uniform float key_strength = 0.66;
uniform float fill_base = 0.15;
uniform float fill_sky = 0.19;
uniform vec4 hole_a = vec4(-0.5, 14.3, 0.45, 1.0);
uniform vec4 hole_b = vec4(0.0);
uniform float occlusion_fade = 0.0;
varying vec3 world_position;
varying vec3 local_position;

float projected_hole_reveal(vec2 ground_point, vec4 hole) {
	if (hole.w < 0.5 || hole.z <= 0.0) { return 0.0; }
	float radius_fraction = distance(ground_point, hole.xy) / hole.z;
	return 1.0 - smoothstep(1.10, 1.38, radius_fraction);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_position = VERTEX;
}

void fragment() {
	// Keep the part below ground visible INSIDE the actual opening, down into the well.
	// Outside the moving hole it is hidden by the floor; no global ground deletion.
	if (enable_hole_clip && world_position.y < -0.025) {
		bool inside_a = hole_a.w > 0.5 && distance(world_position.xz, hole_a.xy) < hole_a.z;
		bool inside_b = hole_b.w > 0.5 && distance(world_position.xz, hole_b.xy) < hole_b.z;
		if ((!inside_a && !inside_b) || world_position.y < -2.60) { discard; }
	}
	// Screen-local reveal of the opening only. Captured objects never fade.
	if (occlusion_fade > 0.001) {
		vec3 ray = PROJECTION_MATRIX[3][3] > 0.5
			? -INV_VIEW_MATRIX[2].xyz : world_position - INV_VIEW_MATRIX[3].xyz;
		float reveal = 0.0;
		if (ray.y < -0.0001 && world_position.y > 0.06) {
			vec2 ground_point = world_position.xz + ray.xz * ((0.06 - world_position.y) / ray.y);
			// The existing .68 eligibility envelope now fully clears the small
			// mouth core, leaving dither only on its feather/transition.
			reveal = clamp(occlusion_fade / 0.68, 0.0, 1.0) * max(projected_hole_reveal(ground_point, hole_a),
				projected_hole_reveal(ground_point, hole_b));
		}
		vec2 pixel = floor(FRAGCOORD.xy);
		float dither = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
		if (dither < reveal) { discard; }
	}
	vec3 base = use_vertex_color ? COLOR.rgb : body_color.rgb;
	// Vertex-colour ALPHA carries the "self-lit" weight of a part. Window glass, lamp shades and
	// reflection collars mark themselves with alpha 1, matte plastic with alpha 0, so ONE surface
	// and ONE material can serve a whole logical unit. That keeps a unit at a single draw call
	// instead of splitting body and glow into two meshes with two materials.
	float glow = use_vertex_color ? COLOR.a : 0.0;
	// Sink shading: geometry below the pavement cools and darkens as it descends.
	float depth_shade = mix(1.0, 0.42, clamp(-world_position.y / 2.6, 0.0, 1.0));
	vec3 albedo = base * depth_shade;
	// Subtle upward light gradient instead of texture detail: keeps small props readable
	// without adding high-frequency noise that would swallow them on the ground.
	float up_lift = clamp(NORMAL.y, 0.0, 1.0) * 0.07;
	ALBEDO = clamp(albedo * (1.0 + up_lift), vec3(0.0), vec3(1.0));
	EMISSION = ALBEDO * (emissive_strength + glow * glow_scale);
	ROUGHNESS = surface_roughness;
	SPECULAR = mix(0.35, 0.0, matte_mix);
}

void light() {
	// Two-term toy lighting. The concept is diffuse and even: bright faces should land just under
	// white, and a face angled away from the sun must stay READABLE, not collapse to black.
	//
	//   1. KEY  - wrapped diffuse. The wrap term bends light around the silhouette the way a large
	//             softbox does, so toy bevels keep their shape instead of clipping into shadow.
	//   2. FILL - a constant floor plus a hemisphere term. This is deliberately NOT the engine's
	//             ambient light (that is disabled): the brief asks for stable key/fill ratios that
	//             do not drift with scene settings, and a pale 15 cm prop sitting on pale pavement
	//             needs that floor to separate from the ground at all.
	//
	// Measured with tests/tone_sweep.gd: the previous single-term version capped a pure white
	// surface at 0.82 luminance and dropped unlit faces to 0.00, which is why light-coloured
	// small props visually melted into the pavement.
	float wrapped = clamp((dot(NORMAL, LIGHT) + wrap_light) / (1.0 + wrap_light), 0.0, 1.0);
	float sky = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	float fill = fill_base + fill_sky * sky;
	DIFFUSE_LIGHT += vec3(wrapped * ATTENUATION * key_strength + fill);
}
