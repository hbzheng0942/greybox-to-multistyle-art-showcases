extends RefCounted
## One shared city for the low/high finish routes, followed by the original open-centre terminal.
var stats: Dictionary = {}

func build(ctx: RefCounted, region: Dictionary) -> Dictionary:
	assert(str(region.id) == "N09")
	ctx.use_scene("finale")
	stats = {"near_city_lots": 0, "lower_city_lots": 0, "castle_landmarks": 0, "terminal_bays": 0, "lanterns": 0, "physical_terminal_gate": 0}
	_city(ctx)
	_landmarks(ctx)
	_terminal(ctx)
	stats["shared_routes"] = ["final_receiver", "final_upper_catch", "final_upper"]
	stats["terminal_structure_source"] = "spatial_full_lab TerminalStation/TerminalGate; victory_run side platforms/canopies and s205 gate"
	stats["ground_source"] = "shared continuous field"
	return stats

func _foundation(ctx: RefCounted, floor_pose: Transform3D, width: float, depth: float, key: String) -> void:
	# Embed the footing below the shared triangulated slope across its whole footprint.
	var embed: float = clampf(maxf(width, depth) * 0.12, 2.0, 8.0)
	var bottom: float = ctx.ground_y(floor_pose.origin) - embed
	var height: float = floor_pose.origin.y - bottom
	if height <= 0.0: return
	ctx._at(floor_pose, Vector3(0, -height * 0.5, 0), Vector3(width, height, depth), key)
	ctx._at(floor_pose, Vector3(0, -0.35, 0), Vector3(width + 0.7, 0.7, depth + 0.7), "stone")
	for side: float in [-1.0, 1.0]:
		ctx._at(floor_pose, Vector3(side * width * 0.41, -height * 0.51, 0), Vector3(1.3, height * 0.98, depth + 0.9), "violet")

func _city(ctx: RefCounted) -> void:
	var index := 0
	# A single physical street is shared by the lower and upper rail; generous safe
	# setbacks are tested as oriented envelopes rather than discarded at road bends.
	for id: String in ["final_approach", "final_receiver"]:
		var track: SpatialTrack = ctx.route.tracks[id]
		for side: float in [-1.0, 1.0]:
			var along := 18.0
			while along < track.length - 8.0:
				var broad: bool = index % 5 == 3
				var width: float = 61.0 if broad else 34.0
				var depth: float = 39.0 if broad else (43.0 + float(index % 3) * 2.0)
				var height: float = 40.0 if broad else 60.0
				var selected := Transform3D.IDENTITY
				var found := false
				for setback: float in [48.0, 57.0, 69.0, 83.0]:
					var candidate: Transform3D = ctx.upright_pose(id, along, side * setback)
					candidate.origin.y = maxf(candidate.origin.y - 18.0, ctx.ground_y(candidate.origin) + 4.0)
					var size := Vector3(depth + 2.0, height + 3.0, width + 2.0)
					if ctx.can_place(candidate.translated_local(Vector3(0, size.y * 0.5, 0)), size, 4.0):
						selected = candidate; found = true; break
				if found:
					var lot_key := "finale_city_lot_" + str(roundi(selected.origin.x / 14.0)) + "_" + str(roundi(selected.origin.z / 14.0))
					if ctx.claim(lot_key):
						var house: Node3D = ctx.place_model("h07_facade_b" if broad else "h07_facade_a", selected, Vector3(depth, height, width), -side * PI / 2.0, "h07_finale_facade_" + str(index), 1100.0)
						if house != null:
							var achieved: Array = ctx.models.fits[-1].achieved_size_m
							_foundation(ctx, selected, float(achieved[0]) + 0.4, float(achieved[2]) + 0.4, "violet")
							var face: float = -side * (float(achieved[0]) * 0.5 + 1.4)
							_lantern(ctx, selected.translated_local(Vector3(face, 16.0, 0)), "street_" + str(index))
							ctx._at(selected, Vector3(face + side * 0.7, 19.5, 0), Vector3(2.4, 0.3, 0.3), "ink")
							ctx.add_light(selected.translated_local(Vector3(face - side * 5.0, 22.0, 0)).origin, 46.0, 44.0)
							stats.near_city_lots += 1
				along += 55.0 if broad else 34.0
				index += 1
	# The near street is backed by two staggered roof districts, not isolated towers
	# standing on a featureless plane. Both are the same physical town seen from above.
	for layer in 2:
		for i in 23:
			for side: float in [-1.0, 1.0]:
				var along: float = 8.0 + i * 43.0 + layer * 21.0
				var pose: Transform3D = ctx.ground_pose("final_receiver", along, side * (113.0 + layer * 57.0 + float(i % 3) * 4.0))
				pose.origin.y += 3.0
				var height: float = 38.0 + float((i + layer) % 4) * 7.0
				var size := Vector3(37.0, height + 17.0, 43.0)
				if not ctx.can_place(pose.translated_local(Vector3(0, size.y * 0.5, 0)), size, 4.0): continue
				_foundation(ctx, pose, 33.5, 39.5, "violet")
				ctx._city_house(pose, side, 39.0, 33.0, height, i + layer * 31 + 50, false)
				_district_windows(ctx, pose, side, height, i + layer)
				if (i + layer) % 3 == 0:
					ctx._mural(pose.translated_local(Vector3(-side * 16.75, height * 0.43, 0)), side, 8.5, height * 0.52, "finale_district_ghost")
				stats.lower_city_lots += 1

