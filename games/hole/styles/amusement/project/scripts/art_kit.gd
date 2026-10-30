extends RefCounted
## Shared palette, materials and compound builders for the Toy Downtown Waterfront pass.
##
## Style rules taken from the frozen brief (references/00_concept/CONCEPT_Toy_Downtown_Waterfront.png):
## rounded toy proportions, clear colour blocks, restrained matte surfaces, no blown-out whites,
## no high-frequency texture, no depth-of-field that hides small props.
##
## Palette tokens are the single source of truth: procedural parts and any future Lux3D
## import both read the same keys, so both must look identical under the same lights.

const Sink = preload("res://scripts/art_sink.gd")
const OBJECT_SHADER = preload("res://shaders/object.gdshader")

const PALETTE := {
	# --- neutral stone / pavement
	"stone_light": Color("efe4cb"),
	"stone_mid": Color("e2d4b4"),
	"stone_deep": Color("cbb894"),
	"stone_shadow": Color("a8946f"),
	"paving": Color("d6cbb0"),
	"sidewalk": Color("9a9c94"),
	"asphalt": Color("414b55"),
	"kerb": Color("c3baa4"),
	# --- wood
	"wood_light": Color("dcae6f"),
	"wood_mid": Color("c2884a"),
	"wood_deep": Color("9a6533"),
	"wood_shadow": Color("7a4e26"),
	# --- donut shop
	"pink_light": Color("f6b7c7"),
	"pink_mid": Color("ee8aa6"),
	"pink_deep": Color("dd5f83"),
	"brick_salmon": Color("e8907f"),
	"brick_light": Color("f0a795"),
	"cream_trim": Color("f4e6cd"),
	# --- boba shop
	"boba_light": Color("b3a4e2"),
	"boba_mid": Color("8d7ccd"),
	"boba_deep": Color("6a55ad"),
	"milk_tea": Color("e4cfae"),
	"tapioca": Color("4a382c"),
	# --- greenery / flowers
	"mint_light": Color("9ed8b6"),
	"mint_mid": Color("6fc09a"),
	"mint_deep": Color("48987a"),
	"leaf_green": Color("7fb45f"),
	"leaf_deep": Color("5c8c42"),
	"blossom": Color("f6d1e0"),
	"flower_yellow": Color("f6c447"),
	# --- books / flowers shops
	"blue_light": Color("9dc9e8"),
	"blue_mid": Color("6ba3d0"),
	"blue_deep": Color("46789f"),
	"teal_mid": Color("4f9e9a"),
	# --- produce / market
	"tomato": Color("e2593f"),
	"carrot": Color("f08a2e"),
	"citrus": Color("f4a72c"),
	"grape": Color("8a5fb0"),
	"apple_green": Color("a8cc4e"),
	# --- props
	"duck_yellow": Color("ffd94f"),
	"duck_deep": Color("f0b81f"),
	"beak_orange": Color("f28a1c"),
	"cone_orange": Color("f2762e"),
	"cone_white": Color("f6f1e6"),
	"bin_blue": Color("5b90c4"),
	"bin_green": Color("5aa06a"),
	"bin_dark": Color("3d4a55"),
	"metal": Color("8f9aa3"),
	"metal_dark": Color("5d6873"),
	"tyre": Color("3a3f45"),
	"car_coral": Color("ef7f6c"),
	"car_yellow": Color("f4c53a"),
	"car_blue": Color("5f8fd0"),
	"car_mint": Color("83ccb4"),
	"glass_warm": Color("ffd6a0"),
	"glass_cool": Color("cfe6f2"),
	"glow_warm": Color("ffcb7d"),
	# --- water & sky backdrop
	"water_shallow": Color("4fb4c6"),
	"water_deep": Color("2b7f9c"),
	"bg_facade_a": Color("e7c9a4"),
	"bg_facade_b": Color("cbb9d6"),
	"bg_facade_c": Color("f0d2c0"),
	"bg_roof": Color("a4626a"),
	# --- black hole presentation
	"hole_rim": Color("8fe6ff"),
	"hole_rim_rival": Color("ffb6d5"),
	"hole_lip": Color("15202b"),
	"hole_throat": Color("070b10"),
}

