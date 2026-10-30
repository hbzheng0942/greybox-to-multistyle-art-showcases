shader_type spatial;
render_mode cull_back, diffuse_burley;

// A runtime material for imported GLBs. The source GLB and its UV/texture data
// remain untouched; this derived material adds the game's hole and occluder rules.
uniform bool has_albedo_texture = true;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
// glTF metallic-roughness textures are linear data. Godot's GLTFDocument
// imports their channels onto BaseMaterial3D, so retain that mapping here.
uniform sampler2D metallic_texture : filter_linear_mipmap;
uniform sampler2D roughness_texture : filter_linear_mipmap;
uniform bool has_metallic_texture = false;
uniform bool has_roughness_texture = false;
uniform int metallic_texture_channel = 2;
uniform int roughness_texture_channel = 1;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool recolor_yellow = false;
uniform vec4 yellow_target : source_color = vec4(1.0);
uniform float surface_roughness = 0.85;
uniform float surface_metallic = 0.0;
uniform float surface_specular = 0.5;
// Source-faithful defaults. Any art adaptation must be explicit in the build recipe.
// A roughness floor erased the actual G channel on most of the first Lux3D batch.
uniform float game_albedo_gain = 1.0;
uniform float game_roughness_floor = 0.0;
// Explicit material revisions retain source MR variation instead of flattening it
// with a global floor. Identity is the default for all historical recipes.
uniform vec2 game_roughness_range = vec2(0.0, 1.0);
// Authored UV regions repair identified baked highlights without changing atlas
// coordinates or touching genuine cream trim on the rest of the model.
uniform int material_region_count = 0;
uniform vec4 material_region_rect[16];
// Optional source-mesh boxes cover fragmented UV islands belonging to one part.
// min.w selects box space; no global/world height test is used.
uniform vec4 material_region_local_min[16];
uniform vec4 material_region_local_max[16];
uniform vec4 material_region_exclude_uv[16];
uniform vec4 material_region_exclude_local_min[16];
uniform vec4 material_region_exclude_local_max[16];
uniform vec4 material_region_exclude_sphere[16];
uniform vec4 material_region_color[16] : source_color;
// x/y: roughness interval, z: protect warm trim, w: retained albedo variation.
uniform vec4 material_region_response[16];
// 0: authored whole region, 1: neutral silver/white paint, 2: coral or neutral,
// 3: bright neutral only; 4: blue paint; 5: coral paint excluding warm cream.
uniform int material_region_color_family[16];
uniform bool enable_hole_clip = true;
uniform vec4 hole_a = vec4(-0.5, 14.3, 0.45, 1.0);
uniform vec4 hole_b = vec4(0.0);
uniform float occlusion_fade = 0.0;
varying vec3 world_position;
varying vec3 source_position;

float sampled_channel(vec4 value, int channel) {
	if (channel == 0) { return value.r; }
	if (channel == 1) { return value.g; }
	if (channel == 2) { return value.b; }
	if (channel == 3) { return value.a; }
	return dot(value.rgb, vec3(0.333333));
}

float projected_hole_reveal(vec2 ground_point, vec4 hole) {
	if (hole.w < 0.5 || hole.z <= 0.0) { return 0.0; }
	float radius_fraction = distance(ground_point, hole.xy) / hole.z;
	return 1.0 - smoothstep(1.10, 1.38, radius_fraction);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	source_position = VERTEX;
}

void fragment() {
	if (enable_hole_clip && world_position.y < -0.025) {
		bool inside_a = hole_a.w > 0.5 && distance(world_position.xz, hole_a.xy) < hole_a.z;
		bool inside_b = hole_b.w > 0.5 && distance(world_position.xz, hole_b.xy) < hole_b.z;
		if ((!inside_a && !inside_b) || world_position.y < -2.60) { discard; }
	}
	if (occlusion_fade > 0.001) {
		// Project this fragment's camera ray onto the actual mouth plane. This
		// follows perspective/orthographic cameras without screen-Y assumptions.
		// Reveal only the hole silhouette plus a narrow feather; the rest of the
		// logical object stays opaque. Main still excludes captured/hidden units.
		vec3 ray = PROJECTION_MATRIX[3][3] > 0.5
			? -INV_VIEW_MATRIX[2].xyz : world_position - INV_VIEW_MATRIX[3].xyz;
		float reveal = 0.0;
		if (ray.y < -0.0001 && world_position.y > 0.06) {
			vec2 ground_point = world_position.xz + ray.xz * ((0.06 - world_position.y) / ray.y);
			// The existing .68 eligibility envelope now fully clears the small
			// mouth core, leaving dither only on its feather/transition.
			reveal = clamp(occlusion_fade / 0.68, 0.0, 1.0) * max(projected_hole_reveal(ground_point, hole_a),
				projected_hole_reveal(ground_point, hole_b));
		}
		vec2 pixel = floor(FRAGCOORD.xy);
		float dither = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
		if (dither < reveal) { discard; }
	}
	vec4 texel = (has_albedo_texture ? texture(albedo_texture, UV) : vec4(1.0)) * albedo_tint;
	float source_roughness = surface_roughness * (has_roughness_texture
		? sampled_channel(texture(roughness_texture, UV), roughness_texture_channel) : 1.0);
	float revised_roughness = mix(game_roughness_range.x, game_roughness_range.y, source_roughness);
	for (int i = 0; i < 16; i++) {
		if (i >= material_region_count) { break; }
		vec4 bounds = material_region_rect[i];
		float inside = step(bounds.x, UV.x) * step(bounds.y, UV.y)
			* step(UV.x, bounds.z) * step(UV.y, bounds.w);
		vec4 local_min = material_region_local_min[i];
		vec4 local_max = material_region_local_max[i];
		if (local_min.w > 0.5) {
			vec3 box_mask = step(local_min.xyz, source_position) * step(source_position, local_max.xyz);
			inside = box_mask.x * box_mask.y * box_mask.z;
		}
		vec4 excluded = material_region_exclude_uv[i];
		inside *= 1.0 - step(excluded.x, UV.x) * step(excluded.y, UV.y)
			* step(UV.x, excluded.z) * step(UV.y, excluded.w);
		vec4 excluded_min = material_region_exclude_local_min[i];
		vec4 excluded_max = material_region_exclude_local_max[i];
		if (excluded_min.w > 0.5) {
			vec3 excluded_box = step(excluded_min.xyz, source_position) * step(source_position, excluded_max.xyz);
			if (excluded_max.w > 0.000001) {
				excluded_box = smoothstep(excluded_min.xyz, excluded_min.xyz + vec3(excluded_max.w), source_position)
					* (vec3(1.0) - smoothstep(excluded_max.xyz - vec3(excluded_max.w), excluded_max.xyz, source_position));
			}
			inside *= 1.0 - excluded_box.x * excluded_box.y * excluded_box.z;
		}
		vec4 excluded_sphere = material_region_exclude_sphere[i];
		if (excluded_sphere.w > 0.0) {
			inside *= step(excluded_sphere.w, distance(source_position, excluded_sphere.xyz));
		}
		vec4 response = material_region_response[i];
		// Warm cream/gold is a real decoration, not a specular highlight.
		float warm = smoothstep(0.12, 0.26, texel.r - texel.b)
			* smoothstep(0.07, 0.18, texel.g - texel.b);
		inside *= 1.0 - warm * response.z;
		float chroma = max(texel.r, max(texel.g, texel.b)) - min(texel.r, min(texel.g, texel.b));
		float neutral = 1.0 - smoothstep(0.04, 0.22, chroma);
		if (material_region_color_family[i] == 1) { inside *= neutral; }
		if (material_region_color_family[i] == 2) {
			inside *= max(neutral, smoothstep(0.01, 0.14, texel.r - texel.b));
		}
		if (material_region_color_family[i] == 3) {
			inside *= neutral * smoothstep(0.18, 0.42, dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722)));
		}
		if (material_region_color_family[i] == 4) {
			inside *= smoothstep(0.025, 0.12, texel.b - texel.r);
		}
		if (material_region_color_family[i] == 5) {
			float red_excess = texel.r - texel.g;
			inside *= smoothstep(0.50, 0.72, red_excess / max(texel.r - texel.b, 0.001))
				* smoothstep(0.035, 0.10, texel.r - texel.b);
		}
		if (material_region_color_family[i] == 6) { inside *= smoothstep(.015,.075,texel.g-texel.r) * smoothstep(.015,.09,texel.g-texel.b); }
		vec4 paint = material_region_color[i];
		float luminance = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722));
		float detail = mix(1.0 - response.w, 1.0 + response.w, luminance);
		texel.rgb = mix(texel.rgb, paint.rgb * detail, inside * paint.a);
		revised_roughness = mix(revised_roughness,
			mix(response.x, response.y, source_roughness), inside);
	}
	if (recolor_yellow && texel.r > texel.b * 1.8 && texel.g > texel.b * 1.4 && texel.r > .25) {
        texel.rgb = yellow_target.rgb * max(texel.r,texel.g);
    }
    ALBEDO = texel.rgb * game_albedo_gain * mix(1.0, 0.42, clamp(-world_position.y / 2.6, 0.0, 1.0));
	ROUGHNESS = max(game_roughness_floor, revised_roughness);
	METALLIC = surface_metallic * (has_metallic_texture
		? sampled_channel(texture(metallic_texture, UV), metallic_texture_channel) : 1.0);
	SPECULAR = surface_specular;
}
