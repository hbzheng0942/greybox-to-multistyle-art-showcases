extends RefCounted
## Two content-changing procedural theme sets on the frozen v0.3 gameplay slots.
## Every model is authored from its envelope base; the caller supplies the unchanged
## centre transform. These are production candidates, not user-approved final art.

const Sink = preload("res://scripts/art_sink.gd")
const Kit = preload("res://scripts/art_kit.gd")
const ModelLoader = preload("res://scripts/theme_model_loader.gd")

var kit
var theme_id: String = "amusement"
var last_triangles: int = 0
var last_slots: int = 1
var preview_theme: String = ""
var preview_slot: String = ""
var preview_path: String = ""
var adopted_bindings: Dictionary = {}
var use_models: bool = true

func _init() -> void:
	kit = Kit.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model-theme="):
			preview_theme = arg.trim_prefix("--model-theme=")
		elif arg.begins_with("--model-slot="):
			preview_slot = arg.trim_prefix("--model-slot=")
		elif arg.begins_with("--model-path="):
			preview_path = arg.trim_prefix("--model-path=")
	var binding_file := "res://data/theme_model_bindings.json"
	if FileAccess.file_exists(binding_file):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(binding_file))
		if parsed is Dictionary and parsed.get("schema", "") == "theme_model_bindings_v1":
			adopted_bindings = parsed.get("themes", {})

func set_use_models(enabled: bool, _hold: bool = false) -> void:
	use_models = enabled

func _complete_landmark_footprint(imported: Node3D, size: Vector3, archetype: String) -> void:
	if archetype != "landmark":
		return
	var fill: Vector2 = imported.get_meta("source_footprint_fill_xz", Vector2.ONE)
	if minf(fill.x, fill.y) >= 0.80:
		return
	# A visible, theme-authored display deck remains part of this ONE gameplay
	# unit. It restores support/footprint without stretching a circular landmark.
	var sink = Sink.new()
	var base_y: float = -size.y * .5
	var main_color: Color = Color("365b7a") if theme_id == "amusement" else Color("9bcfbd")
	var trim_color: Color = Color("f4d68f") if theme_id == "amusement" else Color("f6e9d4")
	var deck_w: float = size.x * .91
	var deck_d: float = size.z * .88
	sink.slab(Transform3D.IDENTITY, Vector3(0, base_y + .075, 0),
		Vector3(deck_w, .15, deck_d), .05, main_color, 2)
	for side in [-1.0, 1.0]:
		sink.slab(Transform3D.IDENTITY, Vector3(side * (deck_w * .5 - .05), base_y + .158, 0),
			Vector3(.04, .016, deck_d - .12), .006, trim_color, 2)
		sink.slab(Transform3D.IDENTITY, Vector3(0, base_y + .158, side * (deck_d * .5 - .05)),
			Vector3(deck_w - .12, .016, .04), .006, trim_color, 2)
	var mesh: ArrayMesh = sink.commit("body")
	if mesh == null:
		return
	var deck := MeshInstance3D.new()
	deck.name = "ThemeDisplayDeck"
	deck.mesh = mesh
	deck.material_override = kit.unit_material()
	imported.add_child(deck)
	var mats: Array = imported.get_meta("cutaway_materials", [])
	mats.append(deck.material_override)
	imported.set_meta("cutaway_materials", mats)
	imported.set_meta("assembled_landmark_deck", true)
	imported.set_meta("triangles", int(imported.get_meta("triangles", 0)) + sink.triangle_count())

func _color(index: int) -> Color:
	var amusement: Array = [Color("efa948"), Color("e8806b"), Color("66b6b4"), Color("4d688b"), Color("f4dfac"), Color("774f6d")]
	var snack: Array = [Color("e99374"), Color("f2d077"), Color("8fbfa2"), Color("785c91"), Color("f6e6c1"), Color("ad7958")]
	var set: Array = amusement if theme_id == "amusement" else snack
	return set[posmod(index, set.size())]

