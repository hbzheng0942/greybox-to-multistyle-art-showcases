shader_type spatial;
render_mode unshaded, cull_disabled;

// Stylised rim: a beveled lip with growth ticks and a swallow flash.
// Presentation only. It never implies a wider capture radius than the simulation grants:
// the tick ring is drawn on the lip itself, inside the functional opening.

uniform vec4 accent : source_color = vec4(0.28, 0.79, 0.93, 1.0);
uniform float growth01 = 0.0;
uniform float bite_pulse = 0.0;
uniform float alive = 1.0;
uniform float tick_count = 6.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float ang = atan(lp.x, lp.z);
	float radius = length(lp.xz);

	vec3 base = vec3(0.085, 0.105, 0.145);
	vec3 col = accent.rgb * (0.62 + 0.38 * growth01);
	col += accent.rgb * pow(max(0.0, cos(ang * tick_count)), 10.0) * (0.45 + 0.55 * growth01);

	// Bevel mask: the outer shoulder keeps a darker lip so the opening still reads as a hole.
	float shoulder = smoothstep(1.005, 1.055, radius);
	col = mix(col, base, shoulder * 0.80);

	if (alive < 0.5) {
		col *= 0.25;
	}

	col += accent.rgb * bite_pulse * 1.15;

	ALBEDO = col;
	// Unshaded: ALBEDO is the final colour, emission only carries the swallow flash.
	EMISSION = accent.rgb * bite_pulse * 1.35;
}
