extends Node
## The wrist readout (D14), on the real XR rig and in the real run scene.
## - Clearance: the readout's rows never sit in the hand mesh or the katana, at
##   the eye tilt limits and in several katana poses (the readout is a plate in the bracer
##   frame; any mesh vertex above it inside its footprint is clipping).
## - Gesture: shown only when the wrist is close to the eyes, its forearm level, its face
##   turned to them and in view; hysteresis at both edges; a 0.15 s fade; nothing drawn while
##   hidden. An upright hand (forearm vertical, back to the eyes) keeps it hidden (P9).
## - Rows (F1): HP, KCAL, ŁADUNKI and CZAS, top to bottom, Latin only. HP's bar is HP/max in
##   teal -> amber -> red, and pulses only when critical. Every row's text has enough contrast
##   against its outline, and the rows fit the plate without overlap. set_row adds a row below.
## - No japanese on the wrist (F1): no kanji or kana in any label, in any state the readout shows.
## - No shader on the wrist (F1, D22): nothing fiery is drawn; the readout is bars, pips and text.
## - Charges (D22, F1): three pips in the row ŁADUNKI, empty grey until a charge is taken;
##   each filled pip takes its element's colour, oldest first; a spent or reset charge empties.
## - Kcal (run.tscn): rises with movement, the resting rate standing still, not in a pause,
##   and the desktop H key raises the readout.
## - SANDBOX mark (D9, run.tscn): drawn on the plate, in view and above the rows, only in a
##   sandbox run; a normal run shows nothing.
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
	await _rows_and_figure()
	await _kcal_in_run()
	await _charges_in_run()
	await _sandbox_mark_in_run()
	await _pixel_contrast_in_run()


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
	# Control: a grip with the blade through the readout's centre must be seen as a hit.
	katana.global_transform = ctrl.global_transform * Transform3D(Basis.IDENTITY, -grip + hud.wrist_unit.position)
	await get_tree().physics_frame
	var through := _readout_hits(_world_vertices(_meshes_under(katana)), hud)
	_check("control: the check sees the katana run through the readout (%d vertices)" % through, through > 0)
	katana.queue_free()

	# Gesture: a readout that is near, faces the eyes and is in view shows; the rest hides it.
	_place_readout(hud, cam, 0.25, 15.0)
	await _frames(20)
	_check("gesture: wrist close, face to the eyes, in view: readout shows", hud.wrist_face.visible and hud.row_labels("hp")[0].is_visible_in_tree())

	_place_readout(hud, cam, 0.6, 15.0)
	await _frames(20)
	_check("far from the eyes (60 cm): readout hidden, nothing drawn", not hud.wrist_face.visible and _drawn_under(hud) == 0)

	_place_readout(hud, cam, 0.25, 120.0)
	await _frames(20)
	_check("face turned away (120 deg): readout hidden", not hud.wrist_face.visible)

	# P9: the watch is checked with the forearm level. The same face turned to the eyes, with
	# the forearm standing up (a hand held upright, its back to the eyes), stays hidden.
	_place_readout(hud, cam, 0.25, 15.0, 80.0)
	await _frames(20)
	_check("upright hand (forearm 80 deg), face to the eyes: readout hidden", not hud.wrist_face.visible and _drawn_under(hud) == 0)

	_place_readout(hud, cam, 0.25, 15.0, 25.0)
	await _frames(20)
	_check("forearm lifted 25 deg, face to the eyes: readout shown", hud.wrist_face.visible)
	_place_readout(hud, cam, 0.25, 15.0)
	await _frames(20)
	_check("forearm level, face to the eyes: readout shown again", hud.wrist_face.visible)

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
## the view), its face turned [param face_deg] off the eyes. The forearm (the wrist's +Z,
## toward the elbow) lies level, the watch check, unless [param forearm_deg] lifts it: 90 is
## straight up or down, with the elbow below. The eyes are read live: the XR body sinks while
## the test runs.
func _place_readout(hud: DiegeticHud, cam: Node3D, dist: float, face_deg: float, forearm_deg := 0.0) -> void:
	var eye := cam.global_position
	var toward := (-cam.global_basis.z + cam.global_basis.x * 0.25 - Vector3.UP * 0.3).normalized()
	var centre := eye + toward * dist
	var to_eye := (eye - centre).normalized()
	var axis := to_eye.cross(Vector3.UP)
	if axis.length_squared() < 1e-6:
		axis = Vector3.RIGHT
	var face := to_eye.rotated(axis.normalized(), deg_to_rad(face_deg))
	# Level: across the face, perpendicular to it. Lifted: the in-plane direction that points down,
	# blended in by the lift angle (the elbow below the hand).
	var level := Vector3.UP.cross(face).normalized()
	var down := -(Vector3.UP - face * Vector3.UP.dot(face)).normalized()
	var lift := deg_to_rad(forearm_deg)
	var z := (level * cos(lift) + down * sin(lift)).normalized()
	var x := face.cross(z).normalized()
	z = x.cross(face).normalized()
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
## The footprint is the rows column: its half width with a margin, from the top row down past
## the last row (the old readout's rectangle is inside it). The plate frame is the face's, so a
## vertex is "above" when its height in that frame is above the margin.
func _readout_hits(verts: PackedVector3Array, hud: DiegeticHud) -> int:
	var inv := hud.wrist_face.global_transform.affine_inverse()
	var hits := 0
	for w in verts:
		var p := inv * w
		var in_rows := absf(p.x) <= 0.031 and p.z >= -0.040 and p.z <= 0.072
		if in_rows and p.y > -CLEAR_MARGIN:
			hits += 1
	return hits


