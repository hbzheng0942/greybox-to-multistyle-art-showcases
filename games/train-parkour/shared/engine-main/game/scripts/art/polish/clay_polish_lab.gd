extends "res://scripts/art/refinement/clay_refinement_lab.gd"
## Authored presentation only. The inherited route, physics and camera remain unchanged.
const Landforms=preload("res://scripts/art/polish/clay_landforms.gd")
var building_mass_shell:=false
var land_poses: Dictionary={}
var sign_slots: Array[Transform3D]=[]
var apparatus_slots: Array[Dictionary]=[]
var supports: Array[Dictionary]=[]
var polish_counts: Dictionary={}
var shoulder_waterfalls:=true
var composition: RefCounted
var heroes: RefCounted
var enrichment: RefCounted
var camera_segments: Array[Dictionary]=[]
var camera_cells: Dictionary={}
var prop_dimensions: Dictionary={}
var rejected_camera_props:=0
func _init() -> void:
	super._init()
	surface=preload("res://scripts/art/polish/clay_polish_surface.gd").new()
	_load_camera_corridors()
	composition=preload("res://scripts/art/polish/clay_scene_composer.gd").new(self)
	heroes=preload("res://scripts/art/polish/clay_hero_set.gd").new(self)
	enrichment=preload("res://scripts/art/polish/clay_lux_enrichment.gd").new(self)

func _ready() -> void:
	super._ready()
	_build_structural_arcades()
	shoulder_waterfalls=true
	_build_garden_shoulders()
	_build_gallery_details()
	_build_roller_supports()
	_build_bridge_edges()
	_build_terminal_vista()
	_build_wayfinding()
	_build_side_run_gallery()
	_build_track_hardware()
	_convert_materials(extra_root)
	_batch_assets(extra_root)
	preload("res://scripts/art/polish/clay_lighting.gd").apply(self)
	print("CLAY_POLISH_READY ",JSON.stringify(polish_counts)," camera_props_rejected=",rejected_camera_props)

func _batch(parent: Node3D,label: String,size: Vector3,material: Material,poses: Array[Transform3D],range_end: float=1100.0) -> void:
	var before:=parent.get_child_count()
	super._batch(parent,label,size,material,poses,range_end)
	if label=="ContactStructure" and str(parent.name).begins_with("wall_"):
		for i in range(before,parent.get_child_count()):
			if parent.get_child(i) is Node3D:parent.get_child(i).hide()
	if label in ["ReleaseWindow","ApproachMarks","Clamps"]:
		for i in range(before,parent.get_child_count()):
			var child=parent.get_child(i)
			if child is MultiMeshInstance3D:
				child.multimesh.mesh=surface.box(size,.08)
				child.material_override=surface.material("red" if label=="ApproachMarks" else "gold" if label=="ReleaseWindow" else "teal")
	if label in ["NoEntrySign","NoEntryBar","CatchGate","GoldGrindCatch"]:
		for i in range(before,parent.get_child_count()):
			var node=parent.get_child(i)
			if node is Node3D:node.hide()
		if label=="NoEntrySign":
			for pose in poses:sign_slots.append(parent.global_transform*pose.orthonormalized())
		elif label in ["CatchGate","GoldGrindCatch"]:
			for pose in poses:apparatus_slots.append({"pose":parent.global_transform*pose.orthonormalized(),"dim":pose.basis.get_scale()*size,"kind":label})
	if label in ["LoopRibs","CoilStation","TrackPiers","BridgePiers"]:
		for i in range(before,parent.get_child_count()):
			var node=parent.get_child(i)
			if node is Node3D:node.hide()
		if label in ["TrackPiers","BridgePiers"]:
			for p in poses:supports.append({"pose":parent.global_transform*p,"dim":p.basis.get_scale()*size})

func _kit_asset(parent: Node3D,id: String,pose: Transform3D) -> Node3D:
	if building_mass_shell and id in ["lavender-outcrop","garden-planter","shrub-cluster"]:return null
	if id in ["belfry-tower","domed-tower","terrace-house"]:
		pose=preload("res://scripts/art/polish/clay_scene_composer.gd").upright(pose)
	if id in ["gallery-frame","gallery-trim"]:pose=pose.scaled_local(Vector3(.85,1,1))
	var actual:="rounded-cliff" if id=="sculpted-cliff" else id
	if id=="domed-tower":actual="belfry-tower";pose=pose.scaled_local(Vector3.ONE*.60)
	if id=="ceramic-lantern":actual="banner-lantern";pose=pose.scaled_local(Vector3.ONE*.78)
	if actual in ["banner-lantern","belfry-tower","cypress-grove","hanging-garden","terrace-house","garden-fountain","sculpted-garden","garden-bed","trailing-garden","cliff-grotto"] and not _camera_prop_clear(pose,actual):
		rejected_camera_props+=1;return null
	var path:="res://assets/clay-polish/"+actual+".glb"
	if not ResourceLoader.exists(path):return super._kit_asset(parent,id,pose)
	if not mesh_assets.has(path):mesh_assets[path]=load(path)
	var node: Node3D=mesh_assets[path].instantiate();parent.add_child(node);node.transform=pose
	node.set_meta("asset_instance",true);node.set_meta("asset_kind",actual)
	assembly.append({"id":actual,"origin":[pose.origin.x,pose.origin.y,pose.origin.z],"basis":[[pose.basis.x.x,pose.basis.x.y,pose.basis.x.z],[pose.basis.y.x,pose.basis.y.y,pose.basis.y.z],[pose.basis.z.x,pose.basis.z.y,pose.basis.z.z]]})
	polish_counts[actual]=polish_counts.get(actual,0)+1
	return node

