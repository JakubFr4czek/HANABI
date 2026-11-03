class_name SoulVessel
extends Node3D
## F7: a soul vessel (naczynie duszy). A small weathered komainu statuette (scan by Yu,
## CC BY 4.0) in which the soul of one villager is sealed. A pale hitodama-blue wisp
## breathes above it; its soft halo is depth tested, so trunks hide it like a torii lamp.
## Not to be confused with SoulOrb (the XP drops of slain yōkai).
##
## [method release] lets the soul go: the wisp rises and thins out, the light flares and
## dies, and the statue stays behind, dark. SoulVesselManager drives everything.

const MODEL := preload("res://assets/models/props/komainu/komainu_scan.glb")
## Height of the statuette, metres (the scan is fitted to it at build time).
const MODEL_HEIGHT := 0.62
## Height of the wisp above the ground, metres.
const WISP_Y := 0.95
## The soul light hangs this high (metres), well above the statue's head.
const LIGHT_Y := 1.7
const SOUL_COLOR := Color(0.62, 0.86, 1.0)
## The candle-like light only burns within this many metres of the player (≤1 at once:
## vessels stand ≥ SoulVesselManager.MIN_SPACING apart).
const LIGHT_RADIUS := 24.0
const RELEASE_SEC := 1.8

var index := -1
var released := false
var _t := 0.0
var _release_t := -1.0
var _wisp: MeshInstance3D
var _halo: MeshInstance3D
var _light: OmniLight3D
var _sign: Label3D
var _wisp_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
static var _glow_tex: GradientTexture2D


func _ready() -> void:
	var model := MODEL.instantiate() as Node3D
	model.name = "Komainu"
	add_child(model)
	_fit_model(model)
	_halo_mat = _glow_material(0.55)
	_wisp_mat = _glow_material(1.0)
	_halo = _quad("Halo", 1.6, _halo_mat)
	_halo.position.y = WISP_Y - 0.15
	_wisp = _quad("Wisp", 0.34, _wisp_mat)
	_wisp.position.y = WISP_Y
	_light = OmniLight3D.new()
	_light.name = "SoulLight"
	_light.light_color = SOUL_COLOR
	# F7 r1: soft and high above the statue, so the stone keeps its texture at 2 m
	# (1.1 at wisp height burned the scan white). The 8 m read comes from the halo.
	_light.light_energy = 0.45
	_light.omni_range = 2.6
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	_light.position.y = LIGHT_Y
	_light.visible = false
	add_child(_light)
	_sign = Label3D.new()
	_sign.name = "Sign"
	# F7 r1: same face and contrast as the F4 controls hint, 2x+ the first size,
	# drawn over trunks and rain so it always reads.
	_sign.font = UiTypography.font(600)
	_sign.font_size = 64
	_sign.pixel_size = 0.00125
	_sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sign.modulate = Color(0.95, 0.97, 1.0)
	_sign.outline_size = 18
	_sign.outline_modulate = Color(0.01, 0.01, 0.02, 0.95)
	_sign.shaded = false
	_sign.double_sided = true
	_sign.no_depth_test = true
	_sign.render_priority = 15
	_sign.outline_render_priority = 14
	_sign.line_spacing = 4.0
	_sign.position.y = 1.45
	_sign.visible = false
	add_child(_sign)


## Fits the scan's mesh to MODEL_HEIGHT and stands it on the ground at the origin.
func _fit_model(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b := (model.global_transform.affine_inverse() * m.global_transform) * m.get_aabb() if is_inside_tree() else m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.size.y <= 0.0001:
		return
	var s := MODEL_HEIGHT / box.size.y
	model.scale = Vector3.ONE * s
	var c := box.get_center()
	model.position = Vector3(-c.x * s, -box.position.y * s - 0.02, -c.z * s)


static func _glow_texture() -> GradientTexture2D:
	if _glow_tex != null:
		return _glow_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.55))
	g.add_point(0.6, Color(1, 1, 1, 0.12))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 128
	_glow_tex.height = 128
	return _glow_tex


func _glow_material(strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow_texture()
	m.albedo_color = Color(SOUL_COLOR.r * strength, SOUL_COLOR.g * strength, SOUL_COLOR.b * strength, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _quad(n: String, size: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi


## World point of the wisp (the glow the player sees from afar).
func wisp_position() -> Vector3:
	return global_position + Vector3(0.0, WISP_Y, 0.0)


## Per-frame: breathing glow, the light only near the player, the sign within reach.
func step(delta: float, player_pos: Vector3, prompted: bool, key_text: String) -> void:
	_t += delta
	if _release_t >= 0.0:
		_step_release(delta)
		return
	if released:
		return
	var breath := 0.5 + 0.5 * sin(_t * 1.7)
	_wisp.position.y = WISP_Y + 0.05 * sin(_t * 1.1)
	_wisp.scale = Vector3.ONE * (0.9 + 0.2 * breath)
	_halo.scale = Vector3.ONE * (0.92 + 0.12 * breath)
	var flat := Vector2(player_pos.x - global_position.x, player_pos.z - global_position.z).length()
	_light.visible = flat < LIGHT_RADIUS
	_light.light_energy = 0.38 + 0.12 * breath
	_sign.visible = prompted
	if prompted:
		_sign.text = "A villager's soul\nis sealed in this stone.\n%s  ·  RELEASE IT" % key_text


## Lets the soul go once; returns false when it was already released.
func release() -> bool:
	if released:
		return false
	released = true
	_release_t = 0.0
	_sign.visible = false
	_light.visible = true
	if Sfx:
		Sfx.play_at("soul_collect", wisp_position(), -4.0, 4.0, 0.62)
		Sfx.play_at("hokora_suzu", wisp_position(), -8.0, 4.0, 1.0)
	return true


func _step_release(delta: float) -> void:
	_release_t += delta
	var k := clampf(_release_t / RELEASE_SEC, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 2.0)
	_wisp.position.y = WISP_Y + 3.2 * ease_k
	_wisp.scale = Vector3.ONE * (1.0 + 1.6 * sin(k * PI))
	var fade := 1.0 - k
	_wisp_mat.albedo_color = Color(SOUL_COLOR.r * fade * 1.4, SOUL_COLOR.g * fade * 1.4, SOUL_COLOR.b * fade * 1.4, 1.0)
	_halo.position.y = _wisp.position.y - 0.15
	_halo_mat.albedo_color = Color(SOUL_COLOR.r * 0.55 * fade, SOUL_COLOR.g * 0.55 * fade, SOUL_COLOR.b * 0.55 * fade, 1.0)
	_light.position.y = maxf(_wisp.position.y, LIGHT_Y)
	_light.light_energy = 1.0 * sin(k * PI) + 0.01
	if k >= 1.0:
		_release_t = -1.0
		_wisp.visible = false
		_halo.visible = false
		_light.visible = false
