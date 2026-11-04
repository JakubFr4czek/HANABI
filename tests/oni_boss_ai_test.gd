extends Node
## Comprehensive test suite for D15: Oni Boss AI & Local Combat.
## Verifies:
##  1. Boss real geometric scale & grounding (measured AABB 2.5-3.0 m, feet on ground).
##  2. Real physical combat & damage (pure blade contact reduces HP, NO fake fallback).
##  3. Parry window & zero-damage deflection (counter_window opens, player unhurt).
##  4. Active approach (from 9.2 m down to <= 3.0 m).
##  5. Three telegraphed attacks (slam, sweep, thrust) with windup -> strike progression.
##  6. Phase behavioral shifts (shorter windup scale in Phase 3).
##  7. AI Brain integration & resilience (whitelisting, instant fallback on null/malformed).
##  N8. Meta AI end-to-end on run.tscn against a local mock API server (real HTTP over
##      loopback): cadence 2–5 s, tactic executed, bubble + overlay, every error -> fallback.
##  8. Real pixel contrast & 8m fog readability on rendered run.tscn frame.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0
var events: Array[Dictionary] = []


func _ready() -> void:
	# Fixed global seed: the gameplay streams (spawner, brains, ragdoll poses, soul orbs) draw
	# from it, so the run is reproducible instead of depending on the launch's random seed.
	seed(20260604)
	GameEvents.event_logged.connect(func(e: Dictionary): events.append(e))
	get_tree().create_timer(150.0).timeout.connect(func():
		print("\nWATCHDOG TIMEOUT in oni_boss_ai_test!")
		get_tree().quit(1)
	)
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	print("--- Running D15 Comprehensive Oni Boss AI & Combat Tests ---")
	await _test_boss_geometric_scale_and_grounding()
	await _test_boss_approach()
	await _test_three_attacks_and_phase_behaviors()
	await _test_real_physical_hit_and_parry()
	await _test_ai_brain_mock_and_failsafe()
	_test_http_reply_parsing()
	await _test_f5_katana_boss_in_run()
	await _test_n8_meta_ai_end_to_end()
	await _test_real_pixel_contrast_and_fog_readability()


func _test_boss_geometric_scale_and_grounding() -> void:
	print("\n[TEST] 1. Real Geometric Scale & Grounding")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var player := run.player as DesktopPlayer
	var health := run.get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health:
		health.max_hp = 1000.0
		health.hp = 1000.0
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	run.wave_director.boss_katana_duelist = false  # F5: the old kanabō Oni, by flag
	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	await _frames(15)  # Let ragdoll settle on ground

	var measured_h: float = oni.get_measured_height()
	_check("Boss real geometric height (AABB) is 2.5-3.0 m (got %.2f m)" % measured_h,
		measured_h >= 2.5 and measured_h <= 3.0)

	var ground_y: float = run.forest_world.height_at(oni.global_position.x, oni.global_position.z)
	var feet_y: float = oni.get_feet_lowest_y()
	_check("Boss feet touch ground level (feet: %.2f m, ground: %.2f m, diff: %.2f m)" % [feet_y, ground_y, absf(feet_y - ground_y)],
		absf(feet_y - ground_y) <= 0.15)

	var pelvis := oni.parts.get("pelvis") as RagdollPart
	_check("Pelvis is elevated for 2.8m humanoid (~1.47 m, got %.2f m)" % (pelvis.position.y if pelvis else 0.0),
		pelvis != null and pelvis.position.y >= 1.3 and pelvis.position.y <= 1.6)

	run.queue_free()
	await _frames(4)


func _test_boss_approach() -> void:
	print("\n[TEST] 2. Active Approach (9.2 m -> <= 2.0 m, inside kanabō reach)")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	run.wave_director.boss_katana_duelist = false  # F5: the old kanabō Oni, by flag
	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	await _frames(4)

	var start_dist := _flat_dist(oni.root_part().global_position, player.global_position)
	_check("Boss spawns at outer combat distance (~9.2 m, got %.2f m)" % start_dist, start_dist >= 8.5)

	# Step physics frames to simulate approach
	for _k in 320:
		await _frames(2)
		var current_d := _flat_dist(oni.root_part().global_position, player.global_position)
		if current_d <= 2.0:
			break

	# A standoff beyond ~2.03 m puts the player outside the kanabō contact zone:
	# the boss would swing at air, so it must close inside it.
	var final_dist := _flat_dist(oni.root_part().global_position, player.global_position)
	_check("Boss actively closes distance inside kanabō reach (<= 2.0 m, got %.2f m)" % final_dist, final_dist <= 2.0)

	run.queue_free()
	await _frames(4)


