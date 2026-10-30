extends RefCounted
## Editable steelwork and cargo assemblies for the approved nine-space B2 atlas.
## Every static mesh is registered through the parent; nothing creates collision or moves gameplay.
const LAMP := "B2-LUX-23-speed_lamp-bent_elbow"
const SCANNER := "B2-LUX-16-scanner_bay-vented_scan_bay"
const HOPPER := "B2-LUX-18-return_hopper-wide_hopper"
const TOWER := "B2-LUX-19-return_tower-single_offset_head"
const RETAINING := "B2-LUX-05-retaining_bay-deep_open_bay"
var host: RefCounted
var world: Node3D
var plan: Dictionary
var counts: Dictionary = {}
var rejected_count := 0
var glow_materials: Dictionary = {}
var occupied: Dictionary = {}
var lamp_index := 0

func build(builder: RefCounted, layout: Dictionary) -> void:
	host=builder
	world=host.rebuild_world
	plan=layout
	_remove_replaced_proxy()
	for region: Dictionary in plan.regions:
		print("B2_FULL_REGION_BEGIN ",region.space," ",Time.get_ticks_msec())
		if region.space=="N06":
			_scanner_corridor(region)
		else:
			_cargo_district(region)
			if region.space=="N03":_sorting_machines(region)
			if region.space=="N04":_winch_hall(region)
			if region.space=="N05":_transfer_gantries(region)
			if region.space=="N07":_return_hub(region)
			if region.space=="N08":_underpass_services(region)
			if region.space=="N09":_dispatch_portals(region)
		host.submit_render_uploads()
		print("B2_FULL_REGION_DONE ",region.space," ",Time.get_ticks_msec())
	_track_interfaces()
	world.set_meta("full_scene",{"schema":1,"spaces":["N01","N02","N03","N04","N05","N06","N07","N08","N09"],
		"new_region_parts":counts,"rejected_scenery_groups":rejected_count,"shared_landmarks":1,
		"station_policy":"Retain previous station layout, primary meshes and light/exposure settings",
		"water":"No added water; approved spatial design uses local dry foundations",
		"new_collision_nodes":0,"human_acceptance":false,"visual_review":"pending native full-route pixels"})

func _use(track_id: String) -> String:
	var space: String=host.track_spaces[track_id]
	host.full_runtime_scene=host.track_scenes[track_id]
	return space

func _upright(pose: Transform3D) -> Transform3D:
	var f: Vector3=-pose.basis.z
	f.y=0
	if f.length_squared()<.001:f=Vector3.FORWARD
	return Transform3D(Basis.looking_at(f.normalized(),Vector3.UP),pose.origin)

func _at(pose: Transform3D, offset: Vector3) -> Transform3D:
	return pose.translated_local(offset)

func _box(size: Vector3, pose: Transform3D, color: String, space: String, role: String, check := true, floor_face := false) -> Node3D:
	if check and not host._route_clear(AABB(-size*.5,size),pose,float(plan.scenery_clearance_m)):
		rejected_count+=1
		return null
	var node: Node3D=host._solid(size,pose,color,space,"full_"+role,floor_face)
	if node!=null:
		host.added_bounds[-1].bounds_kind="authored_full_scene_box"
		counts[space]=int(counts.get(space,0))+1
	return node

func _beam(a: Vector3, b: Vector3, width: float, color: String, space: String, role: String) -> void:
	var d:=b-a
	if d.length()<.05:return
	var up:=Vector3.UP if absf(d.normalized().dot(Vector3.UP))<.97 else Vector3.RIGHT
	_box(Vector3(width,width,d.length()),Transform3D(Basis.looking_at(d.normalized(),up),(a+b)*.5),color,space,role)

func _glow(size: Vector3, pose: Transform3D, space: String, warm := true) -> void:
	var color:="ffe0a1" if warm else "93b9ac"
	var mesh:=_box(size,pose,"d6c295",space,"lamp_diffuser") as MeshInstance3D
	if mesh==null:return
	if not glow_materials.has(color):
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color(color)
		material.emission_enabled=true
		material.emission=Color(color)
		material.emission_energy_multiplier=1.5
		material.roughness=.5
		glow_materials[color]=material
	mesh.material_override=glow_materials[color]

func _light(pose: Transform3D, space: String, energy := 5.0, radius := 32.0) -> void:
	_box(Vector3(4.5,.45,1.5),pose,"42483f",space,"worklight_case")
	_glow(Vector3(4.0,.08,1.1),_at(pose,Vector3(0,-.26,0)),space)
	var light:=OmniLight3D.new()
	light.light_color=Color("ffe0aa")
	light.light_energy=energy
	light.omni_range=radius
	light.omni_attenuation=1.3
	light.shadow_enabled=false
	light.light_volumetric_fog_energy=.08
	light.distance_fade_enabled=true
	light.distance_fade_begin=170
	light.distance_fade_length=55
	world.add_child(light)
	light.global_position=pose.origin+Vector3.DOWN*.65
	lamp_index+=1

func _lamp_on_deck(pose: Transform3D, space: String) -> void:
	if not host.source_boxes.has(LAMP):return
	var source: AABB=host.source_boxes[LAMP]
	host._model(LAMP,pose,4.8/source.size.y,space,"full_joint_worklamp")

func _service_deck(size:Vector3, pose:Transform3D, floor_y:float, space:String, role:String) -> Node3D:
	# Keep each deck, its supports and mounted props atomic at replay-proven camera reserves.
	if not _art_reserve_clear(AABB(-size*.5,size),pose,space,"service_deck"):return null
	var height:=pose.origin.y-size.y*.5-floor_y
	var supports:Array[Transform3D]=[]
	if height>1.0:
		for x:float in [-size.x*.36,size.x*.36]:
			for z:float in [-size.z*.35,size.z*.35]:
				var point:=pose*Vector3(x,0,z)
				point.y=floor_y+height*.5
				var foot:=Transform3D(pose.basis,point)
				if host._route_clear(AABB(-Vector3(1.4,height,1.4)*.5,Vector3(1.4,height,1.4)),foot,9.0):supports.append(foot)
		if supports.size()<2:return null
	var deck:=_box(size,pose,"73735c",space,role)
	if deck==null:return null
	for support:Transform3D in supports:_box(Vector3(1.4,height,1.4),support,"5a6656",space,"service_deck_leg")
	return deck

func _remove_replaced_proxy() -> void:
	var ids: Dictionary={}
	for item: Dictionary in world.get_meta("proxy_geometry_before_calibration",{}).get("items",[]):
		if str(item.get("space_id","")) not in ["N03","N04","N05","N06","N07","N08","N09"]:continue
		if str(item.get("category","")) not in ["background_mass","roof"]:continue
		var candidate:=str(item.id)
		while not candidate.is_empty():
			ids[candidate]=true
			var separator:=candidate.rfind(":")
			if separator<0:break
			candidate=candidate.left(separator)
	for child: Node3D in world.get_children():
		var ident:=str(child.get_meta("instance_id",""))
		if not ident.is_empty() and ids.has(ident):
			child.visible=false
			if not ident in host.replaced_ids:host.replaced_ids.append(ident)

func _art_reserve_clear(bounds: AABB, pose: Transform3D, space: String, group: String) -> bool:
	var world_bounds: AABB=pose*bounds
	for reserve:Dictionary in plan.get("art_reserves",[]):
		if reserve.space!=space or group not in reserve.groups:continue
		var low:Vector3=host.vector(reserve.minimum_m)
		var high:Vector3=host.vector(reserve.maximum_m)
		if world_bounds.intersects(AABB(low,high-low)):
			rejected_count+=1
			return false
	return true

