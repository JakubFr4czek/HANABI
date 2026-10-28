class_name SkillTreeMenu
extends Node3D
## The Ofuda skill-tree scroll as a world-space panel with laser pointers
## (docs/ELEMENTS_PLAN.md Phase E2d).
##
## One quad shows a [SkillTreeCanvas] rendered into a SubViewport (updated only
## when something changes). Pointers ("left", "right", "mouse") are plain rays
## fed by [method update_pointer]: the menu intersects them with its plane,
## hit-tests the canvas, shows a beam and a reticle, pulses the hand on hover
## and acts on a trigger press. Buying a node goes through exactly one door,
## RunGame.unlock_skill(); the menu only displays the verdict.
##
## It processes while the tree is paused (process_mode ALWAYS) and never reads
## game time. The panel material ignores fog; it is depth-tested normally (so
## the player's hands and blade stay in front of it) unless the placement code
## could not find a clear spot, in which case it is drawn on top.

signal close_requested
signal unlocked(node_id: String)
signal denied(node_id: String, reason: String)

## Panel size in metres at its default distance (UiPlacement scales it).
const PANEL_SIZE := Vector2(1.2, 0.75)
const PRIORITY_PANEL := 100
const PRIORITY_BEAM := 103
const PRIORITY_RETICLE := 104
const BEAM_RADIUS := 0.0022
const STUB_LENGTH := 0.3
## Redraws per second for pulsing nodes and sparkle (state changes redraw at once).
const ANIM_FPS := 30.0
## The panel eases in over this many (real) seconds.
const FADE_IN_SECONDS := 0.16

var run_game: RunGame
var canvas: SkillTreeCanvas
var is_open := false
var panel_scale := 1.0
## Whether the last [method open] could not find a clear spot (panel drawn on top).
var drawn_on_top := false
## Called as (pointer_id: String, amplitude: float, seconds: float) to buzz a hand.
var haptic_sink: Callable = Callable()

var _viewport: SubViewport
var _panel: MeshInstance3D
var _panel_mat: StandardMaterial3D
var _pointers: Dictionary = {}  # id -> state dictionary
var _redraw_accum := 0.0
var _age := 1.0
var _stamp := 0
var _beam_mesh: CylinderMesh
var _reticle_mesh: TorusMesh
var _beam_mat: StandardMaterial3D
var _reticle_mat: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_viewport = SubViewport.new()
	_viewport.name = "TreeViewport"
	_viewport.size = Vector2i(roundi(SkillTreeCanvas.SIZE.x), roundi(SkillTreeCanvas.SIZE.y))
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	canvas = SkillTreeCanvas.new()
	canvas.name = "Canvas"
	_viewport.add_child(canvas)

	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_panel_mat.albedo_texture = _viewport.get_texture()
	_panel_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_panel_mat.disable_fog = true
	_panel_mat.render_priority = PRIORITY_PANEL
	_panel_mat.cull_mode = BaseMaterial3D.CULL_BACK
	var quad := QuadMesh.new()
	quad.size = PANEL_SIZE
	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	_panel.mesh = quad
	_panel.material_override = _panel_mat
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_panel.visible = false
	add_child(_panel)

	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = BEAM_RADIUS
	_beam_mesh.bottom_radius = BEAM_RADIUS
	_beam_mesh.height = 1.0
	_beam_mesh.radial_segments = 6
	_beam_mesh.rings = 1
	_beam_mesh.cap_top = false
	_beam_mesh.cap_bottom = false
	_reticle_mesh = TorusMesh.new()
	_reticle_mesh.inner_radius = 0.0075
	_reticle_mesh.outer_radius = 0.0115
	_reticle_mesh.rings = 20
	_reticle_mesh.ring_segments = 6
	_beam_mat = _overlay_material(Color(1.0, 0.82, 0.55, 0.8), PRIORITY_BEAM)
	_reticle_mat = _overlay_material(Color(1.0, 0.9, 0.7, 1.0), PRIORITY_RETICLE)


