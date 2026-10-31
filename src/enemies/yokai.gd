class_name Yokai
extends ActiveRagdoll
## Basic yōkai swarm enemy (docs/GDD.md §7, NIGHT_PLAN.md §1):
## A lightweight 7-body active ragdoll (no sword, no IK) that emerges from the
## storm fog across the water, hunches forward with a pale horned Noh/oni mask,
## crimson-lacquered shoulder/chest armor and ember-tipped claws, staggers on
## blade hits, and collapses + dissolves in a burst of sparks when slain.

signal hit_received(hit: Dictionary)
signal died(yokai: Yokai, last_hit: Dictionary)
signal dissolve_finished(yokai: Yokai)

enum Kind { SWARM, ELITE }

const WET_SURFACE_SHADER := preload("res://src/shaders/wet_surface.gdshader")
const MOVE_ACCEL := 5.0
const BURST_ACCEL := 24.0
## Parts a very strong clean cut takes off. A leg or the head is fatal.
const SEVERABLE := ["arm_l", "arm_r", "leg_l", "leg_r", "head"]
## Skin of a swarm body; an elite tints it a little toward its element.
const SKIN_BASE := Color(0.18, 0.17, 0.26)
## Elite eyes, sigil and claws burn this much brighter than a swarm's, so the
## element still reads from across the fog.
const ELITE_LIFT := 1.3
## Eye light of a swarm yōkai with a school: a few pixels at 8 m, so a bit brighter than plain red.
const SCHOOL_EYE_GLOW := 1.4
## The hit flash of a plain or same-school blow (ember red); a counter flashes in its school's light.
const EMBER_FLASH_SKIN := Color(1.0, 0.36, 0.22)
const EMBER_FLASH_MASK := Color(0.9, 0.3, 0.16)

@export var profile: EnemyProfile
## A cut severs the limb it lands on only when all of these hold: the edge
## leads (alignment), the full arm is behind it (power), the blade is moving
## fast (real m/s at the contact) and the blow carries real momentum (N·s).
@export var sever_min_speed := 8.5
@export var sever_min_power := 0.8
@export var sever_min_impulse := 12.0
@export var sever_min_alignment := 0.7
## Extra damage (fraction of max HP) for taking an arm off.
@export var sever_arm_damage := 0.45

var hp := 45.0
var brain: YokaiBrain
var is_dead := false
var last_kill_element := Elements.NONE
var kind := Kind.SWARM
## Instance id of the torii gate or hokora shrine this yōkai stands guard for (AnchorGuards),
## 0 for an ordinary wave yōkai. Set on every spawn, so a pooled body never keeps a stale post.
var guard_post := 0
## The body's school: rolled per swarm yōkai (WaveProfile), fixed for an elite. Plain = NONE.
var body_element := Elements.NONE
var use_pathfinding := false

var _nav_agent: NavigationAgent3D
var _nav_repath := 0
var _detour_side := 1.0
var _detour_time := 0.0
var _nav_dir := Vector3.ZERO

var _skin := ShaderMaterial.new()
var _mask_mat := ShaderMaterial.new()
var _sash := ShaderMaterial.new()
var _eyes := StandardMaterial3D.new()
## Fog-piercing glow points over the eye slits (EyeGlow).
var _eye_glows: Array[MeshInstance3D] = []
var _claw_mat := StandardMaterial3D.new()
var _sigil_mat := StandardMaterial3D.new()

var _move_blocked := false
var _step_time := 0.0
var _stepping := false
var _was_attacking := false
var _hit_player_this_strike := false
var _last_tell := 0.0
var _flash_time := 0.0
var _dissolve_timer := 0.0
## Longest a dead body falls before it bursts into petals anyway.
var _dissolve_duration := 0.95
var _petal_burst_done := false
## Petals a whole yōkai comes apart into.
const DEATH_PETALS := 90
const MASK_FILL := 0.55
## Size of the eye glow points in the mask sockets (EyeGlow base size, m).
const MASK_EYE_GLOW_SIZE := 0.075
var _slow_time := 0.0
var _slow_scale := 1.0
var _confusion_time := 0.0
var _lod_far := false
var _lod_tick := 0
var _flinch_time := 0.0
var _torso_lag_pitch := 0.0
var _severed := {}  # part name -> true while that limb is gone


func prepare_for_spawn() -> void:
	is_dead = false
	_dissolve_timer = 0.0
	_petal_burst_done = false
	_slow_time = 0.0
	_slow_scale = 1.0
	_confusion_time = 0.0
	_flinch_time = 0.0
	_flash_time = 0.0
	_lod_far = false
	_detour_side = 1.0
	last_kill_element = Elements.NONE
	visible = true
	# The death dissolve shrinks limbs and fades every material to ~0; a pooled
	# body reused without this comes back tiny, dark and tinted by its elite life.
	_reset_spawn_look()
	_severed.clear()
	for p: RagdollPart in parts.values():
		p.scale = Vector3.ONE
		p.visible = true
		p.collision_layer = 2
		p.collision_mask = 4 | 8
	# Before add_child: the joints re-anchor on entering the tree, so the
	# body must be in its rest shape by then (see restore_rest_layout).
	restore_rest_layout()
	# The pool calls this before add_child. reset_body reads global transforms,
	# which are identity off the tree; place_at() resets once the body is back.
	if is_inside_tree():
		reset_body()
		snap_pose("stalk")
	if brain:
		brain.reset()


## Moves a living yōkai to [param pos] facing [param yaw] (straggler recall).
func place_at(pos: Vector3, yaw: float) -> void:
	global_position = pos
	global_rotation = Vector3(0.0, yaw, 0.0)
	_nav_dir = Vector3.ZERO
	_nav_repath = 0
	_move_blocked = false
	_detour_time = 0.0
	reset_body()
	snap_pose("stalk")
	if brain:
		brain.reset()


func apply_distance_lod(dist: float) -> void:
	_lod_far = dist > 12.5
	_eyes.emission_energy_multiplier = 0.22 if _lod_far else 0.85


func _ready() -> void:
	max_anchor_lead = 0.4
	add_to_group("yokai")
	add_to_group("enemies")
	if profile == null:
		profile = EnemyProfile.new()
		profile.display_name = "Yokai"
		profile.max_hp = 95.0
		profile.poise_per_impulse = 0.03
		profile.poise_damage_scale = 0.012
		profile.muscle_damage_scale = 0.006
		profile.knockdown_time = 0.9
		profile.getup_time = 1.1
	hp = profile.max_hp

	# Weathered indigo-slate rain-soaked skin with moonlit sky fill so the
	# silhouette reads clearly against the storm fog and dark water.
	_skin.shader = WET_SURFACE_SHADER
	_skin.set_shader_parameter("base_color", SKIN_BASE)
	_skin.set_shader_parameter("roughness_dry", 0.70)
	_skin.set_shader_parameter("roughness_wet", 0.34)
	_skin.set_shader_parameter("wetness", 0.50)
	_skin.set_shader_parameter("waterline_y", -10.0)
	_skin.set_shader_parameter("grain_amount", 0.35)
	_skin.set_shader_parameter("grain_scale", 28.0)
	_skin.set_shader_parameter("fill", 1.65)
	_skin.set_shader_parameter("flash_color", Color(1.0, 0.36, 0.22))

	# The demon mask (N3): its own albedo, ORM and normal map through the wet shader. The
	# albedo is a dark lacquer; the base colour lifts it to an aged, desaturated tone.
	_mask_mat.shader = WET_SURFACE_SHADER
	_mask_mat.set_shader_parameter("albedo_texture", YokaiForms.mask_albedo())
	_mask_mat.set_shader_parameter("orm_texture", YokaiForms.mask_orm())
	_mask_mat.set_shader_parameter("orm_mode", 1)
	_mask_mat.set_shader_parameter("normal_texture", YokaiForms.mask_normal())
	_mask_mat.set_shader_parameter("normal_depth", 1.0)
	# Aged, not glowing: the face reads in the fog without shining like a signal.
	_mask_mat.set_shader_parameter("base_color", YokaiForms.MASK_TINT)
	_mask_mat.set_shader_parameter("roughness_dry", 0.72)
	_mask_mat.set_shader_parameter("roughness_wet", 0.38)
	_mask_mat.set_shader_parameter("wetness", 0.42)
	_mask_mat.set_shader_parameter("waterline_y", -10.0)
	_mask_mat.set_shader_parameter("fill", MASK_FILL)
	# Hit flash on the mask is the same ember as the skin, not the shader's
	# pale default — a white blink on the face read as a UI clue.
	_mask_mat.set_shader_parameter("flash_color", Color(0.9, 0.3, 0.16))

	# Rain-soaked crimson-vermilion armour lacquer (sode & chest wrap).
	_sash.shader = WET_SURFACE_SHADER
	_sash.set_shader_parameter("base_color", Color(0.46, 0.055, 0.075))
	_sash.set_shader_parameter("roughness_dry", 0.68)
	_sash.set_shader_parameter("roughness_wet", 0.32)
	_sash.set_shader_parameter("wetness", 0.48)
	_sash.set_shader_parameter("waterline_y", -10.0)
	_sash.set_shader_parameter("fill", 1.60)

	_eyes.albedo_color = Color(0.95, 0.18, 0.10)
	_eyes.emission_enabled = true
	_eyes.emission = Color(1.6, 0.22, 0.08)
	_eyes.emission_energy_multiplier = 0.85

	_sigil_mat.albedo_color = Color(0.85, 0.16, 0.10)
	_sigil_mat.emission_enabled = true
	_sigil_mat.emission = Color(1.35, 0.18, 0.08)
	_sigil_mat.emission_energy_multiplier = 0.55

	_claw_mat.albedo_color = Color(0.82, 0.74, 0.64)
	_claw_mat.roughness = 0.55
	_claw_mat.emission_enabled = true
	_claw_mat.emission = Color(1.5, 0.24, 0.10)
	_claw_mat.emission_energy_multiplier = 0.32

	pose_variation_deg = 5.0
	idle_sway_deg = 5.5
	overlay_blend = 0.32
	default_pose_blend = 0.38
	sway_poses = PackedStringArray(["stalk", "approach", "idle", "flinch"])
	super._ready()
	# Standing swarm bodies live on layer 2 but never collide with it: a
	# ragdoll's own parts (and other yōkai) pass through each other. The rest
	# pose already overlaps pelvis/legs and chest/arms by centimetres, so
	# self-collision made the solver constantly pop limbs out of the torso —
	# worst in strike poses, where an arm pressed into the chest was ejected
	# at speed. The joints hold the body together; the brain's separation
	# steering keeps yōkai from stacking. The ground mesh and the trunks are
	# not in the mask either: both snag or launch a foot, and the height
	# spring carries the body. Parts are born on the fallen-body layer; a
	# fresh spawn skips prepare_for_spawn.
	for p: RagdollPart in parts.values():
		p.collision_layer = 2
		p.collision_mask = 4 | 8
	if not state_changed.is_connected(_on_ragdoll_state_changed):
		state_changed.connect(_on_ragdoll_state_changed)

	for child in get_children():
		if child is YokaiBrain:
			brain = child
	if brain == null:
		brain = YokaiBrain.new()
		brain.name = "Brain"
		add_child(brain)
	brain.setup(self, profile)
	snap_pose("stalk")
	# configure_kind runs before add_child (spawn_enemy_at), so the ready look above
	# would overwrite a school's eyes: apply the kind's look once more, last.
	_apply_kind_visuals()


## While standing, the height spring carries the body and the parts ignore
## the terrain (see _ready). Knocked down there is no spring, so the body
## must land on the ground for real — without terrain in the mask it fell
## through the world and rose back minutes later as a "dead" straggler.
func _on_ragdoll_state_changed(new_state: State) -> void:
	if is_dead:
		return
	var mask := (1 | 4 | 8) if new_state != State.STANDING else (4 | 8)
	for p: RagdollPart in parts.values():
		if not _severed.has(String(p.name)):
			p.collision_mask = mask


func configure_kind(p_kind: Kind, element: String = Elements.NONE, max_hp: float = -1.0) -> void:
	kind = p_kind
	body_element = element
	var hp_val := max_hp if max_hp > 0.0 else profile.max_hp
	if p_kind == Kind.ELITE:
		profile = EnemyCatalog.make_elite_profile(element, hp_val)
	else:
		profile = EnemyCatalog.make_swarm_profile(hp_val, element)
	hp = profile.max_hp
	_apply_kind_visuals()
	if brain:
		brain.setup(self, profile)


func enable_pathfinding() -> void:
	if _nav_agent != null:
		use_pathfinding = true
		return
	use_pathfinding = true
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.name = "Navigator"
	_nav_agent.path_desired_distance = 0.45
	_nav_agent.target_desired_distance = 1.05
	_nav_agent.path_max_distance = 24.0
	_nav_agent.avoidance_enabled = false
	add_child(_nav_agent)


func is_elite() -> bool:
	return kind == Kind.ELITE


func is_staggered() -> bool:
	return brain != null and brain.state == YokaiBrain.State.STAGGER


func apply_stagger(duration: float = 1.4) -> void:
	if brain and brain.has_method("stagger"):
		brain.stagger(duration)


