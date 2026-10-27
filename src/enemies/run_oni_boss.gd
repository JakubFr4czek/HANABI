class_name RunOniBoss
extends TrainingDummy
## Periodic Oni boss for survival runs (docs/GDD.md §7, NIGHT_PLAN.md §4).
## DuelistBrain parryable combos; permanent death. Demon flesh + mask, not wood dummy.

signal boss_defeated(oni: RunOniBoss, hit: Dictionary)

var is_dead := false
var _last_hit := {}
var _flesh := ShaderMaterial.new()
var _armor := ShaderMaterial.new()
var _mask := ShaderMaterial.new()
var _rim: OmniLight3D


func _ready() -> void:
	add_to_group("oni_boss")
	add_to_group("enemies")
	scale = Vector3(1.28, 1.28, 1.28)
	_flesh.shader = WET_SURFACE_SHADER
	_flesh.set_shader_parameter("base_color", Color(0.11, 0.04, 0.05))
	_flesh.set_shader_parameter("roughness_dry", 0.62)
	_flesh.set_shader_parameter("roughness_wet", 0.28)
	_flesh.set_shader_parameter("wetness", 0.58)
	_flesh.set_shader_parameter("waterline_y", -10.0)
	_flesh.set_shader_parameter("fill", 2.05)
	_flesh.set_shader_parameter("fog_rim", 1.35)
	_flesh.set_shader_parameter("emission_tint", Color(0.55, 0.08, 0.06))
	_flesh.set_shader_parameter("flash_color", Color(1.2, 0.22, 0.1))
	_armor.shader = WET_SURFACE_SHADER
	_armor.set_shader_parameter("base_color", Color(0.38, 0.03, 0.05))
	_armor.set_shader_parameter("roughness_dry", 0.48)
	_armor.set_shader_parameter("roughness_wet", 0.22)
	_armor.set_shader_parameter("wetness", 0.62)
	_armor.set_shader_parameter("fill", 1.85)
	_armor.set_shader_parameter("fog_rim", 1.1)
	_armor.set_shader_parameter("emission_tint", Color(0.42, 0.05, 0.04))
	_mask.shader = WET_SURFACE_SHADER
	_mask.set_shader_parameter("base_color", Color(0.92, 0.86, 0.78))
	_mask.set_shader_parameter("roughness_dry", 0.68)
	_mask.set_shader_parameter("wetness", 0.35)
	_mask.set_shader_parameter("fill", 2.35)
	_mask.set_shader_parameter("fog_rim", 1.65)
	_mask.set_shader_parameter("emission_tint", Color(0.35, 0.32, 0.28))
	super._ready()
	_apply_oni_visuals()
	_eyes.emission = Color(2.2, 0.42, 0.15)
	_eyes.emission_energy_multiplier = 2.1
	_sash.albedo_color = Color(0.48, 0.04, 0.06)
	_sash.emission_enabled = true
	_sash.emission = Color(0.62, 0.08, 0.05)
	_sash.emission_energy_multiplier = 0.42
	set_attacks_enabled(true)
	_attach_oni_rim_light()
	GameEvents.log_event("oni_spawned", {"hp": hp})


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_oni_readability()


func _update_oni_readability() -> void:
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	var player_pos := head.global_position if head else global_position + Vector3(0, 1.2, 4.0)
	var d := global_position.distance_to(player_pos)
	var near := clampf(1.0 - d / 8.0, 0.0, 1.0)
	if _rim == null:
		_rim = get_node_or_null("OniRimLight") as OmniLight3D
	if _rim:
		_rim.light_energy = lerpf(0.48, 1.35, near)
		_rim.omni_range = lerpf(2.6, 3.8, near)
	_mask.set_shader_parameter("fill", lerpf(2.35, 3.25, near))
	_flesh.set_shader_parameter("fill", lerpf(2.05, 2.65, near))
	_flesh.set_shader_parameter("fog_rim", lerpf(1.35, 2.05, near))
	_armor.set_shader_parameter("fog_rim", lerpf(1.1, 1.65, near))


