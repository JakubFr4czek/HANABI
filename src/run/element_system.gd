class_name ElementSystem
extends Node3D
## Quest-conscious combat implementation for the four run elements (GDD §5, ELEMENTS_PLAN.md).
## Manages the katana's active elemental imbue (~20s duration from Torii gates)
## and 2 distinct active button abilities per element on sword-hand A/B buttons.
## All VFX/SFX are strictly bounded for Quest 3 (zero dynamic OmniLight3D nodes).

signal effect_triggered(type: String, data: Dictionary)

const PETAL_SHADER := preload("res://src/shaders/sakura_petal.gdshader")
const INK_SHADER := preload("res://src/shaders/ink_pool.gdshader")
const SHADOW_SHADER := preload("res://src/shaders/shadow_darkness.gdshader")

const MAX_PETALS := 12
const MAX_INK_POOLS := 6
const MAX_TRANSIENT_MESHES := 18

## All numbers (imbue seconds, cooldowns, damage, ranges) live in [ElementBalance].
## Cooldowns per ability per element (seconds)
const COOLDOWNS_ABILITY_1 := {
	Elements.SAKURA: ElementBalance.SENBONZAKURA_COOLDOWN,
	Elements.STORM: ElementBalance.RAIKIRI_COOLDOWN,
	Elements.INK: ElementBalance.SUMI_COOLDOWN,
	Elements.SHADOW: ElementBalance.KAGEMUSHA_COOLDOWN,
}

const COOLDOWNS_ABILITY_2 := {
	Elements.SAKURA: ElementBalance.HANAMAI_COOLDOWN,
	Elements.STORM: ElementBalance.SHIDEN_COOLDOWN,
	Elements.INK: ElementBalance.KAGE_NAWA_COOLDOWN,
	Elements.SHADOW: ElementBalance.YAMI_COOLDOWN,
}

var run_game: RunGame
var weapon: HeldWeapon
## Ofuda skill trees (E2c): unlocked nodes retune the abilities below via
## [method _fx]. Owned by RunGame; null in standalone tests (base numbers).
var skill_tree: SkillTreeData = null

## The single imbued element on the katana (~20s duration), or Elements.NONE.
var current_element: String = Elements.NONE
var element_time_remaining: float = 0.0
## Length of the current imbue (the wrist arc is remaining / this).
var imbue_total: float = ElementBalance.IMBUE_SECONDS
var is_fade_warning: bool = false

var ability_1_cooldown: float = 0.0
var ability_2_cooldown: float = 0.0

## Active ongoing ability states (finish full duration even if element expires)
var hanamai_time_remaining: float = 0.0
var shadow_cleave_buff_time: float = 0.0
var kagemusha_time_remaining: float = 0.0
var kagemusha_hits_remaining: int = ElementBalance.KAGEMUSHA_HITS
var kagemusha_decoy: Node3D = null
## Skill-tree runtime state (E2c): Ikazuchi lightning barriers, the Abyssal
## ink ward and pending Shadow Clone mirrors.
var _barriers: Array[Dictionary] = []
var abyssal_ward_time: float = 0.0
## Abyssal Sea: true while the player stands in one of their own ink pools.
var abyssal_in_ink: bool = false
var _abyssal_ward_cooldown: float = 0.0
## Plan (d): stepping onto your ink grants a *brief* (0.5 s) invulnerability,
## not immunity for as long as the pool lasts: it triggers on entering ink and
## re-arms after this many seconds.
const ABYSSAL_WARD_TIME := 0.5
const ABYSSAL_WARD_REARM := 4.0
var shadow_clone_charges: int = 0


## Upgraded parameter [param key] for [param element] from the skill tree,
## or [param default_value] when no node (or no tree) provides it.
func _fx(element: String, key: String, default_value: Variant) -> Variant:
	if skill_tree:
		return skill_tree.effect_value(element, key, default_value)
	return default_value


func _has_node(node_id: String) -> bool:
	return skill_tree != null and skill_tree.is_unlocked(node_id)


## Whether the blade's clean cuts split yōkai right now (D4): the school's
## finisher is unlocked and its imbue is running. Plain steel never splits.
func kirisute_ready() -> bool:
	return current_element != Elements.NONE and element_time_remaining > 0.0 \
		and skill_tree != null and skill_tree.has_effect(current_element, "kirisute")


## Potency of every direct ability hit: the Razor Edge multiplier of the blade
## times a small bonus per soul rank ([constant ElementBalance.POWER_PER_RANK]),
## so abilities keep pace with yōkai that grow tougher as the run goes on.
## 1.0 outside a run (tests of the bare numbers).
func ability_power() -> float:
	if run_game == null:
		return 1.0
	var blade := run_game.katana.damage_multiplier * run_game.katana.outgoing_scale if run_game.katana else 1.0
	return blade * (1.0 + ElementBalance.POWER_PER_RANK * float(maxi(run_game.level - 1, 0)))


## Single door for ability damage to a yōkai: scales [param amount] by [method ability_power].
func _hit(enemy: Yokai, amount: float, element: String, point: Vector3, direction: Vector3) -> float:
	return enemy.receive_element_damage(amount * ability_power(), element, point, direction)


## Full cooldown (seconds) of ability [param slot] (1 = A, 2 = B) on the
## current element, including skill-tree upgrades. 0 on plain steel.
func ability_cooldown_total(slot: int) -> float:
	if current_element == Elements.NONE:
		return 0.0
	if slot == 1:
		return float(_fx(current_element, "cooldown_ability_1", float(COOLDOWNS_ABILITY_1.get(current_element, 4.0))))
	return float(_fx(current_element, "cooldown_ability_2", float(COOLDOWNS_ABILITY_2.get(current_element, 8.0))))


## 0..1 readiness of ability [param slot]: 1 = ready, filling while it cools down.
## Plain steel has nothing to ready, so it reads 0.
func ability_ready_ratio(slot: int) -> float:
	if current_element == Elements.NONE:
		return 0.0
	var cd := ability_1_cooldown if slot == 1 else ability_2_cooldown
	if cd <= 0.0:
		return 1.0
	return clampf(1.0 - cd / maxf(ability_cooldown_total(slot), cd), 0.0, 1.0)


## 0..1 share of the imbue still left (the wrist arc); 0 on plain steel.
func imbue_ratio() -> float:
	if current_element == Elements.NONE:
		return 0.0
	return clampf(element_time_remaining / maxf(imbue_total, 0.01), 0.0, 1.0)

