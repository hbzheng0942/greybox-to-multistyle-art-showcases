extends Node
## Additive art is attached to its gameplay owner; raw source transforms stay intact.
##
## Style-local fork of the skill's `runtime/godot/art_layer.gd`.
##
## Why a fork: one concept image asks for the *same* fixture in two colourways --
## the wet room has a mint front-loading washer, the dry room a steel one -- and
## the image-to-3D pipeline bakes the crop's albedo into a single texture, so the
## generated asset arrives in exactly one colour. Before this fork the only way
## to satisfy the concept was to pay for a second generation; now a binding may
## declare a `tint` and the assembler wraps the untouched mesh in a palette
## variant (`tint.gdshader`), keeping every baked panel gap, door ring and painted
## edge while moving only the hue.
##
## Every key the shipped file accepts still behaves identically: a manifest
## without `tint` runs here byte-for-byte the same, and `source_materials_preserved`
## stays true for it.
##
## Second addition, same rule: a binding may declare `gait` to let an imported
## skeleton follow the owner's real ground speed. `character_gait.gd` owns the
## playback and touches no transform, so placement stays here and yaw stays with
## gameplay. A manifest without `gait` allocates nothing and plays nothing.
@export var manifest_path: String
var manifest: Dictionary = {}
var assembly_receipts: Array = []
var assembly_errors: Array = []
var assembled := false
const TINT_SHADER := "tint.gdshader"


func _ready() -> void:
	await get_tree().process_frame
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		assembly_errors.append("Invalid assembly manifest")
		assembled = true
		return
	manifest = parsed
	for binding in manifest.get("bindings", []):
		_attach(binding)
	if not manifest.get("effects", {}).is_empty():
		var script = load(get_script().resource_path.get_base_dir().path_join("effects.gd"))
		var effects := Node3D.new()
		effects.name = "GreyboxEffects"
		effects.set_script(script)
		effects.set("config_json", JSON.stringify(manifest.effects))
		get_parent().add_child(effects)
		for error in effects.get("errors"):
			assembly_errors.append(error)
	assembled = true


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _attach(binding: Dictionary) -> void:
	var logical_owner := get_parent().get_node_or_null(NodePath(binding.owner))
	if not logical_owner is Node3D:
		assembly_errors.append("Missing Node3D owner: " + str(binding.owner))
		return
	var art := Node3D.new()
	art.name = "Art_" + str(binding.id).validate_node_name()
	art.set_meta("greybox_binding", binding.id)
	logical_owner.add_child(art)
	var source: Dictionary = binding.get("source", {})
	var visual: Node3D
	if source.has("path"):
		var packed = load(source.path)
		if not packed is PackedScene:
			assembly_errors.append("Source is not a PackedScene: " + str(source.path))
			art.queue_free()
			return
		visual = packed.instantiate() as Node3D
		if not visual:
			assembly_errors.append("Source root must be Node3D: " + str(source.path))
			art.queue_free()
			return
	else:
		visual = _primitive(source, binding)
	var raw_visual := visual
	if source.get("basis", "godot") == "z_up":
		var source_frame := Node3D.new()
		source_frame.name = "SourceFrame"
		source_frame.rotation.x = -PI * 0.5
		source_frame.add_child(visual)
		raw_visual = source_frame
	art.add_child(raw_visual)
	# Every instance starts from the immutable imported resource. Never bake/flatten.
	var bounds := _bounds(raw_visual, Transform3D.IDENTITY)
	var unit_scale := float({"m": 1.0, "cm": 0.01, "mm": 0.001}.get(source.get("units", "m"), 1.0))
	var factor := float(binding.get("uniform_scale", 1.0)) * unit_scale
	var normalize: Dictionary = binding.get("normalize", {})
	var rotation_basis := Basis.from_euler(_vector(binding.get("rotation_degrees", [0, 0, 0])) * PI / 180.0)
	var normalization_space: String = normalize.get("space", "world")
	var owner_bounds: AABB = _bounds(raw_visual, Transform3D(rotation_basis, Vector3.ZERO))
	var world_bounds: AABB = _bounds(raw_visual, Transform3D(logical_owner.global_basis * rotation_basis, Vector3.ZERO))
	var measured_bounds: AABB = world_bounds if normalization_space == "world" else owner_bounds
	if normalize.get("mode", "none") == "uniform_bounds":
		var longest := maxf(measured_bounds.size.x, maxf(measured_bounds.size.y, measured_bounds.size.z))
		if longest <= 0.000001:
			assembly_errors.append("Cannot normalize empty mesh bounds: " + str(binding.id))
		else:
			factor *= float(normalize.get("max_extent", 1.0)) / (longest * unit_scale)
	art.scale = Vector3.ONE * factor
	var source_anchor := Vector3.ZERO
	if binding.get("anchor_mode", "origin") == "bottom_center":
		source_anchor = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	elif binding.has("source_anchor"):
		source_anchor = _vector(binding.source_anchor)
	art.rotation_degrees = _vector(binding.get("rotation_degrees", [0, 0, 0]))
	art.position = _vector(binding.get("anchor", [0, 0, 0])) - art.basis * source_anchor
	# Imported materials are preserved unless an explicit art treatment is declared.
	if binding.has("material_override"):
		_override_material(visual, binding.material_override)
	if binding.has("tint"):
		_apply_tint(visual, binding.tint)
	var gait_receipt: Dictionary = {}
	if binding.has("gait"):
		gait_receipt = _attach_gait(art, raw_visual, binding)
	for path in binding.get("hide", []):
		var old = get_parent().get_node_or_null(NodePath(path))
		if old is VisualInstance3D:
			old.visible = false
		else:
			assembly_errors.append("hide target must be VisualInstance3D, never gameplay/collision: " + str(path))
	assembly_receipts.append({"id": binding.id, "owner": str(logical_owner.get_path()),
		"art": str(art.get_path()), "uniform_scale": factor,
		"raw_bounds": [bounds.position.x, bounds.position.y, bounds.position.z, bounds.size.x, bounds.size.y, bounds.size.z],
		"normalization_space": normalization_space,
		"normalized_extent": maxf(measured_bounds.size.x, maxf(measured_bounds.size.y, measured_bounds.size.z)) * factor,
		"local_extent": maxf(owner_bounds.size.x, maxf(owner_bounds.size.y, owner_bounds.size.z)) * factor,
		"world_extent": maxf(world_bounds.size.x, maxf(world_bounds.size.y, world_bounds.size.z)) * factor,
		"source_units": source.get("units", "m"), "source_basis": source.get("basis", "godot"),
		"source_materials_preserved": not (binding.has("material_override") or binding.has("tint")),
		"variant": str(binding.get("variant", "")),
		"gait": gait_receipt})


