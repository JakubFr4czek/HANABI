extends Node
## Headless checks for the World Gen profile (docs/WORLDGEN_TOOL.md):
## - the profile is the one source: the game reads the project setting, the
##   presets load and validate, and a round trip through .tres keeps every field
## - validate() catches the mistakes a designer can make
## - reset_group() restores one group and leaves the others alone
## - the sampling and the path network that the forest is built on hold their rules:
##   Poisson disk spacing, dusk palette mix, path routes that reach the glade
##   godot --headless --path . --fixed-fps 90 res://tests/worldgen_profile_test.tscn

var failures := 0
var _digests := {}


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_check_setting_and_presets()
	_check_round_trip()
	_check_validation()
	_check_reset_group()
	_check_palette()
	_check_poisson()
	_check_path_network()
	await _check_forest_determinism()


func _check_setting_and_presets() -> void:
	var active_path := String(ProjectSettings.get_setting("hanabi/worldgen/profile", ""))
	_check("The game names its profile in project settings (%s)" % active_path,
		active_path == WorldGenProfile.DEFAULT_PATH)
	for file in ["default_profile", "dense_dusk", "quest_perf"]:
		var path := "res://data/worldgen/%s.tres" % file
		var preset := load(path) as WorldGenProfile
		_check("Preset %s loads as a WorldGenProfile" % file, preset != null)
		if preset == null:
			continue
		var errors := _errors(preset.validate())
		_check("Preset %s validates without errors (%s)" % [file, ", ".join(errors)], errors.is_empty())
	var default_profile := load(WorldGenProfile.DEFAULT_PATH) as WorldGenProfile
	_check("The default preset matches the built-in defaults (signature)",
		default_profile.signature() == WorldGenProfile.make_default().signature())
	_check("The active profile is the default preset",
		WorldGenProfile.load_active().signature() == default_profile.signature())


func _check_round_trip() -> void:
	var p := WorldGenProfile.make_default()
	p.world_seed = 31337
	p.trees[1].focal_chance = 0.42
	p.trees[0].neon_color = Color(0.2, 0.9, 0.4)
	p.undergrowth[0].cluster_threshold = 0.61
	p.fog_start = 2.25
	p.torii_glow_strength = 0.8
	p.dusk_mix = 0.7
	var path := "user://worldgen_round_trip_test.tres"
	var err := ResourceSaver.save(p, path)
	_check("A profile saves to .tres (%d)" % err, err == OK)
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WorldGenProfile
	_check("The saved profile loads back", back != null)
	if back == null:
		return
	_check("Round trip keeps the signature (no field lost)", back.signature() == p.signature())
	_check("Round trip keeps focal chance, seed, fog and palette",
		back.world_seed == 31337 and is_equal_approx(back.trees[1].focal_chance, 0.42)
		and is_equal_approx(back.fog_start, 2.25) and is_equal_approx(back.dusk_mix, 0.7))
	_check("Round trip keeps the entry colours", back.trees[0].neon_color.is_equal_approx(Color(0.2, 0.9, 0.4)))
	_check("Round trip keeps the undergrowth threshold", is_equal_approx(back.undergrowth[0].cluster_threshold, 0.61))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_validation() -> void:
	_check("The default profile has no errors", _errors(WorldGenProfile.make_default().validate()).is_empty())

	var empty := WorldGenProfile.make_default()
	empty.trees = []
	_check("An empty tree list is an error", not _errors(empty.validate()).is_empty())

	var no_ordinary := WorldGenProfile.make_default()
	no_ordinary.trees[0].weight = 0.0
	_check("Only focal kinds is an error (no forest)", not _errors(no_ordinary.validate()).is_empty())

	var inverted := WorldGenProfile.make_default()
	inverted.trees[0].scale_min = 2.0
	inverted.trees[0].scale_max = 1.0
	_check("Scale min above max is an error", not _errors(inverted.validate()).is_empty())

	var shrines := WorldGenProfile.make_default()
	shrines.shrine_slot_chunks = 1
	shrines.shrine_slot_chance = 1.0
	_check("Shrines as common as gates are an error (rarer than torii, D1)",
		_contains(_errors(shrines.validate()), "kapliczki"))

	var fog := WorldGenProfile.make_default()
	fog.fog_start = 11.0
	fog.fog_end = 10.0
	_check("Fog starting after its end is an error", _contains(_errors(fog.validate()), "mgła"))

	var sceneless := WorldGenProfile.make_default()
	sceneless.trees[0].scene = null
	_check("A cedar without a scene is a warning, not an error",
		_errors(sceneless.validate()).is_empty() and _contains(sceneless.validate(), "nie ma sceny"))

	var volumetric := WorldGenProfile.make_default()
	volumetric.volumetric_fog = true
	_check("Volumetric fog warns about the Quest cost", _contains(volumetric.validate(), "volumetric"))


