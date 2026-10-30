extends Control
## Compact, font-independent silhouettes; labels explain the pictograms.
var steps: Array = []
var signature := ""

func set_pet(pet: Dictionary) -> void:
	var next: Array = []
	if pet.get("needs_treatment", false) or pet.get("service") == "deflea":
		next.append(["除", pet.get("treatment_phase", "") == "ready", "bubble"])
	if pet.get("service") in ["bath", "deflea", "full"]:
		next.append(["洗", pet.stage != "dirty", "wash"])
		next.append(["干", pet.stage == "dry", "dry"])
	if pet.get("service") in ["brush", "full"]:
		next.append(["剪", pet.get("brushed", false), "cut"])
	if pet.get("service") in ["paws", "full"]:
		next.append(["爪", pet.get("paws_done", false), "paw"])
	next.append(["交", false, "exit"])
	var value := JSON.stringify(next)
	if value != signature:
		signature = value
		steps = next
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(0, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var width := minf(34.0, size.x / maxf(1, steps.size()))
	var active := true
	for i in range(steps.size()):
		var item: Array = steps[i]
		var done: bool = item[1]
		var color := Color("81b39a") if done else (Color("ffe1a6") if active else Color("8299a3"))
		if not done:
			active = false
		var p := Vector2(i * width + 9, 9)
		match item[2]:
			"bubble":
				draw_circle(p, 5, color, false, 1.5)
				draw_circle(p + Vector2(5, -5), 2, color)
			"wash":
				draw_polyline(PackedVector2Array([p+Vector2(-7,-3),p+Vector2(-5,5),p+Vector2(5,5),p+Vector2(7,-3)]), color, 1.5)
				draw_line(p+Vector2(-5,0),p+Vector2(5,0),color,1.5)
			"dry":
				for y in [-4, 0, 4]:
					draw_line(p+Vector2(-6,y),p+Vector2(6,y-2),color,1.5)
			"cut":
				draw_circle(p+Vector2(-4,4),2,color,false,1.5)
				draw_circle(p+Vector2(4,4),2,color,false,1.5)
				draw_line(p+Vector2(-3,2),p+Vector2(5,-6),color,1.5)
				draw_line(p+Vector2(3,2),p+Vector2(-5,-6),color,1.5)
			"paw":
				draw_circle(p+Vector2(0,2),4,color)
				for x in [-5, 0, 5]:
					draw_circle(p+Vector2(x,-5),2,color)
			"exit":
				draw_line(p+Vector2(-6,0),p+Vector2(6,0),color,2)
				draw_polyline(PackedVector2Array([p+Vector2(2,-4),p+Vector2(6,0),p+Vector2(2,4)]),color,2)
		draw_string(get_theme_default_font(), Vector2(i*width+3,29), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
