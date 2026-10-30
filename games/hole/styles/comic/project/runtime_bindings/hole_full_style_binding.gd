extends RefCounted
## Hole-owned presentation binding. The generic host supplies the exact contract
## instance; this provider knows Main's object_views and material/cache protocol.
const ModelLoader = preload("res://scripts/theme_model_loader.gd")
const ImportedShader = preload("res://shaders/imported_model.gdshader")
const KNOWN_SHADERS = ["res://shaders/object.gdshader", "res://shaders/imported_model.gdshader", "res://shaders/waterfront_floor.gdshader", "res://shaders/water.gdshader", "res://shaders/park_floor_v2.gdshader", "res://shaders/park_water_v2.gdshader"]

class PresentationSync extends Node:
	var source
	var materials: Array = []
	func _process(_delta: float) -> void:
		if not is_instance_valid(source) or source.floor_material == null:
			return
		var a = source.floor_material.get_shader_parameter("hole_a")
		var b = source.floor_material.get_shader_parameter("hole_b")
		for mat in materials:
			mat.set_shader_parameter("hole_a", a)
			mat.set_shader_parameter("hole_b", b)

func _instance(ctx: Dictionary) -> Dictionary:
	var scene: Node = ctx.get("scene")
	var original: MeshInstance3D = ctx.get("originalVisual")
	for candidate in ctx.get("contract", {}).get("gameplay", {}).get("instances", []):
		if str(candidate.get("id", "")) == str(ctx.get("instanceId", "")) and str(scene.get_path_to(original)) == str(candidate.get("nodePath", "")):
			return candidate
	return {}

func _owner(scene: Node, instance: Dictionary) -> Node3D:
	var root_path := str(instance.get("motionRoot", {}).get("nodePath", ""))
	return scene.get_node_or_null(NodePath(root_path)) as Node3D if not root_path.is_empty() else null

func _register(scene: Node, owner: Node3D, materials: Array) -> void:
	if owner != null and owner in scene.object_views:
		var registered: Array = owner.get_meta("cutaway_materials", []).duplicate()
		for material in materials:
			if not material in registered:
				registered.append(material)
		owner.set_meta("cutaway_materials", registered)
	else:
		var sync: Node = scene.get_node_or_null("WorkbenchHolePresentationSync")
		if sync == null:
			sync = PresentationSync.new()
			sync.name = "WorkbenchHolePresentationSync"
			sync.source = scene
			scene.add_child(sync)
		for material in materials:
			if not material in sync.materials:
				sync.materials.append(material)
		sync.call("_process", 0.0)


