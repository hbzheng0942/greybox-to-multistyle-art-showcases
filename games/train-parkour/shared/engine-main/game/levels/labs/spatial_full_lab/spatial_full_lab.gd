extends "res://levels/labs/controller_lab/controller_lab.gd"
## Functional masses, close reference geometry and contact surfaces share SupportFrames.
@export var geometry_step := 2.0
var soft_props: Dictionary = {}
@export_enum("stone", "steel") var visual_shell := "stone"
var visual_slots: Array[Dictionary] = []

func _build_gates() -> void:
	pass

func _build_track() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--shell=steel": visual_shell = "steel"
	var spatial := route as SpatialRoute
	var mastery := spatial.experience_revision == 2
	var deck := _material(Color(0.14, 0.21, 0.27))
	var silver := _material(Color(0.74, 0.87, 0.91))
	var cyan := _material(Color(0.04, 0.9, 0.78))
	cyan.emission_enabled = true
	cyan.emission = Color(0.01, 0.20, 0.17)
	var gold := _material(Color(1, 0.64, 0.09))
	var violet := _material(Color(0.65, 0.31, 0.93))
	var stone := _material(Color(0.31, 0.38, 0.42) if visual_shell == "steel" else Color(0.36, 0.31, 0.29))
	var dark := _material(Color(0.045, 0.075, 0.11))
	var tunnel_wall := _material(Color(0.09, 0.13, 0.17))
	tunnel_wall.emission_enabled = true
	tunnel_wall.emission = Color(0.018, 0.028, 0.038)
	var red := _material(Color(1, 0.18, 0.11))
	var tunnel_deck := _material(Color(0.20, 0.29, 0.35))
	tunnel_deck.emission_enabled = true
	tunnel_deck.emission = Color(0.035, 0.065, 0.08)
	var tunnel_rail := _material(Color(0.72, 0.88, 0.93))
	tunnel_rail.emission_enabled = true
	tunnel_rail.emission = Color(0.10, 0.18, 0.20)
	var tunnel_red := _material(Color(1, 0.22, 0.13))
	tunnel_red.emission_enabled = true
	tunnel_red.emission = Color(0.65, 0.05, 0.025)
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
			var tunnel_frames: Array[Transform3D] = []
			var guards: Array[Transform3D] = []
			var marks: Array[Transform3D] = []
			var pads: Array[Transform3D] = []
			var devices: Array[Transform3D] = []
			var enclosure: Array[Transform3D] = []
			var landscape: Array[Transform3D] = []
			var speed_markers: Array[Transform3D] = []
			var lamp: Array[Transform3D] = []
			for j in ceili(120.0 / geometry_step):
				var s := index * 120.0 + j * geometry_step
				if s >= track.length: break
				var span := minf(geometry_step, track.length - s)
				var pose := track.pose(s + span * 0.5)
				pose.origin -= chunk.position
				if mastery and j % 10 == 0 and track.enclosure == "open" and track.kind == "wide":
					for sign in [-1, 1]:
						var marker := pose.translated_local(Vector3(sign * (track.width_at(s) + 11.0), 2.7, 0))
						speed_markers.append(marker.scaled_local(Vector3(0.45, 5.4, 0.45)))
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
					var wall_x := track.enclosure_half_width - 0.5
					for sign in [-1, 1]:
						enclosure.append(pose.translated_local(Vector3(sign * wall_x, 6.5, 0)).scaled_local(Vector3(1.2, 14, span + 0.1)))
						if j % 4 == 0: lamp.append(pose.translated_local(Vector3(sign * 9.85, 5, 0)).scaled_local(Vector3(0.10, 0.3, 2.2)))
						if visual_shell == "steel" and j % 10 == 0: tunnel_frames.append(pose.translated_local(Vector3(sign * (wall_x - 0.8), 6.5, 0)).scaled_local(Vector3(0.65, 13.0, 0.8)))
					if visual_shell == "steel" and j % 10 == 0: tunnel_frames.append(pose.translated_local(Vector3(0, track.ceiling - 4.0, 0)).scaled_local(Vector3(track.enclosure_half_width * 2.0 - 2.0, 0.6, 0.8)))
					enclosure.append(pose.translated_local(Vector3(0, track.ceiling - 4.0, 0)).scaled_local(Vector3(track.enclosure_half_width * 2, 1, span + 0.1)))
					enclosure.append(pose.translated_local(Vector3(0, -0.9, 0)).scaled_local(Vector3(track.enclosure_half_width * 2, 1, span + 0.1)))
				# Preserve the release/receiver sight corridors: side masses must not
				# be emitted by an overlapping branch into another branch's camera.
				if j % 24 == 0 and track.enclosure != "tunnel" and track.kind not in ["inverted", "loop", "wall", "grind"] and not (mastery and track.id in ["drop", "rollout", "loop_entry"]) and not (track.id in ["canyon_safe", "canyon_fast_catch", "final_receiver", "final_upper_catch", "upper", "rescue"] and s < 600):
					for sign in [-1, 1]:
						var width := 14.0 + 4.0 * (1 + sin(s * 0.017 + sign))
						var mountain := track.chapter in ["02 CANYON", "06 FINAL YARD"]
						var height := 66.0 + 22.0 * (1 + sin(s * 0.013 + sign)) if mountain else ((44.0 + 14.0 * (1 + sin(s * 0.013 + sign))) if mastery else (28.0 + 11.0 * (1 + sin(s * 0.013 + sign))))
						var mass_offset := 70.0 if mastery and track.id in ["station_carve", "canyon_safe", "return_switchback", "final_receiver"] else (46.0 if mastery else 72.0)
						var at: Vector3 = track.pose(s).origin + track.pose(s).basis.x * sign * (mass_offset + 8.0 * sin(s * 0.02))
						at.y += (-34.0 + height * 0.5) if mastery else ((42.0 if mountain else -2.0) - height * 0.5)
						var mass_bounds := AABB(at - Vector3(width, height, 70) * 0.5, Vector3(width, height, 70))
						# Check the whole solid against all playable rails, including its
						# own curved source track. A centre-only check missed long block ends.
						var clear := _environment_clear_of_rails(spatial, mass_bounds) if mastery else _legacy_mass_clear(spatial, track, at, height, mass_bounds)
						if clear:
							landscape.append(Transform3D(Basis.IDENTITY.scaled(Vector3(width, height, 70)), at - chunk.position))
			_batch(chunk, "Bed", Vector3.ONE, violet if track.kind == "rescue" else (tunnel_deck if track.enclosure == "tunnel" else deck), beds, 650)
			_batch(chunk, "Rail", Vector3.ONE, gold if track.single_lane else (tunnel_rail if track.enclosure == "tunnel" else silver), rails, 650)
			_batch(chunk, "Ties", Vector3.ONE, dark, ties, 500)
			_batch(chunk, "Clamps", Vector3.ONE, silver, ribs, 550)
			_batch(chunk, "TunnelDecorFrames", Vector3.ONE, silver, tunnel_frames, 750)
			_batch(chunk, "EdgeCurbs", Vector3.ONE, silver, guards, 550)
			_batch(chunk, "Pickets", Vector3.ONE, violet if track.kind == "rescue" else cyan, marks, 650)
			_batch(chunk, "PulseArrows", Vector3.ONE, cyan, pads, 650)
			_batch(chunk, "ReleaseWindow", Vector3.ONE, gold, devices, 650)
			_batch(chunk, "ContactStructure", Vector3.ONE, tunnel_wall if track.enclosure == "tunnel" else stone, enclosure, 750)
			_batch(chunk, "TunnelLamps", Vector3.ONE, cyan, lamp, 650)
			_batch(chunk, "NearMasses", Vector3.ONE, stone, landscape, 800)
			if mastery: _batch(chunk, "NearSpeedMarkers", Vector3.ONE, silver, speed_markers, 550)
			if index % 2 == 0 and track.enclosure != "tunnel" and track.kind not in ["inverted", "loop"] and (not mastery or track.id not in ["carve", "wall"]):
				var support: Array[Transform3D] = []
				var anchor := track.pose(minf(track.length, index * 120.0 + 60.0))
				var foot_y := -45.0 if track.chapter.begins_with("01") else minf(-22.0, anchor.origin.y - 28.0)
				var support_height := anchor.origin.y - foot_y
				if support_height > 6.0:
					var deck_edge := track.width_at(minf(track.length, index * 120.0 + 60.0))
					# R2 side piers sit outside the full deck. A pier belonging to an
					# overpassing route must also clear the camera path of lower rails.
					var support_offset := deck_edge + 8.0 if mastery else deck_edge - 1.2
					for sign in [-1, 1]:
						var support_origin: Vector3 = anchor.origin + anchor.basis.x * sign * support_offset
						support_origin.y = foot_y + support_height * 0.5
						var pier_bounds := AABB(support_origin - Vector3(1.2, support_height * 0.5, 1.2), Vector3(2.4, support_height, 2.4))
						if mastery and not _environment_clear_of_rails(spatial, pier_bounds, track, Vector3(8.0, 12.0, 10.0)): continue
						support.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.4, support_height, 2.4)), support_origin - chunk.position))
					_batch(chunk, "TrackPiers", Vector3.ONE, deck, support, 850)
		for ob in track.obstacles:
			for lane in ob.lanes:
				var pose := track.pose(ob.s, lane * 4.4)
				var soft: bool = ob.get("kind", "block") == "soft"
				var beam: bool = ob.get("kind", "block") == "beam"
				var bottom: float = float(ob.get("bottom", 0.0)) if beam else 0.0
				var size := Vector3(1.3, ob.height, 1.3) if soft else Vector3(3, ob.height - bottom, 2)
				var prop_pose := pose.translated_local(Vector3(0, bottom + size.y * 0.5, 0))
				if soft:
					var key := spatial.obstacle_key(track, ob)
					var mesh: PrimitiveMesh
					if str(ob.get("group", "")).contains("cone"):
						var cone := CylinderMesh.new()
						cone.top_radius = 0.12
						cone.bottom_radius = 0.65
						cone.height = size.y
						mesh = cone
					else:
						var barrier := BoxMesh.new()
						barrier.size = size
						mesh = barrier
					mesh.material = orange
					var instance := MeshInstance3D.new()
					instance.name = "SoftProp_" + key.replace(":", "_") + "_" + str(lane)
					instance.mesh = mesh
					presentation.add_child(instance)
					instance.transform = prop_pose
					instance.set_meta("upright_transform", prop_pose)
					if not soft_props.has(key): soft_props[key] = []
					soft_props[key].append(instance)
				else:
					_batch(presentation, "LowBeam" if beam else "Block", Vector3.ONE, tunnel_red if track.enclosure == "tunnel" else red, [prop_pose.scaled_local(size)], 550)
				var preview := maxf(float(ob.get("preview_seconds", 1.8 if mastery else 2.0)) * (175.0 if mastery else 150.0), 170.0 if mastery else 150.0)
				for ratio: float in [1.0, 0.72, 0.48, 0.28]:
					var gap: float = preview * ratio
					var mark_pose := _approach_pose(spatial, track, ob.s - gap)
					_batch(presentation, "ApproachMarks", Vector3(3.5, 0.08, 3.8), tunnel_red if track.enclosure == "tunnel" else red, [mark_pose.translated_local(Vector3(lane * 4.4, 0.18, 0))], 550)
				var sign_pose := _approach_pose(spatial, track, ob.s - preview)
				var sign_side := signf(float(lane)) if lane != 0 else 1.0
				var edge := sign_side * (track.width_at(maxf(0, ob.s - preview)) + 3.0)
				_batch(presentation, "NoEntrySign", Vector3(2.6, 1.8, 0.20), tunnel_red if track.enclosure == "tunnel" else red, [sign_pose.translated_local(Vector3(edge, 4.4, 0))], 700)
				_batch(presentation, "NoEntryBar", Vector3(1.6, 0.20, 0.24), white, [sign_pose.translated_local(Vector3(edge, 4.4, 0))], 700)
		# Compact physical pictograms, not giant debug sentences across the whole screen.
		if track.id in ["wall", "inverted", "loop_entry", "exit_ramp", "grind", "cliff_lip"]:
			var at := 30.0
			var label := Label3D.new()
			label.text = "SPACE" if not track.release_windows.is_empty() else ("LOOP" if track.id == "loop_entry" else "A  /  D")
			if mastery and track.id in ["wall", "inverted", "grind"]:
				# Put the instruction in the actual action window, not behind the
				# arriving train. The icon, key and destination belong to one device.
				at = 78.0 if track.id == "wall" else (133.0 if track.id == "inverted" else 430.0)
				label.text = "SPACE  UP / CEILING" if track.id == "wall" else ("SPACE  / LOWER RAIL" if track.id == "inverted" else "SPACE  HOP / CYAN RELAY")
			label.font_size = 72
			label.pixel_size = 0.022
			label.modulate = Color(1, 0.77, 0.2)
			label.visibility_range_end = 430 if mastery else 300
			presentation.add_child(label)
			label.transform = track.pose(at).translated_local(Vector3(0, 8, 0))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7000, 6000)
	plane.material = _material(Color(0.12, 0.28, 0.32))
	ground.mesh = plane
	ground.position = Vector3(1000, -45, -400)
	environment_root.add_child(ground)
	if mastery:
		# The former 950 m world-aligned banks extended past station_start into
		# station_carve, which turns through the right bank and descends below it.
		# Keep the banks local to the straight platform and below its railbed.
		var opening: SpatialTrack = spatial.tracks.station_start
		var opening_mid := opening.pose(opening.length * 0.5)
		var bank_width := 68.0
		var bank_length := opening.length - 20.0
		var bank_y := minf(opening.pose(0).origin.y, opening.pose(opening.length).origin.y) - 17.0
		var station_banks: Array[Transform3D] = []
		for sign in [-1, 1]:
			var bank_at: Vector3 = opening_mid.origin + opening_mid.basis.x * sign * (opening.half_width + 12.0 + bank_width * 0.5)
			bank_at.y = bank_y - 1.0
			station_banks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(bank_width, 2.0, bank_length)), bank_at))
		_batch(environment_root, "StationGround", Vector3.ONE, _material(Color(0.25, 0.31, 0.32)), station_banks, 1100)
		# The first and second vertical catches share one cyan physical language.
		# All guides sit outside the legal deck; they never enlarge capture rules.
		var catch_guides: Array[Transform3D] = []
		var catch_gates: Array[Transform3D] = []
		for id in ["drop", "relay"]:
			var catch_track: SpatialTrack = spatial.tracks[id]
			var visible_end := 170.0 if id == "drop" else 275.0
			for index in ceili(visible_end / 8.0):
				var catch_pose := catch_track.pose(index * 8.0 + 4.0)
				for sign in [-1, 1]:
					catch_guides.append(catch_pose.translated_local(Vector3(sign * (catch_track.half_width - 0.35), 0.25, 0)).scaled_local(Vector3(0.36, 0.2, 8.0)))
			for gate_s in ([42.0] if id == "drop" else [112.0, 208.0]):
				var gate := catch_track.pose(gate_s)
				for sign in [-1, 1]:
					catch_gates.append(gate.translated_local(Vector3(sign * (catch_track.half_width + 2.8), 4.3, 0)).scaled_local(Vector3(0.7, 8.6, 0.7)))
				catch_gates.append(gate.translated_local(Vector3(0, 8.7, 0)).scaled_local(Vector3(catch_track.half_width * 2 + 6.2, 0.7, 0.7)))
				var catch_label := Label3D.new()
				catch_label.text = "LOWER CATCH" if id == "drop" else "RELAY CATCH"
				catch_label.font_size = 64
				catch_label.pixel_size = 0.02
				catch_label.modulate = Color(0.12, 1.0, 0.84)
				catch_label.visibility_range_end = 430
				presentation.add_child(catch_label)
				catch_label.transform = gate.translated_local(Vector3(0, 11.0, 0))
		_batch(presentation, "CatchRunway", Vector3.ONE, cyan, catch_guides, 650)
		_batch(presentation, "CatchGate", Vector3.ONE, cyan, catch_gates, 650)
		# The safe post-loop catch is a distinct right-hand gold rail. Mark its
		# physical trough, while keeping the higher left route readable as a choice.
		var grind_catch: SpatialTrack = spatial.tracks.grind
		var gold_guides: Array[Transform3D] = []
		for index in 16:
			var catch_s := 310.0 + float(index) * 7.0
			var catch_pose := grind_catch.pose(catch_s)
			for sign in [-1, 1]:
				gold_guides.append(catch_pose.translated_local(Vector3(sign * (grind_catch.width_at(catch_s) + 0.8), 0.25, 0)).scaled_local(Vector3(0.42, 0.3, 7.0)))
		for catch_s in [330.0, 390.0]:
			var catch_pose := grind_catch.pose(catch_s)
			for sign in [-1, 1]:
				gold_guides.append(catch_pose.translated_local(Vector3(sign * (grind_catch.width_at(catch_s) + 3.4), 4.5, 0)).scaled_local(Vector3(0.8, 9.0, 0.8)))
		_batch(presentation, "GoldGrindCatch", Vector3.ONE, gold, gold_guides, 650)
		# The inverted Space verb belongs to four short triangular pads on the
		# actual contact rail. Together with the gold release strip they cover its
		# entire legal window; the cyan receiver remains visible below each pad.
		var ceiling: SpatialTrack = spatial.tracks.inverted
		var release: Vector2 = ceiling.release_windows[0]
		var eject_gold := _material(Color(1.0, 0.51, 0.06))
		eject_gold.emission_enabled = true
		eject_gold.emission = Color(0.45, 0.16, 0.015)
		for pad_index in 4:
			var pad_start := release.x + float(pad_index) * 22.0
			var pad_length := minf(18.0, release.y - pad_start)
			if pad_length <= 0: continue
			for side in [-1, 0, 1]:
				var wedge := PrismMesh.new()
				wedge.size = Vector3(pad_length, 0.42 if side == 0 else 1.55, 4.8 if side == 0 else 0.65)
				wedge.left_to_right = 1.0
				wedge.material = eject_gold
				var eject_pad := MeshInstance3D.new()
				eject_pad.name = "InvertedEjectPad_%02d_%d" % [pad_index, side]
				eject_pad.mesh = wedge
				var side_offset := 0.0 if side == 0 else float(side) * (ceiling.half_width + 0.55)
				eject_pad.transform = ceiling.pose(pad_start + pad_length * 0.5).translated_local(Vector3(side_offset, 0.26 if side == 0 else 0.8, 0)).rotated_local(Vector3.UP, PI * 0.5)
				presentation.add_child(eject_pad)
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
		var point: Vector3 = base.origin + base.basis.x * sign * (45.0 if mastery else 28.0)
		var height := base.origin.y + 120
		point.y = height * 0.5 - 10
		station.append(Transform3D(Basis.IDENTITY.scaled(Vector3(4, height, 4)), point))
	station.append(base.translated_local(Vector3(0, 112, 0)).scaled_local(Vector3(96 if mastery else 60, 3, 3)))
	_batch(environment_root, "CoilStation", Vector3.ONE, gold, station, 1800)
	# Continuous outside frames explain the wall/ceiling/loop support without
	# placing a member in the three-lane or catch sight corridor.
	var vertical_frames: Array[Transform3D] = []
	for id in ["wall", "inverted"]:
		var action_track: SpatialTrack = spatial.tracks[id]
		for i in ceili(action_track.length / 34.0):
			var action_pose := action_track.pose(minf(action_track.length - 4.0, 12.0 + i * 34.0))
			var horizontal_forward := Vector3(-action_pose.basis.z.x, 0, -action_pose.basis.z.z).normalized()
			var horizontal_side := horizontal_forward.cross(Vector3.UP).normalized()
			var frame_basis := Basis(horizontal_side, Vector3.UP, -horizontal_forward)
			for sign in [-1, 1]:
				var post: Vector3 = action_pose.origin + horizontal_side * sign * (36.0 if mastery else 26.0)
				var base_y := -45.0
				var height := action_pose.origin.y + 13.0 - base_y
				post.y = base_y + height * 0.5
				vertical_frames.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.2, height, 2.2)), post))
				vertical_frames.append(Transform3D(frame_basis.scaled_local(Vector3(18, 1.6, 2.0)), action_pose.origin + horizontal_side * sign * (27.0 if mastery else 17.0) + Vector3.UP * 12.0))
				vertical_frames.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 8.0, 1.0)), action_pose.origin + horizontal_side * sign * (18.5 if mastery else 8.5) + Vector3.UP * 7.0))
	_batch(environment_root, "VerticalStationFrame", Vector3.ONE, silver, vertical_frames, 1250)
	var loop_ribs: Array[Transform3D] = []
	for i in ceili(loop.length / 14.0):
		var loop_pose := loop.pose(minf(loop.length - 1.0, float(i) * 14.0))
		for sign in [-1, 1]:
			loop_ribs.append(loop_pose.translated_local(Vector3(sign * 12.0, 0, 0)).scaled_local(Vector3(1.3, 1.3, 16.0)))
			if i % 2 == 0: loop_ribs.append(loop_pose.translated_local(Vector3(sign * 7.5, 0, 0)).scaled_local(Vector3(9.0, 0.9, 1.0)))
	_batch(environment_root, "LoopRibs", Vector3.ONE, gold, loop_ribs, 1250)
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
			if mastery:
				var underpass_corridor: SpatialTrack = spatial.tracks.underpass
				var nearest_underpass := underpass_corridor.pose(underpass_corridor.nearest(point)).origin
				if Vector2(point.x, point.z).distance_to(Vector2(nearest_underpass.x, nearest_underpass.z)) < 85.0: continue
			var cliff_bounds := AABB(point - Vector3(28, height, 68) * 0.5, Vector3(28, height, 68))
			if not mastery or _environment_clear_of_rails(spatial, cliff_bounds):
				cliffs.append(Transform3D(valley_basis.scaled_local(Vector3(28, height, 68)), point))
	_batch(environment_root, "ValleyWalls", Vector3.ONE, stone, cliffs, 1100)
	var floor_point := valley_frame.origin + valley_forward * 430 - valley_right * 40
	floor_point.y = floor_y - 3
	_batch(environment_root, "ValleyFloor", Vector3.ONE, _material(Color(0.24, 0.28, 0.25)), [Transform3D(valley_basis.scaled_local(Vector3(370, 6, 1050)), floor_point)], 0)
	var water_point := floor_point + Vector3.UP * 3.1 - valley_right * 15
	_batch(environment_root, "Riverbed", Vector3.ONE, _material(Color(0.10, 0.43, 0.51)), [Transform3D(valley_basis.scaled_local(Vector3(16, 0.2, 1040)), water_point)], 0)
	# The last flight needs a continuous valley volume beneath the catch. Keep
	# both banks well outside the train and camera corridors.
	var final_ramp: SpatialTrack = spatial.tracks.final_ramp
	var final_frame := final_ramp.pose(final_ramp.length)
	var final_forward := Vector3(-final_frame.basis.z.x, 0, -final_frame.basis.z.z).normalized()
	var final_right := final_forward.cross(Vector3.UP)
	var final_basis := Basis(final_right, Vector3.UP, -final_forward)
	var final_floor_y := final_frame.origin.y - 55.0
	var final_floor := final_frame.origin + final_forward * 510.0
	final_floor.y = final_floor_y - 3.0
	_batch(environment_root, "FinalFloor", Vector3.ONE, _material(Color(0.25, 0.30, 0.30)), [Transform3D(final_basis.scaled_local(Vector3(420, 6, 1120)), final_floor)], 0)
	var final_banks: Array[Transform3D] = []
	for i in 10:
		for sign in [-1, 1]:
			var height := 68.0 + 24.0 * (1.0 + sin(i * 0.84 + sign))
			var point: Vector3 = final_frame.origin + final_forward * (i * 110.0) + final_right * sign * (112.0 + 9.0 * sin(i * 0.6))
			point.y = final_floor_y + height * 0.5
			final_banks.append(Transform3D(final_basis.scaled_local(Vector3(48, height, 114)), point))
	_batch(environment_root, "FinalRidges", Vector3.ONE, stone, final_banks, 1400)
	var piers: Array[Transform3D] = []
	for id in ["upper", "rescue", "finish"]:
		var track: SpatialTrack = spatial.tracks[id]
		for n in ceili(track.length / 28):
			var point := track.pose(n * 28).origin
			var height: float = point.y - floor_y - 0.8
			point.y = floor_y + height * 0.5
			piers.append(Transform3D(valley_basis.scaled_local(Vector3(1.4, height, 1.4)), point))
	_batch(environment_root, "BridgePiers", Vector3.ONE, deck, piers, 1000)
	var yard: SpatialTrack = spatial.tracks.station_start
	var station_blocks: Array[Transform3D] = []
	for along in [75.0, 215.0, 355.0, 495.0]:
		var station_frame := yard.pose(along)
		for sign in [-1, 1]:
			station_blocks.append(station_frame.translated_local(Vector3(sign * 15, -0.35, 0)).scaled_local(Vector3(10, 0.7, 125)))
			station_blocks.append(station_frame.translated_local(Vector3(sign * 19, 5.5, 0)).scaled_local(Vector3(1.1, 11, 1.1)))
			station_blocks.append(station_frame.translated_local(Vector3(sign * 15, 11.0, 0)).scaled_local(Vector3(11, 0.9, 125)))
	_batch(environment_root, "StationPlatforms", Vector3.ONE, silver, station_blocks, 850)
	# A slower, readable destination after the final catch: both platforms have
	# foundations, posts and canopies while the centre running clearance stays open.
	var terminal: SpatialTrack = spatial.tracks.victory_run
	var terminal_blocks: Array[Transform3D] = []
	for along in ([65.0, 155.0] if mastery else [190.0, 330.0]):
		var terminal_frame := terminal.pose(along)
		for sign in [-1, 1]:
			terminal_blocks.append(terminal_frame.translated_local(Vector3(sign * 15, -0.35, 0)).scaled_local(Vector3(11, 0.7, 132)))
			for post_offset in [-52.0, 52.0]:
				terminal_blocks.append(terminal_frame.translated_local(Vector3(sign * 18, 7.5, post_offset)).scaled_local(Vector3(1.1, 15, 1.1)))
			terminal_blocks.append(terminal_frame.translated_local(Vector3(sign * 15, 15.0, 0)).scaled_local(Vector3(11, 1.0, 132)))
	_batch(environment_root, "TerminalStation", Vector3.ONE, silver, terminal_blocks, 1000)
	var finish_frame := terminal.pose(205 if mastery else 465)
	var finish_arch: Array[Transform3D] = []
	for sign in [-1, 1]:
		finish_arch.append(finish_frame.translated_local(Vector3(sign * 16, 9, 0)).scaled_local(Vector3(2, 18, 2)))
	finish_arch.append(finish_frame.translated_local(Vector3(0, 18, 0)).scaled_local(Vector3(34, 2, 2)))
	_batch(environment_root, "TerminalGate", Vector3.ONE, gold, finish_arch, 1000)
	# One structural landmark is visited at track height and then directly below.
	var hub: Array[Transform3D] = []
	var hub_base := (spatial.tracks.cliff_turn as SpatialTrack).pose((spatial.tracks.cliff_turn as SpatialTrack).length * 0.52) if mastery else loop.pose(0)
	for sign in [-1, 1]:
		# R2's lower return crosses the bridge width. Its supports sit beyond
		# the tunnel walls, never in the train's open lane.
		var pillar: Vector3 = hub_base.origin + (-hub_base.basis.z if mastery else hub_base.basis.x) * sign * (46.0 if mastery else 19.0) - Vector3.UP * 23.0
		hub.append(Transform3D(Basis.IDENTITY.scaled(Vector3(3.2, 46, 3.2)), pillar))
	hub.append(hub_base.translated_local(Vector3(0, -4, 0)).scaled_local(Vector3(46, 2.5, 96 if mastery else 18)))
	var under_bridge: SpatialTrack = spatial.tracks.underpass
	var cross_frame := under_bridge.pose(300 if mastery else 325)
	for offset in [-16.0, 16.0]:
		hub.append(cross_frame.translated_local(Vector3(0, 14.5 if mastery else 12.0, offset)).scaled_local(Vector3(21, 1.8, 1.8)))
		for side in [-1, 1]:
			hub.append(cross_frame.translated_local(Vector3(side * 9.7, 9.5 if mastery else 8.0, offset)).scaled_local(Vector3(0.8, 9.0 if mastery else 8.0, 0.8)))
	_batch(environment_root, "HubBridge", Vector3.ONE, gold, hub, 1200)
	# The same bridge gets a tall, sparse silhouette that can be picked out from
	# the opening station rather than introducing a disconnected fake landmark.
	var beacon: Array[Transform3D] = []
	var beacon_top := hub_base.origin.y + 300.0
	var column_height := beacon_top + 45.0
	for x in [-110.0, 110.0]:
		for z in [-110.0, 110.0]:
			var foot := hub_base.origin + Vector3(x, -45.0 + column_height * 0.5 - hub_base.origin.y, z)
			beacon.append(Transform3D(Basis.IDENTITY.scaled(Vector3(7, column_height, 7)), foot))
	for side in [-110.0, 110.0]:
		beacon.append(Transform3D(Basis.IDENTITY.scaled(Vector3(225, 7, 7)), hub_base.origin + Vector3(0, 300, side)))
		beacon.append(Transform3D(Basis.IDENTITY.scaled(Vector3(7, 7, 225)), hub_base.origin + Vector3(side, 300, 0)))
	_batch(environment_root, "HubBeacon", Vector3.ONE, gold, beacon, 6000)
	spatial.index_camera_solids()

