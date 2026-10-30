extends "res://../art/train-parkour/shared/tools/scene_finish_world.gd"
## Art-directed receiving zones and branch-aware cargo islands. Frozen gameplay stays authoritative.
const FINISHED = preload("res://../art/train-parkour/shared/tools/reconstruction_surface.gdshader")
const Nearfield = preload("res://../art/train-parkour/shared/tools/reconstruction_nearfield.gd")
const Batcher = preload("res://../art/train-parkour/shared/tools/reconstruction_batcher.gd")
const DESIGN_PATH := "res://../art/train-parkour/styles/odd-logistics/runtime/reconstruction-layout.json"
var design:Dictionary={}
var new_materials:Dictionary={}
var spatial_groups:Array=[]
var route_cells:Dictionary={}
var indexed_sample_count:=-1
const ROUTE_CELL:=32.0

func build_style(session:Node3D,style_id:String) -> Node3D:
	var world:=super.build_style(session,style_id)
	var report:Dictionary=world.get_meta("scene_rebuild_report")
	report.batching=world.get_meta("reconstruction_batching",{})
	world.set_meta("scene_rebuild_report",report)
	return world

func _route_clear(box:AABB,pose:Transform3D,margin:=6.8) -> bool:
	# Broad phase only: retain the original local-space point containment test.
	if indexed_sample_count!=protected_samples.size():
		route_cells.clear()
		for point:Vector3 in protected_samples:
			var cell:=Vector3i((point/ROUTE_CELL).floor())
			if not route_cells.has(cell):route_cells[cell]=[]
			route_cells[cell].append(point)
		indexed_sample_count=protected_samples.size()
	var inv:=pose.affine_inverse()
	var expanded:=box.grow(margin/pose.basis.x.length())
	# Padding absorbs float roundoff in transformed broad bounds; it does not
	# alter the narrow-phase margin or the max-exclusive has_point semantics.
	var broad:AABB=(pose*expanded).grow(0.01)
	var first:=Vector3i((broad.position/ROUTE_CELL).floor())
	var last:=Vector3i((broad.end/ROUTE_CELL).floor())
	var span:=last-first+Vector3i.ONE
	if span.x*span.y*span.z>protected_samples.size():
		for point:Vector3 in protected_samples:
			if expanded.has_point(inv*point):return false
		return true
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for z in range(first.z,last.z+1):
				for point:Vector3 in route_cells.get(Vector3i(x,y,z),[]):
					if expanded.has_point(inv*point):return false
	return true

func _apply_sample(world:Node3D,config:Dictionary) -> void:
	design=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	super._apply_sample(world,config)
	world.set_meta("reconstruction_design",{"groups":spatial_groups,"source":DESIGN_PATH,"accepted":false,"physical_changes":0})

func _mat(color:String,floor_surface:=false,metal:=0.1) -> Material:
	var key:=color+str(floor_surface)+str(metal)
	if new_materials.has(key):return new_materials[key]
	var mat:=ShaderMaterial.new()
	mat.shader=FINISHED
	mat.set_shader_parameter("base_color",Color(color))
	mat.set_shader_parameter("floor_surface",floor_surface)
	mat.set_shader_parameter("metalness",metal)
	mat.set_shader_parameter("striped",color=="b49a45")
	if color in ["a68a51","b99c60","8e7548","b49b6a","927c4d"]:
		if cardboard_texture==null:
			var source:=Image.load_from_file(ProjectSettings.globalize_path(CARDBOARD_PATH))
			source.generate_mipmaps()
			cardboard_texture=ImageTexture.create_from_image(source)
		mat.set_shader_parameter("cardboard_tex",cardboard_texture)
		mat.set_shader_parameter("textured_cardboard",true)
	new_materials[key]=mat
	return mat

func _pier(pose:Transform3D,height:float,space:String) -> void:
	_solid(Vector3(1.5,height,1.7),_at(pose,Vector3(0,height*.5,0)),"9b9580",space,"warehouse_pier")
	_solid(Vector3(1.8,3.5,1.9),_at(pose,Vector3(0,1.75,0)),"b49a45",space,"pier_protection")
	_solid(Vector3(2.2,.28,2.3),_at(pose,Vector3(0,.12,0)),"4a4e43",space,"pier_baseplate")

