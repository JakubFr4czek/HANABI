class_name RunIntro
extends Node
## Run opening: seiza levitation, petal swirl, seal glow, lightning ripple,
## katana materialize (docs/GDD.md §9, NIGHT_PLAN.md §5).

signal finished

const PETAL_SHADER := preload("res://src/shaders/sakura_petal.gdshader")
const SHADOW_SHADER := preload("res://src/shaders/seiza_shadow.gdshader")
const AIR_STEP_SHADER := preload("res://src/shaders/air_step.gdshader")

const HOVER_HEIGHT := 0.78
const DESCENT_SEC := 3.1
const PETAL_COUNT := 18
## Steps the player takes down the air during the descent, and how long each
## print's ripple lives.
const AIR_STEPS := 6
const AIR_STEP_LIFE := 0.9
## The offered katana's soft light: blade emission and a small lamp.
const GLOW_COLOR := Color(0.72, 0.84, 1.0)
const GLOW_PEAK := 0.9
const GLOW_LIGHT_ENERGY := 0.55

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
## Movement is handed back at touchdown: the player may walk around (and
## walk up to the katana) while the run itself still waits for the grab.
var _movement_unlocked := false
var _float_basis := Basis.IDENTITY
var _shadow: MeshInstance3D
var _petals: Array[MeshInstance3D] = []
var _petal_angles: PackedFloat32Array
var _rng := RandomNumberGenerator.new()
var _meditation_hand := Vector3(0.02, -0.38, -0.22)
var _petal_fade := 1.0
var _air_steps: Array[MeshInstance3D] = []
var _air_step_age: PackedFloat32Array
var _steps_taken := 0
var _katana_mats: Array[ShaderMaterial] = []
var _glow_light: OmniLight3D
var _glow := 0.0
var _glow_tween: Tween


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
	_movement_unlocked = false
	_ripple_t = 0.0
	_katana_reveal = 0.0
	_petal_fade = 1.0
	_steps_taken = 0
	for st in _air_steps:
		st.visible = false
	_set_ripple(0.0, 0.0)
	_set_seal_glow(0.35)
	_hide_katana()
	_lock_player(true)
	_player.rotation = Vector3(0.0, _spawn_yaw, 0.0)
	_place_player_at_height(HOVER_HEIGHT)
	if _shadow:
		_shadow.visible = true
		(_shadow.material_override as ShaderMaterial).set_shader_parameter("shadow_strength", 0.92)
	for p in _petals:
		p.visible = true
		p.scale = Vector3.ONE
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
		# Each step lands where the feet are now, alternating feet, as if
		# walking down an invisible stair.
		var due := int(floor(progress * float(AIR_STEPS) + 0.35))
		if due > _steps_taken and _steps_taken < AIR_STEPS:
			_take_air_step(height)
		if _player is DesktopPlayer:
			var dp := _player as DesktopPlayer
			dp.hand_offset = dp.hand_offset.lerp(_meditation_hand, real_delta * 4.5)
		if progress >= 1.0:
			_touchdown()
	else:
		_step_post_touchdown(real_delta)
	_update_air_steps(real_delta)


func _touchdown() -> void:
	_descent_done = true
	_place_player_at_height(0.0)
	# Feet are on the ground: hand movement back. The run still starts only
	# when the katana is taken, but the player is not frozen in place until
	# then — they can walk up to the blade (or look around) first.
	_movement_unlocked = true
	_lock_player(false)
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
	_katana_reveal = minf(_katana_reveal + delta * 1.4, 1.0)
	_reveal_katana(_katana_reveal)
	_scatter_petals(delta)
	if _waiting_grab:
		_float_katana()
		if _katana and _katana.is_held():
			_finish_intro()
	elif _katana_reveal >= 1.0:
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
	if not _movement_unlocked:
		# Land before unlocking: an XR body released mid-hover would fall and
		# drag the origin below the floor. (After touchdown the player is
		# already free and may have walked off — never yank them back.)
		_place_player_at_height(0.0)
		_lock_player(false)
	for st in _air_steps:
		st.visible = false
	if _katana:
		_katana.freeze = false
	_fade_glow(0.0, 0.8)
	# The grab path already holds it; the skip path still needs the grant.
	if _katana and not _katana.is_held():
		_grant_katana()
	GameEvents.log_event("run_intro_finished", {"skipped": _t < DESCENT_SEC * 0.85})
	finished.emit()


