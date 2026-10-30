extends Node3D
## A01 production entry. Shared gameplay stays canonical; missing art stays visible.
signal assembled
const GAME=preload("res://shared/game/dog_game.tscn")
const A01_GAME=preload("res://styles/A01/runtime/modules/cefaa8054e44c8a0-a01_game.gd")
const CAMERA=preload("res://styles/A01/runtime/modules/395c4f086a53ba66-camera_composition_guard.gd")
const PICK=preload("res://styles/A01/runtime/modules/334ec3c542507687-visual_pick.gd")
const KITS=preload("res://styles/A01/runtime/modules/d9126d48a16b57a6-scene_kits.gd")
const LOADER=preload("res://styles/A01/runtime/modules/edd50d33cc748d6c-asset_loader.gd")
const PLAYER_CONTACT=preload("res://styles/A01/runtime/modules/8eb527291b5ae069-player_art_contact.gd")
const VISITOR_MOTION=preload("res://styles/A01/runtime/modules/09ca506573468454-visitor_visual_motion.gd")
const DOG_MOTION=preload("res://styles/A01/runtime/animation/dog_skeletal_motion.gd")
const VISITOR_SKIN=preload("res://styles/A01/runtime/animation/visitor_skeletal_motion.gd")
const PALETTE=preload("res://styles/A01/runtime/modules/c55f42a18825edd0-material_palette.gd")
const LIGHTING=preload("res://styles/A01/runtime/modules/069f37f06a8d43ae-a01_lighting.gd")
const EXHIBITS=preload("res://styles/A01/runtime/modules/37f3258ff922d886-exhibit_style.gd")
const LAYOUT=preload("res://styles/A01/runtime/modules/ec58f2faa7cec5bb-concept_layout.gd")
const DISPLAY=preload("res://styles/A01/runtime/modules/fb4c3a0f78a4802d-porcelain_display.gd")
const STRUCTURE=preload("res://styles/A01/runtime/modules/1bc1c8a495047e0c-room_structure.gd")
const OCCLUSION=preload("res://styles/A01/runtime/modules/08501ccae70f88f7-a01_occlusion.gd")
const HUD_STYLE=preload("res://styles/A01/runtime/modules/bca603ba5d6f7b42-a01_hud.gd")
const MAPPING="res://styles/A01/runtime/modules/94e5de0ab2d31df6-semantic-bindings.json"
var registry_path="res://styles/A01/runtime/integrated-skeletal-20261030/asset-registry.json"
var game
var camera_guard
var picker
var dog_motion
var visitor_motion
var visitor_skin_motion
var player_art_contact
var report:Dictionary={}
var mapping:Dictionary={}
var loader=LOADER.new()
var kits=KITS.new()
var palette=PALETTE.new()
var exhibits=EXHIBITS.new()
var concept_layout=LAYOUT.new()
var status_label:Label
var ready_for_inspection:=false
var assembly_start_usec:int=0
var assembly_stage_usec:int=0
var assembly_timings:Dictionary={}
var assembly_group_timings:Array=[]

func _ready()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--a01-registry="):registry_path=arg.trim_prefix("--a01-registry=")
	call_deferred("_start")

