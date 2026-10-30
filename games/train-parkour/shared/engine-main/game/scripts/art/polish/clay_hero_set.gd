extends RefCounted
## Reviewed Lux exteriors placed as authored groups; tracks remain procedural.
var lab: Node3D
var assets: Dictionary={}
var support: Array=[]
const SLOTS=[
	{"track":"station_start","s":260.0,"side":-1,"x":43.0,"asset":"station-main-building"},
	{"track":"station_start","s":430.0,"side":1,"x":36.0,"asset":"station-corner-pavilion"},
	{"track":"station_carve","s":267.0,"side":-1,"x":43.0,"asset":"station-main-building"},
	{"track":"station_carve","s":295.0,"side":1,"x":36.0,"asset":"station-corner-pavilion"}
]

func _init(owner_lab: Node3D) -> void:
	lab=owner_lab
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/clay-heroes/manifest.json"))
	for item: Dictionary in data.assets:assets[item.id]=item
	support=JSON.parse_string(FileAccess.get_file_as_string("res://assets/clay-heroes/island-support.json")).samples

func dimension(id: String) -> Vector3:
	var d: Array=assets[id].dimensions_godot_m
	return Vector3(d[0],d[1],d[2])

func reserved(track: String,s: float,side: int,extra: float=0.0) -> bool:
	for slot in SLOTS:
		if slot.track==track and slot.side==side and absf(s-slot.s)<dimension(slot.asset).x*.5+8+extra:return true
	return false

func asset(id: String,pose: Transform3D,far_limit: float=2000.0) -> Node3D:
	var dim:=dimension(id)
	var bounds:=pose*AABB(Vector3(-dim.x*.5,0,-dim.z*.5),dim)
	if not lab._camera_bounds_clear(bounds) or not lab._safe_shape(pose.translated_local(Vector3(0,dim.y*.5,0)),dim):return null
	var path: String="res://"+str(assets[id].runtime).trim_prefix("game/")
	if not lab.mesh_assets.has(path):lab.mesh_assets[path]=load(path)
	var root: Node3D=lab.mesh_assets[path].instantiate()
	lab.extra_root.add_child(root);root.transform=pose
	root.set_meta("hero_instance",true);root.set_meta("asset_kind",id)
	var green:=id in ["cypress-grove","clay-flower-shrub-cluster"]
	var island:=id.begins_with("island-")
	var near_distance:=70.0 if green else 340.0 if island else 160.0
	var mid_distance:=180.0 if green else 850.0 if island else 400.0
	if assets[id].has("visibility_distances_m"):
		near_distance=float(assets[id].visibility_distances_m[0]);mid_distance=float(assets[id].visibility_distances_m[1])
	for part: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		var level:=int(str(part.name).right(1))
		part.set_meta("hero_lod",level)
		# Identical bounds keep distance changes synchronized across the three meshes.
		part.custom_aabb=AABB(Vector3(-dim.x*.5,0,-dim.z*.5),dim)
		part.visibility_range_begin=0.0 if level==0 else near_distance if level==1 else mid_distance
		part.visibility_range_end=near_distance if level==0 else mid_distance if level==1 else far_limit
		part.visibility_range_begin_margin=12.0 if level>0 else 0.0
		part.visibility_range_end_margin=12.0
		part.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		part.lod_bias=.8
	lab.assembly.append({"id":id,"production":"lux-hero","origin":[pose.origin.x,pose.origin.y,pose.origin.z],"basis":[[pose.basis.x.x,pose.basis.x.y,pose.basis.x.z],[pose.basis.y.x,pose.basis.y.y,pose.basis.y.z],[pose.basis.z.x,pose.basis.z.y,pose.basis.z.z]]})
	lab.polish_counts[id]=lab.polish_counts.get(id,0)+1
	return root

func ground_height(x: float) -> float:
	var distance:=absf(x)
	if distance<=36:return .55
	if distance<40:return lerpf(.55,-1.3,(distance-36)/4)
	return -1.3 if distance<67 else 4.0

