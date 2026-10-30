extends "res://themes/paper_atlas/presentation.gd"
## Composition-only opt-in. Frozen physics/camera and the earlier entry stay intact.
const CONTEXT = preload("res://themes/paper_atlas/assets/blockout/context.glb")
const CLOSE = preload("res://themes/paper_atlas/assets/blockout/close.glb")
const RECOMMENDED = preload("res://themes/paper_atlas/assets/blockout/recommended.glb")
const OPEN = preload("res://themes/paper_atlas/assets/blockout/open.glb")

func build(session: Node3D) -> Node3D:
	var result := super.build(session)
	# super's first child is the old station/canyon scenery, not the paper rails.
	result.get_child(0).free()
	var selected := "recommended"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--paper-layout="): selected = arg.get_slice("=",1)
	assert(selected in ["close", "open", "recommended"])
	var scenery = {"close": CLOSE, "open": OPEN, "recommended": RECOMMENDED}[selected]
	for source in [CONTEXT, scenery]:
		var model: Node3D = source.instantiate()
		result.add_child(model)
		# Keep the simple exported matte materials. No texture-replacing shader.
		_register_metadata(model)
	var lab = session.get_node("ControllerLab")
	for tree in [lab.get_node("PresentationRoot"),lab.get_node("EnvironmentRoot")]:
		for node in tree.find_children("*", "GeometryInstance3D", true, false):
			if str(node.name) in ["NearMasses", "NearSpeedMarkers", "DistantPiers", "ValleyWalls", "ValleyFloor", "FinalRidges", "FinalFloor", "HubBridge", "HubBeacon", "StationGround", "StationPlatforms", "TerminalStation", "TerminalGate"]:
				node.visible = false
	result.set_meta("layout_variant", selected)
	return result

func _register_metadata(node: Node) -> void:
	var extras: Dictionary = node.get_meta("extras", {})
	for key in ["scene_id", "asset_id", "instance_id"]:
		if extras.has(key): node.set_meta(key, str(extras[key]))
	for child in node.get_children(): _register_metadata(child)
