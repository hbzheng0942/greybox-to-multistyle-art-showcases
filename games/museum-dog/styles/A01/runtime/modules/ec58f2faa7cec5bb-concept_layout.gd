extends RefCounted
## A01 concept-driven visual layout. Native owner IDs and physics are untouched.
## Absolute dimensions below are authored choices inferred from V1–V6, not image measurements.

func panel_count(region:String,width:float)->int:
	if region in ["kids","vestibule"]:return 1
	var span:=6.5 if region=="hall" else (5.5 if region=="taxidermy" else 4.9)
	return maxi(1,ceili(width/span))

func wall_segments(region:String,width:float,group_id:String)->Array[Vector2]:
	if region=="porcelain" and group_id=="porcelain/shell_wall/-18.0_1.0":
		# Main rear cloth field is wider than the flanking leaves in V2.
		return [Vector2(-width*.365,width*.27),Vector2(0,width*.46),Vector2(width*.365,width*.27)]
	var count:=panel_count(region,width)
	var segments:Array[Vector2]=[]
	for i in range(count):segments.append(Vector2(-width*.5+width*(float(i)+.5)/count,width/count))
	return segments

func wall_bands(region:String)->Array:
	match region:
		"hall":return [[0.0,2.85,"navy"],[2.85,4.0,"cream"],[4.0,20.0,"navy"]]
		"porcelain":return [[0.0,2.05,"navy"],[2.05,3.55,"cream"],[3.55,20.0,"navy"]]
		"taxidermy":return [[0.0,1.70,"navy"],[1.70,3.85,"cream"],[3.85,20.0,"navy"]]
		"kids":return [[0.0,1.30,"navy"],[1.30,5.10,"cream"],[5.10,20.0,"navy"]]
		"vestibule":return [[0.0,.65,"navy"],[.65,1.75,"cream"],[1.75,20.0,"navy"]]
	return [[0.0,20.0,"navy"]]

func graphic_box(group:Dictionary,original:AABB)->AABB:
	var family:=str(group.family_id)
	var id:=str(group.id)
	var center:=original.get_center()
	if family=="information_panel" and str(group.region)=="hall":
		# V1's primary portraits are on the SIDE walls, outside the rear columns
		# in the main view. Retain these original semantic owners; only artwork
		# changes wall/rotation. Keep the rear field reserved for mammoth + door.
		var x:float=-7.85 if center.x<0 else 7.77
		return AABB(Vector3(x,2.05,-3.45),Vector3(.08,1.80,1.50))
	if family=="hall_wall_print":
		# Consolidated secondary groups in the front side bays, away from both
		# three-metre side doors and the main rear-wall composition.
		var z:=4.35
		var width:=1.45
		var height:=1.65
		var y:=2.68
		if id.ends_with("_0") or id.ends_with("_3.4"):
			# Companion prints belong to the front wall, clear of the four tall
			# columns; avoid hiding them behind the z=6.2 column shafts.
			var x:float=(5.35 if id.ends_with("_0") else 3.75)*(1.0 if center.x>0 else -1.0)
			return AABB(Vector3(x-.48,2.08,7.77),Vector3(.96,1.10,.08))
		var x:=7.77 if center.x>0 else -7.85
		return AABB(Vector3(x,y-height*.5,z-width*.5),Vector3(.08,height,width))
	if family=="kids_wall_panel":
		# Three large even illustrations are the rear-wall focal group.
		return AABB(Vector3(center.x-1.06,1.78,-14.87),Vector3(2.12,2.24,.07))
	if family=="fossil_panel":
		# Fish / ribs / leaf keep the existing left-to-right semantic order.
		return AABB(Vector3(17.74,1.95,center.z-.94),Vector3(.10,1.78,1.88))
	if family=="entry_guide_board":
		return AABB(Vector3(-1.35,1.85,11.14),Vector3(2.70,1.30,.10))
	return original

func transform_artwork(artwork:Node3D,group:Dictionary)->Dictionary:
	# Called once by the scene owner AFTER native_local source fitting. This
	# authored translation moves artwork, never its semantic anchor or collider.
	if str(group.get("family_id",""))!="wall_specimen_head":return {}
	if artwork.has_meta("a01_concept_layout_applied"):return artwork.get_meta("a01_concept_layout_applied")
	var delta:=Vector3(0,1.50,0)
	# Convert a world translation through its parent basis (safe under local fit).
	if artwork.get_parent() is Node3D:
		artwork.position+=artwork.get_parent().global_basis.inverse()*delta
	else:artwork.position+=delta
	var result:={"semantic_group":str(group.id),"method":"visual_only_world_translation","world_delta":[0,1.50,0],"physics_unchanged":true,"reason":"secondary high wall-head row; restore three primary fossil plaques"}
	artwork.set_meta("a01_concept_layout_applied",result)
	return result
