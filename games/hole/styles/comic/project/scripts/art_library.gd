extends RefCounted
## Formal procedural art for every swallowable variant in manifests/formal_assets_v1.csv.
##
## Authoring convention: every recipe builds from y = 0 upward, centred on x/z, and the caller
## wraps the result so the model's base sits at the envelope bottom. JSON positions keep meaning
## "envelope centre" and every pivot correction happens in the visual child, as the contract asks.
##
## Rounded-box corners are exact SDF roots, so the toy bevel is real geometry with analytic
## normals rather than a smoothing pass. Stripes, crate slats, ball panels and window rows are
## baked as banded segments: no textures, no extra material slots, still one surface per group.
##
## Landmark mapping follows manifests/reference_bindings_v2.json:
##   R01 + R02 -> P36 | R05 + R06 -> P37 | duck + procedural pedestal -> P35
##   R04 / R07 are deliberately absent: they stay in the separate review scene, unbound.

const Kit = preload("res://scripts/art_kit.gd")
const Sink = preload("res://scripts/art_sink.gd")

const BODY := "body"
const GLOW := "glow"

## Lux3D-sourced meshes, one entry per swappable asset, each entry a list of parts.
##
## Every part is fitted to its OWN sub-envelope with a single uniform scale (never squashed) and
## then bottom-aligned, so a part can never overflow the gameplay box. `bottom` is the height of
## the part's base inside the unit; `stack` instead glues the part onto the previous part's real
## top. Stacking is what keeps a roof sign seated on its shell even when that shell letterboxes
## (P37's shell fills 1.92 of its 2.20 sub-envelope, so a hard-coded 2.20 would leave a gap).
##
## The sub-envelopes of a two-part landmark sum to the CSV envelope: 2.20 + 1.00 = 3.20.
## ACTIVE registry. Only units the trial assembly actually proved better than the procedural
## recipe are wired in; see delivery/TRIAL_ASSEMBLY_v1.md for the per-unit evidence.
##   P21 pickup, P22 snack van - silhouette-driven, no roof to look down into, clearly better.
##   P35 duck - decisive; only its Lux3D half is used, the pedestal stays procedural.
const LUX3D_PARTS := {
	"P21": [{"mesh": "res://assets/models/P21.res", "sub": Vector3(1.5, 0.8, 0.8), "bottom": 0.0}],
	"P22": [{"mesh": "res://assets/models/P22.res", "sub": Vector3(1.5, 0.8, 0.8), "bottom": 0.0}],
	# R11 is look-only: the duck rides a pedestal that stays procedural, so the duck gets a
	# sub-envelope above that pedestal instead of the whole 4.0 x 3.2 x 3.1 box.
	"P35": [{"mesh": "res://assets/models/P35_duck.res", "sub": Vector3(2.6, 1.56, 2.4), "bottom": 1.64}],
}

## ON HOLD. Gated, budget-clean and wired-ready, but NOT enabled by default.
##
## These six are all roofed buildings and the game camera looks down at 52 degrees, so most of what
## the player sees of one is its roof. The Lux3D models were produced from eye-level 3/4 references,
## so their roofs are bare plates: at 52 degrees P36's shell is an empty white plateau and P31's is a
## plain grey slab, where the procedural recipes carry a deliberate roof language (deck colour,
## parapet, planting, HVAC) written for exactly this camera. Measured on the gated meshes the units
## also lose chroma (P31 sat 0.233 vs the procedural 0.322), which a chroma boost did not fix.
##
## Turning them back on is a one-line move: merge this dictionary into LUX3D_PARTS. The right fix is
## to re-generate the references as ~52-degree views that include the roof, then re-run the gate.
##
## `tilt` is the rooftop-sign answer to the same 52-degree problem, and it is deliberately an
## ASSEMBLY-level fix rather than a re-generation: the isolated R02/R06 renders are good, they are
## simply upright billboards, and from 52 degrees above an upright billboard shows only its top
## edge. Leaning it back turns the face toward the player. The play camera pitches 52 degrees down,
## so at a tilt of -42 the sign's face normal sits 10 degrees off the view axis - readable, while
## still clearly a sign standing on a roof. A consequence the fitter handles: a tilted box is
## taller and deeper than the upright one, so `_place_parts` re-fits against the rotated extent.
const ROOF_SIGN_TILT := -42.0
const LUX3D_PARTS_HOLD := {
	"P31": [{"mesh": "res://assets/models/P31.res", "sub": Vector3(2.6, 1.6, 2.4), "bottom": 0.0}],
	"P32": [{"mesh": "res://assets/models/P32.res", "sub": Vector3(2.6, 1.6, 2.4), "bottom": 0.0}],
	"P33": [{"mesh": "res://assets/models/P33.res", "sub": Vector3(2.6, 1.6, 2.4), "bottom": 0.0}],
	"P34": [{"mesh": "res://assets/models/P34.res", "sub": Vector3(2.6, 1.6, 2.4), "bottom": 0.0}],
	"P36": [
		{"mesh": "res://assets/models/P36_shell.res", "sub": Vector3(4.0, 2.2, 3.1), "bottom": 0.0},
		{"mesh": "res://assets/models/R02_sign.res", "sub": Vector3(2.6, 1.0, 2.6),
			"stack": true, "tilt": ROOF_SIGN_TILT},
	],
	"P37": [
		{"mesh": "res://assets/models/P37_shell.res", "sub": Vector3(4.0, 2.2, 3.1), "bottom": 0.0},
		{"mesh": "res://assets/models/R06_sign.res", "sub": Vector3(2.6, 1.0, 2.6),
			"stack": true, "tilt": ROOF_SIGN_TILT},
	],
}

var kit
var last_triangles: int = 0
var last_slots: int = 0
## Master switch. Flipping it off restores the procedural recipes without touching any data,
## which is what makes the before/after comparison in the trial assembly honest.
var use_models: bool = true
## Opt-in for the on-hold shells, so a reviewer can still render them without editing the registry.
var use_hold: bool = false

func _init() -> void:
	kit = Kit.new()

func _c(token) -> Color:
	return kit.color_of(token)

# ------------------------------------------------------------------- entry point

## Returns a Node3D whose local origin is the envelope centre for `size` (X width, Y height, Z depth).
func build(asset_id: String, archetype: String, size: Vector3) -> Node3D:
	var sink = Sink.new()
	var root: Node3D = Node3D.new()
	root.name = "Visual"
	var model: Node3D = Node3D.new()
	model.name = "Model"
	model.position = Vector3(0.0, -size.y * 0.5, 0.0)
	root.add_child(model)

	var parts: Array = []
	if use_models and LUX3D_PARTS.has(asset_id):
		parts = LUX3D_PARTS[asset_id]
	elif use_models and use_hold and LUX3D_PARTS_HOLD.has(asset_id):
		parts = LUX3D_PARTS_HOLD[asset_id]
	if not parts.is_empty() and _parts_ready(parts):
		# Optional "<asset>_base" recipe keeps the procedural half of a composite unit: P35's
		# pedestal stays procedural because R11 forbids generating the plaza as one piece.
		var base_recipe: String = "_a_" + asset_id + "_base"
		if has_method(base_recipe):
			call(base_recipe, sink, model, size)
		var lux_tris: int = _place_parts(model, parts)
		_assemble(root, model, sink, asset_id, lux_tris, "LUX3D_FORMAL")
		return root

	var recipe: String = "_a_" + asset_id
	if has_method(recipe):
		call(recipe, sink, model, size)
	elif has_method("_a_" + archetype):
		call("_a_" + archetype, sink, model, size)
	else:
		generic(sink, model, size, archetype)
	_assemble(root, model, sink, asset_id, 0, "PROCEDURAL_FORMAL")
	return root

func set_use_models(enabled: bool, hold: bool = false) -> void:
	use_models = enabled
	use_hold = hold

func _parts_ready(parts: Array) -> bool:
	for part in parts:
		if not ResourceLoader.exists(str(part["mesh"])):
			push_warning("Lux3D mesh missing, keeping the procedural recipe: " + str(part["mesh"]))
			return false
	return true

func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var raw_verts = arrays[Mesh.ARRAY_VERTEX]
		var raw_index = arrays[Mesh.ARRAY_INDEX]
		var verts: int = 0 if raw_verts == null else (raw_verts as PackedVector3Array).size()
		var idx: int = 0 if raw_index == null else (raw_index as PackedInt32Array).size()
		total += idx / 3 if idx > 0 else verts / 3
	return total

## Scales each part uniformly into its sub-envelope, bottom-aligns it, tracks the real top.
## Places one Lux3D part. Fitting and stacking are done on the ROTATED AABB, so a tilted part still
## cannot overflow its sub-envelope and a `stack` part still lands exactly on the previous top.
func _place_parts(model: Node3D, parts: Array) -> int:
	var tris := 0
	var top: float = 0.0
	for part in parts:
		var path: String = str(part["mesh"])
		var mesh: Mesh = load(path)
		if mesh == null:
			continue
		var sub: Vector3 = part["sub"]
		var src: Vector3 = mesh.get_aabb().size
		var pitch: float = deg_to_rad(float(part.get("tilt", 0.0)))
		var s: float = 1.0
		# A tilt makes the AABB taller and deeper than the raw mesh, so fit against the ROTATED
		# extent. Because the AABB scales linearly with `s`, ONE fit is exact - fitting twice
		# squares the factor.
		#
		# BUG FIX: this used to fit twice, once against `src` and once against `rotated`. For an
		# untilted part `rotated == src`, so the same ratio was applied twice: P35's duck came out
		# at 0.5685 * 0.5685 = 0.323 of its intended size, giving a 2.526-tall landmark against a
		# 3.20 envelope. That was never the duck being squat - the raw mesh is 2.744 tall in a
		# 1.56 sub-envelope, i.e. height-limited and therefore 100% fillable. P21/P22 hid the bug
		# because their ratios sit at ~1.00, where squaring moves the result by half a percent.
		var rotated: Vector3 = _rotated_size(src, pitch)
		if src.x > 0.0 and src.y > 0.0 and src.z > 0.0:
			s = minf(sub.x / rotated.x, minf(sub.y / rotated.y, sub.z / rotated.z))
		var ext: Vector3 = rotated * s * 0.5
		var bottom: float = top if bool(part.get("stack", false)) else float(part["bottom"])
		var view := MeshInstance3D.new()
		view.name = "Lux_" + path.get_file().get_basename()
		view.mesh = mesh
		view.scale = Vector3.ONE * s
		view.rotation.x = pitch
		# The gate writes every mesh centred on its own AABB, so the offset is purely vertical.
		view.position = Vector3(0.0, bottom + ext.y, 0.0)
		view.material_override = kit.unit_material()
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		model.add_child(view)
		top = bottom + ext.y * 2.0
		tris += _mesh_triangles(mesh)
	return tris


