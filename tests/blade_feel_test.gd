extends Node
## Headless checks for how the blade feels against bodies: it stays in the hand
## (never drifts or flies off and snaps back), it never wedges in the dummy,
## a handle grip always seats the sword the same way, and the cutting edge
## deals far more damage than the flat or the spine. Run:
##   godot --headless --path . --fixed-fps 90 res://tests/blade_feel_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")
## Hand roll about the blade (degrees) that puts the edge (-Y), the flat or the
## spine first when the hand sweeps toward -X.
const LEAD_EDGE := -90.0
const LEAD_FLAT := 0.0
const LEAD_SPINE := 90.0

var room: Node3D
var dummy: TrainingDummy
var player: DesktopPlayer
var katana: HeldWeapon
var failures := 0
var events: Array[Dictionary] = []


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	dummy = room.dummy
	player = room.player
	katana = room.katana
	GameEvents.event_logged.connect(func(e): events.append(e))
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _wait(0.5)
	player.holder.release()
	player.left_holder.release()
	player.teleport(Vector3(3.5, 0, 3.5))
	_test_strike_classification()
	await _test_fixed_handle_grip()
	await _test_edge_vs_flat_on_the_dummy()
	await _test_desktop_slash_leads_with_edge()
	await _test_no_wedging()
	await _test_heavy_body_cannot_tear_it_away()


# --- 3. Edge alignment ----------------------------------------------------------------

func _test_strike_classification() -> void:
	katana.global_transform = Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.2, 3.0))
	var mid := katana.global_transform * Vector3(0, 0, -0.5)
	var tip := katana.get_tip_global()
	var cases := [
		["edge", mid, Vector3.DOWN],
		["edge", mid, Vector3(0.3, -1.0, 0.0)],
		["flat", mid, Vector3.RIGHT],
		["spine", mid, Vector3.UP],
		["thrust", tip, Vector3.FORWARD],
		["hilt", katana.global_transform * Vector3(0, 0, 0.1), Vector3.DOWN],
	]
	var got := []
	var ok := true
	for c in cases:
		var s := katana.classify_strike(c[1], c[2])
		got.append("%s→%s×%.1f" % [c[0], s.kind, s.multiplier])
		ok = ok and s.kind == c[0]
	var edge := katana.classify_strike(mid, Vector3.DOWN)
	var flat := katana.classify_strike(mid, Vector3.RIGHT)
	var spine := katana.classify_strike(mid, Vector3.UP)
	_check("strike kind from the angle between motion and the edge (%s)" % ", ".join(got), ok)
	_check("multipliers: edge ×%.1f, flat ×%.1f, spine ×%.1f" % [edge.multiplier, flat.multiplier, spine.multiplier],
		is_equal_approx(edge.multiplier, 1.0) and is_equal_approx(flat.multiplier, 0.3) and is_equal_approx(spine.multiplier, 0.2))
	var club: Dictionary = room.kanabo.classify_strike(room.kanabo.global_transform * Vector3(0, 0, -0.6), Vector3.RIGHT)
	_check("the kanabō has no edge: same damage from every side (%s ×%.1f)" % [club.kind, club.multiplier], club.kind == "blunt" and club.multiplier == 1.0)


# --- 2. Handle grip is always the natural grip ---------------------------------------

func _test_fixed_handle_grip() -> void:
	var holder := _new_holder(Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.3, 3.0)))
	katana.global_transform = Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.3, 3.0))
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	await _wait(0.1)
	var results := []
	var all_ok := true
	# Hands coming in rolled, twisted and tilted, at the handle and at the guard.
	var approaches := [
		[Vector3(0, 0, 0.12), Basis(Vector3.BACK, deg_to_rad(120.0))],
		[Vector3(0, 0, 0.05), Basis.from_euler(Vector3(deg_to_rad(35.0), deg_to_rad(-40.0), deg_to_rad(-75.0)))],
		[Vector3(0, 0, -0.085), Basis(Vector3.BACK, deg_to_rad(180.0))],
	]
	for a in approaches:
		var hand := katana.global_transform * Transform3D(a[1], a[0])
		holder.global_transform = hand
		holder.grab(katana)
		var g := katana.get_local_grip(holder)
		await _wait(0.6)
		var edge_world := katana.global_basis * Vector3.DOWN
		var hand_down := -holder.global_basis.y
		var blade_world := -katana.global_basis.z
		var edge_ok := rad_to_deg(edge_world.angle_to(hand_down)) < 6.0 and rad_to_deg(blade_world.angle_to(-holder.global_basis.z)) < 6.0
		results.append("%s %.0f°" % [katana.get_grip_zone(holder), rad_to_deg(edge_world.angle_to(hand_down))])
		all_ok = all_ok and g.basis.is_equal_approx(Basis.IDENTITY) and edge_ok
		holder.release()
		katana.global_transform = Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.3, 3.0))
		katana.linear_velocity = Vector3.ZERO
		katana.angular_velocity = Vector3.ZERO
		await _wait(0.1)
	_check("handle / guard grip seats the sword the same way however the hand came in: blade out of the fist, edge on the fingers' side (%s)" % ", ".join(results), all_ok)
	# The blunt spine (half-swording) keeps the hand's own angle.
	var spine_hand := katana.global_transform * Transform3D(Basis(Vector3.BACK, deg_to_rad(90.0)), Vector3(0, 0.02, -0.4))
	holder.global_transform = spine_hand
	holder.grab(katana)
	var spine_grip := katana.get_local_grip(holder)
	_check("a grip on the blade spine keeps the hand's angle (zone %s)" % katana.get_grip_zone(holder),
		katana.get_grip_zone(holder) == HeldWeapon.ZONE_MUNE and not spine_grip.basis.is_equal_approx(Basis.IDENTITY))
	holder.release()
	holder.queue_free()


# --- 3. Edge vs flat vs spine on the dummy ----------------------------------------------

func _test_edge_vs_flat_on_the_dummy() -> void:
	var dmg := {}
	for lead in [LEAD_EDGE, LEAD_FLAT, LEAD_SPINE]:
		var hit := await _sweep_through_dummy(lead)
		dmg[lead] = hit
	var e: Dictionary = dmg[LEAD_EDGE]
	var f: Dictionary = dmg[LEAD_FLAT]
	var s: Dictionary = dmg[LEAD_SPINE]
	print("    sweeps: edge %s, flat %s, spine %s" % [_describe(e), _describe(f), _describe(s)])
	_check("the same sweep cuts with the edge, slaps with the flat, knocks with the spine",
		e.get("strike", "") == "edge" and f.get("strike", "") == "flat" and s.get("strike", "") == "spine")
	_check("edge does far more damage than the flat or the spine (%.1f vs %.1f / %.1f)" % [e.get("damage", 0.0), f.get("damage", 0.0), s.get("damage", 0.0)],
		e.get("damage", 0.0) > 0.0 and f.get("damage", 0.0) < e.get("damage", 0.0) * 0.45 and s.get("damage", 0.0) < e.get("damage", 0.0) * 0.35)


func _sweep_through_dummy(lead_deg: float) -> Dictionary:
	room.reset_room()
	await _wait(1.2)
	var basis := Basis(Vector3.BACK, deg_to_rad(lead_deg))
	var start := Transform3D(basis, Vector3(0.8, 1.25, 0.8))
	var holder := _new_holder(start)
	katana.global_transform = start
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	holder.grab(katana, Transform3D.IDENTITY)
	await _wait(0.5)
	events.clear()
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(holder, "global_position", Vector3(-0.8, 1.25, 0.8), 0.25)
	await _wait(0.6)
	holder.release()
	holder.queue_free()
	var hits := events.filter(func(ev): return ev.type == "hit")
	return hits[0] if not hits.is_empty() else {}


func _describe(hit: Dictionary) -> String:
	if hit.is_empty():
		return "no hit"
	return "%s %.1f dmg @ %.1f m/s (align %.2f)" % [hit.strike, hit.damage, hit.speed, hit.edge_alignment]


func _test_desktop_slash_leads_with_edge() -> void:
	room.reset_room()
	player.take_weapon(katana)
	player.teleport(Vector3(0, 0, 1.2))
	await _wait(1.0)
	events.clear()
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _wait(1.0)
	var hits := events.filter(func(ev): return ev.type == "hit")
	_check("desktop rig turns the wrist so a horizontal slash lands with the edge (%s)" % (_describe(hits[0]) if not hits.is_empty() else "no hit"),
		not hits.is_empty() and hits[0].strike == "edge")
	player.holder.release()
	player.teleport(Vector3(3.5, 0, 3.5))


# --- 1. Never wedged, never torn out of the hand --------------------------------------

