extends RefCounted
## Visual construction entry point. All children are purely visual: one build() call creates one
## logical unit's view. IDs, fit proxies, support and rewards stay in scripts/simulation.gd.
##
## Two presentation modes, switchable at runtime:
##   FORMAL  - the Toy Downtown Waterfront art pass (scripts/art_library.gd)
##   GRAYBOX - the original v0.3 proxy recipes (data/visual_proxies.json)
## A missing or empty recipe always falls back to the graybox proxy, so no unit can go blank.

const OBJECT_SHADER = preload("res://shaders/object.gdshader")
const ArtKit = preload("res://scripts/art_kit.gd")
const ArtLibrary = preload("res://scripts/art_library.gd")
const ThemeLibrary = preload("res://scripts/theme_library.gd")
const RecipeLibrary = preload("res://scripts/recipe_library.gd")
const HoleArt = preload("res://scripts/hole_art.gd")

const MODE_FORMAL := "formal"
const MODE_GRAYBOX := "graybox"

const TIER_COLORS = [Color("f4a04b"), Color("4bc9a2"), Color("489fcf"), Color("738dd0"), Color("af84b7"), Color("efb65b")]

var art_mode: String = MODE_FORMAL
var theme_id: String = "saffron"
var materials: Dictionary = {}
var mesh_cache: Dictionary = {}
var proxy_assets: Dictionary = {}
var kit
var library
var recipe_library = RecipeLibrary.new()
var hole_art
## asset_id -> {triangles, slots, source}. Feeds the optimisation / status ledger.
var stats: Dictionary = {}
## asset_id -> unpacked prototype Node3D. Instances are duplicated from the prototype so all
## 215 runtime units share 37 ArrayMesh and 1 material instead of holding 215 private ones.
var _prototypes: Dictionary = {}
var _shared_instances: int = 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--theme="):
			var candidate: String = arg.trim_prefix("--theme=")
			if candidate in ["waterfront", "amusement", "snack", "saffron"]:
				theme_id = candidate
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/visual_proxies.json"))
	if parsed is Dictionary:
		for entry in parsed["assets"]:
			proxy_assets[str(entry["asset_id"])] = entry
	kit = ArtKit.new()
	library = ArtLibrary.new() if theme_id == "waterfront" else ThemeLibrary.new()
	if theme_id != "waterfront":
		library.theme_id = theme_id
	# ONE kit, shared. ArtLibrary would otherwise construct its own, which silently creates a
	# second palette and a second set of materials: units would then render with materials nobody
	# else can address (tone sweeps, hole-clip updates, project-wide palette changes all missed it).
	library.kit = kit
	hole_art = HoleArt.new()

func set_mode(mode: String) -> void:
	art_mode = MODE_FORMAL if mode == MODE_FORMAL else MODE_GRAYBOX
	# Cached prototypes belong to one presentation mode; never mix them across a switch.
	clear_cache()
	stats.clear()

## Swaps the Lux3D-sourced meshes in or out without touching any gameplay data, so the same round
## can be rendered both ways for an honest before/after comparison.
func set_use_models(enabled: bool, hold: bool = false) -> void:
	if library != null:
		library.set_use_models(enabled, hold)
	clear_cache()
	stats.clear()

## Prototypes are Node3D — manually managed — held in a Dictionary owned by this RefCounted.
## Nothing else will ever free them, so whoever owns the factory must call this on teardown.
func clear_cache() -> void:
	recipe_library.clear_sources()
	for key in _prototypes.keys():
		var node = _prototypes[key]
		if node != null and is_instance_valid(node):
			node.free()
	_prototypes.clear()
	_shared_instances = 0

## Number of unique meshes actually held in memory (37 for the full variant set, not 215).
func prototype_count() -> int:
	return _prototypes.size()

func is_formal() -> bool:
	return art_mode == MODE_FORMAL

func scenery_material(color: Color) -> ShaderMaterial:
	return kit.shared_material(color)

func material(color: Color) -> ShaderMaterial:
	var key: String = color.to_html()
	if materials.has(key):
		return materials[key]
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = OBJECT_SHADER
	mat.set_shader_parameter("body_color", color)
	mat.set_shader_parameter("use_vertex_color", false)
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
		var position_values: Array = p.get("position", [0, 0, 0])
		var position: Vector3 = Vector3(position_values[0], position_values[1], position_values[2])
		var color: Color = Color(str(p.get("color", "91a5b2")))
		if str(p["kind"]) == "label":
			var label: Label3D = Label3D.new()
			label.text = str(p["text"])
			label.font_size = int(p.get("font_size", 20))
			label.pixel_size = float(p.get("pixel_size", .007))
			label.modulate = color
			label.outline_size = 0
			label.position = position
			label.no_depth_test = false
			root.add_child(label)
			continue
		var values: Array = p["size"]
		var size: Vector3 = Vector3(values[0], values[1], values[2])
		var mat: Material = scenery_material(color) if scenery else material(color)
		var view: MeshInstance3D = MeshInstance3D.new()
		var cache_key: String = str(p["kind"]) + str(values) + str(p.get("top_radius", -1.0)) + str(p.get("inner_radius", -1.0)) + str(p.get("outer_radius", -1.0))
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
					column.top_radius = float(p.get("top_radius", size.x * .5))
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
			view.rotation_degrees = Vector3(angles[0], angles[1], angles[2])
		root.add_child(view)