## A label's text box on the plate: its x and z extent in the plate's frame (the plate's up is -z).
func _plate_box(hud: DiegeticHud, label: Label3D) -> Rect2:
	var aabb := label.get_aabb()
	var xs: Array[float] = []
	var zs: Array[float] = []
	for c: Vector3 in [aabb.position, aabb.end, Vector3(aabb.position.x, aabb.end.y, 0.0), Vector3(aabb.end.x, aabb.position.y, 0.0)]:
		var p := hud.wrist_face.to_local(label.to_global(c))
		xs.append(p.x)
		zs.append(p.z)
	var x0: float = xs.min()
	var z0: float = zs.min()
	return Rect2(x0, z0, xs.max() - x0, zs.max() - z0)


## Readout nodes drawn right now (zero when hidden: the subtree is not rendered).
func _drawn_under(hud: DiegeticHud) -> int:
	var n := 0
	for c in hud.wrist_face.find_children("*", "VisualInstance3D", true, false):
		if (c as VisualInstance3D).is_visible_in_tree():
			n += 1
	return n


# --- Rows and figures (F1) -----------------------------------------------------------

func _rows_and_figure() -> void:
	# Colour rule: teal when healthy, amber at half, red when critical.
	var full := DiegeticHud.hp_color(1.0)
	var half := DiegeticHud.hp_color(0.5)
	var low := DiegeticHud.hp_color(0.2)
	_check("HP colour at 100%% is teal (%s)" % [full], full.g > full.r and full.b > full.r and full.g > 0.7)
	_check("HP colour at 50%% is amber (%s)" % [half], half.r > 0.9 and half.g > 0.55 and half.g < 0.7 and half.b < 0.3)
	_check("HP colour at 20%% is red (%s)" % [low], low.r > 0.85 and low.g < 0.3 and low.b < 0.3)
	_check("colour runs smoothly: 75%% lies between amber and teal",
		DiegeticHud.hp_color(0.75).g > half.g and DiegeticHud.hp_color(0.75).g < full.g)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://test_wrist_rows_save.cfg"
	add_child(run)
	await _frames(8)
	var hud := run.diegetic_hud
	var health := (run.player as DesktopPlayer).health

	# The rows, top to bottom: HP, KCAL, ŁADUNKI, CZAS (F1).
	_check("rows read top to bottom: HP, KCAL, ŁADUNKI, CZAS, STAMINA, DUSZE (%s)" % [hud.row_keys()],
		hud.row_keys() == ["hp", "kcal", "charges", "time", "stamina", "souls"])
	_check("row labels read HP, KCAL, ŁADUNKI, CZAS",
		hud.row_label("hp") == "HP" and hud.row_label("kcal") == "KCAL"
		and hud.row_label("charges") == "ŁADUNKI" and hud.row_label("time") == "CZAS")

	# HP is set on the player and refreshed the way play does it (RunGame refreshes every tick).
	for case in [[100.0, 1.0], [50.0, 0.5], [20.0, 0.2]]:
		health.hp = health.max_hp * float(case[1])
		run._refresh_hud()
		await _frames(1)
		var fill := hud.row_fill("hp")
		_check("HP bar is HP/max at %.0f%% (fill %.2f)" % [case[0], fill], absf(fill - case[1]) < 0.01)
		_check("HP row reads current / max (%s)" % hud.row_value("hp"),
			hud.row_value("hp") == "%d / %d" % [ceili(health.hp), ceili(health.max_hp)])
	health.hp = health.max_hp
	run._refresh_hud()
	await _frames(1)
	_check("no pulse at full health", not hud.hp_critical)
	health.hp = health.max_hp * 0.2
	run._refresh_hud()
	await _frames(1)
	_check("pulse when critical (20%%)", hud.hp_critical)
	_check("critical HP bar is red", hud._hp_colour.r > 0.85 and hud._hp_colour.g < 0.3)
	health.hp = health.max_hp
	run._refresh_hud()

	# Latin only: no kanji or kana on the readout, in every state it can show.
	await _frames(2)
	_check("no japanese on the readout at rest (%s)" % [_japanese_on_readout(hud)], _japanese_on_readout(hud).is_empty())
	run.element_system.imbue(Elements.SAKURA, 20.0)
	await _frames(2)
	_check("imbued: the charges row shows the seconds left (%s)" % hud.row_value("charges"),
		hud.row_value("charges").ends_with(" s") and hud.row_value("charges").trim_suffix(" s").is_valid_int())
	_check("no japanese with an element imbued (%s)" % [_japanese_on_readout(hud)], _japanese_on_readout(hud).is_empty())
	hud.flash_level_up(3)
	await _frames(2)
	_check("level-up flash: the time row reads LV 3 and +1 PT (%s / %s)" % [hud.row_label("time"), hud.row_value("time")],
		hud.row_label("time") == "LV 3" and hud.row_value("time") == "+1 PT")
	_check("no japanese on the level-up flash (%s)" % [_japanese_on_readout(hud)], _japanese_on_readout(hud).is_empty())
	hud._level_text_left = 0.0
	hud.update_hud(health.hp, health.max_hp, 0, 30, 3, 1, 0, 0, 0.0, Elements.NONE, 0, "速 5 s")
	await _frames(2)
	_check("buffs in kanji are not drawn on the wrist (%s)" % [_japanese_on_readout(hud)], _japanese_on_readout(hud).is_empty())
	run.element_system.reset()
	await _frames(2)

	# Time: CZAS reads mm:ss of the run.
	run.run_time = 125.0
	run._refresh_hud()
	await _frames(1)
	_check("CZAS reads the run time as mm:ss (%s)" % hud.row_value("time"), hud.row_value("time") == "02:05")

	# Contrast: every row's text against its outline (WCAG 4.5:1).
	var worst := 99.0
	for k in hud.row_keys():
		for l in hud.row_labels(k):
			var lab := l as Label3D
			var c := _contrast(Color(lab.modulate.r, lab.modulate.g, lab.modulate.b),
				Color(lab.outline_modulate.r, lab.outline_modulate.g, lab.outline_modulate.b))
			worst = minf(worst, c)
	_check("row text contrast against its outline is at least 4.5:1 (worst %.1f)" % worst, worst >= 4.5)

	# Layout: each row's text is inside the column and sits below the row above it, no overlap.
	var half_w := DiegeticHud.PANEL_HALF_WIDTH + 0.0015
	var fits := true
	var stacked := true
	var above_bottom := -INF
	for k in hud.row_keys():
		var box := _plate_box(hud, hud.row_labels(k)[0]).merge(_plate_box(hud, hud.row_labels(k)[1]))
		fits = fits and absf(box.position.x) <= half_w and absf(box.end.x) <= half_w
		stacked = stacked and box.position.y >= above_bottom
		above_bottom = box.end.y
	_check("the rows fit the column (half width %.4f m)" % half_w, fits)
	_check("the rows stack top to bottom without overlap", stacked)
	# F6 rev.: label (left) and value (right) keep a gap on every row; on ŁADUNKI the value clears the pips.
	var worst_gap := INF
	for k in hud.row_keys():
		var lv := hud.row_labels(k)
		var right_of_label: float = lv[0].position.x + DiegeticHud.text_width(lv[0])
		if k == "charges":
			right_of_label = -DiegeticHud.PANEL_HALF_WIDTH + float(ElementSystem.MAX_CHARGES - 1) * DiegeticHud.PIP_PITCH + DiegeticHud.PIP_SIZE
		var left_of_value: float = lv[1].position.x - DiegeticHud.text_width(lv[1])
		worst_gap = minf(worst_gap, left_of_value - right_of_label)
	_check("every row keeps a gap between label and value (worst %.4f m)" % worst_gap, worst_gap >= DiegeticHud.LABEL_VALUE_GAP - 0.0002)

	# F6: the run's stamina row sits under CZAS and follows the bar (amber when winded).
	var stamina := hud.row_labels("stamina")
	_check("the STAMINA row sits under CZAS and reads full (%s)" % hud.row_value("stamina"), stamina.size() == 2
		and stamina[0].text == "STAMINA" and hud.row_value("stamina") == "100" and absf(hud.row_fill("stamina") - 1.0) < 0.001
		and _plate_box(hud, stamina[0]).position.y >= _plate_box(hud, hud.row_labels("time")[0]).end.y)
	# Read straight after the refresh: the run keeps stepping (and refilling) the bar every tick.
	run.stamina.value = 40.0
	run._refresh_hud()
	_check("the STAMINA row follows the bar (%s, fill %.2f)" % [hud.row_value("stamina"), hud.row_fill("stamina")],
		hud.row_value("stamina") == "40" and absf(hud.row_fill("stamina") - 0.4) < 0.01)
	run.stamina.value = 0.0
	run.stamina.is_exhausted = true
	run._refresh_hud()
	_check("winded: STAMINA reads 0 in amber", hud.row_value("stamina") == "0" and stamina[1].modulate.is_equal_approx(DiegeticHud.AMBER))
	run.stamina.reset()

	# F1 API: a new row set with set_row lands under the last one and shows.
	hud.set_row("probe", "PROBA", "100", 1.0, DiegeticHud.TEAL)
	await _frames(2)
	var probe := hud.row_labels("probe")
	_check("set_row adds a row at the bottom (%d rows)" % hud.row_keys().size(),
		hud.row_keys().size() == 7 and hud.row_keys()[6] == "probe")
	_check("the new row carries its label, value and bar", probe.size() == 2 and probe[0].text == "PROBA"
		and probe[1].text == "100" and absf(hud.row_fill("probe") - 1.0) < 0.001)
	_check("the new row sits below DUSZE", _plate_box(hud, probe[0]).position.y >= _plate_box(hud, hud.row_labels("souls")[0]).end.y)
	hud.set_row("probe", "PROBA", "40", 0.4, DiegeticHud.TEAL)
	await _frames(1)
	_check("set_row updates an existing row in place (%s, fill %.2f)" % [hud.row_value("probe"), hud.row_fill("probe")],
		hud.row_keys().size() == 7 and hud.row_value("probe") == "40" and absf(hud.row_fill("probe") - 0.4) < 0.01)
	run.queue_free()
	await _frames(2)