func station(district: RefCounted) -> void:
	for slot in SLOTS:
		var track: SpatialTrack=lab.route.tracks[slot.track]
		var dim:=dimension(slot.asset)
		var pose: Transform3D=district.ground(track,slot.s,slot.side*slot.x).rotated_local(Vector3.UP,slot.side*PI/2)
		var low:=INF;var high:=-INF
		for along in [-dim.x*.5,0.0,dim.x*.5]:
			for across in [-dim.z*.5,0.0,dim.z*.5]:
				var x: float=slot.side*(slot.x+across)
				var p: Transform3D=district.ground(track,slot.s+along,x,ground_height(x))
				low=minf(low,p.origin.y);high=maxf(high,p.origin.y)
		pose.origin.y=high+.24
		var building:=asset(slot.asset,pose)
		if building==null:continue
		var foot:=pose;foot.origin.y=(high+low)*.5-.3
		lab._box_at(lab.extra_root,foot,Vector3(dim.x+1.2,high-low+1.08,dim.z+1.2),lab.surface.material("cream"),"HeroStationFoundation")
		var street: Transform3D=district.ground(track,slot.s,slot.side*(slot.x-dim.z*.5-3),.55)
		# Broad stair makes the station forecourt a readable destination.
		for step in 5:
			var top:=lerpf(street.origin.y,pose.origin.y,float(step+1)/5)
			var stair:=pose.translated_local(Vector3(0,0,-dim.z*.5-3.6+step*.72))
			stair.origin.y=(street.origin.y-.2+top)*.5
			lab._box_at(lab.extra_root,stair,Vector3(8,top-street.origin.y+.2,.85),lab.surface.material("cream"),"HeroStationEntryStair")
		for along in [-dim.x*.5-5,dim.x*.5+5]:
			var p: Transform3D=district.ground(track,slot.s+along,slot.side*28,.56)
			asset("cypress-grove",p.scaled_local(Vector3.ONE*.92),500)
			asset("clay-flower-shrub-cluster",p.translated_local(Vector3(slot.side*-5,.04,2)).scaled_local(Vector3.ONE*.65),420)
	for id in ["station_start","station_carve"]:
		var track: SpatialTrack=lab.route.tracks[id]
		for n in ceili(track.length/60):
			var s:=30+n*60.0
			for side in [-1,1]:
				if reserved(id,s,side,15):continue
				asset("clay-flower-shrub-cluster",district.ground(track,s,side*32,.56).rotated_local(Vector3.UP,n*.71).scaled_local(Vector3.ONE*.6),420)
	# Replace the former two blank scenic masses with an authored island-city pair.
	var exit: Transform3D=lab.composition.upright(lab.route.tracks.station_ramp.pose(lab.route.tracks.station_ramp.length))
	for side in [-1,1]:
		var center:=exit*Vector3(side*185,-48,-215 if side<0 else -295)
		var facing:=Basis.looking_at((exit.origin-center)*Vector3(1,0,1),Vector3.UP)
		island_city(Transform3D(facing,center),.95 if side<0 else 1.16)

func island_city(pose: Transform3D,factor: float) -> void:
	pose=pose.scaled_local(Vector3.ONE*factor)
	var whole:=Vector3(140,155,148)
	if not lab._safe_shape(pose.translated_local(Vector3(0,whole.y*.5,0)),whole):return
	if asset("island-rock-base",pose,3600)==null:return
	var city_size:=dimension("island-city-crown")
	var foundation_size:=Vector2(city_size.x+4.0,city_size.z+4.0)
	var low:=INF;var high:=-INF
	for sample: Dictionary in support:
		var p: Array=sample.point
		if absf(p[0])<=foundation_size.x*.5+.01 and absf(p[2])<=foundation_size.y*.5+.01:
			low=minf(low,p[1]);high=maxf(high,p[1])
	var top:=high+.30
	# This real foundation spans measured mesa relief; no hovering city on an AABB.
	lab._box_at(lab.extra_root,pose.translated_local(Vector3(0,(low+top)*.5-.35,0)),Vector3(foundation_size.x,top-low+.7,foundation_size.y),lab.surface.material("cream"),"HeroIslandFoundation").visibility_range_end=3600
	asset("island-city-crown",pose.translated_local(Vector3(0,top,0)),3600)
	for sample: Dictionary in support:
		var p: Array=sample.point;var n: Array=sample.normal
		if absf(p[0])<37 or absf(p[2])>23 or absf(p[2])<20 or n[1]<.65:continue
		var plant:=pose.translated_local(Vector3(p[0],p[1]-.15,p[2])).scaled_local(Vector3.ONE*1.65)
		asset("cypress-grove",plant,1600)
