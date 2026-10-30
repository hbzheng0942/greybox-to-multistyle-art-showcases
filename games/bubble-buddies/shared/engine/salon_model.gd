class_name SalonModel
extends RefCounted

const ShiftDirector = preload("res://shared/engine/shift_director.gd")
const DEFAULT_SHIFT_SEED := 20261016
const SHIFT_SECONDS := 150.0
const SOAP_SECONDS := 2.2
const SOAK_SECONDS := 5.0
const RINSE_SECONDS := 1.4
# Kept as the total active work for older callers; soaking always needs tick().
const WASH_SECONDS := SOAP_SECONDS + RINSE_SECONDS
const DRY_SECONDS := 12.0
const BRUSH_SECONDS := 3.0
const PAWS_SECONDS := 2.4
const FAST_DRY_MULTIPLIER := 2.0
const COMIC_WARNING_SECONDS := 1.0
const COMIC_ACCIDENT_SECONDS := 2.0
const COSMETIC_REPAIR_SECONDS := 1.8
const COSMETIC_BASE_MULTIPLIER := 0.65
const SERVICE_BASE_POINTS := {"bath": 160, "brush": 90, "paws": 80, "deflea": 210, "full": 300}
const MAX_SPEED_BONUS := 20
const DUO_STAR_SCORES := [900, 1400, 1900]
const SOLO_STAR_SCORES := [550, 850, 1150]
const TREATMENT_START_SECONDS := 0.8
const TREATMENT_SECONDS := 6.0
const TOWEL_SECONDS := 2.0
const LAUNDRY_SECONDS := 9.0
const TOWEL_TOTAL := 3
const SHAKE_SECONDS := 10.0
const ESCAPE_WAIT_SECONDS := 8.0
const ESCAPE_WARNING_SECONDS := 4.0
const ESCAPE_COOLDOWN := 25.0
const CATCH_PROTECTION_SECONDS := 12.0
const TIME_EPSILON := 0.000001
const MAX_PETS := 6
const MAX_PENDING := 4
const WAIT_SECONDS := 35.0
const SOLO_WAIT_SECONDS := 45.0
const MISSED_PENALTY := 25
const WAIT_MISSED_PENALTY := 10
const SLOT_NAMES := ["intake0", "intake1", "intake2", "intake_dry", "buffer_wet", "buffer_dry", "wash0", "wash1", "treatment", "dryer", "bench0", "bench1", "brush", "paws"]
const PET_NAMES := ["泡泡", "卷卷", "豆包", "毛球", "布丁", "团子", "芝麻", "奶盖",
	"桃桃", "糯米", "果冻", "花生", "芋圆", "橘子", "米粒", "松饼", "饼干", "汤圆", "年糕", "雪糕"]
var slots: Dictionary = {}
var shift_seed: int = DEFAULT_SHIFT_SEED
var order_schedule: Array = []
var carried: Array = [-1, -1]
var pets: Dictionary = {}
var score: int = 0
var delivered: int = 0
var missed: int = 0
var pending_orders: Array[Dictionary] = []
var arrivals_total: int = 0
var refused: int = 0
var remaining: float = SHIFT_SECONDS
var running: bool = false
var ended: bool = false
var goal: int = 900
var elapsed: float = 0.0
var events: Array[Dictionary] = []
var towels: Dictionary = {}
var held_towels: Array = [-1, -1]
var towel_slots: Dictionary = {}
var towels_clean: int:
	get:
		return _count_towels("clean")
var towels_wet: int:
	get:
		return _count_towels("wet")
var laundry_count: int:
	get:
		return _count_towels("washing")
var laundry_remaining: float = 0.0
var stats: Dictionary = {}
var towel_active: int:
	get:
		return _count_towels("active")

var _duo: bool = true
var _next_id: int = 1
var _arrival_index: int = 0
var _escape_cooldown_remaining: float = 0.0
# A hold survives target changes. Only an actual release ends the player's hold.
# Per-pet contexts allow a held key to revisit a target without inventing a release.
var _work_holds: Array[Dictionary] = [{}, {}]
var _comic_repair_locks: Array[Dictionary] = [{}, {}]
# Work registers active time; tick consumes it together with automatic drying.
# Multiple carers never stack the same instant into more than the configured total rate.
var _dryer_work_credit: Dictionary = {}


func _init() -> void:
	reset()


func reset(duo: bool = true, seed: int = DEFAULT_SHIFT_SEED) -> void:
	_duo = duo
	shift_seed = seed
	order_schedule = ShiftDirector.build(duo, seed)
	slots.clear()
	for slot: String in SLOT_NAMES:
		slots[slot] = -1
	carried = [-1, -1]
	_work_holds = [{}, {}]
	_comic_repair_locks = [{}, {}]
	_dryer_work_credit.clear()
	pets.clear()
	events.clear()
	score = 0
	delivered = 0
	missed = 0
	pending_orders.clear()
	arrivals_total = 0
	refused = 0
	remaining = SHIFT_SECONDS
	elapsed = 0.0
	running = true
	ended = false
	goal = DUO_STAR_SCORES[0] if duo else SOLO_STAR_SCORES[0]
	towels = {
		1: {"id": 1, "state": "clean", "location": "rack"},
		2: {"id": 2, "state": "clean", "location": "bench1"},
		3: {"id": 3, "state": "clean", "location": "laundry"},
	}
	held_towels = [-1, -1]
	towel_slots = {"rack": 1, "bench0": -1, "bench1": 2}
	laundry_remaining = 0.0
	stats = {"towel_uses": 0, "laundry_batches": 0, "brushes": 0, "paws": 0, "shakes": 0, "rewets": 0, "handoffs": 0, "escapes": 0, "catches": 0, "rescue_catches": 0, "towel_handoffs": 0}
	stats.merge({"treatments": 0, "arrivals_admitted": 0, "refused": 0, "waiting_expired": 0,
		"delivered_by_service": {"bath": 0, "brush": 0, "paws": 0, "deflea": 0, "full": 0},
		"missed_by_service": {"bath": 0, "brush": 0, "paws": 0, "deflea": 0, "full": 0},
		"frizzed": 0, "crooked": 0, "cosmetic_repairs": 0, "cosmetic_deliveries": 0,
		"window_preparations": 0, "window_exchanges": 0, "teammate_repairs": 0})
	_next_id = 1
	_arrival_index = 0
	_escape_cooldown_remaining = 0.0
	_offer_order("bath", 0.0)
	_offer_order("deflea", 0.0)
	_offer_order("brush", 0.0)
	# Seed work in both rooms without assigning fictional player actions.
	slots["intake0"] = 2
	slots["intake1"] = -1
	slots["intake2"] = -1
	slots["intake_dry"] = -1
	slots["wash0"] = 1
	slots["brush"] = 3
	pets[1].merge({"location": "wash0", "wash_phase": "soak", "soap": 1.0, "wash": 0.53, "soak_remaining": 3.0}, true)
	pets[2]["location"] = "intake0"
	pets[3]["location"] = "brush"


func tick(delta: float) -> void:
	if not running or delta <= 0.0:
		return
	# A positive float residue must not be stranded below the slicing threshold:
	# the HUD uses ceil(), so even this tiny remainder otherwise displays 0:01.
	if remaining <= TIME_EPSILON:
		_finish_shift()
		return
	# Bounded slices preserve event order during long frames and headless checks.
	var pending: float = minf(delta, remaining)
	while pending > 0.0 and running:
		var step: float = minf(pending, 0.25)
		var until_order: float = next_arrival_in()
		if until_order > TIME_EPSILON:
			step = minf(step, until_order)
		_advance(step)
		pending -= step


func is_ready(pet: Dictionary) -> bool:
	if pet.get("stage", "") != "dry":
		return false
	var service: String = pet.get("service", "bath")
	if service in ["bath", "full", "deflea"] and float(pet.get("wash", 0.0)) < 0.999999:
		return false
	if service == "deflea" and pet.get("treatment_phase", "untreated") != "ready":
		return false
	if service in ["brush", "full"] and not bool(pet.get("brushed", false)):
		return false
	if service in ["paws", "full"] and not bool(pet.get("paws_done", false)):
		return false
	return true


func service_label(pet: Dictionary) -> String:
	match pet.get("service", "bath"):
		"brush":
			return "修毛美容"
		"paws":
			return "剪甲护爪"
		"full":
			return "洗剪全套"
		"deflea":
			return "除虫洗护"
	return "快洗"


func route_label(pet: Dictionary) -> String:
	match pet.get("service", "bath"):
		"brush":
			return "美容 → 交还"
		"paws":
			return "护爪 → 交还"
		"full":
			return "洗澡 → 干燥 → 美容＋护爪（可换序）→ 交还"
		"deflea":
			return "除虫 → 冲净 → 干燥 → 交还"
	return "洗澡 → 干燥 → 交还"


func next_step(pet: Dictionary) -> String:
	if pet.get("location", "") == "waiting":
		return "等接待空位"
	if pet.get("location", "") == "loose":
		return "先抱回，再冲净"
	if pet.get("service", "") == "deflea" and pet.get("treatment_phase", "untreated") != "ready":
		if pet.get("treatment_phase", "untreated") == "treating":
			return "除虫中 %d秒" % int(ceilf(float(pet.get("treatment_remaining", 0.0))))
		return "送除虫罩，按住启动"
	if pet.get("stage", "") == "dirty":
		return wash_status(pet)
	if pet.get("stage", "") == "wet":
		return "机器吹干 / 毛巾擦干"
	if pet.get("needs_brush", false):
		if pet.get("needs_paws", false):
			return "美容／护爪任选先做，两项都要"
		return "送美容台修毛"
	if pet.get("needs_paws", false):
		return "送护爪台剪甲"
	return "美容补救 / 瑕疵交还（基础分65%）" if _has_cosmetic(pet) else "交还主人"


func next_arrival_in() -> float:
	if _arrival_index >= order_schedule.size():
		return -1.0
	return maxf(0.0, float(order_schedule[_arrival_index][0]) - elapsed)


func shift_phase() -> String:
	if elapsed >= 110.0:
		return "收尾：停止新单"
	if not _duo:
		return "稳步接待" if elapsed >= 14.0 else "开场分工"
	if elapsed >= 91.0:
		return "最后一波"
	if elapsed >= 78.0:
		return "整理回流"
	if elapsed >= 50.0:
		return "第二波追赶"
	if elapsed >= 36.0:
		return "整理回流"
	if elapsed >= 8.0:
		return "第一波追赶"
	return "开场分工"


func held_item(player_id: int) -> Dictionary:
	if not _valid_player(player_id):
		return {"kind": "none", "id": -1}
	if carried[player_id] != -1:
		return {"kind": "pet", "id": int(carried[player_id])}
	if held_towels[player_id] != -1:
		return {"kind": "towel", "id": int(held_towels[player_id])}
	return {"kind": "none", "id": -1}


func towel_at(slot: String) -> int:
	return int(towel_slots.get(slot, -1))


func towel_label(towel_id: int) -> String:
	if not towels.has(towel_id):
		return ""
	match towels[towel_id]["state"]:
		"clean":
			return "干毛巾"
		"wet":
			return "湿毛巾"
		"washing":
			return "洗烘中的毛巾"
	return "包裹中的毛巾"


func wash_status(pet: Dictionary) -> String:
	if pet.get("stage", "") != "dirty":
		return "已洗净"
	if pet.get("service", "") == "deflea":
		if pet.get("treatment_phase", "untreated") != "ready":
			return "先去除虫罩"
		if not String(pet.get("location", "")).begins_with("wash"):
			return "除虫好了，送浴池冲净"
	match pet.get("wash_phase", "soap"):
		"soak":
			return "泡泡浸洗 %d秒" % int(ceilf(float(pet.get("soak_remaining", 0.0))))
		"rinse":
			return "快冲净！要跑了" if pet.get("escape_warning", false) else "泡好了，按住冲净"
	return "按住搓泡泡"


