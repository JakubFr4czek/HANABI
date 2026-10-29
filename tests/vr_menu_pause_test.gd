extends Node
## E2d: the VR skill-tree menu and the pause around it, through the real
## XRPlayer driven by XrSim (docs/ELEMENTS_PLAN.md Phase E2d):
## - the Left Menu button opens the menu; get_tree().paused, never time_scale 0
## - while open: yōkai, element timer, cooldowns, the run clock, regeneration,
##   wave spawns and particles stand still; abilities are ignored; locomotion
##   is off — but the rig, the hand, the held katana and the pointer keep going
## - opening the menu mid-stride, with the stick deflected and a snap turn
##   running, moves neither the origin nor the body (1 mm, 0.1°) — not at the
##   opening, while paused, nor after closing (D3_fix1)
## - pointing a controller (left or right) and pulling the trigger switches
##   school, selects a node and buys it only through RunGame.unlock_skill;
##   a locked or unaffordable node is refused and costs nothing
## - closing resumes everything, the katana is still in the hand, and a
##   parry slow-mo keeps the time it had left across the pause
## - music is low-passed (750 Hz, -8 dB) while paused and restored after
##   godot --headless --path . --fixed-fps 90 res://tests/vr_menu_pause_test.tscn -- --xr-sim

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0
var run: RunGame
var xr: XRPlayer
var sim: XrSim
var origin: XROrigin3D
var menu: SkillTreeMenu
var ctl: PauseController


func _ready() -> void:
	await _run_all()
	RuntimeGuard.print_summary()
	_check("the runtime guard stayed clean (%d violations)" % RuntimeGuard.violation_count(), RuntimeGuard.violation_count() == 0)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	RuntimeGuard.reset()
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://test_vr_menu_pause_save.cfg"
	add_child(run)
	await _frames(12)
	xr = run.player as XRPlayer
	sim = get_tree().get_first_node_in_group("xr_sim") as XrSim
	_check("the XR player runs on simulated tracking", xr != null and sim != null)
	if xr == null or sim == null:
		return
	origin = xr.get_node("XROrigin3D") as XROrigin3D
	menu = run.pause_controller.menu
	ctl = run.pause_controller
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	# The sim's fist must stay closed or the holder drops the katana.
	sim.set_grip("right", 1.0)
	await _frames(3)
	if xr.right_holder.held != run.katana:
		xr.right_holder.grab(run.katana)
		run.katana.snap_to_hand()
	await _frames(3)
	_check("the run starts with the katana in the sword hand", xr.right_holder.held == run.katana)
	_check("the menu is not open at the start", not ctl.is_open and not get_tree().paused)

	await _test_menu_button_tap_toggles()
	await _test_menu_hold_recenters()
	await _test_menu_carries_the_blade_state()
	await _test_world_stands_still_rig_keeps_going()
	await _test_opening_never_moves_the_player()
	await _test_pointers_buy_only_through_run_game()
	await _test_settings_tab()
	await _test_audio_settings()
	await _test_access_and_pace()
	await _test_controls_page_matches_action_map()
	await _test_slow_motion_survives_pause()
	await _test_refused_states()
	await _test_music_ducking()
	await _test_locomotion_speed_boost()
	await _test_offering_touch_in_vr()
	_test_ui_source_has_one_spending_path()
	run.queue_free()


# --- D12. Shrine touch in VR --------------------------------------------------------

## A free hand on a shrine's offering table opens the yellow Ofuda choice; the sword
## hand does not (the blade never opens a shrine). Tracking runs on the sim's hands.
func _test_offering_touch_in_vr() -> void:
	run.start_run()
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(20)
	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	_check("the opening shrine is in the run for the VR touch test", shrine != null and shrine.lit)
	if shrine == null:
		return
	var altar := shrine.altar_position()
	xr.teleport_feet(Vector3(altar.x + 0.9, run.forest_world.height_at(altar.x + 0.9, altar.z), altar.z))
	await _frames(20)
	var sword_hand := origin.global_transform.affine_inverse() * Transform3D(Basis(), altar)
	sim.set_hand("right", sword_hand)
	await _frames(12)
	_check("the sword hand on the altar does not open the choice", not run.shrine_offering.is_open())
	sim.set_hand("right", Transform3D(sim.hand_xf["right"].basis, sim.hand_xf["right"].origin + Vector3(0.0, 0.0, -0.5)))
	var free_hand := origin.global_transform.affine_inverse() * Transform3D(Basis(), altar)
	sim.set_hand("left", free_hand)
	await _frames(12)
	_check("a free hand on the altar opens the yellow choice", run.shrine_offering.is_open())
	_check("the VR world holds still for the choice (paused, three cards)",
		get_tree().paused and get_tree().get_nodes_in_group("ofuda_talismans").size() == 3)
	# Lift the hand first: a hand still on the altar would open the choice again next frame.
	sim.set_hand("left", Transform3D(sim.hand_xf["left"].basis, sim.hand_xf["left"].origin + Vector3(0.0, 0.0, 0.6)))
	await _frames(6)
	run.shrine_offering.cancel()
	await _frames(10)
	_check("cancelling the choice resumes the world (paused %s, offering %s)" % [get_tree().paused, ctl.offering_open],
		not get_tree().paused and not ctl.offering_open)


# --- 1. Left Menu button ---------------------------------------------------------------

## Holding Left Menu for a second recentres the view once and must not open the
## menu: a hold is not a tap.
func _test_menu_hold_recenters() -> void:
	var recentered := []
	var on_log := func(e: Dictionary) -> void:
		if e.get("type") == "xr_recenter":
			recentered.append(e)
	GameEvents.event_logged.connect(on_log)
	sim.set_button("left", "menu_button", true)
	await _frames(100)  # about 1.1 s held
	sim.set_button("left", "menu_button", false)
	await _frames(6)
	GameEvents.event_logged.disconnect(on_log)
	_check("holding Left Menu for a second recentres the view", recentered.size() == 1)
	_check("a hold does not open the menu", not ctl.is_open and not menu.visible)


func _test_menu_button_tap_toggles() -> void:
	await _tap_menu_button()
	_check("tapping Left Menu opens the menu", ctl.is_open and menu.is_open)
	_check("opening pauses the tree (get_tree().paused)", get_tree().paused)
	_check("pausing never uses Engine.time_scale = 0 (%.2f)" % Engine.time_scale, Engine.time_scale > 0.99)
	_check("the menu processes while paused", menu.process_mode == Node.PROCESS_MODE_ALWAYS and menu.visible)
	await _tap_menu_button()
	_check("tapping Left Menu again closes it", not ctl.is_open and not menu.visible and not get_tree().paused)


