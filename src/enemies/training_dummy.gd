class_name TrainingDummy
extends ActiveRagdoll
## Wooden training dummy: an active ragdoll that staggers, falls and gets up,
## holding a physics bokken in its right hand. Its [DuelistBrain] spars with
## the player when attacks are on (P / B / Y): it stalks, circles, blocks and
## attacks with telegraphed cuts and thrusts that hurt the player
## ([PlayerHealth]); parrying them staggers it.
##
## It never dies for good: at 0 HP it collapses, then gets up with full HP.

signal hit_received(hit: Dictionary)

const DUMMY_SWORD := preload("res://scenes/weapons/dummy_sword.tscn")
const WET_SURFACE_SHADER := preload("res://src/shaders/wet_surface.gdshader")

## How fast the walking speed may change (m/s²): the body leans into a step
## and carries its weight out of it instead of starting and stopping dead.
const MOVE_ACCEL := 4.0
## Acceleration (m/s²) of a planted burst: the strike's step in, an evade.
const BURST_ACCEL := 25.0

@export var profile: EnemyProfile
@export var hold_sword := true

var hp := 100.0
var brain: EnemyBrain
var sword: BladeBody
## Procedural sword arm: the brain asks for a blade line ("guard_line" intent)
## and the arm reaches for it continuously instead of jumping between poses.
var arm_ik: SwordArmIK
## IK iterations per physics tick.
var ik_iterations := 2
## [start, dir] (world) that overrides the brain's blade line (tests, debug).
var forced_blade_line: Array = []

## Spot the dummy returns to when not sparring, and how far it may roam from it.
var home_position := Vector3.ZERO

var _straw := ShaderMaterial.new()  # weathered wood (wet_surface shader)
var _sash := StandardMaterial3D.new()
var _ink := StandardMaterial3D.new()
var _eyes := StandardMaterial3D.new()  # glow up during a wind-up (the tell)
var _prev_tips := {}  # player weapon -> tip position last tick
var _move_blocked := false
var _step_time := 0.0
var _was_attacking := false
var _hit_player_this_strike := false
var _last_tell := 0.0
var _flash_time := 0.0
var _revive_on_getup := false
var _counter_time := 0.0  # > 0 while open to a counter after being parried


func _ready() -> void:
	if profile == null:
		profile = EnemyProfile.new()
	hp = profile.max_hp
	_straw.shader = WET_SURFACE_SHADER
	# Weathered, oiled wood: matte with a soft sheen only where rain runs.
	_straw.set_shader_parameter("base_color", Color(0.3, 0.19, 0.12))
	_straw.set_shader_parameter("roughness_dry", 0.7)
	_straw.set_shader_parameter("roughness_wet", 0.38)
	_straw.set_shader_parameter("wetness", 0.45)
	_straw.set_shader_parameter("waterline_y", -10.0)
	_straw.set_shader_parameter("grain_amount", 0.6)
	_straw.set_shader_parameter("grain_scale", 40.0)
	_straw.set_shader_parameter("fill", 1.6)
	_sash.albedo_color = Color(0.3, 0.02, 0.035)
	_sash.roughness = 0.85
	_ink.albedo_color = Color(0.015, 0.015, 0.02)
	_ink.roughness = 0.6
	_eyes.albedo_color = Color(0.02, 0.01, 0.01)
	_eyes.emission_enabled = true
	_eyes.emission = Color(1.0, 0.16, 0.08)
	_eyes.emission_energy_multiplier = 0.0
	# No two moves exactly alike, and a guard that breathes.
	pose_variation_deg = 5.0
	idle_sway_deg = 3.0
	super._ready()
	home_position = global_position
	for child in get_children():
		if child is EnemyBrain:
			brain = child
	if brain == null:
		brain = DuelistBrain.new()
		brain.name = "Brain"
		add_child(brain)
	brain.setup(self, profile)
	if hold_sword:
		equip_sword()
	arm_ik = SwordArmIK.new()
	arm_ik.setup(self, _rest_grip(), sword, _define_poses()["guard"])
	state_changed.connect(_on_state_changed)


# --- Body ---------------------------------------------------------------------

