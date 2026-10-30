extends RefCounted
## Bounded replacements on existing station terrain and canyon/valley islands.
## Generated groups keep their own proportions; all transforms are world-up.
var lab: Node3D
var records: Array[Dictionary]=[]
var counts: Dictionary={}
func _init(owner_lab: Node3D) -> void:lab=owner_lab

func remember(node: Node3D,id: String,section: String,support: String) -> bool:
	if node==null:return false
	counts[id]=counts.get(id,0)+1
	counts[id+":"+section]=counts.get(id+":"+section,0)+1
	var p:=node.global_position
	records.append({"id":id,"section":section,"support":support,"origin":[p.x,p.y,p.z],"scale":node.global_basis.get_scale().x})
	return true

func house(pose: Transform3D,section: String,ordinal: int) -> bool:
	var id:="terrace-garden-house"
	if ordinal%2!=0 or counts.get(id+":"+section,0)>=8:return false
	var dim: Vector3=lab.heroes.dimension(id)
	# The existing 25x12m foundation and street steps face +Z; Lux fronts face -Z.
	var factor:=minf(1.0,minf(23.0/dim.x,10.8/dim.z))
	var facing:=pose.rotated_local(Vector3.UP,PI).scaled_local(Vector3.ONE*factor)
	# Place the front step at the existing plinth's street edge, not its centre.
	facing.origin+=pose.basis.z*(6.0-dim.z*factor*.5)
	var placed:=false
	var offset_m:=dim.x*factor*.5+.3
	for offset in [-offset_m,offset_m]:
		var paired:=facing;paired.origin+=pose.basis.x*offset
		placed=remember(lab.heroes.asset(id,paired,850),id,section,"TownhouseGroundedPlinth") or placed
	return placed

func garden(district: RefCounted,t: SpatialTrack,s: float,side: int) -> bool:
	var id:="clay-topiary-garden"
	if counts.get(id+":"+t.id,0)>=12:return false
	var dim: Vector3=lab.heroes.dimension(id)*.85
	var pose: Transform3D=district.ground(t,s,side*28).rotated_local(Vector3.UP,side*PI/2)
	var low:=INF;var high:=-INF
	for along in [-dim.x*.5,0.0,dim.x*.5]:
		for across in [-dim.z*.5,0.0,dim.z*.5]:
			var h: float=district.ground(t,s+along,side*28+across,.55).origin.y
			low=minf(low,h);high=maxf(high,h)
	pose.origin.y=high+.06
	var node: Node3D=lab.heroes.asset(id,pose.scaled_local(Vector3.ONE*.85),650)
	if node==null:return false
	var footing:=pose;footing.origin.y=(high+low)*.5-.15
	lab._box_at(lab.extra_root,footing,Vector3(dim.x+.2,high-low+.42,dim.z+.2),lab.surface.material("cream"),"LuxGardenGroundedPlinth")
	return remember(node,id,t.id,"LuxGardenGroundedPlinth")

func island(center: Vector3,dim: Vector3,section: String) -> bool:
	var id:="cliff-terrace-garden"
	var canyon:=section in ["canyon_safe","canyon_fast","canyon_merge"]
	var valley:=section in ["cliff_turn","upper","rescue","finish","valley"]
	if not canyon and not valley:return false
	var group:="canyon" if canyon else "valley"
	if counts.get(group,0)>=6:return false
	var source_dim: Vector3=lab.heroes.dimension(id)
	# Root below the common sea plane; fit the authored island envelope uniformly.
	var factor:=dim.y/source_dim.y
	var root:=Vector3(center.x,-50.0,center.z)
	var near: Vector3=lab._nearest_scenery(center)
	var direction: Vector3=(near-root)*Vector3(1,0,1)
	if direction.length_squared()<.01:return false
	root-=direction.normalized()*maxf(0.0,source_dim.x*factor-dim.x)*.65
	var pose:=Transform3D(Basis.looking_at(direction.normalized(),Vector3.UP),root).scaled_local(Vector3.ONE*factor)
	if not remember(lab.heroes.asset(id,pose,2400),id,group,"Continuous rock base embedded below sea plane"):return false
	counts[group]=counts.get(group,0)+1
	return true
