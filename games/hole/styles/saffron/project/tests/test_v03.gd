extends SceneTree
## Real Godot regression suite. Its existence is NOT evidence it has been executed.
const Simulation = preload("res://scripts/simulation.gd")
const Tuning = preload("res://scripts/tuning.gd")
const Boundary = preload("res://scripts/land_boundary.gd")
var definition: Dictionary = {}
var checks: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	print(("PASS " if ok else "FAIL ")+label)

func fresh(rival: bool = false):
	var s = Simulation.new()
	if not s.initialize(definition,Tuning.new()):
		push_error(s.error_message)
		quit(1)
	if rival:
		s.reset(true)
	return s

func steps(s, seconds: float) -> void:
	for _i in range(int(ceil(seconds*60.0))):
		s.tick(1.0/60.0,Vector2.ZERO)

func first(s, archetype: String) -> Dictionary:
	for o in s.objects:
		if s.gameplay_family(o)==archetype:
			return o
	return {}

func _run() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/graybox_config.json"))
	if not parsed is Dictionary:
		push_error("Configuration did not parse")
		quit(1)
		return
	definition=parsed
	var migrated = Tuning.new()
	migrated.apply_values(Tuning.migrate_saved_values({"round_seconds":60.0,"camera_scale":1.2}))
	check(migrated.round_seconds==60.0 and is_equal_approx(migrated.camera_scale,1.2),"legacy 60 second default stays unchanged")
	migrated.apply_values(Tuning.migrate_saved_values({"_defaults_version":2,"round_seconds":60.0}))
	check(migrated.round_seconds==60.0,"new explicit short-round setting is preserved")
	var s = fresh()
	check(s.objects.size()==215 and s.by_id.size()==215,"215 unique runtime food IDs")
	check(s.count_state(Simulation.LOCKED)==42,"42 existing payloads initially locked")
	steps(s,1.0)
	check(s.stage==Simulation.READY and s.elapsed==0.0,"first movement starts timer, not scene load")
	s.tick(1.0/60.0,Vector2.UP)
	check(s.stage==Simulation.PLAYING,"movement starts round")
	s.reset()
	check(s.total_reward==0 and s.elapsed==0.0,"restart clears time and ledger")
	_test_growth_and_shapes()
	_test_water()
	_test_supports_and_ledger()
	_test_timeout()
	_test_full_clear()
	_test_routes()
	var failures: int = 0
	for result in checks:
		if not result["passed"]:
			failures+=1
	var file: FileAccess = FileAccess.open("user://engine_v03_logic.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"source":"godot_runtime","version":"0.3","engine":Engine.get_version_info(),"checks":checks,"failures":failures},"\t"))
	print("v0.3: %d checks, %d failures"%[checks.size(),failures])
	quit(0 if failures==0 else 1)

func _test_growth_and_shapes() -> void:
	var s = fresh()
	check(s.can_fit(first(s,"tall_pole")),"height is not the planar swallow gate")
	check(not s.is_collectible(first(s,"supported_ball")),"tiny elevated food is not remotely accessible")
	s.holes[0]["growth"]=1
	check(s.desired_diameter(0)>0.9 and s.desired_diameter(0)<1.45,"one point changes target diameter before tier threshold")
	var narrow: Dictionary=first(s,"building_segment")
	var wide: Dictionary=first(s,"wide_building")
	s.holes[0].diameter=(s.fit_span(narrow)+s.fit_span(wide))/(2.0*s.tuning.fit_margin)
	check(s.fit_span(narrow)<s.fit_span(wide) and s.can_fit(narrow) and not s.can_fit(wide),"tall narrow building is earlier than low wide building")
	s.force_size(-1)
	s.holes[0]["growth"]=1134
	check(is_equal_approx(s.desired_diameter(0),6.8),"growth cap remains 6.8 while all 1134 points count")

func _test_water() -> void:
	var s = fresh(true)
	check(not s.land.valid(Vector2(-16,13),.45),"inlet is non-walkable")
	for owner in range(2):
		s.teleport(Vector3(-16,0,13),owner)
		var p: Vector3 = s.holes[owner]["position"]
		check(s.land.valid(Vector2(p.x,p.z),.45),"owner %d water teleport is corrected"%owner)
	for radius in [.45,1.05,3.4,5.1]:
		var start: Vector2 = s.land.project_inside(Vector2(-17,7.5),float(radius))
		var result: Dictionary = s.land.move_and_slide_disk(start,Vector2(8,17),float(radius))
		var safe: bool = s.land.valid(result["position"],float(radius))
		var path: PackedVector2Array = result["path"]
		for i in range(1,path.size()):
			safe=safe and s.land.segment_valid(path[i-1],path[i],float(radius))
		check(safe,"high-speed bank sweep radius %.2f"%float(radius))
		var navigation: PackedVector2Array = s.land.navigation_path(Vector2(-17,5),Vector2(-4,14),float(radius))
		var nav_safe: bool = not navigation.is_empty()
		for i in range(1,navigation.size()):
			nav_safe=nav_safe and s.land.segment_valid(navigation[i-1],navigation[i],float(radius))
		check(nav_safe,"radius-aware route avoids concave shore %.2f"%float(radius))
	s.force_size(5)
	s.teleport(Vector3(-16,0,7.8))
	var p: Vector3 = s.holes[0]["position"]
	check(s.land.valid(Vector2(p.x,p.z),3.1),"growth/lab size corrects full disk, not centre alone")

func _test_supports_and_ledger() -> void:
	var s = fresh()
	s.force_size(2)
	var table: Dictionary = first(s,"support_table")
	var locked: Array = []
	for o in s.objects:
		if o["root_support"]==table["id"]:
			locked.append(o)
	check(locked.size()==6,"one table owns six independent payload IDs")
	s.teleport(table["position"])
	s.begin()
	s._capture(table,0)
	s._update_captured(.12)
	var released: bool = true
	for o in locked:
		released=released and int(o["state"])==Simulation.FALLING
	check(released and s.objects.size()==215,"release updates existing IDs without spawning duplicates")
	check(not s.is_collectible(locked[0]),"released high payload must first fall into capture band")
	steps(s,1.4)
	check(int(table["state"])==Simulation.CONSUMED,"support itself completes independently")
	var before: int = s.total_reward
	s._consume(table)
	check(s.total_reward==before,"duplicate callback cannot double award support")
	s=fresh()
	s.force_size(3)
	s.begin()
	var block: Dictionary = first(s,"building_segment")
	s._capture(block,0)
	s._update_captured(1.2)
	check(s.total_reward==16 and s.consumed_count==1,"one facade unit awards 16, no row-root reward")
	s=fresh(true)
	s.begin()
	var item: Dictionary = first(s,"micro_block")
	s._capture(item,0)
	s._capture(item,1)
	s._update_captured(1.2)
	check(int(item["owner"])==0 and s.total_reward==1,"two owners cannot claim one ID")

func _test_timeout() -> void:
	var s = fresh()
	s.begin()
	s.elapsed=60.0
	s.tick(1.0/60.0,Vector2.ZERO)
	check(s.stage==Simulation.FINISHED and s.tuning.round_seconds==60.0,"default round ends at 60 seconds")
	s = fresh()
	s.force_size(2)
	var table: Dictionary = first(s,"support_table")
	s.begin()
	s._capture(table,0)
	s.elapsed=s.tuning.round_seconds
	s.tick(1.0/60.0,Vector2.ZERO)
	steps(s,1.2)
	check(s.stage==Simulation.FINISHED and s.total_reward==7,"pre-timeout capture drains once")
	check(s.count_state(Simulation.LOCKED)==42,"draining cannot open a late payload release chain")

func _test_full_clear() -> void:
	var s = fresh()
	# The G5 milestone is 6.2m; the actual earned cap is 6.8m.
	# Use the full-growth bound for this assisted reachability/ledger test.
	s.holes[0].growth=1134
	s.holes[0].diameter=s.desired_diameter()
	s.assisted_run=true
	s.lab_unlimited=true
	s.begin()
	for _iteration in range(450):
		if s.consumed_count==215:
			break
		for o in s.objects:
			if s.is_collectible(o):
				s.teleport(o["position"])
				break
		steps(s,1.3)
	check(s.consumed_count==215 and s.total_reward==1134,"assisted exhaustive clear: 215 IDs / 1134, shoreline food reachable")
	var ids: Dictionary = {}
	for event in s.events:
		if event["event"]=="CONSUME":
			ids[event["id"]]=true
	check(ids.size()==215,"all payouts correspond to original unique IDs")

func _test_routes() -> void:
	for route in [1,2]:
		var s = fresh()
		s.route_mode=route
		s.assisted_run=true
		var dry: bool = true
		for _i in range(4200):
			s.tick(1.0/60.0,Vector2.ZERO)
			var h: Dictionary = s.holes[0]
			var p: Vector3 = h["position"]
			dry=dry and s.land.valid(Vector2(p.x,p.z),float(h["diameter"])*.5)
			if s.stage==Simulation.FINISHED:
				break
		check(dry and s.stage==Simulation.FINISHED,"AI route %d stays dry and reaches settlement"%route)
		var file: FileAccess = FileAccess.open("user://route_%d_v03_engine.json"%route,FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify(s.report(),"\t"))
