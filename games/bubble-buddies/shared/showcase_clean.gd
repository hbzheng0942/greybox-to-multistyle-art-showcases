extends Node
## Recording presentation only; gameplay, menus, physics and input stay in their owners.
var clean_view := true

func _ready() -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument == "--show-hud":
			clean_view = false
		elif argument == "--showcase-clean":
			clean_view = true

func _process(_delta: float) -> void:
	if not clean_view:
		return
	for node in get_tree().root.find_children("*", "Label3D", true, false):
		node.visible = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var owner_game := layer.get_parent()
		if layer.name == "HUD" and owner_game.has_method("start_shift"):
			# Bubble's start/pause menu shares its CanvasLayer with prototype readouts.
			# Keep the menu interactive while suppressing the recording overlays.
			var menu: Control = owner_game.menu_panel
			for root_control in layer.get_children():
				for panel in root_control.get_children():
					if panel is CanvasItem and panel != menu:
						panel.visible = false
		else:
			layer.visible = false