func _small_cargo(pose:Transform3D,variant:int,space:String) -> void:
	if posmod(variant,4)==0:
		_model(SAGGING,pose,1.5,space,"cloth_freight")
	elif posmod(variant,4)==1:
		_model(FREIGHT,pose,1.1,space,"strapped_freight")
	else:
		_crate(pose,Vector3(2.1,1.8+float(posmod(variant,3))*.38,2.2),variant,space)
		if posmod(variant,3)==0:_crate(_at(pose,Vector3(.12,2.1,.06)),Vector3(1.7,1.3,1.8),variant+1,space)

func _crate(pose:Transform3D,size:Vector3,variant:int,space:String) -> void:
	# Authored distant cartons stay low-poly. Soft G1 parcels are placed explicitly at focal work areas.
	var colors:=["a68a51","b99c60","8e7548","b49b6a","927c4d"]
	var body:=_solid(size,_at(pose,Vector3(0,size.y*.5,0)),colors[posmod(variant,5)],space,"paper_freight")
	if body==null:return
	(body as MeshInstance3D).mesh=_chamfered_box(size)
	_solid(Vector3(size.x*.06,size.y+.025,size.z+.035),_at(pose,Vector3(size.x*.16,size.y*.5,0)),"665c43",space,"packing_tape")
	if posmod(variant,3)==0:
		_solid(Vector3(size.x*.24,size.y*.18,.03),_at(pose,Vector3(-size.x*.17,size.y*.67,-size.z*.5-.02)),"cbc29d",space,"shipping_label")

func _build_station(track_id:String) -> void:
	var length:float=rebuild_route.tracks[track_id].length
	# Continuous spatial shell; actual work-zone contents are authored separately below.
	for i in range(ceili(length/28.0)):
		var span:=minf(28,length-i*28.0)
		var s:=i*28.0+span*.5
		var pose:=_pose(track_id,s)
		var flat:=Transform3D(_flat(pose),pose.origin)
		var deck:=_unbanked(pose)
		var room:=int(s/112.0)
		var height:=22.0+(2.0 if room%3==1 else 0.0)
		for side:float in [-1.0,1.0]:
			_solid(Vector3(25,1.4,span+1.4),_at(deck,Vector3(side*20.8,-.8,0)),"89836e","N01","receiving_floor",true)
			_pier(_at(flat,Vector3(side*14.8,-.1,0)),height,"N01")
			_solid(Vector3(1.2,height,span+1.5),_at(flat,Vector3(side*33,height*.5,0)),"777a68","N01","warehouse_wall")
			_solid(Vector3(.4,1.0,span+1.5),_at(flat,Vector3(side*14.8,height-.7,0)),"4c5146","N01","roof_longitudinal_beam")
		_solid(Vector3(68,.6,span+2),_at(flat,Vector3(0,height+.3,0)),"464c42","N01","warehouse_roof")
		_solid(Vector3(31,1.25,.9),_at(flat,Vector3(0,height-.65,0)),"555c4d","N01","portal_header")
		# An overhead conveyor is tied to the receiving piers, with small individual parcels.
		if true:
			_solid(Vector3(4.1,.48,span+.3),_at(flat,Vector3(-17.4,7.4,0)),"4a5146","N01","conveyor_spine")
			for x:float in [-19.4,-15.4]:_solid(Vector3(.22,.4,span+.3),_at(flat,Vector3(x,7.8,0)),"727b68","N01","conveyor_edge")
			_beam(flat*Vector3(-14.8,4.5,0),flat*Vector3(-19.3,7.15,0),.30,"565c50","N01","conveyor_diagonal")
			for z:float in [-8,2,9]:_small_cargo(_at(flat,Vector3(-17.4,7.67,z)),i+int(z),"N01")
		if i%2==0:
			_worklight(_at(flat,Vector3(-3 if room%2==0 else 6,height-1.6,0)),"N01",i)
	# Discrete zones: receiving, stock, open cross-aisle. Rack rhythm is independent of roof bays.
	for i in range(ceili(length/17.0)):
		var s:=14.0+i*17.0
		if s>length-5:continue
		var pose:=_pose(track_id,s)
		var flat:=Transform3D(_flat(pose),pose.origin)
		var zone:=int(s/104.0)
		var right_face:=Basis.looking_at(-flat.basis.x,Vector3.UP)
		var left_face:=Basis.looking_at(flat.basis.x,Vector3.UP)
		var gap:=fmod(s+21.0,104.0)>92.0
		if not gap:
			var base:=_at(flat,Vector3(21.6+(3.0 if zone%3==1 else 0.0),0,0))
			_model(LOADED,Transform3D(right_face,base.origin),.62,"N01","stock_shelf_lower")
			if zone%3!=1:
				_model(LOADED,Transform3D(right_face,base.origin+Vector3.UP*6.41),.62,"N01","stock_shelf_upper")
				_model(LOADED,Transform3D(right_face,base.origin+Vector3.UP*12.82),.62,"N01","stock_shelf_crown")
			# Fill part of the open shelf fronts with human-scale cartons, retaining visible frame and access.
			for y:float in [0,3.2,6.45,9.65,12.9]:
				for z:float in [-4.2,-1.3,1.6,4.5]:
					if posmod(i+int(z)+int(y),5)==1:continue
					_crate(_at(flat,Vector3(18.6,y,z)),Vector3(1.6,2.3,2.55),i+int(y)+int(z),"N01")
		elif i%2==0:
			_model(CART,_at(flat,Vector3(13.2,0,0)),1.1,"N01","staged_cage_cart")
		if i%3==0:
			var dock:=_at(flat,Vector3(-24,0,0))
			_model(RECEIVING,Transform3D(left_face,dock.origin),.65,"N01","recessed_loading_dock")
			for j in range(3):
				for z:float in [-3.5,3.5]:
					var camera_exit_shift:=.65 if track_id=="station_carve" and s>length-70 else 0.0
					_small_cargo(_at(flat,Vector3(-12.4-float(j)*3.0-camera_exit_shift,0,z)),i+j+int(z),"N01")
		if gap:
			for side:float in [-1.0,1.0]:
				for j in range(3):_solid(Vector3(7,.025,.35),_at(_unbanked(pose),Vector3(side*12.7,-.08,float(j)*1.1-1.1)),"b6a158","N01","loading_zone_mark",true)
	spatial_groups.append({"space":"N01","track":track_id,"length":length,"roof_height":22,"work_zones":104,"normalized_rack_scale":.62})

