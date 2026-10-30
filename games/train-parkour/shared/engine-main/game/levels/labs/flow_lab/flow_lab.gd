extends "res://levels/labs/controller_lab/controller_lab.gd"
## Geometry is derived from exactly the same course that resolves gameplay.


func _build_gates() -> void:
	pass


func _build_track() -> void:
	var course := (route as FlowRoute).course
	var deck := _material(Color(0.19, 0.25, 0.30))
	var silver := _material(Color(0.67, 0.81, 0.84))
	var gold := _material(Color(1.0, 0.63, 0.07))
	var cyan := _material(Color(0.06, 0.85, 0.82))
	var red := _material(Color(0.95, 0.16, 0.12))
	var white := _material(Color(0.94, 0.97, 0.96))
	var dark := _material(Color(0.08, 0.14, 0.19))
	var concrete := _material(Color(0.29, 0.39, 0.43))
	for index in range(ceili(route.length / 180.0)):
		var chunk := Node3D.new()
		chunk.name = "FlowChunk_%02d" % index
		presentation.add_child(chunk)
		chunk.position = _level_pose(index * 180.0).origin
		var decks: Array[Transform3D] = []
		var rails: Array[Transform3D] = []
		var ties: Array[Transform3D] = []
		var trims: Array[Transform3D] = []
		var frames: Array[Transform3D] = []
		var takeoff: Array[Transform3D] = []
		var landing: Array[Transform3D] = []
		for step in range(90):
			var s := index * 180.0 + step * 2.0
			if s >= route.length: break
			var a := s
			var b := minf(s + 2.0, route.length)
			for gap in course.jumps:
				if a < gap.start: b = minf(b, gap.start)
				elif a < gap.end: a = maxf(a, gap.end)
			if a >= b: continue
			var middle := (a + b) * 0.5
			var span := b - a
			var pose := _level_pose(middle)
			pose.origin -= chunk.position
			for lane in route.lanes_at(middle):
				var fork := s >= course.fork_start and s < course.fork_end
				var width := course.deck_width(middle, lane)
				decks.append(pose.translated_local(Vector3(lane * 4.4, -0.42, 0)).scaled_local(Vector3(width, 0.65, span)))
				for side in [-1, 1]:
					rails.append(pose.translated_local(Vector3(lane * 4.4 + side * 0.72, 0.04, 0)).scaled_local(Vector3(1, 1, span / 2.0)))
				ties.append(pose.translated_local(Vector3(lane * 4.4, -0.04, 0)))
				for jump in course.jumps:
					if s >= jump.start - jump.window and s < jump.start and step % 4 == 0:
						takeoff.append(pose.translated_local(Vector3(lane * 4.4, 0.07, 0)))
					if s >= jump.end and s < jump.end + 45.0 and step % 3 == 0:
						landing.append(pose.translated_local(Vector3(lane * 4.4, 0.07, 0)))
				if fork and lane == 1 and step % 4 == 0:
					landing.append(pose.translated_local(Vector3(4.4, 0.07, 0)))
			if route.has_track(s) and step % 6 == 0:
				for side in [-1, 1]:
					trims.append(pose.translated_local(Vector3(side * 7.3, 1.0, 0)))
			var enclosed := s < 280 or (s > 330 and s < 490) or (s > 1220 and s < 1410) or s > 1710
			if enclosed and step % 9 == 0:
				for side in [-1, 1]:
					frames.append(pose.translated_local(Vector3(side * 12.5, 8.5, 0)).scaled_local(Vector3(1.5, 18, 3)))
				# High crossbeams keep the camera and jump arcs clear.
				if s < 280 or s > 1710:
					frames.append(pose.translated_local(Vector3(0, 18, 0)).scaled_local(Vector3(26, 1, 2)))
		_batch(chunk, "RailBeds", Vector3.ONE, deck, decks)
		_batch(chunk, "Rails", Vector3(0.17, 0.18, 2.0), silver, rails)
		_batch(chunk, "Ties", Vector3(2.2, 0.10, 0.3), dark, ties)
		_batch(chunk, "EdgePickets", Vector3(0.20, 2, 0.5), cyan, trims)
		_batch(chunk, "NearFrames", Vector3.ONE, concrete, frames)
		_batch(chunk, "LaunchStrips", Vector3(3.2, 0.10, 0.65), gold, takeoff)
		_batch(chunk, "CaptureStrips", Vector3(2.6, 0.10, 0.65), cyan, landing)
	for obstacle in course.obstacles:
		for lane in obstacle.lanes:
			var pose := _level_pose(obstacle.s)
			var h: float = obstacle.height
			_batch(presentation, "Barrier", Vector3(2.5, h, 2.0), gold if h < 2 else red, [pose.translated_local(Vector3(lane * 4.4, h * 0.5, 0))])
			for y in [0.6, h - 0.45]:
				_batch(presentation, "WarningBars", Vector3(2.6, 0.25, 0.12), white, [pose.translated_local(Vector3(lane * 4.4, y, 1.07))])
			# Repeated approach marks live on the blocked lane, not across the view.
			for offset in [30, 45, 60, 90]:
				if not route.lanes_at(obstacle.s - offset).has(lane): continue
				var mark := _level_pose(obstacle.s - offset)
				_batch(presentation, "Approach", Vector3(2.2, 0.08, 0.5), gold if h < 2 else red, [mark.translated_local(Vector3(lane * 4.4, 0.08, 0))])
	for turn in course.turns:
		for s in range(int(turn.start) - 36, int(turn.end), 18):
			var pose := _level_pose(s)
			for side in [-1, 1]:
				var at := pose.translated_local(Vector3(side * 8.0, 2.5, 0))
				_batch(presentation, "TurnSign", Vector3(1.5, 1.6, 0.2), gold, [at])
				var label := Label3D.new()
				label.text = ">" if turn.direction > 0 else "<"
				label.font_size = 100
				label.pixel_size = 0.015
				label.modulate = Color(0.04, 0.06, 0.08)
				presentation.add_child(label)
				label.transform = at.translated_local(Vector3(0, 0, 0.15))
				label.visibility_range_begin = 15
				label.visibility_range_end = 220
	_build_horizon(concrete)
