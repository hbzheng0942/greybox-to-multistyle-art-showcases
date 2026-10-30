extends SceneTree
## Final combined-asset fixture, not an uninterrupted natural museum playthrough.
## Run only after the integrator's ready signal. No source or asset mutation.
var entry:String="res://styles/A01/runtime/integrated-skeletal-20261030/play.tscn"
var out:String=""
var scene
var game
var people
var dog_motion
var camera:Camera3D
var banner:Label
var driver:Node
var lead:Dictionary={}
var focus_mode:String="visitor"
var segment:String=""
var phase:String=""
var captured_frames:int=0
var segment_tick:int=0
var capture_enabled:bool=false
var samples:Array=[]
var segments:Array=[]
var assertions:Array=[]
var screenshots:Array=[]
var sources_start:Dictionary={}
var target:RigidBody3D
var watch_actor:String=""
var ever_down:bool=false
var ever_recovered:bool=false
var ever_walk:bool=false
var ever_idle:bool=false
var ever_clap:bool=false
var mouth_rest:Transform3D
var head_neutral:bool=true

class FixtureDriver:
	extends Node
	var game
	func _physics_process(delta:float)->void:
		game._move_dog(delta)
		game._handle_grab(delta)
		game._handle_reset()
		game._update_visitors(delta)
		game._update_camera(delta)
		game._update_hud()

func _initialize()->void:
	root.unfocusable=true
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--entry="):entry=arg.trim_prefix("--entry=")
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
	call_deferred("_run")

