extends RefCounted
## Editable, collisionless H07 character kit. All actors face +Z.
## Pose calls preserve the actor root transform so route/vehicle placement remains authoritative.

var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var generated = preload("res://themes/halloween_festival/generated_actors.gd").new()

func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var palette := {
		"ivory": "f4e8cc", "ivory_shadow": "b8a0bd", "cloth": "f0e6fc",
		"cloth_shadow": "ac8bc4", "ink": "25192e", "purple": "643d91",
		"purple_dark": "342348", "orange": "e97722", "orange_dark": "ac3d19",
		"gold": "efb548", "leaf": "787345", "stem": "705438", "light": "ffac4b",
		"tongue": "b96d94", "eye_glint": "ffe6a6"
	}
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(palette.get(key, "f4e8cc"))
	mat.roughness = 0.76
	mat.metallic = 0.0
	if key == "light":
		mat.emission_enabled = true
		mat.emission = Color("ff851f")
		mat.emission_energy_multiplier = 0.55
	if key == "gold":
		mat.metallic = 0.22
		mat.roughness = 0.54
	_materials[key] = mat
	return mat

func _unit(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	if kind == "sphere":
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 20
		sphere.rings = 12
		mesh = sphere
	elif kind == "cylinder":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 1.0
		cylinder.radial_segments = 10
		mesh = cylinder
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mesh = box
	_meshes[kind] = mesh
	return mesh

func _pivot(parent: Node3D, title: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = title
	node.position = position
	parent.add_child(node)
	return node

func _part(parent: Node3D, title: String, mesh: Mesh, position: Vector3, size: Vector3, material: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.position = position
	node.scale = size
	node.material_override = _material(material)
	parent.add_child(node)
	return node

func _orb(parent: Node3D, title: String, position: Vector3, size: Vector3, material := "ivory") -> MeshInstance3D:
	return _part(parent, title, _unit("sphere"), position, size, material)

func _box(parent: Node3D, title: String, position: Vector3, size: Vector3, material: String) -> MeshInstance3D:
	return _part(parent, title, _unit("box"), position, size, material)

func _bone(parent: Node3D, a: Vector3, b: Vector3, width: float, material := "ivory") -> void:
	width *= 1.32
	var delta := b - a
	var bone := _part(parent, "Bone", _unit("cylinder"), (a + b) * 0.5, Vector3(width, delta.length(), width), material)
	bone.quaternion = Quaternion(Vector3.UP, delta.normalized())
	_orb(parent, "Knuckle", a, Vector3.ONE * width * 1.34, material)
	_orb(parent, "Knuckle", b, Vector3.ONE * width * 1.34, material)

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# SurfaceTool uses clockwise front faces; authoring formulas below use outward CCW.
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)

func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()

func _loft(rings: Array, segments: int, scallop := 0.0, lobes := 0.0) -> ArrayMesh:
	var vertices: Array = []
	for k in rings.size():
		var ring: Vector4 = rings[k]
		var row: Array[Vector3] = []
		for i in segments:
			var angle := TAU * float(i) / float(segments)
			var r := ring.w * (1.0 + lobes * cos(angle * 10.0))
			var edge := scallop * sin(angle * 5.0 + 0.6) * pow(1.0 - float(k) / float(rings.size() - 1), 4.0)
			row.append(Vector3(ring.x + r * sin(angle), ring.y + edge, ring.z + r * cos(angle)))
		vertices.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(rings.size() - 1):
		for i in segments:
			var j := (i + 1) % segments
			_triangle(st, vertices[k][i], vertices[k][j], vertices[k + 1][j])
			_triangle(st, vertices[k][i], vertices[k + 1][j], vertices[k + 1][i])
	for i in segments:
		var j := (i + 1) % segments
		var first: Vector4 = rings[0]
		var last: Vector4 = rings[-1]
		_triangle(st, Vector3(first.x, first.y, first.z), vertices[0][j], vertices[0][i])
		_triangle(st, Vector3(last.x, last.y, last.z), vertices[-1][i], vertices[-1][j])
	return _finish(st)

func _tube(points: Array[Vector3], radii: Array[float], sides := 10) -> ArrayMesh:
	var rows: Array = []
	for k in points.size():
		var forward: Vector3
		if k == 0:
			forward = (points[1] - points[0]).normalized()
		elif k == points.size() - 1:
			forward = (points[k] - points[k - 1]).normalized()
		else:
			forward = (points[k + 1] - points[k - 1]).normalized()
		var up := Vector3.FORWARD if absf(forward.dot(Vector3.UP)) > 0.9 else Vector3.UP
		var x := forward.cross(up).normalized()
		var z := x.cross(forward).normalized()
		var row: Array[Vector3] = []
		for j in sides:
			var a := TAU * float(j) / float(sides)
			row.append(points[k] + radii[k] * (x * cos(a) + z * sin(a)))
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(points.size() - 1):
		for j in sides:
			var n := (j + 1) % sides
			_triangle(st, rows[k][j], rows[k + 1][n], rows[k][n])
			_triangle(st, rows[k][j], rows[k + 1][j], rows[k + 1][n])
	for j in sides:
		var n := (j + 1) % sides
		_triangle(st, points[0], rows[0][j], rows[0][n])
		_triangle(st, points[-1], rows[-1][n], rows[-1][j])
	return _finish(st)

func _polygon(points: PackedVector2Array, depth := 0.02) -> ArrayMesh:
	var triangles := Geometry2D.triangulate_polygon(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, triangles.size(), 3):
		var a := points[triangles[i]]
		var b := points[triangles[i + 1]]
		var c := points[triangles[i + 2]]
		_triangle(st, Vector3(a.x, a.y, depth), Vector3(b.x, b.y, depth), Vector3(c.x, c.y, depth))
		_triangle(st, Vector3(a.x, a.y, -depth), Vector3(c.x, c.y, -depth), Vector3(b.x, b.y, -depth))
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		_triangle(st, Vector3(a.x, a.y, -depth), Vector3(b.x, b.y, depth), Vector3(a.x, a.y, depth))
		_triangle(st, Vector3(a.x, a.y, -depth), Vector3(b.x, b.y, -depth), Vector3(b.x, b.y, depth))
	return _finish(st)

func _merge_static(parent: Node3D) -> void:
	# A rigid bone/head has one surface per material, rather than one draw per tooth/finger.
	var groups: Dictionary = {}
	for child in parent.get_children():
		if child is MeshInstance3D:
			var material: Material = child.material_override
			var id := material.get_instance_id()
			if not groups.has(id):
				groups[id] = {"material": material, "tool": SurfaceTool.new(), "nodes": []}
			groups[id].nodes.append(child)
	for entry: Dictionary in groups.values():
		if entry.nodes.size() < 2:
			continue
		var st: SurfaceTool = entry.tool
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for node: MeshInstance3D in entry.nodes:
			st.append_from(node.mesh, 0, node.transform)
			parent.remove_child(node)
			node.free()
		var merged := MeshInstance3D.new()
		merged.name = "SculptedParts"
		merged.mesh = st.commit()
		merged.material_override = entry.material
		parent.add_child(merged)

func build_ghost() -> Node3D:
	if generated.available("ghost"):
		var imported: Node3D = generated.build_ghost()
		if imported != null:
			return imported
		push_warning("H07 ghost source unavailable; retaining native actor. " + str(generated.errors))
	var actor := Node3D.new()
	actor.name = "MischiefGhost"
	actor.set_meta("festival_actor", "ghost")
	var float_root := _pivot(actor, "Float", Vector3.ZERO)
	var cloth_rings := [
		Vector4(0.05, 0.25, -0.06, 0.65), Vector4(0.01, 0.49, -0.01, 0.57),
		Vector4(-0.02, 0.83, 0.0, 0.59), Vector4(0.0, 1.17, 0.0, 0.64),
		Vector4(0.04, 1.48, -0.03, 0.56), Vector4(0.06, 1.62, -0.05, 0.49),
		Vector4(0.07, 1.73, -0.06, 0.38), Vector4(0.09, 1.83, -0.06, 0.25),
		Vector4(0.10, 1.89, -0.06, 0.13), Vector4(0.11, 1.91, -0.06, 0.01)
	]
	_part(float_root, "ClothBody", _loft(cloth_rings, 50, 0.11), Vector3.ZERO, Vector3.ONE, "cloth")
	# An underside lip gives the floating skirt volume and a cool interior.
	_orb(float_root, "HemInterior", Vector3(0.03, 0.30, -0.05), Vector3(1.04, 0.15, 1.04), "cloth_shadow")
	var tail := _pivot(float_root, "Tail", Vector3(0.0, 0.43, -0.46))
	_part(tail, "ClothTrail", _tube([Vector3.ZERO, Vector3(0.12, -0.04, -0.36), Vector3(0.28, 0.07, -0.66), Vector3(0.35, 0.28, -0.91)], [0.23, 0.19, 0.11, 0.005], 16), Vector3.ZERO, Vector3.ONE, "cloth")
	for side: float in [-1.0, 1.0]:
		var arm := _pivot(float_root, "ArmL" if side < 0.0 else "ArmR", Vector3(side * 0.54, 1.09, -0.03))
		_part(arm, "Flipper", _tube([Vector3.ZERO, Vector3(side * 0.21, -0.01, 0.0), Vector3(side * 0.34, 0.11, 0.02), Vector3(side * 0.42, 0.21, 0.03)], [0.16, 0.14, 0.09, 0.008], 12), Vector3.ZERO, Vector3.ONE, "cloth")
	var face := _pivot(float_root, "Face", Vector3.ZERO)
	_orb(face, "EyeL", Vector3(-0.20, 1.25, 0.586), Vector3(0.175, 0.24, 0.055), "ink")
	_orb(face, "EyeR", Vector3(0.19, 1.29, 0.588), Vector3(0.17, 0.225, 0.055), "ink")
	_orb(face, "GlintL", Vector3(-0.225, 1.30, 0.615), Vector3(0.037, 0.049, 0.012), "eye_glint")
	_orb(face, "GlintR", Vector3(0.165, 1.34, 0.616), Vector3(0.037, 0.049, 0.012), "eye_glint")
	_orb(face, "Mouth", Vector3(0.015, 1.005, 0.586), Vector3(0.18, 0.22, 0.055), "ink")
	_orb(face, "Tongue", Vector3(0.015, 0.951, 0.615), Vector3(0.095, 0.062, 0.014), "tongue")
	_orb(face, "CheekL", Vector3(-0.355, 1.04, 0.487), Vector3(0.16, 0.072, 0.026), "cloth_shadow")
	_orb(face, "CheekR", Vector3(0.355, 1.08, 0.498), Vector3(0.16, 0.072, 0.026), "cloth_shadow")
	_orb(face, "BrowL", Vector3(-0.22, 1.445, 0.494), Vector3(0.17, 0.034, 0.025), "ink").rotation.z = 0.16
	_orb(face, "BrowR", Vector3(0.20, 1.47, 0.51), Vector3(0.17, 0.034, 0.025), "ink").rotation.z = -0.14
	pose_ghost(actor, 0.0)
	return actor

func pose_ghost(actor: Node3D, t: float, impact := 0.0) -> void:
	if actor.get_meta("generated_actor", false):
		generated.pose_ghost(actor, t, impact)
		return
	var body: Node3D = actor.get_node("Float")
	var squash := clampf(impact, 0.0, 1.0)
	body.position.y = 0.09 * sin(t * 2.6)
	body.rotation = Vector3(0.03 * sin(t * 1.7), 0.055 * sin(t * 1.2), 0.06 * sin(t * 2.2))
	body.scale = Vector3(1.0 + 0.66 * squash, 1.0 - 0.52 * squash, 1.0 - 0.35 * squash)
	body.get_node("ArmL").rotation.z = -0.10 + 0.16 * sin(t * 3.0)
	body.get_node("ArmR").rotation.z = 0.10 - 0.16 * sin(t * 3.0 + 0.8)
	body.get_node("Tail").rotation.y = 0.16 * sin(t * 2.6 - 0.8)
	body.get_node("Tail").rotation.x = 0.09 * sin(t * 2.2 - 0.4)
	var face: Node3D = body.get_node("Face")
	for key in ["EyeL", "EyeR"]:
		var eye: MeshInstance3D = face.get_node(key)
		eye.scale.y = (0.24 if key == "EyeL" else 0.225) * (1.0 - 0.80 * squash)
	face.rotation.z = 0.18 * squash * sin(t * 32.0)

func _hand(parent: Node3D, side: float) -> void:
	_orb(parent, "Palm", Vector3(0.0, -0.035, 0.0), Vector3(0.12, 0.15, 0.065))
	for i in 3:
		var x := (float(i) - 1.0) * 0.040
		_bone(parent, Vector3(x, -0.09, 0.0), Vector3(x * 1.3, -0.18 - 0.02 * (1.0 - absf(float(i) - 1.0)), 0.035), 0.031)
	_bone(parent, Vector3(side * 0.04, -0.035, 0.0), Vector3(side * 0.09, -0.105, 0.04), 0.037)
	_merge_static(parent)

func _leg(parent: Node3D, side: float) -> void:
	var hip := _pivot(parent, "LegL" if side < 0 else "LegR", Vector3(side * 0.17, -0.035, 0.0))
	_bone(hip, Vector3.ZERO, Vector3(0.0, -0.34, 0.0), 0.105)
	_merge_static(hip)
	var knee := _pivot(hip, "Knee", Vector3(0.0, -0.34, 0.0))
	_bone(knee, Vector3(-0.025, 0.0, 0.0), Vector3(-0.02, -0.30, 0.0), 0.063)
	_bone(knee, Vector3(0.035, 0.0, 0.01), Vector3(0.035, -0.30, 0.01), 0.040)
	_merge_static(knee)
	var foot := _pivot(knee, "Foot", Vector3(0.0, -0.32, 0.0))
	_orb(foot, "Heel", Vector3(0.0, -0.04, 0.045), Vector3(0.13, 0.14, 0.17))
	for i in 3:
		_bone(foot, Vector3((i - 1) * 0.044, -0.06, 0.09), Vector3((i - 1) * 0.050, -0.07, 0.21 - absf(float(i) - 1.0) * 0.03), 0.043)
	_merge_static(foot)

func _arm(parent: Node3D, side: float) -> void:
	var arm := _pivot(parent, "ArmL" if side < 0 else "ArmR", Vector3(side * 0.35, 0.53, 0.0))
	_bone(arm, Vector3.ZERO, Vector3(0.0, -0.32, 0.0), 0.085)
	_merge_static(arm)
	var elbow := _pivot(arm, "Elbow", Vector3(0.0, -0.32, 0.0))
	_bone(elbow, Vector3(-0.022, 0.0, 0.0), Vector3(-0.018, -0.28, 0.0), 0.045)
	_bone(elbow, Vector3(0.025, 0.0, 0.018), Vector3(0.025, -0.28, 0.018), 0.040)
	_merge_static(elbow)
	var hand := _pivot(elbow, "Hand", Vector3(0.0, -0.29, 0.0))
	_hand(hand, side)

func build_skeleton() -> Node3D:
	if generated.available("skeleton"):
		var hat_source := build_hat()
		var imported: Node3D = generated.build_skeleton(hat_source)
		if imported != null:
			return imported
		hat_source.free()
		push_warning("H07 skeleton source unavailable; retaining native actor. " + str(generated.errors))
	var actor := Node3D.new()
	actor.name = "MoonbathingSkeleton"
	actor.set_meta("festival_actor", "skeleton")
	var rig := _pivot(actor, "Rig", Vector3(0.0, 0.85, 0.0))
	# Pelvis wings, sacrum and a curved, deliberately chunky rib cage.
	_orb(rig, "PelvisL", Vector3(-0.15, 0.02, 0.0), Vector3(0.30, 0.25, 0.25))
	_orb(rig, "PelvisR", Vector3(0.15, 0.02, 0.0), Vector3(0.30, 0.25, 0.25))
	_orb(rig, "Sacrum", Vector3(0.0, 0.06, -0.065), Vector3(0.16, 0.30, 0.15))
	for i in 5:
		_orb(rig, "Vertebra", Vector3(0.0, 0.16 + i * 0.10, -0.06), Vector3(0.14, 0.10, 0.15))
	for i in 4:
		var y := 0.27 + i * 0.09
		var radius := 0.20 + sin((float(i) + 0.6) / 4.0 * PI) * 0.09
		for side: float in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			var radii: Array[float] = []
			for j in 13:
				var a := -0.5 + float(j) / 12.0 * 2.9
				points.append(Vector3(side * radius * sin(a), y - 0.05 * sin(a), -0.025 - radius * 0.58 * cos(a)))
				radii.append(0.038)
			_part(rig, "Rib", _tube(points, radii, 8), Vector3.ZERO, Vector3.ONE, "ivory")
	_bone(rig, Vector3(0.0, 0.27, 0.10), Vector3(0.0, 0.59, 0.10), 0.055)
	_bone(rig, Vector3(-0.30, 0.55, 0.0), Vector3(0.30, 0.55, 0.0), 0.073)
	_bone(rig, Vector3(0.0, 0.61, 0.0), Vector3(0.0, 0.76, 0.0), 0.11)
	_merge_static(rig)
	var head := _pivot(rig, "Head", Vector3(0.0, 0.82, 0.0))
	head.scale = Vector3.ONE * 1.35
	_orb(head, "Cranium", Vector3(0.0, 0.10, -0.015), Vector3(0.65, 0.61, 0.54))
	_orb(head, "CheekL", Vector3(-0.205, -0.055, 0.11), Vector3(0.21, 0.18, 0.30))
	_orb(head, "CheekR", Vector3(0.205, -0.055, 0.11), Vector3(0.21, 0.18, 0.30))
	_orb(head, "SocketL", Vector3(-0.147, 0.105, 0.242), Vector3(0.23, 0.25, 0.069), "ink").rotation.z = -0.11
	_orb(head, "SocketR", Vector3(0.147, 0.105, 0.242), Vector3(0.23, 0.25, 0.069), "ink").rotation.z = 0.11
	_orb(head, "PupilL", Vector3(-0.139, 0.11, 0.278), Vector3(0.042, 0.054, 0.014), "eye_glint")
	_orb(head, "PupilR", Vector3(0.155, 0.11, 0.278), Vector3(0.042, 0.054, 0.014), "eye_glint")
	_part(head, "Nose", _polygon(PackedVector2Array([Vector2(0.0, 0.045), Vector2(-0.053, -0.045), Vector2(0.053, -0.045)])), Vector3(0.0, -0.06, 0.285), Vector3.ONE, "ink")
	for i in 4:
		_orb(head, "UpperTooth", Vector3((i - 1.5) * 0.073, -0.156, 0.226), Vector3(0.063, 0.105, 0.095))
	var crack_points: Array[Vector3] = [Vector3(-0.14, 0.35, 0.10), Vector3(-0.08, 0.30, 0.19), Vector3(-0.13, 0.27, 0.23), Vector3(-0.08, 0.24, 0.24)]
	_part(head, "SkullCrack", _tube(crack_points, [0.008, 0.008, 0.008, 0.004], 5), Vector3.ZERO, Vector3.ONE, "ivory_shadow")
	_merge_static(head)
	var jaw := _pivot(head, "Jaw", Vector3(0.0, -0.16, 0.025))
	_part(jaw, "Mandible", _tube([Vector3(-0.24, 0.02, 0.0), Vector3(-0.22, -0.11, 0.10), Vector3(-0.11, -0.15, 0.20), Vector3(0.11, -0.15, 0.20), Vector3(0.22, -0.11, 0.10), Vector3(0.24, 0.02, 0.0)], [0.040, 0.050, 0.055, 0.055, 0.050, 0.040], 8), Vector3.ZERO, Vector3.ONE, "ivory")
	for i in 4:
		_orb(jaw, "LowerTooth", Vector3((i - 1.5) * 0.068, -0.085, 0.20), Vector3(0.059, 0.09, 0.087))
	_merge_static(jaw)
	var hat := build_hat()
	hat.name = "Hat"
	hat.position = Vector3(0.0, 0.35, 0.0)
	hat.scale = Vector3.ONE * 0.50
	hat.rotation.z = -0.14
	head.add_child(hat)
	_arm(rig, -1.0)
	_arm(rig, 1.0)
	_leg(rig, -1.0)
	_leg(rig, 1.0)
	pose_skeleton(actor, "wave", 0.0)
	return actor

func pose_skeleton(actor: Node3D, mode: String, t: float) -> void:
	if actor.get_meta("generated_actor", false):
		generated.pose_skeleton(actor, mode, t)
		return
	var rig: Node3D = actor.get_node("Rig")
	rig.position = Vector3(0.0, 0.85, 0.0)
	rig.rotation = Vector3.ZERO
	var head: Node3D = rig.get_node("Head")
	head.rotation = Vector3.ZERO
	var jaw: Node3D = head.get_node("Jaw")
	jaw.rotation = Vector3.ZERO
	var hat: Node3D = head.get_node("Hat")
	hat.position.y = 0.35
	hat.rotation = Vector3(0.0, 0.0, -0.14 + 0.025 * sin(t * 1.7))
	for side in ["L", "R"]:
		var sign_value := -1.0 if side == "L" else 1.0
		var arm: Node3D = rig.get_node("Arm" + side)
		var leg: Node3D = rig.get_node("Leg" + side)
		arm.rotation = Vector3(0.0, 0.0, sign_value * 0.12)
		arm.get_node("Elbow").rotation = Vector3(-0.08, 0.0, 0.0)
		arm.get_node("Elbow/Hand").rotation = Vector3.ZERO
		leg.rotation = Vector3(0.0, 0.0, sign_value * 0.05)
		leg.get_node("Knee").rotation = Vector3.ZERO
		leg.get_node("Knee/Foot").position = Vector3(0.0, -0.32, 0.0)
		leg.get_node("Knee/Foot").rotation = Vector3.ZERO
	if mode == "lounge":
		# Sacrum/pelvis rests on the support plane; the torso reclines 66 degrees.
		rig.position.y = 0.13
		rig.rotation.x = -1.15
		head.rotation.x = 0.65
		head.rotation.z = 0.055 * sin(t * 1.5)
		for side in ["L", "R"]:
			var sign_value := -1.0 if side == "L" else 1.0
			rig.get_node("Arm" + side).rotation = Vector3(0.05, 0.0, sign_value * 2.40)
			rig.get_node("Arm" + side + "/Elbow").rotation = Vector3(0.0, 0.0, sign_value * 1.80)
		# Left leg extends along the roof; right knee folds up with the foot planted.
		rig.get_node("LegL").rotation.x = -0.4208
		rig.get_node("LegL/Knee").rotation.x = 0.08
		rig.get_node("LegR").rotation.x = -1.45
		rig.get_node("LegR/Knee").rotation.x = 2.25
		rig.get_node("LegR/Knee/Foot").position.y = -0.315
		rig.get_node("LegR/Knee/Foot").rotation.x = 0.35
	elif mode == "grab":
		rig.position.y = 0.40
		rig.rotation.x = 1.05
		head.rotation.x = -0.70
		head.rotation.z = 0.035 * sin(t * 18.0)
		jaw.rotation.x = 0.27
		hat.position.y = 0.40 + 0.035 * sin(t * 6.0)
		hat.rotation.z = -0.20 + 0.09 * sin(t * 7.0)
		for side in ["L", "R"]:
			var sign_value := -1.0 if side == "L" else 1.0
			rig.get_node("Arm" + side).rotation = Vector3(-1.05, 0.0, sign_value * 0.06)
			rig.get_node("Arm" + side + "/Elbow").rotation.x = 0.0
			rig.get_node("Arm" + side + "/Elbow/Hand").rotation.x = -PI * 0.5
			rig.get_node("Leg" + side).rotation = Vector3(-1.40, 0.0, sign_value * 0.18)
			rig.get_node("Leg" + side + "/Knee").rotation.x = 2.25
	elif mode == "rattle":
		rig.position.y += absf(sin(t * 24.0)) * 0.035
		rig.rotation.z = 0.045 * sin(t * 26.0)
		head.rotation.z = 0.09 * sin(t * 29.0 + 0.4)
		jaw.rotation.x = 0.08 + 0.19 * absf(sin(t * 27.0))
		hat.position.y = 0.35 + 0.045 * absf(sin(t * 21.0))
		rig.get_node("ArmL").rotation.z = -0.40 + 0.12 * sin(t * 23.0)
		rig.get_node("ArmR").rotation.z = 0.40 - 0.12 * sin(t * 23.0)
	elif mode == "sleep":
		rig.position.y = 0.50
		rig.rotation.x = 0.12
		head.rotation.x = 0.30 + 0.08 * sin(t * 1.7)
		head.rotation.z = 0.14
		jaw.rotation.x = 0.12 + 0.04 * sin(t * 1.7)
		for side in ["L", "R"]:
			rig.get_node("Leg" + side).rotation.x = -1.40
			rig.get_node("Leg" + side + "/Knee").rotation.x = 1.40
			rig.get_node("Arm" + side).rotation.x = -0.65
			rig.get_node("Arm" + side + "/Elbow").rotation.x = -0.45
	else:
		head.rotation.z = 0.10 * sin(t * 1.8)
		jaw.rotation.x = 0.04 + 0.035 * sin(t * 3.0)
		rig.get_node("ArmR").rotation.z = 2.12 + 0.12 * sin(t * 3.4)
		rig.get_node("ArmR/Elbow").rotation.z = 0.63 + 0.28 * sin(t * 5.0)
		rig.get_node("ArmR/Elbow/Hand").rotation.z = 0.23 * sin(t * 7.0)
		rig.get_node("ArmL").rotation.x = -0.12

func build_pumpkin() -> Node3D:
	if generated.available("pumpkin"):
		var imported: Node3D = generated.build_pumpkin()
		if imported != null:
			return imported
		push_warning("H07 pumpkin source unavailable; retaining native actor. " + str(generated.errors))
	var actor := Node3D.new()
	actor.name = "BouncyPumpkin"
	actor.set_meta("festival_actor", "pumpkin")
	var body := _pivot(actor, "Body", Vector3.ZERO)
	var rings: Array = []
	for i in 17:
		var a := PI * float(i) / 16.0
		var y := 0.09 + 1.17 * (1.0 - cos(a)) * 0.5
		var radius := maxf(0.025, 0.73 * pow(sin(a), 0.72))
		rings.append(Vector4(0.0, y, 0.0, radius))
	_part(body, "LobedRind", _loft(rings, 80, 0.0, 0.075), Vector3.ZERO, Vector3.ONE, "orange")
	# Lobes carry the surface shading; avoid coincident decorative seam meshes.
	_part(body, "CurledStem", _tube([Vector3(0.0, 1.23, 0.0), Vector3(-0.04, 1.40, -0.02), Vector3(0.02, 1.55, -0.02), Vector3(0.18, 1.60, 0.0), Vector3(0.24, 1.53, 0.0)], [0.12, 0.095, 0.065, 0.043, 0.015], 12), Vector3.ZERO, Vector3.ONE, "stem")
	var leaf := _polygon(PackedVector2Array([Vector2(-0.04, 0.0), Vector2(-0.20, 0.16), Vector2(-0.39, 0.19), Vector2(-0.48, 0.09), Vector2(-0.38, -0.04), Vector2(-0.18, -0.08)]), 0.012)
	var leaf_node := _part(body, "Leaf", leaf, Vector3(0.0, 1.32, 0.10), Vector3.ONE, "leaf")
	leaf_node.rotation.x = -0.8
	for side: float in [-1.0, 1.0]:
		var eye_points := PackedVector2Array([Vector2(-0.12, -0.11), Vector2(0.12, -0.11), Vector2(side * -0.045, 0.15)])
		var eye := _pivot(body, "EyeL" if side < 0.0 else "EyeR", Vector3(side * 0.255, 0.82, 0.647))
		eye.rotation.y = side * 0.28
		_part(eye, "CarvingEdge", _polygon(eye_points, 0.025), Vector3.ZERO, Vector3.ONE, "ink")
		_part(eye, "WarmInterior", _polygon(eye_points, 0.004), Vector3(0.0, 0.0, 0.027), Vector3(0.72, 0.72, 1.0), "light")
	var grin := PackedVector2Array([
		Vector2(-0.44, 0.08), Vector2(-0.27, -0.01), Vector2(-0.20, -0.005), Vector2(-0.20, 0.075),
		Vector2(-0.11, 0.075), Vector2(-0.11, -0.045), Vector2(0.10, -0.045), Vector2(0.10, 0.075),
		Vector2(0.19, 0.075), Vector2(0.19, -0.005), Vector2(0.29, 0.01), Vector2(0.43, 0.10),
		Vector2(0.33, -0.13), Vector2(0.15, -0.21), Vector2(0.08, -0.21), Vector2(0.08, -0.13),
		Vector2(-0.01, -0.13), Vector2(-0.01, -0.23), Vector2(-0.17, -0.20), Vector2(-0.33, -0.11)
	])
	var mouth := _pivot(body, "Grin", Vector3(0.0, 0.51, 0.696))
	_part(mouth, "CarvedSmile", _polygon(grin, 0.025), Vector3.ZERO, Vector3.ONE, "ink")
	_part(mouth, "WarmSmile", _polygon(grin, 0.004), Vector3(0.0, 0.0, 0.027), Vector3(0.84, 0.75, 1.0), "light")
	_merge_static(body)
	pose_pumpkin(actor, 0.0)
	return actor

func pose_pumpkin(actor: Node3D, t: float, squash := 0.0) -> void:
	if actor.get_meta("generated_actor", false):
		generated.pose_pumpkin(actor, t, squash)
		return
	var body: Node3D = actor.get_node("Body")
	var amount := clampf(squash, 0.0, 1.0)
	body.scale = Vector3(1.0 + 0.24 * amount, 1.0 - 0.30 * amount, 1.0 + 0.24 * amount)
	body.rotation = Vector3(0.0, 0.0, sin(t * 3.1) * 0.035 * (1.0 - amount))

func build_hat() -> Node3D:
	var actor := Node3D.new()
	actor.name = "RunawayWitchHat"
	actor.set_meta("festival_actor", "hat")
	var brim := _loft([Vector4(0.0, 0.025, 0.0, 0.57), Vector4(0.0, 0.10, 0.0, 0.61), Vector4(0.0, 0.16, 0.0, 0.40)], 48, 0.035)
	_part(actor, "WavyBrim", brim, Vector3.ZERO, Vector3(1.12, 1.0, 0.96), "purple_dark")
	var crown := _loft([
		Vector4(0.0, 0.10, 0.0, 0.40), Vector4(-0.025, 0.36, 0.0, 0.35),
		Vector4(-0.035, 0.66, 0.0, 0.25), Vector4(0.035, 0.91, 0.0, 0.16),
		Vector4(0.20, 1.10, 0.0, 0.095), Vector4(0.40, 1.10, 0.0, 0.055),
		Vector4(0.55, 0.98, 0.0, 0.008)
	], 40)
	_part(actor, "BentCrown", crown, Vector3.ZERO, Vector3.ONE, "purple")
	_part(actor, "Ribbon", _loft([Vector4(-0.005, 0.19, 0.0, 0.393), Vector4(-0.020, 0.34, 0.0, 0.363)], 40), Vector3.ZERO, Vector3.ONE, "orange")
	for side: float in [-1.0, 1.0]:
		_box(actor, "BuckleUpright", Vector3(side * 0.12, 0.27, 0.381), Vector3(0.036, 0.20, 0.040), "gold")
		_box(actor, "BuckleCrossbar", Vector3(0.0, 0.27 + side * 0.085, 0.381), Vector3(0.24, 0.034, 0.040), "gold")
	_box(actor, "BucklePin", Vector3(0.0, 0.27, 0.41), Vector3(0.15, 0.020, 0.022), "gold")
	_merge_static(actor)
	return actor
