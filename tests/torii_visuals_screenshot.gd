extends Node
## Captures screenshots of the authentic Shinto Torii gate at ~5m and ~20m in fog
## for visual review and GDD aesthetic compliance.
## Run with:
##   godot --path . res://tests/torii_visuals_screenshot.tscn -- --desktop --shots /tmp/hanabi_torii_shots

const TORII_SCENE := preload("res://scenes/world/torii_gate.tscn")
const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")

var out_dir := "/tmp/hanabi_torii_shots"
var env: WorldEnvironment
var cam: Camera3D
var gate: ToriiGate


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Setup Environment matching RunGame / GDD §9 milk fog
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.69, 0.71, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.24, 0.26, 0.28)
	e.ambient_light_energy = 0.85
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.69, 0.71, 0.72)
	e.fog_depth_begin = 3.0
	e.fog_depth_end = 10.5
	e.fog_density = 1.0
	env.environment = e
	add_child(env)

	# Ground plane with wet surface shader
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = WET_SHADER
	ground_mat.set_shader_parameter("base_color", Color(0.12, 0.14, 0.12))
	ground_mat.set_shader_parameter("roughness_dry", 0.92)
	ground_mat.set_shader_parameter("roughness_wet", 0.78)
	ground_mat.set_shader_parameter("wetness", 0.3)
	ground_mat.set_shader_parameter("fog_fill", 0.22)
	ground.material_override = ground_mat
	add_child(ground)

	# Torii Gate at origin
	gate = TORII_SCENE.instantiate() as ToriiGate
	gate.element = Elements.SAKURA
	gate.position = Vector3(0.0, 0.0, 0.0)
	add_child(gate)

	cam = Camera3D.new()
	cam.current = true
	add_child(cam)

	await _frames(15)

	# Shot 1: Close-up ~5m showing authentic Myōjin architecture (kasagi, shimaki, nuki, gakuzuka, daiishi)
	cam.position = Vector3(0.0, 1.8, 5.2)
	cam.look_at(Vector3(0.0, 1.9, 0.0), Vector3.UP)
	await _frames(10)
	await _shot("torii_close_5m")

	# Shot 2: In-fog ~20m showing milk fog dissolution and volumetric lantern halo beacon
	cam.position = Vector3(0.0, 1.8, 20.0)
	cam.look_at(Vector3(0.0, 1.9, 0.0), Vector3.UP)
	await _frames(10)
	await _shot("torii_fog_20m")

	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await _frames(2)
	var tex := get_viewport().get_texture()
	if tex == null:
		push_warning("torii_visuals: no viewport texture for %s" % shot_name)
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		push_warning("torii_visuals: empty image for %s" % shot_name)
		return
	var out_path := out_dir.path_join(shot_name + ".png")
	img.save_png(out_path)
	print("Saved screenshot: ", out_path)
