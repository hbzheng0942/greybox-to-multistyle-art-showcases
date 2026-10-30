extends RefCounted
## Pure fixed-step game state: the renderer NEVER awards rewards.
## No physics engine, timers, scene-tree ownership or asynchronous tweens here.
## Scripted release/fall is deliberate in v0.2; it is not a general rigid-body solver.

signal happened(event: Dictionary)

const LandBoundary = preload("res://scripts/land_boundary.gd")
var land = LandBoundary.new()

const AVAILABLE = 0
const LOCKED = 1
const FALLING = 2
const CAPTURED = 3
const CONSUMED = 4
const READY = 0
const PLAYING = 1
const DRAINING = 2
const FINISHED = 3
const STATE_NAMES = ["AVAILABLE", "SUPPORTED_LOCKED", "RELEASED", "CAPTURED", "CONSUMED"]
const DIAMETERS = [0.90, 1.45, 2.10, 3.00, 4.30, 6.20]
const THRESHOLDS = [0, 16, 60, 140, 280, 520]

var config: Dictionary = {}
var tuning
var archetypes: Dictionary = {}
var objects: Array = []
var by_id: Dictionary = {}
var holes: Array = []
var events: Array = []
var stage: int = READY
var elapsed: float = 0.0
var clock: float = 0.0
var consumed_count: int = 0
var total_reward: int = 0
var last_consume_at: float = 0.0
var forced_tier: int = -1
var lab_unlimited: bool = false
var assisted_run: bool = false
var result_reason: String = ""
var error_message: String = ""
var route_mode: int = 0 # 0 manual, 1 west, 2 east. Automated routes are ALWAYS labelled.
var path_samples: Array = []
var sample_accum: float = 0.0
var event_sequence: int = 0
var run_id: int = 0

func initialize(definition: Dictionary, parameters) -> bool:
	config = definition.duplicate(true)
	tuning = parameters
	if not config.has("instances") or not config.has("archetypes") or not config.has("recipe"):
		error_message = "Missing instances/archetypes/recipe in graybox_config.json"
		return false
	archetypes.clear()
	for entry in config["archetypes"]:
		archetypes[str(entry["id"])] = entry
	var ids: Dictionary = {}
	for entry in config["instances"]:
		var id: String = str(entry["id"])
		if ids.has(id) or not archetypes.has(str(entry["archetype"])):
			error_message = "Duplicate ID or unknown archetype: " + id
			return false
		ids[id] = true
	land.setup(config["map"], tuning.shore_margin)
	reset(false)
	return true

func vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func reset(with_rival: bool = false) -> void:
	objects.clear()
	by_id.clear()
	holes.clear()
	events.clear()
	path_samples.clear()
	stage = READY
	elapsed = 0.0
	clock = 0.0
	consumed_count = 0
	total_reward = 0
	last_consume_at = 0.0
	forced_tier = -1
	lab_unlimited = false
	assisted_run = false
	route_mode = 0
	result_reason = ""
	sample_accum = 0.0
	event_sequence = 0
	run_id += 1
	for entry in config["instances"]:
		var a: Dictionary = archetypes[str(entry["archetype"])]
		var item: Dictionary = {
			"id": str(entry["id"]), "archetype": str(entry["archetype"]),
			"asset_id": str(entry.get("asset_id", "")),
			"zone": str(entry["zone"]), "definition": a,
			"assembly": entry.get("assembly_id"), "root_support": entry.get("root_support_id"),
			"support": entry.get("support_id"), "state": LOCKED if entry["initial_state"] == "SUPPORTED_LOCKED" else AVAILABLE,
			"position": vec3(entry["position_xyz"]), "initial_position": vec3(entry["position_xyz"]),
			"size": vec3(a["size_xyz"]), "yaw": deg_to_rad(float(entry.get("yaw_degrees", 0))),
			"owner": -1, "capture_age": 0.0, "duration": 0.0, "capture_start": Vector3.ZERO,
			"rotation": Vector3.ZERO, "visual_scale": 1.0, "release_done": false,
			"fall_velocity": Vector3.ZERO, "settled": false, "release_origin": Vector3.ZERO,
		}
		by_id[item["id"]] = objects.size()
		objects.append(item)
	_make_hole(0, vec3(config["map"]["spawn_xyz"]))
	if with_rival:
		_make_hole(1, vec3(config["map"]["rival_spawn_xyz"]))
	_emit("RESET", {"rival": with_rival, "tuning": tuning.snapshot()})