func _cargo_tower(pose:Transform3D,top:float,variant:int,distant:bool) -> void:
	var floor_y:=16.0
	var height:=top-floor_y
	pose.origin.y=floor_y
	var width:=13.4
	var depth:=18.0
	var whole:=AABB(Vector3(-width*.5,0,-depth*.5),Vector3(width,height,depth))
	if not _route_clear(whole,pose,9.0):
		rejected_parts.append({"role":"authored_tower_group","position":array(pose.origin),"reason":"Whole tower rejected at designed position; no automatic drift"})
		return
	_solid(Vector3(width+1.3,1.8,depth+1),_at(pose,Vector3(0,-.9,0)),"575f53","N02","tower_foundation")
	for x:float in [-6.6,6.6]:
		for z:float in [-8.8,8.8]:
			_solid(Vector3(.65,height,.8),_at(pose,Vector3(x,height*.5,z)),"555e4f","N02","tower_steel_column")
	# A coherent tower core gives the deep levels volume. Real loaded shelves dress view-relevant levels.
	_solid(Vector3(width-.8,height,1.0),_at(pose,Vector3(0,height*.5,1.7)),"555c4d","N02","tower_rear_wall")
	var level_height:=6.45
	for level in range(int(height/level_height)):
		var y:=float(level)*level_height
		var tier:=_at(pose,Vector3(0,y,0))
		_solid(Vector3(width,.35,depth),_at(tier,Vector3(0,-.18,0)),"665e47","N02","tower_shelf")
		_solid(Vector3(width+.2,.5,.45),_at(tier,Vector3(0,.12,-8.9)),"97573e","N02","tower_crossmember")
		if not distant and y>48 and y<118 and posmod(level+variant,2)==0:
			_model(LOADED,_at(tier,Vector3(0,0,-5.9)),.62,"N02","carton_rack_tier")
		else:
			# Lower/far storage uses bounded cargo masses, with distinct supports and gaps.
			for j in range(4):
				var x:float=-4.7+float(j)*3.1
				var h:float=3.2+float(posmod(j+level+variant,3))*.65
				_crate(_at(tier,Vector3(x,0,-5.9)),Vector3(2.8,h,5.0),variant+level+j,"N02")
		# Packed end faces give the island volume from the route's forward view, rather than a thin facade.
		for z:float in [-5.8,.1,6.0]:
			_crate(_at(tier,Vector3(-4.4,0,z)),Vector3(3.8,4.4+float(posmod(level+variant,2))*.7,5.1),variant+level+int(z),"N02")
			_crate(_at(tier,Vector3(4.4,0,z)),Vector3(3.8,4.0+float(posmod(level+variant+1,3))*.6,5.1),variant+level+int(z)+1,"N02")
		for x:float in [-6.6,6.6]:_solid(Vector3(.38,.5,18),_at(tier,Vector3(x,.12,0)),"97573e","N02","tower_end_crossmember")
		if not distant and posmod(level+variant,7)==0 and y>55 and y<120:
			var balcony:=_at(tier,Vector3(0,0,-10.2))
			_solid(Vector3(11,.45,3.4),balcony,"656852","N02","loading_balcony")
			for x:float in [-5.2,5.2]:
				_solid(Vector3(.15,1.7,3.2),_at(balcony,Vector3(x,1.05,0)),"af9142","N02","balcony_end_guard")
			_worklight(_at(tier,Vector3(-4.7,4.5,-9.5)),"N02",variant+level,true)
			_small_cargo(_at(balcony,Vector3(2,.25,0)),variant+level,"N02")
	_solid(Vector3(width+1,.7,depth+1),_at(pose,Vector3(0,height+.35,0)),"5b6252","N02","tower_top_deck")
	if not distant:
		for x:float in [-3.5,2.2]:_small_cargo(_at(pose,Vector3(x,height+.7,0)),variant+int(x),"N02")

