extends Node
## Public showcase adapter. Canonical gameplay, route and camera are unchanged.
const Host = preload("res://themes/common/production_host.gd")
@export var descriptor := "art/themes/halloween_festival/integrated-theme.json"
@export var direct_scene := ""
@export var style_label := "H07"
@export var pixel_scale := 0
@export var art_shape := "continuous"
@export var art_ink := "bold"
@export var clean_view := true
var host: Node

func _ready() -> void:
    get_window().title = "Train Parkour · " + style_label
    ProjectSettings.set_setting("showcase/art_shape", art_shape)
    ProjectSettings.set_setting("showcase/art_ink", art_ink)
    if "--show-hud" in OS.get_cmdline_user_args(): clean_view = false
    if not direct_scene.is_empty():
        add_child(load(direct_scene).instantiate())
    else:
        var theme: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../" + descriptor))
        host = Host.new()
        host.camera_profile = "comparison"
        host.pixel_scale = pixel_scale
        add_child(host)
        host.create(theme, true)
    _hide_prototype_ui()

func _process(_delta: float) -> void:
    _hide_prototype_ui()

func _hide_prototype_ui() -> void:
    if not clean_view: return
    for layer: Node in find_children("*", "CanvasLayer", true, false):
        layer.visible = false
