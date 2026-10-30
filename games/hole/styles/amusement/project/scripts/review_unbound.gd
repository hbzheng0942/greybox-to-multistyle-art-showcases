extends Node3D
## Independent review scene for the two unbound visual groups (R04 / R07).
##
## This scene is deliberately NOT referenced by scenes/Main.tscn. It exists so the groups can
## be reviewed without being dropped into the playable street, without being given a swallow ID,
## and without a paid generation task. Everything here is a static showcase: no simulation, no
## timer, no ledger.

const UnboundGroups = preload("res://scripts/unbound_groups.gd")
const Kit = preload("res://scripts/art_kit.gd")

func _ready() -> void:
	var groups = UnboundGroups.new()
	var kit = Kit.new()

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.78, 0.88)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation = Vector3(-1.03, -0.55, 0.0)
	light.light_color = Color(1.0, 0.96, 0.88)
	light.light_energy = 0.95
	light.shadow_enabled = true
	add_child(light)

	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 42.0
	camera.position = Vector3(0.0, 2.35, 5.4)
	camera.look_at(Vector3(0.0, 0.35, 0.0), Vector3.UP)
	camera.current = true
	add_child(camera)

	var floor: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(14.0, 8.0)
	floor.mesh = plane
	floor.material_override = kit.shared_material(Color("cfcab8"))
	add_child(floor)

	var back: MeshInstance3D = MeshInstance3D.new()
	var wall: BoxMesh = BoxMesh.new()
	wall.size = Vector3(14.0, 4.0, 0.3)
	back.mesh = wall
	back.position = Vector3(0.0, 2.0, -2.6)
	back.material_override = kit.shared_material(Color("e2d4b4"))
	add_child(back)

	_add_group(groups, "R04", "R04 DONUT DECOR SET / HOLD", Vector3(-1.85, 0.0, 0.35), "R04 / PACKED_GROUP / NO BINDING")
	_add_group(groups, "R07", "R07 BOBA PROP SET / HOLD", Vector3(1.75, 0.0, 0.35), "R07 / PACKED_GROUP / NO BINDING")

	var banner: Label = Label.new()
	banner.position = Vector2(28.0, 22.0)
	banner.add_theme_font_size_override("font_size", 20)
	banner.text = "REVIEW ONLY — unbound packed groups\nNot in the 215-unit ledger. Not placed on the playable street."
	add_child(banner)

func _add_group(groups, ref_id: String, title: String, position: Vector3, subtitle: String) -> void:
	var holder: Node3D = Node3D.new()
	holder.position = position
	add_child(holder)
	holder.add_child(groups.build(ref_id))
	var label: Label3D = Label3D.new()
	label.text = title
	label.font_size = 34
	label.pixel_size = 0.0055
	label.modulate = Color("2b3238")
	label.shaded = false
	label.outline_size = 0
	label.position = Vector3(0.0, 1.5, 0.0)
	holder.add_child(label)
	var sub: Label3D = Label3D.new()
	sub.text = subtitle
	sub.font_size = 22
	sub.pixel_size = 0.0050
	sub.modulate = Color("55636e")
	sub.shaded = false
	sub.outline_size = 0
	sub.position = Vector3(0.0, 1.28, 0.0)
	holder.add_child(sub)
