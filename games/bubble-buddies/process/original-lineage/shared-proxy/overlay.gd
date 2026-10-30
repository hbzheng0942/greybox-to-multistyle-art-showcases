extends Node3D
## Deliberately small procedural S6 massing. Never writes model, physics or legacy Visual.
const V = preload("res://shared/greybox/salon_visuals.gd")
var main
var profile: Dictionary
var staff: Array[Node3D] = []
var pets: Dictionary = {}
var towels: Dictionary = {}
var reunions: Dictionary = {}
var stations: Dictionary = {}
var reset_count := 0
var materials: Dictionary = {}
var contract: Dictionary
var cutaway_candidates: Dictionary = {}
var permanent_cutaway_rids: Array[RID] = []
var active_occluder_count := 0
var cutaway_outlines: Dictionary = {}

func _ready() -> void:
	name = "S6Presentation"
	process_priority = 50
	contract = JSON.parse_string(FileAccess.get_file_as_string("res://process/original-lineage/spatial-contract-v2.json"))
	_hide_static_legacy(main)
	_build_environment()
	for pid in range(2):
		staff.append(_staff(pid))
	var owner := _staff(2)
	owner.name = "WaitingOwnerProxy"
	owner.position = Vector3(8.2, 0, 1.35)
	owner.rotation.y = -PI / 2
	owner.scale = Vector3.ONE * .92
	for child in main.waiting_owner.get_children():
		if child is GeometryInstance3D:
			child.hide()
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var badge := Label.new()
	badge.text = "%s · %s  |  S6 可玩体块代理 · 非正式美术" % [profile.style_id, profile.name]
	badge.add_theme_font_override("font", V.ui_font())
	badge.add_theme_font_size_override("font_size", 18)
	badge.position = Vector2(18, 145)
	badge.add_theme_color_override("font_color", Color("fff1be"))
	badge.add_theme_color_override("font_shadow_color", Color("20353e"))
	badge.add_theme_constant_override("shadow_offset_x", 1)
	badge.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(badge)
	_sync()

func _hide_static_legacy(node: Node) -> void:
	for child in node.get_children():
		if child == self:
			continue
		if child is MeshInstance3D:
			var path := str(child.get_path())
			if "Highlight" not in path and "/Bubbles/" not in path and "/ReadyMarker/" not in path and not str(child.name).begins_with("AccessMark"):
				child.hide()
		_hide_static_legacy(child)

func _mat(hex: String) -> StandardMaterial3D:
	if materials.has(hex):
		return materials[hex]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 1.0
	if profile.shape in ["paper", "cel", "block"]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[hex] = m
	return m

func _box(parent: Node3D, title: String, pos: Vector3, size: Vector3, hex: String) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = title
	var b := BoxMesh.new()
	b.size = size
	n.mesh = b
	n.material_override = _mat(hex)
	parent.add_child(n)
	n.position = pos
	return n

func _form(parent: Node3D, title: String, pos: Vector3, size: Vector3, hex: String) -> MeshInstance3D:
	if profile.shape == "block":
		return _box(parent, title, pos, size, hex)
	var n := MeshInstance3D.new()
	n.name = title
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1.0
	sphere.radial_segments = 6 if profile.shape == "faceted" else (8 if profile.shape == "paper" else 16)
	sphere.rings = 2 if profile.shape == "faceted" else 5
	n.mesh = sphere
	n.scale = size
	if profile.shape == "paper":
		n.scale.z *= .64
	n.material_override = _mat(hex)
	parent.add_child(n)
	n.position = pos
	return n

