extends Node
## Guards for every torii gate and every hokora shrine (playtest note 5, backlog P5).
## - One guard post at a time: the nearest gate or shrine within 40 m has 2–3 guards on the 6–12 m ring
## - A guard stands clear of the footpath network (3 m) and outside the player's view cone
## - The ring has room for 2–3 guards at each footpath site along a walk
## - recall_stragglers leaves a guard at its post, however far the player has walked
## - An anchor that streams away takes its guards with it
## - Over a 120 s walk the live yokai, guards included, never exceed the planner cap
## godot --headless --path . --fixed-fps 90 res://tests/anchor_guards_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_anchor_guards_high_score.cfg"
const EPS := 0.01

var failures := 0
var run: RunGame


func _ready() -> void:
	await _run_all()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = TEST_SAVE_PATH
	add_child(run)
	await _frames(30)

	var ag := run.anchor_guards
	_check("AnchorGuards is attached to the run", ag != null)
	if ag == null:
		run.queue_free()
		return
	_check("The wave director runs, so guards are planned", run.wave_director.active)

	await _test_one_guard_post_at_a_time()
	await _test_walk_sites_have_room()
	await _test_guards_keep_their_post()
	await _test_guards_leave_with_their_gate()
	await _test_budget_over_a_120_second_walk()

	run.queue_free()


## Live yōkai over a 120 s walk (one 3 m step a second, 360 m). The planner's cap bounds the
## wave yōkai; guards add at most one group on top of it.
func _test_budget_over_a_120_second_walk() -> void:
	var wd := run.wave_director
	var player := run.player as DesktopPlayer
	var max_total := 0
	var max_wave := 0
	var max_guards := 0
	var max_cap := 0
	var total_over_budget := 0 # frames with more live yokai than the cap
	for i in range(1, 121):
		var x := 3.0 * float(i)
		player.teleport(Vector3(x, run.forest_world.height_at(x, 0.0), 0.0), 0.0)
		for _f in 90:
			await get_tree().physics_frame
			var total := wd.alive_enemies().size()
			var guards := _guard_count()
			var wave := total - guards
			var cap := wd.concurrent_cap()
			max_total = maxi(max_total, total)
			max_wave = maxi(max_wave, wave)
			max_guards = maxi(max_guards, guards)
			max_cap = maxi(max_cap, cap)
			if total > cap:
				total_over_budget += 1
	print("BUDGET 120 s walk: max live yokai %d, max wave yokai %d (cap up to %d), max guards %d, anchors %d"
		% [max_total, max_wave, max_cap, max_guards, run.forest_world.torii_manager.get_active_gates().size() + run.hokora_manager.alive_shrines().size()])
	_check("Live yokai, guards included, never exceed the planner cap (%d frames over)" % total_over_budget,
		total_over_budget == 0)


func _guard_count() -> int:
	var n := 0
	for e in run.wave_director.alive_enemies():
		if e.guard_post != 0:
			n += 1
	return n


func _test_one_guard_post_at_a_time() -> void:
	var ag := run.anchor_guards
	var tm := run.forest_world.torii_manager
	var anchors: Array[Node3D] = []
	for g in tm.get_active_gates():
		anchors.append(g)
	for s in run.hokora_manager.alive_shrines():
		anchors.append(s)
	_check("The run has gates and shrines to guard (%d anchors)" % anchors.size(), anchors.size() >= 2)

	# One post at a time (the budget): exactly one anchor carries a group, with 2–3 guards,
	# and it is within GUARD_RANGE of the player. The other anchors wait for it to go.
	var paths := run.forest_world.paths
	var player := run._player_center()
	var posted: Array[Node3D] = []
	var live := 0
	var bad_ring := 0
	var bad_path := 0
	for anchor in anchors:
		var n := ag.guards_of(anchor).size()
		if n > 0:
			posted.append(anchor)
			live += n
		var ap := Vector2(anchor.global_position.x, anchor.global_position.z)
		for spot in ag.spots_of(anchor):
			var sp := Vector2(spot.x, spot.z)
			var d := sp.distance_to(ap)
			if d < 6.0 - EPS or d > 12.0 + EPS:
				bad_ring += 1
			if paths != null and paths.nearest_point(sp, ag.PATH_CLEARANCE) != Vector2.INF:
				bad_path += 1
	_check("Exactly one guard post is live (%d posts, %d anchors in the run)" % [posted.size(), anchors.size()],
		posted.size() == 1)
	_check("The live post has 2–3 guards (%d live)" % live, live >= 2 and live <= 3)
	if posted.size() == 1:
		var d := Vector2(posted[0].global_position.x - player.x, posted[0].global_position.z - player.z).length()
		_check("The post is within %d m of the player (%.1f m)" % [AnchorGuards.GUARD_RANGE, d],
			d <= AnchorGuards.GUARD_RANGE)
	_check("Guards stand on the 6–12 m ring round their anchor (%d off the ring)" % bad_ring, bad_ring == 0)
	_check("Guards stand clear of the footpath network (%d within 3 m)" % bad_path, bad_path == 0)


