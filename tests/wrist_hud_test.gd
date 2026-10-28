extends Node
## The wrist readout (D14), on the real XR rig and in the real run scene.
## - Clearance: the ring and its text rows never sit in the hand mesh or the katana, at
##   the eye tilt limits and in several katana poses (the readout is a plate in the bracer
##   frame; any mesh vertex above it inside its footprint is clipping).
## - Gesture: shown only when the wrist is close to the eyes, its face turned to them and
##   in view; hysteresis at both edges; a 0.15 s fade; nothing drawn while hidden.
## - Ring: fill = HP share; colour teal -> amber -> red; pulse only when critical.
## - Figure: the white kcal figure has enough contrast over the fire's middle colour.
## - Kcal (run.tscn): rises with movement, the resting rate standing still, not in a pause,
##   and the desktop H key raises the readout.
## Run with:
##   godot --headless --path . res://tests/wrist_hud_test.tscn -- --desktop
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")
const KATANA_SCENE := preload("res://scenes/weapons/katana.tscn")
## How far above the plate a mesh vertex may still be inside its footprint before we call it a hit (m).
const CLEAR_MARGIN := 0.004

var failures := 0


func _ready() -> void:
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _clearance_and_gesture()
	await _ring_and_figure()
	await _kcal_in_run()


# --- Rig: placement, clearance, gesture ----------------------------------------------

