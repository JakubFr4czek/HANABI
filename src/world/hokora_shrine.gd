class_name HokoraShrine
extends Node3D
## Hokora: a small roadside shrine and the source of the yellow Ofuda choice
## (docs/ELEMENTS_PLAN.md, D1 and D12).
##
## Lit until the player has used it: a hand on the offering table opens the choice
## (see [method is_touched_by]). A used shrine goes dark for the rest of the run;
## an unused one stays lit and waits. Its lantern is the unshaded halo of the torii
## gates (it reads through the milk fog) and a suzu bell rings when the player comes
## near, and when a touch is accepted or refused. No lights: the Quest 3 light budget
## is untouched.
##
## The suzu (P8) hangs beside the offering table. A hand or the blade tip on it, with the
## player close, rings it for one elemental charge (D21) and it rests for
## ElementBalance.HOKORA_BELL_COOLDOWN. It glows faintly while the player stands in reach.
## The bell works whether the shrine is lit or used: it is separate from the Ofuda choice.
##
## The model is procedural and lives under the "ModelSlot" node. D5 replaces its
## children with a real asset; nothing else in this script changes. The suzu is its
## own child of this node, so it survives that swap.

## Seconds after a refused touch before the same hand can try again (no bell spam).
const REFUSE_COOLDOWN := 1.5

const HALO_SHADER := preload("res://src/shaders/torii_lantern_halo.gdshader")
const GLOW_LIT := Color(1.0, 0.5, 0.2)
const CORE_LIT := Color(1.0, 0.9, 0.7)
const WOOD_COLOR := Color(0.38, 0.26, 0.16)
const STONE_COLOR := Color(0.34, 0.34, 0.37)
const ROOF_COLOR := Color(0.16, 0.15, 0.16)
## Where the offering table stands, in shrine space (metres).
const ALTAR_LOCAL := Vector3(0.0, 0.46, 0.78)
const LANTERN_LOCAL := Vector3(0.44, 0.7, 0.8)
## Halo strength when lit: a warm glow for the lantern, not a floodlight in the fog.
const LANTERN_INTENSITY := 0.8
const SUZU_RANGE := 14.0
const SUZU_INTERVAL := 6.0
## The suzu hangs from the front eave, beside the offering table (shrine space, metres).
const BELL_LOCAL := Vector3(-0.42, 0.98, 0.7)
const BELL_COLOR := Color(0.62, 0.48, 0.2)
## Emission while the player stands in reach of a ready bell: a faint glow, the hint.
const BELL_HINT_GLOW := 0.9

## Which forest slot this shrine belongs to (set by HokoraManager).
var slot := Vector2i.ZERO
var lit := true
## Counts down after a refused touch; the shrine ignores touches until it reaches 0.
var touch_cooldown := 0.0
## Counts down after a rung (or refused) bell; the bell ignores touches until it reaches 0.
var bell_cooldown := 0.0
## Bells rung accepted this run at this shrine; picks the element of the next charge.
var bell_rings := 0

var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _flame_mat: StandardMaterial3D
var _altar_cloth_mat: StandardMaterial3D
var _bell_mat: StandardMaterial3D
var _suzu_cd := 0.0
var _clock := 0.0


func _ready() -> void:
	add_to_group("hokora_shrines")
	var slot_root := get_node_or_null("ModelSlot") as Node3D
	if slot_root and slot_root.get_child_count() == 0:
		_build_model(slot_root)
	_build_halo()
	_build_bell()
	_apply_lit()


## Offering table, world space: where a hand has to reach to open the choice.
func altar_position() -> Vector3:
	return global_transform * ALTAR_LOCAL


## True when [param hand] reaches the offering table and the player stands close enough
## (D12). A lit shrine that refused a touch a moment ago ignores the hand until its
## cooldown runs out. Nothing here changes state: [RunGame] decides what the touch does.
func is_touched_by(hand: Vector3, player_pos: Vector3) -> bool:
	if not lit or touch_cooldown > 0.0:
		return false
	var altar := altar_position()
	if hand.distance_to(altar) > ElementBalance.HOKORA_HAND_RADIUS:
		return false
	var d := player_pos - altar
	return Vector2(d.x, d.z).length() <= ElementBalance.HOKORA_TOUCH_RADIUS and absf(d.y) <= 2.0


## The touch was accepted: the bell answers, the shrine waits for the choice.
func ring_accepted() -> void:
	if Sfx:
		Sfx.play_at("hokora_suzu", altar_position(), -2.0, 12.0, 1.15)


## The touch was refused (a yōkai close by, or no room for the cards): a quiet bell
## and a short cooldown. The shrine stays lit.
func refuse() -> void:
	touch_cooldown = REFUSE_COOLDOWN
	if Sfx:
		Sfx.play_at("hokora_suzu", altar_position(), -12.0, 10.0, 0.95)


## Where the suzu hangs, world space: where a hand or the blade tip has to reach.
func bell_position() -> Vector3:
	return global_transform * BELL_LOCAL