## Swarm base look (matches _ready): also the cleanup for a pooled elite
## reused as a swarm — normal size, no elite group or element tint.
func _reset_spawn_look() -> void:
	scale = Vector3.ONE
	remove_from_group("elite_yokai")
	_skin.set_shader_parameter("base_color", SKIN_BASE)
	_skin.set_shader_parameter("fill", 1.65)
	_skin.set_shader_parameter("flash", 0.0)
	_mask_mat.set_shader_parameter("fill", MASK_FILL)
	_mask_mat.set_shader_parameter("flash", 0.0)
	_sash.set_shader_parameter("base_color", Color(0.46, 0.055, 0.075))
	_sash.set_shader_parameter("fill", 1.60)
	_eyes.albedo_color = Color(0.95, 0.18, 0.10)
	_eyes.emission = Color(1.6, 0.22, 0.08)
	_eyes.emission_energy_multiplier = 0.85
	_sigil_mat.albedo_color = Color(0.85, 0.16, 0.10)
	_sigil_mat.emission = Color(1.35, 0.18, 0.08)
	_sigil_mat.emission_energy_multiplier = 0.55
	_claw_mat.albedo_color = Color(0.82, 0.74, 0.64)
	_claw_mat.emission = Color(1.5, 0.24, 0.10)
	_claw_mat.emission_energy_multiplier = 0.32
	EyeGlow.set_color(_eye_glows, Color(1.0, 0.24, 0.1))
	EyeGlow.set_glow(_eye_glows, 1.0)


func _apply_kind_visuals() -> void:
	if kind != Kind.ELITE:
		_reset_spawn_look()
		# A swarm yōkai of a school reads it in the eyes and the mask sigil only:
		# no skin tint and no sash, so it never looks like an elite from afar.
		if body_element != Elements.NONE:
			_apply_element_eyes(Elements.eye_color(body_element))
			EyeGlow.set_glow(_eye_glows, SCHOOL_EYE_GLOW)
		return
	# No node scaling: scaling the Yokai node moves rigid-body parts away
	# from their joint anchors (shapes do not scale with the node), so elite
	# bodies fought their own joints and tore themselves apart. Elites read
	# as elite from the element in the eyes, sigil, sash, claws and skin, not
	# from a ring drawn around them (a ring showed through trees and bodies).
	scale = Vector3.ONE
	var accent := Elements.accent_color(body_element)
	var ember := _elite_ember(accent)
	_skin.set_shader_parameter("base_color", SKIN_BASE.lerp(accent, 0.18))
	_apply_element_eyes(Elements.eye_color(body_element))
	_sash.set_shader_parameter("base_color", accent.darkened(0.55))
	_claw_mat.emission = ember * 1.2


## The elite's lit colour (eyes, sigil, claws). The accents of ink and storm are
## pale, and the eye shader's bloom (×5.5 at the core) pushes a pale glow to
## white. More saturation and a value cap keep the hue once it blooms.
static func _elite_ember(accent: Color) -> Color:
	return Color.from_hsv(accent.h, clampf(accent.s * 1.6, 0.0, 1.0), minf(accent.v, 0.75))


## D17: a counter blow flashes the body in the attacker's school light (docs/ELEMENT_COUNTERS.md §3.8).
func _flash_for_matchup(matchup: float, attacker: String) -> void:
	var counter := matchup > 1.0 and attacker != Elements.NONE
	_skin.set_shader_parameter("flash_color", Elements.accent_color(attacker) if counter else EMBER_FLASH_SKIN)
	_mask_mat.set_shader_parameter("flash_color", Elements.accent_color(attacker) if counter else EMBER_FLASH_MASK)


## The school's light in the eyes, the EyeGlow points and the mask sigil (shared by swarm and elite).
func _apply_element_eyes(accent: Color) -> void:
	var ember := _elite_ember(accent)
	_sigil_mat.emission = ember * 1.35
	_eyes.emission = ember * 1.6
	EyeGlow.set_color(_eye_glows, ember)


# --- 7-body lightweight ragdoll ------------------------------------------------

func _define_parts() -> Dictionary:
	var d := {
		"pelvis": {"shape": "box", "size": Vector3(0.28, 0.17, 0.17), "pos": Vector3(0, 0.90, 0), "mass": 9.0, "zone": "torso"},
		"chest": {"shape": "box", "size": Vector3(0.34, 0.42, 0.20), "pos": Vector3(0, 1.22, 0.03), "mass": 12.0, "zone": "torso",
			"parent": "pelvis", "joint": Vector3(0, 1.00, 0), "max_torque": 520.0,
			"limits": {"x": Vector2(-25, 45), "y": Vector2(-35, 35), "z": Vector2(-25, 25)}},
		"head": {"shape": "sphere", "radius": 0.115, "pos": Vector3(0, 1.56, 0.06), "mass": 3.5, "zone": "head",
			"parent": "chest", "joint": Vector3(0, 1.44, 0.04), "max_torque": 95.0,
			"limits": {"x": Vector2(-40, 40), "y": Vector2(-60, 60), "z": Vector2(-30, 30)}},
	}
	for side in ["l", "r"]:
		var s := 1.0 if side == "l" else -1.0
		d["arm_" + side] = {
			"shape": "capsule", "radius": 0.048, "height": 0.56,
			"pos": Vector3(0.24 * s, 1.12, 0.08),
			"mass": 3.0, "zone": "limb", "parent": "chest",
			"joint": Vector3(0.23 * s, 1.38, 0.03), "max_torque": 240.0,
			"limits": {"x": Vector2(-150, 65), "y": Vector2(-75, 75), "z": _mirror(Vector2(-35, 110), s)},
		}
		d["leg_" + side] = {
			"shape": "capsule", "radius": 0.062, "height": 0.82,
			"pos": Vector3(0.10 * s, 0.44, 0),
			"mass": 9.5, "zone": "limb", "parent": "pelvis",
			"joint": Vector3(0.10 * s, 0.82, 0), "max_torque": 460.0,
			"limits": {"x": Vector2(-85, 45), "y": Vector2(-25, 25), "z": _mirror(Vector2(-15, 45), s)},
			"friction": 0.25,
			"extra_shapes": [{"shape": "box", "size": Vector3(0.10, 0.06, 0.22), "offset": Vector3(0, -0.40, 0.04)}],
		}
	return d


static func _mirror(range_deg: Vector2, s: float) -> Vector2:
	return range_deg if s > 0.0 else Vector2(-range_deg.y, -range_deg.x)


