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
## - Every shrine, the opening one included, stands on a spur within 8 m of the footpath
##   network, and the spur is built from the path to its offering table
## - The house is the scanned asset (SamRi shrine, tris within budget, wet forest shader)
##   and one candle light stands in the whole run: the nearest lit shrine only (N6)
## - Windowed only (pixels, SKIP headless): a shrine 20 m out reads as a warm spot brighter
##   than the sky, and at 3 m its body is not a black silhouette (N6)
## - F3: outside HOKORA_PROMPT_RADIUS no prompt; at 1.5 m in front the altar breathes warm and
##   the sign prints the offering key from RunGame.OFFERING_KEY; a real E key event opens the
##   choice exactly once (a second press while open and a press after the cut do nothing), the
##   candle flares, and the used shrine never shows its prompt again
## - Windowed only: at 1.5 m the lit sign sits whole in the frame and its ink reads on the paper
## - F7 soul vessels: a seed plans exactly SoulVesselManager.COUNT vessels, MIN_SPACING apart,
##   each within 8 m of the footpath network, the same spots every run; A/X (reach_for_offering)
##   in reach releases one exactly once and the wrist row reads DUSZE n/N; N/N saves the village
##   (state GAME_OVER, village_saved, the stele says so). Windowed: the vessel's glow reads in the
##   frame from 8 m (with `--f7-shots`: screenshots to docs/f7/)
## godot --headless --path . --fixed-fps 90 res://tests/hokora_test.tscn -- --desktop [--only-f3 | --only-f7]

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

	if "--only-f7" in OS.get_cmdline_user_args():
		await _test_f7_soul_vessels()
		run.queue_free()
		return
	await _test_walking_up_opens_nothing()
	await _test_prompt_only_in_reach()
	await _test_key_press_opens_once()
	await _test_prompt_reads_at_1p5m()
	# `-- --only-f3`: the F3 checks alone (the windowed pixel run takes minutes otherwise).
	if "--only-f3" in OS.get_cmdline_user_args():
		run.queue_free()
		return
	await _test_touch_refused_with_enemy_close()
	await _test_touch_holds_the_world()
	await _test_katana_hits_only_cards()
	await _test_cards_clear_of_enemies()
	await _test_slice_grants_buff_and_resumes()
	await _test_used_shrine_stays_dark()
	await _test_buffs_multiply_and_hold()
	await _test_choice_reads_on_screen()
	await _test_placement_clear_of_colliders()
	await _test_shrines_on_footpath()
	await _test_density_along_a_walk()
	await _test_shrine_is_the_asset()
	await _test_one_candle_light()
	await _test_shrine_reads_in_the_fog()
	await _test_lantern_reads_at_10m()
	await _test_f7_soul_vessels()

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


## F3: the prompt is the shrine's answer to the player standing at its altar, nothing else.
func _test_prompt_only_in_reach() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	if shrine == null:
		_check("F3: the opening shrine exists", false)
		return
	_stand_in_front(shrine, 6.0)
	await _frames(30)
	_check("F3: 6 m from the altar there is no prompt (no sign text, manager picks none)",
		not shrine.prompt_shown and not shrine.sign_visible() and run.hokora_manager.prompt_shrine() == null)
	var cloth_far := shrine._altar_cloth_mat.emission_energy_multiplier
	_stand_in_front(shrine, 2.6)
	await _frames(30)
	_check("F3: 2.6 m (outside %.1f m) still no prompt" % ElementBalance.HOKORA_PROMPT_RADIUS,
		not shrine.prompt_shown and not shrine.sign_visible())
	_stand_in_front(shrine, 1.5)
	await _frames(30)
	_check("F3: 1.5 m in front of the altar the prompt is up and the sign is lit",
		shrine.prompt_shown and shrine.sign_visible() and run.hokora_manager.prompt_shrine() == shrine)
	var key := OS.get_keycode_string(RunGame.OFFERING_KEY)
	_check("F3: the sign prints the offering key from the binding ('%s' == '%s')" % [shrine._key_label.text, key],
		shrine._key_label.text == key and shrine._key_label.visible and shrine._action_label.text != "")
	_check("F3: the altar cloth glows warmer at the prompt (%.2f > %.2f)" % [shrine._altar_cloth_mat.emission_energy_multiplier, cloth_far],
		shrine._altar_cloth_mat.emission_energy_multiplier > cloth_far + 0.3)
	_check("F3: the prompt opens nothing by itself", not run.shrine_offering.is_open() and shrine.lit)


