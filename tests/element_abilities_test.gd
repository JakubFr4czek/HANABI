extends Node
## Headless verification for E2b (docs/ELEMENTS_PLAN.md):
## - 2 abilities for all 4 elements on sword-hand buttons (A / J = Ability 1, B / K = Ability 2)
## - Plain steel buttons do nothing mechanical (tactile empty click)
## - Cooldowns per ability, 50% cut on same-element refresh, reset on swap
## - Zero element duration consumption
## - Ongoing abilities complete their execution even after the 20s element expires
## - SceneTree pause cleanly halts timers (no Engine.time_scale = 0)
## - Quest 3 performance limits (zero OmniLight3D nodes, bounded pools)

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_element_abilities_save.cfg"

var failures := 0
var run: RunGame
var player: DesktopPlayer
var elem_sys: ElementSystem
var _empty_hits := 0


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
	elem_sys = run.element_system
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)

	await _test_single_press()
	await _test_plain_steel()
	await _test_sakura_abilities()
	await _test_storm_abilities()
	await _test_ink_abilities()
	await _test_shadow_abilities()
	await _test_cooldowns_and_refresh()
	await _test_ongoing_completion_on_expiry()
	await _test_balance_wiring()
	await _test_pause_respect()
	await _test_readability()
	await _test_perf_limits()

	run.queue_free()


func _test_single_press() -> void:
	# Regression (E2b review): one physical press = exactly one ability call.
	elem_sys.reset()
	run.state = RunGame.RunState.PLAYING
	_empty_hits = 0
	var cb := func(type: String, _data: Dictionary) -> void:
		if type == "empty_steel":
			_empty_hits += 1
	elem_sys.effect_triggered.connect(cb)

	# One simulated Desktop InputEventKey J through the real input pipeline:
	# only the DesktopPlayer signal path may fire (run_game has no J/K handler).
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_check("Single J press = exactly one Ability 1 call (one empty_steel)", _empty_hits == 1)

	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_K
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await _frames(3)
	_check("Single K press = exactly one Ability 2 call (one empty_steel)", _empty_hits == 2)

	# VR: the legacy duplicate signal must be gone from XRPlayer.
	var xr_signals: Array = load("res://src/player/xr_player.gd").get_script_signal_list().map(func(s: Dictionary) -> String: return String(s.name))
	_check("XRPlayer has no duplicate element_ability_requested signal", not xr_signals.has("element_ability_requested"))
	_check("XRPlayer exposes exactly one Ability 2 signal", xr_signals.has("ability_2_requested"))
	elem_sys.effect_triggered.disconnect(cb)


func _test_plain_steel() -> void:
	elem_sys.reset()
	run.katana.set_element(Elements.NONE)
	_check("Katana is plain steel (NONE)", elem_sys.current_element == Elements.NONE and run.katana.element == Elements.NONE)

	_empty_hits = 0
	var cb := func(type: String, _data: Dictionary) -> void:
		if type == "empty_steel":
			_empty_hits += 1
	elem_sys.effect_triggered.connect(cb)

	# Ability 1 on steel
	var a1 := elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Ability 1 on plain steel returns false", not a1)
	_check("Ability 1 on plain steel emitted empty_steel feedback", _empty_hits == 1)

	# Ability 2 on steel
	var a2 := elem_sys.execute_ability_2(Vector3.FORWARD)
	_check("Ability 2 on plain steel returns false", not a2)
	_check("Ability 2 on plain steel emitted empty_steel feedback", _empty_hits == 2)

	# Desktop player triggers J and K on plain steel (requires PLAYING state gate in RunGame)
	run.state = RunGame.RunState.PLAYING
	player.trigger_ability_1()
	await _frames(2)
	_check("Desktop J key on plain steel triggers empty feedback", _empty_hits == 3)

	player.trigger_ability_2()
	await _frames(2)
	_check("Desktop K key on plain steel triggers empty feedback", _empty_hits == 4)

	elem_sys.effect_triggered.disconnect(cb)


