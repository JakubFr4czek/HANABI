extends Node
## P8: the hokora suzu. A hand or the blade tip on the bell, with the player in reach,
## stores one elemental charge (D21, buffer of 3). The bell then rests for
## HOKORA_BELL_COOLDOWN seconds, per shrine. Outside reach, on a resting bell, or with a
## full buffer, nothing is stored. Desktop E rings the bell when it is nearer than the altar.
## - A hand on the bell in reach stores one charge; the bell rests for 60 s, then rings again
## - Standing 3 m away, or a hand 1 m from the bell, stores nothing
## - A full buffer refuses the charge: a quiet ring and a short rest, no 60 s cooldown
## - The bell glows only while the player stands in reach of a ready bell
## - A used (dark) shrine's bell still rings
## godot --headless --path . --fixed-fps 90 res://tests/hokora_bell_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_hokora_bell_high_score.cfg"

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

	await _test_hand_on_bell_stores_charge()
	await _test_bell_rests_then_rings_again()
	await _test_out_of_reach_stores_nothing()
	await _test_full_buffer_refuses()
	await _test_bell_glows_in_reach()
	await _test_dark_shrine_bell_rings()

	run.queue_free()


func _test_hand_on_bell_stores_charge() -> void:
	var shrine := await _fresh_run()
	_check("The opening shrine stands in view at the start of a run", shrine != null)
	if shrine == null:
		return
	var bell := shrine.bell_position()
	# Stand on the far side of the bell from the altar, so the bell is the nearer target.
	_stand_beside_bell(shrine, bell - shrine.altar_position(), 0.6)
	await _frames(20)
	var expected := shrine.bell_element()
	var before := run.element_system.get_charges().size()
	run.reach_for_offering()
	await _frames(3)
	var after := run.element_system.get_charges()
	_check("A desktop E on the bell in reach stores one charge (%d -> %d)" % [before, after.size()],
		after.size() == before + 1)
	_check("The charge is the bell's element (%s)" % expected,
		after.size() > 0 and after[after.size() - 1] == expected)
	_check("The bell rests for 60 s after a ring (%.1f s)" % shrine.bell_cooldown,
		shrine.bell_cooldown > 58.0 and shrine.bell_cooldown <= ElementBalance.HOKORA_BELL_COOLDOWN)
	_check("A bell touch opens no Ofuda choice", not run.shrine_offering.is_open())
	_check("The shrine stays lit (the Ofuda choice is not used)", shrine.lit)
	_check("The bell touch counts once: the next frame stores nothing",
		run.element_system.get_charges().size() == after.size())


func _test_bell_rests_then_rings_again() -> void:
	var shrine := await _fresh_run()
	if shrine == null:
		return
	var bell := shrine.bell_position()
	var stand := _stand_beside_bell(shrine, bell - shrine.altar_position(), 0.6)
	await _frames(12)
	run.reach_for_offering()
	await _frames(3)
	var count := run.element_system.get_charges().size()
	_check("The bell rings once to start the rest", count == 1)
	_check("A resting bell refuses the same hand", not shrine.is_bell_touched_by(bell, stand))
	run.reach_for_offering()
	await _frames(3)
	_check("A second E while the bell rests stores nothing", run.element_system.get_charges().size() == count)
	_check("While the bell rests, E falls through to the altar: the Ofuda choice opens", run.shrine_offering.is_open())
	run.shrine_offering.cancel()
	await _frames(3)
	shrine.step(ElementBalance.HOKORA_BELL_COOLDOWN - 1.0, stand)
	_check("The bell still rests one second before its cooldown ends", not shrine.is_bell_touched_by(bell, stand))
	shrine.step(1.1, stand)
	_check("After 60 s the bell is ready and rings again", shrine.is_bell_touched_by(bell, stand))
	run.reach_for_offering()
	await _frames(3)
	_check("The ready bell stores a second charge (%d)" % run.element_system.get_charges().size(),
		run.element_system.get_charges().size() == count + 1)


