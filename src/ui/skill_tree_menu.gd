class_name SkillTreeMenu
extends Node3D
## The skill-tree scroll (points from levels, D12) as a world-space panel with laser pointers
## (docs/ELEMENTS_PLAN.md Phase E2d), dressed as a physical object (N9).
##
## N9: the canvas sits in a lacquered board: a slightly curved plaque (cylinder
## of [constant CURVE_RADIUS], concave toward the player) with a raised frame, a
## chamfered front edge, a back plate that shows its thickness from the side,
## a thin gilt bead around the paper and gilt corner fittings. The frame is ONE
## mesh with its lantern light baked into vertex colours (one unshaded draw
## call, no scene lights, fog-proof); the paper is a second mesh that shows a
## [SkillTreeCanvas] rendered into a SubViewport (updated only when something
## changes). Opening lifts and unfolds the board in [constant OPEN_SECONDS] of
## real time (never game time or Engine.time_scale), closing lowers it in
## [constant CLOSE_SECONDS]; both play a paper-and-wood sound.
##
## Pointers ("left", "right", "mouse") are plain rays fed by
## [method update_pointer]: the menu intersects them with the curved paper,
## hit-tests the canvas, shows a beam and a reticle, pulses the hand on hover
## and acts on a trigger press. Buying a node goes through exactly one door,
## RunGame.unlock_skill(); the menu only displays the verdict.
##
## It processes while the tree is paused (process_mode ALWAYS). The panel
## material ignores fog; it is depth-tested normally (so the player's hands and
## blade stay in front of it) unless the placement code could not find a clear
## spot, in which case the paper and the frame are drawn on top.

signal close_requested
signal unlocked(node_id: String)
signal denied(node_id: String, reason: String)

## Paper size in metres at its default distance (UiPlacement scales it). N9: 1.44 m
## (was 1.2 m) so a 22 px body line is 1° tall from the eyes and 18 px fine print
## 0.84° (docs/n9/README.md); 0.9 mm per canvas pixel both ways.
const PANEL_SIZE := Vector2(1.44, 0.9)
## Radius of the cylinder the board is bent on (vertical axis on the viewer's side).
const CURVE_RADIUS := 2.4
## Frame: width around the paper, how far its face stands in front of the paper,
## how far the back plate sits behind it (metres, before scaling).
const FRAME_WIDTH := 0.036
const FRAME_FRONT := 0.014
const BOARD_DEPTH := 0.030
## The whole board, frame included: what UiPlacement must keep clear.
const OUTER_SIZE := Vector2(PANEL_SIZE.x + 2.0 * FRAME_WIDTH, PANEL_SIZE.y + 2.0 * FRAME_WIDTH)
## Columns of the curved meshes.
const CURVE_SEGMENTS := 40
const PRIORITY_PANEL := 100
const PRIORITY_BEAM := 103
const PRIORITY_RETICLE := 104
const BEAM_RADIUS := 0.0022
const STUB_LENGTH := 0.3
## Redraws per second for pulsing nodes and sparkle (state changes redraw at once).
const ANIM_FPS := 30.0
## The paper eases in over this many (real) seconds.
const FADE_IN_SECONDS := 0.16
## N9: the board lifts and unfolds over this many real seconds, and is set down in CLOSE_SECONDS.
const OPEN_SECONDS := 0.25
const CLOSE_SECONDS := 0.16
## Where the board starts its lift: this far below its rest, folded to this height.
const OPEN_DROP := 0.05
const OPEN_FOLD := 0.06
## Stick scrolling of the credits list (rows per second at full deflection).
const STICK_SCROLL_RATE := 7.0
const STICK_DEADZONE := 0.35
## Lantern light baked into the frame, in board space (above left, from the viewer's side).
const LIGHT_DIR := Vector3(-0.38, 0.62, 0.69)
const LACQUER_COLOR := Color(0.105, 0.032, 0.028)
const GOLD_COLOR := Color(0.80, 0.63, 0.37)

var run_game: RunGame
var canvas: SkillTreeCanvas
var is_open := false
var panel_scale := 1.0
## Whether the last [method open] could not find a clear spot (panel drawn on top).
var drawn_on_top := false
## Called as (pointer_id: String, amplitude: float, seconds: float) to buzz a hand.
var haptic_sink: Callable = Callable()

var _viewport: SubViewport
var _board: Node3D
var _panel: MeshInstance3D
var _panel_mat: StandardMaterial3D
var _frame: MeshInstance3D
var _frame_mat: StandardMaterial3D
## Real seconds since open() / close(); _closing while the board is being set down.
var _open_t := 1.0
var _close_t := 0.0
var _closing := false
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

	_board = Node3D.new()
	_board.name = "Board"
	add_child(_board)

	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_panel_mat.albedo_texture = _viewport.get_texture()
	_panel_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_panel_mat.disable_fog = true
	_panel_mat.render_priority = PRIORITY_PANEL
	_panel_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	_panel.mesh = build_paper_mesh()
	_panel.material_override = _panel_mat
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_panel.visible = false
	_board.add_child(_panel)

	_frame_mat = StandardMaterial3D.new()
	_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_mat.vertex_color_use_as_albedo = true
	_frame_mat.vertex_color_is_srgb = true
	_frame_mat.disable_fog = true
	_frame_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_frame = MeshInstance3D.new()
	_frame.name = "Frame"
	_frame.mesh = build_frame_mesh()
	_frame.material_override = _frame_mat
	_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_frame.visible = false
	_board.add_child(_frame)

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
	_frame_mat.no_depth_test = drawn_on_top
	canvas.tree = game.skill_tree
	canvas.balance = game.skill_points
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
	_frame.visible = true
	_closing = false
	_open_t = 0.0
	_redraw_accum = 0.0
	_age = 0.0
	_panel_mat.albedo_color.a = 0.0
	_apply_board_pose(0.0)
	_redraw_now()


## Stops taking input at once and sets the board down over [constant CLOSE_SECONDS]
## (real time); the node hides itself when the board is down.
func close() -> void:
	var was_shown := is_open or _closing
	is_open = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for id: String in _pointers.keys():
		_hide_pointer_visuals(_pointers[id])
		_pointers[id]["hover"] = {}
	if not was_shown or not visible:
		_finish_close()
		return
	_closing = true
	_close_t = 0.0


func _finish_close() -> void:
	_closing = false
	visible = false
	_panel.visible = false
	_frame.visible = false
	_apply_board_pose(1.0)


## 0 while the board is still folded at the start of its lift, 1 at rest (open or closed).
func open_progress() -> float:
	if _closing:
		return 1.0 - clampf(_close_t / CLOSE_SECONDS, 0.0, 1.0)
	return clampf(_open_t / OPEN_SECONDS, 0.0, 1.0) if is_open else 0.0


## True while the board lifts or is set down.
func is_animating() -> bool:
	return _closing or (is_open and _open_t < OPEN_SECONDS)


# --- Per-frame ----------------------------------------------------------------------

## Seconds of real time behind a _process [param delta]: Engine.time_scale scales
## delta, and the menu must never run slow (or stop) with a slow-mo or a pause.
static func real_delta(delta: float) -> float:
	if Engine.time_scale > 0.001:
		return delta / Engine.time_scale
	return 1.0 / 72.0


func _process(delta: float) -> void:
	var real := real_delta(delta)
	if _closing:
		_close_t += real
		var k := clampf(_close_t / CLOSE_SECONDS, 0.0, 1.0)
		_panel_mat.albedo_color.a = 1.0 - k
		_apply_board_pose(1.0 - k)
		if k >= 1.0:
			_finish_close()
		return
	if not is_open:
		return
	if _open_t < OPEN_SECONDS:
		_open_t += real
		_apply_board_pose(clampf(_open_t / OPEN_SECONDS, 0.0, 1.0))
	if _age < FADE_IN_SECONDS:
		_age += real
		var k := clampf(_age / FADE_IN_SECONDS, 0.0, 1.0)
		_panel_mat.albedo_color.a = k * k * (3.0 - 2.0 * k)
	canvas.advance(real)
	_redraw_accum += real
	if _redraw_accum >= 1.0 / ANIM_FPS:
		_redraw_accum = 0.0
		_redraw_now()


