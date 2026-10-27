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
var rain: StormRain
var ambience: StormAmbience
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
var _seal_progress_mode := false


func _ready() -> void:
	for w in [katana, kanabo]:
		_homes[w] = w.global_transform
	_setup_dojo_visuals()
	GameEvents.clear()
	TimeController.clear()
	var use_xr := is_xr_available() and not OS.get_cmdline_user_args().has("--desktop")
	GameEvents.log_event("session_start", {"scene": "training_arena", "xr": use_xr})
	if use_xr:
		Sfx.route_to_xr_headset()
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
	if _seal_progress_mode:
		return
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

	ambience = StormAmbience.new()
	ambience.name = "StormAmbience"
	ambience.lightning = lightning
	add_child(ambience)

	var music := StormMusic.new()
	music.name = "StormMusic"
	add_child(music)

	rain = StormRain.new()
	rain.name = "StormRain"
	arena.add_child(rain)
	if katana:
		StormRain.add_blade_drips(katana, katana.blade_tip)

	var seal_mesh := get_node_or_null("Arena/SpawnSeal") as MeshInstance3D
	if seal_mesh:
		_seal_material = seal_mesh.material_override as ShaderMaterial
		_setup_seal_kanji(seal_mesh)

	_style_torii_gates(arena)
	_style_scanned_props(arena, "Rocks", Color(0.6, 0.6, 0.64), 0.4, 0.75)
	_style_scanned_props(self, "Room/WeaponRest/KatanaStand", Color(0.85, 0.82, 0.8), 0.42, 0.45)
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
	var idx := Elements.seal_index(elem)
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


## Run mode: keep every unlocked quadrant lit and reserve the inner star for
## an evolution. Training mode still highlights only the held weapon's element.
func set_seal_progress(unlocked: Array[String], evolution_mask: int = 0) -> void:
	_seal_progress_mode = true
	var mask := 0
	for element in unlocked:
		var idx := Elements.seal_index(element)
		if idx >= 0:
			mask |= 1 << idx
	if _seal_material:
		_seal_material.set_shader_parameter("active_element_index", -1)
		_seal_material.set_shader_parameter("active_elements_mask", mask)
		_seal_material.set_shader_parameter("evolution_mask", evolution_mask)
	var inlay := Color(0.2, 0.21, 0.27, 0.8)
	for i in _seal_labels.size():
		var element := Elements.COMBAT_ELEMENTS[i]
		_seal_labels[i].modulate = Elements.accent_color(element) * 0.92 if unlocked.has(element) else inlay


func clear_seal_progress() -> void:
	_seal_progress_mode = false
	if _seal_material:
		_seal_material.set_shader_parameter("active_elements_mask", 0)
		_seal_material.set_shader_parameter("evolution_mask", 0)
	_update_seal_element(Elements.NONE)


func _style_torii_gates(arena: Node) -> void:
	var torii_group := arena.get_node_or_null("ToriiGates")
	if torii_group == null:
		return
	var cache := {}
	for child in torii_group.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var is_giant := mi.get_path().get_concatenated_names().contains("GiantTorii")
		for s in mi.mesh.get_surface_count():
			var orig := mi.mesh.surface_get_material(s) as StandardMaterial3D
			var key := [orig, is_giant]
			if not cache.has(key):
				# The hero gate's vermilion lacquer is the scene's one big red accent:
				# a faint self-glow from its own albedo keeps the red readable when the
				# moon backlights it. Distant tilted gates are darker so they sink into
				# the fog as silhouettes.
				var m := _scanned_wet_material(orig, Color(0.9, 0.86, 0.86) if is_giant else Color(0.42, 0.38, 0.4), 0.42 if is_giant else 0.5, 0.55 if is_giant else 0.6)
				if is_giant:
					m.set_shader_parameter("emission_tint", Color(0.18, 0.035, 0.03))
				cache[key] = m
			mi.set_surface_override_material(s, cache[key])


func _style_scanned_props(root: Node, path: String, tint: Color, rough_wet: float, wetness: float) -> void:
	var group := root.get_node_or_null(path)
	if group == null:
		return
	var cache := {}
	for child in group.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		for s in mi.mesh.get_surface_count():
			var orig := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if not cache.has(orig):
				cache[orig] = _scanned_wet_material(orig, tint, rough_wet, wetness)
			mi.set_surface_override_material(s, cache[orig])


# Scanned assets keep their PBR maps (albedo, normal, metal/rough, AO) under
# the shared rain treatment.
static func _scanned_wet_material(orig: StandardMaterial3D, tint: Color, rough_wet: float, wetness: float) -> ShaderMaterial:
	var m := _wet_material(tint, 1.0, rough_wet, wetness, 0.0)
	if orig == null:
		return m
	m.set_shader_parameter("albedo_texture", orig.albedo_texture)
	m.set_shader_parameter("metallic", orig.metallic)
	if orig.normal_enabled and orig.normal_texture:
		m.set_shader_parameter("normal_texture", orig.normal_texture)
		m.set_shader_parameter("normal_depth", 1.0)
	if orig.roughness_texture:
		m.set_shader_parameter("orm_texture", orig.roughness_texture)
		m.set_shader_parameter("orm_mode", 2 if orig.ao_enabled and orig.ao_texture == orig.roughness_texture else 1)
	return m


static func _wet_material(color: Color, rough_dry: float, rough_wet: float, wetness: float,
		waterline_y: float, fill: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WET_SURFACE_SHADER
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("roughness_dry", rough_dry)
	m.set_shader_parameter("roughness_wet", rough_wet)
	m.set_shader_parameter("wetness", wetness)
	m.set_shader_parameter("waterline_y", waterline_y)
	m.set_shader_parameter("fill", fill)
	return m