func _piece_at(parent: Node3D,mesh: Mesh,pose: Transform3D,mat: Material,label: String) -> MeshInstance3D:
	var node:=super._piece_at(parent,mesh,pose,mat,label)
	node.set_meta("polish_semantic",label)
	if label=="GroundedClayCliff":land_poses[pose.origin]=pose
	if label=="GardenTerrace":node.hide() # superseded by surface-aligned garden patches
	return node

func _build_grounded_world() -> void:
	composition.world()

func _landform(dim: Vector3,seed_value: int) -> ArrayMesh:
	return Landforms.field(dim,seed_value) if dim.y<14 else Landforms.mesh(dim,seed_value)

func _safe_shape(pose: Transform3D,dimensions: Vector3,margin:=Vector3(9,2.0,9)) -> bool:
	var inverse:=pose.affine_inverse()
	var half:=dimensions*.5+margin
	for p in scenery_samples:
		var q: Vector3=inverse*p
		if absf(q.x)<half.x and absf(q.y)<half.y and absf(q.z)<half.z:return false
	return true

func _build_station_furniture() -> void:
	var district=preload("res://scripts/art/polish/clay_station_set.gd").new(self)
	for id in ["station_start","station_carve","victory_run"]:
		var t: SpatialTrack=route.tracks[id]
		for index in ceili(t.length/100):
			var a:=index*100.0;var b:=minf(a+100,t.length)
			var chunk:=Node3D.new();production_root.add_child(chunk);chunk.position=t.pose(a).origin
			var outer:=28.0 if id=="victory_run" else 13.6
			for side in [-1,1]:
				kit.sweep(chunk,"StationPromenade",t,a,b,kit.round_rect((outer-t.width_at((a+b)*.5)+.12)*.5,-1.8,.55,.2),surface.material("cream","",0,true),Vector2(side*(outer+t.width_at((a+b)*.5)-.12)*.5,0))
		for n in ceili(t.length/28):
			var s:=minf(14+n*28.0,t.length)
			if id in ["station_start","victory_run"]:_kit_asset(production_root,"canopy-bay",t.pose(s).translated_local(Vector3(0,.55,0)))
			for side in [-1,1]:
				var frame: Transform3D=district.ground(t,s,side*15,.55) if id.begins_with("station_") else t.pose(s).translated_local(Vector3(side*15,.55,0))
				_kit_asset(production_root,"platform-bench",frame.rotated_local(Vector3.UP,PI/2 if side>0 else -PI/2))
				if n%2==0:_kit_asset(production_root,"banner-lantern",composition.upright(t.pose(s+9).translated_local(Vector3(side*11.8,.55,0))) if id.begins_with("station_") else t.pose(s+9).translated_local(Vector3(side*11.8,.55,0)))
		for s in [38.0,t.length-35]:_kit_asset(production_root,"terminal-clock",district.ground(t,s,-16,.55) if id.begins_with("station_") else t.pose(s).translated_local(Vector3(-16,.55,0)))

func _build_arcades() -> void:
	composition.arcades()

func _cliff_terrace(center: Vector3,dim: Vector3,index: int) -> void:
	var closest:=_nearest_scenery(center)
	var normal:=Vector3(closest.x-center.x,0,closest.z-center.z).normalized()
	if normal.length()<.9 or Vector2(closest.x-center.x,closest.z-center.z).length()>170:return
	var radius:=1.0/sqrt(pow(normal.x/(dim.x*.5),2)+pow(normal.z/(dim.z*.5),2))
	var top:=center.y+dim.y*.5
	var level:=minf(closest.y-5,top-17)
	if level<center.y-dim.y*.5+8:return
	var t:=clampf((level-center.y)/dim.y+.5,.05,.95)
	var mass_pose: Transform3D=land_poses.get(center,Transform3D(Basis.IDENTITY,center))
	var local_direction:=mass_pose.basis.inverse()*normal
	var position: Vector3=mass_pose*Landforms.point(dim,index,t,atan2(local_direction.z,local_direction.x))+normal*5.3
	var pose:=Transform3D(Basis.looking_at(-normal,Vector3.UP),position)
	if not _safe_shape(pose.translated_local(Vector3(0,7.5,0)),Vector3(24,16,11)):return
	_box_at(extra_root,pose.translated_local(Vector3(0,-1.2,0)),Vector3(27,2.4,13),surface.material("cream"),"VillageTerraceFloor")
	if index%4<2:
		_kit_asset(extra_root,"terrace-house",pose.translated_local(Vector3(0,0,-1.7)))
		_kit_asset(extra_root,"cypress-grove",pose.translated_local(Vector3(6,15.35,-1)).scaled_local(Vector3.ONE*.65))
	else:
		_kit_asset(extra_root,"belfry-tower",pose.translated_local(Vector3(-6,0,-2)).scaled_local(Vector3.ONE*.55))
		_kit_asset(extra_root,"cypress-grove",pose.translated_local(Vector3(6,0,-1)).scaled_local(Vector3.ONE*1.1))
		_kit_asset(extra_root,"platform-bench",pose.translated_local(Vector3(3,0,3)))
	for x in [-10,0,10]:
		var corbel:=pose.translated_local(Vector3(x,-4,-2))
		_box_at(extra_root,corbel,Vector3(3.5,6,9),surface.material("peach"),"VillageCorbel")
	for x in [-6.4,6.4]:_kit_asset(extra_root,"promenade-parapet",pose.translated_local(Vector3(x,.1,5.8)))
	if index%2==0:_kit_asset(extra_root,"hanging-garden",pose.translated_local(Vector3(-8,-2,6)).scaled_local(Vector3.ONE*.8))