static func _overlay_material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.no_depth_test = true
	m.disable_fog = true
	m.render_priority = priority
	return m


# --- Open / close ----------------------------------------------------------------

## Shows the panel at [param pose] (from [UiPlacement.place]) for [param game].
func open(game: RunGame, pose: Dictionary, blade_element: String, blade_seconds: float, hint: String) -> void:
	run_game = game
	global_transform = pose.transform
	panel_scale = float(pose.get("scale", 1.0))
	scale = Vector3.ONE * panel_scale
	drawn_on_top = bool(pose.get("blocked", false))
	_panel_mat.no_depth_test = drawn_on_top
	canvas.tree = game.skill_tree
	canvas.balance = game.ofuda_count
	canvas.blade_element = blade_element
	canvas.blade_seconds = blade_seconds
	canvas.abilities = _ability_status(game)
	canvas.hint_text = hint
	canvas.status_text = ""
	canvas.is_settings_tab = false
	if Elements.COMBAT_ELEMENTS.has(blade_element):
		canvas.element = blade_element
	elif not Elements.COMBAT_ELEMENTS.has(canvas.element):
		canvas.element = Elements.SAKURA
	canvas.selected_id = canvas.default_node_for(canvas.element)
	canvas.hover = {}
	for id: String in _pointers.keys():
		_pointers[id]["hover"] = {}
		_pointers[id]["pressed"] = true  # a trigger already held at opening must not click
	is_open = true
	visible = true
	_panel.visible = true
	_redraw_accum = 0.0
	_age = 0.0
	_panel_mat.albedo_color.a = 0.0
	_redraw_now()


func close() -> void:
	is_open = false
	visible = false
	_panel.visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for id: String in _pointers.keys():
		_hide_pointer_visuals(_pointers[id])
		_pointers[id]["hover"] = {}


# --- Per-frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return
	if _age < FADE_IN_SECONDS:
		_age += delta
		var k := clampf(_age / FADE_IN_SECONDS, 0.0, 1.0)
		_panel_mat.albedo_color.a = k * k * (3.0 - 2.0 * k)
	canvas.advance(delta)
	_redraw_accum += delta
	if _redraw_accum >= 1.0 / ANIM_FPS:
		_redraw_accum = 0.0
		_redraw_now()


## The blade's two abilities for the footer line (empty on plain steel).
static func _ability_status(game: RunGame) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var es := game.element_system
	if es == null or es.current_element == Elements.NONE:
		return out
	for slot in [1, 2]:
		var cd := es.ability_1_cooldown if slot == 1 else es.ability_2_cooldown
		out.append({
			"glyph": Elements.ability_glyph(es.current_element, slot),
			"name": Elements.ability_name(es.current_element, slot),
			"ratio": es.ability_ready_ratio(slot),
			"seconds": cd,
		})
	return out


func _redraw_now() -> void:
	canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# --- Pointers -----------------------------------------------------------------------

## Where the ray (origin, dir) meets the panel: {"canvas": Vector2 px, "world": Vector3,
## "distance": float} or {} when it misses (or comes from behind).
func ray_to_canvas(origin: Vector3, dir: Vector3) -> Dictionary:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := inv.basis * dir
	if o.z <= 0.0 or d.z >= -1e-5:
		return {}
	var t := -o.z / d.z
	var p := o + d * t
	if absf(p.x) > PANEL_SIZE.x * 0.5 or absf(p.y) > PANEL_SIZE.y * 0.5:
		return {}
	var px := Vector2((p.x / PANEL_SIZE.x + 0.5) * SkillTreeCanvas.SIZE.x,
			(0.5 - p.y / PANEL_SIZE.y) * SkillTreeCanvas.SIZE.y)
	var world := global_transform * p
	return {"canvas": px, "world": world, "distance": origin.distance_to(world)}


