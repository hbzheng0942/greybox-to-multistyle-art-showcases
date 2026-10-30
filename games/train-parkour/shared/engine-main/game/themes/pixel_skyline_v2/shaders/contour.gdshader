shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

// Forward+ world-only overlay. One texel is one internal (720x405) pixel.
// References: Godot advanced_postprocessing and screen-reading_shaders docs.
uniform sampler2D depth_buffer : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_buffer : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform sampler2D color_buffer : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec3 ink_color : source_color = vec3(0.060, 0.078, 0.140);
uniform float contour_strength = 0.86;
uniform int contour_width = 1;
uniform float crease_strength = 0.23;
uniform float contact_strength = 0.0;
uniform float far_begin = 90.0;
uniform float far_end = 310.0;

vec3 position_at(vec2 uv, mat4 inverse_projection) {
    float depth = textureLod(depth_buffer, uv, 0.0).r;
    vec4 p = inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
    return p.xyz / max(p.w, 0.000001);
}

vec3 normal_at(vec2 uv) {
    return normalize(textureLod(normal_buffer, uv, 0.0).xyz * 2.0 - 1.0);
}

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 pixel = 1.0 / VIEWPORT_SIZE;
    float raw_depth = textureLod(depth_buffer, uv, 0.0).r;
    vec3 p = position_at(uv, INV_PROJECTION_MATRIX);
    vec3 n = normal_at(uv);
    float distance_fade = 1.0 - smoothstep(far_begin, far_end, -p.z);
    float detail_fade = 1.0 - smoothstep(40.0, 150.0, -p.z);
    float world_pixel = max(0.015, -p.z * INV_PROJECTION_MATRIX[1][1] * 2.0 / VIEWPORT_SIZE.y);
    float contour = 0.0;
    float crease = 0.0;
    float contact = 0.0;
    vec2 directions[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
    for (int i = 0; i < 4; i++) {
        vec2 neighbor_uv = clamp(uv + directions[i] * pixel, pixel * 0.5, vec2(1.0) - pixel * 0.5);
        vec3 q = position_at(neighbor_uv, INV_PROJECTION_MATRIX);
        vec3 neighbor_n = normal_at(neighbor_uv);
        // Plane residual avoids falsely outlining a steep uninterrupted road.
        float plane_error = abs(dot(n, q - p));
        float farther = smoothstep(world_pixel * 1.5, world_pixel * 3.0, p.z - q.z);
        float discontinuity = smoothstep(max(0.12, world_pixel * 1.2), max(0.30, world_pixel * 2.5), plane_error);
        contour = max(contour, farther * discontinuity);
        // Widen silhouettes inward only. Creases stay at one pixel, and the
        // second pixel retires with distance instead of thickening far detail.
        if (contour_width > 1) {
            vec2 wide_uv = clamp(uv + directions[i] * pixel * 2.0, pixel * 0.5, vec2(1.0) - pixel * 0.5);
            vec3 wide_q = position_at(wide_uv, INV_PROJECTION_MATRIX);
            float wide_plane = abs(dot(n, wide_q - p));
            float wide_farther = smoothstep(world_pixel * 3.0, world_pixel * 6.0, p.z - wide_q.z);
            float wide_break = smoothstep(max(0.16, world_pixel * 2.4), max(0.40, world_pixel * 5.0), wide_plane);
            float width_fade = 1.0 - smoothstep(45.0, 100.0, -p.z);
            contour = max(contour, wide_farther * wide_break * width_fade);
        }
        float corner = smoothstep(0.28, 0.62, 1.0 - dot(n, neighbor_n));
        float same_surface_depth = 1.0 - smoothstep(world_pixel * 3.0, world_pixel * 7.0, abs(p.z - q.z));
        // Ink only the less camera-facing side of a crease, not both sides.
        crease = max(crease, corner * same_surface_depth * smoothstep(0.02, 0.20, neighbor_n.z - n.z));
        if (contact_strength > 0.0) {
            for (int j = 1; j <= 2; j++) {
                vec2 tap_uv = clamp(uv + directions[i] * pixel * float(j * 2), pixel * 0.5, vec2(1.0) - pixel * 0.5);
                vec3 delta = position_at(tap_uv, INV_PROJECTION_MATRIX) - p;
                float separation = length(delta);
                // Finite radius: distant silhouettes must never become contact shadows.
                float radius = (1.0 - smoothstep(0.70, 2.0, separation)) * smoothstep(0.02, 0.10, separation);
                float occlusion = smoothstep(0.10, 0.48, dot(n, delta / max(separation, 0.001)));
                contact += radius * occlusion / 8.0;
            }
        }
    }
    vec3 scene_color = textureLod(color_buffer, uv, 0.0).rgb;
    // Keep luminous cyan/gold/red gameplay markings and lamp cores readable.
    float chroma = max(scene_color.r, max(scene_color.g, scene_color.b)) - min(scene_color.r, min(scene_color.g, scene_color.b));
    float signal = smoothstep(0.10, 0.30, chroma) * smoothstep(0.20, 0.70, max(scene_color.r, max(scene_color.g, scene_color.b)));
    float ink = max(contour * contour_strength, crease * crease_strength * detail_fade);
    ink = max(ink, clamp(contact * 2.0, 0.0, 0.65) * contact_strength * detail_fade);
    ALBEDO = ink_color;
    ALPHA = ink * distance_fade * (1.0 - signal * 0.92) * step(0.000001, raw_depth);
}
