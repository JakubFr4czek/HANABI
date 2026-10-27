extends Node
## The wrist HUD plate must never sink into the XR hand mesh: measured
## against the real hand model's surface (bind pose), the plate bottom
## stays clear untilted and at the maximum eye-tilt, in both directions.
## Run with:
##   godot --headless --path . res://tests/wrist_hud_test.tscn -- --desktop
## Exit code 0 when everything passed.

var failures := 0


func _ready() -> void:
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var xr_player: XRPlayer = load("res://scenes/player/xr_player.tscn").instantiate()
	var start_xr := xr_player.get_node_or_null("StartXR")
	if start_xr:
		xr_player.remove_child(start_xr)
		start_xr.free()
	add_child(xr_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hud := DiegeticHud.new()
	add_child(hud)
	hud.setup(xr_player, null)
	await get_tree().physics_frame

	var ctrl := xr_player.left_controller
	_check("wrist HUD rides the left controller", hud.wrist_unit.get_parent() == ctrl)
	_check("eye tilt is capped (%.0f deg)" % DiegeticHud.MAX_FACE_TILT_DEG,
		DiegeticHud.MAX_FACE_TILT_DEG <= 10.0)

	var hand_mi: MeshInstance3D = null
	for mi in ctrl.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).name == "mesh_Hand_Nails_low_L":
			hand_mi = mi
	_check("XR hand model found for clearance measurement", hand_mi != null)
	if hand_mi == null:
		return
	var inv := ctrl.global_transform.affine_inverse()
	var hverts: Array[Vector3] = []
	var arrs := hand_mi.mesh.surface_get_arrays(0)
	for v in (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		hverts.append(inv * (hand_mi.global_transform * v))

	for tilt_deg in [0.0, 10.0, -10.0]:
		hud.wrist_face.quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(tilt_deg))
		hud.wrist_face.position.y = absf(sin(deg_to_rad(tilt_deg))) * DiegeticHud.PLATE_SIZE.x * 0.57
		await get_tree().physics_frame
		var worst := INF
		for gx in 5:
			for gz in 5:
				var local := Vector3(lerpf(-0.05, 0.05, float(gx) / 4.0), -0.006, lerpf(-0.027, 0.027, float(gz) / 4.0))
				var pc: Vector3 = ctrl.global_transform.affine_inverse() * (hud.wrist_face.global_transform * local)
				var hand_top := -INF
				for hv in hverts:
					if absf(hv.x - pc.x) < 0.008 and absf(hv.z - pc.z) < 0.008:
						hand_top = maxf(hand_top, hv.y)
				if hand_top > -INF:
					worst = minf(worst, pc.y - hand_top)
		_check("plate clears the hand at %.0f deg tilt (worst %.1f mm)" % [tilt_deg, worst * 1000.0],
			worst > 0.0015)
	xr_player.queue_free()


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
