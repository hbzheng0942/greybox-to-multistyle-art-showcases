extends "res://levels/labs/controller_lab/controller_lab.gd"
## Functional masses, close reference geometry and contact surfaces share SupportFrames.
@export var geometry_step := 2.0

func _build_gates() -> void:
	pass

func _build_track() -> void:
	var spatial := route as SpatialRoute
	var deck := _material(Color(0.14, 0.21, 0.27))
	var silver := _material(Color(0.74, 0.87, 0.91))
	var cyan := _material(Color(0.04, 0.9, 0.78))
	cyan.emission_enabled = true
	cyan.emission = Color(0.01, 0.20, 0.17)
	var gold := _material(Color(1, 0.64, 0.09))
	var violet := _material(Color(0.65, 0.31, 0.93))
	var stone := _material(Color(0.36, 0.31, 0.29))
	var dark := _material(Color(0.045, 0.075, 0.11))
	var red := _material(Color(1, 0.18, 0.11))
	var orange := _material(Color(1, 0.42, 0.08))
	var white := _material(Color(0.95, 0.97, 0.87))
	for track: SpatialTrack in spatial.tracks.values():
		var clip := track.kind in ["wall", "inverted", "loop", "clip"]
		for index in ceili(track.length / 120.0):
			var chunk := Node3D.new()
			chunk.name = track.id + "_%02d" % index
			presentation.add_child(chunk)
			chunk.position = track.pose(index * 120).origin
			var beds: Array[Transform3D] = []
			var rails: Array[Transform3D] = []
			var ties: Array[Transform3D] = []
			var ribs: Array[Transform3D] = []
			var guards: Array[Transform3D] = []
			var marks: Array[Transform3D] = []
			var pads: Array[Transform3D] = []
			var devices: Array[Transform3D] = []
			var enclosure: Array[Transform3D] = []
			var landscape: Array[Transform3D] = []
			var lamp: Array[Transform3D] = []
			for j in ceili(120.0 / geometry_step):
				var s := index * 120.0 + j * geometry_step
				if s >= track.length: break
				var span := minf(geometry_step, track.length - s)
				var pose := track.pose(s + span * 0.5)
				pose.origin -= chunk.position
				beds.append(pose.translated_local(Vector3(0, -0.38, 0)).scaled_local(Vector3(track.width_at(s) * 2, 0.6, span + 0.025)))
				for lane in track.lanes():
					for sign in [-1, 1]:
						rails.append(pose.translated_local(Vector3(lane * 4.4 + sign * (0.26 if track.kind == "grind" else 0.72), 0.06, 0)).scaled_local(Vector3(0.16, 0.2, span)))
					if j % 2 == 0: ties.append(pose.translated_local(Vector3(lane * 4.4, -0.04, 0)).scaled_local(Vector3(2.1, 0.1, 0.3)))
				if not track.single_lane:
					for sign in [-1, 1]: guards.append(pose.translated_local(Vector3(sign * (track.width_at(s) - 0.05), 0.2, 0)).scaled_local(Vector3(0.18, 0.4, span + 0.025)))
				if j % 6 == 0:
					for sign in [-1, 1]: marks.append(pose.translated_local(Vector3(sign * (track.width_at(s) + 0.25), 0.5, 0)).scaled_local(Vector3(0.18, 1, 0.3)))
				if clip and j % 5 == 0:
					for sign in [-1, 1]: ribs.append(pose.translated_local(Vector3(sign * 1.7, -0.2, 0)).scaled_local(Vector3(0.28, 1.3, 0.65)))
				for pad in track.pads:
					if s >= pad.a and s <= pad.b:
						for sign in [-1, 1]:
							pads.append(pose.translated_local(Vector3(pad.lane * 4.4 + sign * 0.65, 0.19, 0)).rotated_local(Vector3.UP, sign * 0.65).scaled_local(Vector3(1.9, 0.12, 0.38)))
				if track.can_release(s):
					var powered := track.impulse.length() > 0.1
					if j % 3 == 0:
						devices.append(pose.translated_local(Vector3(0, 0.12, 0)).scaled_local(Vector3(track.half_width * 1.7, 0.14, 0.5)))
						if powered:
							for sign in [-1, 1]: devices.append(pose.translated_local(Vector3(sign * 1.9, 0.55, 0)).scaled_local(Vector3(0.5, 1.0, 0.65)))
				if track.kind == "wall":
					enclosure.append(pose.translated_local(Vector3(0, -1.0, 0)).scaled_local(Vector3(30, 1.0, span + 0.1)))
				if track.kind == "inverted" and j % 8 == 0:
					ribs.append(pose.translated_local(Vector3(0, -2.5, 0)).scaled_local(Vector3(10, 4, 0.5)))
				if track.enclosure == "tunnel":
					for sign in [-1, 1]:
						enclosure.append(pose.translated_local(Vector3(sign * 10.5, 6.5, 0)).scaled_local(Vector3(1.2, 14, span + 0.1)))
						if j % 4 == 0: lamp.append(pose.translated_local(Vector3(sign * 9.85, 5, 0)).scaled_local(Vector3(0.10, 0.3, 2.2)))
					enclosure.append(pose.translated_local(Vector3(0, 14.0, 0)).scaled_local(Vector3(22, 1, span + 0.1)))
					enclosure.append(pose.translated_local(Vector3(0, -0.9, 0)).scaled_local(Vector3(22, 1, span + 0.1)))
				# Preserve the release/receiver sight corridors: side masses must not
				# be emitted by an overlapping branch into another branch's camera.
				if j % 12 == 0 and track.id in ["rush", "loop_entry", "finish"]:
					for sign in [-1, 1]:
						var width := 7.0 + fmod(s * 0.1, 5)
						var height := 25.0 + 14.0 * (1 + sin(s * 0.015 + sign))
						var at: Vector3 = track.pose(s).origin + track.pose(s).basis.x * sign * (21.0 + 5 * sin(s * 0.02))
						at.y -= height * 0.5 + 8
						landscape.append(Transform3D(Basis.IDENTITY.scaled(Vector3(width, height, 23)), at - chunk.position))
			_batch(chunk, "Bed", Vector3.ONE, violet if track.kind == "rescue" else deck, beds, 650)
			_batch(chunk, "Rail", Vector3.ONE, gold if track.single_lane else silver, rails, 650)
			_batch(chunk, "Ties", Vector3.ONE, dark, ties, 500)
			_batch(chunk, "Clamps", Vector3.ONE, silver, ribs, 550)
			_batch(chunk, "EdgeCurbs", Vector3.ONE, silver, guards, 550)
			_batch(chunk, "Pickets", Vector3.ONE, violet if track.kind == "rescue" else cyan, marks, 650)
			_batch(chunk, "PulseArrows", Vector3.ONE, cyan, pads, 650)
			_batch(chunk, "ReleaseWindow", Vector3.ONE, gold, devices, 650)
			_batch(chunk, "ContactStructure", Vector3.ONE, dark if track.enclosure == "tunnel" else stone, enclosure, 750)
			_batch(chunk, "TunnelLamps", Vector3.ONE, cyan, lamp, 650)
			_batch(chunk, "NearMasses", Vector3.ONE, stone, landscape, 800)
		for ob in track.obstacles:
			for lane in ob.lanes:
				var pose := track.pose(ob.s, lane * 4.4)
				var soft: bool = ob.get("kind", "block") == "soft"
				var size := Vector3(1.3, ob.height, 1.3) if soft else Vector3(3, ob.height, 2)
				_batch(presentation, "SoftProp" if soft else "Block", size, orange if soft else red, [pose.translated_local(Vector3(0, ob.height * 0.5, 0))], 550)
				var preview := maxf(float(ob.get("preview_seconds", 2.0)) * 150.0, 150.0)
				for ratio: float in [1.0, 0.72, 0.48, 0.28]:
					var gap: float = preview * ratio
					_batch(presentation, "ApproachMarks", Vector3(2.4, 0.08, 0.45), red, [track.pose(ob.s - gap, lane * 4.4).translated_local(Vector3(0, 0.18, 0))], 550)
				var sign_pose := track.pose(ob.s - preview, lane * 4.4).translated_local(Vector3(0, 3.5, 0))
				_batch(presentation, "NoEntrySign", Vector3(3.0, 3.0, 0.25), red, [sign_pose], 700)
		# Compact physical pictograms, not giant debug sentences across the whole screen.
		if track.id in ["wall", "inverted", "loop_entry", "exit_ramp", "grind", "cliff_lip"]:
			var at := 30.0
			var label := Label3D.new()
			label.text = "SPACE" if not track.release_windows.is_empty() else ("LOOP" if track.id == "loop_entry" else "A  /  D")
			label.font_size = 72
			label.pixel_size = 0.022
			label.modulate = Color(1, 0.77, 0.2)
			label.visibility_range_end = 300
			presentation.add_child(label)
			label.transform = track.pose(at).translated_local(Vector3(0, 8, 0))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7000, 6000)
	plane.material = _material(Color(0.12, 0.28, 0.32))
	ground.mesh = plane
	ground.position = Vector3(1000, -45, -400)
	environment_root.add_child(ground)
	# Distant scale markers plus one recognisable coil station spanning the real loop.
	var skyline: Array[Transform3D] = []
	for track: SpatialTrack in spatial.tracks.values():
		for sign in [-1, 1]:
			var pose := track.pose(track.length * 0.5)
			var point: Vector3 = pose.origin + pose.basis.x * sign * 180
			point.y = 10
			var bounds := AABB(point - Vector3(14, 50, 16), Vector3(28, 100, 32))
			var corridor := false
			for other: SpatialTrack in spatial.tracks.values():
				if other.bounds.grow(65).intersects(bounds):
					corridor = true
					break
			if not corridor: skyline.append(Transform3D(Basis.IDENTITY.scaled(Vector3(28, 100, 32)), point))
	_batch(environment_root, "DistantPiers", Vector3.ONE, stone, skyline, 1600)
	var loop: SpatialTrack = spatial.tracks.loop
	var base := loop.pose(0)
	var station: Array[Transform3D] = []
	for sign in [-1, 1]:
		var point: Vector3 = base.origin + base.basis.x * sign * 28
		var height := base.origin.y + 120
		point.y = height * 0.5 - 10
		station.append(Transform3D(Basis.IDENTITY.scaled(Vector3(4, height, 4)), point))
	station.append(base.translated_local(Vector3(0, 112, 0)).scaled_local(Vector3(60, 3, 3)))
	_batch(environment_root, "CoilStation", Vector3.ONE, gold, station, 1800)
	# A real valley mass below/around the final flight, not an unreferenced blue void.
	var lip: SpatialTrack = spatial.tracks.cliff_lip
	var valley_frame := lip.pose(lip.length)
	var valley_forward := Vector3(-valley_frame.basis.z.x, 0, -valley_frame.basis.z.z).normalized()
	var valley_right := valley_forward.cross(Vector3.UP)
	var valley_basis := Basis(valley_right, Vector3.UP, -valley_forward)
	var floor_y: float = spatial.tracks.rescue.pose(0).origin.y - 24.0
	var cliffs: Array[Transform3D] = []
	for i in range(-1, 14):
		var along := float(i) * 65
		for sign in [-1, 1]:
			if sign < 0 and along > 280 and along < 780: continue # The lower rescue route has a visible canyon opening.
			var height: float = 58 + 18 * sin(i * 0.77 + sign)
			var point: Vector3 = valley_frame.origin + valley_forward * along + valley_right * sign * (46 + 6 * sin(i * 0.9))
			point.y = floor_y + height * 0.5
			cliffs.append(Transform3D(valley_basis.scaled_local(Vector3(28, height, 68)), point))
	_batch(environment_root, "ValleyWalls", Vector3.ONE, stone, cliffs, 1100)
	var floor_point := valley_frame.origin + valley_forward * 430 - valley_right * 40
	floor_point.y = floor_y - 3
	_batch(environment_root, "ValleyFloor", Vector3.ONE, _material(Color(0.24, 0.28, 0.25)), [Transform3D(valley_basis.scaled_local(Vector3(370, 6, 1050)), floor_point)], 0)
	var water_point := floor_point + Vector3.UP * 3.1 - valley_right * 15
	_batch(environment_root, "Riverbed", Vector3.ONE, _material(Color(0.10, 0.43, 0.51)), [Transform3D(valley_basis.scaled_local(Vector3(16, 0.2, 1040)), water_point)], 0)
	var piers: Array[Transform3D] = []
	for id in ["upper", "rescue", "finish"]:
		var track: SpatialTrack = spatial.tracks[id]
		for n in ceili(track.length / 28):
			var point := track.pose(n * 28).origin
			var height: float = point.y - floor_y - 0.8
			point.y = floor_y + height * 0.5
			piers.append(Transform3D(valley_basis.scaled_local(Vector3(1.4, height, 1.4)), point))
	_batch(environment_root, "BridgePiers", Vector3.ONE, deck, piers, 1000)

func _batch(parent: Node3D, label: String, size: Vector3, material: Material, poses: Array[Transform3D], range_end: float = 1100.0) -> void:
	super._batch(parent, label, size, material, poses, range_end)
	if label not in ["Bed", "Clamps", "ContactStructure", "NearMasses", "DistantPiers", "CoilStation", "Block", "ValleyWalls", "ValleyFloor", "BridgePiers"]: return
	var spatial := route as SpatialRoute
	for i in poses.size():
		# Fine bed pieces are retained: a loop must not be approximated by a giant solid box.
		var transform := global_transform.affine_inverse() * parent.global_transform * poses[i]
		var scale := transform.basis.get_scale()
		var half := size * scale * 0.5
		var rigid := Transform3D(transform.basis.orthonormalized(), transform.origin)
		var extent := rigid.basis.x.abs() * half.x + rigid.basis.y.abs() * half.y + rigid.basis.z.abs() * half.z
		spatial.camera_solids.append({"label": label, "inverse": rigid.affine_inverse(), "half": half, "bounds": AABB(rigid.origin - extent, extent * 2), "actor_block": false})
