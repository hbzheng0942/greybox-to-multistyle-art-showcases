class_name MuseumBuilder
extends Node3D
## Museum shell + exhibit furniture for the museum-dog greybox (v0.3).
## Owns space, scale and exhibit density; no art.
## 铁律：任何展品都必须落在「有碰撞的」支撑面上，摆位高度用 _rest() 算，不允许手写魔法数。
## Footprint 36 x 26 m. Hall ceiling 8.5 m, side galleries 5.2-6 m.

const T := 0.3
const HALL := 8.5
const PORC := 5.2
const TAXI := 5.5
const KIDS := 6.0
const VEST := 3.8
const DOOR_H := 3.6
const FLOOR_TOP := 0.05
const BONE := Color(0.87, 0.84, 0.75)

const PropSpecs = preload("res://shared/game/prop_specs.gd")

var _region_id := "building"

var exhibit_spots: Array = []
var skel_bones: Array = []
var visitor_routes: Dictionary = {}
var lights: Array[OmniLight3D] = []

func build() -> void:
	_build_hall()
	_build_porcelain()
	_build_taxidermy()
	_build_kids()
	_build_vestibule()
	_build_caps()

# ---------------- hall ----------------

func _build_hall() -> void:
	_region_id = "hall"
	_floor(Vector2(-8, -6), Vector2(16, 14), Color(0.36, 0.3, 0.24))
	_ceiling(Vector2(-8, -6), Vector2(16, 14), HALL, Color(0.86, 0.84, 0.79))

	var wall := Color(0.31, 0.32, 0.36)
	_wall_x_with_door(-8, -6, 0, 3, 8, HALL, wall)
	_wall_x_with_door(8, -6, 0, 3, 8, HALL, wall)
	_wall_z_with_door(-6, -8, 2.2, 3.9, 8, HALL, wall)
	_wall_z_with_door(8, -8, -1.5, 1.5, 8, HALL, wall)

	# 天窗条 + 横梁 + 纵向龙骨：靠 8.5 m 层高立住「展览空间」的尺度感
	for i in range(3):
		var z := -4.0 + float(i) * 4.5
		_box(Vector3(11.0, 0.12, 1.6), Vector3(0, HALL - 0.22, z), Color(1.0, 0.98, 0.9), true, true, "ceiling_detail")
		_box(Vector3(15.6, 0.45, 0.4), Vector3(0, HALL - 0.5, z + 2.2), Color(0.66, 0.62, 0.56), false, false, "ceiling_detail")
	for i in range(5):
		var x := -7.4 + float(i) * 3.7
		_box(Vector3(0.32, 0.42, 13.4), Vector3(x, HALL - 0.4, 1.0), Color(0.66, 0.62, 0.56), false, false, "ceiling_detail")

	for corner in [Vector3(-7.05, 0, -4.2), Vector3(7.05, 0, -4.2), Vector3(-7.05, 0, 6.2), Vector3(7.05, 0, 6.2)]:
		_column(corner, HALL)

	# 主展台：压低到 0.85，让骨架撑满竖向，而不是一块黑台子挡视线
	_box(Vector3(7.0, 4.7, 0.2), Vector3(-1.2, FLOOR_TOP + 2.35, -5.66), Color(0.19, 0.2, 0.23), true, false, "structure")
	_box(Vector3(5.4, 0.16, 0.1), Vector3(-1.2, FLOOR_TOP + 3.95, -5.55), Color(0.72, 0.68, 0.6), false, false, "structure")
	_box(Vector3(3.6, 0.1, 0.06), Vector3(-1.7, FLOOR_TOP + 3.62, -5.55), Color(0.5, 0.48, 0.44), false, false, "structure")
	_plinth(Vector3(0, 0, -2.2), Vector3(7.6, 0.8, 3.0), Color(0.68, 0.64, 0.56))
	_skeleton(Vector3(0, FLOOR_TOP + 0.8, -2.2))

	var posts := [Vector3(-4.6, 0, -4.3), Vector3(4.6, 0, -4.3), Vector3(-4.6, 0, -0.1), Vector3(4.6, 0, -0.1)]
	for p in posts:
		_stanchion(p)
	_rope(Vector3(-4.6, 0.95, -4.3), Vector3(4.6, 0.95, -4.3))
	_rope(Vector3(-4.6, 0.95, -0.1), Vector3(4.6, 0.95, -0.1))
	_rope(Vector3(-4.6, 0.95, -4.3), Vector3(-4.6, 0.95, -0.1))
	_rope(Vector3(4.6, 0.95, -4.3), Vector3(4.6, 0.95, -0.1))

	# 两侧墙面：挂画 + 大导览板，避免整面白墙
	for i in range(3):
		var z := -3.4 + float(i) * 3.4
		_painting(Vector3(-8 + T * 0.6, 3.3, z), 90.0, Vector2(1.7, 1.2))
		_painting(Vector3(8 - T * 0.6, 3.3, z), -90.0, Vector2(1.7, 1.2))
	_info_panel(Vector3(-5.9, 2.7, -5.7), 0.0, Vector2(2.2, 1.5))
	_info_panel(Vector3(4.8, 2.7, -5.7), 0.0, Vector2(2.2, 1.5))

	_bench(Vector3(-3.6, 0, 5.4), 180.0)
	_bench(Vector3(3.6, 0, 5.4), 180.0)

	# 四座小基座：胸像 / 矿石，增加「各式各样展台」的层次
	_bust_plinth(Vector3(-6.2, 0, -2.0), 2600)
	_bust_plinth(Vector3(6.2, 0, -2.0), 2400)
	_rock_plinth(Vector3(-6.2, 0, 3.0), 5)
	_rock_plinth(Vector3(6.2, 0, 3.0), 5)

	_gift_table(Vector3(-5.9, 0, 7.0), 0.0)
	_gift_table(Vector3(5.9, 0, 7.0), 0.0)

	_lights_hall()
	_spot(Vector3(-0.6, HALL - 0.6, -2.6), Vector3(-0.6, 1.8, -2.6), 2.0, 40.0, true)
	_spot(Vector3(-6.2, 6.6, -2.0), Vector3(-6.2, 1.2, -2.0), 1.2, 30.0, false)
	_spot(Vector3(6.2, 6.6, -2.0), Vector3(6.2, 1.2, -2.0), 1.2, 30.0, false)

	_sign(Vector3(-7.82, 3.92, 1.5), 90.0, Vector2(2.2, 0.42), Color(0.34, 0.46, 0.58))
	_sign(Vector3(7.82, 3.92, 1.5), -90.0, Vector2(2.2, 0.42), Color(0.3, 0.46, 0.34))
	_sign(Vector3(3.05, 3.92, -5.82), 0.0, Vector2(1.9, 0.42), Color(0.72, 0.5, 0.36))
	_sign(Vector3(0, 3.92, 7.82), 180.0, Vector2(2.2, 0.42), Color(0.42, 0.4, 0.38))

	visitor_routes["hall"] = [
		Vector3(-4.4, 0, 4.4), Vector3(4.4, 0, 4.4), Vector3(-4.6, 0, 2.2),
		Vector3(0, 0, 2.4), Vector3(4.6, 0, 2.2), Vector3(-5.6, 0, 6.4), Vector3(5.6, 0, 6.4)
	]

