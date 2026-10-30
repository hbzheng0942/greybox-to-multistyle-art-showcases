extends RefCounted
## All children are purely visual. One build() call creates one logical unit's view.
## Replacement meshes go here; IDs, fit proxies and rewards stay in the simulation.

const OBJECT_SHADER = preload("res://shaders/object.gdshader")
const TIER_COLORS = [Color("f4a04b"), Color("4bc9a2"), Color("489fcf"), Color("738dd0"), Color("af84b7"), Color("efb65b")]
var materials: Dictionary = {}
var mesh_cache: Dictionary = {}
var proxy_assets: Dictionary = {}

func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/visual_proxies.json"))
	if parsed is Dictionary:
		for entry in parsed["assets"]:
			proxy_assets[str(entry["asset_id"])] = entry

func scenery_material(color: Color) -> ShaderMaterial:
	var key: String = "scene_" + color.to_html()
	if materials.has(key):
		return materials[key]
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = OBJECT_SHADER
	mat.set_shader_parameter("body_color", color)
	mat.set_shader_parameter("enable_hole_clip", false)
	materials[key] = mat
	return mat

func material(color: Color) -> ShaderMaterial:
	var key: String = color.to_html()
	if materials.has(key):
		return materials[key]
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = OBJECT_SHADER
	mat.set_shader_parameter("body_color", color)
	materials[key] = mat
	return mat

func box(parent: Node3D, size: Vector3, center: Vector3, mat: Material) -> MeshInstance3D:
	var key: String = "box_" + str(size)
	var mesh: BoxMesh
	if mesh_cache.has(key):
		mesh = mesh_cache[key]
	else:
		mesh = BoxMesh.new()
		mesh.size = size
		mesh_cache[key] = mesh
	var view: MeshInstance3D = MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = mat
	view.position = center
	parent.add_child(view)
	return view

func cylinder(parent: Node3D, radius: float, height: float, center: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	var view: MeshInstance3D = MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = mat
	view.position = center
	parent.add_child(view)
	return view

func add_parts(root: Node3D, parts: Array, scenery: bool = false) -> void:
	for p in parts:
		var position_values: Array = p.get("position", [0,0,0])
		var position: Vector3 = Vector3(position_values[0],position_values[1],position_values[2])
		var color: Color = Color(str(p.get("color", "91a5b2")))
		if str(p["kind"]) == "label":
			var label: Label3D = Label3D.new()
			label.text = str(p["text"])
			label.font_size = int(p.get("font_size",20))
			label.pixel_size = float(p.get("pixel_size",.007))
			label.modulate = color
			label.outline_size = 0
			label.position = position
			label.no_depth_test = false
			root.add_child(label)
			continue
		var values: Array = p["size"]
		var size: Vector3 = Vector3(values[0],values[1],values[2])
		var mat: Material = scenery_material(color) if scenery else material(color)
		var view: MeshInstance3D = MeshInstance3D.new()
		var cache_key: String = str(p["kind"]) + str(values) + str(p.get("top_radius",-1.0)) + str(p.get("inner_radius",-1.0)) + str(p.get("outer_radius",-1.0))
		var primitive: Mesh
		if mesh_cache.has(cache_key):
			primitive = mesh_cache[cache_key]
		else:
			match str(p["kind"]):
				"sphere":
					var sphere: SphereMesh = SphereMesh.new()
					sphere.radius = 0.5
					sphere.height = 1.0
					sphere.radial_segments = 16
					sphere.rings = 8
					primitive = sphere
				"cylinder":
					var column: CylinderMesh = CylinderMesh.new()
					column.bottom_radius = size.x * 0.5
					column.top_radius = float(p.get("top_radius", size.x*.5))
					column.height = size.y
					column.radial_segments = 16
					primitive = column
				"torus":
					var torus: TorusMesh = TorusMesh.new()
					torus.inner_radius = float(p["inner_radius"])
					torus.outer_radius = float(p["outer_radius"])
					torus.rings = 32
					torus.ring_segments = 12
					primitive = torus
				_:
					var cube: BoxMesh = BoxMesh.new()
					cube.size = size
					primitive = cube
			mesh_cache[cache_key] = primitive
		view.mesh = primitive
		view.material_override = mat
		view.position = position
		if str(p["kind"]) == "sphere":
			view.scale = size
		if p.has("rotation_degrees"):
			var angles: Array = p["rotation_degrees"]
			view.rotation_degrees = Vector3(angles[0],angles[1],angles[2])
		root.add_child(view)

func build(a: Dictionary, asset_id: String = "", logical_id: String = "") -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Visual"
	if proxy_assets.has(asset_id):
		add_parts(root, proxy_assets[asset_id]["proxy_parts"])
	else:
		var s: Array = a["size_xyz"]
		box(root, Vector3(s[0],s[1],s[2]), Vector3.ZERO, material(TIER_COLORS[int(a["min_tier"])]))
	root.set_meta("asset_id", asset_id)
	root.set_meta("status", "PROCEDURAL_PROXY_NOT_FINAL")
	var own_materials: Array = []
	if str(a["id"]) in ["building_segment","wide_building","landmark"]:
		var copies: Dictionary = {}
		for child in root.get_children():
			if child is MeshInstance3D and child.material_override is ShaderMaterial:
				var original: ShaderMaterial = child.material_override
				var key: int = original.get_instance_id()
				if not copies.has(key):
					copies[key] = original.duplicate()
					own_materials.append(copies[key])
				child.material_override = copies[key]
	root.set_meta("cutaway_materials", own_materials)
	root.set_meta("cutaway", 0.0)
	return root

func make_hole(accent: Color) -> Node3D:
	var root: Node3D = Node3D.new()
	var well: MeshInstance3D = MeshInstance3D.new()
	var cylinder_mesh: CylinderMesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 1.0
	cylinder_mesh.bottom_radius = 0.82
	cylinder_mesh.height = 2.65
	cylinder_mesh.radial_segments = 64
	cylinder_mesh.cap_top = false
	well.mesh = cylinder_mesh
	var well_material: StandardMaterial3D = StandardMaterial3D.new()
	well_material.albedo_color = Color("121d24")
	well_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	well_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	well.material_override = well_material
	well.position.y = -1.325
	root.add_child(well)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 1.0
	ring_mesh.outer_radius = 1.04
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	var ring_material: StandardMaterial3D = StandardMaterial3D.new()
	ring_material.albedo_color = accent
	ring_material.roughness = 0.5
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_material
	ring.scale.y = 0.36
	ring.position.y = 0.018
	root.add_child(ring)
	var face: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(1.72,1.72)
	face.mesh = plane
	face.position.y = -1.65
	var face_mat: ShaderMaterial = ShaderMaterial.new()
	face_mat.shader = preload("res://shaders/hole_interior.gdshader")
	face_mat.set_shader_parameter("accent", accent)
	face.material_override = face_mat
	root.add_child(face)
	return root

func proxy_mesh(a: Dictionary) -> ImmediateMesh:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var size: Array = a["size_xyz"]
	var points: Array = []
	if str(a["id"]) in ["tall_pole", "supported_ball"]:
		for i in range(24):
			var t: float = float(i) / 24.0 * TAU
			points.append(Vector3(cos(t) * float(size[0]) * 0.5, 0.0, sin(t) * float(size[2]) * 0.5))
	else:
		var x: float = float(size[0]) * 0.5
		var z: float = float(size[2]) * 0.5
		points = [Vector3(-x, 0.0, -z), Vector3(x, 0.0, -z), Vector3(x, 0.0, z), Vector3(-x, 0.0, z)]
	for i in range(points.size()):
		mesh.surface_add_vertex(points[i])
		mesh.surface_add_vertex(points[(i + 1) % points.size()])
	mesh.surface_end()
	return mesh