## The board at lift progress [param k] (0 folded and low, 1 at rest): it rises
## [constant OPEN_DROP] and unfolds from [constant OPEN_FOLD] of its height with a
## cubic ease-out, like a plaque lifted and opened toward the player.
func _apply_board_pose(k: float) -> void:
	var e := 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)
	var fold := lerpf(OPEN_FOLD, 1.0, e)
	_board.transform = Transform3D(Basis.from_scale(Vector3(lerpf(0.97, 1.0, e), fold, 1.0)),
			Vector3(0.0, -OPEN_DROP * (1.0 - e), 0.0))


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

## Where the ray (origin, dir) meets the curved paper: {"canvas": Vector2 px,
## "world": Vector3, "normal": Vector3 (world, toward the viewer), "distance": float}
## or {} when it misses (or comes from behind).
func ray_to_canvas(origin: Vector3, dir: Vector3) -> Dictionary:
	var inv := global_transform.affine_inverse()
	var hit := local_ray_hit(inv * origin, inv.basis * dir)
	if hit.is_empty():
		return {}
	var p: Vector3 = hit.point
	var px := Vector2((float(hit.u) / PANEL_SIZE.x + 0.5) * SkillTreeCanvas.SIZE.x,
			(0.5 - p.y / PANEL_SIZE.y) * SkillTreeCanvas.SIZE.y)
	var world := global_transform * p
	var normal := (global_basis * (hit.normal as Vector3)).normalized()
	return {"canvas": px, "world": world, "normal": normal, "distance": origin.distance_to(world)}


## Board-space hit of ray (o, d) on the paper cylinder: {point, u (arc length
## from the centre line), normal} or {}. Only the front sheet counts (the side
## facing the viewer), and only from the front.
static func local_ray_hit(o: Vector3, d: Vector3) -> Dictionary:
	var r := CURVE_RADIUS
	var ox := o.x
	var oz := o.z - r
	var a := d.x * d.x + d.z * d.z
	if a < 1e-10:
		return {}
	var b := 2.0 * (ox * d.x + oz * d.z)
	var c := ox * ox + oz * oz - r * r
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return {}
	var root := sqrt(disc)
	for t: float in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
		if t <= 0.0:
			continue
		var p := o + d * t
		var cz := r - p.z
		if cz <= 0.0:
			continue  # the far sheet of the cylinder
		var theta := atan2(p.x, cz)
		var u := theta * r
		if absf(u) > PANEL_SIZE.x * 0.5 or absf(p.y) > PANEL_SIZE.y * 0.5:
			continue
		var n := Vector3(-sin(theta), 0.0, cos(theta))
		if d.dot(n) >= 0.0:
			continue  # from behind the board
		return {"point": p, "u": u, "normal": n}
	return {}


## Board-space point at arc length [param u] (0 = centre line), height [param y],
## [param depth] metres in front of the paper (negative: behind it).
static func surface_point(u: float, y: float, depth := 0.0) -> Vector3:
	var theta := u / CURVE_RADIUS
	var rr := CURVE_RADIUS - depth
	return Vector3(rr * sin(theta), y, CURVE_RADIUS - rr * cos(theta))


## Board-space normal (toward the viewer) at arc length [param u].
static func surface_normal(u: float) -> Vector3:
	var theta := u / CURVE_RADIUS
	return Vector3(-sin(theta), 0.0, cos(theta))


## Board-space direction of growing [param u] along the bend.
static func surface_tangent(u: float) -> Vector3:
	var theta := u / CURVE_RADIUS
	return Vector3(cos(theta), 0.0, sin(theta))


