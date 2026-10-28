extends Node
## E2d: the VR skill-tree menu and the pause around it, through the real
## XRPlayer driven by XrSim (docs/ELEMENTS_PLAN.md Phase E2d):
## - the Left Menu button opens the menu; get_tree().paused, never time_scale 0
## - while open: yōkai, element timer, cooldowns, the run clock, regeneration,
##   wave spawns and particles stand still; abilities are ignored; locomotion
##   is off — but the rig, the hand, the held katana and the pointer keep going
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
	await _test_menu_carries_the_blade_state()
	await _test_world_stands_still_rig_keeps_going()
	await _test_pointers_buy_only_through_run_game()
	await _test_comfort_settings_tab()
	await _test_slow_motion_survives_pause()
	await _test_refused_states()
	await _test_music_ducking()
	await _test_locomotion_speed_boost()
	_test_ui_source_has_one_spending_path()
	run.queue_free()


# --- 1. Left Menu button ---------------------------------------------------------------

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
	run.ofuda_count = 5
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
	run.ofuda_count = 0


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


# --- 3. Pointing and buying ------------------------------------------------------------

func _test_pointers_buy_only_through_run_game() -> void:
	# Static Conduit (tier 1) is affordable, Thunder Splitter (tier 2) one Ofuda short after it.
	var cost1 := int(SkillTreeData.node_by_id("static_conduit").cost)
	var cost2 := int(SkillTreeData.node_by_id("thunder_splitter").cost)
	var purse := cost1 + cost2 - 1
	var left := purse - cost1
	run.ofuda_count = purse
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
	_check("the cost left the wallet (%d -> %d) and the pane follows" % [purse, run.ofuda_count], run.ofuda_count == left and c.balance == left)

	# Right hand: a locked node is refused and costs nothing.
	await _click("right", c.node_rect(SkillTreeData.node_by_id("ikazuchi_avatar")).get_center())
	_check("the right-hand pointer selects too", c.selected_id == "ikazuchi_avatar")
	await _click("right", SkillTreeCanvas.UNLOCK_RECT.get_center())
	_check("a locked node cannot be bought (still %d Ofuda)" % run.ofuda_count,
		not run.skill_tree.is_unlocked("ikazuchi_avatar") and run.ofuda_count == left and c.status_text != "")
	# Affordability: Thunder Splitter costs one more Ofuda than we hold.
	await _click("right", c.node_rect(SkillTreeData.node_by_id("thunder_splitter")).get_center())
	await _click("right", SkillTreeCanvas.UNLOCK_RECT.get_center())
	_check("an unaffordable node is refused without charge",
		not run.skill_tree.is_unlocked("thunder_splitter") and run.ofuda_count == left)
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
	run.ofuda_count = 0
	run.skill_tree.reset()
	run.element_system.reset()


# --- 4b. VR Comfort settings ------------------------------------------------------------

