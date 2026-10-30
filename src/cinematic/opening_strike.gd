class_name OpeningStrike
extends Node3D
## Opening strike (D11, docs/OPENING_STRIKE.md): a three-second cinematic after the
## boot splash and before the seiza intro. First person, a katana runs through six
## yōkai in the real WorldGen forest. Each of the five first cuts is a clean edge
## cut that goes through Yokai.receive_hit with the Kirisute offer, the same data a
## live blade sends, so the body splits along the blade's plane. The sixth is the
## tier-5 finisher (Hanadachi): its school colour builds into a full white screen,
## which hands over to the intro.
##
## Like the boot splash, the stage renders into a SubViewport shown on a board: a
## fixed VR panel in front of the headset (the XR rig is locked, never moved), the
## whole window on desktop. The world is a pure function of the cinematic clock, so
## any moment can be checked. A cut's hit-stop slows this clock only, never
## Engine.time_scale. Sounds sit at the viewer (the stage has its own space).

signal finished

## Clock (s) at which the white starts and is full; the cinematic ends at FINISH_AT.
const WHITE_AT := 2.98
const WHITE_FULL_AT := 3.22
const FINISH_AT := 3.32
## A skip fades to white this fast, then hands over.
const SKIP_FADE := 0.4
## Local hit-stop: after a cut the clock runs at SLOW_SCALE for SLOW_SECONDS real seconds.
const SLOW_SCALE := 0.12
const SLOW_SECONDS := 0.07
## The blade sweeps SWEEP_TRAVEL metres across its contact in 2 × SWEEP_HALF seconds (9 m/s,
## above the Kirisute minimum of 8 m/s).
const SWEEP_HALF := 0.05
const SWEEP_TRAVEL := 0.9
## Hilt to contact along the blade (m).
const HILT_REACH := 0.45
const CUT_SPEED := 9.0
const CHEST_HEIGHT := 1.1
const EYE_HEIGHT := 1.5
const FOV_BASE := 58.0
const FOV_DASH := 12.0
## The camera dashes to the next station and stops this long before the contact.
const DASH_LEAD := 0.1
## The camera holds this long after a contact before the next dash.
const DASH_OUT := 0.06
## Glade centre (x, z) in the forest: the run's spawn clearing at the origin.
const GLADE := Vector2.ZERO
## Scales the cut layout (yōkai and stations) into the run's spawn clearing (radius ~5.2 m),
## the only spot of the default profile found clear of trunks (see docs/OPENING_STRIKE.md, "Lokacja").
const SPACING := 0.7
## The cinematic's cut pieces glow this much hotter than a run's cut: it is the close look.
const CUT_GLOW_BOOST := 1.6
const START_STATION := Vector2(-0.4, 2.4)
const START_LOOK := Vector2(-1.1, -3.2)
## The camera pushes in this far after the last cut, into the white.
const FINAL_PUSH := 0.55
const KATANA_SCENE := preload("res://scenes/weapons/katana.tscn")

## The six cuts, in order. "at" is the clock of the blade's contact. "target" and
## "station" are ground positions (x, z) from the glade centre: the camera stands at
## the station and looks at the target. "plane" (the cut plane's normal) and "axis"
## (the blade) are in view space (x right, y up, -z forward), so each cut reads the
## same from its station. The motion follows from them (see cut_frame).
const CUTS := [
	{"at": 0.42, "element": Elements.SAKURA, "target": Vector2(-1.1, -3.2), "station": Vector2(-0.4, 0.5),
		"plane": Vector3(0.71, 0.71, 0.0), "axis": Vector3(-0.5, 0.5, -0.7)},
	{"at": 0.86, "element": Elements.STORM, "target": Vector2(1.7, -4.0), "station": Vector2(2.2, -1.2),
		"plane": Vector3(0.0, 1.0, 0.0), "axis": Vector3(0.0, 0.0, -1.0)},
	{"at": 1.28, "element": Elements.INK, "target": Vector2(-2.9, -4.9), "station": Vector2(-2.0, -1.6),
		"plane": Vector3(-0.71, 0.71, 0.0), "axis": Vector3(0.5, 0.5, -0.7)},
	{"at": 1.70, "element": Elements.SHADOW, "target": Vector2(2.8, -6.2), "station": Vector2(1.5, -3.1),
		"plane": Vector3(1.0, 0.0, 0.0), "axis": Vector3(0.0, 0.6, -0.8)},
	{"at": 2.12, "element": Elements.STORM, "target": Vector2(-0.6, -6.8), "station": Vector2(0.9, -4.6),
		"plane": Vector3(0.71, -0.71, 0.0), "axis": Vector3(0.5, 0.5, -0.7)},
	{"at": 2.62, "element": Elements.SAKURA, "target": Vector2(-1.2, -4.4), "station": Vector2(-0.7, -1.3),
		"plane": Vector3(0.5, 0.85, 0.0), "axis": Vector3(-0.6, 0.4, -0.7)},
]

