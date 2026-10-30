shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;
// Explicit source colors + bounded lighting: no white floor from ambient/sun addition.
uniform vec4 floor_color : source_color = vec4(0.216, 0.275, 0.318, 1.0);
uniform vec4 grid_color : source_color = vec4(0.310, 0.365, 0.400, 1.0);
uniform vec4 road_color : source_color = vec4(0.161, 0.204, 0.243, 1.0);
uniform vec4 start_color : source_color = vec4(0.239, 0.333, 0.337, 1.0);
uniform vec4 hole_a = vec4(-0.5, 14.3, 0.45, 1.0);
uniform vec4 hole_b = vec4(0.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world_position.xz;
    if (hole_a.w > 0.5 && distance(p, hole_a.xy) < hole_a.z) { discard; }
    if (hole_b.w > 0.5 && distance(p, hole_b.xy) < hole_b.z) { discard; }
    vec3 base = floor_color.rgb;
    // Keep one-world-unit scale references visible, but subordinate to food silhouettes.
    vec2 grid = abs(fract(p - 0.5) - 0.5);
    vec2 aa = max(fwidth(p), vec2(0.006));
    float line = 1.0 - min(smoothstep(aa.x * 0.2, aa.x * 0.85, grid.x), smoothstep(aa.y * 0.2, aa.y * 0.85, grid.y));
    base = mix(base, grid_color.rgb, line * 0.32);
    if (abs(p.x) < 2.5 && p.y < 6.5) { base = mix(base, road_color.rgb, 0.85); }
    if (abs(p.x) < 6.5 && p.y > 7.5) { base = mix(base, start_color.rgb, 0.45); }
    // Dashed scale marks near the legal centre boundary (not a movement collider).
    float boundary_x = 1.0 - smoothstep(0.03, 0.09, abs(abs(p.x) - 18.5));
    float boundary_z = 1.0 - smoothstep(0.03, 0.09, abs(abs(p.y) - 14.5));
    float dash = step(0.5, fract((p.x + p.y) * 0.5));
    base = mix(base, grid_color.rgb, max(boundary_x, boundary_z) * dash * 0.65);
    if (abs(p.x) > 18.6 || abs(p.y) > 14.6) { base *= 0.88; }
    ALBEDO = base;
    EMISSION = base * 0.42;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
void light() {
    // Intentionally calibrated for a SINGLE sun. Shadow attenuation is preserved.
    DIFFUSE_LIGHT += vec3(max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * 0.58);
}
