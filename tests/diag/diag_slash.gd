extends Node
const ROOM := preload("res://scenes/test_room.tscn")
func _ready() -> void:
	var room = ROOM.instantiate()
	add_child(room)
	var player: DesktopPlayer = room.player
	var sword: HeldWeapon = room.sword
	GameEvents.event_logged.connect(func(e): if e.type in ["hit", "clash"]: print("   EVENT ", e.type, " speed=", e.get("speed"), " part=", e.get("part", e.get("defender"))))
	for dur in [0.6, 0.12]:
		room.reset_room()
		player.global_position = Vector3(0, 0, 1.15)
		player.hand_offset = Vector3.ZERO
		for i in 135: await get_tree().physics_frame
		print("== slash duration ", dur)
		player.swing_duration = dur
		player.swing([Vector3(0.6, 0.05, 0), Vector3(-0.6, -0.1, 0)])
		for i in int((0.15 + dur + 0.3) * 90):
			await get_tree().physics_frame
			var st := PhysicsServer3D.body_get_direct_state(sword.get_rid())
			var names := []
			for c in st.get_contact_count():
				var o = st.get_contact_collider_object(c)
				names.append(o.name if o else "?")
			if not names.is_empty() or i % 6 == 0:
				print("  f%03d tip=%s tipspeed=%.1f contacts=%s" % [i, sword.get_tip_global().snapped(Vector3.ONE * 0.01), sword.get_point_velocity(sword.get_tip_global()).length(), names])
	get_tree().quit()