func _test_out_of_reach_stores_nothing() -> void:
	var shrine := await _fresh_run()
	if shrine == null:
		return
	var bell := shrine.bell_position()
	_stand_beside_bell(shrine, Vector3.RIGHT, 3.0)
	await _frames(12)
	var before := run.element_system.get_charges().size()
	run.reach_for_offering()
	await _frames(3)
	_check("Standing 3 m from the bell stores nothing", run.element_system.get_charges().size() == before)
	_check("A bell 3 m away does not ring (cooldown %.1f s)" % shrine.bell_cooldown, shrine.bell_cooldown <= 0.0)
	var stand := _stand_beside_bell(shrine, Vector3.RIGHT, 0.6)
	_check("A hand 1 m from the bell does not touch it",
		not shrine.is_bell_touched_by(bell + Vector3.RIGHT * 1.0, stand))
	_check("A hand on the bell with the player 3 m away does not touch it",
		not shrine.is_bell_touched_by(bell, bell + Vector3.RIGHT * 3.0))
	_check("A hand on the bell with the player in reach does touch it", shrine.is_bell_touched_by(bell, stand))


func _test_full_buffer_refuses() -> void:
	var shrine := await _fresh_run()
	if shrine == null:
		return
	var bell := shrine.bell_position()
	_stand_beside_bell(shrine, bell - shrine.altar_position(), 0.6)
	await _frames(12)
	for i in ElementSystem.MAX_CHARGES:
		run.element_system.add_charge(Elements.SAKURA)
	run.reach_for_offering()
	await _frames(3)
	_check("A full buffer (3) stores no more charge", run.element_system.get_charges().size() == ElementSystem.MAX_CHARGES)
	_check("A refused bell takes the short refusal rest, not the 60 s one (%.1f s)" % shrine.bell_cooldown,
		shrine.bell_cooldown > 0.0 and shrine.bell_cooldown <= ElementBalance.HOKORA_BELL_COOLDOWN and shrine.bell_rings == 0)
	run.element_system.charges.clear()
	await _frames(150)
	run.reach_for_offering()
	await _frames(3)
	_check("Once the refusal rest ends and the buffer has room, the bell rings", run.element_system.get_charges().size() == 1)


func _test_bell_glows_in_reach() -> void:
	var shrine := await _fresh_run()
	if shrine == null:
		return
	var bell := shrine.bell_position()
	_stand_beside_bell(shrine, bell - shrine.altar_position(), 0.6)
	await _frames(6)
	var near_glow: float = shrine._bell_mat.emission_energy_multiplier
	_check("The bell glows faintly in reach of a ready bell (%.2f)" % near_glow, near_glow > 0.0)
	_stand_beside_bell(shrine, Vector3.RIGHT, 6.0)
	await _frames(6)
	_check("The bell goes dark out of reach (%.2f)" % shrine._bell_mat.emission_energy_multiplier,
		shrine._bell_mat.emission_energy_multiplier == 0.0)


func _test_dark_shrine_bell_rings() -> void:
	var shrine := await _fresh_run()
	if shrine == null:
		return
	shrine.set_lit(false)
	var bell := shrine.bell_position()
	var stand := _stand_beside_bell(shrine, bell - shrine.altar_position(), 0.6)
	await _frames(12)
	var before := run.element_system.get_charges().size()
	run.reach_for_offering()
	await _frames(3)
	_check("A used shrine's bell still stores a charge", run.element_system.get_charges().size() == before + 1)
	_check("A used shrine opens no Ofuda choice from the bell", not run.shrine_offering.is_open())
	_check("The bell is resting after the ring", not shrine.is_bell_touched_by(bell, stand))


## A fresh run with an empty charge buffer; returns the opening shrine (or null).
func _fresh_run() -> HokoraShrine:
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	if run.shrine_offering.is_open():
		run.shrine_offering.cancel()
	run.element_system.charges.clear()
	# The opening shrine is built a few physics frames after the run starts.
	await _frames(8)
	return run.hokora_manager.shrine_at(Vector2i.ZERO)


## Puts the player [param meters] from the suzu, on the side [param away] points to,
## facing the bell. Returns the player's feet position.
func _stand_beside_bell(shrine: HokoraShrine, away: Vector3, meters: float) -> Vector3:
	var bell := shrine.bell_position()
	var flat := Vector3(away.x, 0.0, away.z)
	if flat.length_squared() < 1e-6:
		flat = Vector3.RIGHT
	var p := bell + flat.normalized() * meters
	player.teleport(Vector3(p.x, run.forest_world.height_at(p.x, p.z), p.z), 0.0)
	run.forest_world.finish_pending()
	return player.global_position


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