func _test_three_attacks_and_phase_behaviors() -> void:
	print("\n[TEST] 3. Three Attacks & Phase Behavioral Shifts")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var player := run.player as DesktopPlayer
	var health := run.get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health:
		health.max_hp = 10000.0
		health.hp = 10000.0
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	run.wave_director.boss_katana_duelist = false  # F5: the old kanabō Oni, by flag
	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	var brain := oni.brain as OniBossBrain
	# Fixed seed: the decision RNG (block/feint/combo rolls) must not decide whether
	# a windup happens, otherwise the timing checks flake from run to run.
	brain.set_seed(1)
	_check("OniBossBrain is attached", brain != null)
	var forearm := oni.parts.get("lower_arm_r") as RagdollPart
	var kanabo_visual: MeshInstance3D = null
	if forearm:
		kanabo_visual = forearm.find_child("OniKanaboVisual", true, false) as MeshInstance3D
	_check("Kanabō visual is welded to the right forearm",
		kanabo_visual != null and kanabo_visual.mesh != null)
	var profile_leash := float(oni.profile.tactics.get("leash_radius", 0.0)) if oni.profile else 0.0
	_check("Boss leash radius keeps it roaming the arena (>= 40 m, got %.0f m)" % profile_leash,
		profile_leash >= 40.0)

	# The AI decision path must reach the speech bubble and show the AI text.
	brain.apply_ai_decision({"tactic": "advance", "attack": "slam", "speech": "Poczuj gniew demonów!", "source": "ai"})
	await _frames(6)
	_check("AI decision text is shown in the boss speech bubble (got '%s')" % oni.speech_bubble.get_text(),
		oni.speech_bubble.is_showing() and oni.speech_bubble.get_text() == "Poczuj gniew demonów!")

	# Position player facing boss at 2.4 m along boss forward vector (in view cone, reads all telegraphed attacks)
	var b_pos := oni.root_part().global_position
	var fwd := (player.global_position - b_pos)
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	player.teleport(b_pos + fwd * 2.4, atan2(fwd.x, fwd.z))
	player.look_at(oni.root_part().global_position, Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	await _frames(6)

	# Test all 3 attacks sequentially: vertical (slam), horizontal (sweep), thrust (demon thrust)
	var attacks := ["vertical", "horizontal", "thrust"]
	for atk in attacks:
		var bp := oni.root_part().global_position
		fwd = Vector3(sin(oni._facing_yaw), 0.0, cos(oni._facing_yaw))
		if fwd.length_squared() < 0.01:
			fwd = -oni.root_part().global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length_squared() >= 0.01 else Vector3.FORWARD
		player.teleport(bp + fwd * 2.2, atan2(-fwd.x, -fwd.z))
		player.look_at(oni.root_part().global_position, Vector3.UP)
		player.rotation.x = 0.0
		player.rotation.z = 0.0
		oni.face_toward(player.global_position)
		await _frames(6)

		brain.force_attack(atk)
		var entered_windup := false
		for _chk in 90:
			await _frames(1)
			if brain.state == DuelistBrain.State.ATTACK and brain.attack_phase == DuelistBrain.AttackPhase.WINDUP:
				entered_windup = true
				break
		_check("Attack '%s' enters telegraph/windup phase" % atk, entered_windup)

		# Advance through windup to strike (must see STRIKE, RECOVER alone is not enough)
		var saw_windup := false
		var reached_strike := false
		for _w in 240:
			await _frames(1)
			if brain.state == DuelistBrain.State.ATTACK and brain.attack_phase == DuelistBrain.AttackPhase.WINDUP:
				saw_windup = true
			if brain.attack_phase == DuelistBrain.AttackPhase.STRIKE:
				reached_strike = true
				break
		_check("Attack '%s' really reaches STRIKE after a windup > 0 s (windup %.2f s, saw windup %s)" % [atk, brain.last_windup_time, str(saw_windup)],
			saw_windup and reached_strike and brain.last_windup_time > 0.0)

		# Await recovery back to STALK before triggering next attack
		for _rec in 90:
			await _frames(2)
			if is_instance_valid(brain) and brain.state == DuelistBrain.State.STALK:
				break
		await _frames(6)

	# Verify behavioral changes between Phase 1 and Phase 3 (windup scaling and speed)
	var max_hp: float = oni.profile.max_hp if (is_instance_valid(oni) and oni.profile) else 100.0

	oni.hp = max_hp
	brain.update_combat_phase()
	var p1_windup_scale: float = brain.difficulty.windup_scale
	var p1_speed: float = brain.difficulty.move_speed
	_check("Phase 1 has standard telegraph windup (scale %.2f)" % p1_windup_scale, p1_windup_scale >= 1.0)
	brain.difficulty.hesitate_chance = 0.0
	brain.difficulty.feint_chance = 0.0
	var p1_measured := await _measure_attack_windup(oni, brain, player, run)
	_check("Phase 1 really winds up before STRIKE (%.2f s measured)" % p1_measured, p1_measured > 0.0)

	oni.hp = max_hp * 0.50
	brain.update_combat_phase()
	_check("Phase 2 transitions at 50%% HP", brain.current_phase == 2)

	oni.hp = max_hp * 0.20
	brain.update_combat_phase()
	var p3_windup_scale: float = brain.difficulty.windup_scale
	var p3_speed: float = brain.difficulty.move_speed
	_check("Phase 3 transitions at 20%% HP", brain.current_phase == 3)
	# Remove hesitation/feint randomness so the measured windups are comparable.
	brain.difficulty.hesitate_chance = 0.0
	brain.difficulty.feint_chance = 0.0
	var p3_measured := await _measure_attack_windup(oni, brain, player, run)
	_check("Phase 3 measured windup is significantly shorter (%.2f s vs %.2f s)" % [p3_measured, p1_measured],
		p3_measured > 0.0 and p3_measured < p1_measured * 0.9)
	_check("Phase 3 has increased movement aggression (%.2f vs %.2f m/s)" % [p3_speed, p1_speed],
		p3_speed > p1_speed)
	_check("Phase 3 windup scale is faster than Phase 1 (%.2f vs %.2f)" % [p3_windup_scale, p1_windup_scale],
		p3_windup_scale < p1_windup_scale)

	run.queue_free()
	await _frames(4)


func _test_real_physical_hit_and_parry() -> void:
	print("\n[TEST] 4. Real Physical Hit & Parry Deflection")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	run.wave_director.boss_katana_duelist = false  # F5: the old kanabō Oni, by flag
	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	var health := run.get_tree().get_first_node_in_group("player_health") as PlayerHealth
	# Measured in the boss frame: the kanabō chop lands ~1.73 m forward of the pelvis
	# at x ≈ 0; with the 0.2 m torso capsule and 0.105 m head radius the contact zone is
	# 1.43–2.03 m. Stand in its middle so the hit is decided by the swing, not by a
	# player standing on the zone's edge. No hesitation, feint or block rolls here.
	var strike_line := 1.7
	var brain_sp := oni.brain as DuelistBrain
	brain_sp.set_seed(4)
	brain_sp.difficulty.hesitate_chance = 0.0
	brain_sp.difficulty.feint_chance = 0.0
	brain_sp.difficulty.block_chance = 0.0

	_check("Player health node present", health != null)
	if health:
		# 1. Real Physical Hit: Player standing directly in boss front attack line
		var bp := oni.root_part().global_position
		var fwd := Vector3(sin(oni._facing_yaw), 0.0, cos(oni._facing_yaw))
		if fwd.length_squared() < 0.01:
			fwd = -oni.root_part().global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length_squared() >= 0.01 else Vector3.FORWARD
		health.max_hp = 100.0
		health.hp = 100.0
		player.teleport(bp + fwd * strike_line, atan2(-fwd.x, -fwd.z))
		player.look_at(oni.root_part().global_position, Vector3.UP)
		player.rotation.x = 0.0
		player.rotation.z = 0.0
		oni.face_toward(player.global_position)
		await _frames(8)

		var hp_before := health.hp
		oni.play_attack("vertical")
		var hit_connected := false
		for _s in 180:
			await _frames(2)
			if health.hp < hp_before:
				hit_connected = true
				break

		_check("Kanabō physical swing connects with player hurtbox and lowers HP (%.1f -> %.1f)" % [hp_before, health.hp],
			hit_connected and health.hp < hp_before)

		# Wait for recovery back to STALK
		for _rec in 60:
			await _frames(2)
			if (oni.brain as DuelistBrain).state == DuelistBrain.State.STALK:
				break
		await _frames(8)

		# 2. Parry Deflection: Player raises high block with katana; contact in STRIKE deflects kanabō
		var hp_during_parry := health.hp
		if run.katana and not player.holder.held:
			player.take_weapon(run.katana)
		var bp2 := oni.root_part().global_position
		var dir2 := player.global_position - bp2
		dir2.y = 0.0
		dir2 = dir2.normalized() if dir2.length_squared() >= 0.01 else Vector3.FORWARD
		# The high guard holds the katana 0.42 m in front of the eyes (BLOCK_HIGH z), so the
		# body stands one guard-length behind the chop line: the katana, not the torso,
		# meets the kanabō.
		# Freeze the boss's pursuit for the parry: otherwise it walks up to its standoff and
		# drags the katana off the chop line.
		brain_sp.difficulty.move_speed = 0.0
		var parry_line := strike_line + 0.42
		var ground2 := run.forest_world.height_at(bp2.x + dir2.x * parry_line, bp2.z + dir2.z * parry_line)
		player.teleport(Vector3(bp2.x + dir2.x * parry_line, ground2, bp2.z + dir2.z * parry_line), atan2(-dir2.x, -dir2.z))
		player.look_at(oni.root_part().global_position, Vector3.UP)
		player.rotation.x = 0.0
		player.rotation.z = 0.0
		oni.face_toward(player.global_position)
		# Hold the high guard for ~1 s before the cut, as the duelist parry test does,
		# so the katana is already up on the chop line when the kanabō comes down.
		player.force_block = true
		events.clear()
		await _frames(90)
		var parry_brain := oni.brain as DuelistBrain
		parry_brain.force_attack("vertical")
		var parried := false
		for _p in 240:
			await _frames(1)
			if events.any(func(e: Dictionary): return e.type == "parry"):
				parried = true
				break
		await _frames(4)
		player.force_block = false

		_check("Real katana vs kanabō contact in STRIKE is a parry", parried)
		_check("Successful parry inflicts ZERO damage on player (%.1f == %.1f HP)" % [health.hp, hp_during_parry],
			health.hp == hp_during_parry)
		_check("Parry opens counter window on boss (> 0 s, got %.2f s)" % oni.counter_time_left(),
			oni.counter_time_left() > 1.0)
		_check("Sword attack cancelled upon parry", oni.sword != null and not oni.sword.attacking)

	run.queue_free()
	await _frames(4)


## The HTTP reply path: a good reply (also when fenced in markdown) becomes an
## "ai" decision; a failed request, an error status, or a reply that is not the
## expected JSON falls back locally so the boss always gets a decision.
func _test_http_reply_parsing() -> void:
	print("\n[TEST] 6. AI HTTP reply parsing")
	var client := OniAiClient.new()
	add_child(client)
	var decision := JSON.stringify({"tactic": "advance", "attack": "thrust", "speech": "Hej"})
	var good := JSON.stringify({"choices": [{"message": {"content": decision}}]})
	var fenced := JSON.stringify({"choices": [{"message": {"content": "```json\n" + decision + "\n```"}}]})

	var ok := _http_reply(client, HTTPRequest.RESULT_SUCCESS, 200, good)
	_check("a good reply is used as the AI decision", ok.get("source") == "ai" and ok.get("tactic") == "advance")
	var md := _http_reply(client, HTTPRequest.RESULT_SUCCESS, 200, fenced)
	_check("a reply fenced in markdown is still read", md.get("source") == "ai" and md.get("attack") == "thrust")
	var net := _http_reply(client, HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	_check("a failed connection falls back locally", net.get("source") == "fallback")
	var bad_status := _http_reply(client, HTTPRequest.RESULT_SUCCESS, 500, good)
	_check("an error status falls back locally", bad_status.get("source") == "fallback")
	var not_json := _http_reply(client, HTTPRequest.RESULT_SUCCESS, 200, "<html>")
	_check("a non-JSON body falls back locally", not_json.get("source") == "fallback")
	var no_choices := _http_reply(client, HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"error": "quota"}))
	_check("a reply without choices falls back locally", no_choices.get("source") == "fallback")
	var bad_content := _http_reply(client, HTTPRequest.RESULT_SUCCESS, 200,
		JSON.stringify({"choices": [{"message": {"content": "sorry, no json"}}]}))
	_check("a reply whose content is not JSON falls back locally", bad_content.get("source") == "fallback")

	client._is_busy = false
	var late := {}
	client._pending_callback = func(d: Dictionary) -> void: late.merge(d, true)
	client._on_http_request_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), good.to_utf8_buffer())
	_check("a reply that arrives with no request in flight is ignored", late.is_empty())
	client.queue_free()