func _make_hole(id: int, position: Vector3) -> void:
	holes.append({"id": id, "position": position, "previous": position, "velocity": Vector2.ZERO,
		"diameter": float(config["recipe"]["hole_diameters"][0]) * tuning.diameter_scale,
		"tier": 0, "growth": 0, "score": 0, "count": 0, "landmarks": 0, "alive": true,
		"levels": [{"tier": 0, "time": 0.0}], "target": -1, "ai_cooldown": 0.0,
		"motion_path": PackedVector2Array([Vector2(position.x, position.z)]), "nav_path": PackedVector2Array(),
		"nav_target": -1, "nav_radius": -1.0, "bank_contacts": 0})
	_constrain_hole(id)

func item(id: String) -> Dictionary:
	if not by_id.has(id):
		return {}
	return objects[int(by_id[id])]

func effective_tier(owner: int = 0) -> int:
	if owner == 0 and forced_tier >= 0:
		return forced_tier
	return int(holes[owner]["tier"])

func desired_diameter(owner: int = 0) -> float:
	# Milestones still drive the HUD/chime. Actual size grows after EVERY consumed unit.
	# Rendering, floor cutout and fit checks all use this same smoothed physical size.
	var diameters: Array = config["recipe"]["hole_diameters"]
	if (owner == 0 and forced_tier >= 0) or not tuning.continuous_growth:
		return float(diameters[effective_tier(owner)]) * tuning.diameter_scale
	var thresholds: Array = config["recipe"]["growth_thresholds_cumulative"]
	var growth: float = float(holes[owner]["growth"])
	for i in range(thresholds.size() - 1):
		if growth < float(thresholds[i + 1]):
			var u: float = clampf((growth - float(thresholds[i])) / maxf(1.0, float(thresholds[i + 1]) - float(thresholds[i])), 0.0, 1.0)
			return lerpf(float(diameters[i]), float(diameters[i + 1]), u) * tuning.diameter_scale
	# Keep gaining a little after the last milestone; cap inside the playable floor margin.
	var end_score: float = float(config["recipe"].get("continuous_growth_tail_score", 1000))
	var tail: float = clampf((growth - float(thresholds[-1])) / maxf(1.0, end_score - float(thresholds[-1])), 0.0, 1.0)
	return lerpf(float(diameters[-1]), float(config["recipe"].get("continuous_growth_tail_diameter", 6.8)), tail) * tuning.diameter_scale

func can_fit(o: Dictionary, owner: int = 0) -> bool:
	if owner < 0 or owner >= holes.size() or not holes[owner]["alive"]:
		return false
	var a: Dictionary = o["definition"]
	if tuning.enforce_tier_gate and effective_tier(owner) < int(a["min_tier"]):
		return false
	return float(a["proxy_flat_span"]) <= float(holes[owner]["diameter"]) * tuning.fit_margin + 0.00001

func is_collectible(o: Dictionary, owner: int = 0) -> bool:
	if int(o["state"]) not in [AVAILABLE, FALLING] or int(o["owner"]) != -1:
		return false
	var pos: Vector3 = o["position"]
	var size: Vector3 = o["size"]
	return pos.y - size.y * 0.5 <= float(config["recipe"]["capture_band_max_bottom_y"]) and can_fit(o, owner)

func begin() -> void:
	if stage == READY:
		stage = PLAYING
		_emit("START", {})

func force_size(tier: int) -> void:
	forced_tier = clampi(tier, -1, 5)
	assisted_run = true
	holes[0]["diameter"] = desired_diameter(0)
	_constrain_hole(0)
	_emit("DEBUG_SIZE", {"forced_tier": forced_tier})

func teleport(position: Vector3, owner: int = 0) -> void:
	# Set previous too: teleports must not vacuum everything along the teleport path.
	var p: Vector3 = _clamp_position(position, float(holes[owner]["diameter"]) * 0.5)
	holes[owner]["position"] = p
	holes[owner]["previous"] = p
	holes[owner]["motion_path"] = PackedVector2Array([Vector2(p.x, p.z)])
	holes[owner]["nav_target"] = -1
	holes[owner]["velocity"] = Vector2.ZERO
	assisted_run = true
	_emit("DEBUG_TELEPORT", {"owner": owner, "position": _xyz(p)})