func _start()->void:
	assembly_start_usec=Time.get_ticks_usec();assembly_stage_usec=assembly_start_usec
	seed(27)
	game=GAME.instantiate()
	game.set_script(A01_GAME)
	add_child(game)
	_apply_kids_route()
	mapping=JSON.parse_string(FileAccess.get_file_as_string(MAPPING))
	var before:=physics_snapshot()
	var before_structure:=physics_structure_snapshot()
	var before_props:Dictionary={}
	for body in game.props:before_props[str(body.get_path())]=body.global_transform
	loader.load_registry(registry_path)
	report={"schema":1,"kind":"a01-scene-assembly-status","registry_path":registry_path,"registry_error":loader.error,"mapping_sha256":FileAccess.get_sha256(MAPPING),"groups":[],"missing_generated_models":[],"failed":[],"unmapped_native_ids":[],"authored_groups":0,"loaded_generated_groups":0,"absorbed_visual_ids":[],"completed_art_sample":false}
	_mark_assembly("native_baseline_registry")
	var seen:Dictionary={}
	var missing:Dictionary={}
	for group in mapping.groups:
		var group_start_usec:int=Time.get_ticks_usec()
		var valid:=true
		for id in group.semantic_ids:
			if seen.has(id) or not game.visual_catalog.entries.has(id):
				report.failed.append({"group":group.id,"reason":"missing_or_duplicate_native_id","id":id})
				valid=false
			seen[id]=true
		if not valid:continue
		var entry:Dictionary=game.visual_catalog.entries[group.anchor_id]
		var result:Dictionary
		var local:=Transform3D.IDENTITY
		if group.source_route=="authored":
			result=kits.make(group,game.visual_catalog)
			local=(entry.visual as Node3D).global_transform.affine_inverse()*result.world_transform
		else:
			result=loader.prepare(group,game.visual_catalog)
			if result.status!="loaded":
				result["group"]=group.id
				if result.status=="missing":missing[group.asset_id]=result.reason
				else:report.failed.append(result)
				report.groups.append(result)
				continue
			local=result.local_transform
		if result.get("scene")==null or not game.visual_catalog.replace_visual(group.anchor_id,result.scene,local):
			report.failed.append({"group":group.id,"reason":"static_visual_adapter_rejected"})
			continue
		for id in group.semantic_ids:
			if id==group.anchor_id:continue
			var empty:=Node3D.new()
			var empty_scene:PackedScene=kits.pack(empty)
			if not game.visual_catalog.replace_visual(id,empty_scene):
				report.failed.append({"group":group.id,"reason":"absorbed_visual_failed","id":id})
			else:report.absorbed_visual_ids.append(id)
		var row:Dictionary={"group":group.id,"asset_id":group.asset_id,"anchor_id":group.anchor_id,"status":"authored_installed" if group.source_route=="authored" else "loaded","semantic_ids":group.semantic_ids}
		if group.source_route!="authored":
			var artwork:Node3D=game.visual_catalog.entries[group.anchor_id].artwork
			row["concept_placement"]=concept_layout.transform_artwork(artwork,group)
			row["exhibit_style"]=exhibits.apply(artwork,str(group.asset_id))
			row["material_treatment"]=palette.apply_imported(artwork,str(group.asset_id))
		if result.has("report"):row["asset"]=result.report
		if group.has("support"):row["support"]=group.support
		report.groups.append(row)
		if group.source_route=="authored":report.authored_groups+=1
		else:report.loaded_generated_groups+=1
		assembly_group_timings.append({"group":group.id,"route":group.source_route,"milliseconds":(Time.get_ticks_usec()-group_start_usec)/1000.0})
	_mark_assembly("all_visual_groups")
	for id in game.visual_catalog.entries:
		if not seen.has(id):report.unmapped_native_ids.append(id)
	for aid in missing:report.missing_generated_models.append({"asset_id":aid,"reason":missing[aid]})
	report["graphic_portal_adjustments"]=kits.clipped_panels.duplicate(true)
	report["physics_unchanged_by_visual_assembly"]=before==physics_snapshot()
	report["counts"]={"semantic_ids":game.visual_catalog.entries.size(),"ordinary_props":game.builder.exhibit_spots.size(),"bones":game.skel.size(),"visitors":game.visitors.size(),"visitor_parts":game.visitors.size()*3}
	_setup_dog_motion()
	visitor_motion=VISITOR_MOTION.new()
	add_child(visitor_motion)
	report["visitor_visual_motion"]={"bound":visitor_motion.setup(game),"contract":visitor_motion.motion_contract()}
	if not report.visitor_visual_motion.bound:report.failed.append({"reason":"visitor_motion_binding_failed","detail":visitor_motion.failures})
	# Adult skeletal pilot is additive; child/staff retain the existing native visual controller.
	visitor_skin_motion=VISITOR_SKIN.new()
	add_child(visitor_skin_motion)
	var skin_bound:bool=visitor_skin_motion.setup(game)
	report["visitor_skeletal_motion"]={"bound":skin_bound,"contract":visitor_skin_motion.motion_contract()}
	if not skin_bound:report.failed.append({"reason":"adult_skeletal_binding_failed","detail":visitor_skin_motion.failures})
	_mark_assembly("visual_motion_and_snapshot")
	var structure=STRUCTURE.new()
	report["room_structure"]=structure.apply(game,mapping,kits)
	report["porcelain_display"]=DISPLAY.new().apply(game,mapping,kits)
	player_art_contact=PLAYER_CONTACT.new()
	report["player_art_contact"]=player_art_contact.apply(game)
	report["shared_physics_preserved"]=before==physics_snapshot(true)
	report["full_scene_physics_unchanged"]=before==physics_snapshot()
	report["declared_local_contacts"]=report.room_structure.added_colliders+report.porcelain_display.added_colliders+report.player_art_contact.added_shapes
	report["declared_display_pose_changes"]=report.porcelain_display.changed_props.size()
	report["original_physics_structure_preserved"]=before_structure==physics_structure_snapshot()
	report["display_pose_contract"]=_pose_contract(before_props,report.porcelain_display)
	report["shared_physics_contract_passed"]=report.physics_unchanged_by_visual_assembly and report.original_physics_structure_preserved and report.display_pose_contract.passed and report.player_art_contact.get("original_colliders_unchanged",false) and report.player_art_contact.get("mouth_unchanged",false)
	if not report.shared_physics_contract_passed:
		report.failed.append({"reason":"unexpected_physics_change_outside_declared_A01_contacts_and_plate_poses"})
	_mark_assembly("local_contacts_and_contracts")
	_setup_light()
	report["render_occlusion"]=OCCLUSION.new().apply(game,mapping)
	_mark_assembly("lighting_and_occlusion")
	_rebind_visual_queries()
	_mark_assembly("visual_query_binding")
	_build_status()
	report["hud_style"]=HUD_STYLE.new().apply(game)
	_mark_assembly("hud")
	report["assembly_timing"]={"total_milliseconds":(Time.get_ticks_usec()-assembly_start_usec)/1000.0,"stages_milliseconds":assembly_timings,"groups_milliseconds":assembly_group_timings,"includes_gameplay_hot_loop":false}
	ready_for_inspection=true
	print("A01_ASSEMBLY "+JSON.stringify({"authored_groups":report.authored_groups,"generated_groups":report.loaded_generated_groups,"missing_sources":report.missing_generated_models.size(),"failed":report.failed.size(),"shared_physics_preserved":report.shared_physics_preserved,"shared_physics_contract_passed":report.shared_physics_contract_passed,"declared_local_contacts":report.declared_local_contacts,"declared_display_pose_changes":report.declared_display_pose_changes}))
	assembled.emit()

