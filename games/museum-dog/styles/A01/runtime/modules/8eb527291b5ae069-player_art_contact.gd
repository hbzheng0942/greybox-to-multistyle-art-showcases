extends RefCounted
## Explicit A01 player contact adapter. Original capsule, art and Mouth remain
## unchanged. Scene owner must report this as a declared local contact addition.
const RECIPE:="a01-head-contact-safe-turn-02"
const CENTER:=Vector3(0,.50,-.39)
const RADIUS:float=.205
const SHAPE_NAME:="A01HeadArtContact"
const ANGULAR_STEP:float=.035
var turn_samples:int=0
var limited_turns:int=0
var maximum_rejected_yaw:float=0.0
var starting_overlap_frames:int=0
var last_turn:Dictionary={}
var _head:CollisionShape3D

func apply(game:Node)->Dictionary:
	if game==null or not game.get("dog") is CharacterBody3D:return {"status":"failed","reason":"missing_actual_dog","added_shapes":0}
	var result:Dictionary=apply_to_dog(game.dog)
	if result.get("status") in ["applied","already_applied"] and "a01_player_art_contact" in game:game.a01_player_art_contact=self
	return result

func apply_to_dog(dog:CharacterBody3D)->Dictionary:
	var before:Array=_original_colliders(dog)
	var mouth:Node3D=dog.get_node_or_null("Mouth") as Node3D
	var mouth_before:Transform3D=mouth.transform if mouth!=null else Transform3D.IDENTITY
	var existing:Node=dog.get_node_or_null(SHAPE_NAME)
	if existing!=null:
		_head=existing as CollisionShape3D
		return {"status":"already_applied" if existing.get_meta("a01_local_contact",false) else "failed","added_shapes":0,"recipe":RECIPE}
	var shape:=CollisionShape3D.new()
	shape.name=SHAPE_NAME
	var sphere:=SphereShape3D.new()
	sphere.radius=RADIUS
	shape.shape=sphere
	shape.position=CENTER
	shape.set_meta("a01_local_contact",true)
	shape.set_meta("a01_contact_role","player_head_art")
	shape.set_meta("a01_contact_recipe",RECIPE)
	dog.add_child(shape)
	_head=shape
	var after:Array=_original_colliders(dog)
	return {"status":"applied","recipe":RECIPE,"added_shapes":1,"shape_path":str(dog.get_path_to(shape)),"type":"SphereShape3D","center_local":[CENTER.x,CENTER.y,CENTER.z],"radius":RADIUS,"shape_local_aabb":{"min":[-RADIUS,CENTER.y-RADIUS,CENTER.z-RADIUS],"size":[RADIUS*2,RADIUS*2,RADIUS*2]},"original_colliders_unchanged":before==after,"mouth_unchanged":mouth==null or mouth.transform==mouth_before,"original_colliders":before,"collision_layer":dog.collision_layer,"collision_mask":dog.collision_mask,"rotating_offset_shape_requires_regression":true}

func _original_colliders(dog:CharacterBody3D)->Array:
	var rows:Array=[]
	for child in dog.get_children():
		if child is CollisionShape3D and not child.get_meta("a01_local_contact",false):
			var record:Dictionary={"path":str(dog.get_path_to(child)),"transform":str(child.transform),"disabled":child.disabled,"shape_instance_id":child.shape.get_instance_id() if child.shape!=null else 0,"shape_type":child.shape.get_class() if child.shape!=null else "null"}
			if child.shape is CapsuleShape3D:record.merge({"radius":child.shape.radius,"height":child.shape.height})
			rows.append(record)
	return rows


func limit_yaw(game:Node,previous_yaw:float)->void:
	# Shared movement performs translation first and yaw second. Query the full
	# original head sphere at this translation endpoint, before the next physics
	# integration. Reject only unsafe rotation; position, velocity and Mouth are
	# never adjusted. Every intermediate angle is admitted, not just the endpoint.
	if _head==null or not is_instance_valid(_head):return
	var dog:CharacterBody3D=game.dog
	var requested:float=dog.rotation.y
	var delta:float=angle_difference(previous_yaw,requested)
	if absf(delta)<.000001:return
	turn_samples+=1
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=_head.shape
	query.collision_mask=dog.collision_mask
	query.collide_with_areas=false
	query.collide_with_bodies=true
	var exclude:Array[RID]=[dog.get_rid()]
	if is_instance_valid(game.held):exclude.append(game.held.get_rid())
	for other in dog.get_collision_exceptions():
		if is_instance_valid(other):exclude.append(other.get_rid())
	query.exclude=exclude
	var space:PhysicsDirectSpaceState3D=dog.get_world_3d().direct_space_state
	var previous_clear:bool=_yaw_clear(dog,previous_yaw,query,space)
	if not previous_clear:starting_overlap_frames+=1
	var accepted:float=previous_yaw
	var steps:int=maxi(1,ceili(absf(delta)/ANGULAR_STEP))
	var blocked:bool=false
	for step in range(1,steps+1):
		var candidate:float=previous_yaw+delta*float(step)/float(steps)
		if _yaw_clear(dog,candidate,query,space):
			accepted=candidate
			continue
		blocked=true
		# Refine the first obstruction only from an admitted previous pose.
		# If translation recovery began overlapped, retain its prior yaw; never
		# manufacture a positional correction or shrink the sphere to pass.
		if previous_clear or not is_equal_approx(accepted,previous_yaw):
			var low:float=accepted
			var high:float=candidate
			for iteration in range(9):
				var midpoint:float=(low+high)*.5
				if _yaw_clear(dog,midpoint,query,space):low=midpoint
				else:high=midpoint
			accepted=low
		break
	dog.rotation.y=accepted
	var rejected:float=absf(angle_difference(accepted,requested))
	if rejected>.000001:
		limited_turns+=1
		maximum_rejected_yaw=maxf(maximum_rejected_yaw,rejected)
	last_turn={"requested_yaw":requested,"accepted_yaw":accepted,"previous_yaw":previous_yaw,"rejected_radians":rejected,"starting_pose_clear":previous_clear,"blocked":blocked,"translation_changed_by_guard":false}

func _yaw_clear(dog:CharacterBody3D,yaw:float,query:PhysicsShapeQueryParameters3D,space:PhysicsDirectSpaceState3D)->bool:
	var rotation:Vector3=dog.rotation
	rotation.y=yaw
	var local:=Transform3D(Basis.from_euler(rotation).scaled(dog.scale),dog.position)
	var parent:Node3D=dog.get_parent() as Node3D
	var world:Transform3D=parent.global_transform*local if parent!=null else local
	query.transform=world*_head.transform
	for hit in space.intersect_shape(query,32):
		var body:CollisionObject3D=hit.collider as CollisionObject3D
		# A release grace exception may be stored on the other body only.
		if body is PhysicsBody3D and (body as PhysicsBody3D).get_collision_exceptions().has(dog):continue
		return false
	return true

func turn_report()->Dictionary:
	return {"recipe":RECIPE,"samples":turn_samples,"limited_yaw_count":limited_turns,"maximum_rejected_yaw_radians":maximum_rejected_yaw,"starting_overlap_frames":starting_overlap_frames,"last_turn":last_turn,"angular_step_radians":ANGULAR_STEP,"query_sphere_shrink":0.0,"position_or_velocity_modified":false,"limit":"At a wall a rear/side-first dog may need to back out before its head can safely face the requested direction."}