func _run()->void:
	if not out.is_absolute_path() or DirAccess.dir_exists_absolute(out):push_error("New absolute output directory required");quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join(".gdignore"),FileAccess.WRITE).close()
	root.size=Vector2i(1280,720);root.content_scale_size=root.size
	scene=load(entry).instantiate();root.add_child(scene);await scene.assembled
	game=scene.game;people=scene.visitor_skin_motion;dog_motion=scene.dog_motion
	sources_start=_sources()
	_assert("scene_assembled_without_failure",scene.report.failed.is_empty(),scene.report.failed)
	_assert("six_actual_adult_skeletal_visitors",people.actors.size()==6,people.snapshot())
	_assert("one_actual_adult_appearance_resource",people.resource_cache.size()==1,people.motion_contract())
	_assert("dog_27_bones",dog_motion.bound and dog_motion.bones.size()==27,dog_motion.motion_contract())
	_assert("visitor_skin_camera_hulls_registered",people.camera_shapes.size()>0 and is_instance_valid(people.camera_guard),{"camera_shapes":people.camera_shapes.size(),"dog_pose_hash":_pose_hash(dog_motion.skeleton),"adult_pose_hash":_pose_hash(people.actors[0].skeleton)})
	if people.actors.size()!=6 or not dog_motion.bound:
		_write_result("precondition_failed");scene.queue_free();await process_frame;quit(3);return
	for row:Dictionary in people.actors:
		_assert("three_original_bodies_"+str(row.visitor.name),row.visitor.parts.size()==3,{"body_count":row.visitor.parts.size()})
		var skin_ok:bool=not row.meshes.is_empty() and row.skeleton.get_bone_count()>=20
		for mesh_row:Dictionary in row.meshes:skin_ok=skin_ok and (mesh_row.node as MeshInstance3D).skin!=null
		_assert("actual_skin_and_base_clips_"+str(row.visitor.name),skin_ok and not str(row.resource.idle).is_empty() and not str(row.resource.walk).is_empty(),{"bones":row.skeleton.get_bone_count(),"idle":row.resource.idle,"walk":row.resource.walk})
		var visible_old:int=0
		for old:Dictionary in row.old_meshes:
			if (old.node as MeshInstance3D).visible:visible_old+=1
		_assert("old_meshes_hidden_"+str(row.visitor.name),visible_old==0,{"visible_old_meshes":visible_old,"actual_bones":row.skeleton.get_bone_count()})
	game.set_physics_process(false)
	for body:RigidBody3D in game.props:body.freeze=true
	driver=FixtureDriver.new();driver.game=game;scene.add_child(driver)
	mouth_rest=game.mouth.transform
	camera=Camera3D.new();camera.fov=46;scene.add_child(camera);camera.make_current()
	var hud:=CanvasLayer.new();hud.layer=150;scene.add_child(hud)
	banner=Label.new();banner.position=Vector2(300,10);banner.add_theme_font_size_override("font_size",17);banner.add_theme_color_override("font_color",Color("fbf7df"));banner.add_theme_color_override("font_shadow_color",Color.BLACK);banner.add_theme_constant_override("shadow_offset_x",1);banner.add_theme_constant_override("shadow_offset_y",1);hud.add_child(banner)
	_hide_capture_ui(scene)
	hud.visible=false
	lead=_actor("adult");watch_actor=str(lead.visitor.name)
	await _ticks(180,"pre_roll_native_patrol")
	_start_segment("visitors")
	lead=_actor("adult");await _ticks(45,"native patrol | adult")
	lead=_actor("adult");await _ticks(45,"native patrol | adult second view")
	lead=_actor("adult");await _ticks(30,"native idle | adult")
	game.gag_phase=3;game.gag2_phase=0
	await _ticks(90,"native gag state | skeletal clap")
	game.gag_phase=0
	lead=_actor("adult");watch_actor=str(lead.visitor.name)
	game._knock(lead.visitor,Vector3(.7,.2,.25))
	await _ticks(390,"native three-body knockdown | recovery")
	await _ticks(50,"native restored patrol")
	await _tap("dog_reset")
	await _ticks(40,"R reset | restored actors")
	_end_segment()
	_assert("native_patrol_walk_observed",ever_walk,{})
	_assert("idle_observed",ever_idle,{})
	_assert("native_gag_clap_observed",ever_clap,{})
	_assert("native_knockdown_skin_observed",ever_down,{"actor":watch_actor})
	_assert("native_recovery_observed",ever_recovered,{"actor":watch_actor})
	_assert("R_restores_all_visitors",_all_restored(),people.snapshot())
	_assert("R_clears_score_and_held",game.held==null and game.damage==0 and game._broken_count()==0,{"damage":game.damage,"broken":game._broken_count()})
	# A controlled open-floor fixture reuses the original neck body and native E.
	for body:RigidBody3D in game.props:body.freeze=true
	focus_mode="dog";game.dog.global_position=Vector3(0,.055,3.5);game.dog.velocity=Vector3.ZERO;game.dog.rotation.y=0;game.yaw=0
	target=game.skel.neck.body;game._break_bone("neck",Vector3.ZERO)
	target.freeze=true;target.rotation=Vector3.ZERO;target.global_position=Vector3(0,2,2)
	var lower:float=INF
	for shape:CollisionShape3D in target.find_children("*","CollisionShape3D",true,false):lower=minf(lower,(shape.global_transform*shape.shape.get_debug_mesh().get_aabb()).position.y)
	target.global_position.y+=.055-lower;target.linear_velocity=Vector3.ZERO;target.angular_velocity=Vector3.ZERO;target.freeze=false
	await _ticks(60,"dog fixture pre-roll")
	_start_segment("dog-carry")
	await _ticks(45,"dog idle | actual museum")
	for attempt:int in range(20):
		if game.held!=null:break
		await _tap("dog_grab")
		if game.held==null:Input.action_press("dog_forward",.2);await _ticks(6,"native E approach");Input.action_release("dog_forward")
	var acquired:bool=game.held==target
	_assert("E_acquired_original_neck",acquired,{"held":str(game.held.name) if game.held!=null else ""})
	await _ticks(90,"native acquisition | stable bite")
	Input.action_press("dog_forward",.2);await _ticks(90,"skeletal walk | carrying");Input.action_release("dog_forward")
	Input.action_press("dog_right",.2);await _ticks(60,"skeletal turn | carrying");Input.action_release("dog_right")
	await _ticks(45,"skeletal stop | carrying")
	await _tap("dog_throw");await _ticks(45,"Space throw | released")
	_assert("Space_released_neck",game.held==null,{})
	await _tap("dog_reset");await _ticks(60,"R reset | dog and people")
	_end_segment()
	_assert("dog_head_neutral_during_real_states",head_neutral,{})
	_assert("Mouth_transform_unchanged",game.mouth.transform==mouth_rest,{})
	_assert("final_all_visitors_restored",_all_restored(),people.snapshot())
	_assert("camera_skin_hulls_remain_registered",people.camera_shapes.size()>0,{"count":people.camera_shapes.size()})
	var same:bool=sources_start==_sources();_assert("source_and_asset_hashes_unchanged",same,{})
	_write_result("complete")
	for action:String in ["dog_forward","dog_back","dog_left","dog_right","dog_grab","dog_throw","dog_reset"]:Input.action_release(action)
	var failed:int=0
	for row:Dictionary in assertions:
		if not row.passed:failed+=1
	print("COMBINED_NATIVE_RESULT "+JSON.stringify({"failed":failed,"assertions":assertions.size(),"out":out,"segments":segments}))
	scene.queue_free();await process_frame;quit(0 if failed==0 else 4)