func _test_sakura_abilities() -> void:
	elem_sys.imbue(Elements.SAKURA, 20.0)
	_check("Imbued with Sakura", elem_sys.current_element == Elements.SAKURA)

	# Ability 1: Senbonzakura (fan of 6 cutting petals)
	var e1 := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -1.2), player.global_position)
	await _frames(4)
	var hp_before := e1.hp
	var a1_ok := elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Sakura Ability 1 (Senbonzakura) executes successfully", a1_ok)
	_check("Senbonzakura spawned cutting petals", elem_sys._petals.size() > 0)
	await _seconds(0.4)
	_check("Senbonzakura petals dealt damage to target yōkai", e1.is_dead or e1.hp < hp_before)
	_check("Ability 1 cooldown is active", elem_sys.ability_1_cooldown > 0.0)

	# Ability 2: Hanamai (4 orbiting barrier petals, 6.0s duration)
	var a2_ok := elem_sys.execute_ability_2(Vector3.FORWARD)
	_check("Sakura Ability 2 (Hanamai) executes successfully", a2_ok)
	_check("Hanamai spawned 4 orbiting barrier petals", elem_sys._orbit_petals.size() == 4)
	_check("Hanamai duration set to 6.0s", absf(elem_sys.hanamai_time_remaining - 6.0) < 0.2)
	_check("Hanamai incoming damage reduction is active (0.7 multiplier)", absf(elem_sys.get_incoming_damage_multiplier() - 0.7) < 0.01)
	_check("Ability 2 cooldown is active", elem_sys.ability_2_cooldown > 0.0)


func _test_storm_abilities() -> void:
	elem_sys.imbue(Elements.STORM, 20.0)
	_check("Imbued with Storm", elem_sys.current_element == Elements.STORM)

	# Ability 1: Raikiri (chain lightning)
	var target1 := run.wave_director.spawn_enemy_at(Vector3(-0.8, 0.0, -1.2), player.global_position)
	var target2 := run.wave_director.spawn_enemy_at(Vector3(0.8, 0.0, -1.5), player.global_position)
	await _frames(4)
	var hp1 := target1.hp
	var hp2 := target2.hp
	var a1_ok := elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Storm Ability 1 (Raikiri) executes successfully", a1_ok)
	await _frames(3)
	_check("Raikiri damaged primary and chain targets", (target1.is_dead or target1.hp < hp1) and (target2.is_dead or target2.hp < hp2))
	_check("Raikiri cooldown is active", elem_sys.ability_1_cooldown > 0.0)

	# Ability 2: Shiden (thunder dash + stagger)
	var pos_start := player.global_position
	var a2_ok := elem_sys.execute_ability_2(Vector3.FORWARD)
	_check("Storm Ability 2 (Shiden) executes successfully", a2_ok)
	await _frames(3)
	_check("Shiden dashed player forward", player.global_position.distance_to(pos_start) > 2.0)
	_check("Shiden cooldown is active", elem_sys.ability_2_cooldown > 0.0)


func _test_ink_abilities() -> void:
	elem_sys.imbue(Elements.INK, 20.0)
	_check("Imbued with Ink", elem_sys.current_element == Elements.INK)

	# Ability 1: Sumi-gaeshi (cone wave + ground ink pool)
	var victim := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -1.5), player.global_position)
	await _frames(4)
	var pools_before := elem_sys._ink_pools.size()
	var a1_ok := elem_sys.execute_ability_1(Vector3.BACK)
	_check("Ink Ability 1 (Sumi-gaeshi) executes successfully", a1_ok)
	_check("Sumi-gaeshi spawned an ink pool", elem_sys._ink_pools.size() > pools_before)
	await _seconds(0.2)
	_check("Sumi-gaeshi slowed yōkai in cone", victim.is_slowed())
	_check("Sumi-gaeshi cooldown is active", elem_sys.ability_1_cooldown > 0.0)

	# Ability 2: Kage-nawa (binding tendrils + pull) — stand 3 m away so the pull is measurable
	player.teleport(victim.global_position + Vector3(0.0, 0.0, 3.0), 0.0)
	await _frames(2)
	var dist_before := player.global_position.distance_to(victim.global_position)
	var a2_ok := elem_sys.execute_ability_2(Vector3.FORWARD)
	_check("Ink Ability 2 (Kage-nawa) executes successfully", a2_ok)
	var dist_after := player.global_position.distance_to(victim.global_position)
	_check("Kage-nawa pulled enemy toward player", dist_after < dist_before - 0.05)
	_check("Kage-nawa cooldown is active", elem_sys.ability_2_cooldown > 0.0)


