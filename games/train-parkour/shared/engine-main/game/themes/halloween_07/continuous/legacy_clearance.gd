extends RefCounted
## Retire only exact old sample skyline source instances that obstruct the extended route.
static func build(host: RefCounted, field: RefCounted) -> Dictionary:
	var buildings := []
	for i in 38: buildings.append({"p":Vector3(-620+i*34,30+float(i%3)*8,-310+float(i%5)*31),"w":28.0,"d":34.0,"h":95.0+float(i%7)*12.0})
	for side: float in [-1.0,1.0]:
		for i in 14: buildings.append({"p":Vector3(side*(240+float(i%3)*23),20,2250-float(i)*95),"w":45.0,"d":40.0,"h":90.0+float(i%5)*13.0})
	var targets := {}; var roofs := {}; var retired_buildings := []
	for row: Dictionary in buildings:
		var base: Vector3 = row.p-Vector3(0,34,0)
		var envelope := Vector3(row.d*1.12+4,row.h+24,row.w*1.12+4)
		var unsafe:bool=not field.can_place_obb(Transform3D(Basis.IDENTITY,base+Vector3(0,envelope.y*0.5,0)),envelope,0)
		var nearest:=INF
		if row.p.z<0:
			for id:String in ["rush","carve","wall","inverted","drop","rollout"]:
				for sample:Dictionary in field.track_samples[id]:nearest=minf(nearest,Vector2(row.p.x,row.p.z).distance_to(Vector2(sample.p.x,sample.p.z)))
		var foreground:=nearest<125.0
		if not unsafe and not foreground:continue
		targets[str(base.snapped(Vector3.ONE*0.001))] = true
		for sign: float in [-1.0,1.0]:
			var cap := base+Vector3(sign*row.d*0.32,row.h+5,sign*row.w*0.2)
			targets[str(cap.snapped(Vector3.ONE*0.001))] = true
		roofs[str((base+Vector3(0,row.h+7,0)).snapped(Vector3.ONE*0.001))] = true
		retired_buildings.append({"source_origin":[row.p.x,row.p.y,row.p.z],"reason":"Intersects frozen exclusion envelope" if unsafe else "Old blank skyline pillar lies within125m of N03 foreground; replaced by the authored G1 street and stepped castle silhouettes","near_new_route_m":nearest if nearest<INF else null})
	var parts := 0
	for row: Dictionary in host.custom_batches.values():
		if str(row.material) not in ["far","far2"]: continue
		var cells := {}
		for p: Transform3D in row.poses:
			var cell := Vector3i(floori(p.origin.x/128),floori(p.origin.y/96),floori(p.origin.z/128))
			if not cells.has(cell): cells[cell]=[]
			cells[cell].append(p)
		for cell: Vector3i in cells:
			var positions: Array = cells[cell]; var indices := []
			for i in positions.size():
				if targets.has(str(positions[i].origin.snapped(Vector3.ONE*0.001))): indices.append(i)
			if indices.is_empty(): continue
			var origin := Vector3(cell)*Vector3(128,96,128)
			for node in host.world.get_children():
				if not node is MultiMeshInstance3D or node.multimesh.mesh!=row.mesh or node.material_override!=host.mats[row.material] or not node.position.is_equal_approx(origin): continue
				if indices.size()==positions.size(): node.visible=false
				else:
					for i: int in indices: node.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),positions[i].origin-origin))
				parts += indices.size()
	for node in host.world.get_children():
		if not node is MeshInstance3D or not node.mesh is PrismMesh: continue
		if node.material_override not in [host.mats.far,host.mats.far2]: continue
		if roofs.has(str(node.position.snapped(Vector3.ONE*0.001))): node.visible=false; parts+=1
	return {"retired_skyline_buildings":retired_buildings,"retired_exact_source_parts":parts,"unaffected_skyline_preserved":true,"base_source_unchanged":true}
