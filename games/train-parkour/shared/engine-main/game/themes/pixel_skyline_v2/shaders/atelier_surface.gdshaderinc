#ifndef ATELIER_SURFACE_DETAIL_INCLUDED
#define ATELIER_SURFACE_DETAIL_INCLUDED

// Colour-only, world-anchored architectural marks. Opt in by semantic role:
// 0 off; 1 tunnel panel cassette; 2 structural steel; 3 rail SIDE casing;
// 4 district infill masonry only, with broad courses and subordinate joints.
// Never apply to emission/glass/train/G1 texture maps/rock/edge trim/rail tops.
float atelier_surface_box(vec2 p, vec2 center, vec2 half_size, float aa) {
    vec2 distance_to_edge = abs(p - center) - half_size;
    return 1.0 - smoothstep(-aa, aa, max(distance_to_edge.x, distance_to_edge.y));
}

vec3 atelier_surface_detail(vec3 world_position, vec3 world_normal, vec3 base_color, int role) {
    if (role <= 0 || role > 4) {
        return base_color;
    }
    vec3 n = abs(normalize(world_normal));
    vec2 p = world_position.xz;
    if (n.x > n.y && n.x > n.z) {
        p = world_position.zy;
    } else if (n.z > n.y) {
        p = world_position.xy;
    }
    // Differentiate continuous coordinates, not fract/floor module coordinates.
    float footprint = max(length(dFdx(p)), length(dFdy(p)));
    float aa = max(0.012, footprint * 0.65);
    float medium_visibility = 1.0 - smoothstep(0.22, 0.55, footprint);
    float fine_visibility = 1.0 - smoothstep(0.065, 0.19, footprint);
    vec3 result = base_color;

    if (role == 1) {
        vec2 module = vec2(5.6, 3.6);
        vec2 cell = floor(p / module);
        vec2 q = p - cell * module;
        // Large gasket/recess and a two-step painted lip. These are organized
        // sheet-metal modules rather than noise applied over all surfaces.
        float inset = atelier_surface_box(q, module * 0.5, module * 0.5 - vec2(0.105), aa);
        float seal = 1.0 - inset;
        float lip_top = atelier_surface_box(q, vec2(module.x * 0.5, module.y - 0.155), vec2(module.x * 0.5 - 0.19, 0.055), aa);
        float lip_left = atelier_surface_box(q, vec2(0.155, module.y * 0.5), vec2(0.055, module.y * 0.5 - 0.19), aa);
        float lip_bottom = atelier_surface_box(q, vec2(module.x * 0.5, 0.20), vec2(module.x * 0.5 - 0.24, 0.040), aa);
        result = mix(result, base_color * 0.48, seal * medium_visibility);
        result = mix(result, base_color * 1.23, max(lip_top, lip_left) * medium_visibility);
        result = mix(result, base_color * 0.72, lip_bottom * medium_visibility);

        // Fold to the nearest corner: a dark square socket with a brighter
        // square head. Four understandable fasteners, no scattered speckle.
        vec2 corner = min(q, module - q);
        float socket = atelier_surface_box(corner, vec2(0.34), vec2(0.105), aa);
        float bolt = atelier_surface_box(corner, vec2(0.32), vec2(0.045), aa);
        result = mix(result, base_color * 0.46, socket * fine_visibility);
        result = mix(result, base_color * 1.40, bolt * fine_visibility);

        // Every fifth sheet gets one three-slat service vent, rather than
        // repeating louvers on every panel. Count/rhythm are deliberately fixed.
        float vent_sheet = 1.0 - step(0.5, abs(mod(cell.x + cell.y * 3.0, 5.0) - 2.0));
        vec2 vent_center = vec2(3.82, 2.32);
        float vent_frame = atelier_surface_box(q, vent_center, vec2(0.80, 0.50), aa);
        float vent_recess = atelier_surface_box(q, vent_center, vec2(0.70, 0.40), aa);
        float slats = 0.0;
        slats = max(slats, atelier_surface_box(q, vent_center + vec2(0.0, -0.25), vec2(0.64, 0.055), aa));
        slats = max(slats, atelier_surface_box(q, vent_center, vec2(0.64, 0.055), aa));
        slats = max(slats, atelier_surface_box(q, vent_center + vec2(0.0, 0.25), vec2(0.64, 0.055), aa));
        result = mix(result, base_color * 1.15, vent_sheet * vent_frame * medium_visibility);
        result = mix(result, base_color * 0.38, vent_sheet * vent_recess * medium_visibility);
        result = mix(result, base_color * 1.06, vent_sheet * slats * fine_visibility);

        // Short pale identification plate + a single stepped corner abrasion.
        // Both hug plausible handling/fastener regions; no random global wear.
        float label = atelier_surface_box(q, vec2(0.78, 2.85), vec2(0.31, 0.085), aa);
        float worn_sheet = 1.0 - step(0.5, abs(mod(cell.x - cell.y, 3.0) - 1.0));
        float wear = max(
            atelier_surface_box(q, vec2(0.17, 0.51), vec2(0.06, 0.14), aa),
            atelier_surface_box(q, vec2(0.235, 0.435), vec2(0.04, 0.055), aa));
        result = mix(result, base_color * 1.30, label * 0.70 * fine_visibility);
        result = mix(result, base_color * 1.37, wear * worn_sheet * fine_visibility);
    } else if (role == 2) {
        // Structural members retain broad quiet faces. One compact splice plate
        // and two sockets per module, not a second all-over panel grid.
        vec2 module = vec2(4.8, 3.6);
        vec2 q = mod(p + vec2(0.31, 0.42), module);
        vec2 center = vec2(0.64, 1.80);
        float plate = atelier_surface_box(q, center, vec2(0.38, 0.72), aa);
        float plate_face = atelier_surface_box(q, center + vec2(-0.035, 0.035), vec2(0.31, 0.64), aa);
        float socket = max(
            atelier_surface_box(q, center + vec2(0.0, -0.43), vec2(0.085), aa),
            atelier_surface_box(q, center + vec2(0.0, 0.43), vec2(0.085), aa));
        float bolt = max(
            atelier_surface_box(q, center + vec2(-0.02, -0.41), vec2(0.038), aa),
            atelier_surface_box(q, center + vec2(-0.02, 0.45), vec2(0.038), aa));
        result = mix(result, base_color * 0.60, plate * medium_visibility);
        result = mix(result, base_color * 1.18, plate_face * medium_visibility);
        result = mix(result, base_color * 0.42, socket * fine_visibility);
        result = mix(result, base_color * 1.38, bolt * fine_visibility);
    } else if (role == 3) {
        // Optional inspection covers on a rail's side casing only. The normal
        // does not encode track direction: do NOT invent cross-track seams.
        vec2 module = vec2(6.0, 1.8);
        vec2 q = mod(p + vec2(0.51, 0.28), module);
        vec2 center = vec2(0.85, 0.90);
        float cover = atelier_surface_box(q, center, vec2(0.44, 0.25), aa);
        float face = atelier_surface_box(q, center + vec2(-0.025, 0.025), vec2(0.37, 0.18), aa);
        float fastener = max(
            atelier_surface_box(q, center + vec2(-0.28, 0.0), vec2(0.045), aa),
            atelier_surface_box(q, center + vec2(0.28, 0.0), vec2(0.045), aa));
        float vertical_face = 1.0 - smoothstep(0.35, 0.65, n.y);
        result = mix(result, base_color * 0.58, cover * medium_visibility * vertical_face);
        result = mix(result, base_color * 1.10, face * medium_visibility * vertical_face);
        result = mix(result, base_color * 1.30, fastener * fine_visibility * vertical_face);
    } else {
        // Two scales of intentional ashlar courses; no random speckle. The
        // world anchor keeps the joins still during a high-speed banked pass.
        float vertical_face = 1.0 - smoothstep(0.45, 0.75, n.y);
        float row = floor(p.y / 1.35);
        vec2 q = mod(p + vec2(mod(row, 2.0) * 1.45, 0.0), vec2(2.90, 1.35));
        float course_visible = 1.0 - smoothstep(0.32, 0.90, footprint);
        float inset = atelier_surface_box(q, vec2(1.45, 0.675), vec2(1.415, 0.645), aa);
        float upper_lip = atelier_surface_box(q, vec2(1.45, 1.28), vec2(1.35, 0.025), aa);
        float alternate = mod(floor((p.x + mod(row, 2.0)*1.45) / 2.9) + row*2.0, 5.0);
        float grouped_tone = mix(0.96, 1.035, step(2.5, alternate));
        result = mix(result, result*grouped_tone, vertical_face*course_visible);
        result = mix(result, base_color*0.76, (1.0-inset)*vertical_face*course_visible);
        result = mix(result, base_color*1.13, upper_lip*vertical_face*medium_visibility);
    }
    return result;
}
#endif
