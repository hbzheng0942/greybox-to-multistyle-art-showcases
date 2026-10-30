extends RefCounted
## Lux visuals follow frozen owners/poses. No physics, route or interaction changes.
var host: RefCounted
var session: Node3D
var world: Node3D
var config: Dictionary
var proxy: RefCounted
var track_spaces: Dictionary = {}
var counts: Dictionary = {}

func build(app: Node3D, target: Node3D, loader: RefCounted, settings: Dictionary) -> void:
	session = app
	world = target
	host = loader
	config = settings
	proxy = host.ProxyWorld.new()
	proxy.session = session
	proxy.route = session.lab.get_node("RouteRoot/MainRoute")
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(host.CASE + "styles/" + host.sid + "/design/2026-10-20-full-route/spatial-design.json"))
	for space: Dictionary in design.space_designs:
		for track: String in space.track_ids: track_spaces[track] = space.space_id
	_markers()
	_soft_props()
	_hard_blockers()
	_ceiling_fixtures()
	world.set_meta("lux_functional_report", {"counts":counts, "spaces":config.spaces,
		"source_pose_policy":"Frozen native MultiMesh transforms and original soft-prop owners",
		"collision_changes":0, "acceptance":"Pending native visual, route and soft-hit/reset review"})

func _in_scope(track: String) -> bool:
	return track_spaces.get(track, "") in config.spaces

func _asset(role: String) -> String:
	return str(config.get("roles", {}).get(role, ""))

func _template(ident: String) -> Node3D:
	return host.sample_templates.get(ident + ":near")

func _mesh_entry(node: Node, at: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	if node is Node3D: at *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		return {"mesh":node.mesh, "material":node.get_active_material(0), "transform":at}
	for child: Node in node.get_children():
		var found := _mesh_entry(child, at)
		if not found.is_empty(): return found
	return {}

func _record(ident: String, asset: String, pose: Transform3D, mesh: Mesh, space: String, category: String) -> void:
	var box := pose * mesh.get_aabb()
	host.added_bounds.append({"id":ident, "style_id":host.sid, "space_id":space,
		"category":category, "center_m":host.array(box.get_center()), "size_m":host.array(box.size),
		"basis_columns":[[1,0,0],[0,1,0],[0,0,1]], "protected_route":category == "functional",
		"bounds_kind":"conservative_mesh_aabb", "source_asset_id":asset,
		"source_sha256":host.sample_specs[asset].source.sha256,
		"mesh_local_aabb":host.box_record(mesh.get_aabb()), "mesh_to_world":host.transform_array(pose)})

func _batch(ident: String, asset: String, poses: Array[Transform3D], space: String, category: String) -> void:
	var model := _template(asset)
	if model == null or poses.is_empty(): return
	var entry := _mesh_entry(model)
	# Bounded batches avoid one course-sized culling box for hundreds of lamps.
	for first in range(0, poses.size(), 24):
		var amount := mini(24, poses.size() - first)
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = entry.mesh
		batch.instance_count = amount
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = entry.material
		instance.visibility_range_end = 360.0
		world.add_child(instance)
		host._tag_tree(instance, ident + ":batch:" + str(first), asset, "station" if space == "N01" else "valley")
		for i in amount:
			var pose: Transform3D = poses[first + i] * entry.transform
			batch.set_instance_transform(i, pose)
			_record(ident + ":" + str(first + i), asset, pose, entry.mesh, space, category)
	counts[asset] = int(counts.get(asset, 0)) + poses.size()

func _markers() -> void:
	var serial := 0
	var repairs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(host.CASE + "styles/" + host.sid + "/runtime/marker-offsets.json"))
	for source: MultiMeshInstance3D in session.lab.get_node("PresentationRoot").find_children("*", "MultiMeshInstance3D", true, false):
		var semantic: String = proxy._semantic_name(source)
		var source_id := semantic + ":%04d" % serial
		serial += 1
		var tall := semantic.begins_with("NearSpeedMarkers")
		if not tall and not semantic.begins_with("Pickets"): continue
		var track := str(source.get_parent().name).rsplit("_", true, 1)[0]
		if not _in_scope(track): continue
		var asset := _asset("speed_lamp" if tall else "guide_bollard")
		if _template(asset) == null: continue
		var poses: Array[Transform3D] = []
		for i in source.multimesh.instance_count:
			var frozen := source.global_transform * source.multimesh.get_instance_transform(i)
			var height := frozen.basis.get_scale().y
			var pose := Transform3D(frozen.basis.orthonormalized(), frozen.origin)
			var group: String = host.sid + ":marker:" + source_id + ":" + str(i)
			# S6 already moved the original tall pole. Picket source stayed untouched.
			if not tall: pose.origin += host.vector(repairs.get("offsets", {}).get(group, [0,0,0]))
			pose = pose.translated_local(Vector3(0,-height * 0.5,0)).rotated_local(Vector3.UP, PI)
			var target_height := height if tall else 0.84 * float(repairs.get("scale_multipliers", {}).get(group, 1.0))
			poses.append(pose.scaled_local(Vector3.ONE * target_height))
			host.replaced_ids.append(group)
			if tall: host.replaced_ids.append(host.sid + ":moved-pole:" + source_id + ":" + str(i))
		_batch(host.sid + ":lux-marker:" + source_id, asset, poses, track_spaces[track], "support")
		for old: Node3D in world.get_children():
			if str(old.get_meta("instance_id", "")).begins_with(host.sid + ":marker-batch:" + source_id + ":"):
				old.visible = false
		source.visible = false

