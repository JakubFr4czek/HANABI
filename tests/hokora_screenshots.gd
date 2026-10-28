extends Node
## D1/D12 screenshots: the hokora shrine far out in the fog, up close, the hand on the
## altar, the three yellow Ofuda of the choice, the buff after the cut, the level-up
## flash and the skill menu with the points and the empty hint. Windowed (needs rendering):
##   godot --path . --fixed-fps 90 res://tests/hokora_screenshots.tscn -- --desktop --shots /tmp/hanabi_d1

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_d1"
var run: RunGame
var player: DesktopPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://shots_save.cfg"
	add_child(run)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(40)

	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	if shrine == null:
		push_error("no opening shrine")
		get_tree().quit(1)
		return
	var altar := shrine.altar_position()
	var from := Vector3(run.spawn.global_position.x, 0.0, run.spawn.global_position.z)
	# Unit vector from the spawn toward the shrine: the walk-in direction.
	var dir := (Vector3(altar.x, 0.0, altar.z) - from).normalized()

	# 1. From afar: the lantern reads through the milk fog. Stand where the trunks
	# leave a clear line of sight to the lantern.
	_stand_clear_view(altar, shrine.global_transform * HokoraShrine.LANTERN_LOCAL, dir)
	await _frames(60)
	await _shot("00_shrine_far_in_fog")

	# 2. Up close: the plinth, the house, the altar and the paper lantern.
	_stand_facing(altar, altar - dir * 3.2)
	await _frames(40)
	await _shot("01_shrine_close")

	# 3. The touch: a hand on the offering table (desktop: E) opens the yellow choice.
	# Stand 1.6 m off the altar so the three cards hang in frame at the right distance.
	_stand_facing(altar, altar - dir * 1.6)
	await _frames(20)
	run.reach_for_offering()
	await _frames(6)
	await _shot("02_touch_cards_rising")
	await _frames(90)
	await _shot("03_choice_three_yellow_ofuda")

	# 4. The cut: slice the damage card. The world resumes and the wrist shows the buff.
	var damage_card: OfudaTalisman = null
	for c in get_tree().get_nodes_in_group("ofuda_talismans"):
		if int((c as OfudaTalisman).entry.get("kind", -1)) == RunBuffs.Kind.DAMAGE:
			damage_card = c
	if damage_card:
		damage_card.slice(damage_card.global_position, Vector3.RIGHT)
	await _frames(60)
	_check("the damage buff runs after the cut (%.1f s)" % run.buffs.remaining(RunBuffs.Kind.DAMAGE),
		run.buffs.is_active(RunBuffs.Kind.DAMAGE))
	player.wrist_check = true
	await _frames(20)
	await _shot("04_buff_running_after_cut")

	# 5. A level-up: the flash on the charm and the new level and point on the wrist.
	run.add_xp(run.xp_to_next)
	await _frames(6)
	await _shot("05_level_up_flash")
	player.wrist_check = false

	# 6. The skill menu with the points, then with none (the hint line).
	await _frames(100)
	run.pause_controller.open()
	await _frames(12)
	await _shot("06_menu_points")
	run.pause_controller.close()
	await _frames(10)
	run.add_points(-run.skill_points)
	run.pause_controller.open()
	await _frames(12)
	await _shot("07_menu_no_points_hint")
	run.pause_controller.close()
	get_tree().quit(0)

## Tries 22, 18 and 14 m out, fanned ±18° around the walk-in line, and takes the
## first spot whose sight line to the lantern is free of trunks.
func _stand_clear_view(altar: Vector3, lantern: Vector3, dir: Vector3) -> void:
	var space := run.get_world_3d().direct_space_state
	for distance: float in [22.0, 18.0, 14.0]:
		for deg: float in [0.0, 6.0, -6.0, 12.0, -12.0, 18.0, -18.0]:
			var d: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(deg))
			var stand: Vector3 = Vector3(altar.x, 0.0, altar.z) - d * distance
			stand.y = run.forest_world.height_at(stand.x, stand.z)
			var eye: Vector3 = stand + Vector3(0.0, 1.6, 0.0)
			var q := PhysicsRayQueryParameters3D.create(eye, lantern, ForestWorld.TRUNK_LAYER)
			if space.intersect_ray(q).is_empty():
				_stand_facing(altar, stand)
				return
	_stand_facing(altar, Vector3(altar.x, 0.0, altar.z) - dir * 22.0)


## Puts the player at [param stand] (ground height), facing [param target].
func _stand_facing(target: Vector3, stand: Vector3) -> void:
	stand.y = run.forest_world.height_at(stand.x, stand.z)
	var yaw := atan2(-(target.x - stand.x), -(target.z - stand.z))
	player.teleport(stand, yaw)


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)
	var menu := run.pause_controller.menu
	if menu.is_open:
		var cimg := menu._viewport.get_texture().get_image()
		if cimg and not cimg.is_empty():
			cimg.save_png(out_dir.path_join("canvas_" + name + ".png"))


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame
