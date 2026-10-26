extends Node
## Diagnostic: katana tracking error per tick when dropping the high block, normal vs compensated slow-mo.
const ROOM := preload("res://scenes/test_room.tscn")
func _ready() -> void:
	var room = ROOM.instantiate()
	add_child(room)
	var p: DesktopPlayer = room.player
	var k: HeldWeapon = room.katana
	p.teleport(Vector3(3, 0, 3))
	for mode in ["normal", "slowmo"]:
		p.force_block = true
		for i in 90: await get_tree().physics_frame
		if mode == "slowmo": TimeController.slow_motion(0.3, 1.0, true)
		p.force_block = false
		var line: String = mode + ":"
		for i in 20:
			await get_tree().physics_frame
			var ang := rad_to_deg(k.global_basis.get_rotation_quaternion().angle_to(p.holder.global_basis.get_rotation_quaternion()))
			line += " %.2f/%.0f°/%.1f" % [k.grip_error, ang, k.angular_velocity.length()]
		print(line)
		TimeController.clear()
	get_tree().quit()
