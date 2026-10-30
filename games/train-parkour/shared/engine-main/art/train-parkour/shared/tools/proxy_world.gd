extends RefCounted
## S6: reversible native massing. The frozen route remains the spatial authority.
const CASE := "res://../art/train-parkour/"
const WEATHER = preload("res://../art/train-parkour/shared/tools/proxy_weather.gdshader")
var sid := ""
var cartoon := false
var root: Node3D
var session: Node3D
var route: Node
var design: Dictionary
var kit_manifest: Dictionary
var modules: Dictionary = {}
var materials: Dictionary = {}
var track_spaces: Dictionary = {}
var track_scenes: Dictionary = {}
var bounds_items: Array = []
var placements: Array = []
var rejected: Array = []
var counters: Dictionary = {}
var kit_source: Node3D
var protected_points: Dictionary = {}
var functional_counts := {"hard_obstacle_instances": 0, "warning_plate_instances": 0, "marker_instances": 0}
var region_floor_y: Dictionary = {}
var marker_repairs: Dictionary = {}
var moved_pole_count := 0
var construction_errors: Array = []

func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func arr(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

func tag(node: Node, ident: String, asset: String, scene: String) -> void:
	node.set_meta("instance_id", ident)
	node.set_meta("asset_id", asset)
	node.set_meta("scene_id", scene)

func build_style(app: Node3D, style_id: String) -> Node3D:
	sid = style_id
	cartoon = sid == "odd-logistics"
	session = app
	route = session.lab.get_node("RouteRoot/MainRoute")
	root = Node3D.new()
	root.name = "OddLogisticsProxy" if cartoon else "RainEatenCityProxy"
	tag(root, sid + ":world", "S6_proxy_world", "station")
	session.add_child(root)
	design = read_json(CASE + "styles/" + sid + "/design/2026-10-20-full-route/spatial-design.json")
	marker_repairs = read_json(CASE + "styles/" + sid + "/runtime/marker-offsets.json")
	for space: Dictionary in design.space_designs:
		var floor_y := float(space.baseline_facts.track_world_bounds_m.min[1]) - 26.5
		if not cartoon:
			if space.space_id == "N01": floor_y = 73.0
			elif space.space_id == "N02": floor_y = 40.0
			elif space.space_id in ["N07", "N08"]: floor_y = -21.846336364746094
			elif space.space_id == "N09": floor_y = -34.785579681396484
		region_floor_y[space.space_id] = floor_y
		for track_id: String in space.track_ids:
			track_spaces[track_id] = space.space_id
			track_scenes[track_id] = design.baseline_facts.tracks[track_id].runtime_scene_id
	for track_id: String in route.tracks:
		var track = route.tracks[track_id]
		var points: Array = []
		for i in range(ceili(track.length / 6.0) + 1):
			points.append(route.track_pose(track_id, minf(i * 6.0, track.length), 0).origin)
		protected_points[track_id] = points
	_build_materials()
	_load_kit()
	_restyle_existing()
	_train()
	_environment()
	if not modules.is_empty():
		_functional_kit()
		_full_route()
		_landmark()
	_basins_and_floors()
	if kit_source != null:
		kit_source.free()
	if modules.size() != 6: construction_errors.append("Six-module DCC kit required")
	root.set_meta("construction_report", {"errors": construction_errors,
		"stage": "S6_ART_PROXY", "style_id": sid, "module_count": modules.size(),
		"placements": placements.size(), "candidate_rejections": rejected.size(),
		"covered_spaces": counters, "new_collision_nodes": 0,
		"functional_counts": functional_counts,
		"marker_repair_count": marker_repairs.get("offsets", {}).size(),
		"moved_original_poles": moved_pole_count,
		"warning_source_poses_verified": DisplayServer.get_name() != "headless",
		"lux_jobs": 0, "fidelity_acceptance": "not assessed; proxy is spatial evidence"})
	root.set_meta("proxy_geometry", {"schema_version": 1, "units": "metres", "up": "+Y",
		"style_id": sid, "items": bounds_items, "placements": placements, "rejected": rejected,
		"scope": "New environmental solids. Functional replacements stay within frozen visual envelopes; no collision edits."})
	return root

func _material(key: String, color: String, metal := 0.0, rough := 0.8, emission := false) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.metallic = metal
	m.roughness = rough
	if emission:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = 0.7
	materials[key] = m

func _build_materials() -> void:
	_material("bed", "5e655e" if cartoon else "424e53", 0.18, 0.55)
	_material("steel", "474d48" if cartoon else "6c777a", 0.75, 0.30)
	_material("tie", "777761" if cartoon else "53524c", 0.1, 0.8)
	_material("gold", "d9b34b" if cartoon else "bba474", 0.35, 0.6)
	_material("active_gold", "ffc15b", 0.25, 0.4, true)
	_material("red", "9b4639" if cartoon else "863b34", 0.1, 0.65)
	_material("dark", "282c27" if cartoon else "202b30", 0.25, 0.5)
	_material("white", "c1c2a6" if cartoon else "c6cbc5", 0.15, 0.55)
	_material("cyan", "72d7ce", 0.1, 0.35, true)
	_material("purple", "b18ac4", 0.1, 0.65, true)
	_material("rescue_deck", "6a5279", 0.18, 0.6)
	_material("ground", "565747" if cartoon else "3d494b", 0.1, 0.85)
	_material("water", "344f5b", 0.65, 0.18)
	_material("glass", "202d2d" if cartoon else "213d48", 0.7, 0.2)

func _load_kit() -> void:
	var directory := CASE + "styles/" + sid + "/dcc/proxy-v1/"
	kit_manifest = read_json(directory + "manifest.json")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var error := doc.append_from_file(ProjectSettings.globalize_path(directory + "proxy-kit.glb"), state)
	if error != OK:
		push_error("Cannot read proxy kit: " + str(error))
		return
	kit_source = doc.generate_scene(state)
	for module: Node in kit_source.get_children():
		modules[str(module.name)] = module
		for mesh: MeshInstance3D in module.find_children("*", "MeshInstance3D", true, false):
			for index in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(index) as StandardMaterial3D
				if source == null: continue
				var weather := ShaderMaterial.new()
				weather.shader = WEATHER
				weather.set_shader_parameter("base_color", source.albedo_color)
				weather.set_shader_parameter("metalness", source.metallic)
				weather.set_shader_parameter("rough", 0.85 if cartoon else 0.55)
				weather.set_shader_parameter("coarse", cartoon)
				weather.set_shader_parameter("emissive", source.emission_enabled)
				mesh.set_surface_override_material(index, weather)

func _restyle_existing() -> void:
	var hidden := ["NearMasses", "DistantPiers", "HubBeacon"]
	if not cartoon:
		hidden.append_array(["StationGround", "StationPlatforms", "ValleyFloor", "Riverbed", "FinalFloor"])
	for node: GeometryInstance3D in session.find_children("*", "GeometryInstance3D", true, false):
		var n := _semantic_name(node)
		for prefix: String in hidden:
			if n.begins_with(prefix): node.visible = false
		if node is MeshInstance3D and node.mesh is PlaneMesh and node.get_parent() == session.lab.get_node("EnvironmentRoot"):
			node.visible = false
		var key := ""
		if n.begins_with("Bed"): key = "bed"
		elif n.begins_with("Rail"): key = "steel"
		elif n.begins_with("Ties"): key = "tie"
		elif n.begins_with("Clamps") or n.begins_with("EdgeCurbs"): key = "gold" if cartoon else "steel"
		elif n.begins_with("ApproachMarks") or n.begins_with("Block") or n.begins_with("LowBeam") or n.begins_with("NoEntrySign"): key = "red"
		elif n.begins_with("NoEntryBar"): key = "white"
		elif n.begins_with("Release") or n.begins_with("Gold") or n.begins_with("InvertedEject"): key = "active_gold"
		elif n.begins_with("Catch") or n.begins_with("Pulse") or n.begins_with("TunnelLamps"): key = "cyan"
		elif n.begins_with("Pickets") or n.begins_with("NearSpeedMarkers"): key = "dark"
		elif n.begins_with("TrackPiers") or n.begins_with("Vertical") or n.begins_with("Contact"): key = "bed"
		elif n.begins_with("Coil") or n.begins_with("LoopRibs"): key = "gold"
		elif n.begins_with("Valley") or n.begins_with("Final") or n.begins_with("Station"): key = "ground"
		var track_id: String = str(node.get_parent().name).rsplit("_", true, 1)[0]
		if route.tracks.has(track_id):
			var track = route.tracks[track_id]
			if track.kind == "rescue":
				if n == "Bed": key = "rescue_deck"
				elif n in ["Rail", "Pickets", "EdgeCurbs"]: key = "purple"
			elif track.single_lane and n == "Rail":
				key = "active_gold"
		if not key.is_empty(): node.material_override = materials[key]

func _semantic_name(node: GeometryInstance3D) -> String:
	# Repeated root batches get engine-generated names. Identify their frozen
	# primitive dimensions and source material, never that unstable suffix.
	if node is MultiMeshInstance3D and node.get_parent() == session.lab.get_node("PresentationRoot"):
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh is BoxMesh:
			var source := mm.mesh.surface_get_material(0) as BaseMaterial3D
			var size: Vector3 = mm.mesh.size
			if source != null and (source.albedo_color.is_equal_approx(Color(1, .18, .11)) or source.albedo_color.is_equal_approx(Color(1, .22, .13))):
				if size.is_equal_approx(Vector3.ONE): return "Block"
				if size.is_equal_approx(Vector3(3.5, .08, 3.8)): return "ApproachMarks"
				if size.is_equal_approx(Vector3(2.6, 1.8, .2)): return "NoEntrySign"
	return str(node.name)

func _box(parent: Node3D, ident: String, size: Vector3, at: Transform3D, mat: String, category: String, space := "N01", scene := "station", record := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = ident.replace(":", "_")
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = materials[mat]
	parent.add_child(node)
	node.transform = at
	tag(node, ident, "local_" + mat, scene)
	node.visibility_range_end = 1600.0
	if record:
		_record_box(ident, category, space, node.global_transform, size)
	return node

func _record_box(ident: String, category: String, space: String, pose: Transform3D, size: Vector3) -> void:
	var normalized := pose.basis.orthonormalized()
	bounds_items.append({"id": ident, "style_id": sid, "space_id": space, "category": category,
		"center_m": arr(pose.origin), "size_m": arr(size * pose.basis.get_scale().abs()),
		"basis_columns": [arr(normalized.x), arr(normalized.y), arr(normalized.z)],
		"protected_route": category == "functional" or category == "route_surface"})

func _train() -> void:
	var geometry := session.get_node("Actors/Train/VisualRoot/TrickPivot/Geometry") as Node3D
	for child: Node3D in geometry.get_children():
		if child is GeometryInstance3D: child.visible = false
	var body := _box(geometry, sid + ":train:body", Vector3(2.4, 1.35 if not cartoon else 0.65, 9.8 if not cartoon else 7.4),
		Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)), "gold" if cartoon else "white", "functional", "N01", "station", false)
	body.set_meta("proxy_note", "Frozen Body remains hidden in place for camera bounds.")
	if not cartoon:
		_box(geometry, sid + ":train:cab", Vector3(2.15, 1.55, 4.8),
			Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 0.5)), "white", "functional", "N01", "station", false)
	else:
		_box(geometry, sid + ":train:roof", Vector3(2.15, 0.25, 3.2),
			Transform3D(Basis.IDENTITY, Vector3(0, 3.15, 0.5)), "gold", "functional", "N01", "station", false)
		_box(geometry, sid + ":train:seat", Vector3(1.1, 1.2, 0.65),
			Transform3D(Basis.IDENTITY, Vector3(0, 1.9, 0.9)), "dark", "functional", "N01", "station", false)
		for x in [-0.9, 0.9]:
			for z in [-0.9, 1.9]:
				_box(geometry, sid + ":train:cage:" + str(x) + ":" + str(z), Vector3(0.18, 1.8, 0.18),
					Transform3D(Basis.IDENTITY, Vector3(x, 2.2, z)), "gold", "functional", "N01", "station", false)
			_box(geometry, sid + ":train:fork:" + str(x), Vector3(0.28, 0.2, 2.2),
				Transform3D(Basis.IDENTITY, Vector3(x, 0.75, -4.7)), "steel", "functional", "N01", "station", false)
	for side in [-1, 1]:
		if not cartoon:
			_box(geometry, sid + ":train:window:" + str(side), Vector3(0.035, 0.85, 3.6),
				Transform3D(Basis.IDENTITY, Vector3(side * 1.086, 2.55, 0.4)), "glass", "functional", "N01", "station", false)
		_box(geometry, sid + ":train:lamp:" + str(side), Vector3(0.16, 0.6, 0.15),
			Transform3D(Basis.IDENTITY, Vector3(side * 0.9, 1.6, 4.96 if not cartoon else 4.26)), "red", "functional", "N01", "station", false)
		for z in [-3.4, 3.4]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.85 if cartoon else 0.55
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.height = 0.3
			cylinder.radial_segments = 8 if cartoon else 16
			wheel.mesh = cylinder
			wheel.material_override = materials.dark
			geometry.add_child(wheel)
			wheel.position = Vector3(side * 1.1, cylinder.top_radius, z)
			wheel.rotation.z = PI * 0.5
			tag(wheel, sid + ":wheel:" + str(side) + ":" + str(z), "proxy_wheel", "station")
	if not cartoon:
		_box(geometry, sid + ":train:rear-window", Vector3(1.65, 0.85, 0.04),
			Transform3D(Basis.IDENTITY, Vector3(0, 2.55, 2.93)), "glass", "functional", "N01", "station", false)
	# Original soft props own hit/reset transforms; their new visual follows that owner.
	for key in session.lab.soft_props:
		for prop: MeshInstance3D in session.lab.soft_props[key]:
			prop.material_override = materials.gold if cartoon else materials.red
			var size := prop.mesh.get_aabb().size
			_box(prop, sid + ":soft-band:" + str(key) + ":" + str(prop.get_index()), size * Vector3(1.005, 0.15, 1.005),
				Transform3D.IDENTITY, "white", "functional", "N01", "station", false)