## Japanese characters (hiragana, katakana, CJK ideographs) on any label of the readout.
func _japanese_on_readout(hud: DiegeticHud) -> Array[String]:
	var found: Array[String] = []
	for l in hud.wrist_face.find_children("*", "Label3D", true, false):
		var text := (l as Label3D).text
		for i in text.length():
			var cp := text.unicode_at(i)
			if (cp >= 0x3040 and cp <= 0x30FF) or (cp >= 0x4E00 and cp <= 0x9FFF):
				found.append("%s: %s" % [l.name, text])
				break
	return found


## F1 (pixels): the HP text must read on what is behind it in the frame the player sees. In the
## real run scene, the readout raised, the screen rectangle of the HP label and value is
## measured against the ring of pixels just outside it (the ground the text sits on). Text is
## the brightest tenth of the rectangle, its ground the median of the ring; the WCAG ratio must be
## at least 4.5:1. Needs a window (the frame is read back): headless it prints SKIP, and
## visual-perf runs it under xvfb.
func _pixel_contrast_in_run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  pixel contrast of the HP text (needs a window: run under xvfb)")
		return
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://test_wrist_pixels_save.cfg"
	add_child(run)
	await _frames(8)
	var player := run.player as DesktopPlayer
	var hud := run.diegetic_hud
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	player.camera.rotation.x = deg_to_rad(-34.0)
	player.hand_offset = Vector3(0.18, -0.14, 0.0)
	player.health.hp = player.health.max_hp
	run._refresh_hud()
	player.wrist_check = true
	await _frames(40)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var cam := player.camera
	var box := _screen_box(cam, hud.row_labels("hp"))
	var size := Vector2(img.get_width(), img.get_height())
	var inside := box.position.x >= 1.0 and box.position.y >= 1.0 and box.end.x <= size.x - 1.0 and box.end.y <= size.y - 1.0
	_check("HP text is on screen in the frame (box %s in %s)" % [box, size], inside and box.size.x > 4.0)
	if inside:
		var text_lum: Array[float] = []
		var ground: Array[float] = []
		var pad := 6
		for y in range(int(box.position.y) - pad, int(box.end.y) + pad):
			for x in range(int(box.position.x) - pad, int(box.end.x) + pad):
				if x < 0 or y < 0 or x >= size.x or y >= size.y:
					continue
				var lum := _luminance(img.get_pixel(x, y))
				if x >= box.position.x and x < box.end.x and y >= box.position.y and y < box.end.y:
					text_lum.append(lum)
				else:
					ground.append(lum)
		text_lum.sort()
		ground.sort()
		var top_tenth := text_lum.slice(int(text_lum.size() * 0.9))
		var text_mean := 0.0
		for v in top_tenth:
			text_mean += v
		text_mean /= maxf(float(top_tenth.size()), 1.0)
		var ground_mid := ground[ground.size() / 2]
		var ratio := (maxf(text_mean, ground_mid) + 0.05) / (minf(text_mean, ground_mid) + 0.05)
		_check("HP text against its ground in the frame: %.1f:1 (text %.2f, ground %.2f)" % [ratio, text_mean, ground_mid],
			ratio >= 4.5)
	player.wrist_check = false
	run.queue_free()
	await _frames(2)


