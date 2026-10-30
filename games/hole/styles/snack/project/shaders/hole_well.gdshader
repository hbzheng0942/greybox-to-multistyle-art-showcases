shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Functional opening interior: depth falloff + restrained swirl + the playful face.
// Everything here is presentation. The functional radius, swallow timing and payout are
// owned by scripts/simulation.gd and are never read from this shader.
//
// The face is painted on the INSIDE of the funnel and faces the viewing direction, so it
// can never be a flat opaque mask lying on the pavement in front of falling objects.

uniform vec4 accent : source_color = vec4(0.28, 0.79, 0.93, 1.0);
uniform float growth01 = 0.0;
uniform float bite_pulse = 0.0;
uniform float face_angle = 0.0;
uniform float alive = 1.0;
uniform float well_depth = 2.55;
uniform float vortex_strength = 1.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	// Open-ended cylinder: draw both wall faces; never discard the visible interior.

	float ang = atan(lp.x, lp.z);
	float depth01 = clamp(0.5 - lp.y / well_depth, 0.0, 1.0);

	// Restrained swirl: low-amplitude striations, never bright enough to hide a small prop.
	float swirl = sin(ang * 6.0 + depth01 * 7.0 - TIME * 1.35);
	float flicker = 0.95 + 0.05 * sin(TIME * 2.6 + depth01 * 5.0);
	vec3 throat = mix(vec3(0.008, 0.012, 0.022), vec3(0.001, 0.002, 0.004), depth01);
	vec3 col = throat + accent.rgb * (0.008 + 0.005 * swirl) * (1.0 - depth01 * 0.6) * vortex_strength;
	col *= mix(1.0, 0.46, depth01) * flicker;

	// Inner lip light spill: sells depth without washing out anything falling through.
	col += accent.rgb * smoothstep(0.62, 0.0, depth01) * (0.018 + 0.025 * growth01);

	// --- playful face, painted on the funnel wall
	float da = ang - face_angle;
	da = atan(sin(da), cos(da));
	// Increasing depth points down, while face coordinates point up.
	vec2 uv = vec2(da * 1.20, (0.34 - depth01) * 1.70);
	float eye_scale = 1.0 + growth01 * 0.16 - bite_pulse * 0.18;
	vec2 e1 = uv - vec2(-0.46, 0.05);
	vec2 e2 = uv - vec2(0.46, 0.05);
	float eye = min(length(e1 / vec2(0.17, 0.21) * eye_scale), length(e2 / vec2(0.17, 0.21) * eye_scale));
	float white = 1.0 - smoothstep(0.90, 1.0, eye);
	float pupil = 1.0 - smoothstep(0.74, 0.94,
		min(length(e1 / vec2(0.075, 0.095)), length(e2 / vec2(0.075, 0.095))));

	float grin_w = 1.0 + growth01 * 0.35;
	float gm = length(vec2(uv.x / (1.55 * grin_w), (uv.y + 0.36) * 2.15));
	float grin = (1.0 - smoothstep(0.86, 1.0, gm)) * step(uv.y, -0.20);
	float tongue = (1.0 - smoothstep(0.80, 0.98,
		length(vec2(uv.x / (0.55 * grin_w), (uv.y + 0.20) * 2.4)))) * step(uv.y, -0.30);

	// Playful brows: angled inward, lifting slightly as the hole grows.
	float brow_l = 1.0 - smoothstep(0.0, 0.055,
		abs(uv.y - 0.30 + (uv.x + 0.44) * 0.22) + max(abs(uv.x + 0.44) - 0.17, 0.0));
	float brow_r = 1.0 - smoothstep(0.0, 0.055,
		abs(uv.y - 0.30 - (-uv.x + 0.44) * 0.22) + max(abs(uv.x - 0.44) - 0.17, 0.0));

	vec3 ink = vec3(0.035, 0.045, 0.062);
	col = mix(col, vec3(0.96, 0.98, 1.0), white * 0.93 * alive);
	col = mix(col, ink, pupil * white * alive);
	col = mix(col, vec3(0.008, 0.012, 0.02), grin * 0.85 * alive);
	col = mix(col, vec3(0.67, 0.28, 0.39), tongue * 0.45 * alive);
	col = mix(col, ink, (brow_l + brow_r) * 0.75 * alive);

	// Swallow feedback: a short accent bloom that never covers the object being drawn in.
	col += accent.rgb * bite_pulse * 0.30;

	ALBEDO = col;
	// Unshaded: ALBEDO already carries the final colour, so emission only adds the swallow bloom.
	EMISSION = accent.rgb * bite_pulse * 1.15;
}
