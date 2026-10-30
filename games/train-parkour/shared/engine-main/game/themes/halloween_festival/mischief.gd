extends RefCounted
## Collisionless, pooled V2 character gags. Call after the actor's ordinary pose.
## Relative event seconds only; root placement and gameplay state belong to the host.

const DURATION := 3.2
const HAT_PATH := "Rig/Head/Hat"
const HEAD_PATH := "Rig/Head"

func _make_event(label: String, kind: String, owner: Node3D, source: Node3D) -> Node3D:
	var event := Node3D.new()
	event.name = label
	event.visible = false
	var state := {
		"kind": kind, "owner": weakref(owner), "source": weakref(source) if source != null else null,
		"source_visible": source.visible if source != null else false,
		"hidden_source": false, "last_t": -1.0, "aborted": false,
		"ready": source != null, "base_parts": {}, "hand_centers": {}, "internal_rest": [], "duration": DURATION,
	}
	for path in ["Rig/ArmR", "Rig/ArmR/Elbow", "Rig/ArmR/Elbow/Hand", "Rig/ArmL", "Rig/ArmL/Elbow", "Rig/ArmL/Elbow/Hand"]:
		var part := owner.get_node_or_null(path) as Node3D
		if part != null:
			state.base_parts[path] = part.transform
	for side in ["L", "R"]:
		var hand := owner.get_node_or_null("Rig/Arm" + side + "/Elbow/Hand") as Node3D
		if hand != null:
			state.hand_centers[side] = _visual_bounds(hand).get_center()
	event.set_meta("mischief_state", state)
	event.set_meta("event_kind", kind)
	event.set_meta("duration_seconds", DURATION)
	return event

func _reference(state: Dictionary, key: String) -> Node3D:
	var reference = state.get(key)
	if reference is WeakRef:
		var result = reference.get_ref()
		if is_instance_valid(result) and result is Node3D:
			return result
	return null

func _visual_copy(source: Node3D, label: String) -> Node3D:
	# duplicate(0) shares Mesh/Material resources, never duplicates scripts/signals.
	var result := source.duplicate(0) as Node3D
	result.name = label
	_strip_nonvisual(result)
	result.visible = true
	return result

