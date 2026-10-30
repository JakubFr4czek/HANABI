extends Node
## Headless verification for the hokora shrine and its yellow Ofuda choice
## (docs/ELEMENTS_PLAN.md, D1 placement and D12 choice).
## - Walking up to a shrine opens nothing: only a hand on the offering table does
## - A touch with a yōkai within HOKORA_REFUSE_ENEMY_RADIUS is refused; the shrine stays lit
## - An accepted touch holds the world like the menu: the yōkai stands still, the blade
##   hits nothing but the cards, and the player does not move
## - Three cards hang in free air in front of the player, clear of every collider
## - Slicing a card grants its buff once, dims the other two, resumes the world and
##   takes the shrine dark for the run; a used shrine never opens again, even after
##   it streams away and back
## - No shrine stands inside a trunk, boulder or lantern collider; a new run lays them
##   in the same places; a 1.5 km walk meets a rare number of them
## godot --headless --path . --fixed-fps 90 res://tests/hokora_test.tscn -- --desktop

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

	await _test_walking_up_opens_nothing()
	await _test_touch_refused_with_enemy_close()
	await _test_touch_holds_the_world()
	await _test_katana_hits_only_cards()
	await _test_cards_clear_of_enemies()
	await _test_slice_grants_buff_and_resumes()
	await _test_used_shrine_stays_dark()
	await _test_buffs_multiply_and_hold()
	await _test_choice_reads_on_screen()
	await _test_placement_clear_of_colliders()
	await _test_density_along_a_walk()

	run.queue_free()


func _test_walking_up_opens_nothing() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_check("The opening shrine stands in view at the start of a run", shrine != null)
	if shrine == null:
		return
	_teleport_next_to(shrine)
	await _frames(60)
	_check("Walking up to a shrine opens no choice (no touch)", not run.shrine_offering.is_open())
	_check("The shrine stays lit, the world runs", shrine.lit and not get_tree().paused)


func _test_touch_refused_with_enemy_close() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(20)
	var near := run.wave_director.spawn_enemy_at(_ahead(2.0), player.global_position)
	await _frames(30)
	run.reach_for_offering()
	await _frames(3)
	_check("A touch with a yōkai 2 m away is refused (no choice)", not run.shrine_offering.is_open())
	_check("A refused shrine stays lit and rings a quiet refusal", shrine.lit and shrine.touch_cooldown > 0.0)
	_check("The refusal cools the shrine down (%.1f s): the same hand does not ring it again" % shrine.touch_cooldown,
		not shrine.is_touched_by(shrine.altar_position(), player.global_position))
	near.die({"element": Elements.NONE})
	run.wave_director.clear_enemies()
	await _frames(30)


func _test_touch_holds_the_world() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(20)
	var far := run.wave_director.spawn_enemy_at(_ahead(6.0), player.global_position)
	await _frames(90)
	run.reach_for_offering()
	await _frames(3)
	_check("A touch with no yōkai close opens the choice", run.shrine_offering.is_open())
	_check("The choice pauses the tree like the menu (paused and held)", get_tree().paused and run.pause_controller.offering_open)
	_check("Three yellow cards are on the table", run.get_tree().get_nodes_in_group("ofuda_talismans").size() == 3)
	var head_at := player.global_position
	var enemy_at := far.root_part().global_position
	await _frames(90)
	_check("The yōkai stands still while the choice is open (moved %.4f m)" % far.root_part().global_position.distance_to(enemy_at),
		far.root_part().global_position.distance_to(enemy_at) < 0.005)
	_check("The player does not move while the choice is open (moved %.4f m)" % player.global_position.distance_to(head_at),
		player.global_position.distance_to(head_at) < 0.005)
	_check("The blade is blocked from enemies during the choice", run.katana.combat_blocked)
	far.die({"element": Elements.NONE})
	run.wave_director.clear_enemies()
	run.shrine_offering.cancel()
	await _frames(30)


func _test_katana_hits_only_cards() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(20)
	var target := run.wave_director.spawn_enemy_at(_ahead(4.5), player.global_position)
	await _frames(60)
	run.reach_for_offering()
	await _frames(3)
	var hp_before := target.hp
	var part: RagdollPart = target.root_part()
	var hit := {
		"speed": 14.0,
		"collider": part,
		"point": part.global_position,
		"direction": Vector3.RIGHT,
		"normal": Vector3.UP,
	}
	run.katana._handle_hit(hit)
	_check("A cut on a yōkai during the choice deals no damage (%.1f -> %.1f)" % [hp_before, target.hp],
		is_equal_approx(target.hp, hp_before))
	target.die({"element": Elements.NONE})
	run.wave_director.clear_enemies()
	run.shrine_offering.cancel()
	await _frames(30)


