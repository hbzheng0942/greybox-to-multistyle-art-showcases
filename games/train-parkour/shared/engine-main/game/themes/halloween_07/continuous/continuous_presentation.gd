extends "res://themes/halloween_07/presentation.gd"
const Continuous = preload("res://themes/halloween_07/continuous/continuous_world.gd")
const LowerCityLayers = preload("res://themes/halloween_07/lower_city_layers.gd")
var legacy_relocations:=[]

func _record_legacy_move(kind:String,p:Transform3D,q:Transform3D,floor_y:float,reason:String,half_width:float,half_depth:float)->void:
	var feet:=[]
	for x:float in [-half_width,0.0,half_width]:
		for z:float in [-half_depth,0.0,half_depth]:
			var foot:=q*Vector3(x,0,z);feet.append([foot.x,floor_y,foot.z])
	legacy_relocations.append({"kind":kind,"original_root":[p.origin.x,p.origin.y,p.origin.z],"relocated_root":[q.origin.x,q.origin.y,q.origin.z],"foundation_floor_y":floor_y,"foundation_footprint_samples":feet,"shape_and_count_preserved":true,"reason":reason})

func _castle_group(p:Transform3D,index:int,scale_factor:=1.0)->void:
	var q:=p
	var safe:SpatialTrack=route.tracks.canyon_safe
	if index==7 and p.origin.distance_to(_level(safe,390,-95).origin)<0.01:
		q=_level(safe,390,-175)
		_record_legacy_move("safe_s390_negative_castle",p,q,18.0,"FAST raw111/112 actual canonical keep encloses camera; relocate complete keep, foundation and buttresses",43,24)
	super._castle_group(q,index,scale_factor)

func _tower(p:Transform3D,side:float,height:float,index:int,clock_face:=true,front_mural:=false,gallery_deck:float=-1000.0)->void:
	var q:=p
	var safe:SpatialTrack=route.tracks.canyon_safe
	if not clock_face and absf(height-77.0)<0.01 and p.origin.distance_to(_level(safe,365,-46).origin)<0.01:
		q=_level(safe,365,-126)
		_record_legacy_move("safe_s365_negative_tower",p,q,18.0,"FAST raw109 camera enters shoulder turret; move the complete grounded tower, attached gallery landing and lights",18,14)
	super._tower(q,side,height,index,clock_face,front_mural,gallery_deck)

func _viaduct(p:Transform3D,arches:int,span:float,deck_y:float,bottom:float,depth:float,key:String,mural_back_pier:=false)->void:
	var q:=p
	var safe:SpatialTrack=route.tracks.canyon_safe
	if arches==3 and absf(span-30.0)<0.01 and absf(deck_y-27.0)<0.01:
		for s:float in [275.0,365.0,725.0]:
			var original:=_level(safe,s,-34).rotated_local(Vector3.UP,PI/2)
			if p.origin.distance_to(original.origin)<0.01:
				q=_level(safe,s,-114).rotated_local(Vector3.UP,PI/2)
				var reason:="Measured FAST camera-to-train ray crosses real arch/pier; retain complete thick three-bay gallery farther outside"
				if s==365.0:reason="Move attached three-bay gallery by the same80m as its tower landing, preserving the original relative bearing connection"
				_record_legacy_move("safe_s"+str(s)+"_negative_gallery",p,q,q.origin.y+minf(bottom,18.0-q.origin.y),reason,48,4.6)
				break
	super._viaduct(q,arches,span,deck_y,bottom,depth,key,mural_back_pier)

func _make_batch(mesh:Mesh,poses:Array,key:String,ident:String)->void:
	var begin:=world.get_child_count()
	super._make_batch(mesh,poses,key,ident)
	if DisplayServer.get_name()!="headless":return
	var chunks:={}
	for p:Transform3D in poses:
		var cell:=Vector3i(floori(p.origin.x/128.0),floori(p.origin.y/96.0),floori(p.origin.z/128.0))
		if not chunks.has(cell):chunks[cell]=[]
		chunks[cell].append(p)
	for index in range(begin,world.get_child_count()):
		var node:Node3D=world.get_child(index)
		var cell:=Vector3i(roundi(node.position.x/128.0),roundi(node.position.y/96.0),roundi(node.position.z/128.0))
		node.set_meta("h07_audit_source_poses",chunks[cell])

func _lower_city() -> void:
	# Replace the old two sparse rows after all regional structures can be excluded.
	pass

func _place_practicals() -> void:
	Continuous.build_extension(self)
	LowerCityLayers.new().build(self)
	super._place_practicals()

func build(session: Node3D) -> Node3D:
	var result: Node3D = super.build(session)
	result.name = "H07ContinuousWorld"
	var construction: Dictionary = result.get_meta("construction_report")
	construction["production_stage"] = "full_world_native_review_pending_human_acceptance_false"
	construction["scope"] = "37 frozen tracks / 9 continuous regions"
	result.set_meta("construction_report",construction)
	return result