func _node(parent: Node3D, title: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = title
	parent.add_child(n)
	n.position = pos
	return n

func _build_environment() -> void:
	# Render exact collision shell; no new collision objects exist in this overlay.
	for node in main.get_children():
		if node is StaticBody3D and not main.station_bodies.values().has(node):
			var cs: CollisionShape3D
			for child in node.get_children():
				if child is CollisionShape3D:
					cs = child
			if cs == null:
				continue
			if node.name == "RightWall":
				continue
			var color: String = profile.wall
			if node.name == "Floor": color = profile.wet
			var visual := _box(self, "Shell_" + str(node.name), node.position, cs.shape.size, color)
			if is_equal_approx(node.position.x,0) and is_equal_approx(node.position.y,1.3) and is_equal_approx(cs.shape.size.x,.24):
				visual.material_override = visual.material_override.duplicate()
				cutaway_candidates[node.get_instance_id()] = visual
				var outline := _node(self,"WallBoundaryOutline",node.position)
				var extent: Vector3 = cs.shape.size
				var ink := Color(profile.wall).darkened(.35).to_html(false)
				for side in [-1,1]:
					_box(outline,"Upright",Vector3(0,0,side*extent.z*.5),Vector3(.025,extent.y,.025),ink)
					_box(outline,"Rail",Vector3(0,side*extent.y*.5,0),Vector3(.27,.025,extent.z),ink)
				outline.hide()
				cutaway_outlines[node.get_instance_id()] = outline
			if is_equal_approx(node.position.y,2.275) and is_equal_approx(cs.shape.size.y,.65):
				var m: StandardMaterial3D = visual.material_override.duplicate()
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color.a = .20
				visual.material_override = m
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				permanent_cutaway_rids.append(node.get_rid())
	_box(self, "WetSurface", Vector3(-3.2,.014,0), Vector3(6.3,.02,9.6), profile.wet)
	_box(self, "DrySurface", Vector3(3.2,.015,0), Vector3(6.3,.02,9.6), profile.dry)
	_box(self, "PickupCourt", Vector3(8,-.17,0), Vector3(2.4,.32,9.8), profile.dry)
	_box(self, "BenchSeat", Vector3(8.15,.35,-.45), Vector3(1.45,.16,.75), profile.shell)
	_box(self, "BenchBack", Vector3(8.15,.65,-.77), Vector3(1.45,.62,.13), profile.shell)
	_box(self, "RightWallBack", Vector3(6.65,.35,-1.8), Vector3(.3,.7,6.4), profile.wall)
	_box(self, "RightWallFront", Vector3(6.65,.35,4.2), Vector3(.3,.7,1.6), profile.wall)
	_box(self, "PetGate", Vector3(6.65,.22,2.4), Vector3(.16,.44,2), profile.accent)
	# Sparse seams keep broad floor readable; D10 uses straight square cells.
	for x in range(-6, 7):
		_box(self,"FloorSeam",Vector3(x,.027,0),Vector3(.012,.005,9.6),profile.wet if x>0 else profile.dry)
	for z in range(-4,5):
		_box(self,"FloorSeam",Vector3(0,.028,z),Vector3(13,.005,.012),profile.wet if z%2==0 else profile.dry)
	for s in contract.stations.items:
		var p := Vector3(s.position[0], s.position[1], s.position[2])
		var size := Vector3(s.size_xyz[0],s.size_xyz[1],s.size_xyz[2])
		var root := _node(self, "station_" + s.id, p)
		root.set_meta("logical_id", s.id)
		stations[s.id] = root
		_box(root,"FixedShell",Vector3(0,.32,0),size,profile.shell)
		_box(root,"WorkSurface",Vector3(0,.67,0),Vector3(size.x+.06,.10,size.z+.06),profile.dry)
		_box(root,"FrontInset",Vector3(0,.33,size.z*.5+.006),Vector3(size.x*.78,.39,.016),profile.accent)
		if profile.shape == "paper":
			for y in [.18,.26,.34,.42,.50]:
				_box(root,"CardboardEdge",Vector3(0,y,size.z*.5+.017),Vector3(size.x*.8,.014,.008),profile.shell)
		elif profile.shape == "cel":
			for side in [-1,1]:
				_box(root,"InkEdge",Vector3(side*size.x*.5,.34,size.z*.5+.012),Vector3(.025,.6,.025),"39414b")
		elif profile.shape == "faceted":
			var inset := _box(root,"SlantPanel",Vector3(0,.32,size.z*.5+.018),Vector3(size.x*.46,.22,.024),profile.dry)
			inset.rotation.z = .07
		elif profile.shape == "block":
			for i in 4:
				_box(root,"PixelPanel",Vector3(-size.x*.3+i*size.x*.2,.39,size.z*.5+.017),Vector3(size.x*.16,.13,.02),profile.dry)
		if s.id.begins_with("wash"):
			_box(root,"Water",Vector3(0,.73,0),Vector3(1.08,.02,1.0),"8bd8de")
			_box(root,"TapVertical",Vector3(-.48,1,-.48),Vector3(.09,.56,.09),profile.accent)
			_box(root,"TapElbow",Vector3(-.30,1.26,-.48),Vector3(.42,.09,.09),profile.accent)
		elif s.id == "dryer":
			_box(root,"BackVent",Vector3(0,1.07,-.67),Vector3(1.7,.7,.20),profile.accent)
			for i in 5: _box(root,"Vent",Vector3(-.5+i*.25,1.08,-.55),Vector3(.08,.32,.025),profile.wall)
		elif s.id == "brush" or s.id.begins_with("buffer"):
			_box(root,"FlatDryPad",Vector3(0,.735,0),Vector3(size.x*.78,.03,size.z*.76),profile.accent)
		elif s.id == "laundry":
			_form(root,"LaundryDoor",Vector3(0,.38,.74),Vector3(.63,.48,.04),"455968")
			_form(root,"LaundryGlass",Vector3(0,.38,.77),Vector3(.42,.32,.025),"9ac5c5")
		elif s.id == "treatment":
			for side in [-1,1]: _box(root,"OpenHoodPost",Vector3(side*.5,1.04,-.46),Vector3(.06,.68,.06),profile.accent)
			_box(root,"OpenHoodTop",Vector3(0,1.40,-.46),Vector3(1.06,.08,.12),profile.accent)
		elif s.id == "paws":
			for side in [-1,0,1]: _form(root,"PawPad",Vector3(side*.2,.74,-.1),Vector3(.16,.025,.2),profile.accent)
		_node(root,"InventoryAnchor",Vector3(0,.75,0))
		_node(root,"FXAnchor",Vector3(0,1.15,0))
	# Environment lighting stays at greybox calibration for comparable proxies.

func _staff(pid: int) -> Node3D:
	var root := _node(self,"StaffProxy%d"%pid)
	var rig := _node(root,"Pose")
	var ring := MeshInstance3D.new()
	ring.name = "IdentityMarker"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = .31
	ring_mesh.outer_radius = .36
	ring_mesh.rings = 12
	ring_mesh.ring_segments = 4
	ring.mesh = ring_mesh
	ring.material_override = _mat(profile.staff[pid%2])
	root.add_child(ring)
	ring.position.y = .03
	var shade: String = profile.staff[pid%2]
	var skin := "f0ccab"
	if profile.shape == "paper": skin = "bd7540" if pid==0 else "ddd1b6"
	_form(rig,"Torso",Vector3(0,.64,0),Vector3(profile.staff_body_width,.52,.30),shade)
	_box(rig,"Apron",Vector3(0,.59,-.17),Vector3(.32,.38,.025),profile.dry)
	_form(rig,"Head",Vector3(0,1.05,0),Vector3(.46,.42,.36),skin)
	if profile.shape == "paper":
		for side in [-1,1]:
			var ear := _form(rig,"Ear",Vector3(side*.16,1.35,0),Vector3(.14,.38 if pid==1 else .24,.12),skin)
			ear.rotation.z = -side*.22
		_form(rig,"Muzzle",Vector3(0,1.01,-.22),Vector3(.25,.15,.18),profile.dry)
	else:
		_form(rig,"Hat",Vector3(0,1.29,0),Vector3(.5,.18,.4),shade)
	for side in [-1,1]:
		_form(rig,"Eye%d"%side,Vector3(side*.10,1.09,-.181),Vector3(.07,.09,.025),"293943")
		var leg := _node(rig,"Leg%d"%side,Vector3(side*.14,.35,0))
		_box(leg,"Boot",Vector3(0,-.19,-.04),Vector3(.17,.30,.24),"485264")
		_form(rig,"Hand%d"%side,Vector3(side*.3,.67,-.10),Vector3(.15,.16,.15),skin)
		_node(rig,"HandContact%d"%side,Vector3(side*.23,1.04,-.58))
	_node(rig,"CarryPet",Vector3(0,.9,-.58))
	_node(rig,"CarryTowel",Vector3(0,.91,-.55))
	return root

func _pet(id: int, parent: Node3D = self) -> Node3D:
	var root := _node(parent,"PetProxy%d"%id)
	root.set_meta("logical_id",id)
	var coat: String = profile.pet[posmod(id,3)]
	var rig := _node(root,"Pose")
	_form(rig,"Body",Vector3(0,.24,.05),Vector3(.48,.40,.56),coat)
	_form(rig,"Head",Vector3(0,.47,-.22),Vector3(.41,.36,.34),coat)
	_form(rig,"Muzzle",Vector3(0,.39,-.39),Vector3(.24,.15,.14),profile.dry)
	for side in [-1,1]:
		_form(rig,"Eye%d"%side,Vector3(side*.10,.51,-.38),Vector3(.08,.09,.025),"273c45")
		_form(rig,"Ear%d"%side,Vector3(side*.23,.49,-.19),Vector3(.12,.25,.15),coat)
		for z in [-.18,.24]:
			_form(rig,"Paw",Vector3(side*.17,.045,z),Vector3(.15,.15,.17),profile.dry)
	_form(rig,"Tail",Vector3(0,.31,.39),Vector3(.10,.28,.10),coat)
	var ribbon := _node(rig,"Ribbon")
	for side in [-1,1]: _form(ribbon,"Bow",Vector3(side*.09,.24,-.26),Vector3(.17,.11,.06),profile.accent)
	var paws := _node(rig,"PawBadge")
	_box(paws,"Badge",Vector3(0,.14,-.30),Vector3(.20,.09,.035),"f4c4d5")
	var dirt := _node(rig,"Dirt")
	for i in 3: _form(dirt,"Spot",Vector3(-.15+i*.15,.445,.1),Vector3(.11,.025,.13),"79604c")
	var foam := _node(rig,"Foam")
	for i in 4: _form(foam,"Bubble",Vector3(sin(i*2.3)*.18,.43,cos(i*2.3)*.2),Vector3.ONE*.14,"d9f4ef")
	var drops := _node(rig,"WetDrops")
	for side in [-1,1]: _form(drops,"Drop",Vector3(side*.26,.20,0),Vector3(.05,.11,.05),"58bacb")
	var frizz := _node(rig,"Frizz")
	for i in 6: _form(frizz,"Tuft",Vector3(sin(i)*.22,.3,cos(i)*.25),Vector3.ONE*.20,coat)
	var crooked := _node(rig,"Crooked")
	var fringe := _form(crooked,"SideTuft",Vector3(.08,.64,-.25),Vector3(.22,.16,.12),profile.accent)
	fringe.rotation.z = -.45
	for cue in ["Fleas","Alert","PawSparkles","TrimTuft","RepairSparkles"]:
		var cue_root := _node(rig,cue)
		var cue_color := "eea44c" if cue in ["Fleas","Alert"] else "f6e6ab"
		for i in 3:
			_box(cue_root,"Cue%d"%i,Vector3(-.2+i*.2,.76+(i%2)*.06,.08),Vector3(.045,.11,.045),cue_color)
		cue_root.hide()
	_node(rig,"WrapAnchor",Vector3(0,.24,.05))
	_node(rig,"SupportContact",Vector3(0,-.03,0))
	return root

func _update_pet(root: Node3D, state: Dictionary, clock: float) -> void:
	var rig := root.get_node("Pose")
	rig.get_node("Ribbon").visible = state.get("brushed",false)
	rig.get_node("PawBadge").visible = state.get("paws_done",false)
	rig.get_node("Dirt").visible = state.get("stage", "dry") == "dirty"
	rig.get_node("Foam").visible = state.get("stage", "dry") == "dirty" and state.get("wash",0.0)>.03
	rig.get_node("WetDrops").visible = state.get("stage", "dry") == "wet"
	rig.get_node("Frizz").visible = state.get("frizzy",false)
	rig.get_node("Crooked").visible = state.get("crooked",false)
	rig.get_node("Tail").rotation.z = sin(clock*8+int(root.get_meta("logical_id",0)))*.35
	# Support feet remain on a surface; only loose pets get a locomotion bounce.
	rig.position.y = absf(sin(clock*16))*.06 if state.get("location", "") == "loose" else 0.0

func _towel(id: int) -> Node3D:
	var root := _node(self,"TowelProxy%d"%id)
	root.set_meta("logical_id",id)
	var fold := _node(root,"Folded")
	_box(fold,"Fabric",Vector3(0,profile.towel_fold_center_local_y,0),Vector3(.56,.12,.38),profile.dry)
	_box(fold,"Stripe",Vector3(.12,profile.towel_fold_center_local_y+.061,0),Vector3(.05,.01,.38),profile.accent)
	var wrap := _node(root,"Wrapped")
	for side in [-1,1]: _box(wrap,"Side",Vector3(side*.25,.23,.05),Vector3(.07,.34,.49),profile.dry)
	_box(wrap,"Back",Vector3(0,.42,.05),Vector3(.56,.055,.49),profile.dry)
	_box(wrap,"Stripe",Vector3(.10,.451,.05),Vector3(.05,.012,.49),profile.accent)
	return root

func reset_dynamic() -> void:
	reset_count += 1
	for collection in [pets,towels,reunions]:
		for n in collection.values():
			if is_instance_valid(n):
				n.hide()
				n.queue_free()
		collection.clear()

func _process(_delta: float) -> void:
	if not main.paused:
		_sync()

func _sync() -> void:
	var clock: float = main.animation_time
	for pid in range(2):
		var old: Node3D = main.players[pid].get_node("Visual")
		old.hide()
		var root: Node3D = staff[pid]
		root.position = main.players[pid].position
		root.rotation.y = old.rotation.y
		root.scale = Vector3(float(profile.staff_body_width)/.48,float(profile.staff_height)/(1.54 if profile.shape=="paper" else 1.38),1)
		var rig := root.get_node("Pose")
		root.get_node("IdentityMarker").scale = Vector3.ONE * (1.18 if main.duo_mode or main.active_player==pid else .88)
		var carrying: bool = main.model.held_item(pid).kind != "none"
		for side in [-1,1]:
			var hand := rig.get_node("Hand%d"%side)
			var is_towel: bool = main.model.held_item(pid).kind == "towel"
			var target := Vector3(side*.22,.91,-.55) if is_towel else Vector3(side*.23,1.04,-.58)
			hand.position = target if carrying else Vector3(side*.3,.67,-.1)
			if main.care_working[pid]:
				hand.position += Vector3(0,.15,-.28+sin(clock*15+side)*.04)
			var leg := rig.get_node("Leg%d"%side)
			leg.rotation.x = sin(main.stride_distance[pid]/main.STEP_DISTANCE*PI)*side*.45*main.gait_amount[pid]
			if not carrying and not main.care_working[pid]: hand.position.z += sin(main.stride_distance[pid]*4)*side*.1*main.gait_amount[pid]
	for id in pets.keys():
		if not main.model.pets.has(id):
			pets[id].queue_free()
			pets.erase(id)
	for id in main.model.pets:
		if not pets.has(id): pets[id] = _pet(id)
		var state: Dictionary = main.model.pets[id]
		var old: Node3D = main.pet_views.get(id)
		if not is_instance_valid(old): continue
		old.get_node("Visual").hide()
		var root: Node3D = pets[id]
		root.position = old.position
		root.rotation = Vector3(0,old.get_node("Visual").rotation.y,0)
		root.scale = Vector3(float(profile.pet_width)/.58,float(profile.pet_height)/.70,float(profile.pet_depth)/.79)
		_update_pet(root,state,clock)
		for cue in ["Fleas","Alert","PawSparkles","TrimTuft","RepairSparkles"]:
			var cue_root := root.get_node("Pose/"+cue)
			cue_root.visible = old.get_node("Visual/"+cue).visible
			cue_root.position.y = sin(clock*12)*.025
		root.get_node("Pose").rotation.z = old.get_node("Visual").rotation.z*.5
	_update_window_visibility()
	var laundry_index := 0
	for id in main.model.towels:
		if not towels.has(id): towels[id] = _towel(id)
		if main.towel_views.has(id): main.towel_views[id].hide()
		var state: Dictionary = main.model.towels[id]
		var loc: String = state.location
		var n: Node3D = towels[id]
		n.transform = Transform3D.IDENTITY
		var wrapped := loc.begins_with("pet:")
		n.get_node("Folded").visible = not wrapped
		n.get_node("Wrapped").visible = wrapped
		n.visible = true
		if wrapped:
			var pet_id := int(loc.get_slice(":",1))
			if pets.has(pet_id): n.transform = pets[pet_id].transform
			else: n.hide()
		elif loc in ["p0","p1"]:
			var pid := int(loc.right(1))
			n.position = main.players[pid].position + main._visual_facing(pid)*.55+Vector3(0,.91,0)
			n.rotation.y = main.players[pid].get_node("Visual").rotation.y
		elif main.station_positions.has(loc):
			n.position = main.station_positions[loc]+Vector3(0,.82,0)
			if loc == "laundry":
				n.position.y += laundry_index*.16
				laundry_index += 1
		if state.state == "washing": n.rotation.z = sin(clock*14)*.045
		var color: String = "70b5c3" if state.state in ["wet","washing"] else profile.dry
		for mesh in n.find_children("*","MeshInstance3D",true,false):
			if mesh.name != "Stripe": mesh.material_override = _mat(color)
	var alive: Array = []
	for item in main.reunion_pets:
		var old: Node3D = item.node
		var iid := old.get_instance_id()
		alive.append(iid)
		old.get_node("Visual").hide()
		if not reunions.has(iid): reunions[iid] = _pet(int(item.get("pet_id",0)))
		var n: Node3D = reunions[iid]
		n.position = old.position
		n.rotation.y = old.get_node("Visual").rotation.y
		_update_pet(n,item.get("appearance_snapshot",item.quality),clock)
	for id in reunions.keys():
		if id not in alive:
			reunions[id].queue_free()
			reunions.erase(id)

func _update_window_visibility() -> void:
	# Current camera rays decide presentation alpha only. Source physics remains untouched.
	var blockers: Dictionary = {}
	var exclusions: Array[RID] = permanent_cutaway_rids.duplicate()
	for body in main.station_bodies.values(): exclusions.append(body.get_rid())
	for body in main.players: exclusions.append(body.get_rid())
	for id in main.model.pets:
		var state: Dictionary = main.model.pets[id]
		if not String(state.location).begins_with("bench") or not pets.has(id): continue
		var target: Vector3 = pets[id].global_position + Vector3(0,.35,0)
		var screen: Vector2 = main.camera.unproject_position(target)
		var origin: Vector3 = main.camera.project_ray_origin(screen)
		var query := PhysicsRayQueryParameters3D.create(origin,target,5)
		query.exclude = exclusions
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and cutaway_candidates.has(hit.collider.get_instance_id()):
			blockers[hit.collider.get_instance_id()] = true
	active_occluder_count = blockers.size()
	for id in cutaway_candidates:
		cutaway_outlines[id].visible = blockers.has(id)
		var mesh: MeshInstance3D = cutaway_candidates[id]
		var mat: StandardMaterial3D = mesh.material_override
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if blockers.has(id) else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = .12 if blockers.has(id) else 1.0
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if blockers.has(id) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