## F3: one press of the real key opens the choice once; the reward comes from the cut; a
## second press, during the choice or after it, does nothing.
func _test_key_press_opens_once() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	if shrine == null:
		return
	var counts := {"opened": 0, "chosen": 0}
	var on_open := func(_s: HokoraShrine) -> void: counts["opened"] += 1
	var on_chosen := func(_s: HokoraShrine, _k: int) -> void: counts["chosen"] += 1
	run.shrine_offering.opened.connect(on_open)
	run.shrine_offering.chosen.connect(on_chosen)
	var claimed := run.shrines_claimed
	_stand_in_front(shrine, 1.5)
	await _frames(30)
	_press_offering_key()
	await _frames(3)
	_check("F3: one E press at the prompt opens the choice (opened %d)" % counts["opened"],
		counts["opened"] == 1 and run.shrine_offering.is_open())
	_check("F3: the candle flares (%.2f) and the sign goes out for the cards" % shrine.flare,
		shrine.flare > 0.5 and not shrine.prompt_shown)
	_press_offering_key()
	await _frames(3)
	_check("F3: a second press while the choice is open opens nothing more (opened %d)" % counts["opened"],
		counts["opened"] == 1)
	var card: OfudaTalisman = null
	for c in get_tree().get_nodes_in_group("ofuda_talismans"):
		if not (c as OfudaTalisman).is_queued_for_deletion():
			card = c
	if card:
		card.slice(card.global_position, Vector3.RIGHT)
	await _frames(30)
	_check("F3: the cut grants the reward exactly once (chosen %d, claimed +%d)" % [counts["chosen"], run.shrines_claimed - claimed],
		counts["chosen"] == 1 and run.shrines_claimed == claimed + 1)
	_check("F3: the used shrine is dark and shows no prompt at the altar",
		not shrine.lit and not shrine.prompt_shown and not shrine.sign_visible() and run.hokora_manager.prompt_shrine() == null)
	_press_offering_key()
	await _frames(30)
	_check("F3: a press at a used shrine does nothing (opened %d, chosen %d, still dark)" % [counts["opened"], counts["chosen"]],
		counts["opened"] == 1 and counts["chosen"] == 1 and not run.shrine_offering.is_open() and not shrine.lit and not shrine.sign_visible())
	run.shrine_offering.opened.disconnect(on_open)
	run.shrine_offering.chosen.disconnect(on_chosen)
	await _frames(60)


## Windowed only (F3): at 1.5 m, looking down at the altar as a player does, the lit sign
## sits whole in the frame and its ink reads on the warm paper.
func _test_prompt_reads_at_1p5m() -> void:
	if not _rendering():
		print("SKIP  F3: the prompt sign reads at 1.5 m (windowed only: pixels)")
		return
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	if shrine == null:
		return
	_stand_in_front(shrine, 1.5)
	_look_down(20.0)
	await _frames(50)
	var img := player.get_viewport().get_texture().get_image()
	var viewport := player.get_viewport().get_visible_rect().size
	var paper_xf := (shrine.get_node("PromptSign/Panel/Lean/SignPaper") as Node3D).global_transform
	var half := HokoraShrine.SIGN_PAPER_SIZE * 0.5
	var rect := _box_rect(player.camera, paper_xf, AABB(Vector3(-half.x, -half.y, 0.0), Vector3(half.x * 2.0, half.y * 2.0, 0.001)), viewport)
	var inside := Rect2i(Vector2i.ZERO, Vector2i(viewport)).encloses(rect) and rect.position.x > 0 and rect.end.x < int(viewport.x) - 1 and rect.position.y > 0 and rect.end.y < int(viewport.y) - 1
	_check("F3 1.5 m: the sign sits whole in the frame (%s in %s)" % [rect, viewport], inside and rect.size.x >= 60)
	# Inside the paper only (12 % in from each edge): the dark pixels there are ink, not the night.
	var inner := rect.grow_individual(-int(rect.size.x * 0.12), -int(rect.size.y * 0.12), -int(rect.size.x * 0.12), -int(rect.size.y * 0.12))
	var paper := _quantile_luma(img, inner, 0.8)
	var ink := _quantile_luma(img, inner, 0.04)
	_check("F3 1.5 m: the paper is lit (luma %.2f) and the ink reads on it (ink %.2f, contrast %.1f : 1)" % [paper, ink, (paper + 0.05) / (ink + 0.05)],
		paper > 0.45 and (paper + 0.05) / (ink + 0.05) >= 4.5)
	_check("F3 1.5 m: the paper glows warm, not white or neon (%.0f°)" % (_bright_colour(img, rect, 0.3).h * 360.0),
		_is_warm(_bright_colour(img, rect, 0.3), 15.0, 60.0, 0.2))
	_look_down(0.0)


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


## Shrines never stand in the open forest: each one lies within 8 m of the footpath
## network (the spur it stands on), and the spur is built from that path to its altar.
## The opening shrine and a walk of 1.5 km are both checked.
func _test_shrines_on_footpath() -> void:
	_fresh_run()
	await _frames(8)
	var paths := run.forest_world.paths
	var opening := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_check("The opening shrine stands on a spur of the footpath", opening != null and _on_footpath(paths, opening))
	var all_on_path := true
	var spurs := 0
	for s in run.hokora_manager.alive_shrines():
		if not _on_footpath(paths, s):
			all_on_path = false
		if s.get_node_or_null("PathSpur") != null:
			spurs += 1
	var count := run.hokora_manager.alive_shrines().size()
	_check("Every shrine stands within 8 m of the footpath (%d shrines)" % count, all_on_path and count > 0)
	_check("Every shrine has its spur to the path (%d of %d)" % [spurs, count], spurs == count and count > 0)


func _on_footpath(paths: ForestPaths, shrine: HokoraShrine) -> bool:
	var p := shrine.global_position
	return paths != null and paths.nearest_point(Vector2(p.x, p.z), 8.0) != Vector2.INF


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


## The house is the scanned asset (N6): a mesh from the baked glb, within the triangle budget,
## wearing the forest's wet shader with the scan's atlas, not a procedural box.
func _test_shrine_is_the_asset() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	var house := shrine.find_child("Samri", true, false) as Node3D
	_check("The shrine has the scanned house under its model slot", house != null)
	if house == null:
		return
	var meshes := HokoraShrine._mesh_instances(house)
	var tris := 0
	var box := false
	for mi in meshes:
		tris += ForestWorld._triangles(mi.mesh)
		box = box or mi.mesh is BoxMesh
	_check("The house is a mesh from the asset, not a box (%d parts)" % meshes.size(), not meshes.is_empty() and not box)
	_check("The house stays within 3000 triangles (%d)" % tris, tris > 0 and tris <= 3000)
	var mat := meshes[0].material_override as ShaderMaterial if not meshes.is_empty() else null
	_check("The house wears the wet forest shader with its scan atlas",
		mat != null and mat.shader == HokoraShrine.WET_SHADER and mat.get_shader_parameter("albedo_texture") != null)


## One candle light for the whole run: it lights only the lit shrine nearest the player, and
## a used shrine lets it go out (N6, Quest 3 light budget).
func _test_one_candle_light() -> void:
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_teleport_next_to(shrine)
	await _frames(6)
	var candle := shrine.get_node_or_null("CandleLight") as OmniLight3D
	_check("The shrine has its candle light, off until the player is near", candle != null)
	if candle == null:
		return
	var lit_lights := _visible_candle_lights()
	_check("Only the nearest lit shrine shows its candle light (%d visible)" % lit_lights, lit_lights == 1 and candle.visible)
	shrine.consume()
	await _frames(4)
	_check("A used shrine lets its candle light go out (%d visible)" % _visible_candle_lights(), _visible_candle_lights() == 0)


