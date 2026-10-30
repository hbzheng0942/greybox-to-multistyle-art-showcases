class_name ShiftDirector
extends RefCounted
## Small, reproducible demand grammar. Validation is a necessary filter, not a
## proof of complete scheduling, human difficulty, or fun.

const RULE_VERSION := "salon-v7-1"
const DEFAULT_SEED := 20261018
const SERVICES := ["bath", "brush", "paws", "deflea", "full"]
const DRY_SERVICES := ["brush", "paws"]
const SHIFT_SECONDS := 150.0
const MIN_PROCESS_SECONDS := {
	"bath": 10.6, "brush": 3.0, "paws": 2.4, "deflea": 10.2, "full": 16.0,
}
# Active work and passive occupancy are separate budgets. Travel is supplied
# by a layout audit, never inferred from an empty straight-line room.
const RESOURCE_SECONDS := {
	"bath": {"wet_hands": 3.6, "bath": 8.6, "dry_hands": 2.0},
	"brush": {"dry_hands": 3.0, "brush": 3.0},
	"paws": {"dry_hands": 2.4, "paws": 2.4},
	"deflea": {"wet_hands": 2.2, "treatment": 6.8, "bath": 1.4, "dry_hands": 2.0},
	"full": {"wet_hands": 3.6, "bath": 8.6, "dry_hands": 7.4, "brush": 3.0, "paws": 2.4},
}


static func build(duo: bool = true, seed_value: int = DEFAULT_SEED) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array = []
	if not duo:
		var solo := ["paws", "full", "bath", "brush", "deflea", "full", "bath", "paws"]
		# Keep an early local dry task; vary paired work without changing demand.
		for offset: int in [1, 3, 5]:
			if rng.randi_range(0, 1) == 1:
				var temporary: String = solo[offset]
				solo[offset] = solo[offset + 1]
				solo[offset + 1] = temporary
		var times := [14.0, 28.0, 42.0, 56.0, 70.0, 84.0, 98.0, 110.0]
		for index: int in range(solo.size()):
			result.append([times[index], solo[index]])
		return result
	var waves := [
		{"start": 8.0, "end": 36.0, "services": ["full", "bath", "brush", "paws", "deflea"]},
		{"start": 50.0, "end": 78.0, "services": ["full", "bath", "brush", "paws", "deflea"]},
		{"start": 91.0, "end": 110.0, "services": ["full", "bath", "brush", "deflea"]},
	]
	for wave: Dictionary in waves:
		var options: Array = wave.services.duplicate()
		_shuffle(options, rng)
		# Every wave starts with a local dry task. This prevents an upstream
		# processing stall from withholding every new task from the dry player.
		for index: int in range(options.size()):
			if options[index] in DRY_SERVICES:
				var first: String = options[0]
				options[0] = options[index]
				options[index] = first
				break
		# Follow local work with two wet services. Their arrivals are 5-9 seconds
		# apart: a passive dryer can still be occupied when the next handoff lands.
		# The second window/towel route is a useful parallel option, not a script.
		for position: int in [1, 2]:
			if options[position] in DRY_SERVICES:
				for candidate: int in range(position + 1, options.size()):
					if not options[candidate] in DRY_SERVICES:
						var swap: String = options[position]
						options[position] = options[candidate]
						options[candidate] = swap
						break
		for index: int in range(options.size()):
			var time := lerpf(float(wave.start), float(wave.end), float(index) / float(options.size() - 1))
			if index > 0 and index < options.size() - 1:
				time += rng.randf_range(-1.0, 1.0)
			result.append([snappedf(time, 0.1), options[index]])
	return result


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[other]
		values[other] = temporary


