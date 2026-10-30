extends RefCounted
## Shared gameplay owns physics. Each entry exposes only a local VisualRoot for art.
## The initial adapter accepts static, script-free geometry; rig/animation integration
## is a separate task, not implied by the existence of a model replacement API.

var entries: Dictionary = {}
var errors: Array[String] = []

func bind_game(game) -> void:
	entries.clear()
	errors.clear()
	for prop in game.props:
		var id: String = str(prop.get_meta("semantic_id", ""))
		if bool(prop.get_meta("is_bone", false)) and id.is_empty():
			id = "hall/skeleton/" + str(prop.get_meta("bone_id"))
		elif id.is_empty():
			id = "exhibit/" + str(prop.name)
		_bind_body(prop, id, "skeleton_segment" if bool(prop.get_meta("is_bone", false)) else "interactable_prop")
	_bind_body(game.dog, "player/dog", "player")
	for visitor in game.visitors:
		var parts: Array = visitor["parts"]
		for i in range(parts.size()):
			var body: Node3D = parts[i]
			var part_name: String = ["legs", "torso", "head"][i]
			_bind_body(body, "visitor/%s/%s" % [visitor["name"], part_name], "visitor_" + part_name)
	_bind_structure(game.builder)

func _bind_body(body: Node3D, id: String, role: String) -> void:
	var meshes: Array[MeshInstance3D] = []
	var collisions: Array[Node3D] = []
	for child in body.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		elif child is CollisionShape3D:
			collisions.append(child)
	if meshes.is_empty():
		errors.append("No direct visual meshes for " + id)
		return
	var visual := Node3D.new()
	visual.name = "VisualRoot"
	body.add_child(visual)
	_register(id, role, body, visual, meshes, collisions)

func _bind_structure(node: Node) -> void:
	# Take a snapshot because registering a mesh reparents it under a visual root.
	for child in node.get_children():
		if child.is_in_group("art_visual_targets"):
			continue
		if child is MeshInstance3D:
			var id := str(child.get_meta("semantic_id", ""))
			if id.is_empty():
				errors.append("Unbound structural mesh: " + str(child.get_path()))
				continue
			var pivot := Node3D.new()
			pivot.name = "VisualRoot_" + id.sha256_text().substr(0, 12)
			pivot.transform = child.transform
			node.add_child(pivot)
			var collisions: Array[Node3D] = []
			for sibling in node.get_children():
				if sibling is StaticBody3D and str(sibling.get_meta("semantic_id", "")) == id:
					for shape in sibling.get_children():
						if shape is CollisionShape3D:
							collisions.append(shape)
			_register(id, str(child.get_meta("semantic_role", "fixture")), pivot, pivot, [child], collisions)
		else:
			_bind_structure(child)

func _register(id: String, role: String, owner: Node3D, visual: Node3D,
		meshes: Array[MeshInstance3D], collisions: Array[Node3D]) -> void:
	if entries.has(id):
		errors.append("Duplicate visual semantic ID: " + id)
		visual.queue_free()
		return
	visual.add_to_group("art_visual_targets")
	visual.set_meta("semantic_id", id)
	visual.set_meta("semantic_role", role)
	owner.set_meta("semantic_id", id)
	owner.set_meta("semantic_role", role)
	if not owner.has_meta("region_id"):
		owner.set_meta("region_id", meshes[0].get_meta("region_id", "dynamic"))
	var greybox := Node3D.new()
	greybox.name = "Greybox"
	visual.add_child(greybox)
	for mesh in meshes:
		mesh.reparent(greybox, true)
	entries[id] = {"owner": owner, "visual": visual, "greybox": greybox,
		"collisions": collisions, "role": role, "artwork": null}

func replace_visual(id: String, scene: PackedScene, local_transform: Transform3D = Transform3D.IDENTITY) -> bool:
	if not entries.has(id) or scene == null:
		return false
	if not _is_static_scene_state(scene.get_state()):
		return false
	var artwork := scene.instantiate()
	if not artwork is Node3D or not _is_static_visual_tree(artwork):
		artwork.free()
		return false
	# Only local visual scale/pivot can change; gameplay/collider parents are untouched.
	clear_visual(id)
	var entry: Dictionary = entries[id]
	artwork.name = "Artwork"
	(entry["visual"] as Node3D).add_child(artwork)
	(artwork as Node3D).transform = local_transform
	(entry["greybox"] as Node3D).visible = false
	entry["artwork"] = artwork
	return true