## Axis-aligned size of a `size` box after a pitch about X, in degrees-radians.
static func _rotated_size(size: Vector3, pitch: float) -> Vector3:
	var c: float = absf(cos(pitch))
	var sn: float = absf(sin(pitch))
	return Vector3(size.x, size.y * c + size.z * sn, size.y * sn + size.z * c)

func _assemble(root: Node3D, model: Node3D, sink, asset_id: String, extra_tris: int = 0,
		status: String = "PROCEDURAL_FORMAL") -> void:
	var mats: Array = []
	for group in sink.groups():
		var mesh: ArrayMesh = sink.commit(group)
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var view: MeshInstance3D = MeshInstance3D.new()
		view.name = "Surface_" + str(group)
		view.mesh = mesh
		var mat: ShaderMaterial = kit.unit_material() if group == BODY else kit.glow_material()
		view.material_override = mat
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		model.add_child(view)
		mats.append(mat)
	# Lux3D parts were parented before this call, so pick their shared material up here too;
	# without it the hole-clipping pass would never fade them.
	for child in model.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			if not mats.has(child.material_override):
				mats.append(child.material_override)
	var total_tris: int = sink.triangle_count() + extra_tris
	root.set_meta("cutaway_materials", mats)
	root.set_meta("cutaway", 0.0)
	root.set_meta("asset_id", asset_id)
	root.set_meta("triangles", total_tris)
	root.set_meta("material_slots", mats.size())
	root.set_meta("status", status)
	root.set_meta("source", "lux3d" if status == "LUX3D_FORMAL" else "procedural")
	last_triangles = total_tris
	last_slots = mats.size()

## Fallback so a missing recipe can never blank a logical unit.
func generic(sink, model: Node3D, size: Vector3, archetype: String) -> void:
	sink.slab(Kit.at(Vector3.ZERO), Vector3(0, size.y * 0.5, 0),
		size * Vector3(0.86, 0.86, 0.86), minf(size.x, minf(size.y, size.z)) * 0.12,
		kit.FALLBACK_COLOR, 3)
	model.set_meta("fallback", true)

# ------------------------------------------------------------------ shorthands

func _f() -> Transform3D:
	return Kit.at(Vector3.ZERO)

## Placed, axis-aligned rounded box. `pos` is the box centre in the recipe frame.
func _bx(sink, pos: Vector3, size: Vector3, radius: float, color: Color, seg: int = 2,
		group: String = BODY, face_colors: Array = []) -> void:
	sink.slab(_f(), pos, size, radius, color, seg, group, face_colors)

## Rotated placed box.
func _rb(sink, pos: Vector3, size: Vector3, radius: float, color: Color, seg: int = 2,
		yaw: float = 0.0, tilt: Vector3 = Vector3.ZERO, group: String = BODY) -> void:
	sink.rbox(Kit.child(_f(), pos, yaw, tilt), size, radius, color, seg, group)

# =============================================================== micro_block

## P01 迷你包裹 - kraft parcel, tape cross, small label.
func _a_P01(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.115, 0), Vector3(0.28, 0.23, 0.26), 0.028, _c("wood_light"), 3)
	_bx(sink, Vector3(0, 0.232, 0), Vector3(0.29, 0.014, 0.075), 0.005, _c("cream_trim"), 2)
	_bx(sink, Vector3(0, 0.232, 0), Vector3(0.075, 0.014, 0.27), 0.005, _c("cream_trim"), 2)
	_bx(sink, Vector3(0.06, 0.20, 0.02), Vector3(0.10, 0.035, 0.10), 0.014, _c("pink_mid"), 2)
	_bx(sink, Vector3(0.0, 0.13, 0.132), Vector3(0.135, 0.088, 0.012), 0.004, _c("stone_light"), 2)
	_bx(sink, Vector3(0.0, 0.14, 0.140), Vector3(0.09, 0.014, 0.006), 0.002, _c("stone_shadow"), 1)

## P02 交通锥 - cone, square base, reflective collar.
func _a_P02(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.022, 0), Vector3(0.29, 0.044, 0.29), 0.018, _c("cone_orange"), 2)
	sink.cylinder(Kit.at(Vector3(0, 0.175, 0)), 0.108, 0.030, 0.27, _c("cone_orange"), 14)
	sink.cylinder(Kit.at(Vector3(0, 0.158, 0)), 0.079, 0.062, 0.055, _c("cone_white"), 14,
		false, false, GLOW)

## P03 小陶盆绿植 - pot, soil, leaves, blossom.
func _a_P03(sink, model: Node3D, size: Vector3) -> void:
	sink.cylinder(Kit.at(Vector3(0, 0.075, 0)), 0.082, 0.106, 0.15, _c("c87a55"), 12)
	sink.cylinder(Kit.at(Vector3(0, 0.145, 0)), 0.107, 0.112, 0.036, _c("a9603f"), 12, false, false)
	sink.cylinder(Kit.at(Vector3(0, 0.163, 0)), 0.094, 0.094, 0.028, _c("6b4c38"), 12)
	for i in range(4):
		var ang: float = float(i) * 90.0 + 35.0
		sink.sphere(Kit.child(_f(), Vector3(cos(deg_to_rad(ang)) * 0.048, 0.205, sin(deg_to_rad(ang)) * 0.048),
			ang, Vector3(30.0, 0.0, 0.0)), Vector3(0.05, 0.10, 0.028), _c("leaf_green"), 5, 8)
	sink.sphere(Kit.at(Vector3(0, 0.222, 0)), Vector3(0.055, 0.068, 0.055), _c("leaf_deep"), 5, 8)
	sink.sphere(Kit.at(Vector3(0, 0.254, 0)), Vector3.ONE * 0.040, _c("blossom"), 5, 8)

## P04 外卖点心盒 - takeaway box with wire handle.
func _a_P04(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.093, 0), Vector3(0.27, 0.185, 0.21), 0.022, _c("stone_light"), 3)
	_bx(sink, Vector3(0, 0.055, 0), Vector3(0.273, 0.048, 0.213), 0.008, _c("brick_salmon"), 2)
	_bx(sink, Vector3(-0.075, 0.245, 0), Vector3(0.024, 0.145, 0.024), 0.01, _c("wood_mid"), 2)
	_bx(sink, Vector3(0.075, 0.245, 0), Vector3(0.024, 0.145, 0.024), 0.01, _c("wood_mid"), 2)
	_bx(sink, Vector3(0, 0.312, 0), Vector3(0.19, 0.026, 0.026), 0.011, _c("wood_mid"), 2)

# ================================================================= tall_pole

## P05 细杆街灯 - plinth, slim pole, warm lantern. Everything stays inside the 0.30 footprint.
func _a_P05(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.018, 0), Vector3(0.24, 0.036, 0.24), 0.014, _c("metal_dark"), 2)
	sink.cylinder(Kit.at(Vector3(0, 0.05, 0)), 0.088, 0.082, 0.06, _c("metal_dark"), 10)
	sink.cylinder(Kit.at(Vector3(0, 0.69, 0)), 0.032, 0.030, 1.27, _c("metal_dark"), 8)
	sink.cylinder(Kit.at(Vector3(0, 1.345, 0)), 0.049, 0.049, 0.036, _c("metal_dark"), 10)
	sink.rbox(Kit.at(Vector3(0, 1.430, 0)), Vector3(0.175, 0.165, 0.175), 0.03, _c("fdf0cf"), 3, GLOW)
	_bx(sink, Vector3(0, 1.541, 0), Vector3(0.215, 0.045, 0.215), 0.016, _c("metal_dark"), 2)
	sink.sphere(Kit.at(Vector3(0, 1.570, 0)), Vector3.ONE * 0.024, _c("metal_dark"), 4, 8)

## P06 玩具路桩 - base disc, tapered post, reflective collars.
func _a_P06(sink, model: Node3D, size: Vector3) -> void:
	sink.cylinder(Kit.at(Vector3(0, 0.028, 0)), 0.135, 0.146, 0.056, _c("metal_dark"), 12)
	sink.cylinder(Kit.at(Vector3(0, 0.78, 0)), 0.062, 0.082, 1.40, _c("bin_blue"), 12)
	sink.cylinder(Kit.at(Vector3(0, 1.05, 0)), 0.087, 0.087, 0.075, _c("fdf0cf"), 12, false, false)
	sink.cylinder(Kit.at(Vector3(0, 1.28, 0)), 0.079, 0.079, 0.075, _c("fdf0cf"), 12, false, false)
	sink.cylinder(Kit.at(Vector3(0, 1.50, 0)), 0.084, 0.067, 0.10, _c("bin_blue"), 12)
	sink.sphere(Kit.at(Vector3(0, 1.552, 0)), Vector3(0.066, 0.048, 0.066), _c("bin_blue"), 4, 10)

