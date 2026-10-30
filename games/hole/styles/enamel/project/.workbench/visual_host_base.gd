extends Node
## Revision 2: exact native-verified project material callbacks. Revision 1 stays frozen.
## Additive visual binding; gameplay nodes, scripts, resources and collision stay intact.
var recipe: Dictionary = {}
var contract: Dictionary = {}
var scene: Node
var indexed := {}
var applied := {}
var instances_by_path := {}
var scoped_ids := {}
var check_frames := 0

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://.workbench/appearance.json"))
	if parsed is Dictionary:
		recipe = parsed
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://.workbench/contract.json"))
	if source is Dictionary:
		contract = source
	for instance in contract.get("gameplay", {}).get("instances", []):
		instances_by_path[str(instance.stablePath)] = instance
	for identifier in recipe.get("scope", {}).get("instanceIds", []):
		scoped_ids[str(identifier)] = true
	call_deferred("_attach")

func _attach() -> void:
	for _i in range(3):
		await get_tree().process_frame
	scene = get_tree().current_scene
	if scene == null:
		for node in get_tree().root.get_children():
			if node != self and node is Node3D:
				scene = node
				break
	if scene == null:
		push_error("WORKBENCH: visual host has no entry scene")
		return
	_scan(scene, ".")
	_apply_environment()
	get_tree().node_added.connect(_node_added)
	print("WORKBENCH_VISUAL_BIND_PASS: %d bindings" % applied.size())

func _node_added(_node: Node) -> void:
	check_frames = 2

func _process(_delta: float) -> void:
	if check_frames > 0:
		check_frames -= 1
		if check_frames == 0 and is_instance_valid(scene):
			_scan(scene, ".")

func _segment(node: Node) -> String:
	var raw := str(node.name)
	if not raw.begins_with("@"):
		return raw
	var index := 0
	for sibling in node.get_parent().get_children():
		if sibling == node:
			break
		if sibling.get_class() == node.get_class():
			index += 1
	return node.get_class() + "[" + str(index) + "]"

func _scan(node: Node, stable_path: String) -> void:
	if str(node.name).begins_with("Workbench"):
		return
	indexed[stable_path] = node
	if ((node is MeshInstance3D and node.mesh != null) or (node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null)) and not node.has_meta("workbench_applied"):
		var target: Dictionary = instances_by_path.get(stable_path, {})
		if not target.is_empty() and scoped_ids.has(str(target.id)) and (target.get("editable", {}).get("material", false) or target.get("editable", {}).get("model", false)):
			_apply_mesh(node, target)
	for child in node.get_children():
		_scan(child, stable_path.path_join(_segment(child)))

func _color(value, fallback: Color) -> Color:
	return Color(str(value)) if value is String else fallback

func _apply_mesh(node: GeometryInstance3D, instance: Dictionary) -> void:
	var binding: Dictionary = recipe.get("materialBindings", {}).get(str(instance.id), {})
	var palette: Dictionary = binding.get("palette", recipe.get("palette", {}))
	var colors: Array = palette.get("colors", ["748593", "b7bcc6", "45515d"])
	var pick: int = absi(str(instance.get("asset_id", "")).hash()) % maxi(1, colors.size())
	var material := StandardMaterial3D.new()
	material.albedo_color = _color(colors[pick], Color("748593"))
	material.roughness = float(binding.get("roughness", recipe.get("roughness", 0.8)))
	material.metallic = float(binding.get("metallic", recipe.get("metallic", 0.0)))
	# Material overlays preserve original alpha, shader cutaways and gameplay feedback.
	var can_apply_material: bool = instance.get("editable", {}).get("material", false) and not binding.is_empty() and not node.material_override is ShaderMaterial
	if node.material_override is BaseMaterial3D:
		material.transparency = node.material_override.transparency
		material.albedo_color.a = node.material_override.albedo_color.a
	var resource_mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
	for index in range(resource_mesh.get_surface_count()):
		var old = node.get_active_material(index) if node is MeshInstance3D else resource_mesh.surface_get_material(index)
		if old is ShaderMaterial:
			can_apply_material = false
	if can_apply_material:
		node.material_overlay = material
	if not binding.is_empty() and instance.get("editable", {}).get("material", false):
		_apply_material_hooks(node, instance, binding)
	for replacement in recipe.get("replacements", []):
		if node is MeshInstance3D and instance.id in replacement.get("instanceIds", []):
			_replace_mesh(node, replacement)
	for override in recipe.get("visualOverrides", []):
		if node is MeshInstance3D and str(override.get("instanceId", "")) == str(instance.id):
			_apply_visual_override(node, override)
	node.set_meta("workbench_applied", true)
	applied[instance.id] = true