func _test_cards_clear_of_enemies() -> void:
	# Cards never reach an enemy: an enemy within HOKORA_REFUSE_ENEMY_RADIUS refuses the
	# touch, and the cards hang inside that radius. So the cards are checked against a
	# yōkai just outside it, and against a wall right where the centre card would hang.
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(20)
	var close := run.wave_director.spawn_enemy_at(_ahead(4.4), player.global_position)
	await _frames(60)
	run.reach_for_offering()
	await _frames(3)
	_check("A yōkai 4.4 m away (outside the refusal radius) does not refuse the touch", run.shrine_offering.is_open())
	_check("Every card hangs in free space: no yōkai, trunk, rock or prop within 0.2 m of it",
		_cards_clear_of_world(close))
	close.die({"element": Elements.NONE})
	run.wave_director.clear_enemies()
	run.shrine_offering.cancel()
	await _frames(30)

	# A wall straight in front, where the centre card would hang: the choice either
	# finds room for all three cards around it, or refuses. It never clips the wall.
	_fresh_run()
	await _frames(8)
	shrine = run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(20)
	var wall := StaticBody3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(0.5, 2.0, 0.3)
	var wall_cs := CollisionShape3D.new()
	wall_cs.shape = wall_shape
	wall.add_child(wall_cs)
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = _ahead(1.1) + Vector3(0.0, 1.0, 0.0)
	run.add_child(wall)
	await _frames(4)
	run.reach_for_offering()
	await _frames(3)
	var opened_at_wall := run.shrine_offering.is_open()
	var wall_clear := true
	for c in run.get_tree().get_nodes_in_group("ofuda_talismans"):
		var card := c as Node3D
		if card.global_position.distance_to(wall.global_position) < 0.4:
			wall_clear = false
	_check("With a wall in front the cards find room around it or the touch is refused (opened: %s)" % opened_at_wall,
		wall_clear and (not opened_at_wall or run.get_tree().get_nodes_in_group("ofuda_talismans").size() == 3))
	run.shrine_offering.cancel()
	wall.queue_free()
	await _frames(30)


## True when every card of the open choice clears enemies, trunks, rocks and props, and
## stays out of [param enemy]'s reach.
func _cards_clear_of_world(enemy: Yokai) -> bool:
	var cards := run.get_tree().get_nodes_in_group("ofuda_talismans")
	if cards.size() != 3:
		return false
	var space := run.get_world_3d().direct_space_state
	for c in cards:
		var card := c as Node3D
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(VotiveTablet.WIDTH + 0.4, VotiveTablet.HEIGHT + 0.4, 0.28)
		q.shape = box
		q.transform = Transform3D(card.global_basis, card.global_position)
		q.collision_mask = ShrineOffering.CLEAR_MASK
		if not space.intersect_shape(q, 1).is_empty():
			return false
		if card.global_position.distance_to(enemy.root_part().global_position) < 0.3:
			return false
	return true


func _test_slice_grants_buff_and_resumes() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(20)
	run.reach_for_offering()
	await _frames(3)
	var cards: Array = run.get_tree().get_nodes_in_group("ofuda_talismans")
	_check("The choice is open with three cards", run.shrine_offering.is_open() and cards.size() == 3)
	var damage_card: OfudaTalisman = null
	for c in cards:
		if int((c as OfudaTalisman).entry.get("kind", -1)) == RunBuffs.Kind.DAMAGE:
			damage_card = c
	await _frames(60)  # the cards arrive and arm (ARM_TIME)
	damage_card.slice(damage_card.global_position, Vector3.RIGHT)
	await _frames(3)
	_check("Slicing the damage card grants +20 %% damage for 60 s (%.1f s left)" % buffs_remaining(),
		run.buffs.is_active(RunBuffs.Kind.DAMAGE) and buffs_remaining() > 59.0)
	_check("The other two cards fade away", _dismissed_count(cards) == 2)
	_check("The world resumes after the choice", not get_tree().paused and not run.pause_controller.offering_open and not run.katana.combat_blocked)
	_check("The shrine goes dark for the rest of the run", not shrine.lit and run.shrines_claimed == 1)
	_check("The katana carries the damage buff (scale %.2f)" % run.katana.outgoing_scale, is_equal_approx(run.katana.outgoing_scale, ElementBalance.BUFF_DAMAGE_MULTIPLIER))
	await _frames(40)


