extends "res://.workbench/visual_host_base.gd"
## An explicit candidate-only fit, using SHA-bound real model bounds. The verified
## source host stays byte-identical; source hooks observe the final visual fit.
func _apply_material_hooks(node: GeometryInstance3D, instance: Dictionary, binding: Dictionary) -> void:
	super._apply_material_hooks(node, instance, binding)
	for material in node.get_meta("hole_style_materials", []): _repair_comic_lighting(material)
	var roles: Dictionary = binding.get("semanticMaterials", {})
	if roles.is_empty(): return
	var names := {"walkway":"walkway_color","paving":"paving_color","asphalt":"asphalt_color","kerb":"kerb_color","deep":"deep_color","light":"light_color"}
	var material = node.material_override if node.material_override != null else node.get_active_material(0)
	if not material is ShaderMaterial:
		push_error("WORKBENCH: named material requires the declared source shader")
		return
	var uniforms: Array = []
	for parameter in material.shader.get_shader_uniform_list(): uniforms.append(str(parameter.name))
	var recorded: Dictionary = {}
	for role in roles:
		if not names.has(role) or not str(names[role]) in uniforms:
			push_error("WORKBENCH: unsupported named material role: " + str(role))
			return
		var color := Color(str(roles[role]))
		material.set_shader_parameter(names[role],Vector3(color.r,color.g,color.b))
		recorded[role] = names[role]
	node.set_meta("workbench_semantic_uniforms", recorded)

func _repair_comic_lighting(material: Material) -> void:
	if recipe.get("assemblyWorkflowVersion", "") != "deterministic-assembly-v1" or not material is ShaderMaterial or not material.has_meta("workbench_comic_style"): return
	var previous := "DIFFUSE_LIGHT += vec3(0.32+0.68*wb_key)*ATTENUATION;"
	var corrected := "DIFFUSE_LIGHT += vec3(0.32+0.68*wb_key)*ATTENUATION*LIGHT_COLOR/PI;"
	var code: String = material.shader.code
	if code.contains(corrected): return
	if not code.contains(previous):
		push_error("WORKBENCH: unknown comic light implementation")
		return
	var values: Dictionary = {}
	for parameter in material.shader.get_shader_uniform_list(): values[str(parameter.name)] = material.get_shader_parameter(parameter.name)
	var shader := Shader.new()
	shader.code = code.replace(previous,corrected)
	material.shader = shader
	for name in values:
		if values[name] != null: material.set_shader_parameter(name,values[name])
	material.set_meta("workbench_comic_light_energy_fixed", true)

func _replace_mesh(node: MeshInstance3D, replacement: Dictionary) -> void:
	var selected: Dictionary = {}
	for override in recipe.get("visualOverrides", []):
		if str(override.instanceId) == _instance_for_node(node) and override.has("modelFit"):
			selected = override
	if selected.is_empty():
		super._replace_mesh(node, replacement)
		return
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
	if not _apply_model_refit(node, holder, selected):
		return
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
		for material in holder.get_meta("hole_visual_materials", []): _repair_comic_lighting(material)
		hook_records.append({"id": str(hook.id), "sha256": str(hook.sha256), "entrypoint": entrypoint, "ok": true})
	node.set_meta("workbench_hook_records", hook_records)


func _apply_model_refit(node: MeshInstance3D, holder: Node3D, override: Dictionary) -> bool:
	var fit: Dictionary = override.get("modelFit", {})
	if str(fit.get("schema", "")) != "godot_replacement_envelope_refit_v1" or str(fit.get("modelSha256", "")) != str(node.get_meta("workbench_model_sha", "")) or holder.get_child_count() != 1:
		push_error("WORKBENCH: refit model identity mismatch: " + str(override.instanceId))
		return false
	var raw := _bounds(holder.get_child(0), Transform3D.IDENTITY)
	var expected: Dictionary = fit.get("rawBounds", {})
	if not expected.has("min") or not expected.has("max") or not raw.position.is_equal_approx(_v(expected.min)) or not (raw.position + raw.size).is_equal_approx(_v(expected.max)):
		push_error("WORKBENCH: refit actual model bounds mismatch: " + str(override.instanceId))
		return false
	var transform_rows: Array = fit.get("transform", [])
	if transform_rows.size() != 4:
		push_error("WORKBENCH: refit transform missing")
		return false
	holder.transform = Transform3D(Basis(_v(transform_rows[0]), _v(transform_rows[1]), _v(transform_rows[2])), _v(transform_rows[3]))
	return true

func _apply_visual_override(node: MeshInstance3D, override: Dictionary) -> void:
	if not override.has("modelFit"):
		super._apply_visual_override(node, override)
		return
	var holder := node.get_node_or_null("WorkbenchVisual") as Node3D
	if holder == null or not _apply_model_refit(node, holder, override):
		push_error("WORKBENCH: refit replacement missing: " + str(override.instanceId))
		return
	var bounds := _bounds(holder, Transform3D.IDENTITY)
	node.set_meta("workbench_visual_override", override)
	node.set_meta("workbench_visual_override_transform", [_vec(holder.transform.basis.x), _vec(holder.transform.basis.y), _vec(holder.transform.basis.z), _vec(holder.transform.origin)])
	node.set_meta("workbench_visual_override_bounds", {"position": _vec(bounds.position), "size": _vec(bounds.size)})