func interact(player_id: int, slot: String) -> String:
	var error: String = _interaction_error(player_id, slot)
	if not error.is_empty():
		return error
	var held_id: int = int(carried[player_id])
	var towel_id: int = int(held_towels[player_id])
	if slot == "laundry":
		if towel_id != -1:
			held_towels[player_id] = -1
			towels[towel_id]["location"] = "laundry"
			events.append({"type": "towel_placed", "towel_id": towel_id, "player_id": player_id, "slot": slot})
			_decision(player_id, "return_towel", -1, slot)
			return "放回干毛巾" if towels[towel_id]["state"] == "clean" else "湿毛巾已投入，空手按护理启动洗烘"
		for candidate: int in towels.keys():
			if towels[candidate]["state"] == "clean" and towels[candidate]["location"] == "laundry":
				_pickup_towel(player_id, candidate, slot)
				return "拿了一条干毛巾，递给队友吧"
		return "正在洗烘，稍后到这里拿干毛巾" if laundry_count > 0 else "没有可取干毛巾；空手按护理洗湿毛巾"
	if slot == "exit":
		if held_id == -1:
			return "先抱起完成服务的宠物"
		var held: Dictionary = pets[held_id]
		var points: int = delivery_points(held)
		var cosmetic_types: Array[String] = _cosmetic_types(held)
		var cosmetic: bool = not cosmetic_types.is_empty()
		if cosmetic:
			stats["cosmetic_deliveries"] += 1
		var pet_name: String = held["name"]
		score += points
		delivered += 1
		stats["delivered_by_service"][held["service"]] += 1
		var service: String = held["service"]
		_decision(player_id, "deliver", held_id, slot)
		_remove_pet(held_id)
		events.append({"type": "delivered", "pet_id": held_id, "name": pet_name, "service": service, "points": points,
			"cosmetic": cosmetic, "cosmetic_types": cosmetic_types, "player_id": player_id})
		_admit_pending()
		return "%s 顶着搞笑造型回家了！+%d（基础分65%%）" % [pet_name, points] if cosmetic else "%s 香喷喷地回家了！+%d" % [pet_name, points]
	if not slots.has(slot) and not towel_slots.has(slot):
		return "没有可操作的工位"
	var occupant: int = int(slots.get(slot, -1))
	if towel_id != -1:
		if not towel_slots.has(slot):
			return "毛巾放在交接窗或毛巾架，湿毛巾送回洗烘机"
		if occupant != -1:
			var target: Dictionary = pets[occupant]
			if towels[towel_id]["state"] != "clean":
				return "湿毛巾不能擦宠物，先送回洗烘机"
			if target["stage"] != "wet":
				return "这只现在不需要擦干"
			if int(target["towel_id"]) != -1:
				return "已经包上毛巾，空手按护理擦干"
			held_towels[player_id] = -1
			towels[towel_id]["state"] = "active"
			towels[towel_id]["location"] = "pet:%d" % occupant
			target["towel_id"] = towel_id
			target["towel_active"] = true
			target["towel_progress"] = 0.0
			stats["towel_uses"] += 1
			events.append({"type": "towel_wrapped", "pet_id": occupant, "towel_id": towel_id, "player_id": player_id})
			events.append({"type": "towel_started", "pet_id": occupant, "towel_id": towel_id, "player_id": player_id})
			_decision(player_id, "choose_towel", occupant, slot)
			return "包上毛巾了，空手按护理擦干"
		if towel_at(slot) != -1:
			return "这里已经有毛巾了，先腾空交接位"
		held_towels[player_id] = -1
		towel_slots[slot] = towel_id
		towels[towel_id]["location"] = slot
		events.append({"type": "towel_placed", "towel_id": towel_id, "player_id": player_id, "slot": slot})
		_decision(player_id, "place_towel", -1, slot)
		return "放下了%s" % towel_label(towel_id)
	if held_id == -1:
		if towel_at(slot) != -1:
			var pickup_id: int = towel_at(slot)
			_pickup_towel(player_id, pickup_id, slot)
			return "拿起了%s" % towel_label(pickup_id)
		if occupant == -1:
			return "这里暂时没有宠物"
		if pets[occupant]["towel_active"]:
			return "毛巾还没擦完，先空手按护理完成"
		if slot == "treatment" and pets[occupant]["treatment_phase"] != "ready":
			return "除虫护理尚未完成" if pets[occupant]["treatment_phase"] == "treating" else "先按住护理，启动除虫泡泡罩"
		slots[slot] = -1
		_dryer_work_credit.erase(occupant)
		_detach_towel(pets[occupant], slot)
		carried[player_id] = occupant
		var last_carrier: int = pets[occupant].get("last_carrier", -1)
		if last_carrier != -1 and last_carrier != player_id:
			stats["handoffs"] += 1
		pets[occupant]["last_carrier"] = player_id
		pets[occupant]["location"] = "p%d" % player_id
		_decision(player_id, "pickup", occupant, slot)
		_admit_pending()
		return "抱起了 %s" % pets[occupant]["name"]
	var pet: Dictionary = pets[held_id]
	var window_towel := towel_at(slot)
	if window_towel != -1:
		# One handoff can replace the used cloth, or use a teammate's prepared
		# clean cloth. Ownership changes atomically; no resource is teleported.
		if towels[window_towel].state == "wet":
			_pickup_towel(player_id, window_towel, slot)
			stats["window_exchanges"] += 1
		else:
			towel_slots[slot] = -1
			towels[window_towel].state = "active"
			towels[window_towel].location = "pet:%d" % held_id
			pet.towel_id = window_towel
			pet.towel_active = true
			pet.towel_progress = 0.0
			stats["towel_uses"] += 1
			stats["window_preparations"] += 1
			events.append({"type":"towel_wrapped", "pet_id":held_id, "towel_id":window_towel, "player_id":player_id, "prepared":true})
	carried[player_id] = -1
	slots[slot] = held_id
	pet["location"] = slot
	_decision(player_id, "choose_dryer" if slot == "dryer" else "place", held_id, slot)
	return "放下了 %s" % pet["name"]


func can_interact(player_id: int, slot: String) -> bool:
	# Only model legality; runtime still checks the approach, distance and sight.
	return _interaction_error(player_id, slot).is_empty()


func _interaction_error(player_id: int, slot: String) -> String:
	if not running:
		return "本班已暂停或结束"
	if not _valid_player(player_id):
		return "该玩家未加入"
	var pet_id: int = int(carried[player_id])
	if pet_id != -1:
		return _pet_placement_error(slot, pet_id)
	var towel_id: int = int(held_towels[player_id])
	if slot == "laundry":
		if towel_id != -1:
			return ""
		for towel: Dictionary in towels.values():
			if towel["state"] == "clean" and towel["location"] == "laundry":
				return ""
		return "正在洗烘，稍后到这里拿干毛巾" if laundry_count > 0 else "没有可取干毛巾；空手按护理洗湿毛巾"
	if slot == "exit":
		return "先抱起完成服务的宠物"
	if not slots.has(slot) and not towel_slots.has(slot):
		return "没有可操作的工位"
	var occupant: int = int(slots.get(slot, -1))
	if towel_id != -1:
		if not towel_slots.has(slot):
			return "毛巾放在交接窗或毛巾架，湿毛巾送回洗烘机"
		if occupant != -1:
			if towels[towel_id]["state"] != "clean":
				return "湿毛巾不能擦宠物，先送回洗烘机"
			if pets[occupant]["stage"] != "wet":
				return "这只现在不需要擦干"
			if int(pets[occupant]["towel_id"]) != -1:
				return "已经包上毛巾，空手按护理擦干"
			return ""
		return "这里已经有毛巾了，先腾空交接位" if towel_at(slot) != -1 else ""
	if towel_at(slot) != -1:
		return ""
	if occupant == -1:
		return "这里暂时没有宠物"
	if pets[occupant]["towel_active"]:
		return "毛巾还没擦完，先空手按护理完成"
	if slot == "treatment" and pets[occupant]["treatment_phase"] != "ready":
		return "除虫护理尚未完成" if pets[occupant]["treatment_phase"] == "treating" else "先按住护理，启动除虫泡泡罩"
	return ""


func can_receive_pet(slot: String, pet_id: int) -> bool:
	# Pure station compatibility. Runtime still owns distance, sight and intent.
	return _pet_placement_error(slot, pet_id).is_empty()


func _pet_placement_error(slot: String, pet_id: int) -> String:
	if not running:
		return "本班已暂停或结束"
	if not pets.has(pet_id):
		return "宠物已经不在店里了"
	if slot == "laundry":
		return "先放下宠物，再存取毛巾"
	var pet: Dictionary = pets[pet_id]
	if slot == "exit":
		if not is_ready(pet):
			return "还没完成：" + next_step(pet)
		return ""
	if not slots.has(slot) and not towel_slots.has(slot):
		return "没有可操作的工位"
	if slot == "rack":
		return "毛巾架只能放毛巾"
	if int(slots.get(slot, -1)) != -1:
		return "这个位置已经有宠物了"
	var stage: String = pet["stage"]
	if towel_at(slot) != -1:
		var cloth: Dictionary = towels[towel_at(slot)]
		if not slot.begins_with("bench") or (cloth.state != "wet" and not (cloth.state == "clean" and stage == "wet")):
			return "交接位被毛巾占着，先请队友腾空"
	if slot == "treatment":
		if pet["service"] != "deflea":
			return "这张订单不需要除虫，" + next_step(pet)
		if pet["treatment_phase"] == "ready":
			return "除虫已完成，" + next_step(pet)
	if slot.begins_with("wash") and pet["service"] == "deflea" and pet["treatment_phase"] != "ready":
		return "先送除虫泡泡罩，护理完成后再冲净"
	if slot.begins_with("wash") and stage != "dirty":
		return "已经洗干净啦"
	if slot == "dryer" and stage == "dirty":
		return "先洗澡，再吹干"
	if slot == "dryer" and stage == "dry":
		return "已经干了，" + next_step(pet) + "；暂放请用接待或暂候台"
	if slot == "brush":
		if stage != "dry":
			return "先弄干，再修毛美容"
		if not pet["needs_brush"] and not _has_cosmetic(pet):
			return "这只不需要再修毛啦"
	if slot == "paws":
		if stage != "dry":
			return "先弄干，再剪甲护爪"
		if not pet["needs_paws"]:
			return "这只不需要再护爪啦"
	return ""


