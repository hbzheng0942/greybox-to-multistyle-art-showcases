extends RefCounted
## World-up environmental grammar, independent of the track's banking/contact frame.
const Landforms=preload("res://scripts/art/polish/clay_landforms.gd")
var lab: Node3D
var occupied: Array[Vector3]=[]
var island_count:=0
var template_meshes: Dictionary={}
var cliff_points: Array=[]
var cliff_facades: Array=[]
func _init(owner_lab: Node3D) -> void:
	lab=owner_lab
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/clay-polish/cliff_surface.json"))
	cliff_points=data.points;cliff_facades=data.facades

static func upright(pose: Transform3D) -> Transform3D:
	var heading:=Vector3(-pose.basis.z.x,0,-pose.basis.z.z)
	if heading.length_squared()<.001:heading=Vector3.FORWARD
	return Transform3D(Basis.looking_at(heading.normalized(),Vector3.UP).scaled_local(pose.basis.get_scale()),pose.origin)

func asset(id: String,pose: Transform3D) -> void:
	lab._kit_asset(lab.extra_root,id,pose)

func box(pose: Transform3D,dim: Vector3,key: String,label: String) -> void:
	lab._box_at(lab.extra_root,pose,dim,lab.surface.material(key),label)

func clear(pose: Transform3D,dim: Vector3) -> bool:
	return lab._safe_shape(pose,dim,Vector3(14,8,14)) and lab._camera_bounds_clear(pose*AABB(-dim*.5,dim))

func world() -> void:
	# Greybox scenery is an occupancy hint, never a finished building/rock shape.
	# Keep the hub's location as a readable, structurally supported landmark.
	for slot: Dictionary in lab.mass_slots:
		if slot.kind!="HubBeacon":continue
		var d: Vector3=slot.dimensions
		if d.y<d.x*3:continue
		var p: Transform3D=upright(slot.pose.orthonormalized())
		var bottom: float=p.origin.y-d.y*.5
		var center:=Vector3(p.origin.x,(bottom-49)*.5,p.origin.z)
		if clear(Transform3D(Basis.IDENTITY,center),Vector3(115,bottom+49,118)):
			island(center,Vector3(115,bottom+49,118),71+island_count,false)

func landscape() -> void:
	var ordinal:=0
	# Route-specific density: cliffs frame the run, open water separates the groups.
	for id in ["station_start","station_carve","canyon_safe","canyon_fast","canyon_merge","rush","carve","wall","inverted","drop","rollout","loop_entry","loop_out","exit_ramp","grind","relay","high","high_merge","cliff_turn","upper","rescue","finish","landmark_return","return_switchback","final_approach","final_upper","victory_run"]:
		if not lab.route.tracks.has(id):continue
		var t: SpatialTrack=lab.route.tracks[id]
		var gap:=180.0 if id in ["station_start","station_carve","victory_run"] else 155.0
		for n in ceili(t.length/gap):
			var frame: Transform3D=upright(t.pose(minf(70+n*gap,t.length)))
			for side in [-1,1]:
				ordinal+=1
				if side>0 and n%3==1:continue
				var distance:=(175.0 if id in ["station_start","station_carve"] else 88.0)+float(ordinal%3)*12
				var center: Vector3=frame.origin+frame.basis.x*side*distance
				var width:=120.0+float(ordinal%3)*10
				var top: float=frame.origin.y+43+sin(ordinal*1.7)*12
				var height: float=top+49
				if height<45:height=55
				center.y=-49+height*.5
				var dim:=Vector3(width,height,120+float(ordinal%3)*10)
				var too_close:=false
				for existing in occupied:
					if Vector2(existing.x-center.x,existing.z-center.z).length()<85:too_close=true;break
				if too_close:continue
				if not clear(Transform3D(Basis.IDENTITY,center),dim):
					center+=frame.basis.x*side*40
					if not clear(Transform3D(Basis.IDENTITY,center),dim):continue
				if not lab.enrichment.island(center,dim,id):island(center,dim,ordinal,true)
				occupied.append(center)
	for id in ["station_start","canyon_safe","loop_out","cliff_turn","upper","final_approach","victory_run"]:
		var t: SpatialTrack=lab.route.tracks[id]
		for side in [-1,1]:
			var frame:=upright(t.pose(t.length*.60))
			var center: Vector3=frame.origin+frame.basis.x*side*330-frame.basis.z*85
			var dim:=Vector3(220,frame.origin.y+165,220)
			center.y=-49+dim.y*.5
			if clear(Transform3D(Basis.IDENTITY,center),dim):island(center,dim,100+island_count,false)
	bridge_vistas()
	# Deck-mounted lights keep the exact contact frame; they are not buildings.
	for t: SpatialTrack in lab.route.tracks.values():
		if t.id=="tunnel":continue
		for n in ceili(t.length/32.0):
			var s:=minf(n*32.0+6,t.length)
			for side in [-1,1]:asset("way-bollard",t.pose(s).translated_local(Vector3(side*(t.width_at(s)-.18),0,0)).scaled_local(Vector3.ONE*.38))

