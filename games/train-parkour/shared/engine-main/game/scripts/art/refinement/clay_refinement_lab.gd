extends "res://scripts/art/production/clay_production_lab.gd"
## Refinement remains a presentation-only sibling; shared gameplay and camera stay authoritative.
const Surface = preload("res://scripts/art/refinement/clay_surface.gd")
var surface := Surface.new()
var mass_slots: Array[Dictionary] = []
var extra_root: Node3D
var mesh_assets := {}
var assembly: Array[Dictionary] = []
var lux_available := {}
var scenery_samples: Array[Vector3] = []
var authored_meshes := 0
func _init() -> void:kit=preload("res://scripts/art/refinement/clay_refinement_kit.gd").new()
func _pilot_chunk(_chunk: String) -> bool: return false
func _ready() -> void:
	super._ready()
	extra_root = Node3D.new();extra_root.name="RefinedWorld";add_child(extra_root)
	for t: SpatialTrack in route.tracks.values():
		for n in ceili(t.length/10.0)+1:scenery_samples.append(t.pose(minf(n*10.0,t.length)).origin)
	for id in ["garden-planter","shrub-cluster","lavender-outcrop","garden-fountain"]:
		lux_available[id]=ResourceLoader.exists("res://assets/clay-refinement/"+id+".glb")
	_build_grounded_world()
	_build_arcades()
	_build_landscape_belts()
	_build_secondary_gallery()
	_build_tunnel_exterior()
	_build_water()
	_convert_materials(self)
	var env: Environment = $EnvironmentRoot/WorldEnvironment.environment
	env.ambient_light_color=Color("c2d2e3");env.ambient_light_energy=.36;env.tonemap_exposure=.92
	env.ssao_enabled=true;env.ssao_radius=1.8;env.ssao_intensity=1.3;env.ssao_detail=1.0
	env.ssil_enabled=false;env.ssil_radius=5.0;env.ssil_intensity=.7
	env.fog_density=.000065;env.fog_light_color=Color("a9cddd")
	$EnvironmentRoot/Sun.light_energy=1.15;$EnvironmentRoot/Sun.light_color=Color("ffe7c4")
	$EnvironmentRoot/Sun.light_angular_distance=.8;$EnvironmentRoot/Sun.directional_shadow_max_distance=350
	$EnvironmentRoot/Sun.directional_shadow_blend_splits=true
	_batch_assets(extra_root)
	_batch_assets(production_root)
	print("CLAY_REFINEMENT_READY assets=",assembly.size()," authored_meshes=",authored_meshes)
func _batch(parent: Node3D,label: String,size: Vector3,material: Material,poses: Array[Transform3D],range_end: float=1100.0) -> void:
	var before:=parent.get_child_count()
	super._batch(parent,label,size,material,poses,range_end)
	var underpass_shell:=str(parent.name).begins_with("underpass_") and label in ["ContactStructure","TunnelLamps","TunnelDecorFrames"]
	var replaced:=underpass_shell or label in ["NearMasses","DistantPiers","ValleyWalls","FinalRidges","StationGround","ValleyFloor","FinalFloor","Riverbed","StationPlatforms","TerminalStation","TerminalGate","HubBeacon","Block","LowBeam","VerticalStationFrame"]
	if replaced:
		for i in range(before,parent.get_child_count()):
			var child=parent.get_child(i)
			if child is Node3D:child.hide()
	if label in ["NearMasses","DistantPiers","ValleyWalls","FinalRidges","StationGround","ValleyFloor","FinalFloor","HubBeacon","VerticalStationFrame"]:
		for p in poses:mass_slots.append({"kind":label,"pose":parent.global_transform*p,"dimensions":p.basis.get_scale()*size})
	if label in ["Block","LowBeam"]:
		for p in poses:_obstacle(parent,p,size,label)
	if not replaced:
		for i in range(before,parent.get_child_count()):
			var child=parent.get_child(i)
			if child is MultiMeshInstance3D and label in ["TrackPiers","BridgePiers","HubBridge","LoopRibs","CoilStation","ContactStructure"]:child.material_override=surface.material("cream" if label in ["TrackPiers","BridgePiers","HubBridge"] else "peach")