## World position of canvas pixel [param px] on the paper (tests, screenshots).
func canvas_to_world(px: Vector2) -> Vector3:
	var u := (px.x / SkillTreeCanvas.SIZE.x - 0.5) * PANEL_SIZE.x
	var y := (0.5 - px.y / SkillTreeCanvas.SIZE.y) * PANEL_SIZE.y
	return global_transform * surface_point(u, y, 0.0)


## Angular height (degrees) of [param font_px] canvas pixels seen from
## [param distance] metres, at the panel's current scale.
func text_angle_deg(font_px: float, distance: float) -> float:
	var metres := font_px * PANEL_SIZE.y / SkillTreeCanvas.SIZE.y * panel_scale
	return rad_to_deg(2.0 * atan(metres * 0.5 / maxf(distance, 0.01)))


# --- Board geometry (N9) ------------------------------------------------------------

## The paper: a curved strip of [constant CURVE_SEGMENTS] columns, UV = canvas.
static func build_paper_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PANEL_SIZE * 0.5
	for i in CURVE_SEGMENTS:
		var u0 := lerpf(-half.x, half.x, float(i) / CURVE_SEGMENTS)
		var u1 := lerpf(-half.x, half.x, float(i + 1) / CURVE_SEGMENTS)
		var a := [surface_point(u0, half.y), surface_point(u1, half.y), surface_point(u1, -half.y), surface_point(u0, -half.y)]
		var uv := [Vector2(u0 / PANEL_SIZE.x + 0.5, 0.0), Vector2(u1 / PANEL_SIZE.x + 0.5, 0.0),
				Vector2(u1 / PANEL_SIZE.x + 0.5, 1.0), Vector2(u0 / PANEL_SIZE.x + 0.5, 1.0)]
		var n := [surface_normal(u0), surface_normal(u1), surface_normal(u1), surface_normal(u0)]
		_quad(st, a, n, [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE], uv, (n[0] as Vector3) + (n[1] as Vector3))
	return st.commit()


## The lacquered frame, back plate and gilt fittings as one mesh (one draw call),
## lit by [constant LIGHT_DIR] baked into the vertex colours.
static func build_frame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PANEL_SIZE * 0.5
	var fw := FRAME_WIDTH
	# Back plate first (drawn first when the board is drawn on top of the world).
	var ob := half + Vector2(fw, fw)
	for i in CURVE_SEGMENTS:
		var u0 := lerpf(-ob.x, ob.x, float(i) / CURVE_SEGMENTS)
		var u1 := lerpf(-ob.x, ob.x, float(i + 1) / CURVE_SEGMENTS)
		var pts := [surface_point(u0, ob.y, -BOARD_DEPTH), surface_point(u1, ob.y, -BOARD_DEPTH),
				surface_point(u1, -ob.y, -BOARD_DEPTH), surface_point(u0, -ob.y, -BOARD_DEPTH)]
		var nn := [-surface_normal(u0), -surface_normal(u1), -surface_normal(u1), -surface_normal(u0)]
		_quad_lit(st, pts, nn, false, 0.7)
	# The rim: a profile (outward offset from the paper's edge, depth) swept
	# around the paper with mitred corners. Inner gilt bead, flat lacquer face,
	# a chamfer that catches the light, the outer wall down to the back plate.
	var profile: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(0.0, FRAME_FRONT - 0.003), Vector2(0.004, FRAME_FRONT),
		Vector2(fw - 0.008, FRAME_FRONT), Vector2(fw, FRAME_FRONT - 0.008), Vector2(fw, -BOARD_DEPTH),
	]
	var gilt_segments := [0, 1]
	for k in profile.size() - 1:
		var p0 := profile[k]
		var p1 := profile[k + 1]
		var n2 := Vector2(-(p1.y - p0.y), p1.x - p0.x).normalized()  # (outward, depth) normal
		var gold := gilt_segments.has(k)
		_sweep_side(st, p0, p1, n2, gold, half, "top")
		_sweep_side(st, p0, p1, n2, gold, half, "bottom")
		_sweep_side(st, p0, p1, n2, gold, half, "left")
		_sweep_side(st, p0, p1, n2, gold, half, "right")
	# Gilt corner fittings: an L of two thin plates on the frame face at each corner.
	var face := FRAME_FRONT
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var ux: float = sx * (half.x + fw - 0.005)
			var uy: float = sy * (half.y + fw - 0.005)
			# Horizontal arm along the top/bottom rail, vertical arm along the side rail.
			_slab(st, minf(ux, ux - sx * 0.11), maxf(ux, ux - sx * 0.11),
					minf(uy, uy - sy * (fw - 0.012)), maxf(uy, uy - sy * (fw - 0.012)), face, face + 0.0028)
			_slab(st, minf(ux, ux - sx * (fw - 0.012)), maxf(ux, ux - sx * (fw - 0.012)),
					minf(uy, uy - sy * 0.11), maxf(uy, uy - sy * 0.11), face, face + 0.0028)
	return st.commit()