func _storage_stack(pose: Transform3D, height: float, space: String, variant: int, depth := 13.0) -> void:
	var width:=16.0 if variant%3==0 else 13.0
	var bounds:=AABB(Vector3(-width*.5,0,-depth*.5),Vector3(width,height,depth))
	if not _art_reserve_clear(bounds,pose,space,"storage_stack"):return
	if not host._route_clear(bounds,pose,12.0):
		rejected_count+=1
		return
	var key:=Vector3i((pose.origin/Vector3(14,1000,14)).floor())
	if occupied.has(key):return
	occupied[key]=true
	_box(Vector3(width+1,1.0,depth+1),_at(pose,Vector3(0,.5,0)),"676d5b",space,"rack_foot",false)
	for x:float in [-1,1]:
		for z:float in [-1,1]:
			_box(Vector3(.7,height,.85),_at(pose,Vector3(x*(width*.5-.35),height*.5,z*(depth*.5-.4))),"626c59",space,"rack_column",false)
	# An offset solid service back, recessed cargo and open bays give depth without a tiled facade.
	_box(Vector3(width-.9,height,1.0),_at(pose,Vector3(0,height*.5,depth*.5-.6)),"464f44",space,"rack_back",false)
	var levels:=maxi(2,int(height/8.0))
	for level in levels:
		var y:=1.1+level*8.0
		_box(Vector3(width,.42,depth),_at(pose,Vector3(0,y-.2,0)),"5a5b48",space,"rack_shelf",false)
		_box(Vector3(width+.3,.52,.5),_at(pose,Vector3(0,y,-depth*.5)),"9a5c3f",space,"rack_lip",false)
		if posmod(level+variant,5)==0:
			_box(Vector3(3.0,5.8,depth-2.0),_at(pose,Vector3(width*.5-2.2,y+3.0,0)),"72735d",space,"service_locker",false)
		else:
			for cargo in range(3):
				if posmod(variant+level+cargo,8)==2:continue
				var size:=Vector3(width/3.0-.55,4.2+float(posmod(level+cargo+variant,4))*.65,depth-3.0)
				host._crate(_at(pose,Vector3(-width/3.0+cargo*width/3.0,y,0)),size,variant+level+cargo,space)
		if level%3==1:
			_box(Vector3(width-1,.32,2.5),_at(pose,Vector3(0,y-.2,-depth*.5-1.2)),"696c55",space,"service_balcony",false)
			_light(_at(pose,Vector3(0,y+5.8,-depth*.5-.4)),space,3.0,24)
	_box(Vector3(width+1.3,.8,depth+1),_at(pose,Vector3(0,height+.4,0)),"68715e",space,"rack_cap",false)
	if variant%3==0:
		_lamp_on_deck(_at(pose,Vector3(width*.35,height+.8,-depth*.3)),space)

func _cargo_district(region: Dictionary) -> void:
	var variant:=0
	for track_id: String in region.tracks:
		print("B2_FULL_CARGO_TRACK ",track_id," ",Time.get_ticks_msec())
		var space:=_use(track_id)
		var track: Variant=host.rebuild_route.tracks[track_id]
		var spacing:=float(region.spacing)
		for i in range(maxi(1,ceili(track.length/spacing))):
			var s:=minf(18+i*spacing,track.length-4)
			var p:=_upright(host._pose(track_id,s))
			for side_index in 2:
				var side:=float(region.sides[side_index])
				# Staggered islands and wider service clearings follow the local corridor.
				if posmod(i+side_index,6)==4:continue
				var at:=_at(p,Vector3(side+signf(side)*float(i%3)*3.0,0,(12.0 if side_index==1 else -9.0)))
				at.origin.y=float(region.floor)
				at.basis=Basis.looking_at(-p.basis.x*signf(side),Vector3.UP)
				var h:=float(region.height)-float(posmod(i+side_index*2,4))*7.0
				_storage_stack(at,h,space,variant)
				if i%4==0:
					var rear:=_at(p,Vector3(side*2.1,0,-20))
					rear.origin.y=float(region.floor)
					rear.basis=at.basis
					_storage_stack(rear,h+12.0,space,variant+7,18.0)
				variant+=1
			# Independent slim side piers ground elevated route structure; no continuous fill under flight gaps.
			for side:float in [-1,1]:
				var x:float=side*(float(track.half_width)+6.0)
				var top:=p.origin.y-4.5
				var base:=float(region.floor)
				if top>base+2:
					_box(Vector3(1.7,top-base,2.1),Transform3D(p.basis,Vector3(p.origin.x,base+(top-base)*.5,p.origin.z)+p.basis.x*x),"596452",space,"side_bearing_pier")

func _gantry(pose: Transform3D, half: float, top: float, floor_y: float, space: String, variant: int) -> void:
	var height:=pose.origin.y+top-floor_y
	if height<=0:return
	# Reject the entire assembly if a load-bearing pillar would be removed by route clearance.
	for side:float in [-1,1]:
		var center:=pose.origin+pose.basis.x*(side*half)
		center.y=floor_y+height*.5
		if not host._route_clear(AABB(-Vector3(1.8,height,2.2)*.5,Vector3(1.8,height,2.2)),Transform3D(pose.basis,center),9.0):return
	for side:float in [-1,1]:
		var point:=pose.origin+pose.basis.x*(side*half)
		point.y=floor_y+height*.5
		_box(Vector3(1.8,height,2.2),Transform3D(pose.basis,point),"626e5d",space,"gantry_pillar")
		_box(Vector3(2.2,6.5,2.5),_at(pose,Vector3(side*half,3.5,0)),"b49a45",space,"gantry_foot_guard")
	_box(Vector3(half*2+4,2.0,3.2),_at(pose,Vector3(0,top,0)),"9b874e",space,"gantry_beam")
	for side:float in [-1,1]:
		_beam(pose*Vector3(side*(half-8),top-.3,0),pose*Vector3(side*half,top-8,0),.65,"555d4c",space,"gantry_brace")
	_light(_at(pose,Vector3(-half*.4 if variant%2==0 else half*.4,top-1.2,0)),space,5.5,37)