func _nearest_scenery(center: Vector3) -> Vector3:
	var nearest:=Vector3.ZERO;var distance:=INF
	for p in scenery_samples:
		var d:=Vector2(p.x-center.x,p.z-center.z).length_squared()
		if d<distance:distance=d;nearest=p
	return nearest

func _build_landscape_belts() -> void:
	composition.landscape()

func _build_garden_shoulders() -> void:
	composition.vertical()

func _build_structural_arcades() -> void:
	# Replace the old ungrounded greybox needles with the structural viaduct bays.
	for id in ["canyon_safe","canyon_fast","canyon_merge","rush","carve","cliff_turn","upper","rescue","finish","landmark_return","return_switchback","final_approach"]:
		var t: SpatialTrack=route.tracks[id]
		for n in ceili(t.length/32.0):
			var s:=16+n*32.0
			if s+16>t.length:continue
			var frame:=t.pose(s)
			if frame.basis.y.dot(Vector3.UP)<.96:continue
			if t.pose(s-14).basis.z.dot(t.pose(s+14).basis.z)<.94:continue
			var pose:=frame.translated_local(Vector3(0,-29.0,0)).rotated_local(Vector3.UP,PI/2)
			if _safe_shape(pose.translated_local(Vector3(0,13.2,0)),Vector3(32,26.4,7.6),Vector3(8,1,8)):
				_kit_asset(extra_root,"viaduct-bay",pose)
				var foot: Vector3=pose*Vector3(-14.2,0,0)
				var height:=foot.y+49
				if height>3:
					var pier:=Transform3D(preload("res://scripts/art/polish/clay_scene_composer.gd").upright(pose).basis,foot-Vector3.UP*height*.5)
					var size:=Vector3(5.8,height+1,7.2)
					if _safe_shape(pier,size,Vector3(8,1,8)) and _camera_bounds_clear(pier*AABB(-size*.5,size)):
						_box_at(extra_root,pier,size,surface.material("peach"),"GroundedViaductPier")
						_box_at(extra_root,pier.translated_local(Vector3(0,height*.5-.6,0)),Vector3(6.8,1.4,8.0),surface.material("cream"),"ViaductSpringCapital")

func _build_bridge_edges() -> void:
	for t: SpatialTrack in route.tracks.values():
		if t.id in ["tunnel","underpass"] or t.kind in ["loop","wall","inverted","grind"]:continue
		for index in ceili(t.length/100):
			var a:=index*100.0;var b:=minf(a+100,t.length)
			if t.pose((a+b)*.5).basis.y.dot(Vector3.UP)<.88:continue
			var root_part:=Node3D.new();extra_root.add_child(root_part);root_part.position=t.pose(a).origin
			# Low parapets follow the contact frame exactly and remain outside outer lanes.
			var width:=t.width_at((a+b)*.5)
			for side in [-1,1]:
				kit.sweep(root_part,"CeramicEdgeCoping",t,a,b,kit.round_rect(.32,.25,.63,.12),surface.material("cream"),Vector2(side*(width+.3),0))
		for n in ceili(t.length/48):
			var s:=12+n*48.0
			if s>t.length:continue
			if t.pose(s).basis.y.dot(Vector3.UP)<.92:continue
			for side in [-1,1]:
				var pose:=t.pose(s).translated_local(Vector3(side*(t.width_at(s)+.45),0,0))
				_kit_asset(extra_root,"banner-lantern",(composition.upright(pose) if t.id.begins_with("station_") else pose).scaled_local(Vector3.ONE*.67))

