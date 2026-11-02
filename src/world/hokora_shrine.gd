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
## The model lives under the "ModelSlot" node: the SamRi small shrine (CC BY 4.0, 2.8k tris,
## baked in metres by tools/prep_forest_assets.py), mossy and wet like the rest of the forest
## (wet_surface shader). The offering table, the candle and the suzu are built here on top of
## it. The candle carries one warm OmniLight, and only for the shrine nearest the player (N6);
## the other shrines have none, so the Quest 3 light budget holds.

## Seconds after a refused touch before the same hand can try again (no bell spam).
const REFUSE_COOLDOWN := 1.5

const HALO_SHADER := preload("res://src/shaders/torii_lantern_halo.gdshader")
const GLOW_LIT := Color(1.0, 0.5, 0.2)
const CORE_LIT := Color(1.0, 0.9, 0.7)
const WET_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const SHRINE_MODEL := preload("res://assets/models/environment/shrine/shrine_samri_baked.glb")
## The baked model stands on its own base (y 0 .. 1.005 m) and is centred on x/z. This
## moves it back so the shrine's ground (the plinth top) is y = 0 and its front (the
## shimenawa rope, +z) is where the constants below expect it.
const MODEL_OFFSET := Vector3(0.0, -1.0051, -0.0533)
const WOOD_COLOR := Color(0.30, 0.20, 0.13)
const CANDLE_COLOR := Color(0.9, 0.7, 0.5)
const MOSS_COLOR := Color(0.24, 0.38, 0.14)
## Where the offering table stands, in shrine space (metres).
const ALTAR_LOCAL := Vector3(0.0, 0.46, 0.78)
## The candle, behind the front lattice of the house: the warm point the halo and light sit on.
const LANTERN_LOCAL := Vector3(0.0, 0.42, 0.3)
## The candle's light: warm, short range, no shadows. Lit only for the nearest lit shrine.
const CANDLE_LIGHT_RANGE := 4.5
const CANDLE_LIGHT_ENERGY := 3.0
const CANDLE_LIGHT_COLOR := Color(1.0, 0.62, 0.32)
## The light hangs in front of the house, over the offering table: the candle is behind the
## front wall, so a light there would leave the front faces (the ones the player sees) dark.
const CANDLE_LIGHT_LOCAL := Vector3(0.0, 0.8, 0.7)
## Beyond this (metres from the player) no shrine takes the light; nearer shrines do.
const CANDLE_LIGHT_REACH := 30.0
## Halo strength when lit: a warm glow for the lantern, not a floodlight in the fog.
const LANTERN_INTENSITY := 0.8
const SUZU_RANGE := 14.0
const SUZU_INTERVAL := 6.0
## The suzu hangs from the front eave, beside the offering table (shrine space, metres).
const BELL_LOCAL := Vector3(-0.42, 0.6, 0.7)
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
var _shrine_mat: ShaderMaterial
var _candle_light: OmniLight3D
var _suzu_cd := 0.0
var _clock := 0.0


func _ready() -> void:
	add_to_group("hokora_shrines")
	var slot_root := get_node_or_null("ModelSlot") as Node3D
	if slot_root and slot_root.get_child_count() == 0:
		_build_model(slot_root)
	_build_halo()
	_build_bell()
	_build_candle_light()
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
	var flicker := 1.0 + 0.07 * sin(_clock * 3.1 + float(slot.x) * 0.7) + 0.04 * sin(_clock * 7.3)
	if _candle_light:
		_candle_light.visible = lit and _holds_candle_light(player_pos)
		_candle_light.light_energy = CANDLE_LIGHT_ENERGY * flicker
	if _halo == null:
		return
	if lit:
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


## True when this lit shrine is the one nearest the player (flat distance) and within reach.
## Every shrine asks this per frame, so the single candle light moves with the player.
func _holds_candle_light(player_pos: Vector3) -> bool:
	var own := Vector2(player_pos.x - global_position.x, player_pos.z - global_position.z).length()
	if own > CANDLE_LIGHT_REACH:
		return false
	for other in get_tree().get_nodes_in_group("hokora_shrines"):
		var shrine := other as HokoraShrine
		if shrine == null or shrine == self or not shrine.lit:
			continue
		var d := Vector2(player_pos.x - shrine.global_position.x, player_pos.z - shrine.global_position.z).length()
		if d < own:
			return false
	return true