func _actor(kind:String)->Dictionary:
	for row:Dictionary in people.actors:
		if str(row.kind)==kind:return row
	return {}
func _all_restored()->bool:
	for visitor:Dictionary in game.visitors:
		if bool(visitor.down):return false
		for body:RigidBody3D in visitor.parts:
			if not body.freeze:return false
	return true
func _ticks(count:int,label:String)->void:
	phase=label
	for tick:int in range(count):
		await physics_frame;await process_frame
		_position_camera()
		var snapshot:Array=people.snapshot()
		for actor:Dictionary in snapshot:
			ever_walk=ever_walk or actor.mode=="walk";ever_idle=ever_idle or actor.mode=="idle";ever_clap=ever_clap or actor.mode=="clap"
			if str(actor.name)==watch_actor:
				if actor.mode=="ragdoll_skin":ever_down=true
				elif ever_down:ever_recovered=true
		head_neutral=head_neutral and dog_motion.skeleton.get_bone_global_pose(dog_motion.bones.Head).is_equal_approx(dog_motion.rests[dog_motion.bones.Head])
		if capture_enabled:
			banner.text="CONTROLLED NATIVE FIXTURE  |  "+label
			if segment_tick%10==0:
				samples.append({"segment":segment,"capture_tick":segment_tick,"phase":label,"physics_frame":Engine.get_physics_frames(),"visitors":snapshot,"dog":dog_motion.observed.duplicate(true),"held":game.held==target and target!=null,"contact":game.a01_held_art_contact.last.duplicate(true),"camera_shapes":people.camera_shapes.size(),"dog_pose_hash":_pose_hash(dog_motion.skeleton),"adult_pose_hash":_pose_hash(people.actors[0].skeleton)})
			if segment_tick%2==0 and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				var path:String=out.path_join(segment).path_join("frame-%04d.jpg"%captured_frames)
				root.get_texture().get_image().save_jpg(path,.82)
				captured_frames+=1
			segment_tick+=1
func _position_camera()->void:
	if focus_mode=="dog":
		camera.position=game.dog.global_position+Vector3(-2.3,1.55,2.7);camera.look_at(game.dog.global_position+Vector3(0,.55,-.3))
	elif not lead.is_empty():
		var at:Vector3=(lead.visitor.root as Node3D).global_position
		if bool(lead.visitor.down):at=(lead.visitor.torso as RigidBody3D).global_position-Vector3(0,.6,0)
		var offset:=Vector3(-2.2,1.45,-3.0)
		if str(lead.kind)=="child":offset=Vector3(3.0,1.4,0)
		if str(lead.kind)=="staff":offset=Vector3(2.2,1.5,2.6)
		camera.position=at+offset;camera.look_at(at+Vector3(0,.87,0))
func _tap(action:String)->void:
	Input.action_press(action);await _ticks(2,"input "+action);Input.action_release(action);await _ticks(2,"release "+action)
