extends Node
## Candidate-only, exact existing Label3D overrides. Original source and visual hook stay frozen.
var scene: Node
var contract: Dictionary = {}
var recipe: Dictionary = {}
var model_hashes: Dictionary = {}
var baked_labels: Array = []

func _ready() -> void:
	process_priority = 1000
	contract = JSON.parse_string(FileAccess.get_file_as_string("res://.workbench/contract.json"))
	recipe = JSON.parse_string(FileAccess.get_file_as_string("res://.workbench/appearance.json"))
	call_deferred("_attach")

func _process(_delta: float) -> void:
	for label in baked_labels:
		if is_instance_valid(label):
			label.visible = false

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
		push_error("WORKBENCH: text overlay has no scene")
		return
	var pending: Array = []
	for override in recipe.get("labelOverrides", []):
		var item = _apply(override)
		if not item.is_empty():
			pending.append(item)
	await get_tree().process_frame
	for item in pending:
		_fit(item)

func _apply(override: Dictionary) -> Dictionary:
	var declared: Dictionary = {}
	var instance: Dictionary = {}
	for row in contract.get("nodes", []):
		if str(row.path) == str(override.nodePath):
			declared = row
	for row in contract.get("gameplay", {}).get("instances", []):
		if str(row.id) == str(override.instanceId):
			instance = row
	if declared.is_empty() or instance.is_empty() or declared.get("role", "") != "INDEPENDENT_SIGNAGE" or declared.get("class", "") != "Label3D" or not instance.get("editable", {}).get("material", false) or not str(override.instanceId) in recipe.get("scope", {}).get("instanceIds", []) or declared.get("motionRoot", {}).get("stablePath", "") != instance.get("motionRoot", {}).get("stablePath", ""):
		push_error("WORKBENCH: text target is not the declared independent signage")
		return {}
	var label = scene.get_node_or_null(NodePath(str(override.nodePath)))
	if not label is Label3D or label.get_meta("role", "") != "INDEPENDENT_SIGNAGE" or label.text != str(override.expectedText):
		push_error("WORKBENCH: text target path or source text has changed: " + str(override.nodePath))
		return {}
	var path := str(override.fontPath)
	if not path.begins_with("res://") or FileAccess.get_sha256(path) != str(override.fontSha256):
		push_error("WORKBENCH: text font hash mismatch")
		return {}
	var font = load(path)
	if not font is Font:
		push_error("WORKBENCH: text font cannot be loaded")
		return {}
	var text := str(override.text)
	for index in range(text.length()):
		if not font.has_char(text.unicode_at(index)):
			push_error("WORKBENCH: packaged font lacks required text glyph")
			return {}
	var original_bounds: AABB = label.get_aabb()
	var original_pixel_size: float = label.pixel_size
	var transform: Transform3D = label.transform
	label.font = font
	label.text = text
	return {"label": label, "override": override, "originalBounds": original_bounds, "originalPixelSize": original_pixel_size, "transform": transform, "rendering": _rendering(label)}

func _fit(item: Dictionary) -> void:
	var label: Label3D = item.label
	var override: Dictionary = item.override
	var original_bounds: AABB = item.originalBounds
	var original_pixel_size: float = item.originalPixelSize
	# Font shaping is deferred. A production-derived plate can relocate only this exact sign.
	var actual: AABB = label.get_aabb()
	var target_transform: Transform3D = item.transform
	var limits := Vector2(original_bounds.size.x, original_bounds.size.y)
	var anchor: Dictionary = {}
	var baked: Dictionary = override.get("surfaceTextBake", {})
	if not baked.is_empty():
		if not _verify_baked(override):
			return
		var ratio := minf(1.0, minf(limits.x / maxf(actual.size.x, 0.00001), limits.y / maxf(actual.size.y, 0.00001)))
		label.pixel_size = original_pixel_size * ratio
		label.visible = false
		baked_labels.append(label)
		label.set_meta("workbench_text_override", {"labelId":str(override.labelId),"instanceId":str(override.instanceId),"expectedText":str(override.expectedText),"text":label.text,"textSha256":label.text.sha256_text(),"fontSha256":str(override.fontSha256),"originalPixelSize":original_pixel_size,"originalBounds":[original_bounds.size.x,original_bounds.size.y,original_bounds.size.z],"originalRendering":item.rendering,"glyphsVerified":true,"overlaySha256":FileAccess.get_sha256("res://.workbench/text_overlay.gd"),"mode":"basecolor-bake","bakeSha256":baked.sha256})
		return
	if not override.get("surfaceAnchor", {}).is_empty():
		anchor = _surface_anchor(label, override, item.transform)
		if anchor.is_empty():
			return
		target_transform = _transform(anchor.labelTransform)
		limits.x = minf(limits.x, float(anchor.planeSize[0]))
		limits.y = minf(limits.y, float(anchor.planeSize[1]))
	var ratio := minf(1.0, minf(limits.x / maxf(actual.size.x, 0.00001), limits.y / maxf(actual.size.y, 0.00001)))
	label.pixel_size = original_pixel_size * ratio
	label.transform = target_transform
	if anchor.get("schema", "") == "godot_independent_signage_anchor_v1":
		if anchor.get("presentation", {}).get("schema", "") == "deterministic_glyph_only_v1":
			label.shaded = true
			label.outline_size = 0
			label.no_depth_test = false
		else:
			_independent_plate(label, anchor)
	label.set_meta("workbench_text_override", {"labelId": str(override.labelId), "instanceId": str(override.instanceId), "expectedText": str(override.expectedText), "text": label.text, "textSha256": label.text.sha256_text(), "fontSha256": str(override.fontSha256), "originalPixelSize": original_pixel_size, "originalBounds": [original_bounds.size.x, original_bounds.size.y, original_bounds.size.z], "originalRendering": item.rendering, "surfaceAnchor": anchor, "glyphsVerified": true, "overlaySha256": FileAccess.get_sha256("res://.workbench/text_overlay.gd")})