# --- 1b. E3: nothing important lives only on the wrist plate -----------------------------

## The panel can be drawn on top of everything (no clear spot to hang it), which
## would cover the wrist plate. So the footer repeats the blade's element, the time
## left and both buttons, and the header the Ofuda: still true in that mode.
func _test_menu_carries_the_blade_state() -> void:
	var es := run.element_system
	es.imbue(Elements.SAKURA, 20.0)
	es.element_time_remaining = 9.0
	es.ability_1_cooldown = 0.0
	es.ability_2_cooldown = es.ability_cooldown_total(2) * 0.5
	run.skill_points = 5
	ctl.open()
	_check("the panel eases in rather than popping (alpha %.2f right after opening)" % menu._panel_mat.albedo_color.a,
		menu._panel_mat.albedo_color.a < 0.2)
	await _frames(30)
	_check("and is fully opaque after %.2f s" % SkillTreeMenu.FADE_IN_SECONDS, menu._panel_mat.albedo_color.a > 0.99)
	var ab: Array[Dictionary] = menu.canvas.abilities
	_check("the footer lists A and B of the blade (%s)" % [ab], ab.size() == 2
		and ab[0].glyph == Elements.ability_glyph(Elements.SAKURA, 1) and float(ab[0].ratio) >= 0.999
		and ab[1].name == "Hanamai" and absf(float(ab[1].ratio) - 0.5) < 0.03)
	_check("with the element, the seconds left and the Ofuda balance",
		menu.canvas.blade_element == Elements.SAKURA and absf(menu.canvas.blade_seconds - 9.0) < 0.1 and menu.canvas.balance == 5)
	ctl.close()
	# The same in the drawn-on-top mode (a pose with no clear spot).
	var pose := ctl._compute_pose()
	pose["blocked"] = true
	menu.open(run, pose, es.current_element, es.element_time_remaining, "")
	_check("drawn on top: the panel ignores depth and still carries the same state",
		menu.drawn_on_top and menu._panel_mat.no_depth_test and menu.canvas.abilities.size() == 2 and menu.canvas.blade_element == Elements.SAKURA)
	menu.close()
	es.reset()
	run.skill_points = 0


# --- 2. The world stands still, the rig keeps going ------------------------------------

func _test_world_stands_still_rig_keeps_going() -> void:
	var feet := xr.feet_position()
	var yokai := run.wave_director.spawn_enemy_at(feet + Vector3(0.0, 0.0, -9.0), feet)
	await _frames(70)  # let it start stalking toward the player
	_check("a yōkai is alive and approaching before the pause", is_instance_valid(yokai) and not yokai.is_dead)
	var es := run.element_system
	es.imbue(Elements.STORM)
	es.ability_1_cooldown = 0.0
	es.ability_2_cooldown = 0.0
	var fired: Array[String] = []
	es.effect_triggered.connect(func(type: String, _d: Dictionary) -> void: fired.append(type))
	var health := xr.health
	health.regen_per_sec = 10.0
	health.hp = 50.0
	var wave_before := run.wave_director.wave
	var emitter := GPUParticles3D.new()
	emitter.emitting = true
	emitter.speed_scale = 1.0
	run.add_child(emitter)
	var feet_before := xr.feet_position()
	var yaw_before := origin.global_rotation.y

	await _tap_menu_button()
	_check("the menu opened for the standing-still checks", ctl.is_open)
	var t_elem := es.element_time_remaining
	var t_run := run.run_time
	var y_pos := yokai.root_part().global_position
	var hp_open := health.hp
	# The sticks and the ability buttons are used during the pause: all ignored.
	sim.set_stick("left", Vector2(0.0, 1.0))
	sim.set_stick("right", Vector2(1.0, 0.0))
	sim.set_button("right", "ax_button", true)
	await _frames(3)
	sim.set_button("right", "ax_button", false)
	sim.set_button("right", "by_button", true)
	await _frames(3)
	sim.set_button("right", "by_button", false)
	await _frames(60)
	_check("A and B fire no ability while paused (ready abilities: %s)" % [fired],
		fired.is_empty() and es.ability_1_cooldown == 0.0 and es.ability_2_cooldown == 0.0)
	es.ability_2_cooldown = 3.0
	var t_cd := es.ability_2_cooldown
	_check("the left stick does not walk the player while paused (moved %.3f m)" % xr.feet_position().distance_to(feet_before),
		xr.feet_position().distance_to(feet_before) < 0.02)
	_check("snap turn is off while paused (%.3f rad)" % absf(origin.global_rotation.y - yaw_before),
		absf(angle_difference(origin.global_rotation.y, yaw_before)) < 0.01)
	sim.set_stick("left", Vector2.ZERO)
	sim.set_stick("right", Vector2.ZERO)
	# The player moves their head and hand physically during the pause.
	var head_before := _camera().global_position
	var hand_before := xr.right_controller.global_position
	var katana_before := run.katana.global_position
	sim.set_head(Transform3D(sim.head_xf.basis, sim.head_xf.origin + Vector3(0.4, 0.0, 0.0)))
	sim.set_hand("right", Transform3D(sim.hand_xf["right"].basis, sim.hand_xf["right"].origin + Vector3(0.0, 0.0, -0.3)))
	await _frames(30)

	_check("the element timer stands still (%.3f -> %.3f s)" % [t_elem, es.element_time_remaining],
		is_equal_approx(es.element_time_remaining, t_elem))
	_check("cooldowns stand still (%.3f -> %.3f s)" % [t_cd, es.ability_2_cooldown],
		is_equal_approx(es.ability_2_cooldown, t_cd))
	_check("the run clock stands still", is_equal_approx(run.run_time, t_run))
	_check("the yōkai stands still (moved %.4f m)" % yokai.root_part().global_position.distance_to(y_pos),
		yokai.root_part().global_position.distance_to(y_pos) < 0.001)
	_check("no wave is spawned meanwhile", run.wave_director.wave == wave_before and run.wave_director.alive_count() == 1)
	_check("regeneration waits (hp %.2f)" % health.hp, is_equal_approx(health.hp, hp_open))
	_check("particle emitters are frozen", emitter.speed_scale == 0.0)

	var head_moved := _camera().global_position.x - head_before.x
	_check("the headset keeps tracking while paused (moved %.2f m of 0.40)" % head_moved, absf(head_moved - 0.4) < 0.08)
	var hand_moved := xr.right_controller.global_position - hand_before
	_check("the controller keeps tracking while paused (moved %.2f m forward)" % -hand_moved.z, hand_moved.length() > 0.2)
	var katana_moved := run.katana.global_position - katana_before
	_check("the frozen katana rides the moving hand (hand %s, blade %s)" % [hand_moved.snapped(Vector3.ONE * 0.01), katana_moved.snapped(Vector3.ONE * 0.01)],
		katana_moved.distance_to(hand_moved) < 0.03)
	_check("the katana is held kinematic, not simulated", run.katana.freeze and xr.right_holder.held == run.katana)
	_check("the rig neither sinks nor floats while paused (feet y %.3f -> %.3f)" % [feet_before.y, xr.feet_position().y],
		absf(xr.feet_position().y - feet_before.y) < 0.03)

	await _tap_menu_button()
	_check("the menu closes again", not ctl.is_open and not get_tree().paused)
	_check("emitters are thawed", emitter.speed_scale == 1.0)
	_check("the katana is simulated again and still in the hand", not run.katana.freeze and xr.right_holder.held == run.katana)

	var t_elem2 := es.element_time_remaining
	var t_run2 := run.run_time
	var p2 := yokai.root_part().global_position
	await _frames(90)
	_check("the element timer runs again (%.2f -> %.2f s)" % [t_elem2, es.element_time_remaining], es.element_time_remaining < t_elem2 - 0.5)
	_check("the run clock runs again", run.run_time > t_run2 + 0.5)
	_check("the yōkai moves again (%.2f m)" % yokai.root_part().global_position.distance_to(p2), yokai.root_part().global_position.distance_to(p2) > 0.05)
	_check("regeneration resumes (hp %.1f)" % health.hp, health.hp > 50.5)
	es.ability_1_cooldown = 0.0
	es.execute_ability_1(Vector3.FORWARD)
	_check("abilities fire again after closing", es.ability_1_cooldown > 0.0)

	health.regen_per_sec = 0.0
	health.hp = health.max_hp
	emitter.queue_free()
	run.wave_director.clear_enemies()
	es.reset()
	sim.set_head(Transform3D(sim.head_xf.basis, sim.head_xf.origin - Vector3(0.4, 0.0, 0.0)))
	await _frames(5)


