extends Node3D
## Deterministic, collisionless festival actors. One foreground gag at a time.
const Actors = preload("res://themes/halloween_festival/actors.gd")
const Effects = preload("res://themes/halloween_festival/effects.gd")
const Mischief = preload("res://themes/halloween_festival/mischief.gd")
var kit = Actors.new()
var fx = Effects.new()
var jokes = Mischief.new()
var app: Node3D
var route: Node3D
var roof: Node3D
var ghost: Node3D
var lantern_pivot: Node3D
var impact: Node3D
var falling: Node3D
var puff: Node3D
var moon: Node3D
var steal_event: Node3D
var juggle_event: Node3D
var horn_ring: Node3D
var horn_player: AudioStreamPlayer
var hint: Label
var staff: Array[Dictionary] = []
var bats: Array[Dictionary] = []
var pumpkins: Array[Node3D] = []
var hero_pumpkin: Node3D
var ghost_anchor := Transform3D.IDENTITY
var pumpkin_anchor := Transform3D.IDENTITY
var cue_times := {"ghost": -1.0, "pumpkin": -1.0, "land": -1.0, "juggle": -1.0, "steal": -1.0}
var horn_time := -1.0
var horn_target := ""
var last_horn_clock := -100.0
var previous_clock := -1.0
var last_phase := 0
var active_age := -1.0
var moon_progress := -1.0
var variant := "ghost"
var event_log: Array[Dictionary] = []
var manual := false

func _exit_tree() -> void:
	var destination := OS.get_environment("H07_FESTIVAL_EVENTS_PATH")
	if destination.is_empty(): return
	var record := {"variant":variant,"events":event_log,"last_clock":previous_clock,"source_sha256":FileAccess.get_sha256("res://themes/halloween_festival/festival_layer.gd")}
	var file := FileAccess.open(destination,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(record,"\t") + "\n")

func setup(session: Node3D) -> void:
	app = session
	route = app.get_node("ControllerLab/RouteRoot/MainRoute")
	app.train.motion_event.connect(_on_motion_event)
	for argument in OS.get_cmdline_user_args():
		if argument == "--festival-variant=pumpkin": variant = "pumpkin"
	process_priority = 1100
	_build_roof()
	_build_staff()
	_build_ghost()
	_build_pumpkin()
	_build_hazards()
	_build_hero_pumpkin()
	_build_interactions()
	moon = fx.build_moon_flyby()
	moon.name = "MoonSilhouette"
	add_child(moon)
	moon.visible = false
	for i in 3:
		var bat: Node3D = fx.build_bat()
		bat.name = "EavesBat%d" % i
		add_child(bat)
		var p := _level("station_start", 185.0 + i * 145.0, -15.0)
		p.origin += Vector3.UP * 13.2
		bat.transform = p.scaled_local(Vector3.ONE * 0.8)
		bats.append({"node": bat, "pose": bat.transform, "offset": i * 1.7})
	set_meta("authored_actor_count", staff.size() + pumpkins.size() + bats.size() + 6)
	_update(0.0, 0, "station_start", 24.0)

func _build_interactions() -> void:
	steal_event = jokes.build_steal_hat(kit,roof)
	_tag(steal_event,"HatThief")
	roof.add_child(steal_event)
	juggle_event = jokes.build_head_juggle(kit,roof)
	_tag(juggle_event,"HeadJuggler")
	roof.add_child(juggle_event)
	horn_ring = fx.build_impact()
	_tag(horn_ring,"HornSurprise")
	add_child(horn_ring)
	horn_player = AudioStreamPlayer.new()
	horn_player.name = "FestivalHorn"
	horn_player.volume_db = -16.0
	add_child(horn_player)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(6615 * 2)
	for i in 6615:
		var seconds := float(i)/22050.0
		var envelope := sin(PI*float(i)/6615.0)
		var sample := (sin(TAU*262.0*seconds)+sin(TAU*330.0*seconds)*0.45)*envelope*12000.0
		data.encode_s16(i*2,int(sample))
	wave.data = data
	horn_player.stream = wave
	var ui := CanvasLayer.new()
	ui.layer = 8
	add_child(ui)
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(anchor)
	hint = Label.new()
	hint.text = "H · HONK TO SPOOK"
	hint.add_theme_font_size_override("font_size",18)
	hint.add_theme_color_override("font_color",Color("e2c3e8"))
	hint.add_theme_color_override("font_shadow_color",Color("211229"))
	hint.add_theme_constant_override("shadow_offset_x",2)
	hint.add_theme_constant_override("shadow_offset_y",2)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(22,-112)
	anchor.add_child(hint)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		if honk(): get_viewport().set_input_as_handled()