func rock(pose: Transform3D,dim: Vector3,seed_value: int,label: String) -> void:
	# A handful of shared sculpted templates; transform sets physical proportions.
	var key:=seed_value%7
	if not template_meshes.has(key):template_meshes[key]=Landforms.lobe(key)
	var node: MeshInstance3D=lab._piece_at(lab.extra_root,template_meshes[key],pose.scaled_local(dim),lab.surface.material("lavender",["ad94c4","b49ace","a58aba","baa1ce"][seed_value%4]),label)
	node.lod_bias=.65

func island(center: Vector3,dim: Vector3,seed_value: int,dress: bool=true) -> void:
	if dim.y<10:return
	island_count+=1
	var near: Vector3=lab._nearest_scenery(center)
	var normal:=Vector3(near.x-center.x,0,near.z-center.z).normalized()
	if normal.length()<.5:normal=Vector3.FORWARD
	var facing:=Basis.looking_at(-normal,Vector3.UP)
	var factor:=dim.x/24.0
	var top:=center.y+dim.y*.5
	var root:=Vector3(center.x,top-16.69*factor,center.z)
	var base_height:=root.y+50
	var cliff_pose:=Transform3D(Basis(Vector3.UP,float(seed_value%4)*PI*.5),root).scaled_local(Vector3.ONE*factor)
	var cliff_node: Node3D=lab._kit_asset(lab.extra_root,"sculpted-cliff",cliff_pose)
	if cliff_node!=null and base_height>0:_extend_rock_foot(cliff_node,base_height/factor)
	if not dress:return
	# Place every root on a measured triangle of the actual Lux mesh, not a box.
	var planted: Array[Vector3]=[]
	var peak:=Vector3.ZERO;var highest:=-INF
	var ledge:=Vector3.ZERO;var best:=-INF
	for i in cliff_points.size():
		var v: Array=cliff_points[(i*17+seed_value)%cliff_points.size()]
		var local:=Vector3(v[0],v[1],v[2]);var point:=cliff_pose*local
		if point.y>highest:highest=point.y;peak=point
		var frontness: float=(point-root).dot(normal)
		if local.y<11 and local.y>3 and frontness>best:best=frontness;ledge=point
		var too_close:=false
		for other in planted:
			if point.distance_to(other)<16:too_close=true;break
		if too_close or planted.size()>=13:continue
		var plant_factor:=.90+float((i+seed_value)%3)*.20
		var pose:=Transform3D(Basis(Vector3.UP,i*.73),cliff_pose*Vector3(v[0],v[3],v[2])-Vector3.UP*.2).scaled_local(Vector3.ONE*plant_factor)
		if clear(Transform3D(Basis.IDENTITY,point+Vector3.UP*6),Vector3(12,15,12)):
			asset("sculpted-garden",pose);planted.append(point)
	var tower_pose:=Transform3D(Basis(Vector3.UP,seed_value*.71),peak-Vector3.UP*.5).scaled_local(Vector3.ONE*(.72 if seed_value%3 else 1.1))
	if seed_value%9==0 and clear(Transform3D(Basis.IDENTITY,peak+Vector3.UP*15),Vector3(15,30,15)):
		box(Transform3D(Basis.IDENTITY,peak-Vector3.UP*1.0),Vector3(13,2,13),"cream","SummitFoundation")
		asset("belfry-tower",tower_pose)
	# Sample the actual outward face for an embedded water mouth.
	# Whole houses belong to connected terraces, never these cliff brackets.
	var selected_score:=-INF
	for entry: Dictionary in cliff_facades:
		var a: Array=entry.point;var b: Array=entry.normal
		var p: Vector3=cliff_pose*Vector3(a[0],a[1],a[2])
		var outward: Vector3=(cliff_pose.basis*Vector3(b[0],b[1],b[2])).normalized()
		var score: float=outward.dot(normal)*150-absf(p.y-(near.y-8.0))
		if score>selected_score:
			selected_score=score;ledge=p;best=1
			facing=Basis.looking_at(-outward,Vector3.UP)
	if best>-INF and seed_value%2==0 and ledge.y>-33:
		var outward: Vector3=facing.z
		var pose:=Transform3D(facing,ledge+outward*.4-Vector3.UP)
		if clear(pose.translated_local(Vector3(0,4,0)),Vector3(12,9,9)):
			asset("cliff-grotto",pose)
			var lip:=pose.origin+outward*3.1+Vector3.UP*.3
			lab._waterfall(lip,lip.y+44.6,6.4)

