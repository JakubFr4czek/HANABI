class_name HurtFeedback
extends Node
## What the player feels when an enemy cuts them: a red vignette that fades
## out, a heavy haptic thump in both controllers, and a body-hit sound. A faint
## pulsing vignette stays while health is low. No camera shake (VR comfort).

const VIGNETTE_SHADER := preload("res://src/shaders/hurt_vignette.gdshader")

@export var fade_time := 0.6

var health: PlayerHealth
var holders: Array = []
var vignette: MeshInstance3D
var intensity := 0.0

var _material := ShaderMaterial.new()


## [param camera] gets the vignette quad; [param p_holders] get the haptics.
func setup(p_health: PlayerHealth, camera: Node3D, p_holders: Array) -> void:
	health = p_health
	holders = p_holders
	_material.shader = VIGNETTE_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	vignette = MeshInstance3D.new()
	vignette.name = "HurtVignette"
	vignette.mesh = quad
	vignette.material_override = _material
	vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vignette.extra_cull_margin = 16384.0
	vignette.position = Vector3(0.0, 0.0, -0.1)
	vignette.visible = false
	camera.add_child(vignette)
	health.damaged.connect(_on_damaged)


func _on_damaged(amount: float, _hp_left: float, source: Vector3) -> void:
	intensity = clampf(0.45 + amount / 40.0, 0.45, 1.0)
	var heavy := clampf(0.6 + amount / 50.0, 0.6, 1.0)
	for h in holders:
		if h and h.has_method("pulse_pattern"):
			h.pulse_pattern([[heavy, 0.07], [0.0, 0.04], [heavy * 0.45, 0.16]])
	Sfx.play_at("player_hurt", source, 0.0)


func _process(_delta: float) -> void:
	var dt := get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	intensity = maxf(intensity - dt / fade_time, 0.0)
	var low := 0.0
	if health and health.is_alive():
		low = clampf(1.0 - health.hp / (health.max_hp * 0.35), 0.0, 1.0)
	elif health:
		# Subtle crimson edge when fallen so the in-world Memorial Stele remains clear.
		low = 0.22
	_material.set_shader_parameter("intensity", intensity)
	_material.set_shader_parameter("low_health", low)
	if vignette:
		vignette.visible = intensity > 0.001 or low > 0.001
