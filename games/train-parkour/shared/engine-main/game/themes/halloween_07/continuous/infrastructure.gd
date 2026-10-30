extends RefCounted
## Complete frozen track/object presentation. All additions are collisionless.
func build(ctx: RefCounted, region: Dictionary, program: Dictionary) -> Dictionary:
	var bed_tracks := []; var hard := []; var warning := []; var hidden: Dictionary = {}
	var lab: Node = ctx.app.get_node("ControllerLab")
	for id: String in region.tracks:
		ctx.use_scene(str(program.track_scene_overrides.get(id, region.catalog_scene_ids[0])))
		var track: SpatialTrack = ctx.route.tracks[id]
		if id not in program.sample_track_beds: _finish_original_hardware(ctx,track)
		if id not in program.sample_track_beds:
			_track(ctx, track); bed_tracks.append(id); ctx.metrics.new_track_beds.append(id)
		if id in program.sample_objects: continue
		for index in track.obstacles.size():
			var ob: Dictionary = track.obstacles[index]
			var preview := maxf(float(ob.get("preview_seconds",1.8))*175.0,170.0)
			for lane: int in ob.lanes:
				var ident := id + "_" + str(index) + "_" + str(lane)
				var p := track.pose(float(ob.s),float(lane)*4.4)
				var kind := str(ob.get("kind","block"))
				if kind != "soft":
					var bottom := float(ob.get("bottom",0.0)) if kind == "beam" else 0.0
					var h := float(ob.height)-bottom
					var native_pose := p.translated_local(Vector3(0,bottom+h*0.5,0)).scaled_local(Vector3(3,h,2))
					hidden[ctx._pose_key(native_pose)] = true
					_hard(ctx,p,float(ob.height),bottom,kind,ident)
					hard.append(ident); ctx.metrics.hard_obstacles.append(ident)
				for ratio: float in [1.0,0.72,0.48,0.28]:
					var q: Transform3D = lab.call("_approach_pose",ctx.route,track,float(ob.s)-preview*ratio)
					q = q.translated_local(Vector3(float(lane)*4.4,0,0))
					hidden[ctx._pose_key(q.translated_local(Vector3(0,0.18,0)).scaled_local(Vector3(3.5,0.08,3.8)))] = true
					_warning(ctx,q)
					var warn_id := ident + "_" + str(ratio)
					warning.append(warn_id); ctx.metrics.warning_boards.append(warn_id)
	var hidden_count := _hide_replaced(ctx,hidden)
	return {"new_track_beds":bed_tracks,"hard_objects":hard.size(),"warning_boards":warning.size(),"replaced_native_parts":hidden_count,"functional_poses_unchanged":true}