func _district_windows(ctx: RefCounted, pose: Transform3D, street_side: float, height: float, index: int) -> void:
	# The upper branch curves around this same district and sees its end/rear walls.
	# Put real window reveals on those faces, rather than exposing blank proxy backs.
	var rows: int = maxi(3, floori((height - 9.0) / 9.0))
	for row in rows:
		var y: float = 6.0 + row * 9.0
		for side: float in [-1.0, 1.0]:
			var end: Transform3D = pose.translated_local(Vector3(0, y, side * 19.68))
			end.basis = end.basis * Basis(Vector3.UP, PI / 2.0)
			for column: float in [-9.0, 0.0, 9.0]:
				ctx._gothic_window(end.translated_local(Vector3(0, 0, column)), side, 3.7, 6.0, "window_dim" if (row + index) % 3 else "window")
		for z: float in [-10.0, 10.0]:
			ctx._gothic_window(pose.translated_local(Vector3(street_side * 16.7, y, z)), -street_side, 3.2, 5.7, "window_dim")
	for y: float in [height - 0.8, height * 0.48]:
		ctx._at(pose, Vector3(0, y, 0), Vector3(34.0, 0.5, 40.0), "stone")

func _landmarks(ctx: RefCounted) -> void:
	var sites: Array = [
		["final_ramp", 30.0, -112.0, 108.0],
		["final_receiver", 340.0, 126.0, 124.0],
		["final_receiver", 735.0, -118.0, 113.0],
		["victory_run", 218.0, 96.0, 118.0]
	]
	for i in sites.size():
		var row: Array = sites[i]
		var pose: Transform3D = ctx.ground_pose(str(row[0]), float(row[1]), float(row[2]))
		pose.origin.y += 9.0
		var envelope := Vector3(72, float(row[3]), 48)
		if not ctx.can_place(pose.translated_local(Vector3(0, envelope.y * 0.5, 0)), envelope, 10.0): continue
		_foundation(ctx, pose, 74.0, 50.0, "violet")
		var node: Node3D = ctx.place_model("h07_castle_keep", pose, envelope, 0.08 if i % 2 == 0 else PI - 0.08, "h07_finale_shared_castle_" + str(i), 1550.0)
		if node != null:
			stats.castle_landmarks += 1
			ctx.add_light(pose.translated_local(Vector3(0, 18, 28)).origin, 40.0, 48.0)
	# A destination skyline continues beyond the functional finish instead of ending at a blank plane.
	var clock: Transform3D = ctx.upright_pose("victory_run", 220.0, -67.0).translated_local(Vector3(0, 0, -85.0))
	clock.origin.y = ctx.ground_y(clock.origin) + 10.0
	if ctx.can_place(clock.translated_local(Vector3(0, 71, 0)), Vector3(48, 142, 48), 8.0):
		_foundation(ctx, clock, 49, 49, "violet")
		ctx.place_model("h07_clocktower", clock, Vector3(46, 142, 46), 0.0, "h07_finale_arrival_clock", 1800.0)
	for i in 7:
		var pose: Transform3D = ctx.upright_pose("victory_run", 220.0, -180.0 + i * 57.0).translated_local(Vector3(0, 0, -150.0 - float(i % 2) * 35.0))
		pose.origin.y = ctx.ground_y(pose.origin) + 5.0
		var envelope := Vector3(49, 82 + float(i % 3) * 6.0, 70)
		if not ctx.can_place(pose.translated_local(Vector3(0, envelope.y * 0.5, 0)), envelope, 8.0): continue
		# Destination facades face the approaching train; side-only windows would
		# expose a blank rear wall at the end of the station's central perspective.
		var house: Node3D = ctx.place_model("h07_facade_a", pose, envelope, 0.0, "h07_terminal_destination_" + str(i), 1400.0)
		if house != null:
			var achieved: Array = ctx.models.fits[-1].achieved_size_m
			_foundation(ctx, pose, float(achieved[0]) + 0.4, float(achieved[2]) + 0.4, "violet")
			ctx.add_light(pose.translated_local(Vector3(0, 26, float(achieved[2]) * 0.5 + 5.0)).origin, 42, 45)