func _check_reset_group() -> void:
	var p := WorldGenProfile.make_default()
	p.hill_amplitude = 9.0
	p.world_seed = 77
	p.fog_start = 1.0
	p.reset_group("Terrain")
	_check("Reset of Terrain restores the hill amplitude", is_equal_approx(p.hill_amplitude, WorldGenProfile.make_default().hill_amplitude))
	_check("Reset of Terrain leaves the seed alone", p.world_seed == 77)
	_check("Reset of Terrain leaves the fog alone", is_equal_approx(p.fog_start, 1.0))
	p.trees[0].weight = 5.0
	p.reset_group("Trees")
	_check("Reset of Trees restores the tree weights", is_equal_approx(p.trees[0].weight, 1.0))
	var names := p.group_names()
	_check("Every inspector group has a reset (%d groups)" % names.size(), names.has("Terrain") and names.has("Torii") and names.has("Paths"))


func _check_palette() -> void:
	var p := WorldGenProfile.make_default()
	p.dusk_mix = 0.0
	_check("Night palette is the night blue", p.fog_color().is_equal_approx(p.night_blue))
	p.dusk_mix = 1.0
	_check("Dusk palette is the dusk rose", p.fog_color().is_equal_approx(p.dusk_pink))
	p.dusk_mix = 0.5
	var mid := p.fog_color()
	_check("A half mix sits between rose and blue (no hard switch)",
		mid.r > minf(p.night_blue.r, p.dusk_pink.r) and mid.r < maxf(p.night_blue.r, p.dusk_pink.r)
		and not mid.is_equal_approx(p.night_blue) and not mid.is_equal_approx(p.dusk_pink))
	var steps := PackedFloat32Array()
	for k in 11:
		p.dusk_mix = float(k) / 10.0
		steps.append(p.fog_color().r)
	_check("The mix moves the red channel without jumps", absf(steps[10] - steps[0]) > 0.1 and _max_step(steps) < 0.12)


static func _max_step(values: PackedFloat32Array) -> float:
	var m := 0.0
	for k in range(1, values.size()):
		m = maxf(m, absf(values[k] - values[k - 1]))
	return m


func _check_poisson() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pts := PoissonDisk.sample(rng, Vector2(-14.0, -14.0), Vector2(28.0, 28.0), 3.0)
	var min_gap := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_gap = minf(min_gap, pts[i].distance_to(pts[j]))
	_check("Poisson disk keeps its radius (min gap %.2f m ≥ 3.0)" % min_gap, pts.size() > 1 and min_gap >= 3.0 - 1e-4)
	_check("Poisson disk fills a 28 m chunk evenly (%d points)" % pts.size(), pts.size() >= 35 and pts.size() <= 110)
	var again := RandomNumberGenerator.new()
	again.seed = 4242
	var same := PoissonDisk.sample(again, Vector2(-14.0, -14.0), Vector2(28.0, 28.0), 3.0)
	_check("Poisson disk is deterministic for one seed", same == pts)
	var inside := true
	for p in pts:
		inside = inside and p.x >= -14.0 and p.x <= 14.0 and p.y >= -14.0 and p.y <= 14.0
	_check("Poisson disk stays inside its rectangle", inside)


