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
	# Fixed global seed: the gameplay streams (spawner, brains, ragdoll poses, soul orbs) draw
	# from it, so the run is reproducible instead of depending on the launch's random seed.
	seed(20260603)
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_test_slicer()
	# Locks and purchases are checked here: a sandbox switch in the player's own file must not be read (D9).
	VrComfortSettings.sandbox_enabled = false
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

	# Death: the body falls, then comes apart into sakura petals on the wind.
	var before := get_tree().current_scene.get_children().filter(func(c): return c is SakuraScatter)
	y3.die({})
	var scatter: SakuraScatter = null
	var burst_frame := -1
	for i in 150:
		await get_tree().physics_frame
		for c in get_tree().current_scene.get_children():
			if c is SakuraScatter and not before.has(c) and (c as SakuraScatter).petal_count() == Yokai.DEATH_PETALS:
				scatter = c
		if scatter:
			burst_frame = i
			break
	_check("a dead yokai bursts into petals once it is down (frame %d, body visible %s)" % [burst_frame, y3.visible],
		scatter != null and not y3.visible)
	if scatter:
		var start := scatter.petal_center()
		var a0 := scatter.petal_alpha(0)
		# Two seconds of the petals' own (game) time.
		for i in 2000:
			if scatter._age >= 2.0:
				break
			await get_tree().physics_frame
		var drift := scatter.petal_center() - start
		var a1 := scatter.petal_alpha(0)
		_check("the petals ride the wind (drift %.2f m along it) and fade (alpha %.2f -> %.2f)" % [drift.dot(SakuraScatter.WIND.normalized()), a0, a1],
			drift.dot(SakuraScatter.WIND.normalized()) > 1.0 and a1 < a0 * 0.75)
		# (Kills can level up into the 0.2x upgrade slow-mo: count in game time.)
		for i in 2000:
			if not is_instance_valid(scatter):
				break
			await get_tree().physics_frame
		_check("the petals are gone after a few seconds", not is_instance_valid(scatter))
	await _test_kirisute()
	run.queue_free()


## D4 (Kirisute): with a school's finisher unlocked and its imbue running, a
## clean fast edge cut splits the body along the blade's plane. Plain steel,
## weak, flat or thrust contacts do not. Pieces are bounded, glow in the school's
## colour, touch only the terrain and are gone in time, and the katana keeps
## most of its speed through the cut (hand priority).
func _test_kirisute() -> void:
	var katana: HeldWeapon = run.katana
	var elem: ElementSystem = run.element_system
	var a := katana.get_blade_axis()
	var m := (katana.global_basis * -katana.spine_direction).normalized()
	var n := KirisuteCut.plane_normal(m, a)
	_check("the cut plane is normal to both the motion and the blade (n·m %.4f, n·a %.4f)" % [n.dot(m), n.dot(a)],
		absf(n.dot(m)) < 1e-4 and absf(n.dot(a)) < 1e-4 and absf(n.length() - 1.0) < 1e-4)
	_check("right × up gives the plane normal +Z (the upper half is +n)",
		KirisuteCut.plane_normal(Vector3.RIGHT, Vector3.UP).is_equal_approx(Vector3(0.0, 0.0, 1.0)))

	# Plain steel: nothing splits, however clean the cut.
	elem.reset()
	var plain := await _spawn(Vector3(0.0, 0.0, 5.0), 900.0)
	_cut(katana, plain.parts["chest"], 12.0)
	await _frames(2)
	_check("plain steel: a clean fast cut splits nothing (%d pieces)" % _chunk_count(), _chunk_count() == 0 and not plain.is_dead)

	# Imbued, but the school's finisher is still locked: still no split.
	elem.imbue(Elements.SAKURA)
	await _frames(2)
	var locked := await _spawn(Vector3(1.6, 0.0, 5.0), 900.0)
	_cut(katana, locked.parts["chest"], 12.0)
	await _frames(2)
	_check("imbued without the tier-5 finisher: no split (%d pieces)" % _chunk_count(), _chunk_count() == 0 and not katana.kirisute_ready)

	# Unlock the Sakura tree (Hanadachi sits on tier 5).
	run.skill_points = 1000
	for node: Dictionary in SkillTreeData.nodes_for_element(Elements.SAKURA):
		run.unlock_skill(String(node.id))
	elem.imbue(Elements.SAKURA)
	await _frames(2)
	_check("the imbued finisher is ready on the blade (Hanadachi)", katana.kirisute_ready)

	# Weak, flat and thrust contacts never split.
	var weak := await _spawn(Vector3(3.2, 0.0, 5.0), 900.0)
	_cut(katana, weak.parts["chest"], 3.0)
	var flat := await _spawn(Vector3(4.8, 0.0, 5.0), 900.0)
	_cut(katana, flat.parts["chest"], 12.0, katana.get_blade_axis())
	await _frames(2)
	_check("a slow cut (3 m/s), a flat or thrust contact split nothing (%d pieces)" % _chunk_count(),
		_chunk_count() == 0 and not weak.is_dead and not flat.is_dead)

	# A clean, fast cut splits the yōkai in two and kills it.
	var cut := await _spawn(Vector3(-1.6, 0.0, 5.0), 900.0)
	_cut(katana, cut.parts["chest"], 12.0)
	await _frames(2)
	var pieces := _chunks()
	_check("a clean fast cut kills and splits the yōkai into two pieces (%d pieces, dead %s)" % [pieces.size(), cut.is_dead],
		cut.is_dead and pieces.size() == 2)
	if pieces.size() == 2:
		var lower: KirisuteChunk = pieces[0]
		var upper: KirisuteChunk = pieces[1]
		_check("the pieces touch only the terrain (layer %d, mask %d)" % [lower.collision_layer, lower.collision_mask],
			lower.collision_layer == 0 and lower.collision_mask == 1 and upper.collision_mask == 1)
		var glow := KirisuteCut.glow_color(Elements.SAKURA)
		_check("the cut glows in the school's colour (emission %s)" % [lower.cap_material.emission],
			lower.cap_material.emission.is_equal_approx(glow) and lower.cap_material.emission_enabled)

	# Budget: ten rounds of cuts, two per physics frame; the third in a frame stays a plain hit.
	elem.imbue(Elements.SAKURA)
	var crowd: Array[Yokai] = []
	var deaths := [0]
	for i in 30:
		var at := Vector3(-6.0 + 0.5 * i, 0.0, 12.0)
		at.y = float(director.ground_height.call(at.x, at.z))
		var y := director.spawn_enemy_at(at, Vector3.ZERO)
		y.configure_kind(Yokai.Kind.SWARM, Elements.NONE, 900.0)
		y.brain.set_physics_process(false) if y.brain else null
		y.died.connect(func(_y: Yokai, _hit: Dictionary) -> void: deaths[0] += 1)
		_spare_katana(y)
		crowd.append(y)
	await _frames(30)
	var worst := 0
	var third_plain := true
	var first_piece: KirisuteChunk = null
	for round_i in 10:
		var base := round_i * 3
		_cut(katana, crowd[base].parts["chest"], 12.0)
		_cut(katana, crowd[base + 1].parts["chest"], 12.0)
		_cut(katana, crowd[base + 2].parts["chest"], 12.0)
		third_plain = third_plain and not crowd[base + 2].is_dead
		if first_piece == null and _chunk_count() > 0:
			first_piece = _chunks()[0]
		worst = maxi(worst, _chunk_count())
		# Each kill starts a hit-stop; wait for it to end so the rounds do not stack one long freeze.
		await _frames(1)
		while TimeController.is_active("hit_stop"):
			await _frames(1)
	# Counted from the died signal: a pooled yōkai beyond the pool cap is freed, so
	# its is_dead can no longer be read.
	var dead: int = deaths[0]
	_check("two cuts a frame split, the third is a plain hit (third plain %s)" % third_plain, third_plain)
	_check("twenty split cuts kill twenty yōkai (%d dead of 30)" % dead, dead == 20)
	_check("the pieces never exceed the Quest budget (worst %d of %d)" % [worst, ElementBalance.KIRISUTE_MAX_PIECES],
		worst <= ElementBalance.KIRISUTE_MAX_PIECES and worst > 0)
	_check("the oldest pieces are freed first (first piece gone: %s)" % (first_piece == null or not is_instance_valid(first_piece)),
		first_piece == null or not is_instance_valid(first_piece))

	# The katana keeps most of its speed through a Kirisute cut: the same impulse, the
	# same state, at a quarter of the bite (HeldWeapon scales it for a Kirisute hit).
	var contact := {"collider": null, "point": katana.global_position, "speed": 12.0,
		"direction": Vector3.DOWN, "normal": Vector3.UP}
	var mom := {"power": 1.0, "mass": katana.mass, "impulse": 6.0}
	var start := Vector3(0.0, 0.0, -6.0)
	katana.linear_velocity = start
	katana._apply_cut_resistance(contact, mom, "edge", 1.0)
	var plain_loss := (start - katana.linear_velocity).length()
	katana.linear_velocity = start
	katana._apply_cut_resistance(contact, mom, "edge", 0.25)
	var cut_loss := (start - katana.linear_velocity).length()
	_check("a Kirisute cut costs the katana a quarter of a plain cut's speed (%.2f vs %.2f m/s)" % [cut_loss, plain_loss],
		plain_loss > 0.5 and absf(cut_loss - plain_loss * 0.25) < plain_loss * 0.02)

	# The Oni is wounded, not cut in two: a clean cut opens a glowing wound and costs it HP.
	var oni := director.spawn_oni_boss(Vector3(0.0, 0.0, -2.0))
	await _frames(20)
	var oni_hp := oni.hp
	var pieces_before := _chunk_count()
	_cut(katana, oni.parts["chest"], 12.0)
	await _frames(2)
	var open_wounds := 0
	for w in oni._wounds:
		open_wounds += int(is_instance_valid(w))
	_check("the Oni takes a wound, not a split (hp %.0f -> %.0f, open wounds %d, new pieces %d)" % [oni_hp, oni.hp, open_wounds, _chunk_count() - pieces_before],
		not oni.is_dead and oni.hp < oni_hp and open_wounds == 1 and _chunk_count() == pieces_before)
	await _frames(int(ElementBalance.KIRISUTE_WOUND_SECONDS * 90.0) + 20)
	open_wounds = 0
	for w in oni._wounds:
		open_wounds += int(is_instance_valid(w))
	_check("the wound closes after %.1f s (%d open)" % [ElementBalance.KIRISUTE_WOUND_SECONDS, open_wounds], open_wounds == 0)

	# Pieces dissolve into petals and are gone in time.
	await _frames(int((ElementBalance.KIRISUTE_PIECE_SECONDS + ElementBalance.KIRISUTE_DISSOLVE_SECONDS) * 90.0) + 30)
	_check("every piece is gone after its lifetime (%d left)" % _chunk_count(), _chunk_count() == 0)


