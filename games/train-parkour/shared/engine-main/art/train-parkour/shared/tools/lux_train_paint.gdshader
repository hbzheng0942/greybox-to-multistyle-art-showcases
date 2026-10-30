shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_factor : source_color = vec4(1.0);
uniform float metallic_factor = 1.0;
uniform float roughness_factor = 1.0;
uniform mat4 mesh_to_normalized;
varying vec3 asset_position;
void vertex() {
    asset_position = (mesh_to_normalized * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec3 original = texture(albedo_tex, UV).rgb * albedo_factor.rgb;
    vec4 mr = texture(metallic_roughness_tex, UV);
    float band = smoothstep(1.15, 1.18, asset_position.y) * (1.0 - smoothstep(1.40, 1.43, asset_position.y));
    float side = smoothstep(0.78, 0.98, abs(asset_position.x));
    float length_mask = 1.0 - smoothstep(4.70, 5.05, abs(asset_position.z));
    ALBEDO = mix(original, original * vec3(0.20, 0.58, 0.74), band * side * length_mask * 0.86);
    METALLIC = mr.b * metallic_factor;
    ROUGHNESS = mr.g * roughness_factor;
}