func _terminal(ctx: RefCounted) -> void:
	if not ctx.claim("victory_run_double_platform_terminal"): return
	var track: SpatialTrack = ctx.route.tracks.victory_run
	var pitch: float = track.length / 22.0
	for i in 22:
		var pose: Transform3D = ctx.upright_pose("victory_run", (i + 0.5) * pitch)
		for side: float in [-1.0, 1.0]:
			var platform: Transform3D = pose.translated_local(Vector3(side * 15.0, -0.7, 0))
			_foundation(ctx, platform, 11.0, pitch + 0.035, "violet")
			ctx._at(pose, Vector3(side * 15, -0.3, 0), Vector3(11, 0.8, pitch + 0.04), "stone")
			ctx._at(pose, Vector3(side * 9.6, 0.2, 0), Vector3(0.38, 0.15, pitch + 0.04), "ochre")
			ctx._at(pose, Vector3(side * 15, 15.2, 0), Vector3(11.6, 1.4, pitch + 0.04), "roof")
			ctx._at(pose, Vector3(side * 9.3, 14.8, 0), Vector3(0.55, 1.3, pitch + 0.04), "stone")
			ctx._at(pose, Vector3(side * 9.0, 15.55, 0), Vector3(0.18, 0.18, pitch + 0.04), "edge")
			for k in 3:
				ctx._at(pose, Vector3(side * (11.1 + k * 3.5), 14.42, 0), Vector3(3.15, 0.24, pitch - 0.6), "soffit")
			ctx._at(pose, Vector3(side * 15, 14.2, -pitch * 0.48), Vector3(11.1, 0.5, 0.42), "ink")
			ctx._at(pose, Vector3(side * 21.4, 6.8, 0), Vector3(1.5, 14.4, pitch + 0.04), "plum" if i % 4 else "violet")
			for height in [1.0, 13.0]: ctx._at(pose, Vector3(side * 20.55, height, 0), Vector3(0.35, 0.5, pitch + 0.04), "stone")
			if i % 4 == 1:
				ctx._mural(pose.translated_local(Vector3(side * 20.62, 7.2, 0)), side, 6.6, 12.4, "terminal_ghost_paint")
			else:
				ctx._gothic_window(pose.translated_local(Vector3(side * 20.6, 6.5, 0)), side, 3.2, 7.3, "window_dim" if i % 3 == 0 else "window")
			if i % 3 == 1:
				_lantern(ctx, pose.translated_local(Vector3(side * 13.2, 10.0, 0)), "terminal_" + str(i) + "_" + str(int(side)))
				ctx._at(pose, Vector3(side * 13.2, 13.5, 0), Vector3(0.12, 2.3, 0.12), "ink")
				ctx.add_light(pose.translated_local(Vector3(side * 17.4, 5.0, 0)).origin, 35.0, 24.0)
			if i % 4 == 2:
				for height in [0.8, 1.8]: ctx._at(pose, Vector3(side * 17.3, height, 0), Vector3(1.4, 0.2, 4.2), "soffit")
				for z in [-1.5, 1.5]: ctx._at(pose, Vector3(side * 17.3, 0.45, z), Vector3(0.2, 0.9, 0.3), "ink")
		stats.terminal_bays += 1
	for i in 12:
		var pose: Transform3D = ctx.upright_pose("victory_run", minf(i * 20.0, track.length))
		for side: float in [-1.0, 1.0]:
			var post: Transform3D = pose.translated_local(Vector3(side * 18.0, 0, 0))
			ctx._profile(post, 2.0, 2.0, [Vector2(0, 1.1), Vector2(0.65, 1.1), Vector2(1.2, 0.7), Vector2(1.5, 0.6)], "stone")
			ctx._profile(post, 1.05, 1.05, [Vector2(1.4, 1), Vector2(13.5, 0.88), Vector2(13.8, 1.05), Vector2(14.5, 1.7)], "edge")
			ctx._profile(post, 2.0, 2.0, [Vector2(14.1, 0.7), Vector2(14.5, 1), Vector2(14.8, 1.1)], "stone")
			for brace_side: float in [-1.0, 1.0]: ctx._brace(post.translated_local(Vector3(0, 7, 0)).scaled_local(Vector3(0.5, 0.5, 1.0)), brace_side)
			var flag: Transform3D = pose.translated_local(Vector3(side * 10.0, 12.8, -4.0))
			flag.basis = flag.basis * Basis(Vector3.UP, PI / 2.0)
			ctx._festival_flag(flag, "flag" if i % 2 == 0 else "flag_purple")
	if ctx.claim("victory_run_s205_completion_gate"):
		var gate: Transform3D = ctx.upright_pose("victory_run", 205.0)
		for side: float in [-1.0, 1.0]:
			var pier: Transform3D = gate.translated_local(Vector3(side * 16.0, 0, 0))
			ctx._profile(pier, 2.6, 2.8, [Vector2(0, 1.2), Vector2(1.2, 1.2), Vector2(2, 0.9), Vector2(16.5, 0.85), Vector2(17.4, 1.25), Vector2(19, 1.25)], "violet")
			ctx._at(pier, Vector3(0, 8.5, 1.43), Vector3(0.7, 14, 0.15), "gold")
			ctx._roof(pier.translated_local(Vector3(0, 22.0, 0)), 4.8, 6.0, 5.0, "roof")
		ctx._at(gate, Vector3(0, 18.2, 0), Vector3(34, 2.0, 2.3), "violet")
		for height in [17.3, 19.1]: ctx._at(gate, Vector3(0, height, 1.2), Vector3(34.5, 0.22, 0.24), "gold")
		ctx.place_model("h07_lantern", gate.translated_local(Vector3(0, 17.1, 0)), Vector3(3.4, 4.8, 3.4), 0, "h07_completion_pumpkin", 850.0)
		stats.physical_terminal_gate = 1

func _lantern(ctx: RefCounted, pose: Transform3D, ident: String) -> void:
	var node: Node3D = ctx.place_model("h07_lantern", pose, Vector3(1.8, 3.1, 1.8), 0.0, "h07_finale_lantern_" + ident, 310.0)
	if node != null:
		stats.lanterns += 1
		ctx.add_light(pose.translated_local(Vector3(0, 1.6, 0)).origin, 28.0, 27.0)