func _mark_assembly(phase:String)->void:
	var now:int=Time.get_ticks_usec()
	assembly_timings[phase]=(now-assembly_stage_usec)/1000.0
	assembly_stage_usec=now
	print("A01_ASSEMBLY_STAGE "+JSON.stringify({"stage":phase,"milliseconds":assembly_timings[phase]}))

func _setup_dog_motion()->void:
	for row in report.groups:
		if row.get("asset_id")!="dog_player" or row.get("status")!="loaded":continue
		dog_motion=DOG_MOTION.new()
		add_child(dog_motion)
		var bound:bool=dog_motion.setup(game)
		report["dog_visual_motion"]=dog_motion.motion_contract()
		if not bound:report.failed.append({"group":"player/dog","reason":"actual_dog_limb_binding_failed","detail":dog_motion.failure})
		return

func _apply_kids_route()->void:
	# Exact accepted A01 runtime correction, using native restoration once.
	var route:Array=[Vector3(.4,0,-8.2),Vector3(2.4,0,-8.2),Vector3(2.4,0,-9.8),Vector3(.4,0,-9.8)]
	game.builder.visitor_routes["kids"]=route
	for visitor in game.visitors:
		if visitor.room!="kids":continue
		visitor.route=route
		visitor.spawn=route[int(visitor.spawn_index)]
		game._restore_visitor(visitor)

func _rebind_visual_queries()->void:
	# Static art/bones use final triangles; moving garments add conservative
	# blend-target envelopes, explicitly distinct from GPU-deformed triangles.
	if is_instance_valid(picker):picker.free()
	if is_instance_valid(camera_guard):camera_guard.free()
	camera_guard=CAMERA.new()
	camera_guard.setup(game)
	add_child(camera_guard)
	picker=PICK.new()
	picker.setup(game,camera_guard)
	add_child(picker)
	game.a01_picker=picker
	if is_instance_valid(visitor_skin_motion):visitor_skin_motion.bind_camera_guard(camera_guard)

func _setup_light()->void:
	var lighting=LIGHTING.new()
	report["lighting_recipe"]=lighting.apply(game,mapping,kits)
	get_viewport().msaa_3d=Viewport.MSAA_4X
	report["anti_aliasing"]="MSAA_4X"

func _build_status()->void:
	var layer:=CanvasLayer.new()
	layer.layer=20
	add_child(layer)
	status_label=Label.new()
	status_label.position=Vector2(14,120)
	if game.ui_font != null:status_label.add_theme_font_override("font",game.ui_font)
	status_label.add_theme_font_size_override("font_size",13)
	status_label.add_theme_color_override("font_color",Color("f4e7cf"))
	status_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	status_label.add_theme_constant_override("shadow_offset_x",1)
	status_label.add_theme_constant_override("shadow_offset_y",1)
	var ids:Array=[]
	for row in report.missing_generated_models:ids.append(row.asset_id)
	status_label.text="充气奇遇馆"
	status_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(status_label)