var active := false

var _player: Node3D
var _camera: Camera3D
var _clock := 0.0
var _slow_left := 0.0
var _next_cut := 0
var _splits := 0
var _skip_t := -1.0
var _xr_was_down := false
var _saved_cull_mask := 0
var _saved_environment: Environment
var _saved_attributes: CameraAttributes
var _void_env: Environment

var _viewport: SubViewport
var _stage: Node3D
var _stage_camera: Camera3D
var _forest: ForestWorld
var _katana: HeldWeapon
var _yokai: Array[Yokai] = []
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _white: ColorRect
var _boosted := {}
var _board: MeshInstance3D
var _board_mat: StandardMaterial3D
var _quad: QuadMesh


func _ready() -> void:
	visible = false
	set_process(false)
	_board_mat = StandardMaterial3D.new()
	_board_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_board_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad = QuadMesh.new()
	_board = MeshInstance3D.new()
	_board.mesh = _quad
	_board.material_override = _board_mat
	_board.layers = RunSplash.SPLASH_LAYER
	add_child(_board)
	_void_env = Environment.new()
	_void_env.background_mode = Environment.BG_COLOR
	_void_env.background_color = Color.BLACK
	_void_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_void_env.ambient_light_color = Color.BLACK
	_void_env.ambient_light_energy = 0.0


func setup(player: Node3D) -> void:
	_player = player


func is_active() -> bool:
	return active


## Builds the stage (forest, yōkai, katana, camera) without starting it. The run calls
## this while the title plate plays, so the forest build is not felt at the hand-over.
func prepare() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.size = RunSplash.VIDEO_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_stage.name = "Stage"
	_viewport.add_child(_stage)
	_board_mat.albedo_texture = _viewport.get_texture()
	_build_stage()
	_build_overlays()


## Time elapsed on the cinematic's clock (s): the timeline position, not wall time.
func elapsed() -> float:
	return _clock


## How many cuts so far split a yōkai (Kirisute through Yokai.receive_hit).
func split_count() -> int:
	return _splits


## The white overlay's coverage, 0 (scene) to 1 (full white). Once the stage is freed,
## the coverage it ended on.
func white_level() -> float:
	return _white.color.a if _white else _final_white


var _final_white := 0.0


## The SubViewport whose own world holds the stage, its cuts' pieces and effects; null
## when the stage is not built.
func stage_root() -> Node:
	return _viewport


func stage_yokai() -> Array[Yokai]:
	return _yokai


func stage_camera() -> Camera3D:
	return _stage_camera


func forest() -> ForestWorld:
	return _forest


func start() -> void:
	if active or _player == null:
		return
	prepare()
	active = true
	_clock = 0.0
	_slow_left = 0.0
	_next_cut = 0
	_skip_t = -1.0
	_camera = get_viewport().get_camera_3d()
	_place_board()
	_hide_world()
	_mute_world_audio(true)
	_lock_rig(true)
	_xr_was_down = _xr_down()
	visible = true
	set_process(true)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_splits = 0
	_boosted.clear()
	GameEvents.log_event("opening_strike_started", {})
	_apply_pose(0.0)
	# The splash's black veil (still fading as this starts) becomes the cinematic's fade-in.


## Ends the cinematic with a quick fade to white, then the intro starts.
func skip() -> void:
	if not active or _skip_t >= 0.0:
		return
	_skip_t = 0.0
	GameEvents.log_event("opening_strike_skipped", {"clock": snappedf(_clock, 0.01)})


