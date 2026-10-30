extends SceneTree
## Manual clean-view launcher for the selected Hole project. No auto input.
func _initialize() -> void: call_deferred("start")
func start() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clean-size="):
			var parts=arg.trim_prefix("--clean-size=").split("x")
			if parts.size()==2 and int(parts[0])>0 and int(parts[1])>0:
				root.size=Vector2i(int(parts[0]),int(parts[1]))
				root.content_scale_size=root.size
				root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	for i in 12:
		await process_frame
		if current_scene!=null:clean(current_scene)
	var game=current_scene
	if game==null:push_error("Hole entry scene did not load");quit(1);return
	clean(game)
	print("HOLE_CLEAN_VIEW_READY: manual input; prototype HUD and debug labels hidden")
func clean(game:Node) -> void:
	if "hud" in game and game.hud!=null:game.hud.visible=false
	if "ground_labels" in game and game.ground_labels!=null:game.ground_labels.visible=false
	if "show_proxies" in game:game.show_proxies=false
	if "proxy_root" in game and game.proxy_root!=null:game.proxy_root.visible=false
