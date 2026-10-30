extends RefCounted
## Authored H07 festival effects. All posing uses absolute time and prebuilt nodes.
## Roots face +Z in local XY; callers own placement, visibility windows and scale.

var _materials: Dictionary = {}
var _meshes: Dictionary = {}

func _material(key: String, color: Color, unlit := false, alpha := false) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.82
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unlit:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = result
	return result

func _ink() -> StandardMaterial3D:
	return _material("ink", Color("211632"))

func _node(parent: Node3D, label: String, position := Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	result.name = label
	result.position = position
	parent.add_child(result)
	return result

func _instance(parent: Node3D, label: String, mesh: Mesh, material: Material, position := Vector3.ZERO) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	result.material_override = material
	result.position = position
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result

func _ball(parent: Node3D, label: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	if not _meshes.has("sphere"):
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 12
		mesh.rings = 8
		_meshes.sphere = mesh
	var result := _instance(parent, label, _meshes.sphere, material, position)
	result.scale = size
	return result

func _polygon(points: PackedVector2Array, depth := 0.04) -> ArrayMesh:
	var key := str(points) + ":" + str(depth)
	if _meshes.has(key):
		return _meshes[key]
	var triangles := Geometry2D.triangulate_polygon(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, triangles.size(), 3):
		var a: Vector2 = points[triangles[i]]
		var b: Vector2 = points[triangles[i + 1]]
		var c: Vector2 = points[triangles[i + 2]]
		for p in [a, b, c]:
			surface.add_vertex(Vector3(p.x, p.y, depth * 0.5))
		for p in [c, b, a]:
			surface.add_vertex(Vector3(p.x, p.y, -depth * 0.5))
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var af := Vector3(a.x, a.y, depth * 0.5)
		var ab := Vector3(a.x, a.y, -depth * 0.5)
		var bf := Vector3(b.x, b.y, depth * 0.5)
		var bb := Vector3(b.x, b.y, -depth * 0.5)
		for p in [af, ab, bb, af, bb, bf]:
			surface.add_vertex(p)
	surface.generate_normals()
	var result := surface.commit()
	_meshes[key] = result
	return result

func _segment(parent: Node3D, label: String, start: Vector3, end: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 8
	var result := _instance(parent, label, mesh, material, (start + end) * 0.5)
	var up := (end - start).normalized()
	var side := Vector3.FORWARD.cross(up).normalized()
	if side.length_squared() < 0.1:
		side = Vector3.RIGHT
	result.basis = Basis(side, up, side.cross(up)).orthonormalized()
	return result

func build_bat() -> Node3D:
	var root := Node3D.new()
	root.name = "FestivalBat"
	var violet := _material("bat_violet", Color("694b85"))
	var warm := _material("bat_warm", Color("d29a59"))
	var membrane := _material("bat_membrane", Color("a56a8e"))
	var eyes := _material("bat_eyes", Color("f8d99a"), true)
	_ball(root, "Body", Vector3.ZERO, Vector3(0.34, 0.49, 0.27), _ink())
	_ball(root, "Breast", Vector3(0, -0.06, 0.115), Vector3(0.21, 0.27, 0.11), violet)
	_ball(root, "Head", Vector3(0, 0.20, 0.015), Vector3(0.38, 0.33, 0.29), violet)
	var ear := PackedVector2Array([Vector2(-0.09, 0), Vector2(0.02, 0.34), Vector2(0.13, 0.02)])
	for side in [-1.0, 1.0]:
		var label := "L" if side < 0 else "R"
		var ear_node := _instance(root, "Ear" + label, _polygon(ear), _ink(), Vector3(side * 0.12, 0.29, -0.015))
		ear_node.rotation.z = -side * 0.2
		var eye := _ball(root, "Eye" + label, Vector3(side * 0.09, 0.22, 0.153), Vector3(0.075, 0.10, 0.025), eyes)
		eye.rotation.z = side * 0.12
		_ball(root, "Pupil" + label, Vector3(side * 0.09 + 0.012, 0.219, 0.169), Vector3(0.023, 0.058, 0.013), _ink())
		var wing := _node(root, "Wing" + label, Vector3(side * 0.12, 0.09, -0.03))
		var shape := PackedVector2Array([
			Vector2(0, 0), Vector2(0.22, 0.38), Vector2(0.65, 0.55), Vector2(1.13, 0.45),
			Vector2(0.98, 0.27), Vector2(0.91, 0.03), Vector2(0.76, 0.15), Vector2(0.61, 0.16),
			Vector2(0.49, 0.12), Vector2(0.40, -0.16), Vector2(0.29, -0.02), Vector2(0.16, -0.02), Vector2(0, -0.20)])
		var outline := _instance(wing, "ScallopedOutline", _polygon(shape, 0.05), _ink())
		outline.scale.x = side
		var fill := _instance(wing, "Membrane", _polygon(shape, 0.016), membrane, Vector3(side * 0.025, 0.008, 0.033))
		fill.scale = Vector3(side * 0.93, 0.91, 1)
		for point in [Vector2(1.06, 0.44), Vector2(0.89, 0.04), Vector2(0.40, -0.13)]:
			_segment(wing, "Finger", Vector3(0, 0, 0.055), Vector3(side * point.x, point.y, 0.055), 0.013, violet)
		_ball(wing, "Thumb", Vector3(side * 0.20, 0.36, 0.025), Vector3(0.08, 0.12, 0.06), warm)
	var smile := PackedVector2Array([Vector2(-0.085, 0.025), Vector2(0.085, 0.025), Vector2(0.048, -0.045), Vector2(-0.048, -0.045)])
	_instance(root, "Smile", _polygon(smile, 0.015), _ink(), Vector3(0, 0.12, 0.161))
	var tooth := PackedVector2Array([Vector2(-0.015, 0.014), Vector2(0.015, 0.014), Vector2(0, -0.030)])
	_instance(root, "LittleFang", _polygon(tooth, 0.012), eyes, Vector3(0.038, 0.13, 0.177))
	pose_bat(root, 0.0)
	return root

func pose_bat(node: Node3D, t: float) -> void:
	var flap := sin(t * 12.0)
	var fold := 0.12 + 0.80 * flap
	(node.get_node("WingL") as Node3D).rotation = Vector3(0, fold, -0.055 * cos(t * 12.0))
	(node.get_node("WingR") as Node3D).rotation = Vector3(0, -fold, 0.055 * cos(t * 12.0))
	(node.get_node("Head") as Node3D).rotation.z = sin(t * 2.1) * 0.06

func _star() -> ArrayMesh:
	var points := PackedVector2Array()
	for i in 10:
		var angle := PI * 0.5 + i * TAU / 10.0
		var radius := 0.5 if i % 2 == 0 else 0.23
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return _polygon(points, 0.07)

func build_impact() -> Node3D:
	var root := Node3D.new()
	root.name = "ComicImpact"
	var gold := _material("star_gold", Color("ffcb67"), true)
	var lavender := _material("star_lavender", Color("d7bce7"), true)
	for i in 5:
		var pivot := _node(root, "Star" + str(i))
		_instance(pivot, "Ink", _star(), _ink())
		var center := _instance(pivot, "Face", _star(), gold if i % 2 == 0 else lavender, Vector3(0, 0, 0.05))
		center.scale = Vector3(0.82, 0.82, 0.82)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.92
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	var ring := _instance(root, "Ring", ring_mesh, lavender)
	ring.rotation.x = PI * 0.5
	for i in 6:
		_ball(root, "Speck" + str(i), Vector3.ZERO, Vector3.ONE * 0.08, gold)
	pose_impact(root, -1.0)
	return root

func pose_impact(node: Node3D, age: float) -> void:
	node.visible = age >= 0.0 and age < 1.0
	if not node.visible:
		return
	var pop := smoothstep(0.0, 0.12, age)
	var fade := 1.0 - smoothstep(0.52, 1.0, age)
	for i in 5:
		var star := node.get_node("Star" + str(i)) as Node3D
		var angle := TAU * float(i) / 5.0 + 0.35 + age * 0.45
		var distance := 0.35 + sqrt(age) * (0.8 + 0.12 * i)
		star.position = Vector3(cos(angle) * distance, sin(angle) * distance + age * 0.2, float(i % 2) * 0.06)
		star.rotation.z = age * (1.6 if i % 2 == 0 else -1.2)
		star.scale = Vector3.ONE * pop * fade * (0.26 + 0.06 * (i % 3))
	var ring := node.get_node("Ring") as Node3D
	ring.scale = Vector3.ONE * (0.12 + age * 1.7)
	ring.visible = age < 0.3
	for i in 6:
		var speck := node.get_node("Speck" + str(i)) as Node3D
		var angle := i * 2.399 + 0.2
		speck.position = Vector3(cos(angle) * age * 1.8, sin(angle) * age * 1.8 - age * age * 0.6, 0.07)
		speck.scale = Vector3.ONE * 0.07 * fade

func build_puff() -> Node3D:
	var root := Node3D.new()
	root.name = "PumpkinPuff"
	for i in 7:
		var material := _material("smoke", Color("ad82b5"), false, true).duplicate() as StandardMaterial3D
		_ball(root, "Smoke" + str(i), Vector3.ZERO, Vector3.ONE, material)
	var leaf_material := _material("leaf", Color("d1a147"))
	var leaf_shape := PackedVector2Array([Vector2(0, -0.28), Vector2(-0.17, -0.04), Vector2(-0.12, 0.16), Vector2(0.02, 0.31), Vector2(0.19, 0.04), Vector2(0.12, -0.14)])
	for i in 5:
		var leaf := _node(root, "Leaf" + str(i))
		_instance(leaf, "Blade", _polygon(leaf_shape, 0.025), leaf_material)
		_segment(leaf, "Vein", Vector3(0, -0.23, 0.025), Vector3(0.015, 0.23, 0.025), 0.014, _ink())
	pose_puff(root, -1.0)
	return root

func pose_puff(node: Node3D, age: float) -> void:
	node.visible = age >= 0.0 and age < 1.0
	if not node.visible:
		return
	var fade := 1.0 - smoothstep(0.22, 1.0, age)
	for i in 7:
		var cloud := node.get_node("Smoke" + str(i)) as MeshInstance3D
		var angle := i * 2.399
		var spread := 0.25 + age * (1.6 + (i % 3) * 0.25)
		cloud.position = Vector3(cos(angle) * spread, 0.18 + age * (0.4 + (i % 3) * 0.16), sin(angle) * spread * 0.6)
		cloud.scale = Vector3(1.0, 0.75, 0.85) * (0.35 + age * 0.85) * (0.65 + 0.15 * (i % 3))
		var material := cloud.material_override as StandardMaterial3D
		material.albedo_color.a = fade * 0.68
	for i in 5:
		var leaf := node.get_node("Leaf" + str(i)) as Node3D
		var angle := i * 2.399 + 0.5
		leaf.position = Vector3(cos(angle) * age * 2.1, 0.1 + sin(age * PI) * (0.8 + (i % 2) * 0.45), sin(angle) * age * 1.4)
		leaf.rotation = Vector3(age * (4.0 + i), age * 5.0, angle + age * 3.0)
		leaf.scale = Vector3.ONE * (0.65 + 0.12 * (i % 2)) * (1.0 - smoothstep(0.82, 1.0, age))

func _silhouette(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_silhouette(child, material)

func build_moon_flyby() -> Node3D:
	var root := Node3D.new()
	root.name = "MoonFlyby"
	var silhouette := _material("moon_silhouette", Color("191326"), true)
	var witch := _node(root, "Witch", Vector3(0.55, 0.0, 0))
	var cloak := PackedVector2Array([Vector2(-0.50, -0.12), Vector2(-0.35, 0.15), Vector2(-0.26, 0.42), Vector2(-0.01, 0.49), Vector2(0.18, 0.22), Vector2(0.07, -0.18), Vector2(-0.12, -0.37), Vector2(-0.34, -0.25), Vector2(-0.58, -0.30), Vector2(-0.45, -0.18)])
	_instance(witch, "WindCaughtCloak", _polygon(cloak, 0.07), silhouette)
	var head := PackedVector2Array([Vector2(-0.16, 0.43), Vector2(-0.21, 0.66), Vector2(-0.10, 0.81), Vector2(0.08, 0.80), Vector2(0.17, 0.67), Vector2(0.30, 0.62), Vector2(0.18, 0.58), Vector2(0.17, 0.47), Vector2(0.02, 0.41)])
	_instance(witch, "NoseAndHead", _polygon(head, 0.07), silhouette, Vector3(0, 0, 0.012))
	var hat := PackedVector2Array([Vector2(-0.34, 0.72), Vector2(-0.10, 0.80), Vector2(-0.08, 1.08), Vector2(0.04, 1.30), Vector2(0.28, 1.23), Vector2(0.14, 1.17), Vector2(0.17, 0.83), Vector2(0.37, 0.72)])
	_instance(witch, "BentWitchHat", _polygon(hat, 0.08), silhouette)
	var arm := PackedVector2Array([Vector2(-0.03, 0.30), Vector2(0.11, 0.33), Vector2(0.35, 0.04), Vector2(0.59, -0.02), Vector2(0.58, -0.10), Vector2(0.25, -0.08)])
	_instance(witch, "ReachingArm", _polygon(arm, 0.06), silhouette, Vector3(0, 0, 0.025))
	var leg := PackedVector2Array([Vector2(-0.01, -0.13), Vector2(0.20, -0.22), Vector2(0.27, -0.49), Vector2(0.43, -0.51), Vector2(0.50, -0.41), Vector2(0.51, -0.59), Vector2(0.19, -0.64), Vector2(0.09, -0.32), Vector2(-0.17, -0.28)])
	_instance(witch, "CurledBoot", _polygon(leg, 0.06), silhouette)
	_segment(witch, "BroomShaft", Vector3(-0.95, -0.30, -0.04), Vector3(1.05, -0.02, -0.04), 0.035, silhouette)
	var broom := PackedVector2Array([Vector2(-0.62, -0.24), Vector2(-0.87, -0.12), Vector2(-1.26, -0.16), Vector2(-1.12, -0.25), Vector2(-1.34, -0.31), Vector2(-1.13, -0.35), Vector2(-1.29, -0.46), Vector2(-0.94, -0.48), Vector2(-0.67, -0.35)])
	_instance(witch, "BroomStraw", _polygon(broom, 0.05), silhouette)
	var scarf := PackedVector2Array([Vector2(-0.13, 0.43), Vector2(-0.43, 0.45), Vector2(-0.64, 0.60), Vector2(-0.88, 0.55), Vector2(-0.68, 0.44), Vector2(-0.51, 0.29), Vector2(-0.18, 0.31)])
	_instance(witch, "Scarf", _polygon(scarf, 0.035), silhouette, Vector3(0, 0, -0.05))
	for i in 2:
		var bat := build_bat()
		bat.name = "Follower" + str(i)
		_silhouette(bat, silhouette)
		root.add_child(bat)
		bat.scale = Vector3.ONE * (0.22 if i == 0 else 0.16)
	pose_moon_flyby(root, -1.0)
	root.set_meta("local_plane", "XY; normal +Z; root placement is caller-owned")
	root.set_meta("normalized_width", 5.2)
	return root

func pose_moon_flyby(node: Node3D, t: float) -> void:
	node.visible = t >= 0.0 and t <= 1.0
	if not node.visible:
		return
	var witch := node.get_node("Witch") as Node3D
	witch.position = Vector3(0.55, sin(t * TAU * 1.5) * 0.055, 0)
	witch.rotation.z = sin(t * TAU) * 0.035
	var first := node.get_node("Follower0") as Node3D
	pose_bat(first, t * 2.8)
	first.position = Vector3(-1.18, 0.13 + sin(t * TAU * 2.0) * 0.14, 0.02)
	first.rotation.z = sin(t * TAU * 2.0) * 0.10
	# Second bat visibly lags, sprints above the witch, brakes, then backs into line.
	# Each segment is an absolute-time curve: seeking/retry cannot accumulate drift.
	var late := node.get_node("Follower1") as Node3D
	var x := -1.88
	var y := 0.02
	var bank := 0.0
	var flap_time := t * 2.8 - 0.15
	if t < 0.24:
		var u := smoothstep(0.0, 0.24, t)
		x = lerpf(-1.88, -2.7, u)
		y = lerpf(0.02, -0.18, u)
		flap_time = t * 0.65
	elif t < 0.60:
		var u := smoothstep(0.24, 0.60, t)
		x = lerpf(-2.7, 1.75, u)
		y = lerpf(-0.18, 1.55, u) + sin(u * PI) * 0.16
		bank = -sin(u * PI) * 0.23
		flap_time = 0.156 + (t - 0.24) * 4.8
	elif t < 0.70:
		var u := smoothstep(0.60, 0.70, t)
		x = 1.75 + sin(u * PI) * 0.08
		y = lerpf(1.55, 1.62, u)
		bank = sin(u * PI) * 0.38
		flap_time = 1.884 + (t - 0.60) * 1.4
	else:
		var u := smoothstep(0.70, 1.0, t)
		x = lerpf(1.75, -1.88, u)
		y = lerpf(1.62, 0.02, u)
		bank = sin(u * PI) * 0.18
		flap_time = 2.024 + (t - 0.70) * 2.6
	pose_bat(late, flap_time)
	late.position = Vector3(x, y, 0.02)
	late.rotation.z = bank
