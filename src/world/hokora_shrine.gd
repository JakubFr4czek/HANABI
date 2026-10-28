class_name HokoraShrine
extends Node3D
## Hokora: a small roadside shrine and the only source of Ofuda (docs/ELEMENTS_PLAN.md, D1).
##
## Lit until the player has claimed it once; a claimed shrine goes dark for the
## rest of the run and never pays again. Its lantern is the unshaded halo of the
## torii gates (it reads through the milk fog) and a suzu bell rings when the
## player comes near. No lights: the Quest 3 light budget is untouched.
##
## The model is procedural and lives under the "ModelSlot" node. D5 replaces its
## children with a real asset; nothing else in this script changes.

signal claimed(shrine: HokoraShrine, ofuda: int)

const HALO_SHADER := preload("res://src/shaders/torii_lantern_halo.gdshader")
const GLOW_LIT := Color(1.0, 0.5, 0.2)
const CORE_LIT := Color(1.0, 0.9, 0.7)
const WOOD_COLOR := Color(0.38, 0.26, 0.16)
const STONE_COLOR := Color(0.34, 0.34, 0.37)
const ROOF_COLOR := Color(0.16, 0.15, 0.16)
## Where the offering table stands, in shrine space (metres).
const ALTAR_LOCAL := Vector3(0.0, 0.46, 0.78)
const LANTERN_LOCAL := Vector3(0.44, 0.7, 0.8)
const SUZU_RANGE := 14.0
const SUZU_INTERVAL := 6.0

## Which forest slot this shrine belongs to (set by HokoraManager).
var slot := Vector2i.ZERO
var lit := true

var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _flame_mat: StandardMaterial3D
var _suzu_cd := 0.0
var _clock := 0.0


func _ready() -> void:
	add_to_group("hokora_shrines")
	var slot_root := get_node_or_null("ModelSlot") as Node3D
	if slot_root and slot_root.get_child_count() == 0:
		_build_model(slot_root)
	_build_halo()
	_apply_lit()


## Offering table, world space: where the Ofuda rise from when claimed.
func altar_position() -> Vector3:
	return global_transform * ALTAR_LOCAL


## Claims the shrine when the player's feet are inside the claim radius.
## Returns true exactly once per shrine.
func try_claim(player_pos: Vector3) -> bool:
	if not lit:
		return false
	var d := player_pos - altar_position()
	if Vector2(d.x, d.z).length() > ElementBalance.HOKORA_CLAIM_RADIUS or absf(d.y) > 2.0:
		return false
	set_lit(false)
	if Sfx:
		Sfx.play_at("hokora_suzu", altar_position(), -2.0, 12.0, 1.15)
	claimed.emit(self, ElementBalance.OFUDA_PER_HOKORA)
	return true


func set_lit(value: bool) -> void:
	lit = value
	_apply_lit()


## Per-physics-frame: lantern flicker, the halo turns to face the player, and the
## suzu rings when the player comes near (not while the shrine is dark).
func step(delta: float, player_pos: Vector3) -> void:
	_clock += delta
	if _halo == null:
		return
	if lit:
		var flicker := 1.0 + 0.07 * sin(_clock * 3.1 + float(slot.x) * 0.7) + 0.04 * sin(_clock * 7.3)
		_halo_mat.set_shader_parameter("intensity", 1.45 * flicker)
		var to_player := player_pos - _halo.global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			_halo.global_rotation = Vector3(0.0, atan2(to_player.x, to_player.z), 0.0)
		_suzu_cd -= delta
		var d := player_pos - altar_position()
		if _suzu_cd <= 0.0 and Vector2(d.x, d.z).length() < SUZU_RANGE and Sfx:
			Sfx.play_at("hokora_suzu", altar_position(), -8.0, 14.0, 1.0)
			_suzu_cd = SUZU_INTERVAL


func _apply_lit() -> void:
	if _flame_mat:
		var glow := 1.8 if lit else 0.0
		_flame_mat.emission_energy_multiplier = glow
		_flame_mat.albedo_color = Color(0.9, 0.7, 0.5) if lit else Color(0.12, 0.1, 0.09)
	if _halo and _halo_mat:
		_halo.visible = lit
		_halo_mat.set_shader_parameter("intensity", 1.45 if lit else 0.0)


func _build_halo() -> void:
	if _halo != null:
		return
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO_SHADER
	_halo_mat.set_shader_parameter("glow_color", Color(GLOW_LIT, 1.0))
	_halo_mat.set_shader_parameter("core_color", Color(CORE_LIT, 1.0))
	_halo_mat.set_shader_parameter("half_size", Vector2(1.0, 1.0))
	_halo_mat.set_shader_parameter("halo_radius", 0.9)
	_halo_mat.set_shader_parameter("shaft_width", 0.06)
	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 3.4)
	_halo = MeshInstance3D.new()
	_halo.name = "LanternHalo"
	_halo.mesh = quad
	_halo.material_override = _halo_mat
	_halo.position = LANTERN_LOCAL
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)


## Plain procedural hokora: stone plinth, wooden house with a dark door, a
## gabled roof, the offering table and a paper lantern. About ten draw calls.
func _build_model(root: Node3D) -> void:
	var wood := _material(WOOD_COLOR, 0.82)
	var dark := _material(Color(0.04, 0.035, 0.04), 0.9)
	var stone := _material(STONE_COLOR, 0.92)
	var roof := _material(ROOF_COLOR, 0.7)
	_add_box(root, "Plinth", Vector3(1.5, 0.3, 1.2), Vector3(0.0, 0.15, 0.0), stone)
	_add_box(root, "PlinthStep", Vector3(1.2, 0.1, 0.9), Vector3(0.0, 0.35, 0.0), stone)
	_add_box(root, "Platform", Vector3(0.96, 0.1, 0.78), Vector3(0.0, 0.45, 0.0), wood)
	_add_box(root, "House", Vector3(0.72, 0.6, 0.6), Vector3(0.0, 0.8, 0.0), wood)
	_add_box(root, "Door", Vector3(0.3, 0.42, 0.02), Vector3(0.0, 0.76, 0.31), dark)
	# Gabled roof: two slopes meeting at a ridge along X. Each slope is tilted so
	# its outer (eave) edge sits lower than the ridge, with the eaves overhanging.
	for sign_z in [-1.0, 1.0]:
		var slope := _add_box(root, "RoofSlope", Vector3(1.22, 0.05, 0.62),
			Vector3(0.0, 1.16, 0.27 * sign_z), roof)
		slope.rotation_degrees.x = 30.0 * sign_z
	_add_box(root, "RoofRidge", Vector3(1.24, 0.06, 0.07), Vector3(0.0, 1.36, 0.0), dark)
	_add_box(root, "Altar", Vector3(0.52, 0.42, 0.28), Vector3(0.0, 0.21, 0.78), wood)
	var lantern := MeshInstance3D.new()
	lantern.name = "PaperLantern"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.13
	cyl.height = 0.28
	lantern.mesh = cyl
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color(1.0, 0.56, 0.24)
	lantern.material_override = _flame_mat
	lantern.position = LANTERN_LOCAL
	lantern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lantern)


func _add_box(root: Node3D, node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return mi


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic_specular = 0.25
	return m
