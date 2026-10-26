extends Node
## Diagnostic: prints target vs actual relative joint angles of the dummy.
const ROOM := preload("res://scenes/test_room.tscn")
func _ready() -> void:
	var room = ROOM.instantiate()
	add_child(room)
	var d: TrainingDummy = room.dummy
	for step in [0.05, 0.5, 1.0, 3.0]:
		while GameEvents.run_time() < step:
			await get_tree().physics_frame
		print("--- t=%.2f  pelvis h=%.2f lean=%.1f" % [step, d.pelvis_height(), d.lean_degrees()])
		var pose: Dictionary = d._define_poses()["guard"]
		for n in d._order:
			var def: Dictionary = d._defs[n]
			if def.get("parent", "") == "":
				var e: Vector3 = (d.parts[n] as Node3D).global_basis.get_euler()
				print("  %-12s world euler %s" % [n, Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)).snapped(Vector3.ONE)])
				continue
			var rel: Basis = (d.parts[def.parent] as Node3D).global_basis.inverse() * (d.parts[n] as Node3D).global_basis
			var e: Vector3 = rel.get_euler()
			print("  %-12s target %s  actual %s" % [n, pose.get(n, Vector3.ZERO), Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)).snapped(Vector3.ONE)])
	get_tree().quit()
