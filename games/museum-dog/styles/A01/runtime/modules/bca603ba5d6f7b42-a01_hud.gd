extends RefCounted
## A01 presentation only. Shared scoring, prompts and controls retain ownership.
const INK=Color("263c51")
const CREAM=Color("f4e7cf")
const ORANGE=Color("df7435")
const BONE_LABELS={"head":"猛犸头骨","jaw":"猛犸下颌","neck":"颈骨","spine":"脊柱","ribs":"肋骨","chest":"肩骨","pelvis":"胯骨","tail":"尾骨","front_leg_l":"左前腿骨","front_leg_r":"右前腿骨","back_leg_l":"左后腿骨","back_leg_r":"右后腿骨"}
const PROP_LABELS={"plate":"瓷盘","vase":"花瓶","vase_big":"大花瓶","button":"互动按钮","ball":"彩球","rock":"矿石","bone":"骨骼标本","specimen":"动物标本","bust":"半身像","souvenir":"纪念品","craft":"手工作品","brochure":"导览册"}

static func localize_status(game)->void:
	if game.state_label==null or not is_instance_valid(game.held):return
	var name:String=str(game.held.name)
	var bone_id:String=str(game.held.get_meta("bone_id",""))
	var label:String=str(BONE_LABELS.get(bone_id,"骨骼")) if not bone_id.is_empty() else str(PROP_LABELS.get(str(game.held.get_meta("kind","")),"展品"))
	game.state_label.text=game.state_label.text.replace("咬住："+name,"咬住："+label)

func apply(game)->Dictionary:
	if game.loss_label==null:return {"applied":false,"reason":"missing_native_hud"}
	var score:Control=game.loss_label.get_parent()
	var heat:Control=game.heat_label.get_parent()
	var ui:Control=score.get_parent()
	_passthrough(ui)
	var panels:=0
	for child in ui.get_children():
		if child is ColorRect and child.get_child_count()>0 and child.size.y<100:
			_skin_panel(child)
			panels+=1
	for panel in [score,heat]:
		for child in panel.get_children():
			if child is Label:
				child.add_theme_color_override("font_color",INK)
				child.add_theme_color_override("font_shadow_color",Color(0,0,0,0))
				if child==game.loss_label or child==game.heat_label:
					child.add_theme_font_size_override("font_size",28)
	game.heat_bar.color=ORANGE
	for child in heat.get_children():
		if child is ColorRect and child!=game.heat_bar:child.color=Color("d7cfbd")
	game.state_label.add_theme_color_override("font_color",CREAM)
	game.state_label.add_theme_color_override("font_outline_color",Color(.09,.15,.21,.78))
	game.state_label.add_theme_constant_override("outline_size",4)
	game.gag_title.add_theme_color_override("font_color",CREAM)
	game.gag_title.add_theme_color_override("font_outline_color",Color(.09,.15,.21,.85))
	game.gag_title.add_theme_constant_override("outline_size",6)
	game.gag_sub.add_theme_color_override("font_color",Color("ffe0a8"))
	return {"applied":true,"panels":panels,"shared_gameplay_modified":false,"palette":"navy_cream_orange","requires_native_hud_review":true}

func _skin_panel(panel:ColorRect)->void:
	panel.color=Color(0,0,0,0)
	var skin:=Panel.new()
	skin.name="A01SoftCanvasPanel"
	skin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	skin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box:=StyleBoxFlat.new()
	box.bg_color=Color(CREAM,.95)
	box.border_color=Color("a88e69")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.shadow_color=Color(.08,.12,.17,.20)
	box.shadow_size=4
	box.shadow_offset=Vector2(0,3)
	skin.add_theme_stylebox_override("panel",box)
	panel.add_child(skin)
	panel.move_child(skin,0)
	for child in panel.get_children():
		if child is Label:child.add_theme_color_override("font_color",INK)

func _passthrough(node:Node)->void:
	if node is Control:node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():_passthrough(child)
