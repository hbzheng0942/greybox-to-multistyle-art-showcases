shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled;

#include "res://themes/pixel_skyline_v2/shaders/atelier_surface.gdshaderinc"
uniform int surface_detail_role = 0;
varying vec3 surface_world_position;

// UV cells describe painted colour clusters, not the final display resolution.
// Explicit gradients are from unsnapped UVs: mip selection must not follow cells.
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_texture = false;
uniform bool has_normal_texture = false;
uniform bool has_emission_texture = false;
uniform bool emission_on_uv2 = false;
uniform bool use_vertex_color = false;
uniform bool vertex_color_is_srgb = false;
uniform bool double_sided = false;
uniform bool snap_planar_normals = false;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec3 uv2_scale = vec3(1.0);
uniform vec3 uv2_offset = vec3(0.0);
uniform vec2 texture_cells = vec2(256.0);
uniform float normal_strength = 0.18;
// 0: cool architecture, 1: train, 2: rock, 3: authored solid colour.
uniform int palette_mode = 0;
uniform float palette_strength : hint_range(0.0, 1.0) = 0.88;
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.40;
uniform float direct_strength : hint_range(0.0, 1.0) = 0.80;
uniform float window_emission : hint_range(0.0, 3.0) = 0.0;
uniform bool train_window_accent = false;
uniform vec3 authored_emission : source_color = vec3(0.0);
uniform float authored_emission_energy = 0.0;
uniform bool emission_add = false;
uniform float source_alpha_scissor = 0.5;
uniform float source_alpha_hash_scale = 1.0;
uniform int source_alpha_mode = 0;
uniform vec3 ink : source_color = vec3(0.075, 0.102, 0.180);
uniform vec3 shadow : source_color = vec3(0.19, 0.21, 0.34);
uniform vec3 middle : source_color = vec3(0.33, 0.40, 0.56);
uniform vec3 face : source_color = vec3(0.49, 0.60, 0.74);
uniform vec3 edge : source_color = vec3(0.73, 0.81, 0.88);
uniform vec3 warm_window : source_color = vec3(1.0, 0.64, 0.22);
uniform vec3 cream : source_color = vec3(1.0, 0.89, 0.77);
uniform vec3 coral : source_color = vec3(1.0, 0.40, 0.32);
uniform vec3 train_glass : source_color = vec3(0.08, 0.25, 0.34);
uniform vec3 cyan : source_color = vec3(0.22, 0.91, 1.0);
varying vec3 object_world_normal;
varying vec3 object_position;

vec3 srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 ramp(float value) {
    float x = clamp(value, 0.0, 1.0) * 4.0;
    vec3 a = mix(ink, shadow, clamp(x, 0.0, 1.0));
    a = mix(a, middle, clamp(x - 1.0, 0.0, 1.0));
    a = mix(a, face, clamp(x - 2.0, 0.0, 1.0));
    return mix(a, edge, clamp(x - 3.0, 0.0, 1.0));
}