func _soft_props() -> void:
	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent.albedo_color = Color(0,0,0,0)
	for track in proxy.route.tracks.values():
		if not _in_scope(track.id): continue
		for obstacle: Dictionary in track.obstacles:
			if obstacle.get("kind", "block") != "soft": continue
			var key: String = proxy.route.obstacle_key(track, obstacle)
			var asset := _asset("soft_cone" if str(obstacle.get("group", "")).contains("cone") else "soft_bin")
			var template := _template(asset)
			if template == null: continue
			var dims: Vector3 = host.vector(host.sample_specs[asset].result_size_m)
			for original: MeshInstance3D in session.lab.soft_props.get(key, []):
				var envelope := original.mesh.get_aabb()
				var scalar := minf(envelope.size.x / dims.x, minf(envelope.size.y / dims.y, envelope.size.z / dims.z)) * 0.99
				var model := template.duplicate() as Node3D
				var mount := Node3D.new()
				for old: Node3D in original.get_children(): old.visible = false
				original.add_child(mount)
				mount.position = Vector3(0,envelope.position.y,0)
				mount.scale = Vector3.ONE * scalar
				mount.add_child(model)
				original.material_override = transparent
				original.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var ident: String = host.sid + ":lux-soft:" + key + ":" + str(original.get_index())
				host._tag_tree(mount, ident, asset, "station" if track_spaces[track.id] == "N01" else "valley")
				var entry := _mesh_entry(model)
				_record(ident, asset, mount.global_transform * entry.transform, entry.mesh, track_spaces[track.id], "functional")
				counts[asset] = int(counts.get(asset,0)) + 1
				counts["soft_owners_preserved"] = int(counts.get("soft_owners_preserved",0)) + 1

