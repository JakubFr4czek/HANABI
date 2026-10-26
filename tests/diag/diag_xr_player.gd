extends Node
## Diagnostic: the XR rig scene loads and its nodes/scripts resolve (no headset needed).
func _ready() -> void:
	var p = load("res://scenes/player/xr_player.tscn").instantiate()
	add_child(p)
	await get_tree().physics_frame
	for path in ["XROrigin3D/XRCamera3D", "XROrigin3D/LeftHand/WeaponHolder", "XROrigin3D/RightHand/WeaponHolder",
			"XROrigin3D/LeftHand/MovementDirect", "XROrigin3D/RightHand/MovementTurn", "XROrigin3D/PlayerBody", "StartXR"]:
		var n: Node = p.get_node_or_null(path)
		print("%-36s %s" % [path, (n.get_class() + (" script=" + n.get_script().resource_path.get_file() if n.get_script() else "")) if n else "MISSING"])
	print("right holder is WeaponHolder: ", p.right_holder is WeaponHolder, ", camera in player_head group: ", p.get_node("XROrigin3D/XRCamera3D").is_in_group("player_head"))
	get_tree().quit()