func bind_visual(ctx: Dictionary) -> Dictionary:
	var scene: Node = ctx.get("scene")
	var original: MeshInstance3D = ctx.get("originalVisual")
	var replacement: Node = ctx.get("replacementVisual")
	var holder: Node3D = ctx.get("replacementRoot")
	var contract: Dictionary = ctx.get("contract", {})
	var identifier := str(ctx.get("instanceId", ""))
	if scene == null or original == null or replacement == null or holder == null:
		return {"ok": false, "reason": "Missing binding context"}
	var instance: Dictionary = {}
	for candidate in contract.get("gameplay", {}).get("instances", []):
		if str(candidate.get("id", "")) == identifier:
			instance = candidate
			break
	if instance.is_empty() or str(scene.get_path_to(original)) != str(instance.get("nodePath", "")):
		return {"ok": false, "reason": "Exact contract visual does not match"}
	var root_path := str(instance.get("motionRoot", {}).get("nodePath", ""))
	var object_root: Node3D = scene.get_node_or_null(NodePath(root_path)) as Node3D
	var owned_views = scene.get("object_views")
	var static_scenery := str(instance.get("stablePath", "")).begins_with("./WaterfrontEnvironment/") and str(instance.get("semanticRole", "")) == "SCENERY_ONLY"
	if not static_scenery and (root_path.is_empty() or object_root == null or not owned_views is Array or not object_root in owned_views):
		return {"ok": false, "reason": "Motion root is not a source-owned object view"}
	if (not static_scenery and not object_root.is_ancestor_of(original)) or holder.get_parent() != original or replacement.get_parent() != holder:
		return {"ok": false, "reason": "Replacement is outside its exact motion root"}
	if not scene.has_method("_sync_views") or not scene.has_method("_sync_occlusion"):
		return {"ok": false, "reason": "Source material writers are unavailable"}
	var materials: Array = []
	var error := ModelLoader._runtime_materials(replacement, materials, {"enable_hole_clip": true}, {})
	if error != OK or materials.is_empty():
		return {"ok": false, "reason": "GLB has no supported source material surfaces"}
	# The source loader creates a fresh shader for every surface, per object.
	# Do not share their occlusion_fade across separate simulation views.
	for material in materials:
		if not material is ShaderMaterial or material.shader != ImportedShader:
			return {"ok": false, "reason": "Unexpected imported shader"}
	var styled: Array = []
	var binding: Dictionary = ctx.get("binding", {})
	if binding.is_empty():
		binding = ctx.get("recipe", {})
	_paint_replacement(replacement, binding, instance, styled)
	if not styled.is_empty():
		materials = styled
	_register(scene, object_root if not static_scenery else null, materials)
	if not static_scenery:
		_rebuild_geometry(object_root)
	# Initialize from source writers immediately; later ticks use the same arrays.
	scene.call("_sync_views")
	scene.call("_sync_occlusion", 0.0)
	holder.set_meta("hole_visual_materials", materials)
	holder.set_meta("hole_visual_binding", {"instanceId": identifier, "motionRoot": root_path,
		"materialCount": materials.size(), "hiddenOriginalSkipped": original.layers == 0})
	return {"ok": true, "materialCount": materials.size(), "motionRoot": root_path}

func _collect(node: Node, incoming: Transform3D, parts: Array, owner: Node3D) -> void:
	var transform := incoming
	if node is Node3D:
		transform = incoming * node.transform
	# layers=0 hides the original mesh, but its visible replacement children still
	# inherit its retained transform and must be traversed.
	if node is MeshInstance3D and node.mesh != null and node.layers != 0 and node.visible:
		var bounds: AABB = node.mesh.get_aabb()
		parts.append({"bounds": bounds, "to_mesh": transform.affine_inverse(),
			"view_bounds": transform * bounds, "nodePath": str(owner.get_path_to(node))})
	for child in node.get_children():
		_collect(child, transform, parts, owner)

func _rebuild_geometry(view: Node3D) -> void:
	var parts: Array = []
	if view is MeshInstance3D and view.mesh != null and view.layers != 0 and view.visible:
		parts.append({"bounds": view.mesh.get_aabb(), "to_mesh": Transform3D.IDENTITY,
			"view_bounds": view.mesh.get_aabb(), "nodePath": "."})
	for child in view.get_children():
		_collect(child, Transform3D.IDENTITY, parts, view)
	var bounds := AABB()
	for index in range(parts.size()):
		bounds = parts[index]["view_bounds"] if index == 0 else bounds.merge(parts[index]["view_bounds"])
	view.set_meta("occlusion_geometry", {"bounds": bounds, "parts": parts})

