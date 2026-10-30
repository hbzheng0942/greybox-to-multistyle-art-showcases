extends "res://shared/game/dog_game.gd"
## A01 variant: native selection has unconditional priority. The supplement only
## selects visible surfaces of the existing 12 bones when the native pool is empty.
var a01_picker
var a01_last_pick: Dictionary = {}
var a01_player_art_contact
const A01_HUD=preload("res://styles/A01/runtime/modules/bca603ba5d6f7b42-a01_hud.gd")
const A01_HELD_CONTACT=preload("res://styles/A01/runtime/modules/b7b190c992c5008a-held_art_contact.gd")
var a01_held_art_contact=A01_HELD_CONTACT.new()

func _update_hud()->void:
	super._update_hud()
	A01_HUD.localize_status(self)

func _handle_grab(delta:float)->void:
	a01_held_art_contact.before_native_input(self)
	super._handle_grab(delta)
	a01_held_art_contact.update(self,delta)

func _release(throw:bool)->void:
	a01_held_art_contact.before_release(self)
	super._release(throw)

# Native movement body below is copied verbatim except first-grab acquisition and declared held yaw.
# Shared _move_dog SHA256: 983c36e083d2f1d3c86b91e7a9d7df30b9c56ec6bacbbd2ff2eb5bb511f4327c
func _move_dog(delta: float) -> void:
	var previous_yaw:float=dog.rotation.y
	var input := Vector2(
		Input.get_action_strength("dog_right") - Input.get_action_strength("dog_left"),
		Input.get_action_strength("dog_back") - Input.get_action_strength("dog_forward")
	)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := right * input.x + forward * -input.y
	if dir.length() > 1.0:
		dir = dir.normalized()

	var speed := ZOOMIES_SPEED if zoomies_left > 0.0 else MOVE_SPEED
	dog.velocity.x = dir.x * speed
	dog.velocity.z = dir.z * speed
	dog.velocity = a01_held_art_contact.limit_translation(self,dog.velocity,delta)
	dog.velocity.y -= GRAVITY * delta
	dog.move_and_slide()

	if dir.length() > 0.1:
		dog.rotation.y = lerp_angle(dog.rotation.y, atan2(-dir.x, -dir.z), delta * 11.0)

	var on_floor := dog.is_on_floor()
	if on_floor and not was_on_floor and absf(dog.velocity.y) > 1.0:
		_play_sfx("thud", dog.global_position, -9.0, randf_range(1.15, 1.3))
	was_on_floor = on_floor
	if on_floor and dog.global_position.y > -0.5:
		var ray := PhysicsRayQueryParameters3D.create(
			dog.global_position + Vector3(0, 0.08, 0), dog.global_position - Vector3(0, 0.2, 0), 1)
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not floor_hit.is_empty() and Vector3(floor_hit["normal"]).y > 0.65:
			last_safe_dog_transform = dog.global_transform
	if a01_player_art_contact!=null:a01_player_art_contact.limit_yaw(self,previous_yaw)
	a01_held_art_contact.limit_dog_yaw(self,previous_yaw,delta)

func _try_grab() -> void:
	if a01_picker == null or a01_picker.has_native_candidate():
		a01_last_pick = {"method":"native"}
		super._try_grab()
		return
	var choice: Dictionary = a01_picker.pick_supplement()
	a01_last_pick = choice.duplicate()
	if not choice.has("body"):
		_show_feedback("靠近展品，再按 E 咬住")
		return
	if choice.get("blocked",false):
		_show_feedback("被挡住了，换个角度咬")
		return
	var body: RigidBody3D = choice.body
	var id: String = body.get_meta("bone_id")
	var forward := -dog.global_transform.basis.z
	if not bool(skel[id]["broken"]):
		_break_bone(id, forward * 2.4 + Vector3(0,.5,0))
		_show_feedback("骨头拽下来了，可以再咬住甩出")
		return
	# Exact selection-commit fields from shared _try_grab. Following, release,
	# throwing, epoch-safe collision cleanup and reset remain inherited methods.
	held = body
	held.set_meta("release_epoch",int(held.get_meta("release_epoch",0))+1)
	held.gravity_scale = 0.0
	held.linear_damp = 6.0
	held.add_collision_exception_with(dog)
	_play_sfx("soft",held.global_position,-2.0,randf_range(1.0,1.2))
	_log("A01 visible-surface grab " + str(held.name))