func _define_parts() -> Dictionary:
	var d := {
		"pelvis": {"shape": "box", "size": Vector3(0.30, 0.18, 0.18), "pos": Vector3(0, 0.98, 0), "mass": 10.0, "zone": "torso"},
		"chest": {"shape": "box", "size": Vector3(0.36, 0.44, 0.21), "pos": Vector3(0, 1.31, 0), "mass": 14.0, "zone": "torso",
			"parent": "pelvis", "joint": Vector3(0, 1.08, 0), "max_torque": 600.0,
			"limits": {"x": Vector2(-25, 45), "y": Vector2(-35, 35), "z": Vector2(-25, 25)}},
		"head": {"shape": "sphere", "radius": 0.115, "pos": Vector3(0, 1.67, 0), "mass": 4.0, "zone": "head",
			"parent": "chest", "joint": Vector3(0, 1.54, 0), "max_torque": 100.0,
			"limits": {"x": Vector2(-40, 40), "y": Vector2(-60, 60), "z": Vector2(-30, 30)}},
	}
	# Left side is +X (the dummy faces +Z). Right side mirrors y/z limits.
	for side in ["l", "r"]:
		var s := 1.0 if side == "l" else -1.0
		d["upper_arm_" + side] = {"shape": "capsule", "radius": 0.05, "height": 0.32, "pos": Vector3(0.25 * s, 1.33, 0),
			"mass": 2.2, "zone": "limb", "parent": "chest", "joint": Vector3(0.25 * s, 1.49, 0), "max_torque": 250.0,
			"limits": {"x": Vector2(-150, 60), "y": Vector2(-70, 70), "z": _mirror(Vector2(-20, 110), s)}}
		d["lower_arm_" + side] = {"shape": "capsule", "radius": 0.045, "height": 0.30, "pos": Vector3(0.25 * s, 1.03, 0),
			"mass": 1.4, "zone": "limb", "parent": "upper_arm_" + side, "joint": Vector3(0.25 * s, 1.18, 0), "max_torque": 150.0,
			"limits": {"x": Vector2(-150, 5), "y": Vector2(-60, 60), "z": Vector2(-5, 5)}}
		d["upper_leg_" + side] = {"shape": "capsule", "radius": 0.07, "height": 0.44, "pos": Vector3(0.1 * s, 0.69, 0),
			"mass": 7.0, "zone": "limb", "parent": "pelvis", "joint": Vector3(0.1 * s, 0.90, 0), "max_torque": 500.0,
			"limits": {"x": Vector2(-100, 35), "y": Vector2(-35, 35), "z": _mirror(Vector2(-15, 55), s)}}
		d["lower_leg_" + side] = {"shape": "capsule", "radius": 0.055, "height": 0.44, "pos": Vector3(0.1 * s, 0.27, 0),
			"mass": 4.5, "zone": "limb", "parent": "upper_leg_" + side, "joint": Vector3(0.1 * s, 0.48, 0), "max_torque": 400.0,
			"limits": {"x": Vector2(-3, 140), "y": Vector2(-3, 3), "z": Vector2(-3, 3)},
			# Feet slide over the stone (suri-ashi) instead of sticking and skipping.
			"friction": 0.25,
			"extra_shapes": [{"shape": "box", "size": Vector3(0.10, 0.06, 0.24), "offset": Vector3(0, -0.24, 0.05)}]}
	return d


## Mirror a z-axis range for the right side.
static func _mirror(range_deg: Vector2, s: float) -> Vector2:
	return range_deg if s > 0.0 else Vector2(-range_deg.y, -range_deg.x)


