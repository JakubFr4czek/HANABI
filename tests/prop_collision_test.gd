extends Node
## Props collide where they visibly end: rays at the tree trunk, a gate
## pillar, a boulder and a lantern from eight directions must stop on the
## collider within a few cm of where they meet the drawn mesh (never deep
## inside it), and the blades collide with them. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/prop_collision_test.tscn -- --desktop
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")
const MESH_LAYER := 1 << 24

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(20)
	run.wave_director.stop_director()
	var forest := run.forest_world
	var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.2), Vector3(400.0, 50.0, 400.0))
	await _compare("tree trunk", forest._tree_mesh, forest._build_trunk_colliders([xf], 0, Node3D.new()), xf, [0.6, 1.2, 1.8, 2.6])
	var gate_xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 3.5), Vector3(420.0, 50.0, 400.0))
	# Right pillar centre, measured on the mesh just above the footing.
	var xs := PackedFloat32Array()
	for p in forest._torii_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if p.x > 0.0 and p.y > 0.13 and p.y < 0.27:
			xs.append(p.x)
	var span: float = (float(Array(xs).min()) + float(Array(xs).max())) * 0.5 * 3.5
	await _compare("gate pillar", forest._torii_mesh, forest._build_trunk_colliders([gate_xf], 1, Node3D.new()),
		gate_xf, [0.2, 0.5], Vector3(span, 0.0, 0.0), 0.25)
	var lantern_xf := Transform3D(Basis.IDENTITY, Vector3(440.0, 50.0, 400.0))
	await _compare("lantern", forest._lantern_mesh, forest._build_trunk_colliders([lantern_xf], 2, Node3D.new()), lantern_xf, [0.2, 0.55])
	var rock_xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.6), Vector3(460.0, 50.0, 400.0))
	await _compare("boulder", forest._rock_mesh, forest._build_trunk_colliders([rock_xf], 3, Node3D.new()), rock_xf, [0.1, 0.2])
	_check("the katana collides with trunks, gates, lanterns and boulders",
		(run.katana.collision_mask & ForestWorld.TRUNK_LAYER) != 0)

	# Talismans and the stele never spawn inside a tree: plant one right
	# where the middle card would go and level up.
	var frame := run._player_view_frame()
	var spot := frame.origin + Vector3(-frame.basis.z.x, 0.0, -frame.basis.z.z).normalized() * 1.16
	spot.y = forest.height_at(spot.x, spot.z)
	var blocker := forest._build_trunk_colliders([Transform3D(Basis.IDENTITY, spot)], 0, Node3D.new())
	run.add_child(blocker)
	run.xp_to_next = 1
	run.add_xp(5)
	await _frames(5)
	var worst := INF
	for card in run.active_ofuda:
		worst = minf(worst, Vector2(card.global_position.x - spot.x, card.global_position.z - spot.z).length())
	_check("level-up talismans steer clear of a tree in the way (closest %.2f m from its axis)" % worst,
		not run.active_ofuda.is_empty() and worst > forest._trunk_chest_radius + 0.3)
	run.slice_ofuda_choice(1)
	await _frames(30)
	var dp := run.player as DesktopPlayer
	dp.health._invulnerable = 0.0
	dp.health.take_hit(10000.0, dp.global_position + Vector3.FORWARD)
	await _frames(10)
	var rp := run.restart_ofuda.global_position
	_check("the restart talisman steers clear of it too (%.2f m)" % Vector2(rp.x - spot.x, rp.z - spot.z).length(),
		Vector2(rp.x - spot.x, rp.z - spot.z).length() > forest._trunk_chest_radius + 0.3)
	run.queue_free()


## Cast rays inward at [param heights] (mesh-space y, times the scale) from 8
## directions; compare the collider's hit with the exact mesh's hit.
func _compare(label: String, mesh: Mesh, collider: StaticBody3D, xf: Transform3D, heights: Array, center_off := Vector3.ZERO, reach := 3.0) -> void:
	add_child(collider)
	var exact := StaticBody3D.new()
	exact.collision_layer = MESH_LAYER
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	cs.transform = xf
	exact.add_child(cs)
	add_child(exact)
	await _frames(2)
	var space := get_viewport().world_3d.direct_space_state
	var s := xf.basis.get_scale().x
	var worst_out := 0.0
	var worst_in := 0.0
	var rays := 0
	for h in heights:
		for k in 8:
			var ang := TAU * float(k) / 8.0
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var center := xf.origin + center_off + Vector3.UP * float(h) * s
			var from := center + dir * reach * s
			var hit_c := _ray(space, from, center, ForestWorld.TRUNK_LAYER)
			var hit_m := _ray(space, from, center, MESH_LAYER)
			if hit_m.is_empty():
				continue
			rays += 1
			if hit_c.is_empty():
				worst_in = INF
				continue
			# Positive: the collider stops the ray before the surface (outside);
			# negative: the ray reached into the drawn object.
			var d := from.distance_to(hit_m.position) - from.distance_to(hit_c.position)
			worst_out = maxf(worst_out, d)
			worst_in = maxf(worst_in, -d)
	print("    %s: %d rays, collider up to %.3f m outside the surface, %.3f m inside" % [label, rays, worst_out, worst_in])
	_check("%s collides where it is drawn (%.3f m in, %.3f m out)" % [label, worst_in, worst_out],
		rays >= 8 and worst_in < 0.03 and worst_out < 0.12 * maxf(s, 1.0))
	collider.queue_free()
	exact.queue_free()


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	return space.intersect_ray(q)


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
