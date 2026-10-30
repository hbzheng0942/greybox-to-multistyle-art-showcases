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

	// The face now lives on external 2D sprites; the interior stays unobstructed.
	col += accent.rgb * bite_pulse * 0.035;

	ALBEDO = col;
	// Unshaded: ALBEDO already carries the final colour, so emission only adds the swallow bloom.
	EMISSION = vec3(0.0);
}