func _clearance_and_gesture() -> void:
	var xr_player: XRPlayer = load("res://scenes/player/xr_player.tscn").instantiate()
	var start_xr := xr_player.get_node_or_null("StartXR")
	if start_xr:
		xr_player.remove_child(start_xr)
		start_xr.free()
	add_child(xr_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hud := DiegeticHud.new()
	add_child(hud)
	hud.setup(xr_player, null)
	await get_tree().physics_frame

	var ctrl := xr_player.left_controller
	var cam := xr_player.get_node("XROrigin3D/XRCamera3D") as Node3D
	_check("wrist HUD rides the left controller", hud.wrist_unit.get_parent() == ctrl)
	_check("eye tilt is capped (%.0f deg)" % DiegeticHud.MAX_FACE_TILT_DEG,
		DiegeticHud.MAX_FACE_TILT_DEG <= 10.0)

	var hand_meshes: Array[MeshInstance3D] = []
	for mi in ctrl.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == "mesh_Hand_Nails_low_L":
			hand_meshes.append(m)
	_check("XR hand model found for clearance measurement", not hand_meshes.is_empty())
	if hand_meshes.is_empty():
		xr_player.queue_free()
		return

	# Tilt sweep on the real hand: the readout's footprint must stay clear of the hand.
	# The vertices are read each time: the XR body moves while the test runs.
	for tilt_deg in [0.0, 10.0, -10.0]:
		hud.wrist_face.quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(tilt_deg))
		hud.wrist_face.position.y = absf(sin(deg_to_rad(tilt_deg))) * DiegeticHud.PLATE_SIZE.x * 0.57
		await get_tree().physics_frame
		var hits := _readout_hits(_world_vertices(hand_meshes), hud)
		_check("readout clears the hand at %.0f deg tilt (%d vertices in its footprint)" % [tilt_deg, hits],
			hits == 0)
	hud.wrist_face.quaternion = Quaternion.IDENTITY
	hud.wrist_face.position.y = 0.0
	# Control: the same check must see the hand when the readout sinks into it, so the zeros above are real.
	var base := hud.wrist_unit.position
	hud.wrist_unit.position = base + Vector3(0.0, -0.055, 0.0)
	await get_tree().physics_frame
	var sunk := _readout_hits(_world_vertices(hand_meshes), hud)
	hud.wrist_unit.position = base
	_check("control: the check sees the hand once the readout sinks into it (%d vertices)" % sunk, sunk > 0)

	# Katana in the off-hand, grip point on the controller origin, several poses.
	var katana: HeldWeapon = KATANA_SCENE.instantiate()
	katana.freeze = true
	add_child(katana)
	await get_tree().physics_frame
	var grip := Vector3(0.0, 0.0, 0.10)
	var poses := {
		"blade forward": Basis.IDENTITY,
		"blade up": Basis.from_euler(Vector3(deg_to_rad(80.0), 0.0, 0.0)),
		"blade down": Basis.from_euler(Vector3(deg_to_rad(-70.0), 0.0, 0.0)),
		"blade yawed right": Basis.from_euler(Vector3(0.0, deg_to_rad(45.0), 0.0)),
		"blade yawed left": Basis.from_euler(Vector3(0.0, deg_to_rad(-45.0), 0.0)),
		"blade rolled": Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(90.0))),
	}
	for pose_name in poses:
		var rot: Basis = poses[pose_name]
		katana.global_transform = ctrl.global_transform * Transform3D(rot, -(rot * grip))
		await get_tree().physics_frame
		var katana_verts := _world_vertices(_meshes_under(katana))
		var hits := _readout_hits(katana_verts, hud)
		_check("readout clears the katana, %s (%d vertices in its footprint)" % [pose_name, hits], hits == 0)
	# Control: a grip with the blade through the ring centre must be seen as a hit.
	katana.global_transform = ctrl.global_transform * Transform3D(Basis.IDENTITY, -grip + hud.wrist_unit.position)
	await get_tree().physics_frame
	var through := _readout_hits(_world_vertices(_meshes_under(katana)), hud)
	_check("control: the check sees the katana run through the readout (%d vertices)" % through, through > 0)
	katana.queue_free()

	# Gesture: a readout that is near, faces the eyes and is in view shows; the rest hides it.
	_place_readout(hud, cam, 0.25, 15.0)
	await _frames(20)
	_check("gesture: wrist close, face to the eyes, in view: readout shows", hud.wrist_face.visible and hud.ring.is_visible_in_tree())

	_place_readout(hud, cam, 0.6, 15.0)
	await _frames(20)
	_check("far from the eyes (60 cm): readout hidden, nothing drawn", not hud.wrist_face.visible and _drawn_under(hud) == 0)

	_place_readout(hud, cam, 0.25, 120.0)
	await _frames(20)
	_check("face turned away (120 deg): readout hidden", not hud.wrist_face.visible)

	# Hysteresis: visible at 0.30 m stays visible to 0.38 m; hidden at 0.38 m stays hidden.
	_place_readout(hud, cam, 0.30, 15.0)
	await _frames(20)
	_place_readout(hud, cam, 0.38, 15.0)
	await _frames(20)
	_check("hysteresis: shown at 30 cm still shows at 38 cm", hud.wrist_face.visible)
	_place_readout(hud, cam, 0.6, 15.0)
	await _frames(20)
	_place_readout(hud, cam, 0.38, 15.0)
	await _frames(20)
	_check("hysteresis: hidden at 60 cm stays hidden at 38 cm", not hud.wrist_face.visible)

	# Hysteresis on the angle: shown at 40 deg, still shown at 50 deg, hidden at 60 deg.
	_place_readout(hud, cam, 0.25, 40.0)
	await _frames(20)
	_place_readout(hud, cam, 0.25, 50.0)
	await _frames(20)
	var kept := hud.wrist_face.visible
	_place_readout(hud, cam, 0.25, 60.0)
	await _frames(20)
	_check("hysteresis: angle 40 -> 50 deg keeps it, 60 deg hides it (kept %s)" % kept, kept and not hud.wrist_face.visible)

	# Fade: half of the 0.15 s fade is half-presence.
	_place_readout(hud, cam, 0.25, 15.0)
	await _frames(1)
	var fade_half := 0.5 * DiegeticHud.FADE_SECONDS
	await _frames(int(round(fade_half * 90.0)) - 1)
	_check("fade: half-way through the 0.15 s fade the readout is about half shown (%.2f)" % hud._presence,
		absf(hud._presence - 0.5) < 0.12)
	await _frames(20)
	_check("fade: fully shown after the fade", absf(hud._presence - 1.0) < 0.001)

	# The readout is seen from the eyes: its face points at them, text upright.
	var face_dot := hud.wrist_unit.global_basis.y.dot((cam.global_position - hud.wrist_unit.global_position).normalized())
	_check("readout face points at the eyes (dot %.2f)" % face_dot, face_dot > 0.9)
	xr_player.queue_free()


