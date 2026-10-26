extends Node
## Headless checks for the arena scene:
## - LightmapGI bake readiness: every mesh marked GI Mode = Static has a UV2
##   channel, the arena's static stone and torii are among them, and the
##   animated/unlit layers (sky dome, water, mist, the seal) stay out of the bake.
## - The fight zone is a clean circle: nothing to bump into or trip over inside
##   it, a round boundary at its rim, and the weapons rest on a stand at the
##   edge (which the player and the dummy pass through) and go back there on reset.
## - Scanned assets: PBR maps survive the rain material, the katana lies in the
##   stand model's notch, and the arena fits the Quest 3 triangle budget.
## Run:
##   godot --headless --path . --fixed-fps 90 res://tests/arena_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ARENA := preload("res://scenes/training_arena.tscn")
const ROOM := preload("res://scenes/test_room.tscn")
const MUST_BAKE := ["PlatformDisc", "PlatformRim", "NorthThreshold", "GiantTorii"]
const NEVER_BAKE := ["SkyDome", "WaterMirror", "WaterMistLow", "WaterMistHigh", "SpawnSeal", "StormLightning"]
## The fight zone: nothing stands inside this radius (m).
const CLEAR_RADIUS := 4.4

var failures := 0


func _ready() -> void:
	var arena := ARENA.instantiate()
	_test_lightmap_ready(arena)
	_test_clean_circle_layout(arena)
	arena.free()
	await _test_clean_circle_physics()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


# --- LightmapGI ---------------------------------------------------------------------

func _test_lightmap_ready(arena: Node) -> void:
	var lightmap := arena.get_node_or_null("Arena/LightmapGI") as LightmapGI
	_check("LightmapGI node exists", lightmap != null)

	var bakeable: Array[String] = []
	var missing_uv2: Array[String] = []
	var tris := 0
	for node in arena.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			continue
		var path := String(arena.get_path_to(mi))
		if _has_uv2(mi.mesh):
			bakeable.append(path)
			tris += _triangles(mi.mesh)
		else:
			missing_uv2.append(path)
	print("  bakeable meshes: %d (%d triangles)" % [bakeable.size(), tris])
	_check("Every GI-static mesh has UV2 %s" % [missing_uv2], missing_uv2.is_empty())
	for name in MUST_BAKE:
		_check("%s is GI static with UV2" % name, bakeable.any(func(p: String) -> bool: return p.contains(name)))

	for name in NEVER_BAKE:
		var mi := arena.find_child(name, true, false) as GeometryInstance3D
		_check("%s is left out of the bake" % name, mi != null and mi.gi_mode == GeometryInstance3D.GI_MODE_DISABLED)

	if lightmap and lightmap.light_data:
		print("  baked lightmap data present: %s" % lightmap.light_data.resource_path)
	else:
		print("  no baked lightmap yet (bake it in the editor)")


static func _has_uv2(mesh: Mesh) -> bool:
	if mesh.get_surface_count() == 0:
		return false
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty() or arrays[Mesh.ARRAY_TEX_UV2] == null or (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).is_empty():
			return false
	return true