func _solid(parent: Node3D, ident: String, size: Vector3, center: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = 0.45
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = center
	host._tag_tree(mesh,ident,"local_locked_cage_frame","station")

func _hard_blockers() -> void:
	var asset := _asset("hard_lockbox")
	var template := _template(asset)
	if template == null: return
	var records: Array = []
	for track in proxy.route.tracks.values():
		for obstacle: Dictionary in track.obstacles:
			if obstacle.get("kind", "block") == "soft": continue
			for lane: int in obstacle.lanes:
				records.append({"track":track.id,"kind":obstacle.get("kind","block"),"lane":lane,"s":obstacle.s})
	var cursor := 0
	var serial := 0
	for source: MultiMeshInstance3D in session.lab.get_node("PresentationRoot").find_children("*", "MultiMeshInstance3D", true, false):
		var semantic: String = proxy._semantic_name(source)
		var source_id := semantic + ":%04d" % serial
		serial += 1
		if not semantic.begins_with("Block") and not semantic.begins_with("LowBeam"): continue
		for i in source.multimesh.instance_count:
			if cursor >= records.size():
				host.errors.append("Unexpected frozen hard-obstacle source count")
				return
			var record: Dictionary = records[cursor]
			cursor += 1
			if not _in_scope(record.track) or record.kind != "block": continue
			var frozen := source.global_transform * source.multimesh.get_instance_transform(i)
			var size := frozen.basis.get_scale()
			var track = proxy.route.tracks[record.track]
			var expected: Vector3 = (session.lab.get_node("PresentationRoot").global_transform * track.pose(record.s,record.lane * 4.4).translated_local(Vector3(0,size.y * 0.5,0))).origin
			if frozen.origin.distance_to(expected) > 0.01:
				host.errors.append("Frozen hard-obstacle order/pose mismatch")
				continue
			var old_id: String = host.sid + ":hazard:" + source_id + ":" + str(i)
			var found: Array[Node3D] = []
			host._find_instance(world,old_id,found)
			if found.size()!=1:
				host.errors.append("Missing exact hard-obstacle proxy: " + old_id)
				continue
			var mount := Node3D.new()
			world.add_child(mount)
			mount.global_transform = Transform3D(frozen.basis.orthonormalized(),frozen.origin).translated_local(Vector3(0,-size.y*0.5,0))
			var height := (size.y - 0.5) * 0.5
			var dimensions: Vector3 = host.vector(host.sample_specs[asset].result_size_m) * height
			if dimensions.x * 2.0 + 0.1 > size.x - 0.2 or dimensions.z > size.z - 0.2:
				host.errors.append("Uniform lockbox pair exceeds frozen hard envelope")
				mount.free()
				continue
			var ident: String = host.sid + ":lux-hard:" + source_id + ":" + str(i)
			for level in 2:
				for side: int in [-1,1]:
					var position := Vector3(side * (dimensions.x + 0.1) * 0.5,0.25 + level * (height + 0.1),0)
					var part := Node3D.new()
					mount.add_child(part)
					part.position = position
					part.scale = Vector3.ONE * height
					part.add_child(template.duplicate())
			var steel := Color("44494a")
			_solid(mount,ident+":base",Vector3(size.x,0.25,size.z),Vector3(0,0.125,0),steel)
			_solid(mount,ident+":shelf",Vector3(size.x,0.1,size.z),Vector3(0,0.3+height,0),steel)
			_solid(mount,ident+":top",Vector3(size.x,0.15,size.z),Vector3(0,size.y-0.075,0),steel)
			for x: int in [-1,1]:
				for z: int in [-1,1]:
					_solid(mount,ident+":post",Vector3(0.18,size.y,0.18),Vector3(x*(size.x-0.18)*0.5,size.y*0.5,z*(size.z-0.18)*0.5),steel)
			_solid(mount,ident+":danger-band",Vector3(size.x,0.18,0.025),Vector3(0,size.y-0.25,(size.z-0.025)*0.5),Color("b03927"))
			host._tag_tree(mount,ident,asset,"station" if track_spaces[record.track]=="N01" else "valley")
			var measured: Dictionary = host.measure(mount,mount.global_transform.affine_inverse())
			# Explicit visible outer frame reaches the exact pre-existing collision envelope.
			if not AABB(Vector3(-size.x*0.5,0,-size.z*0.5),size).grow(0.015).encloses(measured.bounds):
				host.errors.append("Hard assembly exceeds original local envelope")
				mount.free()
				continue
			for row: Dictionary in host.measure(mount,world.global_transform).meshes:
				var b: Dictionary = row.bounds
				host.added_bounds.append({"id":ident+":"+str(row.path),"style_id":host.sid,"space_id":track_spaces[record.track],
					"category":"functional","center_m":host.array(host.vector(b.position_m)+host.vector(b.size_m)*0.5),"size_m":b.size_m,
					"basis_columns":[[1,0,0],[0,1,0],[0,0,1]],"protected_route":true,"bounds_kind":"conservative_mesh_aabb",
					"mesh_local_aabb":row.local_aabb,"mesh_to_world":row.transform,"source_asset_id":asset})
			found[0].visible=false
			host.replaced_ids.append(old_id)
			counts["hard_cages"] = int(counts.get("hard_cages",0)) + 1
	if cursor != records.size(): host.errors.append("Incomplete frozen hard-obstacle enumeration")

func _ceiling_fixtures() -> void:
	var asset := _asset("ceiling_lamp")
	if _template(asset) == null: return
	var dims: Vector3 = host.vector(host.sample_specs[asset].result_size_m)
	var poses: Array[Transform3D] = []
	for track_id: String in ["station_start", "station_carve"]:
		if not _in_scope(track_id): continue
		var track = proxy.route.tracks[track_id]
		for i in range(ceili(track.length / 105.0)):
			var pose: Transform3D = proxy.route.track_pose(track_id, minf(track.length - 5.0,25.0 + i * 105.0),0)
			var scalar := 8.0 / dims.x
			# Preserve world-up hanging fixtures; roof underside is route height +36.4m.
			var yaw := atan2(pose.basis.z.x,pose.basis.z.z)
			poses.append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE * scalar),pose.origin + Vector3.UP * (36.4 - dims.y * scalar)))
	_batch(host.sid + ":lux-ceiling",asset,poses,"N01","support")