func _approach_pose(spatial: SpatialRoute, track: SpatialTrack, distance: float) -> Transform3D:
	if distance >= 0: return track.pose(distance)
	var candidate: SpatialTrack = null
	for previous: SpatialTrack in spatial.tracks.values():
		if previous.next.has(track.id) and (candidate == null or previous.length > candidate.length): candidate = previous
	return candidate.pose(candidate.length + distance) if candidate != null and candidate.length + distance >= 0 else track.pose(0)

func _legacy_mass_clear(spatial: SpatialRoute, source: SpatialTrack, at: Vector3, height: float, bounds: AABB) -> bool:
	for other: SpatialTrack in spatial.tracks.values():
		if other == source or not other.bounds.grow(55).intersects(bounds): continue
		var near := other.pose(other.nearest(at)).origin
		if Vector2(at.x, at.z).distance_to(Vector2(near.x, near.z)) < 58 and absf(at.y - near.y) < height * 0.5 + 20:
			return false
	return true

func _environment_clear_of_rails(spatial: SpatialRoute, bounds: AABB, source: SpatialTrack = null, clearance: Vector3 = Vector3(5.0, 4.0, 8.0)) -> bool:
	# Only scenery goes through this filter. It must not alter rail contact or
	# substitute a hidden collider. Sample full block extents against each lane.
	var swept := AABB(bounds.position - clearance, bounds.size + clearance * 2.0)
	for other: SpatialTrack in spatial.tracks.values():
		if other == source: continue
		if not other.bounds.grow(12.0).intersects(swept): continue
		for step in ceili(other.length / 3.0) + 1:
			var s := minf(other.length, step * 3.0)
			for lane in other.lanes():
				var rail_pose := other.pose(s, lane * 4.4)
				var body_point := rail_pose.origin + rail_pose.basis.y * 2.4
				if swept.has_point(body_point): return false
	return true