func _sorting_machines(region: Dictionary) -> void:
	for track_id:String in region.tracks:
		var space:=_use(track_id)
		var track:Variant=host.rebuild_route.tracks[track_id]
		for i in range(ceili(track.length/64.0)):
			var p:=_upright(host._pose(track_id,minf(24+i*64.0,track.length-5)))
			_gantry(p,26,33,float(region.floor),space,i)
			# A side conveyor and suspended service carriage identify the sorting plant.
			for side:float in [-1,1]:
				_box(Vector3(5.0,3.6,13.0),_at(p,Vector3(side*21,23,0)),"ae9453",space,"sorter_drive_housing")
				_box(Vector3(2.2,2.2,14.0),_at(p,Vector3(side*21,22.8,0)),"373f37",space,"sorter_drive_inset")
				_box(Vector3(3.8,.45,47),_at(p,Vector3(side*25,15,-12)),"545f4d",space,"suspended_conveyor")
				for z:float in [-21,-3]:
					_beam(p*Vector3(side*25,15,z),p*Vector3(side*26,32,z),.28,"797a64",space,"conveyor_hanger")

func _ring(center: Vector3, axis: Vector3, radius: float, width: float, depth: float, color: String, space: String, role: String) -> void:
	var basis:=Basis.looking_at(axis.normalized(),Vector3.UP if absf(axis.normalized().y)<.95 else Vector3.RIGHT)
	var segments:=32
	for i in segments:
		var angle:=TAU*float(i)/float(segments)
		var radial:=basis.x*cos(angle)+basis.y*sin(angle)
		var tangent:=-basis.x*sin(angle)+basis.y*cos(angle)
		var pose:=Transform3D(Basis(radial,tangent,basis.z),center+radial*radius)
		_box(Vector3(width,radius*TAU/segments+width*.25,depth),pose,color,space,role)

func _winch_hall(region: Dictionary) -> void:
	_use("loop")
	var track:Variant=host.rebuild_route.tracks.loop
	var a:Vector3=host._pose("loop",0).origin
	var b:Vector3=host._pose("loop",track.length*.25).origin
	var c:Vector3=host._pose("loop",track.length*.5).origin
	var center:=(a+c)*.5
	var axis:=(b-a).cross(c-a).normalized()
	var radius:=a.distance_to(center)*.84
	for side:float in [-1,1]:
		var position:=center+axis*(side*34.0)
		_ring(position,axis,radius,4.5,5.8,"b49a45","N04","winch_outer_guard")
		for depth:float in [-2.0,-.7,.7,2.0]:
			_ring(position+axis*depth,axis,radius-4.5,2.2,.7,"303932","N04","coiled_drive_cable")
		_ring(position,axis,6.0,3.0,6.5,"747b64","N04","winch_axle_guard")
		var up:=Vector3.UP
		var radial:=axis.cross(up).normalized()
		for i in 6:
			var v:=radial*cos(float(i)*TAU/6)+up*sin(float(i)*TAU/6)
			_beam(position+v*7,position+v*(radius-1.0),1.4,"8a7848","N04","winch_spoke")
		for sign_side:float in [-1,1]:
			var foot:=position+radial*sign_side*14
			foot.y=float(region.floor)
			_beam(foot,position+radial*sign_side*4,2.7,"5f6958","N04","winch_support")
			_box(Vector3(9,2,9),Transform3D(Basis.IDENTITY,foot+Vector3.UP),"74745d","N04","winch_foot")
		_light(Transform3D(Basis.IDENTITY,position+Vector3.UP*(radius+5)),"N04",8.0,55)
	# High trusses enclose the actual loop volume without placing anything through its center opening.
	for track_id:String in ["loop_entry","loop_out"]:
		var p:=_upright(host._pose(track_id,host.rebuild_route.tracks[track_id].length*.5))
		_gantry(p,43,93,float(region.floor),"N04",0)