func _test_shadow_abilities() -> void:
	elem_sys.imbue(Elements.SHADOW, 20.0)
	_check("Imbued with Shadow", elem_sys.current_element == Elements.SHADOW)

	# Ability 1: Kagemusha (decoy clone redirecting aggro)
	var a1_ok := elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Shadow Ability 1 (Kagemusha) executes successfully", a1_ok)
	var decoy := get_tree().get_first_node_in_group("shadow_decoy") as Node3D
	_check("Kagemusha decoy node spawned in group shadow_decoy", decoy != null and is_instance_valid(decoy))
	_check("Kagemusha cooldown is active", elem_sys.ability_1_cooldown > 0.0)

	# Ability 2: Yami-watari (blink & critical cleave buff)
	var pos_start := player.global_position
	var a2_ok := elem_sys.execute_ability_2(Vector3.LEFT)
	_check("Shadow Ability 2 (Yami-watari) executes successfully", a2_ok)
	await _frames(3)
	_check("Yami-watari teleported player", player.global_position.distance_to(pos_start) > 1.0)
	_check("Yami-watari primed critical cleave buff", elem_sys.shadow_cleave_buff_time > 0.0)
	_check("Yami-watari cooldown is active", elem_sys.ability_2_cooldown > 0.0)

	# Test critical strike consumption
	var enemy := run.wave_director.spawn_enemy_at(player.global_position + Vector3(0.0, 0.0, -1.0), player.global_position)
	await _frames(4)
	var hit := {"attacker": run.katana.weapon_name, "damage": 20.0, "point": player.global_position}
	elem_sys.on_blade_hit(hit)
	_check("Shadow Cleave buff amplified damage (x%.1f)" % ElementBalance.YAMI_CRIT_MULTIPLIER,
		is_equal_approx(float(hit.damage), 20.0 * ElementBalance.YAMI_CRIT_MULTIPLIER))
	_check("Shadow Cleave buff consumed on hit", elem_sys.shadow_cleave_buff_time == 0.0)


func _test_cooldowns_and_refresh() -> void:
	elem_sys.imbue(Elements.SAKURA, 20.0)
	elem_sys.ability_1_cooldown = 0.0
	elem_sys.ability_2_cooldown = 0.0

	var fired_1 := elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Ability 1 fired cleanly", fired_1)
	var double_fire := elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Double-fire while on cooldown is rejected", not double_fire)

	var cd1 := elem_sys.ability_1_cooldown
	_check("Cooldown 1 is initialized to ~4.0s", cd1 >= 3.5 and cd1 <= 4.0)

	# Same-element refresh: cuts cooldown by 50%
	elem_sys.imbue(Elements.SAKURA, 20.0)
	_check("Same-element gate refresh cuts cooldown by 50%", absf(elem_sys.ability_1_cooldown - (cd1 * 0.5)) < 0.1)

	# Different-element swap: resets cooldowns
	elem_sys.imbue(Elements.STORM, 20.0)
	_check("Different-element swap resets Ability 1 cooldown to 0.0", elem_sys.ability_1_cooldown == 0.0)
	_check("Different-element swap resets Ability 2 cooldown to 0.0", elem_sys.ability_2_cooldown == 0.0)

	# Ability use does NOT consume element duration
	var time_before := elem_sys.element_time_remaining
	elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Firing ability does not drain element imbue duration", elem_sys.element_time_remaining == time_before)


func _test_ongoing_completion_on_expiry() -> void:
	elem_sys.imbue(Elements.SAKURA, 2.0)  # Only 2.0s duration left on katana
	elem_sys.ability_2_cooldown = 0.0

	# Fire Hanamai (6.0s duration)
	var hanamai_ok := elem_sys.execute_ability_2(Vector3.FORWARD)
	_check("Hanamai fired with 2.0s element time remaining", hanamai_ok and elem_sys._orbit_petals.size() == 4)

	# Advance 2.5s: 20s gate timer expires to plain steel
	for _i in 25:
		elem_sys._physics_process(0.1)
		run.katana._physics_process(0.1)

	_check("Katana element expired to plain steel", elem_sys.current_element == Elements.NONE and run.katana.element == Elements.NONE)
	_check("Subsequent button press on plain steel returns false", not elem_sys.execute_ability_2(Vector3.FORWARD))
	_check("Ongoing Hanamai barrier completes execution after element expiry (petals=4)", elem_sys._orbit_petals.size() == 4 and elem_sys.hanamai_time_remaining > 0.0)

	# Advance another 4.0s: Hanamai completes full 6.0s duration
	for _i in 40:
		elem_sys._physics_process(0.1)
		run.katana._physics_process(0.1)

	_check("Hanamai cleanly clears after its full 6.0s duration finishes", elem_sys._orbit_petals.size() == 0 and elem_sys.hanamai_time_remaining == 0.0)


## E4: the numbers in ElementBalance are the numbers the abilities really use.
func _test_balance_wiring() -> void:
	elem_sys.reset()
	var cooldown_ok := true
	var table := {
		Elements.SAKURA: [ElementBalance.SENBONZAKURA_COOLDOWN, ElementBalance.HANAMAI_COOLDOWN],
		Elements.STORM: [ElementBalance.RAIKIRI_COOLDOWN, ElementBalance.SHIDEN_COOLDOWN],
		Elements.INK: [ElementBalance.SUMI_COOLDOWN, ElementBalance.KAGE_NAWA_COOLDOWN],
		Elements.SHADOW: [ElementBalance.KAGEMUSHA_COOLDOWN, ElementBalance.YAMI_COOLDOWN],
	}
	var enemy := run.wave_director.spawn_enemy_at(player.global_position + Vector3(0.0, 0.0, -3.0), player.global_position)
	await _frames(3)
	for school: String in table:
		elem_sys.imbue(school)
		elem_sys.execute_ability_1(Vector3.FORWARD)
		elem_sys.execute_ability_2(Vector3.FORWARD)
		cooldown_ok = cooldown_ok \
			and absf(elem_sys.ability_1_cooldown - float(table[school][0])) < 0.01 \
			and absf(elem_sys.ability_2_cooldown - float(table[school][1])) < 0.01 \
			and absf(elem_sys.ability_cooldown_total(1) - float(table[school][0])) < 0.01
	_check("Every school's two cooldowns are the ElementBalance values", cooldown_ok)

	# Potency follows the run: Raikiri's primary hit grows with soul rank and Razor Edge.
	elem_sys.reset()
	run.state = RunGame.RunState.PLAYING
	var rank_before := run.level
	var blade_before := run.katana.damage_multiplier
	enemy.hp = 5000.0
	enemy.profile.max_hp = 5000.0
	elem_sys.imbue(Elements.STORM)
	run.level = 1
	run.katana.damage_multiplier = 1.0
	var hp0 := enemy.hp
	elem_sys.execute_ability_1(Vector3.FORWARD)
	var base_dmg := hp0 - enemy.hp
	_check("Raikiri's primary hit at rank 1 is the base %.0f" % ElementBalance.RAIKIRI_PRIMARY_DAMAGE,
		absf(base_dmg - ElementBalance.RAIKIRI_PRIMARY_DAMAGE) < 0.6)
	run.level = 11
	run.katana.damage_multiplier = 1.5
	var expected_power := 1.5 * (1.0 + ElementBalance.POWER_PER_RANK * 10.0)
	_check("ability_power follows soul rank and Razor Edge (%.2f)" % elem_sys.ability_power(),
		absf(elem_sys.ability_power() - expected_power) < 0.001)
	elem_sys.ability_1_cooldown = 0.0
	var hp1 := enemy.hp
	elem_sys.execute_ability_1(Vector3.FORWARD)
	var strong := hp1 - enemy.hp
	_check("the same Raikiri hits %.1fx harder at rank 11 with Razor Edge (%.1f -> %.1f)" % [expected_power, base_dmg, strong],
		absf(strong - ElementBalance.RAIKIRI_PRIMARY_DAMAGE * expected_power) < 0.8)
	run.level = rank_before
	run.katana.damage_multiplier = blade_before

	# The Kagemusha decoy takes exactly KAGEMUSHA_HITS claws, then dissolves.
	elem_sys.reset()
	elem_sys.imbue(Elements.SHADOW)
	elem_sys.execute_ability_1(Vector3.FORWARD)
	var decoy := elem_sys.kagemusha_decoy
	_check("decoy lasts %.1f s or %d claws" % [ElementBalance.KAGEMUSHA_SECONDS, ElementBalance.KAGEMUSHA_HITS],
		decoy != null and absf(elem_sys.kagemusha_time_remaining - ElementBalance.KAGEMUSHA_SECONDS) < 0.01
		and elem_sys.kagemusha_hits_remaining == ElementBalance.KAGEMUSHA_HITS)
	get_tree().call_group("element_system", "on_decoy_struck")
	_check("after one claw the decoy still stands", is_instance_valid(elem_sys.kagemusha_decoy) and elem_sys.kagemusha_decoy != null)
	get_tree().call_group("element_system", "on_decoy_struck")
	await _frames(2)
	_check("after the second claw the decoy is gone and enemies target the player again",
		elem_sys.kagemusha_decoy == null and not is_instance_valid(decoy)
		and get_tree().get_first_node_in_group("shadow_decoy") == null)
	elem_sys.reset()
	enemy.die()
	run.wave_director.clear_enemies()
	await _frames(2)