## The element the next bell charge stores: the combat elements in turn, offset by the
## slot so neighbouring shrines do not all start on the same one.
func bell_element() -> String:
	return Elements.COMBAT_ELEMENTS[posmod(slot.x + slot.y + bell_rings, Elements.COMBAT_ELEMENTS.size())]


## True when [param point] (a hand or the blade tip) touches the suzu and the player
## stands in its reach (P8). A bell still resting ignores it. Nothing here changes
## state: [RunGame] stores the charge and then calls [method ring_bell].
func is_bell_touched_by(point: Vector3, player_pos: Vector3) -> bool:
	if bell_cooldown > 0.0:
		return false
	if point.distance_to(bell_position()) > ElementBalance.HOKORA_BELL_HAND_RADIUS:
		return false
	return _in_bell_reach(player_pos)


## The charge was stored: the suzu rings, the next charge changes element, the bell rests.
func ring_bell() -> void:
	bell_rings += 1
	bell_cooldown = ElementBalance.HOKORA_BELL_COOLDOWN
	if Sfx:
		Sfx.play_at("hokora_suzu", bell_position(), -2.0, 12.0, 1.3)


## The charge was not stored (the buffer is full): a quiet ring and a short rest only
## (REFUSE_COOLDOWN), not the full bell cooldown, so the next real charge comes soon after.
func refuse_bell() -> void:
	bell_cooldown = REFUSE_COOLDOWN
	if Sfx:
		Sfx.play_at("hokora_suzu", bell_position(), -12.0, 10.0, 1.1)


func _in_bell_reach(player_pos: Vector3) -> bool:
	var d := player_pos - bell_position()
	return Vector2(d.x, d.z).length() <= ElementBalance.HOKORA_BELL_TOUCH_RADIUS and absf(d.y) <= 2.0


## The choice was taken: the shrine goes dark for the rest of the run.
func consume() -> void:
	set_lit(false)


func set_lit(value: bool) -> void:
	lit = value
	_apply_lit()


## Per-physics-frame: lantern flicker, the halo turns to face the player, and the
## suzu rings when the player comes near (not while the shrine is dark).
func step(delta: float, player_pos: Vector3) -> void:
	_clock += delta
	touch_cooldown = maxf(touch_cooldown - delta, 0.0)
	bell_cooldown = maxf(bell_cooldown - delta, 0.0)
	if _bell_mat:
		var hint := bell_cooldown <= 0.0 and _in_bell_reach(player_pos)
		_bell_mat.emission_energy_multiplier = BELL_HINT_GLOW if hint else 0.0
	if _halo == null:
		return
	if lit:
		var flicker := 1.0 + 0.07 * sin(_clock * 3.1 + float(slot.x) * 0.7) + 0.04 * sin(_clock * 7.3)
		_halo_mat.set_shader_parameter("intensity", LANTERN_INTENSITY * flicker)
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
	if _altar_cloth_mat:
		_altar_cloth_mat.emission_energy_multiplier = 0.45 if lit else 0.0
		_altar_cloth_mat.albedo_color = Color(0.85, 0.30, 0.16) if lit else Color(0.20, 0.12, 0.10)
	if _halo and _halo_mat:
		_halo.visible = lit
		_halo_mat.set_shader_parameter("intensity", LANTERN_INTENSITY if lit else 0.0)


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
	quad.size = Vector2(2.0, 2.0)
	_halo = MeshInstance3D.new()
	_halo.name = "LanternHalo"
	_halo.mesh = quad
	_halo.material_override = _halo_mat
	_halo.position = LANTERN_LOCAL
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)


## The suzu: a small bronze bell on a cord under the front eave. Its glow is the hint
## that a bell is ready and in reach. It is not a collider: touches are distance checks.
func _build_bell() -> void:
	_bell_mat = StandardMaterial3D.new()
	_bell_mat.albedo_color = BELL_COLOR
	_bell_mat.metallic = 0.6
	_bell_mat.roughness = 0.35
	_bell_mat.emission_enabled = true
	_bell_mat.emission = Color(1.0, 0.78, 0.4)
	_bell_mat.emission_energy_multiplier = 0.0
	var bell := MeshInstance3D.new()
	bell.name = "Suzu"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.06
	cyl.height = 0.07
	bell.mesh = cyl
	bell.material_override = _bell_mat
	bell.position = BELL_LOCAL
	bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bell)


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
	_altar_cloth_mat = StandardMaterial3D.new()
	_altar_cloth_mat.albedo_color = Color(0.85, 0.30, 0.16)
	_altar_cloth_mat.emission_enabled = true
	_altar_cloth_mat.emission = Color(0.95, 0.45, 0.18)
	_altar_cloth_mat.emission_energy_multiplier = 0.45
	_altar_cloth_mat.roughness = 0.75
	var cloth := _add_box(root, "AltarCloth", Vector3(0.46, 0.015, 0.24), Vector3(0.0, 0.425, 0.78), _altar_cloth_mat)
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