## World position of canvas pixel [param px] on the panel (tests, screenshots).
func canvas_to_world(px: Vector2) -> Vector3:
	var local := Vector3((px.x / SkillTreeCanvas.SIZE.x - 0.5) * PANEL_SIZE.x,
			(0.5 - px.y / SkillTreeCanvas.SIZE.y) * PANEL_SIZE.y, 0.0)
	return global_transform * local


## Feeds pointer [param id] a ray this frame. [param pressed] is the trigger
## state: its rising edge clicks whatever the ray rests on. [param show_beam]
## false (desktop) draws the reticle only.
func update_pointer(id: String, origin: Vector3, dir: Vector3, pressed: bool, show_beam := true) -> void:
	if not is_open:
		return
	var p := _pointer(id)
	var hit := ray_to_canvas(origin, dir.normalized())
	var new_hover: Dictionary = {}
	if not hit.is_empty():
		new_hover = canvas.hit_test(hit.canvas)
	if new_hover != p.hover:
		p.hover = new_hover
		_stamp += 1
		p.stamp = _stamp
		if not new_hover.is_empty():
			_buzz(id, 0.16, 0.025)
		_sync_hover()
		_redraw_now()
	if pressed and not bool(p.pressed) and not new_hover.is_empty():
		_activate(new_hover, id)
	p.pressed = pressed
	_draw_pointer(p, origin, dir.normalized(), hit, show_beam)


## Hides pointer [param id] (controller lost, nothing aimed).
func hide_pointer(id: String) -> void:
	if not _pointers.has(id):
		return
	var p: Dictionary = _pointers[id]
	_hide_pointer_visuals(p)
	if not (p.hover as Dictionary).is_empty():
		p.hover = {}
		_sync_hover()
		_redraw_now()


func pointer_hover(id: String) -> Dictionary:
	return (_pointers[id] as Dictionary).hover if _pointers.has(id) else {}


func _pointer(id: String) -> Dictionary:
	if not _pointers.has(id):
		var beam := MeshInstance3D.new()
		beam.name = "Beam_" + id
		beam.mesh = _beam_mesh
		beam.material_override = _beam_mat
		beam.top_level = true
		beam.visible = false
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		var reticle := MeshInstance3D.new()
		reticle.name = "Reticle_" + id
		reticle.mesh = _reticle_mesh
		reticle.material_override = _reticle_mat
		reticle.top_level = true
		reticle.visible = false
		reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(reticle)
		_pointers[id] = {"hover": {}, "pressed": false, "stamp": 0, "beam": beam, "reticle": reticle}
	return _pointers[id]


## The canvas highlights what the most recently moved pointer rests on.
func _sync_hover() -> void:
	var best: Dictionary = {}
	var best_stamp := -1
	for id: String in _pointers.keys():
		var p: Dictionary = _pointers[id]
		if not (p.hover as Dictionary).is_empty() and int(p.stamp) > best_stamp:
			best = p.hover
			best_stamp = int(p.stamp)
	canvas.hover = best


func _draw_pointer(p: Dictionary, origin: Vector3, dir: Vector3, hit: Dictionary, show_beam: bool) -> void:
	var beam := p.beam as MeshInstance3D
	var reticle := p.reticle as MeshInstance3D
	var forward := -global_basis.z.normalized()  # away from the viewer
	var normal := -forward  # panel front
	var hot := not (p.hover as Dictionary).is_empty()
	if not hit.is_empty():
		var tip: Vector3 = hit.world + normal * 0.004
		reticle.visible = true
		var s := panel_scale * (1.35 if hot else 1.0)
		reticle.global_transform = Transform3D(
				Basis.looking_at(normal, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3.ONE * s),
				tip)
		if show_beam:
			_place_beam(beam, origin + dir * 0.05, tip)
		else:
			beam.visible = false
	else:
		reticle.visible = false
		if show_beam:
			_place_beam(beam, origin + dir * 0.05, origin + dir * STUB_LENGTH)
		else:
			beam.visible = false