func _test_comfort_settings_tab() -> void:
	# Backup existing hanabi_vr.cfg if it exists
	var original_cfg_content := ""
	var had_original_cfg := FileAccess.file_exists(VrComfortSettings.SETTINGS_PATH)
	if had_original_cfg:
		var fa := FileAccess.open(VrComfortSettings.SETTINGS_PATH, FileAccess.READ)
		if fa:
			original_cfg_content = fa.get_as_text()
			fa.close()

	VrComfortSettings.reset_to_defaults(xr)
	await _tap_menu_button()
	_check("the menu opens for comfort checks", ctl.is_open)
	var c: SkillTreeCanvas = menu.canvas

	# Click Comfort tab (tab index 4)
	await _click("left", c.tab_rect(4).get_center())
	_check("clicking tab 4 switches to comfort settings", c.is_comfort_tab)

	# 1. Vignette toggle & strength
	await _click("left", c.comfort_rect("vignette_off").get_center())
	_check("clicking DISABLED turns vignette off", not VrComfortSettings.vignette_enabled)
	var vig: Node = xr._get_vignette()
	var vig_mesh: Node = vig.get_node_or_null("Mesh") if vig else null
	_check("vignette node disabled auto_adjust", vig != null and not bool(vig.get("auto_adjust")))
	_check("vignette mesh hidden when disabled", vig_mesh != null and not bool(vig_mesh.get("visible")))

	await _click("left", c.comfort_rect("vignette_on").get_center())
	_check("clicking ENABLED turns vignette on", VrComfortSettings.vignette_enabled)
	_check("vignette node enabled auto_adjust", vig != null and bool(vig.get("auto_adjust")))
	_check("vignette mesh shown when enabled", vig_mesh != null and bool(vig_mesh.get("visible")))

	await _click("left", c.comfort_rect("vignette_75").get_center())
	_check("clicking 75% sets strength to 0.75", absf(VrComfortSettings.vignette_strength - 0.75) < 0.01)

	# 2. Turning mode & settings
	var turn: Node = xr._get_movement_turn()
	await _click("right", c.comfort_rect("turn_smooth").get_center())
	_check("clicking SMOOTH sets smooth turn mode", not VrComfortSettings.snap_turning and int(turn.get("turn_mode")) == 2)

	await _click("right", c.comfort_rect("smooth_30").get_center())
	_check("clicking 3.0 sets smooth speed to 3.0", absf(VrComfortSettings.smooth_turn_speed - 3.0) < 0.01 and absf(float(turn.get("smooth_turn_speed")) - 3.0) < 0.01)

	await _click("right", c.comfort_rect("turn_snap").get_center())
	_check("clicking SNAP sets snap turn mode", VrComfortSettings.snap_turning and int(turn.get("turn_mode")) == 1)

	await _click("right", c.comfort_rect("snap_60").get_center())
	_check("clicking 60° sets snap angle to 60.0", absf(VrComfortSettings.snap_angle - 60.0) < 0.01 and absf(float(turn.get("step_turn_angle")) - 60.0) < 0.01)

	# 3. Dominant-hand swap
	await _click("left", c.comfort_rect("hand_left").get_center())
	_check("dominant hand swapped to left", VrComfortSettings.dominant_hand == "left" and xr.dominant_hand == "left")
	_check("left holder is now dominant weapon hand", xr.get_dominant_holder() == xr.left_holder)
	_check("movement direct reparented to right controller", xr._get_movement_direct().get_parent() == xr.right_controller)
	_check("movement turn reparented to left controller", xr._get_movement_turn().get_parent() == xr.left_controller)
	_check("turn controller for height adjust is left controller when southpaw", xr._get_turn_controller() == xr.left_controller)
	if run.diegetic_hud and run.diegetic_hud.wrist_unit:
		_check("wrist HUD plate moved to off-hand (right controller)", run.diegetic_hud.wrist_unit.get_parent() == xr.right_controller)

	await _click("left", c.comfort_rect("hand_right").get_center())
	_check("dominant hand swapped back to right", VrComfortSettings.dominant_hand == "right" and xr.dominant_hand == "right")
	_check("right holder is dominant weapon hand", xr.get_dominant_holder() == xr.right_holder)
	_check("movement direct back on left controller", xr._get_movement_direct().get_parent() == xr.left_controller)
	_check("movement turn back on right controller", xr._get_movement_turn().get_parent() == xr.right_controller)
	_check("turn controller for height adjust is right controller when right-dominant", xr._get_turn_controller() == xr.right_controller)
	if run.diegetic_hud and run.diegetic_hud.wrist_unit:
		_check("wrist HUD plate back on left controller", run.diegetic_hud.wrist_unit.get_parent() == xr.left_controller)

	# 4. Seated mode & height
	await _click("right", c.comfort_rect("seated_on").get_center())
	_check("seated mode enabled", VrComfortSettings.seated_mode and VrComfortSettings.height_offset >= 0.20)
	var body_h: float = float(xr._body().get("player_height_offset"))
	_check("player body height offset applied (%.2f m)" % body_h, absf(body_h - VrComfortSettings.height_offset) < 0.01)
	await _frames(8)

	var h_before := VrComfortSettings.height_offset
	await _click("right", c.comfort_rect("height_plus").get_center())
	_check("height plus adjusts by +5 cm (%.2f -> %.2f)" % [h_before, VrComfortSettings.height_offset], absf(VrComfortSettings.height_offset - (h_before + 0.05)) < 0.01)

	await _click("right", c.comfort_rect("seated_off").get_center())
	_check("standing mode restored", not VrComfortSettings.seated_mode)

	await _click("right", c.comfort_rect("height_reset").get_center())
	_check("height reset to 0.00 m", absf(VrComfortSettings.height_offset) < 0.01)

	# 5. Persistence verification
	var cfg := ConfigFile.new()
	var err := cfg.load(VrComfortSettings.SETTINGS_PATH)
	_check("user://hanabi_vr.cfg loaded successfully", err == OK)
	_check("vignette_enabled saved in cfg", cfg.get_value("comfort", "vignette_enabled", false) == true)
	_check("vignette_strength saved in cfg", absf(float(cfg.get_value("comfort", "vignette_strength", 0.0)) - 0.75) < 0.01)
	_check("snap_angle saved in cfg", absf(float(cfg.get_value("comfort", "snap_angle", 0.0)) - 60.0) < 0.01)
	_check("dominant_hand saved in cfg", String(cfg.get_value("comfort", "dominant_hand", "")) == "right")

	# 6. Switch back to skill tree tab
	await _click("left", c.tab_rect(0).get_center())
	_check("clicking tab 0 returns to Sakura tree", not c.is_comfort_tab and c.element == Elements.SAKURA)

	await _release_triggers()
	await _tap_menu_button()
	_check("the menu closes cleanly after comfort checks", not ctl.is_open)

	# Restore original config file and settings
	if had_original_cfg:
		var fw := FileAccess.open(VrComfortSettings.SETTINGS_PATH, FileAccess.WRITE)
		if fw:
			fw.store_string(original_cfg_content)
			fw.close()
	else:
		DirAccess.remove_absolute(VrComfortSettings.SETTINGS_PATH)
	VrComfortSettings.load_settings()
	VrComfortSettings.apply_to_player(xr)


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
	for st in [RunGame.RunState.INTRO, RunGame.RunState.LEVEL_UP, RunGame.RunState.GAME_OVER]:
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
		if "try_unlock(" in src or "ofuda_count -=" in src or "ofuda_count =" in src or "add_ofuda(" in src:
			offenders.append(f)
	_check("UI code never touches the wallet or tree directly (%s)" % [offenders], offenders.is_empty())


# --- Helpers ---------------------------------------------------------------------------

func _imbue_seconds(element: String) -> float:
	var es := run.element_system
	es.imbue(element)
	return es.element_time_remaining


func _camera() -> Node3D:
	return xr.get_node("XROrigin3D/XRCamera3D") as Node3D


func _tap_menu_button() -> void:
	sim.set_button("left", "menu_button", true)
	await _frames(6)  # 0.07 s: a tap
	sim.set_button("left", "menu_button", false)
	await _frames(6)


## Aims a hand at canvas pixel [param px] of the open panel.
func _aim(side: String, px: Vector2) -> void:
	var c := xr.left_controller if side == "left" else xr.right_controller
	for _i in 10:
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
			if not hit.is_empty() and (hit.canvas as Vector2).distance_to(px) < 22.0:
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
