extends Node
## Diagnostic: where the dummy's bokken sits in each block pose, and whether the
## player's scripted swings meet it. Prints blade segments in the dummy's frame
## (x = its left, y = up from the floor, z = toward the player) and the closest
## approach of the player's blade to the dummy's during each swing.
const ROOM := preload("res://scenes/test_room.tscn")
const POSES := ["block_high", "block_left", "block_right", "block_mid"]

var room: Node3D
var dummy: TrainingDummy
var brain: DuelistBrain
var player: DesktopPlayer


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	dummy = room.dummy
	brain = dummy.brain as DuelistBrain
	player = room.player
	await _wait(0.5)
	if OS.get_cmdline_user_args().has("--natural"):
		await _natural()
		get_tree().quit()
		return
	for pose in POSES:
		if not dummy._poses.has(pose):
			continue
		for swing_name in ["horizontal", "overhead"]:
			await _try(pose, swing_name)
	get_tree().quit()


func _try(pose: String, swing_name: String) -> void:
	dummy.set_attacks_enabled(false)
	room.reset_room()
	player.take_weapon(room.katana)
	player.teleport(Vector3(0.0, 0.0, 1.3))
	var d := DuelistDifficulty.preset("normal")
	d.block_chance = 0.0
	d.evade_chance = 0.0
	d.attack_cooldown = Vector2(60, 60)
	dummy.set_difficulty(d)
	await _wait(0.8)
	dummy.set_attacks_enabled(true)
	await _wait(0.1)
	var clashes := [0]
	var cb := func(_c): clashes[0] += 1
	GameEvents.weapon_clash.connect(cb)
	brain._block_pose = pose
	brain._enter(DuelistBrain.State.BLOCK)
	brain.difficulty.block_chance = 0.0
	await _wait(0.12)
	var a := _local(dummy.sword.global_transform * dummy.sword.blade_start)
	var b := _local(dummy.sword.get_tip_global())
	player.swing_duration = 0.3
	player.swing(DesktopPlayer.SLASH_HORIZONTAL if swing_name == "horizontal" else DesktopPlayer.SLASH_OVERHEAD)
	var best := INF
	var best_pts := []
	for i in 40:
		await get_tree().physics_frame
		brain._timer = 0.0  # hold the block for the whole swing
		var w := room.katana as HeldWeapon
		var pa := w.get_blade_start_global()
		var pb := w.get_tip_global()
		var da := dummy.sword.global_transform * dummy.sword.blade_start
		var db := dummy.sword.get_tip_global()
		var pts := Geometry3D.get_closest_points_between_segments(pa, pb, da, db)
		var dist: float = pts[0].distance_to(pts[1])
		if dist < best:
			best = dist
			best_pts = [_local(pa), _local(pb)]
	GameEvents.weapon_clash.disconnect(cb)
	print("%-12s %-10s dummy blade %s -> %s | closest %.3f m, player blade then %s -> %s | clashes %d" % [
		pose, swing_name, a.snapped(Vector3.ONE * 0.01), b.snapped(Vector3.ONE * 0.01), best,
		best_pts[0].snapped(Vector3.ONE * 0.01), best_pts[1].snapped(Vector3.ONE * 0.01), clashes[0]])
	await _wait(0.4)


## The real reaction: block chance 100 %, the dummy decides on its own.
func _natural() -> void:
	dummy.set_attacks_enabled(false)
	room.reset_room()
	player.take_weapon(room.katana)
	player.teleport(Vector3(0.0, 0.0, 1.3))
	var d := DuelistDifficulty.preset("normal")
	d.block_chance = 1.0
	d.evade_chance = 0.0
	d.reaction_time = 0.05
	d.attack_cooldown = Vector2(60, 60)
	d.feint_chance = 0.0
	d.combo_chance = 0.0
	d.riposte_chance = 0.0
	d.hesitate_chance = 0.0
	dummy.set_difficulty(d)
	brain.set_seed(7)
	dummy.set_motion_seed(7)
	await _wait(0.8)
	dummy.set_attacks_enabled(true)
	await _wait(0.6)
	print("dist before swing %.2f, tactic %s" % [Vector2(player.camera.global_position.x - dummy.root_part().global_position.x, player.camera.global_position.z - dummy.root_part().global_position.z).length(), DuelistBrain.TACTIC_NAMES[brain.tactic]])
	GameEvents.event_logged.connect(func(e): if e.type in ["enemy_block", "clash", "enemy_parry"]: print("      event ", e.type, " ", e.get("pose", ""), " landed=", e.get("landed", "")))
	player.swing_duration = 0.3
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	for i in 45:
		await get_tree().physics_frame
		var w := room.katana as HeldWeapon
		var pa := w.get_blade_start_global()
		var pb := w.get_tip_global()
		var da := dummy.sword.global_transform * dummy.sword.blade_start
		var db := dummy.sword.get_tip_global()
		var pts := Geometry3D.get_closest_points_between_segments(pa, pb, da, db)
		print("%2d %-7s %-11s player tip %s  dummy blade %s->%s  gap %.3f" % [i, brain.state_name(), brain._block_pose, _local(pb).snapped(Vector3.ONE * 0.01),
			_local(da).snapped(Vector3.ONE * 0.01), _local(db).snapped(Vector3.ONE * 0.01), pts[0].distance_to(pts[1])])


func _local(p: Vector3) -> Vector3:
	var o := dummy.global_position
	return Basis(Vector3.UP, dummy._facing_yaw).inverse() * (p - Vector3(dummy.root_part().global_position.x, o.y, dummy.root_part().global_position.z))


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