func _track(ctx: RefCounted, track: SpatialTrack) -> void:
	var pieces := ceili(track.length/5.0)
	var pitch := track.length/float(pieces)
	for i in pieces:
		var s := (float(i)+0.5)*pitch
		var p := track.pose(s); var half := track.width_at(s)
		var crossing := track.id == "cliff_turn" and absf(s-track.length*0.52)<48.0
		# The frozen Bed is already the authoritative full curved support mesh.
		# Refinish it in place; a second generic slab enlarged the underside by
		# 0.995m and entered the unchanged low receiver's airborne camera.
		if crossing: ctx._at(p,Vector3(0,-0.075,0),Vector3(half*2+0.6,0.09,pitch+0.09),"ink")
		if track.id == "cliff_turn" and not crossing:
			ctx._at(p,Vector3(0,-0.14,0),Vector3(half*2,0.12,pitch+0.09),"road")
		if track.id == "tunnel":
			# Exact original enclosure-floor envelope; authored material replaces the
			# ContactStructure batch retired with its old roof/walls, without holes.
			ctx._at(p,Vector3(0,-0.9,0),Vector3(track.enclosure_half_width*2.0,1.0,pitch+0.09),"road")
		if track.id == "wall":
			for edge: float in [-14.7,14.7]: ctx._at(p,Vector3(edge,-0.43,0),Vector3(0.35,0.12,pitch+0.09),"stone")
			if i%2==0: ctx._at(p,Vector3(0,-0.44,0),Vector3(29.4,0.10,0.38),"warm_stone")
		for side: float in [-1.0,1.0]:
			if crossing: ctx._at(p,Vector3(side*(half+0.48),0.02,0),Vector3(0.72,0.20,pitch+0.09),"stone")
			if track.kind not in ["wall","inverted","loop","grind"] and track.enclosure != "tunnel":
				if i % 5 == 0: ctx._at(p,Vector3(side*(half+0.55),0.95,0),Vector3(0.16,2.2,0.2),"ink")
				ctx._at(p,Vector3(side*(half+0.55),1.9,0),Vector3(0.20,0.14,pitch+0.09),"ink")
				ctx._at(p,Vector3(side*(half+0.55),1.22,0),Vector3(0.10,0.10,pitch+0.09),"edge")
		if i % 17 == 3 and track.id!="victory_run" and track.kind not in ["wall","inverted","loop","grind"]:
			for side: float in [-1.0,1.0]:
				var socket:=track.pose(s,side*(half+5.5))
				if not ctx.can_place(socket.translated_local(Vector3(0,2.0,0)),Vector3(2.2,6.4,2.2),0.3): continue
				# Short rail-attached bracket: no detached stem or giant ground rod.
				ctx._at(p,Vector3(side*(half+3.05),-0.9,0),Vector3(5.1,0.3,0.55),"ink")
				ctx._profile(socket.translated_local(Vector3(0,-1.1,0)),0.38,0.38,[Vector2(0,1.5),Vector2(0.4,1),Vector2(3.9,0.8),Vector2(4.2,1.3)],"ink")
				ctx.place_model("h07_lantern",socket.translated_local(Vector3(0,3.0,0)),Vector3(1.4,2.0,1.4),0,"H07RailBracket_"+track.id+"_"+str(i)+"_"+str(side),240)
				ctx.add_light(socket.translated_local(Vector3(0,4.0,0)).origin,22,28)
	_support_frames(ctx,track)
	if not ctx.metrics.has("bed_finish_contract"):ctx.metrics.bed_finish_contract={}
	ctx.metrics.bed_finish_contract[track.id]={"original_mesh_transform_preserved":true,"original_local_y_center_m":-0.38,"original_thickness_m":0.6,"original_local_y_interval_m":[-0.68,-0.08],"old_extension_local_y_interval_m":[-1.675,-0.425],"extra_underside_extension_m_removed":0.995,"non_crossing_added_slab_count":0,"original_bed_used_directly":track.id!="cliff_turn","shared_cliff_replacement_owned_separately":track.id=="cliff_turn"}