func _environment() -> void:
	for node: WorldEnvironment in session.find_children("*", "WorldEnvironment", true, false):
		var env := node.environment.duplicate() as Environment
		node.environment = env
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color("3a4445" if cartoon else "697f90")
		sky_mat.sky_horizon_color = Color("938c6c" if cartoon else "c4c9c5")
		sky_mat.ground_bottom_color = Color("333c3b")
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("adb69d" if cartoon else "b0c8d5")
		env.ambient_light_energy = 0.65 if cartoon else 0.8
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.fog_enabled = true
		env.fog_light_color = Color("8a8b73" if cartoon else "a2b6c0")
		env.fog_density = 0.0012 if cartoon else 0.0008
		env.ssao_enabled = true
		env.ssao_radius = 2.0
		env.ssao_intensity = 1.5
		env.ssr_enabled = not cartoon
		env.glow_enabled = true
		env.glow_intensity = 0.25
	for sun: DirectionalLight3D in session.find_children("*", "DirectionalLight3D", true, false):
		sun.light_color = Color("e8dcad" if cartoon else "e9e7db")
		sun.light_energy = 1.2 if cartoon else 1.7
		sun.rotation_degrees = Vector3(-42, -35, 0)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 300.0

func _module_bounds(module: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in module.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func _put_module(module_name: String, ident: String, at: Transform3D, space: String, scene: String, category: String) -> Node3D:
	if not modules.has(module_name):
		push_error("Missing module " + module_name)
		return null
	var node := (modules[module_name] as Node3D).duplicate() as Node3D
	root.add_child(node)
	node.name = ident.replace(":", "_")
	node.transform = at
	tag(node, ident, module_name, scene)
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 1800.0
	for entry: Dictionary in kit_manifest.modules:
		if str(entry.id) != module_name: continue
		for part: Dictionary in entry.collision_proxy_boxes:
			_record_box(ident + ":" + str(part.proxy_id), category, space,
				at * Transform3D(Basis.IDENTITY, v(part.center)), v(part.size))
			bounds_items.back()["bounds_kind"] = "conservative_mesh_aabb"
	placements.append({"id": ident, "module": module_name, "space_id": space, "scene_id": scene,
		"origin_m": arr(at.origin), "basis_columns": [arr(at.basis.x), arr(at.basis.y), arr(at.basis.z)]})
	counters[space] = int(counters.get(space, 0)) + 1
	return node

func _safe_box(bounds: AABB, margin := 13.0) -> bool:
	for track_id: String in protected_points:
		var track = route.tracks[track_id]
		if not track.bounds.grow(margin + 10).intersects(bounds): continue
		for point: Vector3 in protected_points[track_id]:
			if bounds.grow(margin).has_point(point): return false
	return true

func _nearest_track(point: Vector3) -> String:
	var nearest := ""
	var distance := INF
	for track_id: String in protected_points:
		for candidate: Vector3 in protected_points[track_id]:
			var score := point.distance_squared_to(candidate)
			if score < distance:
				distance = score
				nearest = track_id
	return nearest

func _full_route() -> void:
	var sequence := 0
	for track_id: String in route.tracks:
		var track = route.tracks[track_id]
		var space: String = track_spaces[track_id]
		var scene: String = track_scenes[track_id]
		var count := maxi(1, ceili(track.length / 105.0))
		for i in count:
			var s := minf(track.length - 5.0, 25.0 + i * 105.0)
			var pose: Transform3D = route.track_pose(track_id, s, 0)
			var forward := -pose.basis.z
			forward.y = 0
			if forward.length_squared() < 0.01: forward = Vector3.FORWARD
			forward = forward.normalized()
			var side := forward.cross(Vector3.UP)
			var basis := Basis(side, Vector3.UP, -forward)
			for sign in [-1, 1]:
				for band in 2:
					var module_name := "rack_mass" if cartoon else "city_mass"
					if space in ["N03", "N04", "N05"] and i % 3 == 0:
						module_name = "sorter_frame" if cartoon else "pump_frame"
					var template: Node3D = modules[module_name]
					var bounds := _module_bounds(template)
					var scale_y := (0.8 + float((i * 7 + sequence) % 6) * 0.16) if cartoon else (1.2 + float((i * 7 + sequence) % 6) * 0.32)
					if band == 1: scale_y *= 1.65
					var scale := Vector3(1.1 if band == 0 else 1.5, scale_y, 1.5)
					var at: Vector3 = pose.origin + side * sign * (53.0 + band * 105.0)
					var floor_y: float = region_floor_y[space]
					at.y = floor_y + bounds.size.y * scale_y * 0.5
					var transform := Transform3D(basis.scaled_local(scale), at)
					var candidate := transform * bounds
					var ident := sid + ":" + space + ":" + track_id + ":mass:%03d:%d:%d" % [i, sign, band]
					if _safe_box(candidate, 17.0):
						_put_module(module_name, ident, transform, space, scene, "background_mass")
					else:
						rejected.append({"id": ident, "reason": "full-route centerline envelope; not spawned"})
			if cartoon and space in ["N01", "N06", "N08"]:
				var roof_at := Transform3D(basis, pose.origin + Vector3.UP * 37.0)
				var roof_size := Vector3(110, 1.2, 90)
				if _safe_box(roof_at * AABB(-roof_size * 0.5, roof_size), 17.0):
					_box(root, sid + ":" + track_id + ":roof:" + str(i), roof_size, roof_at, "dark", "roof", space, scene)
			sequence += 1

func _landmark() -> void:
	var lm: Dictionary = design.shared_landmarks[0]
	var at := Transform3D(Basis.IDENTITY, v(lm.design_proposal.tower_body_center_world_m))
	_put_module("tower", str(lm.id), at, "N07", "valley", "tower")
	# Side structures only: no downstand girder in the 19 m shared crossing.
	var anchor: Dictionary = lm.baseline_anchor.transform
	var forward := -v(anchor.basis[2])
	forward.y = 0
	forward = forward.normalized()
	var side := forward.cross(Vector3.UP)
	for sign in [-1, 1]:
		var frame := Transform3D(Basis(side, Vector3.UP, -forward), v(anchor.origin) + side * sign * 21.0 + Vector3.UP * 6.0)
		_put_module("side_truss", sid + ":shared-bridge:side:" + str(sign), frame, "N07", "valley", "support")

func _warning_sources() -> Array:
	# Same frozen generation order, including previews placed on a predecessor.
	var records: Array = []
	var presentation: Node3D = session.lab.get_node("PresentationRoot")
	for track in route.tracks.values():
		for ob in track.obstacles:
			for lane in ob.lanes:
				var preview := maxf(float(ob.get("preview_seconds", 1.8)) * 175.0, 170.0)
				for ratio: float in [1.0, 0.72, 0.48, 0.28]:
					var distance := float(ob.s) - preview * ratio
					var support = track
					if distance < 0:
						var previous = null
						for candidate in route.tracks.values():
							if candidate.next.has(track.id) and (previous == null or candidate.length > previous.length):
								previous = candidate
						if previous != null and previous.length + distance >= 0: support = previous
					var expected: Transform3D = session.lab._approach_pose(route, track, distance).translated_local(Vector3(lane * 4.4, 0.18, 0))
					records.append({"obstacle_id": route.obstacle_key(track, ob), "obstacle_track": track.id,
						"support_track": support.id, "ratio": ratio, "pose": presentation.global_transform * expected})
	return records

func _functional_kit() -> void:
	# Source MultiMesh transforms are authoritative. New parts share each original batch envelope.
	var source_nodes: Array = session.lab.get_node("PresentationRoot").find_children("*", "MultiMeshInstance3D", true, false)
	var serial := 0
	var warnings := _warning_sources()
	var warning_index := 0
	for source: MultiMeshInstance3D in source_nodes:
		var n := _semantic_name(source)
		var source_id := n + ":%04d" % serial
		var source_track: String = str(source.get_parent().name).rsplit("_", true, 1)[0]
		var source_space: String = str(track_spaces.get(source_track, "N01"))
		var source_scene: String = str(track_scenes.get(source_track, "station"))
		serial += 1
		if n.begins_with("Pickets") or n.begins_with("NearSpeedMarkers"):
			var desired := Vector3(0.7, 1.33, 0.67) if not cartoon else Vector3(0.9, 1.4, 0.8)
			var module: Node3D = modules.marker
			var module_bounds := _module_bounds(module)
			# Reuse transforms and count; tall speed-markers retain their pole and gain a small lamp head.
			var tall := n.begins_with("NearSpeedMarkers")
			var isolated_poles := false
			var batch_count := source.multimesh.instance_count
			functional_counts.marker_instances += batch_count
			var marker_poses: Array[Transform3D] = []
			for index in batch_count:
				var frozen := source.global_transform * source.multimesh.get_instance_transform(index)
				var size := frozen.basis.get_scale()
				var upright := Transform3D(frozen.basis.orthonormalized(), frozen.origin)
				var scalar := 0.7 if tall else 0.63
				var at := upright.translated_local(Vector3(0, size.y * 0.5 if tall else 0, 0)).rotated_local(Vector3.UP, PI)
				var group_id := sid + ":marker:" + source_id + ":" + str(index)
				var delta := v(marker_repairs.get("offsets", {}).get(group_id, [0, 0, 0]))
				at.origin += delta
				if tall and not delta.is_zero_approx():
					# Isolate the visual batch before moving the paired existing pole.
					if not isolated_poles:
						# Copy instances explicitly; dummy rendering has no readable GPU buffer.
						var original := source.multimesh
						var isolated := MultiMesh.new()
						isolated.transform_format = original.transform_format
						isolated.use_colors = original.use_colors
						isolated.use_custom_data = original.use_custom_data
						isolated.mesh = original.mesh
						isolated.instance_count = original.instance_count
						isolated.visible_instance_count = original.visible_instance_count
						isolated.custom_aabb = original.custom_aabb
						for pole_index in original.instance_count:
							isolated.set_instance_transform(pole_index, original.get_instance_transform(pole_index))
							if original.use_colors: isolated.set_instance_color(pole_index, original.get_instance_color(pole_index))
							if original.use_custom_data: isolated.set_instance_custom_data(pole_index, original.get_instance_custom_data(pole_index))
						source.multimesh = isolated
						isolated_poles = true
					var shifted_pole := frozen
					shifted_pole.origin += delta
					source.multimesh.set_instance_transform(index, source.global_transform.affine_inverse() * shifted_pole)
					var pole_bounds := source.multimesh.mesh.get_aabb()
					_record_box(sid + ":moved-pole:" + source_id + ":" + str(index), "support", source_space,
						shifted_pole * Transform3D(Basis.IDENTITY, pole_bounds.get_center()), pole_bounds.size)
					moved_pole_count += 1
				scalar *= float(marker_repairs.get("scale_multipliers", {}).get(group_id, 1.0))
				marker_poses.append(at.scaled_local(Vector3.ONE * scalar))
			for entry: Dictionary in kit_manifest.modules:
				if str(entry.id) != "marker": continue
				for index in batch_count:
					for part: Dictionary in entry.collision_proxy_boxes:
						_record_box(sid + ":marker:" + source_id + ":" + str(index) + ":" + str(part.proxy_id), "support", source_space,
							marker_poses[index] * Transform3D(Basis.IDENTITY, v(part.center)), v(part.size))
						bounds_items.back()["bounds_kind"] = "conservative_mesh_aabb"
			var piece_index := 0
			for piece: MeshInstance3D in module.find_children("*", "MeshInstance3D", true, false):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = piece.mesh
				mm.instance_count = batch_count
				var instance := MultiMeshInstance3D.new()
				instance.multimesh = mm
				for index in batch_count:
					mm.set_instance_transform(index, marker_poses[index] * piece.transform)
				# Keep individual imported material overrides after MultiMesh conversion.
				if piece.get_surface_override_material_count() > 0:
					instance.material_override = piece.get_surface_override_material(0)
				if route.tracks.has(source_track) and route.tracks[source_track].kind == "rescue" and str(piece.name).to_lower().contains("cyan"):
					instance.material_override = materials.purple
				root.add_child(instance)
				tag(instance, sid + ":marker-batch:" + source_id + ":" + str(piece_index), "marker", source_scene)
				instance.visibility_range_end = 420
				piece_index += 1
			if not tall: source.visible = false
		elif n.begins_with("Block") or n.begins_with("LowBeam"):
			functional_counts.hard_obstacle_instances += source.multimesh.instance_count
			# A metal casing with warning corners, fitted inside the real source size.
			for index in source.multimesh.instance_count:
				var frozen := source.global_transform * source.multimesh.get_instance_transform(index)
				var size := frozen.basis.get_scale()
				var at := Transform3D(frozen.basis.orthonormalized(), frozen.origin)
				var ident := sid + ":hazard:" + source_id + ":" + str(index)
				var bounds := _module_bounds(modules.hazard_shell)
				var track_id := _nearest_track(frozen.origin)
				_put_module("hazard_shell", ident, at.scaled_local(size / bounds.size * 0.99),
					track_spaces[track_id], track_scenes[track_id], "functional")
			source.visible = false
		elif n.begins_with("ApproachMarks"):
			functional_counts.warning_plate_instances += source.multimesh.instance_count
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			var mesh := BoxMesh.new()
			mesh.size = Vector3(3.0, 0.02, 0.23)
			batch.mesh = mesh
			batch.instance_count = source.multimesh.instance_count * 2
			var warning_scene := source_scene
			for index in source.multimesh.instance_count:
				var frozen := source.global_transform * source.multimesh.get_instance_transform(index)
				if warning_index >= warnings.size():
					construction_errors.append("Unexpected warning batch " + source_id)
					continue
				var provenance: Dictionary = warnings[warning_index]
				warning_index += 1
				var expected: Transform3D = provenance.pose
				if DisplayServer.get_name() != "headless" and (frozen.origin.distance_to(expected.origin) > 0.01 or not frozen.basis.is_equal_approx(expected.basis)):
					construction_errors.append("Frozen warning order/pose mismatch: " + source_id)
				var warning_space: String = str(track_spaces[provenance.support_track])
				warning_scene = str(track_scenes[provenance.support_track])
				for arm in 2:
					var at := frozen.translated_local(Vector3(0, 0.051, 0)).rotated_local(Vector3.UP, PI * (0.25 if arm == 0 else -0.25))
					batch.set_instance_transform(index * 2 + arm, at)
					_record_box(sid + ":warning-cross:" + source_id + ":" + str(index) + ":" + str(arm),
						"route_surface", warning_space, at, mesh.size)
					bounds_items.back()["obstacle_id"] = provenance.obstacle_id
					bounds_items.back()["obstacle_track"] = provenance.obstacle_track
					bounds_items.back()["support_track"] = provenance.support_track
					bounds_items.back()["warning_ratio"] = provenance.ratio
			var crosses := MultiMeshInstance3D.new()
			crosses.multimesh = batch
			crosses.material_override = materials.white
			root.add_child(crosses)
			tag(crosses, sid + ":warning-cross:" + source_id, "warning_cross", warning_scene)
			crosses.visibility_range_end = source.visibility_range_end
	if warning_index != warnings.size():
		construction_errors.append("Frozen warning enumeration incomplete")

func _basins_and_floors() -> void:
	if not cartoon:
		for basin: Dictionary in design.water_design.basins:
			var poly: Array = basin.footprint_xz_m
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for point: Array in poly:
				lo = lo.min(Vector2(point[0], point[1]))
				hi = hi.max(Vector2(point[0], point[1]))
			var mid := (lo + hi) * 0.5
			var size := Vector3(hi.x - lo.x, 0.16, hi.y - lo.y)
			var space: String = basin.consumer_space_ids[0]
			_box(root, basin.id, size, Transform3D(Basis.IDENTITY, Vector3(mid.x, basin.water_y_m - 0.08, mid.y)),
				"water", "water", space, "station" if space == "N01" else ("canyon" if space == "N02" else "valley"))
			_box(root, str(basin.id) + ":bed", Vector3(size.x, 1.0, size.z),
				Transform3D(Basis.IDENTITY, Vector3(mid.x, basin.bed_y_range_m[0] - 0.5, mid.y)),
				"ground", "bank", space, "station" if space == "N01" else ("canyon" if space == "N02" else "valley"))
	# World-up regional foundations; water footprints keep their own stepped beds.
	for space: Dictionary in design.space_designs:
		var bounds: Dictionary = space.baseline_facts.track_world_bounds_m
		var lo := v(bounds.min) - Vector3(220, 0, 220)
		var hi := v(bounds.max) + Vector3(220, 0, 220)
		var patches: Array[Rect2] = [Rect2(Vector2(lo.x, lo.z), Vector2(hi.x - lo.x, hi.z - lo.z))]
		if not cartoon:
			for basin: Dictionary in design.water_design.basins:
				var blo := Vector2(INF, INF)
				var bhi := Vector2(-INF, -INF)
				for point: Array in basin.footprint_xz_m:
					blo = blo.min(Vector2(point[0], point[1]))
					bhi = bhi.max(Vector2(point[0], point[1]))
				var next: Array[Rect2] = []
				for patch: Rect2 in patches:
					next.append_array(_subtract_rect(patch, Rect2(blo, bhi - blo)))
				patches = next
		for i in patches.size():
			_ground_patch(space, patches[i], i)

func _subtract_rect(source: Rect2, cut: Rect2) -> Array[Rect2]:
	var overlap := source.intersection(cut)
	if not overlap.has_area(): return [source]
	var result: Array[Rect2] = []
	for rect in [Rect2(source.position, Vector2(overlap.position.x - source.position.x, source.size.y)),
		Rect2(Vector2(overlap.end.x, source.position.y), Vector2(source.end.x - overlap.end.x, source.size.y)),
		Rect2(Vector2(overlap.position.x, source.position.y), Vector2(overlap.size.x, overlap.position.y - source.position.y)),
		Rect2(Vector2(overlap.position.x, overlap.end.y), Vector2(overlap.size.x, source.end.y - overlap.end.y))]:
		if rect.has_area(): result.append(rect)
	return result

func _ground_patch(space: Dictionary, rect: Rect2, serial: int) -> void:
	var floor_y: float = region_floor_y[space.space_id]
	var center := Vector3(rect.get_center().x, floor_y - 0.5, rect.get_center().y)
	var size := Vector3(rect.size.x, 1.0, rect.size.y)
	var ident := sid + ":" + str(space.space_id) + ":floor:" + str(serial)
	if _safe_box(AABB(center - size * 0.5, size), 8.0):
		_box(root, ident, size, Transform3D(Basis.IDENTITY, center), "ground", "bank", space.space_id, space.runtime_scene_ids[0])
	else:
		for x in range(ceili(size.x / 120.0)):
			for z in range(ceili(size.z / 120.0)):
				var tile := Vector3(minf(120.0, size.x - x * 120.0), 1.0, minf(120.0, size.z - z * 120.0))
				var at := Vector3(rect.position.x + x * 120.0 + tile.x * 0.5, center.y, rect.position.y + z * 120.0 + tile.z * 0.5)
				if _safe_box(AABB(at - tile * 0.5, tile), 8.0):
					_box(root, ident + ":%d:%d" % [x, z], tile, Transform3D(Basis.IDENTITY, at), "ground", "bank", space.space_id, space.runtime_scene_ids[0])
