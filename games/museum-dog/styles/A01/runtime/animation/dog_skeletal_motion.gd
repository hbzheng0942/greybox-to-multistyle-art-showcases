extends Node
## Trusted A01-only quadruped controller. Writes Skeleton3D poses exclusively.
## The intact head stays neutral so the shared Mouth/pick-up anchor does not drift.
const RECIPE := "a01-quadruped-skin-20261030-v1"
const LEGS := ["FrontL", "FrontR", "HindL", "HindR"]
var game:Node
var dog:CharacterBody3D
var artwork:Node3D
var skeleton:Skeleton3D
var rests:Array[Transform3D]=[]
var bones:Dictionary={}
var chains:Dictionary={}
var bound:bool=false
var failure:String="not_bound"
var observed:Dictionary={}
var phase:float=0.0
var amplitude:float=0.0
var elapsed:float=0.0
var run_blend:float=0.0
var turn_blend:float=0.0
var previous_position:Vector3
var previous_yaw:float=0.0
var position_sample_valid:bool=false
var motion_bounds:Array=[]

func setup(source_game:Node)->bool:
	game=source_game
	if game.get("visual_catalog")==null or not game.visual_catalog.entries.has("player/dog"):
		failure="missing_player_visual_catalog";return false
	dog=game.dog
	process_physics_priority=50
	previous_position=dog.global_position
	previous_yaw=dog.rotation.y
	position_sample_valid=true
	return bind_artwork(game.visual_catalog.entries["player/dog"].get("artwork"))

func bind_artwork(candidate:Node3D)->bool:
	bound=false;bones.clear();chains.clear();rests.clear();motion_bounds.clear()
	if not is_instance_valid(candidate):failure="missing_actual_artwork";return false
	artwork=candidate
	var candidates:Array=[]
	for child in [candidate]+candidate.find_children("*","Skeleton3D",true,false):
		if child is Skeleton3D:candidates.append(child)
	if candidates.size()!=1:failure="expected_one_actual_quadruped_skeleton";return false
	skeleton=candidates[0]
	for index in range(skeleton.get_bone_count()):
		bones[skeleton.get_bone_name(index)]=index
		rests.append(skeleton.get_bone_global_rest(index))
	for required in ["Root","Pelvis","Spine","Chest","Neck","Head","TailBase","TailMid","TailTip","Ear_L","Ear_R"]:
		if not bones.has(required):failure="missing_bone_"+required;return false
	for name in LEGS:
		for suffix in ["Upper","Lower","Paw","Toe"]:
			if not bones.has(name+"_"+suffix):failure="missing_bone_"+name+"_"+suffix;return false
		var upper:int=bones[name+"_Upper"];var lower:int=bones[name+"_Lower"];var paw:int=bones[name+"_Paw"]
		var hip:Vector3=rests[upper].origin;var knee:Vector3=rests[lower].origin;var ankle:Vector3=rests[paw].origin
		var direction:Vector3=(ankle-hip).normalized()
		var bend:Vector3=knee-hip-direction*(knee-hip).dot(direction)
		if bend.length()<.00001:bend=Vector3(0,0,-1)
		chains[name]={"upper":upper,"lower":lower,"paw":paw,"hip":hip,"knee":knee,"ankle":ankle,"length_a":hip.distance_to(knee),"length_b":knee.distance_to(ankle),"bend":bend.normalized()}
	for child in candidate.find_children("*","MeshInstance3D",true,false):
		if child.mesh==null:continue
		var base:AABB=child.mesh.get_aabb()
		var envelope:AABB=base.grow(.20)
		child.custom_aabb=envelope
		child.set_meta("a01_motion_local_aabb",envelope)
		child.set_meta("a01_motion_root_offset_world_max",Vector3.ZERO)
		child.set_meta("a01_skeletal_motion",true)
		motion_bounds.append({"mesh":str(candidate.get_path_to(child)),"base_local_aabb":_box(base),"animated_local_aabb":_box(envelope),"query_contract":"Conservative skin hull; CPU source triangles remain neutral"})
	bound=true;failure="";reset_pose()
	return true

