class_name RunIntro
extends Node
## Run opening: seiza levitation, petal swirl, seal glow, lightning ripple,
## katana materialize (docs/GDD.md §9, NIGHT_PLAN.md §5).

signal finished

const PETAL_SHADER := preload("res://src/shaders/sakura_petal.gdshader")
const SHADOW_SHADER := preload("res://src/shaders/seiza_shadow.gdshader")

const HOVER_HEIGHT := 0.78
const DESCENT_SEC := 3.1
const PETAL_COUNT := 18

var active := false

var _player: Node3D
var _katana: HeldWeapon
var _spawn_pos := Vector3.ZERO
var _spawn_yaw := 0.0
var _seal_material: ShaderMaterial
var _lightning: StormLightning
var _ground_y := 0.0
var _t := 0.0
var _descent_done := false
var _ripple_t := 0.0
var _ripple_playing := false
var _katana_reveal := 0.0
## After the descent the katana hangs in the air before the player and the run
## only starts once it is taken: the grab is the start button.
var _waiting_grab := false
var _float_basis := Basis.IDENTITY
var _shadow: MeshInstance3D
var _petals: Array[MeshInstance3D] = []
var _petal_angles: PackedFloat32Array
var _rng := RandomNumberGenerator.new()
var _meditation_hand := Vector3(0.02, -0.38, -0.22)


func setup(player: Node3D, katana: HeldWeapon, spawn_pos: Vector3, spawn_yaw: float,
		seal_material: ShaderMaterial, lightning: StormLightning, ground_y: float = 0.0) -> void:
	_player = player
	_katana = katana
	_spawn_pos = spawn_pos
	_spawn_yaw = spawn_yaw
	_seal_material = seal_material
	_lightning = lightning
	_ground_y = ground_y
	_build_visuals()


func start() -> void:
	if _player == null or _katana == null:
		finished.emit()
		return
	active = true
	_t = 0.0
	_descent_done = false
	_ripple_playing = false
	_waiting_grab = false
	_ripple_t = 0.0
	_katana_reveal = 0.0
	_set_ripple(0.0, 0.0)
	_set_seal_glow(0.35)
	_hide_katana()
	_lock_player(true)
	_place_player_at_height(HOVER_HEIGHT)
	if _shadow:
		_shadow.visible = true
		(_shadow.material_override as ShaderMaterial).set_shader_parameter("shadow_strength", 0.92)
	for p in _petals:
		p.visible = true
	GameEvents.log_event("run_intro_started", {})


func skip() -> void:
	if not active:
		return
	_finish_intro()


func is_active() -> bool:
	return active


func _physics_process(delta: float) -> void:
	if not active:
		return
	var real_delta := TimeController.real_tick()
	_t += real_delta
	if not _descent_done:
		var progress := clampf(_t / DESCENT_SEC, 0.0, 1.0)
		var height := lerpf(HOVER_HEIGHT, 0.0, progress)
		_place_player_at_height(height)
		_set_seal_glow(0.35 + progress * 0.65)
		_update_petals(real_delta, progress)
		_update_shadow(progress)
		if _player is DesktopPlayer:
			var dp := _player as DesktopPlayer
			dp.hand_offset = dp.hand_offset.lerp(_meditation_hand, real_delta * 4.5)
		if progress >= 1.0:
			_touchdown()
	else:
		_step_post_touchdown(real_delta)


func _touchdown() -> void:
	_descent_done = true
	_place_player_at_height(0.0)
	_set_seal_glow(1.0)
	_ripple_playing = true
	_ripple_t = 0.0
	_pulse_lightning()
	GameEvents.log_event("run_intro_touchdown", {})


func _step_post_touchdown(delta: float) -> void:
	if _ripple_playing:
		_ripple_t += delta
		var radius := _ripple_t * 11.5
		var gain := clampf(1.0 - _ripple_t / 0.85, 0.0, 1.0) * 0.95
		_set_ripple(radius, gain)
		if _ripple_t >= 0.9:
			_ripple_playing = false
			_set_ripple(0.0, 0.0)
	_katana_reveal = minf(_katana_reveal + delta * 2.4, 1.0)
	_reveal_katana(_katana_reveal)
	_update_petals(delta, 1.0)
	if _waiting_grab:
		_float_katana()
		if _katana and _katana.is_held():
			_finish_intro()
	elif _katana_reveal >= 1.0 and not _ripple_playing:
		_begin_float()


func _finish_intro() -> void:
	if not active:
		return
	active = false
	_set_seal_glow(0.0)
	_set_ripple(0.0, 0.0)
	for p in _petals:
		p.visible = false
	if _shadow:
		_shadow.visible = false
	# Land before unlocking: an XR body released mid-hover would fall and drag
	# the origin below the floor.
	_place_player_at_height(0.0)
	_lock_player(false)
	if _katana:
		_katana.freeze = false
	# The grab path already holds it; the skip path still needs the grant.
	if _katana and not _katana.is_held():
		_grant_katana()
	GameEvents.log_event("run_intro_finished", {"skipped": _t < DESCENT_SEC * 0.85})
	finished.emit()


func _place_player_at_height(hover: float) -> void:
	_player.global_position = Vector3(_spawn_pos.x, _spawn_pos.y + hover, _spawn_pos.z)
	_player.rotation = Vector3(0.0, _spawn_yaw, 0.0)
	if _shadow:
		_shadow.global_position = Vector3(_spawn_pos.x, _ground_y + 0.015, _spawn_pos.z)
		_shadow.rotation.y = _spawn_yaw


