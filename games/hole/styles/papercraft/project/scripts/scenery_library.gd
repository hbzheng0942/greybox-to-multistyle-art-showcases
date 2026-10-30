extends RefCounted
## Formal look for the pure-background records in data/scenery.json (E04-E11).
##
## These records carry no reward and no swallow ID; they exist so the waterfront reads as a
## place. Nothing here changes the land polygon, the shore margin or any gameplay rule,
## and no scenery geometry is ever given a support or a payout.

const Kit = preload("res://scripts/art_kit.gd")
const Sink = preload("res://scripts/art_sink.gd")

const BODY := "body"

var kit
var theme_id: String = "waterfront"
var material_profile: Dictionary = {}

func _init() -> void:
	kit = Kit.new()

func _c(token) -> Color:
	return kit.color_of(token)

func build(asset_id: String, row: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = str(row.get("id", asset_id))
	root.set_meta("role", "SCENERY_ONLY")
	root.set_meta("asset_id", asset_id)
	root.set_meta("score", 0)
	var sink = Sink.new()
	match asset_id:
		"E04": _quay(sink, _part_size(row), _part_yaw(row))
		"E05": _bank(sink)
		"E07": _boat(sink)
		"E08": _bridge(sink)
		"E09": _bg_building(sink, str(row.get("id", "")), 6.0, 9.5, 6.0) if theme_id == "waterfront" else _theme_backdrop(sink, str(row.get("id", "")), 6.0, 9.5, 6.0)
		"E10": _bg_building(sink, str(row.get("id", "")), 6.4, 12.4, 6.4) if theme_id == "waterfront" else _theme_backdrop(sink, str(row.get("id", "")), 6.4, 12.4, 6.4)
		"E11": _tree(sink, str(row.get("id", ""))) if theme_id == "waterfront" else _theme_tree(sink, str(row.get("id", "")))
		_: _generic(sink)
	var mesh: ArrayMesh = sink.commit(BODY)
	if mesh != null and mesh.get_surface_count() > 0:
		var view: MeshInstance3D = MeshInstance3D.new()
		view.name = "Scenery"
		view.mesh = mesh
		if material_profile.get("model", "") == "physical_vertex_color":
			# Scene-authored backdrop lighting shares the physical light response of
			# the new production assets. Legacy toy emission remains in old builds.
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.roughness = float(material_profile.get("roughness", 0.9))
			material.metallic_specular = float(material_profile.get("specular", 0.2))
			view.material_override = material
		else:
			view.material_override = kit.unit_material()
			view.material_override.set_shader_parameter("enable_hole_clip", false)
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(view)
	root.set_meta("triangles", sink.triangle_count())
	return root

func _part_size(row: Dictionary) -> Vector3:
	var parts: Array = row.get("parts", [])
	if parts.is_empty():
		return Vector3(20.0, 0.9, 0.24)
	var values: Array = parts[0].get("size", [20.0, 0.9, 0.24])
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _part_yaw(row: Dictionary) -> float:
	var parts: Array = row.get("parts", [])
	if parts.is_empty():
		return 0.0
	var rot: Array = parts[0].get("rotation_degrees", [0.0, 0.0, 0.0])
	return float(rot[1])

# ------------------------------------------------------------------- E04 quay

## Stone quay wall: it only ever goes DOWN from the deck, so it can never act as a kerb that
## blocks a growing hole. A coping course and mooring rings keep it from reading as a slab.
func _quay(sink, size: Vector3, yaw: float) -> void:
	var length: float = maxf(4.0, size.x)
	var f: Transform3D = Kit.at(Vector3.ZERO, yaw)
	sink.slab(f, Vector3(0, -0.52, 0), Vector3(length, 1.04, 0.30), 0.03, _c("stone_shadow"), 3)
	sink.slab(f, Vector3(0, -1.16, 0), Vector3(length, 0.28, 0.42), 0.02, _c("a4967a"), 2)
	sink.banded_slab(f, Vector3(0, -0.05, 0), Vector3(length, 0.20, 0.40), 0.025,
		maxi(6, int(length / 0.9)), 0, _c("stone_light"), _c("stone_mid"), 2)
	# Block courses: shallow joints so the wall is stone, not a smooth plate.
	var courses: int = maxi(2, int(length / 1.6))
	sink.banded_slab(f, Vector3(0, -0.52, -0.155), Vector3(length, 0.14, 0.03), 0.01,
		courses, 0, _c("a4967a"), _c("8d7f63"), 1)
	# Mooring rings on the water side.
	var rings: int = maxi(2, int(length / 4.2))
	for i in range(rings):
		var x: float = -length * 0.5 + length * (float(i) + 0.5) / float(rings)
		var ring: Transform3D = Kit.child(f, Vector3(x, -0.60, 0.19), 0.0, Vector3(90.0, 0.0, 0.0))
		sink.torus(ring, 0.085, 0.028, _c("metal_dark"), 12, 6)
		sink.slab(f, Vector3(x, -0.70, 0.17), Vector3(0.10, 0.10, 0.09), 0.02, _c("metal_dark"), 2)

# ------------------------------------------------------------------- E05 bank

func _bank(sink) -> void:
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0, -0.60, 0), Vector3(62.0, 1.20, 9.0), 0.05,
		_c("stone_shadow"), 3)
	sink.banded_slab(Kit.at(Vector3.ZERO), Vector3(0, -0.06, 0.0), Vector3(62.0, 0.22, 9.4), 0.04, 24, 0,
		_c("paving"), _c("stone_mid"), 2)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0, -1.40, 0), Vector3(60.0, 0.40, 8.0), 0.04, _c("a4967a"), 2)