var _petals: Array[Dictionary] = []
var _orbit_petals: Array[MeshInstance3D] = []
var _orbit_hits := {}
var _ink_pools: Array[Dictionary] = []
var _transients: Array[Dictionary] = []
var _darkness_areas: Array[Dictionary] = []
var _orbit_clock := 0.0
var _chain_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _petal_mesh: QuadMesh
var _petal_mat: ShaderMaterial


func _ready() -> void:
	add_to_group("element_system")


func setup(p_run_game: RunGame, p_weapon: HeldWeapon) -> void:
	add_to_group("element_system")
	run_game = p_run_game
	weapon = p_weapon
	if run_game and run_game.skill_tree:
		skill_tree = run_game.skill_tree
	_rng.seed = 0x48414E414249
	_build_shared_petals()


func reset() -> void:
	current_element = Elements.NONE
	element_time_remaining = 0.0
	is_fade_warning = false
	ability_1_cooldown = 0.0
	ability_2_cooldown = 0.0
	hanamai_time_remaining = 0.0
	shadow_cleave_buff_time = 0.0
	kagemusha_time_remaining = 0.0
	abyssal_ward_time = 0.0
	abyssal_in_ink = false
	_abyssal_ward_cooldown = 0.0
	shadow_clone_charges = 0
	_clear_runtime_vfx()
	if weapon:
		weapon.set_element(Elements.NONE)


## Effective imbue duration for [param element_name]: the 24 s of Node 1
## (school awakening) when it is unlocked, otherwise [constant ElementBalance.IMBUE_SECONDS].
func imbue_duration_for(element_name: String) -> float:
	if element_name == Elements.NONE:
		return 0.0
	return float(_fx(element_name, "imbue_duration", ElementBalance.IMBUE_SECONDS))


## Imbues the weapon with an element (from a Torii gate). A negative
## [param duration] means "the element's effective duration" (see
## [method imbue_duration_for]); explicit values are honoured as given.
func imbue(element_name: String, duration: float = -1.0) -> void:
	var dur := duration if duration >= 0.0 else imbue_duration_for(element_name)
	imbue_total = maxf(dur, 0.01)
	if element_name == current_element and current_element != Elements.NONE:
		element_time_remaining = dur
		ability_1_cooldown *= ElementBalance.REFRESH_COOLDOWN_KEEP
		ability_2_cooldown *= ElementBalance.REFRESH_COOLDOWN_KEEP
		if weapon:
			weapon.imbue_element(element_name, dur)
		_play_imbue_cue(element_name, true)
		effect_triggered.emit("refresh", {"element": element_name, "duration": dur})
		return

	current_element = element_name
	element_time_remaining = dur if element_name != Elements.NONE else 0.0
	is_fade_warning = false
	ability_1_cooldown = 0.0
	ability_2_cooldown = 0.0
	if weapon:
		weapon.imbue_element(element_name, dur)
	_play_imbue_cue(element_name, false)
	effect_triggered.emit("imbue", {"element": element_name, "duration": dur})


## The sound of the school taking hold of the blade (quiet, from the hand), or a
## softer, higher touch when a gate only tops the same element up.
func _play_imbue_cue(element_name: String, refresh: bool) -> void:
	if element_name == Elements.NONE or not is_inside_tree():
		return
	Sfx.play_at("imbue_" + element_name, _cue_position(), -9.0 if refresh else -5.0, 5.0, 1.12 if refresh else 1.0)


func _cue_position() -> Vector3:
	if weapon and is_instance_valid(weapon) and weapon.is_inside_tree():
		return weapon.global_position
	return _player_origin() + Vector3.UP * 1.1


func _expire_element() -> void:
	var prev := current_element
	Sfx.play_at("element_fade", _cue_position(), -11.0, 5.0)
	current_element = Elements.NONE
	element_time_remaining = 0.0
	is_fade_warning = false
	if weapon:
		weapon.set_element(Elements.NONE)
	# NOTE: Active transient effects (hanamai, ink pools, decoy) finish naturally!
	effect_triggered.emit("element_expired", {"previous": prev})


func visual_element() -> String:
	return current_element


## Human-readable build for the end-screen stele.
func build_summary() -> String:
	if current_element == Elements.NONE:
		return "Unbound"
	return Elements.build_label(current_element)


# --- Active Abilities Entry Points --------------------------------------------

## Triggers Ability 1 (Button A / J) for the active element.
func execute_ability_1(direction: Vector3 = Vector3.ZERO) -> bool:
	if current_element == Elements.NONE:
		_trigger_empty_click()
		return false
	if ability_1_cooldown > 0.0:
		return false

	var dir := _resolve_direction(direction)
	var success := false
	match current_element:
		Elements.SAKURA:
			success = _exec_sakura_1(dir)
		Elements.STORM:
			success = _exec_storm_1(dir)
		Elements.INK:
			success = _exec_ink_1(dir)
		Elements.SHADOW:
			success = _exec_shadow_1(dir)

	if success:
		ability_1_cooldown = float(_fx(current_element, "cooldown_ability_1",
			float(COOLDOWNS_ABILITY_1.get(current_element, 4.0))))
	return success


## Triggers Ability 2 (Button B / K) for the active element.
func execute_ability_2(direction: Vector3 = Vector3.ZERO) -> bool:
	if current_element == Elements.NONE:
		_trigger_empty_click()
		return false
	if ability_2_cooldown > 0.0:
		return false

	var dir := _resolve_direction(direction)
	var success := false
	match current_element:
		Elements.SAKURA:
			success = _exec_sakura_2(dir)
		Elements.STORM:
			success = _exec_storm_2(dir)
		Elements.INK:
			success = _exec_ink_2(dir)
		Elements.SHADOW:
			success = _exec_shadow_2(dir)

	if success:
		ability_2_cooldown = float(_fx(current_element, "cooldown_ability_2",
			float(COOLDOWNS_ABILITY_2.get(current_element, 8.0))))
	return success


## Tactile confirmation on plain steel: subtle muffled click, no popups or error banners.
func _trigger_empty_click() -> void:
	_pulse_sword_hand([[0.12, 0.04]])
	effect_triggered.emit("empty_steel", {})


# --- Sakura Abilities ---------------------------------------------------------