func _transfer_gantries(region: Dictionary) -> void:
	for track_id:String in region.tracks:
		_use(track_id)
		var track:Variant=host.rebuild_route.tracks[track_id]
		for i in range(maxi(1,ceili(track.length/120.0))):
			var p:=_upright(host._pose(track_id,minf(16+i*120.0,track.length-4)))
			# The high-short flight crosses above grind s136; leave this service bay open.
			if not (track_id=="grind" and i==1):
				_gantry(p,23,26,float(region.floor),"N05",i)
			for side:float in [-1,1]:
				var deck:=_at(p,Vector3(side*25,-2.0,0))
				if _service_deck(Vector3(13,1.1,18),deck,float(region.floor),"N05","transfer_service_deck")==null:continue
				_lamp_on_deck(_at(deck,Vector3(0,.6,-5)),"N05")
				if i%2==0:host._model(host.CART,_at(deck,Vector3(0,.6,3)),1.1,"N05","full_waiting_cargo_cart")

func _scanner_corridor(region: Dictionary) -> void:
	_use("tunnel")
	var length:float=host.rebuild_route.tracks.tunnel.length
	for i in range(ceili(length/float(region.spacing))):
		var s:=minf(12+i*float(region.spacing),length-4)
		var p:=_upright(host._pose("tunnel",s))
		var span:=float(region.spacing)+1.2
		# Wall/roof modules remain outside the real camera and route volumes; native route bed is unchanged.
		for side:float in [-1,1]:
			_box(Vector3(1.4,13.1,span),_at(p,Vector3(side*26,6.0,0)),"716d50","N06","scanner_wall")
			_box(Vector3(2.2,13.0,2.2),_at(p,Vector3(side*25.8,6.0,-span*.5)),"847d54","N06","scanner_rib")
			_box(Vector3(18,1.0,span),_at(p,Vector3(side*17,-1.2,0)),"6f715e","N06","scanner_walkway",false,true)
			_box(Vector3(1.7,3.5,6),_at(p,Vector3(side*24.3,3.2,4)),"444d40","N06","vent_case")
			for louver in 5:
				_box(Vector3(.2,.16,5.5),_at(p,Vector3(side*23.4,2.0+louver*.55,4)),"7f836a","N06","vent_louver")
			_box(Vector3(.4,1.0,span),_at(p,Vector3(side*23.7,-.2,0)),"454d42","N06","cable_trunk")
		# Dress inside the retained native roof (underside13.5m); do not hide camera/contact geometry.
		_box(Vector3(54,.4,span),_at(p,Vector3(0,13.2,0)),"5c614b","N06","scanner_ceiling")
		_box(Vector3(51,.7,1.8),_at(p,Vector3(0,12.65,-span*.5)),"8a8056","N06","scanner_crossbeam")
		_light(_at(p,Vector3(-9 if i%2==0 else 9,12.25,0)),"N06",7.5,34)
		if i%5==0:
			var station:=_at(p,Vector3(23.0,-.6,0))
			station.basis=Basis.looking_at(-p.basis.x,Vector3.UP)
			host._model(SCANNER,station,.6,"N06","full_scanner_service_module")
	for s:float in [0,length]:
		var p:=_upright(host._pose("tunnel",s))
		_gantry(p,26,12.6,p.origin.y-4,"N06",0)