# --- 2b. Opening the menu never moves the player (D3_fix1) -----------------------------

## Walking momentum, a deflected stick and a snap turn still running must not carry
## the player through the pause. The reference is the pose the instant the menu takes
## over ("przy otwarciu"): the walk up to the press is ordinary movement and is not
## measured. Tolerance 1 mm and 0.1°.
func _test_opening_never_moves_the_player() -> void:
	var cases := [
		{"label": "walking forward", "move": Vector2(0.0, 1.0), "turn": Vector2.ZERO},
		{"label": "strafing with a snap turn running", "move": Vector2(0.7, 0.7), "turn": Vector2(1.0, 0.0)},
	]
	for c in cases:
		await _open_close_while_moving(c)
	var panel_bodies := menu.find_children("*", "CollisionObject3D", true, false)
	_check("the menu panel has no collision body (%d)" % panel_bodies.size(), panel_bodies.is_empty())


func _open_close_while_moving(c: Dictionary) -> void:
	var label: String = c.label
	sim.set_stick("left", Vector2.ZERO)
	sim.set_stick("right", Vector2.ZERO)
	await _frames(60)  # let any earlier momentum drain
	var yaw_before := origin.global_rotation.y
	sim.set_stick("left", c.move)
	sim.set_stick("right", c.turn)
	await _frames(40)
	var speed := (xr.get_node("XROrigin3D/PlayerBody") as CharacterBody3D).velocity.length()
	_check("%s: moving %.2f m/s when the press lands" % [label, speed], speed > 0.5)
	if c.turn != Vector2.ZERO:
		var turned := rad_to_deg(absf(angle_difference(yaw_before, origin.global_rotation.y)))
		_check("%s: the snap turn is running (%.0f° turned before the press)" % [label, turned], turned > 15.0)
	# The stick stays deflected through the press and the pause.
	var at_open := {}
	ctl.opened.connect(func() -> void: at_open.merge(_rig_pose()), CONNECT_ONE_SHOT)
	await _tap_menu_button()
	_check("%s: the menu is open" % label, ctl.is_open)
	await _frames(45)
	var paused := _rig_pose()
	var gap := _pose_gap(at_open, paused)
	_check("%s: the pose while paused equals the pose at opening (origin %.4f m, body %.4f m, yaw %.3f°)" % [label, gap.x, gap.y, gap.z],
		_same_pose(at_open, paused))
	# Let go of both sticks, then close: nothing may drift at the close or after it.
	sim.set_stick("left", Vector2.ZERO)
	sim.set_stick("right", Vector2.ZERO)
	var at_close := {}
	ctl.closed.connect(func() -> void: at_close.merge(_rig_pose()), CONNECT_ONE_SHOT)
	await _tap_menu_button()
	_check("%s: the menu closed" % label, not ctl.is_open and not get_tree().paused)
	_check("%s: the pose at closing equals the pose at opening" % label, _same_pose(at_open, at_close))
	await _frames(30)
	var after := _rig_pose()
	_check("%s: the pose 30 frames after closing equals the pose at opening" % label, _same_pose(at_open, after))
	_check("%s: no momentum left after the close (%.2f m/s)" % [label, (xr.get_node("XROrigin3D/PlayerBody") as CharacterBody3D).velocity.length()],
		(xr.get_node("XROrigin3D/PlayerBody") as CharacterBody3D).velocity.length() < 0.05)
	# Put the sticks back at rest for the next case.
	await _frames(60)

# --- 3. Pointing and buying ------------------------------------------------------------