func _test_no_wedging() -> void:
	# a) A light press against the chest: the blade rests on it, it doesn't sink in.
	var r: Dictionary = await _push_into_chest(0.06, 0.4)
	_check("light press: the blade rests on the body (no slide-through, grip %.3f m from the hand)" % r.max_offset,
		r.releases == 0 and r.max_offset <= katana.max_contact_offset + 0.01)
	# b) Shoving the hand deep into the dummy: the blade follows the hand instead
	# of wedging, never drifting more than the contact limit, and comes out clean.
	r = await _push_into_chest(0.5, 0.35)
	_check("deep shove: the blade stays in the hand (max %.3f m) and slides through instead of wedging (%d release)" % [r.max_offset, r.releases],
		r.releases >= 1 and r.max_offset <= katana.max_contact_offset + 0.03 and not r.snapped_back)
	_check("pulled back out: nothing left stuck (grip %.3f m, still ignoring %d parts)" % [r.after_offset, r.still_ignored],
		r.after_offset < 0.04 and r.still_ignored == 0)
	# c) A fast slash straight through the dummy.
	room.reset_room()
	await _wait(1.2)
	var start := Transform3D(Basis(Vector3.BACK, deg_to_rad(LEAD_EDGE)), Vector3(0.9, 1.2, 0.55))
	var holder := _new_holder(start)
	katana.global_transform = start
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	holder.grab(katana, Transform3D.IDENTITY)
	await _wait(0.5)
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(holder, "global_position", Vector3(-0.9, 1.2, 0.55), 0.2)
	var max_offset := 0.0
	var max_part_speed := 0.0
	var hand_before := holder.global_position
	for i in 54:
		await get_tree().physics_frame
		# The tween may move the hand after the weapon's tick: compare with the
		# hand the weapon saw, as in VR where tracking updates before physics.
		var grip := katana.global_transform * katana.get_local_grip(holder).origin
		max_offset = maxf(max_offset, minf(grip.distance_to(holder.global_position), grip.distance_to(hand_before)))
		hand_before = holder.global_position
		for p: RagdollPart in dummy.parts.values():
			max_part_speed = maxf(max_part_speed, p.linear_velocity.length())
	_check("fast slash through the dummy: the blade never leaves the hand (max %.3f m) and doesn't launch the dummy (parts ≤ %.1f m/s)" % [max_offset, max_part_speed],
		max_offset <= katana.max_contact_offset + 0.03 and max_part_speed < 8.0)
	holder.release()
	holder.queue_free()


func _push_into_chest(depth: float, seconds: float) -> Dictionary:
	room.reset_room()
	await _wait(1.2)
	var chest: RagdollPart = dummy.parts["chest"]
	# Blade horizontal, pointing at the chest from the dummy's right side, edge down.
	var front := chest.global_position + Vector3(0, 0, 0.75)
	var start := Transform3D(Basis.IDENTITY, front + Vector3(0, 0, 0.35))
	var holder := _new_holder(start)
	katana.global_transform = start
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	holder.grab(katana, Transform3D.IDENTITY)
	await _wait(0.4)
	# Bring the tip just to the surface, then push the hand further in.
	var touch := await _advance_until_contact(holder)
	events.clear()
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(holder, "global_position", touch + Vector3(0, 0, -depth), seconds)
	var max_offset := 0.0
	var snapped := false
	var last := _grip_offset(holder)
	for i in int((seconds + 0.3) * 90):
		await get_tree().physics_frame
		var off := _grip_offset(holder)
		max_offset = maxf(max_offset, off)
		snapped = snapped or (last > 0.2 and off < 0.02)
		last = off
	var releases := events.filter(func(e): return e.type == "blade_wedge_release").size()
	# Pull back out.
	tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(holder, "global_position", start.origin + Vector3(0, 0, 0.3), 0.4)
	await _wait(0.8)
	var still := 0
	for p in dummy.parts.values():
		if katana.is_sliding_through(p):
			still += 1
	var result := {"max_offset": max_offset, "releases": releases, "snapped_back": snapped,
		"after_offset": _grip_offset(holder), "still_ignored": still}
	holder.release()
	holder.queue_free()
	return result


## Move the hand toward -Z until the blade touches the dummy; returns the hand position.
func _advance_until_contact(holder: WeaponHolder) -> Vector3:
	for i in 120:
		holder.global_position += Vector3(0, 0, -0.005)
		await get_tree().physics_frame
		var st := PhysicsServer3D.body_get_direct_state(katana.get_rid())
		for c in st.get_contact_count():
			if st.get_contact_collider_object(c) is RagdollPart:
				return holder.global_position
	return holder.global_position


func _test_heavy_body_cannot_tear_it_away() -> void:
	var start := Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.3, 3.0))
	var holder := _new_holder(start)
	katana.global_transform = start
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	holder.grab(katana, Transform3D.IDENTITY)
	await _wait(0.4)
	var box := RigidBody3D.new()
	box.mass = 25.0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(0.3, 0.3, 0.3)
	box.add_child(shape)
	box.continuous_cd = true
	room.add_child(box)
	box.global_position = katana.global_transform * Vector3(1.0, 0, -0.6)
	box.linear_velocity = Vector3(-9.0, 0, 0)
	var max_offset := 0.0
	for i in 60:
		await get_tree().physics_frame
		max_offset = maxf(max_offset, _grip_offset(holder))
	_check("a 25 kg body slamming into the blade can't tear it from the hand (max grip offset %.3f m)" % max_offset,
		max_offset <= katana.max_grip_offset + 0.03)
	box.queue_free()
	holder.release()
	holder.queue_free()


# --- Helpers ----------------------------------------------------------------------------

func _new_holder(at: Transform3D) -> WeaponHolder:
	var holder := WeaponHolder.new()
	room.add_child(holder)
	holder.global_transform = at
	return holder


## How far the weapon's grip is from the hand right now (m).
func _grip_offset(holder: WeaponHolder) -> float:
	var g := katana.get_local_grip(holder)
	return (katana.global_transform * g.origin).distance_to(holder.global_transform.origin)


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