# ------------------------------------------------------------------- E07 boat

func _boat(sink) -> void:
	var f: Transform3D = Kit.at(Vector3.ZERO)
	sink.slab(f, Vector3(0, 0.18, 0), Vector3(3.10, 0.46, 1.30), 0.14, _c("f4f1e6"), 3)
	sink.slab(f, Vector3(0, 0.44, 0), Vector3(2.70, 0.06, 1.06), 0.03, _c("wood_light"), 2)
	sink.slab(f, Vector3(0, 0.10, 0), Vector3(3.14, 0.16, 1.34), 0.07, _c("46789f"), 2)
	sink.slab(f, Vector3(-0.9, 0.62, 0), Vector3(1.10, 0.52, 1.00), 0.06, _c("f4f1e6"), 3)
	sink.slab(f, Vector3(-0.9, 0.90, 0), Vector3(1.24, 0.08, 1.14), 0.03, _c("d9603f"), 2)
	sink.slab(f, Vector3(0.95, 0.66, 0), Vector3(1.00, 0.06, 0.90), 0.02, _c("cbb894"), 2)
	sink.cylinder(Kit.at(Vector3(0.35, 1.10, 0)), 0.035, 0.030, 1.60, _c("wood_deep"), 8)
	sink.slab(f, Vector3(0.35, 1.92, 0), Vector3(0.30, 0.22, 0.03), 0.01, _c("47c9ee"), 1)
	sink.torus(Kit.at(Vector3(0.35, 0.72, 0)), 0.20, 0.03, _c("f4f1e6"), 14, 6)

# ----------------------------------------------------------------- E08 bridge

func _bridge(sink) -> void:
	var f: Transform3D = Kit.at(Vector3.ZERO)
	for i in range(7):
		var x: float = -7.2 + 2.4 * float(i)
		var lift: float = 0.55 * (1.0 - abs(float(i) - 3.0) / 3.0)
		sink.slab(f, Vector3(x, 1.60 + lift, 0), Vector3(2.5, 0.30, 3.0), 0.05, _c("paving"), 2)
		sink.slab(f, Vector3(x, 1.80 + lift, 0), Vector3(2.5, 0.10, 2.6), 0.03, _c("stone_light"), 2)
		sink.slab(f, Vector3(x, 1.78 + lift, 1.40), Vector3(2.5, 0.34, 0.14), 0.03, _c("stone_light"), 2)
		sink.slab(f, Vector3(x, 1.78 + lift, -1.40), Vector3(2.5, 0.34, 0.14), 0.03, _c("stone_light"), 2)
	for i in range(3):
		var x2: float = -4.8 + 4.8 * float(i)
		var pier: float = 1.45 - abs(x2) * 0.10
		sink.slab(f, Vector3(x2, pier * 0.5 - 0.5, 0), Vector3(1.10, pier + 1.0, 2.30), 0.05,
			_c("stone_mid"), 2)
		sink.slab(f, Vector3(x2, pier + 0.02, 0), Vector3(1.40, 0.16, 2.60), 0.03, _c("stone_deep"), 2)
	for i in range(2):
		var x3: float = -8.6 - 1.6 * float(i)
		sink.slab(f, Vector3(x3, 0.45, 0), Vector3(1.7, 2.9, 3.2), 0.06, _c("stone_mid"), 2)
	# Arch voids: dark blocks that read as openings under the deck.
	for i in range(2):
		var x4: float = -3.0 + 6.0 * float(i)
		sink.slab(f, Vector3(x4, 0.85, 0.95), Vector3(2.2, 1.30, 0.20), 0.10, _c("26313a"), 2)
		sink.slab(f, Vector3(x4, 0.85, -0.95), Vector3(2.2, 1.30, 0.20), 0.10, _c("26313a"), 2)

