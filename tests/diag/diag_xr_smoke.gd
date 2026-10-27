extends Node
const RUN_SCENE := preload("res://scenes/run.tscn")

func _ready() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	add_child(run)
	for i in 60:
		await get_tree().physics_frame
	var xr := run.player as XRPlayer
	print("player is XR: ", xr != null)
	if xr == null:
		get_tree().quit(1)
		return
	var sim := get_tree().get_first_node_in_group("xr_sim") as XrSim
	var cam := xr.get_node("XROrigin3D/XRCamera3D") as Node3D
	print("cam local ", cam.position, " right active ", xr.right_controller.get_is_active(), " right local ", xr.right_controller.position)
	sim.set_head(Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.1, 1.5, 0.0)))
	sim.set_hand("right", Transform3D(Basis.IDENTITY, Vector3(0.3, 1.2, -0.4)))
	for i in 5:
		await get_tree().physics_frame
	print("after move cam local ", cam.position, " yaw ", cam.rotation.y, " right local ", xr.right_controller.position)
	print("hud parent ", run.diegetic_hud.wrist_unit.get_parent().name)
	print("intro active ", run.run_intro.is_active(), " state ", run.state)
	get_tree().quit(0)
