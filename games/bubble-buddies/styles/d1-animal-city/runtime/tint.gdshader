shader_type spatial;
// Palette variant of an unchanged generated asset.
//
// The image-to-3D pipeline bakes the concept crop's albedo into one texture, so
// a fixture's colour cannot be edited after the fact -- recolouring a cream
// washer into the concept's mint machine used to mean paying for a second
// generation. This shader keeps every bit of the baked shading (panel gaps,
// door ring, painted edges) and only moves the colour: saturation first, then a
// multiplicative tint. That is the same operation a texture artist performs in
// Photoshop, minus the round trip.
//
// Deliberately NOT a colour-override: the mesh keeps its own roughness and
// metallic map, so brass stays metal and the door glass stays dark.
render_mode diffuse_burley, specular_schlick_ggx;

// A LINEAR multiplier, deliberately not `source_color`. The albedo below is
// sampled in linear space, so a tint that Godot pre-converted from sRGB would
// double-apply the curve and every channel above 1.0 would overshoot wildly --
// which is exactly how the first steel washer came out at 0.22 albedo and
// photographed as burnt metal. With a plain vec4 the numbers here are the
// ratios a texture artist would type into a levels dialog.
uniform vec4 tint = vec4(1.0);
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal_tex = false;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.7;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;
// Hue guard: pixels that already carry a strong hue are left alone, so the
// brass knob, the coral trim and the painted edges survive the recolour and only
// the near-neutral body moves. A straight multiply turned the washer's brass
// handle olive, which read as a mistake rather than a colourway.
uniform float protect_amount : hint_range(0.0, 1.0) = 0.0;
uniform float protect_low : hint_range(0.0, 1.0) = 0.2;
uniform float protect_high : hint_range(0.0, 1.0) = 0.45;
// Hue replacement: keep the baked *value* structure and swap the *hue* wholesale.
//
// A multiply cannot do this job. The washer's baked body is a warm cream whose
// linear blue channel is 0.18; reaching a mint green by multiplication needs a
// blue gain near 2.0, which also multiplies every baked highlight past 1.0 --
// the first two attempts came out as a khaki box with cyan-green fringes, because
// the clamp turned the highlights into saturated mint while the body stayed warm.
// Dividing by the body's own luma instead keeps the panel gaps, the door ring and
// the AO exactly as baked, and paints the target hue on top of them.
uniform bool hue_replace = false;
uniform float ref_luma = 0.25;
uniform vec3 target = vec3(0.5);
uniform float target_gain : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec3 albedo = base_color.rgb;
	if (has_albedo_tex) {
		vec4 sampled = texture(albedo_tex, UV);
		albedo *= sampled.rgb;
	}
	float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	vec3 recoloured;
	if (hue_replace) {
		float relative = clamp(luma / max(ref_luma, 0.0001), 0.0, 1.35);
		recoloured = target * relative * target_gain;
	} else {
		recoloured = mix(vec3(luma), albedo, saturation) * tint.rgb * brightness;
	}
	if (protect_amount > 0.0) {
		float high = max(max(albedo.r, albedo.g), albedo.b);
		float low = min(min(albedo.r, albedo.g), albedo.b);
		float chroma = high <= 0.0001 ? 0.0 : (high - low) / high;
		float keep = smoothstep(protect_low, protect_high, chroma) * protect_amount;
		recoloured = mix(recoloured, albedo, keep);
	}
	ALBEDO = clamp(recoloured, vec3(0.0), vec3(0.95));
	// ALPHA is deliberately NOT written. The baked basecolour texture carries an
	// alpha channel, but on these GLBs it is not a transparency channel -- and
	// writing ALPHA = sampled.a pushed every tinted fixture onto the transparent
	// render path, where the mint laundry machine showed its own drum through its
	// own front panel and read as a glass box. Fixtures are opaque; leaving the
	// line out keeps them on the opaque path with a depth prepass.
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	if (has_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
