extends SceneTree
const Host = preload("res://process/original-lineage/shared-proxy/proxy_main.gd")
func _initialize() -> void:
	_launch.call_deferred()
func _launch() -> void:
	var style := "D01"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--style="):
			style = arg.get_slice("=", 1)
	if style not in ["D01", "D03", "D05", "D10"]:
		push_error("Unknown style")
		quit(2)
		return
	var game := Host.new()
	game.name = "BubbleBuddiesProxy"
	game.proxy_style = style
	root.add_child(game)