void vertex() {
    object_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    object_position = VERTEX;
    surface_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 source_uv = UV * uv_scale.xy + uv_offset.xy;
    vec2 dx = dFdx(source_uv);
    vec2 dy = dFdy(source_uv);
    vec2 cells = max(texture_cells, vec2(1.0));
    vec2 cell_uv = (floor(source_uv * cells) + 0.5) / cells;
    // Gradually stop snapping once a painted cell is smaller than a screen pixel.
    float footprint = max(length(dx * cells), length(dy * cells));
    vec2 sample_uv = mix(cell_uv, source_uv, smoothstep(0.70, 1.7, footprint));
    // Average the texture inside a painted cell instead of point-picking one
    // noisy source texel. At distance the ordinary derivatives take over.
    vec2 sample_dx = dx * max(1.0, 1.0 / max(length(dx * cells), 0.001));
    vec2 sample_dy = dy * max(1.0, 1.0 / max(length(dy * cells), 0.001));
    vec4 texel = vec4(1.0);
    if (has_albedo_texture) {
        texel = textureGrad(albedo_texture, sample_uv, sample_dx, sample_dy);
    }
    vec4 source = texel * albedo_tint;
    if (use_vertex_color) {
        source *= vec4(vertex_color_is_srgb ? srgb_to_linear(COLOR.rgb) : COLOR.rgb, COLOR.a);
    }
    // Classify in approximately perceptual colour space; colour uniforms and
    // outputs remain linear. Broad masks retain painted recesses and livery.
    vec3 p = sqrt(max(source.rgb, vec3(0.0)));
    float value = sqrt(max(dot(source.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0));
    float grouped = floor(clamp(value, 0.0, 0.999) * 7.0 + 0.25) / 7.0;
    vec3 painted = ramp(grouped);
    vec3 accent_emission = vec3(0.0);
    if (palette_mode == 1) {
        float red_paint = smoothstep(0.06, 0.18, p.r - max(p.g, p.b)) * smoothstep(0.30, 0.48, p.r);
        float pale_paint = smoothstep(0.46, 0.64, value);
        float glass_mask = smoothstep(0.015, 0.085, max(p.g, p.b) - p.r);
        vec3 dark_paint = mix(ink, shadow, clamp(grouped * 1.8, 0.0, 1.0));
        dark_paint = mix(dark_paint, train_glass * (0.65 + grouped * 0.75), glass_mask);
        painted = mix(dark_paint, cream * (0.78 + grouped * 0.22), pale_paint);
        painted = mix(painted, coral * (0.70 + grouped * 0.45), red_paint);
        float cyan_light = smoothstep(0.10, 0.22, min(p.g, p.b) - p.r) * smoothstep(0.58, 0.82, min(p.g, p.b));
        painted = mix(painted, cyan, cyan_light);
        accent_emission = cyan * cyan_light * 0.85;
        if (train_window_accent) {
            // Current normalized motorcar: x +/-1.3, y 0..3.4, z +/-6 m.
            // End-window lower edge only. Dark upper glass and undercarriage stay.
            float end_cap = smoothstep(5.28, 5.50, abs(object_position.z))
                * (1.0 - smoothstep(0.97, 1.08, abs(object_position.x)));
            float lower_window = smoothstep(1.80, 1.87, object_position.y)
                * (1.0 - smoothstep(2.03, 2.09, object_position.y));
            float dark_glass = (1.0 - smoothstep(0.42, 0.62, value)) * (1.0 - red_paint);
            float accent = end_cap * lower_window * dark_glass;
            float fascia = end_cap * smoothstep(1.20, 1.26, object_position.y)
                * (1.0 - smoothstep(1.52, 1.58, object_position.y)) * red_paint;
            painted = mix(painted, cream * 0.90, fascia);
            painted = mix(painted, cyan, accent);
            accent_emission = max(accent_emission, cyan * accent * 1.30);
        }
    } else if (palette_mode == 2) {
        // Preserve teal vegetation embedded in generated rock/settlement maps.
        float vegetation = smoothstep(0.035, 0.12, p.g - p.r) * (1.0 - smoothstep(0.50, 0.70, value));
        painted = mix(painted, painted * vec3(0.55, 1.04, 0.76), vegetation * 0.65);
    } else if (palette_mode == 3) {
        // Authored geometry already carries the chosen palette. Do not recolour it.
        painted = source.rgb;
    } else if (palette_mode == 4) {
        // New cartoon architecture: deliberate broad paint values rather than
        // the generated micro-shading. Derivative-width transitions soften
        // thresholds only when necessary at the actual display footprint.
        float w = clamp(fwidth(value), 0.012, 0.05);
        painted = mix(ink, shadow, smoothstep(0.18-w, 0.18+w, value));
        painted = mix(painted, middle, smoothstep(0.34-w, 0.34+w, value));
        painted = mix(painted, face, smoothstep(0.54-w, 0.54+w, value));
        painted = mix(painted, edge, smoothstep(0.76-w, 0.76+w, value));
        float warm = smoothstep(0.08, 0.18, min(p.r, p.g) - p.b);
        painted = mix(painted, warm_window * (0.50 + 0.50 * smoothstep(0.35, 0.70, value)), warm);
        float cold = smoothstep(0.10, 0.22, min(p.g,p.b)-p.r) * smoothstep(0.50,0.72,min(p.g,p.b));
        painted = mix(painted, cyan, cold);
        accent_emission = cyan * cold * 0.25;
    }
    if (window_emission > 0.0 && palette_mode != 1) {
        // Opt-in architecture only. Bright yellow/orange chroma; warm stone,
        // red paint and neutral cream are deliberately excluded.
        vec3 window_sample = sqrt(max(textureGrad(albedo_texture, source_uv, dx, dy).rgb * albedo_tint.rgb, vec3(0.0)));
        float warm = smoothstep(0.47, 0.64, window_sample.r) * smoothstep(0.34, 0.49, window_sample.g)
            * smoothstep(0.12, 0.23, window_sample.r - window_sample.b)
            * smoothstep(0.055, 0.14, window_sample.g - window_sample.b);
        painted = mix(painted, warm_window, warm * 0.90);
        accent_emission += warm_window * warm * window_emission;
    }
    vec3 color = mix(source.rgb, painted, palette_strength);
    color = atelier_surface_detail(surface_world_position, object_world_normal, color, surface_detail_role);
    ALBEDO = color;
    ROUGHNESS = 0.94;
    METALLIC = 0.0;
    SPECULAR = 0.0;
    if (double_sided && !FRONT_FACING) {
        NORMAL = -NORMAL;
    }
    if (has_normal_texture) {
        NORMAL_MAP = textureGrad(normal_texture, sample_uv, sample_dx, sample_dy).rgb;
        NORMAL_MAP_DEPTH = normal_strength;
    }
    if (snap_planar_normals) {
        vec3 n = normalize(object_world_normal);
        vec3 a = abs(n);
        vec3 axis = a.x > a.y && a.x > a.z ? vec3(sign(n.x),0.0,0.0)
            : (a.y > a.z ? vec3(0.0,sign(n.y),0.0) : vec3(0.0,0.0,sign(n.z)));
        // Keep designed bevels. Only near-planar generated ripple is flattened.
        float planar = smoothstep(0.91,0.98,max(a.x,max(a.y,a.z)));
        NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(mix(n,axis,planar)));
    }
    float sky_face = smoothstep(-0.12, 0.16, object_world_normal.y) * 0.12
        + smoothstep(0.60, 0.80, object_world_normal.y) * 0.08;
    EMISSION = color * vec3(0.76, 0.82, 1.0) * ambient_floor * (0.80 + sky_face) + accent_emission;
    vec3 emissive_sample = vec3(1.0);
    if (has_emission_texture) {
        vec2 emission_uv = emission_on_uv2 ? UV2 * uv2_scale.xy + uv2_offset.xy : source_uv;
        emissive_sample = textureGrad(emission_texture, emission_uv, dFdx(emission_uv), dFdy(emission_uv)).rgb;
    }
    EMISSION += (emission_add && has_emission_texture ? authored_emission + emissive_sample : authored_emission * emissive_sample) * authored_emission_energy;
    // ATELIER_ALPHA_BODY
}

void light() {
    float incidence = max(dot(NORMAL, LIGHT), 0.0);
    // Wide value bands with narrow transitions; no temporal or screen-space noise.
    float width = clamp(fwidth(incidence) * 0.75, 0.018, 0.08);
    float bands = 0.25 * smoothstep(0.08 - width, 0.08 + width, incidence)
        + 0.32 * smoothstep(0.36 - width, 0.36 + width, incidence)
        + 0.27 * smoothstep(0.64 - width, 0.64 + width, incidence)
        + 0.16 * smoothstep(0.88 - width, 0.88 + width, incidence);
    DIFFUSE_LIGHT += bands * ATTENUATION * LIGHT_COLOR * direct_strength / PI;
}