func tick(dt: float, player_input: Vector2) -> void:
	if dt <= 0.0 or stage == FINISHED:
		return
	if stage == READY:
		if player_input.length_squared() < 0.0001 and route_mode == 0:
			return
		begin()
	land.shore_margin = tuning.shore_margin
	clock += dt
	if stage == PLAYING:
		if not lab_unlimited:
			elapsed = minf(elapsed + dt, tuning.round_seconds)
		if elapsed >= tuning.round_seconds and not lab_unlimited:
			stage = DRAINING
			result_reason = "TIME"
			_emit("TIMEOUT", {})
	for index in range(holes.size()):
		var h: Dictionary = holes[index]
		if not h["alive"]:
			continue
		var diameter: float = desired_diameter(index)
		if tuning.growth_blend <= 0.0:
			h["diameter"] = diameter
		else:
			h["diameter"] = lerpf(float(h["diameter"]), diameter, 1.0 - exp(-dt / tuning.growth_blend))
			if absf(float(h["diameter"]) - diameter) < 0.00001:
				h["diameter"] = diameter
		h["previous"] = h["position"]
		var direction: Vector2 = Vector2.ZERO
		if stage == PLAYING:
			if index == 0:
				direction = player_input.limit_length(1.0) if route_mode == 0 else _ai_input(index, dt)
			else:
				direction = _ai_input(index, dt)
		var velocity: Vector2 = h["velocity"]
		var rate: float = tuning.acceleration if direction.length_squared() > 0.0001 else tuning.braking
		velocity = velocity.move_toward(direction * tuning.move_speed, rate * dt)
		if stage != PLAYING:
			velocity = Vector2.ZERO
		h["velocity"] = velocity
		var old: Vector3 = h["position"]
		var start: Vector2 = Vector2(old.x, old.z)
		var movement: Dictionary = land.move_and_slide_disk(start, start + velocity * dt, float(h["diameter"]) * 0.5)
		var stop: Vector2 = movement["position"]
		var legal_start: Vector2 = movement["start"]
		h["position"] = Vector3(stop.x, 0.0, stop.y)
		h["previous"] = Vector3(legal_start.x, 0.0, legal_start.y)
		h["motion_path"] = movement["path"]
		h["bank_contacts"] = int(h["bank_contacts"]) + int(movement["contacts"])
		h["velocity"] = (stop - legal_start) / dt
	_update_falling(dt)
	if stage == PLAYING:
		_capture_pass()
		_check_hole_competition()
	_update_captured(dt)
	if stage == PLAYING and consumed_count == objects.size():
		stage = DRAINING
		result_reason = "CLEARED"
	if stage == DRAINING and count_state(CAPTURED) == 0:
		stage = FINISHED
		_emit("FINISHED", {"reason": result_reason, "score": holes[0]["score"], "landmarks": holes[0]["landmarks"]})
	sample_accum += dt
	if sample_accum >= 0.25:
		sample_accum = 0.0
		path_samples.append({"time": snappedf(clock, 0.001), "position": _xyz(holes[0]["position"]), "tier": effective_tier(0), "score": holes[0]["score"], "diameter": holes[0]["diameter"]})

func _clamp_position(p: Vector3, radius: float = 0.45) -> Vector3:
	var q: Vector2 = land.project_inside(Vector2(p.x, p.z), radius)
	return Vector3(q.x, 0.0, q.y)

func _constrain_hole(owner: int) -> void:
	var h: Dictionary = holes[owner]
	var pos: Vector3 = _clamp_position(h["position"], float(h["diameter"]) * 0.5)
	h["position"] = pos
	h["previous"] = pos
	h["motion_path"] = PackedVector2Array([Vector2(pos.x, pos.z)])
	h["nav_target"] = -1

func constrain_all_holes() -> void:
	land.shore_margin = tuning.shore_margin
	for owner in range(holes.size()):
		_constrain_hole(owner)

func _motion_distance(point: Vector3, hole: Dictionary) -> float:
	var path: PackedVector2Array = hole["motion_path"]
	var p: Vector2 = Vector2(point.x, point.z)
	var distance: float = p.distance_to(path[0])
	for i in range(1, path.size()):
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, path[i - 1], path[i])))
	return distance