## Ability 1 (Sakura): Senbonzakura (千本桜 / Thousand Petal Slash)
## 6 crystalline glass petals outward in forward fan (32° spread), 12 dmg each,
## pierces 2 yōkai. Tree: Petal Sense 15 dmg; Razor Petals 7 petals, pierces
## all; Kageyoshi detonates an active Hanamai orbit for 120 dmg around the player.
func _exec_sakura_1(direction: Vector3) -> bool:
	var origin := weapon.get_tip_global() if weapon else _player_origin() + Vector3.UP * 1.0
	var count := int(_fx(Elements.SAKURA, "senbonzakura_petal_count", ElementBalance.SENBONZAKURA_PETALS))
	var damage := float(_fx(Elements.SAKURA, "senbonzakura_damage", ElementBalance.SENBONZAKURA_DAMAGE))
	var pierce := int(_fx(Elements.SAKURA, "senbonzakura_pierce", ElementBalance.SENBONZAKURA_PIERCE))
	_spawn_cutting_petals(origin, direction, count, damage, pierce)
	if _has_node("senbonzakura_kageyoshi") and hanamai_time_remaining > 0.0:
		var burst := float(_fx(Elements.SAKURA, "kageyoshi_burst_damage", ElementBalance.KAGEYOSHI_DAMAGE))
		var center := _player_origin()
		for enemy in _alive_enemies():
			if _enemy_center(enemy).distance_to(center) <= ElementBalance.KAGEYOSHI_RADIUS:
				_hit(enemy, burst, Elements.SAKURA, _enemy_center(enemy), (_enemy_center(enemy) - center).normalized())
		hanamai_time_remaining = 0.0
		_clear_orbit_petals()
		effect_triggered.emit("kageyoshi_burst", {"damage": burst})
	_pulse_sword_hand([[0.75, 0.03], [0.35, 0.04], [0.15, 0.02]])
	Sfx.play_at("yokai_slice", origin, -2.0, 4.0, 1.25)
	effect_triggered.emit("senbonzakura", {"count": count})
	return true


## Ability 2 (Sakura): Hanamai (花舞 / Petal Dance Barrier)
## 4 glass petals orbiting player torso at 1.2m for 6.0s, 7 dmg per contact
## (every 0.45 s per yōkai), -30% incoming damage. Tree: Storm of Hanami 8.5 s
## and −45% damage taken.
func _exec_sakura_2(_direction: Vector3) -> bool:
	hanamai_time_remaining = float(_fx(Elements.SAKURA, "hanamai_duration", ElementBalance.HANAMAI_DURATION))
	_rebuild_hanamai_orbit(ElementBalance.HANAMAI_PETALS)
	_pulse_both_hands([[0.5, 0.08], [0.25, 0.12]])
	Sfx.play_at("level_up", _player_origin(), -6.0, 3.5, 1.3)
	effect_triggered.emit("hanamai", {"duration": hanamai_time_remaining})
	return true


# --- Storm Abilities ----------------------------------------------------------

## Ability 1 (Storm): Raikiri (雷切 / Lightning Cutter)
## Searing chain lightning: 45 dmg to primary target, 24 dmg to up to 3 nearby enemies within 5m.
func _exec_storm_1(direction: Vector3) -> bool:
	var origin := weapon.get_tip_global() if weapon else _player_origin() + Vector3.UP * 1.0
	var primary := _nearest_enemy_in_cone(origin, direction, ElementBalance.RAIKIRI_RANGE, 0.5)
	if primary == null:
		primary = _nearest_enemy(origin, ElementBalance.RAIKIRI_RANGE)
	if primary == null:
		# Discharge harmlessly forward if no target
		var dummy_point := origin + direction * 5.0
		_spawn_lightning([origin, dummy_point], Color(0.32, 0.82, 1.0), 0.16, 0.010)
		_pulse_sword_hand([[0.9, 0.05], [0.4, 0.06], [0.8, 0.03]])
		Sfx.play_at("thunder", origin, 0.0, 5.0, 1.35)
		effect_triggered.emit("raikiri", {"targets": 0})
		return true

	var primary_center := _enemy_center(primary)
	_hit(primary, ElementBalance.RAIKIRI_PRIMARY_DAMAGE, Elements.STORM, primary_center, direction)
	var stun := float(_fx(Elements.STORM, "raikiri_stun_duration", 0.0))
	if stun > 0.0:
		primary.apply_stagger(stun)
	var points: Array[Vector3] = [origin, primary_center]

	var chain_count := int(_fx(Elements.STORM, "raikiri_chain_targets", ElementBalance.RAIKIRI_CHAIN_TARGETS))
	var chain_targets := _nearest_enemies_excluding(primary_center, chain_count, ElementBalance.RAIKIRI_CHAIN_RADIUS, [primary])
	for enemy in chain_targets:
		var target_center := _enemy_center(enemy)
		_hit(enemy, ElementBalance.RAIKIRI_CHAIN_DAMAGE, Elements.STORM, target_center, (target_center - primary_center).normalized())
		points.append(target_center)

	_spawn_lightning(points, Color(0.32, 0.82, 1.0), 0.16, 0.012)
	_pulse_sword_hand([[0.9, 0.05], [0.4, 0.06], [0.8, 0.03]])
	Sfx.play_at("thunder", origin, 0.0, 5.0, 1.35)
	effect_triggered.emit("raikiri", {"targets": 1 + chain_targets.size()})
	return true


## Ability 2 (Storm): Shiden (紫電 / Thunder Step)
## High-velocity dash 4.2m forward, staggers enemies at departure point within
## 2.8m for 1.4s (15 dmg). Tree: Flash Stride 6.0 m / 2.2 s; Ikazuchi Avatar leaves a
## 4 s lightning barrier between departure and arrival.
func _exec_storm_2(direction: Vector3) -> bool:
	var player_pos := _player_origin()
	var distance := float(_fx(Elements.STORM, "shiden_distance", ElementBalance.SHIDEN_DISTANCE))
	var stagger := float(_fx(Elements.STORM, "shiden_stagger", ElementBalance.SHIDEN_STAGGER))
	var from := player_pos + Vector3(0.0, 0.85, 0.0)

	var sweep := PhysicsShapeQueryParameters3D.new()
	var body := SphereShape3D.new()
	body.radius = 0.32
	sweep.shape = body
	sweep.transform = Transform3D(Basis.IDENTITY, from)
	sweep.motion = direction * distance
	sweep.collision_mask = 1 | ForestWorld.TRUNK_LAYER
	var fractions := get_world_3d().direct_space_state.cast_motion(sweep)
	var safe := float(fractions[0]) if fractions.size() > 0 else 1.0
	var safe_distance := maxf(0.0, distance * safe - 0.5)
	var desired := player_pos + direction * safe_distance

	if run_game and run_game.forest_world:
		desired.y = run_game.forest_world.height_at(desired.x, desired.z)

	# Stagger enemies at departure point within 2.8m
	for enemy in _alive_enemies():
		if _enemy_center(enemy).distance_to(player_pos) <= ElementBalance.SHIDEN_RADIUS:
			enemy.apply_stagger(stagger)
			_hit(enemy, ElementBalance.SHIDEN_DAMAGE, Elements.STORM, _enemy_center(enemy), Vector3.UP)

	# Teleport player
	_teleport_player(desired)

	# Ikazuchi Avatar: a crackling barrier remains along the dash line.
	var barrier_time := float(_fx(Elements.STORM, "shiden_barrier_duration", 0.0))
	if barrier_time > 0.0:
		_barriers.append({
			"from": player_pos, "to": desired, "age": 0.0,
			"lifetime": barrier_time, "tick": 0.0,
			"damage": float(_fx(Elements.STORM, "shiden_barrier_damage", ElementBalance.IKAZUCHI_DAMAGE)),
		})

	# VFX & SFX
	_spawn_lightning([from, desired + Vector3(0.0, 0.85, 0.0)], Color(0.4, 0.9, 2.5), 0.25, 0.016)
	if is_inside_tree() and get_tree().current_scene:
		SparkBurst.spawn(get_tree().current_scene, player_pos + Vector3.UP * 0.5, Vector3.UP, Color(0.32, 0.82, 1.0), 8, 1.5)
	_pulse_both_hands([[0.85, 0.04], [0.7, 0.08]])
	Sfx.play_at("thunder", player_pos, 2.0, 5.0, 1.1)
	effect_triggered.emit("shiden", {"from": player_pos, "to": desired})
	return true


