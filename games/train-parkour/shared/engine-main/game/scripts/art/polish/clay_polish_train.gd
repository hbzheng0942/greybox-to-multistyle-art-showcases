extends Node
func _ready() -> void:
	var geometry:=get_parent().get_node("Actors/Train/VisualRoot/TrickPivot/Geometry")
	for child in geometry.get_children():
		if child is MeshInstance3D and not "Wheel" in str(child.name):child.hide()
	var shell: Node3D=load("res://assets/clay-polish/hero-carriage.glb").instantiate()
	geometry.add_child(shell);shell.position=Vector3(0,.5,0)
	var clay=load("res://scripts/art/polish/clay_polish_surface.gd").new()
	for part in shell.find_children("*","MeshInstance3D",true,false):
		for index in part.mesh.get_surface_count():
			part.set_surface_override_material(index,clay.converted(part.get_active_material(index)))