func _define_poses() -> Dictionary:
	return {
		"stalk": {
			"_blend": 0.42,
			"_ease": "inout",
			"_max_speed": 5.2,
			"chest": Vector3(18, 0, 0),
			"head": Vector3(-12, 0, 0),
			"arm_r": Vector3(-52, -16, -22),
			"arm_l": Vector3(-52, 16, 22),
			"leg_l": Vector3(-8, 0, 5),
			"leg_r": Vector3(6, 0, -5),
		},
		"approach": {
			"_blend": 0.48,
			"_ease": "inout",
			"_stiffness": 0.9,
			"_max_speed": 4.8,
			"chest": Vector3(28, 0, 4),
			"head": Vector3(-8, 0, -6),
			"arm_r": Vector3(-48, -12, -18),
			"arm_l": Vector3(-48, 12, 18),
			"leg_l": Vector3(-14, 0, 8),
			"leg_r": Vector3(10, 0, -6),
		},
		"flinch": {
			"_stiffness": 1.05,
			"_blend": 0.22,
			"_ease": "out",
			"_max_speed": 6.5,
			"chest": Vector3(-22, 0, 0),
			"head": Vector3(-28, 0, 0),
			"arm_r": Vector3(-72, 8, -28),
			"arm_l": Vector3(-72, -8, 28),
		},
		"windup_r": {
			"_stiffness": 1.35,
			"_blend": 0.35,
			"chest": Vector3(-10, -24, 0),
			"head": Vector3(6, 22, -6),
			"arm_r": Vector3(-135, -35, -45),
			"arm_l": Vector3(-35, 20, 28),
			"leg_l": Vector3(-14, 0, 6),
			"leg_r": Vector3(12, 0, -6),
		},
		"slash_r": {
			"_stiffness": 1.6,
			"_max_speed": 8.0,
			"_blend": 0.12,
			"_ease": "in",
			"chest": Vector3(26, 22, 0),
			"head": Vector3(-16, -18, 0),
			"arm_r": Vector3(-65, 38, 12),
			"arm_l": Vector3(-20, 15, 32),
			"leg_l": Vector3(-24, 0, 6),
			"leg_r": Vector3(16, 0, -6),
		},
		"windup_l": {
			"_stiffness": 1.35,
			"_blend": 0.35,
			"chest": Vector3(-10, 24, 0),
			"head": Vector3(6, -22, 6),
			"arm_l": Vector3(-135, 35, 45),
			"arm_r": Vector3(-35, -20, -28),
			"leg_r": Vector3(-14, 0, -6),
			"leg_l": Vector3(12, 0, 6),
		},
		"slash_l": {
			"_stiffness": 1.6,
			"_max_speed": 8.0,
			"_blend": 0.12,
			"_ease": "in",
			"chest": Vector3(26, -22, 0),
			"head": Vector3(-16, 18, 0),
			"arm_l": Vector3(-65, -38, -12),
			"arm_r": Vector3(-20, -15, -32),
			"leg_r": Vector3(-24, 0, -6),
			"leg_l": Vector3(16, 0, 6),
		},
		"windup_double": {
			"_stiffness": 1.4,
			"_blend": 0.38,
			"chest": Vector3(-16, 0, 0),
			"head": Vector3(10, 0, 0),
			"arm_r": Vector3(-142, -18, -32),
			"arm_l": Vector3(-142, 18, 32),
			"leg_l": Vector3(-12, 0, 7),
			"leg_r": Vector3(-12, 0, -7),
		},
		"slash_double": {
			"_stiffness": 1.65,
			"_max_speed": 8.5,
			"_blend": 0.12,
			"_ease": "in",
			"chest": Vector3(30, 0, 0),
			"head": Vector3(-20, 0, 0),
			"arm_r": Vector3(-58, 22, 8),
			"arm_l": Vector3(-58, -22, -8),
			"leg_l": Vector3(-26, 0, 6),
			"leg_r": Vector3(18, 0, -6),
		},
		"step_l": {
			"leg_l": Vector3(-22, 0, 5),
			"leg_r": Vector3(12, 0, -5),
		},
		"step_r": {
			"leg_l": Vector3(12, 0, 5),
			"leg_r": Vector3(-22, 0, -5),
		},
		"staggered": {
			"_stiffness": 0.65,
			"_blend": 0.15,
			"_ease": "out",
			"chest": Vector3(-18, 0, 0),
			"head": Vector3(-18, 0, 0),
			"arm_r": Vector3(-95, 0, -42),
			"arm_l": Vector3(-95, 0, 42),
			"leg_l": Vector3(-4, 0, 8),
			"leg_r": Vector3(8, 0, -8),
		},
		"recover": {
			"_stiffness": 0.82,
			"_blend": 0.38,
			"_ease": "out",
			"chest": Vector3(26, 0, -5),
			"head": Vector3(-18, 0, 4),
			"arm_r": Vector3(-38, 6, -18),
			"arm_l": Vector3(-38, -6, 18),
			"leg_l": Vector3(-18, 0, 6),
			"leg_r": Vector3(12, 0, -6),
		},
		"torso_lag": {
			"_blend": 0.28,
			"_ease": "inout",
			"chest": Vector3(0, 0, 0),
		},
		"idle": {"_blend": 0.5},
	}