func _build_canyon() -> void:
	for i in range(design.canyon_groups.size()):
		var group:Dictionary=design.canyon_groups[i]
		var p:=_pose("canyon_safe",float(group.s))
		var flat:=_flat(p)
		var side:float=group.side
		var face:=Basis.looking_at(-flat.x*side,Vector3.UP)
		for n in range(int(group.count)):
			var at:=p.origin-flat.z*(float(n)-float(group.count-1)*.5)*15.0
			at.x=float(group.x)+side*(3.4 if n%2==1 else 0.0)
			_cargo_tower(Transform3D(face,at),float(group.top)-float(n%2)*8.0,i*3+n,int(group.depth)>0)
		spatial_groups.append(group)
	# Shared roof encloses both branches. Sparse offset openings avoid a continuous zebra stripe.
	for i in range(16):
		var p:=_pose("canyon_safe",float(i)*56+20)
		var roof:=Transform3D(_flat(p),Vector3(p.origin.x,179,p.origin.z))
		var opening_x:=-34.0 if i%3==1 else -46.0
		_solid(Vector3(250,1.1,39),_at(roof,Vector3(-40,0,9)),"505c53","N02","warehouse_roof_panel")
		# 200m wide by17m long opening gives24% skylight area, not a tiny hole in a huge roof.
		_solid(Vector3(opening_x+65,1.1,17),_at(roof,Vector3((opening_x-265)*.5,0,-19)),"505c53","N02","skylight_left_cheek")
		_solid(Vector3(-15-opening_x,1.1,17),_at(roof,Vector3((opening_x+185)*.5,0,-19)),"505c53","N02","skylight_right_cheek")
		_solid(Vector3(250,1.8,1.2),_at(roof,Vector3(-40,-1.5,-27)),"677367","N02","roof_crossbeam")
		for x:float in [-162,83]:
			_solid(Vector3(1.6,164,2.2),_at(roof,Vector3(x,-82,-27)),"657061","N02","roof_support")
		var floor_pose:=Transform3D(_flat(p),Vector3(p.origin.x,14,p.origin.z))
		_solid(Vector3(250,2,58),_at(floor_pose,Vector3(-40,0,0)),"303c36","N02","well_floor",true)
		for side:float in [-1,1]:
			_solid(Vector3(2,164,58),_at(roof,Vector3(-40+side*125,-82,0)),"3b423c","N02","hall_enclosure")
	_distant_warehouse()
	_entrance_frame()