func _verify_baked(override: Dictionary) -> bool:
	var b: Dictionary = override.surfaceTextBake
	var valid := false
	for replacement in recipe.get("replacements", []):
		if str(override.instanceId) in replacement.get("instanceIds", []) and replacement.sha256 == b.modelSha256 and FileAccess.get_sha256(str(replacement.path)) == b.modelSha256:
			valid = true
	var receipt_path := str(b.get("packedReceiptPath", ""))
	if not valid or b.get("schema", "") != "surface_text_bake_binding_v1" or b.get("textSha256", "") != str(override.text).sha256_text() or not b.get("noBackgroundPlate", false) or not receipt_path.begins_with("res://") or FileAccess.get_sha256(receipt_path) != str(b.receiptHash):
		push_error("WORKBENCH: baked lettering model or receipt mismatch")
		return false
	return true

func _surface_anchor(label: Label3D, override: Dictionary, original_transform: Transform3D) -> Dictionary:
	var anchor: Dictionary = override.surfaceAnchor
	var model = scene.get_node_or_null(NodePath(str(anchor.get("modelNodePath", ""))))
	var holder = model.get_node_or_null("WorkbenchVisual") if model is MeshInstance3D else null
	var replacement: Dictionary = {}
	for row in recipe.get("replacements", []):
		if str(override.instanceId) in row.get("instanceIds", []) and str(row.get("sha256", "")) == str(anchor.get("modelSha256", "")):
			replacement = row
	var measured: bool = anchor.get("schema", "") == "godot_measured_signage_anchor_v1"
	var independent: bool = anchor.get("schema", "") == "godot_independent_signage_anchor_v1"
	var valid: bool = (measured or independent or anchor.get("schema", "") == "godot_signage_anchor_v1") and anchor.get("labelId", "") == override.labelId and anchor.get("instanceId", "") == override.instanceId and anchor.get("nodePath", "") == override.nodePath and anchor.get("sourceExpectedText", "") == override.expectedText and model is MeshInstance3D and holder is Node3D and not replacement.is_empty()
	if not valid:
		push_error("WORKBENCH: signage anchor has no exact production model")
		return {}
	var path: String = str(replacement.path)
	if not model_hashes.has(path):
		model_hashes[path] = FileAccess.get_sha256(path)
	if model_hashes[path] != anchor.modelSha256 or model.get_meta("workbench_model_sha", "") != anchor.modelSha256 or not _same_transform(original_transform, _transform(anchor.sourceLabelTransform)) or not _same_transform(holder.transform, _transform(anchor.holderTransform)):
		push_error("WORKBENCH: signage model hash, source transform or actual fit changed")
		return {}
	var host = get_tree().root.get_node_or_null("WorkbenchAppearance")
	if host == null or not host.has_method("_bounds") or holder.get_child_count() != 1:
		push_error("WORKBENCH: signage has no measured managed model holder")
		return {}
	var bounds: AABB = host.call("_bounds", holder.get_child(0), Transform3D.IDENTITY)
	var measured_bounds: Dictionary = anchor.measuredBounds
	if bounds.position.distance_to(_v(measured_bounds.min)) > 0.00004 or bounds.end.distance_to(_v(measured_bounds.max)) > 0.00004:
		push_error("WORKBENCH: signage actual model bounds changed")
		return {}
	var front: Vector3
	var normal: Vector3
	if independent:
		var confirmed: bool = false
		for row in recipe.get("independentSignageAudit", []):
			if row.get("labelId", "") == override.labelId and row.get("instanceId", "") == override.instanceId and row.get("sha256", "") == anchor.sha256 and row.get("geometryHash", "") == anchor.geometryHash and row.get("modelSha256", "") == anchor.modelSha256 and row.get("nativeSceneVerified", true) == false and row.get("humanArtApproval", true) == false:
				confirmed = true
		if not confirmed or replacement.get("source", {}).get("version", "") != "G1" or replacement.get("source", {}).get("planId", "") != anchor.planId or replacement.get("source", {}).get("jobId", "") != anchor.modelJobId or not anchor.get("presentation", {}).get("schema", "") in ["deterministic_sign_quad_v1", "deterministic_glyph_only_v1"] or not anchor.presentation.get("depthTest", false):
			push_error("WORKBENCH: independent signage has no exact explicit presentation decision")
			return {}
	elif measured:
		# Node validates actual triangle coverage; runtime verifies the same bytes and fit.
		var confirmed: bool = false
		for row in recipe.get("signSurfaceMapAudit", []):
			if row.get("mapId", "") == anchor.mapId and row.get("mapHash", "") == anchor.mapHash and row.get("geometryHash", "") == anchor.geometryHash and row.get("modelSha256", "") == anchor.modelSha256 and str(override.labelId) in row.get("labelIds", []):
				confirmed = true
		if not confirmed or replacement.get("source", {}).get("version", "") != "G1" or replacement.get("source", {}).get("planId", "") != anchor.planId or replacement.get("source", {}).get("jobId", "") != anchor.modelJobId:
			push_error("WORKBENCH: measured signage has no exact reviewed map")
			return {}
		front = _v(anchor.surface.center)
		normal = _v(anchor.surface.normal)
	else:
		var part: Dictionary = anchor.part
		var size := _v(part.size)
		var part_basis := Basis.from_euler(_v(part.get("rotation", [0, 0, 0])))
		front = _v(part.position) + part_basis * Vector3(0, 0, size.z * 0.5)
		normal = part_basis.z
	var local_front: Vector3 = _v(anchor.presentation.modelLocalCenter) if independent else holder.transform * front + (holder.transform.basis * normal).normalized() * float(anchor.clearance)
	var relative_transform: Transform3D = label.get_parent().global_transform.affine_inverse() * model.global_transform
	var target := Transform3D(original_transform.basis, relative_transform * local_front)
	if not _same_transform(target, _transform(anchor.labelTransform)):
		push_error("WORKBENCH: signage target is not the measured production plate")
		return {}
	var result: Dictionary = anchor.duplicate(true)
	result.holderTransform = _rows(holder.transform)
	result.measuredBounds = {"min": _vec(bounds.position), "max": _vec(bounds.end)}
	result.labelTransform = _rows(target)
	return result

