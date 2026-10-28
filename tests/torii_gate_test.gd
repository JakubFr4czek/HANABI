extends Node
## Unit tests for Torii gate crossing, single-element imbue, 20s expiry,
## paused-tree immunity, weapon filtering, and 45m distance reactivation.
##   godot --headless --path . --fixed-fps 90 res://tests/torii_gate_test.tscn -- --desktop

const TORII_SCENE := preload("res://scenes/world/torii_gate.tscn")
const KATANA_SCENE := preload("res://scenes/weapons/katana.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var katana: HeldWeapon = KATANA_SCENE.instantiate()
	add_child(katana)

	var elem_sys := ElementSystem.new()
	elem_sys.name = "ElementSystem"
	add_child(elem_sys)
	elem_sys.setup(null, katana)

	var gate: ToriiGate = TORII_SCENE.instantiate()
	gate.element = Elements.SAKURA
	gate.position = Vector3(0.0, 0.0, 0.0)
	add_child(gate)
	await _frames(3)

	# 1. Crossing plane triggers imbue and deactivates gate
	var fake_body := StaticBody3D.new()
	fake_body.name = "PlayerBody"
	fake_body.collision_layer = ToriiGate.PLAYER_BODY_LAYER
	fake_body.add_to_group("player_body")
	fake_body.position = Vector3(0.0, 1.5, 1.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	fake_body.add_child(shape)
	add_child(fake_body)
	gate.set_player_reference(fake_body)

	await _frames(2)
	# Cross plane from z=1.0 to z=-1.0
	fake_body.position = Vector3(0.0, 1.5, -1.0)
	await _frames(4)

	_check("Crossing plane triggers imbue on katana", katana.element == Elements.SAKURA)
	_check("ElementSystem current_element is updated", elem_sys.current_element == Elements.SAKURA)
	_check("Gate deactivates after crossing", not gate.is_active)
	_check("Timer is initialized to ~20.0 s", elem_sys.element_time_remaining >= 19.5 and elem_sys.element_time_remaining <= 20.0)

	# 2. Real sword touch filter: sword & hand physically enter gate aperture and do NOT imbue
	gate.reactivate()
	katana.set_element(Elements.NONE)
	elem_sys.reset()
	# Move fake player body far away so only weapon is near gate
	fake_body.position = Vector3(100.0, 0.0, 100.0)
	await _frames(2)

	# Katana physically penetrates the gate crossing volume
	katana.position = Vector3(0.0, 1.5, 0.0)
	gate._on_body_entered(katana)
	gate.trigger_cross(katana)
	await _frames(4)

	_check("Sword physical touch alone does not trigger gate imbue", katana.element == Elements.NONE and elem_sys.current_element == Elements.NONE)
	_check("Gate remains active when sword alone enters aperture", gate.is_active)

	# Now player body enters -> must trigger imbue
	fake_body.position = Vector3(0.0, 1.5, 1.0)
	await _frames(2)
	fake_body.position = Vector3(0.0, 1.5, -1.0)
	await _frames(4)
	_check("Player body crossing triggers imbue after sword was rejected", katana.element == Elements.SAKURA and not gate.is_active)

	# 3. Single source of truth & pause immunity: 21s paused tree does not decrement element timer
	elem_sys.imbue(Elements.SAKURA, 20.0)
	var t_before := elem_sys.element_time_remaining
	get_tree().paused = true
	for _i in 210:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)
	_check("21s paused tree does not change element time remaining (frozen at %.1f s)" % elem_sys.element_time_remaining,
		elem_sys.element_time_remaining == t_before and katana.element == Elements.SAKURA)
	get_tree().paused = false

	# 4. Same gate refreshes timer
	# Step timer down by 10 seconds in normal time
	for _i in 100:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)
	_check("Timer stepped down to ~10.0 s", elem_sys.element_time_remaining <= 10.5 and elem_sys.element_time_remaining >= 9.5)

	gate.element = Elements.SAKURA
	gate.reactivate()
	fake_body.position = Vector3(0.0, 1.5, 1.0)
	await _frames(2)
	fake_body.position = Vector3(0.0, 1.5, -1.0)
	await _frames(4)

	_check("Same gate refreshes timer back to 20.0 s", elem_sys.element_time_remaining >= 19.5 and elem_sys.element_time_remaining <= 20.0)
	_check("Katana element remains Sakura", katana.element == Elements.SAKURA)

	# 5. Level-up cards / upgrades do NOT grant element to katana
	elem_sys.reset()
	katana.set_element(Elements.NONE)
	elem_sys.apply_upgrade("storm_chain", {"storm_chain": 1})
	_check("Level-up upgrade does not grant element to katana (remains NONE)",
		katana.element == Elements.NONE and elem_sys.current_element == Elements.NONE and elem_sys.element_time_remaining == 0.0)

	# 6. Different gate replaces element
	var storm_gate: ToriiGate = TORII_SCENE.instantiate()
	storm_gate.element = Elements.STORM
	storm_gate.position = Vector3(10.0, 0.0, 0.0)
	add_child(storm_gate)
	storm_gate.set_player_reference(fake_body)
	await _frames(3)

	fake_body.position = Vector3(10.0, 1.5, 1.0)
	await _frames(2)
	fake_body.position = Vector3(10.0, 1.5, -1.0)
	await _frames(4)

	_check("Different gate replaces element with Storm", katana.element == Elements.STORM)
	_check("ElementSystem reflects new element Storm", elem_sys.current_element == Elements.STORM)
	_check("Timer reset to 20.0 s on new element", elem_sys.element_time_remaining >= 19.5 and elem_sys.element_time_remaining <= 20.0)

	# 7. 20 s timer expires to plain steel
	for _i in 210:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)

	_check("20 s timer expires cleanly to plain steel", katana.element == Elements.NONE)
	_check("ElementSystem current_element is NONE after expiry", elem_sys.current_element == Elements.NONE)
	_check("active_elements is empty after expiry", elem_sys.active_elements.is_empty())

	# 8. Gate reactivates after 45m distance
	storm_gate.is_active = false
	fake_body.position = storm_gate.global_position + Vector3(0.0, 0.0, 20.0)
	await _frames(4)
	_check("Gate remains inactive at 20 m distance", not storm_gate.is_active)

	fake_body.position = storm_gate.global_position + Vector3(0.0, 0.0, 46.0)
	await _frames(4)
	_check("Gate reactivates when player moves >= 45.0 m away", storm_gate.is_active)

	# 9. Sakura Ability 2 (Hanamai) barrier and ongoing completion across 20s gate expiry
	elem_sys.reset()
	katana.set_element(Elements.NONE)
	_check("Plain steel without gate spawns 0 orbit petals", elem_sys._orbit_petals.size() == 0)

	# Cross gate with Sakura element
	gate.element = Elements.SAKURA
	gate.reactivate()
	fake_body.position = Vector3(0.0, 1.5, 1.0)
	await _frames(2)
	fake_body.position = Vector3(0.0, 1.5, -1.0)
	await _frames(4)
	_check("After Sakura gate crossed, element is SAKURA", elem_sys.current_element == Elements.SAKURA)

	# Trigger Hanamai (Ability 2)
	var hanamai_ok := elem_sys.execute_ability_2(Vector3.FORWARD)
	_check("Sakura Ability 2 (Hanamai) triggers barrier petals (count=4)", hanamai_ok and elem_sys._orbit_petals.size() == 4)

	# Step 5 seconds: Hanamai still active (6s total duration, 1s remaining)
	for _i in 50:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)
	_check("Hanamai barrier active at 5s", elem_sys._orbit_petals.size() == 4 and elem_sys.hanamai_time_remaining > 0.0)

	# Step another 2 seconds: Hanamai finishes at 6.0s
	for _i in 20:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)
	_check("Hanamai barrier finishes when its 6s duration ends (count=0)", elem_sys._orbit_petals.size() == 0)

	# Test ongoing ability completion across gate expiry:
	# Trigger Hanamai when gate imbue has only 2s remaining
	elem_sys.element_time_remaining = 2.0
	elem_sys.ability_2_cooldown = 0.0
	elem_sys.execute_ability_2(Vector3.FORWARD)
	_check("Hanamai triggered with 2s gate time remaining", elem_sys._orbit_petals.size() == 4)

	# Step 3.0s: gate element expires at 2.0s (blade plain steel), but Hanamai finishes full duration!
	for _i in 30:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)
	_check("Gate element expired to plain steel", elem_sys.current_element == Elements.NONE and katana.element == Elements.NONE)
	_check("Ongoing Hanamai still active after gate expiry (count=4)", elem_sys._orbit_petals.size() == 4 and elem_sys.hanamai_time_remaining > 0.0)

	# Step another 3.5s: Hanamai finishes full 6s duration
	for _i in 35:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)
	_check("Hanamai cleanly clears after completing full duration (count=0)", elem_sys._orbit_petals.size() == 0)

	katana.queue_free()
	elem_sys.queue_free()
	gate.queue_free()
	storm_gate.queue_free()
	fake_body.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