## Places the readout's centre [param dist] metres from the eyes (down and to the left of
## the view), its face turned [param face_deg] off the eyes. The eyes are read live: the XR
## body sinks while the test runs.
func _place_readout(hud: DiegeticHud, cam: Node3D, dist: float, face_deg: float) -> void:
	var eye := cam.global_position
	var toward := (-cam.global_basis.z + cam.global_basis.x * 0.25 - Vector3.UP * 0.3).normalized()
	var centre := eye + toward * dist
	var to_eye := (eye - centre).normalized()
	var axis := to_eye.cross(Vector3.UP)
	if axis.length_squared() < 1e-6:
		axis = Vector3.RIGHT
	var face := to_eye.rotated(axis.normalized(), deg_to_rad(face_deg))
	var x := Vector3.RIGHT.cross(face)
	if x.length_squared() < 1e-6:
		x = Vector3.FORWARD.cross(face)
	x = x.normalized()
	var z := x.cross(face).normalized()
	hud.wrist_unit.global_transform = Transform3D(Basis(x, face, z), centre)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## Every mesh vertex in world space, for the given instances.
func _world_vertices(meshes: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var arrs := m.mesh.surface_get_arrays(s)
			for v in (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				out.append(m.global_transform * v)
	return out


func _meshes_under(root: Node) -> Array:
	var out: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


## Vertices (world space) that sit above the readout's plate inside its footprint.
## The footprint is the ring disc and the rows of text under it. The plate frame is the
## face's, so a vertex is "above" when its height in that frame is above the margin.
func _readout_hits(verts: PackedVector3Array, hud: DiegeticHud) -> int:
	var inv := hud.wrist_face.global_transform.affine_inverse()
	var hits := 0
	var disc := DiegeticHud.ELEMENT_RADIUS + 0.002
	for w in verts:
		var p := inv * w
		var in_ring := Vector2(p.x, p.z).length() <= disc
		var in_rows := absf(p.x) <= 0.024 and p.z >= 0.0 and p.z <= 0.066
		if (in_ring or in_rows) and p.y > -CLEAR_MARGIN:
			hits += 1
	return hits


## Readout nodes drawn right now (zero when hidden: the subtree is not rendered).
func _drawn_under(hud: DiegeticHud) -> int:
	var n := 0
	for c in hud.wrist_face.find_children("*", "VisualInstance3D", true, false):
		if (c as VisualInstance3D).is_visible_in_tree():
			n += 1
	return n


# --- Ring and figure -----------------------------------------------------------------

func _ring_and_figure() -> void:
	# Colour rule: teal when healthy, amber at half, red when critical.
	var full := DiegeticHud.hp_color(1.0)
	var half := DiegeticHud.hp_color(0.5)
	var low := DiegeticHud.hp_color(0.2)
	_check("ring colour at 100%% is teal (%s)" % [full], full.g > full.r and full.b > full.r and full.g > 0.7)
	_check("ring colour at 50%% is amber (%s)" % [half], half.r > 0.9 and half.g > 0.55 and half.g < 0.7 and half.b < 0.3)
	_check("ring colour at 20%% is red (%s)" % [low], low.r > 0.85 and low.g < 0.3 and low.b < 0.3)
	_check("colour runs smoothly: 75%% lies between amber and teal",
		DiegeticHud.hp_color(0.75).g > half.g and DiegeticHud.hp_color(0.75).g < full.g)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var hud := run.diegetic_hud
	var health := (run.player as DesktopPlayer).health
	# HP is set on the player and refreshed the way play does it (RunGame refreshes every tick).
	for case in [[100.0, 1.0], [50.0, 0.5], [20.0, 0.2]]:
		health.hp = health.max_hp * float(case[1])
		run._refresh_hud()
		await _frames(1)
		var fill: float = hud._ring_cache.get("hp_fill", -1.0)
		_check("ring fill is HP/max at %.0f%% (fill %.2f)" % [case[0], fill], absf(fill - case[1]) < 0.01)
	health.hp = health.max_hp
	run._refresh_hud()
	await _frames(1)
	_check("no pulse at full health", float(hud._ring_cache.get("hp_pulse", 1.0)) == 0.0)
	health.hp = health.max_hp * 0.2
	run._refresh_hud()
	await _frames(1)
	_check("pulse when critical (20%%)", float(hud._ring_cache.get("hp_pulse", 0.0)) == 1.0)
	health.hp = health.max_hp
	run._refresh_hud()

	# The white figure over the fire: WCAG-style contrast of white against the fire's middle.
	var ratio := _contrast(DiegeticHud.KCAL_COLOR, DiegeticHud.FLAME_MID)
	_check("kcal figure contrast over the fire is at least 4.5:1 (%.1f)" % ratio, ratio >= 4.5)
	_check("kcal figure is white", DiegeticHud.KCAL_COLOR == Color(1.0, 1.0, 1.0))
	run.queue_free()
	await _frames(2)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


# --- Kcal in the run scene -----------------------------------------------------------

func _kcal_in_run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var meter := run.calorie_meter
	var hud := run.diegetic_hud
	_check("kcal: the meter is counting in the run", meter != null and run.state == RunGame.RunState.PLAYING and meter.counting)

	# Drive the meter from plain nodes: the desktop rig rewrites its hand every frame.
	var hand := Node3D.new()
	var head := Node3D.new()
	add_child(hand)
	add_child(head)
	meter.set_sources([hand], head)
	await _frames(4)
	var k0 := meter.kcal
	await _frames(90)
	var idle := meter.kcal - k0
	var resting := CalorieMeter.kcal_for(CalorieMeter.MET_STANDING, VrComfortSettings.body_weight_kg, 1.0)
	_check("kcal: standing still burns the resting rate (%.4f kcal/s, want %.4f)" % [idle, resting / 1.0],
		absf(idle - resting) < resting * 0.05)

	k0 = meter.kcal
	for _i in 90:
		hand.global_position.x += 1.5 / 90.0
		await get_tree().physics_frame
	var moving := meter.kcal - k0
	_check("kcal: swinging the hand at 1.5 m/s burns more than twice the resting rate (%.4f vs %.4f)" % [moving, idle],
		moving > 2.0 * idle)

	get_tree().paused = true
	k0 = meter.kcal
	await _frames(90)
	var paused_gain := meter.kcal - k0
	get_tree().paused = false
	_check("kcal: nothing burns while the game is paused (%.6f)" % paused_gain, is_zero_approx(paused_gain))

	# The readout shows the figure (desktop: H held raises the wrist readout).
	var player := run.player as DesktopPlayer
	player.wrist_check = true
	await _frames(20)
	_check("H held raises the wrist readout", hud.wrist_face.visible and hud.kcal_label.visible)
	_check("the readout figure is the kcal estimate (%s)" % hud.kcal_label.text,
		hud.kcal_label.text == str(floori(meter.kcal)))
	player.wrist_check = false
	await _frames(20)
	_check("H released: the readout hides and draws nothing", not hud.wrist_face.visible and _drawn_under(hud) == 0)
	run.queue_free()
	await _frames(2)


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