func _decorate_part(part_name: String, part: RagdollPart, def: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = YokaiForms.body_mesh(part_name, def)
	mi.material_override = _skin
	part.add_child(mi)

	match part_name:
		"head":
			# The demon mask (N3, CC BY 4.0, baked into the head's frame). Kept on a Kirisute
			# piece: the mask and the eyes read as the yōkai's head.
			var mask_mi := MeshInstance3D.new()
			mask_mi.mesh = YokaiForms.mask_mesh()
			mask_mi.material_override = _mask_mat
			mask_mi.set_meta("keep_on_piece", true)
			part.add_child(mask_mi)
			# Glowing eyes in the mask's sockets; the school's light in them (see _apply_element_eyes).
			for sx in [-1.0, 1.0]:
				var eye := MeshInstance3D.new()
				eye.mesh = YokaiForms.eye_mesh()
				eye.position = Vector3(YokaiForms.EYE_X * sx, YokaiForms.EYE_Y, YokaiForms.EYE_Z)
				eye.material_override = _eyes
				part.add_child(eye)
			# A little larger than the old eye slits: the dark mask around the eyes takes colour from them.
			_eye_glows.append(EyeGlow.attach(part, Vector3(0.0, YokaiForms.EYE_Y, YokaiForms.EYE_Z),
				Color(1.0, 0.24, 0.1), YokaiForms.EYE_X * 2.0, MASK_EYE_GLOW_SIZE))

		"chest":
			# Lacquered crimson wrap over the chest, sode shoulder plates and the glowing curse sigil.
			var wrap := MeshInstance3D.new()
			wrap.mesh = YokaiForms.sash_band("wrap")
			wrap.material_override = _sash
			part.add_child(wrap)

			for sx in [-1.0, 1.0]:
				var sode := MeshInstance3D.new()
				sode.mesh = YokaiForms.ellipsoid(0.055, 0.09, 0.10)
				sode.position = Vector3(0.20 * sx, 0.12, 0.0)
				sode.rotation.z = deg_to_rad(-18.0 * sx)
				sode.material_override = _sash
				part.add_child(sode)

			var sigil := MeshInstance3D.new()
			sigil.mesh = YokaiForms.ellipsoid(0.016, 0.12, 0.006, 8)
			sigil.position = Vector3(0, 0.01, 0.102)
			sigil.material_override = _sigil_mat
			part.add_child(sigil)

		"pelvis":
			var obi := MeshInstance3D.new()
			obi.mesh = YokaiForms.sash_band("obi")
			obi.material_override = _sash
			part.add_child(obi)
			# Torn hakama on the hips: one ragged skirt over the thighs.
			var skirt := MeshInstance3D.new()
			skirt.mesh = YokaiForms.hakama()
			skirt.material_override = _skin
			part.add_child(skirt)

		"arm_l", "arm_r":
			# Three long bone/ember claws extending from the hand (-Y end of the arm capsule).
			for c_idx in [-1, 0, 1]:
				var claw := MeshInstance3D.new()
				claw.mesh = YokaiForms.claw()
				claw.position = Vector3(c_idx * 0.024, -0.32, 0.028)
				claw.rotation.x = deg_to_rad(18.0)
				claw.material_override = _claw_mat
				part.add_child(claw)


func receive_hit(part: RagdollPart, hit: Dictionary) -> Dictionary:
	if is_dead:
		hit["damage"] = 0.0
		hit["hp_left"] = 0.0
		return hit
	var element: String = hit.get("element", "physical")
	last_kill_element = element
	var dmg: float = hit.base_damage * profile.damage_multiplier(hit.zone, element)
	if is_elite() and bool(profile.tactics.get("parry_armor", false)):
		var phys := element == Elements.NONE or element == "physical"
		if phys and not is_staggered() and not hit.get("counter", false):
			dmg *= 0.26
		elif is_staggered():
			dmg *= 1.35
	# Kirisute (D4): a clean cut the blade offered splits the body along its plane.
	# A swarm yōkai dies to it; an elite takes extra damage and splits only when
	# that kills it (a non-lethal elite cut is a wound, see _kirisute_wound).
	var cut := false
	if bool(hit.get("kirisute_offer", false)):
		if is_elite():
			var extra := profile.max_hp * ElementBalance.KIRISUTE_ELITE_FRACTION
			cut = dmg + extra >= hp and KirisuteCut.claim_cut()
			dmg += extra
		elif KirisuteCut.claim_cut():
			cut = true
			dmg = hp
	if not cut and can_sever(part, hit):
		var part_name := String(part.name)
		# A leg or the head off ends it; an arm off takes a big bite of HP.
		dmg = maxf(dmg, hp) if part_name == "head" or part_name.begins_with("leg") else dmg + profile.max_hp * sever_arm_damage
		_sever(part, hit)
		hit["severed"] = part_name
	dmg = snappedf(dmg, 0.1)
	hp = maxf(hp - dmg, 0.0)
	hit["target"] = profile.display_name
	hit["damage"] = dmg
	hit["hp_left"] = hp
	# The counter stage, for the blade's feedback (held_weapon): >1 counter, <1 same school.
	hit["matchup"] = profile.matchup(element)
	_flash_for_matchup(float(hit["matchup"]), element)

	var kb: Vector3 = hit.get("knockback", Vector3.ZERO)
	if kb.length_squared() > 1e-6:
		# Directional reaction: the hit limb (and torso) folds toward where
		# the blade travelled, scaled by the blow's impulse.
		apply_hit_reaction(part, hit.point, kb.normalized(), minf(kb.length(), 28.0))
	var poise := float(hit.impulse) * profile.poise_per_impulse if hit.has("impulse") else dmg * profile.poise_damage_scale
	weaken(dmg * profile.muscle_damage_scale, poise)
	hit["balance_left"] = snappedf(balance, 0.01)
	hit.erase("knockback")
	GameEvents.report_hit(hit)
	if brain:
		brain.on_hit(hit)
	if brain == null or brain.state != YokaiBrain.State.STAGGER:
		_flinch_time = maxf(_flinch_time, clampf(dmg / 40.0, 0.12, 0.28))
	hit_received.emit(hit)
	_flash_time = 0.12

	if hp <= 0.0 and not is_dead:
		die(hit)
	if cut:
		# Only a body the plane really divides comes apart; otherwise it dies as usual.
		hit["kirisute"] = _split_into_pieces(hit)
	elif bool(hit.get("kirisute_offer", false)) and not is_dead:
		_kirisute_wound(hit)
	return hit


## Damage from bounded run abilities (petals, lightning and ink tendrils).
## Kept separate from weapon contacts so it cannot recursively proc on-hit effects.
func is_severed(part_name: String) -> bool:
	return _severed.has(part_name)


## Whether [param hit] on [param part] is strong and clean enough to take the
## limb off: a committed full-arm cut with the edge leading, fast.
func can_sever(part: RagdollPart, hit: Dictionary) -> bool:
	if is_dead or part == null or not SEVERABLE.has(String(part.name)) or _severed.has(String(part.name)):
		return false
	if String(hit.get("strike", "")) != "edge":
		return false
	return float(hit.get("edge_alignment", 0.0)) >= sever_min_alignment \
		and float(hit.get("power", 0.0)) >= sever_min_power \
		and float(hit.get("speed", 0.0)) >= sever_min_speed \
		and float(hit.get("impulse", 0.0)) >= sever_min_impulse


## Take [param part] off: a free copy flies along the cut, the original stays
## jointed in the ragdoll but hidden and touching nothing (see SeveredLimb).
func _sever(part: RagdollPart, hit: Dictionary) -> void:
	var part_name := String(part.name)
	_severed[part_name] = true
	var dir: Vector3 = hit.get("direction", Vector3.ZERO)
	var impulse := float(hit.get("impulse", 0.0))
	var ember := Color(1.7, 0.3, 0.16)
	var scene := _fx_scene()
	if scene:
		SeveredLimb.spawn_from(scene, part, dir, impulse, ember)
		# The wound: a hot spray of spirit embers out of the stump along the
		# cut, and a second, slower puff back toward the body.
		var stump := _joint_point(part_name)
		SparkBurst.spawn(scene, stump, dir if dir.length_squared() > 1e-6 else Vector3.UP, ember, 26, 3.2)
		SparkBurst.spawn(scene, stump, Vector3.UP, Color(0.5, 0.06, 0.05), 12, 1.4)
		Sfx.play_at("yokai_slice", stump, -2.0, 3.0, 0.85)
	part.visible = false
	part.collision_layer = 0
	part.collision_mask = 0
	GameEvents.log_event("enemy_dismembered", {"enemy": profile.display_name, "part": part_name})


## Where this yōkai's effects (sparks, fireworks, petals, pieces) go: the scene it is in.
## A yōkai inside a SubViewport of its own (the opening strike, D11) keeps them in that
## viewport's world; in the run they go to the current scene, as before.
func _fx_scene() -> Node:
	if not is_inside_tree():
		return null
	var n := get_parent()
	while n != null and not (n is SubViewport):
		n = n.get_parent()
	return n if n != null else get_tree().current_scene


## Kirisute (D4): the body is already dead; it comes apart along the blade's plane
## where it was cut. Returns false when the plane misses it (no split, plain death).
func _split_into_pieces(hit: Dictionary) -> bool:
	var scene := _fx_scene()
	if scene == null:
		return false
	var point: Vector3 = hit.get("point", global_position)
	var motion: Vector3 = hit.get("direction", Vector3.ZERO)
	var element: String = hit.get("element", Elements.NONE)
	var normal := KirisuteCut.plane_normal(motion, hit.get("blade_axis", Vector3.UP))
	var pieces := KirisuteCut.split(self, parts, scene, point, normal, motion, element)
	if pieces.size() < 2:
		return false
	for p: RagdollPart in parts.values():
		p.visible = false
		p.collision_layer = 0
		p.collision_mask = 0
	visible = false
	_petal_burst_done = true
	SparkBurst.spawn(scene, point, normal, KirisuteCut.glow_color(element), 22, 3.0)
	Sfx.play_at("yokai_slice", point, -1.0, 3.0, 0.9)
	GameEvents.log_event("enemy_split", {"enemy": profile.display_name, "element": element, "pieces": pieces.size()})
	# The body goes back to its pool once this hit has finished unwinding.
	_finish_split.call_deferred()
	return true


func _finish_split() -> void:
	dissolve_finished.emit(self)


## Kirisute (D4): an elite cut that does not kill leaves a glowing wound in the
## school's colour, a spray of sparks along the blade and a sharp sound.
func _kirisute_wound(hit: Dictionary) -> void:
	var scene := _fx_scene()
	if scene == null:
		return
	KirisuteCut.wound(scene, hit.get("point", global_position), hit.get("direction", Vector3.UP),
		hit.get("element", Elements.NONE))


## World position of the joint that holds [param part_name] to its parent,
## carried by the parent part (the Joint nodes stay where the body was built,
## and the body walks away from its node).
func _joint_point(part_name: String) -> Vector3:
	var def: Dictionary = _defs.get(part_name, {})
	var parent_part := parts.get(String(def.get("parent", ""))) as RagdollPart
	if parent_part == null or not def.has("joint"):
		return (parts[part_name] as RagdollPart).global_position
	var parent_rest: Transform3D = _rest[parent_part.name]
	return parent_part.global_transform * (parent_rest.affine_inverse() * (def.joint as Vector3))


func receive_element_damage(amount: float, element: String, point: Vector3, direction: Vector3) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	last_kill_element = element
	var damage := snappedf(amount * profile.damage_multiplier("torso", element), 0.1)
	_flash_for_matchup(profile.matchup(element), element)
	hp = maxf(hp - damage, 0.0)
	var chest := parts.get("chest") as RagdollPart
	if chest and direction.length_squared() > 1e-6:
		apply_hit_reaction(chest, point, direction.normalized(), minf(damage * 0.045, 1.8))
	weaken(damage * profile.muscle_damage_scale * 0.45, damage * profile.poise_damage_scale * 0.35)
	var hit := {
		"attacker": "element_ability",
		"element": element,
		"target": profile.display_name,
		"part": "chest",
		"zone": "torso",
		"damage": damage,
		"point": point,
		"direction": direction,
		"hp_left": hp,
	}
	GameEvents.log_event("element_hit", hit)
	_flash_time = 0.10
	if brain:
		brain.on_hit(hit)
	if hp <= 0.0:
		die(hit)
	return damage


func apply_slow(duration: float, scale: float) -> void:
	_slow_time = maxf(_slow_time, duration)
	_slow_scale = minf(_slow_scale, clampf(scale, 0.25, 1.0))


func apply_confusion(duration: float) -> void:
	_confusion_time = maxf(_confusion_time, duration)


func is_slowed() -> bool:
	return _slow_time > 0.0


func is_confused() -> bool:
	return _confusion_time > 0.0


func die(hit: Dictionary = {}) -> void:
	if is_dead:
		return
	is_dead = true
	weaken(1.0, 1.0)
	move_velocity = Vector3.ZERO
	_flash_time = 0.10
	var chest_pos := (parts["chest"] as RagdollPart).global_position if parts.has("chest") else global_position + Vector3(0, 1.1, 0)
	# Stop corpses from blocking the player or other yōkai while they collapse and dissolve.
	for p: RagdollPart in parts.values():
		p.collision_layer = 0
		p.collision_mask = 1
	var col := Elements.color(last_kill_element) if last_kill_element != Elements.NONE else Color(1.8, 0.35, 0.22)
	if last_kill_element == Elements.INK:
		col = Color(0.55, 0.68, 1.2)
	var fx := _fx_scene()
	if fx:
		Sfx.play_at("yokai_slice", chest_pos, -5.0, 3.5, 1.05)
		ElementFirework.spawn(fx, chest_pos, last_kill_element, 1.0 if kind == Kind.SWARM else 1.18)
	GameEvents.log_event("enemy_defeated", {
		"enemy": profile.display_name,
		"element": last_kill_element,
		"position": chest_pos,
	})
	died.emit(self, hit)


## Down: the pelvis is near the ground, or the body has stopped falling.
func _body_landed() -> bool:
	var pelvis := root_part()
	if pelvis == null:
		return true
	if ground_probe.is_valid():
		var gy := float(ground_probe.call(pelvis.global_position.x, pelvis.global_position.z))
		if pelvis.global_position.y - gy < 0.32:
			return true
	return _dissolve_timer >= 0.5 and pelvis.linear_velocity.length() < 0.5


func _burst_into_petals() -> void:
	_petal_burst_done = true
	var scene := _fx_scene()
	if scene:
		var push := root_part().linear_velocity if root_part() else Vector3.ZERO
		var tint := Elements.color(last_kill_element) if last_kill_element != Elements.NONE and last_kill_element != "physical" else Color.WHITE
		SakuraScatter.burst_from(self, scene, DEATH_PETALS, push, tint)
	visible = false
	dissolve_finished.emit(self)


func _balance_regen() -> float: return 0.0 if is_dead else profile.balance_regen
func _muscle_regen() -> float: return 0.0 if is_dead else profile.muscle_regen
func _knockdown_time() -> float: return 999.0 if is_dead else profile.knockdown_time
func _getup_time() -> float: return profile.getup_time


func _physics_process(delta: float) -> void:
	if is_dead:
		balance = 0.0
		muscle = 0.0
		move_velocity = Vector3.ZERO
		_dissolve_timer += delta
		if _petal_burst_done:
			return
		var t := clampf(_dissolve_timer / _dissolve_duration, 0.0, 1.0)
		var brief_flash := maxf(0.0, (0.12 - _dissolve_timer) / 0.12) * 0.45
		_skin.set_shader_parameter("flash", brief_flash)
		_mask_mat.set_shader_parameter("flash", brief_flash * 0.5)
		_eyes.emission_energy_multiplier = maxf(0.0, (1.0 - t * 2.0) * 0.85)
		EyeGlow.set_glow(_eye_glows, maxf(0.0, 1.0 - t * 2.5))
		_sigil_mat.emission_energy_multiplier = maxf(0.0, (1.0 - t * 2.0) * 0.55)
		# The body falls limp; once it is down (or after the longest fall)
		# it comes apart into sakura petals that the wind carries off.
		if _dissolve_timer >= _dissolve_duration or (_dissolve_timer >= 0.3 and _body_landed()):
			_burst_into_petals()
		return

	# Safety net: whatever happened (a launch, a knockdown through a gap in
	# the height spring), a living yōkai never stays under the terrain. One
	# that sank read as dying before it ever reached the player.
	if ground_probe.is_valid() and not parts.is_empty():
		var rp := root_part().global_position
		var gy := float(ground_probe.call(rp.x, rp.z))
		if rp.y < gy - 1.2:
			place_at(Vector3(rp.x, gy, rp.z), _facing_yaw)
	_slow_time = maxf(0.0, _slow_time - delta)
	if _slow_time <= 0.0:
		_slow_scale = 1.0
	_confusion_time = maxf(0.0, _confusion_time - delta)
	_lod_tick += 1
	var think_delta := delta if not _lod_far or _lod_tick % 2 == 0 else delta * 0.5
	_flinch_time = maxf(0.0, _flinch_time - delta)
	var intent := brain.think(think_delta, _perceive())
	var move: Vector3 = intent.get("move", Vector3.ZERO)
	if use_pathfinding and _nav_agent and move.length_squared() > 0.01 and state == State.STANDING:
		move = _steer_along_navmesh(move)
	var pose_name := String(intent.get("pose", "stalk"))
	if _flinch_time > 0.0 and brain.state != YokaiBrain.State.STAGGER:
		pose_name = "flinch"
	set_pose(pose_name)
	var attacking: bool = intent.get("attacking", false) and state == State.STANDING
	if attacking and not _was_attacking:
		_hit_player_this_strike = false
	_was_attacking = attacking
	if attacking:
		_try_claw_player(float(intent.get("damage", 12.0)), String(intent.get("attack", "right")))
	if intent.has("face_position") and state == State.STANDING:
		face_toward(intent.face_position)
	_apply_move(move, delta, intent.get("plant", false))
	_show_tell(float(intent.get("tell", 0.0)))
	super._physics_process(delta)
	# No ground under the feet to lean on, so a standing pelvis is kept
	# upright by bleeding off its pitch/roll spin; the balance drive does
	# the actual uprighting. (Teleporting the pelvis basis upright every
	# tick, as before, rotated the body into whatever it overlapped and
	# the solver popped it back out — a steady source of launches.)
	if state == State.STANDING and not is_dead:
		var pelvis := root_part()
		var spin := pelvis.angular_velocity
		pelvis.angular_velocity = Vector3(spin.x * 0.6, spin.y, spin.z * 0.6)
	_apply_secondary_motion_overlay()


## Bends [param move] around navmesh obstacles. The path is queried from the
## pelvis, not from this node: the ragdoll walks away from the Yokai root, so a
## NavigationAgent3D (which paths from its parent) kept steering the body back
## toward its spawn point.
func _steer_along_navmesh(move: Vector3) -> Vector3:
	var flat := Vector3(move.x, 0.0, move.z)
	var map := _nav_agent.get_navigation_map()
	if flat.length_squared() < 1e-4 or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return move
	_nav_repath -= 1
	var root_pos := root_part().global_position
	if _nav_repath <= 0:
		_nav_repath = 6
		_nav_dir = Vector3.ZERO
		var path := NavigationServer3D.map_get_path(map, root_pos, root_pos + flat.normalized() * 4.0, true)
		# Off the baked navmesh (deep in the forest) the path starts at the
		# nearest mesh point, which says nothing about the way ahead.
		if path.is_empty() or Vector2(path[0].x - root_pos.x, path[0].z - root_pos.z).length() > 1.0:
			path = PackedVector3Array()
		for point in path:
			var steer := point - root_pos
			steer.y = 0.0
			if steer.length_squared() > 0.09:
				_nav_dir = steer.normalized()
				break
	# A path that turns more than ~80° from where the brain wants to go is a
	# navmesh artefact, not a detour; trust the brain.
	if _nav_dir == Vector3.ZERO or _nav_dir.dot(flat.normalized()) < 0.17:
		return move
	return _nav_dir * move.length()


func _apply_secondary_motion_overlay() -> void:
	if is_dead or brain == null:
		return
	if brain.state == YokaiBrain.State.RECOVER:
		overlay_pose = "recover"
		return
	if _stepping:
		return
	if not parts.has("head") or not parts.has("chest"):
		return
	var head_p: RagdollPart = parts["head"]
	var chest_p: RagdollPart = parts["chest"]
	var head_fwd := -head_p.global_transform.basis.z
	var chest_fwd := -chest_p.global_transform.basis.z
	head_fwd.y = 0.0
	chest_fwd.y = 0.0
	if head_fwd.length_squared() < 0.01 or chest_fwd.length_squared() < 0.01:
		return
	head_fwd = head_fwd.normalized()
	chest_fwd = chest_fwd.normalized()
	var yaw_lag := chest_fwd.signed_angle_to(head_fwd, Vector3.UP)
	var pitch_lag := (head_p.rotation.x - chest_p.rotation.x) * 0.32
	_torso_lag_pitch = lerpf(_torso_lag_pitch, pitch_lag, 0.18)
	var chest_deg := Vector3(
		rad_to_deg(_torso_lag_pitch) + rad_to_deg(yaw_lag) * 0.12,
		rad_to_deg(yaw_lag) * 0.08,
		0.0)
	if chest_deg.length() < 1.5:
		if overlay_pose == "torso_lag":
			overlay_pose = ""
		return
	_poses["torso_lag"] = {"chest": chest_deg}
	overlay_pose = "torso_lag"


func _perceive() -> Dictionary:
	var pelvis := root_part()
	var self_pos := pelvis.global_position
	var ctx := {
		"self_position": self_pos,
		"self_forward": Vector3(sin(_facing_yaw), 0.0, cos(_facing_yaw)),
		"can_act": state == State.STANDING and not is_dead,
		"move_blocked": _move_blocked,
	}
	var decoy := get_tree().get_first_node_in_group("shadow_decoy") as Node3D if get_tree() else null
	if decoy and is_instance_valid(decoy) and self_pos.distance_to(decoy.global_position) <= 9.0:
		ctx["player_position"] = decoy.global_position
		ctx["player_forward"] = -decoy.global_basis.z
	else:
		var head := get_tree().get_first_node_in_group("player_head") as Node3D if get_tree() else null
		if head:
			ctx["player_position"] = head.global_position
			ctx["player_forward"] = -head.global_basis.z
			if _confusion_time > 0.0:
				var real_to_player := head.global_position - self_pos
				var false_angle := sin(_confusion_time * 4.2 + float(get_instance_id() % 17)) * 1.25
				ctx["player_position"] = self_pos + real_to_player.rotated(Vector3.UP, false_angle)
				ctx["player_forward"] = (-head.global_basis.z).rotated(Vector3.UP, -false_angle * 0.6)
	var health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	ctx["player_alive"] = health == null or health.is_alive()

	# Swarm separation so multiple yōkai spread out around the player.
	var sep := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("yokai"):
		if node == self or not (node is Yokai):
			continue
		var other := node as Yokai
		if other.is_dead:
			continue
		var diff := self_pos - other.root_part().global_position
		diff.y = 0.0
		var d := diff.length()
		if d > 0.001 and d < 1.15:
			sep += (diff / d) * ((1.15 - d) / 1.15)
	var forest := get_tree().get_first_node_in_group("forest_world") as ForestWorld
	if forest and ctx.has("player_position"):
		sep += forest.trunk_push(self_pos, (ctx.player_position as Vector3) - self_pos)
	ctx["separation"] = sep.limit_length(1.5)
	return ctx


func _apply_move(move: Vector3, delta: float, planted := false) -> void:
	move.y = 0.0
	move *= _slow_scale
	if state != State.STANDING or is_dead:
		move_velocity = Vector3.ZERO
		overlay_pose = ""
		_move_blocked = false
		burst = false
		return
	if move.length() < 0.02:
		move = Vector3.ZERO
		_move_blocked = false
	else:
		_move_blocked = _blocked_toward(move.normalized())
	_detour_time = maxf(_detour_time - delta, 0.0)
	if _move_blocked and move.length_squared() > 0.01:
		# Walk around a trunk: widen the angle until clear, preferring the side
		# chosen last time so the yōkai does not dither in front of it.
		var forward := move.normalized()
		var sides: Array[float] = [_detour_side, -_detour_side]
		for angle in [0.6, 1.05, 1.57]:
			for flip in sides:
				var detour := forward.rotated(Vector3.UP, angle * flip)
				if not _blocked_toward(detour):
					move = detour * move.length()
					_move_blocked = false
					_detour_side = flip
					_detour_time = 0.8
					break
			if not _move_blocked:
				break
	if _move_blocked:
		move_velocity = Vector3.ZERO
	else:
		move_velocity = move_velocity.move_toward(move, (BURST_ACCEL if planted else MOVE_ACCEL) * delta)
	burst = planted and move_velocity.length() > 0.5
	var v := move_velocity.length()
	_stepping = not planted and (v > 0.2 or (_stepping and v > 0.08))
	if _stepping:
		var cadence := clampf(0.14 / maxf(v, 0.01), 0.22, 0.42)
		_step_time += delta * 0.32 / cadence
		overlay_pose = "step_l" if fmod(_step_time, cadence * 2.0) < cadence else "step_r"
	else:
		overlay_pose = ""


func _blocked_toward(dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := root_part().global_position
	var own: Array[RID] = []
	for p: RagdollPart in parts.values():
		own.append(p.get_rid())
	for h in [-0.5, -0.1]:
		var a := Vector3(from.x, from.y + h, from.z)
		var q := PhysicsRayQueryParameters3D.create(a, a + dir * 0.45, 1, own)
		var hit := space.intersect_ray(q)
		# A rising hillside is ground to walk up, not a wall (trunks are).
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.55:
			return true
	return false


func _try_claw_player(damage: float, attack: String) -> void:
	if _hit_player_this_strike or is_dead:
		return
	var decoy := get_tree().get_first_node_in_group("shadow_decoy") as Node3D if get_tree() else null
	if decoy and is_instance_valid(decoy):
		var decoy_pos := decoy.global_position
		if root_part().global_position.distance_to(decoy_pos) < 1.6:
			_hit_player_this_strike = true
			get_tree().call_group("element_system", "on_decoy_struck")
			return
	var health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health == null or not health.is_alive():
		return
	var body := health.hurt_capsule()  # [top, bottom, radius]
	var arms: Array[String] = []
	match attack:
		"left": arms = ["arm_l"]
		"right": arms = ["arm_r"]
		_: arms = ["arm_l", "arm_r"]
	for arm_name in arms:
		var arm: RagdollPart = parts.get(arm_name)
		if arm == null or _severed.has(arm_name):
			continue
		var shoulder := arm.global_transform * Vector3(0, 0.22, 0)
		var claw_tip := arm.global_transform * Vector3(0, -0.36, 0.05)
		var pts := Geometry3D.get_closest_points_between_segments(shoulder, claw_tip, body[0], body[1])
		if pts[0].distance_to(pts[1]) <= float(body[2]) + 0.14:
			_hit_player_this_strike = true
			health.take_hit(damage, pts[0], {"attacker": profile.display_name, "attack": attack})
			return


func _show_tell(tell: float) -> void:
	# The wind-up reads from the pose and the sound; the glow only warms
	# slightly. The old multipliers blew the eyes/claws out to white-hot
	# signal lights, which read as UI markers instead of a creature.
	var lift := ELITE_LIFT if kind == Kind.ELITE else 1.0
	_eyes.emission_energy_multiplier = (0.85 + tell * tell * 1.6) * lift
	EyeGlow.set_glow(_eye_glows, 1.0 + tell * tell * 0.7)
	_claw_mat.emission_energy_multiplier = (0.32 + tell * tell * 1.4) * lift
	_sigil_mat.emission_energy_multiplier = (0.55 + tell * tell * 1.0) * lift
	if tell > 0.05 and _last_tell <= 0.05:
		var head_part: RagdollPart = parts.get("head")
		Sfx.play_at("enemy_tell", head_part.global_position if head_part else global_position, -5.0)
	_last_tell = tell


func _process(delta: float) -> void:
	if _flash_time > 0.0 and not is_dead:
		_flash_time -= delta
		var f := clampf(_flash_time / 0.12, 0.0, 1.0) * 0.55
		_skin.set_shader_parameter("flash", f)
		_mask_mat.set_shader_parameter("flash", f * 0.3)
