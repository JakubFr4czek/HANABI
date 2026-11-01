class_name RunOniBoss
extends TrainingDummy
## Periodic Oni boss for survival runs (docs/GDD.md §7, §8, Zadanie D15).
##
## AI-controlled demonic warlord (~2.7m tall) wielding a heavy spiked Kanabō.
## Features:
## - Scaled body proportions (~2.7m tall) with matching physical hitboxes.
## - Active pursuit and 3 telegraphed attacks (Overhead Slam, Cleave Sweep, Demon Lunge).
## - AI-controlled via [OniBossBrain] with Meta Model API (Muse Spark / Llama) and local fallback.
## - 3D billboard speech bubble for atmospheric Polish/English combat lines.
## - Permanent defeat upon deplete, dropping storm fireworks and emitting [signal boss_defeated].

signal boss_defeated(oni: RunOniBoss, hit: Dictionary)

const ONI_SCALE := 1.50
## Scale of the boss mask node (N3): the shared demon mask, at the size of the old boss mask.
const ONI_MASK_SCALE := 1.88
## Half-thickness of the visible kanabō head: mesh AABB x 0.144 m × 1.45 scale
## (0.209 m) → radius 0.105 m. Added to the player capsule radius; the blade
## segment below already spans the whole visible head, so no extra reach fudge.
const KANABO_HIT_RADIUS := 0.105

const ONI_BODY_GLB := preload("res://assets/models/enemies/oni_body_run.glb")
const ONI_KANABO_GLB := preload("res://assets/models/enemies/oni_kanabo_run.glb")

var is_dead := false
## Open Kirisute wounds (D4 §8): most this many glow at once (Quest budget).
const MAX_WOUNDS := 2
var _wounds: Array[MeshInstance3D] = []
var _last_hit := {}
var _flesh := ShaderMaterial.new()
var _armor := ShaderMaterial.new()
var _mask := ShaderMaterial.new()
var _rim: OmniLight3D
var _robe := ShaderMaterial.new()
static var _cached_body_mesh: Mesh
static var _cached_kanabo_mesh: Mesh

var speech_bubble: OniSpeechBubble


func _define_parts() -> Dictionary:
	var s_scale := ONI_SCALE
	var d := {
		"pelvis": {"shape": "box", "size": Vector3(0.30, 0.18, 0.18) * s_scale, "pos": Vector3(0, 0.98 * s_scale, 0), "mass": 24.0, "zone": "torso"},
		"chest": {"shape": "box", "size": Vector3(0.36, 0.44, 0.21) * s_scale, "pos": Vector3(0, 1.31 * s_scale, 0), "mass": 36.0, "zone": "torso",
			"parent": "pelvis", "joint": Vector3(0, 1.08 * s_scale, 0), "max_torque": 1200.0,
			"limits": {"x": Vector2(-25, 45), "y": Vector2(-35, 35), "z": Vector2(-25, 25)}},
		"head": {"shape": "sphere", "radius": 0.115 * s_scale, "pos": Vector3(0, 1.67 * s_scale, 0), "mass": 10.0, "zone": "head",
			"parent": "chest", "joint": Vector3(0, 1.54 * s_scale, 0), "max_torque": 250.0,
			"limits": {"x": Vector2(-40, 40), "y": Vector2(-60, 60), "z": Vector2(-30, 30)}},
	}
	# Left side is +X (dummy faces +Z). Right side mirrors y/z limits.
	for side in ["l", "r"]:
		var s := 1.0 if side == "l" else -1.0
		d["upper_arm_" + side] = {"shape": "capsule", "radius": 0.05 * s_scale, "height": 0.32 * s_scale, "pos": Vector3(0.25 * s * s_scale, 1.33 * s_scale, 0),
			"mass": 5.5, "zone": "limb", "parent": "chest", "joint": Vector3(0.25 * s * s_scale, 1.49 * s_scale, 0), "max_torque": 500.0,
			"limits": {"x": Vector2(-150, 60), "y": Vector2(-70, 70), "z": _mirror(Vector2(-20, 110), s)}}
		d["lower_arm_" + side] = {"shape": "capsule", "radius": 0.045 * s_scale, "height": 0.30 * s_scale, "pos": Vector3(0.25 * s * s_scale, 1.03 * s_scale, 0),
			"mass": 3.5, "zone": "limb", "parent": "upper_arm_" + side, "joint": Vector3(0.25 * s * s_scale, 1.18 * s_scale, 0), "max_torque": 300.0,
			"limits": {"x": Vector2(-150, 5), "y": Vector2(-60, 60), "z": Vector2(-5, 5)}}
		d["upper_leg_" + side] = {"shape": "capsule", "radius": 0.07 * s_scale, "height": 0.44 * s_scale, "pos": Vector3(0.1 * s * s_scale, 0.69 * s_scale, 0),
			"mass": 16.0, "zone": "limb", "parent": "pelvis", "joint": Vector3(0.1 * s * s_scale, 0.90 * s_scale, 0), "max_torque": 1000.0,
			"limits": {"x": Vector2(-100, 35), "y": Vector2(-35, 35), "z": _mirror(Vector2(-15, 55), s)}}
		d["lower_leg_" + side] = {"shape": "capsule", "radius": 0.055 * s_scale, "height": 0.44 * s_scale, "pos": Vector3(0.1 * s * s_scale, 0.27 * s_scale, 0),
			"mass": 10.0, "zone": "limb", "parent": "upper_leg_" + side, "joint": Vector3(0.1 * s * s_scale, 0.48 * s_scale, 0), "max_torque": 800.0,
			"limits": {"x": Vector2(-3, 140), "y": Vector2(-3, 3), "z": Vector2(-3, 3)},
			"friction": 0.25,
			"extra_shapes": [{"shape": "box", "size": Vector3(0.10, 0.06, 0.24) * s_scale, "offset": Vector3(0, -0.24 * s_scale, 0.05 * s_scale)}]}
	return d