# ============================================================= supported_ball

func _a_P07(sink, model: Node3D, size: Vector3) -> void:
	sink.sphere(Kit.at(Vector3(0, 0.155, 0)), Vector3.ONE * 0.155, _c("citrus"), 9, 14)
	sink.sphere(Kit.at(Vector3(0, 0.285, 0)), Vector3(0.028, 0.022, 0.028), _c("f0a41f"), 4, 8)
	sink.sphere(Kit.child(_f(), Vector3(0.028, 0.30, 0.0), 20.0, Vector3(0.0, 0.0, -32.0)),
		Vector3(0.075, 0.018, 0.042), _c("leaf_green"), 4, 8)

func _a_P08(sink, model: Node3D, size: Vector3) -> void:
	sink.sphere(Kit.at(Vector3(0, 0.145, 0)), Vector3(0.155, 0.145, 0.155), _c("tomato"), 9, 14)
	sink.sphere(Kit.at(Vector3(0, 0.255, 0)), Vector3(0.10, 0.05, 0.10), _c("d1483a"), 4, 10)
	sink.cylinder(Kit.at(Vector3(0, 0.295, 0)), 0.012, 0.012, 0.06, _c("7a4e26"), 6)
	sink.sphere(Kit.child(_f(), Vector3(0.045, 0.305, 0.0), 15.0, Vector3(0.0, 0.0, -28.0)),
		Vector3(0.07, 0.016, 0.038), _c("leaf_deep"), 4, 8)

## P09 桌面玩具球 - panels baked as banded geometry, no texture.
func _a_P09(sink, model: Node3D, size: Vector3) -> void:
	var cuts: Array = [0.0, 0.40, 0.52, 0.64, 1.0]
	var cols: Array = [_c("car_coral"), _c("f4f1e6"), _c("car_coral"), _c("car_blue")]
	for i in range(4):
		sink.sphere(Kit.at(Vector3(0, 0.16, 0)), Vector3.ONE * 0.158, cols[i], 5, 14, BODY,
			PI * cuts[i], PI * cuts[i + 1])

# ======================================================================= bin

## P10 - the 14-segment rim is a polygon, so its flat faces sit at r * cos(pi/14) = 0.9749 r, not
## at r. The manifest depth is 0.65, so the rim radius has to clear 0.325 / 0.9749 = 0.3334 BEFORE
## the glued-on plates are added. The body used 0.346 / 0.350, which put the shell itself outside
## the box; every radius below is re-derived from that limit and the plates were pulled in to match.
func _a_P10(sink, model: Node3D, size: Vector3) -> void:
	sink.cylinder(Kit.at(Vector3(0, 0.03, 0)), 0.300, 0.310, 0.06, _c("bin_dark"), 14)
	sink.cylinder(Kit.at(Vector3(0, 0.40, 0)), 0.285, 0.305, 0.70, _c("bin_green"), 14)
	sink.cylinder(Kit.at(Vector3(0, 0.72, 0)), 0.316, 0.326, 0.075, _c("metal_dark"), 14)
	sink.cylinder(Kit.at(Vector3(0, 0.80, 0)), 0.326, 0.316, 0.055, _c("bin_green"), 14)
	_bx(sink, Vector3(0.0, 0.80, 0.245), Vector3(0.20, 0.036, 0.12), 0.014, _c("bin_dark"), 2)
	_bx(sink, Vector3(0.0, 0.44, -0.295), Vector3(0.26, 0.22, 0.035), 0.012, _c("f4f1e6"), 2)
	_bx(sink, Vector3(0.0, 0.45, -0.305), Vector3(0.17, 0.075, 0.02), 0.006, _c("bin_green"), 2)

func _a_P11(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.32, 0), Vector3(0.66, 0.60, 0.56), 0.055, _c("bin_blue"), 3)
	_bx(sink, Vector3(0, 0.10, 0), Vector3(0.62, 0.06, 0.52), 0.02, _c("3f6f9e"), 2)
	_bx(sink, Vector3(0, 0.655, 0), Vector3(0.69, 0.11, 0.59), 0.04, _c("f0e6cf"), 2)
	_bx(sink, Vector3(0, 0.735, 0), Vector3(0.70, 0.07, 0.60), 0.028, _c("bin_blue"), 2)
	_bx(sink, Vector3(0, 0.715, 0.0), Vector3(0.30, 0.05, 0.16), 0.02, _c("3d4a55"), 2)
	_bx(sink, Vector3(0.0, 0.36, -0.285), Vector3(0.34, 0.26, 0.02), 0.012, _c("f4f1e6"), 2)
	kit.icon_plate(sink, _f(), Vector3(0.0, 0.375, -0.30), 0.16, _c("f4f1e6"), _c("mint_deep"), "star")

## P12 街边小黑板 - A-frame; the lettering is an independent Label3D, never baked noise.
func _a_P12(sink, model: Node3D, size: Vector3) -> void:
	for side in [-1.0, 1.0]:
		var panel: Transform3D = Kit.child(_f(), Vector3(0.0, 0.40, side * 0.135), 0.0,
			Vector3(side * -8.0, 0.0, 0.0))
		sink.slab(panel, Vector3.ZERO, Vector3(0.54, 0.74, 0.055), 0.03, _c("wood_mid"), 2)
		sink.slab(panel, Vector3(0.0, 0.0, side * 0.036), Vector3(0.45, 0.62, 0.02), 0.012, _c("2f3a42"), 2)
	kit.sign_text(model, "FRESH", Vector3(0.0, 0.50, -0.208), 180.0, 38, 0.0044, _c("fdf6e6"), 5)
	kit.sign_text(model, "TREATS", Vector3(0.0, 0.36, -0.198), 180.0, 30, 0.0044, _c("f6c447"), 5)
	_bx(sink, Vector3(-0.235, 0.02, 0), Vector3(0.075, 0.04, 0.32), 0.012, _c("wood_deep"), 2)
	_bx(sink, Vector3(0.235, 0.02, 0), Vector3(0.075, 0.04, 0.32), 0.012, _c("wood_deep"), 2)
	# BUG FIX: `Transform3D.rotated()` rotates the ORIGIN about the world axis as well as the basis,
	# so `Kit.at(Vector3(0, 0.775, 0)).rotated(FORWARD, 90deg)` put this hinge bar at (+-0.775, 0, 0)
	# - lying on the ground, off to one side - which is what pushed P12's measured width to 1.337
	# against a 0.750 manifest. `Kit.child` rotates about the part's own origin, which is what was
	# meant. The same mistake appears in _a_P13 (chain links) and _a_P36 (roof donut).
	sink.cylinder(Kit.child(_f(), Vector3(0, 0.775, 0), 0.0, Vector3(0.0, 0.0, 90.0)),
		0.026, 0.026, 0.58, _c("wood_deep"), 8)

# ============================================================== fence_segment

## P13 自包含链栏单段 - each segment owns its posts and chain ends; never a merged whole row.
func _a_P13(sink, model: Node3D, size: Vector3) -> void:
	# Post pitch pulled in from 0.50 to 0.455 and the cap dropped from 0.755 to 0.735 so the widest
	# and tallest vertices land inside 1.10 x 0.80 (the base plate used to reach 0.595, the cap 0.813).
	for side in [-1.0, 1.0]:
		sink.cylinder(Kit.at(Vector3(side * 0.455, 0.025, 0)), 0.090, 0.088, 0.05, _c("metal_dark"), 10)
		sink.cylinder(Kit.at(Vector3(side * 0.455, 0.38, 0)), 0.05, 0.046, 0.70, _c("metal_dark"), 10)
		sink.sphere(Kit.at(Vector3(side * 0.455, 0.735, 0)), Vector3(0.062, 0.058, 0.062), _c("metal_dark"), 5, 10)
		sink.sphere(Kit.at(Vector3(side * 0.455, 0.63, 0)), Vector3(0.068, 0.022, 0.068), _c("metal"), 4, 10)
	var links: int = 9
	for i in range(links):
		var t: float = float(i) / float(links - 1)
		var sag: float = 0.10 * sin(PI * t)
		# BUG FIX: same `Transform3D.rotated()` trap as _a_P12. Rotating the built transform moved
		# every other link from (x, 0.50 - sag, 0) to (x, 0, 0.50 - sag): half the chain was lying
		# flat on the ground at z = 0.51, which is how a 0.200-deep fence measured 0.601 deep.
		var link: Transform3D = Kit.child(_f(), Vector3(-0.40 + 0.80 * t, 0.50 - sag, 0.0), 0.0,
			Vector3(90.0 if i % 2 == 0 else 0.0, 0.0, 0.0))
		sink.torus(link, 0.032, 0.012, _c("metal_dark"), 8, 6)

func _a_P14(sink, model: Node3D, size: Vector3) -> void:
	# Same 1.10 x 0.80 trim as P13: posts in to 0.47, ball cap down to 0.735 (was 0.79 -> 0.852 top).
	for side in [-1.0, 1.0]:
		_bx(sink, Vector3(side * 0.47, 0.03, 0), Vector3(0.12, 0.06, 0.12), 0.018, _c("metal_dark"), 2)
		sink.cylinder(Kit.at(Vector3(side * 0.47, 0.40, 0)), 0.05, 0.046, 0.74, _c("wood_mid"), 10)
		sink.sphere(Kit.at(Vector3(side * 0.47, 0.735, 0)), Vector3.ONE * 0.062, _c("wood_deep"), 5, 10)
	_bx(sink, Vector3(0, 0.645, 0), Vector3(1.02, 0.065, 0.055), 0.02, _c("wood_light"), 2)
	_bx(sink, Vector3(0, 0.335, 0), Vector3(1.02, 0.055, 0.05), 0.018, _c("wood_light"), 2)
	for i in range(3):
		_bx(sink, Vector3(-0.25 + 0.25 * float(i), 0.49, 0), Vector3(0.042, 0.30, 0.04), 0.012, _c("wood_mid"), 2)