func honk() -> bool:
	if not is_instance_valid(app) or get_tree().paused: return false
	if bool(app.get("finished")) or bool(app.get("failed")): return false
	var clock: float = app.train.motion.clock
	if clock-last_horn_clock < 1.2 or int(app.train.motion.phase) == 2: return false
	horn_time = clock
	last_horn_clock = clock
	horn_target = "ghost" if ghost.visible else "roof"
	event_log.append({"event":"horn","clock":clock,"target":horn_target})
	var sound = app.get("sound")
	if DisplayServer.get_name() != "headless" and sound != null and not bool(sound.get("muted")):
		horn_player.play()
	return true

func _tag(node: Node3D, ident: String) -> void:
	node.name = ident
	node.set_meta("scene_id", "station")
	node.set_meta("asset_id", "h07_authored_festival")
	node.set_meta("instance_id", "festival_" + ident)

func _level(track_id: String, s: float, side := 0.0) -> Transform3D:
	var p: Transform3D = route.track_pose(track_id, s, side)
	var forward := -p.basis.z
	forward.y = 0.0
	return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), p.origin)

func _build_roof() -> void:
	roof = kit.build_skeleton()
	_tag(roof, "RoofSkeleton")
	app.get_node("Actors/Train/VisualRoot/TrickPivot/Geometry").add_child(roof)
	var body: Node3D = roof.get_parent().get_node("H07TrainCanonical")
	var roof_bounds := _bounds(body,body.transform)
	roof.position = Vector3(0.0, roof_bounds.end.y + 0.025, 0.5)
	roof.scale = Vector3.ONE * 1.50
	kit.pose_skeleton(roof, "lounge", 0.0)

func _build_staff() -> void:
	# Unequal groups between the station's support columns; all outside the rail bed.
	var spots := [[155.0, 10.4, "wave"], [301.0, -10.5, "sleep"], [452.0, 10.8, "wave"], [454.0, 14.7, "sleep"]]
	for i in spots.size():
		var a: Array = spots[i]
		var actor: Node3D = kit.build_skeleton()
		_tag(actor, "StationSkeleton%d" % i)
		add_child(actor)
		var p := _level("station_start", a[0], a[1])
		p.origin.y += 0.52
		p.basis = p.basis * Basis(Vector3.UP, -0.45 if a[1] > 0.0 else 0.45)
		actor.transform = p.scaled_local(Vector3.ONE * 1.9)
		staff.append({"node": actor, "mode": a[2], "offset": float(i) * 0.73})