# ---------------------------------------------------------- E09 / E10 backdrop

func _bg_building(sink, id: String, width: float, height: float, depth: float) -> void:
	var seed: int = abs(id.hash()) % 3
	var facade: Color = [_c("bg_facade_a"), _c("bg_facade_b"), _c("bg_facade_c")][seed]
	var f: Transform3D = Kit.at(Vector3.ZERO)
	sink.slab(f, Vector3(0, height * 0.5, 0), Vector3(width, height, depth), 0.10, facade, 3)
	sink.slab(f, Vector3(0, height + 0.22, 0), Vector3(width + 0.30, 0.44, depth + 0.30), 0.06, _c("stone_light"), 2)
	sink.slab(f, Vector3(0, height + 0.50, 0), Vector3(width - 0.7, 0.24, depth - 0.7), 0.05, _c("bg_roof"), 2)
	var rows: int = maxi(2, int((height - 2.2) / 2.1))
	for r in range(rows):
		for c in range(3):
			var x: float = (float(c) - 1.0) * (width * 0.28)
			var y: float = 1.85 + 2.05 * float(r)
			sink.slab(f, Vector3(x, y, depth * 0.5 + 0.02), Vector3(width * 0.17, 0.95, 0.10), 0.03,
				_c("f4f1e6"), 2)
			sink.slab(f, Vector3(x, y, depth * 0.5 + 0.08), Vector3(width * 0.12, 0.74, 0.05), 0.02,
				_c("6ba3d0"), 2)
	for side in [-1.0, 1.0]:
		for r in range(rows):
			sink.slab(f, Vector3(side * (width * 0.5 + 0.02), 1.85 + 2.05 * float(r), 0),
				Vector3(0.10, 0.95, depth * 0.22), 0.03, _c("f4f1e6"), 2)
	sink.slab(f, Vector3(0, 1.05, depth * 0.5 + 0.04), Vector3(width * 0.78, 1.10, 0.12), 0.04,
		_c("46789f"), 2)

func _theme_backdrop(sink, id: String, width: float, height: float, depth: float) -> void:
	var seed: int = abs(id.hash()) % 3
	var f: Transform3D = Kit.at(Vector3.ZERO)
	if theme_id == "amusement":
		# Background pavilions and rounded ride towers keep the waterfront skyline position,
		# while changing the structure that occupies it. They carry no gameplay ID.
		var body: Color = [Color("db8962"), Color("72aaa4"), Color("e9bd65")][seed]
		sink.slab(f, Vector3(0, height * .28, 0), Vector3(width * .76, height * .55, depth * .74), .18, body, 3)
		for x in [-.32, .32]:
			for z in [-.32, .32]:
				sink.cylinder(Kit.at(Vector3(width * x, height * .38, depth * z)), width * .055, width * .055, height * .72, Color("fff0ca"), 10)
		sink.slab(f, Vector3(0, height * .73, 0), Vector3(width * .93, height * .10, depth * .90), .08, Color("fff0ca"), 3)
		sink.cylinder(Kit.at(Vector3(0, height * .81, 0)), width * .21, width * .25, height * .18, body, 14)
		sink.sphere(Kit.at(Vector3(0, height * .96, 0)), Vector3(width * .28, height * .055, depth * .28), Color("f4d16f"), 7, 14)
		for x in [-.24, 0.0, .24]:
			sink.slab(f, Vector3(width * x, height * .48, depth * .385), Vector3(width * .11, height * .18, .06), .02, Color("395f73"), 2)
	else:
		# Snack backdrop reads as tall illustrated packaging and candy-store display,
		# with a broad roof object visible from the fixed 52-degree camera.
		var pack: Color = [Color("e7a06e"), Color("9dc5a8"), Color("b994bf")][seed]
		sink.slab(f, Vector3(0, height * .39, 0), Vector3(width * .75, height * .77, depth * .76), .20, pack, 3)
		for x in [-.32, -.16, 0.0, .16, .32]:
			sink.slab(f, Vector3(width * x, height * .38, depth * .39), Vector3(width * .055, height * .62, .07), .018, Color("fff0d7"), 2)
		sink.slab(f, Vector3(0, height * .79, 0), Vector3(width * .84, height * .09, depth * .84), .07, Color("fff0d7"), 3)
		sink.sphere(Kit.at(Vector3(0, height * .89, 0)), Vector3(width * .30, height * .09, depth * .29), Color("9d654f"), 8, 16)
		for i in 6:
			var angle: float = TAU * float(i) / 6.0
			sink.sphere(Kit.at(Vector3(cos(angle) * width * .18, height * .985, sin(angle) * depth * .17)), Vector3(.16, .08, .16), Color("f0d38f"), 5, 8)

func _theme_tree(sink, id: String) -> void:
	var seed: int = abs(id.hash()) % 3
	var f: Transform3D = Kit.at(Vector3.ZERO)
	var bright: Array = [Color("f2b963"), Color("eb8d85"), Color("80bcb0"), Color("9b83b7")]
	if theme_id == "amusement":
		sink.slab(f, Vector3(0, .16, 0), Vector3(.78, .32, .78), .08, Color("e8d1a4"), 2)
		sink.cylinder(Kit.at(Vector3(0, 1.05, 0)), .08, .10, 1.75, Color("f8ebce"), 8)
		for i in 4:
			var a: float = TAU * float(i) / 4.0 + float(seed) * .3
			sink.sphere(Kit.at(Vector3(cos(a) * .48, 2.15 + .15 * sin(a), sin(a) * .40)), Vector3(.48, .62, .48), bright[i], 8, 12)
	else:
		sink.slab(f, Vector3(0, .15, 0), Vector3(.68, .30, .68), .07, Color("e6b391"), 2)
		sink.cylinder(Kit.at(Vector3(0, 1.10, 0)), .11, .12, 1.90, Color("f8e9cc"), 8)
		for i in 3:
			sink.sphere(Kit.at(Vector3((float(i) - 1.0) * .47, 2.12 + .15 * float(i % 2), 0)), Vector3(.55, .47, .55), bright[(i + seed) % 4], 8, 12)

# ------------------------------------------------------------------- E11 tree

func _tree(sink, id: String) -> void:
	var seed: int = abs(id.hash()) % 3
	var scale: float = 0.88 + 0.16 * float(seed)
	var f: Transform3D = Kit.at(Vector3.ZERO, float(seed) * 37.0)
	sink.cylinder(Kit.child(f, Vector3(0, 0.75 * scale, 0)), 0.16 * scale, 0.20 * scale,
		1.50 * scale, _c("7a4e26"), 8)
	sink.sphere(Kit.child(f, Vector3(0, 2.10 * scale, 0)), Vector3(1.05, 0.92, 1.05) * scale,
		_c("leaf_deep"), 7, 12)
	sink.sphere(Kit.child(f, Vector3(0.42 * scale, 2.62 * scale, 0.18 * scale)),
		Vector3(0.72, 0.66, 0.72) * scale, _c("leaf_green"), 6, 10)
	sink.sphere(Kit.child(f, Vector3(-0.44 * scale, 2.48 * scale, -0.16 * scale)),
		Vector3(0.66, 0.60, 0.66) * scale, _c("7fb45f"), 6, 10)

func _generic(sink) -> void:
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0, 0.4, 0), Vector3(2.0, 0.8, 2.0), 0.05, _c("stone_shadow"), 2)