func _ready() -> void:
	add_to_group("oni_boss")
	add_to_group("enemies")
	scale = Vector3.ONE  # Clean 1:1 scale; physical parts are scaled in _define_parts
	max_anchor_lead = 0.6
	anchor_stiffness = 3.5
	anchor_gain = 0.08

	# Deep crimson flesh: the shader's `fill` is a flat self-light, so keep it low
	# and let the practicals model the form instead of turning the body into a
	# glowing balloon. A warm rim keeps the silhouette readable in the fog.
	_flesh.shader = WET_SURFACE_SHADER
	_flesh.set_shader_parameter("base_color", Color(0.18, 0.06, 0.06))
	_flesh.set_shader_parameter("roughness_dry", 0.60)
	_flesh.set_shader_parameter("roughness_wet", 0.28)
	_flesh.set_shader_parameter("wetness", 0.58)
	_flesh.set_shader_parameter("waterline_y", -10.0)
	_flesh.set_shader_parameter("fill", 0.85)
	_flesh.set_shader_parameter("fog_rim", 1.25)
	_flesh.set_shader_parameter("emission_tint", Color(0.30, 0.05, 0.04))
	_flesh.set_shader_parameter("flash_color", Color(1.2, 0.22, 0.1))

	# Lacquered plate: darker than the flesh, brighter rim so shoulders and the
	# chest plate read as facets instead of a single red egg.
	_armor.shader = WET_SURFACE_SHADER
	_armor.set_shader_parameter("base_color", Color(0.28, 0.055, 0.06))
	_armor.set_shader_parameter("roughness_dry", 0.44)
	_armor.set_shader_parameter("roughness_wet", 0.20)
	_armor.set_shader_parameter("wetness", 0.62)
	_armor.set_shader_parameter("fill", 0.65)
	_armor.set_shader_parameter("fog_rim", 0.95)
	_armor.set_shader_parameter("emission_tint", Color(0.20, 0.03, 0.03))

	_robe.shader = WET_SURFACE_SHADER
	_robe.set_shader_parameter("base_color", Color(0.08, 0.05, 0.07))
	_robe.set_shader_parameter("roughness_dry", 0.72)
	_robe.set_shader_parameter("roughness_wet", 0.34)
	_robe.set_shader_parameter("wetness", 0.52)
	_robe.set_shader_parameter("fill", 1.65)
	_robe.set_shader_parameter("fog_rim", 1.25)
	_robe.set_shader_parameter("procedural_ao", 0.55)

	_mask.shader = WET_SURFACE_SHADER
	# The mask is the demon mask shared with the yōkai (N3, CC BY 4.0): its own albedo, ORM and normal.
	_mask.set_shader_parameter("albedo_texture", YokaiForms.mask_albedo())
	_mask.set_shader_parameter("orm_texture", YokaiForms.mask_orm())
	_mask.set_shader_parameter("orm_mode", 1)
	_mask.set_shader_parameter("base_color", YokaiForms.MASK_TINT)
	_mask.set_shader_parameter("roughness_dry", 0.58)
	_mask.set_shader_parameter("roughness_wet", 0.22)
	_mask.set_shader_parameter("wetness", 0.48)
	_mask.set_shader_parameter("fill", 2.35)
	_mask.set_shader_parameter("fog_rim", 1.25)
	_mask.set_shader_parameter("flash_color", Color(0.9, 0.3, 0.16))
	_mask.set_shader_parameter("normal_texture", YokaiForms.mask_normal())
	_mask.set_shader_parameter("normal_depth", 1.35)
	_mask.set_shader_parameter("procedural_ao", 0.42)
	_mask.set_shader_parameter("emission_tint", Color(0.35, 0.32, 0.28))

	# Attach specialized Oni AI brain before super._ready()
	if brain == null:
		brain = OniBossBrain.new()
		brain.name = "Brain"
		add_child(brain)

	super._ready()

	_apply_oni_visuals()
	_attach_oni_rim_light()

	speech_bubble = OniSpeechBubble.new()
	speech_bubble.name = "SpeechBubble"
	add_child(speech_bubble)

	if brain is OniBossBrain:
		var oni_brain := brain as OniBossBrain
		oni_brain.speech_requested.connect(func(text: String): speech_bubble.show_speech(text))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_oni_readability()
	if speech_bubble and parts.has("head"):
		var head_part := parts["head"] as RagdollPart
		speech_bubble.global_position = head_part.global_position + Vector3(0.0, 0.72, 0.0)