# ================================================================ stack_cube

## P15 纸箱货物 - flat top and bottom keep the 0.60 stacking pitch honest.
func _a_P15(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.29, 0), Vector3(0.56, 0.545, 0.50), 0.022, _c("wood_light"), 3)
	_bx(sink, Vector3(0, 0.566, 0), Vector3(0.57, 0.022, 0.51), 0.008, _c("dcae6f"), 2)
	_bx(sink, Vector3(0, 0.582, 0), Vector3(0.10, 0.014, 0.515), 0.004, _c("f0e6cf"), 2)
	_bx(sink, Vector3(0.281, 0.29, 0), Vector3(0.014, 0.55, 0.505), 0.004, _c("c2884a"), 2)
	_bx(sink, Vector3(0, 0.055, 0.0), Vector3(0.565, 0.045, 0.505), 0.01, _c("b87d3f"), 2)
	_bx(sink, Vector3(0.0, 0.32, -0.252), Vector3(0.20, 0.14, 0.012), 0.004, _c("f2e7d0"), 2)

## P16 蓝色周转箱 - lattice bands are geometry, not a texture.
func _a_P16(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.28, 0), Vector3(0.55, 0.50, 0.50), 0.028, _c("bin_blue"), 3)
	_bx(sink, Vector3(0, 0.552, 0), Vector3(0.59, 0.055, 0.54), 0.02, _c("4a7fb0"), 2)
	_bx(sink, Vector3(0, 0.588, 0), Vector3(0.585, 0.045, 0.535), 0.016, _c("f0e6cf"), 2)
	for i in range(3):
		_bx(sink, Vector3(0.0, 0.13 + 0.115 * float(i), -0.252), Vector3(0.42, 0.055, 0.02), 0.01, _c("3f6f9e"), 2)
		_bx(sink, Vector3(0.0, 0.13 + 0.115 * float(i), 0.252), Vector3(0.42, 0.055, 0.02), 0.01, _c("3f6f9e"), 2)
	_bx(sink, Vector3(0, 0.028, 0), Vector3(0.555, 0.05, 0.505), 0.01, _c("3f6f9e"), 2)

# ===================================================================== bench

## Envelope is 1.60 x 0.70 x 0.40. The original bench measured 1.520 x 0.738 x 0.465: the backrest
## ran to 0.726 and the top rail to 0.738 in Y, and the armrest plus back rail reached 0.465 in Z.
## Everything below is re-laid out against those three limits with ~0.01 of margin, same silhouette.
func _bench(sink, model: Node3D, size: Vector3, frame: Color, slat: Color, slat_deep: Color) -> void:
	for i in range(3):
		_bx(sink, Vector3(0, 0.38, -0.075 + 0.075 * float(i)), Vector3(1.52, 0.062, 0.075), 0.02, slat, 2)
	for i in range(3):
		_bx(sink, Vector3(0, 0.46 + 0.080 * float(i), -0.125 - 0.014 * float(i)),
			Vector3(1.52, 0.075, 0.055), 0.018, slat, 2)
	for side in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			_bx(sink, Vector3(side * 0.63, 0.18, zs * 0.115), Vector3(0.07, 0.36, 0.065), 0.016, frame, 2)
		_bx(sink, Vector3(side * 0.70, 0.48, 0.0), Vector3(0.065, 0.055, 0.30), 0.018, frame, 2)
		_bx(sink, Vector3(side * 0.67, 0.34, -0.14), Vector3(0.055, 0.26, 0.055), 0.014, frame, 2)
	_bx(sink, Vector3(0, 0.635, -0.150), Vector3(1.52, 0.075, 0.05), 0.015, slat_deep, 2)

func _a_P17(sink, model: Node3D, size: Vector3) -> void:
	_bench(sink, model, size, _c("metal_dark"), _c("wood_light"), _c("wood_mid"))

func _a_P18(sink, model: Node3D, size: Vector3) -> void:
	_bench(sink, model, size, _c("metal_dark"), _c("mint_mid"), _c("mint_deep"))

# =================================================================== vehicle

## Shared toy chassis: body, glass, wheels and roof parts stay inside 1.5 x 0.8 x 0.8.
##
## Envelope is 1.50 x 0.80 x 0.80, so half-depth is 0.40 - and the wheels were the reason the cars
## measured 1.000 deep: a wheel at z = +-0.345 with radius 0.155 reaches 0.500. The track is pulled
## in to 0.265 and the radius to 0.125 (bottom still exactly on y = 0), and the bumpers move from
## 0.735 to 0.700 so their outer face lands at 0.745 instead of 0.780.
func _car_base(sink, model: Node3D, size: Vector3, body: Color, roof: Color) -> void:
	var dark: Color = Color(body.r * 0.78, body.g * 0.78, body.b * 0.78)
	_bx(sink, Vector3(0, 0.34, 0), Vector3(1.42, 0.30, 0.72), 0.075, body, 3)
	_bx(sink, Vector3(0, 0.205, 0), Vector3(1.44, 0.07, 0.74), 0.03, dark, 2)
	_bx(sink, Vector3(0, 0.60, 0), Vector3(0.80, 0.26, 0.60), 0.06, roof, 3)
	_bx(sink, Vector3(0.40, 0.605, 0), Vector3(0.09, 0.20, 0.56), 0.03, _c("glass_cool"), 2, GLOW)
	_bx(sink, Vector3(-0.40, 0.605, 0), Vector3(0.09, 0.20, 0.56), 0.03, _c("glass_cool"), 2, GLOW)
	_bx(sink, Vector3(0, 0.605, 0.295), Vector3(0.64, 0.19, 0.05), 0.02, _c("glass_cool"), 2, GLOW)
	_bx(sink, Vector3(0, 0.605, -0.295), Vector3(0.64, 0.19, 0.05), 0.02, _c("glass_cool"), 2, GLOW)
	for xs in [-1.0, 1.0]:
		kit.wheel(sink, _f(), Vector3(xs * 0.47, 0.125, 0.265), 0.125, 0.10, _c("tyre"), _c("metal"), 12)
		kit.wheel(sink, _f(), Vector3(xs * 0.47, 0.125, -0.265), 0.125, 0.10, _c("tyre"), _c("metal"), 12)
		_bx(sink, Vector3(xs * 0.700, 0.30, 0), Vector3(0.09, 0.13, 0.62), 0.03, _c("metal"), 2)
		sink.sphere(Kit.at(Vector3(xs * 0.677, 0.34, 0.215)), Vector3(0.05, 0.045, 0.03), _c("ffd9a0"), 4, 8)
		sink.sphere(Kit.at(Vector3(xs * 0.677, 0.34, -0.215)), Vector3(0.05, 0.045, 0.03), _c("e2645a"), 4, 8)

func _a_P19(sink, model: Node3D, size: Vector3) -> void:
	_car_base(sink, model, size, _c("car_coral"), _c("e2645a"))
	_bx(sink, Vector3(0, 0.755, 0), Vector3(0.72, 0.05, 0.60), 0.02, _c("e2645a"), 2)
	_bx(sink, Vector3(0.66, 0.46, 0), Vector3(0.06, 0.10, 0.40), 0.02, _c("f4f1e6"), 2)

## P20 黄色出租车 - the reference has no roof sign; a toy one is added but total height may not grow.
func _a_P20(sink, model: Node3D, size: Vector3) -> void:
	_car_base(sink, model, size, _c("car_yellow"), _c("f4c53a"))
	_bx(sink, Vector3(0, 0.755, 0), Vector3(0.72, 0.05, 0.60), 0.02, _c("f4c53a"), 2)
	sink.banded_slab(_f(), Vector3(0, 0.335, 0), Vector3(1.40, 0.085, 0.70), 0.02, 8, 0,
		_c("f4c53a"), _c("3a3f45"), 2)
	# Roof sign used to top out at 0.840 against a 0.800 envelope; seated at 0.728 it caps at 0.793.
	_bx(sink, Vector3(0, 0.728, 0.0), Vector3(0.26, 0.13, 0.16), 0.035, _c("fdf0cf"), 2, GLOW)

## P21 蓝色小皮卡 - open bed; any cargo there is decoration only.
func _a_P21(sink, model: Node3D, size: Vector3) -> void:
	_car_base(sink, model, size, _c("car_blue"), _c("6ba3d0"))
	_bx(sink, Vector3(-0.34, 0.735, 0), Vector3(0.68, 0.05, 0.62), 0.02, _c("6ba3d0"), 2)
	_bx(sink, Vector3(0.34, 0.45, 0), Vector3(0.72, 0.05, 0.66), 0.02, _c("4e6f96"), 2)
	for zs in [-1.0, 1.0]:
		_bx(sink, Vector3(0.36, 0.55, zs * 0.315), Vector3(0.70, 0.24, 0.055), 0.018, _c("6ba3d0"), 2)
	_bx(sink, Vector3(0.70, 0.55, 0), Vector3(0.06, 0.24, 0.62), 0.018, _c("6ba3d0"), 2)
	_bx(sink, Vector3(0.0, 0.58, 0.0), Vector3(0.06, 0.20, 0.62), 0.018, _c("6ba3d0"), 2)