func _visible_candle_lights() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("hokora_shrines"):
		var light := node.get_node_or_null("CandleLight") as OmniLight3D
		if light != null and light.visible:
			n += 1
	return n


## Windowed only. 20 m out, the candle's halo is a warm spot (hue orange to yellow) and
## brighter than the sky behind it. At 3 m the shrine's body is not a black silhouette.
## Headless renders nothing, so this prints SKIP there (the run's pixel checks happen windowed).
func _test_shrine_reads_in_the_fog() -> void:
	if not _rendering():
		print("SKIP  the shrine reads in the fog (windowed only: pixels)")
		return
	_fresh_run()
	await _frames(8)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	var viewport := get_viewport().get_visible_rect().size
	var xform := shrine.global_transform
	var halo_local := AABB(HokoraShrine.LANTERN_LOCAL - Vector3(0.9, 0.9, 0.9), Vector3(1.8, 1.8, 1.8))
	var body_local := AABB(Vector3(-0.8, 0.0, -0.6), Vector3(1.6, 1.5, 1.2))

	_stand_at_distance(shrine, 20.0)
	await _frames(40)
	var img := get_viewport().get_texture().get_image()
	var glow := _box_rect(player.camera, xform, halo_local, viewport)
	var sky := Rect2i(0, 0, int(viewport.x), int(viewport.y * 0.25))
	var sky_luma := _quantile_luma(img, sky, 0.5)
	var warm := _bright_colour(img, glow, 0.02)
	_check("20 m: the candle's glow is a warm hue (%.0f°, sat %.2f)" % [warm.h * 360.0, warm.s],
		glow.size.x > 0 and _is_warm(warm))
	_check("20 m: the glow is brighter than the sky (glow %.2f, sky %.2f)" % [_luma(warm), sky_luma],
		_luma(warm) > sky_luma + 0.08)

	_stand_at_distance(shrine, 3.2)
	await _frames(40)
	img = get_viewport().get_texture().get_image()
	var body := _box_rect(player.camera, xform, body_local, viewport)
	var body_luma := _mean_luma(img, body)
	_check("3 m: the body is not a black silhouette (mean luma %.3f over %d x %d px)" % [body_luma, body.size.x, body.size.y],
		body.size.x >= 60 and body_luma > SHRINE_BODY_MIN_LUMA)


## The threshold below which the body reads as a silhouette (mean luma, 0..1).
const SHRINE_BODY_MIN_LUMA := 0.1


## Puts the player [param distance] m from the shrine, on the walk-in side, with a clear sight
## line to its candle (so no trunk hides the body).
func _stand_at_distance(shrine: HokoraShrine, distance: float) -> void:
	var altar := shrine.altar_position()
	var from := Vector3(run.spawn.global_position.x, 0.0, run.spawn.global_position.z)
	var dir := (Vector3(altar.x, 0.0, altar.z) - from).normalized()
	var candle := shrine.global_transform * HokoraShrine.LANTERN_LOCAL
	var space := run.get_world_3d().direct_space_state
	var stand := Vector3(altar.x, 0.0, altar.z) - dir * distance
	for deg in [0.0, 6.0, -6.0, 12.0, -12.0, 18.0, -18.0]:
		var d: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(deg))
		var cand := Vector3(altar.x, 0.0, altar.z) - d * distance
		cand.y = run.forest_world.height_at(cand.x, cand.z)
		var q := PhysicsRayQueryParameters3D.create(cand + Vector3(0.0, 1.6, 0.0), candle, ForestWorld.TRUNK_LAYER)
		if space.intersect_ray(q).is_empty():
			stand = cand
			break
	stand.y = run.forest_world.height_at(stand.x, stand.z)
	var yaw := atan2(-(altar.x - stand.x), -(altar.z - stand.z))
	player.teleport(stand, yaw)
	run.forest_world.finish_pending()


