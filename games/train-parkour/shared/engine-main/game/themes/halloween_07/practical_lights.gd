extends Node3D
## Fixed light pool with persistent assignments and smooth runtime fade; frozen camera captures explicitly snap selection.
const BUDGET:=22
const SHADOW_BUDGET:=3
var candidates: Array=[]
var pool: Array[OmniLight3D]=[]
var slots: Array=[]
var targets: Array=[]
var camera: Camera3D
var elapsed:=0.0
func configure(rows: Array,view: Camera3D) -> void:
	candidates=rows;camera=view
	for i in BUDGET:
		var light:=OmniLight3D.new();light.name="WarmPool_"+str(i);light.light_color=Color("ff8838");light.omni_attenuation=1.4;light.shadow_enabled=i<2;light.shadow_bias=0.06;light.light_energy=0.0;light.light_volumetric_fog_energy=0.0;add_child(light);pool.append(light);slots.append(-1);targets.append(0.0)
	sync_view(view)
func sync_view(view: Camera3D,immediate:=true) -> void:
	camera=view
	var ranked: Array=[]
	var city_ranked: Array=[]
	for i in candidates.size():
		var row: Dictionary=candidates[i]
		var city: bool=row.get("role","")=="lower_city"
		var distance:=camera.global_position.distance_squared_to(row.p)
		var selection_distance:=240.0 if city else 145.0
		if distance>selection_distance*selection_distance:continue
		var focus: Vector3=row.get("focus",row.p)
		var score:=distance*(0.55 if camera.is_position_in_frustum(focus) else 1.45)
		if city:city_ranked.append({"index":i,"score":score})
		else:ranked.append({"index":i,"score":score})
	ranked.sort_custom(func(a,b):return a.score<b.score)
	city_ranked.sort_custom(func(a,b):return a.score<b.score)
	var selected: Array=[];var shadow_candidates: Array=[]
	# Reserve lower-city pools; shadow ownership is resolved from actual fixtures below.
	for i in mini(SHADOW_BUDGET,ranked.size()):selected.append(ranked[i].index)
	var city_selected: Array=[]
	for entry: Dictionary in city_ranked:
		var index: int=entry.index
		var separated:=true
		for previous: int in city_selected:
			if candidates[previous].p.distance_to(candidates[index].p)<45.0:separated=false;break
		if separated:city_selected.append(index)
		if city_selected.size()==4:break
	selected.append_array(city_selected)
	for i in range(mini(SHADOW_BUDGET,ranked.size()),mini(ranked.size(),BUDGET-city_selected.size())):selected.append(ranked[i].index)

	# Only a visible lantern casts a practical shadow. Wall-fill sockets are not fixtures.
	for entry: Dictionary in ranked:
		var index: int=entry.index
		if index in selected and candidates[index].get("role","")=="lantern" and shadow_candidates.size()<SHADOW_BUDGET:shadow_candidates.append(index)

	if immediate:
		for i in BUDGET:
			slots[i]=-1;targets[i]=0.0;pool[i].light_energy=0;pool[i].visible=false
	for i in BUDGET:
		if not slots[i] in selected:targets[i]=0.0;pool[i].shadow_enabled=false
		if targets[i]==0.0 and pool[i].light_energy<0.12:slots[i]=-1;pool[i].visible=false
	for index: int in selected:
		var slot: int=slots.find(index)
		if slot<0:slot=slots.find(-1)
		if slot<0:continue
		var row: Dictionary=candidates[index];var light:=pool[slot]
		var city: bool=row.get("role","")=="lower_city"
		var energy: float=row.energy*(1.0 if city else .90)
		# Reset every recycled slot: a previous violet city light must never tint a lantern.
		light.light_color=row.get("color",Color("ff8838"));light.omni_attenuation=float(row.get("attenuation",1.4));light.light_specular=float(row.get("specular",1.0))
		slots[slot]=index;targets[slot]=energy;light.global_position=row.p;light.omni_range=row.range*(1.0 if city else .90);light.visible=true;light.shadow_enabled=index in shadow_candidates
		if immediate:light.light_energy=energy
	var active:=0;var shadowed:=0
	for light in pool:
		if light.visible:active+=1;shadowed+=int(light.shadow_enabled)
	set_meta("view_light_budget",{"candidate_count":candidates.size(),"active":active+2,"maximum":24,"pool_active":active,"pool_maximum":BUDGET,"fixed_train_headlights_budget":2,"shadowed":shadowed,"selected_candidates":selected,"lower_city_slots":city_selected.size(),"lower_city_color":"pink_violet_uplight","runtime_fade_seconds_approx":0.5})
func _process(delta: float) -> void:
	for i in BUDGET:pool[i].light_energy=lerpf(pool[i].light_energy,targets[i],minf(1,delta*8.0))
	elapsed+=delta
	if elapsed>0.12 and is_instance_valid(camera):elapsed=0.0;sync_view(camera,false)