func _place_beam(beam: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var v := to - from
	var len := v.length()
	if len < 0.01:
		beam.visible = false
		return
	beam.visible = true
	var y := v / len
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	beam.global_transform = Transform3D(Basis(x, y * len, z), from + v * 0.5)


func _hide_pointer_visuals(p: Dictionary) -> void:
	(p.beam as MeshInstance3D).visible = false
	(p.reticle as MeshInstance3D).visible = false


func _buzz(id: String, amplitude: float, seconds: float) -> void:
	if haptic_sink.is_valid():
		haptic_sink.call(id, amplitude, seconds)


# --- Actions ------------------------------------------------------------------------

func _activate(target: Dictionary, pointer_id: String) -> void:
	match String(target.kind):
		"tab":
			var k := int(target.key)
			if k == 4:
				select_settings()
			else:
				select_element(Elements.COMBAT_ELEMENTS[k])
			_buzz(pointer_id, 0.3, 0.03)
		"node":
			select_node(String(target.key))
			_buzz(pointer_id, 0.3, 0.03)
		"unlock":
			unlock_selected(pointer_id)
		"close":
			close_requested.emit()
		"settings":
			_handle_settings_action(String(target.key), pointer_id)


## Opens the SETTINGS tab on the page it was left on (audio, movement, access, controls).
func select_settings() -> void:
	canvas.is_settings_tab = true
	canvas.status_text = ""
	Sfx.play_at("ofuda_slice", global_position, -17.0, 4.0, 1.25)
	_redraw_now()


func select_element(el: String) -> void:
	canvas.is_settings_tab = false
	if not Elements.COMBAT_ELEMENTS.has(el):
		return
	canvas.element = el
	canvas.selected_id = canvas.default_node_for(el)
	canvas.status_text = ""
	Sfx.play_at("ofuda_slice", global_position, -17.0, 4.0, 1.25)
	_redraw_now()


func select_node(id: String) -> void:
	if SkillTreeData.node_by_id(id).is_empty():
		return
	canvas.selected_id = id
	canvas.status_text = ""
	Sfx.play_at("ofuda_slice", global_position, -17.0, 4.0, 1.1)
	_redraw_now()


## Buys the selected node through RunGame.unlock_skill (the only spending
## path). Returns that verdict ({} with no game attached).
func unlock_selected(pointer_id: String = "") -> Dictionary:
	if run_game == null or canvas.selected_id == "":
		return {}
	var id := canvas.selected_id
	var verdict := run_game.unlock_skill(id)
	canvas.balance = run_game.ofuda_count
	if bool(verdict.get("ok", false)):
		canvas.status_text = ""
		canvas.flash_unlock(id)
		Sfx.play_at("level_up", global_position, -9.0, 5.0, 1.15)
		Sfx.play_at("ofuda_slice", global_position, -10.0, 4.0, 0.9)
		_buzz(pointer_id, 0.75, 0.09)
		unlocked.emit(id)
	else:
		canvas.status_text = reason_text(String(verdict.get("reason", "")))
		canvas.flash_denied()
		Sfx.play_at("slap", global_position, -13.0, 4.0, 0.8)
		_buzz(pointer_id, 0.5, 0.05)
		denied.emit(id, String(verdict.get("reason", "")))
	_redraw_now()
	return verdict


static func reason_text(reason: String) -> String:
	match reason:
		SkillTreeData.REASON_PREREQUISITE:
			return "Master the earlier technique first."
		SkillTreeData.REASON_OFUDA:
			return "Find hokora shrines in the forest for more Ofuda."
		SkillTreeData.REASON_ALREADY_UNLOCKED:
			return "Already part of your school."
	return ""


## Settings buttons. A page button shows that page; every other button sets one
## value in VrComfortSettings (saved at once) or runs its action.
func _handle_settings_action(key: String, pointer_id: String) -> void:
	var player: Node3D = run_game.player if run_game else null
	if key.begins_with("page_"):
		canvas.settings_page = int(SkillTreeCanvas.SUBNAV_PAGE[key])
	elif VrComfortSettings:
		match key:
			"vignette_on":
				VrComfortSettings.set_vignette_enabled(true, player)
			"vignette_off":
				VrComfortSettings.set_vignette_enabled(false, player)
			"vignette_25":
				VrComfortSettings.set_vignette_strength(0.25, player)
			"vignette_50":
				VrComfortSettings.set_vignette_strength(0.50, player)
			"vignette_75":
				VrComfortSettings.set_vignette_strength(0.75, player)
			"vignette_100":
				VrComfortSettings.set_vignette_strength(1.00, player)
			"turn_snap":
				VrComfortSettings.set_snap_turning(true, player)
			"turn_smooth":
				VrComfortSettings.set_snap_turning(false, player)
			"snap_15":
				VrComfortSettings.set_snap_angle(15.0, player)
			"snap_30":
				VrComfortSettings.set_snap_angle(30.0, player)
			"snap_45":
				VrComfortSettings.set_snap_angle(45.0, player)
			"snap_60":
				VrComfortSettings.set_snap_angle(60.0, player)
			"snap_90":
				VrComfortSettings.set_snap_angle(90.0, player)
			"smooth_10":
				VrComfortSettings.set_smooth_turn_speed(1.0, player)
			"smooth_15":
				VrComfortSettings.set_smooth_turn_speed(1.5, player)
			"smooth_20":
				VrComfortSettings.set_smooth_turn_speed(2.0, player)
			"smooth_30":
				VrComfortSettings.set_smooth_turn_speed(3.0, player)
			"smooth_40":
				VrComfortSettings.set_smooth_turn_speed(4.0, player)
			"walk_slow":
				VrComfortSettings.set_walk_scale(0.7, player)
			"walk_normal":
				VrComfortSettings.set_walk_scale(1.0, player)
			"walk_fast":
				VrComfortSettings.set_walk_scale(1.3, player)
			"hand_right":
				VrComfortSettings.set_dominant_hand("right", player)
			"hand_left":
				VrComfortSettings.set_dominant_hand("left", player)
			"seated_off":
				VrComfortSettings.set_seated_mode(false, player)
			"seated_on":
				VrComfortSettings.set_seated_mode(true, player)
			"height_minus":
				VrComfortSettings.adjust_height(-VrComfortSettings.HEIGHT_STEP, player)
			"height_plus":
				VrComfortSettings.adjust_height(VrComfortSettings.HEIGHT_STEP, player)
			"height_reset":
				VrComfortSettings.reset_height(player)
			"recenter":
				if player is XRPlayer:
					(player as XRPlayer).recenter_view()
				else:
					XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
			"vol_master_dn", "vol_music_dn", "vol_sfx_dn", "vol_ambience_dn":
				VrComfortSettings.step_volume(_volume_key(key), -1)
			"vol_master_up", "vol_music_up", "vol_sfx_up", "vol_ambience_up":
				VrComfortSettings.step_volume(_volume_key(key), 1)
			"flash_100":
				VrComfortSettings.set_flash_percent(100)
			"flash_50":
				VrComfortSettings.set_flash_percent(50)
			"flash_0":
				VrComfortSettings.set_flash_percent(0)
			"haptic_0":
				VrComfortSettings.set_haptic_percent(0)
			"haptic_50":
				VrComfortSettings.set_haptic_percent(50)
			"haptic_100":
				VrComfortSettings.set_haptic_percent(100)
			"haptic_test":
				# Hears and feels the setting: one pulse on the katana hand.
				if player is XRPlayer:
					(player as XRPlayer).get_dominant_holder().pulse(0.6, 0.12)
	Sfx.play_at("ofuda_slice", global_position, -16.0, 4.0, 1.1)
	_buzz(pointer_id, 0.35, 0.04)
	_redraw_now()


## "vol_sfx_up" -> "sfx".
static func _volume_key(key: String) -> String:
	return key.split("_")[1]