func _place_player_at_height(hover: float) -> void:
	# Position only: rewriting the rig's yaw every physics tick fought the
	# headset/snap-turn and made the camera judder through the whole descent.
	_player.global_position = Vector3(_spawn_pos.x, _spawn_pos.y + hover, _spawn_pos.z)
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
		# Parked, frozen, at the offering spot for the whole descent: left
		# to physics it fell to the ground unseen and then rose back up.
		_katana.visible = false
		_katana.freeze = true
		_katana.linear_velocity = Vector3.ZERO
		_katana.angular_velocity = Vector3.ZERO
		_float_basis = _offer_basis()
		_katana.global_transform = _float_pose()
	_set_glow(0.0)


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


## Lying across before the player, handle to the right hand, edge up, the
## point tipped a little up (blade along local -Z).
func _offer_basis() -> Basis:
	return Basis(Vector3.UP, _spawn_yaw + PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(8.0))


## The offering pose: chest height, half a metre before the player, swaying
## gently until taken (it no longer spins, so the handle stays at hand).
func _float_pose() -> Transform3D:
	var fwd := (Basis(Vector3.UP, _spawn_yaw) * Vector3.FORWARD)
	fwd.y = 0.0
	if fwd.length_squared() < 1e-4:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var pos := _spawn_pos + fwd * 0.55 + Vector3.UP * (_ground_y + 1.2 + sin(_t * 1.8) * 0.025)
	var sway := Basis(Vector3.UP, sin(_t * 0.7) * deg_to_rad(6.0)) * Basis(Vector3.FORWARD, sin(_t * 1.1) * deg_to_rad(3.0))
	return Transform3D(sway * _float_basis, pos)


func _begin_float() -> void:
	_waiting_grab = true
	if _katana:
		_katana.freeze = true
		_katana.linear_velocity = Vector3.ZERO
		_katana.angular_velocity = Vector3.ZERO
	GameEvents.log_event("katana_offered", {})


func _float_katana() -> void:
	if _katana == null:
		return
	_katana.global_transform = _float_pose()
	# A slow breath of light while it waits.
	_set_glow(GLOW_PEAK * (0.78 + 0.22 * sin(_t * 2.1)))


## The blade appears where it is offered and its soft light swells: no
## swirl, no fly-in.
func _reveal_katana(amount: float) -> void:
	if _katana == null:
		return
	_katana.visible = amount > 0.02
	if _waiting_grab:
		return
	_katana.global_transform = _float_pose()
	var e := amount * amount * (3.0 - 2.0 * amount)
	_set_glow(GLOW_PEAK * (0.3 + 1.1 * e) if amount < 1.0 else GLOW_PEAK)


func _katana_steel_materials() -> Array[ShaderMaterial]:
	if not _katana_mats.is_empty() or _katana == null:
		return _katana_mats
	for mi in _katana.find_children("*", "MeshInstance3D", true, false):
		var surf := mi as MeshInstance3D
		for si in surf.get_surface_override_material_count():
			var mat := surf.get_surface_override_material(si)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader \
					and String((mat as ShaderMaterial).shader.resource_path).ends_with("katana_steel.gdshader"):
				_katana_mats.append(mat)
	return _katana_mats


