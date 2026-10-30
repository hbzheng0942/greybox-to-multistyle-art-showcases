extends RefCounted
## B2 authored near-field assemblies; frozen geometry and owner transforms remain intact.
## Called once after spatial assembly, before sample templates are released.
const SPEED_LAMP := "B2-LUX-23-speed_lamp-bent_elbow"
const TRACKS := ["station_start", "station_carve", "station_ramp", "canyon_safe", "canyon_fast_catch"]
var host: RefCounted
var world: Node3D
var session: Node3D
var batch_rows: Dictionary = {}
var count: Dictionary = {}
var materials: Dictionary = {}
var vehicle_parts: Array = []
var serial := 0

func build(builder: RefCounted) -> void:
	host = builder
	world = host.rebuild_world
	session = host.rebuild_session
	if world.has_meta("reconstruction_nearfield"): return
	# Replace only the old decorative sleeper/clip batches owned by the rebuild.
	for node: Node3D in world.get_children():
		if str(node.get_meta("asset_id", "")) == "authored_rail_fasteners": node.visible = false
	_prepare_reused_lamp()
	_trackwork()
	_practicals()
	_action_housings()
	_vehicle_trim()
	_flush_batches()
	world.set_meta("reconstruction_nearfield", {"schema":1,"counts":count,
		"source_concepts":["B2-scene-v2.png","B2-functional-kit-v2.png"],
		"static_geometry":"All new static parts have per-instance local bounds and world transforms in proxy_geometry",
		"vehicle_parts":vehicle_parts,"new_collision_nodes":0,
		"route_policy":"Original native Rail/Bed geometry retained; internal fastening appearance is surface shading. New guards and side assemblies retain full geometry review",
		"limitations":"Sampled broad-phase guards are not dynamic flight/camera proof. Native same-view and final geometry review required."})

func _space(track: String) -> String:
	return "N01" if track in ["station_start", "station_carve"] else "N02"

func _at(pose: Transform3D, point: Vector3) -> Transform3D:
	return pose.translated_local(point)

func _queue(size: Vector3, pose: Transform3D, color: String, role: String, space: String, emissive := false) -> void:
	var key := str(size)+color+role+str(emissive)
	if not batch_rows.has(key): batch_rows[key] = {"size":size,"color":color,"role":role,"emissive":emissive,"items":[]}
	batch_rows[key].items.append({"pose":pose,"space":space})
	count[role] = int(count.get(role,0))+1

func _surface(color: String, emissive: bool) -> Material:
	if not emissive: return host._mat(color,false,0.55)
	if materials.has(color): return materials[color]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.emission_enabled = true
	mat.emission = Color(color)
	mat.emission_energy_multiplier = 1.5
	mat.roughness = 0.28
	materials[color] = mat
	return mat

func _record(pose: Transform3D, box: AABB, ident: String, role: String, space: String) -> void:
	var bounds: AABB = pose * box
	host.added_bounds.append({"id":ident,"style_id":host.sid,"space_id":space,
		"category":"support","center_m":host.array(bounds.get_center()),"size_m":host.array(bounds.size),
		"basis_columns":[[1,0,0],[0,1,0],[0,0,1]],"protected_route":false,
		"mesh_local_aabb":host.box_record(box),"mesh_to_world":host.transform_array(pose),
		"bounds_kind":"authored_nearfield_box","source_asset_id":"authored_nearfield_"+role})

func _flush_batches() -> void:
	for key: String in batch_rows:
		var row: Dictionary = batch_rows[key]
		var shape := BoxMesh.new()
		shape.size = row.size
		var entries: Array = row.items
		var first := 0
		while first < entries.size():
			var anchor: Vector3 = (entries[first].pose as Transform3D).origin
			var amount := 1
			while amount < mini(64,entries.size()-first):
				var next_origin: Vector3 = (entries[first+amount].pose as Transform3D).origin
				if anchor.distance_to(next_origin)>96.0:break
				amount += 1
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = shape
			mm.instance_count = amount
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			node.material_override = _surface(row.color,row.emissive)
			node.visibility_range_end = 240.0
			node.visibility_range_end_margin = 35.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			world.add_child(node)
			var center := Vector3.ZERO
			for i in amount: center += (entries[first+i].pose as Transform3D).origin
			center /= float(amount)
			node.global_transform = Transform3D(Basis.IDENTITY,center)
			for i in amount:
				var item: Dictionary = entries[first+i]
				var pose: Transform3D = item.pose
				mm.set_instance_transform(i,Transform3D(pose.basis,pose.origin-center))
				serial += 1
				_record(pose,shape.get_aabb(),"rebuild:"+str(item.space)+":nearfield:"+str(serial),str(row.role),str(item.space))
			host._tag_tree(node,"rebuild:nearfield_batch:"+str(serial),"authored_nearfield_"+str(row.role),"station")
			node.name = "ReconstructionNearfield_"+str(row.role)+"_"+str(serial)
			first += amount
		host.parts.append({"kind":"nearfield_batched_geometry","role":row.role,"count":entries.size(),
			"size":host.array(row.size),"recorded_in_added_bounds":true})