func _swept_distance(point: Vector3, start: Vector3, end: Vector3) -> float:
	var p: Vector2 = Vector2(point.x, point.z)
	var a: Vector2 = Vector2(start.x, start.z)
	var b: Vector2 = Vector2(end.x, end.z)
	var ab: Vector2 = b - a
	var t: float = 0.0
	if ab.length_squared() > 0.000001:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _capture_pass() -> void:
	# 215 objects x <=2 holes: bounded simple scan, easy to audit. Swap broadphase later.
	for o in objects:
		if int(o["state"]) not in [AVAILABLE, FALLING]:
			continue
		var winner: int = -1
		var best: float = INF
		for owner in range(holes.size()):
			if not is_collectible(o, owner):
				continue
			var h: Dictionary = holes[owner]
			var distance: float = _motion_distance(o["position"], h)
			var radius: float = float(h["diameter"]) * 0.5 * tuning.capture_factor
			if distance <= radius and distance < best - 0.000001:
				winner = owner
				best = distance
		# Deterministic tie-break: smaller hole ID. Deliberate, not a fairness claim.
		if winner >= 0:
			_capture(o, winner)

func _capture(o: Dictionary, owner: int) -> void:
	if stage != PLAYING or int(o["owner"]) >= 0 or int(o["state"]) not in [AVAILABLE, FALLING]:
		return
	o["state"] = CAPTURED
	o["owner"] = owner
	o["capture_age"] = 0.0
	o["capture_start"] = o["position"]
	o["duration"] = float(config["recipe"]["swallow_durations_seconds"][int(o["definition"]["min_tier"])]) * tuning.swallow_time_scale
	_emit("CAPTURE", _object_event(o))

func _release_payload(root_id: String) -> void:
	var sequence: int = 0
	for o in objects:
		if o["root_support"] != root_id or int(o["state"]) != LOCKED:
			continue
		o["state"] = FALLING
		o["support"] = null
		o["release_origin"] = o["position"]
		# Fan stacked cubes slightly apart; this is a controlled release, not contact physics.
		var x_speed: float = (float(sequence % 3) - 1.0) * 0.65 if o["archetype"] == "stack_cube" else 0.0
		o["fall_velocity"] = Vector3(x_speed, 0.0, 0.0)
		sequence += 1
		_emit("RELEASE", _object_event(o))

func _update_falling(dt: float) -> void:
	for o in objects:
		if int(o["state"]) != FALLING:
			continue
		var velocity: Vector3 = o["fall_velocity"]
		velocity.y -= 12.0 * dt
		var position: Vector3 = o["position"] + velocity * dt
		var size: Vector3 = o["size"]
		if position.y <= size.y * 0.5:
			position.y = size.y * 0.5
			velocity = Vector3.ZERO
			o["state"] = AVAILABLE
			o["settled"] = true
			o["rotation"] = Vector3.ZERO
		var flat: Vector2 = land.project_inside(Vector2(position.x, position.z), float(o["definition"]["proxy_flat_span"]) * 0.5)
		position.x = flat.x
		position.z = flat.y
		o["position"] = position
		o["fall_velocity"] = velocity

func _update_captured(dt: float) -> void:
	for o in objects:
		if int(o["state"]) != CAPTURED:
			continue
		o["capture_age"] = float(o["capture_age"]) + dt
		var duration: float = maxf(float(o["duration"]), 0.04)
		var age: float = float(o["capture_age"])
		if not o["release_done"] and age >= minf(0.10, duration * 0.45):
			o["release_done"] = true
			if stage == PLAYING:
				_release_payload(str(o["id"]))
		var u: float = clampf(age / duration, 0.0, 1.0)
		var initial: Vector3 = o["capture_start"]
		var hole: Dictionary = holes[int(o["owner"])]
		var target: Vector3 = hole["position"]
		var align: float = smoothstep(0.0, 0.35, u)
		var pos: Vector3 = initial.lerp(Vector3(target.x, initial.y, target.z), align)
		var sink: float = smoothstep(0.12, 1.0, u)
		var size: Vector3 = o["size"]
		pos.y = initial.y - (initial.y + size.y * 0.7 + 0.22) * sink
		o["position"] = pos
		var profile: String = str(o["definition"]["swallow_profile"])
		var tip: float = 0.0
		if profile == "tip_and_sink":
			tip = sin(u * PI * 0.7) * 0.50
		elif profile in ["long_tip", "long_align_sink", "align_and_sink"]:
			tip = sin(u * PI) * 0.22
		else:
			tip = sin(u * PI) * 0.08
		o["rotation"] = Vector3(tip, float(o["yaw"]), tip * 0.35)
		o["visual_scale"] = 1.0 - smoothstep(0.65, 1.0, u) * 0.12
		if u >= 1.0:
			_consume(o)