## One side of the rim between profile points [param p0] and [param p1].
static func _sweep_side(st: SurfaceTool, p0: Vector2, p1: Vector2, n2: Vector2, gold: bool,
		half: Vector2, side: String) -> void:
	var horizontal := side == "top" or side == "bottom"
	var sgn := 1.0 if side == "top" or side == "right" else -1.0
	var steps := CURVE_SEGMENTS if horizontal else 2
	for i in steps:
		var f0 := float(i) / steps
		var f1 := float(i + 1) / steps
		var pts := []
		var nn := []
		for corner in [[f0, p0], [f1, p0], [f1, p1], [f0, p1]]:
			var f: float = corner[0]
			var pp: Vector2 = corner[1]
			var u: float
			var y: float
			var out_dir: Vector3
			if horizontal:
				u = lerpf(-(half.x + pp.x), half.x + pp.x, f)
				y = sgn * (half.y + pp.x)
				out_dir = Vector3(0.0, sgn, 0.0)
			else:
				u = sgn * (half.x + pp.x)
				y = lerpf(-(half.y + pp.x), half.y + pp.x, f)
				out_dir = surface_tangent(u) * sgn
			pts.append(surface_point(u, y, pp.y))
			nn.append((out_dir * n2.x + surface_normal(u) * n2.y).normalized())
		_quad_lit(st, pts, nn, gold, 1.0)


## A thin raised gilt plate on the frame face, [u0, u1] x [y0, y1], depth d0..d1.
static func _slab(st: SurfaceTool, u0: float, u1: float, y0: float, y1: float, d0: float, d1: float) -> void:
	var um := (u0 + u1) * 0.5
	var nf := surface_normal(um)
	_quad_lit(st, [surface_point(u0, y1, d1), surface_point(u1, y1, d1), surface_point(u1, y0, d1), surface_point(u0, y0, d1)],
			[nf, nf, nf, nf], true, 1.0)
	var up := Vector3.UP
	_quad_lit(st, [surface_point(u0, y1, d0), surface_point(u1, y1, d0), surface_point(u1, y1, d1), surface_point(u0, y1, d1)],
			[up, up, up, up], true, 1.0)
	_quad_lit(st, [surface_point(u0, y0, d1), surface_point(u1, y0, d1), surface_point(u1, y0, d0), surface_point(u0, y0, d0)],
			[-up, -up, -up, -up], true, 1.0)
	var tl := -surface_tangent(u0)
	var tr := surface_tangent(u1)
	_quad_lit(st, [surface_point(u0, y0, d0), surface_point(u0, y1, d0), surface_point(u0, y1, d1), surface_point(u0, y0, d1)],
			[tl, tl, tl, tl], true, 1.0)
	_quad_lit(st, [surface_point(u1, y0, d1), surface_point(u1, y1, d1), surface_point(u1, y1, d0), surface_point(u1, y0, d0)],
			[tr, tr, tr, tr], true, 1.0)


static func _quad_lit(st: SurfaceTool, pts: Array, normals: Array, gold: bool, gain: float) -> void:
	var cols := []
	for i in 4:
		cols.append(shade(pts[i], normals[i], gold) * Color(gain, gain, gain, 1.0))
	var avg := (normals[0] as Vector3) + (normals[1] as Vector3) + (normals[2] as Vector3) + (normals[3] as Vector3)
	_quad(st, pts, normals, cols, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], avg)


## Two triangles facing [param facing] (Godot front faces wind clockwise).
static func _quad(st: SurfaceTool, pts: Array, normals: Array, cols: Array, uvs: Array, facing: Vector3) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	var geo := ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[2] as Vector3) - (pts[0] as Vector3))
	if geo.dot(facing) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		st.set_normal(normals[i])
		st.set_color(cols[i])
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


## Lantern light on lacquer or gilt at board point [param p] with normal [param n]:
## a soft key from above left, a sheen lobe toward the viewer, a faint rim.
static func shade(p: Vector3, n: Vector3, gold: bool) -> Color:
	var l := LIGHT_DIR.normalized()
	var v := (Vector3(0.0, 0.0, UiPlacement.DEFAULT_DISTANCE) - p).normalized()
	var h := (l + v).normalized()
	var ndl := maxf(n.dot(l), 0.0)
	var ndh := maxf(n.dot(h), 0.0)
	var fres := pow(1.0 - clampf(n.dot(v), 0.0, 1.0), 4.0)
	var c: Color
	if gold:
		c = GOLD_COLOR * (0.40 + 0.55 * ndl) + Color(1.0, 0.88, 0.62) * (0.55 * pow(ndh, 10.0))
	else:
		c = LACQUER_COLOR * (0.62 + 0.75 * ndl) + Color(1.0, 0.90, 0.80) * (0.20 * pow(ndh, 16.0) + 0.05 * fres)
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0)


## Feeds pointer [param id] a ray this frame. [param pressed] is the trigger
## state: its rising edge clicks whatever the ray rests on. [param show_beam]
## false (desktop) draws the reticle only.
func update_pointer(id: String, origin: Vector3, dir: Vector3, pressed: bool, show_beam := true) -> void:
	if not is_open:
		return
	var p := _pointer(id)
	var hit := ray_to_canvas(origin, dir.normalized())
	p.on_panel = not hit.is_empty()
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
	p.on_panel = false
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
		_pointers[id] = {"hover": {}, "pressed": false, "stamp": 0, "beam": beam, "reticle": reticle, "on_panel": false}
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
	var hot := not (p.hover as Dictionary).is_empty()
	if not hit.is_empty():
		var normal: Vector3 = hit.normal  # the curved paper's front at the hit
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
	_tick(1.0)
	_redraw_now()


## Opens SETTINGS on its CREDITS page (N9), at the top of the list.
func select_credits() -> void:
	canvas.is_settings_tab = true
	canvas.settings_page = SkillTreeCanvas.PAGE_CREDITS
	canvas.credits_first = 0
	canvas.status_text = ""
	_tick(1.0)
	_redraw_now()


## Scrolls the credits list by [param rows] (positive: down). True when it moved.
func scroll_credits(rows: int) -> bool:
	if not (canvas.is_settings_tab and canvas.settings_page == SkillTreeCanvas.PAGE_CREDITS):
		return false
	if not canvas.scroll_credits(rows):
		return false
	_tick(1.15, -22.0)
	_redraw_now()
	return true


