extends Node3D
## Owned effect recipes. Gameplay geometry, input and renderer stay with the host.
##
## Style-local fork of the skill's `runtime/godot/effects.gd`.
##
## Why a fork: the shipped recipe exposes a deliberately small lighting surface
## (path / rotation / energy / colour / shadow on-off / sky / ambient / exposure).
## That is enough to light a scene, but not enough to *match a concept image*:
## the things that make an illustrated shop read as illustrated -- contact
## darkening in the corners, a soft shadow edge instead of a razor stencil, a
## highlight roll-off that keeps cream walls off pure white -- are all renderer
## features the shipped contract does not name. Rather than change what the
## plan means, the style adds optional keys. Every key the shipped file accepts
## still behaves identically, and every added key is inert when absent, so an
## older manifest runs here unchanged.
##
## Added keys (all optional, all clamped):
##   shadow_softness / sun_angle   degrees of sun angular size -> penumbra width
##   shadow_blur                   split blend between cascades
##   shadow_max_distance           cascade reach in metres
##   shadow_bias / shadow_normal_bias
##   ssao / ssao_radius / ssao_intensity / ssao_power / ssao_detail
##   ssao_light_affect / ssao_channel_affect
##   ssil / ssil_radius / ssil_intensity
##   glow / glow_intensity / glow_bloom / glow_threshold / glow_blend
##   tonemap                       "filmic" | "aces" | "agx" | "linear" | "reinhard"
##   tonemap_white                 HDR white point for the filmic/ACES curves
##   saturation / contrast / brightness
##   fog_light_color / fog_sun_scatter / fog_aerial_perspective
@export var config_json: String = "{}"
var errors: Array = []
var grass_report: Dictionary = {}


## Named curves instead of a const dictionary: the enum values are not constant
## expressions GDScript accepts inside `const`, and a typo here would silently
## fall back to Filmic.
func _tonemap(name: String) -> int:
	match name:
		"linear":
			return Environment.TONE_MAPPER_LINEAR
		"reinhard":
			return Environment.TONE_MAPPER_REINHARDT
		"aces":
			return Environment.TONE_MAPPER_ACES
		"agx":
			return Environment.TONE_MAPPER_AGX
		_:
			return -1


func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _color(value: Array) -> Color:
	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)


func _material(filename: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(get_script().resource_path.get_base_dir().path_join(filename))
	return material


func _texture(path: String) -> Texture2D:
	var resource_path := ProjectSettings.localize_path(path) if path.is_absolute_path() else path
	if not resource_path.begins_with("res://"):
		resource_path = "res://" + resource_path
	var texture := load(resource_path) as Texture2D
	if not texture:
		errors.append("Effect input is not a readable Texture2D: " + resource_path)
	return texture


func _ready() -> void:
	var config = JSON.parse_string(config_json)
	if not config is Dictionary:
		errors.append("Invalid effect configuration")
		return
	if config.has("lighting"):
		_lighting(config.lighting)
	for kind in ["water", "ground"]:
		if config.has(kind):
			_surface(kind, config[kind])
	if config.has("grass"):
		_grass(config.grass)


## `light_path` resolves against the running scene, because the point of the
## key is to *take over* a host light rather than add a competing one. A headless
## harness that forgets `current_scene` used to fail silently here and render
## with the host's flat default -- which reads as "the recipe did nothing".
func _host() -> Node:
	var tree := get_tree()
	if tree.current_scene:
		return tree.current_scene
	# Headless harnesses routinely forget `current_scene`. Walk up from this
	# node to the top-level scene instead of returning null.
	var node: Node = self
	while node.get_parent() and node.get_parent() != tree.root:
		node = node.get_parent()
	return node


func _lighting(c: Dictionary) -> void:
	var host := _host()
	if not host:
		errors.append("lighting needs a running scene to resolve light_path against")
		return
	var sun: DirectionalLight3D
	if c.has("light_path"):
		sun = host.get_node_or_null(NodePath(c.light_path)) as DirectionalLight3D
		if not sun:
			errors.append("lighting.light_path must identify an existing DirectionalLight3D")
			return
	else:
		sun = DirectionalLight3D.new()
		sun.name = "RecipeSun"
		add_child(sun)
	sun.rotation_degrees = _v(c.get("sun_rotation", [-45, -30, 0]))
	sun.light_energy = float(c.get("sun_energy", 1.0))
	sun.light_color = _color(c.get("color", [1.0, 0.95, 0.85]))
	sun.shadow_enabled = bool(c.get("shadows", true))
	if sun.shadow_enabled:
		# A single hard-edged shadow under a 0.85 white sun is what made the
		# first pass look like an unlit grey box: every contact read as a
		# stencil cut. Sun angular size is the physical control for penumbra.
		var softness := float(c.get("shadow_softness", c.get("sun_angle", 0.0)))
		if softness > 0.0:
			sun.light_angular_distance = clampf(softness, 0.0, 90.0)
		# SHADOW_ORTHOGONAL was measured dead under this project's orthographic
		# camera (tools/shadow_probe.gd renders a cube with no shadow at every
		# bias); PSSM is the only mode that produces one here. Splits are blended
		# so the cascade seam does not show as a line across the shop floor.
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_max_distance = clampf(float(c.get("shadow_max_distance", 45.0)), 1.0, 400.0)
		sun.shadow_blur = clampf(float(c.get("shadow_blur", 1.0)), 0.0, 8.0)
		if c.has("shadow_bias"):
			sun.shadow_bias = float(c.shadow_bias)
		if c.has("shadow_normal_bias"):
			sun.shadow_normal_bias = float(c.shadow_normal_bias)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _color(c.get("background_color", [0.25, 0.4, 0.6]))
	if bool(c.get("sky", true)):
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = environment.background_color
		sky_material.sky_horizon_color = _color(c.get("ambient_color", [0.65, 0.75, 0.9]))
		environment.sky = Sky.new()
		environment.sky.sky_material = sky_material
		environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _color(c.get("ambient_color", [0.65, 0.75, 0.9]))
	environment.ambient_light_energy = float(c.get("ambient_energy", 0.5))
	environment.tonemap_exposure = float(c.get("exposure", 1.0))
	var mapper: String = str(c.get("tonemap", "filmic")).to_lower()
	var curve := _tonemap(mapper)
	if curve >= 0:
		environment.tonemap_mode = curve
	elif mapper != "filmic":
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		errors.append("lighting.tonemap is unknown; Filmic retained")
	else:
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if c.has("tonemap_white"):
		environment.tonemap_white = clampf(float(c.tonemap_white), 1.0, 16.0)
	# Screen-space ambient occlusion is the single biggest difference between
	# "objects placed in a box" and "objects resting in a room": it darkens the
	# seams at wall/floor and prop/floor contacts that a pure analytic light
	# cannot see. Unavailable under Compatibility, hence inert there.
	environment.ssao_enabled = bool(c.get("ssao", false))
	if environment.ssao_enabled:
		environment.ssao_radius = clampf(float(c.get("ssao_radius", 1.0)), 0.01, 16.0)
		environment.ssao_intensity = clampf(float(c.get("ssao_intensity", 2.0)), 0.0, 32.0)
		environment.ssao_power = clampf(float(c.get("ssao_power", 1.5)), 0.01, 16.0)
		environment.ssao_detail = clampf(float(c.get("ssao_detail", 0.5)), 0.0, 1.0)
		environment.ssao_light_affect = clampf(float(c.get("ssao_light_affect", 0.0)), 0.0, 1.0)
		environment.ssao_ao_channel_affect = clampf(float(c.get("ssao_channel_affect", 0.0)), 0.0, 1.0)
	environment.ssil_enabled = bool(c.get("ssil", false))
	if environment.ssil_enabled:
		environment.ssil_radius = clampf(float(c.get("ssil_radius", 5.0)), 0.05, 400.0)
		environment.ssil_intensity = clampf(float(c.get("ssil_intensity", 1.0)), 0.0, 16.0)
	# Glow is a highlight roll-off, not a lens flare: keep the threshold high
	# and the intensity low so only warm lamp bulbs and brass edges bloom.
	environment.glow_enabled = bool(c.get("glow", c.get("bloom", false)))
	if environment.glow_enabled:
		environment.glow_intensity = clampf(float(c.get("glow_intensity", 0.5)), 0.0, 8.0)
		environment.glow_bloom = clampf(float(c.get("glow_bloom", 0.05)), 0.0, 1.0)
		environment.glow_hdr_threshold = clampf(float(c.get("glow_threshold", 1.1)), 0.0, 8.0)
		environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		# Wide, weak levels only: a tight level-0 bloom turns into plastic sheen.
		for level in range(7):
			environment.set_glow_level(level, 0.0)
		environment.set_glow_level(2, 0.6)
		environment.set_glow_level(3, 0.7)
		environment.set_glow_level(4, 0.5)
	if c.has("saturation") or c.has("contrast") or c.has("brightness"):
		environment.adjustment_enabled = true
		environment.adjustment_saturation = clampf(float(c.get("saturation", 1.0)), 0.0, 4.0)
		environment.adjustment_contrast = clampf(float(c.get("contrast", 1.0)), 0.5, 2.0)
		environment.adjustment_brightness = clampf(float(c.get("brightness", 1.0)), 0.5, 2.0)
	var fog_density := float(c.get("fog_density", 0.0))
	environment.fog_enabled = fog_density > 0.0
	if environment.fog_enabled:
		environment.fog_density = fog_density
		environment.fog_light_color = _color(c.get("fog_light_color", c.get("ambient_color", [0.65, 0.75, 0.9])))
		environment.fog_sun_scatter = clampf(float(c.get("fog_sun_scatter", 0.0)), 0.0, 1.0)
		environment.fog_aerial_perspective = clampf(float(c.get("fog_aerial_perspective", 0.0)), 0.0, 1.0)
	var renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility")
	if renderer == "gl_compatibility" and (environment.ssao_enabled or environment.glow_enabled):
		errors.append("SSAO/glow unavailable in Compatibility; renderer retained")
	var found := host.find_children("*", "WorldEnvironment", true, false)
	if not found.is_empty():
		found[0].environment = environment
	else:
		var node := WorldEnvironment.new()
		node.environment = environment
		add_child(node)


func _surface(kind: String, c: Dictionary) -> void:
	var node := MeshInstance3D.new()
	node.name = "Recipe" + kind.capitalize()
	var mesh := PlaneMesh.new()
	var size: Array = c.get("size", [10, 10])
	mesh.size = Vector2(float(size[0]), float(size[1]))
	mesh.subdivide_width = 24 if kind == "water" else 0
	mesh.subdivide_depth = 24 if kind == "water" else 0
	node.mesh = mesh
	node.position = _v(c.get("position", [0, 0, 0]))
	var material := _material(kind + ".gdshader")
	material.set_shader_parameter("base_color", _color(c.get("color", [0.08, 0.42, 0.6, 0.8] if kind == "water" else [0.3, 0.36, 0.2, 1])))
	if kind == "water":
		material.set_shader_parameter("flow_speed", float(c.get("speed", 0.4)))
		material.set_shader_parameter("amplitude", float(c.get("amplitude", 0.05)))
		material.set_shader_parameter("surface_size", mesh.size)
		material.set_shader_parameter("roughness", float(c.get("roughness", 0.18)))
		material.set_shader_parameter("shore_width", float(c.get("shore_width", 0.08 * minf(mesh.size.x, mesh.size.y))))
		material.set_shader_parameter("depth_distance", float(c.get("depth_distance", 0.08 * minf(mesh.size.x, mesh.size.y))))
		var shallow := _color(c.get("color", [0.08, 0.42, 0.6, 0.8]))
		material.set_shader_parameter("deep_color", _color(c.get("deep_color", [shallow.r, shallow.g, shallow.b, shallow.a])))
		if not c.has("deep_color"):
			# Legacy water used color inland and a 1.6x brighter edge.
			material.set_shader_parameter("base_color", Color(shallow.r * 1.6, shallow.g * 1.6, shallow.b * 1.6, shallow.a))
		if c.has("shore_mask"):
			material.set_shader_parameter("shore_mask", _texture(c.shore_mask))
			material.set_shader_parameter("use_shore_mask", true)
		if c.has("normal_texture"):
			material.set_shader_parameter("normal_texture", _texture(c.normal_texture))
			material.set_shader_parameter("use_normal_texture", true)
	else:
		material.set_shader_parameter("secondary_color", _color(c.get("secondary_color", [0.5, 0.45, 0.28, 1])))
		material.set_shader_parameter("tile_scale", float(c.get("tile_scale", 2.0)))
		for field in ["texture", "secondary_texture", "blend_mask"]:
			if c.has(field):
				material.set_shader_parameter("albedo_texture" if field == "texture" else field, _texture(c[field]))
				material.set_shader_parameter("use_" + field, true)
	node.material_override = material
	add_child(node)


func _grass(c: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("seed", 1))
	var bounds: Array = c.get("bounds", [-5, -5, 5, 5])
	var groups: Dictionary = {}
	var count: int = int(c.get("count", 400))
	var chunk_size := float(c.get("chunk_size", 8.0))
	var ground_y := float(c.get("ground_y", c.get("y", 0.0)))
	var base_height := float(c.get("height", 0.45))
	# Existing cards were 0.35 * height wide; explicit width uses world units.
	var base_width := float(c.get("width", base_height * 0.35))
	var mask: Image
	if c.has("density_mask"):
		var texture := _texture(c.density_mask)
		if not texture:
			return
		mask = texture.get_image()
		if mask == null or mask.is_empty():
			errors.append("Grass density mask has no readable image")
			return
		if mask.is_compressed() and mask.decompress() != OK:
			errors.append("Grass density mask cannot be decompressed")
			return
	var accepted := 0
	for attempt in range(maxi(1, count * 30)):
		if accepted >= count:
			break
		var x := rng.randf_range(float(bounds[0]), float(bounds[2]))
		var z := rng.randf_range(float(bounds[1]), float(bounds[3]))
		var excluded := false
		for rect in c.get("exclude_rects", []):
			if x >= rect[0] and z >= rect[1] and x <= rect[2] and z <= rect[3]:
				excluded = true
		if excluded:
			continue
		if mask:
			var u := (x - float(bounds[0])) / (float(bounds[2]) - float(bounds[0]))
			var v := (z - float(bounds[1])) / (float(bounds[3]) - float(bounds[1]))
			var value := mask.get_pixel(clampi(int(u * mask.get_width()), 0, mask.get_width() - 1), clampi(int(v * mask.get_height()), 0, mask.get_height() - 1)).r
			if value <= float(c.get("mask_threshold", 0.0)) or rng.randf() >= value:
				continue
		var key := Vector2i(floori(x / chunk_size), floori(z / chunk_size))
		if not groups.has(key):
			groups[key] = []
		var variation := rng.randf_range(0.7, 1.3)
		var height := base_height * variation
		var center := Vector3((float(key.x) + 0.5) * chunk_size, ground_y, (float(key.y) + 0.5) * chunk_size)
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis.from_scale(Vector3(base_width * variation, height, 1.0))
		var transform := Transform3D(basis, Vector3(x, ground_y + height * 0.5, z) - center)
		groups[key].append(transform)
		accepted += 1
	grass_report = {"requested": count, "accepted": accepted, "seed": int(c.get("seed", 1)), "chunks": groups.size(), "chunk_size": chunk_size, "masked": mask != null}
	for key in groups:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		var blade := QuadMesh.new()
		blade.size = Vector2.ONE
		multi.mesh = blade
		multi.instance_count = groups[key].size()
		for index in range(groups[key].size()):
			multi.set_instance_transform(index, groups[key][index])
		var node := MultiMeshInstance3D.new()
		node.name = "GrassChunk_" + str(key.x) + "_" + str(key.y)
		node.position = Vector3((float(key.x) + 0.5) * chunk_size, ground_y, (float(key.y) + 0.5) * chunk_size)
		node.multimesh = multi
		node.visibility_range_end = float(c.get("cull_distance", 60.0))
		# Include shader wind in culling bounds without changing gameplay collision.
		node.extra_cull_margin = maxf(float(c.get("wind", 0.12)), 0.01)
		var material := _material("grass.gdshader")
		material.set_shader_parameter("base_color", _color(c.get("color", [0.22, 0.5, 0.13, 1])))
		material.set_shader_parameter("wind", float(c.get("wind", 0.12)))
		node.material_override = material
		add_child(node)
