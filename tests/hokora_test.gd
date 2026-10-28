extends Node
## Headless verification for D1 (docs/ELEMENTS_PLAN.md, "D1 – ofuda z kapliczek"):
## Ofuda come only from hokora shrines.
## - Yōkai and elites drop no Ofuda; the wallet and the wrist tally do not move
## - Claiming a shrine gives exactly ElementBalance.OFUDA_PER_HOKORA, once;
##   a claimed shrine is dark and never pays again
## - The opening shrine is in view at the start, and it survives streaming:
##   walking away culls it, walking back shows the same one (no duplicate,
##   no refill), and a new run places it at the same spot (deterministic)
## - No shrine stands inside a trunk, boulder or lantern collider, or near a torii
##   godot --headless --path . --fixed-fps 90 res://tests/hokora_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_hokora_high_score.cfg"

var failures := 0
var run: RunGame
var player: DesktopPlayer


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
	await _frames(12)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)

	await _test_no_drops_from_yokai()
	await _test_opening_shrine_in_view()
	await _test_claim_pays_exactly_once()
	await _test_streaming_no_duplicates_no_farming()
	await _test_placement_clear_of_colliders()
	await _test_density_along_a_walk()

	run.queue_free()


func _test_no_drops_from_yokai() -> void:
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)
	var before := run.ofuda_count
	var elite := run.wave_director.spawn_elite_at(
		player.global_position + Vector3(0.0, 0.0, -2.5), player.global_position, Elements.SAKURA)
	await _frames(4)
	elite.die({"element": Elements.SAKURA})
	for i in 6:
		var swarm := run.wave_director.spawn_enemy_at(player.global_position + Vector3(float(i) - 3.0, 0.0, -3.0), player.global_position)
		await _frames(3)
		swarm.die({"element": Elements.NONE})
	await _frames(120)
	_check("Killing an elite and six swarm yōkai drops no Ofuda (wallet %d -> %d)" % [before, run.ofuda_count],
		run.ofuda_count == before)
	_check("No loose Ofuda pickups after yōkai deaths (%d)" % _pickup_count(), _pickup_count() == 0)
	_check("No yōkai drop code remains on RunGame (drop roller and scatter gone)",
		not run.has_method("ofuda_drop_count_for") and not run.has_method("_spawn_ofuda_drops"))


func _test_opening_shrine_in_view() -> void:
	run.start_run()
	run.wave_director.stop_director()
	await _frames(8)
	var opening := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_check("The opening shrine stands in view at the start of a run", opening != null)
	if opening == null:
		return
	var d := Vector2(opening.global_position.x - run.spawn.global_position.x,
		opening.global_position.z - run.spawn.global_position.z).length()
	_check("The opening shrine is %.0f m from the spawn (20–34 m: in view, off the fight ring)" % d,
		d >= ElementBalance.HOKORA_MIN_START_DISTANCE and d <= ElementBalance.HOKORA_SPAWN_RADIUS)


func _test_claim_pays_exactly_once() -> void:
	run.start_run()
	run.wave_director.stop_director()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	var before := run.ofuda_count
	_teleport_next_to(shrine)
	await _frames(240)
	var expected := ElementBalance.OFUDA_PER_HOKORA
	_check("Claiming a shrine gives exactly %d Ofuda (wallet %d -> %d)" % [expected, before, run.ofuda_count],
		run.ofuda_count == before + expected and _pickup_count() == 0)
	_check("The wrist tally shows the new total (札×%d)" % run.ofuda_count,
		run.diegetic_hud.wrist_label.text.contains("札×%d" % run.ofuda_count))
	_check("The claimed shrine goes dark", not shrine.lit)
	var after_first := run.ofuda_count
	_teleport_next_to(shrine)
	await _frames(60)
	_check("A second visit to the same shrine pays nothing (%d)" % run.ofuda_count, run.ofuda_count == after_first)
	_check("The run counts one shrine claimed", run.shrines_claimed == 1)


