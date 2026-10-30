shader_type sky;
render_mode disable_fog;

uniform sampler2D moon_paint : source_color, filter_linear_mipmap_anisotropic;

// One approved-style painted RGBA cloud, world-fixed and instanced with varied pose.
uniform sampler2D cloud_paint : source_color, filter_linear_mipmap_anisotropic;
vec4 cloud_packet(vec2 p, vec2 center, vec2 extent, float tilt, float seed, float depth) {
	vec2 q = p - center;
	q.x = mod(q.x + 3.14159265, 6.2831853) - 3.14159265;
	q.y -= q.x * tilt;
	q /= extent;
	if (abs(q.x) > 1.0 || abs(q.y) > 1.0) { return vec4(0.0); }
	vec2 uv = vec2(q.x, -q.y) * 0.5 + vec2(0.5);
	if (mod(seed, 2.0) > 0.5) { uv.x = 1.0 - uv.x; }
	vec4 paint = texture(cloud_paint, uv);
	paint.rgb *= mix(0.72, 0.48, depth);
	return paint;
}

vec3 add_cloud(vec3 sky_color, vec4 cloud, float opacity, float moon) {
	// The disk remains legible behind a partly occluding foreground bank.
	return mix(sky_color, cloud.rgb, cloud.a * opacity * (1.0 - moon * 0.48));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 p = vec2(atan(d.x, -d.z), asin(d.y));
	COLOR = mix(vec3(0.002, 0.009, 0.040), vec3(0.001, 0.013, 0.060), smoothstep(-0.08, 0.65, d.y));
	COLOR += vec3(0.004, 0.009, 0.022) * (1.0 - smoothstep(0.08, 0.42, abs(p.y - 0.29)));

	// Original source08 center and angular radius remain authoritative.
	vec2 moon_delta = p - vec2(-0.06, 0.31);
	float md = length(moon_delta / vec2(0.215));
	float moon = 1.0 - smoothstep(0.992, 1.008, md);
	COLOR += vec3(0.02, 0.14, 0.18) * exp(-md * md * 0.8);
	// Sample only the v2 disk; the analytic circle excludes outside splashes.
	vec2 moon_uv = moon_delta / 0.43 * 0.928 + vec2(0.5);
	vec4 painted_moon = texture(moon_paint, moon_uv);
	vec3 moon_color = mix(vec3(0.055, 0.67, 0.74), painted_moon.rgb * vec3(0.75, 0.90, 0.93), painted_moon.a);
	COLOR = mix(COLOR, moon_color, moon);

	// Unequal separated painted cloud masses around the same world sky.
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-1.120, 0.490), vec2(0.200, 0.080), -0.090, 2.0, 0.30), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-0.660, 0.490), vec2(0.230, 0.100), -0.070, 7.0, 0.00), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-0.190, 0.610), vec2(0.130, 0.055), 0.080, 12.0, 0.20), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(0.320, 0.500), vec2(0.160, 0.065), 0.090, 18.0, 0.10), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(0.770, 0.600), vec2(0.235, 0.100), 0.140, 23.0, 0.00), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(1.300, 0.400), vec2(0.190, 0.080), -0.120, 29.0, 0.40), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-0.550, 0.260), vec2(0.120, 0.045), -0.060, 31.0, 0.50), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-0.210, 0.200), vec2(0.090, 0.033), -0.050, 38.0, 0.60), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(0.380, 0.250), vec2(0.140, 0.050), 0.100, 41.0, 0.50), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-1.660, 0.430), vec2(0.220, 0.090), -0.100, 48.0, 0.30), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-2.210, 0.560), vec2(0.230, 0.100), 0.100, 53.0, 0.10), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(-2.760, 0.310), vec2(0.220, 0.080), -0.080, 58.0, 0.40), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(1.860, 0.570), vec2(0.210, 0.090), -0.100, 61.0, 0.20), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(2.400, 0.340), vec2(0.200, 0.085), 0.100, 68.0, 0.30), 0.94, moon);
	COLOR = add_cloud(COLOR, cloud_packet(p, vec2(2.940, 0.580), vec2(0.220, 0.090), -0.100, 73.0, 0.20), 0.94, moon);
}