## Windowed only (N6): a stone lantern 10 m off, on open ground, shows its warm paper against
## the stone. The paper is the brightest share of the lantern's rectangle; the stone is the rest.
## Headless renders nothing, so this prints SKIP there.
func _test_lantern_reads_at_10m() -> void:
	if not _rendering():
		print("SKIP  the stone lantern reads at 10 m (windowed only: pixels)")
		return
	_fresh_run()
	await _frames(8)
	var forest := run.forest_world
	var altar_free := Vector3(run.spawn.global_position.x, 0.0, run.spawn.global_position.z)
	var lantern_at := Vector3.ZERO
	var stand := Vector3.ZERO
	var space := run.get_world_3d().direct_space_state
	# The first side (and then the other way round) whose sight line from the stand is free of trunks.
	for k in 12:
		var yaw := TAU * float(k) / 12.0
		var ahead := Vector3(sin(yaw), 0.0, cos(yaw))
		var s0 := altar_free + ahead * 8.0
		s0.y = forest.height_at(s0.x, s0.z)
		var l0 := s0 + ahead * 10.0
		l0.y = forest.height_at(l0.x, l0.z)
		var q := PhysicsRayQueryParameters3D.create(s0 + Vector3(0.0, 1.6, 0.0), l0 + Vector3(0.0, 0.7, 0.0), ForestWorld.TRUNK_LAYER)
		if space.intersect_ray(q).is_empty():
			stand = s0
			lantern_at = l0
			break
	var lantern := MeshInstance3D.new()
	lantern.name = "ProbeLantern"
	lantern.mesh = forest._lantern_mesh
	lantern.material_override = forest._lantern_mat
	run.add_child(lantern)
	lantern.global_position = lantern_at
	var face := atan2(-(lantern_at.x - stand.x), -(lantern_at.z - stand.z))
	player.teleport(stand, face)
	forest.finish_pending()
	await _frames(40)
	var img := player.get_viewport().get_texture().get_image()
	var viewport := player.get_viewport().get_visible_rect().size
	var rect := _box_rect(player.camera, Transform3D(Basis(), lantern_at), AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.5, 0.8)), viewport)
	var paper := _bright_colour(img, rect, 0.03)
	var paper_luma := _luma(paper)
	var stone_luma := _quantile_luma(img, rect, 0.5)
	_check("10 m: the lantern's paper is warm (%.0f°)" % (paper.h * 360.0), rect.size.x >= 8 and _is_warm(paper))
	_check("10 m: the paper reads brighter than the stone (paper %.2f, stone %.2f)" % [paper_luma, stone_luma],
		paper_luma > stone_luma + 0.12)
	# The stone shaft (30–70 % of the lantern's height, centre columns) reads grey, not brown:
	# low saturation over its lit pixels. Brown wood or a rust tint would fail this.
	var shaft := Rect2i(rect.position + Vector2i(int(rect.size.x * 0.25), int(rect.size.y * 0.3)),
		Vector2i(int(rect.size.x * 0.5), int(rect.size.y * 0.4)))
	var stone := _mean_lit_colour(img, shaft, 0.02)
	_check("10 m: the stone reads grey, not brown (saturation %.2f of its mean colour, needs < 0.25)" % stone.s,
		stone.s < 0.25)
	lantern.queue_free()
	run.wave_director.clear_enemies()




## The mean colour of the rectangle's pixels brighter than [param min_luma] (the lit part).
static func _mean_lit_colour(img: Image, rect: Rect2i, min_luma: float) -> Color:
	var acc := Color(0, 0, 0, 1)
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := img.get_pixel(x, y)
			if _luma(c) >= min_luma:
				acc += c
				n += 1
	return Color(acc.r / maxf(float(n), 1.0), acc.g / maxf(float(n), 1.0), acc.b / maxf(float(n), 1.0), 1.0)

## The pixel helpers (windowed checks only). Each works on the frame the viewport rendered.
static func _rendering() -> bool:
	return DisplayServer.get_name() != "headless"


## Screen rectangle covered by [param local] (a box in [param xform]'s space), clamped to
## the viewport. Empty when every corner is behind the camera.
static func _box_rect(cam: Camera3D, xform: Transform3D, local: AABB, viewport: Vector2) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var corner := local.position + local.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)
		var world := xform * corner
		if cam.is_position_behind(world):
			continue
		var p := cam.unproject_position(world)
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		return Rect2i()
	var r := Rect2i(Vector2i(lo.floor()), Vector2i((hi - lo).ceil()))
	return r.intersection(Rect2i(Vector2i.ZERO, Vector2i(viewport)))