func arcades() -> void:
	preload("res://scripts/art/polish/clay_station_set.gd").new(lab).build()
	for id in ["victory_run"]:
		var t: SpatialTrack=lab.route.tracks[id]
		for n in ceili(t.length/13):
			var s:=minf(6.5+n*13.0,t.length-1)
			for side in [-1,1]:
				var frame: Transform3D=t.pose(s).translated_local(Vector3(side*24,.55,0))
				var pose:=frame.rotated_local(Vector3.UP,-side*PI/2)
				if n%3==0:
					asset("garden-bed",upright(t.pose(s+3).translated_local(Vector3(side*17,.58,0))).rotated_local(Vector3.UP,-side*PI/2))
	var tunnel: SpatialTrack=lab.route.tracks.tunnel
	for n in ceili(tunnel.length/32):
		for side in [-1,1]:
			var pose:=tunnel.pose(minf(n*32.0+11,tunnel.length)).translated_local(Vector3(side*15,.6,0)).rotated_local(Vector3.UP,-side*PI/2)
			asset("garden-bed",pose.scaled_local(Vector3.ONE*.80))
	# Gardened, solid portals retain the actual opening dimensions.
	for s in [0.0,tunnel.length]:
		for side in [-1,1]:
			var pose:=upright(tunnel.pose(s).translated_local(Vector3(side*40,-4,0)))
			rock(pose.translated_local(Vector3(0,12,0)),Vector3(34,32,48),int(side)+8,"PortalShoulder")
			asset("sculpted-garden",pose.translated_local(Vector3(0,28,0)).scaled_local(Vector3.ONE*1.6))

func vertical() -> void:
	# Complete architectural bays, rooted below the inverted track and outside
	# both recorded camera corridors; no free-standing greybox needles.
	for id in ["wall","inverted"]:
		var t: SpatialTrack=lab.route.tracks[id]
		for n in ceili(t.length/32):
			var frame:=upright(t.pose(minf(16+n*32.0,t.length)))
			for side in [-1,1]:
				var pose:=frame.translated_local(Vector3(side*36,-30,0)).rotated_local(Vector3.UP,PI/2)
				if clear(pose.translated_local(Vector3(0,13,0)),Vector3(33,27,8)):
					asset("viaduct-bay",pose)
					asset("trailing-garden",pose.translated_local(Vector3(7,25,4)).scaled_local(Vector3.ONE*1.5))
					asset("sculpted-garden",pose.translated_local(Vector3(-7,26,0)).scaled_local(Vector3.ONE*.9))
			if id=="inverted":
				# The station is deliberately inverted with its supporting railway.
				var canopy:=t.pose(minf(16+n*32.0,t.length)).translated_local(Vector3(0,0,0))
				if canopy_clear(canopy):
					asset("canopy-bay",canopy)
					for side in [-1,1]:asset("trailing-garden",canopy.translated_local(Vector3(side*17,13,0)).scaled_local(Vector3.ONE*1.4))