func _physics_process(delta:float)->void:
	if not bound or not is_instance_valid(dog):return
	var planar:=Vector3(dog.velocity.x,0,dog.velocity.z)
	var forward:Vector3=-dog.global_basis.z
	var distance:float=0.0
	if position_sample_valid:
		var displacement:Vector3=dog.global_position-previous_position;displacement.y=0.0
		distance=displacement.length()
		if distance>maxf(1.0,delta*18.0):reset_pose();distance=0.0
	previous_position=dog.global_position
	position_sample_valid=true
	var yaw_delta:float=wrapf(dog.rotation.y-previous_yaw,-PI,PI)
	previous_yaw=dog.rotation.y
	turn_blend=move_toward(turn_blend,clampf(yaw_delta/maxf(delta,.000001),-2.0,2.0),delta*8.0)
	advance_visual(delta,distance/maxf(delta,.000001),planar.dot(forward),dog.is_on_floor(),distance)

func advance_visual(delta:float,speed:float,signed_forward_speed:float,grounded:bool,travelled:float=-1.0)->void:
	if not bound:return
	elapsed+=delta
	var moving:bool=speed>.08 and grounded
	amplitude=move_toward(amplitude,clampf(speed/.85,0.0,1.0) if moving else 0.0,delta*(5.5 if moving else 7.0))
	run_blend=move_toward(run_blend,smoothstep(3.0,7.0,speed) if moving else 0.0,delta*3.0)
	if moving:
		var distance:float=travelled if travelled>=0.0 else speed*delta
		var direction:float=-1.0 if signed_forward_speed<-.05 else 1.0
		# Distance-driven onset/blocked response. Very high gameplay speed remains stylized.
		phase=fposmod(phase+minf(distance/lerpf(.72,1.25,run_blend),delta*lerpf(4.5,5.4,run_blend))*direction,1.0)
	skeleton.reset_bone_poses()
	observed={"speed":speed,"signed_forward_speed":signed_forward_speed,"grounded":grounded,"amplitude":amplitude,"phase":phase,"run_blend":run_blend,"foot_locked":false,"phase_source":"actual_planar_distance" if travelled>=0.0 else "supplied_speed","head_neck_pinned":true,"limbs":{}}
	var walk_offsets:Array=[0.0,.5,.75,.25]
	var trot_offsets:Array=[0.0,.5,.5,0.0]
	var run_offsets:Array=[0.0,.13,.48,.61]
	var trot:float=smoothstep(.6,2.0,speed)
	for index in range(LEGS.size()):
		var name:String=LEGS[index]
		var offset:float=lerpf(float(walk_offsets[index]),float(trot_offsets[index]),trot)
		offset=lerpf(offset,float(run_offsets[index]),run_blend)
		var cycle:float=fposmod(phase+offset,1.0)
		var stance_fraction:float=lerpf(.60,.43,run_blend)
		var stance:bool=cycle<stance_fraction
		var u:float=cycle/stance_fraction if stance else (cycle-stance_fraction)/(1.0-stance_fraction)
		var half_stride:float=lerpf(.073,.108,run_blend)*amplitude
		var z:float=lerpf(-half_stride,half_stride,u) if stance else lerpf(half_stride,-half_stride,smoothstep(0.0,1.0,u))
		var lift:float=0.0 if stance else sin(u*PI)*lerpf(.026,.060,run_blend)*amplitude
		var chain:Dictionary=chains[name]
		var hip:Vector3=chain.hip
		hip.y-=lerpf(.027,.038,run_blend)*amplitude if name.begins_with("Front") else .012*amplitude
		var target:Vector3=chain.ankle+Vector3(0,lift,z)
		# Turning shortens the inside step, with a restrained lateral lead.
		var side:float=-1.0 if name.contains("L") else 1.0
		target.z=chain.ankle.z+z*(1.0-side*turn_blend*.10)
		target.x+=turn_blend*.007*amplitude
		var solved:Dictionary=_solve_leg(chain,hip,target)
		observed.limbs[name]={"phase":"stance" if stance else "swing","target":_a(target),"ankle":_a(solved.ankle),"hip":_a(hip),"knee":_a(solved.knee),"reach_clamped":solved.clamped,"swing_clearance_m":lift}
	# Secondary motion is independent of the fixed muzzle/head. No armature root bob.
	for tail in ["TailBase","TailMid","TailTip"]:
		var index:int=bones[tail]
		var amount:float=(.16+amplitude*.10)*(1.0 if tail=="TailBase" else .75)
		skeleton.set_bone_pose_rotation(index,Quaternion(Vector3.UP,sin(elapsed*TAU*2.4-float(index)*.3)*amount))
	for ear in ["Ear_L","Ear_R"]:
		var index:int=bones[ear]
		skeleton.set_bone_pose_rotation(index,Quaternion(Vector3.RIGHT,sin(elapsed*TAU*lerpf(2.0,4.0,run_blend))*.055*amplitude))
	skeleton.force_update_all_bone_transforms()
	if amplitude<.00001:
		# Idle tail may continue, but every leg is restored exactly.
		for chain in chains.values():
			for key in ["upper","lower","paw"]:
				skeleton.set_bone_pose_position(chain[key],skeleton.get_bone_rest(chain[key]).origin)
				skeleton.set_bone_pose_rotation(chain[key],skeleton.get_bone_rest(chain[key]).basis.get_rotation_quaternion())
				skeleton.set_bone_pose_scale(chain[key],skeleton.get_bone_rest(chain[key]).basis.get_scale())
		skeleton.force_update_all_bone_transforms()