func _process(delta: float) -> void:
	if not active:
		return
	var down := _xr_down()
	if down and not _xr_was_down:
		skip()
	_xr_was_down = down
	advance(delta)


func _input(event: InputEvent) -> void:
	if not active:
		return
	var pressed := false
	if event is InputEventMouseButton:
		pressed = event.is_pressed()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		pressed = (event as InputEventKey).physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]
	if pressed:
		skip()
		get_viewport().set_input_as_handled()


## One step of the cinematic by [param delta] real seconds. Public so tests can step it.
func advance(delta: float) -> void:
	if not active:
		return
	if _skip_t >= 0.0:
		_skip_t += delta
		if _skip_t >= SKIP_FADE:
			_finish(true)
			return
	else:
		var rate := 1.0
		if _slow_left > 0.0:
			_slow_left = maxf(_slow_left - delta, 0.0)
			rate = SLOW_SCALE
		_clock += delta * rate
		while _next_cut < CUTS.size() and _clock >= float(CUTS[_next_cut].at):
			_strike(_next_cut)
			_next_cut += 1
		if _clock >= FINISH_AT:
			_finish(false)
			return
	_apply_pose(_clock)


## Camera pose and field of view at clock [param t]: dash to the next station, hold for
## the contact, shake that dies after it. Pure in t.
func camera_at(t: float) -> Dictionary:
	var from := START_STATION
	var look_from := START_LOOK
	var prev_end := 0.0
	for i in CUTS.size():
		var cut: Dictionary = CUTS[i]
		var at: float = cut.at
		var dash_end: float = at - DASH_LEAD
		var station: Vector2 = cut.station
		var target: Vector2 = cut.target
		if t < dash_end:
			var u := clampf((t - prev_end) / maxf(dash_end - prev_end, 0.001), 0.0, 1.0)
			var s := 1.0 - pow(1.0 - u, 3.0)
			return _shot(_eye_at(from.lerp(station, s)), _point_at(look_from.lerp(target, s)), t,
				FOV_DASH * sin(PI * s))
		if t < at + DASH_OUT:
			var push := 0.12 * smoothstep(dash_end, at + DASH_OUT, t)
			return _shot(_eye_at(station), _point_at(target), t, 0.0, push, at)
		from = station
		look_from = target
		prev_end = at + DASH_OUT
	# After the finisher: a slow push into the white, still shaking from the last cut.
	var last: Dictionary = CUTS[CUTS.size() - 1]
	var last_at: float = last.at
	var push_in := FINAL_PUSH * smoothstep(last_at + DASH_OUT, FINISH_AT, t)
	return _shot(_eye_at(last.station), _point_at(last.target), t, 0.0, 0.12 + push_in, last_at)


## Katana pose at clock [param t]: a guard in front of the camera, and a sweep through
## each contact. Blended in and out, so the blade never snaps.
func katana_at(t: float) -> Transform3D:
	var cam: Transform3D = camera_at(t).pose
	var guard := _guard_pose(cam)
	for i in CUTS.size():
		var w := _sweep_weight(t - float(CUTS[i].at))
		if w > 0.0:
			var f := cut_frame(i)
			var s := clampf((t - (float(CUTS[i].at) - SWEEP_HALF)) / (2.0 * SWEEP_HALF), 0.0, 1.0)
			var origin: Vector3 = f.point - f.axis * HILT_REACH + f.motion * (s - 0.5) * SWEEP_TRAVEL
			var sweep := Transform3D(_blade_basis(f.axis, f.motion), origin)
			return guard.interpolate_with(sweep, w)
	return guard


## The plane and motion of cut [param i], in world space. The motion is the edge's
## lead (basis.y is -motion, so the edge leads), and the cut plane's normal is
## motion × axis: the same numbers KirisuteCut.plane_normal uses.
func cut_frame(i: int) -> Dictionary:
	var cut: Dictionary = CUTS[i]
	var cam: Transform3D = camera_at(float(cut.at)).pose
	var plane: Vector3 = cut.plane
	var view_axis: Vector3 = cut.axis
	var n := (cam.basis * plane).normalized()
	var a0 := cam.basis * view_axis
	var axis := (a0 - n * a0.dot(n)).normalized()
	var motion := axis.cross(n).normalized()
	var target: Vector2 = cut.target
	return {"point": _point_at(target), "motion": motion, "axis": axis, "normal": n}


