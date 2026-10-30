shader_type spatial;
render_mode cull_back, ambient_light_disabled;
uniform vec4 body_color : source_color = vec4(0.80, 0.48, 0.22, 1.0);
uniform bool enable_hole_clip = true;
uniform float surface_roughness = 0.95;
uniform vec4 hole_a = vec4(-0.5, 14.3, 0.45, 1.0);
uniform vec4 hole_b = vec4(0.0);
uniform float occlusion_fade = 0.0;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    // Keep the part below ground visible INSIDE the actual opening, down into the well.
    // Outside the moving hole it is hidden by the floor; no global ground deletion.
    if (enable_hole_clip && world_position.y < -0.025) {
        bool inside_a = hole_a.w > 0.5 && distance(world_position.xz, hole_a.xy) < hole_a.z;
        bool inside_b = hole_b.w > 0.5 && distance(world_position.xz, hole_b.xy) < hole_b.z;
        if ((!inside_a && !inside_b) || world_position.y < -2.60) { discard; }
    }
    // Screen-door cutaway for an occluding building only. Captured objects never fade.
    if (occlusion_fade > 0.001) {
        vec2 pixel = floor(FRAGCOORD.xy);
        float dither = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
        if (dither < occlusion_fade) { discard; }
    }
    float depth_shade = mix(1.0, 0.38, clamp(-world_position.y / 2.6, 0.0, 1.0));
    ALBEDO = body_color.rgb * depth_shade;
    EMISSION = ALBEDO * 0.38;
    ROUGHNESS = surface_roughness;
    SPECULAR = 0.0;
}
void light() {
    DIFFUSE_LIGHT += vec3(max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * 0.62);
}