func _beam(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius; mesh.bottom_radius = radius
	mesh.height = from.distance_to(to); mesh.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color; mat.roughness = 0.8
	var node := MeshInstance3D.new()
	node.mesh = mesh; node.material_override = mat
	node.position = (from + to) * 0.5
	var y := (to - from).normalized()
	var x := Vector3.FORWARD.cross(y).normalized()
	if x.length() < 0.1: x = Vector3.RIGHT
	node.basis = Basis(x, y, x.cross(y).normalized())
	parent.add_child(node)

func _build_ghost() -> void:
	ghost_anchor = _level("station_carve", 286.0, -14.0)
	ghost_anchor.origin.y += 6.8
	ghost = kit.build_ghost()
	_tag(ghost, "MischievousGhost")
	add_child(ghost)
	ghost.transform = ghost_anchor.scaled_local(Vector3.ONE * 3.0)
	var hook := Node3D.new()
	hook.name = "LanternBracket"
	add_child(hook)
	hook.transform = ghost_anchor
	_beam(hook, Vector3(-12, -6.8, 0), Vector3(-12, 8, 0), 0.18, Color("241b36"))
	_beam(hook, Vector3(-12, 8, 0), Vector3(0, 8, 0), 0.17, Color("241b36"))
	_beam(hook, Vector3(-12, 5, 0), Vector3(-8, 8, 0), 0.12, Color("a46c40"))
	lantern_pivot = Node3D.new()
	hook.add_child(lantern_pivot)
	lantern_pivot.position.y = 8.0
	_beam(lantern_pivot, Vector3.ZERO, Vector3(0,-5.0,0), 0.07, Color("241b36"))
	var lantern: Node3D = kit.build_pumpkin()
	lantern_pivot.add_child(lantern)
	lantern.position = Vector3(0,-6.7,0)
	lantern.scale = Vector3.ONE * 1.6
	impact = fx.build_impact()
	add_child(impact)
	impact.transform = ghost_anchor.translated_local(Vector3(0,2,1)).scaled_local(Vector3.ONE * 2.0)

func _build_pumpkin() -> void:
	pumpkin_anchor = _level("station_start", 445.0, 10.5)
	pumpkin_anchor.origin.y += 0.52
	falling = kit.build_pumpkin()
	_tag(falling, "FallingSidePumpkin")
	add_child(falling)
	falling.transform = pumpkin_anchor.scaled_local(Vector3.ONE * 1.8)
	puff = fx.build_puff()
	add_child(puff)
	puff.transform = pumpkin_anchor.scaled_local(Vector3.ONE * 2.3)
	# A small visible shelf explains where the decoration drops from.
	var shelf := Node3D.new()
	add_child(shelf); shelf.transform = pumpkin_anchor
	_beam(shelf, Vector3(2,0,0),Vector3(2,10,0),0.14,Color("241b36"))
	_beam(shelf,Vector3(2,10,0),Vector3(-1,10,0),0.16,Color("241b36"))

func _build_hazards() -> void:
	# One existing hard obstacle receives a pumpkin disguise; the original collision
	# and front warning frame remain. Decorative rind fits strictly inside 3x5x2.
	var track = route.tracks["station_start"]
	for ob: Dictionary in track.obstacles:
		if ob.get("kind", "") != "block": continue
		for lane in ob.lanes:
			var p: Transform3D = route.track_pose("station_start", float(ob.s), float(lane) * 4.4)
			var pumpkin: Node3D = kit.build_pumpkin()
			_tag(pumpkin, "PumpkinObstacle%d" % pumpkins.size())
			add_child(pumpkin)
			# Fit actual authored bounds after construction; no assumptions about mesh size.
			var bounds := _bounds(pumpkin, Transform3D.IDENTITY)
			var target := Vector3(2.76, minf(float(ob.height)-0.4, 4.55), 1.76)
			# Preserve the broad pumpkin silhouette; a visible frame fills the tall blocker.
			var uniform := minf(target.x/bounds.size.x,minf(target.y/bounds.size.y,target.z/bounds.size.z))
			var factor := Vector3.ONE * uniform
			pumpkin.scale = factor
			pumpkin.position = -bounds.position * factor + Vector3(-bounds.size.x*uniform/2.0,0.2,-bounds.size.z*uniform/2.0)
			var holder := Node3D.new()
			add_child(holder); holder.global_transform = p
			pumpkin.reparent(holder, false)
			pumpkins.append(pumpkin)
			_beam(holder,Vector3(-1.35,0,0.92),Vector3(-1.35,float(ob.height),0.92),0.10,Color("261c35"))
			_beam(holder,Vector3(1.35,0,0.92),Vector3(1.35,float(ob.height),0.92),0.10,Color("261c35"))
			_beam(holder,Vector3(-1.35,float(ob.height),0.92),Vector3(1.35,float(ob.height),0.92),0.10,Color("261c35"))
			# Keep the mandatory magenta X readable on a matching full-height frame.
			_beam(holder,Vector3(-1.15,0.5,0.93),Vector3(1.15,float(ob.height)-0.5,0.93),0.15,Color("ee286f"))
			_beam(holder,Vector3(1.15,0.5,0.93),Vector3(-1.15,float(ob.height)-0.5,0.93),0.15,Color("ee286f"))
			for node in get_parent().get_children():
				# Godot sanitizes decimal dots in node names; contract IDs preserve them.
				if str(node.get_meta("instance_id", "")) == "H07Hazard_station_start_" + str(ob.s) + "_" + str(lane): node.visible = false
		return

func _build_hero_pumpkin() -> void:
	# Between the current station's column line and rear wall, before its exit arch.
	# This is a trackside landmark; existing blocker collision and warnings remain separate.
	var anchor := _level("station_start",572.0,23.0)
	anchor.origin.y += 0.54
	var holder := Node3D.new()
	_tag(holder,"GiantPumpkinLandmark")
	add_child(holder)
	holder.transform = anchor
	hero_pumpkin = kit.build_pumpkin()
	holder.add_child(hero_pumpkin)
	var bounds := _bounds(hero_pumpkin,Transform3D.IDENTITY)
	var factor := minf(12.0/bounds.size.x,minf(10.0/bounds.size.y,9.0/bounds.size.z))
	hero_pumpkin.scale = Vector3.ONE*factor
	hero_pumpkin.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
	var plinth := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.height = 0.14;shape.top_radius = 5.0;shape.bottom_radius = 5.15;shape.radial_segments = 32
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("52425e");stone.roughness = 0.93
	plinth.mesh = shape;plinth.material_override = stone
	plinth.position.y = -0.07
	plinth.scale.z = 0.8
	holder.add_child(plinth)
	holder.set_meta("placement_limits",{"track":"station_start","s":572.0,"side":23.0,"max_size":[12.0,10.0,9.0],"purpose":"trackside_landmark_not_gameplay_blocker"})

func _bounds(node: Node3D, transform_from_root: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	if node is MeshInstance3D:
		result = transform_from_root * node.get_aabb(); first = false
	for child in node.get_children():
		if child is Node3D:
			var a := _bounds(child, transform_from_root * child.transform)
			if a.size.length_squared() > 0.000001:
				result = a if first else result.merge(a); first = false
	return result

func _trigger(key: String, t: float) -> void:
	if cue_times[key] < 0.0:
		cue_times[key] = t
		event_log.append({"event": key, "clock": t})

func _on_motion_event(kind: String, payload: Dictionary) -> void:
	if manual: return
	if kind == "CAPTURE" and str(payload.get("target",app.train.motion.route.current.id)) in ["canyon_safe","canyon_fast","canyon_fast_catch"]:
		_trigger("land",float(payload.get("seconds",app.train.motion.clock)))

func reset() -> void:
	cue_times = {"ghost": -1.0, "pumpkin": -1.0, "land": -1.0, "juggle": -1.0, "steal": -1.0}
	horn_time = -1.0; horn_target = ""; last_horn_clock = -100.0
	if is_instance_valid(steal_event): jokes.reset(steal_event)
	if is_instance_valid(juggle_event): jokes.reset(juggle_event)
	if is_instance_valid(horn_player): horn_player.stop()
	if is_instance_valid(horn_ring):
		horn_ring.transform = Transform3D.IDENTITY
		fx.pose_impact(horn_ring,-1.0)
	event_log.clear(); last_phase = 0; previous_clock = -1.0

func _process(_delta: float) -> void:
	if manual or not is_instance_valid(app): return
	var sound = app.get("sound")
	if horn_player.playing and sound != null and bool(sound.get("muted")): horn_player.stop()
	var motion = app.train.motion
	_update(motion.clock, motion.phase, motion.route.current.id, motion.s)
	sync_sky(app.camera)

func seek(t: float, state: Dictionary = {}) -> void:
	manual = true
	reset()
	# Recorded first-main-route event times only for static review reconstruction.
	if t >= 5.416667: cue_times.ghost = 5.416667
	if t >= 1.90: cue_times.pumpkin = 1.90
	if t >= 10.67: cue_times.land = 10.67
	if variant == "ghost" and t >= 1.183333: cue_times.juggle = 1.183333
	if variant == "pumpkin" and t >= 50.94: cue_times.juggle = 50.94
	if t >= 55.516667: cue_times.steal = 55.516667
	# Final review can supply actual event clocks from this exact recorded execution.
	for key: String in state.get("cue_times",{}):
		if cue_times.has(key):
			var clock: float = state.cue_times[key]
			cue_times[key] = clock if clock >= 0.0 and t >= clock else -1.0
	_update(t, int(state.get("phase", 2 if t > 8.4 and t < 10.67 else 0)), str(state.get("track", "station_start")), float(state.get("s",24.0)))

func _update(t: float, phase: int, track_id: String, distance: float) -> void:
	if previous_clock >= 0.0 and t < previous_clock: reset()
	if variant == "ghost" and track_id == "station_carve" and distance >= 100.0: _trigger("ghost",t)
	if variant == "pumpkin" and track_id == "station_start" and distance >= 260.0: _trigger("pumpkin",t)
	if variant == "ghost" and track_id == "station_start" and distance >= 160.0: _trigger("juggle",t)
	if variant == "pumpkin" and track_id == "landmark_return" and distance >= 300.0: _trigger("juggle",t)
	if track_id == "landmark_return" and distance >= 1100.0 and phase != 2: _trigger("steal",t)
	if last_phase == 2 and phase in [0,1] and track_id in ["canyon_safe","canyon_fast","canyon_fast_catch"]: _trigger("land",t)
	var landing_age := t - float(cue_times.land) if cue_times.land >= 0.0 else -1.0
	var juggle_age := t - float(cue_times.juggle) if cue_times.juggle >= 0.0 else -1.0
	var steal_age := t - float(cue_times.steal) if cue_times.steal >= 0.0 else -1.0
	var roof_pose := "grab" if phase == 2 else ("rattle" if landing_age >= 0.0 and landing_age < 0.7 else "lounge")
	if juggle_age >= 0.0 and juggle_age < 3.2 and phase != 2: roof_pose = "wave"
	kit.pose_skeleton(roof,roof_pose,t)
	for row in staff: kit.pose_skeleton(row.node, row.mode, t + row.offset)
	for row in bats:
		fx.pose_bat(row.node,t + row.offset)
		row.node.transform = row.pose
		row.node.position.y += sin(t * 1.4 + row.offset) * 0.16
	var ghost_age := t - float(cue_times.ghost) if cue_times.ghost >= 0.0 else -1.0
	_ghost_action(ghost_age if variant == "ghost" else -1.0)
	var pumpkin_age := t - float(cue_times.pumpkin) if cue_times.pumpkin >= 0.0 else -1.0
	_pumpkin_action(pumpkin_age if variant == "pumpkin" else -1.0)
	jokes.pose_head_juggle(juggle_event,juggle_age if phase != 2 else -1.0,roof)
	jokes.pose_steal_hat(steal_event,steal_age,roof,phase)
	var horn_age := t-horn_time if horn_time >= 0.0 else -1.0
	if horn_age >= 0.0 and horn_age < 0.65:
		var startled: Node3D = ghost if horn_target == "ghost" and ghost.visible else roof
		jokes.pose_startle(startled,horn_age,"ghost" if startled == ghost else "skeleton")
		horn_ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*1.5),startled.global_position+Vector3.UP*2.5)
	fx.pose_impact(horn_ring,horn_age/0.65)
	hint.visible = phase != 2 and not bool(app.get("finished")) and not bool(app.get("failed"))
	moon_progress = (landing_age - 0.75) / 2.7 if landing_age >= 0.0 and phase != 2 else -1.0
	moon.visible = moon_progress >= 0.0 and moon_progress <= 1.0
	if moon.visible: fx.pose_moon_flyby(moon,moon_progress)
	last_phase = phase; previous_clock = t
	set_meta("festival_state", {"clock":t,"variant":variant,"phase":phase,"track":track_id,"events":event_log.duplicate(true),"moon":moon.visible,"ghost_age":ghost_age,"juggle_age":juggle_age,"steal_age":steal_age,"horn_age":horn_age})