func _skeleton(origin: Vector3) -> void:
	# 猛犸象式骨架：中庭 3.4 m 高的视觉锚点，也是「整具骨架垮下来」的载体。
	# 侧影优先：四条腿 → 骨盆/肩胛 → 悬在脊柱下的肋骨 → 头骨獠牙 → 尾巴。
	# 头朝东（+X），和北墙偏东的门洞同侧；转 180° 试过，头/肩/颈会挤成一团，反而更糊。
	#
	# 12 段全是冻结刚体：平时立着，被撞断的段解冻掉落。sup 是「谁在撑着我」，
	# 只有当某段的支撑全断了它才会跟着塌 —— 只撞断一条后腿，骨架会歪但站得住。
	_label_plate(origin + Vector3(-0.1, 0.04, 1.45))

	# 四条腿：一条腿一段，撞断哪条掉哪条
	for spec in [
		{"id": "back_leg_l", "at": Vector3(-1.25, 0.86, -0.55)},
		{"id": "back_leg_r", "at": Vector3(-1.25, 0.86, 0.55)},
		{"id": "front_leg_l", "at": Vector3(1.25, 0.86, -0.55)},
		{"id": "front_leg_r", "at": Vector3(1.25, 0.86, 0.55)},
	]:
		var at: Vector3 = spec["at"]
		var body := _bone(origin, str(spec["id"]), [], Vector3(0.34, 1.72, 0.34), at, 3.2, 2600)
		_part(body, Vector3(0.5, 0.12, 0.42), Vector3(0, -0.78, 0), BONE)
		_part(body, Vector3(0.19, 0.82, 0.19), Vector3(0, -0.34, 0), BONE)
		_part(body, Vector3(0.26, 0.14, 0.26), Vector3(0, 0.12, 0), BONE.darkened(0.12))
		_part(body, Vector3(0.22, 0.75, 0.22), Vector3(0, 0.54, 0), BONE)

	var pelvis := _bone(origin, "pelvis", ["back_leg_l", "back_leg_r"],
		Vector3(0.9, 0.64, 1.08), Vector3(-1.25, 1.95, 0), 6.0, 7200)
	_part(pelvis, Vector3(0.85, 0.62, 1.05), Vector3.ZERO, BONE)

	var chest := _bone(origin, "chest", ["front_leg_l", "front_leg_r"],
		Vector3(0.76, 0.74, 1.04), Vector3(1.25, 2.05, 0), 6.0, 6800)
	_part(chest, Vector3(0.72, 0.72, 1.0), Vector3.ZERO, BONE)

	var spine := _bone(origin, "spine", ["pelvis", "chest"],
		Vector3(3.1, 0.19, 0.22), Vector3(0, 2.34, 0), 2.4, 5400)
	_part(spine, Vector3(3.1, 0.17, 0.2), Vector3.ZERO, BONE.lightened(0.04))

	# 肋骨群：9 根挂在一个刚体上，否则碰撞体太多、塌起来像撒豆子
	var ribs := _bone(origin, "ribs", ["spine"],
		Vector3(2.35, 1.05, 1.02), Vector3(0.3, 1.74, 0), 4.0, 6400)
	for i in range(9):
		var x := -0.85 + float(i) * 0.24
		var t := absf(x - 0.25) / 1.1
		var h := 1.05 - t * 0.28
		_part(ribs, Vector3(0.055, h, 1.02 - t * 0.12), Vector3(x - 0.3, 2.26 - h * 0.5 - 1.74, 0), BONE)

	var neck := _bone(origin, "neck", ["spine"],
		Vector3(0.62, 0.5, 0.52), Vector3(1.6, 2.38, 0), 1.4, 3200)
	_part(neck, Vector3(0.44, 0.44, 0.44), Vector3.ZERO, BONE)
	_part(neck, Vector3(0.5, 0.12, 0.16), Vector3(-0.34, 0.16, 0), BONE.darkened(0.08))

	var head := _bone(origin, "head", ["neck"],
		Vector3(1.0, 0.62, 0.6), Vector3(2.2, 2.44, 0), 2.6, 9800)
	_part(head, Vector3(0.86, 0.56, 0.52), Vector3.ZERO, BONE.lightened(0.05))

	var jaw := _bone(origin, "jaw", ["head"],
		Vector3(0.92, 0.22, 0.52), Vector3(2.38, 2.05, 0), 1.2, 3600)
	_part(jaw, Vector3(0.8, 0.16, 0.34), Vector3(-0.14, 0.07, 0), BONE)
	for sz in [-0.25, 0.25]:
		_part(jaw, Vector3(0.86, 0.09, 0.09), Vector3(0.22, -0.15, sz), BONE)

	var tail := _bone(origin, "tail", ["pelvis"],
		Vector3(1.55, 0.34, 0.24), Vector3(-2.28, 2.0, 0), 1.8, 2800)
	for i in range(4):
		_part(tail, Vector3(0.36, 0.09, 0.09), Vector3(0.42 - float(i) * 0.34, 0.22 - float(i) * 0.24, 0), BONE)

## 咬下一根骨：冻结刚体 + 一个盒碰撞体，挂在 skel_bones 里等玩家来撞断
func _bone(origin: Vector3, id: String, sup: Array, size: Vector3, at: Vector3,
		mass: float, value: int) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Bone_" + id
	body.position = origin + at
	body.mass = mass
	body.collision_layer = 2
	body.collision_mask = 1 | 2 | 4
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.set_meta("value", value)
	body.set_meta("kind", "bone")
	body.set_meta("spawn_pos", body.position)
	body.set_meta("spawn_y", body.position.y)
	body.set_meta("spawn_basis", body.transform.basis)
	body.set_meta("counted", false)
	body.set_meta("bone_id", id)
	body.set_meta("semantic_id", "hall/skeleton/" + id)
	body.set_meta("semantic_role", "bone")
	body.set_meta("region_id", "hall")
	body.set_meta("native_size", size)
	body.set_meta("supports", sup.duplicate())
	body.set_meta("reach", maxf(size.x, maxf(size.y, size.z)) * 0.5 + 0.55)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.name = "PhysicsShape"
	body.add_child(cs)
	add_child(body)
	skel_bones.append({"id": id, "body": body, "sup": sup, "broken": false})
	return body

