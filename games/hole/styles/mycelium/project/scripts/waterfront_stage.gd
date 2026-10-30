extends RefCounted
## Environment roles are deliberately separate from the food ledger.
const FLOOR = preload("res://shaders/waterfront_floor.gdshader")
const WATER = preload("res://shaders/water.gdshader")

func build(parent: Node3D, factory, map: Dictionary) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.name = "WaterfrontEnvironment"
	parent.add_child(root)
	var floor_mat: ShaderMaterial = ShaderMaterial.new()
	floor_mat.shader = FLOOR
	var corner: Array = map["water_cut_corner_xz"]
	floor_mat.set_shader_parameter("water_corner", Vector2(corner[0], corner[1]))
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(map["floor_size_xz"][0], map["floor_size_xz"][1])
	var floor_view: MeshInstance3D = MeshInstance3D.new()
	floor_view.name = "DryLand_HoleAware"
	floor_view.mesh = floor_mesh
	floor_view.material_override = floor_mat
	root.add_child(floor_view)
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "Water_NOT_PLAYABLE"
	var water_mesh: PlaneMesh = PlaneMesh.new()
	water_mesh.size = Vector2(88.0, 72.0)
	water.mesh = water_mesh
	water.position.y = -0.40
	var water_mat: ShaderMaterial = ShaderMaterial.new()
	water_mat.shader = WATER
	water_mat.set_shader_parameter("water_corner", Vector2(corner[0], corner[1]))
	water.material_override = water_mat
	root.add_child(water)
	# Understructure is decomposed around the inlet; it never fills the hole interior.
	var base_mat: Material = factory.scenery_material(Color("283b48"))
	factory.box(root, Vector3(44,0.20,26),Vector3(0,-2.90,-5),base_mat)
	factory.box(root, Vector3(31,0.20,10),Vector3(6.5,-2.90,13),base_mat)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenery.json"))
	if parsed is Dictionary:
		for row in parsed["scenery"]:
			var view: Node3D = Node3D.new()
			view.name = str(row["id"])
			view.set_meta("role", "SCENERY_ONLY")
			view.set_meta("asset_id", row["asset_id"])
			var p: Array = row["position_xyz"]
			view.position = Vector3(p[0],p[1],p[2])
			factory.add_parts(view, row["parts"], true)
			root.add_child(view)
	# Collision volumes expose shore geometry to future rigid-body extensions.
	# Current player/AI use land_boundary.gd analytic full-disk collision, not these bodies.
	var banks: StaticBody3D = StaticBody3D.new()
	banks.name = "BankCollision_FuturePhysics"
	banks.collision_layer = 16
	banks.collision_mask = 0
	root.add_child(banks)
	var points: Array = map["land_polygon_xz"]
	for i in range(points.size()):
		var a: Vector2 = Vector2(points[i][0], points[i][1])
		var next: Array = points[(i+1)%points.size()]
		var b: Vector2 = Vector2(next[0], next[1])
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(a.distance_to(b), 1.0, 0.14)
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3((a.x+b.x)*.5, -.3, (a.y+b.y)*.5)
		collider.rotation.y = -atan2(b.y-a.y,b.x-a.x)
		banks.add_child(collider)
	return {"root":root, "floor_material":floor_mat}