func _sweep_weight(dt: float) -> float:
	return smoothstep(-SWEEP_HALF * 3.2, -SWEEP_HALF, dt) * (1.0 - smoothstep(SWEEP_HALF, SWEEP_HALF * 4.0, dt))


func _guard_pose(cam: Transform3D) -> Transform3D:
	var origin := cam.origin + cam.basis * Vector3(0.24, -0.27, -0.5)
	var z := -(cam.basis * Vector3(-0.2, 0.4, -1.0)).normalized()
	var y := (cam.basis.y - z * cam.basis.y.dot(z)).normalized()
	var x := y.cross(z)
	return Transform3D(Basis(x, y, z), origin)


## Blade basis: local -Z along the blade (hilt to tip), local -Y along the motion, so
## the edge (basis × -spine = -Y) leads the cut.
func _blade_basis(axis: Vector3, motion: Vector3) -> Basis:
	var z := -axis
	var y := -motion
	var x := y.cross(z)
	return Basis(x, y, z)


## Trail of the blade's edge through the current sweep: a fading ribbon, from the
## contact's sweep start up to the blade now.
func _update_trail(t: float) -> void:
	_trail_mesh.clear_surfaces()
	for i in CUTS.size():
		var at: float = CUTS[i].at
		var dt := t - at
		if dt < -SWEEP_HALF or dt > SWEEP_HALF + 0.04:
			continue
		var f := cut_frame(i)
		var col := Elements.color(CUTS[i].element) * 2.2
		var end := clampf(dt, -SWEEP_HALF, SWEEP_HALF)
		var steps := 8
		_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for k in steps + 1:
			var tk := lerpf(-SWEEP_HALF, end, float(k) / steps)
			var s := clampf((tk + SWEEP_HALF) / (2.0 * SWEEP_HALF), 0.0, 1.0)
			var origin: Vector3 = f.point - f.axis * HILT_REACH + f.motion * (s - 0.5) * SWEEP_TRAVEL
			var fade := float(k) / steps
			_trail_mesh.surface_set_color(Color(col.r, col.g, col.b, fade))
			_trail_mesh.surface_add_vertex(origin + f.axis * 0.22)
			_trail_mesh.surface_set_color(Color(col.r, col.g, col.b, fade))
			_trail_mesh.surface_add_vertex(origin + f.axis * 0.76)
		_trail_mesh.surface_end()


## One cut: the real Kirisute path. The yōkai's chest is hit with the blade's data,
## the edge leading (alignment 1), at 9 m/s, with the Kirisute offer set.
func _strike(i: int) -> void:
	var cut: Dictionary = CUTS[i]
	var f := cut_frame(i)
	var yokai: Yokai = _yokai[i]
	var part := yokai.parts.get("chest") as RagdollPart
	var hit := {
		"attacker": "katana",
		"element": cut.element,
		"part": "chest",
		"zone": "body",
		"speed": CUT_SPEED,
		"strike": "edge",
		"edge_alignment": 1.0,
		"base_damage": 200.0,
		"point": f.point,
		"direction": f.motion,
		"power": 1.0,
		"impulse": 6.0,
		"knockback": f.motion * 6.0,
		"kirisute_offer": true,
		"blade_axis": f.axis,
	}
	var out := yokai.receive_hit(part, hit)
	if bool(out.get("kirisute", false)):
		_splits += 1
		_boost_pieces()
	# The finisher bursts in its school's colour at the contact (the game's own firework).
	if i == CUTS.size() - 1:
		ElementFirework.spawn(_viewport, f.point, cut.element, 1.4)
	_slow_left = SLOW_SECONDS
	Sfx.play_at("swing", _sound_point(), -4.0, 40.0, 1.0 + 0.04 * float(i))
	Sfx.play_at("cut", _sound_point(), -3.0, 40.0)
	GameEvents.log_event("opening_strike_cut", {"index": i, "element": cut.element,
		"split": bool(out.get("kirisute", false))})


## The new pieces of this stage start at CUT_GLOW_BOOST times a run's cut glow. Only
## pieces not seen before are touched, so each split is boosted once.
func _boost_pieces() -> void:
	for c in _viewport.get_children():
		if c is KirisuteChunk and not _boosted.has(c):
			_boosted[c] = true
			var chunk := c as KirisuteChunk
			chunk.hot_energy *= CUT_GLOW_BOOST
			if chunk.cap_material:
				chunk.cap_material.emission_energy_multiplier = chunk.hot_energy