## The screen rectangle that covers the given labels' boxes, projected from the camera.
func _screen_box(cam: Camera3D, labels: Array[Label3D]) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for l in labels:
		var a := l.get_aabb()
		for i in 8:
			var corner := a.position + a.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)
			var world := l.global_transform * corner
			if cam.is_position_behind(world):
				continue
			var p := cam.unproject_position(world)
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2(lo, hi - lo)


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
	_check("H held raises the wrist readout", hud.wrist_face.visible and hud.row_labels("kcal")[1].visible)
	_check("the readout figure is the kcal estimate (%s)" % hud.row_value("kcal"),
		hud.row_value("kcal") == str(floori(meter.kcal)))
	player.wrist_check = false
	await _frames(20)
	_check("H released: the readout hides and draws nothing", not hud.wrist_face.visible and _drawn_under(hud) == 0)
	run.queue_free()
	await _frames(2)


## D9: a sandbox run wears a small amber SANDBOX mark on the plate, and only that run does. Checked
## in the real run scene with the wrist raised: the mark is drawn, sits on the plate, is in the
## camera's view and sits above the rows. A normal run draws nothing.
func _sandbox_mark_in_run() -> void:
	var real_path := VrComfortSettings.settings_path
	VrComfortSettings.settings_path = "user://test_wrist_sandbox.cfg"
	VrComfortSettings.sandbox_enabled = true
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://test_wrist_sandbox_save.cfg"
	add_child(run)
	await _frames(8)
	var hud := run.diegetic_hud
	var player := run.player as DesktopPlayer
	var label := hud.sandbox_label
	player.wrist_check = true
	await _frames(20)
	var cam := player.camera
	# The text's box in the plate's own frame: its four corners, carried through the label's rotation.
	var aabb := label.get_aabb()
	var xs: Array[float] = []
	var zs: Array[float] = []
	for c: Vector3 in [aabb.position, aabb.end, Vector3(aabb.position.x, aabb.end.y, 0.0), Vector3(aabb.end.x, aabb.position.y, 0.0)]:
		var p := hud.wrist_face.to_local(label.to_global(c))
		xs.append(p.x)
		zs.append(p.z)
	var left := minf(xs[0], minf(xs[1], minf(xs[2], xs[3])))
	var right := maxf(xs[0], maxf(xs[1], maxf(xs[2], xs[3])))
	var top := minf(zs[0], minf(zs[1], minf(zs[2], zs[3])))
	var bottom := maxf(zs[0], maxf(zs[1], maxf(zs[2], zs[3])))
	var half := DiegeticHud.PLATE_SIZE * 0.5
	_check("sandbox run: the SANDBOX mark is drawn with the raised wrist (visible %s)" % label.visible,
		label.visible and label.text == "SANDBOX" and label.is_visible_in_tree() and hud.wrist_face.visible)
	_check("the mark sits on the plate (x %.4f..%.4f, z %.4f..%.4f)" % [left, right, top, bottom],
		left >= -half.x and right <= half.x and top >= -half.y and bottom <= half.y)
	_check("the mark is in the camera's view", cam.is_position_in_frustum(label.global_position))
	_check("the mark sits above the first row (bottom %.4f, first row %.4f)" % [bottom, DiegeticHud.row_top(0)],
		bottom < DiegeticHud.row_top(0))
	player.wrist_check = false
	run.queue_free()
	await _frames(4)

	VrComfortSettings.sandbox_enabled = false
	var plain: RunGame = RUN_SCENE.instantiate()
	plain.skip_run_intro = true
	plain.high_score_path = "user://test_wrist_sandbox_save.cfg"
	add_child(plain)
	await _frames(8)
	var plain_player := plain.player as DesktopPlayer
	plain_player.wrist_check = true
	await _frames(20)
	_check("a normal run draws no SANDBOX mark (visible %s)" % plain.diegetic_hud.sandbox_label.visible,
		not plain.diegetic_hud.sandbox_label.visible and plain.diegetic_hud.wrist_face.visible)
	plain_player.wrist_check = false
	plain.queue_free()
	await _frames(2)
	VrComfortSettings.settings_path = real_path