func _update_oni_readability() -> void:
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	var player_pos := head.global_position if head else global_position + Vector3(0, 1.2, 4.0)
	var d := global_position.distance_to(player_pos)
	var near := clampf(1.0 - d / 8.0, 0.0, 1.0)
	if _rim == null:
		_rim = get_node_or_null("OniRimLight") as OmniLight3D
	if _rim:
		var active := d < 14.0
		_rim.visible = active
		if active:
			_rim.light_energy = lerpf(1.0, 1.7, near)
			_rim.omni_range = lerpf(3.2, 4.6, near)
		else:
			_rim.light_energy = 0.0
	_mask.set_shader_parameter("fill", lerpf(2.35, 3.25, near))
	_mask.set_shader_parameter("fog_rim", lerpf(1.35, 2.05, near))
	_flesh.set_shader_parameter("fill", lerpf(0.85, 1.25, near))
	_flesh.set_shader_parameter("fog_rim", lerpf(1.25, 1.75, near))
	_armor.set_shader_parameter("fill", lerpf(0.65, 0.95, near))
	_armor.set_shader_parameter("fog_rim", lerpf(0.95, 1.35, near))


func _attach_oni_rim_light() -> void:
	if get_node_or_null("OniRimLight"):
		return
	var lamp := OmniLight3D.new()
	lamp.name = "OniRimLight"
	lamp.light_color = Color(1.0, 0.30, 0.11)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.0
	lamp.shadow_enabled = false
	# Behind and above the shoulders: an ember rim, not a hot spot on the chest.
	lamp.position = Vector3(0.0, 2.25, -0.6)
	add_child(lamp)

	# A dim cool key from the front-left models the chest and mask under the
	# canopy without the flat self-light (fill) that used to wash out the form.
	var key := OmniLight3D.new()
	key.name = "OniKeyLight"
	key.light_color = Color(0.58, 0.66, 0.9)
	key.light_energy = 0.5
	key.omni_range = 3.6
	key.shadow_enabled = false
	key.position = Vector3(0.55, 2.1, 1.25)
	add_child(key)