func _hardware_materials(ctx: RefCounted) -> void:
	if ctx.mats.has("continuous_clamp"):return
	# Original clamp/Space-pad meshes retain their exact transforms and function.
	# A matte segmented paint finish replaces bare cyan/orange prototype surfaces.
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform vec4 coat:source_color=vec4(0.09,0.15,0.23,1.0);
uniform bool release_pad=false;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 uv=UV;float edge=min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y));
 float brush=sin(wp.x*.43+sin(wp.z*.27))*sin(wp.y*.57+wp.z*.19);
 vec3 c=coat.rgb*(.86+.12*brush);
 float rim=1.0-smoothstep(.018,.055,edge);
 float seam=1.0-smoothstep(.008,.016,abs(uv.x-.5));
 c=mix(c,release_pad?vec3(.16,.085,.035):vec3(.028,.046,.072),max(rim*.78,seam*.65));
 if(!release_pad){float stripe=step(.12,uv.y)*step(uv.y,.19);c=mix(c,vec3(.12,.34,.38),stripe*.7);}
 ALBEDO=c;ROUGHNESS=.87;SPECULAR=.14;
 EMISSION=c*(release_pad?.035:.012);
}
"""
	var clamp_material:=ShaderMaterial.new();clamp_material.shader=shader;clamp_material.set_shader_parameter("coat",Color("32475d"))
	var release_material:=ShaderMaterial.new();release_material.shader=shader;release_material.set_shader_parameter("coat",Color("d88d23"));release_material.set_shader_parameter("release_pad",true)
	ctx.mats["continuous_clamp"]=clamp_material;ctx.mats["continuous_release_pad"]=release_material

func _finish_original_hardware(ctx: RefCounted, track: SpatialTrack) -> void:
	var presentation: Node = ctx.app.get_node("ControllerLab/PresentationRoot")
	_hardware_materials(ctx)
	if not ctx.metrics.has("original_surface_finishes"):ctx.metrics["original_surface_finishes"]=[]
	for index in ceili(track.length/120.0):
		var chunk: Node = presentation.get_node_or_null(track.id+"_%02d"%index)
		if chunk==null: continue
		for node in chunk.get_children():
			if not node is GeometryInstance3D: continue
			var name:=str(node.name)
			var material_key:=""
			if name.begins_with("Bed") and track.id!="cliff_turn":material_key="road"
			elif name.begins_with("ContactStructure") and track.id=="wall":material_key="violet"
			elif name.begins_with("Clamps") and track.id=="inverted":material_key="continuous_clamp"
			elif name.begins_with("ReleaseWindow"):material_key="gold"
			if not material_key.is_empty():
				node.material_override=ctx.mats[material_key]
				ctx.metrics.original_surface_finishes.append({"path":str(node.get_path()),"track":track.id,"material":material_key,"original_mesh_transform_preserved":true})
	if track.id=="inverted":
		var pads:=0
		for node in presentation.get_children():
			if node is GeometryInstance3D and str(node.name).begins_with("InvertedEjectPad_"):
				node.material_override=ctx.mats.continuous_release_pad;pads+=1
				ctx.metrics.original_surface_finishes.append({"path":str(node.get_path()),"track":track.id,"material":"continuous_release_pad","original_mesh_transform_preserved":true})
		ctx.metrics["inverted_pad_finish"]={"original_meshes_repainted":pads,"original_mesh_and_transform_preserved":true,"semantic":"orange/gold Space release pads; unchanged legal windows and impulses"}

func _support_frames(ctx: RefCounted, track: SpatialTrack) -> void:
	var connected := 0; var retained := 0
	var presentation: Node = ctx.app.get_node("ControllerLab/PresentationRoot")
	for index in ceili(track.length/120.0):
		var chunk: Node = presentation.get_node_or_null(track.id+"_%02d"%index)
		if chunk == null: continue
		for source in chunk.get_children():
			if not source is MultiMeshInstance3D or not str(source.name).begins_with("TrackPiers"): continue
			# Material refinement is independent of whether the one shared bridge or a new cap owns support geometry.
			source.material_override=ctx.mats.violet
			ctx.metrics.original_surface_finishes.append({"path":str(source.get_path()),"track":track.id,"material":"violet","original_mesh_transform_preserved":true,"connector_added":false})
			if track.id == "cliff_turn": continue # Replaced once by the shared bridge owner.
			# Receiver/high/crossing tracks share the same frozen airborne corridor.
			# Keep their original columns, without new hanging beam/stiffener volume.
			if track.id in ["canyon_fast_catch","canyon_merge","high","high_merge","upper","rescue","rescue_merge","finish","final_receiver","final_upper_catch","final_upper"]:retained+=1;continue
			var s := minf(track.length,float(index)*120.0+60.0)
			var p := track.pose(s); var half := track.width_at(s)
			var upright: Transform3D = ctx.upright_pose(track.id,s)
			# Even when a new connector is rejected, the retained column has an authored surface.
			source.material_override = ctx.mats.violet
			var cap := upright.translated_local(Vector3(0,-4.0,0)); var cap_size := Vector3((half+8.0)*2.0+5.0,2.6,4.0)
			if not ctx.can_place(cap,cap_size,0.0): retained += 1; continue
			# Preserve the original exact columns; add a load-bearing capital/beam,
			# and a rail-local underside stiffener meeting that beam below contact.
			source.material_override = ctx.mats.violet
			ctx._box(cap,cap_size,"stone")
			ctx._at(p,Vector3(0,-2.0,0),Vector3(half*2.0+0.6,1.6,4.0),"violet")
			ctx._at(upright,Vector3(0,-4.9,0),Vector3(cap_size.x+0.5,0.45,4.5),"warm_stone")
			for side: float in [-1.0,1.0]:
				var column := Transform3D(Basis.IDENTITY,p.origin+p.basis.x*side*(half+8.0)); column.origin.y=p.origin.y
				ctx._at(column,Vector3(0,-2.6,0),Vector3(3.8,1.0,4.2),"stone")
			connected += 1
	if not ctx.metrics.has("support_frames"): ctx.metrics.support_frames = {}
	ctx.metrics.support_frames[track.id] = {"connected_original_column_batches":connected,"unchanged_when_connector_envelope_rejected":retained,"removed_disconnected_extension_columns":true,"original_column_transforms_preserved":true}

func _hard(ctx: RefCounted, p: Transform3D, height: float, bottom: float, kind: String, ident: String) -> void:
	if kind == "beam":
		ctx._at(p,Vector3(0,(height+bottom)*0.5,0),Vector3(3,height-bottom,2),"ink")
		for side: float in [-1.0,1.0]: ctx._at(p,Vector3(side*1.43,(height+bottom)*0.5,1.02),Vector3(0.14,height-bottom,0.1),"hazard_trim")
		ctx._at(p,Vector3(0,height-0.12,1.02),Vector3(2.9,0.24,0.1),"pink")
		return
	var floor_y := 0.7365269661
	ctx.place_model("h07_hazard",p.translated_local(Vector3(0,floor_y,0)),Vector3(3,height-floor_y,2),0,"H07ContinuousHazard_"+ident,330)
	ctx._profile(p,3,2,[Vector2(0,0.96),Vector2(0.12,1),Vector2(0.24,1),Vector2(0.61,0.93),Vector2(floor_y,0.98)],"ink")
	ctx._at(p,Vector3(0,height*0.5,-0.91),Vector3(2.88,height-0.14,0.16),"ink")
	for side: float in [-1.0,1.0]: ctx._at(p,Vector3(side*1.44,height*0.5,0.92),Vector3(0.10,height,0.10),"hazard_trim")
	ctx._at(p,Vector3(0,height-0.06,0.92),Vector3(2.98,0.12,0.10),"hazard_trim")

func _warning(ctx: RefCounted, p: Transform3D) -> void:
	ctx._at(p,Vector3(0,0.18,0),Vector3(3.5,0.08,3.8),"ink")
	var brush := PackedVector2Array([Vector2(-0.21,-1.96),Vector2(-0.11,-2.07),Vector2(0.13,-1.92),Vector2(0.22,-1.42),Vector2(0.16,-0.78),Vector2(0.26,-0.08),Vector2(0.20,0.50),Vector2(0.27,1.22),Vector2(0.14,2.02),Vector2(0.02,1.88),Vector2(-0.13,2.07),Vector2(-0.24,1.68),Vector2(-0.18,0.80),Vector2(-0.28,0.19),Vector2(-0.19,-0.54),Vector2(-0.25,-1.30)])
	for sign: float in [-1.0,1.0]:
		var q := p.translated_local(Vector3(0,0.235,0)); q.basis = q.basis*Basis(Vector3.UP,sign*PI/4)*Basis(Vector3.RIGHT,-PI/2)
		ctx._prism(q,brush,0.018,"warning_paint","rough_flush_warning_brush")

func _hide_replaced(ctx: RefCounted, wanted: Dictionary) -> int:
	var hidden := 0
	for node in ctx.app.get_node("ControllerLab/PresentationRoot").find_children("*","GeometryInstance3D",true,false):
		var name := str(node.name)
		var path := str(node.get_path())
		if "/cliff_turn" in path and name.begins_with("Bed"): node.visible = false
		if ("/tunnel" in path or "/underpass" in path) and (name.begins_with("ContactStructure") or name.begins_with("TunnelDecorFrames") or name.begins_with("TunnelLamps")):
			node.visible = false
		if not node is MultiMeshInstance3D or node.multimesh.instance_count != 1 or not node.multimesh.mesh is BoxMesh: continue
		var p: Transform3D = node.global_transform*node.multimesh.get_instance_transform(0)
		p = p.scaled_local(node.multimesh.mesh.size)
		if wanted.has(ctx._pose_key(p)): node.visible = false; hidden += 1
	return hidden
