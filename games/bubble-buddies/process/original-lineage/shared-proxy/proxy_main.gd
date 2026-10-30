extends "res://shared/greybox/main.gd"
## S6 presentation host: all game rules/input/collisions remain in original main.
const ProxyOverlay = preload("res://process/original-lineage/shared-proxy/overlay.gd")
var proxy_style := "D01"
var proxy_overlay: Node3D
var presentation_snapshots: Dictionary = {}
var proxy_epoch := 0
var initial_collision_signature := ""

func _ready() -> void:
	super._ready()
	initial_collision_signature = collision_signature()
	proxy_overlay = ProxyOverlay.new()
	proxy_overlay.main = self
	proxy_overlay.profile = JSON.parse_string(FileAccess.get_file_as_string("res://process/original-lineage/%s/proxy/profile.json" % proxy_style))
	add_child(proxy_overlay)
	DisplayServer.window_set_title("Bubble Buddies | %s | S6 ART PROXY" % proxy_style)

func interact_with(pid: int, slot: String) -> String:
	# Capture before original model.interact removes a delivered pet. No event drain here.
	for id in model.pets:
		presentation_snapshots[id] = model.pets[id].duplicate(true)
	return super.interact_with(pid, slot)

func _show_reunion(id: int, pet_name: String, quality: Dictionary = {}) -> void:
	var full: Dictionary = presentation_snapshots.get(id, {}).duplicate(true)
	full.merge(quality, true)
	super._show_reunion(id, pet_name, full)
	if not reunion_pets.is_empty():
		reunion_pets.back()["appearance_snapshot"] = full.duplicate(true)
		reunion_pets.back()["pet_id"] = id

func start_shift(duo: bool = true, seed_value: int = -1) -> void:
	proxy_epoch += 1
	presentation_snapshots.clear()
	if is_instance_valid(proxy_overlay):
		proxy_overlay.reset_dynamic()
	super.start_shift(duo, seed_value)

func collision_signature() -> String:
	var records: Array[String] = []
	for node in find_children("*", "CollisionShape3D", true, false):
		var shape = node.shape
		var detail := str(shape.size) if shape is BoxShape3D else str([shape.radius, shape.height])
		records.append(str(node.get_path()) + "|" + str(node.transform) + "|" + str(Vector3.ZERO if node.get_parent() is CharacterBody3D else node.get_parent().position) + "|" + detail + "|" + str(node.disabled) + "|" + str(node.get_parent().collision_layer) + "|" + str(node.get_parent().collision_mask) + "|" + str(node.get_parent().global_basis))
	return "\n".join(records).sha256_text()