func _solve_leg(chain:Dictionary,hip:Vector3,target:Vector3)->Dictionary:
	var delta:Vector3=target-hip
	var distance:float=delta.length()
	var a:float=chain.length_a;var b:float=chain.length_b
	var bounded:float=clampf(distance,absf(a-b)+.00001,a+b-.00001)
	var axis:Vector3=delta.normalized()
	var actual:Vector3=hip+axis*bounded
	var bend:Vector3=chain.bend-axis*(chain.bend as Vector3).dot(axis)
	if bend.length()<.00001:bend=Vector3.FORWARD-axis*Vector3.FORWARD.dot(axis)
	bend=bend.normalized()
	var along:float=(a*a-b*b+bounded*bounded)/(2.0*bounded)
	var height:float=sqrt(maxf(0.0,a*a-along*along))
	var knee:Vector3=hip+axis*along+bend*height
	_set_segment(chain.upper,hip,chain.knee-chain.hip,knee-hip)
	_set_segment(chain.lower,knee,chain.ankle-chain.knee,actual-knee)
	var paw_pose:Transform3D=rests[chain.paw]
	paw_pose.origin=actual
	skeleton.set_bone_global_pose(chain.paw,paw_pose)
	return {"ankle":actual,"knee":knee,"clamped":absf(distance-bounded)>.0001}

func _set_segment(index:int,origin:Vector3,rest_direction:Vector3,direction:Vector3)->void:
	var pose:Transform3D=rests[index]
	pose.origin=origin
	pose.basis=Basis(Quaternion(rest_direction.normalized(),direction.normalized()))*pose.basis
	skeleton.set_bone_global_pose(index,pose)

func reset_pose()->void:
	phase=0.0;amplitude=0.0;run_blend=0.0;turn_blend=0.0
	if is_instance_valid(skeleton):skeleton.reset_bone_poses();skeleton.force_update_all_bone_transforms()

func motion_contract()->Dictionary:
	return {"recipe":RECIPE,"bound":bound,"failure":failure,"route":"true_quadruped_skin_with_two_link_leg_IK_and_flat_paws","bones":bones.size(),"head_neck_pinned":true,"physics_transforms_written":false,"motion_bounds":motion_bounds,"limits":["High gameplay speed uses bounded stylized cadence; not a claim of no foot sliding.","Source triangles returned to CPU remain neutral; conservative skin AABB must be used for camera admission.","Native isolated motion is separate from complete museum contact/performance acceptance."]}

func _a(v:Vector3)->Array:return [v.x,v.y,v.z]
func _box(b:AABB)->Dictionary:return {"min":_a(b.position),"size":_a(b.size)}