func _test_pointers_buy_only_through_run_game() -> void:
	# Static Conduit (tier 1) is affordable, Thunder Splitter (tier 2) one Ofuda short after it.
	var cost1 := int(SkillTreeData.node_by_id("static_conduit").cost)
	var cost2 := int(SkillTreeData.node_by_id("thunder_splitter").cost)
	var purse := cost1 + cost2 - 1
	var left := purse - cost1
	run.skill_points = purse
	run.skill_tree.reset()
	var events: Array[String] = []
	run.skill_unlocked.connect(func(id: String) -> void: events.append(id))
	await _tap_menu_button()
	_check("the menu opens for the purchase checks", ctl.is_open)
	var c: SkillTreeCanvas = menu.canvas
	_check("the pane shows the Ofuda balance", c.balance == purse)

	# Left hand: choose Storm, then Static Conduit (tier 1), then UNLOCK.
	await _click("left", c.tab_rect(1).get_center())
	_check("left-hand trigger on the Storm tab switches school", c.element == Elements.STORM)
	await _click("left", c.node_rect(SkillTreeData.node_by_id("static_conduit")).get_center())
	_check("clicking a node selects it", c.selected_id == "static_conduit")
	await _click("left", SkillTreeCanvas.UNLOCK_RECT.get_center())
	_check("UNLOCK buys through RunGame.unlock_skill (signal %s)" % [events],
		events == ["static_conduit"] and run.skill_tree.is_unlocked("static_conduit"))
	_check("the cost left the wallet (%d -> %d) and the pane follows" % [purse, run.skill_points], run.skill_points == left and c.balance == left)

	# Right hand: a locked node is refused and costs nothing.
	await _click("right", c.node_rect(SkillTreeData.node_by_id("ikazuchi_avatar")).get_center())
	_check("the right-hand pointer selects too", c.selected_id == "ikazuchi_avatar")
	await _click("right", SkillTreeCanvas.UNLOCK_RECT.get_center())
	_check("a locked node cannot be bought (still %d Ofuda)" % run.skill_points,
		not run.skill_tree.is_unlocked("ikazuchi_avatar") and run.skill_points == left and c.status_text != "")
	# Affordability: Thunder Splitter costs one more Ofuda than we hold.
	await _click("right", c.node_rect(SkillTreeData.node_by_id("thunder_splitter")).get_center())
	await _click("right", SkillTreeCanvas.UNLOCK_RECT.get_center())
	_check("an unaffordable node is refused without charge",
		not run.skill_tree.is_unlocked("thunder_splitter") and run.skill_points == left)
	var spec := c.button_spec("thunder_splitter")
	_check("the button reads how many Ofuda are missing (%s)" % spec.label, spec.mode == "poor" and "1" in String(spec.label))
	_check("only the one legitimate purchase was signalled", events == ["static_conduit"])

	# The pointer draws a beam and a reticle and buzzes on hover.
	_check("a pointer on the panel shows its reticle", (menu.get_node("Reticle_left") as Node3D).visible or (menu.get_node("Reticle_right") as Node3D).visible)
	var buzzes := [0]
	menu.haptic_sink = func(_id: String, _a: float, _d: float) -> void: buzzes[0] += 1
	await _aim("left", c.tab_rect(0).get_center())
	await _aim("left", c.tab_rect(2).get_center())
	_check("hovering a new target pulses the hand (%d pulses)" % buzzes[0], buzzes[0] >= 1)
	menu.haptic_sink = ctl._haptic

	await _release_triggers()
	await _tap_menu_button()
	_check("the menu closes after shopping", not ctl.is_open)
	_check("the purchase is live in the ability (Static Conduit: imbue 24 s)", _imbue_seconds(Elements.STORM) == 24.0)
	run.skill_points = 0
	run.skill_tree.reset()
	run.element_system.reset()


# --- 4b. SETTINGS tab (comfort, audio, access, controls) ----------------------------------

## Settings the tests change are saved to the player's real hanabi_vr.cfg: keep
## a copy and put it back, so a test run never leaves the headset tuned.
func _backup_settings_file() -> Dictionary:
	var had := FileAccess.file_exists(VrComfortSettings.SETTINGS_PATH)
	var content := ""
	if had:
		var fa := FileAccess.open(VrComfortSettings.SETTINGS_PATH, FileAccess.READ)
		if fa:
			content = fa.get_as_text()
			fa.close()
	return {"had": had, "content": content}


func _restore_settings_file(backup: Dictionary) -> void:
	if backup.had:
		var fw := FileAccess.open(VrComfortSettings.SETTINGS_PATH, FileAccess.WRITE)
		if fw:
			fw.store_string(backup.content)
			fw.close()
	else:
		DirAccess.remove_absolute(VrComfortSettings.SETTINGS_PATH)
	VrComfortSettings.load_settings()
	VrComfortSettings.apply_to_player(xr)


## Opens the menu on the SETTINGS tab; returns the canvas.
func _open_settings() -> SkillTreeCanvas:
	VrComfortSettings.reset_to_defaults(xr)
	await _tap_menu_button()
	var c: SkillTreeCanvas = menu.canvas
	await _click("left", c.tab_rect(4).get_center())
	return c


func _click_page(key: String) -> void:
	await _click("left", (SkillTreeCanvas.SUBNAV_RECTS[key] as Rect2).get_center())


