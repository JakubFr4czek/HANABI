extends Node3D
## Dojo of the Storm — training arena & physics test level (GDD §9).
## Spawns the VR rig when an OpenXR runtime is running, otherwise the desktop rig.
## R (desktop) or A/X (VR) resets the dummy and puts weapons nobody holds back on
## the weapon stand. P (desktop) or B/Y without grip (VR) toggles the dummy's
## attacks for parry practice.
##
## Pass `-- --desktop` on the command line to force the desktop rig.

const XR_PLAYER := preload("res://scenes/player/xr_player.tscn")
const SPAWN_SEAL_SHADER := preload("res://src/shaders/spawn_seal.gdshader")
const STONE_PLATFORM_SHADER := preload("res://src/shaders/stone_platform.gdshader")
const WATER_MIRROR_SHADER := preload("res://src/shaders/water_mirror.gdshader")
const WATER_MIST_SHADER := preload("res://src/shaders/water_mist.gdshader")
const STORM_SKY_SHADER := preload("res://src/shaders/storm_sky_dome.gdshader")

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

	var water_mi := get_node_or_null("Arena/WaterMirror") as MeshInstance3D
	if water_mi and water_mi.material_override is ShaderMaterial:
		_setup_water_baked_panorama(water_mi.material_override as ShaderMaterial)

	var flash_mats: Array[ShaderMaterial] = []
	for path in [
		"Arena/SkyDome",
		"Arena/WaterMirror",
		"Arena/PlatformDisc",
		"Arena/WaterMistLow",
		"Arena/WaterMistHigh",
	]:
		var mi := get_node_or_null(path) as MeshInstance3D
		if mi and mi.material_override is ShaderMaterial:
			var sm := mi.material_override as ShaderMaterial
			if not flash_mats.has(sm):
				flash_mats.append(sm)

	if lightning:
		lightning.flash_materials = flash_mats
		lightning.flash_light = get_node_or_null("Arena/LightningFlashLight") as Light3D
		var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we and we.environment:
			lightning.world_environment = we.environment
			lightning.base_fog_light_color = we.environment.fog_light_color

	var seal_mesh := get_node_or_null("Arena/SpawnSeal") as MeshInstance3D
	if seal_mesh:
		_seal_material = seal_mesh.material_override as ShaderMaterial
		_setup_seal_kanji(seal_mesh)

	_style_torii_gates(arena)
	_style_lanterns(arena)
	_update_seal_element(Elements.NONE)


## Bake a lightweight equirectangular storm-sky panorama once at startup so the
## water shader can sample distorted sky reflections (`reflect(-VIEW, NORMAL)`)
## without any realtime reflection probes or screen-space effects on Quest 3.
func _setup_water_baked_panorama(water_mat: ShaderMaterial) -> void:
	if water_mat.get_shader_parameter("sky_panorama") != null:
		return
	var w := 128
	var h := 64
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var zenith := Color(0.028, 0.016, 0.072)
	var mid_sky := Color(0.056, 0.040, 0.138)
	var horizon := Color(0.032, 0.026, 0.072)
	var cloud_col := Color(0.18, 0.11, 0.34)
	var torii_glow := Color(0.50, 0.08, 0.09)

	for y in h:
		var v := float(y) / float(h - 1)  # 0 = zenith, 1 = horizon
		var elev := pow(1.0 - v, 1.4)
		var base_row := horizon.lerp(mid_sky, clampf(elev * 2.2, 0.0, 1.0)).lerp(zenith, clampf((elev - 0.25) / 0.75, 0.0, 1.0))
		for x in w:
			var u := float(x) / float(w)
			var az := (u - 0.5) * TAU
			var c_wave := 0.5 + 0.5 * sin(az * 4.0 + v * 6.5) * cos(az * 3.0 - v * 4.8)
			var c_fine := 0.5 + 0.5 * sin(az * 9.0 - v * 11.0)
			var cloud_amt := smoothstep(0.28, 0.78, c_wave * 0.7 + c_fine * 0.3) * sin(v * PI)
			var col := base_row.lerp(cloud_col, cloud_amt * 0.68)
			var horizon_band := smoothstep(0.30, 1.0, v)
			var torii_align := maxf(0.0, cos(az - 0.0))
			col += torii_glow * (pow(torii_align, 4.5) * horizon_band * 0.24)
			col.a = 1.0
			img.set_pixel(x, y, col)

	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	water_mat.set_shader_parameter("sky_panorama", tex)


