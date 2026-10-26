extends Node
## Headless physics checks for the test room. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/physics_test.tscn -- --desktop
## Prints PASS/FAIL per check and exits with code 0 if everything passed.

const ROOM := preload("res://scenes/test_room.tscn")

var room: Node3D
var dummy: TrainingDummy
var player: DesktopPlayer
var sword: HeldWeapon
var hits: Array[Dictionary] = []
var clashes: Array[Dictionary] = []
var failures := 0


func _ready() -> void:
	room = ROOM.instantiate()
	# Damage tests need clean hits on the body; the dummy gets its sword later
	# for the clash test (its guard blocks most slashes, which is intended).
	room.get_node("TrainingDummy").hold_sword = false
	add_child(room)
	dummy = room.dummy
	player = room.player
	sword = room.sword
	GameEvents.hit_landed.connect(func(h): hits.append(h))
	GameEvents.weapon_clash.connect(func(c): clashes.append(c))
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	# 1. The dummy stands up by itself and holds its guard.
	await _wait(3.0)
	_check("dummy stands (pelvis height %.2f m)" % dummy.pelvis_height(), absf(dummy.pelvis_height() - 0.98) < 0.12)
	_check("dummy upright (lean %.1f°)" % dummy.lean_degrees(), dummy.lean_degrees() < 15.0)
	_check("player holds the katana", sword.is_held())

	# 2. Slow vs fast horizontal slash: faster swing -> faster impact, more damage.
	var slow := await _slash_and_get_hit(0.6)
	var fast := await _slash_and_get_hit(0.12)
	_check("slow slash registers a hit", not slow.is_empty())
	_check("fast slash registers a hit", not fast.is_empty())
	if not slow.is_empty() and not fast.is_empty():
		print("    slow: %.1f m/s -> %.1f dmg (%s) | fast: %.1f m/s -> %.1f dmg (%s)" % [
			slow.speed, slow.damage, slow.part, fast.speed, fast.damage, fast.part])
		_check("fast hit is faster than slow", fast.speed > slow.speed)
		_check("fast hit does more damage", fast.damage > slow.damage)

	# 3. Heavy hits stagger, then knock down; the dummy gets up again.
	room.reset_room()
	await _wait(2.0)
	var min_balance := 1.0
	var was_down := false
	for i in 8:
		# Step in 1.15 m in front of the dummy, then a fast slash; 0.55 s apart
		# so balance has little time to recover between hits.
		var target := dummy.root_part().global_position
		player.teleport(Vector3(target.x, 0, target.z + 1.15))
		player.swing_duration = 0.1
		player.swing(DesktopPlayer.SLASH_HORIZONTAL)
		for f in 50:
			await get_tree().physics_frame
			min_balance = minf(min_balance, dummy.balance)
			was_down = was_down or dummy.state != ActiveRagdoll.State.STANDING
		if was_down:
			break
	_check("heavy hits stagger (min balance %.2f)" % min_balance, min_balance < 0.8)
	_check("repeated heavy hits knock the dummy down", was_down)
	player.teleport(Vector3(0, 0, 2.5))  # step back so our blade is not in the way
	var trace := ""
	for k in 12:
		await _wait(0.5)
		trace += " [%d h%.2f l%.0f p%s]" % [dummy.state, dummy.pelvis_height(), dummy.lean_degrees(), Vector2(dummy.root_part().global_position.x, dummy.root_part().global_position.z).snapped(Vector2.ONE * 0.1)]
	if dummy.state != ActiveRagdoll.State.STANDING or dummy.pelvis_height() < 0.83:
		print("    get-up trace (state, pelvis height, lean, pelvis xz every 0.5 s):" + trace)
		print("    joint errors (deg): ", dummy.pose_errors())
		print("    balance %.2f muscle %.2f pelvis v %s time_scale %.2f pose %s anchor %s" % [dummy.balance, dummy.muscle, dummy.root_part().linear_velocity.snapped(Vector3.ONE * 0.01), Engine.time_scale, dummy.current_pose, dummy.anchor_position])
		for n in dummy.parts:
			print("      %-12s %s" % [n, (dummy.parts[n] as Node3D).global_position.snapped(Vector3.ONE * 0.01)])
	_check("dummy gets back up (state %d, height %.2f, lean %.1f°)" % [dummy.state, dummy.pelvis_height(), dummy.lean_degrees()],
		dummy.state == ActiveRagdoll.State.STANDING and absf(dummy.pelvis_height() - 0.98) < 0.15 and dummy.lean_degrees() < 20.0)

	# 4. The held sword cannot be pushed through a wall.
	room.reset_room()
	player.teleport(Vector3(0, 0, -3.9))  # 1.1 m in front of the north wall (inner face z = -5.0)
	await _wait(0.5)
	var deepest := 0.0
	player.swing(DesktopPlayer.THRUST)
	for f in 90:
		await get_tree().physics_frame
		deepest = minf(deepest, sword.get_tip_global().z)
	_check("thrust into the wall stops at the wall (tip z min %.2f, wall face -5.00)" % deepest, deepest > -5.06)

	# 5. The dummy holds a physics sword in its guard; blade vs blade is detected.
	# Step the player back and drop the bokken so it does not push the dummy.
	player.holder.release()
	player.teleport(Vector3(0, 0, 3.5))
	room.reset_room()
	dummy.equip_sword()
	await _wait(2.0)
	var hand := dummy.parts["lower_arm_r"] as RagdollPart
	var sword_gap := dummy.sword.global_position.distance_to(hand.global_transform * Vector3(0, -0.17, 0))
	_check("dummy sword stays in its hand (gap %.2f m)" % sword_gap, sword_gap < 0.12)
	_check("dummy keeps its balance with the sword (lean %.1f°)" % dummy.lean_degrees(), dummy.lean_degrees() < 15.0)
	var holder := WeaponHolder.new()
	room.add_child(holder)
	var blade_mid: Vector3 = dummy.sword.global_transform * Vector3(0, 0, -0.55)
	holder.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), blade_mid + Vector3(1.2, 0.45, 0.0))
	sword.global_transform = holder.global_transform
	holder.grab(sword)
	await _wait(0.3)
	clashes.clear()
	for f in 50:
		holder.global_position += Vector3(-0.05, 0, 0)  # 4.5 m/s sideways through the dummy's blade
		await get_tree().physics_frame
	_check("blade clash detected (%d clash events)" % clashes.size(), clashes.size() > 0)
	if not clashes.is_empty():
		print("    clash: %.1f m/s at %.0f° between blades" % [clashes[0].speed, clashes[0].angle_deg])


## Slash at the dummy with the given swing time; return the first hit (or {}).
func _slash_and_get_hit(duration: float) -> Dictionary:
	room.reset_room()
	player.teleport(Vector3(0, 0, 1.15))
	player.hand_offset = Vector3.ZERO
	await _wait(1.5)
	hits.clear()
	player.swing_duration = duration
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _wait(0.15 + duration + 0.3)
	return hits[0] if not hits.is_empty() else {}


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