func can_work(player_id: int, slot: String) -> bool:
	return _work_error(player_id, slot).is_empty()


func _work_error(player_id: int, slot: String) -> String:
	if not running:
		return "本班已暂停或结束"
	if not _valid_player(player_id):
		return "该玩家未加入"
	if held_towels[player_id] != -1:
		return "先放下毛巾，或用拿放给湿宠包上"
	if carried[player_id] != -1:
		return "" if slot.is_empty() and pets[int(carried[player_id])]["stage"] == "wet" else "先放下怀里的宠物"
	if slot == "laundry":
		if laundry_count > 0:
			return "毛巾正在洗烘，完成后到这里取"
		for towel: Dictionary in towels.values():
			if towel["state"] == "wet" and towel["location"] == "laundry":
				return ""
		return "先把湿毛巾拿回来投入洗烘机"
	if not slots.has(slot) or slots[slot] == -1:
		return "这里没有需要护理的宠物"
	var pet: Dictionary = pets[int(slots[slot])]
	if slot == "treatment":
		if pet["treatment_phase"] == "ready":
			return "除虫好了，抱去普通浴池冲净"
		return "泡泡罩正在除虫，先做下一张单" if pet["treatment_phase"] == "treating" else ""
	if slot.begins_with("wash"):
		if pet["stage"] != "dirty":
			return "洗好了！快送去弄干"
		if pet["service"] == "deflea" and pet["treatment_phase"] != "ready":
			return "先完成除虫护理"
		return "泡泡正在浸洗，先照看另一只吧" if pet["wash_phase"] == "soak" else ""
	if slot == "brush" or slot == "paws":
		if pet["stage"] != "dry":
			return "先弄干，再修毛美容" if slot == "brush" else "先弄干，再剪甲护爪"
		if slot == "brush":
			if _has_cosmetic(pet) and _comic_repair_locks[player_id].has(int(pet["id"])):
				return "先松开护理键，再补救；队友也能接手"
			if pet["needs_brush"] or _has_cosmetic(pet) or _hold_phase(player_id, int(pet["id"]), "brush") == "overgroom":
				return ""
		return "" if slot == "paws" and pet["needs_paws"] else "这项护理已完成：" + next_step(pet)
	if slot.begins_with("bench"):
		if pet["stage"] == "dry" and _has_cosmetic(pet):
			return "先松开护理键，再补救；队友也能接手" if _comic_repair_locks[player_id].has(int(pet.id)) else ""
		if pet["stage"] != "wet":
			return "这里可以交接，湿宠可用毛巾擦干"
		return "" if pet["towel_active"] else "先拿一条干毛巾，用拿放包上；也可送去烘干"
	if slot == "dryer":
		if pet["stage"] == "wet":
			return ""
		return "" if _hold_phase(player_id, int(pet["id"]), "dryer") == "overdry" else "干啦，" + next_step(pet)
	return "这里只暂放宠物，抱到对应护理台继续"


