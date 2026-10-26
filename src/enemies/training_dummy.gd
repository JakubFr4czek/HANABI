class_name TrainingDummy
extends ActiveRagdoll
## Straw training dummy (kakashi) for testing sword physics: an active ragdoll
## that staggers, falls and gets up, holding a physics bokken in its right hand
## so blade-vs-blade clashes (future parries) can be tested.
##
## It never dies for good: at 0 HP it collapses, then gets up with full HP.

signal hit_received(hit: Dictionary)

const DUMMY_SWORD := preload("res://scenes/weapons/dummy_sword.tscn")

@export var profile: EnemyProfile
@export var hold_sword := true

var hp := 100.0
var brain: EnemyBrain
var sword: BladeBody

var _straw := StandardMaterial3D.new()
var _sash := StandardMaterial3D.new()
var _ink := StandardMaterial3D.new()
var _flash_time := 0.0
var _revive_on_getup := false
var _counter_time := 0.0  # > 0 while open to a counter after being parried


func _ready() -> void:
	if profile == null:
		profile = EnemyProfile.new()
	hp = profile.max_hp
	_straw.albedo_color = Color(0.70, 0.58, 0.36)
	_straw.roughness = 0.95
	_sash.albedo_color = Color(0.75, 0.06, 0.08)
	_sash.roughness = 0.6
	_ink.albedo_color = Color(0.03, 0.03, 0.04)
	super._ready()
	for child in get_children():
		if child is EnemyBrain:
			brain = child
	if brain == null:
		brain = DummyBrain.new()
		brain.name = "Brain"
		add_child(brain)
	brain.setup(self, profile)
	if hold_sword:
		equip_sword()
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
			"extra_shapes": [{"shape": "box", "size": Vector3(0.10, 0.06, 0.24), "offset": Vector3(0, -0.24, 0.05)}]}
	return d


## Mirror a z-axis range for the right side.
static func _mirror(range_deg: Vector2, s: float) -> Vector2:
	return range_deg if s > 0.0 else Vector2(-range_deg.y, -range_deg.x)


func _define_poses() -> Dictionary:
	return {
		# Chūdan-ish guard: sword in the right hand, held forward and up.
		"guard": {
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
			"_max_speed": 7.0,
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
		# Thrown off balance after a parry: arms flung up and back.
		"staggered": {
			"_stiffness": 0.7,
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
		"idle": {},
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
				eye.material_override = _ink
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
	var rest_grip := Transform3D(Basis.looking_at(Vector3(0, -0.71, 0.71), Vector3.BACK), Vector3(-0.25, 0.86, 0.02))
	return forearm.global_transform * (_rest["lower_arm_r"].affine_inverse() * rest_grip)


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

	var kb: Vector3 = hit.get("knockback", Vector3.ZERO)
	if kb != Vector3.ZERO:
		part.apply_impulse(kb.limit_length(25.0), hit.point - part.global_position)
	weaken(dmg * profile.muscle_damage_scale, dmg * profile.poise_damage_scale)
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


func set_attacks_enabled(enabled: bool) -> void:
	if brain is DummyBrain:
		(brain as DummyBrain).attacks_enabled = enabled
		GameEvents.log_event("dummy_attacks", {"enabled": enabled})


func attacks_enabled() -> bool:
	return brain is DummyBrain and (brain as DummyBrain).attacks_enabled


func reset_dummy() -> void:
	hp = profile.max_hp
	_revive_on_getup = false
	_counter_time = 0.0
	reset_body()
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
	var context := {"self_position": root_part().global_position, "can_act": state == State.STANDING}
	var players := get_tree().get_nodes_in_group("player_head")
	if not players.is_empty():
		context["player_position"] = (players[0] as Node3D).global_position
	var intent := brain.think(delta, context)
	set_pose(intent.get("pose", "guard"))
	if sword:
		sword.attacking = intent.get("attacking", false) and state == State.STANDING
	if intent.has("face_position") and state == State.STANDING:
		face_toward(intent.face_position)
	super._physics_process(delta)


func _process(delta: float) -> void:
	# Brief red flash on hit.
	if _flash_time > 0.0:
		_flash_time -= delta
		_straw.albedo_color = Color(0.95, 0.35, 0.3) if _flash_time > 0.0 else Color(0.70, 0.58, 0.36)