static func validate(schedule: Array, duo: bool = true, space_budget: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var counts := {"bath": 1, "brush": 1, "paws": 0, "deflea": 1, "full": 0}
	var previous := 0.0
	var travel: Dictionary = space_budget.get("route_travel_seconds", {})
	var station_counts: Dictionary = space_budget.get("station_counts", {})
	var resources := {"wet_hands": 0.0, "dry_hands": 0.0, "bath": 0.0, "treatment": 0.0, "brush": 0.0, "paws": 0.0}
	var minimum_gap := 4.0 if duo else 10.0
	if schedule.size() != (14 if duo else 8):
		errors.append("wrong_order_count")
	for order: Variant in schedule:
		if not order is Array or order.size() != 2 or not (order[0] is float or order[0] is int) or not order[1] is String:
			errors.append("invalid_order_shape")
			continue
		var time := float(order[0])
		var service := String(order[1])
		if not is_finite(time) or time < 0.0 or time > 110.0:
			errors.append("arrival_outside_shift_window")
		if time - previous < minimum_gap:
			errors.append("arrivals_too_close")
		previous = time
		if not service in SERVICES:
			errors.append("unknown_service")
			continue
		counts[service] += 1
		var route_time := float(travel.get(service, 0.0))
		if not travel.is_empty() and (not travel.has(service) or not is_finite(route_time) or route_time < 0.0):
			errors.append("invalid_or_missing_route_budget:" + service)
		var duration := float(MIN_PROCESS_SECONDS[service]) + route_time
		if duration < 0.0 or not is_finite(duration) or time + duration > SHIFT_SECONDS:
			errors.append("late_order_cannot_finish_necessary_chain")
		for resource: String in RESOURCE_SECONDS[service]:
			resources[resource] += float(RESOURCE_SECONDS[service][resource])
	# Opening work also consumes capacity, though initial bath is already soaked.
	resources.wet_hands += 3.6
	resources.dry_hands += 7.0
	resources.bath += 5.8
	resources.treatment += 6.8
	resources.brush += 3.0
	var expected := {"bath": 4, "brush": 4, "paws": 2, "deflea": 4, "full": 3} if duo else {"bath": 3, "brush": 2, "paws": 2, "deflea": 2, "full": 2}
	if counts != expected:
		errors.append("service_mix_outside_profile")
	if not schedule.is_empty() and schedule[0] is Array and schedule[0].size() == 2 and not schedule[0][1] in DRY_SERVICES:
		errors.append("first_arrival_must_offer_local_dry_work")
	if duo and schedule.size() == 14:
		for pair: Array in [[0, 8.0, 36.0, 5], [5, 50.0, 78.0, 5], [10, 91.0, 110.0, 4]]:
			var wave_valid := true
			var first: Variant = schedule[int(pair[0])]
			if not first is Array or first.size() != 2 or not first[1] in DRY_SERVICES:
				errors.append("wave_must_open_with_local_dry_work")
			for index: int in range(int(pair[0]), int(pair[0]) + int(pair[3])):
				if not schedule[index] is Array or schedule[index].size() != 2 or not (schedule[index][0] is float or schedule[index][0] is int):
					wave_valid = false
					continue
				wave_valid = wave_valid and float(schedule[index][0]) >= float(pair[1]) and float(schedule[index][0]) <= float(pair[2])
			if not wave_valid:
				errors.append("pressure_wave_outside_window")
	if not station_counts.is_empty():
		for station: String in ["bath", "treatment", "brush", "paws"]:
			var capacity := int(station_counts.get(station, 0))
			if capacity <= 0 or float(resources[station]) > SHIFT_SECONDS * capacity:
				errors.append("missing_or_insufficient_station:" + station)
		# Six generic pet-only spaces ensure a carried pet has somewhere to park
		# under the six-pet active cap. Reachability remains a separate spatial test.
		if int(station_counts.get("generic_parking", 0)) < int(space_budget.get("max_active_pets", 6)):
			errors.append("insufficient_reversible_parking")
		if int(station_counts.get("windows", 0)) < 2:
			errors.append("missing_two_way_handoff_capacity")
	if space_budget.get("all_operation_faces_reachable", true) == false:
		errors.append("unreachable_operation_face")
	var recovery := recovery_screen(schedule, duo, space_budget.get("cosmetic_recovery", {}))
	for error: String in recovery.errors:
		errors.append(error)
	var burst := burst_screen(schedule, space_budget)
	for error: String in burst.errors:
		errors.append(error)
	return {"passed": errors.is_empty(), "errors": errors, "rule_version": RULE_VERSION,
		"service_counts": counts, "resource_seconds_lower_bound": resources,
		"machine_dryer_seconds_if_no_towels": 12.0 * (int(counts.bath) + int(counts.deflea) + int(counts.full)),
		"spatial_budget_supplied": not travel.is_empty() and not station_counts.is_empty(),
		"cosmetic_recovery_screen": recovery, "burst_screen": burst,
		"scope": "Demand grammar and necessary capacity/deadline/parking filters; does not prove joint scheduling, recovery timing or fun."}


static func burst_screen(schedule: Array, space_budget: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var windows: Array = []
	var travel: Dictionary = space_budget.get("route_travel_seconds", {})
	if travel.is_empty():
		return {"supplied": false, "errors": errors, "windows": windows}
	# A design guardrail: a 20-second arrival burst may commit at most 40 seconds
	# of lower-bound work to either player. Backlog is intentional; this is not
	# an impossibility proof. Travel is conservatively charged to both actors.
	for first: Variant in schedule:
		if not first is Array or first.size() != 2 or not (first[0] is float or first[0] is int):
			continue
		var wet := 0.0
		var dry := 0.0
		for order: Variant in schedule:
			if not order is Array or order.size() != 2 or not (order[0] is float or order[0] is int) or not order[1] in SERVICES:
				continue
			if float(order[0]) < float(first[0]) or float(order[0]) >= float(first[0]) + 20.0:
				continue
			var service: String = order[1]
			var route := float(travel.get(service, INF))
			if not service in DRY_SERVICES:
				wet += float(RESOURCE_SECONDS[service].get("wet_hands", 0)) + route + 1.2
			dry += float(RESOURCE_SECONDS[service].dry_hands) + route + 1.2
		windows.append({"from": first[0], "to": float(first[0]) + 20.0, "wet_committed_seconds": wet, "dry_committed_seconds": dry})
		if maxf(wet, dry) > 40.0 and not errors.has("burst_exceeds_local_work_budget"):
			errors.append("burst_exceeds_local_work_budget")
	return {"supplied": true, "errors": errors, "windows": windows, "window_seconds": 20.0, "committed_seconds_limit": 40.0,
		"scope": "Tuning filter using spatial travel plus active service and 1.2s assumed handling per order. Double-charges full route travel to each required actor. Does not include carry-in backlog, towel restock, congestion or reactions; not a feasibility proof."}


static func recovery_screen(schedule: Array, duo: bool, recovery: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var windows: Array = []
	if recovery.is_empty():
		return {"supplied": false, "errors": errors, "windows": windows}
	var allowance := float(recovery.get("park_then_repair_allowance_seconds", INF))
	if not recovery.get("reachable", false) or not is_finite(allowance) or allowance <= 0.0:
		errors.append("invalid_cosmetic_recovery_route")
	if duo and schedule.size() == 14:
		for pair: Array in [[4, 5], [9, 10]]:
			var before: Variant = schedule[pair[0]]
			var after: Variant = schedule[pair[1]]
			if not before is Array or not after is Array or before.size() != 2 or after.size() != 2:
				continue
			if not (before[0] is float or before[0] is int) or not (after[0] is float or after[0] is int):
				continue
			var gap := float(after[0]) - float(before[0])
			windows.append({"from": before[0], "to": after[0], "seconds": gap, "spare_after_one_local_repair": gap - allowance})
			if gap < allowance:
				errors.append("recovery_gap_shorter_than_local_park_and_repair")
	return {"supplied": true, "errors": errors, "windows": windows,
		"park_and_repair_allowance_seconds": allowance,
		"scope": "One local cosmetic repair fits inside an arrival gap only if the brush/buffer are free. Does not subtract existing backlog or prove a whole-wave recovery schedule. Solo demand has no dedicated wave gaps."}
