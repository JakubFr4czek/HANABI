extends Node
## Guards for every torii gate and every hokora shrine (playtest note 5, backlog P5).
## - Every live gate and shrine stands with 2–3 guards, each on the ring 6–12 m from it
## - A guard stands clear of the footpath network (3 m) and outside the player's view cone
## - The ring has room for 2–3 guards at each footpath site along a walk
## - recall_stragglers leaves a guard at its post, however far the player has walked
## - A gate that streams away takes its guards with it
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

	await _test_every_anchor_has_two_or_three_guards()
	await _test_walk_sites_have_room()
	await _test_guards_keep_their_post()
	await _test_guards_leave_with_their_gate()

	run.queue_free()


func _test_every_anchor_has_two_or_three_guards() -> void:
	var ag := run.anchor_guards
	var tm := run.forest_world.torii_manager
	var anchors: Array[Node3D] = []
	for g in tm.get_active_gates():
		anchors.append(g)
	for s in run.hokora_manager.alive_shrines():
		anchors.append(s)
	_check("The run has gates and shrines to guard (%d anchors)" % anchors.size(), anchors.size() >= 2)

	var paths := run.forest_world.paths
	var bad_counts := 0
	var bad_ring := 0
	var bad_path := 0
	for anchor in anchors:
		var n := ag.guards_of(anchor).size()
		if n < 2 or n > 3:
			bad_counts += 1
		var ap := Vector2(anchor.global_position.x, anchor.global_position.z)
		for spot in ag.spots_of(anchor):
			var sp := Vector2(spot.x, spot.z)
			var d := sp.distance_to(ap)
			if d < 6.0 - EPS or d > 12.0 + EPS:
				bad_ring += 1
			if paths != null and paths.nearest_point(sp, ag.PATH_CLEARANCE) != Vector2.INF:
				bad_path += 1
	_check("Every live gate and shrine has 2–3 guards (%d anchors checked, %d outside 2–3)" % [anchors.size(), bad_counts],
		bad_counts == 0)
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
	var tm := run.forest_world.torii_manager
	var gate: ToriiGate = null
	for g in tm.get_active_gates():
		if not ag.guards_of(g).is_empty():
			gate = g
			break
	_check("A gate with guards is up before it streams away", gate != null)
	if gate == null:
		return
	var id := gate.get_instance_id()
	var before := _guards_with_post(id)
	tm.clear_gates()
	await _frames(40)
	var after := _guards_with_post(id)
	_check("A gate that streams away takes its %d guards with it (%d left)" % [before, after],
		before >= 2 and after == 0)


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