func _independent_plate(label: Label3D, anchor: Dictionary) -> void:
	if label.get_node_or_null("WorkbenchIndependentSign") != null:
		push_error("WORKBENCH: independent signage child already exists")
		return
	var plane := QuadMesh.new()
	plane.size = Vector2(float(anchor.planeSize[0]), float(anchor.planeSize[1]))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(str(anchor.presentation.color))
	material.no_depth_test = false
	var plate := MeshInstance3D.new()
	plate.name = "WorkbenchIndependentSign"
	plate.mesh = plane
	plate.material_override = material
	plate.position.z = -float(anchor.clearance) * 0.4
	plate.set_meta("workbench_independent_signage", {"labelId": anchor.labelId, "instanceId": anchor.instanceId, "bindingSha256": anchor.sha256, "geometryHash": anchor.geometryHash, "modelSha256": anchor.modelSha256, "planeSize": anchor.planeSize, "depthTest": true, "newGameplayInstance": false, "nativeSceneVerified": false})
	# Exact Label3D parent retains its existing motion, hide and depth relationship.
	label.add_child(plate)

func _rendering(label: Label3D) -> Dictionary:
	return {"noDepthTest": label.no_depth_test, "outlineSize": label.outline_size, "shaded": label.shaded, "doubleSided": label.double_sided, "alphaCut": label.alpha_cut}

func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _transform(value: Array) -> Transform3D:
	return Transform3D(Basis(_v(value[0]), _v(value[1]), _v(value[2])), _v(value[3]))

func _same_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.basis.x.distance_to(b.basis.x) < 0.00004 and a.basis.y.distance_to(b.basis.y) < 0.00004 and a.basis.z.distance_to(b.basis.z) < 0.00004 and a.origin.distance_to(b.origin) < 0.00004

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _rows(value: Transform3D) -> Array:
	return [_vec(value.basis.x), _vec(value.basis.y), _vec(value.basis.z), _vec(value.origin)]