# --- Ink Abilities ------------------------------------------------------------

## Ability 1 (Ink): Sumi-gaeshi (墨返し / Ink Sweep)
## Horizontal ground wave in 60° forward cone up to 4.5m: 7 dmg + 60% slow,
## paints a 5.0 s ink pool (8 dmg/s). Tree: Sumi Mastery slows 75%; Splatter Tide
## widens the cone to 90° and doubles the pool's damage over time.
func _exec_ink_1(direction: Vector3) -> bool:
	var player_pos := _player_origin()
	var cone_range := ElementBalance.SUMI_RANGE
	var half_deg := float(_fx(Elements.INK, "sumi_cone_half_deg", ElementBalance.SUMI_HALF_DEGREES))
	var half_angle_cos := cos(deg_to_rad(half_deg))
	var slow_scale := float(_fx(Elements.INK, "ink_slow_scale", ElementBalance.SUMI_SLOW_SCALE))

	for enemy in _alive_enemies():
		var diff := _enemy_center(enemy) - player_pos
		var flat_dist := Vector2(diff.x, diff.z).length()
		if flat_dist <= cone_range and flat_dist > 0.05:
			var dot := Vector2(direction.x, direction.z).normalized().dot(Vector2(diff.x, diff.z).normalized())
			if dot >= half_angle_cos:
				_hit(enemy, ElementBalance.SUMI_DAMAGE, Elements.INK, _enemy_center(enemy), direction)
				enemy.apply_slow(ElementBalance.SUMI_SLOW_SECONDS, slow_scale)

	var pool_center := player_pos + direction * ElementBalance.SUMI_POOL_RADIUS
	paint_ink(pool_center, ElementBalance.SUMI_POOL_RADIUS, ElementBalance.SUMI_POOL_SECONDS,
		float(_fx(Elements.INK, "ink_dps", ElementBalance.SUMI_POOL_DPS)))

	_pulse_sword_hand([[0.6, 0.14]])
	Sfx.play_at("slap", pool_center, 0.0, 4.0, 0.8)
	effect_triggered.emit("sumi_gaeshi", {"position": pool_center})
	return true


## Ability 2 (Ink): Kage-nawa (影縄 / Ink Binding Tendrils)
## Roots up to 3 enemies within 7m for 2.8s, deals 20 impact dmg, and drags
## them 1.5m toward player. Tree: Black Bind snares 5 and pulls into melee.
func _exec_ink_2(_direction: Vector3) -> bool:
	var player_pos := _player_origin()
	var max_targets := int(_fx(Elements.INK, "kage_nawa_targets", ElementBalance.KAGE_NAWA_TARGETS))
	var targets := _nearest_enemies(player_pos, max_targets, ElementBalance.KAGE_NAWA_RANGE)
	if targets.is_empty():
		return false

	for enemy in targets:
		var center := _enemy_center(enemy)
		_hit(enemy, ElementBalance.KAGE_NAWA_DAMAGE, Elements.INK, center, Vector3.UP)
		enemy.apply_slow(ElementBalance.KAGE_NAWA_ROOT_SECONDS, ElementBalance.KAGE_NAWA_ROOT_SCALE)

		# Pull toward the player (into melee range with Black Bind).
		var to_player := player_pos - center
		to_player.y = 0.0
		var dist := to_player.length()
		var pull_amount := clampf(dist - 1.05, 0.0, 6.0) if _has_node("black_bind") else clampf(dist - 1.2, 0.0, ElementBalance.KAGE_NAWA_PULL)
		if pull_amount > 0.0 and dist > 0.01:
			var pull_vec := to_player.normalized() * pull_amount
			enemy.global_position += pull_vec

		_spawn_ink_tendril(_ground_below(center), center)

	_pulse_sword_hand([[0.3, 0.06], [0.5, 0.08], [0.8, 0.06]])
	Sfx.play_at("cut", player_pos, -2.0, 4.0, 0.7)
	effect_triggered.emit("kage_nawa", {"targets": targets.size()})
	return true


# --- Shadow Abilities ---------------------------------------------------------

## Ability 1 (Shadow): Kagemusha (影武者 / Shadow Decoy)
## Smoke silhouette decoy for 4.0s or 2 hits; redirects enemy aggro within 9.0m.
func _exec_shadow_1(_direction: Vector3) -> bool:
	var player_pos := _player_origin()
	_spawn_shadow_decoy(player_pos)
	_pulse_sword_hand([[0.35, 0.04], [0.2, 0.08]])
	Sfx.play_at("enemy_tell", player_pos, -4.0, 4.0, 0.65)
	effect_triggered.emit("kagemusha", {"position": player_pos})
	return true