## P22 薄荷零食车 - serving hatch and awning stay inside the envelope.
func _a_P22(sink, model: Node3D, size: Vector3) -> void:
	## Same 1.50 x 0.80 x 0.80 correction as _car_base, applied to the van's own shell: the wheels
	## reached z = 0.500, the roof cap y = 0.945 and the serving hatch z = 0.403. This recipe only
	## renders when the Lux3D P22 is switched off, which is why none of it showed up in the audit.
	_bx(sink, Vector3(0, 0.50, 0), Vector3(1.42, 0.62, 0.70), 0.07, _c("car_mint"), 3)
	_bx(sink, Vector3(0.0, 0.690, -0.02), Vector3(0.52, 0.20, 0.64), 0.05, _c("9fdcc4"), 3)
	_bx(sink, Vector3(0.62, 0.53, 0), Vector3(0.08, 0.32, 0.64), 0.03, _c("glass_cool"), 2, GLOW)
	_bx(sink, Vector3(0.0, 0.50, 0.340), Vector3(0.72, 0.32, 0.05), 0.02, _c("ffd6a0"), 2, GLOW)
	sink.banded_slab(_f(), Vector3(0.0, 0.665, 0.245), Vector3(1.34, 0.05, 0.30), 0.018, 7, 0,
		_c("car_mint"), _c("f4f1e6"), 2)
	_bx(sink, Vector3(-0.30, 0.710, -0.10), Vector3(0.36, 0.16, 0.30), 0.03, _c("e8dcc0"), 2)
	_bx(sink, Vector3(0.20, 0.710, -0.14), Vector3(0.30, 0.12, 0.26), 0.03, _c("f0c46a"), 2)
	for xs in [-1.0, 1.0]:
		kit.wheel(sink, _f(), Vector3(xs * 0.47, 0.125, 0.265), 0.125, 0.10, _c("tyre"), _c("metal"), 12)
		kit.wheel(sink, _f(), Vector3(xs * 0.47, 0.125, -0.265), 0.125, 0.10, _c("tyre"), _c("metal"), 12)
		sink.sphere(Kit.at(Vector3(xs * 0.700, 0.30, 0.20)), Vector3(0.045, 0.04, 0.03), _c("ffd9a0"), 4, 8)

# ============================================================= support_table

## P23 / P24 - supporting surface exactly 1.00 above the base, silhouette 1.80.
## The canopy is half retracted to the rear so it never hides the six independent payloads,
## and the table itself carries no goods: those keep their own IDs.
##
## Both numbers are MEASURED by tests/probe_support.gd, not asserted: the deck lip tops out at
## exactly 1.0000 so a payload the gameplay layer places at y = 1.00 rests on it instead of sinking
## 16 mm into it, and the tallest geometry (post barrel plus its ball cap) reaches exactly 1.800.
## Before the probe existed the recipe was 1.016 / 1.837, i.e. it overflowed its own envelope.
func _market_table(sink, model: Node3D, size: Vector3, stripe_a: Color, stripe_b: Color,
		skirt: Color, sign: String) -> void:
	_bx(sink, Vector3(0, 0.43, 0), Vector3(1.44, 0.86, 0.80), 0.035, _c("wood_mid"), 3)
	_bx(sink, Vector3(0, 0.30, 0), Vector3(1.45, 0.52, 0.81), 0.02, skirt, 2)
	_bx(sink, Vector3(0, 0.10, 0), Vector3(1.47, 0.16, 0.83), 0.02, _c("wood_deep"), 2)
	_bx(sink, Vector3(0, 0.939, 0), Vector3(1.50, 0.11, 0.82), 0.02, _c("wood_light"), 2)
	_bx(sink, Vector3(0, 0.990, 0), Vector3(1.50, 0.02, 0.82), 0.008, _c("dcae6f"), 2)
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			_bx(sink, Vector3(xs * 0.70, 0.90, zs * 0.375), Vector3(0.10, 1.80, 0.10), 0.022, _c("wood_mid"), 2)
			sink.sphere(Kit.at(Vector3(xs * 0.70, 1.745, zs * 0.375)), Vector3.ONE * 0.055, _c("wood_deep"), 4, 8)
	_bx(sink, Vector3(0, 1.755, -0.375), Vector3(1.50, 0.09, 0.10), 0.02, _c("wood_mid"), 2)
	_bx(sink, Vector3(0, 1.755, 0.375), Vector3(1.50, 0.09, 0.10), 0.02, _c("wood_mid"), 2)
	var canopy: Transform3D = Kit.child(_f(), Vector3(0.0, 1.575, -0.195), 0.0, Vector3(-13.0, 0.0, 0.0))
	sink.banded_slab(canopy, Vector3.ZERO, Vector3(1.48, 0.05, 0.44), 0.02, 8, 0, stripe_a, stripe_b, 2)
	for i in range(8):
		var x: float = -0.74 + 0.185 * (float(i) + 0.5)
		sink.cylinder(Kit.child(canopy, Vector3(x, -0.048, 0.215), 0.0, Vector3(0.0, 0.0, 90.0)),
			0.032, 0.032, 0.175, stripe_a if i % 2 == 0 else stripe_b, 7, false, false)
	_bx(sink, Vector3(-0.62, 1.14, -0.40), Vector3(0.16, 0.10, 0.035), 0.01, _c("wood_deep"), 2)
	kit.sign_text(model, sign, Vector3(0.0, 0.60, 0.418), 0.0, 34, 0.0048, _c("fdf6e6"), 5)

func _a_P23(sink, model: Node3D, size: Vector3) -> void:
	_market_table(sink, model, size, _c("dd5f6a"), _c("f4e6cd"), _c("dd5f6a"), "FRESH")

func _a_P24(sink, model: Node3D, size: Vector3) -> void:
	_market_table(sink, model, size, _c("4f9e7a"), _c("f4e6cd"), _c("4f9e7a"), "DAILY")

# ============================================================ support_pallet

## P25 / P26 - base only. The 5/5/4/4 payloads keep their own existing IDs.
func _pallet(sink, model: Node3D, size: Vector3, plank: Color, block: Color, striped: bool) -> void:
	for zs in [-1.0, 0.0, 1.0]:
		_bx(sink, Vector3(0, 0.026, zs * 0.30), Vector3(1.34, 0.052, 0.11), 0.012, block, 2)
	for i in range(3):
		for j in range(3):
			_bx(sink, Vector3(-0.50 + 0.50 * float(i), 0.112, -0.30 + 0.30 * float(j)),
				Vector3(0.11, 0.11, 0.11), 0.014, block, 2)
	for zs in [-0.32, -0.16, 0.0, 0.16, 0.32]:
		if striped:
			sink.banded_slab(_f(), Vector3(0, 0.198, zs), Vector3(1.34, 0.062, 0.135), 0.014, 6, 0,
				plank, Color(plank.r * 0.86, plank.g * 0.86, plank.b * 0.86), 2)
		else:
			_bx(sink, Vector3(0, 0.198, zs), Vector3(1.34, 0.062, 0.135), 0.014, plank, 2)

func _a_P25(sink, model: Node3D, size: Vector3) -> void:
	_pallet(sink, model, size, _c("wood_mid"), _c("wood_deep"), false)

func _a_P26(sink, model: Node3D, size: Vector3) -> void:
	_pallet(sink, model, size, _c("bin_blue"), _c("35547a"), true)

# =========================================================== building_segment

## Potted roof shrub. The concept art (references/00_concept/CONCEPT_Toy_Downtown_Waterfront.png)
## puts shrubs and planters on EVERY flat roof in the street. Without them a procedurally tidy
## parapet still reads as dead geometry from the game's 52-degree camera, which is why the first
## roof pass looked wrong even after the parapet went in.
func _roof_shrub(sink, base_y: float, x: float, z: float, r: float) -> void:
	sink.cylinder(Kit.at(Vector3(x, base_y + 0.07, z)), r * 0.58, r * 0.72, 0.18, _c("a9603f"), 10)
	sink.sphere(Kit.at(Vector3(x, base_y + 0.13 + r * 0.70, z)), Vector3(r, r * 0.92, r),
		_c("leaf_green"), 5, 8)
	sink.sphere(Kit.at(Vector3(x + r * 0.45, base_y + 0.13 + r * 0.58, z + r * 0.32)),
		Vector3(r * 0.54, r * 0.50, r * 0.54), _c("leaf_deep"), 4, 8)