func _start_segment(name:String)->void:
	segment=name;segment_tick=0;captured_frames=0;capture_enabled=true
	DirAccess.make_dir_recursive_absolute(out.path_join(name))
func _end_segment()->void:
	segments.append({"name":segment,"ticks":segment_tick,"frames":captured_frames,"encoded_fps":30,"nominal_seconds":captured_frames/30.0,"path":out.path_join(segment)})
	capture_enabled=false
func _assert(label:String,passed:bool,detail:Variant)->void:
	assertions.append({"id":label,"passed":passed,"detail":detail})
func _sources()->Dictionary:
	var result:Dictionary={"entry":_file(entry),"test":_file(get_script().resource_path)}
	for node:Node in [scene,game,people,dog_motion,scene.camera_guard]:
		var script:Script=node.get_script()
		if script!=null:result[script.resource_path]=_file(script.resource_path)
	result["registry"]=_file(str(scene.registry_path))
	if FileAccess.file_exists(str(people.manifest_path)):result["visitor_manifest"]=_file(str(people.manifest_path))
	for source:Dictionary in people.motion_contract().sources:result[str(source.path)]=_file(str(source.path))
	var registry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(scene.registry_path)))
	result["dog_model"]=_file(str(registry.assets.dog_player.scene_path))
	return result
func _file(path:String)->Dictionary:return {"path":path,"sha256":FileAccess.get_sha256(path)}
func _write_result(status:String)->void:
	var contact_errors:Array=[];var acquisition_errors:Array=[]
	for sample:Dictionary in samples:
		if not sample.held or not sample.contact.has("bite_error_m"):continue
		if sample.contact.get("mode")=="carrying":contact_errors.append(sample.contact.bite_error_m)
		elif sample.contact.get("mode")=="acquiring":acquisition_errors.append(sample.contact.bite_error_m)
	contact_errors.sort();acquisition_errors.sort()
	var record:Dictionary={"kind":"final-combined-native-skin-and-gameplay-fixture","status":status,"entry":entry,"sources_start":sources_start,"sources_end":_sources(),"assertions":assertions,"segments":segments,"samples":samples,"stable_carry_samples":contact_errors.size(),"maximum_stable_bite_error_m":contact_errors.back() if not contact_errors.is_empty() else null,"maximum_transient_acquisition_gap_m":acquisition_errors.back() if not acquisition_errors.is_empty() else null,"visitor_motion_contract":people.motion_contract(),"dog_motion_contract":dog_motion.motion_contract(),"actual_tree_counts":_tree_counts(scene),"scope":"Staged complete environment with dog skin and six adult skins; two children/two staff retain earlier procedural fragments (upstream rigs pending). Controlled fixture: unrelated props frozen, native motor/grab/throw/R and visitor patrol/recovery driven by trusted test node, explicit gag phase to exercise existing clap state. Phase names are sidecar only; overlay UI is hidden; camera cuts are intentional. No claim of uninterrupted natural gallery route, production performance, or user acceptance."}
	FileAccess.open(out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(record,"  ")+"\n")

func _hide_capture_ui(node:Node)->void:
	if node is CanvasLayer:node.visible=false
	for child in node.get_children():_hide_capture_ui(child)

func _pose_hash(skeleton:Skeleton3D)->String:
	var poses:Array=[]
	for i in range(skeleton.get_bone_count()):poses.append(str(skeleton.get_bone_global_pose(i)))
	return JSON.stringify(poses).sha256_text()

func _tree_counts(node:Node)->Dictionary:
	var counts:Dictionary={"Skeleton3D":0,"AnimationPlayer":0,"AnimationTree":0,"BoneAttachment3D":0,"skinned_meshes":0}
	for child:Node in [node]+node.find_children("*","",true,false):
		for kind in ["Skeleton3D","AnimationPlayer","AnimationTree","BoneAttachment3D"]:
			if child.is_class(kind):counts[kind]+=1
		if child is MeshInstance3D and child.skin!=null:counts.skinned_meshes+=1
	return counts