func _define_poses() -> Dictionary:
	return {
		# Chūdan-ish guard: sword in the right hand, held forward and up.
		"guard": {
			"_blend": 0.45,
			"chest": Vector3(8, 0, 0),
			"head": Vector3(-6, 0, 0),
			"upper_arm_r": Vector3(-40, 0, 15),
			"lower_arm_r": Vector3(-55, 0, 0),
			"upper_arm_l": Vector3(-40, 0, -25),
			"lower_arm_l": Vector3(-60, 0, 0),
			"upper_leg_l": Vector3(-10, 0, 6),
			"lower_leg_l": Vector3(14, 0, 0),
			"upper_leg_r": Vector3(6, 0, -6),
			"lower_leg_r": Vector3(8, 0, 0),
		},
		# Overhead cut, telegraphed: sword raised behind the head...
		"windup": {
			"_stiffness": 1.3,
			"_blend": 0.4,
			"chest": Vector3(-8, 0, 0),
			"head": Vector3(-5, 0, 0),
			"upper_arm_r": Vector3(-150, 0, 10),
			"lower_arm_r": Vector3(-30, 0, 0),
			"upper_arm_l": Vector3(-140, 0, -20),
			"lower_arm_l": Vector3(-40, 0, 0),
			"upper_leg_l": Vector3(-10, 0, 6),
			"lower_leg_l": Vector3(14, 0, 0),
			"upper_leg_r": Vector3(6, 0, -6),
			"lower_leg_r": Vector3(8, 0, 0),
		},
		# ...then brought down and forward fast.
		"strike": {
			"_stiffness": 1.5,
			"_max_speed": 6.0,
			"_blend": 0.14,
			"_ease": "in",
			"chest": Vector3(22, 0, 0),
			"head": Vector3(-12, 0, 0),
			"upper_arm_r": Vector3(-45, 0, 12),
			"lower_arm_r": Vector3(-5, 0, 0),
			"upper_arm_l": Vector3(-50, 0, -25),
			"lower_arm_l": Vector3(-20, 0, 0),
			"upper_leg_l": Vector3(-25, 0, 6),
			"lower_leg_l": Vector3(25, 0, 0),
			"upper_leg_r": Vector3(15, 0, -6),
			"lower_leg_r": Vector3(10, 0, 0),
		},
		# Horizontal cut, right to left: sword drawn back past the right shoulder...
		"windup_h": {
			"_stiffness": 1.3,
			"_blend": 0.4,
			"chest": Vector3(4, -14, 0),
			"head": Vector3(-6, 20, 0),
			"upper_arm_r": Vector3(-67, -61, -39),
			"lower_arm_r": Vector3(-35, 50, 0),
			"upper_arm_l": Vector3(-60, -20, -20),
			"lower_arm_l": Vector3(-70, 0, 0),
			"upper_leg_l": Vector3(-12, 0, 8),
			"lower_leg_l": Vector3(16, 0, 0),
			"upper_leg_r": Vector3(10, 0, -8),
			"lower_leg_r": Vector3(10, 0, 0),
		},
		# ...then swept across at chest height.
		"strike_h": {
			"_stiffness": 1.5,
			"_max_speed": 6.0,
			"_blend": 0.14,
			"_ease": "in",
			"chest": Vector3(10, 13, 0),
			"head": Vector3(-8, -20, 0),
			"upper_arm_r": Vector3(-85, 30, -34),
			"lower_arm_r": Vector3(-10, 74, 0),
			"upper_arm_l": Vector3(-40, 30, -30),
			"lower_arm_l": Vector3(-40, 0, 0),
			"upper_leg_l": Vector3(-22, 0, 8),
			"lower_leg_l": Vector3(22, 0, 0),
			"upper_leg_r": Vector3(14, 0, -8),
			"lower_leg_r": Vector3(10, 0, 0),
		},
		# Thrust: fist pulled back to the hip, point aimed at the player...
		"windup_t": {
			"_stiffness": 1.3,
			"_blend": 0.4,
			"chest": Vector3(-22, -1, 0),
			"head": Vector3(-6, 18, 0),
			"upper_arm_r": Vector3(49, -1, -38),
			"lower_arm_r": Vector3(-99, -12, 0),
			"upper_arm_l": Vector3(-50, 20, -30),
			"lower_arm_l": Vector3(-60, 0, 0),
			"upper_leg_l": Vector3(-20, 0, 8),
			"lower_leg_l": Vector3(20, 0, 0),
			"upper_leg_r": Vector3(18, 0, -8),
			"lower_leg_r": Vector3(12, 0, 0),
		},
		# ...then driven straight forward with a lunge.
		"strike_t": {
			"_stiffness": 1.6,
			"_max_speed": 8.0,
			"_blend": 0.12,
			"_ease": "in",
			"chest": Vector3(18, 8, 0),
			"head": Vector3(-14, -6, 0),
			"upper_arm_r": Vector3(-74, 0, 8),
			"lower_arm_r": Vector3(-5, -12, 0),
			"upper_arm_l": Vector3(-20, 0, -15),
			"lower_arm_l": Vector3(-30, 0, 0),
			"upper_leg_l": Vector3(-35, 0, 8),
			"lower_leg_l": Vector3(30, 0, 0),
			"upper_leg_r": Vector3(25, 0, -8),
			"lower_leg_r": Vector3(8, 0, 0),
		},
		# Blocks (solved with tests/diag/diag_block_ik.tscn): the bokken held in
		# front of the body across the line of the player's cut, left hand on
		# the handle, leaning in from the waist. High = across above the head;
		# left / right = rising diagonally on that side; mid = diagonal across
		# the chest (thrusts, centre cuts). Together they cover chest to head.
		"block_high": {
			"_stiffness": 1.8,
			"_blend": 0.08,
			"_ease": "out",
			"chest": Vector3(8, 2, 0),
			"head": Vector3(-4, -1, 0),
			"upper_arm_r": Vector3(-10, 22, -104),
			"lower_arm_r": Vector3(-99, -39, 0),
			"upper_arm_l": Vector3(-110, -52, -17),
			"lower_arm_l": Vector3(-1, -57, 0),
		},
		"block_left": {
			"_stiffness": 1.8,
			"_blend": 0.08,
			"_ease": "out",
			"chest": Vector3(24, 1, 0),
			"head": Vector3(-4, -1, 0),
			"upper_arm_r": Vector3(-13, 57, -25),
			"lower_arm_r": Vector3(-90, -5, 0),
			"upper_arm_l": Vector3(-40, -65, 45),
			"lower_arm_l": Vector3(-65, -57, 0),
		},
		"block_right": {
			"_stiffness": 1.8,
			"_blend": 0.08,
			"_ease": "out",
			"chest": Vector3(24, 16, 0),
			"head": Vector3(-4, -11, 0),
			"upper_arm_r": Vector3(-26, 20, 17),
			"lower_arm_r": Vector3(-112, -57, 0),
			"upper_arm_l": Vector3(-60, -67, 5),
			"lower_arm_l": Vector3(-17, 6, 0),
		},
		"block_mid": {
			"_stiffness": 1.8,
			"_blend": 0.08,
			"_ease": "out",
			"chest": Vector3(24, -10, 0),
			"head": Vector3(-4, 7, 0),
			"upper_arm_r": Vector3(-6, 39, -47),
			"lower_arm_r": Vector3(-100, 7, 0),
			"upper_arm_l": Vector3(-68, -67, 12),
			"lower_arm_l": Vector3(-4, -15, 0),
		},
		# Leg overlays while walking (arms keep the main pose): low sliding
		# steps (suri-ashi), the feet barely leave the floor.
		"step_l": {
			"upper_leg_l": Vector3(-20, 0, 6),
			"lower_leg_l": Vector3(26, 0, 0),
			"upper_leg_r": Vector3(6, 0, -6),
			"lower_leg_r": Vector3(8, 0, 0),
		},
		"step_r": {
			"upper_leg_l": Vector3(6, 0, 6),
			"lower_leg_l": Vector3(8, 0, 0),
			"upper_leg_r": Vector3(-20, 0, -6),
			"lower_leg_r": Vector3(26, 0, 0),
		},
		# Thrown off balance after a parry: arms flung up and back.
		"staggered": {
			"_stiffness": 0.7,
			"_blend": 0.18,
			"_ease": "out",
			"chest": Vector3(-15, 0, 0),
			"head": Vector3(-15, 0, 0),
			"upper_arm_r": Vector3(-120, 0, -30),
			"lower_arm_r": Vector3(-20, 0, 0),
			"upper_arm_l": Vector3(-30, 0, 40),
			"lower_arm_l": Vector3(-30, 0, 0),
			"upper_leg_l": Vector3(-5, 0, 8),
			"lower_leg_l": Vector3(10, 0, 0),
			"upper_leg_r": Vector3(10, 0, -8),
			"lower_leg_r": Vector3(10, 0, 0),
		},
		# Follow-through after a strike: the blade carried low, weight still
		# forward, muscles loose; the brain then eases back into the guard.
		"recover": {
			"_stiffness": 0.85,
			"_blend": 0.2,
			"_ease": "out",
			"chest": Vector3(16, 0, 0),
			"head": Vector3(-10, 0, 0),
			"upper_arm_r": Vector3(-25, 0, 14),
			"lower_arm_r": Vector3(-25, 0, 0),
			"upper_arm_l": Vector3(-30, 0, -22),
			"lower_arm_l": Vector3(-35, 0, 0),
			"upper_leg_l": Vector3(-20, 0, 6),
			"lower_leg_l": Vector3(22, 0, 0),
			"upper_leg_r": Vector3(12, 0, -6),
			"lower_leg_r": Vector3(10, 0, 0),
		},
		"idle": {"_blend": 0.6},
	}