## Rec.709 luma of a colour (sRGB values as stored in the frame).
static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Mean luma over the rectangle.
static func _mean_luma(img: Image, rect: Rect2i) -> float:
	var sum := 0.0
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			sum += _luma(img.get_pixel(x, y))
			n += 1
	return sum / maxf(float(n), 1.0)


## Luma at quantile [param q] (0..1) over the rectangle.
static func _quantile_luma(img: Image, rect: Rect2i, q: float) -> float:
	var values := PackedFloat32Array()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			values.append(_luma(img.get_pixel(x, y)))
	if values.is_empty():
		return 0.0
	values.sort()
	return values[clampi(int(q * float(values.size())), 0, values.size() - 1)]


## Mean colour of the brightest [param share] of the rectangle's pixels (0..1).
static func _bright_colour(img: Image, rect: Rect2i, share: float) -> Color:
	var px: Array[Color] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			px.append(img.get_pixel(x, y))
	if px.is_empty():
		return Color.BLACK
	px.sort_custom(func(a: Color, b: Color) -> bool: return _luma(a) > _luma(b))
	var n := maxi(1, int(share * float(px.size())))
	var acc := Color(0, 0, 0, 1)
	for k in n:
		acc += px[k]
	return Color(acc.r / n, acc.g / n, acc.b / n, 1.0)


## True for a warm colour: hue between [param lo] and [param hi] degrees (orange to yellow
## by default) and enough saturation to read as a colour, not as grey fog.
static func _is_warm(c: Color, lo := 10.0, hi := 70.0, min_sat := 0.35) -> bool:
	var h := c.h * 360.0
	return h >= lo and h <= hi and c.s >= min_sat


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


## Stands the player [param meters] in front of the shrine's altar (along its +Z), facing it.
func _stand_in_front(shrine: HokoraShrine, meters: float) -> void:
	var a := shrine.altar_position()
	var front := shrine.global_basis.z
	front.y = 0.0
	front = front.normalized()
	var stand := a + front * meters
	stand.y = run.forest_world.height_at(stand.x, stand.z)
	player.teleport(stand, atan2(-(a.x - stand.x), -(a.z - stand.z)))
	run.forest_world.finish_pending()


func _look_down(degrees: float) -> void:
	player._pitch = deg_to_rad(-degrees)
	player.camera.rotation.x = player._pitch


## A real key event for the offering key (what a desktop player presses).
func _press_offering_key() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = RunGame.OFFERING_KEY
	ev.keycode = RunGame.OFFERING_KEY
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	get_viewport().push_input(up)


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


# --- F7: soul vessels ------------------------------------------------------------------

