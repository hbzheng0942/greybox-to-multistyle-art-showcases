extends RefCounted
const World=preload("res://../art/train-parkour/shared/tools/full_scene_world.gd")
func build(session:Node3D)->Node3D:
	return World.new().build_style(session,"odd-logistics")