## WaveDirector swaps in the Oni difficulty after setup(); re-apply the phase
## parameters so phase 1 does not silently keep the generic "hard" preset.
func set_difficulty(new_difficulty: DuelistDifficulty) -> void:
	super.set_difficulty(new_difficulty)
	if brain is OniBossBrain:
		(brain as OniBossBrain).refresh_phase_parameters()


func _sword_grip_transform() -> Transform3D:
	if not parts.has("lower_arm_r"):
		return super._sword_grip_transform()
	var forearm: RagdollPart = parts["lower_arm_r"]
	var grip_rot := Basis.from_euler(Vector3(deg_to_rad(-78.0), deg_to_rad(12.0), deg_to_rad(6.0)))
	var grip_pos := Vector3(0.08, -0.28, 0.12)
	return forearm.global_transform * Transform3D(grip_rot, grip_pos)


func equip_sword() -> void:
	super.equip_sword()
	if sword:
		sword.visible = false
		# Hit segment = the visible kanabō head, not a katana blade. Mesh AABB
		# 0.144 × 0.535 × 0.52 m at scale 1.45 (head 0.21 × 0.78 × 0.75 m),
		# centred ~0.05 m off the grip: forward tip -0.43 m, back end +0.34 m.
		sword.blade_start = Vector3(0, 0, 0.34)
		sword.blade_tip = Vector3(0, 0, -0.43)
		sword.mass = 4.5
	_attach_kanabo_visual()


func _apply_oni_visuals() -> void:
	for p: RagdollPart in parts.values():
		for c in p.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				if mi.name in ["OniMask", "OniBodyShell", "OniKanaboVisual"]:
					continue
				if p.name in ["pelvis", "chest"]:
					mi.visible = false
				else:
					mi.visible = true
					if mi.material_override == _straw or mi.material_override == null:
						mi.material_override = _flesh
	if parts.has("pelvis"):
		_attach_oni_body_shell(parts["pelvis"] as RagdollPart)
	if parts.has("head"):
		var head := parts["head"] as RagdollPart
		for c in head.get_children():
			if c is MeshInstance3D and c.name != "OniMask":
				(c as MeshInstance3D).visible = false
		_attach_oni_mask(head)


func _attach_oni_body_shell(pelvis: RagdollPart) -> void:
	for c in pelvis.get_children():
		if c.name == "OniBodyShell":
			return
	var body_mi := MeshInstance3D.new()
	body_mi.name = "OniBodyShell"
	var mesh := _oni_body_mesh()
	body_mi.mesh = mesh if mesh else BoxMesh.new()
	# Keep the shell below the neck: with a uniform 1.48 scale the generated
	# torso reached ~2.77 m and swallowed the 2.5 m head, hiding the mask behind
	# the chest plate whenever the boss faced the camera dead-on.
	body_mi.position = Vector3(0.0, 0.02, 0.0)
	body_mi.scale = Vector3(1.48, 1.20, 1.48)
	body_mi.material_override = _armor
	pelvis.add_child(body_mi)


func _attach_kanabo_visual() -> void:
	if not parts.has("lower_arm_r"):
		return
	var arm := parts["lower_arm_r"] as RagdollPart
	for c in arm.get_children():
		if c.name == "OniKanaboVisual":
			return
	var club := MeshInstance3D.new()
	club.name = "OniKanaboVisual"
	var mesh := _oni_kanabo_mesh()
	club.mesh = mesh if mesh else CylinderMesh.new()
	club.position = Vector3(0.12, -0.32, 0.18)
	club.rotation = Vector3(deg_to_rad(-78.0), deg_to_rad(12.0), deg_to_rad(6.0))
	club.scale = Vector3(1.45, 1.45, 1.45)
	var mat := ShaderMaterial.new()
	mat.shader = WET_SURFACE_SHADER
	mat.set_shader_parameter("base_color", Color(0.22, 0.20, 0.21))
	mat.set_shader_parameter("roughness_dry", 0.38)
	mat.set_shader_parameter("roughness_wet", 0.18)
	mat.set_shader_parameter("wetness", 0.55)
	mat.set_shader_parameter("metallic", 0.72)
	mat.set_shader_parameter("fill", 1.95)
	mat.set_shader_parameter("fog_rim", 1.35)
	club.material_override = mat
	arm.add_child(club)