func bind_material(ctx: Dictionary) -> Dictionary:
	var scene: Node = ctx.get("scene")
	var original: MeshInstance3D = ctx.get("originalVisual")
	if scene == null or original == null:
		return {"ok": false, "reason": "Missing material context"}
	var instance := _instance(ctx)
	if instance.is_empty():
		return {"ok": false, "reason": "Exact material contract mismatch"}
	var path := str(instance.get("stablePath", ""))
	if not path.begins_with("./LogicalUnits_215/") and not path.begins_with("./WaterfrontEnvironment/"):
		return {"ok": false, "reason": "Gameplay UI, character and feedback retained"}
	var owner := _owner(scene, instance)
	if path.begins_with("./LogicalUnits_215/") and (owner == null or not owner in scene.object_views or not owner.is_ancestor_of(original)):
		return {"ok": false, "reason": "Source motion owner mismatch"}
	var materials: Array = []
	var binding: Dictionary = ctx.get("binding", {})
	if original.material_override is ShaderMaterial:
		var previous: ShaderMaterial = original.material_override
		var next := _style_material(previous, binding, instance)
		if next == null:
			return {"ok": false, "reason": "Unsupported source shader"}
		original.material_override = next
		if scene.floor_material == previous:
			scene.floor_material = next
		materials.append(next)
	else:
		for index in range(original.mesh.get_surface_count()):
			var previous = original.get_active_material(index)
			if not previous is ShaderMaterial:
				return {"ok": false, "reason": "Only declared source shader surfaces supported"}
			var next := _style_material(previous, binding, instance)
			if next == null:
				return {"ok": false, "reason": "Unsupported source shader surface"}
			original.set_surface_override_material(index, next)
			materials.append(next)
	_register(scene, owner, materials)
	scene.call("_sync_views")
	scene.call("_sync_occlusion", 0.0)
	original.set_meta("hole_style_materials", materials)
	return {"ok": true, "materialCount": materials.size(), "style": binding.get("renderStyle", {})}