func _entrance_frame() -> void:
	# An explicit loading portal resolves the transition between launch deck and tall storage hall.
	var p:=_pose("station_ramp",65)
	var frame:=Transform3D(_flat(p),Vector3(p.origin.x,16,p.origin.z))
	var height:=140.0
	for side:float in [-1.0,1.0]:
		var x:=side*24.5
		_solid(Vector3(2.2,height,4.5),_at(frame,Vector3(x,height*.5,0)),"858573","N02","entrance_jamb")
		_solid(Vector3(2.7,8,5),_at(frame,Vector3(x,80,0)),"b49a45","N02","entrance_protection")
		_solid(Vector3(3.8,1.5,6),_at(frame,Vector3(x,0,0)),"50564a","N02","entrance_footing")
		# A recessed mechanical side wall connects the front doorway back to the outer hall.
		_solid(Vector3(12,height,1.5),_at(frame,Vector3(side*31,height*.5,1.8)),"6b705f","N02","entrance_equipment_wall")
		for y in range(18,138,18):
			_solid(Vector3(10,.65,1.8),_at(frame,Vector3(side*31,float(y),.8)),"9c7745","N02","entrance_service_band")
			_solid(Vector3(3.0,7,2.5),_at(frame,Vector3(side*30,float(y)+4,0)),"4e594e","N02","entrance_service_panel")
		_worklight(_at(frame,Vector3(side*21,98,-3.0)),"N02",int(side)*3,true)
	_solid(Vector3(51,4,5),_at(frame,Vector3(0,height,0)),"737b68","N02","entrance_lintel")
	_solid(Vector3(46,1.0,5.2),_at(frame,Vector3(0,height-2.2,0)),"b49a45","N02","entrance_safety_header")
	spatial_groups.append({"space":"N02","role":"launch_to_storage_loading_portal","track":"station_ramp","s":65,"floor_world_y":16,"top_world_y":156,"opening_width":46.8})

func _apply_sample_lighting(session:Node3D,world:Node3D) -> void:
	# Functional G1 sources are now loaded; near-field fittings can reuse their actual meshes.
	Nearfield.new().build(self)
	super._apply_sample_lighting(session,world)
	for node:WorldEnvironment in session.find_children("*","WorldEnvironment",true,false):
		var env:=node.environment
		env.ambient_light_color=Color("bdc6c4")
		env.ambient_light_energy=.21
		env.tonemap_exposure=1.1
		env.fog_light_color=Color("90aeb6")
		env.fog_density=.00055
		env.volumetric_fog_density=.0007
		env.ssao_intensity=2.4
		env.ssao_radius=1.6
	for sun:DirectionalLight3D in session.find_children("*","DirectionalLight3D",true,false):
		sun.rotation_degrees=Vector3(-56,22,0)
		sun.light_color=Color("dceef5")
		sun.light_energy=2.0
		sun.directional_shadow_max_distance=320
	for spot:SpotLight3D in world.find_children("*","SpotLight3D",true,false):
		spot.light_color=Color("ffe0a1")
		spot.light_energy=18.0
		spot.spot_range=40
		spot.spot_angle=58
	# Local warm fill belongs to receiving work bays, leaving the cargo well lit by skylight openings.
	for track_id:String in ["station_start","station_carve"]:
		var length:float=rebuild_route.tracks[track_id].length
		for i in range(ceili(length/65.0)):
			var p:=_pose(track_id,minf(30+i*65.0,length-5))
			var lamp:=OmniLight3D.new()
			lamp.light_color=Color("ffe0ab")
			lamp.light_energy=5.5
			lamp.omni_range=35
			lamp.omni_attenuation=1.25
			lamp.shadow_enabled=false
			lamp.light_volumetric_fog_energy=.1
			lamp.distance_fade_enabled=true
			lamp.distance_fade_begin=160
			lamp.distance_fade_length=60
			world.add_child(lamp)
			lamp.global_position=p.origin+_flat(p).x*(-12 if i%2==0 else 14)+Vector3.UP*9
	Batcher.new().build(self)