func _build_gallery_details() -> void:
	var t: SpatialTrack=route.tracks.tunnel
	for n in ceili(t.length/32.0):
		var s:=minf(3+n*32.0,t.length-1)
		_kit_asset(extra_root,"gallery-trim",t.pose(s).translated_local(Vector3(0,0,1.6)))
		for side in [-1,1]:
			var face:=t.pose(s+15).translated_local(Vector3(side*16.15,0,0)).rotated_local(Vector3.UP,-side*PI/2)
			_kit_asset(extra_root,"wall-sconce",face.translated_local(Vector3(0,6,0)))
			if n%3==2:_kit_asset(extra_root,"maintenance-bay",face.translated_local(Vector3(0,.6,0)))
			if n%5==1:_kit_asset(extra_root,"hanging-garden",face.translated_local(Vector3(3.8,4.8,.4)).scaled_local(Vector3.ONE*.55))
	for index in ceili(t.length/100):
		var a:=index*100.0;var b:=minf(a+100,t.length)
		var chunk:=Node3D.new();extra_root.add_child(chunk);chunk.position=t.pose(a).origin
		for side in [-1,1]:
			for y in [2.65,3.08]:
				kit.sweep(chunk,"GlazedServiceConduit",t,a,b,kit.round_rect(.095,y-.095,y+.095,.045),surface.material("teal"),Vector2(side*16.75,0))
		for x in [-10,0,10]:
			var y:=7.2+sqrt(1.0-pow(x/17.2,2.0))*6.4
			kit.sweep(chunk,"VaultCofferMolding",t,a,b,kit.round_rect(.16,y-.18,y+.04,.055),surface.material("peach"),Vector2(x,0))

func _build_roller_supports() -> void:
	var t: SpatialTrack=route.tracks.loop
	for index in ceili(t.length/100):
		var a:=index*100.0;var b:=minf(a+100,t.length)
		var chunk:=Node3D.new();extra_root.add_child(chunk);chunk.position=t.pose(a).origin
		for side in [-1,1]:kit.sweep(chunk,"SculptedLoopSpine",t,a,b,kit.round_rect(.8,-2.8,-1.2,.4),surface.material("peach"),Vector2(side*11.2,0))
	for n in ceili(t.length/18):
		var pose:=t.pose(minf(n*18.0,t.length)).translated_local(Vector3(0,-2.1,0))
		_box_at(extra_root,pose,Vector3(23.6,.9,1.2),surface.material("cream"),"LoopCrossSleeper")
	for t2: SpatialTrack in [route.tracks.loop_entry,route.tracks.loop_out,route.tracks.relay]:
		for side in [-1,1]:
			var pose:=preload("res://scripts/art/polish/clay_scene_composer.gd").upright(t2.pose(15).translated_local(Vector3(side*28,-4,0)))
			var height:=pose.origin.y+48
			var foundation:=Transform3D(Basis.IDENTITY,pose.origin-Vector3.UP*height*.5)
			if _safe_shape(pose.translated_local(Vector3(0,13,0)),Vector3(12,27,12)) and _safe_shape(foundation,Vector3(18,height,18)):
				_piece_at(extra_root,_landform(Vector3(18,height,18),int(side)+2),foundation,surface.material("lavender"),"ReceiverIsland")
				_kit_asset(extra_root,"belfry-tower",pose)

func _build_water() -> void:
	var water:=ShaderMaterial.new();water.shader=load("res://materials/clay-polish/water.gdshader")
	for node in find_children("*","MeshInstance3D",true,false):
		if node.mesh is PlaneMesh and node.mesh.size.x>1000:node.material_override=water

func _build_side_run_gallery() -> void:
	# Keep every ornamental face behind the greybox wall plane (-.5m).
	# Even a shallow raised panel can catch the swept departure camera.
	var t: SpatialTrack=route.tracks.wall
	# An open departure bay lets the airborne camera pass the end of the wall.
	var gallery_end:=maxf(0.0,t.length-16.0)
	for index in ceili(gallery_end/100):
		var a:=index*100.0;var b:=minf(a+100,gallery_end)
		var chunk:=Node3D.new();extra_root.add_child(chunk);chunk.position=t.pose(a).origin
		kit.sweep(chunk,"WallGalleryBacking",t,a,b,kit.round_rect(15,-1.8,-.85,.22),surface.material("cream")).set_meta("polish_semantic","WallGalleryBacking")
		for side in [-1,1]:
			kit.sweep(chunk,"WallGlazedCoffer",t,a,b,kit.round_rect(4.6,-.86,-.77,.035),surface.material("teal"),Vector2(side*9.3,0)).set_meta("polish_semantic","WallGlazedCoffer")
			for x in [4.6,14.1]:
				kit.sweep(chunk,"WallCofferRim",t,a,b,kit.round_rect(.22,-.80,-.55,.1),surface.material("cream"),Vector2(side*x,0)).set_meta("polish_semantic","WallCofferRim")
	for n in ceili(gallery_end/20):
		var s:=10+n*20.0
		if s>gallery_end:continue
		for side in [-1,1]:
			var p:=t.pose(s).translated_local(Vector3(side*9.3,-.73,0))
			_box_at(extra_root,p,Vector3(9.8,.35,.8),surface.material("cream"),"WallCofferCrossbeam")
			for x in [5.3,13.3]:
				_piece_at(extra_root,kit.cylinder(.28,.10),t.pose(s).translated_local(Vector3(side*x,-.60,0)),surface.material("gold"),"WallRosette")