func clear_visual(id: String) -> void:
	if not entries.has(id):
		return
	var entry: Dictionary = entries[id]
	var artwork: Node = entry["artwork"]
	if is_instance_valid(artwork):
		artwork.get_parent().remove_child(artwork)
		artwork.queue_free()
	entry["artwork"] = null
	(entry["greybox"] as Node3D).visible = true

func _is_static_scene_state(state: SceneState) -> bool:
	# This is an adapter compatibility check for trusted project assets, not a
	# sandbox. Inspect node scripts before instantiation so rejected _init cannot run.
	var base := state.get_base_scene_state()
	if base != null and not _is_static_scene_state(base):
		return false
	for i in range(state.get_node_count()):
		var nested := state.get_node_instance(i)
		if nested != null and not _is_static_scene_state(nested.get_state()):
			return false
		var type_name := str(state.get_node_type(i))
		if not type_name.is_empty() and type_name not in ["Node3D", "MeshInstance3D", "Skeleton3D", "BoneAttachment3D"]:
			return false
		for j in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, j) == &"script" and state.get_node_property_value(i, j) != null:
				return false
	return true

func _is_static_visual_tree(node: Node) -> bool:
	# Deliberately narrow: embedded colliders, scripts, cameras, lights or animation
	# controllers cannot silently alter the shared playable scene through a skin.
	if node.get_script() != null:
		return false
	if node.get_class() not in ["Node3D", "MeshInstance3D", "Skeleton3D", "BoneAttachment3D"]:
		return false
	for child in node.get_children():
		if not _is_static_visual_tree(child):
			return false
	return true

func export_contract() -> Dictionary:
	var bindings: Array = []
	var keys: Array = entries.keys()
	keys.sort()
	for id in keys:
		var entry: Dictionary = entries[id]
		var owner: Node3D = entry["owner"]
		var visual: Node3D = entry["visual"]
		var collision_data: Array = []
		for collider in entry["collisions"]:
			var body: CollisionObject3D = collider.get_parent()
			collision_data.append({"path": str(collider.get_path()), "shape": collider.shape.get_class(),
				"world_aabb": _aabb_data(_world_aabb(collider, collider.shape.get_debug_mesh().get_aabb())),
				"layer": body.collision_layer, "mask": body.collision_mask})
		var item := {"id": id, "role": entry["role"], "native_owner": str(owner.get_path()),
			"region": str(owner.get_meta("region_id", "dynamic")),
			"visual_target": str(visual.get_path()), "world_transform": _transform_data(visual.global_transform),
			"greybox_world_aabb": _aabb_data(_visual_bounds(entry["greybox"])),
			"colliders": collision_data, "replaceable": "static visual children only"}
		if owner is RigidBody3D:
			item["mass"] = owner.mass
			item["kind"] = str(owner.get_meta("kind", ""))
			item["value"] = int(owner.get_meta("value", 0))
			if owner.has_meta("supports"):
				item["supported_by_bone_ids"] = owner.get_meta("supports")
		if id == "player/dog":
			item["interaction_anchor"] = str(owner.get_node("Mouth").get_path())
			item["mouth_local_position"] = _vec(owner.get_node("Mouth").position)
		bindings.append(item)
	return {"schema": 1, "kind": "museum-dog-native-visual-contract", "bindings": bindings,
		"binding_errors": errors.duplicate(), "restrictions": ["Keep colliders, gameplay transforms, masses and joints shared", "Static script-free visual scenes only; rig/animation integration not yet validated"]}

func _visual_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var initialized := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		var current := _world_aabb(mesh, mesh.get_aabb())
		bounds = bounds.merge(current) if initialized else current
		initialized = true
	return bounds

func _world_aabb(node: Node3D, local: AABB) -> AABB:
	var bounds := AABB(node.global_transform * local.position, Vector3.ZERO)
	for i in range(8):
		bounds = bounds.expand(node.global_transform * local.get_endpoint(i))
	return bounds

func _transform_data(value: Transform3D) -> Dictionary:
	return {"position": _vec(value.origin), "basis_x": _vec(value.basis.x),
		"basis_y": _vec(value.basis.y), "basis_z": _vec(value.basis.z)}

func _aabb_data(value: AABB) -> Dictionary:
	return {"min": _vec(value.position), "size": _vec(value.size)}

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