func _ghost_action(age: float) -> void:
	ghost.visible = age >= 0.0 and age < 3.4
	var hit := 1.15
	# Contact holds for one beat, then the cloth peels off before the embarrassed exit.
	var squash := 0.0
	if age >= hit-0.16 and age < hit: squash = (age-hit+0.16)/0.16
	elif age >= hit and age < hit+0.24: squash = 1.0
	elif age >= hit+0.24: squash = maxf(0.0,1.0-(age-hit-0.24)/0.55)
	kit.pose_ghost(ghost,maxf(age,0.0),squash)
	var offset := Vector3(0.0, 0.8, 0.0)
	if age < hit:
		var u := clampf(age/hit,0,1)
		offset = Vector3(2.2*sin(u*PI),0.8+sin(u*PI)*1.2,18.0*(1-u)*(1-u))
	else:
		var u := maxf(age-hit-0.30,0.0)
		offset = Vector3(sin(u*4.0)*exp(-u)*1.0,0.8+maxf(u-0.9,0.0)*3.0,1.3+u*2.4)
	ghost.transform = ghost_anchor.translated_local(offset).scaled_local(Vector3.ONE * 3.0)
	lantern_pivot.rotation.z = sin(maxf(age-hit,0.0)*11.0)*exp(-maxf(age-hit,0.0)*1.6)*0.40 if age >= hit else 0.0
	fx.pose_impact(impact,(age-hit)/0.6)