func _set_glow(v: float) -> void:
	_glow = v
	for m in _katana_steel_materials():
		m.set_shader_parameter("spirit_glow", v)
		m.set_shader_parameter("spirit_color", GLOW_COLOR)
	if _katana and _glow_light == null:
		_glow_light = OmniLight3D.new()
		_glow_light.name = "OfferingGlow"
		_glow_light.light_color = GLOW_COLOR
		_glow_light.omni_range = 1.6
		_glow_light.omni_attenuation = 1.6
		_glow_light.shadow_enabled = false
		_katana.add_child(_glow_light)
		_glow_light.position = Vector3(0.0, 0.0, -0.35)
	if _glow_light:
		_glow_light.light_energy = GLOW_LIGHT_ENERGY * v / GLOW_PEAK
		_glow_light.visible = v > 0.01


func _fade_glow(to: float, seconds: float) -> void:
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_method(_set_glow, _glow, to, seconds).set_trans(Tween.TRANS_SINE)


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


## At touchdown the petal swirl breaks: the petals drift outward and up and
## shrink away instead of circling the offered blade.
func _scatter_petals(delta: float) -> void:
	_petal_fade = maxf(_petal_fade - delta * 1.6, 0.0)
	var center := _player.global_position + Vector3(0.0, 0.7, 0.0) if _player else Vector3.ZERO
	for p in _petals:
		if not p.visible:
			continue
		var out := p.global_position - center
		out.y = 0.0
		p.global_position += (out.normalized() * 1.6 + Vector3.UP * 0.5) * delta
		p.rotation.z += delta * 3.5
		p.scale = Vector3.ONE * maxf(_petal_fade, 0.01)
		p.visible = _petal_fade > 0.0


func _feet_xz() -> Vector3:
	var cam := _player.get_viewport().get_camera_3d() if _player and _player.get_viewport() else null
	if _player is XRPlayer and cam:
		return Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	return Vector3(_player.global_position.x, 0.0, _player.global_position.z)


func _take_air_step(height: float) -> void:
	var i := _steps_taken % _air_steps.size()
	_steps_taken += 1
	var step := _air_steps[i]
	var side := -1.0 if _steps_taken % 2 == 1 else 1.0
	var facing := Basis(Vector3.UP, _spawn_yaw)
	var feet := _feet_xz() + facing * Vector3(0.11 * side, 0.0, -0.05)
	step.global_position = Vector3(feet.x, _spawn_pos.y + height + 0.02, feet.z)
	step.rotation = Vector3(-PI * 0.5, _spawn_yaw, 0.0)
	step.visible = true
	_air_step_age[i] = 0.0
	(step.material_override as ShaderMaterial).set_shader_parameter("progress", 0.0)
	# A soft chime per step, rising a little like walking down a scale.
	Sfx.play_at("soul_collect", step.global_position, -15.0, 3.0, 0.8 + 0.06 * float(_steps_taken))
	if _player is XRPlayer:
		var xr := _player as XRPlayer
		var ctrl := xr.left_controller if side < 0.0 else xr.right_controller
		if ctrl:
			ctrl.trigger_haptic_pulse("haptic", 0.0, 0.25, 0.05, 0.0)


func _update_air_steps(delta: float) -> void:
	for i in _air_steps.size():
		var step := _air_steps[i]
		if not step.visible:
			continue
		_air_step_age[i] += delta
		var prog := _air_step_age[i] / AIR_STEP_LIFE
		if prog >= 1.0:
			step.visible = false
			continue
		(step.material_override as ShaderMaterial).set_shader_parameter("progress", prog)


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

	var step_mesh := QuadMesh.new()
	step_mesh.size = Vector2(0.62, 0.62)
	_air_step_age.resize(AIR_STEPS)
	for i in AIR_STEPS:
		var step := MeshInstance3D.new()
		step.name = "AirStep%d" % i
		step.mesh = step_mesh
		var m := ShaderMaterial.new()
		m.shader = AIR_STEP_SHADER
		m.render_priority = 3
		step.material_override = m
		step.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		step.visible = false
		_air_steps.append(step)
		add_child(step)

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