func _test_used_shrine_stays_dark() -> void:
	# The same shrine, touched again, opens nothing.
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_check("Touching the used shrine again opens no choice", shrine != null and not shrine.lit)
	run.reach_for_offering()
	await _frames(3)
	_check("A second touch on the used shrine opens nothing", not run.shrine_offering.is_open())
	# Streams away and comes back: still dark (the state is kept per slot for the run).
	var slot_pos := shrine.global_position
	player.teleport(Vector3(900.0, 0.0, 900.0), 0.0)
	await _frames(40)
	_check("Walking 1.2 km away culls the shrine", run.hokora_manager.shrine_at(Vector2i.ZERO) == null)
	player.teleport(Vector3(slot_pos.x + 4.0, run.forest_world.height_at(slot_pos.x + 4.0, slot_pos.z), slot_pos.z), 0.0)
	run.forest_world.finish_pending()
	await _frames(40)
	var back := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_check("Walking back shows exactly one shrine in the slot (no duplicate)",
		back != null and run.hokora_manager.alive_shrines().size() == 1 and back.global_position.distance_to(slot_pos) < 0.05)
	_check("A used shrine comes back dark", back != null and not back.lit)
	# The buff itself: speed and heal behave as ElementBalance says (pure, no scene).
	_check("Shrine buffs stack by kind: a second damage buff refreshes, not doubles",
		_refresh_check())


func _test_placement_clear_of_colliders() -> void:
	# A new run lays the same shrines in the same places (seeded per slot), and each
	# one must stand clear of trunks, boulders and lanterns.
	_fresh_run()
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

	_fresh_run()
	await _frames(8)
	var again := run.hokora_manager.alive_shrines()
	var same := again.size() == positions.size()
	for i in mini(again.size(), positions.size()):
		if again[i].global_position.distance_to(positions[i]) > 0.05:
			same = false
	_check("A new run places the same shrines in the same places (%d)" % again.size(), same and not again.is_empty())


## The balance model assumes a shrine about every 215 m of walking
## (WorldGenProfile shrine_slot_*). Walk 1.5 km in a straight line, 30 m a step, and
## count the distinct shrines met: the design says about 8, and it must stay rare.
func _test_density_along_a_walk() -> void:
	_fresh_run()
	await _frames(8)
	var seen := {}
	var steps := 50
	for i in range(1, steps + 1):
		var x := 30.0 * float(i)
		player.teleport(Vector3(x, run.forest_world.height_at(x, 0.0), 0.0), 0.0)
		run.forest_world.finish_pending()
		await _frames(24)
		for s in run.hokora_manager.alive_shrines():
			seen[s.slot] = true
	var met := seen.size()
	var spacing := 1500.0 / float(maxi(met, 1))
	_check("A 1.5 km straight walk meets %d shrines (about %.0f m apart; design ~215 m)" % [met, spacing],
		met >= 5 and met <= 11)


## The three buffs act on the numbers the game uses, and their timers stop with the world.
func _test_buffs_multiply_and_hold() -> void:
	_fresh_run()
	await _frames(8)
	var base_speed: float = run._base_move_speed
	var base_power := run.element_system.ability_power()
	var health := run._player_health()
	health.hp = 60.0
	run.buffs.apply(RunBuffs.Kind.SPEED, health)
	run.buffs.apply(RunBuffs.Kind.DAMAGE, health)
	await _frames(3)
	_check("Speed buff: the desktop walking speed is base × 1.2 (%.2f -> %.2f)" % [base_speed, player.move_speed],
		is_equal_approx(player.move_speed, base_speed * ElementBalance.BUFF_SPEED_MULTIPLIER))
	_check("Damage buff: ability power scales by 1.2 (%.2f -> %.2f)" % [base_power, run.element_system.ability_power()],
		is_equal_approx(run.element_system.ability_power(), base_power * ElementBalance.BUFF_DAMAGE_MULTIPLIER))
	run.buffs.clear()
	run.buffs.apply(RunBuffs.Kind.HEAL, health)
	_check("Heal: 35 %% of max HP at once (hp 60 -> %.0f)" % health.hp, is_equal_approx(health.hp, 95.0))
	run.buffs.step(10.0, health)
	_check("Heal: the next 15 %% of max HP runs as regeneration and stops at max (hp %.0f)" % health.hp,
		is_equal_approx(health.hp, 100.0))
	health.hp = 100.0
	run.buffs.apply(RunBuffs.Kind.HEAL, health)
	_check("A heal at full HP adds nothing and max HP never grows (hp %.0f, max %.0f)" % [health.hp, health.max_hp],
		is_equal_approx(health.hp, 100.0) and is_equal_approx(health.max_hp, 100.0))

	# Timers stop while the world is held for the choice.
	run.buffs.clear()
	run.buffs.apply(RunBuffs.Kind.SPEED, health)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	if shrine == null or not shrine.lit:
		_check("Setup: a lit shrine for the hold check", false)
		return
	_teleport_next_to(shrine)
	await _frames(20)
	run.reach_for_offering()
	await _frames(3)
	var before := run.buffs.remaining(RunBuffs.Kind.SPEED)
	await _frames(60)
	_check("The buff timer stands still while the choice holds the world (%.2f -> %.2f)" % [before, run.buffs.remaining(RunBuffs.Kind.SPEED)],
		is_equal_approx(before, run.buffs.remaining(RunBuffs.Kind.SPEED)))
	run.shrine_offering.cancel()
	await _frames(30)
	var after_pause := run.buffs.remaining(RunBuffs.Kind.SPEED)
	await _frames(30)
	_check("The buff timer runs again once the world resumes (%.2f -> %.2f)" % [after_pause, run.buffs.remaining(RunBuffs.Kind.SPEED)],
		run.buffs.remaining(RunBuffs.Kind.SPEED) < after_pause)
	run.buffs.clear()