func _piece_at(parent: Node3D,mesh: Mesh,pose: Transform3D,mat: Material,label: String) -> MeshInstance3D:
	var n:=MeshInstance3D.new();n.mesh=mesh;n.material_override=mat;n.name=label;parent.add_child(n);n.transform=pose;n.visibility_range_end=1400;authored_meshes+=1;return n
func _box_at(parent: Node3D,pose: Transform3D,dim: Vector3,mat: Material,label: String) -> MeshInstance3D:
	return _piece_at(parent,surface.box(dim),pose,mat,label)
func _obstacle(parent: Node3D,p: Transform3D,size: Vector3,label: String) -> void:
	var dim:=p.basis.get_scale()*size;var pose:=p.orthonormalized()
	_box_at(parent,pose,dim,surface.material("red"),"CeramicSafetyBody")
	var panel:=pose.translated_local(Vector3(0,0,dim.z*.5+.07))
	_box_at(parent,panel,Vector3(dim.x*.91,minf(dim.y*.65,1.45),.13),surface.material("cream"),"WarningPanel")
	for sign in [-1,0,1]:
		var stripe:=panel.translated_local(Vector3(sign*dim.x*.26,0,.09)).rotated_local(Vector3.FORWARD,-.42)
		_box_at(parent,stripe,Vector3(dim.x*.16,minf(dim.y*.48,1.08),.04),surface.material("red"),"RedStripe")
	if label=="Block":
		_box_at(parent,pose.translated_local(Vector3(0,dim.y*.5-.15,0)),Vector3(dim.x,.3,dim.z),surface.material("cream"),"CreamHood")
func _kit_asset(parent: Node3D,id: String,pose: Transform3D) -> Node3D:
	var path:="res://assets/clay-refinement/"+id+".glb"
	if not ResourceLoader.exists(path):path="res://assets/clay-production/"+id+".glb"
	if not mesh_assets.has(path):mesh_assets[path]=load(path)
	var node: Node3D=mesh_assets[path].instantiate();parent.add_child(node);node.transform=pose
	node.set_meta("asset_instance",true);node.set_meta("asset_kind",id)
	assembly.append({"id":id,"origin":[pose.origin.x,pose.origin.y,pose.origin.z],"basis":[[pose.basis.x.x,pose.basis.x.y,pose.basis.x.z],[pose.basis.y.x,pose.basis.y.y,pose.basis.y.z],[pose.basis.z.x,pose.basis.z.y,pose.basis.z.z]]})
	return node
func _build_gallery() -> void:
	var t: SpatialTrack=route.tracks.tunnel
	for index in ceili(t.length/120):
		var a:=index*120.0;var b:=minf(a+120,t.length);var chunk:=Node3D.new();production_root.add_child(chunk);chunk.position=t.pose(a).origin
		kit.sweep(chunk,"InnerGallery",t,a,b,kit.tunnel_profile(20.2,13.6),surface.material("lavender"),Vector2.ZERO,true)
		kit.sweep(chunk,"ClayGalleryFloor",t,a,b,kit.round_rect(20.2,-.85,-.42,.1),surface.material("floor","",0,true))
		for side in [-1,1]:
			kit.sweep(chunk,"RaisedPromenade",t,a,b,kit.round_rect(5.1,-.35,.60,.12),surface.material("cream","",0,true),Vector2(side*14.4,0))
			kit.sweep(chunk,"TerracottaDado",t,a,b,kit.round_rect(.42,.55,2.2,.14),surface.material("peach"),Vector2(side*19.6,0))
			kit.sweep(chunk,"CreamDadoCap",t,a,b,kit.round_rect(.50,2.05,2.30,.08),surface.material("cream"),Vector2(side*19.5,0))
	for n in ceili(t.length/32.0):
		var s:=minf(n*32.0+3,t.length-1)
		_kit_asset(production_root,"gallery-frame",t.pose(s))
		for side in [-1,1]:
			var lamp_pose:=t.pose(s+12).translated_local(Vector3(side*10.8,.6,0))
			_kit_asset(production_root,"way-bollard",lamp_pose)
			if n%2==0:
				_kit_asset(production_root,"ceramic-lantern",lamp_pose.translated_local(Vector3(side*3,0,1)))
			if n%3!=2:
				var niche_pose:=t.pose(s+17).translated_local(Vector3(side*19.15,.6,0)).rotated_local(Vector3.UP,-side*PI/2)
				_kit_asset(production_root,"arched-niche",niche_pose)
			if n%3==0:
				_kit_asset(production_root,"service-cabinet",t.pose(s+22).translated_local(Vector3(side*16,.6,0)).rotated_local(Vector3.UP,-side*PI/2))
				_kit_asset(production_root,"wall-vent",t.pose(s+22).translated_local(Vector3(side*19,3.9,0)).rotated_local(Vector3.UP,-side*PI/2))
			if n%3==1:_kit_asset(production_root,"platform-bench",t.pose(s+22).translated_local(Vector3(side*15,.6,0)).rotated_local(Vector3.UP,-side*PI/2))
			var light:=OmniLight3D.new();production_root.add_child(light);light.position=t.pose(s)*Vector3(side*16.0,6.2,0);light.light_color=Color("ffdb9d");light.light_energy=4.5;light.omni_range=26;light.omni_attenuation=.8
			light.distance_fade_enabled=true;light.distance_fade_begin=120;light.distance_fade_length=45
			light.shadow_enabled=n%2==0;light.shadow_bias=.06;light.distance_fade_shadow=70
	for s in [0.0,t.length]:
		_kit_asset(production_root,"gallery-frame",t.pose(s))