func _apply_pose(t: float) -> void:
	if _stage_camera == null:
		return
	var shot := camera_at(t)
	_stage_camera.global_transform = shot.pose
	_stage_camera.fov = shot.fov
	_katana.global_transform = katana_at(t)
	_update_trail(t)
	_update_overlays(t)


func _update_overlays(t: float) -> void:
	var white := smoothstep(WHITE_AT, WHITE_FULL_AT, t)
	if _skip_t >= 0.0:
		white = maxf(white, clampf(_skip_t / SKIP_FADE, 0.0, 1.0))
	_white.color.a = white


## One camera shot: the eye and look points, the shake of the moment, the fov.
## [param cut_at] is the contact the shake comes from (-1 for none, during a dash).
func _shot(eye: Vector3, look: Vector3, t: float, fov_kick: float, push := 0.0, cut_at := -1.0) -> Dictionary:
	var pos := eye + (look - eye).normalized() * push
	var shake := 0.0
	if cut_at >= 0.0:
		shake = exp(-maxf(t - cut_at, 0.0) * 14.0) * 0.03
	pos += Vector3(sin(t * 67.0) * shake, sin(t * 45.0 + 1.0) * shake, 0.0)
	var basis := Basis.looking_at(look - pos, Vector3.UP)
	return {"pose": Transform3D(basis, pos), "fov": FOV_BASE + fov_kick - push * 2.0}


func _ground_at(v: Vector2) -> Vector3:
	var x := GLADE.x + v.x * SPACING
	var z := GLADE.y + v.y * SPACING
	return Vector3(x, _forest.height_at(x, z) if _forest else 0.0, z)


func _eye_at(v: Vector2) -> Vector3:
	return _ground_at(v) + Vector3(0.0, EYE_HEIGHT, 0.0)


func _point_at(v: Vector2) -> Vector3:
	return _ground_at(v) + Vector3(0.0, CHEST_HEIGHT, 0.0)


## The cut's contact point: the target's chest.
func _target_point(i: int) -> Vector3:
	return _point_at(CUTS[i].target)


## Where the cinematic's sounds sit: the viewer, so the stage's own space does not
## pan them (the stage is a separate world).
func _sound_point() -> Vector3:
	return _camera.global_position if _camera else Vector3.ZERO


func _build_stage() -> void:
	var profile := WorldGenProfile.load_active()
	var env := Environment.new()
	WorldGenLook.apply_fog(env, profile)
	WorldGenLook.apply_light(env, profile)
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-38.0), 0.0)
	WorldGenLook.apply_moon(moon, profile)
	_stage.add_child(moon)

	var follow := Node3D.new()
	follow.position = Vector3(GLADE.x, 0.0, GLADE.y)
	_stage.add_child(follow)
	_forest = ForestWorld.new()
	_forest.profile = profile
	_stage.add_child(_forest)
	_forest.moon_direction = moon.global_basis.z.normalized()
	_forest.setup(follow)

	_stage_camera = Camera3D.new()
	_stage_camera.name = "CinematicCamera"
	_stage_camera.near = 0.05
	_stage_camera.far = 260.0
	_stage_camera.current = true
	_stage.add_child(_stage_camera)

	for i in CUTS.size():
		_spawn_yokai(i)

	var katana := KATANA_SCENE.instantiate() as HeldWeapon
	katana.freeze = true
	katana.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	katana.collision_layer = 0
	katana.collision_mask = 0
	_stage.add_child(katana)
	katana.set_physics_process(false)
	_katana = katana

	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = mat
	_stage.add_child(_trail)