func _visual_bounds(node: Node3D, local := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var found := false
	if node is MeshInstance3D and node.mesh != null:
		result = local * node.get_aabb()
		found = true
	for child in node.get_children():
		if child is Node3D and child.name != "Hat":
			var bounds := _visual_bounds(child, local * child.transform)
			if bounds.size.length_squared() > 0.000001:
				result = result.merge(bounds) if found else bounds
				found = true
	return result

func _ik_to_contact(owner: Node3D, side: String, world_contact: Vector3, weight: float, state: Dictionary) -> bool:
	var solver: Callable = owner.get_meta("pose_arm_target", Callable())
	var reach_query: Callable = owner.get_meta("arm_reach", Callable())
	if not solver.is_valid() or not reach_query.is_valid():
		return false
	if weight <= 0.0001:
		return true
	var data: Dictionary = reach_query.call(side)
	var contact := owner.to_local(world_contact)
	var shoulder: Vector3 = data.shoulder_actor
	var approach := (contact - shoulder).normalized()
	var hand_center: Vector3 = state.hand_centers.get(side, Vector3(0.0, -0.10, 0.0))
	var wrist_target := contact - approach * maxf(hand_center.length(), 0.04)
	var current_wrist: Vector3 = data.wrist_actor
	var target := current_wrist.lerp(wrist_target, clampf(weight, 0.0, 1.0))
	solver.call(side, target, Vector3(-0.8 if side == "L" else 0.8, -0.3, 0.5))
	var hand := owner.get_node_or_null("Rig/Arm" + side + "/Elbow/Hand") as Node3D
	if hand != null and hand_center.length_squared() > 0.00001:
		var desired := (world_contact - hand.global_position).normalized()
		var hand_parent := hand.get_parent() as Node3D
		var local_direction: Vector3 = (hand_parent.global_basis.inverse() * desired).normalized()
		var aimed := Quaternion(hand_center.normalized(), local_direction)
		hand.quaternion = hand.quaternion.slerp(aimed, clampf(weight, 0.0, 1.0))
	return true

func _strip_nonvisual(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Light3D or child is AnimationPlayer or child is AudioStreamPlayer3D or child is GPUParticles3D or child is CPUParticles3D:
			child.free()
		else:
			_strip_nonvisual(child)

func _source_visibility(state: Dictionary, hidden: bool) -> void:
	var source := _reference(state, "source")
	if source == null:
		return
	if hidden:
		if not state.hidden_source:
			state.source_visible = source.visible
			source.visible = false
			state.hidden_source = true
	elif state.hidden_source:
		source.visible = bool(state.source_visible)
		state.hidden_source = false

func _restore_parts(state: Dictionary) -> void:
	var owner := _reference(state, "owner")
	if owner == null:
		return
	for path: String in state.base_parts:
		var part := owner.get_node_or_null(path) as Node3D
		if part != null:
			part.transform = state.base_parts[path]

func _cache_internal_rest(event: Node3D) -> void:
	var state: Dictionary = event.get_meta("mischief_state")
	state.internal_rest.clear()
	for part in event.find_children("*", "Node3D", true, false):
		state.internal_rest.append({"node": weakref(part), "transform": part.transform, "visible": part.visible})

func _restore_internal(state: Dictionary) -> void:
	# Hidden nodes are also part of deterministic seek/capture state. Restore all
	# pooled visuals, while leaving the caller's event root and actor untouched.
	for row: Dictionary in state.internal_rest:
		var part = row.node.get_ref()
		if is_instance_valid(part):
			part.transform = row.transform
			part.visible = row.visible

func _finish(event: Node3D, state: Dictionary, restore_parts := true) -> void:
	_source_visibility(state, false)
	if restore_parts:
		_restore_parts(state)
	_restore_internal(state)
	event.visible = false

func reset(event: Node3D, restore_parts := true) -> void:
	if not is_instance_valid(event) or not event.has_meta("mischief_state"):
		return
	var state: Dictionary = event.get_meta("mischief_state")
	_finish(event, state, restore_parts)
	state.last_t = -1.0
	state.aborted = false
	event.set_meta("event_stage", "idle")

func _ready_for_pose(event: Node3D, owner: Node3D, t: float) -> Dictionary:
	if not is_instance_valid(event) or not event.has_meta("mischief_state"):
		return {}
	var state: Dictionary = event.get_meta("mischief_state")
	if t < float(state.last_t) - 0.00001:
		# Caller already authored this frame's base pose (possibly airborne grab).
		reset(event, false)
	state.last_t = t
	if t < 0.0 or t >= DURATION:
		_finish(event, state, false)
		if t < 0.0:
			state.aborted = false
		event.set_meta("event_stage", "idle" if t < 0.0 else "finished")
		return {}
	if not state.ready or _reference(state, "owner") != owner or _reference(state, "source") == null:
		_finish(event, state, false)
		event.set_meta("event_stage", "source_unavailable")
		return {}
	if not owner.is_inside_tree() or not event.is_inside_tree():
		return {}
	return state

func _arm_rotation(owner: Node3D, path: String, target: Vector3, weight: float, state: Dictionary) -> void:
	var part := owner.get_node_or_null(path) as Node3D
	if part == null or not state.base_parts.has(path):
		return
	var base: Transform3D = state.base_parts[path]
	part.transform = base
	part.quaternion = base.basis.get_rotation_quaternion().slerp(Quaternion.from_euler(target), clampf(weight, 0.0, 1.0))

func _relative_to(node: Node3D, frame: Node3D) -> Transform3D:
	# Compose local transforms when sharing the moving actor's hierarchy. Reading
	# and reapplying world transforms on a static sibling splits physics interpolation.
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != frame:
		if cursor is Node3D:
			result = cursor.transform * result
		cursor = cursor.get_parent()
	if cursor == frame:
		return result
	return frame.global_transform.affine_inverse() * node.global_transform

func _place_from_actor(node: Node3D, actor: Node3D, local: Transform3D) -> void:
	# Event roots may have arbitrary local transforms. On moving hosts they must
	# be descendants of the actor so every render uses the same interpolation chain.
	var parent := node.get_parent() as Node3D
	node.transform = _relative_to(parent, actor).affine_inverse() * local

func build_steal_hat(kit, roof: Node3D) -> Node3D:
	var source := roof.get_node_or_null(HAT_PATH) as Node3D
	var event := _make_event("StealHatEvent", "steal_hat", roof, source)
	var state: Dictionary = event.get_meta("mischief_state")
	state.kit = kit
	if source == null or not kit.has_method("build_ghost"):
		state.ready = false
		return event
	var ghost: Node3D = kit.build_ghost()
	ghost.name = "Ghost"
	event.add_child(ghost)
	var floating := ghost.get_node_or_null("Float") as Node3D
	var ghost_bounds := _visual_bounds(floating if floating != null else ghost)
	state.ghost_hat_anchor = Vector3(ghost_bounds.get_center().x, ghost_bounds.end.y - ghost_bounds.size.y * 0.035, ghost_bounds.get_center().z + ghost_bounds.size.y * 0.025)
	var hat := _visual_copy(source, "TransferHat")
	event.add_child(hat)
	hat.visible = false
	_cache_internal_rest(event)
	return event

func pose_steal_hat(event: Node3D, t: float, roof: Node3D, phase: int) -> void:
	var state := _ready_for_pose(event, roof, t)
	if state.is_empty():
		return
	# Airborne grab wins on this frame; never restore stale lounge arms over it.
	if phase == 2:
		state.aborted = true
		_finish(event, state, false)
		event.set_meta("event_stage", "cancelled_for_airborne_grab")
		return
	if state.aborted:
		_finish(event, state, false)
		return
	event.visible = true
	var source := _reference(state, "source")
	var ghost := event.get_node_or_null("Ghost") as Node3D
	var hat := event.get_node_or_null("TransferHat") as Node3D
	if ghost == null or hat == null:
		reset(event, false)
		return
	var source_local := _relative_to(source, roof)
	var approach := smoothstep(0.0, 0.60, t)
	var leave := smoothstep(2.65, DURATION, t)
	var ghost_offset := Vector3(lerpf(-4.4, -2.05, approach) - leave * 2.4, 0.45 + leave * 1.0, 0.1)
	var panic := smoothstep(1.05, 1.25, t) * (1.0 - smoothstep(1.70, 1.85, t))
	ghost_offset.y += sin(t * 4.0) * 0.10
	var ghost_local := Transform3D(Basis(Vector3.FORWARD, sin(t * 26.0) * 0.12 * panic).scaled(Vector3.ONE * 1.12), ghost_offset)
	_place_from_actor(ghost, roof, ghost_local)
	state.kit.pose_ghost(ghost, t, panic * 0.12)
	var reach := smoothstep(0.55, 0.85, t) * (1.0 - smoothstep(2.45, 2.90, t))
	if not _ik_to_contact(roof, "R", roof.global_transform * (source_local.origin - Vector3.UP * 0.12), reach, state):
		_arm_rotation(roof, "Rig/ArmR", Vector3(0.05, 0.0, 2.0), reach, state)
		_arm_rotation(roof, "Rig/ArmR/Elbow", Vector3(0.0, 0.0, 1.20), reach, state)
		_arm_rotation(roof, "Rig/ArmR/Elbow/Hand", Vector3(0.0, 0.0, -0.4), reach, state)
	var floating := ghost.get_node_or_null("Float") as Node3D
	var head_frame := ghost_local * floating.transform if floating != null else ghost_local
	# Keep the stolen hat upright on the ghost instead of inheriting the lounging
	# skeleton's pitched head. Preserve its authored size and follow Float's hover.
	var hat_basis := head_frame.basis.orthonormalized() * Basis(Vector3.FORWARD, -0.10) * Basis.from_scale(source_local.basis.get_scale())
	var on_ghost := Transform3D(hat_basis, head_frame * state.ghost_hat_anchor)
	if t < 0.45:
		_source_visibility(state, false)
		hat.visible = false
		event.set_meta("event_stage", "eyeing_hat")
	elif t < 0.95:
		_source_visibility(state, true)
		hat.visible = true
		var u := smoothstep(0.45, 0.95, t)
		var target := source_local.interpolate_with(on_ghost, u)
		target.origin += Vector3.UP * sin(u * PI) * 0.65
		_place_from_actor(hat, roof, target)
		event.set_meta("event_stage", "stealing_hat")
	elif t < 1.78:
		_source_visibility(state, true)
		hat.visible = true
		_place_from_actor(hat, roof, on_ghost)
		event.set_meta("event_stage", "hat_over_eyes")
	elif t < 2.65:
		_source_visibility(state, true)
		hat.visible = true
		var u := smoothstep(1.78, 2.65, t)
		var target := on_ghost.interpolate_with(source_local, u)
		target.origin += Vector3.UP * sin(u * PI) * 1.00
		target.basis = target.basis * Basis(Vector3.RIGHT, TAU * u)
		_place_from_actor(hat, roof, target)
		event.set_meta("event_stage", "tossing_hat_back")
	else:
		_source_visibility(state, false)
		hat.visible = false
		event.set_meta("event_stage", "recovering")

func build_head_juggle(kit, skeleton: Node3D) -> Node3D:
	var source := skeleton.get_node_or_null(HEAD_PATH) as Node3D
	var event := _make_event("HeadJuggleEvent", "head_juggle", skeleton, source)
	var state: Dictionary = event.get_meta("mischief_state")
	state.kit = kit
	if source != null:
		event.add_child(_visual_copy(source, "TransferHead"))
		state.head_bounds = _visual_bounds(source)
	_cache_internal_rest(event)
	return event

func pose_head_juggle(event: Node3D, t: float, skeleton: Node3D) -> void:
	var state := _ready_for_pose(event, skeleton, t)
	if state.is_empty():
		return
	var source := _reference(state, "source")
	var head := event.get_node_or_null("TransferHead") as Node3D
	if head == null:
		reset(event)
		return
	event.visible = true
	_source_visibility(state, true)
	var source_local := _relative_to(source, skeleton)
	var target := source_local
	var hold := smoothstep(0.35, 0.88, t) * (1.0 - smoothstep(2.85, DURATION, t))
	var lift := smoothstep(1.35, 2.03, t)
	var cradle := source_local
	cradle.origin = source_local.origin + Vector3(0.0, -0.30, 0.50)
	if t < 0.45:
		var wobble := sin(t / 0.45 * PI * 2.0) * 0.23
		target.basis = source_local.basis * Basis(Vector3.FORWARD, wobble)
		event.set_meta("event_stage", "loose_head")
	elif t < 0.95:
		var u := clampf((t - 0.45) / 0.50, 0.0, 1.0)
		target = source_local.interpolate_with(cradle, u * u)
		target.basis = target.basis * Basis(Vector3.FORWARD, sin(u * PI) * 0.3)
		event.set_meta("event_stage", "catching_head")
	elif t < 1.35:
		target = cradle
		target.basis = target.basis * Basis(Vector3.UP, sin((t - 0.95) / 0.4 * PI) * 0.25)
		event.set_meta("event_stage", "holding_head")
	elif t < 2.03:
		var u := smoothstep(1.35, 2.03, t)
		target = cradle.interpolate_with(source_local, u)
		# Wrong-way means facing backward, not inverted: a pointed hat must not
		# plunge through the chest when the skull reaches its neck socket.
		target.basis = target.basis * Basis(Vector3.UP, PI * u)
		event.set_meta("event_stage", "backwards_head")
	elif t < 2.32:
		target.basis = target.basis * Basis(Vector3.UP, PI)
		event.set_meta("event_stage", "wrong_way_pause")
	elif t < 2.85:
		var u := smoothstep(2.32, 2.85, t)
		target.basis = target.basis * Basis(Vector3.UP, PI * (1.0 - u) - sin(u * PI) * 0.12)
		event.set_meta("event_stage", "turning_head_right")
	else:
		_source_visibility(state, false)
		head.visible = false
		event.set_meta("event_stage", "recovering")
	if t < 2.85:
		head.visible = true
		_place_from_actor(head, skeleton, target)
	# Contact points follow the actual imported head bounds, excluding the hat.
	# Left/right stay on the actor's sides even while the head rotates backward.
	var bounds: AABB = state.head_bounds
	var grip_center := target * Vector3(bounds.get_center().x, bounds.position.y + bounds.size.y * 0.22, bounds.get_center().z)
	var half_width := bounds.size.x * target.basis.get_scale().x * 0.44
	for side in ["L", "R"]:
		var sign_value := -1.0 if side == "L" else 1.0
		var grip := grip_center + Vector3.RIGHT * half_width * sign_value
		if not _ik_to_contact(skeleton, side, skeleton.global_transform * grip, hold, state):
			_arm_rotation(skeleton, "Rig/Arm" + side, Vector3(lerpf(-0.75, -1.45, lift), 0.0, -sign_value * 0.25), hold, state)
			_arm_rotation(skeleton, "Rig/Arm" + side + "/Elbow", Vector3(lerpf(-0.65, -0.45, lift), 0, 0), hold, state)
			_arm_rotation(skeleton, "Rig/Arm" + side + "/Elbow/Hand", Vector3(-PI * 0.5, 0, 0), hold, state)

func pose_startle(actor: Node3D, age: float, kind: String) -> void:
	# A short additive response to the host's optional horn. The ordinary actor
	# pose must run first each frame; inactive ages deliberately change nothing.
	if age < 0.0 or age > 0.65 or not is_instance_valid(actor):
		return
	var amount := sin(clampf(age / 0.65, 0.0, 1.0) * PI)
	if kind == "ghost":
		var body := actor.get_node_or_null("Float") as Node3D
		if body == null:
			return
		body.position.y += amount * 0.16
		body.rotation.z += sin(age * 30.0) * 0.13 * amount
		# G1's ordinary ghost pose resets position/rotation but intentionally keeps
		# authored scale. Do not compound scale here or leave it changed at expiry.
		for side in ["L", "R"]:
			var arm := body.get_node_or_null("Arm" + side) as Node3D
			if arm != null:
				arm.rotation.z += (-0.45 if side == "L" else 0.45) * amount
	elif kind == "skeleton":
		var head := actor.get_node_or_null(HEAD_PATH) as Node3D
		if head != null:
			head.rotation.z += sin(age * 27.0) * 0.16 * amount
			var jaw := head.get_node_or_null("Jaw") as Node3D
			if jaw != null:
				jaw.rotation.x += amount * 0.18
		var rig := actor.get_node_or_null("Rig") as Node3D
		if rig != null:
			rig.rotation.z += sin(age * 22.0) * 0.06 * amount