## A contact with the torso of a yōkai: the blade meets [param part] at [param speed]
## moving across its edge, or along [param direction] when given.
func _cut(weapon: HeldWeapon, part: RagdollPart, speed: float, direction := Vector3.ZERO) -> void:
	_pose_blade(weapon, part)
	var dir := direction
	if dir == Vector3.ZERO:
		dir = (weapon.global_basis * -weapon.spine_direction).normalized()
	weapon._handle_hit({"collider": part, "point": part.global_position, "speed": speed,
		"direction": dir, "normal": -dir})


## Hangs the katana mid-blade on [param part], edge toward the body, without striking it.
func _pose_blade(weapon: HeldWeapon, part: RagdollPart) -> void:
	weapon.global_transform = Transform3D(Basis.IDENTITY, part.global_position + Vector3(0.0, 0.0, 0.5))


func _chunks() -> Array[KirisuteChunk]:
	var out: Array[KirisuteChunk] = []
	for c: KirisuteChunk in KirisuteChunk._alive:
		if is_instance_valid(c):
			out.append(c)
	return out


func _chunk_count() -> int:
	return _chunks().size()


func _spawn(at: Vector3, hp: float) -> Yokai:
	at.y = float(director.ground_height.call(at.x, at.z))
	var y := director.spawn_enemy_at(at, Vector3.ZERO)
	# Fixed pose variation and sway: the body's random posture moves the tear and the landing.
	y.set_motion_seed(7)
	y.configure_kind(Yokai.Kind.SWARM, Elements.NONE, hp)
	y.brain.set_physics_process(false) if y.brain else null
	_spare_katana(y)
	await _frames(30)
	return y