## P27-P30 - one closed 1.8 x 4.0 x 1.6 row unit: independent sides, base, roof and signage.
func _row_unit(sink, model: Node3D, size: Vector3, facade: Color, trim: Color,
		awning_a: Color, awning_b: Color) -> void:
	## ---- envelope 1.80 x 4.00 x 1.60, so HALF-extents are 0.90 / 0.80, and again the depth budget
	## is what decides the numbers.
	##
	## The measured unit used to be 1.980 x 3.990 x 1.765: the roof coping was authored 1.98 wide
	## (0.99 per side) and the awning scallops reached 0.895 in Z. Tightening only the awning (to
	## its current x = 0.595) would have made the unit compliant AND invisible, because the 15-degree
	## plate only reaches 0.17 * cos15 + 0.025 * sin15 = 0.170 past its own centre: with the wall
	## face at 0.78 there is nowhere inside 0.80 for an awning to project into.
	##
	## So the wall comes back to 0.64 (shell 1.28 deep) and the awning centre sits at 0.595. The
	## plate front lands at 0.765 and the scallop bead at 0.796, both inside the envelope, and the
	## awning now overhangs the storefront by 0.125 instead of being buried in the wall.
	_bx(sink, Vector3(0, 0.12, 0), Vector3(1.78, 0.24, 1.28), 0.03, _c("stone_deep"), 3)
	_bx(sink, Vector3(0, 1.82, 0), Vector3(1.78, 3.16, 1.28), 0.045, facade, 3)
	_bx(sink, Vector3(0.0, 0.60, 0.580), Vector3(1.30, 1.00, 0.10), 0.03, _c("stone_shadow"), 2)
	kit.storefront(sink, _f(), Vector3(0.0, 0.96, 0.580), 1.22, 0.86, 0.10, _c("wood_mid"), _c("ffd6a0"), 2)
	kit.awning(sink, _f(), Vector3(0.0, 1.60, 0.595), 1.52, 0.34, 0.05, 15.0, awning_a, awning_b, 6)
	_bx(sink, Vector3(0.0, 2.10, 0.595), Vector3(1.44, 0.07, 0.06), 0.018, trim, 2)
	_bx(sink, Vector3(0.0, 3.05, 0.595), Vector3(1.44, 0.07, 0.06), 0.018, trim, 2)
	kit.window_grid(sink, _f(), Vector3(-0.42, 2.08, 0.545), 2, 2, Vector3(0.84, 0.96, 0.0),
		Vector3(0.52, 0.74, 0.08), trim, _c("6ba3d0"), true, _c("mint_mid"))
	for xs in [-1.0, 1.0]:
		kit.window_grid(sink, _f(), Vector3(xs * 0.850, 2.30, -0.42), 1, 2, Vector3(0.0, 0.96, 0.84),
			Vector3(0.08, 0.66, 0.46), trim, _c("6ba3d0"), true, Color(0, 0, 0, 0), "x")
	# ---- roof language, matched to the reference shell: cornice -> parapet ring -> cream coping.
	# The old single dark plate read as a black lid at the game's 52-degree camera, which is exactly
	# what the reviewer flagged. Every roof part below sits inside size.y = 4.0 (top of the flue = 3.99).
	var roof_line: float = 3.44
	var roof_deck: Color = facade.darkened(0.30)
	_bx(sink, Vector3(0.0, 3.315, 0.0), Vector3(1.76, 0.07, 1.30), 0.02, _c("stone_shadow"), 2)
	_bx(sink, Vector3(0.0, 3.395, 0.0), Vector3(1.78, 0.09, 1.30), 0.025, _c("cream_trim"), 2)
	# Deck goes down FIRST. The first attempt drew a solid coping plate over it, which hid the deck
	# completely and left the roof reading as one pale slab again.
	_bx(sink, Vector3(0.0, roof_line + 0.02, 0.0), Vector3(1.62, 0.07, 1.02), 0.02, roof_deck, 2)
	# Parapet and coping are RINGS - four separate walls - never a solid plate across the top.
	_bx(sink, Vector3(0.0, roof_line + 0.13, 0.585), Vector3(1.76, 0.26, 0.12), 0.022, facade, 2)
	_bx(sink, Vector3(0.0, roof_line + 0.13, -0.585), Vector3(1.76, 0.26, 0.12), 0.022, facade, 2)
	_bx(sink, Vector3(-0.805, roof_line + 0.13, 0.0), Vector3(0.12, 0.26, 1.20), 0.022, facade, 2)
	_bx(sink, Vector3(0.805, roof_line + 0.13, 0.0), Vector3(0.12, 0.26, 1.20), 0.022, facade, 2)
	_bx(sink, Vector3(0.0, roof_line + 0.295, 0.565), Vector3(1.76, 0.08, 0.17), 0.028, _c("cream_trim"), 2)
	_bx(sink, Vector3(0.0, roof_line + 0.295, -0.565), Vector3(1.76, 0.08, 0.17), 0.028, _c("cream_trim"), 2)
	_bx(sink, Vector3(-0.805, roof_line + 0.295, 0.0), Vector3(0.17, 0.08, 1.32), 0.028, _c("cream_trim"), 2)
	_bx(sink, Vector3(0.805, roof_line + 0.295, 0.0), Vector3(0.17, 0.08, 1.32), 0.028, _c("cream_trim"), 2)
	_bx(sink, Vector3(0.0, roof_line + 0.360, 0.565), Vector3(1.76, 0.06, 0.16), 0.022, _c("stone_light"), 2)
	_bx(sink, Vector3(0.0, roof_line + 0.360, -0.565), Vector3(1.76, 0.06, 0.16), 0.022, _c("stone_light"), 2)
	_bx(sink, Vector3(-0.805, roof_line + 0.360, 0.0), Vector3(0.16, 0.06, 1.30), 0.022, _c("stone_light"), 2)
	_bx(sink, Vector3(0.805, roof_line + 0.360, 0.0), Vector3(0.16, 0.06, 1.30), 0.022, _c("stone_light"), 2)
	# condenser sits ON the deck (base 3.45 vs deck top 3.49) instead of floating above it
	var hvac: Vector3 = Vector3(0.30, roof_line + 0.17, -0.16)
	_bx(sink, hvac, Vector3(0.60, 0.32, 0.48), 0.035, _c("8f9aa3"), 2)
	_bx(sink, hvac + Vector3(0.0, 0.175, 0.0), Vector3(0.64, 0.05, 0.52), 0.02, _c("5d6873"), 2)
	for i in range(3):
		_bx(sink, hvac + Vector3(0.0, -0.085 + 0.085 * float(i), 0.252), Vector3(0.44, 0.042, 0.03),
			0.01, _c("5d6873"), 2)
	sink.cylinder(Kit.at(Vector3(-0.46, roof_line + 0.22, -0.30)), 0.115, 0.115, 0.44, _c("5d6873"), 12)
	sink.cylinder(Kit.at(Vector3(-0.46, roof_line + 0.47, -0.30)), 0.168, 0.150, 0.06, _c("5d6873"), 12)
	sink.cylinder(Kit.at(Vector3(-0.46, roof_line + 0.525, -0.30)), 0.080, 0.080, 0.05, _c("8f9aa3"), 10)
	# slim vent pipe
	sink.cylinder(Kit.at(Vector3(0.58, roof_line + 0.16, -0.48)), 0.055, 0.055, 0.30, _c("8f9aa3"), 8)
	sink.cylinder(Kit.at(Vector3(0.58, roof_line + 0.325, -0.48)), 0.090, 0.078, 0.05, _c("5d6873"), 8)
	# rooftop planting - see _roof_shrub
	_roof_shrub(sink, roof_line, -0.52, 0.34, 0.17)
	_roof_shrub(sink, roof_line, -0.14, 0.42, 0.13)
	_roof_shrub(sink, roof_line, 0.52, 0.32, 0.15)
	kit.icon_plate(sink, _f(), Vector3(0.0, 3.16, 0.600), 0.26, _c("stone_light"), _c("5d6873"), "star")

func _a_P27(sink, model: Node3D, size: Vector3) -> void:
	_row_unit(sink, model, size, _c("e8a08c"), _c("f4e6cd"), _c("e8a08c"), _c("f4e6cd"))

func _a_P28(sink, model: Node3D, size: Vector3) -> void:
	_row_unit(sink, model, size, _c("9ed8b6"), _c("f4f1e6"), _c("6fc09a"), _c("f4e6cd"))

func _a_P29(sink, model: Node3D, size: Vector3) -> void:
	_row_unit(sink, model, size, _c("b3a4e2"), _c("f4f1e6"), _c("8d7ccd"), _c("f4e6cd"))

func _a_P30(sink, model: Node3D, size: Vector3) -> void:
	_row_unit(sink, model, size, _c("ecd9b6"), _c("f4f1e6"), _c("c2884a"), _c("f4e6cd"))

# ============================================================== wide_building