func _hide_katana() -> void:
	if _player is DesktopPlayer:
		var dp := _player as DesktopPlayer
		dp.left_holder.release()
		dp.holder.release()
	elif _player is XRPlayer:
		var xr := _player as XRPlayer
		xr.left_holder.release()
		xr.right_holder.release()
	if _katana:
		_katana.visible = false
		_katana.linear_velocity = Vector3.ZERO
		_katana.angular_velocity = Vector3.ZERO


func _grant_katana() -> void:
	if _katana == null or _player == null:
		return
	_katana.visible = true
	if _player is DesktopPlayer:
		(_player as DesktopPlayer).take_weapon(_katana)
	elif _player is XRPlayer:
		var xr := _player as XRPlayer
		if xr.right_holder:
			xr.right_holder.grab(_katana)
			_katana.snap_to_hand()


## The offering pose: chest height, half a metre before the player, blade
## pointing down, turning slowly until taken.
func _float_pose() -> Transform3D:
	var fwd := (Basis(Vector3.UP, _spawn_yaw) * Vector3.FORWARD)
	fwd.y = 0.0
	if fwd.length_squared() < 1e-4:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var pos := _spawn_pos + fwd * 0.55 + Vector3.UP * (_ground_y + 1.25 + sin(_t * 1.8) * 0.03)
	return Transform3D(Basis(Vector3.UP, _t * 0.55) * _float_basis, pos)


func _begin_float() -> void:
	_waiting_grab = true
	if _katana:
		_float_basis = _katana.global_basis.orthonormalized()
		_katana.freeze = true
		_katana.linear_velocity = Vector3.ZERO
		_katana.angular_velocity = Vector3.ZERO
	GameEvents.log_event("katana_offered", {})


func _float_katana() -> void:
	if _katana == null:
		return
	_katana.global_transform = _float_pose()


func _reveal_katana(amount: float) -> void:
	if _katana == null:
		return
	_katana.visible = amount > 0.02
	if _waiting_grab or amount >= 0.98:
		return
	# The blade flies in to the offering spot while it materializes.
	_katana.global_transform = _katana.global_transform.interpolate_with(
		_float_pose(), clampf(amount * 1.5, 0.0, 1.0))


func _lock_player(locked: bool) -> void:
	if _player is DesktopPlayer:
		(_player as DesktopPlayer).movement_locked = locked
	elif _player is XRPlayer:
		(_player as XRPlayer).set_rig_locked(locked)
	_player.set_meta("run_intro_locked", locked)


func _set_seal_glow(v: float) -> void:
	if _seal_material:
		_seal_material.set_shader_parameter("intro_seal_glow", v)


func _set_ripple(radius: float, gain: float) -> void:
	RenderingServer.global_shader_parameter_set("intro_ripple_radius", radius)
	RenderingServer.global_shader_parameter_set("intro_ripple_gain", gain)


func _pulse_lightning() -> void:
	if _lightning:
		_lightning.trigger_strike(0.06)
	else:
		RenderingServer.global_shader_parameter_set("storm_flash", 0.85)
		RenderingServer.global_shader_parameter_set("storm_flash_dir", Vector2(0.08, -0.98))


func _update_shadow(progress: float) -> void:
	if _shadow == null:
		return
	var mat := _shadow.material_override as ShaderMaterial
	mat.set_shader_parameter("shadow_strength", lerpf(0.35, 0.88, progress))


func _update_petals(delta: float, progress: float) -> void:
	if _player == null:
		return
	var center := _player.global_position + Vector3(0.0, 0.55 + progress * 0.15, 0.0)
	var orbit_r := lerpf(1.35, 0.85, progress)
	var spin := _t * 1.35
	for i in _petals.size():
		var ang := _petal_angles[i] + spin + float(i) * 0.4
		var bob := sin(_t * 2.2 + float(i)) * 0.12
		var p := _petals[i]
		p.global_position = center + Vector3(cos(ang) * orbit_r, bob, sin(ang) * orbit_r)
		p.look_at(center + Vector3(0.0, 0.2, 0.0), Vector3.UP)
		p.rotation.z += delta * 2.6


func _build_visuals() -> void:
	_rng.randomize()
	_shadow = MeshInstance3D.new()
	_shadow.name = "SeizaShadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.35, 1.35)
	_shadow.mesh = plane
	_shadow.rotation.x = -PI * 0.5
	var sm := ShaderMaterial.new()
	sm.shader = SHADOW_SHADER
	sm.render_priority = 2
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.22)
	var mat := ShaderMaterial.new()
	mat.shader = PETAL_SHADER
	mat.render_priority = 4
	_petal_angles.resize(PETAL_COUNT)
	for i in PETAL_COUNT:
		var petal := MeshInstance3D.new()
		petal.mesh = mesh
		var pm := mat.duplicate() as ShaderMaterial
		pm.set_shader_parameter("petal_color", Color(1.0, 0.24, 0.58))
		pm.set_shader_parameter("rim_color", Color(1.1, 0.48, 0.9))
		petal.material_override = pm
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_petal_angles[i] = _rng.randf() * TAU
		_petals.append(petal)
		add_child(petal)