func _paint_replacement(node: Node, binding: Dictionary, instance: Dictionary, materials: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for index in range(node.mesh.get_surface_count()):
			var source = node.get_active_material(index)
			if source is ShaderMaterial:
				var styled := _style_material(source, binding, instance)
				if styled != null:
					node.set_surface_override_material(index, styled)
					materials.append(styled)
	for child in node.get_children():
		_paint_replacement(child, binding, instance, materials)

func _function_end(code: String, name: String) -> int:
	var start := code.find("void " + name + "()")
	if start < 0:
		return -1
	var opening := code.find("{", start)
	var depth := 1
	for index in range(opening + 1, code.length()):
		if code[index] == "{":
			depth += 1
		elif code[index] == "}":
			depth -= 1
			if depth == 0:
				return index
	return -1

func _style_material(source: ShaderMaterial, binding: Dictionary, instance: Dictionary) -> ShaderMaterial:
	var shader_path := source.shader.resource_path
	if not shader_path in KNOWN_SHADERS:
		return null
	var material: ShaderMaterial = source.duplicate()
	var colors: Array = binding.get("palette", {}).get("colors", ["ae493b", "e5d4b1", "679884", "233e3b"])
	var family := str(instance.get("sourceFamily", instance.get("asset_id", "")))
	var selected := absi(family.hash()) % colors.size()
	var palette_color := Color(str(colors[selected]))
	var is_floor := str(instance.get("semanticRole", "")) == "GROUND_SURFACE"
	var is_water := str(instance.get("semanticRole", "")) == "WATER_VISUAL"
	if is_floor:
		palette_color = Color(str(colors[mini(1, colors.size()-1)]))
		for parameter in ["walkway_color", "paving_color", "kerb_color"]:
			var color := palette_color if parameter != "kerb_color" else Color(str(colors[0]))
			material.set_shader_parameter(parameter, Vector3(color.r,color.g,color.b))
		var road := Color(str(colors[mini(3, colors.size()-1)]))
		material.set_shader_parameter("asphalt_color", Vector3(road.r,road.g,road.b))
	elif is_water:
		palette_color = Color(str(colors[mini(2, colors.size()-1)]))
		var deep := palette_color.darkened(0.30)
		var light := palette_color.lightened(0.18)
		material.set_shader_parameter("deep_color", Vector3(deep.r,deep.g,deep.b))
		material.set_shader_parameter("light_color", Vector3(light.r,light.g,light.b))
	var style: Dictionary = binding.get("renderStyle", {})
	if style.get("mode", "") != "comic":
		if shader_path.ends_with("object.gdshader"):
			material.set_shader_parameter("body_color", palette_color)
		return material
	var code: String = source.shader.code
	# This is a source-owned, single fragment pass. Existing discard statements and
	# uniforms survive byte-for-byte; no expanded hull can escape clipping or bounds.
	var uniforms := "\nuniform vec4 wb_ink_color : source_color = vec4(0.08,0.12,0.12,1.0);\nuniform vec4 wb_palette_color : source_color = vec4(1.0);\nuniform float wb_palette_mix = 0.75;\nuniform float wb_ink_strength = 0.78;\nuniform float wb_contour_width = 0.08;\nuniform float wb_hatch_strength = 0.08;\nuniform float wb_light_bands = 3.0;\n"
	var end := _function_end(code, "fragment")
	if end < 0:
		return null
	var shade := "\n\tvec3 wb_world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL,0.0)).xyz);\n\tfloat wb_facing = dot(wb_world_normal,normalize(vec3(0.45,0.82,0.35)));\n\tfloat wb_band = floor(clamp(wb_facing*0.5+0.5,0.0,0.999)*wb_light_bands)/max(wb_light_bands-1.0,1.0);\n\tfloat wb_ink = 1.0-smoothstep(wb_contour_width,wb_contour_width*2.0+0.01,abs(dot(normalize(NORMAL),normalize(VIEW))));\n\tfloat wb_hatch = step(0.83,fract((FRAGCOORD.x+FRAGCOORD.y*0.67)*0.105))*step(wb_facing,0.20)*wb_hatch_strength;\n\tfloat wb_luma = dot(ALBEDO,vec3(0.2126,0.7152,0.0722));\n\tvec3 wb_paper = mix(ALBEDO,wb_palette_color.rgb*(0.68+0.32*wb_luma),wb_palette_mix);\n\tALBEDO = mix(wb_paper*(0.66+0.34*wb_band),wb_ink_color.rgb,clamp(wb_ink*wb_ink_strength+wb_hatch,0.0,1.0));\n\tEMISSION = ALBEDO*0.18;\n\tROUGHNESS = 1.0;\n\tSPECULAR = 0.0;\n"
	code = code.insert(end, shade)
	# Imported PBR and source toy shaders receive the same cel light, while water
	# remains unshaded. Source clipping stays ahead of the injected paint operation.
	var light_end := _function_end(code, "light")
	if light_end >= 0:
		var light_start := code.find("{", code.find("void light()"))
		code = code.substr(0, light_start+1) + "\n\tfloat wb_key = floor(clamp(dot(NORMAL,LIGHT)*0.5+0.5,0.0,0.999)*wb_light_bands)/max(wb_light_bands-1.0,1.0);\n\tDIFFUSE_LIGHT += vec3(0.32+0.68*wb_key)*ATTENUATION;\n" + code.substr(light_end)
	else:
		code += "\nvoid light() { float wb_key = floor(clamp(dot(NORMAL,LIGHT)*0.5+0.5,0.0,0.999)*wb_light_bands)/max(wb_light_bands-1.0,1.0); DIFFUSE_LIGHT += vec3(0.32+0.68*wb_key)*ATTENUATION; }\n"
	var derived := Shader.new()
	derived.code = code.insert(code.find("varying "), uniforms)
	material.shader = derived
	material.set_shader_parameter("wb_ink_color", Color(str(style.get("inkColor", "182a2a"))))
	material.set_shader_parameter("wb_palette_color", palette_color)
	var mix_amount := float(style.get("paletteMix", 0.78))
	# Preserve an authored replacement's national-comic surface identity and UVs.
	if shader_path.ends_with("imported_model.gdshader"):
		mix_amount *= 0.25
	if is_floor or is_water:
		mix_amount = 0.0
	material.set_shader_parameter("wb_palette_mix", mix_amount)
	material.set_shader_parameter("wb_ink_strength", float(style.get("inkStrength", 0.78)))
	material.set_shader_parameter("wb_contour_width", float(style.get("contourWidth", 0.08)))
	material.set_shader_parameter("wb_hatch_strength", float(style.get("hatchStrength", 0.08)))
	material.set_shader_parameter("wb_light_bands", float(style.get("lightBands", 3)))
	material.set_meta("workbench_comic_style", style.duplicate(true))
	material.set_meta("workbench_source_shader", shader_path)
	return material
