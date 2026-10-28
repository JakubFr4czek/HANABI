extends Node
## E2d screenshots: the skill-tree menu in the milk-fog forest, standing right
## next to a tree. Windowed (needs rendering):
##   godot --path . --fixed-fps 90 res://tests/skill_menu_screenshots.tscn -- --desktop --shots /tmp/hanabi_e2d

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_e2d"
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

	# Stand 1.5 m from the nearest trunk's bark, facing it.
	var trunk := _nearest_trunk()
	var tree_pos := Vector3(trunk.x, 0.0, trunk.y)
	var dir := (Vector3.ZERO - tree_pos).normalized()
	if dir.length() < 0.1:
		dir = Vector3.BACK
	var stand := tree_pos + dir * (trunk.z + 1.5)
	stand.y = run.forest_world.height_at(stand.x, stand.z)
	var yaw := atan2(-(tree_pos.x - stand.x), -(tree_pos.z - stand.z))
	player.teleport(stand, yaw)
	await _frames(40)

	run.ofuda_count = 9
	run.unlock_skill("petal_sense")
	run.unlock_skill("hanami_storm")
	run.element_system.imbue(Elements.SAKURA)
	run.element_system.element_time_remaining = 14.0
	# A couple of frozen yōkai in the fog behind the panel.
	var fwd := player.get_look_direction()
	run.wave_director.spawn_enemy_at(stand + fwd * 4.5 + Vector3(1.4, 0, 0), stand)
	run.wave_director.spawn_enemy_at(stand + fwd * 6.5 + Vector3(-1.8, 0, 0), stand)
	await _frames(60)

	await _shot("00_forest_before_menu")
	run.pause_controller.open()
	var menu := run.pause_controller.menu
	await _frames(12)
	await _shot("01_menu_next_to_tree_sakura")

	# Hover + select Razor Petals, ready to unlock.
	menu.select_node("razor_petals")
	_aim(menu, menu.canvas.node_rect(SkillTreeData.node_by_id("razor_petals")).get_center())
	await _frames(8)
	await _shot("02_sakura_node_selected")

	# Storm: nothing owned, one affordable.
	menu.select_element(Elements.STORM)
	_aim(menu, SkillTreeCanvas.UNLOCK_RECT.get_center())
	await _frames(8)
	await _shot("03_storm_unlock_hover")

	# Ink: locked node selected, balance too low.
	run.ofuda_count = 1
	menu.canvas.balance = 1
	menu.select_element(Elements.INK)
	menu.select_node("abyssal_sea")
	_aim(menu, menu.canvas.tab_rect(3).get_center())
	await _frames(8)
	await _shot("04_ink_locked_node")

	# Buy something: flash.
	run.ofuda_count = 6
	menu.canvas.balance = 6
	menu.select_element(Elements.SHADOW)
	menu.select_node("night_veil")
	menu.unlock_selected()
	await _frames(14)
	await _shot("05_shadow_unlocked_flash")

	run.pause_controller.close()
	run.queue_free()
	get_tree().quit(0)


func _aim(menu: SkillTreeMenu, px: Vector2) -> void:
	var cam := player.camera
	var target := menu.canvas_to_world(px)
	menu.update_pointer("mouse", cam.global_position, (target - cam.global_position).normalized(), false, false)


func _nearest_trunk() -> Vector3:
	var best := Vector3(0.0, 4.0, 0.3)
	var best_d := INF
	for cell in run.forest_world._trunk_cells:
		for e: Vector3 in run.forest_world._trunk_cells[cell]:
			var d := Vector2(e.x, e.y).length()
			if e.z >= 0.25 and d > 3.0 and d < best_d:
				best_d = d
				best = e
	return best


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)
	# The menu's own 1600x1000 canvas, 1 px per headset pixel (what VR shows).
	var menu := run.pause_controller.menu
	if menu.is_open:
		var cimg := menu._viewport.get_texture().get_image()
		if cimg and not cimg.is_empty():
			cimg.save_png(out_dir.path_join("canvas_" + name + ".png"))