func _http_reply(client: OniAiClient, result: int, code: int, body: String) -> Dictionary:
	var got := {}
	client._is_busy = true
	client._pending_callback = func(d: Dictionary) -> void: got.merge(d, true)
	client._on_http_request_completed(result, code, PackedStringArray(), body.to_utf8_buffer())
	return got


func _test_ai_brain_mock_and_failsafe() -> void:
	print("\n[TEST] 5. AI Brain Mock & Failsafe Resilience")
	var ai_client := OniAiClient.new()
	add_child(ai_client)

	# 1. Mock integration with whitelisted tactic & attack
	var box := {"called": false, "result": {}}
	ai_client.set_mock_provider(func(_state: Dictionary) -> Dictionary:
		box["called"] = true
		return {
			"tactic": "advance",
			"attack": "thrust",
			"speech": "Poczuj gniew demonów!"
		}
	)

	ai_client.request_decision({"player_hp": 80.0}, func(res: Dictionary):
		box["result"] = res
	)
	await _frames(2)

	_check("Mock provider was invoked", box["called"])
	_check("Whitelisted tactic returned (advance)", box["result"].get("tactic") == "advance")
	_check("Whitelisted attack returned (thrust)", box["result"].get("attack") == "thrust")
	_check("Whitelisted speech returned (Poczuj gniew demonów!)", box["result"].get("speech") == "Poczuj gniew demonów!")

	# 2. Failsafe: provider returns invalid malicious tactic and attack
	ai_client.set_mock_provider(func(_state: Dictionary) -> Dictionary:
		return {
			"tactic": "INVALID_TELEPORT_HACK",
			"attack": "DROP_TABLE_PLAYERS",
			"speech": "A".repeat(300)
		}
	)

	var sanitized_box := {"result": {}}
	ai_client.request_decision({}, func(res: Dictionary):
		sanitized_box["result"] = res
	)
	await _frames(2)

	var s_tactic := String(sanitized_box["result"].get("tactic", ""))
	var s_attack := String(sanitized_box["result"].get("attack", ""))
	_check("Invalid tactic sanitized to whitelist (got %s)" % s_tactic,
		OniAiClient.VALID_TACTICS.has(s_tactic))
	_check("Invalid attack sanitized to whitelist (got %s)" % s_attack,
		OniAiClient.VALID_ATTACKS.has(s_attack))
	_check("Speech length sanitized (<= 80 chars, got %d)" % String(sanitized_box["result"].get("speech", "")).length(),
		String(sanitized_box["result"].get("speech", "")).length() <= 80)

	# 2b. Null/malformed provider result -> local fallback with non-empty speech
	ai_client.set_mock_provider(func(_state: Dictionary) -> Variant:
		return null
	)
	var null_box := {"result": {}}
	ai_client.request_decision({"phase": 2}, func(res: Dictionary): null_box["result"] = res)
	await _frames(2)
	_check("Null provider -> local fallback with non-empty speech ('%s')" % String(null_box["result"].get("speech", "")),
		String(null_box["result"].get("source", "")) == "fallback"
		and String(null_box["result"].get("speech", "")).strip_edges() != ""
		and OniAiClient.VALID_TACTICS.has(String(null_box["result"].get("tactic", ""))))
	ai_client.set_mock_provider(func(_state: Dictionary) -> Variant:
		return "boom"
	)
	var junk_box := {"result": {}}
	ai_client.request_decision({}, func(res: Dictionary): junk_box["result"] = res)
	await _frames(2)
	_check("Malformed provider result -> local fallback with non-empty speech",
		String(junk_box["result"].get("source", "")) == "fallback"
		and String(junk_box["result"].get("speech", "")).strip_edges() != "")

	# 3. The endpoint configured in Settings is the URL actually requested (no network).
	ai_client.clear_mock_provider()
	var old_endpoint: String = VrComfortSettings.ai_endpoint
	var old_key: String = VrComfortSettings.meta_api_key
	var old_enabled: bool = VrComfortSettings.ai_boss_enabled
	var capture := {"url": "", "called": false}
	VrComfortSettings.ai_endpoint = "https://endpoint.test/v1/chat/completions"
	VrComfortSettings.meta_api_key = "test-key-not-a-secret"
	VrComfortSettings.ai_boss_enabled = true
	ai_client.set_request_hook(func(url: String, _headers: PackedStringArray, _body: String) -> int:
		capture["url"] = url
		capture["called"] = true
		return OK
	)
	ai_client.request_decision({"distance": 2.0}, func(_res: Dictionary): pass)
	_check("Settings endpoint reaches the request URL (%s)" % capture["url"],
		capture["called"] and capture["url"] == "https://endpoint.test/v1/chat/completions")
	_check("OniAiClient default endpoint is Meta Model API (%s)" % OniAiClient.DEFAULT_META_ENDPOINT,
		OniAiClient.DEFAULT_META_ENDPOINT == VrComfortSettings.DEFAULT_META_ENDPOINT
		and OniAiClient.DEFAULT_META_ENDPOINT == "https://api.meta.ai/v1/chat/completions")
	VrComfortSettings.meta_api_key = old_key
	VrComfortSettings.ai_boss_enabled = old_enabled
	VrComfortSettings.ai_endpoint = old_endpoint

	ai_client.queue_free()
	await _frames(2)


func _test_real_pixel_contrast_and_fog_readability() -> void:
	print("\n[TEST] 6. Real Pixel Contrast & 8 m Fog Readability")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(10)

	var player := run.player as DesktopPlayer
	var cam: Camera3D = player.camera
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	run.wave_director.boss_katana_duelist = false  # F5: the old kanabō Oni, by flag
	var oni: RunOniBoss = run.wave_director.spawn_oni_boss(player.global_position)
	await _frames(10)

	# 1. 5.0 m Distance Viewport Render
	oni.global_rotation = Vector3(0.0, 0.0, 0.0)
	oni.global_position = Vector3(0.0, 0.0, -5.0)
	oni.home_position = oni.global_position
	oni.anchor_position = oni.global_position
	oni.reset()
	player.teleport(Vector3(0.0, 0.0, 0.0), 0.0)
	await _frames(15)

	var ground5 := run.forest_world.height_at(0.0, -5.0)
	oni.global_position = Vector3(0.0, ground5, -5.0)
	oni.home_position = oni.global_position
	oni.anchor_position = oni.global_position
	oni.reset()
	player.teleport(Vector3(0.0, run.forest_world.height_at(0.0, 0.0), 0.0), 0.0)
	await _frames(15)

	var head_pos := oni.head_part().global_position
	var feet_pos := oni.root_part().global_position
	feet_pos.y = oni.get_feet_lowest_y()

	_check("Boss is within camera view frustum at 5 m",
		cam.is_position_in_frustum(head_pos) and cam.is_position_in_frustum(feet_pos))

	# Show speech bubble with high-contrast text
	oni.speech_bubble.instant_show("Ten las spłynie twoją krwią!")
	await _frames(8)

	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var shell := oni.find_child("OniBodyShell", true, false) as MeshInstance3D
		var torso_pos := head_pos
		if shell and shell.mesh:
			torso_pos = shell.global_transform * shell.mesh.get_aabb().get_center()
		var sp_torso := cam.unproject_position(torso_pos)
		var sp_bg := cam.unproject_position(head_pos + Vector3(2.2, 0.0, 0.0))
		var sp_bubble := cam.unproject_position(oni.speech_bubble.global_position)

		var c_torso := _sample_color(img, sp_torso, 4)
		oni.visible = false
		await RenderingServer.frame_post_draw
		var bg_img := get_viewport().get_texture().get_image()
		oni.visible = true
		await RenderingServer.frame_post_draw
		var c_background := _sample_color(bg_img, sp_torso, 4)
		var torso_delta := _color_delta(c_torso, c_background)
		var l_fog := _sample_luminance(img, sp_bg)
		var l_bubble := _sample_luminance(img, sp_bubble)
		var contrast_bubble := (maxf(l_bubble, l_fog) + 0.05) / (minf(l_bubble, l_fog) + 0.05)
		print("DEBUG 5m: torso=%s bg=%s bub=%s torso_delta=%.3f l_fog=%.4f l_bub=%.4f c_bub=%.2f:1" % [sp_torso, sp_bg, sp_bubble, torso_delta, l_fog, l_bubble, contrast_bubble])
		_check("Torso shell silhouette differs from the background behind it (delta %.3f >= 0.10)" % torso_delta,
			torso_delta >= 0.10)
		_check("Speech bubble pixel contrast at 5 m >= 2.0:1 (got %.2f:1)" % contrast_bubble, contrast_bubble >= 2.0)

		# 2. Fog Readability at 8.0 m
		oni.global_rotation = Vector3(0.0, 0.0, 0.0)
		oni.global_position = Vector3(0.0, 0.0, -8.0)
		oni.home_position = oni.global_position
		oni.anchor_position = oni.global_position
		oni.reset()
		oni.speech_bubble.instant_show("Nikt nie ujdzie z tej puszczy!")
		await _frames(12)
		await RenderingServer.frame_post_draw
		var img8 := get_viewport().get_texture().get_image()
		var bubble_pos8 := oni.speech_bubble.global_position
		var sp_bubble8 := cam.unproject_position(bubble_pos8)
		var sp_fog8 := cam.unproject_position(bubble_pos8 + Vector3(1.5, 0.0, 0.0))

		var l_bub8 := _sample_luminance(img8, sp_bubble8)
		var l_fog8 := _sample_luminance(img8, sp_fog8)
		var contrast8 := (maxf(l_bub8, l_fog8) + 0.05) / (minf(l_bub8, l_fog8) + 0.05)
		_check("Speech bubble readable in fog at 8 m (contrast %.2f:1 >= 1.8:1)" % contrast8, contrast8 >= 1.8)
	else:
		_skip("Real pixel contrast & 8 m fog readability need a rendered window (headless has no framebuffer)")

	run.queue_free()
	await _frames(4)


