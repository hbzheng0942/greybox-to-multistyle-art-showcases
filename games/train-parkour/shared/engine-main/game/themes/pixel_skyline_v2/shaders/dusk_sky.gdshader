shader_type sky;
render_mode disable_fog;

// World-locked angular cells: no screen-space noise or TIME-driven swimming.
uniform vec3 zenith_color : source_color = vec3(0.18, 0.19, 0.40);
uniform vec3 middle_color : source_color = vec3(0.51, 0.31, 0.57);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.58, 0.40);
uniform vec3 ground_color : source_color = vec3(0.20, 0.24, 0.39);
uniform vec3 cloud_shadow : source_color = vec3(0.59, 0.34, 0.57);
uniform vec3 cloud_body : source_color = vec3(0.95, 0.48, 0.45);
uniform vec3 cloud_edge : source_color = vec3(1.0, 0.68, 0.46);
uniform vec3 sun_color : source_color = vec3(1.0, 0.82, 0.53);
uniform vec3 sun_direction = vec3(-0.56, 0.075, -0.825);
uniform float sun_radius : hint_range(0.002, 0.10) = 0.021;
uniform vec2 angular_cells = vec2(768.0, 288.0);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p, float period_x) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period_x);
	float x1 = mod(i.x + 1.0, period_x);
	return mix(mix(hash2(vec2(x0, i.y)), hash2(vec2(x1, i.y)), f.x),
		mix(hash2(vec2(x0, i.y + 1.0)), hash2(vec2(x1, i.y + 1.0)), f.x), f.y);
}

void sky() {
	vec2 angular = vec2(atan(EYEDIR.x, EYEDIR.z) / 6.283185307 + 0.5,
		asin(clamp(EYEDIR.y, -1.0, 1.0)) / 3.141592654 + 0.5);
	vec2 cell = (floor(angular * angular_cells) + 0.5) / angular_cells;
	float elevation = sin((cell.y - 0.5) * 3.141592654);
	float height = max(elevation, 0.0);
	float gradient_step = floor(clamp(height / 0.72, 0.0, 1.0) * 32.0) / 32.0;
	vec3 color = mix(horizon_color, middle_color, smoothstep(0.0, 0.25, gradient_step));
	color = mix(color, zenith_color, smoothstep(0.20, 1.0, gradient_step));
	color = mix(color, ground_color, smoothstep(0.0, 0.20, -elevation));

	// Long, broken strata have several silhouette scales. Quantize shape and
	// light together so each cloud consists of deliberate blocks of color.
	vec2 cloud_uv = cell * vec2(48.0, 76.0);
	// Integer periods join across the azimuth seam, including the initial -Z view.
	float broad = noise2(cloud_uv * vec2(0.5, 1.0), 24.0);
	float fine = noise2(cloud_uv * 3.0 + vec2(7.3, 19.7), 144.0);
	float shape = broad * 0.76 + fine * 0.24;
	float band = smoothstep(0.025, 0.09, height) * (1.0 - smoothstep(0.38, 0.57, height));
	float clouds = step(0.56, shape) * band;
	vec3 cloud = mix(cloud_shadow, cloud_body, step(0.615, shape));
	cloud = mix(cloud, cloud_edge, step(0.70, shape));
	color = mix(color, cloud, clouds);

	vec3 direction = normalize(sun_direction);
	float disc_distance = acos(clamp(dot(normalize(EYEDIR), direction), -1.0, 1.0));
	float sun = step(disc_distance, sun_radius) * step(0.0, EYEDIR.y);
	color = mix(color, sun_color, sun * (1.0 - clouds));
	COLOR = color;
}