func _return_hub(region: Dictionary) -> void:
	print("B2_FULL_HUB_BEGIN ",Time.get_ticks_msec())
	_use("cliff_turn")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(host.CASE+"styles/odd-logistics/runtime/sample-finale-layout-v1.json"))
	var point:Vector3=host.vector(source.shared_landmark.revised_bottom_center_m)
	var pose:=Transform3D(Basis(Vector3.UP,.689076103974),point)
	var node:Node3D=host._model(TOWER,pose,1.0,"N07","full_B2_LM01_return_head")
	print("B2_FULL_HUB_TOWER ",Time.get_ticks_msec())
	if node!=null:
		node.set_meta("shared_landmark_id","B2-LM01")
		for child:Node3D in world.get_children():
			if str(child.get_meta("instance_id",""))=="B2-LM01":
				child.visible=false
				if not "B2-LM01" in host.replaced_ids:host.replaced_ids.append("B2-LM01")
		var base_y:=float(region.floor)
		var height:=point.y-base_y
		for x:float in [-8.5,8.5]:
			for z:float in [-8.0,8.0]:
				_box(Vector3(2.7,height,2.7),_at(pose,Vector3(x,-height*.5,z)),"67715f","N07","landmark_raised_foot")
		_box(Vector3(29,1.7,27),_at(pose,Vector3(0,-.85,0)),"8e8558","N07","landmark_service_deck")
		_lamp_on_deck(_at(pose,Vector3(-12,0,-11)),"N07")
		_lamp_on_deck(_at(pose,Vector3(12,0,-11)),"N07")
	for track_id:String in ["cliff_lip","upper","finish"]:
		print("B2_FULL_HUB_TRACK ",track_id," ",Time.get_ticks_msec())
		_use(track_id)
		var length:float=host.rebuild_route.tracks[track_id].length
		for i in range(ceili(length/150.0)):
			var p:=_upright(host._pose(track_id,minf(20+i*150.0,length-5)))
			for side:float in [-1,1]:
				var at:=_at(p,Vector3(side*27,-1.0,0))
				var deck:=_service_deck(Vector3(17,1.0,20),at,float(region.floor),"N07","return_work_deck")
				if deck!=null:
					host._model(HOPPER,_at(at,Vector3(0,.5,0)),.8,"N07","full_return_hopper")
					_lamp_on_deck(_at(at,Vector3(side*5,.5,-7)),"N07")

func _underpass_services(region: Dictionary) -> void:
	for track_id:String in region.tracks:
		_use(track_id)
		var length:float=host.rebuild_route.tracks[track_id].length
		for i in range(ceili(length/120.0)):
			var s:=minf(30+i*120.0,length-5)
			var p:=_upright(host._pose(track_id,s))
			# Shared bridge: never add a central downstand or another head tower at the crossing.
			if track_id=="underpass" and absf(s-300)<95:continue
			for side:float in [-1,1]:
				var at:=_at(p,Vector3(side*24,-1.0,0))
				if _service_deck(Vector3(12,1.0,16),at,float(region.floor),"N08","lower_loading_deck")==null:continue
				_lamp_on_deck(_at(at,Vector3(0,.5,-5)),"N08")
				if i%3==0:host._model(RETAINING,_at(p,Vector3(side*42,float(region.floor)-p.origin.y,0)),.8,"N08","full_open_storage_bay")
	_use("underpass")
	for i in range(ceili(host.rebuild_route.tracks.underpass.length/24.0)):
		var p:=_upright(host._pose("underpass",12+i*24.0))
		for side:float in [-1,1]:
			_box(Vector3(.55,12.7,1.2),_at(p,Vector3(side*9.4,6.0,0)),"7d805b","N08","underpass_rib")
			_box(Vector3(.2,1.5,22.5),_at(p,Vector3(side*9.65,8.6,0)),"7d805b","N08","underpass_service_panel")
		_box(Vector3(19,.55,1.2),_at(p,Vector3(0,12.6,0)),"877b51","N08","underpass_roof_rib")
		_light(_at(p,Vector3(-4 if i%2==0 else 4,12.0,0)),"N08",4.5,24)

func _dispatch_portals(region: Dictionary) -> void:
	for track_id:String in ["final_approach","final_receiver","final_upper","victory_run"]:
		_use(track_id)
		var length:float=host.rebuild_route.tracks[track_id].length
		for i in range(ceili(length/125.0)):
			var p:=_upright(host._pose(track_id,minf(22+i*125.0,length-5)))
			_gantry(p,23,23,float(region.floor),"N09",i)
			for side:float in [-1,1]:
				var dock:=_at(p,Vector3(side*26,-1.0,0))
				if _service_deck(Vector3(16,1.4,22),dock,float(region.floor),"N09","dispatch_dock")==null:continue
				if i%2==0:host._model(host.RECEIVING,_at(dock,Vector3(0,.7,3)),.6,"N09","full_dispatch_receiving_bay")
				_lamp_on_deck(_at(dock,Vector3(0,.7,-7)),"N09")

