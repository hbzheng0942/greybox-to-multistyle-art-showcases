extends RefCounted
## Primitive placeholders only. All collisions and gameplay are owned elsewhere.

static var font_cache: Font

static func ui_font() -> Font:
	if font_cache != null:
		return font_cache
	var candidates := PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "Arial Unicode MS", "Arial", "DejaVu Sans"])
	var available := OS.get_system_fonts()
	for family in candidates:
		if family in available:
			var font := SystemFont.new()
			font.font_names = PackedStringArray([family])
			font_cache = font
			return font_cache
	font_cache = ThemeDB.fallback_font
	return font_cache

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

static func box(parent: Node3D, title: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = pos
	return node

static func ball(parent: Node3D, title: String, pos: Vector3, scale_value: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = pos
	node.scale = scale_value
	return node

static func cylinder(parent: Node3D, title: String, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = pos
	return node

static func label(parent: Node3D, title: String, pos: Vector3, color: Color = Color.WHITE, font_size: int = 28) -> Label3D:
	var node := Label3D.new()
	node.font = ui_font()
	node.text = title
	node.font_size = font_size
	node.outline_size = 8
	node.modulate = color
	node.pixel_size = 0.008
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.no_depth_test = true
	parent.add_child(node)
	node.position = pos
	return node

static func treatment_station(parent: Node3D, pos: Vector3) -> Node3D:
	# Presentation only, within the 1.15m base footprint. Open ribs keep the pet visible.
	var root := Node3D.new()
	root.name = "TreatmentHood"
	parent.add_child(root)
	root.position = pos
	var frame := Color("9ec9b8")
	var rim := Color("e7eee1")
	for z in [-0.43, 0.43]:
		for side in [-1, 1]:
			box(root, "HoodPost", Vector3(side * 0.52, 0.96, z), Vector3(0.07, 0.48, 0.07), frame)
		for segment in 6:
			var start := PI * float(segment) / 6.0
			var end := PI * float(segment + 1) / 6.0
			var a := Vector3(cos(start) * 0.52, 1.20 + sin(start) * 0.62, z)
			var b := Vector3(cos(end) * 0.52, 1.20 + sin(end) * 0.62, z)
			_visual_rod(root, "CanopyRib", a, b, 0.055, rim)
	box(root, "CanopyRidge", Vector3(0, 1.82, 0), Vector3(0.09, 0.09, 0.92), frame)
	var ring := MeshInstance3D.new()
	ring.name = "BubbleRim"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.46
	torus.outer_radius = 0.55
	torus.rings = 20
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = material(rim)
	root.add_child(ring)
	ring.position.y = 0.78
	# The bubble shower sits above the back edge, unlike the open bath's faucet.
	box(root, "BubblePump", Vector3(0, 1.50, -0.47), Vector3(0.32, 0.26, 0.13), frame)
	for side in [-1, 1]:
		ball(root, "PumpBubble", Vector3(side * 0.085, 1.51, -0.38), Vector3.ONE * 0.055, Color("f1efd9"))
	var bubbles := Node3D.new()
	bubbles.name = "Bubbles"
	root.add_child(bubbles)
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var bubble := ball(bubbles, "Bubble%d" % index, Vector3(sin(angle) * 0.40, 1.04 + float(index % 3) * 0.15, cos(angle) * 0.40), Vector3.ONE * (0.065 + float(index % 2) * 0.025), Color("e7f5dc"))
		bubble.set_meta("rest_position", bubble.position)
	bubbles.visible = false
	var ready := Node3D.new()
	ready.name = "ReadyMarker"
	root.add_child(ready)
	ready.position = Vector3(0.36, 1.82, 0.0)
	_visual_rod(ready, "CheckShort", Vector3(-0.12, 0.04, 0), Vector3(-0.03, -0.05, 0), 0.06, Color("f2e6aa"))
	_visual_rod(ready, "CheckLong", Vector3(-0.03, -0.05, 0), Vector3(0.13, 0.14, 0), 0.06, Color("f2e6aa"))
	ready.visible = false
	return root

static func _visual_rod(parent: Node3D, title: String, a: Vector3, b: Vector3, width: float, color: Color) -> MeshInstance3D:
	var segment := b - a
	var rod := box(parent, title, (a + b) * 0.5, Vector3(width, segment.length(), width), color)
	rod.quaternion = Quaternion(Vector3.UP, segment.normalized())
	return rod

static func paw_station(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "PawCareTools"
	parent.add_child(root)
	root.position = pos
	# File, rounded clipper and paw-shaped mat: cosmetic props inside the counter.
	ball(root, "PawPad", Vector3(0, 0.75, 0.10), Vector3(0.27, 0.025, 0.22), Color("f4d6d6"))
	for index in 3:
		ball(root, "ToePad", Vector3(-0.22 + index * 0.22, 0.75, -0.20), Vector3(0.095, 0.025, 0.11), Color("f4d6d6"))
	var file := box(root, "PawFile", Vector3(0.40, 0.80, 0.10), Vector3(0.10, 0.05, 0.51), Color("e9dfed"))
	file.rotation.y = -0.22
	for side in [-1, 1]:
		var handle := box(root, "ClipperHandle", Vector3(-0.38 + side * 0.055, 0.82, 0.20), Vector3(0.055, 0.06, 0.30), Color("9a728e"))
		handle.rotation.y = side * 0.25
	ball(root, "ClipperTip", Vector3(-0.38, 0.82, 0.02), Vector3(0.08, 0.035, 0.065), Color("e1e4e8"))
	return root

static func player(parent: Node3D, index: int, color: Color) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Player%d" % (index + 1)
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.2
	shape.shape = capsule
	shape.position.y = 0.6
	body.add_child(shape)
	parent.add_child(body)
	var pivot := Node3D.new()
	pivot.name = "Visual"
	body.add_child(pivot)
	cylinder(pivot, "FootMarker", Vector3(0, 0.035, 0), 0.39, 0.035, color)
	cylinder(pivot, "Apron", Vector3(0, 0.58, 0), 0.27, 0.57, color)
	box(pivot, "ApronPocket", Vector3(0, 0.55, -0.27), Vector3(0.24, 0.18, 0.035), color.lightened(0.30))
	ball(pivot, "Head", Vector3(0, 1.05, 0), Vector3.ONE * 0.26, Color("f4dcc3"))
	# Shape and the existing P-number both identify a player without relying on hue.
	if index == 0:
		ball(pivot, "Cap", Vector3(0, 1.25, 0), Vector3(0.30, 0.16, 0.28), color.lightened(0.15))
		ball(pivot, "CapButton", Vector3(0, 1.41, 0), Vector3.ONE * 0.06, Color("edf0e9"))
		box(pivot, "CapBrim", Vector3(0, 1.22, -0.25), Vector3(0.34, 0.05, 0.25), color)
	else:
		box(pivot, "Cap", Vector3(0, 1.30, 0), Vector3(0.50, 0.24, 0.43), color.lightened(0.15))
		box(pivot, "CapBand", Vector3(0, 1.20, 0), Vector3(0.53, 0.07, 0.45), Color("edf0e9"))
		for side in [-1, 1]:
			ball(pivot, "CapCorner%d" % side, Vector3(side * 0.21, 1.43, 0), Vector3(0.075, 0.085, 0.15), color.lightened(0.15))
	for side in [-1, 1]:
		ball(pivot, "Hand%d" % side, Vector3(side * 0.32, 0.65, -0.04), Vector3.ONE * 0.10, Color("f4dcc3"))
		ball(pivot, "Eye%d" % side, Vector3(side * 0.085, 1.07, -0.23), Vector3.ONE * 0.035, Color("26323b"))
		box(pivot, "Boot%d" % side, Vector3(side * 0.14, 0.15, -0.03), Vector3(0.18, 0.23, 0.28), Color("324552"))
	ball(pivot, "Smile", Vector3(0, 0.98, -0.244), Vector3(0.065, 0.027, 0.018), Color("835d50"))
	label(body, "P%d" % (index + 1), Vector3(0, 1.65, 0), color.lightened(0.4), 30)
	for part: Node3D in pivot.get_children():
		part.set_meta("rest_position", part.position)
	return body

static func animate_player(body: CharacterBody3D, stride: float, amount: float, carrying: bool, working: bool, clock: float, selected: bool) -> void:
	var pivot: Node3D = body.get_node("Visual")
	for part: Node3D in pivot.get_children():
		var rest: Vector3 = part.get_meta("rest_position", part.position)
		part.position = rest
		part.rotation.x = 0.0
		if part.name == "FootMarker":
			part.scale = Vector3.ONE * (1.18 if selected else 0.88)
			continue
		part.position.y += absf(sin(stride)) * 0.045 * amount
	for side in [-1, 1]:
		var boot: Node3D = pivot.get_node("Boot%d" % side)
		var swing: float = sin(stride) * side * amount
		boot.position.z += swing * 0.17
		boot.position.y += maxf(swing, 0.0) * 0.10
		boot.rotation.x = swing * 0.38
		var hand: Node3D = pivot.get_node("Hand%d" % side)
		if carrying:
			hand.position += Vector3(-side * 0.04, 0.12, -0.30)
		elif working:
			hand.position += Vector3(0, 0.06, -0.24 + sin(clock * 20.0 + side) * 0.06)
		else:
			hand.position.z -= swing * 0.18

static func cutaway(mesh: MeshInstance3D, opacity: float = 0.20) -> void:
	# Visibility only: full-height collision and the room boundary stay intact.
	var mat: StandardMaterial3D = mesh.material_override.duplicate()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = opacity
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func pet(parent: Node3D, id: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Pet%d" % id
	parent.add_child(root)
	var pivot := Node3D.new()
	pivot.name = "Visual"
	root.add_child(pivot)
	# Three readable silhouettes, not breed-specific art or different gameplay sizes.
	var variant := posmod(id, 3)
	var coats := [Color("d8c9b4"), Color("e5e1d9"), Color("b4b9c2")]
	var coat: Color = coats[id % coats.size()]
	var body_scale := Vector3(0.34, 0.28, 0.45)
	var head_scale := Vector3(0.31, 0.29, 0.29)
	if variant == 1:
		body_scale = Vector3(0.32, 0.31, 0.37)
		head_scale = Vector3(0.28, 0.28, 0.27)
	elif variant == 2:
		body_scale = Vector3(0.39, 0.31, 0.37)
		head_scale = Vector3(0.35, 0.30, 0.29)
	ball(pivot, "Body", Vector3(0, 0.40, 0.08), body_scale, coat)
	ball(pivot, "Chest", Vector3(0, 0.40, -0.19), Vector3(0.23, 0.23, 0.23), coat.lightened(0.18))
	ball(pivot, "Head", Vector3(0, 0.65, -0.35), head_scale, coat)
	ball(pivot, "Muzzle", Vector3(0, 0.57, -0.60), Vector3(0.21, 0.14, 0.14), coat.lightened(0.24))
	ball(pivot, "Nose", Vector3(0, 0.64, -0.72), Vector3(0.075, 0.055, 0.045), Color("26323b"))
	ball(pivot, "Smile", Vector3(0, 0.535, -0.724), Vector3(0.11, 0.045, 0.02), Color("544c49"))
	ball(pivot, "Tongue", Vector3(0.025, 0.49, -0.735), Vector3(0.055, 0.055, 0.025), Color("d8a8a1"))
	for side in [-1, 1]:
		if variant == 0:
			var ear := ball(pivot, "Ear%d" % side, Vector3(side * 0.31, 0.57, -0.30), Vector3(0.13, 0.28, 0.16), coat.darkened(0.20))
			ear.rotation.z = side * 0.18
		elif variant == 1:
			var ear := cylinder(pivot, "Ear%d" % side, Vector3(side * 0.20, 0.97, -0.30), 0.135, 0.38, coat.darkened(0.20))
			(ear.mesh as CylinderMesh).top_radius = 0.015
			ear.rotation.z = -side * 0.22
			ball(pivot, "InnerEar%d" % side, Vector3(side * 0.205, 0.98, -0.38), Vector3(0.055, 0.105, 0.025), coat.lightened(0.25))
		else:
			ball(pivot, "Ear%d" % side, Vector3(side * 0.31, 0.85, -0.31), Vector3(0.14, 0.13, 0.13), coat.darkened(0.20))
			ball(pivot, "Cheek%d" % side, Vector3(side * 0.25, 0.60, -0.53), Vector3(0.13, 0.15, 0.12), coat.lightened(0.10))
		ball(pivot, "EyeWhite%d" % side, Vector3(side * 0.125, 0.77, -0.59), Vector3(0.075, 0.085, 0.045), Color("f4f1e9"))
		ball(pivot, "Eye%d" % side, Vector3(side * 0.125, 0.775, -0.626), Vector3(0.043, 0.060, 0.024), Color("26323b"))
		ball(pivot, "EyeGlint%d" % side, Vector3(side * 0.125 - 0.012, 0.796, -0.648), Vector3.ONE * 0.013, Color("ffffff"))
		var brow := ball(pivot, "Brow%d" % side, Vector3(side * 0.14, 0.86, -0.57), Vector3(0.082, 0.025, 0.04), coat.darkened(0.30))
		brow.rotation.z = side * 0.20
		for z in [-0.15, 0.32]:
			ball(pivot, "Leg", Vector3(side * 0.23, 0.22, z), Vector3(0.10, 0.15, 0.11), coat.darkened(0.05))
			ball(pivot, "Paw", Vector3(side * 0.23, 0.13, z), Vector3(0.13, 0.12, 0.17), coat.lightened(0.15))
	var tail := ball(pivot, "Tail", Vector3(0, 0.58, 0.51), Vector3(0.10, 0.25, 0.10) if variant != 2 else Vector3(0.16, 0.17, 0.15), coat.darkened(0.15))
	tail.rotation.x = 0.5
	var dirt := Node3D.new()
	dirt.name = "Dirt"
	pivot.add_child(dirt)
	ball(dirt, "Spot0", Vector3(-0.19, 0.65, 0.08), Vector3(0.13, 0.025, 0.15), Color("795747"))
	ball(dirt, "Spot1", Vector3(0.19, 0.62, 0.25), Vector3(0.12, 0.03, 0.11), Color("795747"))
	ball(dirt, "Spot2", Vector3(0.14, 0.89, -0.31), Vector3(0.10, 0.025, 0.08), Color("795747"))
	var foam := Node3D.new()
	foam.name = "Foam"
	pivot.add_child(foam)
	for i in range(6):
		ball(foam, "Bubble%d" % i, Vector3(sin(i * 2.3) * 0.25, 0.69 + (i % 2) * 0.08, cos(i * 2.3) * 0.26), Vector3.ONE * (0.13 + (i % 3) * 0.025), Color("d5f4f5"))
	foam.visible = false
	var ribbon := Node3D.new()
	ribbon.name = "Ribbon"
	pivot.add_child(ribbon)
	for side in [-1, 1]:
		var bow := ball(ribbon, "Bow%d" % side, Vector3(side * 0.105, 0.40, -0.44), Vector3(0.11, 0.09, 0.055), Color("9ebaa3"))
		bow.rotation.z = side * 0.35
	ball(ribbon, "Knot", Vector3(0, 0.40, -0.48), Vector3.ONE * 0.055, Color("dbe2d9"))
	ribbon.visible = false
	_pet_feedback_nodes(pivot, coat)
	_pet_comic_nodes(pivot, coat)
	var status := label(root, "", Vector3(0, 1.32, 0), Color.WHITE, 25)
	status.name = "Status"
	return root

static func _pet_feedback_nodes(pivot: Node3D, coat: Color) -> void:
	# These presentation-only hooks are driven by main.gd; all start hidden.
	var paws := Node3D.new()
	paws.name = "PawBadge"
	pivot.add_child(paws)
	for side in [-1, 1]:
		ball(paws, "CleanPaw", Vector3(side * 0.23, 0.19, -0.24), Vector3(0.105, 0.035, 0.07), Color("e9d0dd"))
	paws.visible = false
	var paw_sparkles := Node3D.new()
	paw_sparkles.name = "PawSparkles"
	pivot.add_child(paw_sparkles)
	for index in 4:
		var sparkle := box(paw_sparkles, "PawSpark%d" % index, Vector3(-0.40 + index * 0.27, 0.20 + float(index % 2) * 0.12, -0.42), Vector3(0.035, 0.12, 0.035), Color("f9e4c5"))
		sparkle.rotation.z = PI / 4
		sparkle.set_meta("rest_position", sparkle.position)
	paw_sparkles.visible = false
	var fleas := Node3D.new()
	fleas.name = "Fleas"
	pivot.add_child(fleas)
	var flea_positions := [Vector3(-0.36, 0.79, 0.12), Vector3(0.35, 0.90, 0.10), Vector3(-0.10, 0.99, 0.22), Vector3(0.23, 0.70, 0.44)]
	for index in 4:
		var flea := Node3D.new()
		flea.name = "Flea%d" % index
		fleas.add_child(flea)
		flea.position = flea_positions[index]
		flea.set_meta("rest_position", flea.position)
		# Tiny antennaed jumping beans: a readable infestation cue without distress.
		ball(flea, "Bean", Vector3.ZERO, Vector3(0.045, 0.065, 0.045), Color("dc9c56") if index % 2 == 0 else Color("b8a1d0"))
		for side in [-1, 1]:
			_visual_rod(flea, "Antenna", Vector3(side * 0.02, 0.04, 0), Vector3(side * 0.055, 0.09, 0), 0.016, Color("605868"))
	fleas.visible = false
	var trim := Node3D.new()
	trim.name = "TrimTuft"
	pivot.add_child(trim)
	for index in 5:
		var clip := Node3D.new()
		clip.name = "Clip%d" % index
		trim.add_child(clip)
		var side := -1.0 if index % 2 == 0 else 1.0
		clip.position = Vector3(side * (0.38 + float(index % 2) * 0.08), 0.26 + float(index % 3) * 0.10, -0.23 + float(index) * 0.13)
		clip.set_meta("rest_position", clip.position)
		var curl := ball(clip, "Curl", Vector3.ZERO, Vector3(0.09, 0.035, 0.035), coat.lightened(0.22))
		curl.rotation.z = side * (0.3 + float(index) * 0.2)
		ball(clip, "Tip", Vector3(side * 0.05, 0.025, 0), Vector3(0.035, 0.04, 0.035), coat.lightened(0.22))
	trim.visible = false
	var towel := Node3D.new()
	towel.name = "TowelWrap"
	pivot.add_child(towel)
	ball(towel, "Wrap", Vector3(0, 0.40, 0.08), Vector3(0.42, 0.34, 0.43), Color("e2e6df"))
	box(towel, "Fold", Vector3(0, 0.72, 0.10), Vector3(0.17, 0.035, 0.68), Color("bdc8c7"))
	ball(towel, "Tuck", Vector3(0.33, 0.50, -0.08), Vector3(0.13, 0.17, 0.11), Color("e2e6df"))
	towel.visible = false
	var fluff := Node3D.new()
	fluff.name = "Fluff"
	pivot.add_child(fluff)
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		ball(fluff, "Tuft%d" % i, Vector3(sin(angle) * 0.29, 0.47 + float(i % 2) * 0.10, 0.08 + cos(angle) * 0.31), Vector3(0.17, 0.20, 0.18), coat.lightened(0.10))
	fluff.visible = false
	var drops := Node3D.new()
	drops.name = "WetDrops"
	pivot.add_child(drops)
	for side in [-1, 1]:
		ball(drops, "Drop%d" % side, Vector3(side * 0.35, 0.36, -0.03), Vector3(0.06, 0.13, 0.06), Color("91c8d6"))
		ball(drops, "Bead%d" % side, Vector3(side * 0.22, 0.67, 0.18), Vector3(0.055, 0.045, 0.065), Color("b8dce2"))
	drops.visible = false
	var alert := Node3D.new()
	alert.name = "Alert"
	pivot.add_child(alert)
	# Offset to the side so the exclamation does not obscure the status text.
	var mark := box(alert, "Stroke", Vector3(0.51, 1.02, 0), Vector3(0.065, 0.24, 0.065), Color("edc181"))
	mark.material_override = material(Color("edc181"), true)
	var dot := ball(alert, "Dot", Vector3(0.51, 0.82, 0), Vector3.ONE * 0.045, Color("edc181"))
	dot.material_override = material(Color("edc181"), true)
	alert.visible = false


static func _pet_comic_nodes(pivot: Node3D, coat: Color) -> void:
	# Presentation only. Oversized tufts preserve the same pet/physics footprint.
	var frizz := Node3D.new()
	frizz.name = "Frizz"
	pivot.add_child(frizz)
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var tuft := ball(frizz, "Puff%d" % index, Vector3(sin(angle) * 0.42, 0.55 + float(index % 3) * 0.10, 0.12 + cos(angle) * 0.34), Vector3.ONE * (0.24 + float(index % 2) * 0.04), coat.lightened(0.12))
		tuft.set_meta("rest_scale", tuft.scale)
	# A rear crown makes the head visibly explode into a cotton ball while the
	# eyes, muzzle and smiling tongue stay in front of the silhouette.
	for index in 7:
		var angle := PI * float(index) / 6.0
		ball(frizz, "Crown%d" % index, Vector3(cos(angle) * 0.38, 0.79 + sin(angle) * 0.30, -0.27), Vector3.ONE * 0.23, coat.lightened(0.16))
	frizz.visible = false
	var crooked := Node3D.new()
	crooked.name = "Crooked"
	pivot.add_child(crooked)
	for index in 4:
		var tuft := ball(crooked, "SideSwept%d" % index, Vector3(-0.12 + float(index) * 0.10, 1.02 - float(index) * 0.045, -0.53), Vector3(0.12, 0.19, 0.09), coat.darkened(0.12))
		tuft.rotation.z = -0.65
	# The short patch is clipped coat, never skin or an injury cue.
	ball(crooked, "ShortPatch", Vector3(-0.24, 0.95, -0.38), Vector3(0.12, 0.035, 0.11), coat.lightened(0.28))
	crooked.visible = false
	var repairing := Node3D.new()
	repairing.name = "RepairSparkles"
	pivot.add_child(repairing)
	for index in 5:
		var spark := box(repairing, "CombSpark%d" % index, Vector3(sin(index * 2.1) * 0.46, 0.74 + float(index % 3) * 0.11, cos(index * 2.1) * 0.28), Vector3(0.045, 0.13, 0.045), Color("f8e8b5"))
		spark.rotation.z = PI / 4
		spark.set_meta("rest_position", spark.position)
	repairing.visible = false


static func apply_pet_cosmetics(pivot: Node3D, pet_state: Dictionary, clock_seconds: float = 0.0, repairing: bool = false) -> void:
	var frizzy: bool = pet_state.get("frizzy", false)
	var crooked: bool = pet_state.get("crooked", false)
	pivot.get_node("Frizz").visible = frizzy
	pivot.get_node("Crooked").visible = crooked
	pivot.get_node("Fluff").visible = pet_state.get("stage", "dry") == "dry" and not frizzy
	# A subtle breathing puff reads as a comic hairstyle, without shaking controls.
	pivot.get_node("Frizz").scale = Vector3.ONE * (1.0 + 0.035 * sin(clock_seconds * 7.0))
	pivot.get_node("Crooked").rotation.z = sin(clock_seconds * 5.0) * 0.04 if crooked else 0.0
	var sparks: Node3D = pivot.get_node("RepairSparkles")
	sparks.visible = repairing
	for spark: Node3D in sparks.get_children():
		var rest: Vector3 = spark.get_meta("rest_position", spark.position)
		spark.position = rest + Vector3(0, sin(clock_seconds * 14.0 + spark.get_index()) * 0.07, 0)