## Ability 2 (Shadow): Yami-watari (闇渡り / Shadow Step & Cleave)
## Blinks behind nearest target within 4.5m (or forward); primes a x2.2
## critical strike on the next hit within 2.5 s. Tree: Umbral Reach searches 6.5 m; Shadow
## Clones mirror the next cut onto 2 nearby yōkai.
func _exec_shadow_2(direction: Vector3) -> bool:
	var player_pos := _player_origin()
	var search_range := float(_fx(Elements.SHADOW, "yami_range", ElementBalance.YAMI_RANGE))
	var target := _nearest_enemy(player_pos, search_range)
	var desired := player_pos + direction * 2.5
	var target_yaw := 0.0

	if target:
		var enemy_pos := _enemy_center(target)
		var enemy_fwd := Vector3(sin(target._facing_yaw), 0.0, cos(target._facing_yaw))
		desired = enemy_pos - enemy_fwd * 0.9
		target_yaw = atan2(enemy_pos.x - desired.x, enemy_pos.z - desired.z)
		# Keep distance within test bounds
		if player_pos.distance_to(desired) > 3.0:
			desired = player_pos + (desired - player_pos).normalized() * 2.8
	elif run_game and run_game.player:
		target_yaw = run_game.player.rotation.y

	# Obstacle raycast clamp
	if run_game and run_game.forest_world:
		desired.y = run_game.forest_world.height_at(desired.x, desired.z)

	_spawn_darkness(player_pos)
	_spawn_shadow_trace(player_pos + Vector3.UP * 0.8, desired + Vector3.UP * 0.8)
	_teleport_player(desired, target_yaw)

	shadow_cleave_buff_time = ElementBalance.YAMI_CRIT_SECONDS
	shadow_clone_charges = int(_fx(Elements.SHADOW, "shadow_clone_count", 0))
	_pulse_sword_hand([[0.25, 0.04], [0.9, 0.06]])
	Sfx.play_at("ofuda_slice", player_pos, 0.0, 4.0, 0.9)
	effect_triggered.emit("yami_watari", {"from": player_pos, "to": desired})
	return true


# --- Physics Processing & Lifecycle -------------------------------------------

func _physics_process(delta: float) -> void:
	# CRITICAL: Respect SceneTree pause cleanly (NEVER Engine.time_scale = 0)
	if get_tree() and get_tree().paused:
		return
	if weapon:
		weapon.kirisute_ready = kirisute_ready()

	# Tick cooldowns
	ability_1_cooldown = maxf(0.0, ability_1_cooldown - delta)
	ability_2_cooldown = maxf(0.0, ability_2_cooldown - delta)
	_chain_cooldown = maxf(0.0, _chain_cooldown - delta)
	shadow_cleave_buff_time = maxf(0.0, shadow_cleave_buff_time - delta)

	# Tick ongoing Hanamai barrier (independent of element duration)
	if hanamai_time_remaining > 0.0:
		hanamai_time_remaining = maxf(0.0, hanamai_time_remaining - delta)
		_update_orbit_petals(delta)
		if hanamai_time_remaining <= 0.0:
			_clear_orbit_petals()

	# Tick ongoing Shadow Decoy (Phantom Retaliation: expiry explodes)
	if kagemusha_time_remaining > 0.0:
		kagemusha_time_remaining = maxf(0.0, kagemusha_time_remaining - delta)
		if kagemusha_time_remaining <= 0.0:
			_end_decoy()

	# Tick element imbue duration
	if current_element != Elements.NONE:
		element_time_remaining = maxf(0.0, element_time_remaining - delta)
		is_fade_warning = (element_time_remaining <= ElementBalance.FADE_WARNING_SECONDS and element_time_remaining > 0.0)
		if weapon:
			weapon.element = current_element
			weapon.element_time_remaining = element_time_remaining
			weapon.is_fade_warning = is_fade_warning
			weapon._update_blade_material()
		if element_time_remaining <= 0.0:
			_expire_element()

	_update_barriers(delta)
	_update_abyssal_ward(delta)

	_update_petals(delta)
	_update_ink_pools(delta)
	_update_darkness(delta)
	_update_transients(delta)


## A yōkai's claw landed on the decoy (called through the "element_system" group
## by [Yokai]): it absorbs [constant ElementBalance.KAGEMUSHA_HITS] strikes, then
## dissolves like it would on time-out.
func on_decoy_struck() -> void:
	if kagemusha_decoy == null or not is_instance_valid(kagemusha_decoy):
		return
	kagemusha_hits_remaining -= 1
	if kagemusha_hits_remaining <= 0:
		kagemusha_time_remaining = 0.0
		_end_decoy()


## Removes the decoy; Phantom Retaliation (Shadow Node 2) makes it burst.
func _end_decoy() -> void:
	if kagemusha_decoy == null or not is_instance_valid(kagemusha_decoy):
		return
	var decoy_pos := kagemusha_decoy.global_position
	kagemusha_decoy.queue_free()
	kagemusha_decoy = null
	var boom := float(_fx(Elements.SHADOW, "decoy_explosion_damage", 0.0))
	if boom > 0.0:
		for enemy in _alive_enemies():
			if _enemy_center(enemy).distance_to(decoy_pos) <= ElementBalance.DECOY_EXPLOSION_RADIUS:
				_hit(enemy, boom, Elements.SHADOW, _enemy_center(enemy), Vector3.UP)
		_spawn_darkness(decoy_pos, 3.0, 1.2)
		effect_triggered.emit("decoy_explosion", {"position": decoy_pos, "damage": boom})


## Ikazuchi Avatar barriers: yōkai near the dash line take damage twice a second.
func _update_barriers(delta: float) -> void:
	for i in range(_barriers.size() - 1, -1, -1):
		var b: Dictionary = _barriers[i]
		b.age = float(b.age) + delta
		if float(b.age) >= float(b.lifetime):
			_barriers.remove_at(i)
			continue
		b.tick = float(b.tick) - delta
		if float(b.tick) <= 0.0:
			b.tick = 0.5
			var a: Vector3 = b.from
			var c: Vector3 = b.to
			for enemy in _alive_enemies():
				var center := _enemy_center(enemy)
				var closest := Geometry3D.get_closest_point_to_segment(center, a + Vector3.UP * 0.8, c + Vector3.UP * 0.8)
				if center.distance_to(closest) <= 1.1:
					_hit(enemy, float(b.damage), Elements.STORM, center, Vector3.UP)
			_spawn_lightning([a + Vector3.UP * 0.8, c + Vector3.UP * 0.8], Color(0.32, 0.82, 1.0), 0.3, 0.008)
		_barriers[i] = b


## Abyssal Sea: stepping onto your own ink grants a 0.5 s ward (once per
## [constant ABYSSAL_WARD_REARM]); standing in it keeps the speed boost.
func _update_abyssal_ward(delta: float) -> void:
	abyssal_ward_time = maxf(0.0, abyssal_ward_time - delta)
	_abyssal_ward_cooldown = maxf(0.0, _abyssal_ward_cooldown - delta)
	var inside := false
	if _has_node("abyssal_sea") and not _ink_pools.is_empty():
		var p := _player_origin()
		for pool: Dictionary in _ink_pools:
			var flat := p - (pool.position as Vector3)
			flat.y = 0.0
			if flat.length() <= float(pool.radius):
				inside = true
				break
	if inside and not abyssal_in_ink and _abyssal_ward_cooldown <= 0.0:
		abyssal_ward_time = ABYSSAL_WARD_TIME
		_abyssal_ward_cooldown = ABYSSAL_WARD_REARM
	abyssal_in_ink = inside


