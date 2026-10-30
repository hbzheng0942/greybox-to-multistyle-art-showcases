extends RefCounted
## Visual-only finishes; exact frozen mesh dimensions identify warning roles.
const SURFACE = preload("res://themes/pixel_skyline_v2/shaders/route_finish.gdshader")
const WARNING = preload("res://themes/pixel_skyline_v2/shaders/warning_kit.gdshader")
const CartoonTrial = preload("res://themes/pixel_skyline_v2/cartoon_trial.gd")

static func surface(role: int, color: String, edge: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("role", role)
	m.set_shader_parameter("base_color", Color(color))
	m.set_shader_parameter("light_color", Color(edge))
	return m

static func warning(role: int, size: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WARNING
	m.set_shader_parameter("role", role)
	m.set_shader_parameter("mesh_size", size)
	return m

static func warning_role(node: GeometryInstance3D, parent: Node) -> int:
	if not node is MultiMeshInstance3D or node.get_parent() != parent:
		return -1
	var mm := (node as MultiMeshInstance3D).multimesh
	if mm == null or not mm.mesh is BoxMesh:
		return -1
	var source := mm.mesh.surface_get_material(0) as BaseMaterial3D
	if source == null or not (source.albedo_color.is_equal_approx(Color(1,.18,.11)) or source.albedo_color.is_equal_approx(Color(1,.22,.13))):
		return -1
	var size := (mm.mesh as BoxMesh).size
	if size.is_equal_approx(Vector3.ONE): return 0
	if size.is_equal_approx(Vector3(3.5,.08,3.8)): return 1
	if size.is_equal_approx(Vector3(2.6,1.8,.20)): return 2
	return -1

static func install_district(world: Node3D) -> Dictionary:
	if not CartoonTrial.expanded(): return {"mode":"baseline"}
	var original := world.find_child("district_integration_root", true, false) as Node3D
	var path := "res://themes/pixel_skyline_v2/assets/district_finish.glb"
	var packed := load(path) as PackedScene if ResourceLoader.exists(path, "PackedScene") else null
	var replacement := packed.instantiate() as Node3D if packed != null else null
	if original == null or replacement == null or not replacement.transform.is_equal_approx(Transform3D.IDENTITY) or CartoonTrial.contains_collision(replacement):
		if replacement != null: replacement.free()
		return {"error":"invalid_district_finish_contract"}
	var before := original.find_children("*", "MeshInstance3D", true, false).size()
	var after := replacement.find_children("*", "MeshInstance3D", true, false).size()
	if before != 148 or after != 148:
		replacement.free()
		return {"error":"district_finish_batch_count_mismatch", "before":before,"after":after}
	replacement.name = "DistrictFinish"
	world.add_child(replacement)
	original.visible = false
	return {"mode":"continuous", "replaced_meshes":before, "new_meshes":after,
		"source":"art/source/pixel-skyline-v2/district_finish.blend"}