## A yōkai standing at cut [param i]'s target, facing its station. Its brain is off:
## the cinematic places it and the cut does the rest.
func _spawn_yokai(i: int) -> void:
	var cut: Dictionary = CUTS[i]
	var y := Yokai.new()
	y.configure_kind(Yokai.Kind.SWARM, Elements.NONE, 900.0)
	y.ground_probe = _forest.height_at
	_stage.add_child(y)
	var at := _ground_at(cut.target)
	var toward := _ground_at(cut.station) - at
	y.place_at(at, atan2(toward.x, toward.z))
	if y.brain:
		y.brain.set_physics_process(false)
	# A statue until its cut: frozen where the cinematic put it. On a slope the free
	# ragdoll slides off its contact, and the cut plane would miss the body.
	for part in y.parts.values():
		(part as RigidBody3D).freeze = true
	y.dissolve_finished.connect(func(body: Yokai) -> void: body.queue_free())
	_yokai.append(y)


func _build_overlays() -> void:
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_white)


func _finish(skipped: bool) -> void:
	active = false
	set_process(false)
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_restore_world()
	_mute_world_audio(false)
	_lock_rig(false)
	GameEvents.log_event("opening_strike_finished", {"skipped": skipped, "splits": _splits})
	# The handover is always on full white, a skipped one included.
	if _white:
		_white.color.a = 1.0
	_veil(Color.WHITE)
	_clear_stage()
	finished.emit()


## Frees the stage world (forest, yōkai, katana): nothing of the cinematic stays in the
## run's physics or draw counts once it is over. prepare() builds it again.
func _clear_stage() -> void:
	_final_white = white_level()
	_board_mat.albedo_texture = null
	if _viewport:
		_viewport.queue_free()
	_viewport = null
	_stage = null
	_stage_camera = null
	_forest = null
	_katana = null
	_trail = null
	_trail_mesh = null
	_white = null
	_yokai.clear()


## Places the board BOARD_DISTANCE ahead of the camera, at eye height, facing it.
## Only yaw is taken from the head, so the horizon stays level.
func _place_board() -> void:
	var eye: Vector3
	var forward: Vector3
	if _camera:
		eye = _camera.global_position
		forward = -_camera.global_basis.z
	else:
		eye = _player.global_position + Vector3(0.0, 1.6, 0.0)
		forward = -_player.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), eye + forward * RunSplash.BOARD_DISTANCE)
	_quad.size = _board_size()


## Desktop: the board covers the window. VR and any other rig: the fixed VR panel.
func _board_size() -> Vector2:
	var width := RunSplash.VR_BOARD_WIDTH
	if _player is DesktopPlayer and _camera:
		var view := _camera.get_viewport().get_visible_rect().size
		var view_aspect := view.x / view.y
		var span := 2.0 * RunSplash.BOARD_DISTANCE * tan(deg_to_rad(_camera.fov) * 0.5)
		var frame_w := span * view_aspect if _camera.keep_aspect == Camera3D.KEEP_HEIGHT else span
		var frame_h := frame_w / view_aspect
		width = minf(frame_w, frame_h * RunSplash.VIDEO_ASPECT)
	return Vector2(width, width / RunSplash.VIDEO_ASPECT)


func _hide_world() -> void:
	if _camera == null:
		return
	_saved_cull_mask = _camera.cull_mask
	_saved_environment = _camera.environment
	_saved_attributes = _camera.attributes
	_camera.cull_mask = RunSplash.SPLASH_LAYER
	_camera.environment = _void_env
	_camera.attributes = null


func _restore_world() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.cull_mask = _saved_cull_mask
	_camera.environment = _saved_environment
	_camera.attributes = _saved_attributes


## The Ambience and World buses are silent while the cinematic plays, as under the splash.
func _mute_world_audio(muted: bool) -> void:
	for bus in [Sfx.AMBIENCE_BUS, Sfx.WORLD_BUS]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_mute(idx, muted)


## A veil in [param color] fades out over the hand-over, so the next scene comes up from it.
func _veil(color: Color) -> void:
	RunSplash.fade_veil(_camera, color)


func _lock_rig(locked: bool) -> void:
	if _player is DesktopPlayer:
		(_player as DesktopPlayer).movement_locked = locked
	elif _player is XRPlayer:
		(_player as XRPlayer).set_rig_locked(locked)


func _xr_down() -> bool:
	var xr := _player as XRPlayer
	if xr == null:
		return false
	for c in [xr.left_controller, xr.right_controller]:
		if c and (c.is_button_pressed("ax_button") or c.get_float("trigger") > RunSplash.TRIGGER_THRESHOLD):
			return true
	return false


func _exit_tree() -> void:
	if active:
		_mute_world_audio(false)