static func _oni_body_mesh() -> Mesh:
	if _cached_body_mesh != null:
		return _cached_body_mesh
	var inst := ONI_BODY_GLB.instantiate()
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh:
			_cached_body_mesh = mi.mesh
			break
	inst.free()
	return _cached_body_mesh


static func _oni_kanabo_mesh() -> Mesh:
	if _cached_kanabo_mesh != null:
		return _cached_kanabo_mesh
	var inst := ONI_KANABO_GLB.instantiate()
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh:
			_cached_kanabo_mesh = mi.mesh
			break
	inst.free()
	return _cached_kanabo_mesh


static func _oni_mask_mesh() -> Mesh:
	return YokaiForms.mask_mesh()


func _attach_oni_mask(head: RagdollPart) -> void:
	for c in head.get_children():
		if c.name == "OniMask":
			return
	var mask_mi := MeshInstance3D.new()
	mask_mi.name = "OniMask"
	var mesh := _oni_mask_mesh()
	mask_mi.mesh = mesh if mesh else _fallback_mask_mesh()
	mask_mi.position = Vector3(0.0, 0.03, 0.16)
	# The yōkai mask is 0.22 m wide; at 1.88 the boss mask is about 0.41 m wide, as before (N3 fix2).
	mask_mi.scale = Vector3.ONE * ONI_MASK_SCALE
	mask_mi.material_override = _mask
	var eye_l := MeshInstance3D.new()
	var eye_m := SphereMesh.new()
	# Sized to the scaled mask: about 0.05 m eyes on the boss, as before.
	eye_m.radius = 0.05 / ONI_MASK_SCALE
	eye_m.height = 2.0 * eye_m.radius
	eye_l.mesh = eye_m
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.disable_fog = true
	eye_mat.render_priority = 5
	eye_mat.albedo_color = Color(3.5, 0.65, 0.15)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(3.5, 0.65, 0.15)
	eye_mat.emission_energy_multiplier = 3.0
	eye_l.material_override = eye_mat
	for sx in [-1.0, 1.0]:
		var e := eye_l.duplicate() as MeshInstance3D
		e.name = "OniEye_" + ("l" if sx < 0 else "r")
		# In the mask's sockets (YokaiForms.EYE_*), in the mask's own frame.
		e.position = Vector3(YokaiForms.EYE_X * sx, YokaiForms.EYE_Y, YokaiForms.EYE_Z)
		mask_mi.add_child(e)
	head.add_child(mask_mi)


static func _fallback_mask_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.38, 0.44, 0.09)
	return m



func _try_hit_player(damage: float, attack: String) -> void:
	if _hit_player_this_strike or sword == null:
		return
	var health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health == null or not health.is_alive():
		return
	var body := health.hurt_capsule()
	var a := sword.global_transform * sword.blade_start
	var b := sword.get_tip_global()
	var pts := Geometry3D.get_closest_points_between_segments(a, b, body[0], body[1])
	var reach_radius := float(body[2]) + KANABO_HIT_RADIUS
	if pts[0].distance_to(pts[1]) <= reach_radius:
		_hit_player_this_strike = true
		health.take_hit(damage, pts[0], {"attacker": profile.display_name, "attack": attack})


## Returns actual physical height measured from real visible mesh geometry.
func get_boss_height() -> float:
	return get_measured_height()