func _test_walk_sites_have_room() -> void:
	var ag := run.anchor_guards
	var paths := run.forest_world.paths
	var c := Vector2(run._player_center().x, run._player_center().z)
	var sites: Array[Vector4] = []
	if paths != null:
		for s in paths.samples_in_rect(Rect2(c - Vector2(60.0, 60.0), Vector2(120.0, 120.0)), 1.0):
			var d := Vector2(s.x, s.y).distance_to(c)
			if d >= 20.0 and d <= 40.0:
				sites.append(s)
	# Twenty sites spread along the footpaths, not twenty neighbours of one spot.
	var picked: Array[Vector4] = []
	var stride: int = maxi(1, sites.size() / 20)
	var i := 0
	while i < sites.size() and picked.size() < 20:
		picked.append(sites[i])
		i += stride
	_check("The walk has footpath sites to test (%d found)" % sites.size(), picked.size() >= 10)

	var short := 0
	var worst := 3
	var far := 0
	for s in picked:
		var anchor := Vector3(s.x, 0.0, s.y)
		var spots := ag.plan_spots(anchor, 3, run._player_center(), Vector3.ZERO)
		worst = mini(worst, spots.size())
		if spots.size() < 2:
			short += 1
		for spot in spots:
			var d := Vector2(spot.x - s.x, spot.z - s.y).length()
			if d < 6.0 - EPS or d > 12.0 + EPS:
				far += 1
	_check("Every walk site fits 2 guards or more (%d short, fewest %d)" % [short, worst], short == 0)
	_check("Guard spots for walk sites land on the 6–12 m ring (%d off)" % far, far == 0)


func _test_guards_keep_their_post() -> void:
	var ag := run.anchor_guards
	var wd := run.wave_director
	var player := run._player_center()
	var stray: Yokai = null
	for e in wd.alive_enemies():
		if e.guard_post == 0:
			continue
		var rp := e.root_part().global_position
		if Vector2(rp.x - player.x, rp.z - player.z).length() > wd.get_profile().straggler_distance:
			stray = e
			break
	_check("A guard stands beyond the straggler distance (so the rule matters)", stray != null)
	if stray == null:
		return
	var before := stray.root_part().global_position
	wd.recall_stragglers(player)
	var after := stray.root_part().global_position
	_check("recall_stragglers leaves a guard at its post (moved %.3f m)" % before.distance_to(after),
		before.distance_to(after) < EPS)
	await _frames(1)


func _test_guards_leave_with_their_gate() -> void:
	var ag := run.anchor_guards
	var anchor: Node3D = null
	for a in _anchors_now():
		if not ag.guards_of(a).is_empty():
			anchor = a
			break
	_check("A guarded gate or shrine is up before it streams away", anchor != null)
	if anchor == null:
		return
	var id := anchor.get_instance_id()
	var before := _guards_with_post(id)
	anchor.queue_free()
	await _frames(40)
	var after := _guards_with_post(id)
	_check("An anchor that streams away takes its %d guards with it (%d left)" % [before, after],
		before >= 2 and after == 0)


func _anchors_now() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for g in run.forest_world.torii_manager.get_active_gates():
		out.append(g)
	for s in run.hokora_manager.alive_shrines():
		out.append(s)
	return out


func _guards_with_post(post_id: int) -> int:
	var n := 0
	for e in run.wave_director.alive_enemies():
		if e.guard_post == post_id:
			n += 1
	return n


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