func _build_track_hardware() -> void:
	# A small instanced fastening family grounds the rails in their sleepers.
	# Cosmetic only: all parts stay below the original wheel contact plane.
	var poses: Array[Transform3D]=[]
	for t: SpatialTrack in route.tracks.values():
		if t.single_lane:continue
		for n in ceili(t.length/4.8):
			var s:=n*4.8
			for lane in t.lanes():
				for side in [-1,1]:poses.append(t.pose(s).translated_local(Vector3(lane*4.4+side*.93,-.045,0)))
	var cells: Dictionary={}
	for pose in poses:
		var cell:=Vector3i((pose.origin/120.0).floor())
		if not cells.has(cell):cells[cell]=[]
		cells[cell].append(pose)
	for cell in cells:
		var group: Array=cells[cell];var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=surface.box(Vector3(.23,.085,.3),.032);mm.instance_count=group.size()
		var center:=Vector3(cell)*120
		for i in group.size():
			var pose: Transform3D=group[i];pose.origin-=center;mm.set_instance_transform(i,pose)
		var node:=MultiMeshInstance3D.new();extra_root.add_child(node);node.position=center
		node.multimesh=mm;node.material_override=surface.material("fastener","81768b");node.visibility_range_end=110;node.name="RailFastenings"
		node.set_meta("world_instance_transforms",group);node.set_meta("asset_kind","rail-fastener")

func _shoreline(node: MeshInstance3D,dim: Vector3,seed_value: int) -> void:
	var t:=(-44.6-node.global_position.y)/dim.y+.5
	if t<=.015 or t>=.97:return
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 64:
		var a:=TAU*i/64.0;var b:=TAU*(i+1)/64.0
		var p:=Landforms.point(dim,seed_value,t,a);var q:=Landforms.point(dim,seed_value,t,b)
		var va:=Vector3(cos(a),0,sin(a));var vb:=Vector3(cos(b),0,sin(b))
		var width:=.8+.5*sin(a*5+seed_value)
		for v in [p,q,p+va*width,q,q+vb*width,p+va*width]:
			st.set_normal(Vector3.UP);st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
	_piece_at(extra_root,st.commit(),node.global_transform,surface.material("shorefoam","c8e5dd"),"ShorelineFoam")

func _waterfall(top: Vector3,height: float,width: float) -> void:
	if height<8 or not shoulder_waterfalls:return
	var near:=_nearest_scenery(top)
	var facing:=Vector3(near.x-top.x,0,near.z-top.z).normalized()
	if facing.length()<.5:facing=Vector3.FORWARD
	var basis:=Basis.looking_at(-facing,Vector3.UP)
	var mat:=ShaderMaterial.new();mat.shader=load("res://materials/clay-polish/water.gdshader");mat.set_shader_parameter("falling",true)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A curved sheet leaves a real spill lip, fans out at the foot and meets the sea.
	for y in 32:
		for x in 8:
			for ij: Vector2i in [Vector2i(x,y),Vector2i(x+1,y),Vector2i(x,y+1),Vector2i(x+1,y),Vector2i(x+1,y+1),Vector2i(x,y+1)]:
				var u:=float(ij.x)/8;var v:=float(ij.y)/32
				var spread:=.85+.32*pow(v,6)
				var z:=1.4*(1-exp(-v*20.0))+.18*sin(u*TAU*3.0+v*8)
				st.set_uv(Vector2(u,v));st.add_vertex(Vector3((u-.5)*width*spread,-v*height,z))
	st.generate_normals()
	_piece_at(extra_root,st.commit(),Transform3D(basis,top),mat,"SculptedWaterfall")
	# The spillway is partly embedded in the ledge; its rail-facing arch explains the source.
	var lip:=Transform3D(basis,top).translated_local(Vector3(0,-.6,-1.4))
	_box_at(extra_root,lip,Vector3(width+2,1.2,4.4),surface.material("cream"),"WaterSpillSill")
	for side in [-1,1]:_box_at(extra_root,lip.translated_local(Vector3(side*(width*.5+.55),1.05,-.3)),Vector3(1.1,2.1,4.5),surface.material("peach"),"SpillwayCheek")
	for i in 7:
		var foam:=SphereMesh.new();foam.radius=width*(.12+float(i%2)*.065);foam.height=.55;foam.radial_segments=16;foam.rings=8
		var p:=top-Vector3.UP*height+basis.x*(i-3)*width*.16+basis.z*(1.3+sin(i*1.7)*1.2)
		_piece_at(extra_root,foam,Transform3D(Basis.IDENTITY,p),surface.material("foam","d7eee2"),"FoamLobe")

func _clouds() -> void:
	var source: PackedScene=load("res://assets/clay-polish/cloud-cluster.glb")
	for id: String in ["station_start","canyon_merge","inverted","loop","tunnel","upper","final_approach","victory_run"]:
		var t: SpatialTrack=route.tracks[id]
		for side in [-1,1]:
			var cloud: Node3D=source.instantiate();environment_root.add_child(cloud)
			cloud.position=t.pose(t.length*.5).origin+Vector3(side*490,195+side*30,-350)
			cloud.scale=Vector3.ONE*(1.6 if side>0 else 2.3)
			cloud.rotation.y=float(side)*.48
			for part: MeshInstance3D in cloud.find_children("*","MeshInstance3D",true,false):part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_terminal_vista() -> void:
	composition.terminal()

func _batch_assets(parent: Node3D) -> void:
	var groups: Dictionary={};var roots: Array[Node3D]=[]
	for n: Node3D in parent.find_children("*","Node3D",true,false):
		if n.has_meta("asset_instance"):roots.append(n)
	for instance in roots:
		for part: MeshInstance3D in instance.find_children("*","MeshInstance3D",true,false):
			var cell: Vector3i=Vector3i((part.global_position/180.0).floor())
			var key:=str(part.mesh.get_instance_id())+str(cell)
			for s in part.mesh.get_surface_count():key+=str(part.get_active_material(s).get_instance_id())
			if not groups.has(key):groups[key]={"part":part,"poses":[],"center":Vector3(cell)*180,"kind":str(instance.get_meta("asset_kind",""))}
			groups[key].poses.append(part.global_transform)
	for group: Dictionary in groups.values():
		var part: MeshInstance3D=group.part
		var mesh: Mesh=part.mesh.duplicate()
		for s in mesh.get_surface_count():mesh.surface_set_material(s,part.get_active_material(s))
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=group.poses.size()
		for i in group.poses.size():
			var pose: Transform3D=group.poses[i];pose.origin-=group.center;mm.set_instance_transform(i,pose)
		var batch:=MultiMeshInstance3D.new();parent.add_child(batch);batch.global_position=group.center;batch.multimesh=mm;batch.visibility_range_end=1100
		var kind: String=group.kind
		batch.set_meta("asset_kind",kind)
		batch.set_meta("world_instance_transforms",group.poses.duplicate())
		batch.lod_bias=.70 if kind in ["cypress-grove","sculpted-cliff","shrub-cluster","garden-planter"] else .50
		if kind in ["cypress-grove","shrub-cluster","garden-planter","sculpted-garden","garden-bed"]:batch.visibility_range_end=650
		elif kind in ["hanging-garden","trailing-garden","wall-sconce","wall-vent","service-cabinet","maintenance-bay"]:batch.visibility_range_end=350
		elif kind in ["banner-lantern","way-bollard","platform-bench","terminal-clock"]:batch.visibility_range_end=550
		batch.visibility_range_end_margin=35
	for instance in roots:instance.free()

func _load_camera_corridors() -> void:
	var document: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/clay-polish/camera_corridors.json"))
	for path: Dictionary in document.paths:
		var previous:=Vector3.ZERO
		for point: Array in path.points:
			var p:=Vector3(point[0],point[1],point[2])
			var a:=previous if previous.distance_to(p)<35 else p
			var bounds:=AABB(a,Vector3.ZERO).expand(p).grow(1.25)
			var index:=camera_segments.size();camera_segments.append({"a":a,"b":p})
			var lo:=Vector3i((bounds.position/48).floor());var hi:=Vector3i((bounds.end/48).floor())
			for x in range(lo.x,hi.x+1):
				for y in range(lo.y,hi.y+1):
					for z in range(lo.z,hi.z+1):
						var key:=Vector3i(x,y,z)
						if not camera_cells.has(key):camera_cells[key]=[]
						camera_cells[key].append(index)
			previous=p
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/clay-polish/manifest.json"))
	for asset: Dictionary in manifest.assets:
		var dim: Array=asset.dimensions_godot_m
		prop_dimensions[asset.id]=Vector3(dim[0],dim[1],dim[2])
	prop_dimensions["cypress-grove"]=Vector3(5.5,9.06,5.32)
	prop_dimensions["hanging-garden"]=Vector3(4.03,5.07,3.5)
	prop_dimensions["garden-fountain"]=Vector3(4.5,4.38,4.5)

func _camera_prop_clear(pose: Transform3D,id: String) -> bool:
	var dim: Vector3=prop_dimensions[id]
	return _camera_bounds_clear(pose*AABB(Vector3(-dim.x*.5,0,-dim.z*.5),dim))

func _camera_bounds_clear(box: AABB) -> bool:
	var bounds:=box.grow(1.25)
	var lo:=Vector3i((bounds.position/48).floor());var hi:=Vector3i((bounds.end/48).floor())
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			for z in range(lo.z,hi.z+1):
				for index in camera_cells.get(Vector3i(x,y,z),[]):
					var segment: Dictionary=camera_segments[index]
					if bounds.has_point(segment.a) or bounds.has_point(segment.b) or bounds.intersects_segment(segment.a,segment.b)!=null:return false
	return true