func _test_settings_tab() -> void:
	var backup := _backup_settings_file()
	var c := await _open_settings()
	_check("clicking tab 4 switches to settings", c.is_settings_tab)
	_check("the settings tab opens on AUDIO", c.settings_page == SkillTreeCanvas.PAGE_AUDIO)
	# The settings tab is part of the pause: the run clock stands still while it is open.
	var t_run := run.run_time
	await _frames(30)
	_check("the settings tab keeps the world paused (run clock %.3f -> %.3f)" % [t_run, run.run_time],
		get_tree().paused and is_equal_approx(run.run_time, t_run))

	# 1. Vignette toggle & strength
	await _click_page("page_move")
	_check("the MOVEMENT page is showing", c.settings_page == SkillTreeCanvas.PAGE_MOVE)
	await _click("left", c.settings_rect("vignette_off").get_center())
	_check("clicking DISABLED turns vignette off", not VrComfortSettings.vignette_enabled)
	var vig: Node = xr._get_vignette()
	var vig_mesh: Node = vig.get_node_or_null("Mesh") if vig else null
	_check("vignette node disabled auto_adjust", vig != null and not bool(vig.get("auto_adjust")))
	_check("vignette mesh hidden when disabled", vig_mesh != null and not bool(vig_mesh.get("visible")))

	await _click("left", c.settings_rect("vignette_on").get_center())
	_check("clicking ENABLED turns vignette on", VrComfortSettings.vignette_enabled)
	_check("vignette node enabled auto_adjust", vig != null and bool(vig.get("auto_adjust")))
	_check("vignette mesh shown when enabled", vig_mesh != null and bool(vig_mesh.get("visible")))

	await _click("left", c.settings_rect("vignette_75").get_center())
	_check("clicking 75% sets strength to 0.75", absf(VrComfortSettings.vignette_strength - 0.75) < 0.01)

	# 2. Turning mode, speeds and walking pace
	var turn: Node = xr._get_movement_turn()
	await _click("right", c.settings_rect("turn_smooth").get_center())
	_check("clicking SMOOTH sets smooth turn mode", not VrComfortSettings.snap_turning and int(turn.get("turn_mode")) == 2)

	await _click("right", c.settings_rect("smooth_30").get_center())
	_check("clicking 3.0 sets smooth speed to 3.0", absf(VrComfortSettings.smooth_turn_speed - 3.0) < 0.01 and absf(float(turn.get("smooth_turn_speed")) - 3.0) < 0.01)

	await _click("right", c.settings_rect("turn_snap").get_center())
	_check("clicking SNAP sets snap turn mode", VrComfortSettings.snap_turning and int(turn.get("turn_mode")) == 1)

	await _click("right", c.settings_rect("snap_60").get_center())
	_check("clicking 60° sets snap angle to 60.0", absf(VrComfortSettings.snap_angle - 60.0) < 0.01 and absf(float(turn.get("step_turn_angle")) - 60.0) < 0.01)

	# 3. Dominant hand: the swap is on CONTROLS, where the diagram follows it.
	await _click_page("page_controls")
	await _click("left", c.settings_rect("hand_left").get_center())
	_check("dominant hand swapped to left", VrComfortSettings.dominant_hand == "left" and xr.dominant_hand == "left")
	_check("left holder is now dominant weapon hand", xr.get_dominant_holder() == xr.left_holder)
	_check("movement direct reparented to right controller", xr._get_movement_direct().get_parent() == xr.right_controller)
	_check("movement turn reparented to left controller", xr._get_movement_turn().get_parent() == xr.left_controller)
	_check("turn controller for height adjust is left controller when southpaw", xr._get_turn_controller() == xr.left_controller)
	if run.diegetic_hud and run.diegetic_hud.wrist_unit:
		_check("wrist HUD plate moved to off-hand (right controller)", run.diegetic_hud.wrist_unit.get_parent() == xr.right_controller)

	await _click("left", c.settings_rect("hand_right").get_center())
	_check("dominant hand swapped back to right", VrComfortSettings.dominant_hand == "right" and xr.dominant_hand == "right")
	_check("right holder is dominant weapon hand", xr.get_dominant_holder() == xr.right_holder)
	_check("movement direct back on left controller", xr._get_movement_direct().get_parent() == xr.left_controller)
	_check("movement turn back on right controller", xr._get_movement_turn().get_parent() == xr.right_controller)
	_check("turn controller for height adjust is right controller when right-dominant", xr._get_turn_controller() == xr.right_controller)
	if run.diegetic_hud and run.diegetic_hud.wrist_unit:
		_check("wrist HUD plate back on left controller", run.diegetic_hud.wrist_unit.get_parent() == xr.left_controller)

	# 4. Seated mode & height
	await _click_page("page_move")
	await _click("right", c.settings_rect("seated_on").get_center())
	_check("seated mode enabled", VrComfortSettings.seated_mode and VrComfortSettings.height_offset >= 0.20)
	var body_h: float = float(xr._body().get("player_height_offset"))
	_check("player body height offset applied (%.2f m)" % body_h, absf(body_h - VrComfortSettings.height_offset) < 0.01)
	await _frames(8)

	var h_before := VrComfortSettings.height_offset
	await _click("right", c.settings_rect("height_plus").get_center())
	_check("height plus adjusts by +5 cm (%.2f -> %.2f)" % [h_before, VrComfortSettings.height_offset], absf(VrComfortSettings.height_offset - (h_before + 0.05)) < 0.01)

	await _click("right", c.settings_rect("seated_off").get_center())
	_check("standing mode restored", not VrComfortSettings.seated_mode)

	await _click("right", c.settings_rect("height_reset").get_center())
	_check("height reset to 0.00 m", absf(VrComfortSettings.height_offset) < 0.01)

	# 5. Persistence verification
	var cfg := ConfigFile.new()
	var err := cfg.load(VrComfortSettings.SETTINGS_PATH)
	_check("user://hanabi_vr.cfg loaded successfully", err == OK)
	_check("vignette_enabled saved in cfg", cfg.get_value("comfort", "vignette_enabled", false) == true)
	_check("vignette_strength saved in cfg", absf(float(cfg.get_value("comfort", "vignette_strength", 0.0)) - 0.75) < 0.01)
	_check("snap_angle saved in cfg", absf(float(cfg.get_value("comfort", "snap_angle", 0.0)) - 60.0) < 0.01)
	_check("dominant_hand saved in cfg", String(cfg.get_value("comfort", "dominant_hand", "")) == "right")

	# 6. Back to the element tabs; the pause ends with the menu.
	await _click("left", c.tab_rect(0).get_center())
	_check("clicking tab 0 returns to Sakura tree", not c.is_settings_tab and c.element == Elements.SAKURA)

	await _release_triggers()
	await _tap_menu_button()
	_check("the menu closes cleanly after settings checks", not ctl.is_open and not get_tree().paused)
	_restore_settings_file(backup)