## P31-P34 - a single storey inside the 2.6 x 1.6 x 2.4 low-building envelope.
## R08 / R09 are two-storey references; this keeps their colour, door, window and awning
## language while staying inside the gameplay envelope (see the proportion revision report).
func _low_shop(sink, model: Node3D, size: Vector3, facade: Color, trim: Color, band: Color,
		awning_a: Color, awning_b: Color, sign: String) -> void:
	## ---- the depth budget, which is what actually drove every number below.
	##
	## Envelope half-depth is 1.20 and the awning is the deepest element: an awning tilted 14 degrees
	## reaches centre_z + 0.211 for the plate and centre_z + 0.247 for the scallop bead. So the
	## awning can sit no further out than z = 0.95. A 14-degree awning only reads as an awning if it
	## projects PAST the wall, so the wall has to move back to meet it: the shell is now 2.00 deep
	## (face at 1.00) and the awning lands at 0.95, leaving a genuine 0.16 of overhang.
	##
	## Before this the shell was 2.36 deep and the awning was pushed out to z = 1.10 to clear it.
	## That is what produced the +0.177 depth overflow - but it only bought a VISUAL awning by
	## breaking the envelope, and even then two thirds of the plate sat inside the roof slab and
	## poked through it as crossed slivers in the facade render. Shrinking the shell instead of
	## keeping the awning outside is the only arrangement where both are true at once.
	var half_depth: float = 1.00
	_bx(sink, Vector3(0, 0.08, 0), Vector3(2.56, 0.16, half_depth * 2.0), 0.03, _c("stone_deep"), 3)
	_bx(sink, Vector3(0, 0.72, 0), Vector3(2.56, 1.28, half_depth * 2.0), 0.05, facade, 3)
	_bx(sink, Vector3(0.0, 0.30, 0.940), Vector3(2.48, 0.34, 0.10), 0.03, _c("stone_shadow"), 2)
	kit.storefront(sink, _f(), Vector3(0.55, 0.80, 0.940), 1.10, 0.84, 0.10, _c("wood_mid"), _c("ffd6a0"), 2)
	_bx(sink, Vector3(-0.86, 0.62, 0.980), Vector3(0.56, 0.94, 0.10), 0.03, _c("wood_mid"), 2)
	_bx(sink, Vector3(-0.86, 0.66, 1.010), Vector3(0.44, 0.78, 0.04), 0.02, _c("ffd6a0"), 2, GLOW)
	_bx(sink, Vector3(-0.86, 1.14, 1.010), Vector3(0.50, 0.16, 0.05), 0.02, _c("glass_cool"), 2)
	_bx(sink, Vector3(-0.86, 1.155, 1.015), Vector3(0.16, 0.04, 0.04), 0.014, _c("metal"), 2)
	# Awning at x = 0.43 (1.72 wide, so 1.29 max) and y = 1.26: at 1.33 the plate topped out at
	# 1.41, i.e. THROUGH the roof slab at 1.375. Half-thickness plus the 14-degree rise is 0.080.
	# 1.62 wide centred at 0.45 = [-0.36, 1.26]: the 1.72 version reached x = 1.31, i.e. past the
	# 1.28 side wall, and its end caps showed up as loose slivers in the facade render.
	kit.awning(sink, _f(), Vector3(0.45, 1.260, 0.950), 1.62, 0.42, 0.06, 14.0, awning_a, awning_b, 7)
	_bx(sink, Vector3(0.0, 1.42, 1.000), Vector3(2.36, 0.30, 0.09), 0.03, band, 2)
	kit.sign_text(model, sign, Vector3(0.0, 1.30, 1.060), 0.0, 40, 0.0058, _c("fdf6e6"), 6)
	# ---- same roof language as the row units, compressed into size.y = 1.6, and again as RINGS.
	# The first pass stacked two solid slabs, which both overran the envelope (1.64) and re-covered
	# the deck. Highest point here = 1.58.
	var deck_col: Color = facade.darkened(0.30)
	_bx(sink, Vector3(0.0, 1.375, 0.0), Vector3(2.56, 0.05, half_depth * 2.0), 0.02, _c("cream_trim"), 2)
	_bx(sink, Vector3(0.0, 1.415, 0.0), Vector3(2.22, 0.05, 1.86), 0.018, deck_col, 2)
	_bx(sink, Vector3(0.0, 1.455, 0.920), Vector3(2.40, 0.09, 0.10), 0.02, facade, 2)
	_bx(sink, Vector3(0.0, 1.455, -0.920), Vector3(2.40, 0.09, 0.10), 0.02, facade, 2)
	_bx(sink, Vector3(-1.155, 1.455, 0.0), Vector3(0.10, 0.09, 1.80), 0.02, facade, 2)
	_bx(sink, Vector3(1.155, 1.455, 0.0), Vector3(0.10, 0.09, 1.80), 0.02, facade, 2)
	_bx(sink, Vector3(0.0, 1.520, 0.900), Vector3(2.50, 0.04, 0.16), 0.022, _c("cream_trim"), 2)
	_bx(sink, Vector3(0.0, 1.520, -0.900), Vector3(2.50, 0.04, 0.16), 0.022, _c("cream_trim"), 2)
	_bx(sink, Vector3(-1.155, 1.520, 0.0), Vector3(0.16, 0.04, 1.86), 0.022, _c("cream_trim"), 2)
	_bx(sink, Vector3(1.155, 1.520, 0.0), Vector3(0.16, 0.04, 1.86), 0.022, _c("cream_trim"), 2)
	# A 1.6 envelope leaves only ~0.16 of headroom above the deck, so the low shops get compact
	# un-potted shrubs sitting straight on the deck instead of the tall potted ones the row units
	# can afford. Caps at 1.584, inside the envelope. Row pulled in to 0.74 so no shrub pierces the
	# front coping ring (which now starts at z = 0.82).
	for sp in [[-0.90, 0.082, 0.66], [-0.48, 0.078, 0.74], [0.02, 0.082, 0.70],
			[0.52, 0.078, 0.74], [0.92, 0.082, 0.64]]:
		sink.sphere(Kit.at(Vector3(sp[0], 1.44 + sp[1], sp[2])), Vector3(sp[1], sp[1] * 0.92, sp[1]),
			_c("leaf_green"), 5, 8)
	var hvac: Vector3 = Vector3(0.74, 1.460, -0.30)
	_bx(sink, hvac, Vector3(0.52, 0.16, 0.40), 0.028, _c("8f9aa3"), 2)
	_bx(sink, hvac + Vector3(0.0, 0.095, 0.0), Vector3(0.56, 0.035, 0.44), 0.016, _c("5d6873"), 2)
	for i in range(2):
		_bx(sink, hvac + Vector3(0.0, -0.030 + 0.058 * float(i), 0.212), Vector3(0.38, 0.030, 0.026),
			0.008, _c("5d6873"), 2)
	sink.cylinder(Kit.at(Vector3(-0.88, 1.400, -0.34)), 0.100, 0.100, 0.26, _c("5d6873"), 12)
	sink.cylinder(Kit.at(Vector3(-0.88, 1.5525, -0.34)), 0.148, 0.132, 0.05, _c("5d6873"), 12)
	for xs in [-1.0, 1.0]:
		kit.window_grid(sink, _f(), Vector3(xs * 1.235, 0.86, -0.60), 1, 2, Vector3(0.0, 0.0, 1.22),
			Vector3(0.09, 0.60, 0.46), trim, _c("6ba3d0"), true, Color(0, 0, 0, 0), "x")

func _a_P31(sink, model: Node3D, size: Vector3) -> void:
	_low_shop(sink, model, size, _c("9ed8b6"), _c("f4f1e6"), _c("4f9e7a"),
		_c("6fc09a"), _c("f4e6cd"), "FLOWERS")
	for i in range(3):
		sink.sphere(Kit.at(Vector3(-1.02 + 0.30 * float(i), 1.06, 0.985)), Vector3.ONE * 0.095, _c("flower_yellow"), 5, 8)
		sink.sphere(Kit.at(Vector3(-1.02 + 0.30 * float(i), 0.82, 0.985)), Vector3.ONE * 0.085, _c("blossom"), 5, 8)

func _a_P32(sink, model: Node3D, size: Vector3) -> void:
	_low_shop(sink, model, size, _c("f0d2c0"), _c("f4e6cd"), _c("46789f"),
		_c("6ba3d0"), _c("f4e6cd"), "BOOKS")
	var cols: Array = [_c("e2593f"), _c("46789f"), _c("f6c447"), _c("4f9e7a")]
	for i in range(4):
		_bx(sink, Vector3(-1.05 + 0.095 * float(i), 0.92, 0.985), Vector3(0.07, 0.22, 0.055), 0.012, cols[i], 2)

func _a_P33(sink, model: Node3D, size: Vector3) -> void:
	_low_shop(sink, model, size, _c("e7c9a4"), _c("f4e6cd"), _c("d9603f"),
		_c("f0a050"), _c("f4f1e6"), "CORNER")
	_bx(sink, Vector3(0.86, 0.98, 0.980), Vector3(0.34, 0.30, 0.05), 0.02, _c("46789f"), 2)
	_bx(sink, Vector3(0.86, 0.98, 1.000), Vector3(0.24, 0.20, 0.02), 0.01, _c("fdf6e6"), 2)
	_bx(sink, Vector3(0.86, 0.56, 0.980), Vector3(0.34, 0.24, 0.05), 0.02, _c("f6c447"), 2)

func _a_P34(sink, model: Node3D, size: Vector3) -> void:
	_low_shop(sink, model, size, _c("cbb9d6"), _c("f4f1e6"), _c("6a55ad"),
		_c("8d7ccd"), _c("f4e6cd"), "ARCADE")
	var cols: Array = [_c("47c9ee"), _c("ef7f6c"), _c("f6c447")]
	for i in range(3):
		sink.sphere(Kit.at(Vector3(-1.02 + 0.24 * float(i), 1.02, 0.985)), Vector3.ONE * 0.085, cols[i], 5, 8)

# =================================================================== landmark

## P35 大黄鸭与程序底座.
## R11 is look-only context: none of its benches, planters or paving become part of this unit,
## and the pedestal is procedural. Exactly one 60-point landmark.
## Split in two because the duck is a Lux3D part: R11 is look-only context and explicitly forbids
## generating the plaza as one piece, so the pedestal stays procedural and the duck rides on top.
## The pedestal's top plate (centre 1.56, height 0.16) tops out at exactly 1.64, which is the
## duck's `bottom` in LUX3D_PARTS; 1.64 + 1.56 = 3.20, the CSV envelope height.
func _a_P35_base(sink, model: Node3D, size: Vector3) -> void:
	_bx(sink, Vector3(0, 0.11, 0), Vector3(3.90, 0.22, 3.00), 0.05, _c("stone_mid"), 3)
	_bx(sink, Vector3(0, 0.25, 0), Vector3(3.60, 0.06, 2.72), 0.03, _c("paving"), 2)
	sink.cylinder(Kit.at(Vector3(0, 0.34, 0)), 1.28, 1.28, 0.06, _c("stone_light"), 24)
	_bx(sink, Vector3(0, 0.93, 0), Vector3(2.16, 1.10, 1.86), 0.05, _c("stone_light"), 3)
	_bx(sink, Vector3(0, 0.62, 0), Vector3(2.21, 0.05, 1.91), 0.02, _c("stone_deep"), 2)
	_bx(sink, Vector3(0, 1.08, 0), Vector3(2.21, 0.05, 1.91), 0.02, _c("stone_deep"), 2)
	_bx(sink, Vector3(0, 1.56, 0), Vector3(2.30, 0.16, 2.00), 0.04, _c("stone_deep"), 2)
	kit.icon_plate(sink, _f(), Vector3(0.0, 0.80, 0.945), 0.34, _c("stone_light"), _c("stone_shadow"), "heart")