## A thumbstick deflection [param stick_y] (up positive) from pointer [param id]
## scrolls the credits while that pointer rests on the panel: up to
## [constant STICK_SCROLL_RATE] rows a second, a light tick on the hand per row.
func stick_scroll(id: String, stick_y: float, real_seconds: float) -> void:
	if not is_open or not _pointers.has(id):
		return
	var p: Dictionary = _pointers[id]
	if not bool(p.get("on_panel", false)) or absf(stick_y) < STICK_DEADZONE:
		p["stick_acc"] = 0.0
		p["stick_held"] = false
		return
	var acc := float(p.get("stick_acc", 0.0))
	if not bool(p.get("stick_held", false)):
		p["stick_held"] = true
		acc = -signf(stick_y)  # the first row moves at once
	else:
		acc += -stick_y * STICK_SCROLL_RATE * real_seconds
	while absf(acc) >= 1.0:
		var step := int(signf(acc))
		acc -= float(step)
		if scroll_credits(step):
			_buzz(id, 0.10, 0.012)
		else:
			acc = 0.0
			break
	p["stick_acc"] = acc


## The paper-and-wood tick of a choice.
func _tick(pitch: float, volume_db := -15.0) -> void:
	Sfx.play_at("menu_tick", global_position, volume_db, 4.0, pitch)


func select_element(el: String) -> void:
	canvas.is_settings_tab = false
	if not Elements.COMBAT_ELEMENTS.has(el):
		return
	canvas.element = el
	canvas.selected_id = canvas.default_node_for(el)
	canvas.status_text = ""
	_tick(1.0)
	_redraw_now()


func select_node(id: String) -> void:
	if SkillTreeData.node_by_id(id).is_empty():
		return
	canvas.selected_id = id
	canvas.status_text = ""
	_tick(0.92)
	_redraw_now()


## Buys the selected node through RunGame.unlock_skill (the only spending
## path). Returns that verdict ({} with no game attached).
func unlock_selected(pointer_id: String = "") -> Dictionary:
	if run_game == null or canvas.selected_id == "":
		return {}
	var id := canvas.selected_id
	var verdict := run_game.unlock_skill(id)
	canvas.balance = run_game.skill_points
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
		SkillTreeData.REASON_POINTS:
			return "Every level gives one point. Keep fighting."
		SkillTreeData.REASON_ALREADY_UNLOCKED:
			return "Already part of your school."
	return ""


## Settings buttons. A page button shows that page; every other button sets one
## value in VrComfortSettings (saved at once) or runs its action.
func _handle_settings_action(key: String, pointer_id: String) -> void:
	var player: Node3D = run_game.player if run_game else null
	if key.begins_with("page_"):
		canvas.settings_page = int(SkillTreeCanvas.SUBNAV_PAGE[key])
	elif key == "credits_up" or key == "credits_down":
		canvas.scroll_credits(SkillTreeCanvas.CREDITS_STEP * (-1 if key == "credits_up" else 1))
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
			"weight_minus":
				VrComfortSettings.adjust_body_weight(-VrComfortSettings.WEIGHT_STEP)
			"weight_plus":
				VrComfortSettings.adjust_body_weight(VrComfortSettings.WEIGHT_STEP)
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
			"ai_toggle":
				VrComfortSettings.set_ai_boss_enabled(not VrComfortSettings.ai_boss_enabled)
			"ai_key_paste":
				if DisplayServer.clipboard_has():
					var text := DisplayServer.clipboard_get().strip_edges()
					if text != "":
						VrComfortSettings.set_meta_api_key(text)
			"ai_key_clear":
				VrComfortSettings.set_meta_api_key("")
			"ai_lang_pl":
				VrComfortSettings.set_ai_language("pl")
			"ai_lang_en":
				VrComfortSettings.set_ai_language("en")
			"sandbox_on":
				VrComfortSettings.set_sandbox_enabled(true)
			"sandbox_off":
				VrComfortSettings.set_sandbox_enabled(false)
	_tick(1.05, -14.0)
	_buzz(pointer_id, 0.35, 0.04)
	_redraw_now()


## "vol_sfx_up" -> "sfx".
static func _volume_key(key: String) -> String:
	return key.split("_")[1]
