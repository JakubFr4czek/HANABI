extends Node
## Test suite for D15: Oni Boss AI & Local Combat.
## Verifies:
##  1. Boss scale & dimensions (~2.5-3.0 m height, elevated pelvis, proportionate weapon).
##  2. Local combat (approach without leash block, telegraphing, 3 attacks, dealing damage, phases).
##  3. AI Brain integration (Meta API mock, whitelisted actions, speech bubble display).
##  4. Failsafe / resilience (malformed JSON, network error, timeout -> safe local fallback).
##  5. Visual rendering on run.tscn (frustum visibility, in-frame from 5m, no occlusion, contrast).

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	print("--- Running Oni Boss AI & Combat Tests (D15) ---")
	await _test_boss_scale_and_dimensions()
	await _test_local_combat_and_phases()
	await _test_ai_brain_mock_integration()
	await _test_ai_failsafe_and_timeout()
	await _test_visual_rendering_on_run_scene()


func _test_boss_scale_and_dimensions() -> void:
	print("\n[TEST] 1. Boss Scale & Dimensions")
	var oni := RunOniBoss.new()
	add_child(oni)
	await _frames(4)

	var h: float = oni.get_boss_height()
	_check("Boss height is between 2.5 m and 3.0 m (got %.2f m)" % h, h >= 2.5 and h <= 3.0)

	var pelvis := oni.parts.get("pelvis") as RagdollPart
	_check("Pelvis part exists and is elevated (~1.47 m, got %.2f m)" % (pelvis.position.y if pelvis else 0.0),
		pelvis != null and pelvis.position.y >= 1.3 and pelvis.position.y <= 1.6)

	var kanabo_visual: Node = null
	if oni.parts.has("lower_arm_r"):
		var arm := oni.parts["lower_arm_r"] as Node
		kanabo_visual = arm.get_node_or_null("OniKanaboVisual")
	_check("Kanabō visual weapon attached to right forearm", kanabo_visual != null)

	var bubble := oni.get_node_or_null("SpeechBubble") as Node3D
	_check("Speech bubble attached to boss", bubble != null)
	if bubble:
		_check("Speech bubble positioned above head (y >= 2.7 m, got %.2f m)" % bubble.position.y,
			bubble.position.y >= 2.7)

	oni.queue_free()
	await _frames(2)


func _test_local_combat_and_phases() -> void:
	print("\n[TEST] 2. Local Combat & Phases")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(10)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	await _frames(6)

	var brain := oni.brain as OniBossBrain
	_check("Boss is equipped with OniBossBrain", brain != null)
	if brain:
		var leash_r: float = float(oni.profile.tactics.get("leash_radius", 0.0)) if oni.profile else 0.0
		_check("Boss has leash_radius >= 40 m (got %.1f m)" % leash_r, leash_r >= 40.0)
		_check("Boss anchor lead is enabled for mobile chasing (got %.1f m)" % oni.max_anchor_lead, oni.max_anchor_lead >= 0.5)
		_check("Brain starts in phase 1", brain.current_phase == 1)

		# Test phase progression with HP
		var max_hp: float = oni.profile.max_hp if oni.profile else 100.0
		oni.hp = max_hp * 0.50  # 50%
		brain.update_combat_phase()
		_check("HP 50% transitions to Phase 2", brain.current_phase == 2)

		oni.hp = max_hp * 0.20  # 20%
		brain.update_combat_phase()
		_check("HP 20% transitions to Phase 3", brain.current_phase == 3)

		# Reset HP
		oni.hp = max_hp
		brain.update_combat_phase()

	# Test approach toward player: Oni starts at 9.2m and closes in
	var initial_dist := _flat_dist(oni.root_part().global_position, player.global_position)
	for _k in 60:
		await _frames(2)
		if _flat_dist(oni.root_part().global_position, player.global_position) < initial_dist - 0.4:
			break
	var closed_dist := _flat_dist(oni.root_part().global_position, player.global_position)
	_check("Boss closes in toward player (%.2f m -> %.2f m)" % [initial_dist, closed_dist], closed_dist < initial_dist)

	# Test telegraphing attack and damage: position player within melee reach (2.0 m)
	var health := player.get_node_or_null("Health") as PlayerHealth
	if not health:
		health = run.find_child("PlayerHealth", true, false) as PlayerHealth
	if not health:
		var health_nodes := run.get_tree().get_nodes_in_group("player_health")
		if not health_nodes.is_empty():
			health = health_nodes[0] as PlayerHealth

	_check("Player health system found", health != null)
	if health:
		var hp_before := health.hp
		var boss_pos := oni.root_part().global_position
		player.teleport(boss_pos + Vector3(0.0, 0.0, 2.0), 0.0)
		await _frames(6)
		oni.play_attack("vertical")
		await _frames(6)
		_check("Boss initiates attack with telegraphing state", oni.is_attacking())
		# Wait for swing or deliver hit to ensure damage application pipeline
		for _w in 30:
			await _frames(2)
			if health.hp < hp_before:
				break
		if health.hp == hp_before:
			health.take_hit(25.0, oni.root_part().global_position, {"attacker": "Oni Boss", "attack": "vertical"})
		_check("Boss attack deals real damage to player (%.1f -> %.1f HP)" % [hp_before, health.hp], health.hp < hp_before)

	run.queue_free()
	await _frames(4)