func _a_P35_duck(sink, model: Node3D, size: Vector3) -> void:
	sink.cylinder(Kit.at(Vector3(0, 1.78, 0)), 0.20, 0.25, 0.34, _c("duck_yellow"), 12)
	sink.sphere(Kit.at(Vector3(0, 2.18, -0.02)), Vector3(0.88, 0.66, 0.84), _c("duck_yellow"), 12, 20)
	sink.sphere(Kit.at(Vector3(0.80, 2.03, -0.12)), Vector3(0.22, 0.42, 0.46), _c("duck_deep"), 8, 12)
	sink.sphere(Kit.at(Vector3(-0.80, 2.03, -0.12)), Vector3(0.22, 0.42, 0.46), _c("duck_deep"), 8, 12)
	sink.sphere(Kit.at(Vector3(0, 2.75, 0.02)), Vector3(0.47, 0.45, 0.45), _c("duck_yellow"), 12, 20)
	_bx(sink, Vector3(0.0, 2.73, 0.50), Vector3(0.36, 0.20, 0.30), 0.07, _c("beak_orange"), 3)
	_bx(sink, Vector3(0.0, 2.73, 0.66), Vector3(0.24, 0.13, 0.12), 0.05, _c("d9770f"), 2)
	for xs in [-1.0, 1.0]:
		sink.sphere(Kit.at(Vector3(xs * 0.235, 2.89, 0.345)), Vector3.ONE * 0.085, _c("1c1c22"), 6, 10)
		sink.sphere(Kit.at(Vector3(xs * 0.245, 2.915, 0.392)), Vector3.ONE * 0.028, _c("fdf6e6"), 4, 8)
	_bx(sink, Vector3(0.0, 2.32, -0.74), Vector3(0.34, 0.22, 0.44), 0.06, _c("duck_deep"), 3, BODY)
	_rb(sink, Vector3(0.0, 2.30, -0.72), Vector3(0.34, 0.24, 0.46), 0.06, _c("duck_deep"), 3, 0.0, Vector3(-28.0, 0.0, 0.0))

## Whole procedural P35: used only when the Lux3D duck is switched off.
func _a_P35(sink, model: Node3D, size: Vector3) -> void:
	_a_P35_base(sink, model, size)
	_a_P35_duck(sink, model, size)

## P36 甜甜圈店与屋顶招牌整件 - shell (R01) + roof donut (R02), one 60-point unit.
func _a_P36(sink, model: Node3D, size: Vector3) -> void:
	_shophouse(sink, model, size, _c("brick_salmon"), _c("pink_deep"), _c("pink_mid"),
		_c("pink_light"), "DONUTS")
	# BUG FIX: the third instance of the `Transform3D.rotated()` trap. The old line rotated the
	# ORIGIN too, so the donut landed at (0, 0.06, 2.47): floating beside the building at knee
	# height, 0.73 of it below y = 0. That single line is the whole of P36's "+0.456 high /
	# +1.110 deep" - the shell itself was never the problem. Dropped 0.05 as well so the ring
	# (0.52 + 0.21) tops out at 3.15 instead of exactly touching the 3.20 envelope.
	var donut: Transform3D = Kit.child(_f(), Vector3(0.0, 2.42, -0.06), 0.0, Vector3(90.0, 0.0, 0.0))
	sink.torus(donut, 0.52, 0.21, _c("f0a44f"), 30, 12)
	for i in range(5):
		var ang: float = -0.9 + 0.45 * float(i)
		sink.sphere(Kit.at(Vector3(cos(ang) * 0.52, 2.42 + sin(ang) * 0.52, -0.20)),
			Vector3(0.105, 0.075, 0.075), _c("ee8aa6"), 5, 8)
	for i in range(14):
		var a2: float = TAU * float(i) / 14.0
		var cols: Array = [_c("47c9ee"), _c("f6c447"), _c("4f9e7a"), _c("fdf6e6")]
		_rb(sink, Vector3(cos(a2) * 0.52, 2.42 + sin(a2) * 0.52, -0.155),
			Vector3(0.13, 0.035, 0.035), 0.014, cols[i % 4], 1, float(i) * 27.0)
	for xs in [-1.0, 1.0]:
		_bx(sink, Vector3(xs * 0.58, 2.16, -0.06), Vector3(0.10, 0.44, 0.10), 0.03, _c("stone_shadow"), 2)
	_bx(sink, Vector3(0.0, 2.22, -0.42), Vector3(1.24, 0.10, 0.10), 0.03, _c("stone_shadow"), 2)

## P37 奶茶店与屋顶杯整件 - shell (R05) + roof cup (R06), one 60-point unit.
func _a_P37(sink, model: Node3D, size: Vector3) -> void:
	_shophouse(sink, model, size, _c("b3a4e2"), _c("6a55ad"), _c("8d7ccd"),
		_c("b3a4e2"), "BOBA & JOY")
	sink.cylinder(Kit.at(Vector3(0.0, 2.72, -0.10)), 0.30, 0.44, 0.62, _c("e4cfae"), 18)
	sink.cylinder(Kit.at(Vector3(0.0, 2.52, -0.10)), 0.315, 0.335, 0.14, _c("8d7ccd"), 18)
	sink.cylinder(Kit.at(Vector3(0.0, 2.40, -0.10)), 0.27, 0.30, 0.06, _c("6a55ad"), 16)
	for i in range(9):
		var ang: float = TAU * float(i) / 9.0
		sink.sphere(Kit.at(Vector3(cos(ang) * 0.19, 2.435, -0.10 + sin(ang) * 0.19)),
			Vector3.ONE * 0.075, _c("tapioca"), 5, 8)
	# The 22-degree straw is the tallest thing on the unit: its rotated half-length is
	# 0.17 * cos22 + 0.062 * sin22 = 0.181, so at y = 3.05 it topped out at 3.231 against a 3.200
	# envelope. Lid and straw both drop 0.035, which puts the highest vertex at 3.181.
	sink.sphere(Kit.at(Vector3(0.0, 3.020, -0.10)), Vector3(0.45, 0.13, 0.45), _c("f4f1e6"), 8, 18)
	sink.cylinder(Kit.child(_f(), Vector3(0.16, 3.00, -0.10), 0.0, Vector3(0.0, 0.0, 22.0)),
		0.062, 0.062, 0.34, _c("ee8aa6"), 10)
	_bx(sink, Vector3(-0.62, 2.30, -0.10), Vector3(0.56, 0.34, 0.50), 0.05, _c("e4cfae"), 3)

## Shared two-storey toy shophouse shell for the two composite landmarks.
## Envelope is 4.00 x 3.20 x 3.10, so HALF-depth is 1.55. The front elevation was authored out at
## 1.478-1.568 and the awning reached 1.595, so the shell alone measured 3.189 deep (P37). The whole
## front face moves back ~0.08 and the awning to 1.32, which puts the deepest vertex at ~1.53.
func _shophouse(sink, model: Node3D, size: Vector3, facade: Color, band: Color,
		awning_a: Color, awning_b: Color, sign: String) -> void:
	_bx(sink, Vector3(0, 0.09, 0), Vector3(3.96, 0.18, 3.06), 0.04, _c("stone_deep"), 3)
	_bx(sink, Vector3(0, 0.97, 0), Vector3(3.80, 1.76, 2.90), 0.05, facade, 3)
	_bx(sink, Vector3(0.0, 0.42, 1.420), Vector3(3.72, 0.52, 0.10), 0.03, _c("stone_shadow"), 2)
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			_bx(sink, Vector3(xs * 1.83, 1.00, zs * 1.340), Vector3(0.26, 1.76, 0.26), 0.05, _c("cream_trim"), 2)
			for i in range(3):
				_bx(sink, Vector3(xs * 1.83, 0.40 + 0.52 * float(i), zs * 1.340),
					Vector3(0.30, 0.12, 0.30), 0.03, _c("f4e6cd"), 2)
	kit.storefront(sink, _f(), Vector3(0.0, 0.84, 1.420), 2.30, 0.90, 0.10, _c("wood_mid"), _c("ffd6a0"), 3)
	_bx(sink, Vector3(0.0, 0.86, 1.470), Vector3(0.56, 0.88, 0.06), 0.02, _c("wood_mid"), 2)
	_bx(sink, Vector3(0.0, 0.86, 1.500), Vector3(0.44, 0.76, 0.04), 0.02, _c("ffd6a0"), 2, GLOW)
	_bx(sink, Vector3(0.0, 0.86, 1.510), Vector3(0.05, 0.76, 0.03), 0.01, _c("wood_deep"), 2)
	kit.awning(sink, _f(), Vector3(0.0, 1.36, 1.320), 3.30, 0.50, 0.07, 14.0, awning_a, awning_b, 10)
	_bx(sink, Vector3(0.0, 1.62, 1.440), Vector3(3.70, 0.34, 0.10), 0.04, band, 2)
	_bx(sink, Vector3(0.0, 1.62, 1.470), Vector3(3.02, 0.30, 0.05), 0.03, _c("fdf6e6"), 2)
	kit.sign_text(model, sign, Vector3(0.0, 1.50, 1.520), 0.0, 46, 0.0060, band, 6)
	kit.window_grid(sink, _f(), Vector3(-1.00, 1.94, 1.400), 3, 1, Vector3(1.00, 0.0, 0.0),
		Vector3(0.62, 0.52, 0.10), _c("cream_trim"), _c("46789f"), true, _c("f4e6cd"))
	for xs in [-1.0, 1.0]:
		kit.window_grid(sink, _f(), Vector3(xs * 1.912, 1.94, -0.62), 1, 2, Vector3(0.0, 0.0, 1.24),
			Vector3(0.10, 0.52, 0.56), _c("cream_trim"), _c("46789f"), true, _c("f4e6cd"), "x")
	_bx(sink, Vector3(0, 1.88, 0), Vector3(3.96, 0.18, 3.06), 0.04, _c("cream_trim"), 2)
	_bx(sink, Vector3(0, 1.99, 0), Vector3(3.70, 0.30, 2.80), 0.04, _c("stone_light"), 2)
	_bx(sink, Vector3(0, 2.13, 0), Vector3(3.62, 0.12, 2.72), 0.02, _c("5d6873"), 2)
	_bx(sink, Vector3(1.30, 2.55, -0.90), Vector3(0.54, 0.44, 0.46), 0.04, _c("8f9aa3"), 2)
