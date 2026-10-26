extends Node3D
## Dojo of the Storm — training arena & physics test level (GDD §9).
## Spawns the VR rig when an OpenXR runtime is running, otherwise the desktop rig.
## R (desktop) or A/X (VR) resets the dummy and puts weapons nobody holds back on
## the weapon stand. P (desktop) or B/Y without grip (VR) toggles the dummy's
## attacks for parry practice.
##
## Pass `-- --desktop` on the command line to force the desktop rig.

const XR_PLAYER := preload("res://scenes/player/xr_player.tscn")
const WET_SURFACE_SHADER := preload("res://src/shaders/wet_surface.gdshader")

@onready var dummy: TrainingDummy = $TrainingDummy
@onready var katana: HeldWeapon = $Katana
@onready var kanabo: HeldWeapon = $Kanabo
@onready var spawn: Marker3D = $PlayerSpawn
@onready var lightning: StormLightning = get_node_or_null("Arena/StormLightning") as StormLightning

## Kept for older callers/tests: the default weapon.
var sword: HeldWeapon:
	get: return katana

var player: Node3D
var _homes := {}  # weapon -> Transform3D on the stand
var _seal_material: ShaderMaterial
var _seal_labels: Array[Label3D] = []
var _last_seal_element := ""


func _ready() -> void:
	for w in [katana, kanabo]:
		_homes[w] = w.global_transform
	_setup_dojo_visuals()
	GameEvents.clear()
	TimeController.clear()
	var use_xr := is_xr_available() and not OS.get_cmdline_user_args().has("--desktop")
	GameEvents.log_event("session_start", {"scene": "training_arena", "xr": use_xr})
	if use_xr:
		player = XR_PLAYER.instantiate()
		player.reset_requested.connect(reset_room)
		player.toggle_attacks_requested.connect(toggle_dummy_attacks)
	else:
		player = DesktopPlayer.new()
		player.name = "DesktopPlayer"
		player.weapons = [katana, kanabo]
		player.toggle_attacks_requested.connect(toggle_dummy_attacks)
	add_child(player)
	player.global_transform = spawn.global_transform
	for w in [katana, kanabo]:
		w.register_player_collision_exceptions(player)
	if player is DesktopPlayer:
		(player as DesktopPlayer).holder.grab(katana)


static func is_xr_available() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and xr.is_initialized()


func _process(_delta: float) -> void:
	var active_elem := Elements.NONE
	if katana and katana.is_held():
		active_elem = katana.element
	elif kanabo and kanabo.is_held():
		active_elem = kanabo.element
	if active_elem != _last_seal_element:
		_last_seal_element = active_elem
		_update_seal_element(active_elem)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset_room()


func toggle_dummy_attacks() -> void:
	dummy.set_attacks_enabled(not dummy.attacks_enabled())


func reset_room() -> void:
	TimeController.clear()
	dummy.reset_dummy()
	for w: HeldWeapon in _homes:
		if not w.is_held():
			w.global_transform = _homes[w]
			w.linear_velocity = Vector3.ZERO
			w.angular_velocity = Vector3.ZERO
			if w.trail:
				w.trail.clear()


# --- Dojo of the Storm setup ---------------------------------------------------

func _setup_dojo_visuals() -> void:
	var arena := get_node_or_null("Arena")
	if arena == null:
		return
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env: Environment = we.environment if we else null
	if env:
		RenderingServer.global_shader_parameter_set("storm_fog_color", env.fog_light_color)
		# Glow needs an extra full-screen pass, too costly on Quest (Compatibility).
		if OS.has_feature("android"):
			env.glow_enabled = false
	var moon := get_node_or_null("Moon") as DirectionalLight3D
	if moon:
		RenderingServer.global_shader_parameter_set("moon_direction", moon.global_basis.z.normalized())

	var water_mi := get_node_or_null("Arena/WaterMirror") as MeshInstance3D
	if water_mi and water_mi.material_override is ShaderMaterial:
		_setup_water_baked_panorama(water_mi.material_override as ShaderMaterial, env.fog_light_color if env else Color.BLACK)

	if lightning:
		lightning.flash_light = get_node_or_null("Arena/LightningFlashLight") as Light3D
		if env:
			lightning.world_environment = env
			lightning.base_fog_light_color = env.fog_light_color
			lightning.base_ambient_energy = env.ambient_light_energy

	var seal_mesh := get_node_or_null("Arena/SpawnSeal") as MeshInstance3D
	if seal_mesh:
		_seal_material = seal_mesh.material_override as ShaderMaterial
		_setup_seal_kanji(seal_mesh)

	_style_torii_gates(arena)
	_style_lanterns(arena)
	_update_seal_element(Elements.NONE)