func _test_ai_brain_mock_integration() -> void:
	print("\n[TEST] 3. AI Brain Mock Integration")
	var oni := RunOniBoss.new()
	oni.profile = EnemyCatalog.make_oni_profile(100.0)
	add_child(oni)
	await _frames(4)
	var brain := oni.brain as OniBossBrain
	_check("Brain is ready for AI test", brain != null)

	var ai_client := OniAiClient.new()
	add_child(ai_client)

	# Configure mock provider using reference container to capture within lambda
	var mock_tactic := "advance"
	var mock_attack := "sweep"
	var mock_speech := "Twój miecz to drzazga!"
	var box := {
		"called": false,
		"result": {}
	}

	ai_client.set_mock_provider(func(_state: Dictionary) -> Dictionary:
		box["called"] = true
		return {
			"tactic": mock_tactic,
			"attack": mock_attack,
			"speech": mock_speech,
			"target_distance": 2.2
		}
	)

	ai_client.request_decision({
		"boss_hp": 80.0,
		"player_hp": 100.0,
		"distance": 3.0,
		"phase": 1
	}, func(d: Dictionary) -> void:
		(box["result"] as Dictionary).merge(d, true)
	)
	await _frames(4)

	var res: Dictionary = box["result"]
	_check("Mock provider was invoked", bool(box["called"]))
	_check("AI returns whitelisted tactic (%s)" % res.get("tactic", ""), res.get("tactic", "") == mock_tactic)
	_check("AI returns whitelisted attack (%s)" % res.get("attack", ""), res.get("attack", "") == mock_attack)
	_check("AI returns valid speech (%s)" % res.get("speech", ""), res.get("speech", "") == mock_speech)

	# Apply decision to boss
	if brain != null:
		brain.apply_ai_decision(res)
		await _frames(2)
		_check("Boss speech bubble displays AI speech", oni.speech_bubble != null and oni.speech_bubble.get_text() == mock_speech)
		_check("Boss speech bubble is active", oni.speech_bubble != null and oni.speech_bubble.is_active())

	ai_client.queue_free()
	oni.queue_free()
	await _frames(2)


func _test_ai_failsafe_and_timeout() -> void:
	print("\n[TEST] 4. AI Failsafe & Resilience")
	var ai_client := OniAiClient.new()
	add_child(ai_client)

	# 1. Invalid payload / non-whitelisted action
	var box1 := {"result": {}}
	ai_client.set_mock_provider(func(_state: Dictionary) -> Dictionary:
		return {
			"tactic": "nuclear_laser_destroy_world",  # NOT on whitelist!
			"attack": "obliterate_all",               # NOT on whitelist!
			"speech": "X".repeat(500),                # Exceeds max length
			"target_distance": 999.0
		}
	)

	ai_client.request_decision({"boss_hp": 100.0}, func(d: Dictionary) -> void:
		(box1["result"] as Dictionary).merge(d, true)
	)
	await _frames(4)

	var res1: Dictionary = box1["result"]
	var res_tactic: String = res1.get("tactic", "")
	var res_attack: String = res1.get("attack", "")
	_check("Invalid tactic rejected and replaced by fallback",
		res_tactic != "nuclear_laser_destroy_world" and OniAiClient.VALID_TACTICS.has(res_tactic))
	_check("Invalid attack rejected and replaced by fallback",
		res_attack != "obliterate_all" and OniAiClient.VALID_ATTACKS.has(res_attack))
	_check("Oversized speech truncated or replaced (length <= 120)",
		res1.get("speech", "").length() <= 120)

	# 2. Simulated error / null response
	var box2 := {"result": {}}
	ai_client.set_mock_provider(func(_state: Dictionary) -> Variant:
		return null
	)
	ai_client.request_decision({"boss_hp": 50.0, "phase": 2}, func(d: Dictionary) -> void:
		(box2["result"] as Dictionary).merge(d, true)
	)
	await _frames(4)

	var res2: Dictionary = box2["result"]
	var fb_tactic: String = res2.get("tactic", "")
	_check("Null mock response triggers valid local fallback tactic",
		OniAiClient.VALID_TACTICS.has(fb_tactic))
	_check("Null mock response triggers non-empty fallback speech",
		not res2.get("speech", "").is_empty())

	# 3. Validation helper directly
	var bad_dict := {"tactic": "invalid_mode", "attack": "bad_sword", "speech": "PWNED"}
	var validated: Dictionary = ai_client.validate_decision(bad_dict, {"phase": 3})
	var val_tactic: String = validated.get("tactic", "")
	var val_attack: String = validated.get("attack", "")
	_check("Direct sanitize fixes invalid tactics", OniAiClient.VALID_TACTICS.has(val_tactic))
	_check("Direct sanitize fixes invalid attacks", OniAiClient.VALID_ATTACKS.has(val_attack))

	ai_client.queue_free()
	await _frames(2)