func _box(sink, at: Vector3, size: Vector3, color: Color, radius: float = 0.03) -> void:
	sink.slab(Transform3D.IDENTITY, at, size, radius, color, 2)

func _ball(sink, at: Vector3, radius: Vector3, color: Color) -> void:
	sink.sphere(Transform3D(Basis.IDENTITY, at), radius, color, 7, 12)

func _cup(sink, at: Vector3, bottom: float, top: float, height: float, color: Color) -> void:
	sink.cylinder(Transform3D(Basis.IDENTITY, at), bottom, top, height, color, 12)

func _ring(sink, at: Vector3, major: float, minor: float, color: Color, vertical: bool = false) -> void:
	var basis: Basis = Basis(Vector3.RIGHT, PI * 0.5) if vertical else Basis.IDENTITY
	sink.torus(Transform3D(basis, at), major, minor, color, 20, 6)

func _bar(sink, a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var middle: Vector3 = (a + b) * 0.5
	var direction: Vector3 = b - a
	var basis: Basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	sink.cylinder(Transform3D(basis, middle), thickness, thickness, direction.length(), color, 8)

func build(asset_id: String, archetype: String, size: Vector3, support_height_from_base: float = 0.0) -> Node3D:
	var required_model_failed: bool = false
	if use_models and theme_id == preview_theme and asset_id == preview_slot and not preview_path.is_empty():
		var imported: Node3D = ModelLoader.build(preview_path, size, theme_id, asset_id, archetype, support_height_from_base)
		if imported != null:
			_complete_landmark_footprint(imported, size, archetype)
			last_triangles = int(imported.get_meta("triangles", 0))
			last_slots = int(imported.get_meta("material_slots", 0))
			return imported
		required_model_failed = true
	elif use_models and adopted_bindings.has(theme_id) and (adopted_bindings[theme_id] as Dictionary).has(asset_id):
		var binding: Dictionary = adopted_bindings[theme_id][asset_id]
		var source_path: String = str(binding.get("path", ""))
		var local_path: String = ProjectSettings.globalize_path(source_path) if source_path.begins_with("res://") else source_path
		var imported: Node3D = ModelLoader.build(local_path, size, theme_id, asset_id, archetype, support_height_from_base)
		if imported != null:
			_complete_landmark_footprint(imported, size, archetype)
			imported.set_meta("status", "LUX3D_RAW_ADOPTED")
			imported.set_meta("source", "lux3d_raw_adopted")
			imported.set_meta("asset_revision", str(binding.get("assetId", "")))
			last_triangles = int(imported.get_meta("triangles", 0))
			last_slots = int(imported.get_meta("material_slots", 0))
			return imported
		required_model_failed = true
	var root: Node3D = Node3D.new()
	root.name = "Visual"
	var model: Node3D = Node3D.new()
	model.name = "Model"
	model.position = Vector3(0, -size.y * 0.5, 0)
	root.add_child(model)
	var sink = Sink.new()
	var idn: int = int(asset_id.substr(1))
	if idn <= 4:
		_micro(sink, idn, size)
	elif idn <= 6:
		_pole(sink, idn, size)
	elif idn <= 9:
		_supported(sink, idn, size)
	elif idn <= 12:
		_bin(sink, idn, size)
	elif idn <= 14:
		_fence(sink, idn, size)
	elif idn <= 16:
		_stack(sink, idn, size)
	elif idn <= 18:
		_bench(sink, idn, size)
	elif idn <= 22:
		_vehicle(sink, idn, size)
	elif idn <= 24:
		_table(sink, idn, size)
	elif idn <= 26:
		_pallet(sink, idn, size)
	elif idn <= 30:
		_facade(sink, idn, size)
	elif idn <= 34:
		_shop(sink, idn, size)
	else:
		_landmark(sink, idn, size)
	var mesh: ArrayMesh = sink.commit("body")
	if mesh != null:
		var view: MeshInstance3D = MeshInstance3D.new()
		view.name = "ThemeSurface"
		view.mesh = mesh
		view.material_override = kit.unit_material()
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		model.add_child(view)
		root.set_meta("cutaway_materials", [view.material_override])
	root.set_meta("cutaway", 0.0)
	root.set_meta("asset_id", asset_id)
	root.set_meta("theme_id", theme_id)
	root.set_meta("triangles", sink.triangle_count())
	root.set_meta("material_slots", 1)
	root.set_meta("status", "PROCEDURAL_THEME_CANDIDATE")
	root.set_meta("source", "procedural_theme")
	if required_model_failed:
		root.set_meta("fallback", true)
		root.set_meta("status", "REQUIRED_MODEL_IMPORT_FAILED")
	last_triangles = sink.triangle_count()
	return root

func _micro(sink, idn: int, s: Vector3) -> void:
	var y: float = s.y
	if idn == 1:
		_box(sink, Vector3(0, y * .40, 0), Vector3(s.x * .83, y * .72, s.z * .75), _color(idn), .022)
		_box(sink, Vector3(0, y * .79, 0), Vector3(s.x * .75, y * .09, s.z * .69), _color(4), .008)
	elif idn == 2:
		_cup(sink, Vector3(0, y * .35, 0), s.x * .34, s.x * .40, y * .7, _color(idn))
		_ball(sink, Vector3(0, y * .75, 0), Vector3(s.x * .24, y * .17, s.z * .24), _color(4))
	elif idn == 3:
		_cup(sink, Vector3(0, y * .21, 0), s.x * .36, s.x * .39, y * .36, _color(5))
		for i in 3:
			_ball(sink, Vector3((i - 1) * s.x * .18, y * .61, 0), Vector3(s.x * .16, y * .22, s.z * .16), _color(i + 1))
	else:
		_box(sink, Vector3(0, y * .42, 0), Vector3(s.x * .80, y * .75, s.z * .78), _color(idn), .025)
		_box(sink, Vector3(0, y * .64, s.z * .315), Vector3(s.x * .52, y * .20, s.z * .025), _color(4), .005)

func _pole(sink, idn: int, s: Vector3) -> void:
	var c: Color = _color(idn)
	_cup(sink, Vector3(0, s.y * .04, 0), s.x * .29, s.x * .26, s.y * .08, _color(3))
	_bar(sink, Vector3(0, s.y * .07, 0), Vector3(0, s.y * .80, 0), s.x * .075, c)
	if theme_id == "amusement":
		_ball(sink, Vector3(0, s.y * .85, 0), Vector3(s.x * .31, s.y * .10, s.z * .31), _color(4))
	else:
		_ball(sink, Vector3(0, s.y * .83, 0), Vector3(s.x * .27, s.y * .12, s.z * .27), _color(1))
		_bar(sink, Vector3(0, s.y * .83, 0), Vector3(0, s.y * .96, 0), s.x * .045, _color(4))

func _supported(sink, idn: int, s: Vector3) -> void:
	var r: float = minf(s.x, minf(s.y, s.z)) * .41
	_ball(sink, Vector3(0, s.y * .52, 0), Vector3(r, r, r), _color(idn))
	if idn == 8:
		_ring(sink, Vector3(0, s.y * .69, 0), r * .58, r * .13, _color(4))
	elif idn == 9:
		for i in 3:
			_ball(sink, Vector3((i - 1) * r * .4, s.y * .77, 0), Vector3(r * .16, r * .12, r * .16), _color(i))

func _bin(sink, idn: int, s: Vector3) -> void:
	var c: Color = _color(idn)
	if idn == 12:
		_box(sink, Vector3(0, s.y * .62, 0), Vector3(s.x * .72, s.y * .56, s.z * .34), _color(3), .02)
		_box(sink, Vector3(0, s.y * .62, s.z * .19), Vector3(s.x * .56, s.y * .41, s.z * .035), _color(4), .006)
		for x in [-.24, .24]:
			_bar(sink, Vector3(x * s.x, s.y * .06, 0), Vector3(x * s.x, s.y * .39, 0), s.x * .035, c)
	else:
		_cup(sink, Vector3(0, s.y * .47, 0), s.x * .35, s.x * .39, s.y * .79, c)
		_cup(sink, Vector3(0, s.y * .90, 0), s.x * .42, s.x * .42, s.y * .06, _color(4))
		_box(sink, Vector3(0, s.y * .54, s.z * .36), Vector3(s.x * .40, s.y * .18, s.z * .018), _color(4), .005)

func _fence(sink, idn: int, s: Vector3) -> void:
	var c: Color = _color(idn)
	for x in [-.44, .44]:
		_bar(sink, Vector3(x * s.x, s.y * .08, 0), Vector3(x * s.x, s.y * .89, 0), s.z * .23, _color(3))
		_ball(sink, Vector3(x * s.x, s.y * .92, 0), Vector3(s.z * .24, s.z * .24, s.z * .24), c)
	for y in [.38, .62]:
		_bar(sink, Vector3(-s.x * .43, s.y * y, 0), Vector3(s.x * .43, s.y * y, 0), s.z * .14, c)

func _stack(sink, idn: int, s: Vector3) -> void:
	_box(sink, Vector3(0, s.y * .49, 0), Vector3(s.x * .89, s.y * .88, s.z * .87), _color(idn), .027)
	for x in [-.26, .26]:
		_box(sink, Vector3(s.x * x, s.y * .53, s.z * .45), Vector3(s.x * .08, s.y * .73, s.z * .018), _color(4), .005)
	if theme_id == "snack":
		_box(sink, Vector3(0, s.y * .63, s.z * .455), Vector3(s.x * .47, s.y * .27, s.z * .019), _color(4), .005)

func _bench(sink, idn: int, s: Vector3) -> void:
	for x in [-.38, .38]:
		_box(sink, Vector3(s.x * x, s.y * .24, 0), Vector3(s.x * .07, s.y * .40, s.z * .64), _color(3), .01)
	_box(sink, Vector3(0, s.y * .48, 0), Vector3(s.x * .91, s.y * .11, s.z * .74), _color(idn), .027)
	_box(sink, Vector3(0, s.y * .72, -s.z * .27), Vector3(s.x * .89, s.y * .44, s.z * .10), _color(idn + 1), .021)
	if theme_id == "amusement":
		for x in [-.25, .25]:
			_ball(sink, Vector3(s.x * x, s.y * .88, -s.z * .27), Vector3(s.z * .11, s.z * .11, s.z * .11), _color(4))

func _vehicle(sink, idn: int, s: Vector3) -> void:
	var w: float = s.x
	var h: float = s.y
	var d: float = s.z
	var c: Color = _color(idn)
	_box(sink, Vector3(0, h * .44, 0), Vector3(w * .82, h * .55, d * .77), c, .06)
	_box(sink, Vector3(-w * .18, h * .72, 0), Vector3(w * .41, h * .20, d * .70), _color(4), .026)
	for x in [-.29, .28]:
		for z in [-.35, .35]:
			_ball(sink, Vector3(w * x, h * .17, d * z), Vector3(h * .16, h * .16, d * .07), _color(3))
	if idn >= 21:
		_box(sink, Vector3(w * .13, h * .70, d * .385), Vector3(w * .34, h * .18, d * .025), _color(4), .012)
		if theme_id == "amusement":
			_ball(sink, Vector3(w * .23, h * .85, 0), Vector3(w * .12, h * .10, d * .16), _color(1))
		else:
			_box(sink, Vector3(w * .23, h * .85, 0), Vector3(w * .22, h * .08, d * .25), _color(1), .012)

func _table(sink, idn: int, s: Vector3) -> void:
	var w: float = s.x
	var h: float = s.y
	var d: float = s.z
	for x in [-.39, .39]:
		for z in [-.35, .35]:
			_box(sink, Vector3(w * x, .48, d * z), Vector3(w * .07, .90, d * .09), _color(3), .012)
	# Existing gameplay support is at 1.00 above the base; keep this visual contact.
	_box(sink, Vector3(0, 1.00, 0), Vector3(w * .88, .10, d * .88), _color(idn), .025)
	for x in [-.38, .38]:
		_bar(sink, Vector3(w * x, 1.05, -d * .32), Vector3(w * x, h * .91, -d * .32), w * .025, _color(3))
	_box(sink, Vector3(0, h * .94, 0), Vector3(w * .89, h * .08, d * .81), _color(4), .027)
	if theme_id == "amusement":
		for i in 4:
			_box(sink, Vector3(w * (-.30 + i * .20), h * .955, 0), Vector3(w * .08, h * .09, d * .79), _color(i), .01)
	else:
		_box(sink, Vector3(0, h * .86, d * .37), Vector3(w * .57, h * .13, d * .03), _color(2), .006)

func _pallet(sink, idn: int, s: Vector3) -> void:
	for x in [-.35, 0.0, .35]:
		_box(sink, Vector3(s.x * x, s.y * .47, 0), Vector3(s.x * .23, s.y * .56, s.z * .88), _color(idn + int((x + .35) * 4.0)), .008)
	for z in [-.32, .32]:
		_box(sink, Vector3(0, s.y * .14, s.z * z), Vector3(s.x * .88, s.y * .22, s.z * .12), _color(3), .007)

func _facade(sink, idn: int, s: Vector3) -> void:
	var w: float = s.x
	var h: float = s.y
	var d: float = s.z
	if theme_id == "amusement":
		# A carnival attraction facade: painted frame, large readable game panel,
		# striped roof and one crest. No apartment-window syntax.
		_box(sink, Vector3(0, h * .42, 0), Vector3(w * .86, h * .82, d * .82), _color(idn), .055)
		for x in [-.37, .37]:
			_box(sink, Vector3(w * x, h * .42, d * .43), Vector3(w * .085, h * .77, d * .04), _color(4), .018)
		_box(sink, Vector3(0, h * .46, d * .43), Vector3(w * .62, h * .46, d * .035), _color(3), .025)
		_box(sink, Vector3(0, h * .46, d * .455), Vector3(w * .48, h * .31, d * .02), _color(4), .018)
		for x in [-.19, 0.0, .19]:
			_ball(sink, Vector3(w * x, h * .50, d * .47), Vector3(w * .065, h * .055, d * .03), _color(idn + int(x * 10.0)),)
		_box(sink, Vector3(0, h * .84, 0), Vector3(w * .95, h * .09, d * .91), _color(4), .025)
		for i in 5:
			_box(sink, Vector3(w * (-.38 + float(i) * .19), h * .893, 0), Vector3(w * .09, h * .055, d * .88), _color(i + idn), .010)
		_ring(sink, Vector3(0, h * .92, d * .05), w * .12, w * .02, _color(1), true)
		return
	if theme_id == "snack":
		# A tall product shelf with repeated packs, not a residential facade.
		_box(sink, Vector3(0, h * .42, 0), Vector3(w * .86, h * .82, d * .81), _color(idn), .055)
		for x in [-.35, .35]:
			_box(sink, Vector3(w * x, h * .43, d * .43), Vector3(w * .08, h * .79, d * .04), _color(4), .015)
		for level in 3:
			var y: float = h * (.23 + float(level) * .22)
			_box(sink, Vector3(0, y, d * .44), Vector3(w * .64, h * .035, d * .045), _color(4), .010)
			for x in [-.19, 0.0, .19]:
				_box(sink, Vector3(w * x, y + h * .08, d * .45), Vector3(w * .14, h * .13, d * .045), _color(idn + level + int(x * 10.0)), .014)
		_box(sink, Vector3(0, h * .84, 0), Vector3(w * .95, h * .09, d * .90), _color(4), .026)
		for x in [-.22, 0.0, .22]:
			_ball(sink, Vector3(w * x, h * .94, 0), Vector3(w * .115, h * .06, d * .12), _color(idn + int(x * 10.0)))
		return
	var c: Color = _color(idn)
	_box(sink, Vector3(0, h * .47, -d * .05), Vector3(w * .90, h * .90, d * .80), c, .045)
	_box(sink, Vector3(0, h * .92, -d * .05), Vector3(w * .95, h * .12, d * .87), _color(4), .028)
	for level in 3:
		for x in [-.25, .25]:
			_box(sink, Vector3(w * x, h * (.19 + level * .23), d * .365), Vector3(w * .25, h * .13, d * .023), _color(3), .008)
	_box(sink, Vector3(0, h * .76, d * .39), Vector3(w * .77, h * .08, d * .13), _color(idn + 1), .018)
	if theme_id == "snack":
		for x in [-.30, 0.0, .30]:
			_ball(sink, Vector3(w * x, h * .94, 0), Vector3(w * .11, h * .045, d * .12), _color(idn + 2))
	else:
		for x in [-.30, 0.0, .30]:
			_box(sink, Vector3(w * x, h * .92, d * .18), Vector3(w * .13, h * .06, d * .15), _color(idn + 2), .014)

func _shop(sink, idn: int, s: Vector3) -> void:
	var w: float = s.x
	var h: float = s.y
	var d: float = s.z
	if theme_id == "amusement":
		_box(sink, Vector3(0, h * .36, 0), Vector3(w * .88, h * .70, d * .82), _color(idn), .060)
		_box(sink, Vector3(0, h * .36, d * .425), Vector3(w * .70, h * .44, d * .04), _color(3), .026)
		for x in [-.25, 0.0, .25]:
			_box(sink, Vector3(w * x, h * .36, d * .45), Vector3(w * .14, h * .30, d * .025), _color(idn + int(x * 10.0)), .016)
		_box(sink, Vector3(0, h * .71, d * .20), Vector3(w * .93, h * .12, d * .55), _color(4), .022)
		for i in 6:
			_box(sink, Vector3(w * (-.375 + float(i) * .15), h * .78, d * .17), Vector3(w * .07, h * .05, d * .52), _color(i + idn), .010)
		_box(sink, Vector3(0, h * .84, -d * .08), Vector3(w * .84, h * .12, d * .71), _color(idn + 1), .045)
		for x in [-.28, 0.0, .28]:
			_ball(sink, Vector3(w * x, h * .94, -d * .08), Vector3(w * .09, h * .055, d * .10), _color(idn + 2))
		return
	if theme_id == "snack":
		_box(sink, Vector3(0, h * .35, 0), Vector3(w * .89, h * .69, d * .84), _color(idn), .065)
		_box(sink, Vector3(0, h * .41, d * .445), Vector3(w * .72, h * .43, d * .035), _color(4), .023)
		for level in 2:
			_box(sink, Vector3(0, h * (.30 + float(level) * .17), d * .47), Vector3(w * .65, h * .035, d * .04), _color(3), .010)
			for x in [-.24, 0.0, .24]:
				_ball(sink, Vector3(w * x, h * (.35 + float(level) * .17), d * .49), Vector3(w * .075, h * .045, d * .02), _color(idn + level + int(x * 10.0)))
		_box(sink, Vector3(0, h * .72, d * .16), Vector3(w * .94, h * .11, d * .58), _color(4), .024)
		_box(sink, Vector3(0, h * .85, -d * .05), Vector3(w * .84, h * .10, d * .74), _color(idn + 1), .038)
		_cup(sink, Vector3(0, h * .925, -d * .05), w * .18, w * .17, h * .08, _color(idn + 2))
		for x in [-.21, .21]:
			_ball(sink, Vector3(w * x, h * .94, -d * .05), Vector3(w * .09, h * .04, d * .09), _color(4))
		return
	var c: Color = _color(idn)
	_box(sink, Vector3(0, h * .43, -d * .04), Vector3(w * .90, h * .81, d * .85), c, .060)
	_box(sink, Vector3(0, h * .88, -d * .04), Vector3(w * .95, h * .12, d * .90), _color(4), .028)
	for x in [-.26, .26]:
		_box(sink, Vector3(w * x, h * .40, d * .39), Vector3(w * .30, h * .38, d * .03), _color(3), .011)
	_box(sink, Vector3(0, h * .70, d * .43), Vector3(w * .76, h * .10, d * .08), _color(idn + 1), .015)
	if theme_id == "amusement":
		for x in [-.32, 0.0, .32]:
			_ball(sink, Vector3(w * x, h * .96, -d * .04), Vector3(w * .09, h * .035, d * .08), _color(idn + 2))
	else:
		for x in [-.25, .25]:
			_box(sink, Vector3(w * x, h * .955, -d * .04), Vector3(w * .22, h * .06, d * .20), _color(idn + 2), .018)

func _landmark(sink, idn: int, s: Vector3) -> void:
	var w: float = s.x
	var h: float = s.y
	var d: float = s.z
	_box(sink, Vector3(0, h * .12, 0), Vector3(w * .90, h * .23, d * .88), _color(3), .08)
	if theme_id == "amusement" and idn == 35:
		# A vertical wheel with its own support, all inside one swallowable landmark.
		var r: float = minf(w * .35, h * .34)
		_ring(sink, Vector3(0, h * .59, 0), r, w * .024, _color(1), true)
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			var end: Vector3 = Vector3(cos(a) * r, h * .59 + sin(a) * r, 0)
			_bar(sink, Vector3(0, h * .59, 0), end, w * .014, _color(i))
			_ball(sink, end, Vector3(w * .055, h * .05, d * .065), _color(i + 1))
		_bar(sink, Vector3(-w * .18, h * .22, 0), Vector3(0, h * .59, 0), w * .035, _color(4))
		_bar(sink, Vector3(w * .18, h * .22, 0), Vector3(0, h * .59, 0), w * .035, _color(4))
	elif theme_id == "amusement" and idn == 36:
		_cup(sink, Vector3(0, h * .48, 0), w * .31, w * .31, h * .35, _color(4))
		_cup(sink, Vector3(0, h * .76, 0), w * .37, w * .07, h * .27, _color(1))
		for i in 6:
			var a: float = TAU * float(i) / 6.0
			_cup(sink, Vector3(cos(a) * w * .23, h * .39, sin(a) * d * .24), w * .065, w * .065, h * .16, _color(i))
	elif theme_id == "amusement":
		for i in 4:
			_box(sink, Vector3((i - 1.5) * w * .18, h * (.35 + i * .16), 0), Vector3(w * .27, h * .13, d * .55), _color(i), .07)
		_ball(sink, Vector3(w * .26, h * .92, 0), Vector3(w * .12, h * .075, d * .14), _color(4))
	elif idn == 35:
		_cup(sink, Vector3(0, h * .55, 0), w * .31, w * .31, h * .50, _color(5))
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			_ball(sink, Vector3(cos(a) * w * .20, h * .82, sin(a) * d * .21), Vector3(w * .045, h * .035, d * .05), _color(3))
	elif idn == 36:
		_cup(sink, Vector3(0, h * .52, 0), w * .26, w * .35, h * .65, _color(1))
		_cup(sink, Vector3(0, h * .86, 0), w * .37, w * .37, h * .08, _color(4))
		_bar(sink, Vector3(w * .18, h * .88, 0), Vector3(w * .23, h * .99, 0), w * .025, _color(3))
		for i in 5:
			_ball(sink, Vector3((i - 2) * w * .12, h * .39, d * .30), Vector3(w * .045, h * .04, d * .05), _color(3))
	else:
		_cup(sink, Vector3(0, h * .50, 0), w * .32, w * .32, h * .62, _color(4))
		_cup(sink, Vector3(0, h * .87, 0), w * .35, w * .30, h * .12, _color(1))
		for i in 5:
			_ball(sink, Vector3((i - 2) * w * .12, h * .54, d * .28), Vector3(w * .05, h * .06, d * .05), _color(i))
