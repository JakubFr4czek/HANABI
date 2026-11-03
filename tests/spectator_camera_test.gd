extends Node3D
## N10 spectator (demo-recording) camera, headless, fixed delta:
## - never created with the Quest/Android feature tags;
## - a 10 cm head jump moves the smoothed camera <= 2 cm in the first 72 Hz frame, it settles
##   later, and a rolled head still gives a level horizon;
## - third person with a trunk right behind the player: the camera stays in front of the bark.

const DT := 1.0 / 72.0
const MAX_FIRST_FRAME_MOVE := 0.02
var failures := 0


func _ready() -> void:
	# 1. Platform gate.
	var holder := Node.new()
	add_child(holder)
	_check("android build: no spectator", SpectatorCamera.attach_if_supported(holder, PackedStringArray(["android", "mobile"])) == null
		and holder.get_child_count() == 0)
	_check("quest feature set (android only) refused", not SpectatorCamera.platform_ok(PackedStringArray(["android", "arm64"])))
	_check("pc feature set allowed", SpectatorCamera.platform_ok(PackedStringArray(["pc", "linux", "x86_64"])))
	_check("this machine (linux pc) allows it", SpectatorCamera.platform_ok())
	holder.queue_free()

	# 2. Smoothing and level horizon.
	var head := Node3D.new()
	add_child(head)
	head.global_position = Vector3(0, 1.7, 0)
	var spec := SpectatorCamera.attach_if_supported(self)
	_check("spectator off by default", spec != null and not spec.is_active())
	spec.head_override = head
	spec.set_physics_process(false)
	spec.set_mode(SpectatorCamera.Mode.FIRST_PERSON)
	spec.set_physics_process(false)
	for i in 30:
		spec.step(DT)
	var before := spec.camera.global_position
	head.global_position += Vector3(0.1, 0, 0)
	spec.step(DT)
	var moved := spec.camera.global_position.distance_to(before)
	_check("10 cm head jump -> camera moves %.4f m in frame 1 (<= %.2f)" % [moved, MAX_FIRST_FRAME_MOVE],
		moved > 0.0 and moved <= MAX_FIRST_FRAME_MOVE)
	for i in 144:
		spec.step(DT)
	_check("camera settles on the head after 2 s (%.4f m off)" % spec.camera.global_position.distance_to(head.global_position),
		spec.camera.global_position.distance_to(head.global_position) < 0.005)
	head.rotation = Vector3(deg_to_rad(-10), deg_to_rad(30), deg_to_rad(25))
	for i in 144:
		spec.step(DT)
	var roll_y := spec.camera.global_basis.x.y
	_check("rolled head (25°) -> level horizon (camera right.y %.4f)" % roll_y, absf(roll_y) < 0.001)
	_check("fov in 75–85 (%.0f), 16:9 view %s" % [spec.camera.fov, spec.viewport.size],
		spec.camera.fov >= 75.0 and spec.camera.fov <= 85.0 and absf(float(spec.viewport.size.x) / spec.viewport.size.y - 16.0 / 9.0) < 0.01)

	# 3. Third person with a trunk 1 m behind the player.
	head.rotation = Vector3.ZERO
	head.global_position = Vector3(0, 1.7, 0)
	var trunk := StaticBody3D.new()
	trunk.collision_layer = ForestWorld.TRUNK_LAYER
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 8.0
	cs.shape = cyl
	trunk.add_child(cs)
	add_child(trunk)
	trunk.global_position = Vector3(0.3, 2.0, 1.4)  # behind (+z) and a bit right: on the boom
	await get_tree().physics_frame
	await get_tree().physics_frame
	spec.set_mode(SpectatorCamera.Mode.OFF)
	spec.set_mode(SpectatorCamera.Mode.THIRD_PERSON)
	for i in 72:
		spec.step(DT)
	var cam := spec.camera.global_position
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(head.global_position, cam, ForestWorld.TRUNK_LAYER)
	var hit := space.intersect_ray(ray)
	var pt := PhysicsPointQueryParameters3D.new()
	pt.position = cam
	pt.collision_mask = ForestWorld.TRUNK_LAYER
	var inside := space.intersect_point(pt)
	var flat_d := Vector2(cam.x - trunk.global_position.x, cam.z - trunk.global_position.z).length()
	_check("TP camera clear of the trunk (ray hit %s, inside %d, %.2f m from axis)" % [not hit.is_empty(), inside.size(), flat_d],
		hit.is_empty() and inside.is_empty() and flat_d > cyl.radius + 0.1)
	_check("TP camera still behind the head (z %.2f)" % cam.z, cam.z > head.global_position.z + 0.05)
	# Trunk gone: the boom grows back to full length.
	trunk.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in 300:
		spec.step(DT)
	var full := Vector3(SpectatorCamera.TP_BACK, SpectatorCamera.TP_UP, SpectatorCamera.TP_RIGHT).length()
	var boom := spec.camera.global_position.distance_to(head.global_position)
	_check("boom grows back without the trunk (%.2f of %.2f m)" % [boom, full], boom > full - 0.15)

	# 4. Clean frame hides debug HUD.
	var dbg := CanvasLayer.new()
	dbg.add_to_group(SpectatorCamera.DEBUG_GROUP)
	add_child(dbg)
	spec.set_clean_frame(true)
	var hidden := not dbg.visible
	spec.set_clean_frame(false)
	_check("clean frame hides debug HUD and restores it", hidden and dbg.visible)

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
