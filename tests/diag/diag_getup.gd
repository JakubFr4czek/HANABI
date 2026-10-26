extends Node3D
## Diagnostic: knock the dummy over in several directions and track the get-up.
const ROOM := preload("res://scenes/test_room.tscn")
func _ready() -> void:
	var room = ROOM.instantiate()
	room.get_node("TrainingDummy").hold_sword = (OS.get_cmdline_user_args().has("--sword"))
	add_child(room)
	var d: TrainingDummy = room.dummy
	room.player.global_position = Vector3(0, 0, 4)
	for dir in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		room.reset_room()
		for i in 90: await get_tree().physics_frame
		(d.parts["chest"] as RigidBody3D).apply_central_impulse(dir * 60.0)
		d.weaken(1.0, 1.0)
		var line := "push %s:" % dir
		for i in 600:
			await get_tree().physics_frame
			if i % 60 == 59:
				line += " [%d h%.2f l%.0f]" % [d.state, d.pelvis_height(), d.lean_degrees()]
		print(line)
	get_tree().quit()