func _track_interfaces() -> void:
	# Sparse outer armour and action casings follow the actual rolled frame, including inverted/loop track.
	for track_id:String in host.rebuild_route.tracks:
		var space:=_use(track_id)
		if space in ["N01","N02"]:continue
		var track:Variant=host.rebuild_route.tracks[track_id]
		var half:float=track.half_width
		for i in range(ceili(track.length/15.0)):
			var p:Transform3D=host._pose(track_id,minf(7.5+i*15.0,track.length-2))
			for side:float in [-1,1]:
				_box(Vector3(.7,.65,9.0),_at(p,Vector3(side*(half+1.0),-.6,0)),"7c784e",space,"outer_rail_guard",false)
				if i%4==0:
					_box(Vector3(1.2,1.1,2.2),_at(p,Vector3(side*(half+1.2),-.9,0)),"a38b4d",space,"outer_drive_clamp",false)
		for window:Vector2 in track.release_windows:
			var s:float=(window.x+window.y)*.5
			var p:Transform3D=host._pose(track_id,s)
			for side:float in [-1,1]:
				var at:=_at(p,Vector3(side*(half+3.0),-.6,0))
				_box(Vector3(2.4,2.4,5.5),at,"b09a57",space,"release_machine_case",false)
				_box(Vector3(2.6,.55,3.4),_at(at,Vector3(0,1.4,0)),"5e6856",space,"release_machine_cap",false)
				for z:float in [-1.9,1.9]:_box(Vector3(.8,.7,.8),_at(at,Vector3(0,1.7,z)),"b49a45",space,"release_latch",false)
	host.full_runtime_scene=""

func _finish_native_structures() -> void:
	# Dress exact native visual batches without changing shared mesh resources or any transforms.
	var palette:={"VerticalStationFrame":"626e5d","BridgePiers":"596452", "TerminalStation":"626c59","TerminalGate":"b49a45","HubBridge":"9b874e"}
	var dressed:Array[String]=[]
	var environment:Node=host.rebuild_session.lab.get_node("EnvironmentRoot")
	for label:String in palette:
		var node:=environment.get_node_or_null(NodePath(label)) as MultiMeshInstance3D
		if node==null:continue
		node.material_override=host._mat(palette[label],false,.55)
		dressed.append("EnvironmentRoot/"+label)
	for node:MultiMeshInstance3D in host.rebuild_session.lab.get_node("PresentationRoot").find_children("*","MultiMeshInstance3D",true,false):
		var track_id:=str(node.get_parent().name).rsplit("_",true,1)[0]
		if not host.track_spaces.has(track_id):continue
		var selected:bool=str(node.name)=="TrackPiers" and host.track_spaces[track_id] in ["N03","N07","N09"]
		selected=selected or (track_id=="wall" and str(node.name)=="ContactStructure")
		if not selected:continue
		node.material_override=host._mat("626c59",false,.45)
		dressed.append("PresentationRoot/"+str(node.get_parent().name)+"/"+str(node.name))
	var report:Dictionary=world.get_meta("full_scene",{})
	report.native_material_dressing={"count":dressed.size(),"node_paths":dressed,"geometry_changes":0,
		"shared_batch_scope":"HubBridge contains N07 piers/deck and the N08 crossing; its single override intentionally covers both.",
		"station_canyon_unchanged":true}
	world.set_meta("full_scene",report)

func finish_surfaces() -> void:
	_finish_native_structures()
	# Reuse the verified recessed rail/fastener shader on new tracks; no raised hardware in wheel lanes.
	var original: ShaderMaterial
	for node:MultiMeshInstance3D in host.rebuild_session.lab.get_node("PresentationRoot").find_children("*","MultiMeshInstance3D",true,false):
		if str(node.name).begins_with("Bed") and str(node.get_parent().name).begins_with("station_start_"):
			if node.material_override is ShaderMaterial:original=node.material_override;break
	if original==null:return
	for node:MultiMeshInstance3D in host.rebuild_session.lab.get_node("PresentationRoot").find_children("*","MultiMeshInstance3D",true,false):
		if not str(node.name).begins_with("Bed"):continue
		var track_id:=str(node.get_parent().name).rsplit("_",true,1)[0]
		if not host.rebuild_route.tracks.has(track_id) or host.track_spaces[track_id] in ["N01","N02"]:continue
		var track:Variant=host.rebuild_route.tracks[track_id]
		var material:=original.duplicate() as ShaderMaterial
		material.set_shader_parameter("single_lane",track.single_lane)
		material.set_shader_parameter("rail_offset",.26 if track.kind=="grind" else .72)
		node.material_override=material