func _build_station_furniture() -> void:
	for id in ["station_start","station_carve","victory_run"]:
		var t: SpatialTrack=route.tracks[id]
		for index in ceili(t.length/100):
			var a:=index*100.0;var b:=minf(a+100,t.length);var chunk:=Node3D.new();production_root.add_child(chunk);chunk.position=t.pose(a).origin
			for side in [-1,1]:kit.sweep(chunk,"StationPromenade",t,a,b,kit.round_rect(5.5,-1.8,.55,.2),surface.material("cream","",0,true),Vector2(side*15,0))
		for n in ceili(t.length/28.0):
			var s:=minf(12+n*28.0,t.length-1)
			for side in [-1,1]:
				var frame:=t.pose(s).translated_local(Vector3(side*18,.55,0))
				_kit_asset(production_root,"station-column",frame)
				if n%2==0:_kit_asset(production_root,"ceramic-lantern",t.pose(s+10).translated_local(Vector3(side*10.8,.55,0)))
				if n%3==0:_kit_asset(production_root,"platform-bench",t.pose(s+15).translated_local(Vector3(side*15,.55,0)))
			if id in ["station_start","victory_run"]:
				_box_at(production_root,t.pose(s).translated_local(Vector3(0,13.4,0)),Vector3(39,1.1,1.4),surface.material("cream"),"CanopyCrossbeam")
				for side in [-1,1]:
					_box_at(production_root,t.pose(s).translated_local(Vector3(side*15,12.8,0)),Vector3(10.5,.8,28),surface.material("teal"),"CanopyCoffer")
func _landform(dim: Vector3, seed_value: int) -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Array[float]=[0.0,.04,.12,.32,.35,.60,.64,.88,.97,1.0]
	var radii: Array[float]=[.82,.95,1.0,.94,.85,.84,.71,.70,.61,.52]
	var rings: Array[PackedVector3Array]=[]
	for j in heights.size():
		var ring:=PackedVector3Array()
		for k in 48:
			var angle:=TAU*k/48.0
			var rx:=signf(cos(angle))*pow(absf(cos(angle)),.68)
			var rz:=signf(sin(angle))*pow(absf(sin(angle)),.68)
			var wobble:=.965+.035*sin(angle*5+seed_value*.7+j*.28)
			ring.append(Vector3(rx*dim.x*.5*radii[j]*wobble,dim.y*(heights[j]-.5),rz*dim.z*.5*radii[j]*wobble))
		rings.append(ring)
	for j in rings.size()-1:
		for k in 48:
			var b:=(k+1)%48
			for point in [rings[j][k],rings[j][b],rings[j+1][k],rings[j][b],rings[j+1][b],rings[j+1][k]]:st.add_vertex(point)
	for k in 48:
		for point in [Vector3(0,dim.y*.5,0),rings[-1][k],rings[-1][(k+1)%48]]:st.add_vertex(point)
	st.generate_normals();return st.commit()
func _clear_ground(center: Vector3, dim: Vector3) -> bool:
	for p in scenery_samples:
		if absf(p.x-center.x)<dim.x*.53+10 and absf(p.z-center.z)<dim.z*.53+10 and p.y>center.y-dim.y*.5-12 and p.y<center.y+dim.y*.5+12:return false
	return true
func _plant(parent: Node3D, pose: Transform3D, scale_value: float=1.0, shrub: bool=false) -> void:
	var id:="shrub-cluster" if shrub else "garden-planter"
	if lux_available.get(id,false):_kit_asset(parent,id,pose.scaled_local(Vector3.ONE*scale_value))
	else:
		var n:=Node3D.new();parent.add_child(n);n.transform=pose
		_asset(n,"cypress",Vector3.ZERO,scale_value*.38)
func _build_grounded_world() -> void:
	for i in mass_slots.size():
		var slot: Dictionary=mass_slots[i];var pose: Transform3D=slot.pose;var dim: Vector3=slot.dimensions;pose=pose.orthonormalized()
		var kind: String=slot.kind
		if kind=="VerticalStationFrame":
			if dim.y>dim.x*3 and dim.y>dim.z*3:
				var radius:=minf(dim.x,dim.z)*.48
				_piece_at(extra_root,kit.cylinder(radius,dim.y),pose,surface.material("peach"),"VerticalClayColumn")
				for side in [-1,1]:
					_piece_at(extra_root,kit.cylinder(radius*1.1,1.5),pose.translated_local(Vector3(0,side*(dim.y*.5-.75),0)),surface.material("cream"),"ColumnCapital")
			else:_box_at(extra_root,pose,dim,surface.material("cream"),"VerticalClaySupport")
			continue
		if kind=="HubBeacon":
			if dim.y>dim.x*3:
				_piece_at(extra_root,kit.cylinder(dim.x*.46,dim.y,dim.x*.35),pose,surface.material("peach"),"LandmarkPylon")
				for level in ceili(dim.y/42.0):
					_piece_at(extra_root,kit.cylinder(dim.x*.53,.8),pose.translated_local(Vector3(0,-dim.y*.5+level*42.0,0)),surface.material("cream"),"PylonBand")
				_kit_asset(extra_root,"domed-tower",pose.translated_local(Vector3(0,dim.y*.5,0)).scaled_local(Vector3.ONE*1.1))
			else:
				_box_at(extra_root,pose,dim,surface.material("cream"),"LandmarkCrownBeam")
			continue
		if kind=="StationGround":
			_box_at(extra_root,pose,dim,surface.material("cream"),"StationIslandDeck")
			continue
		if kind in ["ValleyFloor","FinalFloor"]:
			_piece_at(extra_root,_landform(dim,i),pose,surface.material("lavender"),"ContinuousValleyLand")
			continue
		var top:=pose.origin.y+dim.y*.5
		var old_bottom:=pose.origin.y-dim.y*.5
		if old_bottom>-48:
			var extension:=Vector3(dim.x,old_bottom+48,dim.z)
			var extension_center:=Vector3(pose.origin.x,(-48+old_bottom)*.5,pose.origin.z)
			if _clear_ground(extension_center,extension):dim.y=top+48;pose.origin.y=(top-48)*.5
		_piece_at(extra_root,_landform(dim,i),pose,surface.material("lavender",["b2a0c5","a391b8","bdaac9","998cab"][i%4]),"GroundedClayCliff")
		if kind in ["NearMasses","ValleyWalls","FinalRidges"] and i%3!=1:_cliff_terrace(pose.origin,dim,i)
		var crown:=Transform3D(Basis.IDENTITY,Vector3(pose.origin.x,top,pose.origin.z))
		if kind=="DistantPiers" or i%4==0:
			var scale_value:=clampf(minf(dim.x,dim.z)/15.0,.65,2.3)
			_kit_asset(extra_root,"domed-tower",crown.scaled_local(Vector3.ONE*scale_value))
		elif i%3==1 and lux_available.get("lavender-outcrop",false):
			_kit_asset(extra_root,"lavender-outcrop",crown.scaled_local(Vector3.ONE*minf(dim.x/24.0,1.2)))
		for j in 2:
			var point:=crown.translated_local(Vector3((j-.5)*dim.x*.30,0,(i%3-1)*dim.z*.14))
			_plant(extra_root,point,.9+i%3*.23,i%2==0)