func _test_f7_soul_vessels() -> void:
	_fresh_run()
	await _frames(6)
	var sv := run.soul_vessels
	var spots := sv.spots.duplicate()
	_check("F7: the seed plans exactly %d soul vessels (%d)" % [SoulVesselManager.COUNT, spots.size()],
		spots.size() == SoulVesselManager.COUNT)
	var min_gap := INF
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			min_gap = minf(min_gap, Vector2(spots[i].x - spots[j].x, spots[i].z - spots[j].z).length())
	_check("F7: vessels stand >= %.0f m apart (closest %.1f m)" % [SoulVesselManager.MIN_SPACING, min_gap],
		min_gap >= SoulVesselManager.MIN_SPACING)
	var reachable := true
	for p in spots:
		if run.forest_world.paths.nearest_point(Vector2(p.x, p.z), 8.0) == Vector2.INF:
			reachable = false
	_check("F7: every vessel is within 8 m of a footpath", reachable)
	_fresh_run()
	await _frames(2)
	_check("F7: a new run lays the vessels in the same places", run.soul_vessels.spots == spots)
	# Release one: stand beside it, press A/X (reach_for_offering) twice.
	await _f7_stand_near(0, 1.4)
	var v := sv.vessel(0)
	_check("F7: walking near builds the vessel (komainu scan + glow)", v != null and v.get_node_or_null("Komainu") != null)
	run.reach_for_offering()
	run.reach_for_offering()
	await _frames(3)
	_check("F7: one press releases one soul, a second press on it does nothing (%d)" % sv.released_count(),
		sv.released_count() == 1 and sv.is_released(0))
	_check("F7: the wrist reads DUSZE 1/%d (%s %s)" % [spots.size(), run.diegetic_hud.row_label("souls"), run.diegetic_hud.row_value("souls")],
		run.diegetic_hud.row_label("souls") == "DUSZE" and run.diegetic_hud.row_value("souls") == "1/%d" % spots.size())
	_check("F7: the run goes on after one soul", run.state == RunGame.RunState.PLAYING)
	var sign := v.get_node("Sign") as Label3D
	_check("F7 r1: the vessel sign is big and drawn over the world (%d px × %.5f, no_depth_test %s)" % [sign.font_size, sign.pixel_size, sign.no_depth_test],
		float(sign.font_size) * sign.pixel_size >= 2.0 * 34.0 * 0.0011 and sign.no_depth_test and sign.outline_size >= 12)
	var light := v.get_node("SoulLight") as OmniLight3D
	_check("F7 r1: the soul light is soft and above the statue (energy base %.2f, y %.2f)" % [0.45, light.position.y],
		light.position.y >= SoulVessel.LIGHT_Y - 0.01 and light.omni_range <= 2.8)
	if _rendering() and "--f7-shots" in OS.get_cmdline_user_args():
		await _frames(50)
		await _f7_shot("f7_release.png")
	for i in range(1, spots.size()):
		await _f7_stand_near(i, 1.4)
		run.reach_for_offering()
		await _frames(2)
	_check("F7: %d/%d souls released" % [sv.released_count(), spots.size()], sv.released_count() == spots.size())
	_check("F7: all souls = the village is saved, the run ends", run.state == RunGame.RunState.GAME_OVER and run.village_saved)
	var saved_label := false
	for l in run._end_screen_root.find_children("*", "Label3D", true, false):
		if (l as Label3D).text == "THE VILLAGE IS SAVED":
			saved_label = true
	_check("F7: the stele reads THE VILLAGE IS SAVED", saved_label)
	var souls_lbl := run._end_screen_root.find_child("SoulsFreedLabel", true, false) as Label3D
	_check("F7 r1: the souls row has its own line, readable and on the stele (%s)" % (souls_lbl.text if souls_lbl else "none"),
		souls_lbl != null and float(souls_lbl.font_size) * souls_lbl.pixel_size >= 0.045
		and souls_lbl.position.y - 0.025 > -0.31 and souls_lbl.text.contains("5 / 5"))
	if _rendering() and "--f7-shots" in OS.get_cmdline_user_args():
		await _frames(20)
		await _f7_shot("f7_win.png")
	await _test_f7_vessel_reads_at_8m()