func _apply_material_hooks(node: GeometryInstance3D, instance: Dictionary, binding: Dictionary) -> void:
	var records: Array = []
	for hook in binding.get("hooks", []):
		var path := str(hook.get("path", ""))
		var entrypoint := str(hook.get("materialEntrypoint", ""))
		if not path.begins_with("res://") or FileAccess.get_sha256(path) != str(hook.get("sha256", "")):
			push_error("WORKBENCH: material hook hash mismatch")
			return
		var script = load(path)
		if not script is Script or not script.can_instantiate():
			push_error("WORKBENCH: material hook cannot be instantiated")
			return
		var handler = script.new()
		if not handler is RefCounted or not handler.has_method(entrypoint):
			push_error("WORKBENCH: material hook must expose its declared entrypoint")
			return
		var result = handler.call(entrypoint, {"scene": scene, "originalVisual": node, "instanceId": instance.id, "contract": contract, "binding": binding, "recipe": recipe})
		if not result is Dictionary or not bool(result.get("ok", false)):
			push_error("WORKBENCH: material hook rejected exact binding: " + str(instance.id))
			return
		records.append({"id": str(hook.id), "sha256": str(hook.sha256), "entrypoint": entrypoint, "ok": true})
	node.set_meta("workbench_material_hook_records", records)

func _replace_mesh(node: MeshInstance3D, replacement: Dictionary) -> void:
	var resource = load(str(replacement.path))
	if not resource is PackedScene:
		push_error("WORKBENCH: visual asset is not a PackedScene: " + str(replacement.path))
		return
	var holder := Node3D.new()
	holder.name = "WorkbenchVisual"
	node.add_child(holder)
	var visual: Node = resource.instantiate()
	holder.add_child(visual)
	var bounds := _bounds(visual, Transform3D.IDENTITY)
	if bounds.size.length_squared() <= 0.000001:
		push_error("WORKBENCH: generated visual has empty bounds")
		holder.queue_free()
		return
	var expected: Array = replacement.get("envelope", [1, 1, 1])
	var target := Vector3(float(expected[0]), float(expected[1]), float(expected[2]))
	var ratio := minf(target.x / maxf(bounds.size.x, 0.00001), minf(target.y / maxf(bounds.size.y, 0.00001), target.z / maxf(bounds.size.z, 0.00001)))
	holder.scale = Vector3.ONE * ratio
	var original := node.mesh.get_aabb()
	holder.position = original.position + original.size * 0.5 - (bounds.position + bounds.size * 0.5) * ratio
	# Keep the original mesh and its transform accessible to gameplay scripts.
	node.layers = 0
	node.set_meta("workbench_model_sha", str(replacement.sha256))
	holder.set_meta("workbench_source", replacement.get("source", {}))
	var material_binding: Dictionary = recipe.get("materialBindings", {}).get(str(_instance_for_node(node)), {})
	if material_binding.get("explicitMaterial", false):
		_paint_model(visual, material_binding)
	var hook_records: Array = []
	for hook in replacement.get("hooks", []):
		var path := str(hook.get("path", ""))
		if not path.begins_with("res://") or FileAccess.get_sha256(path) != str(hook.get("sha256", "")):
			push_error("WORKBENCH: visual binding hook hash mismatch")
			return
		var script = load(path)
		if not script is Script or not script.can_instantiate():
			push_error("WORKBENCH: visual binding hook cannot be instantiated")
			return
		var handler = script.new()
		var entrypoint := str(hook.get("entrypoint", ""))
		if not handler is RefCounted or not handler.has_method(entrypoint):
			push_error("WORKBENCH: visual binding hook must be RefCounted with its declared entrypoint")
			return
		var result = handler.call(entrypoint, {"scene": scene, "originalVisual": node, "replacementRoot": holder, "replacementVisual": visual, "instanceId": _instance_for_node(node), "contract": contract, "replacement": replacement, "recipe": recipe, "binding": material_binding})
		if not result is Dictionary or not bool(result.get("ok", false)):
			push_error("WORKBENCH: visual binding hook rejected replacement")
			return
		hook_records.append({"id": str(hook.id), "sha256": str(hook.sha256), "entrypoint": entrypoint, "ok": true})
	node.set_meta("workbench_hook_records", hook_records)

func _v(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _apply_visual_override(node: MeshInstance3D, override: Dictionary) -> void:
	var holder: Node3D = node.get_node_or_null("WorkbenchVisual") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "WorkbenchVisual"
		node.add_child(holder)
		var mirror := MeshInstance3D.new()
		mirror.name = "WorkbenchOriginalVisual"
		mirror.mesh = node.mesh
		mirror.material_override = node.material_override
		mirror.material_overlay = node.material_overlay
		mirror.cast_shadow = node.cast_shadow
		mirror.gi_mode = node.gi_mode
		mirror.layers = node.layers
		for index in range(node.mesh.get_surface_count()):
			mirror.set_surface_override_material(index, node.get_surface_override_material(index))
		holder.add_child(mirror)
		node.layers = 0
	var q: Array = override.quaternion
	var basis := Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))).scaled_local(_v(override.scale))
	var anchor := _v(override.anchor)
	var offset := _v(override.offset)
	holder.transform = Transform3D(basis, anchor + offset - basis * anchor) * holder.transform
	var bounds := _bounds(holder, Transform3D.IDENTITY)
	node.set_meta("workbench_visual_override", override)
	node.set_meta("workbench_visual_override_transform", [_vec(holder.transform.basis.x), _vec(holder.transform.basis.y), _vec(holder.transform.basis.z), _vec(holder.transform.origin)])
	node.set_meta("workbench_visual_override_bounds", {"position": _vec(bounds.position), "size": _vec(bounds.size)})

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _instance_for_node(node: Node) -> String:
	for instance in contract.get("gameplay", {}).get("instances", []):
		if str(instance.nodePath) == str(scene.get_path_to(node)):
			return str(instance.id)
	return ""

func _paint_model(node: Node, binding: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var colors: Array = binding.get("palette", {}).get("colors", ["ffffff"])
		var color := _color(colors[0], Color.WHITE)
		for index in range(node.mesh.get_surface_count()):
			var original = node.get_active_material(index)
			if original is BaseMaterial3D:
				var material: BaseMaterial3D = original.duplicate(true)
				material.albedo_color *= color
				material.roughness = float(binding.get("roughness", material.roughness))
				material.metallic = float(binding.get("metallic", material.metallic))
				node.set_surface_override_material(index, material)
	for child in node.get_children():
		_paint_model(child, binding)

func _bounds(node: Node, accumulated: Transform3D) -> AABB:
	var transform := accumulated
	if node is Node3D:
		transform = accumulated * node.transform
	var result := AABB()
	var populated := false
	if node is MeshInstance3D and node.mesh != null:
		result = transform * node.mesh.get_aabb()
		populated = true
	for child in node.get_children():
		var child_bounds := _bounds(child, transform)
		if child_bounds.size.length_squared() > 0:
			result = result.merge(child_bounds) if populated else child_bounds
			populated = true
	return result

func _apply_environment() -> void:
	var settings: Dictionary = recipe.get("environment", {})
	if settings.is_empty():
		return
	var env_node := _find_environment(scene)
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorkbenchEnvironment"
		scene.add_child(env_node)
	var environment: Environment = env_node.environment.duplicate(true) if env_node.environment != null else Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _color(settings.get("background", "182431"), Color("182431"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _color(settings.get("ambient", "d2e2f0"), Color("d2e2f0"))
	environment.ambient_light_energy = float(settings.get("ambientEnergy", 0.7))
	env_node.environment = environment
	var lights: Array = []
	_collect_lights(scene, lights)
	for light in lights:
		light.light_color = _color(settings.get("lightColor", "fff1dd"), Color("fff1dd"))
		light.light_energy = float(settings.get("lightEnergy", 1.0))

func _find_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found := _find_environment(child)
		if found != null:
			return found
	return null

func _collect_lights(node: Node, result: Array) -> void:
	if node is DirectionalLight3D:
		result.append(node)
	for child in node.get_children():
		_collect_lights(child, result)
