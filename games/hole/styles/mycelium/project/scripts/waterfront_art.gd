extends RefCounted
## Waterfront environment build (E01-E12). Environment roles stay deliberately separate from
## the food ledger: nothing built here has a swallow ID, a support relation or a payout.
##
## The land polygon, the water cut corner, the shore margin and the bank collision volumes are
## carried over from v0.3 unchanged. Only the surface look and the backdrop geometry are new,
## and both still respect the two moving openings.

const FLOOR = preload("res://shaders/waterfront_floor.gdshader")
const WATER = preload("res://shaders/water.gdshader")
const SceneryLibrary = preload("res://scripts/scenery_library.gd")

var scenery_library

func build(parent: Node3D, factory, map: Dictionary) -> Dictionary:
	scenery_library = SceneryLibrary.new()
	scenery_library.theme_id = factory.theme_id
	var root: Node3D = Node3D.new()
	root.name = "WaterfrontEnvironment"
	parent.add_child(root)
	var corner: Array = map["water_cut_corner_xz"]
	var formal: bool = factory.is_formal()
	var scene_recipe: Dictionary = factory.recipe_library.recipe
	scenery_library.material_profile = scene_recipe.get("sceneryMaterial", {})

	# --- E01 / E02 / E03 / E12: one shared hole-aware dry surface
	var floor_mat: ShaderMaterial = ShaderMaterial.new()
	floor_mat.shader = load(str(scene_recipe["floorShader"])) as Shader if scene_recipe.has("floorShader") else FLOOR
	floor_mat.set_shader_parameter("water_corner", Vector2(corner[0], corner[1]))
	floor_mat.set_shader_parameter("land_half_size", Vector2(map["floor_size_xz"][0] * 0.5, map["floor_size_xz"][1] * 0.5))
	if factory.theme_id == "amusement":
		floor_mat.set_shader_parameter("walkway_color", Vector3(0.64, 0.62, 0.55))
		floor_mat.set_shader_parameter("paving_color", Vector3(0.82, 0.72, 0.54))
		floor_mat.set_shader_parameter("asphalt_color", Vector3(0.29, 0.37, 0.42))
		floor_mat.set_shader_parameter("kerb_color", Vector3(0.90, 0.78, 0.59))
	elif factory.theme_id == "snack":
		floor_mat.set_shader_parameter("walkway_color", Vector3(0.74, 0.66, 0.64))
		floor_mat.set_shader_parameter("paving_color", Vector3(0.91, 0.79, 0.67))
		floor_mat.set_shader_parameter("asphalt_color", Vector3(0.45, 0.37, 0.44))
		floor_mat.set_shader_parameter("kerb_color", Vector3(0.95, 0.83, 0.73))
	for key in scene_recipe.get("floor", {}):
		var value = scene_recipe["floor"][key]
		floor_mat.set_shader_parameter(key, Vector3(value[0],value[1],value[2]) if value is Array else value)
	var marks: Array = scene_recipe.get("groundMarks", [])
	var motifs := PackedVector4Array()
	var colors := PackedColorArray()
	var rotations := PackedVector2Array()
	var options := PackedVector2Array()
	for i in range(32):
		var mark: Dictionary = marks[i] if i < mini(marks.size(),32) else {}
		var center: Array = mark.get("center",[0,0])
		var color: Array = mark.get("color",[0,0,0,0])
		var angle: float = float(mark.get("angle",0.0))
		motifs.append(Vector4(center[0],center[1],float(mark.get("radius",1.0)),2.0 if mark.get("shape","")=="rounded_rect" else (1.0 if mark.get("shape","")=="triangle" else 0.0)))
		colors.append(Color(color[0],color[1],color[2],color[3]))
		rotations.append(Vector2(cos(angle),sin(angle)))
		options.append(Vector2(float(mark.get("aspect",1.0)),1.0 if mark.get("roadOnly",false) else 0.0))
	floor_mat.set_shader_parameter("motif_count",mini(marks.size(),32))
	floor_mat.set_shader_parameter("motifs",motifs)
	floor_mat.set_shader_parameter("motif_colors",colors)
	floor_mat.set_shader_parameter("motif_rotations",rotations)
	floor_mat.set_shader_parameter("motif_options",options)
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(map["floor_size_xz"][0], map["floor_size_xz"][1])
	var floor_view: MeshInstance3D = MeshInstance3D.new()
	floor_view.name = "DryLand_HoleAware"
	floor_view.mesh = floor_mesh
	floor_view.material_override = floor_mat
	root.add_child(floor_view)

	# --- E06: water. Visual only, never walkable, never scoring.
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "Water_NOT_PLAYABLE"
	var water_mesh: PlaneMesh = PlaneMesh.new()
	water_mesh.size = Vector2(88.0, 72.0)
	water.mesh = water_mesh
	water.position.y = -0.40
	var water_mat: ShaderMaterial = ShaderMaterial.new()
	water_mat.shader = load(str(scene_recipe.get("waterShader", "res://shaders/water.gdshader"))) as Shader
	water_mat.set_shader_parameter("water_corner", Vector2(corner[0], corner[1]))
	water_mat.set_shader_parameter("land_half_size", Vector2(map["floor_size_xz"][0] * 0.5, map["floor_size_xz"][1] * 0.5))
	if factory.theme_id == "amusement":
		water_mat.set_shader_parameter("deep_color", Vector3(0.075, 0.24, 0.33))
		water_mat.set_shader_parameter("light_color", Vector3(0.24, 0.53, 0.57))
	elif factory.theme_id == "snack":
		water_mat.set_shader_parameter("deep_color", Vector3(0.12, 0.32, 0.38))
		water_mat.set_shader_parameter("light_color", Vector3(0.34, 0.63, 0.64))
	for key in scene_recipe.get("water", {}):
		var value: Array = scene_recipe["water"][key]
		water_mat.set_shader_parameter(key,Vector3(value[0],value[1],value[2]))
	water.material_override = water_mat
	root.add_child(water)

	# --- E05 understructure: decomposed around the inlet, never filling the hole cavity.
	var base_mat: Material = factory.scenery_material(Color("5b4f43"))
	factory.box(root, Vector3(44, 0.20, 26), Vector3(0, -2.90, -5), base_mat)
	factory.box(root, Vector3(31, 0.20, 10), Vector3(6.5, -2.90, 13), base_mat)
	if formal:
		# A skirting mass so the platform reads as a quay block rather than a floating card.
		factory.box(root, Vector3(44, 2.30, 0.60), Vector3(0, -1.30, -17.60), factory.scenery_material(Color("8d7f63")))
		# The south skirt follows the L-shaped land; the cut-out inlet has no quay here.
		var south_length: float = float(map["floor_size_xz"][0])*.5-float(corner[0])
		factory.box(root, Vector3(south_length, 2.30, 0.60), Vector3(float(corner[0])+south_length*.5, -1.30, 17.60), factory.scenery_material(Color("8d7f63")))
		factory.box(root, Vector3(0.60, 2.30, 36), Vector3(21.60, -1.30, 0), factory.scenery_material(Color("8d7f63")))
		factory.box(root, Vector3(13.0, 2.30, 0.60), Vector3(-15.60, -1.30, 7.60), factory.scenery_material(Color("8d7f63")))
		factory.box(root, Vector3(0.60, 2.30, 10), Vector3(-8.60, -1.30, 13.0), factory.scenery_material(Color("8d7f63")))

	# --- E04 / E05 / E07 / E08 / E09 / E10 / E11 background records, verbatim positions
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenery.json"))
	if parsed is Dictionary:
		for row in parsed["scenery"]:
			var arrangement: Dictionary = scene_recipe.get("sceneryOverrides", {}).get(str(row["id"]), {})
			var view: Node3D = Node3D.new()
			view.name = str(row["id"])
			var p: Array = row["position_xyz"]
			view.position = Vector3(p[0], p[1], p[2])
			# Only existing non-playable scenery rows accept these visual transforms.
			# Gameplay instance transforms remain owned by the graybox contract.
			var rotation: Array = arrangement.get("rotationDegrees", [0,0,0])
			var scale_xyz: Array = arrangement.get("scale", [1,1,1])
			view.rotation_degrees = Vector3(rotation[0],rotation[1],rotation[2])
			view.scale = Vector3(scale_xyz[0],scale_xyz[1],scale_xyz[2])
			if formal:
				var asset_key: String = str(arrangement.get("assetKey", row["asset_id"]))
				var formal_view: Node3D = factory.recipe_library.build(asset_key,Vector3.ZERO) if factory.recipe_library.has_asset(asset_key) else scenery_library.build(str(row["asset_id"]), row)
				formal_view.position = Vector3.ZERO
				view.add_child(formal_view)
			else:
				view.set_meta("role", "SCENERY_ONLY")
				view.set_meta("asset_id", row["asset_id"])
				factory.add_parts(view, row["parts"], true)
			root.add_child(view)

	# --- shore collision volumes are unchanged from v0.3; the live player/AI path uses the
	# analytical full-disk solver in land_boundary.gd, not these bodies.
	var banks: StaticBody3D = StaticBody3D.new()
	banks.name = "BankCollision_FuturePhysics"
	banks.collision_layer = 16
	banks.collision_mask = 0
	root.add_child(banks)
	var points: Array = map["land_polygon_xz"]
	for i in range(points.size()):
		var a: Vector2 = Vector2(points[i][0], points[i][1])
		var next: Array = points[(i + 1) % points.size()]
		var b: Vector2 = Vector2(next[0], next[1])
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(a.distance_to(b), 1.0, 0.14)
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3((a.x + b.x) * .5, -.3, (a.y + b.y) * .5)
		collider.rotation.y = -atan2(b.y - a.y, b.x - a.x)
		banks.add_child(collider)
	return {"root": root, "floor_material": floor_mat}
