extends RefCounted
## A01 fallback for an actual tabletop obstruction after camera candidates fail.
const PARTITION=preload("res://styles/A01/runtime/modules/8a2387b28b666c09-camera_furniture_surfaces.gd")
const TORSO=[Vector3(-.17,.38,.08),Vector3(.17,.38,.08),Vector3(0,.40,.26)]
var game
var guard
var furniture_enabled:=true
var furniture_rows:Array=[]
var furniture_mesh_restores:Array=[]
var furniture_trace:Dictionary={}

func setup(target,owner_guard)->void:
	game=target
	guard=owner_guard
	for id in game.visual_catalog.entries:
		var entry:Dictionary=game.visual_catalog.entries[id]
		if entry.role!="gift_table" or entry.artwork==null or entry.collisions.is_empty():continue
		var collision:CollisionShape3D=entry.collisions[0]
		if not collision.shape is BoxShape3D:continue
		var body:StaticBody3D=collision.get_parent()
		var top:float=collision.global_position.y+collision.shape.size.y*.5
		var row:Dictionary={"semantic_id":id,"body":body,"shape":collision,"surfaces":[],"alpha":1.0,"active_dwell":0.0,"max_dwell":0.0,"total_dwell":0.0,"restorations":0,"pending_restore":false}
		for mesh:MeshInstance3D in entry.artwork.find_children("*","MeshInstance3D",true,false):
			var part:Dictionary=PARTITION.partition_support(mesh,top,collision.shape.size.y)
			if not part.ready:continue
			var overrides:Array=[]
			for surface in range(mesh.mesh.get_surface_count()):overrides.append(mesh.get_surface_override_material(surface))
			furniture_mesh_restores.append({"mesh":mesh,"original_mesh":mesh.mesh,"material_override":mesh.material_override,"surface_overrides":overrides})
			mesh.mesh=part.mesh;mesh.material_override=null
			for surface in range(mesh.mesh.get_surface_count()):mesh.set_surface_override_material(surface,null)
			for surface in part.support_surfaces:
				var source:Material=mesh.get_active_material(surface)
				if not source is StandardMaterial3D:continue
				var fade:StandardMaterial3D=source.duplicate()
				mesh.set_surface_override_material(surface,fade)
				row.surfaces.append({"mesh":mesh,"surface":surface,"source":source,"material":fade,"base_alpha":source.albedo_color.a,"base_transparency":source.transparency,"support_triangles":part.selected_triangles})
		if not row.surfaces.is_empty():furniture_rows.append(row)

func update(delta:float,no_safe_candidate:bool,viewport_ok:bool)->void:
	if not is_instance_valid(game):return
	var snapshots:Array=[]
	for row in furniture_rows:
		var hit_count:=0
		var local:Vector3=row.shape.to_local(game.dog.global_position)
		var half:Vector3=row.shape.shape.size*.5
		var underneath:bool=absf(local.x)<half.x+.1 and absf(local.z)<half.z+.1 and local.y+.4<half.y
		if furniture_enabled and no_safe_candidate and underneath:
			for point:Vector3 in TORSO:
				var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.cam.global_position,game.dog.to_global(point),1))
				if hit.get("collider")==row.body and _caps_only_path(game.cam.global_position,game.dog.to_global(point),row):hit_count+=1
		var needed:bool=furniture_enabled and no_safe_candidate and hit_count>=2 and underneath and viewport_ok
		row.alpha=move_toward(float(row.alpha),.18 if needed else 1.0,delta*(9.0 if needed else 12.0))
		if needed:
			row.active_dwell+=delta;row.total_dwell+=delta;row.max_dwell=maxf(row.max_dwell,row.active_dwell)
			row.pending_restore=true
		else:row.active_dwell=0.0
		if row.alpha>=.999 and row.pending_restore:
			row.restorations+=1;row.pending_restore=false
		for item in row.surfaces:
			item.material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if row.alpha<.999 else item.base_transparency
			item.material.albedo_color.a=item.base_alpha*row.alpha
		snapshots.append({"semantic_id":row.semantic_id,"alpha":row.alpha,"needed":needed,"native_blocked_torso_points":hit_count,"underneath":underneath,"active_dwell_seconds":row.active_dwell,"max_dwell_seconds":row.max_dwell,"total_dwell_seconds":row.total_dwell,"restorations":row.restorations,"faded_surface_count":row.surfaces.size(),"surface_paths":row.surfaces.map(func(item):return str(item.mesh.get_path())+":"+str(item.surface))})
	furniture_trace={"enabled":furniture_enabled,"no_admitted_opaque_camera_pose":no_safe_candidate,"scope":"gift_table horizontal slab caps only; legs/apron/exhibits/walls and all collision untouched","rows":snapshots,"long_fallback_limit_seconds":1.5,"raw_probes":guard.composition.get("visible_probe_points",0)}

func _caps_only_path(from:Vector3,to:Vector3,row:Dictionary)->bool:
	# Excluding a whole native box is truthful only when this ray crosses the
	# two faded horizontal caps and does not pass through an opaque apron side.
	var a:Vector3=row.shape.to_local(from);var b:Vector3=row.shape.to_local(to)
	var half:Vector3=row.shape.shape.size*.5
	if not (a.y>half.y and b.y< -half.y):return false
	for y in [-half.y,half.y]:
		var t:float=(float(y)-a.y)/(b.y-a.y)
		var p:Vector3=a.lerp(b,t)
		if absf(p.x)>=half.x-.005 or absf(p.z)>=half.z-.005:return false
	return true

func native_exclusions(from:Vector3,to:Vector3)->Array[RID]:
	var excluded:Array[RID]=[]
	for row in furniture_rows:
		if row.alpha<=.25 and _caps_only_path(from,to,row):excluded.append(row.body.get_rid())
	return excluded

func _furniture_visible(position:Vector3,points:Array)->int:
	var visible:=0
	var visual_ignored:Array[RID]=guard._transparent_held_rids()
	var inverse:Transform3D=game.cam.global_transform.affine_inverse()
	var half_y:=tan(deg_to_rad(game.cam.fov*.5))
	var aspect:float=game.cam.get_viewport().get_visible_rect().size.aspect()
	for local:Vector3 in points:
		var point:Vector3=game.dog.to_global(local)
		if not guard._point_on_screen(point,inverse,half_y,aspect):continue
		var hit:Dictionary=guard.visual_occlusion_ray(position,point,3,visual_ignored)
		var native_ignored:=native_exclusions(position,point)
		var native:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position,point,1,native_ignored))
		if hit.is_empty() and native.is_empty():visible+=1
	return visible

func restore()->void:
	for item in furniture_mesh_restores:
		if not is_instance_valid(item.mesh):continue
		item.mesh.mesh=item.original_mesh
		item.mesh.material_override=item.material_override
		for surface in range(item.surface_overrides.size()):item.mesh.set_surface_override_material(surface,item.surface_overrides[surface])
	furniture_mesh_restores.clear();furniture_rows.clear()

func snapshot()->Dictionary:
	var result:Dictionary=furniture_trace.duplicate(true)
	result["raw_probes"]=guard.composition.get("visible_probe_points",0)
	result["presentation_torso_visible_points"]=_furniture_visible(game.cam.global_position,TORSO)
	return result