## D22: the three charge orbs follow the element system's charges (oldest first, FIFO), the
## spent charge empties at once, and a reset empties them all. Checked in the real run scene.
func _charges_in_run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://test_wrist_charges_save.cfg"
	add_child(run)
	await _frames(8)
	var hud := run.diegetic_hud
	var es := run.element_system
	es.reset()
	await _frames(1)
	_check("charges: nothing held, all three orbs empty", _orbs_filled(hud) == [false, false, false])
	_check("charges: an empty orb is a grey outline (fill %.1f)" % _orb(hud, 0).a, _orb(hud, 0).a == 0.0)

	es.add_charge(Elements.SAKURA)
	await _frames(1)
	_check("charges: one Sakura charge fills the first orb with Sakura's colour", _orbs_filled(hud) == [true, false, false] and _same_rgb(_orb(hud, 0), Elements.accent_color(Elements.SAKURA)))
	es.add_charge(Elements.STORM)
	await _frames(1)
	_check("charges: Storm fills the second orb in Storm's colour", _orbs_filled(hud) == [true, true, false] and _same_rgb(_orb(hud, 1), Elements.accent_color(Elements.STORM)))
	es.add_charge(Elements.INK)
	await _frames(1)
	_check("charges: Ink fills the third orb in Ink's colour", _orbs_filled(hud) == [true, true, true] and _same_rgb(_orb(hud, 2), Elements.accent_color(Elements.INK)))
	_check("charges: a full buffer refuses a fourth charge", not es.add_charge(Elements.SHADOW))

	# Spending the oldest (Sakura) takes the first orb; Storm moves to the front, Ink to the second.
	var spent := es.activate_charge()
	await _frames(1)
	_check("charges: spending the oldest empties the buffer's front (spent %s)" % spent,
		spent and _orbs_filled(hud) == [true, true, false] and _same_rgb(_orb(hud, 0), Elements.accent_color(Elements.STORM)) and _same_rgb(_orb(hud, 1), Elements.accent_color(Elements.INK)))

	es.reset()
	await _frames(1)
	_check("charges: a reset empties every orb", _orbs_filled(hud) == [false, false, false])
	run.queue_free()
	await _frames(2)


func _orb(hud: DiegeticHud, index: int) -> Color:
	return hud.charge_slots()[index]


func _orbs_filled(hud: DiegeticHud) -> Array:
	var out: Array = []
	for i in ElementSystem.MAX_CHARGES:
		out.append(_orb(hud, i).a > 0.5)
	return out


func _same_rgb(c: Color, want: Color) -> bool:
	return absf(c.r - want.r) < 0.001 and absf(c.g - want.g) < 0.001 and absf(c.b - want.b) < 0.001


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