func _pumpkin_action(age: float) -> void:
	var y := 8.4
	var squash := 0.0
	var sideways := 0.0
	if age >= 0.0:
		if age < 0.45: y += sin(age*28.0)*0.12
		elif age < 1.15: y = 8.4*(1.0-pow((age-0.45)/0.7,2))
		else:
			var b := age-1.15
			y = absf(sin(b*7.0))*exp(-b*2.0)*2.0
			squash = maxf(0.0,1.0-b/0.18)
			sideways = minf(b,2.8)*1.4
	falling.transform = pumpkin_anchor.translated_local(Vector3(sideways,y,0)).scaled_local(Vector3.ONE*1.8)
	falling.rotation.z += -sideways*0.20
	kit.pose_pumpkin(falling,maxf(age,0.0),squash)
	fx.pose_puff(puff,(age-1.15)/0.75)

func sync_sky(camera: Camera3D) -> void:
	if not is_instance_valid(moon) or not moon.visible: return
	# Sky angular position is world-anchored like H07's moon. Camera translation
	# cancels parallax at sky distance; camera rotation never changes moon bearing.
	var yaw := -0.06 + lerpf(-0.19,0.19,clampf(moon_progress,0,1))
	var elevation := 0.31 + sin(moon_progress*PI)*0.035
	var direction := Vector3(sin(yaw)*cos(elevation),sin(elevation),-cos(yaw)*cos(elevation))
	moon.global_transform = Transform3D(Basis.looking_at(direction,Vector3.UP).scaled(Vector3.ONE*23.0),camera.global_position+direction*1300.0)