func _test_pause_respect() -> void:
	elem_sys.imbue(Elements.STORM, 20.0)
	elem_sys.ability_1_cooldown = 3.0
	var timer_before := elem_sys.element_time_remaining
	var cd_before := elem_sys.ability_1_cooldown

	# Pause scene tree cleanly
	get_tree().paused = true
	elem_sys._physics_process(0.5)
	elem_sys._physics_process(0.5)

	_check("Paused tree halts element duration timer", elem_sys.element_time_remaining == timer_before)
	_check("Paused tree halts ability cooldown timer", elem_sys.ability_1_cooldown == cd_before)

	get_tree().paused = false
	elem_sys._physics_process(0.5)
	_check("Unpaused tree resumes timers", elem_sys.element_time_remaining < timer_before and elem_sys.ability_1_cooldown < cd_before)


# --- E3: the player always knows what is on the blade -----------------------------------

func _blade_param(key: String) -> Variant:
	return run.katana._get_blade_material().get_shader_parameter(key)


func _playing_cue(category: String) -> bool:
	for p in Sfx._pool:
		if p.playing and p.stream == Sfx._streams.get(category):
			return true
	return false


func _test_readability() -> void:
	var hud := run.diegetic_hud
	elem_sys.reset()
	await _frames(3)
	# A reset lets the light drain for a moment: skip past it.
	run.katana._fade_msec -= int(BladeBody.FADE_SECONDS * 1000.0) + 50
	run.katana._update_blade_material()
	_check("plain steel: the wrist shows no element arc, no kanji and no count",
		hud._ring_cache.get("element_on") == 0.0 and hud.element_label.text == "" and hud.ability_a_label.text == "")
	_check("plain steel: the blade has no element light", float(_blade_param("element_glow")) == 0.0)
	var steel: ShaderMaterial = run.katana._get_blade_material()
	_check("plain steel: no rim-light pass (no extra draw call)", steel.next_pass == null)

	# Every element: blade kind/colour, crest kanji, ability glyphs, the imbue cue.
	for el in Elements.COMBAT_ELEMENTS:
		elem_sys.reset()
		for p in Sfx._pool:
			p.stop()
		elem_sys.imbue(el, 20.0)
		_check("%s: a cue plays when the blade takes the element" % el, _playing_cue("imbue_" + el))
		await _frames(3)
		var c := BladeBody.glow_color(el)
		var bc: Vector3 = _blade_param("element_color")
		_check("%s: the blade lights up in its own colour and kind" % el,
			float(_blade_param("element_glow")) > 0.5 and int(_blade_param("element_kind")) == run.katana.KIND[el]
			and absf(bc.x - c.r) < 0.01 and absf(bc.z - c.b) < 0.01)
		var rim: ShaderMaterial = steel.next_pass as ShaderMaterial
		_check("%s: the rim-light pass is on the blade, in the school's colour, as strong as its glow" % el,
			rim != null and float(rim.get_shader_parameter("rim_strength")) > 0.5
			and rim.get_shader_parameter("rim_color") == Vector3(
				BladeBody.RIM[el].color.r, BladeBody.RIM[el].color.g, BladeBody.RIM[el].color.b))
		_check("%s: the wrist shows %s and both ability glyphs" % [el, Elements.build_label(el)],
			hud.element_label.text.begins_with(Elements.build_label(el))
			and hud.ability_a_label.text == Elements.ability_glyph(el, 1)
			and hud.ability_b_label.text == Elements.ability_glyph(el, 2))

	# The numbers on the wrist follow the system: time arc, count, button glyphs.
	elem_sys.reset()
	elem_sys.imbue(Elements.STORM, 20.0)
	elem_sys.element_time_remaining = 12.0
	elem_sys.ability_1_cooldown = 0.0
	elem_sys.ability_2_cooldown = elem_sys.ability_cooldown_total(2) * 0.5
	await _frames(3)
	var tint := Elements.accent_color(Elements.STORM).lightened(0.35)
	_check("the element arc shows the time left (12/20 = %.2f)" % float(hud._ring_cache.get("element_fill")),
		absf(float(hud._ring_cache.get("element_fill")) - 0.6) < 0.02 and hud.element_label.text == "%s 12" % Elements.build_label(Elements.STORM))
	_check("button A reads ready, button B half recharged (A %.2f, B %.2f)" % [elem_sys.ability_ready_ratio(1), elem_sys.ability_ready_ratio(2)],
		_rgb_close(hud.ability_a_label.modulate, DiegeticHud.ability_colour(tint, 1.0))
		and _rgb_close(hud.ability_b_label.modulate, DiegeticHud.ability_colour(tint, 0.5)))
	elem_sys.execute_ability_1(Vector3.FORWARD)
	await _frames(3)
	_check("firing A dims its glyph until it recharges", _rgb_close(hud.ability_a_label.modulate, DiegeticHud.ability_colour(tint, 0.0)))

	# The last 3 s: the blade and the crest beat together, on the imbue clock.
	_check("no warning beat before the last 3 s", float(_blade_param("element_warn")) == 0.0 and not hud._element_warn)
	elem_sys.element_time_remaining = 2.6
	elem_sys._physics_process(0.016)
	await _frames(3)
	_check("last 3 s: blade pulse on", float(_blade_param("element_warn")) == 1.0 and absf(float(_blade_param("element_left")) - elem_sys.element_time_remaining) < 0.2)
	_check("last 3 s: the wrist element figure beats too", hud._element_warn)
	# Same-element top-up: the warning ends and a softer cue plays.
	for p in Sfx._pool:
		p.stop()
	elem_sys.imbue(Elements.STORM, 20.0)
	elem_sys._physics_process(0.016)
	await _frames(2)
	_check("a gate topping the element up ends the warning and chimes again", float(_blade_param("element_warn")) == 0.0 and _playing_cue("imbue_storm"))

	# Expiry: the light drains instead of snapping off, and a soft cue plays.
	for p in Sfx._pool:
		p.stop()
	elem_sys.element_time_remaining = 0.05
	elem_sys._physics_process(0.1)
	_check("expiry plays the fade cue", _playing_cue("element_fade"))
	run.katana._update_blade_material()
	_check("expiry: the blade is still glowing while it fades", float(_blade_param("element_glow")) > 0.0)
	run.katana._fade_msec -= int(BladeBody.FADE_SECONDS * 1000.0) + 50
	run.katana._update_blade_material()
	_check("expiry: then plain steel", float(_blade_param("element_glow")) == 0.0)
	_check("expiry: the rim-light pass leaves the blade with the glow", steel.next_pass == null)
	await _frames(3)
	_check("expiry: the wrist element arc goes again", hud._ring_cache.get("element_on") == 0.0 and hud.element_label.text == "")