func set_soft_prop_visible(key: String, shown: bool) -> void:
	for prop: MeshInstance3D in soft_props.get(key, []):
		var upright: Transform3D = prop.get_meta("upright_transform")
		prop.transform = upright if shown else upright.translated_local(Vector3(0, -0.65, 0)).rotated_local(Vector3.FORWARD, 1.25)

func _batch(parent: Node3D, label: String, size: Vector3, material: Material, poses: Array[Transform3D], range_end: float = 1100.0) -> void:
	var display_poses := poses
	if visual_shell == "steel" and label in ["NearMasses", "DistantPiers"]:
		display_poses = []
		for pose in poses:
			for x in [-0.43, 0.43]:
				for z in [-0.43, 0.43]:
					display_poses.append(pose * Transform3D(Basis.IDENTITY.scaled(Vector3(0.12, 1, 0.12)), Vector3(x, 0, z)))
			display_poses.append(pose * Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.08, 1)), Vector3(0, 0.46, 0)))
	super._batch(parent, label, size, material, display_poses, range_end)
	if not poses.is_empty() and label in ["NearMasses", "DistantPiers", "CoilStation", "VerticalStationFrame", "LoopRibs", "ValleyWalls", "ValleyFloor", "FinalRidges", "FinalFloor", "BridgePiers", "TrackPiers", "HubBridge", "HubBeacon", "StationGround", "StationPlatforms", "TerminalStation", "TerminalGate"]:
		for i in poses.size():
			var pose := poses[i]
			var dimensions := pose.basis.get_scale() * size
			var id := str(parent.name) + ":" + label + ":" + str(i)
			var asset_id := "m1.7r/" + visual_shell + "/" + label.to_snake_case()
			var asset_color := str((material as BaseMaterial3D).albedo_color) if material is BaseMaterial3D else "uncolored"
			visual_slots.append({"id": id, "slot": label, "local_transform": {"origin": [pose.origin.x, pose.origin.y, pose.origin.z], "basis_x": [pose.basis.x.x, pose.basis.x.y, pose.basis.x.z], "basis_y": [pose.basis.y.x, pose.basis.y.y, pose.basis.y.z], "basis_z": [pose.basis.z.x, pose.basis.z.y, pose.basis.z.z]}, "functional_envelope_m": [dimensions.x, dimensions.y, dimensions.z], "camera_corridor": "retain registered solid envelope", "slot_fingerprint": (id + str(pose) + str(dimensions)).sha256_text(), "asset_id": asset_id, "asset_version_hash": (asset_id + "|procedural-v2|" + str(size) + "|" + asset_color).sha256_text()})
	if label not in ["Bed", "Clamps", "ContactStructure", "NearMasses", "DistantPiers", "CoilStation", "VerticalStationFrame", "LoopRibs", "Block", "LowBeam", "ValleyWalls", "ValleyFloor", "BridgePiers", "TrackPiers", "TrackBraces", "HubBridge", "HubBeacon", "StationGround", "StationPlatforms", "TerminalStation", "TerminalGate"]: return
	var spatial := route as SpatialRoute
	for i in poses.size():
		# Fine bed pieces are retained: a loop must not be approximated by a giant solid box.
		var transform := global_transform.affine_inverse() * parent.global_transform * poses[i]
		var scale := transform.basis.get_scale()
		var half := size * scale * 0.5
		var rigid := Transform3D(transform.basis.orthonormalized(), transform.origin)
		var extent := rigid.basis.x.abs() * half.x + rigid.basis.y.abs() * half.y + rigid.basis.z.abs() * half.z
		spatial.camera_solids.append({"label": label, "inverse": rigid.affine_inverse(), "half": half, "bounds": AABB(rigid.origin - extent, extent * 2), "actor_block": false})
