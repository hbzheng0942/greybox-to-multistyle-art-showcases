extends RefCounted
## G1 actor sources and UV-preserving, anatomy-driven rigid rig.
## Assets become available only through an explicit hash-bound manifest.
const MANIFEST := "res://../art/themes/halloween_festival/generated-actors.json"
const GHOST_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_factor : source_color = vec4(1.0);
uniform float roughness_factor = 0.8;
uniform mat4 local_to_actor;
uniform mat4 actor_to_local;
uniform float actor_height = 2.0;
instance uniform float ghost_time = 0.0;
instance uniform float ghost_impact = 0.0;
void vertex() {
 vec3 p = (local_to_actor * vec4(VERTEX,1.0)).xyz;
 float h = clamp(p.y / actor_height,0.0,1.0);
 float skirt = 1.0-smoothstep(0.18,0.46,h);
 float head = smoothstep(0.42,0.55,h);
 float torso = smoothstep(0.16,0.34,h)*(1.0-head);
 float hit = clamp(ghost_impact,0.0,1.0);
 p.x += skirt*(0.07*sin(ghost_time*3.4+p.z*3.0)+0.035*sin(ghost_time*5.1+p.x*4.0));
 p.z += skirt*0.065*sin(ghost_time*2.8+p.x*4.0-0.8);
 p.y += skirt*0.04*sin(ghost_time*4.0+p.x*6.0);
 p.x *= 1.0+hit*0.15*torso;
 p.y -= hit*actor_height*0.105*torso;
 p.z -= hit*0.16*torso;
 // The head and face move together as a readable rigid mass; they do not pancake.
 p.x += head*hit*0.045*sin(ghost_time*25.0);
 p.y += head*hit*0.035;
 VERTEX=(actor_to_local*vec4(p,1.0)).xyz;
}
void fragment() {
 ALBEDO=texture(albedo_map,UV).rgb*albedo_factor.rgb;
 ROUGHNESS=roughness_factor;
 METALLIC=0.0;
}
"""

var sources: Dictionary = {}
var cache: Dictionary = {}
var errors: Array[String] = []
var _ghost_shader: Shader
var _joint_mesh: SphereMesh
var _joint_material: StandardMaterial3D

func _init() -> void:
	if FileAccess.file_exists(MANIFEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary:
			sources = parsed.get("assets", {})
	_ghost_shader = Shader.new()
	_ghost_shader.code = GHOST_SHADER
	_joint_mesh = SphereMesh.new()
	_joint_mesh.radius = 0.5
	_joint_mesh.height = 1.0
	_joint_mesh.radial_segments = 16
	_joint_mesh.rings = 8
	_joint_material = StandardMaterial3D.new()
	_joint_material.albedo_color = Color("cfb99b")
	_joint_material.roughness = 0.90
	_joint_material.metallic_specular = 0.18

func available(kind: String) -> bool:
	return sources.has(kind) and sources[kind].get("enabled", false)

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _path(path: String) -> String:
	return ProjectSettings.globalize_path("res://../" + path)

func _bounds(node: Node, transform: Transform3D, output: Array) -> void:
	var current := transform
	if node is Node3D:
		current = transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		output.append(current * node.mesh.get_aabb())
	for child in node.get_children():
		_bounds(child, current, output)

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := node.transform
	var cursor := node.get_parent()
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			result = cursor.transform * result
		cursor = cursor.get_parent()
	return result

func _load(kind: String) -> bool:
	if cache.has(kind):
		return true
	if not available(kind):
		return false
	var source: Dictionary = sources[kind]
	var path := _path(source.path)
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != source.sha256:
		errors.append(kind + ": missing or changed source")
		return false
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file(path, state)
	if result != OK:
		errors.append(kind + ": GLTF load error " + str(result))
		return false
	var scene := document.generate_scene(state) as Node3D
	if scene == null:
		errors.append(kind + ": GLTF scene is empty")
		return false
	var boxes: Array = []
	_bounds(scene, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		scene.free()
		errors.append(kind + ": GLTF has no mesh geometry")
		return false
	var bounds: AABB = boxes[0]
	for box: AABB in boxes:
		bounds = bounds.merge(box)
	cache[kind] = {"scene": scene, "bounds": bounds}
	return true

func _pivot(parent: Node3D, name: String, origin: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = origin
	parent.add_child(node)
	return node

func _normalized(kind: String, name: String) -> Node3D:
	if not _load(kind):
		return null
	var row: Dictionary = sources[kind]
	var actor := Node3D.new()
	actor.name = name
	actor.set_meta("festival_actor", kind)
	actor.set_meta("generated_actor", true)
	actor.set_meta("source_sha256", row.sha256)
	var pivot := _pivot(actor, "Float" if kind == "ghost" else "Body", Vector3.ZERO)
	var imported: Node3D = cache[kind].scene.duplicate()
	imported.name = "CanonicalG1"
	pivot.add_child(imported)
	var rotation := Basis(Vector3.UP, deg_to_rad(float(row.get("yaw_degrees", 0.0))))
	var original: AABB = cache[kind].bounds
	var rotated: AABB = Transform3D(rotation, Vector3.ZERO) * original
	var factor := float(row.get("target_height", 2.0)) / rotated.size.y
	if row.has("target_width"):
		factor = float(row.target_width) / rotated.size.x
	var offset := -Vector3(rotated.get_center().x, rotated.position.y, rotated.get_center().z) * factor
	imported.transform = Transform3D(rotation.scaled(Vector3.ONE * factor), offset) * imported.transform
	actor.set_meta("normalized_size", rotated.size * factor)
	if kind == "ghost":
		var meshes: Array[MeshInstance3D] = []
		for mesh: MeshInstance3D in imported.find_children("*", "MeshInstance3D", true, false):
			var space := _relative(mesh, actor)
			for surface in mesh.mesh.get_surface_count():
				var original_material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if original_material == null or original_material.albedo_texture == null:
					continue
				var mat := ShaderMaterial.new()
				mat.shader = _ghost_shader
				mat.set_shader_parameter("albedo_map", original_material.albedo_texture)
				mat.set_shader_parameter("albedo_factor", original_material.albedo_color)
				mat.set_shader_parameter("roughness_factor", maxf(0.65, original_material.roughness))
				mat.set_shader_parameter("local_to_actor", space)
				mat.set_shader_parameter("actor_to_local", space.affine_inverse())
				mat.set_shader_parameter("actor_height", rotated.size.y * factor)
				mesh.set_surface_override_material(surface, mat)
			mesh.extra_cull_margin = 0.5
			meshes.append(mesh)
		actor.set_meta("deforming_meshes", meshes)
	return actor

func build_ghost() -> Node3D:
	return _normalized("ghost", "SoftClothGhost")

func build_pumpkin() -> Node3D:
	return _normalized("pumpkin", "CarvedPumpkin")

func build_skeleton(hat: Node3D) -> Node3D:
	if not _load("skeleton"):
		return null
	var row: Dictionary = sources.skeleton
	var rig_path := _path(row.rig_path)
	if not FileAccess.file_exists(rig_path) or FileAccess.get_sha256(rig_path) != row.rig_sha256:
		errors.append("skeleton: rig manifest changed")
		return null
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(rig_path))
	var actor := Node3D.new()
	actor.name = "PaintedSkeleton"
	actor.set_meta("festival_actor", "skeleton")
	actor.set_meta("generated_actor", true)
	actor.set_meta("source_sha256", row.sha256)
	var joints: Dictionary = {}
	for key: String in data.joints:
		joints[key] = _vector(data.joints[key])
	actor.set_meta("rig_joints", joints)
	var rig := _pivot(actor, "Rig", joints.pelvis)
	var head := _pivot(rig, "Head", joints.head - joints.pelvis)
	_pivot(head, "Jaw", joints.jaw - joints.head)
	hat.name = "Hat"
	hat.position = joints.hat - joints.head
	hat.scale = Vector3.ONE * float(data.get("hat_scale", 0.55))
	hat.rotation.z = -0.12
	head.add_child(hat)
	actor.set_meta("hat_rest_y", hat.position.y)
	var paths := {"Torso": "Rig", "Head": "Rig/Head", "Jaw": "Rig/Head/Jaw"}
	var pivots := {"Torso": joints.pelvis, "Head": joints.head, "Jaw": joints.jaw}
	for side in ["L", "R"]:
		var suffix: String = side.to_lower()
		var arm := _pivot(rig, "Arm" + side, joints["shoulder_" + suffix] - joints.pelvis)
		var elbow := _pivot(arm, "Elbow", joints["elbow_" + suffix] - joints["shoulder_" + suffix])
		_pivot(elbow, "Hand", joints["wrist_" + suffix] - joints["elbow_" + suffix])
		var leg := _pivot(rig, "Leg" + side, joints["hip_" + suffix] - joints.pelvis)
		var knee := _pivot(leg, "Knee", joints["knee_" + suffix] - joints["hip_" + suffix])
		_pivot(knee, "Foot", joints["ankle_" + suffix] - joints["knee_" + suffix])
		paths["UpperArm" + side] = "Rig/Arm" + side
		paths["Forearm" + side] = "Rig/Arm" + side + "/Elbow"
		paths["Hand" + side] = "Rig/Arm" + side + "/Elbow/Hand"
		paths["Thigh" + side] = "Rig/Leg" + side
		paths["Shin" + side] = "Rig/Leg" + side + "/Knee"
		paths["Foot" + side] = "Rig/Leg" + side + "/Knee/Foot"
		for group in ["UpperArm", "Forearm", "Hand", "Thigh", "Shin", "Foot"]:
			var key: String = {"UpperArm": "shoulder", "Forearm": "elbow", "Hand": "wrist", "Thigh": "hip", "Shin": "knee", "Foot": "ankle"}[group]
			pivots[group + side] = joints[key + "_" + suffix]
	var imported: Node3D = cache.skeleton.scene.duplicate()
	var contacts: Array = []
	for part: Dictionary in data.parts:
		var matches := imported.find_children(part.node, "MeshInstance3D", true, false)
		if matches.is_empty() or not paths.has(part.part):
			errors.append("skeleton: prepared part missing " + str(part.node))
			continue
		var mesh: MeshInstance3D = matches[0]
		var transform := _relative(mesh, imported)
		mesh.get_parent().remove_child(mesh)
		actor.get_node(paths[part.part]).add_child(mesh)
		mesh.transform = Transform3D(Basis.IDENTITY, -pivots[part.part]) * transform
		contacts.append({"mesh": mesh, "points": part.contact_samples})
	imported.free()
	actor.set_meta("contact_parts", contacts)
	for side in ["L", "R"]:
		for entry in [["Arm" + side, 0.13], ["Arm" + side + "/Elbow", 0.14], ["Arm" + side + "/Elbow/Hand", 0.105], ["Leg" + side, 0.17], ["Leg" + side + "/Knee", 0.18], ["Leg" + side + "/Knee/Foot", 0.13]]:
			var cover := MeshInstance3D.new()
			cover.name = "JointCover"
			cover.mesh = _joint_mesh
			cover.material_override = _joint_material
			cover.scale = Vector3.ONE * entry[1]
			rig.get_node(entry[0]).add_child(cover)
	actor.set_meta("pose_arm_target", Callable(self, "_bound_arm_target").bind(actor))
	actor.set_meta("arm_reach", Callable(self, "_bound_arm_reach").bind(actor))
	pose_skeleton(actor, "wave", 0.0)
	return actor

func pose_ghost(actor: Node3D, t: float, impact := 0.0) -> void:
	var floating: Node3D = actor.get_node("Float")
	floating.position.y = 0.07 * sin(t * 2.3)
	floating.rotation = Vector3(0.035 * sin(t * 1.7), 0.025 * sin(t * 1.1), 0.035 * sin(t * 2.0))
	for mesh: MeshInstance3D in actor.get_meta("deforming_meshes", []):
		mesh.set_instance_shader_parameter("ghost_time", t)
		mesh.set_instance_shader_parameter("ghost_impact", clampf(impact, 0.0, 1.0))

func pose_pumpkin(actor: Node3D, t: float, squash := 0.0) -> void:
	var body: Node3D = actor.get_node("Body")
	var amount := clampf(squash, 0.0, 1.0)
	body.scale = Vector3(1.0 + 0.10 * amount, 1.0 - 0.16 * amount, 1.0 + 0.10 * amount)
	body.rotation.z = 0.025 * sin(t * 2.4) * (1.0 - amount)

func _chain(root: Node3D, middle: Node3D, rest_upper: Vector3, rest_lower: Vector3, upper_angles: Vector3, lower_angles: Vector3) -> void:
	var authored_upper := Basis.from_euler(upper_angles)
	var authored_lower := authored_upper * Basis.from_euler(lower_angles)
	root.quaternion = Quaternion(rest_upper.normalized(), (authored_upper * Vector3.DOWN).normalized())
	middle.quaternion = Quaternion(rest_lower.normalized(), (root.basis.inverse() * authored_lower * Vector3.DOWN).normalized())

func _ground(actor: Node3D, parts: Array = []) -> void:
	var low := INF
	for part: Dictionary in actor.get_meta("contact_parts", []):
		if not parts.is_empty() and not parts.any(func(value): return str(part.mesh.name).contains("__" + str(value) + "__")):
			continue
		var transform := _relative(part.mesh, actor)
		for point: Array in part.points:
			low = minf(low, (transform * _vector(point)).y)
	# Spherical joint covers contribute real surface contact too. In lounge, the
	# pelvis covers support the torso while the feet are positioned independently.
	for cover: MeshInstance3D in actor.find_children("JointCover", "MeshInstance3D", true, false):
		var path := str(actor.get_path_to(cover))
		if not parts.is_empty() and path not in ["Rig/LegL/JointCover", "Rig/LegR/JointCover"]:
			continue
		var space := _relative(cover, actor)
		low = minf(low, space.origin.y - space.basis.get_scale().y * 0.5)
	if is_finite(low):
		actor.get_node("Rig").position.y -= low

func _ik(actor: Node3D, first: Node3D, second: Node3D, rest_first: Vector3, rest_second: Vector3, target: Vector3, bend_hint: Vector3) -> void:
	var parent_transform := _relative(first.get_parent(), actor)
	var origin := (parent_transform * first.transform).origin
	var length_a := rest_first.length()
	var length_b := rest_second.length()
	var delta := target - origin
	var distance := clampf(delta.length(), absf(length_a - length_b) + 0.002, length_a + length_b - 0.002)
	var direction := delta.normalized()
	if direction.length_squared() < 0.5:
		direction = Vector3.DOWN
	var bend := bend_hint - direction * bend_hint.dot(direction)
	if bend.length_squared() < 0.0001:
		bend = Vector3.RIGHT - direction * Vector3.RIGHT.dot(direction)
	bend = bend.normalized()
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
	var high := sqrt(maxf(0.0, length_a * length_a - along * along))
	var elbow_target := origin + direction * along + bend * high
	var final_target := origin + direction * distance
	first.quaternion = Quaternion(rest_first.normalized(), (parent_transform.basis.inverse() * (elbow_target - origin)).normalized())
	var first_basis := parent_transform.basis * first.basis
	second.quaternion = Quaternion(rest_second.normalized(), (first_basis.inverse() * (final_target - elbow_target)).normalized())

func arm_reach(actor: Node3D, side: String) -> Dictionary:
	var suffix := side.to_lower()
	var joints: Dictionary = actor.get_meta("rig_joints")
	var arm: Node3D = actor.get_node("Rig/Arm" + side.to_upper())
	return {"shoulder_actor": _relative(arm, actor).origin, "wrist_actor": _relative(arm.get_node("Elbow/Hand"), actor).origin, "upper_length": (joints["elbow_" + suffix] - joints["shoulder_" + suffix]).length(), "lower_length": (joints["wrist_" + suffix] - joints["elbow_" + suffix]).length()}

func pose_arm_target(actor: Node3D, side: String, target_actor: Vector3, bend_hint_actor := Vector3.UP) -> void:
	var suffix := side.to_lower()
	var joints: Dictionary = actor.get_meta("rig_joints")
	var arm: Node3D = actor.get_node("Rig/Arm" + side.to_upper())
	_ik(actor, arm, arm.get_node("Elbow"), joints["elbow_" + suffix] - joints["shoulder_" + suffix], joints["wrist_" + suffix] - joints["elbow_" + suffix], target_actor, bend_hint_actor)

func _bound_arm_target(side: String, target_actor: Vector3, bend_hint_actor: Vector3, actor: Node3D) -> void:
	pose_arm_target(actor, side, target_actor, bend_hint_actor)

func _bound_arm_reach(side: String, actor: Node3D) -> Dictionary:
	return arm_reach(actor, side)

func pose_skeleton(actor: Node3D, mode: String, t: float) -> void:
	var joints: Dictionary = actor.get_meta("rig_joints")
	var rig: Node3D = actor.get_node("Rig")
	rig.position = joints.pelvis
	rig.rotation = Vector3.ZERO
	var head: Node3D = rig.get_node("Head")
	head.rotation = Vector3.ZERO
	var jaw: Node3D = head.get_node("Jaw")
	jaw.rotation = Vector3.ZERO
	var hat: Node3D = head.get_node("Hat")
	hat.position.y = actor.get_meta("hat_rest_y")
	hat.rotation.z = -0.12 + 0.025 * sin(t * 1.7)
	if mode == "rest":
		for side in ["L", "R"]:
			for path in ["Arm" + side, "Arm" + side + "/Elbow", "Arm" + side + "/Elbow/Hand", "Leg" + side, "Leg" + side + "/Knee", "Leg" + side + "/Knee/Foot"]:
				rig.get_node(path).quaternion = Quaternion.IDENTITY
		_ground(actor)
		return
	var upper_arm := {"L": Vector3(0.0, 0.0, -0.12), "R": Vector3(0.0, 0.0, 0.12)}
	var lower_arm := {"L": Vector3(-0.08, 0.0, 0.0), "R": Vector3(-0.08, 0.0, 0.0)}
	var thighs := {"L": Vector3(0.0, 0.0, -0.06), "R": Vector3(0.0, 0.0, 0.06)}
	var shins := {"L": Vector3.ZERO, "R": Vector3.ZERO}
	if mode == "lounge":
		rig.rotation.x = -1.45
		head.rotation.x = 0.55
		head.rotation.z = 0.025 * sin(t * 1.6)
		upper_arm = {"L": Vector3(0.10, 0.0, -2.35), "R": Vector3(0.10, 0.0, 2.35)}
		lower_arm = {"L": Vector3(0.0, 0.0, -1.60), "R": Vector3(0.0, 0.0, 1.60)}
		thighs = {"L": Vector3(-0.32, 0.0, -0.07), "R": Vector3(-1.35, 0.0, 0.13)}
		shins = {"L": Vector3(0.04, 0.0, 0.0), "R": Vector3(2.25, 0.0, 0.0)}
	elif mode == "grab":
		rig.rotation.x = 1.05
		head.rotation.x = -0.70
		jaw.rotation.x = 0.18
		upper_arm = {"L": Vector3(-1.05, 0.0, -0.16), "R": Vector3(-1.05, 0.0, 0.16)}
		lower_arm = {"L": Vector3.ZERO, "R": Vector3.ZERO}
		thighs = {"L": Vector3(-1.45, 0.0, -0.25), "R": Vector3(-1.45, 0.0, 0.25)}
		shins = {"L": Vector3(2.15, 0.0, 0.0), "R": Vector3(2.15, 0.0, 0.0)}
		hat.position.y += 0.015 * sin(t * 6.0)
	elif mode == "sleep":
		rig.rotation.x = 0.12
		head.rotation = Vector3(0.25 + 0.045 * sin(t * 1.6), 0.0, 0.10)
		jaw.rotation.x = 0.06
		upper_arm = {"L": Vector3(-0.65, 0.0, -0.10), "R": Vector3(-0.65, 0.0, 0.10)}
		lower_arm = {"L": Vector3(-0.45, 0.0, 0.0), "R": Vector3(-0.45, 0.0, 0.0)}
		thighs = {"L": Vector3(-1.40, 0.0, -0.08), "R": Vector3(-1.40, 0.0, 0.08)}
		shins = {"L": Vector3(1.40, 0.0, 0.0), "R": Vector3(1.40, 0.0, 0.0)}
	elif mode == "rattle":
		rig.rotation.z = 0.025 * sin(t * 26.0)
		head.rotation.z = 0.075 * sin(t * 29.0)
		jaw.rotation.x = 0.06 + 0.17 * absf(sin(t * 27.0))
		upper_arm.L.z = -0.35 + 0.08 * sin(t * 23.0)
		upper_arm.R.z = 0.35 - 0.08 * sin(t * 23.0)
	else:
		head.rotation.z = 0.07 * sin(t * 1.8)
		upper_arm.R = Vector3(0.0, 0.0, 2.12 + 0.10 * sin(t * 3.4))
		lower_arm.R = Vector3(0.0, 0.0, 0.63 + 0.25 * sin(t * 5.0))
	for side in ["L", "R"]:
		var suffix: String = side.to_lower()
		var arm: Node3D = rig.get_node("Arm" + side)
		var elbow: Node3D = arm.get_node("Elbow")
		_chain(arm, elbow, joints["elbow_" + suffix] - joints["shoulder_" + suffix], joints["wrist_" + suffix] - joints["elbow_" + suffix], upper_arm[side], lower_arm[side])
		var hand: Node3D = elbow.get_node("Hand")
		hand.rotation = Vector3.ZERO
		if mode == "grab":
			hand.quaternion = (arm.quaternion * elbow.quaternion).inverse() * Quaternion(Vector3.RIGHT, -PI * 0.5 - rig.rotation.x)
		var leg: Node3D = rig.get_node("Leg" + side)
		var knee: Node3D = leg.get_node("Knee")
		_chain(leg, knee, joints["knee_" + suffix] - joints["hip_" + suffix], joints["ankle_" + suffix] - joints["knee_" + suffix], thighs[side], shins[side])
		var foot: Node3D = knee.get_node("Foot")
		foot.quaternion = (leg.quaternion * knee.quaternion).inverse() * Quaternion(Vector3.RIGHT, -rig.rotation.x)
		if mode == "lounge" and side == "L":
			foot.quaternion = (leg.quaternion * knee.quaternion).inverse() * Quaternion(Vector3.RIGHT, 1.15)
	if mode == "lounge":
		_ground(actor, ["Torso"])
		for side in ["L", "R"]:
			var suffix: String = side.to_lower()
			var leg: Node3D = rig.get_node("Leg" + side)
			var knee: Node3D = leg.get_node("Knee")
			var hip := _relative(leg, actor).origin
			var ankle_height: float = joints["ankle_" + suffix].y
			var length_a: float = (joints["knee_" + suffix] - joints["hip_" + suffix]).length()
			var length_b: float = (joints["ankle_" + suffix] - joints["knee_" + suffix]).length()
			var extension := (length_a + length_b) * (0.97 if side == "L" else 0.57)
			var ankle_target := Vector3(hip.x + (-0.04 if side == "L" else 0.04), ankle_height + 0.005, hip.z + extension)
			_ik(actor, leg, knee, joints["knee_" + suffix] - joints["hip_" + suffix], joints["ankle_" + suffix] - joints["knee_" + suffix], ankle_target, Vector3.UP)
			knee.get_node("Foot").quaternion = (_relative(knee, actor).basis).get_rotation_quaternion().inverse()
	else:
		_ground(actor)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for entry: Dictionary in cache.values():
			if is_instance_valid(entry.scene):
				entry.scene.free()
		cache.clear()