func _setup_seal_kanji(seal_root: Node3D) -> void:
	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Hiragino Mincho ProN", "YuMincho", "Songti SC", "Noto Serif CJK JP", "Hiragino Sans", "Arial Unicode MS"
	])
	# Four-part mark: 桜 (East), 雷 (North), 墨 (West), 影 (South).
	var glyphs := [
		{"kanji": "桜", "pos": Vector3(1.08, 0.006, 0.0), "yaw": -PI * 0.5, "col": Color(1.0, 0.25, 0.62)},
		{"kanji": "雷", "pos": Vector3(0.0, 0.006, -1.08), "yaw": 0.0, "col": Color(0.32, 0.76, 1.0)},
		{"kanji": "墨", "pos": Vector3(-1.08, 0.006, 0.0), "yaw": PI * 0.5, "col": Color(0.55, 0.64, 0.85)},
		{"kanji": "影", "pos": Vector3(0.0, 0.006, 1.08), "yaw": PI, "col": Color(0.68, 0.34, 1.0)},
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
		lbl.modulate = g.col
		lbl.outline_modulate = Color(0.02, 0.02, 0.05, 0.85)
		lbl.outline_size = 10
		lbl.position = g.pos
		lbl.rotation = Vector3(-PI * 0.5, g.yaw, 0.0)
		seal_root.add_child(lbl)
		_seal_labels.append(lbl)


func _update_seal_element(elem: String) -> void:
	var idx := -1
	match elem:
		Elements.SAKURA: idx = 0
		Elements.STORM: idx = 1
		Elements.INK: idx = 2
		Elements.SHADOW: idx = 3
	if _seal_material:
		_seal_material.set_shader_parameter("active_element_index", idx)
	var base_colors := [
		Color(1.0, 0.25, 0.62),
		Color(0.32, 0.76, 1.0),
		Color(0.55, 0.64, 0.85),
		Color(0.68, 0.34, 1.0),
	]
	for i in _seal_labels.size():
		var boost := 1.0 if idx < 0 else (1.6 if idx == i else 0.42)
		var c: Color = base_colors[i]
		_seal_labels[i].modulate = Color(c.r * boost, c.g * boost, c.b * boost, 0.92 if idx == i or idx < 0 else 0.55)


func _style_torii_gates(arena: Node) -> void:
	var torii_group := arena.get_node_or_null("ToriiGates")
	if torii_group == null:
		return
	var hero_mat: StandardMaterial3D = null
	var sunken_mat: StandardMaterial3D = null
	for child in torii_group.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		if hero_mat == null and mi.mesh and mi.mesh.get_surface_count() > 0:
			var orig := mi.mesh.surface_get_material(0) as StandardMaterial3D
			hero_mat = StandardMaterial3D.new()
			if orig and orig.albedo_texture:
				hero_mat.albedo_texture = orig.albedo_texture
			# Deep weathered vermilion lacquer for the hero Giant Torii.
			hero_mat.albedo_color = Color(0.74, 0.15, 0.17, 1.0)
			hero_mat.roughness = 0.42
			hero_mat.metallic = 0.08
			hero_mat.emission_enabled = true
			hero_mat.emission = Color(0.075, 0.010, 0.014)

			sunken_mat = hero_mat.duplicate() as StandardMaterial3D
			# Distant crooked torii gates are darker and less emissive so they fade into the storm fog.
			sunken_mat.albedo_color = Color(0.38, 0.09, 0.13, 1.0)
			sunken_mat.roughness = 0.62
			sunken_mat.emission = Color(0.012, 0.002, 0.004)
		var is_giant := mi.get_path().get_concatenated_names().contains("GiantTorii")
		if is_giant and hero_mat:
			mi.material_override = hero_mat
		elif sunken_mat:
			mi.material_override = sunken_mat


func _style_lanterns(arena: Node) -> void:
	var lanterns := arena.get_node_or_null("Lanterns")
	if lanterns == null:
		return
	for child in lanterns.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		if mi.mesh and mi.mesh.get_surface_count() > 0:
			var orig := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if orig:
				var mat := orig.duplicate() as StandardMaterial3D
				mat.albedo_color = Color(0.42, 0.44, 0.54)
				mat.roughness = 0.78
				mi.material_override = mat