## The katana is posed by the test, not swung: keep it from colliding with the
## test yōkai physically, so only the hits the test reports can land.
func _spare_katana(y: Yokai) -> void:
	var katana: HeldWeapon = run.katana
	for p: RagdollPart in y.parts.values():
		katana.add_collision_exception_with(p)


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


## The mesh cut behind Kirisute (docs/ELEMENTS_PLAN.md, D4 §3): a convex
## primitive cut by a plane gives two halves that close on the cut, add up to
## the whole, wind the way their normals say, and leave the cap as its own surface.
func _test_slicer() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.062
	capsule.height = 0.82
	capsule.radial_segments = 10
	capsule.rings = 2
	var cases := [
		["box", box, Vector3(0.05, 0.0, 0.0), Vector3.RIGHT],
		["capsule", capsule, Vector3(0.01, 0.1, 0.0), Vector3(0.6, 0.8, 0.1)],
	]
	for c: Array in cases:
		var label: String = c[0]
		var arrays := MeshSlicer.surface_arrays(c[1])
		var whole_verts := _expand_arrays(arrays)
		var whole := MeshSlicer.volume_of(whole_verts)
		var p: Vector3 = c[2]
		var n: Vector3 = (c[3] as Vector3).normalized()
		var halves := MeshSlicer.cut(arrays, p, n)
		var above: Dictionary = halves["above"]
		var below: Dictionary = halves["below"]
		var s := MeshSlicer.winding_sign(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_INDEX])
		var open_above := _open_rim_edges(above["verts"], p, n)
		var open_below := _open_rim_edges(below["verts"], p, n)
		_check("%s cut in two halves that close on the cut (open rim edges %d and %d)" % [label, open_above, open_below],
			open_above == 0 and open_below == 0 and (above["verts"] as PackedVector3Array).size() > 0)
		var sum := float(above["volume"]) + float(below["volume"])
		_check("%s halves add up to the whole (%.4f vs %.4f m³)" % [label, sum, whole],
			absf(sum - whole) <= whole * 0.05)
		_check("%s triangles wind with their normals on both halves" % label,
			_bad_winding(above, s) == 0 and _bad_winding(below, s) == 0)
		var cap_from: int = above["cap_from"]
		_check("%s the cap is its own surface after the skin (cap starts at %d of %d)" % [label, cap_from, (above["verts"] as PackedVector3Array).size()],
			cap_from > 0 and cap_from < (above["verts"] as PackedVector3Array).size())
		var coll := MeshSlicer.decimate_points(arrays[Mesh.ARRAY_VERTEX], 32)
		_check("%s collision hull stays at 32 points or fewer (%d)" % [label, coll.size()], coll.size() <= 32)


## Triangle list of an indexed surface, with the index applied.
func _expand_arrays(arrays: Array) -> PackedVector3Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index = arrays[Mesh.ARRAY_INDEX]
	if index == null:
		return verts
	var out := PackedVector3Array()
	for i: int in index:
		out.append(verts[i])
	return out


## Edges that lie on the plane and are not used by exactly two triangles.
## Matched by distance, not by rounding, so float noise cannot split an edge.
func _open_rim_edges(verts: PackedVector3Array, p: Vector3, n: Vector3) -> int:
	var rim: Array = []
	for i in range(0, verts.size(), 3):
		for k in 3:
			var a := verts[i + k]
			var b := verts[i + (k + 1) % 3]
			if absf(n.dot(a - p)) < 1e-4 and absf(n.dot(b - p)) < 1e-4 and a.distance_to(b) > 1e-4:
				rim.append([a, b])
	var open := 0
	for e: Array in rim:
		var uses := 0
		for f: Array in rim:
			if (e[0].distance_to(f[0]) < 1e-4 and e[1].distance_to(f[1]) < 1e-4) \
					or (e[0].distance_to(f[1]) < 1e-4 and e[1].distance_to(f[0]) < 1e-4):
				uses += 1
		if uses != 2:
			open += 1
	return open


## Triangles whose geometric winding disagrees with their vertex normal.
func _bad_winding(side: Dictionary, s: float) -> int:
	var verts: PackedVector3Array = side["verts"]
	var norms: PackedVector3Array = side["normals"]
	var bad := 0
	for i in range(0, verts.size(), 3):
		var g := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
		if g.length_squared() > 1e-14 and g.dot(norms[i]) * s <= 0.0:
			bad += 1
	return bad


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