## Locomotion hook, resolved against this layer's own parent (the scene root) so
## a binding never has to guess a relative node path from inside the art tree.
func _attach_gait(art: Node3D, visual: Node3D, binding: Dictionary) -> Dictionary:
	var spec: Dictionary = binding.gait
	var script := load(get_script().resource_path.get_base_dir().path_join("character_gait.gd"))
	if not script:
		assembly_errors.append("gait script missing beside art_layer.gd: character_gait.gd")
		return {"ok": false, "error": "script_missing"}
	var node := Node.new()
	node.name = "Gait"
	node.set_script(script)
	art.add_child(node)
	var body: Node3D = get_parent().get_node_or_null(NodePath(str(spec.get("controller", ""))))
	if not body is Node3D:
		assembly_errors.append("gait controller missing: " + str(spec.get("controller", "")))
		return {"ok": false, "error": "controller_missing"}
	node.call("setup", visual, body, spec)
	for error in node.get("errors"):
		assembly_errors.append(str(error))
	return {"ok": node.get("errors").is_empty(), "controller": str(body.get_path()),
		"clips": spec.get("clips", {}), "nominal_speed": spec.get("nominal_speed", {}),
		"errors": node.get("errors")}


func _primitive(source: Dictionary, binding: Dictionary) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var size := _vector(source.get("size", [1, 1, 1]))
	match source.get("primitive", "box"):
		"sphere":
			var shape := SphereMesh.new()
			shape.radius = size.x * 0.5
			shape.height = size.y
			shape.radial_segments = 16
			shape.rings = 8
			mesh.mesh = shape
		"cylinder":
			var shape := CylinderMesh.new()
			shape.top_radius = size.x * 0.5
			shape.bottom_radius = size.z * 0.5
			shape.height = size.y
			shape.radial_segments = 8
			mesh.mesh = shape
		_:
			var shape := BoxMesh.new()
			shape.size = size
			mesh.mesh = shape
	mesh.material_override = _material(binding.get("material", {"color": "#cccccc"}))
	return mesh