# --------------------------------------------------------------------- build

## One call builds one logical unit's view. Geometry is generated once per asset variant and then
## shared: the returned node is a duplicate whose Mesh and Material resources are the prototype's.
##
## Why this matters for performance: without sharing, a street holding 20 parcels would keep 20
## identical vertex buffers in VRAM and 20 identical meshes in the render list. With it, the
## round pays for 37 meshes no matter how many of each unit it places, and the only per-instance
## cost left is a transform.
func build(a: Dictionary, asset_id: String = "", instance_id: String = "") -> Node3D:
	var visual_key: String = str(recipe_library.recipe.get("instanceAssets", {}).get(instance_id, asset_id))
	if not recipe_library.has_asset(visual_key):
		visual_key = asset_id
	if art_mode == MODE_FORMAL:
		if not _prototypes.has(visual_key):
			var candidate: Node3D
			if recipe_library.has_asset(visual_key):
				candidate = recipe_library.build(visual_key, _vec3(a["size_xyz"]))
			elif theme_id == "waterfront":
				candidate = library.build(asset_id, str(a.get("gameplay_family", a["id"])), _vec3(a["size_xyz"]))
			else:
				candidate = library.build(asset_id, str(a.get("gameplay_family", a["id"])), _vec3(a["size_xyz"]),
					float(a.get("support_surface_height_from_base", 0.0)))
			if candidate == null:
				return _graybox(a, asset_id)
			var candidate_tris: int = int(candidate.get_meta("triangles", 0))
			if candidate_tris > 0 and not candidate.get_meta("fallback", false):
				_prototypes[visual_key] = candidate
				stats[visual_key] = {
					"triangles": candidate_tris,
					"slots": int(candidate.get_meta("material_slots", 1)),
					"source": str(candidate.get_meta("source", "procedural")),
				}
			else:
				candidate.free()
				stats[visual_key] = {"triangles": 0, "slots": 0, "source": "graybox_fallback"}
		if _prototypes.has(visual_key):
			_shared_instances += 1
			var instance: Node3D = (_prototypes[visual_key] as Node3D).duplicate()
			instance.name = "Visual"
			# Meshes remain shared, but occlusion_fade is mutated for each object.
			# Give each runtime object its own material state and metadata list.
			var own_materials: Array = []
			var copies: Dictionary = {}
			_own_mutable_materials(instance, copies, own_materials)
			instance.set_meta("cutaway_materials", own_materials)
			return instance
	return _graybox(a, asset_id)

func _own_mutable_materials(node: Node, copies: Dictionary, own_materials: Array) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		if mesh_instance.material_override is ShaderMaterial:
			var original: ShaderMaterial = mesh_instance.material_override
			var key: int = original.get_instance_id()
			if not copies.has(key):
				copies[key] = original.duplicate()
				own_materials.append(copies[key])
			mesh_instance.material_override = copies[key]
		if mesh_instance.mesh != null:
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var original_surface: Material = mesh_instance.get_surface_override_material(surface)
				if original_surface is ShaderMaterial:
					var surface_key: int = original_surface.get_instance_id()
					if not copies.has(surface_key):
						copies[surface_key] = original_surface.duplicate()
						own_materials.append(copies[surface_key])
					mesh_instance.set_surface_override_material(surface, copies[surface_key])
	for child in node.get_children():
		_own_mutable_materials(child, copies, own_materials)

func _graybox(a: Dictionary, asset_id: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Visual"
	if proxy_assets.has(asset_id):
		add_parts(root, proxy_assets[asset_id]["proxy_parts"])
	else:
		var s: Array = a["size_xyz"]
		box(root, Vector3(s[0], s[1], s[2]), Vector3.ZERO, material(TIER_COLORS[int(a["min_tier"])]))
	root.set_meta("asset_id", asset_id)
	root.set_meta("status", "PROCEDURAL_PROXY_NOT_FINAL")
	root.set_meta("cutaway", 0.0)
	var own_materials: Array = []
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
	return root

func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

# ----------------------------------------------------------------- black hole

func make_hole(accent: Color, rival: bool = false) -> Node3D:
	return hole_art.make(accent, rival)

func update_hole(view: Node3D, accent: Color, growth01: float, bite_pulse: float,
		face_angle: float, alive: bool) -> void:
	hole_art.update(view, accent, growth01, bite_pulse, face_angle, alive)

# -------------------------------------------------------------------- reports

## Triangle / material-slot ledger for every asset that actually got constructed.
func object_stats() -> Dictionary:
	return stats

func stats_summary() -> Dictionary:
	var total: int = 0
	var slots_max: int = 0
	var procedural: int = 0
	var fallback: int = 0
	for key in stats:
		var entry: Dictionary = stats[key]
		total += int(entry["triangles"])
		slots_max = maxi(slots_max, int(entry["slots"]))
		if str(entry["source"]) == "procedural":
			procedural += 1
		else:
			fallback += 1
	return {
		"variants": stats.size(),
		"triangles_total_per_variant": total,
		"slots_max": slots_max,
		"procedural": procedural,
		"graybox_fallback": fallback,
		"mode": art_mode,
		"prototype_meshes_held": _prototypes.size(),
		"instances_served_from_prototypes": _shared_instances,
	}

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
