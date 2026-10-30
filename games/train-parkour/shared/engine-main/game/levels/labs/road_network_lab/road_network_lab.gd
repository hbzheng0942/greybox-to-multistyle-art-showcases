extends "res://levels/labs/controller_lab/controller_lab.gd"
## Chunked instancing; the same segment data drives every visible support and hazard.

func _build_gates() -> void:
	pass


func _build_track() -> void:
	var network := route as NetworkRoute
	var deck := _material(Color(0.20, 0.27, 0.32))
	var rail := _material(Color(0.8, 0.89, 0.91))
	var cyan := _material(Color(0.06, 0.88, 0.81))
	var gold := _material(Color(1, 0.64, 0.1))
	var red := _material(Color(0.97, 0.19, 0.13))
	var violet := _material(Color(0.65, 0.43, 0.97))
	var stone := _material(Color(0.30, 0.25, 0.23))
	var tunnel_shell := _material(Color(0.08, 0.12, 0.16))
	var light := _material(Color(0.15, 0.85, 0.92))
	light.emission_enabled = true
	light.emission = Color(0.1, 0.5, 0.7)
	var structure := _material(Color(0.32, 0.42, 0.48))
	for segment: RoadSegment in network.segments.values():
		for chunk_index in ceili(segment.length / 180.0):
			var chunk := Node3D.new()
			chunk.name = segment.id + "_%d" % chunk_index
			presentation.add_child(chunk)
			chunk.position = segment.pose(chunk_index * 180).origin
			var beds: Array[Transform3D] = []
			var rails: Array[Transform3D] = []
			var marks: Array[Transform3D] = []
			var pads: Array[Transform3D] = []
			var launch: Array[Transform3D] = []
			var early_launch: Array[Transform3D] = []
			var frames: Array[Transform3D] = []
			var cliffs: Array[Transform3D] = []
			var shell: Array[Transform3D] = []
			var lights: Array[Transform3D] = []
			var kickers: Array[Transform3D] = []
			for i in 45:
				var s := chunk_index * 180.0 + i * 4.0
				if s >= segment.length: break
				var span := minf(4, segment.length - s)
				var pose := segment.pose(s + span * 0.5)
				pose.origin -= chunk.position
				beds.append(pose.translated_local(Vector3(0, -0.4, 0)).scaled_local(Vector3(segment.half_width * 2, 0.65, span + 0.03)))
				for lane in segment.lanes():
					for side in [-1, 1]:
						rails.append(pose.translated_local(Vector3(lane * 4.4 + side * (0.25 if segment.support == "grind" else 0.72), 0.04, 0)).scaled_local(Vector3(0.16, 0.18, span)))
				for pad in segment.boosts:
					if s >= pad.start and s <= pad.end:
						pads.append(pose.translated_local(Vector3(pad.lane * 4.4, 0.15, 0)).scaled_local(Vector3(3.0, 0.1, 1.6)))
				if segment.choice == "timing" and s >= 175 and s <= 189:
					early_launch.append(pose.translated_local(Vector3(0, 0.16, 0)).scaled_local(Vector3(segment.half_width * 1.5, 0.1, 0.7)))
				if segment.launch_at(s) and not (segment.choice == "timing" and s < 220):
					launch.append(pose.translated_local(Vector3(0, 0.16, 0)).scaled_local(Vector3(minf(segment.half_width * 1.5, 9), 0.1, 0.7)))
				if segment.launch_impulse > 0 and segment.launch_at(s):
					var device_side := 0.0 if segment.launcher_lane == 99 else segment.launcher_lane * 4.4
					kickers.append(pose.translated_local(Vector3(device_side, -0.1, 0)).scaled_local(Vector3(3.3, 0.4, span)))
					for side in [-1, 1]:
						kickers.append(pose.translated_local(Vector3(device_side + side * 1.9, 0.5, 0)).scaled_local(Vector3(0.45, 1.0, 0.45)))
				if segment.enclosure == "canyon" or segment.enclosure == "gallery":
					if i % 6 == 0:
						for side in [-1, 1]:
							var height := 62.0 + 18.0 * sin(s * 0.024 + side)
							cliffs.append(pose.translated_local(Vector3(side * (19.0 + 3 * sin(s * 0.013)), height * 0.5 - 25, 0)).scaled_local(Vector3(8, height, 27)))
				if segment.enclosure == "tunnel" or (segment.enclosure == "gallery" and chunk_index % 3 == 1):
					for side in [-1, 1]:
						shell.append(pose.translated_local(Vector3(side * 11.6, 7.5, 0)).scaled_local(Vector3(1.8, 16, span + 0.1)))
						if i % 2 == 0: lights.append(pose.translated_local(Vector3(side * 10.6, 6, 0)).scaled_local(Vector3(0.15, 0.3, 2.0)))
					shell.append(pose.translated_local(Vector3(0, 15.6, 0)).scaled_local(Vector3(25, 1.2, span + 0.1)))
					shell.append(pose.translated_local(Vector3(0, -0.85, 0)).scaled_local(Vector3(25, 0.8, span + 0.1)))
				if i % 4 == 0:
					for side in [-1, 1]: marks.append(pose.translated_local(Vector3(side * (segment.half_width + 0.5), 0.8, 0)).scaled_local(Vector3(0.2, 1.6, 0.3)))
				if i % 9 == 0 and segment.support == "wide":
					for side in [-1, 1]: frames.append(pose.translated_local(Vector3(side * 12.5, -6, 0)).scaled_local(Vector3(1.0, 23, 1.3)))
			_batch(chunk, "Support", Vector3.ONE, violet if segment.id.contains("rescue") else deck, beds)
			_batch(chunk, "Rails", Vector3.ONE, gold if segment.support == "grind" else rail, rails)
			_batch(chunk, "Pickets", Vector3.ONE, violet if segment.id.contains("rescue") else cyan, marks)
			_batch(chunk, "BoostSurface", Vector3.ONE, cyan, pads)
			_batch(chunk, "LaunchWindow", Vector3.ONE, gold, launch)
			_batch(chunk, "EarlyLowWindow", Vector3.ONE, violet, early_launch)
			_batch(chunk, "NearStructure", Vector3.ONE, structure, frames)
			_batch(chunk, "CanyonWalls", Vector3.ONE, stone, cliffs, 900)
			_batch(chunk, "TunnelShell", Vector3.ONE, tunnel_shell, shell, 1000)
			_batch(chunk, "TunnelStrips", Vector3.ONE, light, lights)
			_batch(chunk, "PoweredKickers", Vector3.ONE, gold, kickers)
		for obstacle in segment.obstacles:
			var is_beam: bool = obstacle.get("kind", "block") == "beam"
			for lane in obstacle.lanes:
				var h: float = obstacle.height
				var y: float = obstacle.bottom + h * 0.5 if is_beam else h * 0.5
				var pose := segment.pose(obstacle.s, lane * 4.4)
				_batch(presentation, "LowBeam" if is_beam else "Barrier", Vector3(3.0, h, 2), red if h > 2 or is_beam else gold, [pose.translated_local(Vector3(0, y, 0))])
				for ahead in [35, 55, 85, 120]:
					_batch(presentation, "Warning", Vector3(2.5, 0.08, 0.6), red if is_beam or h > 2 else gold, [segment.pose(obstacle.s - ahead, lane * 4.4).translated_local(Vector3(0, 0.13, 0))])
		# Signs at entry and before decisions, no billboards across the flight corridor.
		for s in [40.0, maxf(80, segment.length - 210)]:
			var label := Label3D.new()
			label.text = segment.title
			label.font_size = 48
			label.pixel_size = 0.025
			label.modulate = Color(0.78, 1, 0.94)
			presentation.add_child(label)
			label.transform = segment.pose(s).translated_local(Vector3(0, 14, 0))
			label.visibility_range_end = 330
	var plane := PlaneMesh.new()
	plane.size = Vector2(14000, 18000)
	plane.material = _material(Color(0.12, 0.21, 0.25))
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0, -180, -2500)
	environment_root.add_child(ground)
	# One immutable bridge/tower landmark, encountered on its deck and below it.
	var landmarks: Array[Transform3D] = []
	for x in [-32, 32]:
		landmarks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(5, 180, 6)), Vector3(x, 35, -600 - signf(x) * 30)))
	landmarks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(70, 4, 8)), Vector3(0, 126, -600)))
	_batch(environment_root, "TwinTowerLandmark", Vector3.ONE, gold, landmarks, 0)