func _build_wayfinding() -> void:
	for pose in sign_slots:
		var disc:=CylinderMesh.new();disc.top_radius=1.15;disc.bottom_radius=1.15;disc.height=.26;disc.radial_segments=32
		_piece_at(extra_root,disc,pose.rotated_local(Vector3.RIGHT,PI/2),surface.material("red"),"EnamelNoEntrySign")
		_box_at(extra_root,pose.translated_local(Vector3(0,0,.16)),Vector3(1.6,.23,.08),surface.material("cream"),"EnamelSignBar")
		_box_at(extra_root,pose.translated_local(Vector3(0,-2.25,-.10)),Vector3(.22,3.5,.24),surface.material("teal"),"WayfindingPost")
		_box_at(extra_root,pose.translated_local(Vector3(0,-3.9,-.10)),Vector3(.95,.38,.75),surface.material("cream"),"WayfindingFoot")
	for item in apparatus_slots:
		var pose: Transform3D=item.pose;var dim: Vector3=item.dim
		if not _camera_bounds_clear(pose*AABB(-dim*.5,dim)):continue
		var body:=surface.material("gold" if item.kind=="GoldGrindCatch" else "teal")
		_box_at(extra_root,pose,dim,body,"CeramicReceiverHousing")
		if dim.y>4:
			_box_at(extra_root,pose.translated_local(Vector3(0,dim.y*.38,0)),Vector3(dim.x*1.22,dim.y*.12,dim.z*1.22),surface.material("cream"),"ReceiverCap")
			_box_at(extra_root,pose.translated_local(Vector3(0,0,dim.z*.51)),Vector3(dim.x*.42,dim.y*.55,.055),surface.material("teal","6cbbae",.28),"ReceiverStatusInset")
		elif dim.z>5:
			for side in [-1,1]:_box_at(extra_root,pose.translated_local(Vector3(0,0,side*dim.z*.35)),Vector3(dim.x*1.1,dim.y*1.2,.35),surface.material("cream"),"ReceiverBrassClamp")
	var signs:=[{"track":"station_start","s":65.0,"text":"01  PORTO","x":-17.0,"y":8.8}, {"track":"victory_run","s":35.0,"text":"07  ARRIVO","x":-17.0,"y":8.8}]
	for n in 5:signs.append({"track":"tunnel","s":55.0+n*280.0,"text":"GROTTA  %02d"%(n+1),"x":-16.0,"y":7.3})
	for spec in signs:
		var track: SpatialTrack=route.tracks[spec.track]
		if spec.s>=track.length:continue
		var pose:=track.pose(spec.s).translated_local(Vector3(spec.x,spec.y,0))
		if not _camera_bounds_clear(pose*AABB(Vector3(-3.8,-.7,-.22),Vector3(7.6,1.4,.44))):continue
		_box_at(extra_root,pose,Vector3(7.6,1.4,.30),surface.material("teal"),"EnamelPlaceName")
		var label:=Label3D.new();extra_root.add_child(label);label.transform=pose.translated_local(Vector3(0,0,.18));label.text=spec.text
		label.font_size=96;label.pixel_size=.010;label.modulate=Color("fff0ce");label.outline_size=0;label.no_depth_test=false;label.double_sided=false
		label.visibility_range_end=170

func _meadow_details(node: MeshInstance3D,dim: Vector3,seed_value: int) -> void:
	# The greybox floor was a scenery envelope, not a meadow biome. Open its
	# negative space back to the sea and anchor small islands beneath the route.
	node.hide()
	for j in 16:
		var x:=sin(j*2.399+seed_value)*dim.x*.39
		var z:=cos(j*1.618+seed_value)*dim.z*.39
		var center:=node.global_transform*Vector3(x,0,z)
		var shape:=Vector3(60+float(j%4)*17,38+float(j%3)*12,72+float(j%5)*13)
		center.y=-49+shape.y*.5
		var pose:=Transform3D(Basis(Vector3.UP,j*.61),center)
		if not _safe_shape(pose,shape,Vector3(16,12,16)):continue
		if enrichment.island(center,shape,"valley"):continue
		var island:=_piece_at(extra_root,Landforms.mesh(shape,seed_value+j),pose,surface.material("lavender"),"ValleyArchipelago")
		_shoreline(island,shape,seed_value+j)
		for k in 3:
			var crown:=pose*Landforms.point(shape,seed_value+j,1.0,k*2.1)
			crown.x=lerpf(center.x,crown.x,.42);crown.z=lerpf(center.z,crown.z,.42)
			var factor:=1.6+float(k%2)*.8
			var plant_pose:=Transform3D(Basis(Vector3.UP,j+k),crown).scaled_local(Vector3.ONE*factor)
			if _safe_shape(plant_pose.translated_local(Vector3(0,4,0)),Vector3(8,9,8)*factor):
				_kit_asset(extra_root,"cypress-grove" if k==0 else "shrub-cluster",plant_pose)

func _convert_materials(node: Node,kind: String="") -> void:
	if node.has_meta("asset_kind"):kind=str(node.get_meta("asset_kind"))
	super._convert_materials(node,kind)
	if node is MeshInstance3D and kind in ["sculpted-cliff","rounded-cliff"]:
		for index in node.mesh.get_surface_count():
			var material: Material=node.get_active_material(index)
			if material is ShaderMaterial:
				material.set_shader_parameter("clay_color",Color("b09ac8"))
				material.set_shader_parameter("remap_texture",true)
				material.set_shader_parameter("stone",true)
				material.set_shader_parameter("relief",.045)
	if node is MeshInstance3D and kind in ["clay-topiary-garden","cliff-terrace-garden"]:
		for index in node.mesh.get_surface_count():
			var material: Material=node.get_active_material(index)
			if material is ShaderMaterial:
				material.set_shader_parameter("roughness_floor",.72)
				material.set_shader_parameter("specular_strength",.24)
				material.set_shader_parameter("metal",0.0)
	if node is MeshInstance3D and kind in ["cypress-grove","garden-planter","shrub-cluster","hanging-garden"]:
		for index in node.mesh.get_surface_count():
			var material: Material=node.get_active_material(index)
			if material is ShaderMaterial:material.set_shader_parameter("foliage",true)