func _build_arcades() -> void:
	for id in ["station_start","station_carve","victory_run"]:
		var t: SpatialTrack=route.tracks[id]
		for n in ceili(t.length/13.0):
			var s:=minf(n*13.0+5,t.length-1)
			for side in [-1,1]:
				var pose:=t.pose(s).translated_local(Vector3(side*20,.5,0)).rotated_local(Vector3.UP,-side*PI/2)
				_kit_asset(extra_root,"arcade-wall",pose)
				if n%3==0:_plant(extra_root,t.pose(s).translated_local(Vector3(side*13,.6,3)),.78)
		for n in ceili(t.length/90.0):
			var s:=minf(n*90.0+42,t.length-2)
			for side in [-1,1]:
				var base:=t.pose(s).translated_local(Vector3(side*27,-2,0))
				_box_at(extra_root,base.translated_local(Vector3(0,-3,0)),Vector3(12,6,14),surface.material("cream"),"TowerFoundation")
				_kit_asset(extra_root,"domed-tower",base.scaled_local(Vector3.ONE*1.4))
				if lux_available.get("garden-fountain",false) and n%2==0:_kit_asset(extra_root,"garden-fountain",t.pose(s+15).translated_local(Vector3(14,.6,0)).scaled_local(Vector3.ONE*.7))
	var tunnel: SpatialTrack=route.tracks.tunnel
	for n in ceili(tunnel.length/32.0):
		for side in [-1,1]:_plant(extra_root,tunnel.pose(minf(n*32.0+9,tunnel.length)).translated_local(Vector3(side*13.8,.6,0)),.70)
	for s in [0.0,tunnel.length]:
		for side in [-1,1]:
			var pose:=tunnel.pose(s).translated_local(Vector3(side*37,-3,0))
			_piece_at(extra_root,_landform(Vector3(30,48,60),37),pose,surface.material("lavender"),"GroundedPortalCliff")
			_kit_asset(extra_root,"domed-tower",pose.translated_local(Vector3(0,24,0)).scaled_local(Vector3.ONE*1.25))
			_plant(extra_root,pose.translated_local(Vector3(side*4,24,-9)),1.8)

	# Support spans are authored below the contact surface and rejected near a lower route.
	for id in ["cliff_turn","receiver_high","valley_slalom","final_runup","final_ground"]:
		if not route.tracks.has(id):continue
		var t: SpatialTrack=route.tracks[id]
		for n in ceili(t.length/28.0):
			var pose:=t.pose(minf(14+n*28.0,t.length)).translated_local(Vector3(0,-12,0)).rotated_local(Vector3.UP,PI/2)
			if _clear_ground(pose.origin+Vector3(0,4,0),Vector3(9,6,16)):_kit_asset(extra_root,"arcade-wall",pose)
func _build_water() -> void:
	var water:=ShaderMaterial.new();water.shader=load("res://materials/clay-refinement/water.gdshader")
	for n in find_children("*","MeshInstance3D",true,false):
		if n.mesh is PlaneMesh and n.mesh.size.x>1000:n.material_override=water
func _convert_materials(node: Node,kind: String="") -> void:
	if node.has_meta("asset_kind"):kind=str(node.get_meta("asset_kind"))
	if node is MeshInstance3D and node.mesh!=null:
		if node.material_override!=null:node.material_override=surface.converted(node.material_override)
		else:
			for index in node.mesh.get_surface_count():
				var mat: Material=surface.converted(node.get_active_material(index))
				if kind=="lavender-outcrop" and mat is ShaderMaterial:
					mat.set_shader_parameter("clay_color",Color("ac98c1"));mat.set_shader_parameter("remap_texture",true)
				node.set_surface_override_material(index,mat)
	elif node is MultiMeshInstance3D and node.material_override!=null:node.material_override=surface.converted(node.material_override)
	for child in node.get_children():_convert_materials(child,kind)
func _batch_assets(parent: Node3D) -> void:
	var groups: Dictionary={};var roots: Array[Node3D]=[]
	for n: Node3D in parent.find_children("*","Node3D",true,false):
		if n.has_meta("asset_instance"):roots.append(n)
	for instance in roots:
		for part: MeshInstance3D in instance.find_children("*","MeshInstance3D",true,false):
			var cell: Vector3i=Vector3i((part.global_position/180.0).floor())
			var key:=str(part.mesh.get_instance_id())+str(cell)
			for s in part.mesh.get_surface_count():key+=str(part.get_active_material(s).get_instance_id())
			if not groups.has(key):groups[key]={"part":part,"poses":[],"center":Vector3(cell)*180}
			groups[key].poses.append(part.global_transform)
	for group: Dictionary in groups.values():
		var part: MeshInstance3D=group.part
		var mesh: Mesh=part.mesh.duplicate()
		for s in mesh.get_surface_count():mesh.surface_set_material(s,part.get_active_material(s))
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=group.poses.size()
		for i in group.poses.size():
			var pose: Transform3D=group.poses[i];pose.origin-=group.center;mm.set_instance_transform(i,pose)
		var batch:=MultiMeshInstance3D.new();parent.add_child(batch);batch.global_position=group.center;batch.multimesh=mm;batch.visibility_range_end=1100
	for instance in roots:instance.free()

