shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Opaque finite-volume cascades. Metre-scale ribbons move down world Y;
// all spatial cells stay attached to the world, avoiding camera-relative crawl.
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float hash_cell(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
    vec2 horizontal = floor(world_position.xz / 0.65);
    float column = hash_cell(horizontal);
    float vertical = floor((world_position.y + TIME * 7.0) / 1.6);
    float fleck = hash_cell(vec2(column * 47.0, vertical));
    float bright = step(0.66, column * 0.62 + fleck * 0.38);
    ALBEDO = mix(vec3(0.075, 0.18, 0.30), vec3(0.29, 0.57, 0.71), bright);
    ALBEDO += step(0.90, fleck) * vec3(0.10, 0.15, 0.16);
    ROUGHNESS = 0.78;
    METALLIC = 0.03;
    SPECULAR = 0.18;
}
