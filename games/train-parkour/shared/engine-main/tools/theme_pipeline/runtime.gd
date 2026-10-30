extends SceneTree
## Generic adapter: the authoritative app is instantiated before presentation assembly.
const Host = preload("res://themes/common/production_host.gd")
var host: Node
const Driver = preload("res://../tools/theme_pipeline/coverage_driver.gd")
var main: SpatialSession
var driver: RefCounted
var seen := -1.0
var previous_us := 0
var frame_times: Array[float] = []
var profiling := false
var timing_samples: Array = []
var track_regions := {}
var warmup_report := {}
var initialization_ms := 0
var initialized_at := 0
var options: Dictionary = {}
var theme: Dictionary
var recipe: Dictionary
var catalog: Dictionary
var presentation: Node3D

func _initialize() -> void:
	initialized_at = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair = arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	run.call_deferred()

func _process(_delta: float) -> bool:
	if driver != null and main != null:
		if profiling:
			var now = Time.get_ticks_usec()
			if previous_us > 0:
				var ms: float = (now - previous_us) / 1000.0
				frame_times.append(ms)
				var motion = main.train.motion
				timing_samples.append({"ms":ms,"track":motion.route.current.id,"s":motion.s,"clock":motion.clock,
					"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
			previous_us = now
	return false

func _physics_process(_delta: float) -> bool:
	if driver != null and main != null:
		var clock = main.train.motion.clock
		if clock != seen:
			driver.tick(main.train)
			# Deliver synthetic key edges in this physics step, before the train polls them.
			# Otherwise two 120 Hz steps in one render frame can buffer duplicate lane taps.
			Input.flush_buffered_events()
			seen = clock
	return false

func project_path(value: String) -> String:
	return "res://../" + value

func data(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func clean(value: Variant) -> Variant:
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Vector2: return [value.x, value.y]
	if value is Quaternion: return [value.x, value.y, value.z, value.w]
	if value is Basis: return [clean(value.x), clean(value.y), clean(value.z)]
	if value is Transform3D: return {"origin": clean(value.origin), "basis": clean(value.basis)}
	if value is AABB: return {"position": clean(value.position), "size": clean(value.size)}
	if value is Dictionary:
		var result = {}
		for key in value: result[str(key)] = clean(value[key])
		return result
	if value is Array or value is PackedVector3Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedStringArray:
		var result = []
		for item in value: result.append(clean(item))
		return result
	if value is float and not is_finite(value): return "positive_infinity" if value > 0 else "negative_infinity"
	return value

func script_values(object: Object) -> Dictionary:
	var result = {}
	for prop in object.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = object.get(prop.name)
			if not value is Object: result[prop.name] = clean(value)
	return result

func shape_values(shape: Shape3D) -> Dictionary:
	if shape == null: return {}
	var result = {"class": shape.get_class()}
	for prop in shape.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE:
			var value = shape.get(prop.name)
			if not value is Object: result[prop.name] = clean(value)
	return result

func fingerprint(app: SpatialSession) -> Dictionary:
	var route = app.lab.route
	var tracks = {}
	for id in route.tracks: tracks[id] = script_values(route.tracks[id])
	var collisions = []
	for node in app.find_children("*", "CollisionObject3D", true, false):
		collisions.append({"path": str(app.get_path_to(node)), "pose": clean(node.global_transform), "layer": node.collision_layer, "mask": node.collision_mask})
	var shapes = []
	for node in app.find_children("*", "CollisionShape3D", true, false):
		shapes.append({"path": str(app.get_path_to(node)), "pose": clean(node.global_transform),
			"disabled": node.disabled, "shape": shape_values(node.shape)})
	return {"tracks": tracks, "route_transform": clean(route.global_transform), "start_id": route.start_id,
		"camera_solids": clean(route.camera_solids), "revision": route.experience_revision,
		"settings": script_values(app.train.settings), "motion_tuning": script_values(app.train.tuning),
		"camera": {"script": app.camera.get_script().resource_path, "pose": clean(app.camera.global_transform),
			"fov": app.camera.fov, "near": app.camera.near, "far": app.camera.far, "comfort": app.camera.comfort,
			"projection": app.camera.projection, "keep_aspect": app.camera.keep_aspect,
			"offset": [app.camera.h_offset, app.camera.v_offset], "frustum_offset": clean(app.camera.frustum_offset)},
		"collisions": collisions, "collision_shapes": shapes}

func encode(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)

func assemble(app: SpatialSession) -> Array:
	presentation = Node3D.new()
	presentation.name = "ThemePresentation"
	app.add_child(presentation)
	var assets = {}
	for asset in recipe.assets: assets[asset.id] = asset
	var result = []
	for spec in recipe.instances:
		var asset = assets[spec.asset_id]
		var node: Node3D
		if asset.kind == "box":
			var mesh = BoxMesh.new()
			mesh.size = vec(asset.size_m)
			var material = StandardMaterial3D.new()
			material.albedo_color = Color(asset.color)
			var instance = MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			node = instance
		else:
			node = load(project_path(asset.path)).instantiate()
		node.name = spec.id
		presentation.add_child(node)
		var pose = Transform3D.IDENTITY
		if spec.frame == "track":
			var track = app.lab.route.tracks[spec.track_id]
			assert(spec.s_m <= track.length, "Instance beyond track end")
			pose = app.lab.route.track_pose(spec.track_id, spec.s_m)
			pose.origin += pose.basis * vec(spec.offset_m)
			if spec.orientation == "world_up":
				var forward = -pose.basis.z
				forward.y = 0
				assert(forward.length_squared() > 0.00001, "World-up yaw undefined on vertical track; use world anchor")
				pose.basis = Basis.looking_at(forward.normalized(), Vector3.UP)
		else:
			pose.origin = vec(spec.offset_m)
		pose.basis *= Basis.from_euler(vec(spec.rotation_deg) * PI / 180.0)
		pose.basis = pose.basis.scaled(Vector3.ONE * spec.scale)
		node.global_transform = pose
		node.set_meta("instance_id", spec.id)
		node.set_meta("asset_id", spec.asset_id)
		node.set_meta("scene_id", spec.scene_id)
		result.append({"id": spec.id, "asset_id": spec.asset_id, "scene_id": spec.scene_id,
			"transform": clean(pose), "support": spec.support})
	return result

func save_report(report: Dictionary) -> void:
	var file = FileAccess.open(options.output, FileAccess.WRITE)
	assert(file != null, "Cannot write report")
	if host != null: report.merge(host.evidence())
	if host != null and host.presentation != null and host.presentation.has_meta("construction_report"):
		report["construction"] = clean(host.presentation.get_meta("construction_report"))
		report.passed = report.passed and report.construction.errors.is_empty()
	file.store_string(JSON.stringify(report, "", true, true) + "\n")
	print("THEME_PIPELINE_RESULT mode=", options.mode, " passed=", report.passed)
	quit(0 if report.passed else 1)

func run() -> void:
	theme = data(project_path(options.theme))
	recipe = data(project_path(theme.recipe))
	catalog = data(project_path(theme.catalog))
	var baseline = data(project_path(theme.baseline))
	Engine.physics_ticks_per_second = int(options.get("hz", "60"))
	root.size = Vector2i(1440, 810)
	var reference = load(project_path(baseline.application_scene)).instantiate()
	root.add_child(reference)
	var expected = fingerprint(reference)
	reference.free()
	host = Host.new()
	host.camera_profile = options.get("camera-profile", "comparison")
	host.pixel_scale = int(options.get("pixel-scale", "0"))
	root.add_child(host)
	main = host.create(theme, false).session
	var initial = fingerprint(main)
	host.build_presentation()
	var instances = assemble(main)
	var actual = fingerprint(main)
	host.refresh_geometry()
	var registered = host.invalid_geometry() if theme.has("presentation_script") else []
	for node in host.generated_geometry:
		if theme.has("presentation_script"):
			var info = host.registration(node)
			instances.append({"id": info.get("instance_id", ""), "asset_id": info.get("asset_id", ""), "scene_id": info.get("scene_id", ""), "path": str(main.get_path_to(node)), "transform": clean(node.global_transform)})
	host.apply_camera_profile()
	var invalid = []
	for node in main.find_children("*", "Node3D", true, false):
		if (node is CollisionObject3D and (presentation.is_ancestor_of(node) or host.presentation.is_ancestor_of(node))) or not node.global_transform.is_finite(): invalid.append(str(node.get_path()))
	var assigned = []
	for scene in catalog.scenes:
		for id in scene.tracks:
			assigned.append(id)
			track_regions[id] = scene.id
	assigned.sort()
	var real_ids = main.lab.route.tracks.keys()
	real_ids.sort()
	var invalid_shots = []
	for shot in catalog.shots:
		if not main.lab.route.tracks.has(shot.track_id) or shot.s_m > main.lab.route.tracks[shot.track_id].length:
			invalid_shots.append(shot.id)
	var scene_ids = []
	for scene in catalog.scenes: scene_ids.append(scene.id)
	for instance in instances:
		if not instance.scene_id in scene_ids: registered.append(instance.id)
	var checks = {"full_gameplay_and_camera_equal": encode(expected) == encode(actual) and encode(expected) == encode(initial),
		"camera_profile_valid": host.camera_profile_valid(), "generated_geometry_registered": registered.is_empty(),
		"all_37_tracks_assigned": assigned == real_ids and real_ids.size() == baseline.expected_tracks,
		"valid_presentation": invalid.is_empty(), "shot_anchors_valid": invalid_shots.is_empty()}
	var valid = checks.values().all(func(x): return x)
	var mode = options.get("mode", "check")
	if not valid or mode in ["check", "survey"]:
		var report = {"passed": valid, "checks": checks, "instances": instances,
			"fingerprint": encode(actual).sha256_text(), "baseline_fingerprint": encode(expected).sha256_text(),
			"invalid_presentation": invalid, "unregistered_geometry": registered, "invalid_shots": invalid_shots,
			"scope": "Instantiated complete track arrays, gameplay fields, tuning, camera initialization and presentation contract; not visual acceptance."}
		if mode == "survey":
			report["snapshot"] = actual
			var route_samples = {}
			for id in main.lab.route.tracks:
				var track = main.lab.route.tracks[id]
				var rows = []
				for i in ceili(track.length / 16.0) + 1:
					var distance = minf(track.length,i*16.0)
					rows.append({"s":distance,"pose":clean(track.pose(distance))})
				route_samples[id] = rows
			report["route_samples"] = route_samples
			report["catalog"] = catalog
		save_report(report)
		return
	if mode == "run": return
	if mode == "clearance":
		await clearance()
		return
	initialization_ms = Time.get_ticks_msec()-initialized_at
	await replay(mode)

func percentile(values: Array[float], q: float) -> float:
	var sorted = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, floori(sorted.size() * q))] if not sorted.is_empty() else 0

func replay(mode: String) -> void:
	if mode == "profile":
		await replay("warmup")
		if not warmup_report.get("passed",false):
			save_report(warmup_report)
			return
		main.restart_run()
		seen = -1.0
		previous_us = 0
		frame_times.clear()
		timing_samples.clear()
	var native = DisplayServer.get_name() != "headless"
	assert(not mode in ["capture", "profile"] or native, "Native renderer required")
	if options.branch == "comfort": main.camera.comfort = true
	for i in 10: await process_frame
	# Attach steering before starting motion. Waiting for rendered frames first
	# let a heavy theme cross the start pad without input and changed its launch.
	driver = Driver.new()
	driver.high_short = options.branch=="high-short"
	if options.branch == "fast": driver.fast_canyon = true; driver.final_upper = true
	if options.branch in ["high","high-short"]: driver.high_route = true
	if options.branch == "safe": driver.safe_rollout = true
	if options.branch == "rescue": driver.rescue = true
	seen = -1.0
	var starter = Driver.new()
	starter.set_key([KEY_1,KEY_2,KEY_3][int(options.get("pace","3"))-1], true)
	for i in 3: await physics_frame
	starter.release()
	if mode in ["profile","warmup"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	profiling = mode in ["profile","warmup"]
	var selected = str(options.get("shots", "")).split(",", false)
	var captured = []
	var frames = []
	var trajectory = []
	var visited = {}
	var traversed := {}
	var contact_intervals := {}
	var camera_errors = 0
	var next_sample = 0.0
	var video_fps := int(options.get("video-fps","0"))
	var video_end := float(options.get("video-end","0"))
	assert(is_finite(video_end) and video_end >= 0.0, "Finite non-negative video end required")
	var next_video := 0.0
	var video_frames: Array = []
	if video_fps > 0: DirAccess.make_dir_recursive_absolute(str(options.output).get_base_dir().path_join("video"))
	var start = Time.get_ticks_msec()
	while not main.finished and main.recoveries == 0 and Time.get_ticks_msec() - start < 210000:
		await process_frame
		host.apply_camera_profile()
		if not host.camera_profile_valid(): camera_errors += 1
		var motion = main.train.motion
		var id = motion.route.current.id
		visited[id] = true
		if motion.phase in [SpatialMotionSolver.RAIL,SpatialMotionSolver.DRIFT]:
			if not contact_intervals.has(id): contact_intervals[id] = {"s_min":motion.s,"s_max":motion.s,"samples":0}
			contact_intervals[id].s_min = minf(contact_intervals[id].s_min,motion.s)
			contact_intervals[id].s_max = maxf(contact_intervals[id].s_max,motion.s)
			contact_intervals[id].samples += 1
		if not traversed.has(id): traversed[id] = {"s_min":motion.s,"s_max":motion.s,"first_clock":motion.clock,"last_clock":motion.clock,"samples":0}
		traversed[id].s_min = minf(traversed[id].s_min,motion.s)
		traversed[id].s_max = maxf(traversed[id].s_max,motion.s)
		traversed[id].last_clock = motion.clock
		traversed[id].samples += 1
		if mode != "profile" and motion.clock >= next_sample:
			next_sample = motion.clock + 0.1
			trajectory.append({"track": id, "s": motion.s, "clock": motion.clock, "speed": motion.speed,
				"camera": clean(main.camera.get_camera_transform()), "train": clean(motion.world_pose), "train_collision": clean(main.train.get_node("CollisionShape3D").global_transform), "fov": main.camera.fov})
		if video_fps > 0 and motion.clock >= next_video and (video_end == 0.0 or motion.clock <= video_end):
			next_video = motion.clock + 1.0 / video_fps
			RenderingServer.force_draw(false)
			var filename := "video/%05d.jpg" % video_frames.size()
			var error := root.get_texture().get_image().save_jpg(str(options.output).get_base_dir().path_join(filename),0.88)
			video_frames.append({"file":filename,"clock":motion.clock,"track":id,"s":motion.s,"save_error":error})
		if mode == "capture":
			for shot in catalog.shots:
				if shot.id in selected and not shot.id in captured and id == shot.track_id and motion.s >= shot.s_m:
					RenderingServer.force_draw(false)
					var image_path = str(options.output).get_base_dir().path_join(shot.id + ".jpg")
					var error = root.get_texture().get_image().save_jpg(image_path, 0.88)
					frames.append({"id": shot.id, "file": image_path.get_file(), "save_error": error,
						"track": id, "s": motion.s, "camera": clean(main.camera.get_camera_transform()), "fov": main.camera.fov})
					captured.append(shot.id)
	driver.release()
	driver = null
	profiling = false
	var missing = []
	for id in selected:
		if not id in captured: missing.append(id)
	var passed = main.finished and main.recoveries == 0 and camera_errors == 0 and video_frames.all(func(x): return x.save_error == OK)
	if mode == "capture": passed = passed and missing.is_empty() and frames.all(func(x): return x.save_error == OK)
	var expected_choices: Array = {"fast":["canyon_fast","final_upper"],"high":["high_merge"],"high-short":["high"],"safe":["rollout"],"rescue":["rescue","rescue_merge"]}.get(options.branch,[])
	var choices_ok := expected_choices.all(func(id): return contact_intervals.has(id))
	passed = passed and choices_ok
	var report = {"initialization_wall_ms":initialization_ms,"branch_choices_satisfied":choices_ok,"expected_branch_tracks":expected_choices,"passed": passed, "finished": main.finished, "recoveries": main.recoveries,
		"simulation_seconds": main.train.motion.clock, "branch": options.branch, "pace":int(options.get("pace","3")),
		"native": native, "hz": Engine.physics_ticks_per_second, "resolution": [root.size.x, root.size.y],
		"renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(),
		"video_frames":video_frames, "video_timebase":"simulation_clock; original speed; not a performance benchmark",
		"video_capture_end_seconds":video_end,"gameplay_replay_truncated":false,
		"camera_contract_errors": camera_errors, "visited_tracks": visited.keys(), "trajectory": trajectory, "frames": frames, "missing_shots": missing,
		"scope": "Synthetic-key replay; capture and performance are separate; no human visual or comfort acceptance."}
	var uncovered = main.lab.route.tracks.keys().filter(func(id): return not visited.has(id))
	report["route_coverage"] = {"visited":visited.keys(),"traversed_intervals":traversed,"contact_intervals":contact_intervals,"unvisited":uncovered,"declared_track_count":main.lab.route.tracks.size(),"scope":"Union of branch reports required; individual run does not cover all tracks"}
	if mode in ["profile","warmup"]:
		var regions := {}
		var long_frames := []
		for row in timing_samples:
			var region: String = track_regions.get(row.track,"unknown")
			if not regions.has(region): regions[region] = []
			regions[region].append(row)
			if row.ms > 33.3: long_frames.append(row)
		var segment_timing := {}
		for region in regions:
			var times: Array[float] = []
			var peak_draws := 0.0
			var peak_primitives := 0.0
			for row in regions[region]:
				times.append(row.ms)
				peak_draws = maxf(peak_draws,row.draw_calls)
				peak_primitives = maxf(peak_primitives,row.primitives)
			segment_timing[region] = {"frames":times.size(),"p95_ms":percentile(times,0.95),"p99_ms":percentile(times,0.99),"peak_draw_calls":peak_draws,"peak_primitives":peak_primitives}
		report["segment_timing"] = segment_timing
		report["long_frames"] = long_frames
		report["over_33_3ms_fraction"] = float(long_frames.size()) / maxf(1,frame_times.size())
		report["warmup_policy"] = "one complete same-branch traversal before measurement; cold traversal reported separately" if mode=="profile" else "first traversal; cold/first-entry evidence"
		report["wall_frame_ms"] = {"p50": percentile(frame_times, 0.5), "p95": percentile(frame_times, 0.95), "p99": percentile(frame_times, 0.99)}
		report["frame_count"] = frame_times.size()
		var consecutive = 0
		var worst = 0
		for value in frame_times:
			consecutive = consecutive + 1 if value > 1000.0 / 30.0 else 0
			worst = maxi(worst, consecutive)
		report["timing_mode"] = "uncapped_vsync_disabled"
		report["performance_gate"] = {"passed": percentile(frame_times, 0.95) <= 1000.0 / 60.0 and percentile(frame_times, 0.99) <= 20.0 and float(long_frames.size()) / maxf(1,frame_times.size()) <= 0.001 and long_frames.all(func(row): return row.ms <= 50.0),
			"p95_limit_ms": 1000.0 / 60.0, "p99_limit_ms": 20.0, "longest_consecutive_over_33ms": worst,
			"scope": "Single uncapped run only; final acceptance requires three isolated runs and normal 60Hz presentation."}
		report["wall_duration_ms"] = Time.get_ticks_msec() - start
	if mode=="warmup":
		warmup_report = report
		return
	if mode=="profile": report["cold_traversal"] = warmup_report
	save_report(report)

func clearance() -> void:
	var trajectory = data(options.source).trajectory
	assert(not trajectory.is_empty(), "Empty trajectory")
	var bodies = Node3D.new()
	root.add_child(bodies)
	var mesh_count = 0
	var unsupported = []
	for node in host.generated_geometry:
		if not node.is_visible_in_tree() or main.train.is_ancestor_of(node): continue
		# Camera-attached clip-space effects are not world geometry or solids.
		if main.camera.is_ancestor_of(node) and node.get_meta("screen_space_effect", false): continue
		var mesh: Mesh
		var poses: Array[Transform3D] = []
		if node is MeshInstance3D:
			mesh = node.mesh
			poses.append(node.global_transform)
		elif node is MultiMeshInstance3D and node.multimesh != null:
			mesh = node.multimesh.mesh
			var count = node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else node.multimesh.visible_instance_count
			for i in count: poses.append(node.global_transform * node.multimesh.get_instance_transform(i))
		else:
			unsupported.append(str(node.get_path()))
			continue
		if mesh == null:
			unsupported.append(str(node.get_path()))
			continue
		var shape = mesh.create_trimesh_shape()
		if shape == null:
			unsupported.append(str(node.get_path()))
			continue
		shape.backface_collision = true
		for pose in poses:
			var body = StaticBody3D.new()
			body.collision_layer = 1 << 19
			body.collision_mask = 0
			bodies.add_child(body)
			body.global_transform = pose
			body.set_meta("source", str(node.get_path()))
			var collider = CollisionShape3D.new()
			collider.shape = shape
			body.add_child(collider)
			mesh_count += 1
	await physics_frame
	await physics_frame
	var space = root.world_3d.direct_space_state
	var sphere = SphereShape3D.new()
	sphere.radius = 0.35
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1 << 19
	var failures = []
	var previous = vec(trajectory[0].camera.origin)
	var previous_train = Transform3D.IDENTITY
	var train_samples = 0
	var previous_source_index := -1
	var skipped_discontinuities := 0
	for sample in trajectory:
		var source_index: int = int(sample.get("clearance_source_index",previous_source_index+1))
		var contiguous := previous_source_index>=0 and source_index==previous_source_index+1
		if previous_source_index>=0 and not contiguous: skipped_discontinuities+=1
		previous_source_index=source_index
		var point = vec(sample.camera.origin)
		query.transform = Transform3D(Basis.IDENTITY, point)
		var hits = space.intersect_shape(query, 4)
		if not hits.is_empty(): failures.append({"track": sample.track, "s": sample.s, "kind": "sphere", "source": hits[0].collider.get_meta("source")})
		if contiguous and previous.distance_to(point) > 0.001:
			query.transform.origin = previous
			query.motion = point - previous
			var sweep = space.cast_motion(query)
			if sweep[0] < 1.0: failures.append({"track": sample.track, "s": sample.s, "kind": "camera_sweep", "safe_fraction": sweep[0]})
			query.motion = Vector3.ZERO
		if sample.has("train"):
			var train_shape = BoxShape3D.new()
			train_shape.size = Vector3(2.6, 3.4, 12.0)
			var train_query = PhysicsShapeQueryParameters3D.new()
			train_query.shape = train_shape
			train_query.collision_mask = 1 << 19
			var train_pose: Dictionary = sample.get("train_collision", sample.train)
			var columns = train_pose.basis
			train_query.transform = Transform3D(Basis(vec(columns[0]), vec(columns[1]), vec(columns[2])), vec(train_pose.origin))
			if not sample.has("train_collision"): train_query.transform.origin += train_query.transform.basis.y * 1.7
			var train_hits = space.intersect_shape(train_query, 4)
			if not train_hits.is_empty(): failures.append({"track": sample.track, "s": sample.s, "kind": "train_envelope", "source": train_hits[0].collider.get_meta("source")})
			var current_train = train_query.transform
			if train_samples > 0 and contiguous:
				train_query.transform = previous_train
				train_query.motion = current_train.origin - previous_train.origin
				var train_sweep = space.cast_motion(train_query)
				if train_sweep[0] < 1.0: failures.append({"track": sample.track, "s": sample.s, "kind": "train_translation_sweep", "safe_fraction": train_sweep[0]})
			previous_train = current_train
			train_samples += 1
		previous = point
	save_report({"passed": failures.is_empty() and unsupported.is_empty(), "samples": trajectory.size(),
		"train_samples": train_samples, "skipped_discontinuities": skipped_discontinuities, "meshes": mesh_count, "failures": failures, "unsupported_geometry": unsupported,
		"scope": "All generated presentation meshes including MultiMesh transforms; 0.35m camera spheres and sample center segments. Does not certify unchanged base geometry, curved paths or rotating train volume between samples, support or occlusion. Train uses frozen 2.6x3.4x12m physical box and linear translations. Train envelope checked only where trajectory has train poses; self-mounted train geometry is excluded."})