func _sample_luminance(img: Image, pos: Vector2, radius: int = 2) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var count := 0
	var cx := int(round(pos.x))
	var cy := int(round(pos.y))
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and x < w and y >= 0 and y < h:
				var c := img.get_pixel(x, y)
				sum += _luminance(c)
				count += 1
	return sum / maxf(float(count), 1.0)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s" % label)
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _measure_attack_windup(oni: RunOniBoss, brain: DuelistBrain, player: DesktopPlayer, run: RunGame) -> float:
	var bp := oni.root_part().global_position
	var fwd := player.global_position - bp
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() >= 0.01 else Vector3.FORWARD
	var target := bp + fwd * 2.2
	var ground := run.forest_world.height_at(target.x, target.z)
	player.teleport(Vector3(target.x, ground, target.z), atan2(-fwd.x, -fwd.z))
	player.look_at(oni.root_part().global_position, Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	oni.face_toward(player.global_position)
	# Wait until the boss is back in STALK so force_attack is not dropped mid-recover.
	for _w in 300:
		await _frames(1)
		if brain.state == DuelistBrain.State.STALK:
			break
	await _frames(4)
	oni.face_toward(player.global_position)
	brain.last_windup_time = 0.0
	brain.force_attack("vertical")
	var saw_windup := false
	for _w in 240:
		await _frames(1)
		if brain.attack_phase == DuelistBrain.AttackPhase.WINDUP:
			saw_windup = true
		if brain.attack_phase == DuelistBrain.AttackPhase.STRIKE:
			return brain.last_windup_time if saw_windup else -1.0
	return -1.0


func _skip(label: String) -> void:
	print("SKIP  %s" % label)


func _sample_color(img: Image, pos: Vector2, radius: int = 2) -> Color:
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	var cx := int(round(pos.x))
	var cy := int(round(pos.y))
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				sum += img.get_pixel(x, y)
				count += 1
	return sum / maxf(float(count), 1.0)


func _color_delta(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()



## F5: the run boss is the test-room katana duelist, driven by the AI client.
func _test_f5_katana_boss_in_run() -> void:
	print("\n[TEST] F5. Katana duelist boss in the run (demo profile, AI tactics, fallback, defeat)")
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var player := run.player as DesktopPlayer
	var health := run.get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health:
		health.max_hp = 100000.0
		health.hp = 100000.0
	var director := run.wave_director
	# The demo run in fixed 0.1 s steps of virtual time (the N7 stand-in player kills the
	# yōkai): the boss is looked at the moment the director places it (~2:00).
	await _frames(60)
	run.set_physics_process(false)
	director.profile = load(WaveProfile.preset_path("demo")) as WaveProfile
	var seen := {"t": -1.0, "katana": false, "brain": false, "sword": false, "kanabo": true, "shell": true, "mask": false, "hp": 0.0}
	director.oni_spawned.connect(func(b: RunOniBoss) -> void:
		if seen.t >= 0.0:
			return
		var bb := b.brain as OniBossBrain
		seen.t = director.run_seconds
		seen.katana = b.katana_duelist
		seen.brain = bb != null and bb.katana_mode and bb.ai_client != null and bb.ai_client.katana_mode
		seen.sword = b.sword != null and b.sword.visible
		seen.kanabo = b.find_child("OniKanaboVisual", true, false) != null
		seen.shell = b.find_child("OniBodyShell", true, false) != null
		seen.mask = b.find_child("OniMask", true, false) != null
		seen.hp = b.profile.max_hp)
	var sim := N7PacingSim.new()
	await sim.play(get_tree(), run, director, 160.0, 20260604, false)
	run.set_physics_process(true)
	_check("Demo run: the boss appears at the Oni's moment (%.1f s, in [60, 100], N13)" % seen.t,
		seen.t >= 60.0 and seen.t <= 100.0)
	_check("Run boss = the katana duelist (katana visible, no kanabō/Oni shell, demon mask on)",
		seen.katana and seen.sword and not seen.kanabo and not seen.shell and seen.mask)
	_check("Run boss brain drives the duelist in katana mode with the AI client", seen.brain)
	var standard_hp := EnemyCatalog.make_swarm_profile(director.get_profile().hp_for(1, 0.0)).max_hp
	_check("Boss has more HP than a plain enemy (%.0f vs %.0f)" % [seen.hp, standard_hp],
		seen.hp > standard_hp * 3.0)

	# Fresh boss close by, the yōkai of the demo cleared away.
	director.stop_director()
	director.clear_enemies()
	var boss := director.spawn_oni_boss(player.global_position)
	var brain := boss.brain as OniBossBrain
	await _frames(30)
	var h := boss.get_measured_height()
	# N13: a head taller than the yōkai (body_scale 1.08), still a man, not the 2.7 m Oni.
	_check("Swordsman silhouette is a tall man (%.2f m, 1.85–2.3 m)" % h, h >= 1.85 and h <= 2.3)
	_check("N13 entrance: the boss holds and faces the player first (intro %.2f s)" % brain.intro_hold,
		brain.intro_hold > 0.5 and boss.speech_bubble.is_showing())

	# 1. The mock AI answers "flank_left": the brain takes the tactic and circles to its left.
	# A box, not a plain local: lambdas capture locals by value.
	var reply := {"r": {"tactic": "flank_left", "attack": "sweep", "speech": "Twój bok jest odsłonięty."}}
	brain.ai_client.set_mock_provider(func(_state: Dictionary) -> Dictionary: return reply.r)
	boss.global_position = player.global_position + Vector3(0.0, 0.0, -2.4)
	boss.reset_body()
	await _frames(10)
	brain._ai_timer = 0.0
	await _frames(3)
	_check("AI reply sets the swordsman tactic (got %s)" % brain.current_tactic, brain.current_tactic == "flank_left")
	_check("AI speech shows in the bubble ('%s')" % boss.speech_bubble.get_text(),
		boss.speech_bubble.is_showing() and boss.speech_bubble.get_text() == "Twój bok jest odsłonięty.")
	var p0 := boss.root_part().global_position
	var fwd := player.global_position - p0
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	brain._ai_timer = 99.0
	await _frames(120)
	var lateral := (boss.root_part().global_position - p0).dot(side)
	_check("flank_left is executed: the boss steps sideways to its left (%.2f m)" % lateral, lateral > 0.25)

	# 2. The next reply switches to "retreat": the boss gives ground.
	reply.r = {"tactic": "retreat", "speech": "Jeszcze nie teraz."}
	var d0 := _flat_dist(boss.root_part().global_position, player.global_position)
	brain._ai_timer = 0.0
	await _frames(3)
	brain._ai_timer = 99.0
	await _frames(60)
	var d1 := _flat_dist(boss.root_part().global_position, player.global_position)
	_check("The reply changes the tactic to retreat and the boss backs off (%.2f -> %.2f m; body state %d, balance %.2f, blocked %s, brain state %d)" % [
			d0, d1, boss.state, boss.balance, str(boss._move_blocked), brain.state],
		brain.current_tactic == "retreat" and d1 > d0 + 0.3)

	# 3. No key: the local fallback answers at once, the duelist keeps its own logic.
	brain.ai_client.clear_mock_provider()
	var old_key: String = VrComfortSettings.meta_api_key
	VrComfortSettings.meta_api_key = ""
	brain.tactic_time_left = 0.0
	boss.global_position = player.global_position + Vector3(0.0, 0.0, -6.0)
	boss.reset_body()
	await _frames(5)
	brain._ai_timer = 0.0
	await _frames(3)
	_check("No key -> fallback decision without waiting (tactic %s, busy %s)" % [brain.current_tactic, brain.ai_client._is_busy],
		brain.current_tactic == "duel" and not brain.ai_client._is_busy
		and String(brain._last_ai_decision.get("source", "")) == "fallback")
	for _k in 200:
		await _frames(2)
		if _flat_dist(boss.root_part().global_position, player.global_position) <= 3.0:
			break
	var df := _flat_dist(boss.root_part().global_position, player.global_position)
	_check("Fallback boss keeps fighting: it closes in from 6 m (%.2f m)" % df, df <= 3.0)
	VrComfortSettings.meta_api_key = old_key

	# 4. HP -> 0 ends the fight: the boss is defeated for good.
	var defeated := {"hit": false}
	director.oni_defeated.connect(func(_o: RunOniBoss, _h: Dictionary) -> void: defeated.hit = true)
	var chest := boss.parts["chest"] as RagdollPart
	boss.receive_hit(chest, {
		"base_damage": boss.hp + 50.0, "zone": "torso", "element": "physical",
		"point": chest.global_position, "knockback": Vector3.ZERO,
	})
	var wait := int((boss.profile.knockdown_time + boss.profile.getup_time + 0.3) * Engine.physics_ticks_per_second)
	await _frames(wait)
	_check("HP -> 0 defeats the katana boss (signal %s, active %s, hp %.1f, dead %s, body state %s)" % [defeated.hit, director.has_active_oni(),
			boss.hp if is_instance_valid(boss) else 0.0, str(boss.is_dead) if is_instance_valid(boss) else "freed",
			str(boss.state) if is_instance_valid(boss) else "freed"],
		defeated.hit and not director.has_active_oni())
	run.queue_free()
	await _frames(4)


# --- N8: Meta AI end-to-end against the local mock API ---------------------------------

func _test_n8_meta_ai_end_to_end() -> void:
	print("\n[TEST] N8. Meta AI end-to-end: run.tscn + local mock chat-completions server")
	var server := MetaApiMockServer.new()
	add_child(server)
	var started := server.start()
	_check("mock API server listens on loopback (port %d)" % server.port, started == OK)
	var old := [VrComfortSettings.ai_endpoint, VrComfortSettings.meta_api_key,
		VrComfortSettings.ai_boss_enabled, VrComfortSettings.ai_demo_overlay]
	VrComfortSettings.ai_endpoint = server.endpoint()
	VrComfortSettings.meta_api_key = "test-key-not-a-secret"
	VrComfortSettings.ai_boss_enabled = true
	VrComfortSettings.ai_demo_overlay = true
	_check("debug build honours the loopback endpoint (%s)" % OniAiClient.resolve_endpoint(server.endpoint()),
		OniAiClient.resolve_endpoint(server.endpoint()) == server.endpoint())

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var player := run.player as DesktopPlayer
	var health := run.get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health:
		health.max_hp = 100000.0
		health.hp = 100000.0
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	# Telemetry: the player's last cuts all travel right -> left with fire on the blade.
	var cam := get_viewport().get_camera_3d()
	var right := cam.global_basis.x if cam else Vector3.RIGHT
	for k in 5:
		GameEvents.log_event("hit", {"attacker": "katana", "element": "fire", "direction": -right})
	var boss := director.spawn_oni_boss(player.global_position)
	var brain := boss.brain as OniBossBrain
	var client := brain.ai_client
	boss.global_position = player.global_position + Vector3(0.0, 0.0, -2.4)
	boss.reset_body()
	var sent: Array[int] = []
	client.request_sent.connect(func(_u: String) -> void: sent.append(Engine.get_physics_frames()))
	var got: Array[Dictionary] = []
	client.decision_received.connect(func(d: Dictionary) -> void: got.append(d))
	brain._ai_timer = 0.3
	var hz := float(Engine.physics_ticks_per_second)
	var first_ai := -1
	var first_ai_abs := -1
	var p0 := Vector3.ZERO
	var side := Vector3.ZERO
	var lateral := 0.0
	var bubble_text := ""
	var thought := ""
	for f in int(14.0 * hz):
		await get_tree().physics_frame
		if first_ai < 0 and got.size() > 0 and String(got[0].get("source", "")) == "ai":
			first_ai = f
			first_ai_abs = Engine.get_physics_frames()
			bubble_text = boss.speech_bubble.get_text() if boss.speech_bubble.is_showing() else ""
			thought = boss.speech_bubble.get_thought() if boss.speech_bubble.is_overlay_showing() else ""
			p0 = boss.root_part().global_position
			var fwd := player.global_position - p0
			fwd.y = 0.0
			side = Vector3(fwd.normalized().z, 0.0, -fwd.normalized().x)
		if first_ai >= 0 and f == first_ai + 120:
			lateral = (boss.root_part().global_position - p0).dot(side)
	_check("the boss asked the mock API over HTTP (%d requests)" % server.requests.size(), server.requests.size() >= 3)
	_check("first AI reply arrives within 1 s of the request (%d frames)" % (first_ai_abs - (sent[0] if sent.size() > 0 else 0)),
		first_ai >= 0 and sent.size() > 0 and first_ai_abs - sent[0] <= int(hz))
	var gaps_ok := sent.size() >= 3
	var gaps: Array[float] = []
	for k in range(1, sent.size()):
		var g := float(sent[k] - sent[k - 1]) / hz
		gaps.append(snappedf(g, 0.01))
		gaps_ok = gaps_ok and g >= 1.95 and g <= 5.05
	_check("requests every 2–5 s, never per frame (gaps %s)" % [gaps], gaps_ok)
	_check("Authorization carries the Settings key as Bearer", server.auth_headers.size() > 0
		and server.auth_headers[0] == "Bearer test-key-not-a-secret")
	var req: Dictionary = server.requests[0] if server.requests.size() > 0 else {}
	var user_json: Variant = {}
	if req.has("messages") and (req.messages as Array).size() >= 2:
		user_json = JSON.parse_string(String(req.messages[1].get("content", "")))
	var style: Dictionary = (user_json as Dictionary).get("player_style", {}) if user_json is Dictionary else {}
	_check("prompt carries the player's style (%s)" % style,
		String(style.get("cut_from", "")) == "right" and String(style.get("favourite_element", "")) == "fire")
	_check("the mock reply sets the tactic flank_left (got %s)" % brain.current_tactic,
		got.size() > 0 and String(got[0].get("tactic", "")) == "flank_left")
	_check("flank_left is executed: the boss steps to its left (%.2f m)" % lateral, lateral > 0.25)
	var applied := events.filter(func(e: Dictionary) -> bool:
		return e.get("type") == "oni_ai_decision_applied" and e.get("source") == "ai" and e.get("tactic") == "flank_left")
	_check("the run log records the AI tactic with the boss position (%d entries)" % applied.size(),
		applied.size() > 0 and applied[0].has("x"))
	_check("the AI speech shows in the bubble ('%s')" % bubble_text, bubble_text == "You always cut from the right.")
	_check("demo overlay names tactic and source ('%s')" % thought,
		thought.begins_with("Oni myśli: flank_left") and thought.contains("ai"))
	# The bubble fades after a few seconds when no new line comes.
	brain._ai_timer = 999.0
	await _frames(int((OniSpeechBubble.DEFAULT_DURATION + OniSpeechBubble.FADE_OUT_TIME + 0.4) * hz))
	_check("the bubble is gone a few seconds after the last line", not boss.speech_bubble.is_showing())
	_check("the overlay stays while the setting is on", boss.speech_bubble.is_overlay_showing())
	VrComfortSettings.ai_demo_overlay = false
	await _frames(3)
	_check("overlay off in Settings -> slip hidden", not boss.speech_bubble.is_overlay_showing())

	# Errors: every one falls back locally, the frame never stalls.
	for mode in ["401", "500", "garbage", "bad_content"]:
		server.mode = mode
		var r := await _n8_ask(client)
		_check("%s -> local fallback (%s, %d frames, worst frame %.0f ms)" % [mode, r.d.get("fallback_reason", ""), r.frames, r.worst_ms],
			String(r.d.get("source", "")) == "fallback" and r.frames <= 60 and r.worst_ms < 250.0)
	server.mode = "hang"
	var t := await _n8_ask(client, int(OniAiClient.TIMEOUT_SECONDS * hz * 2.0) + 60)
	# Game time, not frame count: the fallback lands in the tick the 3 s deadline passes.
	var limit_s := OniAiClient.TIMEOUT_SECONDS + float(t.max_dt) * 1.5
	_check("timeout -> fallback the tick the deadline passes (%s, %.3f s game time <= %.3f, %d frames, worst frame %.0f ms)" % [
			t.d.get("fallback_reason", ""), t.game_s, limit_s, t.frames, t.worst_ms],
		String(t.d.get("fallback_reason", "")) == "timeout" and float(t.game_s) <= limit_s
		and float(t.game_s) >= OniAiClient.TIMEOUT_SECONDS - 0.05 and t.worst_ms < 250.0
		and not client._is_busy)
	server.mode = "ok"
	server.decision = {"tactic": "teleport_behind_player", "attack": "nuke", "speech": "Hah."}
	var w := await _n8_ask(client)
	_check("tactic outside the whitelist -> duelist's own logic (got %s / %s)" % [w.d.get("tactic"), w.d.get("attack")],
		String(w.d.get("source")) == "ai" and String(w.d.get("tactic")) == "duel"
		and OniAiClient.VALID_ATTACKS.has(String(w.d.get("attack"))))
	server.decision = {"tactic": "aggressive", "speech": "Twoje cięcia zawsze idą z prawej strony, wędrowcze, a ja to widzę od samego początku tej walki w lesie."}
	var l := await _n8_ask(client)
	var sp := String(l.d.get("speech", ""))
	_check("too-long speech is clipped at a word (%d chars: '%s')" % [sp.length(), sp],
		sp.length() <= OniAiClient.MAX_SPEECH_CHARS and sp.ends_with("…") and sp.begins_with("Twoje cięcia"))
	# No key: answered locally at once, nothing sent.
	VrComfortSettings.meta_api_key = ""
	var before := server.requests.size()
	var nk := {"d": {}}
	var sends := sent.size()
	client.request_decision({"phase": 1}, func(d: Dictionary) -> void: nk.d = d)
	_check("no key -> fallback synchronously, no request, no traffic",
		String(nk.d.get("source", "")) == "fallback" and sent.size() == sends and server.requests.size() == before)

	VrComfortSettings.ai_endpoint = old[0]
	VrComfortSettings.meta_api_key = old[1]
	VrComfortSettings.ai_boss_enabled = old[2]
	VrComfortSettings.ai_demo_overlay = old[3]
	run.queue_free()
	server.queue_free()
	await _frames(4)


## One request through the real HTTP client; returns the decision, frames waited and the
## worst wall-clock frame time while waiting.
func _n8_ask(client: OniAiClient, max_frames: int = 90) -> Dictionary:
	var box := {"d": {}, "done": false}
	client._is_busy = false
	client.request_decision({"phase": 1, "distance": 2.0}, func(d: Dictionary) -> void:
		box.d = d
		box.done = true)
	var frames := 0
	var worst := 0.0
	var game_s := 0.0
	var max_dt := 0.0
	var last := Time.get_ticks_usec()
	while not box.done and frames < max_frames:
		await get_tree().process_frame
		game_s += get_process_delta_time()
		max_dt = maxf(max_dt, get_process_delta_time())
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	return {"d": box.d, "frames": frames, "worst_ms": worst, "game_s": game_s, "max_dt": max_dt}
