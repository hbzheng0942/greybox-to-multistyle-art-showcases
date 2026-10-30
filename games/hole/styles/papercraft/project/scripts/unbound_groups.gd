extends RefCounted
## R04 / R07 - the two packed decor groups from reference_bindings_v2.json.
##
## They are built ONLY for the separate review scene. They carry no gameplay binding:
##   production_packaging: PACKED_GROUP
##   runtime_binding:      UNBOUND_VISUAL_GROUP
##   execution_status:     HOLD_BINDING_APPROVAL
## They are never instantiated by scenes/Main.tscn and never added to the 215-unit ledger.
## Nothing here merges two existing swallowable IDs into one prop, and no pot / crate / cup
## is promoted to its own food ID: that would need an approved binding first.

const Kit = preload("res://scripts/art_kit.gd")
const Sink = preload("res://scripts/art_sink.gd")

const BODY := "body"

var kit

func _init() -> void:
	kit = Kit.new()

func _c(token) -> Color:
	return kit.color_of(token)

func build(ref_id: String) -> Node3D:
	var sink = Sink.new()
	var root: Node3D = Node3D.new()
	root.name = ref_id
	root.set_meta("role", "REVIEW_ONLY")
	root.set_meta("production_packaging", "PACKED_GROUP")
	root.set_meta("runtime_binding", "UNBOUND_VISUAL_GROUP")
	root.set_meta("execution_status", "HOLD_BINDING_APPROVAL")
	root.set_meta("in_playable_street", false)
	match ref_id:
		"R04": _donut_decor(sink, root)
		"R07": _boba_props(sink, root)
		_: _generic(sink)
	var mesh: ArrayMesh = sink.commit(BODY)
	if mesh != null and mesh.get_surface_count() > 0:
		var view: MeshInstance3D = MeshInstance3D.new()
		view.name = "GroupSurface"
		view.mesh = mesh
		view.material_override = kit.unit_material()
		root.add_child(view)
	root.set_meta("triangles", sink.triangle_count())
	return root

## R04 - donut shop door decor: planter, crate stack, cups, small A-board. Whole-group look only.
func _donut_decor(sink, root: Node3D) -> void:
	_planter(sink, Vector3(-0.62, 0.0, 0.10), 0.34, _c("c87a55"), _c("blossom"))
	_planter(sink, Vector3(-0.22, 0.0, -0.32), 0.28, _c("c87a55"), _c("flower_yellow"))
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0.22, 0.20, 0.30), Vector3(0.30, 0.30, 0.30), 0.03, _c("wood_light"), 3)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0.22, 0.505, 0.30), Vector3(0.26, 0.24, 0.26), 0.03, _c("wood_mid"), 3)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0.10, 0.02, 0.30), Vector3(0.34, 0.04, 0.34), 0.01, _c("wood_deep"), 2)
	for i in range(3):
		_cup(sink, Vector3(0.58 + 0.16 * float(i), 0.0, -0.22 + 0.06 * float(i)), 1.0 - 0.08 * float(i))
	kit.sign_text(root, "OPEN", Vector3(0.62, 0.62, 0.42), 168.0, 30, 0.0042, _c("fdf6e6"), 5)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0.62, 0.30, 0.34), Vector3(0.46, 0.60, 0.05), 0.02, _c("wood_mid"), 2)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0.62, 0.34, 0.37), Vector3(0.36, 0.42, 0.03), 0.01, _c("2f3a42"), 2)

## R07 - boba shop door props: crates, cups, planter and a tray. Whole-group look only.
func _boba_props(sink, root: Node3D) -> void:
	sink.slab(Kit.at(Vector3.ZERO), Vector3(-0.40, 0.21, 0.0), Vector3(0.44, 0.42, 0.44), 0.04, _c("bin_blue"), 3)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(-0.40, 0.62, 0.0), Vector3(0.40, 0.40, 0.40), 0.04, _c("wood_light"), 3)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(-0.40, 0.86, 0.0), Vector3(0.44, 0.08, 0.44), 0.02, _c("cream_trim"), 2)
	_planter(sink, Vector3(0.10, 0.0, -0.40), 0.30, _c("9a7f68"), _c("leaf_green"))
	for i in range(4):
		_cup(sink, Vector3(0.28 + 0.15 * float(i), 0.0, 0.30 - 0.05 * float(i)), 1.0)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0.70, 0.02, 0.62), Vector3(0.60, 0.04, 0.36), 0.01, _c("wood_mid"), 2)
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0.70, 0.09, 0.62), Vector3(0.34, 0.10, 0.24), 0.02, _c("f4f1e6"), 2)

func _planter(sink, base: Vector3, radius: float, pot: Color, bloom: Color) -> void:
	sink.cylinder(Kit.at(base + Vector3(0, radius * 0.42, 0)), radius * 0.78, radius, radius * 0.84, pot, 12)
	sink.cylinder(Kit.at(base + Vector3(0, radius * 0.86, 0)), radius, radius * 1.04, radius * 0.16, _c("a9603f"), 12, false, false)
	for i in range(3):
		var ang: float = float(i) * 120.0
		sink.sphere(Kit.at(base + Vector3(cos(deg_to_rad(ang)) * radius * 0.36, radius * 1.16, sin(deg_to_rad(ang)) * radius * 0.36)),
			Vector3(radius * 0.42, radius * 0.58, radius * 0.42), _c("leaf_green"), 5, 8)
	sink.sphere(Kit.at(base + Vector3(0, radius * 1.42, 0)), Vector3.ONE * radius * 0.34, bloom, 5, 8)

func _cup(sink, base: Vector3, scale: float) -> void:
	sink.cylinder(Kit.at(base + Vector3(0, 0.13 * scale, 0)), 0.075 * scale, 0.105 * scale, 0.26 * scale,
		_c("e4cfae"), 12)
	sink.cylinder(Kit.at(base + Vector3(0, 0.27 * scale, 0)), 0.115 * scale, 0.11 * scale, 0.05 * scale,
		_c("8d7ccd"), 12)
	sink.sphere(Kit.at(base + Vector3(0, 0.30 * scale, 0)), Vector3(0.115, 0.05, 0.115) * scale, _c("f4f1e6"), 5, 10)
	sink.cylinder(Kit.child(Kit.at(Vector3.ZERO), base + Vector3(0.03, 0.30, 0.0), 0.0, Vector3(0.0, 0.0, 20.0)),
		0.017 * scale, 0.017 * scale, 0.20 * scale, _c("ee8aa6"), 8)

func _generic(sink) -> void:
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.6), 0.04, _c("stone_mid"), 2)