func _test_streaming_no_duplicates_no_farming() -> void:
	# Claim the opening shrine, then stream it away and back: it must come back
	# once, dark, and never refill.
	run.start_run()
	run.wave_director.stop_director()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	var slot_pos := shrine.global_position
	_teleport_next_to(shrine)
	await _frames(240)
	var claimed_once := run.ofuda_count
	_check("Setup: the opening shrine is claimed (wallet %d)" % claimed_once, claimed_once == ElementBalance.OFUDA_PER_HOKORA)
	# Walk far enough that every chunk around the shrine is streamed away.
	player.teleport(Vector3(900.0, 0.0, 900.0), 0.0)
	await _frames(40)
	_check("Walking 1.2 km away culls the shrine (alive: %d)" % run.hokora_manager.alive_shrines().size(),
		run.hokora_manager.shrine_at(Vector2i.ZERO) == null)
	# Come back 4 m off the altar: outside the claim radius, so nothing is taken.
	player.teleport(Vector3(slot_pos.x + 4.0, run.forest_world.height_at(slot_pos.x + 4.0, slot_pos.z), slot_pos.z), 0.0)
	await _frames(40)
	var back := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_check("Walking back shows exactly one shrine in the slot (no duplicate)",
		back != null and run.hokora_manager.alive_shrines().size() == 1 and back.global_position.distance_to(slot_pos) < 0.05)
	_check("A claimed shrine comes back dark", back != null and not back.lit)
	_teleport_next_to(back)
	await _frames(120)
	_check("Coming back does not refill a claimed shrine (%d -> %d)" % [claimed_once, run.ofuda_count],
		run.ofuda_count == claimed_once)


func _test_placement_clear_of_colliders() -> void:
	# A new run lays the same shrines in the same places (seeded per slot), and each
	# one must stand clear of trunks, boulders and lanterns.
	run.start_run()
	run.wave_director.stop_director()
	await _frames(8)
	var found := run.hokora_manager.alive_shrines()
	var positions: Array[Vector3] = []
	for s in found:
		positions.append(s.global_position)
	var clear := true
	var space := run.get_world_3d().direct_space_state
	var probe := CylinderShape3D.new()
	probe.radius = HokoraManager.CLEARANCE
	probe.height = 4.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.collision_mask = ForestWorld.TRUNK_LAYER
	for s in found:
		var p := s.global_position
		q.transform = Transform3D(Basis(), Vector3(p.x, p.y + 2.0, p.z))
		if not space.intersect_shape(q, 1).is_empty():
			clear = false
		if not run.forest_world.is_clear_of_props(p.x, p.z, HokoraManager.CLEARANCE):
			clear = false
	_check("Every shrine stands clear of trunks, boulders and lanterns (%d shrines)" % found.size(), clear and not found.is_empty())

	run.start_run()
	run.wave_director.stop_director()
	await _frames(8)
	var again := run.hokora_manager.alive_shrines()
	var same := again.size() == positions.size()
	for i in mini(again.size(), positions.size()):
		if again[i].global_position.distance_to(positions[i]) > 0.05:
			same = false
	_check("A new run places the same shrines in the same places (%d)" % again.size(), same and not again.is_empty())


## The balance model assumes a shrine about every 215 m of walking
## (ElementBalance.HOKORA_SLOT_*). Walk 1.5 km in a straight line, 30 m a step, and
## count the distinct shrines met: the design says about 8, and it must stay rare.
func _test_density_along_a_walk() -> void:
	run.start_run()
	run.wave_director.stop_director()
	await _frames(8)
	var seen := {}
	var steps := 50
	for i in range(1, steps + 1):
		var x := 30.0 * float(i)
		player.teleport(Vector3(x, run.forest_world.height_at(x, 0.0), 0.0), 0.0)
		await _frames(24)
		for s in run.hokora_manager.alive_shrines():
			seen[s.slot] = true
	var met := seen.size()
	var spacing := 1500.0 / float(maxi(met, 1))
	_check("A 1.5 km straight walk meets %d shrines (about %.0f m apart; design ~215 m)" % [met, spacing],
		met >= 5 and met <= 11)


func _teleport_next_to(shrine: HokoraShrine) -> void:
	var a := shrine.altar_position()
	player.teleport(Vector3(a.x + 0.9, run.forest_world.height_at(a.x + 0.9, a.z), a.z), 0.0)


func _teleport_next_to_point(p: Vector3) -> void:
	player.teleport(Vector3(p.x + 0.9, run.forest_world.height_at(p.x + 0.9, p.z), p.z), 0.0)


func _pickup_count() -> int:
	return run.get_node("OfudaPickups").get_child_count()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