func physics_snapshot(exclude_local_contacts:bool=false)->String:
	var rows:Array=[]
	_snapshot(game,rows,exclude_local_contacts)
	return JSON.stringify(rows).sha256_text()

func _snapshot(node:Node,rows:Array,exclude_local_contacts:bool=false)->void:
	if exclude_local_contacts and node.get_meta("a01_local_contact",false):return
	if node is CollisionShape3D:rows.append({"path":str(node.get_path()),"shape":node.shape.get_class(),"transform":str(node.global_transform),"aabb":str(node.shape.get_debug_mesh().get_aabb())})
	if node is CollisionObject3D:rows.append({"path":str(node.get_path()),"layer":node.collision_layer,"mask":node.collision_mask})
	if node is RigidBody3D:rows.append({"path":str(node.get_path()),"mass":node.mass,"freeze":node.freeze,"supports":node.get_meta("supports",[])})
	for child in node.get_children():_snapshot(child,rows,exclude_local_contacts)

func physics_structure_snapshot()->String:
	var rows:Array=[]
	_structure_snapshot(game,rows)
	return JSON.stringify(rows).sha256_text()

func _structure_snapshot(node:Node,rows:Array)->void:
	if node.get_meta("a01_local_contact",false):return
	if node is CollisionShape3D:rows.append({"path":str(node.get_path()),"shape":node.shape.get_class(),"local_transform":str(node.transform),"aabb":str(node.shape.get_debug_mesh().get_aabb())})
	if node is CollisionObject3D:rows.append({"path":str(node.get_path()),"layer":node.collision_layer,"mask":node.collision_mask})
	if node is StaticBody3D:rows.append({"path":str(node.get_path()),"static_global_transform":str(node.global_transform)})
	if node is RigidBody3D:rows.append({"path":str(node.get_path()),"mass":node.mass,"freeze":node.freeze,"gravity_scale":node.gravity_scale,"linear_damp":node.linear_damp,"supports":node.get_meta("supports",[])})
	for child in node.get_children():_structure_snapshot(child,rows)

func _dict_transform(value:Dictionary)->Transform3D:
	return Transform3D(Basis(_array_vector(value.basis_x),_array_vector(value.basis_y),_array_vector(value.basis_z)),_array_vector(value.position))
func _array_vector(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
func _pose_contract(before:Dictionary,layout:Dictionary)->Dictionary:
	var issues:Array=[]
	var changed:Array=[]
	var declared:Dictionary={}
	for row in layout.get("changed_props",[]):
		var path:String=str(row.node)
		if declared.has(path):issues.append({"node":path,"reason":"duplicate_declared_pose"})
		declared[path]=row
	for body in game.props:
		var path:=str(body.get_path())
		if not before[path].is_equal_approx(body.global_transform):changed.append(path)
		if not declared.has(path):
			if not before[path].is_equal_approx(body.global_transform):issues.append({"node":path,"reason":"undeclared_pose_change"})
			continue
		var row:Dictionary=declared[path]
		if not body.get_meta("a01_display_pose",false) or str(body.get_meta("kind",""))!="plate" or str(body.get_meta("semantic_id",""))!=str(row.semantic_id):issues.append({"node":path,"reason":"wrong_declared_body_or_semantic"})
		if not before[path].is_equal_approx(_dict_transform(row.original_transform)):issues.append({"node":path,"reason":"original_pose_receipt_mismatch"})
		if not body.global_transform.is_equal_approx(_dict_transform(row.new_transform)):issues.append({"node":path,"reason":"new_pose_receipt_mismatch"})
		if not body.transform.is_equal_approx(body.get_meta("spawn_transform",Transform3D.IDENTITY)) or not body.position.is_equal_approx(body.get_meta("spawn_pos",Vector3.INF)) or not is_equal_approx(body.global_position.y,float(body.get_meta("spawn_y",INF))):issues.append({"node":path,"reason":"reset_pose_does_not_match_A01_display"})
		declared.erase(path)
	for path in declared:issues.append({"node":path,"reason":"missing_declared_body"})
	if changed.size()!=layout.get("changed_props",[]).size():issues.append({"reason":"changed_pose_count_mismatch","actual":changed.size()})
	return {"changed_props":changed,"issues":issues,"passed":issues.is_empty()}