static func _triangles(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var idx = arrays[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# --- Clean circle -------------------------------------------------------------------

## Scene layout: no furniture left, and nothing static rises above the floor
## inside the fight zone.
func _test_clean_circle_layout(arena: Node) -> void:
	var gone := ["SwordTable", "Lanterns", "LanternLeft", "LanternRight", "WallNorth", "WallEast"]
	var left := gone.filter(func(n: String) -> bool: return arena.find_child(n, true, false) != null)
	_check("bench, lanterns and the square walls are gone %s" % [left], left.is_empty())

	var obstacles: Array[String] = []
	for root in [arena.get_node("Arena"), arena.get_node("Room")]:
		for node in (root as Node).find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			if gi.name in ["SkyDome", "WaterMirror", "WaterMistLow", "WaterMistHigh", "StormLightning"]:
				continue
			var aabb := _global_aabb(gi)
			if aabb.size == Vector3.ZERO:
				continue
			# Rings and discs around the whole circle (the rim trim) are not in the way.
			if aabb.size.x > 2.0 * CLEAR_RADIUS and aabb.size.z > 2.0 * CLEAR_RADIUS:
				continue
			var top := aabb.end.y
			var nearest := Vector2(clampf(0.0, aabb.position.x, aabb.end.x), clampf(0.0, aabb.position.z, aabb.end.z))
			if top > 0.05 and nearest.length() < CLEAR_RADIUS:
				obstacles.append("%s (top %.2f m)" % [gi.name, top])
	_check("no geometry rises above the floor inside the fight circle (r < %.1f m) %s" % [CLEAR_RADIUS, obstacles], obstacles.is_empty())


func _global_aabb(gi: GeometryInstance3D) -> AABB:
	var local := gi.get_aabb()
	var xf := Transform3D.IDENTITY
	var n: Node = gi
	while n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf * local


func _test_clean_circle_physics() -> void:
	var room: Node3D = ROOM.instantiate()
	add_child(room)
	var player := room.player as DesktopPlayer
	await _wait(0.3)
	player.holder.release()
	player.left_holder.release()
	player.teleport(Vector3(-3.0, 0.0, -2.5))
	room.reset_room()
	var space := (room as Node3D).get_world_3d().direct_space_state

	# A player-sized capsule fits everywhere inside the circle.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | 2
	var blocked: Array[String] = []
	for r in [0.0, 1.5, 3.0, CLEAR_RADIUS - 0.35]:
		for k in 12:
			var a := TAU * k / 12.0
			var p := Vector3(sin(a) * r, 0.9, cos(a) * r)
			query.transform = Transform3D(Basis.IDENTITY, p)
			if not space.intersect_shape(query, 1).is_empty():
				blocked.append(str(p.snapped(Vector3.ONE * 0.1)))
	_check("a player-sized body fits anywhere in the fight circle (blocked at %s)" % [blocked], blocked.is_empty())

	# The boundary is round: walking out in any direction stops at the rim.
	var radii: Array[float] = []
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, 0), dir * 8.0 + Vector3(0, 1.0, 0), 1)
		var hit := space.intersect_ray(ray)
		radii.append(Vector2(hit.position.x, hit.position.z).length() if not hit.is_empty() else INF)
	_check("the boundary is a circle at the platform's rim (%.2f-%.2f m)" % [radii.min(), radii.max()],
		radii.min() > 5.0 and radii.max() < 5.3)

	# The weapon stand: the player and the dummy pass through it, the weapons rest on it.
	var rest := room.get_node("Room/WeaponRest") as StaticBody3D
	var player_mask := player.collision_mask
	var dummy_mask := ActiveRagdoll.BODY_MASK
	_check("the weapon stand sits at the rim (r %.2f m) and only weapons touch it" % Vector2(rest.global_position.x, rest.global_position.z).length(),
		Vector2(rest.global_position.x, rest.global_position.z).length() > CLEAR_RADIUS
			and rest.collision_layer & player_mask == 0 and rest.collision_layer & dummy_mask == 0
			and rest.collision_layer & room.katana.collision_mask != 0 and rest.collision_layer & room.kanabo.collision_mask != 0)

	var homes := {}
	for w: HeldWeapon in [room.katana, room.kanabo]:
		homes[w] = w.global_position
	await _wait(3.0)
	var drift := {}
	for w: HeldWeapon in homes:
		drift[w.weapon_name] = snappedf(w.global_position.distance_to(homes[w]), 0.001)
	_check("both weapons lie still on the stand (drift %s m)" % [drift], drift.values().max() < 0.03)
	_test_katana_in_stand_notch(rest, room.katana)
	_test_scanned_assets(room)

	room.katana.global_position += Vector3(-2.0, 0.5, -1.0)
	room.kanabo.global_position += Vector3(-2.5, 0.5, -1.5)
	await _wait(1.0)
	room.reset_room()
	await _wait(2.0)
	var back := {}
	for w: HeldWeapon in homes:
		back[w.weapon_name] = snappedf(w.global_position.distance_to(homes[w]), 0.001)
	_check("reset puts the weapons back on the stand (%s m)" % [back], back.values().max() < 0.03)
	room.queue_free()


## The visible katana stand (scaled 1.6×) has its handle-side arm at rest-local
## x = -0.171 with the notch floor at y = 0.166, centred on z = 0. The handle's
## spine (radius 0.016 under its curved axis) must sit in that notch, and the
## tsuba between the arms.
func _test_katana_in_stand_notch(rest: Node3D, katana: HeldWeapon) -> void:
	_check("the katana stand model is on the weapon rest", rest.get_node_or_null("KatanaStand") != null)
	var to_rest := rest.global_transform.affine_inverse() * katana.global_transform
	var best := Vector3.INF
	for i in 47:
		var z := i * 0.005
		var p := to_rest * Vector3(0.0, 0.001 + 0.09 * z, z)
		if absf(p.x + 0.171) < absf(best.x + 0.171):
			best = p
	var guard := to_rest * Vector3(0, 0, -0.085)
	_check("the katana handle lies in the stand's notch (rest-local %s)" % [best.snapped(Vector3.ONE * 0.001)],
		absf(best.x + 0.171) < 0.006 and absf(best.z) < 0.008 and best.y - 0.016 > 0.155 and best.y - 0.016 < 0.185)
	_check("the tsuba sits between the stand's arms (x %.3f)" % guard.x, absf(guard.x) < 0.14)


## Scanned assets keep their PBR maps under the rain treatment, and the whole
## arena stays inside a Quest 3 triangle budget (LOD0, i.e. worst case).
func _test_scanned_assets(room: Node) -> void:
	const TRI_BUDGET := 300000
	var tris := 0
	for mi: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_check("arena triangles at LOD0 within the Quest budget (%d < %d)" % [tris, TRI_BUDGET], tris < TRI_BUDGET)

	var bare := []
	for path in ["Arena/ToriiGates", "Arena/Rocks", "Room/WeaponRest/KatanaStand"]:
		var group := room.get_node_or_null(path)
		if group == null:
			bare.append(path)
			continue
		for mi: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s) as ShaderMaterial
				if m == null or m.get_shader_parameter("albedo_texture") == null \
						or m.get_shader_parameter("normal_depth") <= 0.0 or m.get_shader_parameter("orm_mode") <= 0:
					bare.append(mi.get_path())
	_check("torii, rocks and the stand keep albedo, normal and roughness maps %s" % [bare], bare.is_empty())
	_test_matte_materials(room)


## Rain must not turn everything into glossy plastic: the moon's specular is
## not boosted, and every rain-soaked material stays matte outside its water
## film (dry roughness >= 0.6, film roughness >= 0.25; scanned maps scale 1.0).
func _test_matte_materials(room: Node) -> void:
	var moon := room.get_node("Moon") as DirectionalLight3D
	_check("moon specular is not boosted above its diffuse (%.2f <= 0.8)" % moon.light_specular, moon.light_specular <= 0.8)
	var glossy := []
	var seen := {}
	for gi: GeometryInstance3D in room.find_children("*", "GeometryInstance3D", true, false):
		var mats: Array = [gi.material_override]
		var mi := gi as MeshInstance3D
		if mi and mi.mesh:
			for s in mi.mesh.get_surface_count():
				mats.append(mi.get_surface_override_material(s))
				mats.append(mi.mesh.surface_get_material(s))
		for m in mats:
			var sm := m as ShaderMaterial
			if sm == null or seen.has(sm) or sm.shader == null or not sm.shader.resource_path.ends_with("wet_surface.gdshader"):
				continue
			seen[sm] = true
			var dry := _param(sm, "roughness_dry")
			var wet := _param(sm, "roughness_wet")
			if dry < 0.6 or wet < 0.25:
				glossy.append("%s dry %.2f wet %.2f" % [gi.name, dry, wet])
	_check("%d rain-soaked materials stay matte outside the water film %s" % [seen.size(), glossy], seen.size() >= 4 and glossy.is_empty())


func _param(m: ShaderMaterial, name: String) -> float:
	var v = m.get_shader_parameter(name)
	if v == null:
		v = RenderingServer.shader_get_parameter_default(m.shader.get_rid(), name)
	return float(v)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