func _build_exact_rails() -> void:
	var deck := surface.material("floor")
	var rail := surface.material("rail")
	var gold := surface.material("gold","",.08)
	var sleeper := surface.material("sleeper")
	for t: SpatialTrack in (route as SpatialRoute).tracks.values():
		for index in ceili(t.length/120.0):
			var a := index*120.0
			var b := minf(a+120,t.length)
			var chunk := Node3D.new()
			chunk.name = "Precise_"+t.id+"_"+str(index)
			production_root.add_child(chunk)
			chunk.position = t.pose(a).origin
			kit.sweep(chunk,"ClayDeck",t,a,b,kit.round_rect(1.0,-0.7,-0.08,0.10),deck,Vector2.ZERO,false,true)
			for lane in t.lanes():
				for side in [-1,1]:
					kit.sweep(chunk,"ClayRail",t,a,b,kit.round_rect(0.095,-0.015,0.165,0.035),gold if t.single_lane else rail,Vector2(lane*4.4+side*(0.26 if t.kind=="grind" else 0.72),0))
			var ties: Array[Transform3D] = []
			for n in range(ceili(a/2.4),ceili(b/2.4)):
				for lane in t.lanes():
					var pose := t.pose(n*2.4,lane*4.4)
					pose.origin -= chunk.position
					ties.append(pose)
			_rigid_instances(chunk,"Sleepers","rail-sleeper",ties,sleeper)
			if t.kind in ["loop","wall","inverted","grind"]:
				kit.sweep(chunk,"StructuralSpine",t,a,b,kit.round_rect(0.9,-1.6,-0.73,0.15),surface.material("peach"))

func _lantern(parent: Node3D,pose: Transform3D,color: String,factor: float,semantic: String) -> void:
	# Near-speed markers have no structural meaning; replace their rhythm on the actual deck.
	if semantic=="receiver_lantern":super._lantern(parent,pose,color,factor,semantic)
func _build_landscape_belts() -> void:
	var index:=0
	for id in ["station_start","canyon_safe","canyon_fast","rush","carve","loop_entry","loop_out","relay","cliff_turn","upper","finish","landmark_return","return_switchback","final_approach","victory_run"]:
		var t: SpatialTrack=route.tracks[id]
		for n in ceili(t.length/110.0):
			var s:=minf(40+n*110.0,t.length)
			var frame:=t.pose(s);var right:=Vector3(frame.basis.x.x,0,frame.basis.x.z).normalized()
			if right.length()<.8:right=Vector3.RIGHT
			for side in [-1,1]:
				index+=1
				var top:=frame.origin.y+24+sin(index*1.7)*28
				var center: Vector3=frame.origin+right*side*(128+sin(index*.9)*18);center.y=(top-49)*.5
				var dim:=Vector3(132,top+49,170)
				if not _clear_ground(center,dim):continue
				_piece_at(extra_root,_landform(dim,index),Transform3D(Basis.IDENTITY,center),surface.material("lavender",["b5a3c4","a495b9","beadcc"][index%3]),"RegionalClayIsland")
				_piece_at(extra_root,_landform(Vector3(dim.x*.54,1.4,dim.z*.54),index),Transform3D(Basis.IDENTITY,Vector3(center.x,top,center.z)),surface.material("sage","95a381"),"GardenTerrace")
				for j in 3:
					var crown:=Transform3D(Basis.IDENTITY,Vector3(center.x+(j-1)*18,top+.65,center.z+sin(j*3)*15))
					if j==1 and index%3==0:
						_kit_asset(extra_root,"domed-tower",crown.scaled_local(Vector3.ONE*2.1))
						_kit_asset(extra_root,"arcade-wall",crown.translated_local(Vector3(17,0,0)).scaled_local(Vector3.ONE*1.35))
					else:_plant(extra_root,crown,2.5+index%3,true)
				if lux_available.get("lavender-outcrop",false):
					for j in 3:
						var p:=Transform3D(Basis.IDENTITY,Vector3(center.x+(j-1)*20,top+.65,center.z-25))
						_kit_asset(extra_root,"lavender-outcrop",p.scaled_local(Vector3.ONE*2.0))
				if index%5==0:_waterfall(Vector3(center.x-side*dim.x*.42,top-2,center.z),top+46,12.0)
	for t: SpatialTrack in route.tracks.values():
		if t.id=="tunnel":continue
		for n in ceili(t.length/24.0):
			var s:=minf(n*24.0+6,t.length)
			for side in [-1,1]:
				var pose:=t.pose(s).translated_local(Vector3(side*(t.width_at(s)-.18),0,0))
				_kit_asset(extra_root,"way-bollard",pose.scaled_local(Vector3.ONE*.38))