func _build_gallery() -> void:
	var t: SpatialTrack=route.tracks.tunnel
	for index in ceili(t.length/120):
		var a:=index*120.0;var b:=minf(a+120,t.length);var chunk:=Node3D.new();production_root.add_child(chunk);chunk.position=t.pose(a).origin
		kit.sweep(chunk,"InnerGallery",t,a,b,kit.tunnel_profile(17.2,13.6),surface.material("lavender"),Vector2.ZERO,true)
		kit.sweep(chunk,"ClayGalleryFloor",t,a,b,kit.round_rect(17.2,-.85,-.42,.1),surface.material("floor","",0,true))
		for side in [-1,1]:
			kit.sweep(chunk,"RaisedPromenade",t,a,b,kit.round_rect(3.6,-.35,.60,.12),surface.material("cream","",0,true),Vector2(side*13.2,0))
			kit.sweep(chunk,"TerracottaDado",t,a,b,kit.round_rect(.42,.55,2.2,.14),surface.material("peach"),Vector2(side*16.6,0))
			kit.sweep(chunk,"CreamDadoCap",t,a,b,kit.round_rect(.50,2.05,2.30,.08),surface.material("cream"),Vector2(side*16.5,0))
	for n in ceili(t.length/32.0):
		var s:=minf(n*32.0+3,t.length-1)
		_kit_asset(production_root,"gallery-frame",t.pose(s))
		for side in [-1,1]:
			var lamp_pose:=t.pose(s+12).translated_local(Vector3(side*10.8,.6,0))
			_kit_asset(production_root,"way-bollard",lamp_pose)
			if n%2==0:
				_kit_asset(production_root,"ceramic-lantern",lamp_pose.translated_local(Vector3(side*3,0,1)))
			if n%3!=2:
				var niche_pose:=t.pose(s+17).translated_local(Vector3(side*16.15,.6,0)).rotated_local(Vector3.UP,-side*PI/2)
				_kit_asset(production_root,"arched-niche",niche_pose)
			if n%3==0:
				_kit_asset(production_root,"service-cabinet",t.pose(s+22).translated_local(Vector3(side*14.8,.6,0)).rotated_local(Vector3.UP,-side*PI/2))
				_kit_asset(production_root,"wall-vent",t.pose(s+22).translated_local(Vector3(side*14.8,3.9,0)).rotated_local(Vector3.UP,-side*PI/2))
			if n%3==1:_kit_asset(production_root,"platform-bench",t.pose(s+22).translated_local(Vector3(side*13.8,.6,0)).rotated_local(Vector3.UP,-side*PI/2))
			var light:=OmniLight3D.new();production_root.add_child(light);light.position=t.pose(s)*Vector3(side*16.0,6.2,0);light.light_color=Color("ffdb9d");light.light_energy=3.4;light.omni_range=26;light.omni_attenuation=.8
			light.distance_fade_enabled=true;light.distance_fade_begin=120;light.distance_fade_length=45
			light.shadow_enabled=n%2==0;light.shadow_bias=.06;light.distance_fade_shadow=70
	for s in [0.0,t.length]:
		_kit_asset(production_root,"gallery-frame",t.pose(s))

func _build_tunnel_exterior() -> void:
	for id in ["tunnel","underpass"]:
		var t: SpatialTrack=route.tracks[id]
		var inner_width:=17.2 if id=="tunnel" else 10.45
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


func _obstacle(parent: Node3D,p: Transform3D,size: Vector3,label: String) -> void:
	super._obstacle(parent,p,size,label)
	if label!="Block":return
	var dim:=p.basis.get_scale()*size;var pose:=p.orthonormalized()
	# Familiar red stop silhouette; hardware explains it as a railway safety unit.
	_box_at(parent,pose.translated_local(Vector3(0,-dim.y*.40,0)),Vector3(dim.x*.98,dim.y*.16,dim.z*.98),surface.material("teal"),"StopUnitPlinth")
	for side in [-1,1]:
		_box_at(parent,pose.translated_local(Vector3(side*dim.x*.45,0,0)),Vector3(dim.x*.09,dim.y*.86,dim.z*.88),surface.material("cream"),"StopUnitEdgeGuard")
		var lamp:=SphereMesh.new();lamp.radius=.14;lamp.height=.28;lamp.radial_segments=12;lamp.rings=8
		_piece_at(parent,lamp,pose.translated_local(Vector3(side*dim.x*.32,dim.y*.29,dim.z*.5)),surface.material("gold","f6c978",.18),"StopUnitSignal")
		for j in 4:
			_box_at(parent,pose.translated_local(Vector3(side*dim.x*.505,-dim.y*.20+j*.22,0)),Vector3(.035,.085,dim.z*.53),surface.material("dark"),"StopUnitCoolingSlot")