func _test_audio_settings() -> void:
	var backup := _backup_settings_file()
	var c := await _open_settings()
	await _click_page("page_audio")
	var master := AudioServer.get_bus_index("Master")
	var music := AudioServer.get_bus_index(Sfx.MUSIC_BUS)
	var world := AudioServer.get_bus_index(Sfx.WORLD_BUS)
	var ambience := AudioServer.get_bus_index(Sfx.AMBIENCE_BUS)

	await _click("left", c.settings_rect("vol_music_dn").get_center())
	_check("MUSIC down steps to 90%% (%d)" % VrComfortSettings.audio_percent["music"], VrComfortSettings.audio_percent["music"] == 90)
	for _i in 5:
		await _click("left", c.settings_rect("vol_master_dn").get_center())
	_check("MASTER five steps down reaches 50%% (%d)" % VrComfortSettings.audio_percent["master"], VrComfortSettings.audio_percent["master"] == 50)
	for _i in 2:
		await _click("left", c.settings_rect("vol_sfx_dn").get_center())
	await _click("left", c.settings_rect("vol_ambience_dn").get_center())
	await _frames(40)  # the pause duck fades in over 0.25 s
	# While the menu is open the pause duck (-8 dB on Music) still applies on top of the volume.
	_check("MUSIC bus reads 90%% and the pause duck (%.2f dB, want %.2f)" % [AudioServer.get_bus_volume_db(music), linear_to_db(0.9) - 8.0],
		absf(AudioServer.get_bus_volume_db(music) - (linear_to_db(0.9) - 8.0)) < 0.3)

	# Bounds and 10 % snapping, without the pointer.
	VrComfortSettings.set_volume_percent("sfx", 150)
	_check("SFX above 100%% stops at 100%% (%d)" % VrComfortSettings.audio_percent["sfx"], VrComfortSettings.audio_percent["sfx"] == 100)
	VrComfortSettings.set_volume_percent("ambience", -30)
	_check("Ambience below 0%% stops at 0%% (%d)" % VrComfortSettings.audio_percent["ambience"], VrComfortSettings.audio_percent["ambience"] == 0)
	VrComfortSettings.set_volume_percent("ambience", 90)
	VrComfortSettings.set_volume_percent("sfx", 80)
	_check("the buses follow the values (SFX %.2f dB)" % AudioServer.get_bus_volume_db(world), absf(AudioServer.get_bus_volume_db(world) - linear_to_db(0.8)) < 0.3)

	await _release_triggers()
	await _tap_menu_button()
	await _frames(40)
	_check("closing the menu leaves the chosen levels (Master %.2f, Music %.2f, SFX %.2f, Ambience %.2f dB)" % [
			AudioServer.get_bus_volume_db(master), AudioServer.get_bus_volume_db(music),
			AudioServer.get_bus_volume_db(world), AudioServer.get_bus_volume_db(ambience)],
		absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.5)) < 0.3
		and absf(AudioServer.get_bus_volume_db(music) - linear_to_db(0.9)) < 0.3
		and absf(AudioServer.get_bus_volume_db(world) - linear_to_db(0.8)) < 0.3
		and absf(AudioServer.get_bus_volume_db(ambience) - linear_to_db(0.9)) < 0.3)

	# Survives a save and a reload: forget the values in memory, then load the file.
	var cfg := ConfigFile.new()
	cfg.load(VrComfortSettings.SETTINGS_PATH)
	_check("the [audio] section is saved (master %s, music %s, sfx %s, ambience %s)" % [
			cfg.get_value("audio", "master"), cfg.get_value("audio", "music"),
			cfg.get_value("audio", "sfx"), cfg.get_value("audio", "ambience")],
		int(cfg.get_value("audio", "master", -1)) == 50 and int(cfg.get_value("audio", "music", -1)) == 90
		and int(cfg.get_value("audio", "sfx", -1)) == 80 and int(cfg.get_value("audio", "ambience", -1)) == 90)
	for key in VrComfortSettings.AUDIO_KEYS:
		VrComfortSettings.audio_percent[key] = 100
	VrComfortSettings.apply_audio()
	VrComfortSettings.load_settings()
	_check("loading the file restores the volumes (master %d, music %d, sfx %d, ambience %d)" % [
			VrComfortSettings.audio_percent["master"], VrComfortSettings.audio_percent["music"],
			VrComfortSettings.audio_percent["sfx"], VrComfortSettings.audio_percent["ambience"]],
		VrComfortSettings.audio_percent == {"master": 50, "music": 90, "sfx": 80, "ambience": 90}
		and absf(AudioServer.get_bus_volume_db(music) - linear_to_db(0.9)) < 0.3)
	_restore_settings_file(backup)


func _test_access_and_pace() -> void:
	var backup := _backup_settings_file()
	var c := await _open_settings()

	# Photosensitivity: OFF drops the firework lamp and keeps the sparks.
	await _click_page("page_access")
	await _click("left", c.settings_rect("flash_50").get_center())
	_check("SOFT 50 %% stores a flash scale of 0.5 (%.2f)" % VrComfortSettings.flash_scale(), absf(VrComfortSettings.flash_scale() - 0.5) < 0.001)
	await _click("left", c.settings_rect("flash_100").get_center())
	await _frames(40)  # earlier lamps fade within 0.16 s
	var lamps := func() -> int: return run.find_children("FireworkFlash", "OmniLight3D", true, false).size()
	var before: int = lamps.call()
	VfxPool.spawn_firework_flash(run, xr.feet_position() + Vector3(0.0, 2.0, -3.0), Color(1.0, 0.5, 0.6), 1.0)
	_check("FULL flash keeps the firework lamp (%d new)" % (int(lamps.call()) - before), int(lamps.call()) == before + 1)
	await _click("left", c.settings_rect("flash_0").get_center())
	await _frames(40)
	before = lamps.call()
	VfxPool.spawn_firework_flash(run, xr.feet_position() + Vector3(0.0, 2.0, -3.0), Color(1.0, 0.5, 0.6), 1.0)
	_check("OFF flash drops the lamp and keeps the sparks (%d new)" % (int(lamps.call()) - before), int(lamps.call()) == before)

	# Haptics: the strength scales every pulse; OFF is silent.
	await _click("left", c.settings_rect("haptic_50").get_center())
	xr.right_holder.pulse(1.0, 0.05)
	_check("HALF 50 %% sends half the amplitude (%.2f)" % xr.right_holder.last_pulse_amplitude, absf(xr.right_holder.last_pulse_amplitude - 0.5) < 0.001)
	await _click("left", c.settings_rect("haptic_0").get_center())
	xr.right_holder.pulse(1.0, 0.05)
	_check("OFF sends no vibration (%.2f)" % xr.right_holder.last_pulse_amplitude, xr.right_holder.last_pulse_amplitude == 0.0)
	await _click("left", c.settings_rect("haptic_100").get_center())
	await _click("left", c.settings_rect("haptic_test").get_center())
	_check("TEST pulses the katana hand at full strength (%.2f)" % xr.right_holder.last_pulse_amplitude, absf(xr.right_holder.last_pulse_amplitude - 0.6) < 0.001)

	# Walking pace stacks with the ink boost and is saved.
	await _click_page("page_move")
	await _click("left", c.settings_rect("walk_normal").get_center())
	var base := xr.get_move_speed()
	await _click("left", c.settings_rect("walk_fast").get_center())
	_check("FAST walks at 1.3x the default pace (%.2f -> %.2f)" % [base, xr.get_move_speed()], absf(xr.get_move_speed() - base * 1.3) < 0.01)
	run.apply_locomotion_speed(1.2)
	_check("the ink boost stacks on top of the pace (%.2f)" % xr.get_move_speed(), absf(xr.get_move_speed() - base * 1.3 * 1.2) < 0.01)
	run.apply_locomotion_speed(1.0)
	await _click("left", c.settings_rect("walk_slow").get_center())
	_check("SLOW walks at 0.7x (%.2f)" % xr.get_move_speed(), absf(xr.get_move_speed() - base * 0.7) < 0.01)
	var cfg := ConfigFile.new()
	cfg.load(VrComfortSettings.SETTINGS_PATH)
	_check("the pace and the access levels are saved", absf(float(cfg.get_value("comfort", "walk_scale", 0.0)) - 0.7) < 0.001
		and int(cfg.get_value("access", "flash_percent", -1)) == 0 and int(cfg.get_value("access", "haptic_percent", -1)) == 100)

	await _release_triggers()
	await _tap_menu_button()
	_restore_settings_file(backup)
	await _frames(5)


