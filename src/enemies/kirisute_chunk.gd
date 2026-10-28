class_name KirisuteChunk
extends RigidBody3D
## One half of a body cut by Kirisute (docs/ELEMENTS_PLAN.md, D4 §5). A loose
## piece: it collides with the terrain only, so the blade and the player pass
## through it. Its cut glows hot and cools, then the piece dissolves into sakura
## petals where it was cut.

static var _alive: Array[KirisuteChunk] = []

## Visual node (the one mesh child); it shrinks at the end, the body does not.
var visual: MeshInstance3D
## The cut's glowing material, shared with the other half of the same cut.
var cap_material: StandardMaterial3D
var _age := 0.0
var _dissolving := false


## The cap material of a cut in [param element]'s colour. Ink is glossy black with
## an indigo wash, the other schools glow in their own colour.
static func make_cap_material(element: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.04, 0.06)
	m.roughness = 0.35
	m.metallic_specular = 0.8
	if element == Elements.INK:
		# Glossy black: the wet sheen is the roughness, the indigo is the glow.
		m.albedo_color = Color(0.01, 0.01, 0.015)
		m.roughness = 0.12
	m.emission_enabled = true
	m.emission = KirisuteCut.glow_color(element)
	m.emission_energy_multiplier = KirisuteCut.CAP_HOT
	return m


## Makes room for [param count] new pieces: the oldest go first beyond
## [constant ElementBalance.KIRISUTE_MAX_PIECES] (Quest budget).
static func make_room(count: int) -> void:
	while _alive.size() + count > ElementBalance.KIRISUTE_MAX_PIECES and not _alive.is_empty():
		var oldest: KirisuteChunk = _alive.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _enter_tree() -> void:
	_alive.append(self)


func _exit_tree() -> void:
	_alive.erase(self)


func _physics_process(delta: float) -> void:
	_age += delta
	if cap_material:
		var t := clampf(_age / ElementBalance.KIRISUTE_CAP_FADE_SECONDS, 0.0, 1.0)
		cap_material.emission_energy_multiplier = lerpf(KirisuteCut.CAP_HOT, KirisuteCut.CAP_COOL, t)
	var lie := ElementBalance.KIRISUTE_PIECE_SECONDS
	var dissolve := ElementBalance.KIRISUTE_DISSOLVE_SECONDS
	if not _dissolving and _age >= lie:
		# The petals are born inside the meshes at full size, then the piece shrinks away.
		_dissolving = true
		SakuraScatter.burst_from(self, get_parent(), 14, linear_velocity, cap_material.emission if cap_material else Color.WHITE)
	if _dissolving:
		var t := clampf((_age - lie) / dissolve, 0.0, 1.0)
		if visual:
			visual.scale = Vector3.ONE * (1.0 - t)
		if t >= 1.0:
			queue_free()
			set_physics_process(false)