## Bake a small equirectangular storm-sky panorama once at startup so the water
## shader can sample distorted sky reflections without reflection probes or
## screen-space effects on Quest 3. Matches StormSkyDome: fog-colored horizon,
## dark zenith, cloud masses (the moon itself is added analytically in the shader).
func _setup_water_baked_panorama(water_mat: ShaderMaterial, fog: Color) -> void:
	if water_mat.get_shader_parameter("sky_panorama") != null:
		return
	var w := 128
	var h := 64
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var zenith := Color(0.11, 0.11, 0.19)
	var cloud := Color(0.08, 0.08, 0.14)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.9
	for y in h:
		var v := float(y) / float(h - 1)  # 0 = zenith, 1 = horizon
		var row := zenith.lerp(fog, smoothstep(0.35, 0.95, v))
		for x in w:
			var az := float(x) / float(w) * TAU
			var dir := Vector2(cos(az), sin(az)) * (1.0 - v + 0.2)
			var c := smoothstep(0.0, 0.5, noise.get_noise_2d(dir.x * 3.0, dir.y * 3.0) + 0.1) * (1.0 - smoothstep(0.75, 0.95, v))
			var col := row.lerp(cloud, c * 0.6)
			col.a = 1.0
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	water_mat.set_shader_parameter("sky_panorama", ImageTexture.create_from_image(img))


func _setup_seal_kanji(seal_root: Node3D) -> void:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Hiragino Mincho ProN", "YuMincho", "Songti SC", "Noto Serif CJK JP", "Hiragino Sans", "Arial Unicode MS"
	])
	# Four-part mark: 桜 (East), 雷 (North), 墨 (West), 影 (South).
	var glyphs := [
		{"kanji": "桜", "pos": Vector3(1.08, 0.006, 0.0), "yaw": -PI * 0.5},
		{"kanji": "雷", "pos": Vector3(0.0, 0.006, -1.08), "yaw": 0.0},
		{"kanji": "墨", "pos": Vector3(-1.08, 0.006, 0.0), "yaw": PI * 0.5},
		{"kanji": "影", "pos": Vector3(0.0, 0.006, 1.08), "yaw": PI},
	]
	_seal_labels.clear()
	for g in glyphs:
		var lbl := Label3D.new()
		lbl.text = g.kanji
		lbl.font = sys_font
		lbl.font_size = 96
		lbl.pixel_size = 0.0042
		lbl.shaded = false
		lbl.double_sided = true
		lbl.outline_size = 0
		lbl.position = g.pos
		lbl.rotation = Vector3(-PI * 0.5, g.yaw, 0.0)
		seal_root.add_child(lbl)
		_seal_labels.append(lbl)


## The seal is a dim silver inlay; only the active element's glyph lights up.
func _update_seal_element(elem: String) -> void:
	var idx := -1
	match elem:
		Elements.SAKURA: idx = 0
		Elements.STORM: idx = 1
		Elements.INK: idx = 2
		Elements.SHADOW: idx = 3
	if _seal_material:
		_seal_material.set_shader_parameter("active_element_index", idx)
	var neon := [
		Color(1.6, 0.35, 0.9),
		Color(0.35, 0.9, 2.0),
		Color(0.55, 0.64, 0.85),
		Color(0.8, 0.25, 1.6),
	]
	var inlay := Color(0.2, 0.21, 0.27, 0.8)
	for i in _seal_labels.size():
		_seal_labels[i].modulate = neon[i] if idx == i else inlay


func _style_torii_gates(arena: Node) -> void:
	var torii_group := arena.get_node_or_null("ToriiGates")
	if torii_group == null:
		return
	var hero_mat: ShaderMaterial = null
	var sunken_mat: ShaderMaterial = null
	for child in torii_group.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		if hero_mat == null and mi.mesh and mi.mesh.get_surface_count() > 0:
			var orig := mi.mesh.surface_get_material(0) as StandardMaterial3D
			# Deep vermilion lacquer, soaked and glossy, darkened at the water line.
			# Vermilion lacquer: the scene's one big red accent. A faint self-glow keeps
			# the red readable when the moon backlights it.
			hero_mat = _wet_material(Color(0.5, 0.05, 0.035), 0.5, 0.3, 0.55, 0.0)
			hero_mat.set_shader_parameter("rim_amount", 0.6)
			hero_mat.set_shader_parameter("flash_color", Color(0.55, 0.04, 0.02))
			hero_mat.set_shader_parameter("flash", 0.2)
			if orig and orig.albedo_texture:
				hero_mat.set_shader_parameter("albedo_texture", orig.albedo_texture)
			# Distant tilted torii are darker so they sink into the fog as silhouettes.
			sunken_mat = hero_mat.duplicate() as ShaderMaterial
			sunken_mat.set_shader_parameter("base_color", Color(0.16, 0.03, 0.035))
			sunken_mat.set_shader_parameter("flash", 0.0)
		var is_giant := mi.get_path().get_concatenated_names().contains("GiantTorii")
		mi.material_override = hero_mat if is_giant else sunken_mat


func _style_lanterns(arena: Node) -> void:
	var lanterns := arena.get_node_or_null("Lanterns")
	if lanterns == null:
		return
	var stone := _wet_material(Color(0.14, 0.14, 0.16), 0.75, 0.18, 0.75, -10.0)
	for child in lanterns.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var mat := stone.duplicate() as ShaderMaterial
		var orig := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh and mi.mesh.get_surface_count() > 0 else null
		if orig and orig.albedo_texture:
			mat.set_shader_parameter("albedo_texture", orig.albedo_texture)
		mi.material_override = mat


static func _wet_material(color: Color, rough_dry: float, rough_wet: float, wetness: float, waterline_y: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WET_SURFACE_SHADER
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("roughness_dry", rough_dry)
	m.set_shader_parameter("roughness_wet", rough_wet)
	m.set_shader_parameter("wetness", wetness)
	m.set_shader_parameter("waterline_y", waterline_y)
	return m