# Colour used when a variant is not given an explicit one, so a missing recipe
# still reads as a deliberate object instead of a default white.
const FALLBACK_COLOR := Color("9fb0bd")

var _materials: Dictionary = {}
var _shared: Dictionary = {}
var _unit_mat: ShaderMaterial = null

func palette(key: String, fallback: Color = FALLBACK_COLOR) -> Color:
	return PALETTE.get(key, fallback)

func color_of(token) -> Color:
	if token is Color:
		return token
	var text: String = str(token)
	if PALETTE.has(text):
		return PALETTE[text]
	if text.begins_with("#"):
		return Color(text)
	if text.length() == 6 or text.length() == 8:
		return Color(text)
	return FALLBACK_COLOR

## The single material every swallowable unit in the game uses.
##
## Draw-call discipline: because the palette and the self-lit weight both ride in vertex colours
## (RGB = colour, A = glow), one material instance can serve all 215 units at once. Sharing it
## across every unit also means the per-frame hole-clipping update writes four shader parameters
## once, instead of walking 215 views and their material lists.
func unit_material() -> ShaderMaterial:
	if _unit_mat != null:
		return _unit_mat
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = OBJECT_SHADER
	mat.set_shader_parameter("body_color", Color.WHITE)
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("enable_hole_clip", true)
	mat.set_shader_parameter("surface_roughness", 0.86)
	mat.set_shader_parameter("matte_mix", 0.78)
	mat.set_shader_parameter("emissive_strength", 0.20)
	mat.set_shader_parameter("glow_scale", 0.72)
	mat.resource_name = "UnitMaterial"
	_unit_mat = mat
	return mat

## Kept as an alias: the merged single-surface pipeline no longer needs a second material, but
## older call sites and the graybox fallback still ask for one.
func glow_material() -> ShaderMaterial:
	return unit_material()

## Shared, non-animated scenery material. Keeps the background cheap.
func shared_material(color: Color) -> ShaderMaterial:
	var key: String = color.to_html()
	if _shared.has(key):
		return _shared[key]
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = OBJECT_SHADER
	mat.set_shader_parameter("body_color", color)
	mat.set_shader_parameter("use_vertex_color", false)
	mat.set_shader_parameter("enable_hole_clip", false)
	mat.set_shader_parameter("surface_roughness", 0.94)
	_shared[key] = mat
	return mat

func shared_materials() -> Dictionary:
	return _shared

# ------------------------------------------------------------------ transforms

static func at(origin: Vector3, yaw_degrees: float = 0.0, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var basis: Basis = Basis.from_euler(Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)).scaled(scale)
	return Transform3D(basis, origin)

static func child(parent: Transform3D, offset: Vector3, yaw_degrees: float = 0.0,
		tilt_degrees: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis: Basis = Basis.from_euler(Vector3(
		deg_to_rad(tilt_degrees.x), deg_to_rad(yaw_degrees + tilt_degrees.y), deg_to_rad(tilt_degrees.z)))
	var out: Transform3D = parent
	out.basis = parent.basis * basis
	out.origin = parent * offset
	return out

# ------------------------------------------------------------------- compounds

## Upright post standing on the local ground plane (y = 0 at its base).
func post(sink, parent: Transform3D, x: float, z: float, height: float, radius: float,
		color: Color, segs: int = 8, group: String = Sink.GROUP_BODY) -> void:
	var xf: Transform3D = at(parent.origin + parent.basis * Vector3(x, height * 0.5, z))
	xf.basis = parent.basis
	sink.cylinder(xf, radius, radius, height, color, segs, true, true, group)

## Toy wheel lying in the YZ plane (rolls about +X).
func wheel(sink, parent: Transform3D, center: Vector3, radius: float, width: float,
		tyre: Color, hub: Color, segs: int = 12) -> void:
	var xf: Transform3D = parent
	xf.origin = parent * center
	xf.basis = parent.basis * Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5))
	sink.cylinder(xf, radius, radius, width, tyre, segs, true, true, Sink.GROUP_BODY)
	var hub_xf: Transform3D = parent
	hub_xf.origin = parent * (center + Vector3(width * 0.5 + 0.004, 0.0, 0.0))
	hub_xf.basis = parent.basis * Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5))
	sink.cylinder(hub_xf, radius * 0.45, radius * 0.45, 0.012, hub, segs, true, true, Sink.GROUP_BODY)

## Slanted striped awning with a scalloped leading edge and a side valance.
func awning(sink, parent: Transform3D, center: Vector3, width: float, depth: float,
		thickness: float, tilt_degrees: float, color_a: Color, color_b: Color,
		bands: int = 6, scallops: bool = true, glow: bool = false) -> void:
	var group: String = Sink.GROUP_GLOW if glow else Sink.GROUP_BODY
	var xf: Transform3D = child(parent, center, 0.0, Vector3(tilt_degrees, 0.0, 0.0))
	sink.banded_slab(xf, Vector3.ZERO, Vector3(width, thickness, depth),
		thickness * 0.46, bands, 0, color_a, color_b, 2, group)
	# Valance hangs from the outer (front) edge: +Z in the awning's own frame.
	if scallops:
		var count: int = maxi(2, bands)
		var step: float = width / float(count)
		for i in range(count):
			var x: float = -width * 0.5 + step * (float(i) + 0.5)
			var scallop: Transform3D = child(xf, Vector3(x, -thickness * 1.35, depth * 0.5), 0.0,
				Vector3(0.0, 0.0, 90.0))
			sink.cylinder(scallop, thickness * 0.62, thickness * 0.62, step * 0.98,
				color_a if i % 2 == 0 else color_b, 7, false, false, group)

## Recessed shop window / door panel: frame, jambs and a warm interior card.
func storefront(sink, parent: Transform3D, center: Vector3, width: float, height: float,
		depth: float, frame: Color, glass: Color, mullions: int = 2, glow: bool = true) -> void:
	var group: String = Sink.GROUP_GLOW if glow else Sink.GROUP_BODY
	sink.slab(parent, center, Vector3(width, height, depth * 0.55), depth * 0.22, frame, 2, Sink.GROUP_BODY)
	sink.slab(parent, center + Vector3(0.0, 0.0, depth * 0.30),
		Vector3(width * 0.84, height * 0.80, depth * 0.20), depth * 0.12, glass, 2, group)
	if mullions > 1:
		for i in range(1, mullions):
			var x: float = -width * 0.42 + width * 0.84 * float(i) / float(mullions)
			sink.slab(parent, center + Vector3(x, 0.0, depth * 0.42),
				Vector3(width * 0.84 / float(mullions) * 0.10 + 0.02, height * 0.82, depth * 0.16),
				0.012, frame, 2, Sink.GROUP_BODY)