## The choice reads on screen in the real run scene: the three cards sit in the
## camera's view, a comfortable reading distance away, with nothing in front of them,
## and the ink reads on the yellow paper (contrast).
func _test_choice_reads_on_screen() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(20)
	run.reach_for_offering()
	await _frames(70)  # the cards arrive and settle
	var cam := player.camera
	var cards := run.get_tree().get_nodes_in_group("ofuda_talismans")
	var view := run.get_viewport().get_visible_rect().size
	var space := run.get_world_3d().direct_space_state
	var in_view := 0
	var unblocked := 0
	var facing := 0
	var reading := 0
	var central := 0
	for c in cards:
		var card := c as Node3D
		var at := card.global_position
		if cam.is_position_in_frustum(at):
			in_view += 1
		var dist := cam.global_position.distance_to(at)
		if dist >= 0.75 and dist <= 1.3:
			reading += 1
		var sp := cam.unproject_position(at)
		if sp.x > view.x * 0.2 and sp.x < view.x * 0.8 and sp.y > view.y * 0.2 and sp.y < view.y * 0.8:
			central += 1
		var ray := PhysicsRayQueryParameters3D.create(cam.global_position, at, 1 | 2 | 64)
		if space.intersect_ray(ray).is_empty():
			unblocked += 1
		# The front of the card (+Z) must face the eyes, or the inscription reads backwards.
		var to_eye := (cam.global_position - at).normalized()
		if card.global_basis.z.dot(to_eye) > 0.7:
			facing += 1
	_check("All three cards are in the camera's view (%d/3)" % in_view, in_view == 3)
	_check("All three cards read at 0.75–1.3 m from the eyes (%d/3)" % reading, reading == 3)
	_check("All three cards sit in the central 60 %% of the screen (%d/3)" % central, central == 3)
	_check("Nothing blocks the view of any card: no trunk, prop or terrain in front (%d/3)" % unblocked, unblocked == 3)
	_check("Every card faces the player, so the inscription reads the right way round (%d/3)" % facing, facing == 3)
	var ink := OfudaTalisman.INK
	var paper := OfudaTalisman.PAPER
	var ratio := (_luminance(paper) + 0.05) / (_luminance(ink) + 0.05)
	_check("Ink on the yellow paper reads at contrast %.1f : 1 (needs 4.5)" % ratio, ratio >= 4.5)
	var header_ratio := (_luminance(paper) + 0.05) / (_luminance(OfudaTalisman.CINNABAR_TEXT) + 0.05)
	_check("The cinnabar header reads at contrast %.1f : 1 (needs 4.5)" % header_ratio, header_ratio >= 4.5)
	run.shrine_offering.cancel()
	await _frames(30)


static func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func _refresh_check() -> bool:
	var b := RunBuffs.new()
	var health := PlayerHealth.new()
	health.max_hp = 100.0
	health.hp = 100.0
	b.apply(RunBuffs.Kind.DAMAGE, health)
	b.step(30.0, health)
	b.apply(RunBuffs.Kind.DAMAGE, health)
	var refreshed := is_equal_approx(b.remaining(RunBuffs.Kind.DAMAGE), ElementBalance.BUFF_SECONDS)
	health.free()
	return refreshed


func buffs_remaining() -> float:
	return run.buffs.remaining(RunBuffs.Kind.DAMAGE)



func _dismissed_count(cards: Array) -> int:
	var n := 0
	for c in cards:
		if is_instance_valid(c) and (c as VotiveTablet).is_dismissed:
			n += 1
	return n


func _fresh_run() -> void:
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	if run.shrine_offering.is_open():
		run.shrine_offering.cancel()


## A point [param meters] straight ahead of the player on the ground.
func _ahead(meters: float) -> Vector3:
	var fwd := -player.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var p := player.global_position + fwd * meters
	p.y = run.forest_world.height_at(p.x, p.z)
	return p


func _teleport_next_to(shrine: HokoraShrine) -> void:
	var a := shrine.altar_position()
	player.teleport(Vector3(a.x + 0.9, run.forest_world.height_at(a.x + 0.9, a.z), a.z), 0.0)
	run.forest_world.finish_pending()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