func _apply_lit() -> void:
	if _candle_light:
		_candle_light.light_energy = CANDLE_LIGHT_ENERGY if lit else 0.0
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


## The asset: the SamRi shrine (house, roof, stairs, shimenawa, plinth), then the offering
## table, the cloth and the candle, which the asset does not carry. One mesh, one material,
## one draw call for the house.
func _build_model(root: Node3D) -> void:
	var model := SHRINE_MODEL.instantiate() as Node3D
	model.name = "Samri"
	model.position = MODEL_OFFSET
	root.add_child(model)
	_dress_model(model)
	_build_altar(root)
	_build_candle(root)


## Every mesh of the asset takes the forest's wet shader: the scan's atlas as the albedo,
## soaked, with moss on the up-facing parts (roof, steps, plinth cap).
func _dress_model(model: Node3D) -> void:
	var albedo: Texture2D = null
	var meshes := _mesh_instances(model)
	for mi in meshes:
		var base := mi.get_active_material(0) as BaseMaterial3D
		if base != null and albedo == null:
			albedo = base.albedo_texture
	_shrine_mat = ShaderMaterial.new()
	_shrine_mat.shader = WET_SHADER
	_shrine_mat.set_shader_parameter("albedo_texture", albedo)
	_shrine_mat.set_shader_parameter("base_color", Color.WHITE)
	_shrine_mat.set_shader_parameter("roughness_dry", 0.86)
	_shrine_mat.set_shader_parameter("roughness_wet", 0.7)
	_shrine_mat.set_shader_parameter("wetness", 0.4)
	_shrine_mat.set_shader_parameter("waterline_y", -10.0)
	_shrine_mat.set_shader_parameter("fill", 1.0)
	_shrine_mat.set_shader_parameter("specular_scale", 0.15)
	_shrine_mat.set_shader_parameter("fog_fill", 0.6)
	_shrine_mat.set_shader_parameter("procedural_ao", 0.45)
	_shrine_mat.set_shader_parameter("fog_rim", 0.6)
	# Faint warm self-light on the scan's own texture: the form of the wood reads at night
	# even where the candle does not reach (the candle is the warm point, this is the body).
	_shrine_mat.set_shader_parameter("emission_tint", Color(0.55, 0.32, 0.16))
	_shrine_mat.set_shader_parameter("moss_amount", 0.8)
	_shrine_mat.set_shader_parameter("moss_color", MOSS_COLOR)
	for mi in meshes:
		mi.material_override = _shrine_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_mesh_instances(child))
	return out


## Offering table (wood, with the red cloth that glows while the shrine is lit).
func _build_altar(root: Node3D) -> void:
	var wood := _material(WOOD_COLOR, 0.82)
	_add_box(root, "Altar", Vector3(0.52, 0.42, 0.28), Vector3(0.0, 0.21, 0.78), wood)
	_altar_cloth_mat = StandardMaterial3D.new()
	_altar_cloth_mat.albedo_color = Color(0.85, 0.30, 0.16)
	_altar_cloth_mat.emission_enabled = true
	_altar_cloth_mat.emission = Color(0.95, 0.45, 0.18)
	_altar_cloth_mat.emission_energy_multiplier = 0.45
	_altar_cloth_mat.roughness = 0.75
	var cloth := _add_box(root, "AltarCloth", Vector3(0.46, 0.015, 0.24), Vector3(0.0, 0.425, 0.78), _altar_cloth_mat)
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The candle behind the lattice: an unshaded flame that goes out with the shrine.
func _build_candle(root: Node3D) -> void:
	var candle := MeshInstance3D.new()
	candle.name = "Candle"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.06
	cyl.height = 0.2
	candle.mesh = cyl
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color(1.0, 0.56, 0.24)
	candle.material_override = _flame_mat
	candle.position = LANTERN_LOCAL
	candle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(candle)


## The one warm light of the shrine (see [method _holds_candle_light]). No shadows.
func _build_candle_light() -> void:
	_candle_light = OmniLight3D.new()
	_candle_light.name = "CandleLight"
	_candle_light.light_color = CANDLE_LIGHT_COLOR
	_candle_light.omni_range = CANDLE_LIGHT_RANGE
	_candle_light.shadow_enabled = false
	_candle_light.position = CANDLE_LIGHT_LOCAL
	_candle_light.visible = false
	add_child(_candle_light)


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