func get_measured_height() -> float:
	var min_y := INF
	var max_y := -INF
	for p: RagdollPart in parts.values():
		for c in p.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				if mi.visible and mi.mesh != null and mi.name != "OniKanaboVisual":
					var aabb := mi.mesh.get_aabb()
					for i in 8:
						var world_pt := mi.global_transform * aabb.get_endpoint(i)
						min_y = minf(min_y, world_pt.y)
						max_y = maxf(max_y, world_pt.y)
	if min_y == INF or max_y == -INF:
		push_warning("RunOniBoss: no visible mesh geometry to measure the boss height")
		return 0.0
	return max_y - min_y


func get_feet_lowest_y() -> float:
	var min_y := INF
	for side in ["l", "r"]:
		var part_name: String = "lower_leg_" + str(side)
		if parts.has(part_name):
			var leg := parts[part_name] as RagdollPart
			for c in leg.get_children():
				if c is MeshInstance3D:
					var mi := c as MeshInstance3D
					if mi.visible and mi.mesh != null and mi.name != "OniKanaboVisual":
						var aabb := mi.mesh.get_aabb()
						for i in 8:
							var world_pt := mi.global_transform * aabb.get_endpoint(i)
							min_y = minf(min_y, world_pt.y)
	return min_y if min_y != INF else global_position.y



func reset() -> void:
	reset_dummy()


func _allow_revive_after_knockout() -> bool:
	return false


func receive_hit(part: RagdollPart, hit: Dictionary) -> Dictionary:
	_last_hit = hit
	var result := super.receive_hit(part, hit)
	if bool(hit.get("kirisute_offer", false)) and not is_dead:
		_open_wound(part, hit)
	return result


## Kirisute (D4 §8): clean cuts leave glowing element wounds that close over ~2 s.
func _open_wound(part: RagdollPart, hit: Dictionary) -> void:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return
	var element: String = hit.get("element", Elements.NONE)
	var point: Vector3 = hit.get("point", part.global_position)
	KirisuteCut.wound(scene, point, hit.get("direction", Vector3.UP), element)
	var radial := point - part.global_position
	radial = radial.normalized() if radial.length_squared() > 1e-8 else Vector3.FORWARD
	var axis: Vector3 = hit.get("blade_axis", Vector3.RIGHT)
	var along := axis - radial * axis.dot(radial)
	if along.length_squared() < 1e-6:
		return
	along = along.normalized()
	var slit := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.38, 0.024)
	slit.mesh = quad
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = KirisuteCut.glow_color(element)
	glow.emission_enabled = true
	glow.emission = KirisuteCut.glow_color(element)
	glow.emission_energy_multiplier = 2.0
	slit.material_override = glow
	part.add_child(slit)
	slit.global_transform = Transform3D(Basis(along, radial.cross(along), radial), point + radial * 0.005)
	_wounds.append(slit)
	while _wounds.size() > MAX_WOUNDS:
		var closing: MeshInstance3D = _wounds.pop_front()
		if is_instance_valid(closing):
			closing.queue_free()
	var closes := slit.create_tween()
	closes.tween_property(glow, "albedo_color:a", 0.0, ElementBalance.KIRISUTE_WOUND_SECONDS)
	closes.tween_callback(slit.queue_free)


func _on_permanent_defeat() -> void:
	if is_dead:
		return
	is_dead = true
	set_attacks_enabled(false)
	if sword:
		sword.attacking = false
	var chest := parts.get("chest") as RagdollPart if parts.has("chest") else null
	var pos := chest.global_position if chest else global_position + Vector3(0, 1.8, 0)
	if is_inside_tree() and get_tree().current_scene:
		ElementFirework.spawn(get_tree().current_scene, pos, Elements.STORM, 1.45)
	GameEvents.log_event("oni_defeated", {"hp": 0.0})
	boss_defeated.emit(self, _last_hit)
	call_deferred("queue_free")

func head_part() -> RagdollPart:
	return parts.get("head") as RagdollPart

func play_attack(attack_type: String = "vertical") -> void:
	if brain is DuelistBrain:
		var d_brain := brain as DuelistBrain
		d_brain.force_attack(attack_type)


func is_attacking() -> bool:
	if brain is DuelistBrain:
		var d_brain := brain as DuelistBrain
		return d_brain.state == DuelistBrain.State.ATTACK
	return false
