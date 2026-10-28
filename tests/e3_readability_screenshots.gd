extends Node
## E3 screenshots: every element on the blade, a gate active and spent (close and
## in the milk fog), the wrist plate and the skill-tree menu. Windowed:
##   godot --path . --fixed-fps 90 res://tests/e3_readability_screenshots.tscn -- --desktop --shots /tmp/hanabi_e3
## Optional: `--only blade|gate|wrist|menu`.

const RUN_SCENE := preload("res://scenes/run.tscn")
const GATE_SCENE := preload("res://scenes/world/torii_gate.tscn")

var out_dir := "/tmp/hanabi_e3"
var only := ""
var run: RunGame
var player: DesktopPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://shots_save.cfg"
	add_child(run)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(40)
	player.teleport(Vector3(0.0, 0.0, 0.0), 0.0)
	player.camera.rotation.x = deg_to_rad(-6.0)
	await _frames(30)

	if only in ["", "blade"]:
		await _blade_shots()
	if only in ["", "gate"]:
		await _gate_shots()
	if only in ["", "wrist"]:
		await _wrist_shots()
	if only in ["", "menu"]:
		await _menu_shots()
	run.queue_free()
	get_tree().quit(0)


func _blade_shots() -> void:
	# Blade held up in front of the face, tip towards the fog.
	player.hand_offset = Vector3(0.06, 0.1, 0.12)
	for el in Elements.COMBAT_ELEMENTS:
		run.element_system.imbue(el, 20.0)
		await _real(0.25)
		await _shot("blade_%s_sweep" % el)
		await _real(1.0)
		await _shot("blade_%s" % el)
	run.element_system.imbue(Elements.STORM, 20.0)
	run.element_system.element_time_remaining = 1.4
	await _real(1.2)
	await _shot("blade_storm_warning")
	run.element_system.reset()
	await _real(1.0)
	await _shot("blade_plain_steel")
	player.hand_offset = Vector3.ZERO


func _gate_shots() -> void:
	run.element_system.reset()
	var specs := [
		["gate_sakura_active_6m", Elements.SAKURA, 6.0, true],
		["gate_sakura_spent_6m", Elements.SAKURA, 6.0, false],
		["gate_storm_active_20m_fog", Elements.STORM, 20.0, true],
		["gate_ink_active_14m_fog", Elements.INK, 14.0, true],
		["gate_shadow_active_28m_fog", Elements.SHADOW, 28.0, true],
		["gate_storm_spent_20m_fog", Elements.STORM, 20.0, false],
	]
	var fwd := player.get_look_direction()
	fwd.y = 0.0
	fwd = fwd.normalized()
	player.hand_offset = Vector3(0.55, -0.45, 0.0)
	for s in specs:
		var gate := GATE_SCENE.instantiate() as ToriiGate
		gate.element = String(s[1])
		run.add_child(gate)
		var at: Vector3 = player.global_position + fwd * float(s[2])
		at.y = run.forest_world.height_at(at.x, at.z)
		gate.global_position = at
		gate.look_at(at - fwd, Vector3.UP)
		gate.is_active = bool(s[3])
		await _real(0.15 if not bool(s[3]) else 0.1)
		if not bool(s[3]):
			await _shot(String(s[0]) + "_flare")
		await _real(1.4)
		await _shot(String(s[0]))
		gate.queue_free()
		await _frames(2)
	player.hand_offset = Vector3.ZERO


func _wrist_shots() -> void:
	player.camera.rotation.x = deg_to_rad(-34.0)
	player.hand_offset = Vector3(0.18, -0.14, 0.0)
	run.kills = 12
	run.score = 740
	run.ofuda_count = 7
	run._refresh_hud()
	run.element_system.reset()
	await _frames(20)
	await _shot("wrist_plain_steel")
	var es := run.element_system
	for el in Elements.COMBAT_ELEMENTS:
		es.imbue(el, 20.0)
		es.element_time_remaining = 13.0
		es.ability_1_cooldown = 0.0
		es.ability_2_cooldown = es.ability_cooldown_total(2) * 0.55
		run._refresh_hud()
		await _frames(14)
		await _shot("wrist_%s" % el)
	es.imbue(Elements.SAKURA, 20.0)
	es.element_time_remaining = 2.0
	es.ability_1_cooldown = es.ability_cooldown_total(1) * 0.3
	es.ability_2_cooldown = 0.0
	await _frames(12)
	await _shot("wrist_sakura_warning")
	es.reset()
	player.camera.rotation.x = deg_to_rad(-6.0)
	player.hand_offset = Vector3.ZERO


func _menu_shots() -> void:
	run.ofuda_count = 9
	run.element_system.imbue(Elements.INK, 20.0)
	run.element_system.element_time_remaining = 11.0
	run.element_system.ability_2_cooldown = 3.0
	player.hand_offset = Vector3(0.55, -0.45, 0.0)
	await _frames(10)
	run.pause_controller.open()
	await _frames(14)
	await _shot("menu_open")
	await _frames(30)
	run.pause_controller.close()


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


## Blade and gate animations run on the wall clock: wait real seconds.
func _real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