func _test_controls_page_matches_action_map() -> void:
	var backup := _backup_settings_file()
	var c := await _open_settings()
	await _click_page("page_controls")
	await _frames(2)

	# Expected: every binding and action name of the Quest profile in the action map.
	var expected_bindings := {}
	var expected_actions := {}
	for b: Dictionary in ControlsMap.bindings():
		expected_bindings[b.path] = true
		expected_actions[b.action] = true
	var drawn_bindings := {}
	for p in c.drawn_bindings:
		drawn_bindings[p] = true
	var drawn_actions := {}
	for a in c.drawn_actions:
		drawn_actions[a] = true
	_check("the controls page draws every binding of the action map (%d of %d)" % [drawn_bindings.size(), expected_bindings.size()],
		_same_keys(expected_bindings, drawn_bindings) and not expected_bindings.is_empty())
	_check("and every action by name (%d of %d)" % [drawn_actions.size(), expected_actions.size()],
		_same_keys(expected_actions, drawn_actions))
	_check("nothing in the action map is left unplaced (%s)" % [ControlsMap.layout("right").unmapped], ControlsMap.layout("right").unmapped.is_empty())
	var game_uses := ["ax_button", "by_button", "trigger", "grip", "primary", "menu_button"]
	var missing: Array[String] = []
	for n in game_uses:
		if not drawn_actions.has(n):
			missing.append(n)
	_check("the buttons the game reads are all drawn (missing %s)" % [missing], missing.is_empty())
	_check("the Meta button is drawn and marked as the system's", c.drawn_callouts.any(
		func(d: Dictionary) -> bool: return d.slot == "top_button" and d.side == "right" and String(d.title).begins_with("META")))

	# Dominant hand: the drawing follows the swap.
	await _click("left", c.settings_rect("hand_left").get_center())
	await _frames(2)
	var roles: Dictionary = ControlsMap.layout(VrComfortSettings.dominant_hand).roles
	_check("swapped: the katana is in the left hand, the wrist HUD on the right (katana %s, HUD %s)" % [roles.katana, roles.hud],
		roles.katana == "left" and roles.hud == "right")
	_check("swapped: the drawn right stick walks (%s)" % _drawn_callout("right", "stick"), _drawn_callout("right", "stick").begins_with("Walk"))
	_check("swapped: the drawn left stick turns (%s)" % _drawn_callout("left", "stick"), _drawn_callout("left", "stick").begins_with("Turn"))
	await _click("left", c.settings_rect("hand_right").get_center())
	await _frames(2)
	_check("back to right: the drawn right stick turns again (%s)" % _drawn_callout("right", "stick"), _drawn_callout("right", "stick").begins_with("Turn"))

	await _release_triggers()
	await _tap_menu_button()
	_restore_settings_file(backup)


## The body text of the drawn callout for [param side] and [param slot] ("" if none).
func _drawn_callout(side: String, slot: String) -> String:
	for d: Dictionary in menu.canvas.drawn_callouts:
		if d.side == side and d.slot == slot:
			return String(d.body)
	return ""


func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	return a.size() == b.size() and a.keys().all(func(k: Variant) -> bool: return b.has(k))


# --- 5. Slow-mo state survives ---------------------------------------------------------

func _test_slow_motion_survives_pause() -> void:
	TimeController.slow_motion(0.3, 2.0, true)
	await _frames(2)
	_check("a parry slow-mo is running (Engine %.2f)" % Engine.time_scale, absf(Engine.time_scale - 0.3) < 0.01)
	await _tap_menu_button()
	_check("opening during slow-mo parks it (Engine.time_scale %.2f)" % Engine.time_scale, absf(Engine.time_scale - 1.0) < 0.01)
	_check("the slow-mo effect is remembered (%.2f)" % TimeController.time_scale, absf(TimeController.time_scale - 0.3) < 0.01 and TimeController.is_active("slow_motion"))
	await _frames(270)  # 3 s: longer than the effect had left
	_check("the slow-mo does not expire while paused", TimeController.is_active("slow_motion"))
	await _tap_menu_button()
	_check("closing restores the exact slow-mo (Engine %.2f)" % Engine.time_scale, absf(Engine.time_scale - 0.3) < 0.01)
	await _frames(150)  # ~1.7 s of its 2 s are used up, minus the 2 frames before the pause
	_check("it still has time left after the pause (≈0.3 s)", TimeController.is_active("slow_motion"))
	await _frames(60)
	_check("and then ends normally", not TimeController.is_active("slow_motion") and absf(Engine.time_scale - 1.0) < 0.01)


# --- 6. The menu only opens mid-fight --------------------------------------------------

func _test_refused_states() -> void:
	for st in [RunGame.RunState.INTRO, RunGame.RunState.GAME_OVER]:
		run.state = st
		await _tap_menu_button()
		_check("the menu does not open in state %d" % st, not ctl.is_open and not get_tree().paused)
	run.state = RunGame.RunState.PLAYING
	# A run that ends under an open menu closes it.
	await _tap_menu_button()
	_check("open again in PLAYING", ctl.is_open)
	run._on_player_died()
	await _frames(3)
	_check("death closes the menu and unpauses", not ctl.is_open and not get_tree().paused)
	run.start_run()
	await _frames(5)
	run.state = RunGame.RunState.PLAYING
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()


# --- 7. Audio atmosphere ---------------------------------------------------------------

func _test_music_ducking() -> void:
	await _frames(40)  # let any earlier pause fade finish
	var bus := AudioServer.get_bus_index(Sfx.MUSIC_BUS)
	var base_db := AudioServer.get_bus_volume_db(bus)
	await _tap_menu_button()
	await _frames(40)  # the fade is 0.25 s
	var lp: AudioEffectLowPassFilter = null
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			lp = AudioServer.get_bus_effect(bus, i)
	_check("a low-pass sits on the Music bus", lp != null)
	if lp:
		_check("paused music is low-passed to 750 Hz (%.0f)" % lp.cutoff_hz, absf(lp.cutoff_hz - 750.0) < 20.0)
	var ducked_db := AudioServer.get_bus_volume_db(bus)
	_check("paused music is ducked 8 dB (%.1f -> %.1f)" % [base_db, ducked_db], absf((base_db - ducked_db) - 8.0) < 0.3)
	var amb := AudioServer.get_bus_index(Sfx.AMBIENCE_BUS)
	_check("ambience is ducked on the same bus rules", amb >= 0)
	_check("the music keeps playing (node processes while paused)",
		run.get_node("StormMusic").process_mode == Node.PROCESS_MODE_ALWAYS)
	await _tap_menu_button()
	await _frames(40)
	if lp:
		_check("closing opens the filter again (%.0f Hz)" % lp.cutoff_hz, lp.cutoff_hz > 15000.0)
	_check("closing restores the music level (%.1f dB)" % AudioServer.get_bus_volume_db(bus), absf(AudioServer.get_bus_volume_db(bus) - base_db) < 0.3)


# --- 8. Abyssal Sea speed on the XR rig -------------------------------------------------

func _test_locomotion_speed_boost() -> void:
	var es := run.element_system
	var base_speed := xr.get_move_speed()
	run.apply_locomotion_speed(1.2)
	_check("the XR rig walks 20%% faster with Abyssal Sea (%.2f -> %.2f)" % [base_speed, xr.get_move_speed()],
		absf(xr.get_move_speed() - base_speed * 1.2) < 0.01)
	run.apply_locomotion_speed(1.0)
	_check("and back to normal outside the ink (%.2f)" % xr.get_move_speed(), absf(xr.get_move_speed() - base_speed) < 0.01)
	# End to end: ink pool at the feet + the Abyssal node => multiplier read by RunGame.
	run.skill_tree.reset()
	for id in ["sumi_mastery", "splatter_tide", "dragon_calligraphy", "abyssal_sea"]:
		run.skill_tree.try_unlock(id, 99)
	es.reset()
	es.imbue(Elements.INK)
	es.ability_1_cooldown = 0.0
	es.execute_ability_1(Vector3.FORWARD)
	await _frames(3)
	var standing_in_ink := es.abyssal_in_ink
	if not standing_in_ink and not es._ink_pools.is_empty():
		# Step into the pool wherever the cone put it.
		es._ink_pools[0].position = es._player_origin()
		await _frames(3)
	_check("standing in own ink raises the multiplier (%.2f)" % es.get_player_speed_multiplier(), es.abyssal_in_ink and es.get_player_speed_multiplier() > 1.19)
	await _frames(3)
	_check("RunGame hands that to the XR locomotion (%.2f vs base %.2f)" % [xr.get_move_speed(), base_speed],
		absf(xr.get_move_speed() - base_speed * 1.2) < 0.01)
	# The ward is brief, not permanent immunity.
	xr.health._invulnerable = 0.0
	var ward_hit_a := xr.health.take_hit(1.0, xr.feet_position())
	_check("stepping onto the ink wards the first hit window (refused: %s)" % [not ward_hit_a], not ward_hit_a)
	await _frames(60)  # 0.67 s: the 0.5 s ward is over, although we still stand in the ink
	xr.health._invulnerable = 0.0
	var hp0 := xr.health.hp
	xr.health.take_hit(5.0, xr.feet_position())
	_check("standing in ink longer than 0.5 s no longer blocks damage (hp %.1f -> %.1f)" % [hp0, xr.health.hp], xr.health.hp < hp0)
	es.reset()
	run.skill_tree.reset()
	run.apply_locomotion_speed(1.0)
	xr.health.heal_full()


# --- 9. One door for spending ----------------------------------------------------------

func _test_ui_source_has_one_spending_path() -> void:
	var offenders: Array[String] = []
	for f in DirAccess.get_files_at("res://src/ui"):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://src/ui/" + f)
		if "try_unlock(" in src or "skill_points -=" in src or "skill_points =" in src or "add_points(" in src:
			offenders.append(f)
	_check("UI code never touches the wallet or tree directly (%s)" % [offenders], offenders.is_empty())


# --- Helpers ---------------------------------------------------------------------------

func _imbue_seconds(element: String) -> float:
	var es := run.element_system
	es.imbue(element)
	return es.element_time_remaining


func _camera() -> Node3D:
	return xr.get_node("XROrigin3D/XRCamera3D") as Node3D


## Where the rig stands: the XR origin and the physics body, with their yaw.
func _rig_pose() -> Dictionary:
	var body := xr.get_node("XROrigin3D/PlayerBody") as Node3D
	return {"origin": origin.global_position, "body": body.global_position,
		"origin_yaw": origin.global_rotation.y, "body_yaw": body.global_rotation.y}


## Gaps between two rig poses: (origin m, body m, yaw degrees, the larger of origin and body yaw).
func _pose_gap(a: Dictionary, b: Dictionary) -> Vector3:
	return Vector3(
		(a.origin as Vector3).distance_to(b.origin),
		(a.body as Vector3).distance_to(b.body),
		rad_to_deg(maxf(absf(angle_difference(a.origin_yaw, b.origin_yaw)), absf(angle_difference(a.body_yaw, b.body_yaw)))))


func _same_pose(a: Dictionary, b: Dictionary) -> bool:
	var gap := _pose_gap(a, b)
	return gap.x < 0.001 and gap.y < 0.001 and gap.z < 0.1


func _tap_menu_button() -> void:
	sim.set_button("left", "menu_button", true)
	await _frames(6)  # 0.07 s: a tap
	sim.set_button("left", "menu_button", false)
	await _frames(6)


## Aims a hand at canvas pixel [param px] of the open panel.
func _aim(side: String, px: Vector2) -> void:
	var c := xr.left_controller if side == "left" else xr.right_controller
	for _i in 30:
		var target := menu.canvas_to_world(px)
		var head := _camera().global_position
		var sign_x := -1.0 if side == "left" else 1.0
		var hand_world := head + Vector3(0.22 * sign_x, -0.35, 0.0) + (target - head).normalized() * 0.35
		var basis := Basis.looking_at((target - hand_world).normalized(), Vector3.UP)
		var local := origin.global_transform.affine_inverse() * Transform3D(basis, hand_world)
		sim.set_hand(side, local)
		await _frames(2)
		if c:
			var hit := menu.ray_to_canvas(c.global_position, -c.global_basis.z)
			# Settle on the target, not at its rim: a 50 px button leaves no room for drift.
			if not hit.is_empty() and (hit.canvas as Vector2).distance_to(px) < 6.0:
				break


func _click(side: String, px: Vector2) -> void:
	sim.set_trigger(side, 0.0)
	await _aim(side, px)
	if OS.get_cmdline_user_args().has("--debug-click"):
		print("    click %s at %s hover %s ray %s" % [side, px, menu.pointer_hover(side), menu.ray_to_canvas(xr.left_controller.global_position if side == "left" else xr.right_controller.global_position, -(xr.left_controller if side == "left" else xr.right_controller).global_basis.z)])
	sim.set_trigger(side, 1.0)
	await _frames(4)
	sim.set_trigger(side, 0.0)
	await _frames(4)


func _release_triggers() -> void:
	sim.set_trigger("left", 0.0)
	sim.set_trigger("right", 0.0)
	await _frames(2)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