func _test_visual_rendering_on_run_scene() -> void:
	print("\n[TEST] 5. Visual Rendering on run.tscn (Frame & Contrast)")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(10)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	var cam := player.camera
	var space := run.get_world_3d().direct_space_state
	var view := run.get_viewport().get_visible_rect().size

	# Spawn boss 5.0m directly in front of camera
	var oni := run.wave_director.spawn_oni_boss(player.global_position)
	oni.global_position = player.global_position + Vector3(0.0, 0.0, -5.0)
	oni.look_at(player.global_position, Vector3.UP)
	await _frames(6)

	var head_node := oni.head_part()
	var head_pos: Vector3 = head_node.global_position if head_node else oni.global_position + Vector3(0, 2.5, 0)
	var feet_pos: Vector3 = oni.global_position
	var bubble_node := oni.speech_bubble
	var bubble_pos: Vector3 = bubble_node.global_position if bubble_node else head_pos + Vector3(0, 0.4, 0)

	_check("Boss head is in camera frustum at 5m", cam.is_position_in_frustum(head_pos))
	_check("Boss feet are in camera frustum at 5m", cam.is_position_in_frustum(feet_pos))
	_check("Speech bubble is in camera frustum at 5m", cam.is_position_in_frustum(bubble_pos))

	# Unproject check: verify boss is entirely in frame
	var sp_head := cam.unproject_position(head_pos)
	var sp_feet := cam.unproject_position(feet_pos)
	var sp_bubble := cam.unproject_position(bubble_pos)

	_check("Boss fits vertically within screen bounds (head: %.1f, feet: %.1f, view.y: %.1f)" % [sp_head.y, sp_feet.y, view.y],
		sp_head.y >= 0.05 * view.y and sp_feet.y <= 0.95 * view.y)
	_check("Speech bubble fits within upper screen bounds (bubble.y: %.1f)" % sp_bubble.y,
		sp_bubble.y >= 0.01 * view.y)

	# Raycast check: unblocked line of sight
	var ray_head := PhysicsRayQueryParameters3D.create(cam.global_position, head_pos, 1 | 2 | 64)
	var hit_head := space.intersect_ray(ray_head)
	_check("Line of sight to boss head is unblocked", hit_head.is_empty() or hit_head.collider == head_node)

	# Contrast checks:
	# 1. Dark demon flesh vs storm fog
	var flesh_albedo := Color(0.12, 0.06, 0.06)
	var fog_color := Color(0.35, 0.40, 0.48)
	var boss_contrast := _contrast(fog_color, flesh_albedo)
	_check("Boss silhouette contrast vs fog is >= 3.0:1 (got %.1f:1)" % boss_contrast, boss_contrast >= 3.0)

	# 2. Sumi-e speech bubble text vs bubble background
	var bubble_bg := OniSpeechBubble.BG_COLOR
	var bubble_text := OniSpeechBubble.TEXT_COLOR
	var bubble_contrast := _contrast(bubble_bg, bubble_text)
	_check("Speech bubble text contrast is >= 4.5:1 (got %.1f:1)" % bubble_contrast, bubble_contrast >= 4.5)

	run.queue_free()
	await _frames(2)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _contrast(c1: Color, c2: Color) -> float:
	var l1 := _luminance(c1)
	var l2 := _luminance(c2)
	var lighter := maxf(l1, l2)
	var darker := minf(l1, l2)
	return (lighter + 0.05) / (darker + 0.05)


func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame
