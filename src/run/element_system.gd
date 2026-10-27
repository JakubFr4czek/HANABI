class_name ElementSystem
extends Node3D
## Quest-conscious combat implementation for the four run elements (GDD §5).
## Effects are bounded: 16 flying petals, 6 ink pools, one orbit set and short
## mesh-based lightning/darkness events. No realtime lights or screen effects.

signal effect_triggered(type: String, data: Dictionary)

const PETAL_SHADER := preload("res://src/shaders/sakura_petal.gdshader")
const INK_SHADER := preload("res://src/shaders/ink_pool.gdshader")
const SHADOW_SHADER := preload("res://src/shaders/shadow_darkness.gdshader")
const MAX_PETALS := 12
const MAX_INK_POOLS := 6
const MAX_TRANSIENT_MESHES := 18

var run_game: RunGame
var weapon: HeldWeapon
var active_elements: Array[String] = []
var evolutions: Array[String] = []
var stacks: Dictionary = {}

var storm_charge := 0.0
var blink_cooldown := 0.0

var _petals: Array[Dictionary] = []
var _orbit_petals: Array[MeshInstance3D] = []
var _orbit_hits := {}
var _ink_pools: Array[Dictionary] = []
var _transients: Array[Dictionary] = []
var _darkness_areas: Array[Dictionary] = []
var _prev_tip := Vector3.ZERO
var _petal_swing_cooldown := 0.0
var _chain_cooldown := 0.0
var _charge_vfx_cooldown := 0.0
var _orbit_clock := 0.0
var _rng := RandomNumberGenerator.new()
var _petal_mesh: QuadMesh
var _petal_mat: ShaderMaterial
var _phantom_petal_mat: ShaderMaterial


func setup(p_run_game: RunGame, p_weapon: HeldWeapon) -> void:
	run_game = p_run_game
	weapon = p_weapon
	_rng.seed = 0x48414E414249
	_prev_tip = weapon.get_tip_global() if weapon else Vector3.ZERO
	_build_shared_petals()


func reset() -> void:
	active_elements.clear()
	evolutions.clear()
	stacks.clear()
	storm_charge = 0.0
	blink_cooldown = 0.0
	_petal_swing_cooldown = 0.0
	_chain_cooldown = 0.0
	_charge_vfx_cooldown = 0.0
	_clear_runtime_vfx()
	if weapon:
		weapon.set_element(Elements.NONE)


func apply_upgrade(id: String, all_stacks: Dictionary) -> void:
	stacks = all_stacks.duplicate()
	var element := UpgradePool.element_for_upgrade(id)
	if element != Elements.NONE and not active_elements.has(element):
		if active_elements.size() >= 2:
			return
		active_elements.append(element)
	_refresh_evolutions()
	_rebuild_orbit_petals()
	if weapon:
		weapon.set_element(visual_element())
	effect_triggered.emit("upgrade", {"id": id, "element": element, "evolutions": evolutions.duplicate()})


func visual_element() -> String:
	if evolutions.has(Elements.BLACK_LIGHTNING):
		return Elements.BLACK_LIGHTNING
	if evolutions.has(Elements.PHANTOM_PETALS):
		return Elements.PHANTOM_PETALS
	return active_elements[-1] if not active_elements.is_empty() else Elements.NONE


func has_evolution(id: String) -> bool:
	return evolutions.has(id)


func on_blade_hit(hit: Dictionary) -> void:
	if run_game == null or weapon == null or float(hit.get("damage", 0.0)) <= 0.0:
		return
	if String(hit.get("attacker", "")) != weapon.weapon_name:
		return
	var point: Vector3 = hit.get("point", weapon.get_tip_global())
	var direction: Vector3 = hit.get("direction", Vector3.FORWARD)

	if active_elements.has(Elements.SAKURA):
		var petal_targets := _nearest_enemies(point, 1, 1.2)
		if not petal_targets.is_empty():
			petal_targets[0].receive_element_damage(3.0, Elements.SAKURA, point, direction)
		if is_inside_tree() and get_tree().current_scene:
			SparkBurst.spawn(get_tree().current_scene, point, direction, Elements.color(Elements.SAKURA), 6, 1.2)
	if active_elements.has(Elements.STORM) and _chain_cooldown <= 0.0:
		_chain_cooldown = 0.30
		_release_chain_lightning(point, direction)
	if active_elements.has(Elements.INK):
		paint_ink(point)
	if active_elements.has(Elements.SHADOW):
		for enemy in _nearest_enemies(point, 1, 1.4):
			enemy.apply_confusion(0.75 if not has_evolution(Elements.PHANTOM_PETALS) else 1.6)

	if int(stacks.get("storm_charge", 0)) > 0 and storm_charge >= 1.0:
		storm_charge = 0.0
		_release_charged_strike(point)


func on_enemy_died(_enemy: Yokai) -> void:
	if int(stacks.get("sakura_heal", 0)) <= 0 or run_game == null:
		return
	var health := run_game._player_health()
	if health:
		health.heal(5.0 if has_evolution(Elements.PHANTOM_PETALS) else 3.0)
		effect_triggered.emit("sakura_heal", {"amount": 5.0 if has_evolution(Elements.PHANTOM_PETALS) else 3.0})


func try_shadow_blink(direction: Vector3 = Vector3.ZERO) -> bool:
	if not active_elements.has(Elements.SHADOW) or blink_cooldown > 0.0 or run_game == null or run_game.player == null:
		return false
	var dir := direction
	if dir.length_squared() < 0.01:
		var frame := run_game._player_view_frame()
		dir = -frame.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return false
	dir = dir.normalized()

	var player_pos := run_game.player.global_position
	var distance := 2.8 if int(stacks.get("shadow_veil", 0)) > 0 else 2.2
	var from := player_pos + Vector3(0.0, 0.85, 0.0)
	var desired := player_pos + dir * distance
	var query := PhysicsRayQueryParameters3D.create(from, desired + Vector3(0.0, 0.85, 0.0), 1 | RunGame.PLAYER_BOUNDARY_LAYER)
	var collision := get_world_3d().direct_space_state.intersect_ray(query)
	if not collision.is_empty():
		desired = Vector3(collision.position.x, player_pos.y, collision.position.z) - dir * 0.38
	if desired.distance_to(player_pos) < 0.45:
		return false

	_spawn_shadow_trace(player_pos + Vector3(0.0, 0.85, 0.0), desired + Vector3(0.0, 0.85, 0.0))
	if run_game.player is DesktopPlayer:
		(run_game.player as DesktopPlayer).teleport(desired, run_game.player.rotation.y)
	else:
		run_game.player.global_position = desired
	if int(stacks.get("shadow_darkness", 0)) > 0:
		_spawn_darkness(desired)
	blink_cooldown = 3.4 if int(stacks.get("shadow_veil", 0)) > 0 else 5.0
	GameEvents.log_event("shadow_blink", {"distance": player_pos.distance_to(desired)})
	effect_triggered.emit("shadow_blink", {"from": player_pos, "to": desired})
	return true


func paint_ink(at: Vector3) -> void:
	if not active_elements.has(Elements.INK):
		return
	var ground := _ground_below(at)
	var radius := 1.55 if int(stacks.get("ink_depth", 0)) > 0 else 1.12
	var lifetime := 10.0 if int(stacks.get("ink_depth", 0)) > 0 else 7.0
	if _ink_pools.size() >= MAX_INK_POOLS:
		_free_pool(0)

	var root := Node3D.new()
	root.name = "InkPool"
	add_child(root)
	root.global_position = ground + Vector3(0.0, 0.018, 0.0)
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	mesh_instance.mesh = quad
	mesh_instance.rotation.x = -PI * 0.5
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = INK_SHADER
	mat.set_shader_parameter("lifetime", lifetime)
	if has_evolution(Elements.BLACK_LIGHTNING):
		mat.set_shader_parameter("edge_color", Color(0.18, 0.55, 0.98))
	mesh_instance.material_override = mat
	root.add_child(mesh_instance)
	_ink_pools.append({
		"node": root, "mat": mat, "position": root.global_position,
		"radius": radius, "lifetime": lifetime, "age": 0.0, "pulse": 0.25,
	})
	effect_triggered.emit("ink_pool", {"position": ground, "radius": radius})


func debug_release_petals(direction: Vector3) -> void:
	_spawn_swing_petals(direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD)


func _physics_process(delta: float) -> void:
	if run_game == null or weapon == null:
		return
	blink_cooldown = maxf(0.0, blink_cooldown - delta)
	_petal_swing_cooldown = maxf(0.0, _petal_swing_cooldown - delta)
	_chain_cooldown = maxf(0.0, _chain_cooldown - delta)
	_charge_vfx_cooldown = maxf(0.0, _charge_vfx_cooldown - delta)
	_orbit_clock += delta
	for id in _orbit_hits.keys():
		_orbit_hits[id] -= delta
		if _orbit_hits[id] <= 0.0:
			_orbit_hits.erase(id)

	var tip := weapon.get_tip_global()
	var motion := tip - _prev_tip
	_prev_tip = tip
	if active_elements.has(Elements.SAKURA) and _petal_swing_cooldown <= 0.0 \
			and weapon.measured_tip_speed >= 6.2 and motion.length_squared() > 0.0004 \
			and Engine.get_physics_frames() - weapon.teleported_frame > 2:
		_petal_swing_cooldown = 0.36
		_spawn_swing_petals(motion.normalized())
	if int(stacks.get("storm_charge", 0)) > 0 and weapon.is_held() and weapon.measured_tip_speed > 4.5:
		storm_charge = minf(1.0, storm_charge + delta * (0.18 + weapon.measured_tip_speed * 0.045))
	if storm_charge >= 1.0 and _charge_vfx_cooldown <= 0.0:
		_charge_vfx_cooldown = 0.28
		var blade_start := weapon.get_blade_start_global()
		var blade_tip := weapon.get_tip_global()
		var charge_points: Array[Vector3] = [
			blade_start,
			blade_start.lerp(blade_tip, 0.48) + weapon.global_basis.x * 0.025,
			blade_tip,
		]
		_spawn_lightning(charge_points, Color(0.32, 0.82, 1.6), 0.14, 0.006)

	_update_petals(delta)
	_update_orbit_petals(delta)
	_update_ink_pools(delta)
	_update_darkness(delta)
	_update_transients(delta)


func _refresh_evolutions() -> void:
	evolutions.clear()
	if UpgradePool.tree_complete(Elements.STORM, stacks) and UpgradePool.tree_complete(Elements.INK, stacks):
		evolutions.append(Elements.BLACK_LIGHTNING)
	if UpgradePool.tree_complete(Elements.SAKURA, stacks) and UpgradePool.tree_complete(Elements.SHADOW, stacks):
		evolutions.append(Elements.PHANTOM_PETALS)


func _build_shared_petals() -> void:
	_petal_mesh = QuadMesh.new()
	_petal_mesh.size = Vector2(0.075, 0.16)
	_petal_mat = ShaderMaterial.new()
	_petal_mat.shader = PETAL_SHADER
	_phantom_petal_mat = _petal_mat.duplicate() as ShaderMaterial
	_phantom_petal_mat.set_shader_parameter("phantom", 1.0)


func _spawn_swing_petals(direction: Vector3) -> void:
	if _petals.size() >= MAX_PETALS:
		_free_petal(0)
	var count := 5 if has_evolution(Elements.PHANTOM_PETALS) else 3
	var origin := weapon.get_tip_global()
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	for i in count:
		if _petals.size() >= MAX_PETALS:
			_free_petal(0)
		var node := MeshInstance3D.new()
		node.name = "PhantomPetal" if has_evolution(Elements.PHANTOM_PETALS) else "CuttingPetal"
		node.mesh = _petal_mesh
		node.material_override = _phantom_petal_mat if has_evolution(Elements.PHANTOM_PETALS) else _petal_mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(node)
		var fan := float(i) - float(count - 1) * 0.5
		node.global_position = origin + right * fan * 0.050 \
			+ Vector3.UP * (fan * 0.024 + _rng.randf_range(-0.018, 0.018))
		var petal_scale := _rng.randf_range(0.82, 1.12)
		node.scale = Vector3(petal_scale, petal_scale, petal_scale)
		var spread := right * fan * 0.055 + Vector3.UP * _rng.randf_range(-0.035, 0.055)
		var velocity := (direction + spread).normalized() * (7.6 + float(i) * 0.28)
		node.look_at(node.global_position + velocity, Vector3.UP)
		node.rotate_object_local(Vector3.FORWARD, fan * 0.24 + _rng.randf_range(-0.22, 0.22))
		_petals.append({"node": node, "velocity": velocity, "age": 0.0, "hit": {}})
	effect_triggered.emit("sakura_petals", {"count": count, "phantom": has_evolution(Elements.PHANTOM_PETALS)})


func _update_petals(delta: float) -> void:
	for i in range(_petals.size() - 1, -1, -1):
		var p: Dictionary = _petals[i]
		var node := p.node as MeshInstance3D
		if not is_instance_valid(node):
			_petals.remove_at(i)
			continue
		p.age = float(p.age) + delta
		if p.age >= 1.15:
			_free_petal(i)
			continue
		var velocity: Vector3 = p.velocity
		if has_evolution(Elements.PHANTOM_PETALS):
			var targets := _nearest_enemies(node.global_position, 1, 4.0)
			if not targets.is_empty():
				var target_dir := (_enemy_center(targets[0]) - node.global_position).normalized()
				velocity = velocity.lerp(target_dir * velocity.length(), clampf(delta * 4.5, 0.0, 1.0))
		node.global_position += velocity * delta
		node.rotate_object_local(Vector3.FORWARD, delta * 8.0)
		p.velocity = velocity
		_petals[i] = p
		for enemy in _nearest_enemies(node.global_position, 1, 0.42):
			enemy.receive_element_damage(13.0 if has_evolution(Elements.PHANTOM_PETALS) else 8.0,
				Elements.PHANTOM_PETALS if has_evolution(Elements.PHANTOM_PETALS) else Elements.SAKURA,
				node.global_position, velocity.normalized())
			if has_evolution(Elements.PHANTOM_PETALS):
				enemy.apply_confusion(1.4)
			_free_petal(i)
			break


func _rebuild_orbit_petals() -> void:
	for p in _orbit_petals:
		if is_instance_valid(p):
			p.queue_free()
	_orbit_petals.clear()
	if int(stacks.get("sakura_orbit", 0)) <= 0:
		return
	var count := 5 if has_evolution(Elements.PHANTOM_PETALS) else 3
	for i in count:
		var petal := MeshInstance3D.new()
		petal.name = "OrbitPetal"
		petal.mesh = _petal_mesh
		petal.material_override = _phantom_petal_mat if has_evolution(Elements.PHANTOM_PETALS) else _petal_mat
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		petal.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(petal)
		_orbit_petals.append(petal)


func _update_orbit_petals(_delta: float) -> void:
	if _orbit_petals.is_empty():
		return
	var center := run_game._player_center() + Vector3(0.0, -0.18, 0.0)
	for i in _orbit_petals.size():
		var angle := _orbit_clock * 2.15 + TAU * float(i) / float(_orbit_petals.size())
		var radius := 0.78 + sin(_orbit_clock * 1.7 + float(i)) * 0.06
		var petal := _orbit_petals[i]
		petal.global_position = center + Vector3(cos(angle) * radius, sin(angle * 2.0) * 0.16, sin(angle) * radius)
		petal.rotation = Vector3(angle * 0.8, -angle, angle * 1.4)
		for enemy in _nearest_enemies(petal.global_position, 1, 0.34):
			var id := enemy.get_instance_id()
			if not _orbit_hits.has(id):
				_orbit_hits[id] = 0.55
				enemy.receive_element_damage(6.0, Elements.SAKURA, petal.global_position,
					(_enemy_center(enemy) - center).normalized())


func _release_chain_lightning(origin: Vector3, direction: Vector3) -> void:
	var max_targets := 4 if int(stacks.get("storm_overload", 0)) > 0 else 3
	var targets := _nearest_enemies(origin, max_targets, 4.8)
	if targets.is_empty():
		return
	var points: Array[Vector3] = [origin]
	var damage := 11.0 if int(stacks.get("storm_overload", 0)) > 0 else 8.0
	for enemy in targets:
		var point := _enemy_center(enemy)
		points.append(point)
		enemy.receive_element_damage(damage, Elements.BLACK_LIGHTNING if has_evolution(Elements.BLACK_LIGHTNING) else Elements.STORM,
			point, direction)
		if has_evolution(Elements.BLACK_LIGHTNING):
			paint_ink(point)
	var color := Color(0.18, 0.48, 1.8) if has_evolution(Elements.BLACK_LIGHTNING) else Color(0.35, 1.0, 2.4)
	_spawn_lightning(points, color, 0.26, 0.010, has_evolution(Elements.BLACK_LIGHTNING))
	effect_triggered.emit("chain_lightning", {"targets": targets.size(), "black": has_evolution(Elements.BLACK_LIGHTNING)})


func _release_charged_strike(origin: Vector3) -> void:
	var targets := _nearest_enemies(origin, 5 if int(stacks.get("storm_overload", 0)) > 0 else 3, 5.5)
	var points: Array[Vector3] = [origin]
	for enemy in targets:
		var point := _enemy_center(enemy)
		points.append(point)
		enemy.receive_element_damage(22.0, Elements.BLACK_LIGHTNING if has_evolution(Elements.BLACK_LIGHTNING) else Elements.STORM,
			point, (point - origin).normalized())
		if has_evolution(Elements.BLACK_LIGHTNING):
			paint_ink(point)
	if points.size() == 1:
		points.append(origin + Vector3.UP * 2.2)
	var blackened := has_evolution(Elements.BLACK_LIGHTNING)
	_spawn_lightning(points, Color(0.16, 0.42, 1.5) if blackened else Color(0.46, 1.2, 2.8),
		0.42, 0.012, blackened)
	effect_triggered.emit("charged_strike", {"targets": targets.size()})


func _update_ink_pools(delta: float) -> void:
	for i in range(_ink_pools.size() - 1, -1, -1):
		var pool: Dictionary = _ink_pools[i]
		pool.age = float(pool.age) + delta
		pool.pulse = float(pool.pulse) - delta
		if pool.age >= float(pool.lifetime) or not is_instance_valid(pool.node):
			_free_pool(i)
			continue
		(pool.mat as ShaderMaterial).set_shader_parameter("age", pool.age)
		var trapped: Array[Yokai] = []
		for enemy in _alive_enemies():
			var flat := _enemy_center(enemy) - (pool.position as Vector3)
			flat.y = 0.0
			if flat.length() <= float(pool.radius):
				enemy.apply_slow(0.22, 0.52)
				trapped.append(enemy)
		if int(stacks.get("ink_tendrils", 0)) > 0 and pool.pulse <= 0.0 and not trapped.is_empty():
			pool.pulse = 1.0
			for enemy in trapped.slice(0, mini(3, trapped.size())):
				var point := _enemy_center(enemy)
				enemy.receive_element_damage(6.0, Elements.BLACK_LIGHTNING if has_evolution(Elements.BLACK_LIGHTNING) else Elements.INK,
					point, Vector3.UP)
				_spawn_ink_tendril(pool.position, point)
		_ink_pools[i] = pool


func _spawn_ink_tendril(from: Vector3, to: Vector3) -> void:
	var points: Array[Vector3] = [
		from + Vector3.UP * 0.04,
		from.lerp(to, 0.45) + Vector3.UP * 0.55,
		to,
	]
	_spawn_lightning(points, Color(0.24, 0.28, 0.52), 0.38, 0.012, true)


func _spawn_darkness(at: Vector3) -> void:
	var radius := 4.2 if int(stacks.get("shadow_veil", 0)) > 0 else 3.4
	var lifetime := 4.5 if int(stacks.get("shadow_veil", 0)) > 0 else 3.2
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	sphere.mesh = mesh
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sphere.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("phase", _rng.randf() * TAU)
	sphere.material_override = mat
	add_child(sphere)
	sphere.global_position = at + Vector3.UP * 0.75
	_darkness_areas.append({"node": sphere, "mat": mat, "position": at, "radius": radius, "age": 0.0, "lifetime": lifetime})
	effect_triggered.emit("shadow_darkness", {"position": at, "radius": radius})


func _update_darkness(delta: float) -> void:
	for i in range(_darkness_areas.size() - 1, -1, -1):
		var area: Dictionary = _darkness_areas[i]
		area.age = float(area.age) + delta
		if area.age >= float(area.lifetime) or not is_instance_valid(area.node):
			if is_instance_valid(area.node):
				area.node.queue_free()
			_darkness_areas.remove_at(i)
			continue
		var fade := minf(1.0, float(area.age) / 0.25) * (1.0 - smoothstep(float(area.lifetime) - 0.8, float(area.lifetime), float(area.age)))
		(area.mat as ShaderMaterial).set_shader_parameter("opacity", fade * 0.42)
		for enemy in _alive_enemies():
			var offset := _enemy_center(enemy) - (area.position as Vector3)
			offset.y = 0.0
			if offset.length() <= float(area.radius):
				enemy.apply_confusion(0.24)
		_darkness_areas[i] = area


func _spawn_shadow_trace(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	if dir.length_squared() < 0.01:
		return
	var points: Array[Vector3] = [from, from.lerp(to, 0.5) + Vector3.UP * 0.18, to]
	_spawn_lightning(points, Color(0.58, 0.16, 1.2), 0.30, 0.018)


func _spawn_lightning(points: Array[Vector3], color: Color, lifetime: float, width: float = 0.010,
		blackened: bool = false) -> void:
	if points.size() < 2:
		return
	var edges: Array = []
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var previous := a
		var segments := 5
		for s in segments:
			var t := float(s + 1) / float(segments)
			var next := a.lerp(b, t)
			if s < segments - 1:
				var tangent := (b - a).normalized()
				var side := tangent.cross(Vector3.UP)
				if side.length_squared() < 0.01:
					side = tangent.cross(Vector3.RIGHT)
				next += side.normalized() * _rng.randf_range(-0.065, 0.065)
				next += Vector3.UP * _rng.randf_range(-0.045, 0.045)
			edges.append([previous, next])
			previous = next

	# Two mesh ribbons give a soft colored envelope and a razor-white core
	# without a light, particles, bloom dependency or screen-space pass.
	if blackened:
		_spawn_lightning_layer(edges, Color(0.004, 0.006, 0.014), lifetime, width * 3.0, 0.78, 0.0, false)
		_spawn_lightning_layer(edges, Color(0.10, 0.55, 1.40), lifetime, width * 0.82, 0.86, 0.90, true)
	else:
		_spawn_lightning_layer(edges, color * 0.42, lifetime, width * 2.5, 0.16, 0.24, true)
		var core := Color(0.72 + color.r * 0.12, 0.82 + color.g * 0.10, 1.02 + color.b * 0.08)
		_spawn_lightning_layer(edges, core, lifetime, width * 0.72, 0.88, 0.95, true)


func _spawn_lightning_layer(edges: Array, color: Color, lifetime: float, width: float,
		alpha: float, energy: float, additive: bool) -> void:
	if _transients.size() >= MAX_TRANSIENT_MESHES:
		var oldest: Dictionary = _transients.pop_front()
		if is_instance_valid(oldest.node):
			oldest.node.queue_free()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = energy > 0.0
	if mat.emission_enabled:
		mat.emission = color
		mat.emission_energy_multiplier = energy
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for edge in edges:
		_append_bolt_quad(mesh, edge[0], edge[1], width)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(node)
	_transients.append({
		"node": node, "mat": mat, "age": 0.0, "lifetime": lifetime,
		"energy": energy, "alpha": alpha,
	})


func _append_bolt_quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, width: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized() * width
	for normal_side in [side, axis.cross(side).normalized() * width]:
		mesh.surface_add_vertex(a - normal_side)
		mesh.surface_add_vertex(a + normal_side)
		mesh.surface_add_vertex(b + normal_side)
		mesh.surface_add_vertex(a - normal_side)
		mesh.surface_add_vertex(b + normal_side)
		mesh.surface_add_vertex(b - normal_side)


func _update_transients(delta: float) -> void:
	for i in range(_transients.size() - 1, -1, -1):
		var fx: Dictionary = _transients[i]
		fx.age = float(fx.age) + delta
		if fx.age >= float(fx.lifetime) or not is_instance_valid(fx.node):
			if is_instance_valid(fx.node):
				fx.node.queue_free()
			_transients.remove_at(i)
			continue
		var alpha := 1.0 - smoothstep(float(fx.lifetime) * 0.42, float(fx.lifetime), float(fx.age))
		var mat := fx.mat as StandardMaterial3D
		var col := mat.albedo_color
		col.a = float(fx.alpha) * alpha
		mat.albedo_color = col
		mat.emission_energy_multiplier = float(fx.energy) * alpha
		_transients[i] = fx


func _alive_enemies() -> Array[Yokai]:
	return run_game.wave_director.alive_enemies() if run_game and run_game.wave_director else []


func _nearest_enemies(point: Vector3, count: int, max_distance: float) -> Array[Yokai]:
	var candidates := _alive_enemies()
	candidates.sort_custom(func(a: Yokai, b: Yokai) -> bool:
		return _enemy_center(a).distance_squared_to(point) < _enemy_center(b).distance_squared_to(point))
	var result: Array[Yokai] = []
	for enemy in candidates:
		if _enemy_center(enemy).distance_to(point) <= max_distance:
			result.append(enemy)
			if result.size() >= count:
				break
	return result


static func _enemy_center(enemy: Yokai) -> Vector3:
	if enemy.parts.has("chest"):
		return (enemy.parts["chest"] as RagdollPart).global_position
	return enemy.global_position + Vector3.UP


func _ground_below(point: Vector3) -> Vector3:
	var from := point + Vector3.UP * 0.4
	var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.DOWN * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	return Vector3(point.x, 0.0, point.z)


func _free_petal(index: int) -> void:
	if index < 0 or index >= _petals.size():
		return
	var node: Object = _petals[index].node
	if is_instance_valid(node):
		node.queue_free()
	_petals.remove_at(index)


func _free_pool(index: int) -> void:
	if index < 0 or index >= _ink_pools.size():
		return
	var node: Object = _ink_pools[index].node
	if is_instance_valid(node):
		node.queue_free()
	_ink_pools.remove_at(index)


func _clear_runtime_vfx() -> void:
	for collection in [_petals, _ink_pools, _transients, _darkness_areas]:
		for entry in collection:
			var node: Object = entry.get("node")
			if is_instance_valid(node):
				node.queue_free()
		collection.clear()
	for p in _orbit_petals:
		if is_instance_valid(p):
			p.queue_free()
	_orbit_petals.clear()
	_orbit_hits.clear()