func _material(spec: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(str(spec.get("color", "#cccccc")))
	material.roughness = float(spec.get("roughness", 0.8))
	material.metallic = float(spec.get("metallic", 0.0))
	return material


func _override_material(node: Node, spec: Dictionary) -> void:
	if node is MeshInstance3D:
		node.material_override = _material(spec)
	for child in node.get_children():
		_override_material(child, spec)


## Palette variant of one unchanged generated asset.
##
## Instance-level surface overrides only (`set_surface_override_material`), never
## `mesh.surface_set_material`: the mesh is the shared imported resource, and
## writing to it would repaint every other binding of the same asset.
func _apply_tint(node: Node, spec: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh:
		var mesh: Mesh = node.mesh
		var shader := load(get_script().resource_path.get_base_dir().path_join(TINT_SHADER))
		if not shader:
			assembly_errors.append("tint shader missing beside art_layer.gd: " + TINT_SHADER)
			return
		for index in range(mesh.get_surface_count()):
			var source_material: Material = node.get_surface_override_material(index)
			if not source_material:
				source_material = mesh.surface_get_material(index)
			var material := ShaderMaterial.new()
			material.shader = shader
			var base := Color(1, 1, 1, 1)
			var roughness := 0.7
			var metallic := 0.0
			var specular := 0.5
			if source_material is BaseMaterial3D:
				var standard := source_material as BaseMaterial3D
				base = standard.albedo_color
				roughness = standard.roughness
				metallic = standard.metallic
				specular = standard.metallic_specular
				if standard.albedo_texture:
					material.set_shader_parameter("albedo_tex", standard.albedo_texture)
					material.set_shader_parameter("has_albedo_tex", true)
				if standard.normal_enabled and standard.normal_texture:
					material.set_shader_parameter("normal_tex", standard.normal_texture)
					material.set_shader_parameter("has_normal_tex", true)
					material.set_shader_parameter("normal_strength", standard.normal_scale)
			material.set_shader_parameter("base_color", base)
			material.set_shader_parameter("tint", Color(
				float(spec.get("color", [1, 1, 1])[0]),
				float(spec.get("color", [1, 1, 1])[1]),
				float(spec.get("color", [1, 1, 1])[2]),
				1.0))
			material.set_shader_parameter("saturation", float(spec.get("saturation", 1.0)))
			material.set_shader_parameter("brightness", float(spec.get("brightness", 1.0)))
			material.set_shader_parameter("protect_amount", float(spec.get("protect", 0.0)))
			material.set_shader_parameter("protect_low", float(spec.get("protect_low", 0.2)))
			material.set_shader_parameter("protect_high", float(spec.get("protect_high", 0.45)))
			if spec.has("target"):
				var target: Array = spec.target
				material.set_shader_parameter("hue_replace", true)
				material.set_shader_parameter("target", Vector3(
					float(target[0]), float(target[1]), float(target[2])))
				material.set_shader_parameter("ref_luma", float(spec.get("ref_luma", 0.25)))
				material.set_shader_parameter("target_gain", float(spec.get("gain", 1.0)))
			material.set_shader_parameter("roughness_value", float(spec.get("roughness", roughness)))
			material.set_shader_parameter("metallic_value", float(spec.get("metallic", metallic)))
			material.set_shader_parameter("specular_value", float(spec.get("specular", specular)))
			node.set_surface_override_material(index, material)
	for child in node.get_children():
		_apply_tint(child, spec)


func _bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	var result := AABB()
	var found := false
	if node is MeshInstance3D and node.mesh:
		result = transform * node.mesh.get_aabb()
		found = true
	for child in node.get_children():
		var child_bounds := _bounds(child, transform)
		if child_bounds.size.length_squared() > 0:
			result = result.merge(child_bounds) if found else child_bounds
			found = true
	return result
