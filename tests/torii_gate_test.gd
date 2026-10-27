extends Node
## Unit tests for Torii gate crossing, single-element imbue, 20s expiry,
## and 45m distance reactivation (docs/ELEMENTS_PLAN.md Phase E2a).
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

	# 2. Sword touch alone does not trigger
	gate.reactivate()
	katana.set_element(Elements.NONE)
	elem_sys.reset()
	# Move fake body far away
	fake_body.position = Vector3(100.0, 0.0, 100.0)
	await _frames(2)

	# Move katana through gate aperture
	katana.position = Vector3(0.0, 1.5, 1.0)
	await _frames(2)
	katana.position = Vector3(0.0, 1.5, -1.0)
	await _frames(4)

	_check("Sword touch alone does not trigger gate imbue", katana.element == Elements.NONE)
	_check("Gate remains active when sword alone crosses", gate.is_active)

	# 3. Same gate refreshes timer
	elem_sys.imbue(Elements.SAKURA, 20.0)
	# Step timer down by 10 seconds
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

	# 4. Different gate replaces element
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
	_check("ElementSystem active_elements has only Storm", elem_sys.active_elements == [Elements.STORM])
	_check("Timer reset to 20.0 s on new element", elem_sys.element_time_remaining >= 19.5 and elem_sys.element_time_remaining <= 20.0)

	# 5. 20 s timer expires to plain steel
	# Step time past 20.0s (e.g. 21.0 seconds total)
	for _i in 210:
		elem_sys._physics_process(0.1)
		katana._physics_process(0.1)

	_check("20 s timer expires cleanly to plain steel", katana.element == Elements.NONE)
	_check("ElementSystem current_element is NONE after expiry", elem_sys.current_element == Elements.NONE)
	_check("active_elements is empty after expiry", elem_sys.active_elements.is_empty())

	# 6. Gate reactivates after 45m distance (tested with time/physics stepping)
	storm_gate.is_active = false
	fake_body.position = storm_gate.global_position + Vector3(0.0, 0.0, 20.0) # 20m away
	await _frames(4)
	_check("Gate remains inactive at 20 m distance", not storm_gate.is_active)

	# Step player out past 45m (to 46.0m)
	fake_body.position = storm_gate.global_position + Vector3(0.0, 0.0, 46.0)
	await _frames(4)
	_check("Gate reactivates when player moves >= 45.0 m away", storm_gate.is_active)

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