func _consume(o: Dictionary) -> void:
	if int(o["state"]) != CAPTURED:
		return
	o["state"] = CONSUMED
	var owner: int = int(o["owner"])
	var h: Dictionary = holes[owner]
	var a: Dictionary = o["definition"]
	h["growth"] = int(h["growth"]) + int(a["growth"])
	h["score"] = int(h["score"]) + int(a["score"])
	h["count"] = int(h["count"]) + 1
	consumed_count += 1
	total_reward += int(a["score"])
	if owner == 0:
		last_consume_at = clock
	if o["archetype"] == "landmark":
		h["landmarks"] = int(h["landmarks"]) + 1
	_emit("CONSUME", _object_event(o))
	var thresholds: Array = config["recipe"]["growth_thresholds_cumulative"]
	while int(h["tier"]) < thresholds.size() - 1 and int(h["growth"]) >= int(thresholds[int(h["tier"]) + 1]):
		h["tier"] = int(h["tier"]) + 1
		h["levels"].append({"tier": h["tier"], "time": snappedf(clock, 0.001)})
		_emit("LEVEL_UP", {"owner": owner, "tier": h["tier"], "score": h["score"], "diameter": desired_diameter(owner)})

func _check_hole_competition() -> void:
	if holes.size() < 2 or not holes[0]["alive"] or not holes[1]["alive"]:
		return
	var h0: Dictionary = holes[0]
	var h1: Dictionary = holes[1]
	var big: int = 0 if float(h0["diameter"]) > float(h1["diameter"]) else 1
	var small: int = 1 - big
	var big_radius: float = float(holes[big]["diameter"]) * 0.5
	var small_radius: float = float(holes[small]["diameter"]) * 0.5
	var distance: float = holes[big]["position"].distance_to(holes[small]["position"])
	if big_radius >= small_radius * 1.35 and distance + small_radius <= big_radius * 0.92:
		holes[small]["alive"] = false
		# No transfer / duplication of already-accounted world rewards.
		_emit("HOLE_EATEN", {"owner": big, "victim": small})
		if small == 0:
			stage = DRAINING
			result_reason = "EATEN"

func _ai_input(owner: int, dt: float) -> Vector2:
	var h: Dictionary = holes[owner]
	h["ai_cooldown"] = float(h["ai_cooldown"]) - dt
	var target: int = int(h["target"])
	if float(h["ai_cooldown"]) <= 0.0 or target < 0 or not is_collectible(objects[target], owner):
		h["ai_cooldown"] = 0.18
		var best: float = -INF
		target = -1
		for index in range(objects.size()):
			var o: Dictionary = objects[index]
			if not is_collectible(o, owner):
				continue
			var here: Vector3 = h["position"]
			var there: Vector3 = o["position"]
			var approach: Vector2 = land.project_inside(Vector2(there.x, there.z), float(h["diameter"]) * 0.5)
			if approach.distance_to(Vector2(there.x, there.z)) > float(h["diameter"]) * 0.5 * tuning.capture_factor * 0.99:
				continue
			var distance: float = Vector2(here.x, here.z).distance_to(Vector2(there.x, there.z))
			var value: float = pow(float(o["definition"]["growth"]), 0.65) / (distance + 1.0)
			if owner == 0 and route_mode > 0 and int(h["growth"]) < 150:
				var preferred: String = "B" if route_mode == 1 else "D"
				if str(o["zone"]) not in ["A", preferred]:
					value *= 0.12
			# Same resources and same gates as the player; no hidden growth.
			if holes.size() > 1:
				var opponent: Dictionary = holes[1 - owner]
				if opponent["alive"] and float(opponent["diameter"]) > float(h["diameter"]) * 1.25:
					if o["position"].distance_to(opponent["position"]) < float(opponent["diameter"]) + 1.0:
						value *= 0.15
			if value > best:
				best = value
				target = index
		h["target"] = target
	if target < 0:
		return Vector2.ZERO
	var from3: Vector3 = h["position"]
	var target3: Vector3 = objects[target]["position"]
	var from: Vector2 = Vector2(from3.x, from3.z)
	var target_flat: Vector2 = Vector2(target3.x, target3.z)
	var radius: float = float(h["diameter"]) * 0.5
	var goal: Vector2 = land.project_inside(target_flat, radius)
	if from.distance_to(target_flat) <= radius * tuning.capture_factor * 0.44:
		return Vector2.ZERO
	if int(h["nav_target"]) != target or absf(float(h["nav_radius"]) - radius) > 0.12:
		h["nav_path"] = land.navigation_path(from, goal, radius)
		h["nav_target"] = target
		h["nav_radius"] = radius
	var path: PackedVector2Array = h["nav_path"]
	while path.size() > 1 and from.distance_to(path[0]) < 0.22:
		path.remove_at(0)
	h["nav_path"] = path
	if path.is_empty():
		h["target"] = -1
		return Vector2.ZERO
	# Direct shortcuts are used only when the entire swept disk remains on land.
	if land.segment_valid(from, goal, radius):
		return (goal - from).normalized()
	return (path[0] - from).normalized()