func terminal() -> void:
	var t: SpatialTrack=lab.route.tracks.victory_run
	var end:=upright(t.pose(t.length))
	for i in 3:
		var center:=end*Vector3((i-1)*165,-55,-310-abs(i-1)*55)
		var dim:=Vector3(155,110+float(i%2)*30,150)
		if clear(Transform3D(Basis.IDENTITY,center),dim):island(center,dim,91+i,true)

func canopy_clear(pose: Transform3D) -> bool:
	# Test solid columns/roof separately: the room's empty interior must remain usable.
	for x in [-25.65,25.65]:
		var p:=pose.translated_local(Vector3(x,7.5,0))
		if not lab._safe_shape(p,Vector3(3,15,31),Vector3(8,2,8)) or not lab._camera_bounds_clear(p*AABB(Vector3(-1.5,-7.5,-15.5),Vector3(3,15,31))):return false
	var roof:=pose.translated_local(Vector3(0,16.6,0))
	return lab._safe_shape(roof,Vector3(55,1.2,31),Vector3(8,1,8)) and lab._camera_bounds_clear(roof*AABB(Vector3(-27.5,-.6,-15.5),Vector3(55,1.2,31)))

func _extend_rock_foot(node: Node3D,depth: float) -> void:
	# Deform only the buried lower skirt of the accepted mesh; the sculpted upper
	# shape and measured planting anchors stay exact. No separate cylindrical base.
	for part: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var to_asset:=node.global_transform.affine_inverse()*part.global_transform
		var from_asset:=to_asset.affine_inverse()
		var mesh:=ArrayMesh.new()
		for surface_index in part.mesh.get_surface_count():
			var arrays: Array=part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for i in vertices.size():
				var p: Vector3=to_asset*vertices[i]
				var t:=clampf(p.y/2.5,0,1)
				var derivative:=1.0+depth*6.0*t*(1.0-t)/2.5
				var n: Vector3=to_asset.basis.inverse().transposed()*normals[i]
				n.y/=derivative
				normals[i]=(to_asset.basis.transposed()*n).normalized()
				p.y-=depth*(1.0-smoothstep(0.0,2.5,p.y))
				vertices[i]=from_asset*p
			arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.surface_set_material(surface_index,part.get_active_material(surface_index))
		part.mesh=mesh

func bridge_vistas() -> void:
	for id in ["station_start","station_carve","canyon_safe","cliff_turn","final_approach","victory_run"]:
		var t: SpatialTrack=lab.route.tracks[id]
		var frame:=upright(t.pose(t.length*.58))
		for j in 9:
			var pose:=frame.translated_local(Vector3(165,-44,(j-4)*32.0-45)).rotated_local(Vector3.UP,PI/2)
			if not clear(pose.translated_local(Vector3(0,13,0)),Vector3(33,27,8)):continue
			asset("viaduct-bay",pose)
			var foot:=pose*Vector3(-14.2,0,0)
			var h:=foot.y+48
			if h>2:
				var p:=Transform3D(pose.basis,foot-Vector3.UP*h*.5)
				if clear(p,Vector3(6,h,8)):box(p,Vector3(6,h,8),"peach","VistaBridgePier")
			if j%2==0:asset("sculpted-garden",pose.translated_local(Vector3(-11,26.2,0)).scaled_local(Vector3.ONE*.72))
			if j in [0,8]:asset("belfry-tower",pose.translated_local(Vector3(0,26.2,0)).scaled_local(Vector3.ONE*.68))