## True during the brief Abyssal Sea ward (PlayerHealth negates that one hit window).
func is_player_warded() -> bool:
	return abyssal_ward_time > 0.0


## Locomotion multiplier from Abyssal Sea while standing in ink (1.0 else).
func get_player_speed_multiplier() -> float:
	if abyssal_in_ink and _has_node("abyssal_sea"):
		return float(_fx(Elements.INK, "abyssal_speed_multiplier", 1.0))
	return 1.0


func on_blade_hit(hit: Dictionary) -> void:
	if float(hit.get("damage", 0.0)) <= 0.0:
		return
	var point: Vector3 = hit.get("point", weapon.get_tip_global() if weapon else Vector3.ZERO)
	var direction: Vector3 = hit.get("direction", Vector3.FORWARD)

	# Shadow Cleave critical strike
	if shadow_cleave_buff_time > 0.0:
		shadow_cleave_buff_time = 0.0
		hit["damage"] = float(hit.get("damage", 0.0)) * ElementBalance.YAMI_CRIT_MULTIPLIER
		_spawn_shadow_trace(point, point + Vector3.UP * 0.5)
		effect_triggered.emit("shadow_cleave_crit", {"point": point})

	# Skill-tree blade procs (E2c). All are gated on their node being unlocked.
	if current_element != Elements.NONE and skill_tree:
		var struck := _enemy_near(point, 1.4)
		if current_element == Elements.SAKURA:
			# Life Bloom: each connecting Sakura cut restores a little life.
			var heal_hit := float(_fx(Elements.SAKURA, "heal_on_hit", 0.0))
			if heal_hit > 0.0 and run_game:
				var health := run_game._player_health()
				if health and health.is_alive():
					health.heal(heal_hit)
		elif current_element == Elements.STORM and struck:
			# Overcharge: the cut arcs to one more nearby yōkai.
			var arc := float(_fx(Elements.STORM, "overcharge_damage", 0.0))
			if arc > 0.0 and _chain_cooldown <= 0.0:
				var others := _nearest_enemies_excluding(_enemy_center(struck), 1, 5.0, [struck])
				if not others.is_empty():
					var other_center := _enemy_center(others[0])
					_hit(others[0], arc, Elements.STORM, other_center, Vector3.UP)
					_spawn_lightning([point, other_center], Color(0.32, 0.82, 1.0), 0.14, 0.008)
					_chain_cooldown = ElementBalance.OVERCHARGE_COOLDOWN
					effect_triggered.emit("overcharge", {"point": other_center})
		elif current_element == Elements.INK and struck:
			# Dragon Calligraphy: yōkai standing in ink take heavier cuts.
			var dragon := float(_fx(Elements.INK, "dragon_damage_multiplier", 1.0))
			if dragon > 1.0 and _enemy_in_ink(struck):
				hit["damage"] = float(hit.get("damage", 0.0)) * dragon
				effect_triggered.emit("dragon_calligraphy", {"point": point})
		elif current_element == Elements.SHADOW and struck:
			# Backstab Execution: a strike from behind cuts far deeper (D1: the
			# bonus Ofuda is gone, Ofuda come from hokora shrines only).
			var mult := float(_fx(Elements.SHADOW, "backstab_multiplier", 1.0))
			if mult > 1.0:
				var fwd := Vector3(sin(struck._facing_yaw), 0.0, cos(struck._facing_yaw))
				var to_player := _player_origin() - _enemy_center(struck)
				to_player.y = 0.0
				if to_player.length_squared() > 0.01 and fwd.dot(to_player.normalized()) < -0.2:
					hit["damage"] = float(hit.get("damage", 0.0)) * mult
					effect_triggered.emit("backstab", {"point": point})
		# Shadow Clones: the first cut after Yami-watari is mirrored onto
		# the nearest other yōkai by two fleeting silhouettes.
		if shadow_clone_charges > 0 and struck:
			var mirrors := _nearest_enemies_excluding(_enemy_center(struck),
				shadow_clone_charges, 4.5, [struck])
			for mirror in mirrors:
				mirror.receive_element_damage(float(hit.get("damage", 0.0)), Elements.SHADOW,
					_enemy_center(mirror), Vector3.UP)
			if not mirrors.is_empty():
				effect_triggered.emit("shadow_clones", {"targets": mirrors.size()})
			shadow_clone_charges = 0

	# Elemental spark feedback on hit
	if current_element != Elements.NONE and is_inside_tree() and get_tree().current_scene:
		SparkBurst.spawn(get_tree().current_scene, point, direction, Elements.color(current_element), 6, 1.2)


## Nearest living yōkai to [param point] within [param max_dist], or null.
func _enemy_near(point: Vector3, max_dist: float) -> Yokai:
	var best: Yokai = null
	var best_d := max_dist
	for enemy in _alive_enemies():
		var d := _enemy_center(enemy).distance_to(point)
		if d <= best_d:
			best = enemy
			best_d = d
	return best


## True when [param enemy] stands inside one of the player's ink pools.
func _enemy_in_ink(enemy: Yokai) -> bool:
	var center := _enemy_center(enemy)
	for pool: Dictionary in _ink_pools:
		var flat := center - (pool.position as Vector3)
		flat.y = 0.0
		if flat.length() <= float(pool.radius):
			return true
	return false


func on_enemy_died(_enemy: Yokai) -> void:
	# Life Bloom (Sakura Node 4): a kill under Sakura restores 12 HP.
	if current_element == Elements.SAKURA and run_game:
		var heal_kill := float(_fx(Elements.SAKURA, "heal_on_kill", 0.0))
		if heal_kill <= 0.0:
			return
		var health := run_game._player_health()
		if health and health.is_alive():
			health.heal(heal_kill)
			effect_triggered.emit("sakura_heal", {"amount": heal_kill})


## Damage multiplier for Hanamai (Sakura Ability 2): incoming damage reduced
## by 30% (45% with Storm of Hanami) while the barrier orbits.
func get_incoming_damage_multiplier() -> float:
	if hanamai_time_remaining <= 0.0:
		return 1.0
	return float(_fx(Elements.SAKURA, "incoming_damage_multiplier", ElementBalance.HANAMAI_DAMAGE_TAKEN))


# --- VFX & Mesh Pool Systems --------------------------------------------------

func _build_shared_petals() -> void:
	_petal_mesh = QuadMesh.new()
	_petal_mesh.size = Vector2(0.075, 0.16)
	_petal_mat = ShaderMaterial.new()
	_petal_mat.shader = PETAL_SHADER


func debug_release_petals(direction: Vector3 = Vector3.FORWARD) -> void:
	var origin := weapon.get_tip_global() if weapon else _player_origin() + Vector3.UP * 1.0
	_spawn_cutting_petals(origin, direction.normalized() if direction.length_squared() > 0.01 else Vector3.FORWARD, 3)


func _spawn_cutting_petals(origin: Vector3, direction: Vector3, count: int = ElementBalance.SENBONZAKURA_PETALS,
		damage: float = ElementBalance.SENBONZAKURA_DAMAGE, pierce: int = ElementBalance.SENBONZAKURA_PIERCE) -> void:
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()

	var arc_rad := deg_to_rad(ElementBalance.SENBONZAKURA_FAN_DEGREES)
	var step := arc_rad / maxf(1.0, float(count - 1))

	for i in count:
		while _petals.size() >= MAX_PETALS:
			_free_petal(0)

		var node := MeshInstance3D.new()
		node.name = "CuttingPetal"
		node.mesh = _petal_mesh
		node.material_override = _petal_mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(node)

		var offset_angle := -arc_rad * 0.5 + float(i) * step
		var petal_dir := direction.rotated(Vector3.UP, offset_angle).normalized()
		node.global_position = origin + right * (float(i) - float(count - 1) * 0.5) * 0.05
		node.look_at(node.global_position + petal_dir, Vector3.UP)

		var velocity := petal_dir * ElementBalance.SENBONZAKURA_SPEED
		_petals.append({
			"node": node,
			"velocity": velocity,
			"age": 0.0,
			"max_age": ElementBalance.SENBONZAKURA_LIFETIME,
			"damage": damage,
			"pierce": pierce,
			"hit_ids": {},
		})


func _update_petals(delta: float) -> void:
	for i in range(_petals.size() - 1, -1, -1):
		var p: Dictionary = _petals[i]
		var node := p.node as MeshInstance3D
		if not is_instance_valid(node):
			_petals.remove_at(i)
			continue
		p.age = float(p.age) + delta
		if p.age >= float(p.max_age):
			_free_petal(i)
			continue

		var velocity: Vector3 = p.velocity
		node.global_position += velocity * delta
		node.rotate_object_local(Vector3.FORWARD, delta * 8.0)
		_petals[i] = p

		for enemy in _alive_enemies():
			var e_center := _enemy_center(enemy)
			var diff := node.global_position - e_center
			if absf(diff.y) <= 0.85 and Vector2(diff.x, diff.z).length() <= 0.65:
				var id := enemy.get_instance_id()
				var hit_ids: Dictionary = p.hit_ids
				if not hit_ids.has(id):
					hit_ids[id] = true
					_hit(enemy, float(p.damage), Elements.SAKURA, node.global_position, velocity.normalized())
					p.pierce = int(p.pierce) - 1
					if int(p.pierce) <= 0:
						_free_petal(i)
						break


func _rebuild_hanamai_orbit(count: int = 4) -> void:
	_clear_orbit_petals()
	for i in count:
		var petal := MeshInstance3D.new()
		petal.name = "HanamaiPetal"
		petal.mesh = _petal_mesh
		petal.material_override = _petal_mat
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		petal.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(petal)
		_orbit_petals.append(petal)


func _update_orbit_petals(delta: float) -> void:
	if _orbit_petals.is_empty():
		return
	_orbit_clock += delta
	for id in _orbit_hits.keys():
		_orbit_hits[id] -= delta
		if _orbit_hits[id] <= 0.0:
			_orbit_hits.erase(id)

	var center := _player_origin() + Vector3(0.0, 0.9, 0.0)
	var radius := ElementBalance.HANAMAI_RADIUS
	for i in _orbit_petals.size():
		var angle := _orbit_clock * 2.5 + TAU * float(i) / float(_orbit_petals.size())
		var petal := _orbit_petals[i]
		petal.global_position = center + Vector3(cos(angle) * radius, sin(angle * 2.0) * 0.12, sin(angle) * radius)
		petal.rotation = Vector3(angle * 0.8, -angle, angle * 1.4)
		for enemy in _nearest_enemies(petal.global_position, 1, 0.45):
			var id := enemy.get_instance_id()
			if not _orbit_hits.has(id):
				_orbit_hits[id] = ElementBalance.HANAMAI_TICK
				_hit(enemy, ElementBalance.HANAMAI_DAMAGE, Elements.SAKURA, petal.global_position, (_enemy_center(enemy) - center).normalized())


func _clear_orbit_petals() -> void:
	for p in _orbit_petals:
		if is_instance_valid(p):
			p.queue_free()
	_orbit_petals.clear()
	_orbit_hits.clear()


func paint_ink(at: Vector3, radius: float = ElementBalance.SUMI_POOL_RADIUS,
		lifetime: float = ElementBalance.SUMI_POOL_SECONDS, dps: float = ElementBalance.SUMI_POOL_DPS) -> void:
	var ground := _ground_below(at)
	while _ink_pools.size() >= MAX_INK_POOLS:
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
	mesh_instance.material_override = mat
	root.add_child(mesh_instance)
	_ink_pools.append({
		"node": root, "mat": mat, "position": root.global_position,
		"radius": radius, "lifetime": lifetime, "age": 0.0, "dps": dps,
	})
	effect_triggered.emit("ink_pool", {"position": ground, "radius": radius})


func _update_ink_pools(delta: float) -> void:
	for i in range(_ink_pools.size() - 1, -1, -1):
		var pool: Dictionary = _ink_pools[i]
		pool.age = float(pool.age) + delta
		if pool.age >= float(pool.lifetime) or not is_instance_valid(pool.node):
			_free_pool(i)
			continue
		(pool.mat as ShaderMaterial).set_shader_parameter("age", pool.age)
		var pool_slow := float(_fx(Elements.INK, "ink_slow_scale", ElementBalance.SUMI_SLOW_SCALE))
		for enemy in _alive_enemies():
			var flat := _enemy_center(enemy) - (pool.position as Vector3)
			flat.y = 0.0
			if flat.length() <= float(pool.radius):
				enemy.apply_slow(0.3, pool_slow)
				_hit(enemy, float(pool.get("dps", ElementBalance.SUMI_POOL_DPS)) * delta, Elements.INK, _enemy_center(enemy), Vector3.UP)
		_ink_pools[i] = pool