func _decorate_part(part_name: String, part: RagdollPart, def: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	match def.shape:
		"box":
			var m := BoxMesh.new()
			m.size = def.size
			mi.mesh = m
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = def.radius
			m.height = def.height
			m.radial_segments = 12
			m.rings = 3
			mi.mesh = m
		"sphere":
			var m := SphereMesh.new()
			m.radius = def.radius
			m.height = def.radius * 2.0
			m.radial_segments = 16
			m.rings = 8
			mi.mesh = m
	mi.material_override = _straw
	part.add_child(mi)
	for extra in def.get("extra_shapes", []):
		var em := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = extra.size
		em.mesh = bm
		em.position = extra.offset
		em.material_override = _ink
		part.add_child(em)

	match part_name:
		"head":
			# Red hachimaki band and two ink eyes on the +Z (front) side.
			var band := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.11
			torus.outer_radius = 0.13
			band.mesh = torus
			band.position = Vector3(0, 0.03, 0)
			band.material_override = _sash
			part.add_child(band)
			for ex in [-0.04, 0.04]:
				var eye := MeshInstance3D.new()
				var eb := BoxMesh.new()
				eb.size = Vector3(0.035, 0.012, 0.01)
				eye.mesh = eb
				eye.position = Vector3(ex, 0.0, 0.11)
				eye.material_override = _eyes
				part.add_child(eye)
		"pelvis":
			var obi := MeshInstance3D.new()
			var ob := BoxMesh.new()
			ob.size = Vector3(0.32, 0.06, 0.20)
			obi.mesh = ob
			obi.position = Vector3(0, 0.07, 0)
			obi.material_override = _sash
			part.add_child(obi)


## Put a bokken in the right fist and lock it there with a fixed joint.
## Works at any time: the grip is placed relative to where the forearm is now.
func equip_sword() -> void:
	if sword:
		return
	sword = DUMMY_SWORD.instantiate()
	sword.name = "Sword"
	add_child(sword)
	sword.global_transform = _sword_grip_transform()
	sword.wielder = self
	attach_to_part("lower_arm_r", sword, sword.global_position)


## Where the sword sits relative to the right forearm. In rest pose the forearm
## hangs down and the blade points down-forward; once the guard pose raises the
## forearm to horizontal, the blade ends up pointing up-forward.
func _sword_grip_transform() -> Transform3D:
	var forearm: RagdollPart = parts["lower_arm_r"]
	return forearm.global_transform * (_rest["lower_arm_r"].affine_inverse() * _rest_grip())


## The sword in the rest frame while the arm hangs in its rest pose.
static func _rest_grip() -> Transform3D:
	return Transform3D(Basis.looking_at(Vector3(0, -0.71, 0.71), Vector3.BACK), Vector3(-0.25, 0.86, 0.02))


## Reach for a blade line in world space: [param start] where the blade begins
## above the guard, [param dir] the blade direction. [param weight] fades the
## procedural arm in (1) or back to the pose (0).
func reach_blade_line(start: Vector3, dir: Vector3, weight: float = 1.0) -> void:
	if arm_ik == null:
		return
	if weight > 0.0:
		arm_ik.solve(arm_ik.to_rest_frame(start), arm_ik.dir_to_rest_frame(dir), ik_iterations)
	set_ik(arm_ik.joint_targets(), weight)


# --- Damage -------------------------------------------------------------------

## Called by weapons. Fills in damage and returns the completed hit.
func receive_hit(part: RagdollPart, hit: Dictionary) -> Dictionary:
	var element: String = hit.get("element", "physical")
	var dmg: float = hit.base_damage * profile.damage_multiplier(hit.zone, element)
	if _counter_time > 0.0:
		dmg *= profile.counter_multiplier
		hit["counter"] = true
	dmg = snappedf(dmg, 0.1)
	hp = maxf(hp - dmg, 0.0)
	hit["target"] = profile.display_name
	hit["damage"] = dmg
	hit["hp_left"] = hp

	# Momentum, not damage, knocks the body off balance: a committed swing
	# staggers, a wrist flick barely moves it.
	var kb: Vector3 = hit.get("knockback", Vector3.ZERO)
	if kb != Vector3.ZERO:
		part.apply_impulse(kb.limit_length(30.0), hit.point - part.global_position)
	var poise := float(hit.impulse) * profile.poise_per_impulse if hit.has("impulse") else dmg * profile.poise_damage_scale
	weaken(dmg * profile.muscle_damage_scale, poise)
	hit["balance_left"] = snappedf(balance, 0.01)
	hit.erase("knockback")
	GameEvents.report_hit(hit)
	brain.on_hit(hit)
	hit_received.emit(hit)
	_flash_time = 0.12

	if hp <= 0.0 and not _revive_on_getup:
		_revive_on_getup = true
		GameEvents.log_event("enemy_defeated", {"enemy": profile.display_name})
		weaken(1.0, 1.0)
	return hit


## The player parried our attack: stagger and open a counter window.
func on_parried(info: Dictionary) -> void:
	_counter_time = profile.counter_window
	weaken(0.45, 0.5)
	brain.on_parried(info)
	if sword:
		sword.attacking = false
	GameEvents.log_event("enemy_parried", {"enemy": profile.display_name, "counter_window": profile.counter_window})


## Seconds left in which a hit counts as a counter (0 = closed).
func counter_time_left() -> float:
	return _counter_time


## The player's blade met ours without a parry: a block on either side.
func on_blade_contact(info: Dictionary) -> void:
	var duelist := brain as DuelistBrain
	if duelist == null:
		return
	if duelist.state == DuelistBrain.State.BLOCK:
		if duelist.on_block_contact(info):
			# Raised in time: the swing is deflected (the dummy's parry).
			var weapon = info.get("weapon")
			if weapon and weapon.has_method("feel_deflected"):
				weapon.feel_deflected(info.get("point", sword.global_position if sword else global_position))
			GameEvents.log_event("enemy_parry", {"enemy": profile.display_name})
	elif sword and sword.attacking:
		sword.attacking = false
		duelist.on_strike_blocked(info)


func set_attacks_enabled(enabled: bool) -> void:
	if brain is DuelistBrain:
		(brain as DuelistBrain).attacks_enabled = enabled
		GameEvents.log_event("dummy_attacks", {"enabled": enabled})


func attacks_enabled() -> bool:
	return brain is DuelistBrain and (brain as DuelistBrain).attacks_enabled


func set_difficulty(difficulty: DuelistDifficulty) -> void:
	if brain is DuelistBrain:
		(brain as DuelistBrain).difficulty = difficulty
		GameEvents.log_event("dummy_difficulty", {"level": difficulty.level})


func reset_dummy() -> void:
	hp = profile.max_hp
	_revive_on_getup = false
	_counter_time = 0.0
	global_position = home_position
	reset_body()
	if brain is DuelistBrain:
		(brain as DuelistBrain).reset()
	if sword:
		sword.global_transform = _sword_grip_transform()
		sword.linear_velocity = Vector3.ZERO
		sword.angular_velocity = Vector3.ZERO
	GameEvents.log_event("enemy_reset", {"enemy": profile.display_name})


func _on_state_changed(new_state: State) -> void:
	var names := {State.STANDING: "standing", State.KNOCKED_DOWN: "knocked_down", State.GETTING_UP: "getting_up"}
	GameEvents.log_event("enemy_state", {"enemy": profile.display_name, "state": names[new_state]})
	if new_state == State.STANDING and _revive_on_getup:
		_revive_on_getup = false
		hp = profile.max_hp


func _balance_regen() -> float: return profile.balance_regen
func _muscle_regen() -> float: return profile.muscle_regen
func _knockdown_time() -> float: return profile.knockdown_time
func _getup_time() -> float: return profile.getup_time


func _physics_process(delta: float) -> void:
	_counter_time = maxf(_counter_time - delta, 0.0)
	var intent := brain.think(delta, _perceive(delta))
	set_pose(intent.get("pose", "guard"))
	var attacking: bool = intent.get("attacking", false) and state == State.STANDING
	if sword:
		sword.attacking = attacking
	if attacking and not _was_attacking:
		_hit_player_this_strike = false
	_was_attacking = attacking
	if attacking:
		_try_hit_player(float(intent.get("damage", 10.0)), String(intent.get("attack", "")))
	if intent.has("face_position") and state == State.STANDING:
		face_toward(intent.face_position)
	_apply_move(intent.get("move", Vector3.ZERO), delta, intent.get("plant", false))
	if not forced_blade_line.is_empty():
		reach_blade_line(forced_blade_line[0], forced_blade_line[1], 1.0)
	elif intent.has("guard_line"):
		var line: Array = intent.guard_line
		reach_blade_line(line[0], line[1], 1.0)
	else:
		reach_blade_line(Vector3.ZERO, Vector3.FORWARD, 0.0)
	_show_tell(float(intent.get("tell", 0.0)))
	super._physics_process(delta)


## What the brain gets to know this tick (see [method EnemyBrain.think]).
func _perceive(delta: float) -> Dictionary:
	var pelvis := root_part()
	var ctx := {
		"self_position": pelvis.global_position,
		"self_forward": Vector3(sin(_facing_yaw), 0.0, cos(_facing_yaw)),
		"chest_position": (parts["chest"] as RagdollPart).global_position,
		"home_position": home_position,
		"anchor_position": anchor_position,
		"can_act": state == State.STANDING,
		"move_blocked": _move_blocked,
	}
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	if head:
		ctx["player_position"] = head.global_position
		ctx["player_forward"] = -head.global_basis.z
	var health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	ctx["player_alive"] = health == null or health.is_alive()
	var blades: Array[Dictionary] = []
	for w in get_tree().get_nodes_in_group("player_weapons"):
		var weapon := w as HeldWeapon
		if weapon == null or not weapon.is_held():
			_prev_tips.erase(w)
			continue
		var tip := weapon.get_tip_global()
		var prev: Vector3 = _prev_tips.get(w, tip)
		_prev_tips[w] = tip
		blades.append({"tip": tip, "velocity": (tip - prev) / maxf(delta, 1e-4)})
	ctx["player_blades"] = blades
	return ctx


## Walk the anchor, but not into walls or props. [param planted]: the pose
## owns the legs (wind-up, strike step, block), so no walking steps on top.
func _apply_move(move: Vector3, delta: float, planted := false) -> void:
	move.y = 0.0
	if state != State.STANDING:
		move_velocity = Vector3.ZERO
		overlay_pose = ""
		_move_blocked = false
		return
	if move.length() < 0.02:
		move = Vector3.ZERO
		_move_blocked = false
	else:
		_move_blocked = _blocked_toward(move.normalized())
	if _move_blocked:
		move_velocity = Vector3.ZERO
	else:
		move_velocity = move_velocity.move_toward(move, (BURST_ACCEL if planted else MOVE_ACCEL) * delta)
	if move_velocity.length() > 0.15 and not planted:
		_step_time += delta
		overlay_pose = "step_l" if fmod(_step_time, 0.56) < 0.28 else "step_r"
	else:
		overlay_pose = ""


func _blocked_toward(dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := root_part().global_position
	var own: Array[RID] = []
	for p: RagdollPart in parts.values():
		own.append(p.get_rid())
	if sword:
		own.append(sword.get_rid())
	for h in [-0.6, -0.1]:
		var a := Vector3(from.x, from.y + h, from.z)
		var q := PhysicsRayQueryParameters3D.create(a, a + dir * 0.5, 1, own)
		if not space.intersect_ray(q).is_empty():
			return true
	return false


## The blade cuts the player if it passes through their body during a strike.
func _try_hit_player(damage: float, attack: String) -> void:
	if _hit_player_this_strike or sword == null:
		return
	var health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health == null or not health.is_alive():
		return
	var body := health.hurt_capsule()  # [top, bottom, radius]
	var a := sword.global_transform * sword.blade_start
	var b := sword.get_tip_global()
	var pts := Geometry3D.get_closest_points_between_segments(a, b, body[0], body[1])
	if pts[0].distance_to(pts[1]) <= float(body[2]):
		_hit_player_this_strike = true
		health.take_hit(damage, pts[0], {"attacker": profile.display_name, "attack": attack})


func _show_tell(tell: float) -> void:
	_eyes.emission_energy_multiplier = tell * tell * 4.0
	if tell > 0.0 and _last_tell <= 0.0 and sword:
		Sfx.play_at("enemy_tell", sword.global_position, -4.0)
	_last_tell = tell


func _process(delta: float) -> void:
	# Brief red flash on hit.
	if _flash_time > 0.0:
		_flash_time -= delta
		_straw.set_shader_parameter("flash", clampf(_flash_time / 0.12, 0.0, 1.0) * 0.6)