func _attach_oni_rim_light() -> void:
	if get_node_or_null("OniRimLight"):
		return
	var lamp := OmniLight3D.new()
	lamp.name = "OniRimLight"
	lamp.light_color = Color(1.0, 0.32, 0.12)
	lamp.light_energy = 0.42
	lamp.omni_range = 2.6
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.0, 1.35, 0.25)
	add_child(lamp)


func _apply_oni_visuals() -> void:
	for p: RagdollPart in parts.values():
		for c in p.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				if mi.material_override == _straw:
					mi.material_override = _flesh
	if parts.has("head"):
		_attach_oni_mask(parts["head"] as RagdollPart)
	if parts.has("chest"):
		_attach_oni_armor(parts["chest"] as RagdollPart)


func _attach_oni_mask(head: RagdollPart) -> void:
	for c in head.get_children():
		if c.name == "OniMask":
			return
	var mask_mi := MeshInstance3D.new()
	mask_mi.name = "OniMask"
	var m := BoxMesh.new()
	m.size = Vector3(0.26, 0.30, 0.065)
	mask_mi.mesh = m
	mask_mi.position = Vector3(0, 0.04, 0.12)
	mask_mi.material_override = _mask
	var brow := MeshInstance3D.new()
	brow.name = "OniBrow"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.028, 0.04)
	brow.mesh = bm
	brow.position = Vector3(0, 0.1, 0.145)
	var brow_mat := StandardMaterial3D.new()
	brow_mat.albedo_color = Color(0.62, 0.06, 0.05)
	brow_mat.emission_enabled = true
	brow_mat.emission = Color(0.95, 0.12, 0.06)
	brow_mat.emission_energy_multiplier = 0.55
	brow.material_override = brow_mat
	mask_mi.add_child(brow)
	var eye_l := MeshInstance3D.new()
	var eye_m := SphereMesh.new()
	eye_m.radius = 0.018
	eye_m.height = 0.036
	eye_l.mesh = eye_m
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(2.5, 0.35, 0.08)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(2.8, 0.45, 0.1)
	eye_mat.emission_energy_multiplier = 2.4
	eye_l.material_override = eye_mat
	for sx in [-1.0, 1.0]:
		var e := eye_l.duplicate() as MeshInstance3D
		e.position = Vector3(0.055 * sx, 0.02, 0.14)
		mask_mi.add_child(e)
	head.add_child(mask_mi)
	for sx in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.bottom_radius = 0.032
		cyl.top_radius = 0.006
		cyl.height = 0.26
		cyl.radial_segments = 10
		horn.mesh = cyl
		horn.position = Vector3(0.07 * sx, 0.16, 0.09)
		horn.rotation = Vector3(deg_to_rad(-35.0), 0.0, deg_to_rad(-22.0 * sx))
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.08, 0.05, 0.06)
		hm.emission_enabled = true
		hm.emission = Color(0.85, 0.12, 0.05)
		hm.emission_energy_multiplier = 0.95
		horn.material_override = hm
		head.add_child(horn)


func _attach_oni_armor(chest: RagdollPart) -> void:
	for c in chest.get_children():
		if c.name == "OniArmor":
			return
	var plate := MeshInstance3D.new()
	plate.name = "OniArmor"
	var m := BoxMesh.new()
	m.size = Vector3(0.48, 0.22, 0.28)
	plate.mesh = m
	plate.position = Vector3(0, 0.14, 0.04)
	plate.material_override = _armor
	chest.add_child(plate)


func _allow_revive_after_knockout() -> bool:
	return false


func receive_hit(part: RagdollPart, hit: Dictionary) -> Dictionary:
	_last_hit = hit
	return super.receive_hit(part, hit)


func _on_permanent_defeat() -> void:
	if is_dead:
		return
	is_dead = true
	set_attacks_enabled(false)
	if sword:
		sword.attacking = false
	var chest := parts.get("chest") as RagdollPart if parts.has("chest") else null
	var pos := chest.global_position if chest else global_position + Vector3(0, 1.2, 0)
	if is_inside_tree() and get_tree().current_scene:
		ElementFirework.spawn(get_tree().current_scene, pos, Elements.STORM, 1.45)
	GameEvents.log_event("oni_defeated", {"hp": 0.0})
	boss_defeated.emit(self, _last_hit)
	call_deferred("queue_free")