func _waterfall(top: Vector3,height: float,width: float) -> void:
	if height<8:return
	var mesh:=PlaneMesh.new();mesh.size=Vector2(width,height)
	var mat:=ShaderMaterial.new();mat.shader=load("res://materials/clay-refinement/water.gdshader");mat.set_shader_parameter("falling",true)
	var pose:=Transform3D(Basis(Vector3.RIGHT,PI/2),top-Vector3(0,height*.5,0))
	_piece_at(extra_root,mesh,pose,mat,"TealWaterfall")
	var pool:=SphereMesh.new();pool.radius=width*.7;pool.height=2.0;pool.radial_segments=24;pool.rings=8
	_piece_at(extra_root,pool,Transform3D(Basis.IDENTITY,top-Vector3(0,height,0)),surface.material("cream","c8ded7"),"WaterfallFoam")
func _cliff_terrace(center: Vector3,dim: Vector3,index: int) -> void:
	# Put human-scale architecture where the player sees the cliff, not only on its summit.
	var nearest:=Vector3.ZERO;var distance:=INF
	for point in scenery_samples:
		var d:=Vector2(point.x-center.x,point.z-center.z).length_squared()
		if d<distance:distance=d;nearest=point
	if distance>180*180:return
	var normal:=Vector3(nearest.x-center.x,0,nearest.z-center.z).normalized()
	if normal.length()<.9:return
	var radius:=1.0/sqrt(pow(normal.x/(dim.x*.5),2)+pow(normal.z/(dim.z*.5),2))
	var top:=center.y+dim.y*.5
	var level:=minf(nearest.y-3.8,top-12)
	if level<center.y-dim.y*.5+5:return
	var position:=Vector3(center.x,level,center.z)+normal*(radius*.84+1.8)
	var facing:=Basis.looking_at(-normal,Vector3.UP)
	var extent:=facing.x.abs()*17+Vector3.UP*12+facing.z.abs()*6
	if not _clear_ground(position+Vector3(0,5,0),extent):return
	var pose:=Transform3D(facing,position)
	_box_at(extra_root,pose.translated_local(Vector3(0,-1,0)),Vector3(17,2,6),surface.material("cream"),"CliffVillageTerrace")
	for x in [-6,0,6]:
		_box_at(extra_root,pose.translated_local(Vector3(x,-3.5,-1.1)),Vector3(2.2,5,4.4),surface.material("peach"),"TerraceCorbel")
	_kit_asset(extra_root,"arcade-wall",pose.translated_local(Vector3(-1,0,-.8)).scaled_local(Vector3.ONE*.78))
	_kit_asset(extra_root,"arched-niche",pose.translated_local(Vector3(-1,.25,-1.1)).scaled_local(Vector3.ONE*.8))
	_kit_asset(extra_root,"domed-tower",pose.translated_local(Vector3(6.0,0,-1.0)).scaled_local(Vector3.ONE*.56))
	_plant(extra_root,pose.translated_local(Vector3(-6.8,.1,1.8)),.72)
	_plant(extra_root,pose.translated_local(Vector3(2.8,.1,1.8)),.8,true)
	if index%3==0:_kit_asset(extra_root,"ceramic-lantern",pose.translated_local(Vector3(0,.1,2)))