func _rgb_close(c: Color, want: Color) -> bool:
	return absf(c.r - want.r) < 0.01 and absf(c.g - want.g) < 0.01 and absf(c.b - want.b) < 0.01


func _test_perf_limits() -> void:
	elem_sys.imbue(Elements.SAKURA, 20.0)
	for i in 10:
		elem_sys.debug_release_petals(Vector3.FORWARD)
	_check("Petals strictly capped at MAX_PETALS (12)", elem_sys._petals.size() <= ElementSystem.MAX_PETALS)

	elem_sys.imbue(Elements.INK, 20.0)
	for i in 10:
		elem_sys.paint_ink(Vector3(float(i), 0.0, 0.0))
	_check("Ink pools strictly capped at MAX_INK_POOLS (6)", elem_sys._ink_pools.size() <= ElementSystem.MAX_INK_POOLS)

	for i in 25:
		elem_sys._spawn_lightning([Vector3.ZERO, Vector3(float(i), 1.0, 0.0)], Color.CYAN, 0.2)
	_check("Transients strictly capped at MAX_TRANSIENT_MESHES (18)", elem_sys._transients.size() <= ElementSystem.MAX_TRANSIENT_MESHES)

	var omni_count := 0
	for node in elem_sys.find_children("*", "OmniLight3D", true, false):
		omni_count += 1
	_check("Zero dynamic OmniLight3D nodes on ElementSystem (omni=0)", omni_count == 0)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * Engine.physics_ticks_per_second))