## Grid of windows, optionally with independent per-row shutters/awnings.
##
## `normal` is the wall's outward axis: "z" for a facade facing +Z (the default), "x" for a side
## wall facing +X. The glass card and the shutter are both pushed OUT along that axis, and their
## cross-sections swap with it.
##
## Before this parameter existed the "+Z" offset was applied to side walls as well, so on a side
## grid the glass card drifted along the wall and the shutter was thrown off the end of the
## building - which is what left loose slivers floating near the P27 / P31 roof corners. Side walls
## also drop the shutter: its outward reach (0.62 * normal thickness) does not fit in the sliver of
## envelope left beside a facade that already fills its width, so a side window is frame + glass.
func window_grid(sink, parent: Transform3D, first: Vector3, columns: int, rows: int,
		step: Vector3, size: Vector3, frame: Color, glass: Color, glow: bool = true,
		shutter: Color = Color(0, 0, 0, 0), normal: String = "z") -> void:
	var group: String = Sink.GROUP_GLOW if glow else Sink.GROUP_BODY
	var along_z: bool = normal == "z"
	var outward: Vector3 = Vector3(0.0, 0.0, size.z) if along_z else Vector3(size.x, 0.0, 0.0)
	var glass_size: Vector3 = Vector3(size.x * 0.74, size.y * 0.72, size.z * 0.34) if along_z \
		else Vector3(size.x * 0.34, size.y * 0.72, size.z * 0.74)
	var shutter_size: Vector3 = Vector3(size.x * 1.12, size.y * 0.20, size.z * 0.70) if along_z \
		else Vector3(size.x * 0.70, size.y * 0.20, size.z * 1.12)
	for r in range(rows):
		for c in range(columns):
			var center: Vector3 = first + Vector3(step.x * float(c), step.y * float(r), step.z * float(r))
			sink.slab(parent, center, size, size.x * 0.16, frame, 2, Sink.GROUP_BODY)
			sink.slab(parent, center + outward * 0.42, glass_size, size.x * 0.10, glass, 2, group)
			if shutter.a > 0.001 and along_z:
				sink.slab(parent, center + Vector3(0.0, size.y * 0.62, size.z * 0.62),
					shutter_size, size.x * 0.10, shutter, 2, Sink.GROUP_BODY)

## Independent signage: real text, never baked gibberish.
func sign_text(parent: Node3D, text: String, position: Vector3, yaw_degrees: float = 0.0,
		font_size: int = 44, pixel_size: float = 0.0055, color: Color = Color("fdf6e6"),
		outline: int = 6, outline_color: Color = Color(0.16, 0.10, 0.14, 0.85)) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_modulate = outline_color
	label.outline_size = outline
	label.shaded = false
	label.double_sided = true
	label.no_depth_test = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = position
	label.rotation_degrees.y = yaw_degrees
	label.set_meta("role", "INDEPENDENT_SIGNAGE")
	parent.add_child(label)
	return label

## Small flat icon plate (arrow, heart, star) assembled from real geometry.
## Text always ships as an independent Label3D; these plates only carry punctuation marks.
func icon_plate(sink, parent: Transform3D, center: Vector3, size: float, plate: Color,
		glyph: Color, kind: String = "star", yaw_degrees: float = 0.0) -> void:
	var base: Transform3D = child(parent, center, yaw_degrees)
	sink.rbox(base, Vector3(size, size, size * 0.22), size * 0.22, plate, 2)
	match kind:
		"star":
			for i in range(4):
				var spoke: Transform3D = child(base, Vector3(0.0, 0.0, size * 0.10), float(i) * 45.0)
				sink.rbox(spoke, Vector3(size * 0.68, size * 0.13, size * 0.10), size * 0.05, glyph, 1)
		"heart":
			sink.sphere(child(base, Vector3(-size * 0.15, size * 0.10, size * 0.11)),
				Vector3.ONE * size * 0.27, glyph, 5, 8)
			sink.sphere(child(base, Vector3(size * 0.15, size * 0.10, size * 0.11)),
				Vector3.ONE * size * 0.27, glyph, 5, 8)
			sink.rbox(child(base, Vector3(0.0, -size * 0.13, size * 0.11), 45.0),
				Vector3(size * 0.46, size * 0.46, size * 0.12), size * 0.05, glyph, 1)
		_:
			sink.rbox(child(base, Vector3(0.0, 0.0, size * 0.10)),
				Vector3(size * 0.62, size * 0.14, size * 0.12), size * 0.05, glyph, 1)