func _build_secondary_gallery() -> void:
	var t: SpatialTrack=route.tracks.underpass
	for index in ceili(t.length/100):
		var a:=index*100.0;var b:=minf(a+100,t.length);var chunk:=Node3D.new();extra_root.add_child(chunk);chunk.position=t.pose(a).origin
		kit.sweep(chunk,"ReturnGallery",t,a,b,kit.tunnel_profile(10.45,13.6),surface.material("lavender"),Vector2.ZERO,true)
		kit.sweep(chunk,"ReturnFloor",t,a,b,kit.round_rect(10.4,-.9,-.42,.10),surface.material("floor","",0,true))
		for side in [-1,1]:
			kit.sweep(chunk,"ReturnWalkway",t,a,b,kit.round_rect(1.25,-.3,.45,.1),surface.material("cream","",0,true),Vector2(side*8.6,0))
			kit.sweep(chunk,"ReturnDado",t,a,b,kit.round_rect(.22,.45,2.0,.08),surface.material("peach"),Vector2(side*10.15,0))
	for n in ceili(t.length/25.0):
		var s:=minf(3+n*25.0,t.length)
		_kit_asset(extra_root,"underpass-frame",t.pose(s))
		for side in [-1,1]:
			_kit_asset(extra_root,"way-bollard",t.pose(s+10).translated_local(Vector3(side*7.75,.45,0)).scaled_local(Vector3.ONE*.5))
			if n%2==0:_plant(extra_root,t.pose(s+14).translated_local(Vector3(side*8.8,.45,0)),.44)
			var light:=OmniLight3D.new();extra_root.add_child(light);light.position=t.pose(s)*Vector3(side*8.5,5.7,0);light.light_color=Color("ffdcac");light.light_energy=2.8;light.omni_range=20;light.omni_attenuation=.7
			light.distance_fade_enabled=true;light.distance_fade_begin=100;light.distance_fade_length=40
			if n%3==1:_kit_asset(extra_root,"arched-niche",t.pose(s+13).translated_local(Vector3(side*10.1,.45,0)).rotated_local(Vector3.UP,-side*PI/2).scaled_local(Vector3.ONE*.65))
func _build_tunnel_exterior() -> void:
	for id in ["tunnel","underpass"]:
		var t: SpatialTrack=route.tracks[id]
		var inner_width:=20.2 if id=="tunnel" else 10.45
		var outer_width:=34.0 if id=="tunnel" else 12.8
		var outer_height:=26.0 if id=="tunnel" else 17.1
		for index in ceili(t.length/100):
			var a:=index*100.0;var b:=minf(a+100,t.length);var chunk:=Node3D.new();extra_root.add_child(chunk);chunk.position=t.pose(a).origin
			kit.sweep(chunk,"ExteriorClayShell",t,a,b,kit.tunnel_profile(outer_width,outer_height),surface.material("lavender"))
			if id=="tunnel":
				for side in [-1,1]:
					var support_frame:=t.pose((a+b)*.5).translated_local(Vector3(side*28,0,0))
					if _foundation_clear(support_frame,Vector3(11,85,b-a),-85,-.5):kit.sweep(chunk,"MountainFoundation",t,a,b,kit.round_rect(5.5,-85,-.5,1.2),surface.material("lavender"),Vector2(side*28,0))
		for end in [0,1]:
			var frame:=t.pose(t.length*end);var inner:=kit.tunnel_profile(inner_width,13.6);var outer:=kit.tunnel_profile(outer_width,outer_height)
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in inner.size()-1:
				var j:=i+1
				var ps: Array[Vector2]=[inner[i],outer[i],outer[j],inner[i],outer[j],inner[j]]
				if end==1:ps.reverse()
				for p in ps:st.add_vertex(Vector3(p.x,p.y,0))
			st.generate_normals()
			var mat:=surface.material("lavender").duplicate();mat.set_shader_parameter("relief",.01)
			_piece_at(extra_root,st.commit(),frame,mat,"SolidPortalOpening")
		if id=="tunnel":
			for n in ceili(t.length/80.0):
				var frame:=t.pose(minf(30+n*80.0,t.length));var crown:=frame.translated_local(Vector3(0,outer_height-.4,0))
				if lux_available.get("lavender-outcrop",false):_kit_asset(extra_root,"lavender-outcrop",crown.scaled_local(Vector3.ONE*1.8))
				_plant(extra_root,crown.translated_local(Vector3(-8,-.7,9)),2.6,true)