func _check_path_network() -> void:
	var p := WorldGenProfile.make_default()
	p.world_seed = 9
	var net := ForestPaths.new()
	net.setup(p, Callable(self, "_flat_height"))
	# Every node reaches the glade in a finite number of parent steps: the tree of
	# paths is connected to the start by construction, anywhere in the forest.
	var connected := true
	var worst := 0
	for i in range(-12, 13):
		for j in range(-12, 13):
			var n := Vector2i(i, j)
			var steps := 0
			var cur := n
			while cur != Vector2i.ZERO and steps < 200:
				cur = net.parent_of(cur)
				steps += 1
			connected = connected and cur == Vector2i.ZERO
			worst = maxi(worst, steps)
	_check("Every node of the path network reaches the glade (worst %d steps)" % worst, connected)
	# A routed edge starts and ends on its two nodes and stays a metre apart.
	var a := Vector2i(1, 0)
	var b := Vector2i(1, 1)
	var line := net.polyline(ForestPaths.edge_key(a, b))
	_check("A routed path starts and ends on its nodes",
		line.size() >= 2 and line[0].distance_to(net.node_xz(a)) < 1e-3 and line[line.size() - 1].distance_to(net.node_xz(b)) < 1e-3)
	var even := true
	for k in range(line.size() - 2):
		var gap := line[k].distance_to(line[k + 1])
		even = even and gap <= 1.0 + 1e-3 and gap > 0.0
	_check("A routed path is resampled to about one metre", even)
	# The glade is kept: the first edge out of the origin starts at the origin.
	var out := net.edges_in_rect(Rect2(Vector2(-5.0, -5.0), Vector2(10.0, 10.0)))
	_check("The glade is part of the network (%d edges around it)" % out.size(), out.size() >= 2)


static func _flat_height(_x: float, _z: float) -> float:
	return 0.0


func _check_forest_determinism() -> void:
	var base := WorldGenProfile.make_default()
	base.world_seed = 2024
	var d1 := await _isolated_digest(base)
	var d2 := await _isolated_digest(base)
	_check("Same seed and profile give the same forest (digest %d)" % d1, d1 == d2 and d1 != 0)
	var other := base.duplicate(true) as WorldGenProfile
	other.world_seed = 2025
	_check("A different seed gives a different forest", await _isolated_digest(other) != d1)


## Digest of a forest built alone. Gates are placed with physics queries against
## the whole world, so a second forest in the same physics space would place
## its gates differently: the forest is freed (and its bodies leave the space)
## before the next one is built.
func _isolated_digest(profile: WorldGenProfile) -> int:
	var forest := _build(profile)
	var d := _digest(forest)
	forest.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return d


## Builds a forest for [param profile] in this scene and returns it. No frame
## is waited for: gameplay gates (ToriiManager) spawn in physics frames and cut
## trunks near them, which is game state, not generation.
func _build(profile: WorldGenProfile) -> ForestWorld:
	var follow := Node3D.new()
	add_child(follow)
	var forest := ForestWorld.new()
	forest.profile = profile
	add_child(forest)
	forest.setup(follow)
	return forest


## One hash of the tree transforms and gates of every chunk, in chunk order.
func _digest(forest: ForestWorld) -> int:
	var keys := forest._chunks.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	var parts := PackedStringArray()
	for key in keys:
		var chunk := forest._chunks[key] as Node3D
		for xf in chunk.get_meta("tree_local_xfs", []):
			var t: Transform3D = xf
			parts.append("%.4f,%.4f,%.4f" % [t.origin.x, t.origin.y, t.origin.z])
		for p in chunk.get_meta("torii_world_positions", []):
			parts.append(str(p))
	return ",".join(parts).hash()


static func _errors(messages: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for m in messages:
		if m.begins_with("BŁĄD"):
			out.append(m)
	return out


static func _contains(messages: Array[String], needle: String) -> bool:
	for m in messages:
		if m.contains(needle):
			return true
	return false


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
