extends "res://themes/halloween_07/presentation.gd"
## Independent regional buffers. No sample build or host flush is called here.
var host: RefCounted
var region: Dictionary
var region_id := ""
var scene_id := ""
var shared: Dictionary
var metrics: Dictionary = {}
var _finished := false

func configure(owner: RefCounted, definition: Dictionary, common: Dictionary) -> void:
	host = owner; region = definition; shared = common
	region_id = str(region.id); scene_id = str(region.catalog_scene_ids[0])
	app = host.app; route = host.route; models = host.models; mats = host.mats
	shape_cache = host.shape_cache
	world = Node3D.new(); world.name = "H07" + region_id
	world.set_meta("scene_id", scene_id); world.set_meta("asset_id", "h07_continuous_architecture")
	world.set_meta("instance_id", "h07_continuous_" + region_id)
	host.world.add_child(world)
	metrics = {"region": region_id, "emitted_parts": 0, "rejected_envelopes": 0, "models": 0, "tracks": region.tracks.duplicate(), "new_track_beds": [], "hard_obstacles": [], "warning_boards": []}

func track_pose(track_id: String, s: float, side: float = 0.0) -> Transform3D:
	return route.tracks[track_id].pose(clampf(s, 0.0, route.tracks[track_id].length), side)

func upright_pose(track_id: String, s: float, side: float = 0.0) -> Transform3D:
	var p := track_pose(track_id, s)
	var forward := -p.basis.z; forward.y = 0.0
	if forward.length_squared() < 0.00001:
		forward = Vector3(p.basis.x.z, 0.0, -p.basis.x.x)
	if forward.length_squared() < 0.00001: forward = Vector3.FORWARD
	var basis := Basis.looking_at(forward.normalized(), Vector3.UP)
	return Transform3D(basis, p.origin+basis.x*side)

func ground_y(point: Vector3) -> float:
	return shared.field.height_at(point)

func ground_pose(track_id: String, s: float, side: float = 0.0) -> Transform3D:
	var p := upright_pose(track_id, s, side); p.origin.y = ground_y(p.origin)
	return p

func claim(ident: String) -> bool:
	if shared.claims.has(ident): return false
	shared.claims[ident] = region_id
	return true

func can_place(p: Transform3D, size: Vector3, margin: float = 4.0) -> bool:
	# p is the box CENTRE. Each wall/arch component is checked separately.
	var accepted: bool = shared.field.can_place_obb(p,size,margin)
	if not accepted: metrics.rejected_envelopes += 1
	return accepted

func add_light(point: Vector3, energy: float = 30.0, range_m: float = 30.0) -> void:
	light_candidates.append({"p": point, "energy": energy, "range": range_m})

func place_model(asset_id: String, p: Transform3D, envelope: Vector3, yaw: float, ident: String, distance: float = 900.0) -> Node3D:
	if not claim(ident): return null
	var node: Node3D = models.place(asset_id, world, p, envelope, yaw, ident, distance)
	if node == null: return null
	_stamp(node, asset_id, ident)
	for child in node.find_children("*", "Node3D", true, false): _stamp(child, asset_id, ident + "_" + str(node.get_path_to(child)))
	# Fit records share canonical sources, while their region must match actual placement.
	if not models.fits.is_empty(): models.fits[-1]["scene_id"] = scene_id; models.fits[-1]["region_id"] = region_id
	metrics.models += 1
	return node

func use_scene(value: String) -> void:
	assert(value in ["station", "canyon", "vertical", "coaster", "tunnel", "valley", "finale"])
	scene_id = value

func _stamp(node: Node, asset: String, ident: String) -> void:
	node.set_meta("scene_id", scene_id); node.set_meta("asset_id", asset); node.set_meta("instance_id", ident)

func _box(p: Transform3D, size: Vector3, key: String) -> void:
	var token := scene_id + "|" + key
	if not batches.has(token): batches[token] = []
	batches[token].append(p.scaled_local(size)); count += 1
	if key not in ["window", "warm", "cyan"]:
		record.append({"kind": "box", "material": key, "scene_id": scene_id, "region_id": region_id, "center": [p.origin.x, p.origin.y, p.origin.z], "size": [size.x, size.y, size.z]})

func _inst(mesh: Mesh, p: Transform3D, key: String, tag: String) -> void:
	var token := scene_id + "|" + tag + "_" + key
	if not custom_batches.has(token): custom_batches[token] = {"mesh": mesh, "poses": [], "material": key, "scene": scene_id}
	custom_batches[token].poses.append(p); count += 1

func _flush() -> void:
	var previous := scene_id
	for token: String in batches:
		var split := token.split("|", true, 1); scene_id = split[0]
		var mesh := BoxMesh.new(); mesh.size = Vector3.ONE
		_make_batch(mesh, batches[token], split[1], "H07_" + split[1])
	for token: String in custom_batches:
		var row: Dictionary = custom_batches[token]; scene_id = row.scene
		_make_batch(row.mesh, row.poses, row.material, token.get_slice("|", 1))
	scene_id = previous

func _mesh(mesh: Mesh, p: Transform3D, key: String, ident: String) -> void:
	var node := MeshInstance3D.new(); node.mesh = mesh; node.transform = p; node.material_override = mats[key]
	node.name = ident + "_" + str(count)
	_stamp(node, "h07_authored_" + key, "h07_" + region_id + "_" + node.name)
	world.add_child(node); count += 1

func _make_batch(mesh: Mesh, poses: Array, key: String, ident: String) -> void:
	var chunks: Dictionary = {}
	for pose: Transform3D in poses:
		var cell := Vector3i(floori(pose.origin.x / 128.0), floori(pose.origin.y / 96.0), floori(pose.origin.z / 128.0))
		var token := str(cell)
		if not chunks.has(token): chunks[token] = {"origin": Vector3(cell) * Vector3(128, 96, 128), "poses": []}
		chunks[token].poses.append(pose)
	for token: String in chunks:
		var chunk: Dictionary = chunks[token]; var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = mesh; mm.instance_count = chunk.poses.size()
		for i in mm.instance_count:
			var pose: Transform3D = chunk.poses[i]; pose.origin -= chunk.origin; mm.set_instance_transform(i, pose)
		var node := MultiMeshInstance3D.new(); node.multimesh = mm; node.position = chunk.origin
		# Dummy headless RenderingServer cannot reliably read MultiMesh buffers.
		# Retain the exact emitted source transforms for source/mesh audits only.
		if DisplayServer.get_name()=="headless":node.set_meta("h07_audit_source_poses",chunk.poses)
		node.name = scene_id + "_" + ident + "_" + token
		_stamp(node, "h07_authored_" + (key if not key.is_empty() else "masonry_wedges"), "h07_" + region_id + "_" + node.name)
		if not key.is_empty(): node.material_override = mats[key]
		world.add_child(node)

func finish() -> Dictionary:
	assert(not _finished, "A regional context must flush exactly once")
	_finished = true; _flush()
	host.count += count; host.record.append_array(record); host.light_candidates.append_array(light_candidates)
	host.city_anchors.append_array(city_anchors); host.wedge_merge_checks.append_array(wedge_merge_checks)
	metrics.emitted_parts = count; metrics.light_candidates = light_candidates.size()
	world.set_meta("h07_region_report", metrics)
	return metrics