func work(player_id: int, slot: String, delta: float) -> String:
	var error: String = _work_error(player_id, slot)
	if not error.is_empty():
		return error
	# Queries and non-positive/non-finite work must have no state side effects.
	if not is_finite(delta) or delta <= 0.0:
		return "按住护理继续；松手可安全等待"
	var amount: float = delta
	if held_towels[player_id] != -1:
		return "先放下毛巾，或用拿放给湿宠包上"
	if carried[player_id] != -1:
		var held: Dictionary = pets[int(carried[player_id])]
		if slot.is_empty() and held["stage"] == "wet":
			_soothe(held, amount)
			return "抱稳安抚中，松手后继续倒计时"
		return "先放下怀里的宠物"
	if slot == "laundry":
		if laundry_count > 0:
			return "毛巾正在洗烘，完成后到这里取"
		if amount <= 0.0:
			return "空手按护理，启动已投入的湿毛巾"
		var batch: Array[int] = []
		for towel_id: int in towels.keys():
			if towels[towel_id]["state"] == "wet" and towels[towel_id]["location"] == "laundry":
				batch.append(towel_id)
		if batch.is_empty():
			return "先把湿毛巾拿回来投入洗烘机"
		for towel_id: int in batch:
			towels[towel_id]["state"] = "washing"
		laundry_remaining = LAUNDRY_SECONDS
		stats["laundry_batches"] += 1
		events.append({"type": "laundry_started", "count": batch.size(), "towel_ids": batch, "player_id": player_id})
		_decision(player_id, "start_laundry", -1, slot)
		return "%d 条毛巾开始洗烘，稍后记得来拿！" % batch.size()
	if not slots.has(slot) or slots[slot] == -1:
		return "这里没有需要护理的宠物"
	var pet_id: int = int(slots[slot])
	var pet: Dictionary = pets[pet_id]
	if slot == "treatment":
		if pet["treatment_phase"] == "ready":
			return "除虫好了，抱去普通浴池冲净"
		if pet["treatment_phase"] == "treating":
			return "泡泡罩正在除虫，先做下一张单"
		if amount <= 0.0:
			return "按住护理启动除虫泡泡罩"
		pet["last_carer"] = player_id
		pet["treatment_phase"] = "starting"
		pet["treatment_progress"] = minf(1.0, float(pet["treatment_progress"]) + amount / TREATMENT_START_SECONDS)
		if float(pet["treatment_progress"]) >= 0.999999:
			pet["treatment_progress"] = 1.0
			pet["treatment_phase"] = "treating"
			pet["treatment_remaining"] = TREATMENT_SECONDS
			stats["treatments"] += 1
			events.append({"type": "treatment_started", "pet_id": pet_id, "player_id": player_id, "slot": slot})
			return "除虫开始，先照看别的宠物！"
		return "启动除虫泡泡罩……"
	if slot.begins_with("wash"):
		if pet["stage"] != "dirty":
			return "洗好了！快送去弄干"
		if pet["service"] == "deflea" and pet["treatment_phase"] != "ready":
			return "先完成除虫护理"
		if pet["wash_phase"] == "soak":
			return "泡泡正在浸洗，先照看另一只吧"
		if amount <= 0.0:
			return wash_status(pet)
		pet["last_carer"] = player_id
		if pet["wash_phase"] == "soap":
			pet["soap"] = minf(1.0, float(pet["soap"]) + amount / SOAP_SECONDS)
			pet["wash"] = 0.45 * float(pet["soap"])
			if float(pet["soap"]) >= 0.999999:
				pet["soap"] = 1.0
				pet["wash"] = 0.45
				pet["wash_phase"] = "soak"
				pet["soak_remaining"] = SOAK_SECONDS
				events.append({"type": "soaking", "pet_id": pet_id, "slot": slot})
				return "泡泡开始浸洗，先去接下一只！"
			return "搓搓泡泡……"
		pet["rinse"] = minf(1.0, float(pet["rinse"]) + amount / RINSE_SECONDS)
		pet["wash"] = 0.65 + 0.35 * float(pet["rinse"])
		pet["bath_wait"] = 0.0
		pet["escape_warning"] = false
		if float(pet["rinse"]) >= 0.999999:
			pet["rinse"] = 1.0
			pet["wash"] = 1.0
			pet["wash_phase"] = "done"
			pet["stage"] = "wet"
			pet["dry"] = 0.0
			pet["shake"] = SHAKE_SECONDS
			events.append({"type": "washed", "pet_id": pet_id})
			return "洗好了！快送去弄干"
		return "冲净泡泡……"
	if slot == "dryer":
		if pet["stage"] == "wet":
			var key: String = _hold_key(pet_id, slot)
			if not _work_holds[player_id].has(key):
				_work_holds[player_id][key] = {"pet_id": pet_id, "slot": slot, "phase": "boost", "danger": 0.0, "warned": false, "credit": 0.0}
			if not _dryer_work_credit.has(pet_id):
				_dryer_work_credit[pet_id] = {}
			_dryer_work_credit[pet_id][player_id] = maxf(float(_dryer_work_credit[pet_id].get(player_id, 0.0)), amount)
			pet["last_carer"] = player_id
			return "强风快干2倍！干了记得松手"
		return _overcare(player_id, pet, slot, amount, "frizzed")
	if slot == "brush":
		if pet["needs_brush"]:
			pet["last_carer"] = player_id
			pet["brush"] = minf(1.0, float(pet["brush"]) + amount / BRUSH_SECONDS)
			if float(pet["brush"]) >= 0.999999:
				pet["brush"] = 1.0
				pet["brushed"] = true
				pet["needs_brush"] = false
				stats["brushes"] += 1
				events.append({"type": "brushed", "pet_id": pet_id, "player_id": player_id})
				if pet["frizzy"]:
					_clear_cosmetics(pet, player_id, ["frizzy"])
				if not pet["crooked_once"]:
					_work_holds[player_id][_hold_key(pet_id, slot)] = {"pet_id": pet_id, "slot": slot, "phase": "overgroom", "danger": 0.0, "warned": false, "credit": 0.0}
				return "修好了！松手；" + next_step(pet)
			return "咔嚓修毛……"
		if _has_cosmetic(pet):
			pet["last_carer"] = player_id
			pet["repair_progress"] = minf(1.0, float(pet["repair_progress"]) + amount / COSMETIC_REPAIR_SECONDS)
			if float(pet["repair_progress"]) >= 0.999999:
				_clear_cosmetics(pet, player_id, _cosmetic_types(pet))
				_work_holds[player_id].erase(_hold_key(pet_id, slot))
				return "造型救回来了！" + next_step(pet)
			return "补救造型 %d%%……" % int(float(pet["repair_progress"]) * 100.0)
		return _overcare(player_id, pet, slot, amount, "crooked")
	if slot == "paws":
		if amount <= 0.0:
			return "按住护理，剪甲护爪"
		pet["last_carer"] = player_id
		pet["paws"] = minf(1.0, float(pet["paws"]) + amount / PAWS_SECONDS)
		if float(pet["paws"]) >= 0.999999:
			pet["paws"] = 1.0
			pet["paws_done"] = true
			pet["needs_paws"] = false
			stats["paws"] += 1
			events.append({"type": "paws_done", "pet_id": pet_id, "player_id": player_id})
			return "小爪整齐！" + next_step(pet)
		return "咔哒剪甲……"
	if slot.begins_with("bench"):
		if pet["stage"] == "dry" and _has_cosmetic(pet):
			pet["repair_progress"] = minf(1.0, float(pet["repair_progress"]) + amount / COSMETIC_REPAIR_SECONDS)
			if float(pet["repair_progress"]) >= 0.999999:
				_clear_cosmetics(pet, player_id, _cosmetic_types(pet))
				return "窗口补梳救回来了！" + next_step(pet)
			return "窗口急救补梳……"
		if pet["stage"] != "wet":
			return "这里可以交接，湿宠可用毛巾擦干"
		if not pet["towel_active"]:
			return "先拿一条干毛巾，用拿放包上；也可送去烘干"
		if amount <= 0.0:
			return "按住护理，擦干包着毛巾的宠物"
		pet["last_carer"] = player_id
		_soothe(pet, amount)
		pet["towel_progress"] = minf(1.0, float(pet["towel_progress"]) + amount / TOWEL_SECONDS)
		if float(pet["towel_progress"]) >= 0.999999:
			pet["towel_progress"] = 1.0
			pet["dry"] = 1.0
			pet["stage"] = "dry"
			pet["shake"] = 0.0
			pet["soothe_credit"] = 0.0
			pet["towel_active"] = false
			towels[int(pet["towel_id"])]["state"] = "wet"
			events.append({"type": "towel_dried", "pet_id": pet_id, "towel_id": pet["towel_id"]})
			return "擦干了！抱走宠物后，湿毛巾会留在窗台"
		return "毛巾擦擦……"
	return "先抱去护理台吧"


func release_work(player_id: int) -> void:
	if not _valid_player(player_id):
		return
	_work_holds[player_id].clear()
	_comic_repair_locks[player_id].clear()
	for pet_id: int in _dryer_work_credit.keys():
		_dryer_work_credit[pet_id].erase(player_id)
		if _dryer_work_credit[pet_id].is_empty():
			_dryer_work_credit.erase(pet_id)


func delivery_points(pet: Dictionary) -> int:
	# This is a pure preview. Core service requirements still gate delivery.
	if not is_ready(pet):
		return 0
	var base: int = int(SERVICE_BASE_POINTS.get(pet.get("service", "bath"), 0))
	if _has_cosmetic(pet):
		base = int(floorf(float(base) * COSMETIC_BASE_MULTIPLIER))
	return base + speed_bonus(pet)


func speed_bonus(pet: Dictionary) -> int:
	return int(ceilf(MAX_SPEED_BONUS * clampf(float(pet.get("patience", 0.0)) / maxf(1.0, float(pet.get("max_patience", 80.0))), 0.0, 1.0)))


func star_thresholds() -> Array:
	return DUO_STAR_SCORES if _duo else SOLO_STAR_SCORES


func stars() -> int:
	var count := 0
	for threshold: int in star_thresholds():
		count += int(score >= threshold)
	return count


func has_won() -> bool:
	return score >= goal


func cosmetic_status(pet: Dictionary) -> String:
	var types: Array[String] = _cosmetic_types(pet)
	if not types.is_empty():
		var labels: Array[String] = []
		if "frizzy" in types:
			labels.append("炸毛")
		if "crooked" in types:
			labels.append("歪刘海")
		var repair: float = float(pet.get("repair_progress", 0.0))
		var choice: String = " / 瑕疵交还基础分65%" if is_ready(pet) else " / 须先完成基础护理"
		return "＋".join(labels) + (" · 美容补救%d%%" % int(repair * 100.0)) + choice
	var pet_id: int = int(pet.get("id", -1))
	for holds: Dictionary in _work_holds:
		for context: Dictionary in holds.values():
			if int(context["pet_id"]) != pet_id:
				continue
			match context["phase"]:
				"boost":
					if pet.get("stage", "") == "wet" and pet.get("location", "") == "dryer":
						return "强风快干2倍 · 干了要松手"
				"overdry":
					return "快松手！要炸毛了" if context["warned"] else "干了！松手"
				"overgroom":
					return "快松手！刘海要歪了" if context["warned"] else "修好了！松手"
	return "造型正常"


func _has_cosmetic(pet: Dictionary) -> bool:
	return bool(pet.get("frizzy", false)) or bool(pet.get("crooked", false))