## Stands the player [param meters] from vessel [param i] on its footpath side, facing it.
func _f7_stand_near(i: int, meters: float) -> void:
	var at: Vector3 = run.soul_vessels.spots[i]
	var path := run.forest_world.paths.nearest_point(Vector2(at.x, at.z), 8.0)
	var dir := Vector2(path.x - at.x, path.y - at.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2(0, 1)
	var stand := Vector3(at.x + dir.x * meters, 0.0, at.z + dir.y * meters)
	stand.y = run.forest_world.height_at(stand.x, stand.z)
	player.teleport(stand, atan2(-(at.x - stand.x), -(at.z - stand.z)))
	run.forest_world.finish_pending()
	await _frames(4)


func _f7_shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/f7"))
	player.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/f7/" + file))
	print("SHOT  docs/f7/" + file)


## Windowed only: from 8 m, with a free sight line, the vessel's wisp is the brightest,
## cool spot of its rectangle and stands clear of the forest behind it.
func _test_f7_vessel_reads_at_8m() -> void:
	if not _rendering():
		print("SKIP  F7: the soul vessel reads at 8 m (windowed only: pixels)")
		return
	_fresh_run()
	await _frames(6)
	var sv := run.soul_vessels
	var space := run.get_world_3d().direct_space_state
	var best := -1
	var stand := Vector3.ZERO
	var at := Vector3.ZERO
	for i in sv.spots.size():
		at = sv.spots[i]
		for k in 16:
			var yaw := TAU * float(k) / 16.0
			var s := at + Vector3(sin(yaw), 0.0, cos(yaw)) * 8.0
			s.y = run.forest_world.height_at(s.x, s.z)
			var q := PhysicsRayQueryParameters3D.create(s + Vector3(0, 1.6, 0), at + Vector3(0, SoulVessel.WISP_Y, 0), ForestWorld.TRUNK_LAYER)
			if space.intersect_ray(q).is_empty() and run.forest_world.is_clear_of_props(s.x, s.z, 0.6):
				best = i
				stand = s
				break
		if best >= 0:
			break
	_check("F7: some vessel has a free 8 m sight line", best >= 0)
	if best < 0:
		return
	at = sv.spots[best]
	player.teleport(stand, atan2(-(at.x - stand.x), -(at.z - stand.z)))
	run.forest_world.finish_pending()
	_look_down(4.0)
	await _frames(60)
	var v := sv.vessel(best)
	var viewport := player.get_viewport().get_visible_rect().size
	var rect := _box_rect(player.camera, Transform3D(Basis(), at), AABB(Vector3(-0.6, 0.0, -0.6), Vector3(1.2, 1.6, 1.2)), viewport)
	v.visible = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	var before := player.get_viewport().get_texture().get_image()
	if "--f7-shots" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/f7"))
		before.save_png(ProjectSettings.globalize_path("res://docs/f7/f7_before_8m.png"))
	v.visible = true
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := player.get_viewport().get_texture().get_image()
	if "--f7-shots" in OS.get_cmdline_user_args():
		img.save_png(ProjectSettings.globalize_path("res://docs/f7/f7_vessel_8m.png"))
		print("SHOT  docs/f7/f7_before_8m.png, f7_vessel_8m.png")
	var centre := Vector2(viewport) * 0.5
	var in_frame := rect.size.x >= 6 and rect.size.y >= 6
	_check("F7: 8 m: the vessel sits in the frame (%s)" % rect, in_frame)
	var glow := _bright_colour(img, rect, 0.04)
	var bg := _bright_colour(before, rect, 0.04)
	_check("F7: 8 m: the glow lifts the vessel above the forest (luma %.2f vs %.2f without it)" % [_luma(glow), _luma(bg)],
		_luma(glow) > _luma(bg) + 0.12)
	_check("F7: 8 m: the glow is cool soul-blue, not warm (hue %.0f°)" % (glow.h * 360.0),
		glow.b > glow.r and glow.h * 360.0 > 160.0 and glow.h * 360.0 < 240.0)
	_check("F7: 8 m: the vessel stands near the middle of the view", Vector2(rect.get_center()).distance_to(centre) < viewport.x * 0.3)
	# The wrist readout with the counter (desktop pins it to the camera).
	# F7 r1: at 2 m the stone keeps its texture, it is not burned white by the soul light.
	await _f7_stand_near(best, 2.0)
	_look_down(28.0)
	await _frames(30)
	await RenderingServer.frame_post_draw
	var close := player.get_viewport().get_texture().get_image()
	var srect := _box_rect(player.camera, Transform3D(Basis(), at), AABB(Vector3(-0.2, 0.05, -0.2), Vector3(0.4, 0.5, 0.4)), viewport)
	var stone_mid := _quantile_luma(close, srect, 0.5)
	var stone_hi := _quantile_luma(close, srect, 0.9)
	_check("F7 r1: 2 m: the statue is not burned white (median luma %.2f < 0.7, p90 %.2f < 0.92)" % [stone_mid, stone_hi],
		srect.size.x >= 8 and stone_mid < 0.7 and stone_hi < 0.92)
	if "--f7-shots" in OS.get_cmdline_user_args():
		await _f7_shot("f7_prompt.png")