func _dress_existing_deck() -> void:
	# Exact native rail positions come from spatial_full_lab.gd, not the old rebuild's four-column approximation.
	# The rigid 12m vehicle dips into convex track presentation near the ramp: additional raised hardware is unsuitable.
	# Keep that original topology and place painted/recessed construction detail in its existing surface material.
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx;
uniform bool single_lane=false;
uniform float rail_offset=0.72;
varying vec3 deck_local;
varying vec3 world_at;
varying float top_face;
float hash2(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float rect(vec2 p,vec2 h){return 1.0-step(0.0,max(abs(p.x)-h.x,abs(p.y)-h.y));}
void vertex(){deck_local=VERTEX*vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));world_at=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;top_face=max(0.0,NORMAL.y);}
void fragment(){
 float grain=hash2(floor(world_at.xz*3.0));
 vec3 color=vec3(0.29,0.30,0.25)*(0.86+0.18*grain);
 float metal=0.12;
 if(top_face>0.8){
  float sleeper=1.0-smoothstep(0.20,0.25,abs(deck_local.z));
  color=mix(color,vec3(0.19,0.22,0.19),sleeper*0.70);
  for(int lane=-1;lane<=1;lane++){
   if(single_lane && lane!=0){continue;}
   for(int side=-1;side<=1;side+=2){
    float rail=float(lane)*4.4+float(side)*rail_offset;
    float groove=1.0-smoothstep(0.10,0.16,abs(deck_local.x-rail));
    color=mix(color,vec3(0.14,0.18,0.16),groove*0.7);
    for(int clamp_side=-1;clamp_side<=1;clamp_side+=2){
     vec2 p=vec2(deck_local.x-rail-float(clamp_side)*0.29,deck_local.z);
     float clamp_shape=rect(p,vec2(0.17,0.31));
     color=mix(color,vec3(0.53,0.44,0.20)*(0.92+0.08*grain),clamp_shape);
     float bolt=1.0-smoothstep(0.065,0.08,length(p*vec2(1.0,0.85)));
     color=mix(color,vec3(0.20,0.24,0.21),bolt);
     float edge=clamp_shape*(1.0-rect(p,vec2(0.13,0.26)));
     color=mix(color,vec3(0.64,0.58,0.37),edge*0.55);
     metal=max(metal,clamp_shape*0.55);
    }
   }
  }
 }
 ALBEDO=color;ROUGHNESS=0.72;METALLIC=metal;
}
"""
	for node: MultiMeshInstance3D in session.lab.get_node("PresentationRoot").find_children("*","MultiMeshInstance3D",true,false):
		if not str(node.name).begins_with("Bed"):continue
		var track_id := str(node.get_parent().name).rsplit("_",true,1)[0]
		if track_id not in TRACKS:continue
		var track: Variant = host.rebuild_route.tracks[track_id]
		var mat := ShaderMaterial.new()
		mat.shader=shader
		mat.set_shader_parameter("single_lane",track.single_lane)
		mat.set_shader_parameter("rail_offset",0.26 if track.kind=="grind" else 0.72)
		node.material_override=mat
		count["native_bed_surface_batches"] = int(count.get("native_bed_surface_batches",0))+1

func _trackwork() -> void:
	_dress_existing_deck()
	for track_id: String in TRACKS:
		var track: Variant = host.rebuild_route.tracks[track_id]
		var space := _space(track_id)
		var length: float = track.length
		var half: float = 2.2 if track.single_lane else 6.9
		# The deck edge is broken into short cast segments, not a continuous giant colored plane.
		for i in range(ceili(length/7.6)):
			var span := minf(7.6,length-float(i)*7.6)
			if span<1.0:continue
			var s := float(i)*7.6+span*0.5
			var pose: Transform3D = host._pose(track_id,s)
			for side: float in [-1.0,1.0]:
				var x := side*(half+1.05)
				var size := Vector3(0.85,0.54,span-0.35)
				var edge := _at(pose,Vector3(x,-0.46,0))
				# Protect every branch; no route/camera geometry is hidden to fit these pieces.
				if not host._route_clear(AABB(-size*0.5,size),edge,6.8): continue
				_queue(size,edge,"596057","cast_guard_base",space)
				_queue(Vector3(0.92,0.12,span-0.35),_at(pose,Vector3(x,-0.14,0)),"b59a45" if i%3!=1 else "575c53","guard_cap",space)
				for z: float in [-span*0.31,span*0.31]:
					_queue(Vector3(0.17,0.08,0.21),_at(pose,Vector3(x,-0.04,z)),"343b37","guard_bolt",space)

func _safe_group(pose: Transform3D, size: Vector3, offset: Vector3) -> bool:
	return host._route_clear(AABB(offset-size*0.5,size),pose,7.0)

func _practicals() -> void:
	for track_id: String in TRACKS:
		var track: Variant = host.rebuild_route.tracks[track_id]
		var space := _space(track_id)
		for i in range(ceili(track.length/56.0)):
			var s := minf(17.0+float(i)*56.0,track.length-12.0)
			var pose: Transform3D = host._pose(track_id,s)
			var side := -1.0 if i%2==0 else 1.0
			# The main branch flies beneath the right terminal bracket of this elevated catch rail.
			# Move the complete final fixture to the left: base, inward-facing G1 head and all support members.
			if track_id == "canyon_fast_catch" and i == 3: side = -1.0
			var base := _at(pose,Vector3(side*9.65,-0.25,0))
			# Whole lamp including its inward angled arm must clear the same protected corridor.
			if not _safe_group(base,Vector3(3.4,6.0,2.8),Vector3(-side*0.35,2.7,0)): continue
			_outrigger(pose,side*9.65,2.2 if track.single_lane else 6.9,space,"lamp")
			_lamp(base,side,space)

func _outrigger(pose: Transform3D, x: float, deck_half: float, space: String, role: String) -> void:
	# Attach each outboard fixture to the actual rail support; nothing floats over the canyon.
	var inner := signf(x)*(deck_half+0.20)
	var span := absf(x-inner)+1.0
	_queue(Vector3(span,0.38,1.8),_at(pose,Vector3((x+inner)*0.5,-1.20,0)),"404b43",role+"_outrigger",space)
	_queue(Vector3(0.55,2.15,1.25),_at(pose,Vector3(inner,-2.30,0)),"4c574c",role+"_support_web",space)
	_queue(Vector3(0.68,1.10,1.38),_at(pose,Vector3(x,-0.72,0)),"525d4f",role+"_outer_mount",space)
	for z: float in [-0.52,0.52]:
		var a: Vector3 = pose*Vector3(inner,-3.25,z)
		var b: Vector3 = pose*Vector3(x,-1.31,z)
		var axis := Basis.looking_at((b-a).normalized(),pose.basis.z)
		_queue(Vector3(0.25,0.35,a.distance_to(b)),Transform3D(axis,(a+b)*0.5),"677160",role+"_diagonal_stay",space)

func _prepare_reused_lamp() -> void:
	var template: Node3D = host.sample_templates.get(SPEED_LAMP+":near")
	if template==null:
		host.errors.append("Nearfield requires loaded G1 bent-elbow lamp template")
		return
	var measured: Dictionary = host.measure(template)
	var bounds: AABB = measured.bounds
	if not measured.finite or absf(bounds.size.y-1.0)>0.02:
		host.errors.append("Nearfield G1 lamp must retain normalized height1 source")
		return
	host.source_boxes[SPEED_LAMP] = bounds

func _lamp(pose: Transform3D, side: float, space: String) -> void:
	# Existing image-conditioned G1 fixture carries the authored casting, pivots and chipped paint.
	# Its normalized facing is -Z; rotate the head inward towards the rail.
	if not host.source_boxes.has(SPEED_LAMP):return
	var facing := pose.rotated_local(Vector3.UP,side*PI*0.5)
	var model: Node3D = host._model(SPEED_LAMP,facing,4.8,space,"nearfield_G1_worklamp")
	if model!=null: count["G1_worklamp"] = int(count.get("G1_worklamp",0))+1

func _action_housings() -> void:
	# Side-mounted launch machinery explains the preserved native release strip.
	var ramp: Variant = host.rebuild_route.tracks["station_ramp"]
	for s: float in [12.0,30.0]:
		if s>ramp.length-2.0:continue
		var pose: Transform3D = host._pose("station_ramp",s)
		for side: float in [-1.0,1.0]:
			var base := _at(pose,Vector3(side*9.8,-0.35,0))
			if not _safe_group(base,Vector3(3.2,4.6,5.8),Vector3(-side*0.15,1.7,0)):continue
			_outrigger(pose,side*9.8,6.9,"N02","launch")
			_machine(base,side,"N02","launch")
	# Open lateral catch arms only: no new overhead bar crosses the flight path.
	for track_id: String in ["canyon_safe","canyon_fast_catch"]:
		for s: float in [9.0,37.0]:
			var pose: Transform3D = host._pose(track_id,s)
			for side: float in [-1.0,1.0]:
				var base := _at(pose,Vector3(side*10.4,-0.35,0))
				if not _safe_group(base,Vector3(3.5,5.8,6.2),Vector3(-side*0.2,2.0,0)):continue
				_outrigger(pose,side*10.4,2.2 if track_id=="canyon_fast_catch" else 6.9,"N02","catch")
				_machine(base,side,"N02","catch")

func _machine(pose: Transform3D, side: float, space: String, kind: String) -> void:
	_queue(Vector3(2.3,0.50,4.5),_at(pose,Vector3(0,0.25,0)),"414b43",kind+"_skid",space)
	_queue(Vector3(1.8,1.1,3.0),_at(pose,Vector3(0,1.0,0)),"b59a45",kind+"_gearbox",space)
	_queue(Vector3(1.15,0.42,3.6),_at(pose,Vector3(0,1.75,0)),"343f38",kind+"_shoulder",space)
	var arm := _at(pose,Vector3(-side*0.25,2.75,-0.6)).rotated_local(Vector3.RIGHT,-0.28)
	_queue(Vector3(0.65,2.4,1.05),arm,"b39a4b",kind+"_articulated_arm",space)
	_queue(Vector3(1.28,0.78,0.84),_at(pose,Vector3(-side*0.25,3.95,-0.94)),"4d574c",kind+"_open_jaw",space)
	_queue(Vector3(0.95,0.30,0.18),_at(pose,Vector3(-side*0.25,4.05,-1.40)),"c8ae5f" if kind=="launch" else "56bdb5",kind+"_edge_lens",space,true)
	for z: float in [-1.1,1.1]:
		_queue(Vector3(0.20,0.75,0.75),_at(pose,Vector3(-side*0.95,1.25,z)),"333f37",kind+"_gear_axle",space)
		_queue(Vector3(0.22,0.40,0.40),_at(pose,Vector3(-side*1.07,1.25,z)),"929b87",kind+"_axle_cap",space)

func _vehicle_trim() -> void:
	var geometry := session.get_node_or_null(host.GEOMETRY_PATH) as Node3D
	if geometry==null or geometry.has_node("ReconstructionCarrierTrim"):return
	var trim := Node3D.new()
	trim.name="ReconstructionCarrierTrim"
	geometry.add_child(trim)
	var envelope := AABB(Vector3(-1.3,0,-6),Vector3(2.6,3.4,12))
	for sign_z: float in [-1.0,1.0]:
		_vehicle_box(trim,Vector3(2.42,0.26,0.28),Vector3(0,0.55,sign_z*5.75),"b19846","end_bumper",envelope)
		for x: float in [-0.87,0.87]:
			_vehicle_box(trim,Vector3(0.32,0.22,0.16),Vector3(x,0.95,sign_z*5.84),"cdbd7b","end_lamp",envelope)
			_vehicle_box(trim,Vector3(0.20,0.45,0.27),Vector3(x,0.92,sign_z*5.60),"424e43","bumper_bracket",envelope)
	host._tag_tree(trim,"odd-logistics:reconstruction:carrier_trim","authored_carrier_end_trim","station")
	host.instance_reports.append({"id":"odd-logistics:reconstruction:carrier_trim","role":"player_vehicle_visual_trim",
		"parent":host.GEOMETRY_PATH,"parts":vehicle_parts,"envelope_m":host.box_record(envelope),
		"moving_owner":"Original Geometry/TrickPivot","collision_changes":0,"source_vehicle_retained":true})

func _vehicle_box(parent: Node3D,size: Vector3,at: Vector3,color: String,role: String,envelope: AABB) -> void:
	var bounds := AABB(at-size*0.5,size)
	if not envelope.encloses(bounds):return
	var mesh := BoxMesh.new()
	mesh.size=size
	var node := MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=host._mat(color,false,0.6)
	node.position=at
	parent.add_child(node)
	vehicle_parts.append({"role":role,"bounds_geometry_local":host.box_record(bounds)})