func _cosmetic_types(pet: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if pet.get("frizzy", false):
		result.append("frizzy")
	if pet.get("crooked", false):
		result.append("crooked")
	return result


func _hold_key(pet_id: int, slot: String) -> String:
	return "%s:%d" % [slot, pet_id]


func _hold_phase(player_id: int, pet_id: int, slot: String) -> String:
	return String(_work_holds[player_id].get(_hold_key(pet_id, slot), {}).get("phase", ""))


func _overcare(player_id: int, pet: Dictionary, slot: String, amount: float, incident: String) -> String:
	var pet_id: int = int(pet["id"])
	var key: String = _hold_key(pet_id, slot)
	var holds: Dictionary = _work_holds[player_id]
	var once_field: String = "frizzed_once" if incident == "frizzed" else "crooked_once"
	if pet[once_field] or not holds.has(key):
		return "护理已经完成，可以安全抱走"
	var context: Dictionary = holds[key]
	# Queue only the actually requested interval. Repeated same-frame calls and
	# two nearby players cannot compress the two-second reaction window.
	context["credit"] = maxf(float(context["credit"]), amount)
	return cosmetic_status(pet)


func _advance_comic(pet: Dictionary, delta: float) -> void:
	var pet_id: int = int(pet["id"])
	for player_id: int in range(2):
		var holds: Dictionary = _work_holds[player_id]
		for key: String in holds.keys():
			var context: Dictionary = holds[key]
			if int(context["pet_id"]) != pet_id or context["phase"] not in ["overdry", "overgroom"]:
				continue
			var credit: float = float(context["credit"])
			context["credit"] = maxf(0.0, credit - delta)
			if pet["stage"] != "dry" or pet["location"] != context["slot"]:
				context["credit"] = 0.0
				continue
			var amount: float = minf(delta, credit)
			if amount <= 0.0:
				continue
			var incident: String = "frizzed" if context["phase"] == "overdry" else "crooked"
			var threshold: float = COMIC_ACCIDENT_SECONDS if context["warned"] else COMIC_WARNING_SECONDS
			context["danger"] = minf(threshold, float(context["danger"]) + amount)
			if not context["warned"] and float(context["danger"]) + TIME_EPSILON >= COMIC_WARNING_SECONDS:
				var already_warned: bool = _other_hold_warned(pet_id, String(context["phase"]), player_id, key)
				context["warned"] = true
				# Discard a giant call's leftover at the warning boundary. There must
				# be another actual work request after the warning before an accident.
				context["credit"] = 0.0
				if not already_warned:
					events.append({"type": "comic_warning", "incident": incident, "pet_id": pet_id, "player_id": player_id, "slot": context["slot"]})
			elif float(context["danger"]) + TIME_EPSILON >= COMIC_ACCIDENT_SECONDS:
				pet["frizzy" if incident == "frizzed" else "crooked"] = true
				pet["frizzed_once" if incident == "frizzed" else "crooked_once"] = true
				_comic_repair_locks[player_id][pet_id] = true
				pet["comic_culprit"] = player_id
				stats[incident] += 1
				events.append({"type": incident, "pet_id": pet_id, "player_id": player_id, "slot": context["slot"]})
				_forget_pet_work(pet_id, false)
				return


func _other_hold_warned(pet_id: int, phase: String, player_id: int, key: String) -> bool:
	for other_player: int in range(2):
		for other_key: String in _work_holds[other_player]:
			if other_player == player_id and other_key == key:
				continue
			var other: Dictionary = _work_holds[other_player][other_key]
			if int(other["pet_id"]) == pet_id and other["phase"] == phase and bool(other["warned"]):
				return true
	return false


func _clear_cosmetics(pet: Dictionary, player_id: int, types: Array[String]) -> void:
	var cleared: Array[String] = []
	for kind: String in types:
		if bool(pet.get(kind, false)):
			pet[kind] = false
			cleared.append(kind)
	if cleared.is_empty():
		return
	if not _has_cosmetic(pet):
		pet["repair_progress"] = 0.0
	stats["cosmetic_repairs"] += 1
	var teammate := int(pet.get("comic_culprit", -1)) >= 0 and int(pet.get("comic_culprit", -1)) != player_id
	if teammate:
		stats["teammate_repairs"] += 1
	events.append({"type": "cosmetic_repaired", "pet_id": int(pet["id"]), "player_id": player_id, "slot": pet.location, "cosmetic_types": cleared, "teammate_rescue":teammate})


func _forget_pet_work(pet_id: int, clear_locks: bool) -> void:
	for player_id: int in range(2):
		for key: String in _work_holds[player_id].keys():
			if int(_work_holds[player_id][key]["pet_id"]) == pet_id:
				_work_holds[player_id].erase(key)
		if clear_locks:
			_comic_repair_locks[player_id].erase(pet_id)
	_dryer_work_credit.erase(pet_id)


func rewet(pet_id: int) -> bool:
	if not running or not pets.has(pet_id):
		return false
	var pet: Dictionary = pets[pet_id]
	# A splash only changes a dry pet once; preserve cleaning and both grooming tasks.
	if pet["stage"] != "dry":
		return false
	pet["stage"] = "wet"
	pet["dry"] = 0.55
	pet["shake"] = SHAKE_SECONDS
	pet["soothe_credit"] = 0.0
	_forget_pet_work(pet_id, false)
	stats["rewets"] += 1
	events.append({"type": "rewet", "pet_id": pet_id})
	return true


func catch_pet(player_id: int, pet_id: int) -> String:
	# Runtime checks distance and wall visibility; the model owns atomic pickup.
	if not running or not _valid_player(player_id):
		return "现在不能找回宠物"
	if not pets.has(pet_id) or pets[pet_id]["location"] != "loose":
		return "这只已经被照顾好啦"
	if held_item(player_id)["kind"] != "none":
		return "先腾出双手，再抱回宠物"
	var pet: Dictionary = pets[pet_id]
	var previous_carer: int = int(pet["last_carer"])
	pet["location"] = "p%d" % player_id
	pet["last_carrier"] = player_id
	pet["bath_wait"] = 0.0
	pet["escape_warning"] = false
	pet["escape_protected_until"] = elapsed + CATCH_PROTECTION_SECONDS
	carried[player_id] = pet_id
	stats["catches"] += 1
	var teammate_rescue: bool = previous_carer != -1 and previous_carer != player_id
	if teammate_rescue:
		stats["rescue_catches"] += 1
	events.append({"type": "caught", "pet_id": pet_id, "player_id": player_id, "previous_carer": previous_carer, "teammate_rescue": teammate_rescue})
	_decision(player_id, "catch", pet_id, "loose")
	return "抱回了 %s！护理进度还在" % pet["name"]


func drain_events() -> Array:
	var drained: Array = events.duplicate(true)
	events.clear()
	return drained


func _advance(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	elapsed = SHIFT_SECONDS - remaining
	_escape_cooldown_remaining = maxf(0.0, _escape_cooldown_remaining - delta)
	if laundry_count > 0:
		laundry_remaining = maxf(0.0, laundry_remaining - delta)
		if laundry_remaining <= 0.000001:
			var count: int = laundry_count
			for towel: Dictionary in towels.values():
				if towel["state"] == "washing":
					towel["state"] = "clean"
			laundry_remaining = 0.0
			events.append({"type": "laundry_ready", "count": count})
	for pet_id: int in pets.keys():
		var pet: Dictionary = pets[pet_id]
		pet["patience"] = maxf(0.0, float(pet["patience"]) - delta)
		if float(pet["patience"]) <= 0.000001:
			_record_missed(pet, "patience", false)
			_remove_pet(pet_id)
			continue
		if pet["location"] == "treatment" and pet["treatment_phase"] == "treating":
			pet["treatment_remaining"] = maxf(0.0, float(pet["treatment_remaining"]) - delta)
			if float(pet["treatment_remaining"]) <= TIME_EPSILON:
				pet["treatment_remaining"] = 0.0
				pet["treatment_phase"] = "ready"
				pet["wash_phase"] = "rinse"
				pet["wash"] = 0.65
				events.append({"type": "treatment_ready", "pet_id": pet_id, "slot": "treatment"})
		if pet["stage"] == "dirty" and String(pet["location"]).begins_with("wash"):
			_advance_bath(pet_id, delta)
		if pet["location"] == "dryer" and pet["stage"] == "wet":
			pet["soothe_credit"] = 0.0
			_dry_pet(pet_id, delta)
		elif pet["stage"] == "wet":
			# A wrapped pet can wriggle, but its cloth contains the spray. The
			# scarce towel and occupied window remain committed until active care.
			if pet["towel_active"]:
				pet["soothe_credit"] = 0.0
				continue
			var soothed: float = minf(delta, float(pet["soothe_credit"]))
			pet["soothe_credit"] = maxf(0.0, float(pet["soothe_credit"]) - delta)
			pet["shake"] = float(pet["shake"]) - (delta - soothed)
			if float(pet["shake"]) <= 0.000001:
				pet["shake"] = SHAKE_SECONDS
				stats["shakes"] += 1
				events.append({"type": "shake", "pet_id": pet_id})
		_advance_comic(pet, delta)
	# Waiting has its own clock. An admitted order gets the full service allowance.
	for index: int in range(pending_orders.size() - 1, -1, -1):
		var ticket: Dictionary = pending_orders[index]
		ticket["patience"] = maxf(0.0, float(ticket["patience"]) - delta)
		if float(ticket["patience"]) <= TIME_EPSILON:
			pending_orders.remove_at(index)
			_record_missed(ticket, "waiting_timeout", true)
	_admit_pending()
	while _arrival_index < order_schedule.size() and elapsed + TIME_EPSILON >= float(order_schedule[_arrival_index][0]):
		var order: Array = order_schedule[_arrival_index]
		_arrival_index += 1
		_offer_order(String(order[1]), float(order[0]))
	if remaining <= TIME_EPSILON:
		_finish_shift()


func _advance_bath(pet_id: int, delta: float) -> void:
	var pet: Dictionary = pets[pet_id]
	var waiting_time: float = delta
	if pet["wash_phase"] == "soak":
		var previous_remaining: float = float(pet["soak_remaining"])
		pet["soak_remaining"] = maxf(0.0, previous_remaining - delta)
		pet["wash"] = 0.45 + 0.2 * (1.0 - float(pet["soak_remaining"]) / SOAK_SECONDS)
		if float(pet["soak_remaining"]) > TIME_EPSILON:
			return
		pet["soak_remaining"] = 0.0
		pet["wash"] = 0.65
		pet["wash_phase"] = "rinse"
		pet["bath_wait"] = 0.0
		waiting_time = maxf(0.0, delta - previous_remaining)
		events.append({"type": "bath_ready", "pet_id": pet_id, "slot": pet["location"]})
	if pet["wash_phase"] != "rinse":
		return
	# Catch grace does not silently accumulate a full escape timer. Otherwise a
	# late catch after the global cooldown could warn and escape in the same frame.
	waiting_time = minf(waiting_time, maxf(0.0, elapsed - float(pet["escape_protected_until"])))
	pet["bath_wait"] = float(pet["bath_wait"]) + waiting_time
	if not pet["restless"] or elapsed < float(pet["escape_protected_until"]):
		return
	if float(pet["bath_wait"]) + TIME_EPSILON >= ESCAPE_WARNING_SECONDS and not pet["escape_warning"]:
		pet["escape_warning"] = true
		events.append({"type": "escape_warning", "pet_id": pet_id, "slot": pet["location"]})
	if float(pet["bath_wait"]) + TIME_EPSILON < ESCAPE_WAIT_SECONDS or _escape_cooldown_remaining > TIME_EPSILON:
		return
	for other: Dictionary in pets.values():
		if other["location"] == "loose":
			return
	var from_slot: String = pet["location"]
	slots[from_slot] = -1
	pet["location"] = "loose"
	pet["escape_warning"] = false
	_escape_cooldown_remaining = ESCAPE_COOLDOWN
	stats["escapes"] += 1
	events.append({"type": "escaped", "pet_id": pet_id, "from_slot": from_slot, "previous_carer": pet["last_carer"]})


func _finish_shift() -> void:
	if ended:
		return
	remaining = 0.0
	elapsed = SHIFT_SECONDS
	running = false
	ended = true
	for player_id: int in range(2):
		release_work(player_id)
	events.append({"type": "end", "score": score, "delivered": delivered, "missed": missed, "goal": goal, "goal_unit": "service_points", "stars": stars(), "won": has_won(), "shift_seed": shift_seed,
		"arrivals_total": arrivals_total, "refused": refused, "unfinished": pets.size(), "waiting": pending_orders.size()})


func _dry_pet(pet_id: int, delta: float) -> void:
	var pet: Dictionary = pets[pet_id]
	var boosted_seconds := 0.0
	var active_carers: Array[int] = []
	if _dryer_work_credit.has(pet_id):
		var credits: Dictionary = _dryer_work_credit[pet_id]
		for player_id: int in credits.keys():
			var used: float = minf(delta, float(credits[player_id]))
			if used > 0.0:
				active_carers.append(player_id)
				boosted_seconds = maxf(boosted_seconds, used)
			credits[player_id] = maxf(0.0, float(credits[player_id]) - delta)
	# One base interval plus 2x only for the actually registered active interval.
	pet["dry"] = minf(1.0, float(pet["dry"]) + (delta + (FAST_DRY_MULTIPLIER - 1.0) * boosted_seconds) / DRY_SECONDS)
	if float(pet["dry"]) >= 0.999999:
		pet["dry"] = 1.0
		pet["stage"] = "dry"
		pet["shake"] = 0.0
		pet["soothe_credit"] = 0.0
		events.append({"type": "dried", "pet_id": pet_id, "assisted": not active_carers.is_empty()})
		for player_id: int in active_carers:
			if not pet["frizzed_once"]:
				_work_holds[player_id][_hold_key(pet_id, "dryer")] = {"pet_id": pet_id, "slot": "dryer", "phase": "overdry", "danger": 0.0, "warned": false, "credit": 0.0}
			else:
				_work_holds[player_id].erase(_hold_key(pet_id, "dryer"))
		_dryer_work_credit.erase(pet_id)


func _soothe(pet: Dictionary, amount: float) -> void:
	# Work is called before tick each frame. Credit pauses only the time actually
	# spent caring; repeated players/calls cannot stack free warning resets.
	pet["soothe_credit"] = maxf(float(pet["soothe_credit"]), amount)


func _count_towels(state: String) -> int:
	var count := 0
	for towel: Dictionary in towels.values():
		if towel["state"] == state:
			count += 1
	return count


func _pickup_towel(player_id: int, towel_id: int, from_slot: String) -> void:
	if towel_slots.has(from_slot):
		towel_slots[from_slot] = -1
	var previous_carrier: int = int(towels[towel_id].get("last_carrier", -1))
	if previous_carrier != -1 and previous_carrier != player_id:
		stats["towel_handoffs"] += 1
	towels[towel_id]["last_carrier"] = player_id
	towels[towel_id]["location"] = "p%d" % player_id
	held_towels[player_id] = towel_id
	events.append({"type": "towel_pickup", "towel_id": towel_id, "player_id": player_id, "slot": from_slot})
	_decision(player_id, "pickup_towel", -1, from_slot)


func _detach_towel(pet: Dictionary, preferred_slot: String) -> void:
	var towel_id: int = int(pet["towel_id"])
	if towel_id == -1:
		return
	towels[towel_id]["state"] = "wet"
	var destination: String = "laundry"
	if towel_slots.has(preferred_slot) and towel_at(preferred_slot) == -1 and int(slots.get(preferred_slot, -1)) == -1:
		destination = preferred_slot
		towel_slots[destination] = towel_id
	towels[towel_id]["location"] = destination
	pet["towel_id"] = -1
	pet["towel_active"] = false
	pet["towel_progress"] = 0.0
	events.append({"type": "towel_placed", "towel_id": towel_id, "slot": destination, "pet_id": pet["id"], "reason": "left_after_pet"})
	if destination == "laundry":
		events.append({"type": "towel_recovered", "towel_id": towel_id, "slot": destination, "pet_id": pet["id"]})


func _decision(player_id: int, action: String, pet_id: int, slot: String) -> void:
	events.append({"type": "decision", "player_id": player_id, "action": action, "pet_id": pet_id, "slot": slot, "elapsed": elapsed})


func _is_dry_service(service: String) -> bool:
	return service in ["brush", "paws"]


func _free_intake(service: String) -> String:
	if pets.size() >= MAX_PETS:
		return ""
	if _is_dry_service(service):
		return "intake_dry" if slots["intake_dry"] == -1 else ""
	for index: int in range(3):
		var candidate := "intake%d" % index
		if slots[candidate] == -1:
			return candidate
	return ""


func _offer_order(service: String, offered_at: float) -> void:
	var pet_id: int = _next_id
	_next_id += 1
	arrivals_total += 1
	var patience: float = WAIT_SECONDS if _duo else SOLO_WAIT_SECONDS
	var dry_only: bool = _is_dry_service(service)
	var ticket: Dictionary = {
		"id": pet_id, "name": _pet_name(pet_id), "service": service,
		"stage": "dry" if dry_only else "dirty", "wash": 1.0 if dry_only else 0.0,
		"wash_phase": "done" if dry_only else ("treatment" if service == "deflea" else "soap"), "soap": 0.0, "soak_remaining": 0.0,
		"treatment_phase": "untreated" if service == "deflea" else "not_needed", "treatment_progress": 0.0, "treatment_remaining": 0.0,
		"rinse": 0.0, "bath_wait": 0.0, "restless": not dry_only and pet_id % 3 != 0,
		"escape_warning": false, "escape_protected_until": 0.0, "last_carer": -1,
		"dry": 1.0 if dry_only else 0.0, "needs_brush": service in ["brush", "full"],
		"needs_paws": service in ["paws", "full"], "paws": 0.0, "paws_done": false,
		"brushed": false, "brush": 0.0, "frizzy": false, "crooked": false,
		"frizzed_once": false, "crooked_once": false, "repair_progress": 0.0,
		"towel_id": -1, "towel_active": false,
		"towel_progress": 0.0, "soothe_credit": 0.0, "patience": patience,
		"max_patience": patience, "shake": 0.0, "location": "waiting", "last_carrier": -1,
		"offered_at": offered_at, "admitted_at": -1.0,
	}
	events.append({"type": "order_offered", "pet_id": pet_id, "name": ticket["name"], "service": service, "elapsed": offered_at})
	var free_slot: String = _free_intake(service)
	var older_same_room := false
	for waiting: Dictionary in pending_orders:
		if _is_dry_service(waiting["service"]) == dry_only:
			older_same_room = true
			break
	if not free_slot.is_empty() and not older_same_room:
		_admit_order(ticket, free_slot)
	elif pending_orders.size() < MAX_PENDING:
		pending_orders.append(ticket)
		events.append({"type": "order_waiting", "pet_id": pet_id, "name": ticket["name"], "service": service, "wait_seconds": patience})
	else:
		_record_missed(ticket, "queue_full", true)


func _pet_name(pet_id: int) -> String:
	var index: int = pet_id - 1
	var base: String = PET_NAMES[index % PET_NAMES.size()]
	var cycle: int = int(index / PET_NAMES.size()) + 1
	return base if cycle == 1 else "%s%d" % [base, cycle]


func _admit_order(ticket: Dictionary, free_slot: String) -> void:
	var pet_id: int = int(ticket["id"])
	var patience: float = 80.0 if _duo else 110.0
	ticket["patience"] = patience
	ticket["max_patience"] = patience
	ticket["location"] = free_slot
	ticket["admitted_at"] = elapsed
	pets[pet_id] = ticket
	slots[free_slot] = pet_id
	stats["arrivals_admitted"] += 1
	events.append({"type": "arrival", "pet_id": pet_id, "name": ticket["name"], "service": ticket["service"], "waited_seconds": maxf(0.0, elapsed - float(ticket["offered_at"]))})


func _admit_pending() -> void:
	# FIFO within each room. A blocked dry entrance must not stall a free wet
	# entrance (or vice versa), while the shared six-pet capacity remains strict.
	var index := 0
	var blocked_rooms: Dictionary = {}
	while index < pending_orders.size() and pets.size() < MAX_PETS:
		var ticket: Dictionary = pending_orders[index]
		var room: String = "dry" if _is_dry_service(ticket["service"]) else "wet"
		var free_slot: String = "" if blocked_rooms.has(room) else _free_intake(ticket["service"])
		if free_slot.is_empty():
			blocked_rooms[room] = true
			index += 1
			continue
		pending_orders.remove_at(index)
		_admit_order(ticket, free_slot)


func _record_missed(ticket: Dictionary, reason: String, was_waiting: bool) -> void:
	missed += 1
	stats["missed_by_service"][ticket["service"]] += 1
	if reason == "queue_full":
		refused += 1
		stats["refused"] += 1
	elif reason == "waiting_timeout":
		stats["waiting_expired"] += 1
	score = maxi(0, score - (WAIT_MISSED_PENALTY if was_waiting else MISSED_PENALTY))
	events.append({"type": "missed", "pet_id": ticket["id"], "name": ticket["name"], "service": ticket["service"], "reason": reason, "waiting": was_waiting})


func _remove_pet(pet_id: int) -> void:
	_forget_pet_work(pet_id, true)
	var previous_slot: String = pets[pet_id]["location"]
	for slot: String in slots.keys():
		if slots[slot] == pet_id:
			slots[slot] = -1
	_detach_towel(pets[pet_id], previous_slot)
	for player_id: int in range(carried.size()):
		if carried[player_id] == pet_id:
			carried[player_id] = -1
	pets.erase(pet_id)


func _valid_player(player_id: int) -> bool:
	# Solo controls switch between both avatars; mode only changes shift tuning.
	return player_id >= 0 and player_id < 2
