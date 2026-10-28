extends Node
## E2d: world-space UI never clips through geometry (docs/ELEMENTS_PLAN.md (e)(4)).
## The skill-tree panel is placed next to a tree, a boulder, a torii pillar, a
## wall and a standing yōkai, on hills, and nothing of the (scaled) panel may
## touch static world, trunks, gates, boulders or enemy bodies; when no clear
## spot exists the panel is flagged and drawn on top (no_depth_test,
## render_priority >= 100). Level-up talismans are held to the same standard.
##   godot --headless --path . --fixed-fps 90 res://tests/ui_clipping_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const GATE_SCENE := preload("res://scenes/world/torii_gate.tscn")

var failures := 0
var run: RunGame
var player: DesktopPlayer
var forest: ForestWorld
var _blockers: Array[Node] = []
var _prop_roots: Array[Node3D] = []


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://test_ui_clipping_save.cfg"
	add_child(run)
	await _frames(20)
	player = run.player as DesktopPlayer
	forest = run.forest_world
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	await _test_tree_nose_to_bark()
	await _test_tree_at_arm_length()
	await _test_wall_distances()
	await _test_blocked_falls_back_to_on_top()
	await _test_torii_pillar()
	await _test_standing_yokai()
	await _test_hills()
	await _test_level_up_cards_beside_obstacles()
	await _test_level_up_cards_beside_torii()
	_test_material_guarantees()
	run.queue_free()


# --- Scenarios --------------------------------------------------------------------

func _test_tree_nose_to_bark() -> void:
	await _stand_at(Vector3(0.0, 0.0, 0.0))
	var head := _head()
	# Trunk whose bark is about 0.30 m in front of the eyes.
	_add_prop(0, _ground(head + Vector3(0.0, 0.0, -(forest._trunk_chest_radius * 1.2 + 0.30))), 1.2)
	await _frames(3)
	var bark := _distance_ahead()
	_check("nose to bark: the bark really is close (%.2f m)" % bark, bark > 0.1 and bark < 0.6)
	var pose := _pose()
	# Either the panel turned (at most 50°, still in view) to free air, or no clear
	# spot exists and it is flagged for on-top drawing: never a silent overlap.
	if bool(pose.blocked):
		_check("nose to bark: no clear spot, so the panel is flagged blocked at the minimum distance (%.2f m)" % pose.distance,
			absf(float(pose.distance) - UiPlacement.MIN_DISTANCE) < 0.001)
	else:
		_check_pose("nose to bark", pose)
		_check("nose-to-bark: the panel turned %.0f° (≤ 50°) away from the trunk" % pose.yaw_offset_deg,
			absf(float(pose.yaw_offset_deg)) > 1.0 and absf(float(pose.yaw_offset_deg)) <= 50.0)
	_clear_blockers()


func _test_tree_at_arm_length() -> void:
	await _stand_at(Vector3(0.0, 0.0, 0.0))
	var head := _head()
	_add_prop(0, _ground(head + Vector3(0.0, 0.0, -(forest._trunk_chest_radius * 1.2 + 0.90))), 1.2)
	await _frames(3)
	var bark := _distance_ahead()
	var pose := _pose()
	_check_pose("tree about 0.9 m ahead", pose)
	_check("tree ahead: kept straight ahead and pulled %.2f m in front of the bark at %.2f m (panel %.2f m)" % [UiPlacement.WALL_MARGIN, bark, pose.distance],
		float(pose.yaw_offset_deg) == 0.0 and float(pose.distance) <= bark - UiPlacement.WALL_MARGIN + 0.001
		and float(pose.distance) >= UiPlacement.MIN_DISTANCE)
	_clear_blockers()


func _test_wall_distances() -> void:
	for wall_dist in [1.4, 1.1, 0.9]:
		await _stand_at(Vector3(0.0, 0.0, 0.0))
		var head := _head()
		_add_wall(Vector3(head.x, head.y, head.z - wall_dist - 0.1), Vector3(40.0, 8.0, 0.2))
		await _frames(3)
		var face := _distance_ahead()
		var pose := _pose()
		_check_pose("wall %.1f m ahead" % wall_dist, pose)
		var want := minf(UiPlacement.DEFAULT_DISTANCE, face - UiPlacement.WALL_MARGIN)
		_check("wall %.1f m ahead: panel pulled in front of it to %.2f m (wanted ≈ %.2f), scaled to match (%.2f)" % [wall_dist, pose.distance, want, pose.scale],
			float(pose.distance) <= maxf(want, UiPlacement.MIN_DISTANCE) + 0.001 and float(pose.distance) >= UiPlacement.MIN_DISTANCE
			and absf(float(pose.scale) - float(pose.distance) / UiPlacement.DEFAULT_DISTANCE) < 0.001 and not bool(pose.blocked))
		_clear_blockers()


func _test_blocked_falls_back_to_on_top() -> void:
	await _stand_at(Vector3(0.0, 0.0, 0.0))
	var head := _head()
	# A wall 0.5 m from the eyes, wide enough that turning does not help.
	_add_wall(Vector3(head.x, head.y, head.z - 0.6), Vector3(60.0, 8.0, 0.2))
	await _frames(3)
	var pose := _pose()
	_check("wall at 0.5 m leaves no clear spot: placement says blocked", bool(pose.blocked))
	_check("blocked placement keeps the minimum distance (%.2f m)" % pose.distance, absf(float(pose.distance) - UiPlacement.MIN_DISTANCE) < 0.001)
	# Through the real controller: the panel is drawn on top.
	run.pause_controller.open()
	var menu := run.pause_controller.menu
	_check("a blocked panel is drawn on top (no_depth_test, priority %d)" % menu._panel_mat.render_priority,
		menu.drawn_on_top and menu._panel_mat.no_depth_test and menu._panel_mat.render_priority >= 100)
	run.pause_controller.close()
	_clear_blockers()
	await _frames(2)
	run.pause_controller.open()
	_check("a clear panel is depth-tested, so hands and blade stay in front of it",
		not menu.drawn_on_top and not menu._panel_mat.no_depth_test)
	run.pause_controller.close()


func _test_torii_pillar() -> void:
	var gate: ToriiGate = GATE_SCENE.instantiate()
	run.add_child(gate)
	_blockers.append(gate)
	var worst_overlap := 0
	var blocked_count := 0
	var positions := 0
	for dx in [-1.6, -1.3, -1.0, -0.6, 0.0, 0.6, 1.0, 1.3, 1.6]:
		await _stand_at(Vector3(0.0, 0.0, 0.0))
		var feet := player.global_position
		gate.global_position = Vector3(feet.x - dx, feet.y, feet.z - 0.9)
		gate.global_rotation = Vector3.ZERO
		await _frames(3)
		var pose := _pose()
		positions += 1
		worst_overlap = maxi(worst_overlap, _overlaps(pose))
		if bool(pose.blocked):
			blocked_count += 1
	_check("torii: panel clear of the pillars and beams from 9 stances (worst overlap samples %d, %d flagged blocked)" % [worst_overlap, blocked_count],
		positions == 9 and (worst_overlap == 0 or blocked_count > 0))
	_check("torii: never needs the on-top fallback while standing at the gate", blocked_count == 0)
	_clear_blockers()


func _test_standing_yokai() -> void:
	await _stand_at(Vector3(0.0, 0.0, 0.0))
	var feet := player.global_position
	var yokai := run.wave_director.spawn_enemy_at(feet + Vector3(0.0, 0.0, -0.7), feet)
	await _frames(4)
	var pose := _pose()
	_check_pose("yōkai 0.7 m ahead", pose)
	var centre: Vector3 = pose.transform.origin
	_check("yōkai: the panel does not hang inside its body (%.2f m from its core)" % centre.distance_to(yokai.root_part().global_position),
		centre.distance_to(yokai.root_part().global_position) > 0.4 or bool(pose.blocked))
	run.wave_director.clear_enemies()


func _test_hills() -> void:
	var worst_bottom := INF
	var ok := true
	var spots := [Vector2(9.0, 7.0), Vector2(-13.0, 5.0), Vector2(6.0, -15.0), Vector2(-8.0, -11.0), Vector2(17.0, 14.0), Vector2(-18.0, 12.0)]
	for spot: Vector2 in spots:
		for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
			var feet := await _stand_at(Vector3(spot.x, 0.0, spot.y), yaw)
			var pose := _pose()
			var xf: Transform3D = pose.transform
			var half: Vector2 = SkillTreeMenu.PANEL_SIZE * 0.5 * float(pose.scale)
			for sx in [-1.0, 0.0, 1.0]:
				var corner := xf * Vector3(half.x * sx, -half.y, 0.0)
				var gap := corner.y - forest.height_at(corner.x, corner.z)
				worst_bottom = minf(worst_bottom, gap)
				if gap < 0.1:
					ok = false
			if _overlaps(pose) > 0 and not bool(pose.blocked):
				ok = false
	_check("hills: the panel's lower edge stays %.2f m above the terrain at 24 stances (≥ 0.10)" % worst_bottom, ok)
	_clear_blockers()


func _test_level_up_cards_beside_obstacles() -> void:
	await _stand_at(Vector3(0.0, 0.0, 0.0))
	var frame := run._player_view_frame()
	var fwd := -frame.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# A tree where the middle card would hang and a boulder where the right one would.
	_add_prop(0, _ground(frame.origin + fwd * 1.16), 1.0)
	_add_prop(3, _ground(frame.origin + fwd * 1.0 + frame.basis.x * 0.55), 1.6)
	await _frames(3)
	run.xp_to_next = 1
	run.add_xp(5)
	await _frames(5)
	var worst := 0
	for card in run.active_ofuda:
		worst += _card_overlaps(card)
	_check("level-up cards (%d) hang clear of a tree and a boulder (overlapping samples: %d)" % [run.active_ofuda.size(), worst],
		run.active_ofuda.size() == 3 and worst == 0)
	run.slice_ofuda_choice(1)
	TimeController.clear()
	await _frames(20)
	_clear_blockers()


func _test_level_up_cards_beside_torii() -> void:
	# A torii gate (not in the forest's trunk registry) straight ahead: the
	# talismans must not hang inside its pillars either.
	var gate: ToriiGate = GATE_SCENE.instantiate()
	run.add_child(gate)
	_blockers.append(gate)
	var worst := 0
	var stances := 0
	# Stances that put a pillar (at ±1.13 m from the gate's centre) right where a card would hang.
	for dx in [-1.13, 1.13, -0.75, 0.75, -1.5]:
		await _stand_at(Vector3(0.0, 0.0, 0.0))
		var feet := player.global_position
		gate.global_position = Vector3(feet.x - dx, feet.y, feet.z - 1.16)
		gate.global_rotation = Vector3.ZERO
		await _frames(3)
		run.xp_to_next = 1
		run.add_xp(5)
		await _frames(3)
		if run.active_ofuda.size() != 3:
			worst += 100
		for card in run.active_ofuda:
			worst += _card_overlaps(card)
		stances += 1
		run.slice_ofuda_choice(1)
		TimeController.clear()
		await _frames(25)
	_check("level-up cards hang clear of a torii gate from %d stances (overlapping samples: %d)" % [stances, worst], worst == 0)
	_clear_blockers()


func _test_material_guarantees() -> void:
	var menu := run.pause_controller.menu
	_check("panel material ignores fog (menu stays crisp in the milk fog)", menu._panel_mat.disable_fog)
	_check("panel sorts in a high render priority (%d)" % menu._panel_mat.render_priority, menu._panel_mat.render_priority >= 100)
	_check("pointer beam and reticle are always on top of the panel",
		menu._beam_mat.no_depth_test and menu._reticle_mat.no_depth_test
		and menu._beam_mat.render_priority > menu._panel_mat.render_priority
		and menu._reticle_mat.render_priority > menu._beam_mat.render_priority and menu._beam_mat.disable_fog)


# --- Helpers ----------------------------------------------------------------------

## Teleports the desktop rig to ground level at [param xz] and returns its feet.
func _stand_at(xz: Vector3, yaw := 0.0) -> Vector3:
	var y := forest.height_at(xz.x, xz.z)
	player.teleport(Vector3(xz.x, y, xz.z), yaw)
	# Let the body settle on the slope: the eyes must not move while we measure.
	var prev := Vector3.INF
	var still := 0
	for _i in 120:
		await get_tree().physics_frame
		still = still + 1 if player.global_position.distance_to(prev) < 0.0005 else 0
		prev = player.global_position
		if still >= 8:
			break
	return player.global_position


func _head() -> Vector3:
	return player.camera.global_position


## Distance from the eyes straight ahead (-Z) to the first solid.
func _distance_ahead() -> float:
	var head := _head()
	var ray := PhysicsRayQueryParameters3D.create(head, head + Vector3(0.0, 0.0, -4.0), UiPlacement.MASK)
	var hit := _space().intersect_ray(ray)
	return head.distance_to(hit.position) if not hit.is_empty() else INF


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, forest.height_at(p.x, p.z), p.z)


func _pose() -> Dictionary:
	return run.pause_controller._compute_pose()


func _add_prop(kind: int, pos: Vector3, scale: float) -> void:
	var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), pos)
	var root := Node3D.new()
	var body := forest._build_trunk_colliders([xf], kind, root)
	run.add_child(body)
	_blockers.append(body)
	_prop_roots.append(root)  # carries the registry entries _clear_blockers must forget


func _add_wall(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = centre  # before it enters the tree: never overlap the player at the origin
	run.add_child(body)
	_blockers.append(body)


func _clear_blockers() -> void:
	# Props the test planted are also registered in the forest's steering index.
	for root in _prop_roots:
		forest._forget_trunks(root)
		root.free()
	_prop_roots.clear()
	for b in _blockers:
		if is_instance_valid(b):
			b.queue_free()
	_blockers.clear()


func _space() -> PhysicsDirectSpaceState3D:
	return run.get_world_3d().direct_space_state


## Samples across the (scaled) panel; counts those within 5 cm of any solid.
func _overlaps(pose: Dictionary) -> int:
	var xf: Transform3D = pose.transform
	var half: Vector2 = SkillTreeMenu.PANEL_SIZE * 0.5 * float(pose.scale)
	var shape := SphereShape3D.new()
	shape.radius = 0.05
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = UiPlacement.MASK
	var hits := 0
	for ix in 7:
		for iy in 5:
			var local := Vector3(lerpf(-half.x, half.x, float(ix) / 6.0), lerpf(-half.y, half.y, float(iy) / 4.0), 0.0)
			q.transform = Transform3D(Basis.IDENTITY, xf * local)
			if not _space().intersect_shape(q, 1).is_empty():
				hits += 1
	return hits


func _card_overlaps(card: OfudaTalisman) -> int:
	var shape := BoxShape3D.new()
	shape.size = Vector3(OfudaTalisman.WIDTH, OfudaTalisman.HEIGHT, 0.04)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = ForestWorld.TRUNK_LAYER | 1
	q.transform = card.global_transform
	return _space().intersect_shape(q, 4).size()


func _check_pose(label: String, pose: Dictionary) -> void:
	var overlaps := _overlaps(pose)
	_check("%s: nothing within 5 cm of the panel (%d of 35 samples; blocked flag %s)" % [label, overlaps, pose.blocked],
		overlaps == 0 and not bool(pose.blocked))
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	var d: float = head.global_position.distance_to((pose.transform as Transform3D).origin)
	_check("%s: panel stays within comfortable reach (%.2f m, scale %.2f)" % [label, d, pose.scale],
		d >= UiPlacement.MIN_DISTANCE - 0.05 and d <= UiPlacement.DEFAULT_DISTANCE + 0.15 and float(pose.scale) <= 1.0)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