func _part(body: RigidBody3D, size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = offset
	var semantic_id := str(body.get_meta("semantic_id")) + "/visual/" + (str(offset) + str(size)).sha256_text().substr(0, 12)
	_tag_node(mesh, semantic_id, "bone_detail", "visual")
	mesh.set_meta("semantic_owner_id", body.get_meta("semantic_id"))
	mesh.set_meta("native_size", size)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh.material_override = material
	body.add_child(mesh)
func _bust_plinth(pos: Vector3, value: int) -> void:
	_box(Vector3(0.9, 1.15, 0.9), pos + Vector3(0, FLOOR_TOP + 0.57, 0), Color(0.46, 0.44, 0.4), true, false, "display_platform")
	var top := FLOOR_TOP + 1.15
	_box(Vector3(1.0, 0.07, 1.0), pos + Vector3(0, top + 0.03, 0), Color(0.55, 0.52, 0.48), false, false, "display_platform")
	_exhibit(pos + Vector3(0, _rest("bust", top + 0.06), 0), "bust", value, Color(0.88, 0.86, 0.8))
	_label_plate(pos + Vector3(0, 0.9, 0.47))

func _rock_plinth(pos: Vector3, count: int) -> void:
	_box(Vector3(1.8, 0.85, 1.8), pos + Vector3(0, FLOOR_TOP + 0.42, 0), Color(0.5, 0.47, 0.43), true, false, "display_platform")
	var top := FLOOR_TOP + 0.85
	for i in range(count):
		var x := -0.45 + float(i % 2) * 0.9
		var z := -0.45 + float(i / 2) * 0.6
		var tint := Color(0.62, 0.58, 0.5).lerp(Color(0.75, 0.6, 0.4), float(i) / float(maxi(count, 1)))
		_exhibit(pos + Vector3(x, _rest("rock", top), z), "rock", 220 + 40 * i, tint)

# ---------------- porcelain ----------------

func _build_porcelain() -> void:
	_region_id = "porcelain"
	_floor(Vector2(-18, -4), Vector2(10, 10), Color(0.52, 0.56, 0.6))
	_ceiling(Vector2(-18, -4), Vector2(10, 10), PORC, Color(0.72, 0.74, 0.76))
	_wall_x(-18, -4, 6, 0, PORC, Color(0.14, 0.2, 0.24))
	_wall_z(-4, -18, -8, 0, PORC, Color(0.14, 0.2, 0.24))
	_wall_z(6, -18, -8, 0, PORC, Color(0.14, 0.2, 0.24))

	# 两面通高瓷器柜：三层盘子 = 一条能连锁倒塌的“多米诺”
	_shelf_wall(Vector3(-13.0, 0, -3.82), 9.0, 0.0)
	_shelf_wall(Vector3(-13.0, 0, 5.82), 9.0, 180.0)

	# 六张展台，每张三个花瓶
	for tx in [-16.2, -13.4, -10.6]:
		for tz in [-1.2, 2.6]:
			_vitrine(Vector3(tx, 0, tz))

	# 镇馆大瓶
	_box(Vector3(1.4, 1.0, 1.4), Vector3(-9.6, FLOOR_TOP + 0.5, 3.6), Color(0.88, 0.86, 0.8), true, false, "display_platform")
	var star_top := FLOOR_TOP + 1.0
	_box(Vector3(1.55, 0.08, 1.55), Vector3(-9.6, star_top + 0.03, 3.6), Color(0.55, 0.52, 0.48), false, false, "display_platform")
	_exhibit(Vector3(-9.6, _rest("vase_big", star_top + 0.06), 3.6), "vase_big", 6200, Color(0.92, 0.9, 0.84))
	_label_plate(Vector3(-9.6, 0.85, 4.32))

	_lights_room(Vector3(-13, 0, 1), PORC, 3)
	_spot(Vector3(-9.6, PORC - 0.4, 3.6), Vector3(-9.6, 1.0, 3.6), 2.2, 34.0, true)
	visitor_routes["porcelain"] = [
		Vector3(-15.4, 0, 0.6), Vector3(-11.4, 0, 0.6), Vector3(-16.2, 0, 4.4),
		Vector3(-10.4, 0, 4.4), Vector3(-13.2, 0, 1.6)
	]

func _vitrine(pos: Vector3) -> void:
	# 敞开式展台：花瓶直接落在台面上，狗够得着，也绝不会穿模
	_box(Vector3(2.1, 0.85, 1.1), pos + Vector3(0, FLOOR_TOP + 0.42, 0), Color(0.58, 0.55, 0.5), true, false, "display_table")
	var top := FLOOR_TOP + 0.85
	_box(Vector3(2.25, 0.07, 1.25), pos + Vector3(0, top + 0.03, 0), Color(0.86, 0.85, 0.8), false, false, "display_table")
	for i in range(3):
		_exhibit(pos + Vector3(-0.6 + float(i) * 0.6, _rest("vase", top + 0.06), 0), "vase", 900 + 300 * i)
	_label_plate(pos + Vector3(0, 0.7, 0.58))

func _shelf_wall(pos: Vector3, length: float, rotation_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rotation_y
	add_child(root)
	_tag_node(root, _semantic_id("display_shelf", pos, Vector3.ZERO, self), "display_shelf", "assembly")
	# 背板退到 z=-0.11，层板向前伸：展品不会再被塞进背板里
	_box_at(root, Vector3(length, 3.0, 0.22), Vector3(0, 1.55, -0.11), Color(0.26, 0.22, 0.19), true, false, "display_shelf")
	_box_at(root, Vector3(length, 0.16, 0.6), Vector3(0, 0.08, 0.08), Color(0.22, 0.19, 0.16), true, false, "display_shelf")
	_box_at(root, Vector3(length, 0.22, 0.62), Vector3(0, 3.06, 0.08), Color(0.22, 0.19, 0.16), true, false, "display_shelf")
	for level in range(3):
		var y := 0.95 + float(level) * 0.72
		_box_at(root, Vector3(length - 0.24, 0.07, 0.5), Vector3(0, y, 0.14), Color(0.36, 0.31, 0.25), true, false, "display_shelf")
		var top := y + 0.035
		for i in range(8):
			var x := -length * 0.5 + 0.72 + float(i) * (length - 1.44) / 7.0
			var tint := Color(0.88, 0.9, 0.93).lerp(Color(0.8, 0.86, 0.95), float(i) / 7.0)
			_exhibit(root.to_global(Vector3(x, top + 0.032, 0.14)), "plate", 480, tint)

# ---------------- taxidermy ----------------

func _build_taxidermy() -> void:
	_region_id = "taxidermy"
	_floor(Vector2(8, -4), Vector2(10, 10), Color(0.35, 0.28, 0.21))
	_ceiling(Vector2(8, -4), Vector2(10, 10), TAXI, Color(0.48, 0.46, 0.42))
	_wall_x(18, -4, 6, 0, TAXI, Color(0.18, 0.26, 0.2))
	_wall_z(-4, 8, 18, 0, TAXI, Color(0.18, 0.26, 0.2))
	_wall_z(6, 8, 18, 0, TAXI, Color(0.18, 0.26, 0.2))

	# 化石墙：内嵌石板，给东墙一点内容
	for i in range(3):
		var z := -2.2 + float(i) * 2.4
		_box(Vector3(0.18, 1.5, 2.0), Vector3(18 - T * 0.55, 3.1, z), Color(0.62, 0.58, 0.48), false, false, "furniture")
		_box(Vector3(0.12, 1.1, 0.5), Vector3(18 - T * 0.75, 3.1, z - 0.3), Color(0.8, 0.76, 0.66), false, false, "furniture")
		_box(Vector3(0.12, 0.4, 1.2), Vector3(18 - T * 0.75, 2.9, z + 0.3), Color(0.8, 0.76, 0.66), false, false, "furniture")

	_animal_platform(Vector3(10.8, 0, -1.4), "bear", 0.0)
	_animal_platform(Vector3(14.8, 0, -1.8), "deer", 0.0)
	_animal_platform(Vector3(12.4, 0, 3.0), "wolf", 0.0)

	# 可被偷走的“标本零件”放在独立小边几上，不再插在动物背上
	_specimen_table(Vector3(10.6, 0, 1.2), 3400)
	_specimen_table(Vector3(14.6, 0, 1.4), 2800)
	_specimen_table(Vector3(12.4, 0, 5.0), 3100)

	for i in range(4):
		var z := -2.8 + float(i) * 2.2
		_wall_head(Vector3(18 - T * 0.7, 2.9, z))

	_box(Vector3(3.2, 0.55, 1.2), Vector3(15.4, FLOOR_TOP + 0.28, 4.8), Color(0.5, 0.4, 0.3), true, false, "furniture")
	var bone_top := FLOOR_TOP + 0.55
	for i in range(6):
		_exhibit(Vector3(14.2 + float(i) * 0.48, _rest("bone", bone_top), 4.8), "bone", 350, Color(0.92, 0.9, 0.82))
	_bench(Vector3(11.2, 0, 5.4), 180.0)

	_lights_room(Vector3(13, 0, 1), TAXI, 3)
	_spot(Vector3(10.8, TAXI - 0.5, -1.4), Vector3(10.8, 1.8, -1.4), 1.6, 32.0, false)
	_spot(Vector3(14.8, TAXI - 0.5, -1.8), Vector3(14.8, 1.7, -1.8), 1.6, 32.0, false)
	visitor_routes["taxidermy"] = [
		Vector3(10.2, 0, 1.6), Vector3(15.6, 0, 1.2), Vector3(12.6, 0, 4.2), Vector3(16.2, 0, 3.4)
	]

func _animal_platform(pos: Vector3, kind: String, _unused: float) -> void:
	_box(Vector3(2.6, 0.8, 2.1), pos + Vector3(0, FLOOR_TOP + 0.4, 0), Color(0.52, 0.42, 0.3), true, false, "specimen_display")
	var top := FLOOR_TOP + 0.8
	_box(Vector3(2.7, 0.08, 2.2), pos + Vector3(0, top + 0.04, 0), Color(0.7, 0.65, 0.55), false, false, "specimen_display")

	var body := Color(0.44, 0.33, 0.23)
	var h := 0.0
	if kind == "deer":
		body = Color(0.58, 0.44, 0.29)
		h = 0.25
	elif kind == "wolf":
		body = Color(0.42, 0.42, 0.45)
		h = -0.15

	var stand := top + 0.08
	# 四条腿
	for sx in [-0.55, 0.55]:
		for sz in [-0.32, 0.32]:
			_box(Vector3(0.18, 1.05 + h, 0.18), pos + Vector3(sx, stand + 0.52 + h * 0.5, sz), body.darkened(0.1), false, false, "specimen_display")
	# 躯干 + 脖子 + 头
	_box(Vector3(1.55, 0.8 + h, 0.78), pos + Vector3(0, stand + 1.45 + h * 0.5, 0), body, false, false, "specimen_display")
	_box(Vector3(0.55, 0.7 + h * 0.5, 0.55), pos + Vector3(-0.85, stand + 1.75 + h * 0.5, 0), body, false, false, "specimen_display")
	_box(Vector3(0.75, 0.55, 0.5), pos + Vector3(-1.15, stand + 2.02 + h * 0.5, 0), body.lightened(0.06), false, false, "specimen_display")
	_box(Vector3(0.3, 0.22, 0.34), pos + Vector3(-1.5, stand + 1.92 + h * 0.5, 0), body.darkened(0.2), false, false, "specimen_display")
	# 尾巴
	_box(Vector3(0.5, 0.12, 0.12), pos + Vector3(0.95, stand + 1.3 + h * 0.5, 0), body.darkened(0.15), false, false, "specimen_display")
	if kind == "deer":
		for sz in [-0.14, 0.14]:
			_box(Vector3(0.1, 0.55, 0.1), pos + Vector3(-1.2, stand + 2.45, sz), Color(0.78, 0.72, 0.62), false, false, "specimen_display")
	_label_plate(pos + Vector3(0, 0.7, 1.12))

func _specimen_table(pos: Vector3, value: int) -> void:
	_box(Vector3(1.0, 0.72, 0.7), pos + Vector3(0, FLOOR_TOP + 0.36, 0), Color(0.46, 0.36, 0.26), true, false, "display_table")
	var top := FLOOR_TOP + 0.72
	_box(Vector3(1.1, 0.06, 0.8), pos + Vector3(0, top + 0.03, 0), Color(0.66, 0.6, 0.5), false, false, "display_table")
	_exhibit(pos + Vector3(0, _rest("specimen", top + 0.06), 0), "specimen", value, Color(0.7, 0.62, 0.46))

# ---------------- kids / interactive ----------------

func _build_kids() -> void:
	_region_id = "kids"
	_floor(Vector2(-4, -15), Vector2(8, 9), Color(0.78, 0.7, 0.58))
	_ceiling(Vector2(-4, -15), Vector2(8, 9), KIDS, Color(0.9, 0.86, 0.8))
	_wall_x(-4, -15, -6, 0, KIDS, Color(0.92, 0.84, 0.77))
	_wall_x(4, -15, -6, 0, KIDS, Color(0.92, 0.84, 0.77))
	_wall_z(-15, -4, 4, 0, KIDS, Color(0.92, 0.84, 0.77))

	# 手作长桌
	_box(Vector3(5.4, 0.16, 1.5), Vector3(0, FLOOR_TOP + 0.76, -11.2), Color(0.86, 0.82, 0.74), true, false, "furniture")
	for i in range(4):
		_box(Vector3(0.12, 0.76, 0.12), Vector3(-2.4 + float(i) * 1.6, FLOOR_TOP + 0.38, -10.6), Color(0.6, 0.55, 0.48), false, false, "furniture")
	var craft_top := FLOOR_TOP + 0.84
	for i in range(16):
		var px := -2.2 + float(i % 8) * 0.62
		var pz := -11.5 + float(i / 8) * 0.6
		_exhibit(Vector3(px, _rest("craft", craft_top), pz), "craft", 320, Color(0.95, 0.5 + 0.04 * float(i % 6), 0.4))

	# 球池：矮围板（0.26），从站立视角就能看见里面的球
	var pit := Vector2(2.1, -13.6)
	_box(Vector3(3.2, 0.26, 0.16), Vector3(pit.x, FLOOR_TOP + 0.13, pit.y - 1.4), Color(0.55, 0.62, 0.7), true, false, "furniture")
	_box(Vector3(3.2, 0.26, 0.16), Vector3(pit.x, FLOOR_TOP + 0.13, pit.y + 1.4), Color(0.55, 0.62, 0.7), true, false, "furniture")
	_box(Vector3(0.16, 0.26, 2.96), Vector3(pit.x - 1.6, FLOOR_TOP + 0.13, pit.y), Color(0.55, 0.62, 0.7), true, false, "furniture")
	_box(Vector3(0.16, 0.26, 2.96), Vector3(pit.x + 1.6, FLOOR_TOP + 0.13, pit.y), Color(0.55, 0.62, 0.7), true, false, "furniture")
	for i in range(12):
		var bx := pit.x - 1.1 + float(i % 4) * 0.72
		var bz := pit.y - 0.95 + float(i / 4) * 0.9
		var tint: Color = [Color(0.95, 0.72, 0.35), Color(0.9, 0.45, 0.4), Color(0.45, 0.7, 0.85)][i % 3]
		_exhibit(Vector3(bx, _rest("ball", FLOOR_TOP), bz), "ball", 260, tint)

	# 按钮台
	_box(Vector3(2.0, 1.0, 0.8), Vector3(-2.4, FLOOR_TOP + 0.5, -14.2), Color(0.36, 0.42, 0.48), true, false, "furniture")
	var btn_top := FLOOR_TOP + 1.0
	for i in range(4):
		_exhibit(Vector3(-3.0 + float(i) * 0.4, _rest("button", btn_top), -14.2), "button", 800, Color(0.92, 0.35, 0.3))

	# 软包攀爬块：给儿童区一点体量，也是狗可以爬上去的地方
	var soft := Color(0.62, 0.72, 0.6)
	_box(Vector3(1.6, 0.5, 1.6), Vector3(-2.4, FLOOR_TOP + 0.25, -8.6), soft, true, false, "furniture")
	_box(Vector3(1.2, 0.9, 1.2), Vector3(-2.5, FLOOR_TOP + 0.45, -9.9), soft.darkened(0.08), true, false, "furniture")
	_box(Vector3(1.4, 0.35, 2.4), Vector3(-2.6, FLOOR_TOP + 0.17, -12.4), soft.lightened(0.05), true, false, "furniture")

	# 墙面彩板 + 地毯 + 玩具架：别让儿童区只剩一张桌子
	var mural := [Color(0.86, 0.6, 0.36), Color(0.5, 0.7, 0.7), Color(0.75, 0.55, 0.68)]
	for i in range(3):
		_box(Vector3(1.9, 1.5, 0.1), Vector3(-2.4 + float(i) * 2.4, 2.5, -15 + T * 0.5), mural[i], false, false, "furniture")
	_box(Vector3(3.4, 0.02, 2.6), Vector3(0.2, FLOOR_TOP + 0.011, -9.4), Color(0.62, 0.48, 0.5), false, false, "furniture")
	# 玩具架（贴西墙）：背板退后，层板前伸，展品落在层板上而不是塞进背板
	_box(Vector3(0.16, 1.2, 3.2), Vector3(-3.78, FLOOR_TOP + 0.6, -12.6), Color(0.66, 0.58, 0.46), true, false, "furniture")
	for level in range(2):
		var sy := FLOOR_TOP + 0.55 + float(level) * 0.4
		_box(Vector3(0.36, 0.06, 3.1), Vector3(-3.6, sy, -12.6), Color(0.5, 0.44, 0.36), true, false, "furniture")
		for i in range(6):
			var sz2 := -13.95 + float(i) * 0.54
			_exhibit(Vector3(-3.6, _rest("craft", sy + 0.03), sz2), "craft", 300, Color(0.55, 0.75, 0.85))

	_lights_room(Vector3(0, 0, -11), KIDS, 2)
	visitor_routes["kids"] = [
		Vector3(-2.8, 0, -8.2), Vector3(2.4, 0, -8.2), Vector3(-2.8, 0, -12.0), Vector3(0.4, 0, -10.6)
	]

# ---------------- vestibule ----------------

func _build_vestibule() -> void:
	_region_id = "vestibule"
	_floor(Vector2(-3, 8), Vector2(6, 3.4), Color(0.5, 0.48, 0.45))
	_ceiling(Vector2(-3, 8), Vector2(6, 3.4), VEST, Color(0.7, 0.7, 0.68))
	_wall_x(-3, 8, 11.4, 0, VEST, Color(0.74, 0.72, 0.68))
	_wall_x(3, 8, 11.4, 0, VEST, Color(0.74, 0.72, 0.68))
	_wall_z(11.4, -3, -1.0, 0, VEST, Color(0.74, 0.72, 0.68))
	_wall_z(11.4, 1.0, 3, 0, VEST, Color(0.74, 0.72, 0.68))
	# This greybox has no exterior level: close its outer entrance visibly and physically.
	_box(Vector3(2.0, VEST, 0.22), Vector3(0, VEST * 0.5, 11.4), Color(0.28, 0.33, 0.36), true, false, "entrance_door")
	_box(Vector3(0.025, 1.7, 0.025), Vector3(0, 0.9, 11.275), Color(0.1, 0.12, 0.13), false, false, "entrance_door_detail")
	for side in [-1.0, 1.0]:
		_box(Vector3(0.045, 0.36, 0.08), Vector3(side * 0.14, 1.0, 11.23), Color(0.72, 0.7, 0.64), false, false, "entrance_door_handle")
	_box(Vector3(2.2, 0.95, 0.9), Vector3(-1.9, FLOOR_TOP + 0.47, 9.4), Color(0.56, 0.54, 0.5), true, false, "furniture")
	var desk := FLOOR_TOP + 0.95
	_box(Vector3(2.3, 0.06, 1.0), Vector3(-1.9, desk + 0.03, 9.4), Color(0.72, 0.7, 0.64), false, false, "furniture")
	_exhibit(Vector3(-1.9, _rest("brochure", desk + 0.06), 9.4), "brochure", 150, Color(0.92, 0.88, 0.7))
	# 门厅主视觉：大块深色导览牌 + 地面导流垫
	_box(Vector3(4.6, 1.3, 0.14), Vector3(0, 2.5, 11.25), Color(0.2, 0.22, 0.26), false, false, "furniture")
	_box(Vector3(4.2, 0.95, 0.08), Vector3(0, 2.5, 11.16), Color(0.82, 0.79, 0.7), false, false, "furniture")
	_box(Vector3(2.6, 0.02, 1.6), Vector3(0, FLOOR_TOP + 0.01, 9.9), Color(0.3, 0.3, 0.32), false, false, "furniture")
	_lights_room(Vector3(0, 0, 9.6), VEST, 1)
	visitor_routes["vestibule"] = [Vector3(-1.2, 0, 9.0), Vector3(1.4, 0, 9.6), Vector3(0, 0, 10.4)]

func _build_caps() -> void:
	_region_id = "building"
	# 侧厅上方的石带：让低层高读成「建筑」，而不是「矮房间」
	_box(Vector3(10.4, 0.55, 0.5), Vector3(-13, PORC + 0.28, -4.15), Color(0.62, 0.6, 0.54), false, false, "roof_trim")
	_box(Vector3(10.4, 0.55, 0.5), Vector3(-13, PORC + 0.28, 6.15), Color(0.62, 0.6, 0.54), false, false, "roof_trim")
	_box(Vector3(10.4, 0.55, 0.5), Vector3(13, TAXI + 0.28, -4.15), Color(0.62, 0.6, 0.54), false, false, "roof_trim")
	_box(Vector3(10.4, 0.55, 0.5), Vector3(13, TAXI + 0.28, 6.15), Color(0.62, 0.6, 0.54), false, false, "roof_trim")

# ---------------- primitives ----------------

func _rest(kind: String, top: float) -> float:
	return top + PropSpecs.rest_height(kind) * 0.5 + 0.012

func _plinth(center: Vector3, size: Vector3, color: Color) -> void:
	_box(size, Vector3(center.x, FLOOR_TOP + size.y * 0.5, center.z), color, true, false, "display_platform")
	_box(Vector3(size.x + 0.18, 0.07, size.z + 0.18), Vector3(center.x, FLOOR_TOP + size.y + 0.035, center.z), Color(0.42, 0.4, 0.36), false, false, "display_platform")

func _floor(top_left: Vector2, size: Vector2, color: Color) -> void:
	var center := Vector3(top_left.x + size.x * 0.5, 0.0, top_left.y + size.y * 0.5)
	_box(Vector3(size.x, 0.3, size.y), center + Vector3(0, FLOOR_TOP - 0.15, 0), color.darkened(0.18), true, false, "floor")
	# 内嵌方框：地面分色，读得出「展区」边界，也把墙脚压住
	_box(Vector3(size.x - 1.8, 0.02, size.y - 1.8), center + Vector3(0, FLOOR_TOP + 0.011, 0), color.lightened(0.05), false, false, "floor")
	for dx in [-1.0, 1.0]:
		_box(Vector3(0.35, 0.02, size.y - 1.8), center + Vector3(dx * (size.x * 0.5 - 0.9), FLOOR_TOP + 0.012, 0), color.darkened(0.22), false, false, "floor")
	for dz in [-1.0, 1.0]:
		_box(Vector3(size.x - 1.8, 0.02, 0.35), center + Vector3(0, FLOOR_TOP + 0.012, dz * (size.y * 0.5 - 0.9)), color.darkened(0.22), false, false, "floor")

func _ceiling(top_left: Vector2, size: Vector2, height: float, color: Color) -> void:
	var center := Vector3(top_left.x + size.x * 0.5, height + 0.15, top_left.y + size.y * 0.5)
	_box(Vector3(size.x, 0.3, size.y), center, color, true, false, "ceiling")
	_box(Vector3(size.x, 0.2, 0.2), center + Vector3(0, -0.22, -size.y * 0.5 + 0.1), color.darkened(0.18), false, false, "ceiling")
	_box(Vector3(size.x, 0.2, 0.2), center + Vector3(0, -0.22, size.y * 0.5 - 0.1), color.darkened(0.18), false, false, "ceiling")
	_box(Vector3(0.2, 0.2, size.y), center + Vector3(-size.x * 0.5 + 0.1, -0.22, 0), color.darkened(0.18), false, false, "ceiling")
	_box(Vector3(0.2, 0.2, size.y), center + Vector3(size.x * 0.5 - 0.1, -0.22, 0), color.darkened(0.18), false, false, "ceiling")

func _wall_x(x: float, z0: float, z1: float, y0: float, height: float, color: Color) -> void:
	var length := absf(z1 - z0)
	_box(Vector3(T, height, length), Vector3(x, y0 + height * 0.5, (z0 + z1) * 0.5), color, true, false, "wall")
	# 踢脚线：0.16 m 深色带，把地面和墙分开
	_box(Vector3(T + 0.06, 0.16, length), Vector3(x, y0 + 0.08, (z0 + z1) * 0.5), color.darkened(0.42), false, false, "wall")

func _wall_z(z: float, x0: float, x1: float, y0: float, height: float, color: Color) -> void:
	var length := absf(x1 - x0)
	_box(Vector3(length, height, T), Vector3((x0 + x1) * 0.5, y0 + height * 0.5, z), color, true, false, "wall")
	_box(Vector3(length, 0.16, T + 0.06), Vector3((x0 + x1) * 0.5, y0 + 0.08, z), color.darkened(0.42), false, false, "wall")

func _wall_x_with_door(x: float, z0: float, door0: float, door1: float, z1: float, height: float, color: Color) -> void:
	if door0 > z0 + 0.01:
		_wall_x(x, z0, door0, 0, height, color)
	if z1 > door1 + 0.01:
		_wall_x(x, door1, z1, 0, height, color)
	_box(Vector3(T, height - DOOR_H, door1 - door0), Vector3(x, DOOR_H + (height - DOOR_H) * 0.5, (door0 + door1) * 0.5), color, true, false, "door_frame")
	# 门洞侧壁（洞口进深），门洞看起来才不是纸片剪的
	for dz in [door0, door1]:
		_box(Vector3(0.6, DOOR_H, 0.14), Vector3(x, DOOR_H * 0.5, dz), color.darkened(0.12), true, false, "door_frame")

func _wall_z_with_door(z: float, x0: float, door0: float, door1: float, x1: float, height: float, color: Color) -> void:
	if door0 > x0 + 0.01:
		_wall_z(z, x0, door0, 0, height, color)
	if x1 > door1 + 0.01:
		_wall_z(z, door1, x1, 0, height, color)
	_box(Vector3(door1 - door0, height - DOOR_H, T), Vector3((door0 + door1) * 0.5, DOOR_H + (height - DOOR_H) * 0.5, z), color, true, false, "door_frame")
	for dx in [door0, door1]:
		_box(Vector3(0.14, DOOR_H, 0.6), Vector3(dx, DOOR_H * 0.5, z), color.darkened(0.12), true, false, "door_frame")

func _column(pos: Vector3, height: float) -> void:
	_box(Vector3(0.95, 0.35, 0.95), pos + Vector3(0, 0.175, 0), Color(0.8, 0.77, 0.7), true, false, "column")
	_box(Vector3(0.7, height - 0.7, 0.7), pos + Vector3(0, height * 0.5, 0), Color(0.88, 0.85, 0.78), true, false, "column")
	_box(Vector3(0.95, 0.35, 0.95), pos + Vector3(0, height - 0.175, 0), Color(0.8, 0.77, 0.7), true, false, "column")

func _stanchion(pos: Vector3) -> void:
	_box(Vector3(0.34, 0.06, 0.34), pos + Vector3(0, 0.03, 0), Color(0.55, 0.5, 0.4), false, false, "barrier_post")
	_box(Vector3(0.06, 0.95, 0.06), pos + Vector3(0, 0.48, 0), Color(0.85, 0.7, 0.3), true, false, "barrier_post")
	_box(Vector3(0.1, 0.1, 0.1), pos + Vector3(0, 0.98, 0), Color(0.85, 0.7, 0.3), false, false, "barrier_post")

func _rope(a: Vector3, b: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(a.distance_to(b), 0.05, 0.05)
	mesh.mesh = box
	mesh.position = (a + b) * 0.5
	_tag_node(mesh, _semantic_id("barrier_rope", mesh.position, box.size, self), "barrier_rope", "visual")
	mesh.set_meta("native_endpoints", PackedVector3Array([a, b]))
	mesh.material_override = _mat(Color(0.6, 0.16, 0.2))
	add_child(mesh)

func _bench(pos: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rotation_y
	add_child(root)
	_tag_node(root, _semantic_id("bench", pos, Vector3.ZERO, self), "bench", "assembly")
	_box_at(root, Vector3(2.2, 0.14, 0.6), Vector3(0, FLOOR_TOP + 0.48, 0), Color(0.5, 0.38, 0.28), true, false, "bench")
	_box_at(root, Vector3(2.2, 0.5, 0.12), Vector3(0, FLOOR_TOP + 0.78, 0.24), Color(0.5, 0.38, 0.28), true, false, "bench")
	for dx in [-0.85, 0.85]:
		_box_at(root, Vector3(0.12, 0.48, 0.5), Vector3(dx, FLOOR_TOP + 0.24, 0), Color(0.35, 0.35, 0.35), false, false, "bench")

func _painting(pos: Vector3, rotation_y: float, size: Vector2) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rotation_y
	add_child(root)
	_tag_node(root, _semantic_id("painting", pos, Vector3.ZERO, self), "painting", "assembly")
	_box_at(root, Vector3(size.x, size.y, 0.1), Vector3.ZERO, Color(0.42, 0.32, 0.18), false, false, "painting")
	_box_at(root, Vector3(size.x - 0.16, size.y - 0.16, 0.05), Vector3(0, 0, 0.07), Color(0.78, 0.66, 0.48), false, false, "painting")
	_box_at(root, Vector3(size.x * 0.5, size.y * 0.42, 0.03), Vector3(-0.1, 0.12, 0.1), Color(0.36, 0.42, 0.36), false, false, "painting")
	_box_at(root, Vector3(0.34, 0.06, 0.02), Vector3(size.x * 0.5 + 0.34, 0, 0.02), Color(0.3, 0.28, 0.26), false, false, "painting")

func _sign(pos: Vector3, rotation_y: float, size: Vector2, color: Color) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rotation_y
	add_child(root)
	_tag_node(root, _semantic_id("sign", pos, Vector3.ZERO, self), "sign", "assembly")
	_box_at(root, Vector3(size.x, size.y, 0.07), Vector3.ZERO, color, false, false, "sign")
	_box_at(root, Vector3(size.x - 0.24, 0.08, 0.04), Vector3(-0.06, 0.02, 0.05), Color(0.94, 0.93, 0.9), false, false, "sign")

func _info_panel(pos: Vector3, rotation_y: float, size: Vector2) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rotation_y
	add_child(root)
	_tag_node(root, _semantic_id("information_panel", pos, Vector3.ZERO, self), "information_panel", "assembly")
	_box_at(root, Vector3(size.x, size.y, 0.09), Vector3.ZERO, Color(0.24, 0.26, 0.28), false, false, "information_panel")
	_box_at(root, Vector3(size.x - 0.2, size.y - 0.2, 0.04), Vector3(0, 0, 0.06), Color(0.86, 0.84, 0.78), false, false, "information_panel")
	for i in range(4):
		_box_at(root, Vector3(size.x - 0.7, 0.07, 0.02), Vector3(0, size.y * 0.28 - float(i) * 0.22, 0.09), Color(0.45, 0.43, 0.4), false, false, "information_panel")

func _label_plate(pos: Vector3) -> void:
	_box(Vector3(0.34, 0.14, 0.03), pos + Vector3(0, 0, 0), Color(0.22, 0.21, 0.2), false, false, "label")

func _gift_table(pos: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rotation_y
	add_child(root)
	_tag_node(root, _semantic_id("gift_table", pos, Vector3.ZERO, self), "gift_table", "assembly")
	_box_at(root, Vector3(2.4, 0.12, 1.2), Vector3(0, FLOOR_TOP + 0.82, 0), Color(0.62, 0.57, 0.48), true, false, "gift_table")
	for dx in [-1.0, 1.0]:
		_box_at(root, Vector3(0.1, 0.82, 0.1), Vector3(dx, FLOOR_TOP + 0.41, 0), Color(0.4, 0.38, 0.34), false, false, "gift_table")
	var top := FLOOR_TOP + 0.88
	for i in range(8):
		var x := -0.85 + float(i % 4) * 0.56
		var z := -0.24 + float(i / 4) * 0.48
		_exhibit(root.to_global(Vector3(x, _rest("souvenir", top), z)), "souvenir", 420 + 90 * i, Color(0.86, 0.62, 0.36))

func _wall_head(pos: Vector3) -> void:
	_box(Vector3(0.22, 0.22, 0.7), pos + Vector3(-0.02, 0, 0), Color(0.5, 0.42, 0.3), false, false, "wall_specimen")
	_box(Vector3(0.5, 0.52, 0.44), pos + Vector3(0.3, 0, 0), Color(0.44, 0.35, 0.25), false, false, "wall_specimen")
	_box(Vector3(0.34, 0.24, 0.26), pos + Vector3(0.62, -0.08, 0), Color(0.36, 0.29, 0.2), false, false, "wall_specimen")
	for dz in [-0.15, 0.15]:
		_box(Vector3(0.12, 0.34, 0.1), pos + Vector3(0.18, 0.34, dz), Color(0.3, 0.25, 0.18), false, false, "wall_specimen")

func _exhibit(pos: Vector3, kind: String, value: int, color: Color = Color(0.9, 0.9, 0.88)) -> void:
	exhibit_spots.append({"id": _semantic_id("prop_" + kind, pos, Vector3.ZERO, self), "region": _region_id, "pos": pos, "kind": kind, "value": value, "color": color})

func _lights_hall() -> void:
	for pos in [Vector3(-3.4, HALL - 1.0, -2.0), Vector3(3.4, HALL - 1.0, -2.0), Vector3(-3.4, HALL - 1.0, 5.0), Vector3(3.4, HALL - 1.0, 5.0)]:
		_omni(pos, Color(1.0, 0.93, 0.82), 2.1, 16.0)
		_fixture(pos, 0.34)

func _lights_room(center: Vector3, height: float, count: int) -> void:
	for i in range(count):
		var angle := TAU * float(i) / float(maxi(count, 1))
		var pos := center + Vector3(cos(angle) * 2.6, height - 1.0, sin(angle) * 2.6)
		_omni(pos, Color(1.0, 0.92, 0.8), 1.5, 12.0)
		_fixture(pos, 0.26)

func _omni(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	_tag_node(light, _semantic_id("omni_light", pos, Vector3.ZERO, self), "omni_light", "light")
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	add_child(light)
	lights.append(light)

func _fixture(pos: Vector3, radius: float) -> void:
	var fixture := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius * 0.6
	disc.height = 0.1
	fixture.mesh = disc
	fixture.position = pos
	_tag_node(fixture, _semantic_id("light_fixture", pos, Vector3(radius * 2.0, 0.1, radius * 2.0), self), "light_fixture", "visual")
	fixture.material_override = _mat(Color(1.0, 0.96, 0.86), true)
	add_child(fixture)

func _spot(pos: Vector3, target: Vector3, energy: float, angle: float, shadows: bool) -> void:
	var spot := SpotLight3D.new()
	spot.position = pos
	_tag_node(spot, _semantic_id("spot_light", pos, target, self), "spot_light", "light")
	spot.light_energy = energy
	spot.spot_angle = angle
	spot.spot_range = pos.distance_to(target) * 1.4
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = shadows
	add_child(spot)
	# 垂直向下的灯和 UP 共线，换一个参考轴，否则朝向会抖动
	var dir := (target - pos).normalized()
	spot.look_at(target, Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP)

# ---------------- helpers ----------------

func _box(size: Vector3, pos: Vector3, color: Color, collider: bool, emissive: bool = false, role: String = "structure") -> void:
	_box_at(self, size, pos, color, collider, emissive, role)

func _box_at(parent: Node3D, size: Vector3, pos: Vector3, color: Color, collider: bool, emissive: bool = false, role: String = "structure") -> void:
	var semantic_id := _semantic_id(role, pos, size, parent)
	var mesh := MeshInstance3D.new()
	_tag_node(mesh, semantic_id, role, "visual")
	mesh.set_meta("native_size", size)
	mesh.set_meta("has_native_collision", collider)
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = _mat(color, emissive)
	parent.add_child(mesh)
	if collider:
		var body := StaticBody3D.new()
		_tag_node(body, semantic_id, role, "collision")
		body.set_meta("native_size", size)
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		body.position = pos
		parent.add_child(body)

func _mat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	return material

## Identity derives from authored native geometry, never node creation order or an asset path.
func _semantic_id(role: String, pos: Vector3, size: Vector3, parent: Node3D) -> String:
	var authored_transform := parent.global_transform * Transform3D(Basis.IDENTITY, pos)
	var fingerprint := (str(authored_transform) + "|" + str(size)).sha256_text().substr(0, 12)
	return "%s/%s/%s" % [_region_id, role, fingerprint]

func _tag_node(node: Node, semantic_id: String, role: String, component: String) -> void:
	node.name = component.capitalize() + "_" + role + "_" + semantic_id.get_slice("/", semantic_id.get_slice_count("/") - 1)
	node.set_meta("semantic_id", semantic_id)
	node.set_meta("semantic_role", role)
	node.set_meta("region_id", _region_id)
	node.set_meta("semantic_component", component)
	if component == "visual":
		node.set_meta("greybox_visual", true)