func _spawn_ink_tendril(from: Vector3, to: Vector3) -> void:
	var points: Array[Vector3] = [
		from + Vector3.UP * 0.04,
		from.lerp(to, 0.45) + Vector3.UP * 0.55,
		to,
	]
	_spawn_lightning(points, Color(0.24, 0.28, 0.52), 0.40, 0.014, false)


func _spawn_shadow_decoy(at: Vector3) -> void:
	if kagemusha_decoy and is_instance_valid(kagemusha_decoy):
		kagemusha_decoy.queue_free()

	kagemusha_decoy = Node3D.new()
	kagemusha_decoy.name = "ShadowDecoy"
	kagemusha_decoy.add_to_group("shadow_decoy")
	add_child(kagemusha_decoy)
	kagemusha_decoy.global_position = at

	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.30
	capsule.height = 1.75
	mesh_inst.mesh = capsule
	mesh_inst.position.y = 0.88
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("phase", 0.0)
	mat.set_shader_parameter("opacity", 0.65)
	mesh_inst.material_override = mat
	kagemusha_decoy.add_child(mesh_inst)

	kagemusha_time_remaining = float(_fx(Elements.SHADOW, "kagemusha_duration", ElementBalance.KAGEMUSHA_SECONDS))
	kagemusha_hits_remaining = ElementBalance.KAGEMUSHA_HITS


func _spawn_darkness(at: Vector3, radius: float = 3.4, lifetime: float = 3.2) -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
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


func _spawn_shadow_trace(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	if dir.length_squared() < 0.01:
		return
	var points: Array[Vector3] = [from, from.lerp(to, 0.5) + Vector3.UP * 0.18, to]
	_spawn_lightning(points, Color(0.58, 0.16, 1.2), 0.30, 0.018, false)


## [param electric] gives the bolt a deep saturated blue outline (Storm); without
## it the outline is just the tint (the Ink tendrils).
func _spawn_lightning(points: Array[Vector3], color: Color, lifetime: float, width: float = 0.010,
		electric: bool = true) -> void:
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

	if electric:
		# A saturated outline mixed (not added) over the pale fog keeps its hue and
		# contrasts with the near-white core; a pastel halo would wash into the mist.
		var halo := Color(color.r * 0.30, color.g * 0.62, minf(color.b * 1.3, 1.4))
		_spawn_lightning_layer(edges, halo, lifetime, width * 3.0, 0.62, 0.6, false)
		var spark_core := Color(0.78 + color.r * 0.10, 0.90 + color.g * 0.06, 1.08)
		_spawn_lightning_layer(edges, spark_core, lifetime, width * 0.62, 0.92, 1.1, true)
	else:
		_spawn_lightning_layer(edges, color * 0.42, lifetime, width * 2.5, 0.38, 0.24, false)
		var core := Color(0.72 + color.r * 0.12, 0.82 + color.g * 0.10, 1.02 + color.b * 0.08)
		_spawn_lightning_layer(edges, core, lifetime, width * 0.72, 0.88, 0.95, true)


func _spawn_lightning_layer(edges: Array, color: Color, lifetime: float, width: float,
		alpha: float, energy: float, additive: bool) -> void:
	while _transients.size() >= MAX_TRANSIENT_MESHES:
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


# --- Target Finding & Spatial Helpers ------------------------------------------

func _alive_enemies() -> Array[Yokai]:
	if run_game and run_game.wave_director:
		return run_game.wave_director.alive_enemies()
	var empty: Array[Yokai] = []
	return empty


func _nearest_enemy(point: Vector3, max_dist: float) -> Yokai:
	var list := _nearest_enemies(point, 1, max_dist)
	return list[0] if not list.is_empty() else null


func _nearest_enemy_in_cone(point: Vector3, direction: Vector3, max_dist: float, min_dot: float) -> Yokai:
	var best: Yokai = null
	var best_dist := max_dist
	for enemy in _alive_enemies():
		var to_e := _enemy_center(enemy) - point
		var d := to_e.length()
		if d <= best_dist and d > 0.05:
			if direction.normalized().dot(to_e.normalized()) >= min_dot:
				best = enemy
				best_dist = d
	return best


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


func _nearest_enemies_excluding(point: Vector3, count: int, max_distance: float, exclude: Array[Yokai]) -> Array[Yokai]:
	var candidates := _alive_enemies()
	candidates.sort_custom(func(a: Yokai, b: Yokai) -> bool:
		return _enemy_center(a).distance_squared_to(point) < _enemy_center(b).distance_squared_to(point))
	var result: Array[Yokai] = []
	for enemy in candidates:
		if exclude.has(enemy):
			continue
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


func _resolve_direction(dir: Vector3) -> Vector3:
	if dir.length_squared() > 0.01:
		return dir.normalized()
	if run_game and run_game.player:
		var frame := run_game._player_view_frame()
		var f := -frame.basis.z
		f.y = 0.0
		if f.length_squared() > 0.01:
			return f.normalized()
	return Vector3.FORWARD


func _player_origin() -> Vector3:
	if run_game and run_game.player:
		if run_game.player is XRPlayer:
			return (run_game.player as XRPlayer).feet_position()
		return run_game.player.global_position
	return global_position


func _teleport_player(target_pos: Vector3, yaw: float = 0.0) -> void:
	if run_game and run_game.player:
		if run_game.player is DesktopPlayer:
			(run_game.player as DesktopPlayer).teleport(target_pos, yaw)
		elif run_game.player is XRPlayer:
			(run_game.player as XRPlayer).teleport_feet(target_pos)
		else:
			run_game.player.global_position = target_pos


func _pulse_sword_hand(pattern: Array) -> void:
	if weapon and weapon.holder and weapon.holder.has_method("pulse_pattern"):
		weapon.holder.pulse_pattern(pattern)
	elif weapon:
		for h in weapon.holders:
			if h and h.has_method("pulse_pattern"):
				h.pulse_pattern(pattern)


func _pulse_both_hands(pattern: Array) -> void:
	if weapon:
		for h in weapon.holders:
			if h and h.has_method("pulse_pattern"):
				h.pulse_pattern(pattern)
	if run_game and run_game.player is XRPlayer:
		var xr: XRPlayer = run_game.player
		if xr.left_holder: xr.left_holder.pulse_pattern(pattern)
		if xr.right_holder: xr.right_holder.pulse_pattern(pattern)


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
	_barriers.clear()
	for collection in [_petals, _ink_pools, _transients, _darkness_areas]:
		for entry in collection:
			var node: Object = entry.get("node")
			if is_instance_valid(node):
				node.queue_free()
		collection.clear()
	_clear_orbit_petals()
	if kagemusha_decoy and is_instance_valid(kagemusha_decoy):
		kagemusha_decoy.queue_free()
		kagemusha_decoy = null