func count_state(state: int) -> int:
	var count: int = 0
	for o in objects:
		if int(o["state"]) == state:
			count += 1
	return count

func available_growth(owner: int = 0) -> int:
	var value: int = 0
	for o in objects:
		if is_collectible(o, owner):
			value += int(o["definition"]["growth"])
	return value

func _object_event(o: Dictionary) -> Dictionary:
	var result: Dictionary = {"id": o["id"], "archetype": o["archetype"], "zone": o["zone"],
		"owner": o["owner"], "position": _xyz(o["position"]), "state": STATE_NAMES[int(o["state"])], "object_tier": int(o["definition"]["min_tier"]), "reward": int(o["definition"]["score"])}
	if int(o["owner"]) >= 0:
		result["tier"] = effective_tier(int(o["owner"]))
		result["score"] = holes[int(o["owner"])]["score"]
	return result

func _emit(kind: String, values: Dictionary) -> void:
	var event: Dictionary = values.duplicate(true)
	event["event"] = kind
	event["time"] = snappedf(clock, 0.001)
	event["round_time"] = snappedf(elapsed, 0.001)
	event["sequence"] = event_sequence
	event_sequence += 1
	events.append(event)
	happened.emit(event)

func _xyz(value: Vector3) -> Array:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]

func report() -> Dictionary:
	var players: Array = []
	for h in holes:
		players.append({"id": h["id"], "score": h["score"], "growth": h["growth"], "count": h["count"], "tier": h["tier"], "levels": h["levels"], "landmarks": h["landmarks"], "alive": h["alive"], "bank_contacts": h["bank_contacts"]})
	return {"format": "hole_waterfront_run_v0.3", "run_id": run_id, "stage": stage, "reason": result_reason,
		"clock": clock, "elapsed": elapsed, "consumed_units": consumed_count, "world_score": total_reward,
		"world_available_total": config["summary"]["score_total"], "layout_version": "v0.3", "boundary_policy": "full_disk_on_land",
		"assisted": assisted_run, "route_mode": route_mode, "tuning": tuning.snapshot(),
		"players": players, "events": events, "path_samples": path_samples}

func reset_assembly(assembly_id: String) -> bool:
	if assembly_id.is_empty():
		return false
	var touched: bool = false
	for o in objects:
		if o["assembly"] != assembly_id:
			continue
		touched = true
		o["state"] = LOCKED if o["root_support"] != null else AVAILABLE
		o["position"] = o["initial_position"]
		o["owner"] = -1
		o["capture_age"] = 0.0
		o["rotation"] = Vector3.ZERO
		o["visual_scale"] = 1.0
		o["release_done"] = false
		o["fall_velocity"] = Vector3.ZERO
		o["settled"] = false
		for entry in config["instances"]:
			if str(entry["id"]) == str(o["id"]):
				o["support"] = entry.get("support_id")
				break
	if not touched:
		return false
	# Recompute the ledger, instead of duplicating rewards on repeated group resets.
	consumed_count = 0
	total_reward = 0
	for h in holes:
		h["score"] = 0
		h["growth"] = 0
		h["count"] = 0
		h["landmarks"] = 0
		h["tier"] = 0
	for o in objects:
		if int(o["state"]) != CONSUMED:
			continue
		var h: Dictionary = holes[int(o["owner"])]
		h["score"] += int(o["definition"]["score"])
		h["growth"] += int(o["definition"]["growth"])
		h["count"] += 1
		total_reward += int(o["definition"]["score"])
		consumed_count += 1
		if o["archetype"] == "landmark":
			h["landmarks"] += 1
	for h in holes:
		while int(h["tier"]) < 5 and int(h["growth"]) >= int(config["recipe"]["growth_thresholds_cumulative"][int(h["tier"]) + 1]):
			h["tier"] += 1
		h["levels"] = [{"tier": h["tier"], "time": clock, "debug_recomputed": true}]
	lab_unlimited = true
	assisted_run = true
	stage = PLAYING
	result_reason = ""
	_emit("RESET_ASSEMBLY", {"assembly": assembly_id})
	return true
