extends Node
## Dismemberment: a very strong clean cut takes the limb off; weaker or
## non-edge hits never do. The body stays whole (the original part is hidden,
## never unjointed), the limb flies off and lands, a severed arm cannot claw,
## a leg or the head is fatal, and a pooled body comes back with all limbs.
## Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/dismember_test.tscn -- --desktop
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0
var run: RunGame
var director: WaveDirector


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	director = run.wave_director
	director.stop_director()
	director.clear_enemies()
	await _frames(4)

	var y := await _spawn(Vector3(0.0, 0.0, 5.0), 900.0)
	var arm: RagdollPart = y.parts["arm_l"]
	# Weak, wrist-only and flat hits never take a limb off.
	y.receive_hit(arm, _hit(arm, {"power": 0.4, "impulse": 6.0, "speed": 6.0}))
	y.receive_hit(arm, _hit(arm, {"strike": "flat"}))
	y.receive_hit(arm, _hit(arm, {"edge_alignment": 0.3}))
	_check("weak, flat or skewed cuts keep the arm on", not y.is_severed("arm_l") and arm.visible)

	var limbs_before := _limb_count()
	var hp_before := y.hp
	var hit := y.receive_hit(arm, _hit(arm, {}))
	_check("a full committed edge cut takes the arm off (severed=%s)" % hit.get("severed", ""),
		y.is_severed("arm_l") and hit.get("severed", "") == "arm_l")
	_check("the arm's part is hidden and touches nothing", not arm.visible and arm.collision_layer == 0 and arm.collision_mask == 0)
	_check("taking an arm off costs a big bite of HP (%.0f -> %.0f) but is not fatal" % [hp_before, y.hp],
		hp_before - y.hp >= y.profile.max_hp * 0.4 and not y.is_dead)
	await _frames(2)
	_check("a severed limb flies free (%d -> %d)" % [limbs_before, _limb_count()], _limb_count() == limbs_before + 1)
	var limb := _newest_limb()
	var worst := 0.0
	for i in 180:
		await get_tree().physics_frame
		worst = maxf(worst, _tear(y))
	_check("the body stays whole after losing the arm (worst tear %.2f m)" % worst, worst < 0.35)
	var gy := float(director.ground_height.call(limb.global_position.x, limb.global_position.z))
	_check("the limb landed on the terrain (%.2f m above ground)" % (limb.global_position.y - gy),
		absf(limb.global_position.y - gy) < 0.35)
	_check("a cut on the gone arm cannot sever it twice", not y.can_sever(arm, _hit(arm, {})))
	# A state change (knockdown) must not give the hidden arm collision back.
	y.weaken(0.0, 1.0)
	await _frames(2)
	_check("knockdown keeps the gone arm out of collision (mask %d)" % arm.collision_mask, arm.collision_mask == 0)
	await _frames(int(SeveredLimb.LIFETIME * 90.0))
	_check("the limb is gone after its lifetime", not is_instance_valid(limb))

	# A leg off is fatal; the pool hands the body back with every limb.
	var y2 := await _spawn(Vector3(2.0, 0.0, 6.0), 900.0)
	var leg: RagdollPart = y2.parts["leg_r"]
	var h2 := y2.receive_hit(leg, _hit(leg, {}))
	_check("taking a leg off kills (dead=%s, severed=%s)" % [y2.is_dead, h2.get("severed", "")], y2.is_dead and y2.is_severed("leg_r"))
	await _frames(150)
	var y3 := await _spawn(Vector3(-2.0, 0.0, 6.0), 900.0)
	var all_back := true
	for p in y3.parts.values():
		all_back = all_back and (p as RagdollPart).visible and (p as RagdollPart).collision_layer == 2
	_check("a recycled body comes back with every limb (%s)" % ("same body" if y3 == y2 else "new body"),
		all_back and not y3.is_severed("leg_r"))
	run.queue_free()


func _spawn(at: Vector3, hp: float) -> Yokai:
	at.y = float(director.ground_height.call(at.x, at.z))
	var y := director.spawn_enemy_at(at, Vector3.ZERO)
	y.configure_kind(Yokai.Kind.SWARM, Elements.NONE, hp)
	y.brain.set_physics_process(false) if y.brain else null
	await _frames(30)
	return y


## A committed, edge-on, fast katana cut on [param part]; [param over] tweaks it.
func _hit(part: RagdollPart, over: Dictionary) -> Dictionary:
	var h := {
		"attacker": "katana", "element": "physical", "part": String(part.name),
		"zone": String(part.get_meta("zone", "limb")), "speed": 14.0, "strike": "edge",
		"edge_alignment": 0.95, "base_damage": 20.0, "point": part.global_position,
		"direction": Vector3.RIGHT, "power": 1.0, "impulse": 18.0, "knockback": Vector3.RIGHT * 18.0,
	}
	h.merge(over, true)
	return h


func _limb_count() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c is SeveredLimb:
			n += 1
	return n


func _newest_limb() -> SeveredLimb:
	var out: SeveredLimb = null
	for c in get_tree().current_scene.get_children():
		if c is SeveredLimb:
			out = c
	return out


func _tear(e: ActiveRagdoll) -> float:
	var pelvis := e.root_part()
	var rest_root: Transform3D = e._rest[pelvis.name]
	var worst := 0.0
	for part_name in e.parts:
		if e is Yokai and (e as Yokai).is_severed(part_name):
			continue  # hidden, and free to hang however it likes
		var rest_d := ((e._rest[part_name] as Transform3D).origin - rest_root.origin).length()
		worst = maxf(worst, absf((e.parts[part_name] as RagdollPart).global_position.distance_to(pelvis.global_position) - rest_d))
	return worst


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
