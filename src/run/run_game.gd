class_name RunGame
extends "res://src/core/test_room.gd"
## Survival run loop on the Dojo of the Storm shrine platform (docs/GDD.md §3, §6, NIGHT_PLAN.md §1):
## - Endless yōkai waves emerging from the fog across the water
## - Hitodama soul drops that drift into the player and grant XP
## - Rising XP curve; on level-up time slows and 3 floating Ofuda appear in front
##   of the player — slicing one with the katana selects the upgrade
## - Diegetic HUD on the katana tsuba (XP ring) and wrist (glowing HP charm, XP,
##   time, score, level) with no floating 2D screen-space UI
## - Death ends the run, saves local high score, and presents an in-world
##   memorial stele + a Restart Ofuda that starts a new run when sliced.

enum RunState { INTRO, PLAYING, LEVEL_UP, GAME_OVER }

signal level_up_started(level: int, choices: Array[Dictionary])
signal upgrade_chosen(upgrade: Dictionary, level: int)
signal run_ended(summary: Dictionary)
signal run_started

const PLAYER_BOUNDARY_LAYER := 64  # bit 7: blocks player body, lets yōkai walk onto platform

@export var high_score_path := "user://high_score.cfg"
@export var base_magnet_radius := 3.8
@export var orbs_per_kill := 4
@export var xp_per_orb := 6
@export var skip_run_intro := false

var state := RunState.INTRO
var run_time := 0.0
var xp := 0
var level := 1
var xp_to_next := 24
var kills := 0
var score := 0
var high_score := 0
var new_record := false
var soul_magnet_radius := 3.8
var upgrade_stacks := {}  # upgrade_id -> int

var wave_director: WaveDirector
var diegetic_hud: DiegeticHud
var element_system: ElementSystem
var forest_world: ForestWorld
const RUN_COMBAT_FOG := preload("res://src/run/run_combat_fog.gd")

var combat_fog: Node
var run_intro: RunIntro
var active_ofuda: Array[OfudaTalisman] = []
var restart_ofuda: OfudaTalisman = null

var _souls_root: Node3D
var _ofuda_root: Node3D
var _end_screen_root: Node3D
var _pending_level_ups := 0
var _base_max_force := 260.0
var _base_max_torque := 40.0
var _base_follow_freq := 9.0
var _base_angular_freq := 9.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	super._ready()
	QuestPerfOverlay.attach_if_needed(self)
	GameEvents.log_event("session_start", {"scene": "run", "xr": is_xr_available() and not OS.get_cmdline_user_args().has("--desktop")})

	if katana:
		_base_max_force = katana.max_force
		_base_max_torque = katana.max_torque
		_base_follow_freq = katana.follow_frequency
		_base_angular_freq = katana.angular_frequency

	_prepare_run_arena()
	_setup_run_nodes()
	load_high_score()
	start_run()


func _prepare_run_arena() -> void:
	# Hide/disable the training arena's dummy and debug panels.
	if dummy:
		dummy.set_physics_process(false)
		dummy.set_process(false)
		dummy.visible = false
		for body in dummy.find_children("*", "CollisionObject3D", true, false):
			(body as CollisionObject3D).collision_layer = 0
			(body as CollisionObject3D).collision_mask = 0
		dummy.position = Vector3(0, -50, 0)
	for node_name in ["HitDebugPanel", "HelpLabel", "CreditsLabel"]:
		var n := get_node_or_null(node_name) as Node3D
		if n:
			n.visible = false
			n.set_process(false)

	# Keep the player inside the 5.2 m platform circle, while allowing yōkai to
	# wade in across the water onto the platform without hitting the boundary.
	var boundary := get_node_or_null("Room/Boundary") as StaticBody3D
	if boundary:
		boundary.collision_layer = PLAYER_BOUNDARY_LAYER
		boundary.collision_mask = 0
	if player is CharacterBody3D:
		(player as CharacterBody3D).collision_mask |= PLAYER_BOUNDARY_LAYER
	elif player:
		for pb in player.find_children("*", "CharacterBody3D", true, false):
			(pb as CharacterBody3D).collision_mask |= PLAYER_BOUNDARY_LAYER

	# Wide floor collider under the surrounding water so yōkai can walk from the
	# fog rings (8-12 m out) onto the stone platform.
	var room_node := get_node_or_null("Room")
	if room_node and room_node.get_node_or_null("WaterFloor") == null:
		var wf := StaticBody3D.new()
		wf.name = "WaterFloor"
		wf.position = Vector3(0, -0.5, 0)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(90.0, 1.0, 90.0)
		cs.shape = box
		wf.add_child(cs)
		room_node.add_child(wf)

	# Configure player health for survival runs (death ends the run).
	var health := _player_health()
	if health:
		health.auto_revive = false
		if not health.died.is_connected(_on_player_died):
			health.died.connect(_on_player_died)

	_configure_run_forest()
	_configure_run_navigation()


func _configure_run_navigation() -> void:
	if get_node_or_null("RunNavigation") != null:
		return
	var region := NavigationRegion3D.new()
	region.name = "RunNavigation"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.35
	nav_mesh.agent_height = 1.75
	nav_mesh.cell_size = 0.35
	nav_mesh.cell_height = 0.25
	region.navigation_mesh = nav_mesh
	add_child(region)
	var floor_body := StaticBody3D.new()
	floor_body.name = "NavBakeFloor"
	floor_body.position.y = -0.34
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(88.0, 0.5, 88.0)
	cs.shape = box
	floor_body.add_child(cs)
	region.add_child(floor_body)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, src, floor_body)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, src)
	region.navigation_mesh = nav_mesh


func _configure_run_forest() -> void:
	var arena := get_node_or_null("Arena")
	if arena:
		var water := arena.get_node_or_null("WaterMirror") as MeshInstance3D
		if water:
			water.visible = false
		var rocks := arena.get_node_or_null("Rocks") as Node3D
		if rocks:
			rocks.visible = false
		var torii_group := arena.get_node_or_null("ToriiGates") as Node3D
		if torii_group:
			for child in torii_group.get_children():
				child.visible = child.name == "GiantTorii"
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	var arena_lm := get_node_or_null("Arena/LightmapGI") as LightmapGI
	if we and we.environment:
		# Beyond the giant torii (~10.5 m) the world must read as endless fog (GDD §9).
		we.environment.fog_enabled = true
		we.environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		we.environment.fog_depth_begin = 2.2
		we.environment.fog_depth_end = 9.6
		we.environment.fog_density = 1.42
		we.environment.fog_height = 0.15
		we.environment.fog_height_density = 0.68
		we.environment.fog_sky_affect = 0.0
	if combat_fog == null:
		combat_fog = RUN_COMBAT_FOG.new()
		combat_fog.name = "RunCombatFog"
		add_child(combat_fog)
	if we:
		combat_fog.bind_environment(we)
	if forest_world == null:
		forest_world = ForestWorld.new()
		forest_world.name = "ForestWorld"
		add_child(forest_world)
		move_child(forest_world, 0)
	forest_world.setup(player, arena_lm)
	if get_node_or_null("RunForestAmbience") == null:
		var forest_amb := RunForestAmbience.new()
		forest_amb.name = "RunForestAmbience"
		add_child(forest_amb)


func _setup_run_nodes() -> void:
	_souls_root = Node3D.new()
	_souls_root.name = "Souls"
	add_child(_souls_root)

	_ofuda_root = Node3D.new()
	_ofuda_root.name = "OfudaChoices"
	add_child(_ofuda_root)

	_end_screen_root = Node3D.new()
	_end_screen_root.name = "EndScreen"
	add_child(_end_screen_root)

	wave_director = WaveDirector.new()
	wave_director.name = "WaveDirector"
	wave_director.enemy_died.connect(_on_enemy_died)
	wave_director.oni_defeated.connect(_on_oni_defeated)
	add_child(wave_director)

	diegetic_hud = DiegeticHud.new()
	diegetic_hud.name = "DiegeticHud"
	add_child(diegetic_hud)
	diegetic_hud.setup(player, katana)
	if not GameEvents.parry.is_connected(_on_parry_diegetic):
		GameEvents.parry.connect(_on_parry_diegetic)

	element_system = ElementSystem.new()
	element_system.name = "ElementSystem"
	add_child(element_system)
	element_system.setup(self, katana)
	GameEvents.hit_landed.connect(_on_game_hit)
	if player is XRPlayer:
		var xr := player as XRPlayer
		xr.run_element_mode = true
		xr.element_ability_requested.connect(_on_element_ability_requested)

	run_intro = RunIntro.new()
	run_intro.name = "RunIntro"
	var seal_mesh := get_node_or_null("Arena/SpawnSeal") as MeshInstance3D
	var seal_mat := seal_mesh.material_override as ShaderMaterial if seal_mesh else null
	run_intro.setup(player, katana, spawn.global_position, spawn.global_rotation.y, seal_mat, lightning)
	run_intro.finished.connect(_on_run_intro_finished)
	add_child(run_intro)


func start_run() -> void:
	TimeController.clear()
	if VfxPool:
		VfxPool.ensure_run_budget(40)
	_clear_souls()
	_clear_ofuda()
	_clear_end_screen()
	wave_director.clear_enemies()
	wave_director.stop_director()

	state = RunState.INTRO
	run_time = 0.0
	xp = 0
	level = 1
	xp_to_next = xp_for_level(1)
	kills = 0
	score = 0
	new_record = false
	_pending_level_ups = 0
	upgrade_stacks.clear()
	soul_magnet_radius = base_magnet_radius
	element_system.reset()
	if forest_world:
		forest_world.reset()
	set_seal_progress([], 0)

	var health := _player_health()
	if health:
		health.max_hp = 100.0
		health.regen_per_sec = 0.0
		health.heal_full()

	if katana:
		katana.damage_multiplier = 1.0
		katana.max_force = _base_max_force
		katana.max_torque = _base_max_torque
		katana.follow_frequency = _base_follow_freq
		katana.angular_frequency = _base_angular_freq
		katana.set_element(Elements.NONE)

	if skip_run_intro:
		_begin_play_after_intro()
	else:
		run_intro.start()
	_refresh_hud()


func _begin_play_after_intro() -> void:
	state = RunState.PLAYING
	if player is DesktopPlayer:
		var dp := player as DesktopPlayer
		dp.teleport(spawn.global_position, spawn.global_rotation.y)
		if katana and not katana.is_held():
			dp.take_weapon(katana)
	elif player is XRPlayer:
		var xr := player as XRPlayer
		xr.global_transform = spawn.global_transform
		if xr.right_holder and katana and not katana.is_held():
			xr.right_holder.grab(katana)
			katana.snap_to_hand()
	wave_director.start_director()
	GameEvents.log_event("run_started", {"high_score": high_score})
	run_started.emit()
	_refresh_hud()


func _on_run_intro_finished() -> void:
	_begin_play_after_intro()


## Rising XP requirement for advancing from [param current_level] to the next.
static func xp_for_level(current_level: int) -> int:
	return int(round(24.0 * pow(1.35, float(maxi(current_level - 1, 0)))))


func _physics_process(delta: float) -> void:
	var p_pos := _player_center()
	if state == RunState.PLAYING:
		run_time += delta
		wave_director.step_director(delta, p_pos)
		for enemy in wave_director.alive_enemies():
			enemy.apply_distance_lod(p_pos.distance_to(enemy.root_part().global_position))
		score = compute_score()
		if combat_fog:
			combat_fog.step(p_pos, wave_director.alive_enemies(), true)
	elif combat_fog:
		combat_fog.step(p_pos, [], false)

	# Step soul orbs even during level-up slow-mo (using simulation delta).
	if _souls_root == null:
		return
	for child in _souls_root.get_children():
		if child is SoulOrb:
			(child as SoulOrb).step_orb(delta, p_pos, soul_magnet_radius)

	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state == RunState.INTRO and run_intro and run_intro.is_active():
		if (event is InputEventKey and event.pressed and not event.echo
				and event.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]):
			run_intro.skip()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			run_intro.skip()
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.physical_keycode
	if state == RunState.LEVEL_UP:
		if key in [KEY_1, KEY_2, KEY_3]:
			var idx: int = key - KEY_1
			slice_ofuda_choice(idx)
			get_viewport().set_input_as_handled()
			return
	if key == KEY_R:
		if state == RunState.GAME_OVER and restart_ofuda and is_instance_valid(restart_ofuda):
			restart_ofuda.slice(restart_ofuda.global_position, Vector3.RIGHT)
		else:
			start_run()
		get_viewport().set_input_as_handled()
	elif key == KEY_B and state == RunState.PLAYING:
		element_system.try_shadow_blink()
		get_viewport().set_input_as_handled()


# --- Kills, Souls & XP ---------------------------------------------------------

func _on_oni_defeated(oni: RunOniBoss, hit: Dictionary) -> void:
	if state == RunState.GAME_OVER:
		return
	kills += 3
	score = compute_score()
	var origin: Vector3 = hit.get("point", oni.global_position + Vector3(0, 1.2, 0))
	var orbs := SoulOrb.spawn_cluster(_souls_root, origin, 8, xp_per_orb + 2, Elements.STORM)
	for orb in orbs:
		orb.collected.connect(_on_soul_collected)
	GameEvents.log_event("oni_boss_kill", {"kills": kills, "element": hit.get("element", Elements.NONE)})


func _on_enemy_died(yokai: Yokai, _hit: Dictionary) -> void:
	if state == RunState.GAME_OVER:
		return
	kills += 1
	element_system.on_enemy_died(yokai)
	score = compute_score()
	var origin: Vector3 = (yokai.parts["chest"] as RagdollPart).global_position if yokai.parts.has("chest") else yokai.global_position + Vector3(0, 1.0, 0)
	var elem: String = yokai.last_kill_element if yokai.last_kill_element != "physical" else Elements.NONE
	var orbs := SoulOrb.spawn_cluster(_souls_root, origin, orbs_per_kill, xp_per_orb, elem)
	for orb in orbs:
		orb.collected.connect(_on_soul_collected)


func _on_soul_collected(xp_amount: int, elem: String) -> void:
	GameEvents.log_event("soul_collected", {"xp": xp_amount, "element": elem})
	add_xp(xp_amount)


func add_xp(amount: int) -> void:
	if state == RunState.GAME_OVER or amount <= 0:
		return
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = xp_for_level(level)
		_pending_level_ups += 1
		GameEvents.log_event("level_up", {"level": level, "xp_to_next": xp_to_next})
	if _pending_level_ups > 0 and state == RunState.PLAYING:
		_present_level_up()
	_refresh_hud()


# --- Level-Up & Ofuda Slicing --------------------------------------------------

func _present_level_up() -> void:
	if _pending_level_ups <= 0 or state == RunState.GAME_OVER:
		return
	_pending_level_ups -= 1
	state = RunState.LEVEL_UP
	_clear_ofuda()

	# Slow time to 0.2x while keeping the player's blade at real-time speed.
	TimeController.slow_motion(0.2, 120.0, true)

	var frame := _player_view_frame()
	var chime_pos := frame.origin + (-frame.basis.z) * 0.8
	Sfx.play_at("level_up", chime_pos, -4.0, 5.0)

	var health := _player_health()
	var hp_ratio := (health.hp / maxf(health.max_hp, 1.0)) if health else 1.0
	var choices := UpgradePool.pick_choices(
		3, upgrade_stacks, hp_ratio, _rng,
		element_system.active_elements, UpgradePool.element_slot_count(upgrade_stacks))

	var center := frame.origin + (-frame.basis.z) * 1.16
	center.y = clampf(frame.origin.y - 0.14, 1.15, 1.55)
	var right := frame.basis.x
	var offsets: Array[float] = [-0.38, 0.0, 0.38]

	for i in choices.size():
		var ofuda := OfudaTalisman.new()
		ofuda.setup(choices[i], i)
		var depth_bias := 0.04 if i == 1 else 0.0
		var card_pos: Vector3 = center + right * offsets[i] + (-frame.basis.z) * depth_bias
		_ofuda_root.add_child(ofuda)
		ofuda.global_position = card_pos
		var look_target := Vector3(frame.origin.x, card_pos.y, frame.origin.z)
		if card_pos.distance_to(look_target) > 0.05:
			ofuda.look_at(look_target, Vector3.UP, true)
		ofuda.sliced.connect(_on_ofuda_sliced)
		active_ofuda.append(ofuda)

	level_up_started.emit(level, choices)


## Slice Ofuda [param index] (0 = left, 1 = center, 2 = right).
func slice_ofuda_choice(index: int) -> void:
	if index < 0 or index >= active_ofuda.size():
		return
	var target := active_ofuda[index]
	if is_instance_valid(target) and not target.is_sliced:
		target.slice(target.global_position, Vector3.RIGHT)


func _on_ofuda_sliced(chosen: OfudaTalisman, upgrade: Dictionary) -> void:
	if state != RunState.LEVEL_UP:
		return
	for o in active_ofuda:
		if is_instance_valid(o) and o != chosen:
			o.dismiss()
	active_ofuda.clear()

	_apply_upgrade(upgrade)
	upgrade_chosen.emit(upgrade, level)

	if _pending_level_ups > 0 and (_player_health() == null or _player_health().is_alive()):
		_present_level_up()
	else:
		TimeController.clear()
		if state == RunState.LEVEL_UP:
			state = RunState.PLAYING
	_refresh_hud()


func _apply_upgrade(upgrade: Dictionary) -> void:
	var id := String(upgrade.get("id", ""))
	if id == "":
		return
	var element := UpgradePool.element_for_upgrade(id)
	if element != Elements.NONE:
		if not element_system.active_elements.has(element) and element_system.active_elements.size() >= 2:
			return
		if int(upgrade_stacks.get(id, 0)) <= 0 and UpgradePool.element_slot_count(upgrade_stacks) >= UpgradePool.ELEMENT_SLOT_LIMIT:
			return
	var stacks := int(upgrade_stacks.get(id, 0)) + 1
	upgrade_stacks[id] = stacks
	var health := _player_health()

	match id:
		"damage":
			if katana:
				katana.damage_multiplier = 1.0 + 0.25 * float(stacks)
		"max_hp":
			if health:
				health.add_max_hp(25.0, true)
		"heal":
			if health:
				health.heal(50.0)
		"magnet":
			soul_magnet_radius = base_magnet_radius * (1.0 + 0.45 * float(stacks))
		"arm_strength":
			if katana:
				var mult := 1.0 + 0.25 * float(stacks)
				katana.max_force = _base_max_force * mult
				katana.max_torque = _base_max_torque * mult
				katana.follow_frequency = _base_follow_freq * (1.0 + 0.12 * float(stacks))
				katana.angular_frequency = _base_angular_freq * (1.0 + 0.12 * float(stacks))
		"regen":
			if health:
				health.regen_per_sec = 2.5 * float(stacks)
		_:
			if element != Elements.NONE:
				element_system.apply_upgrade(id, upgrade_stacks)
				_update_element_seal()

	GameEvents.log_event("upgrade_picked", {
		"id": id,
		"stacks": stacks,
		"level": level,
	})


func _on_game_hit(hit: Dictionary) -> void:
	if state == RunState.PLAYING and element_system:
		element_system.on_blade_hit(hit)


func _on_element_ability_requested(direction: Vector3) -> void:
	if state == RunState.PLAYING and element_system:
		element_system.try_shadow_blink(direction)


func _update_element_seal() -> void:
	var evolution_mask := 0
	if element_system.has_evolution(Elements.BLACK_LIGHTNING):
		evolution_mask |= 1
	if element_system.has_evolution(Elements.PHANTOM_PETALS):
		evolution_mask |= 2
	set_seal_progress(element_system.active_elements, evolution_mask)


# --- Death, End Screen & High Score --------------------------------------------

func compute_score() -> int:
	return kills * 100 + int(run_time * 10.0) + maxi(level - 1, 0) * 150


func _on_player_died() -> void:
	if state == RunState.GAME_OVER:
		return
	state = RunState.GAME_OVER
	_pending_level_ups = 0
	TimeController.clear()
	wave_director.stop_director()
	for e in wave_director.alive_enemies():
		e.die({"element": Elements.NONE})
	for o in active_ofuda:
		if is_instance_valid(o):
			o.dismiss()
	active_ofuda.clear()

	score = compute_score()
	new_record = score > high_score
	if new_record:
		high_score = score
		save_high_score()

	var summary := {
		"score": score,
		"high_score": high_score,
		"new_record": new_record,
		"time": snappedf(run_time, 0.1),
		"kills": kills,
		"level": level,
		"wave": wave_director.wave,
		"upgrades": upgrade_stacks.duplicate(),
		"build": element_system.build_summary() if element_system else "Unbound",
	}
	GameEvents.log_event("run_ended", summary)
	_build_end_screen(summary)
	run_ended.emit(summary)
	_refresh_hud()


func _build_end_screen(summary: Dictionary) -> void:
	_clear_end_screen()
	var frame := _player_view_frame()
	var stele_pos := frame.origin + (-frame.basis.z) * 1.44 + frame.basis.x * (-0.24)
	stele_pos.y = 1.36

	var board := Node3D.new()
	board.name = "MemorialStele"
	_end_screen_root.add_child(board)
	board.global_position = stele_pos
	var look_target := Vector3(frame.origin.x, stele_pos.y, frame.origin.z)
	if stele_pos.distance_to(look_target) > 0.05:
		board.look_at(look_target, Vector3.UP, true)

	# Dark obsidian-lacquer shrine tablet catching the ambient moon fill.
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(0.92, 0.62, 0.036)
	slab.mesh = slab_mesh
	slab.material_override = _wet_material(Color(0.11, 0.12, 0.19), 0.72, 0.34, 0.45, -10.0, 1.65)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slab.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	board.add_child(slab)

	# Vermilion lacquer top beam (kasagi) + side pillars framing the memorial tablet.
	var vermilion_mat := _wet_material(Color(0.55, 0.08, 0.08), 0.66, 0.32, 0.45, -10.0, 1.65)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(1.00, 0.042, 0.052)
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 0.32, 0)
	cap.material_override = vermilion_mat
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	board.add_child(cap)

	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.032, 0.64, 0.046)
		post.mesh = post_mesh
		post.position = Vector3(sx * 0.455, 0.0, 0.0)
		post.material_override = vermilion_mat
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		board.add_child(post)

	var sys_font := SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Hiragino Mincho ProN", "YuMincho", "Songti SC", "Noto Serif CJK JP", "Hiragino Sans", "Arial Unicode MS"
	])

	var title_lbl := OfudaTalisman.make_label("散華 · RUN ENDED", sys_font, 46, 0.0013, Color(1.15, 0.30, 0.24), Vector3(0, 0.21, 0.024))
	board.add_child(title_lbl)

	var mins := int(run_time) / 60
	var secs := int(run_time) % 60
	var rec_tag := "  [NEW RECORD]" if summary.get("new_record", false) else ""
	var stats_text := "SCORE  %d%s\nHIGH SCORE  %d\nTIME  %02d:%02d   ·   YŌKAI SLAIN  %d   ·   LEVEL  %d (WAVE %d)" % [
		int(summary.score), rec_tag, int(summary.high_score), mins, secs, int(summary.kills), int(summary.level), int(summary.wave)
	]
	var stats_lbl := OfudaTalisman.make_label(stats_text, sys_font, 30, 0.00105, Color(0.92, 0.94, 1.0), Vector3(0, 0.06, 0.024))
	board.add_child(stats_lbl)

	var build_text := String(summary.get("build", "Unbound"))
	var build_lbl := OfudaTalisman.make_label("BUILD  %s" % build_text, sys_font, 28, 0.0010, Color(0.88, 0.72, 1.0), Vector3(0, -0.06, 0.024))
	board.add_child(build_lbl)

	var upg_parts: Array[String] = []
	for u_id in upgrade_stacks:
		var def := UpgradePool.get_upgrade(String(u_id))
		var name_str := String(def.get("title", String(u_id).to_upper()))
		upg_parts.append("%s ×%d" % [name_str, int(upgrade_stacks[u_id])])
	var upg_line := "UPGRADES: " + (", ".join(upg_parts) if not upg_parts.is_empty() else "None")
	var upg_lbl := OfudaTalisman.make_label(upg_line, sys_font, 22, 0.00088, Color(0.76, 0.82, 0.94), Vector3(0, -0.20, 0.024))
	board.add_child(upg_lbl)

	# Floating Restart Ofuda positioned cleanly to the right of the Memorial Stele:
	# slice it with the katana to begin a fresh run.
	restart_ofuda = OfudaTalisman.new()
	restart_ofuda.setup({
		"id": "restart",
		"header": "御札 · NEW RUN",
		"kanji": "再",
		"title": "RUN AGAIN",
		"subtitle": "Slice to begin anew",
		"color": Color(1.0, 0.34, 0.24),
	}, 0)
	var r_pos := frame.origin + (-frame.basis.z) * 1.14 + frame.basis.x * 0.38
	r_pos.y = 1.24
	_end_screen_root.add_child(restart_ofuda)
	restart_ofuda.global_position = r_pos
	var r_look := Vector3(frame.origin.x, r_pos.y, frame.origin.z)
	if r_pos.distance_to(r_look) > 0.05:
		restart_ofuda.look_at(r_look, Vector3.UP, true)
	restart_ofuda.sliced.connect(_on_restart_ofuda_sliced)


func _on_restart_ofuda_sliced(_ofuda: OfudaTalisman, _upgrade: Dictionary) -> void:
	restart_ofuda = null
	start_run()


func load_high_score() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(high_score_path) == OK:
		high_score = int(cfg.get_value("run", "high_score", 0))
	else:
		high_score = 0
	return high_score


func save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "high_score", high_score)
	cfg.save(high_score_path)


# --- Helpers -------------------------------------------------------------------

func _refresh_hud() -> void:
	if diegetic_hud == null:
		return
	var health := _player_health()
	var hp_val := health.hp if health else 100.0
	var max_hp_val := health.max_hp if health else 100.0
	var elem := element_system.visual_element() if element_system else (katana.element if katana else Elements.NONE)
	diegetic_hud.update_hud(hp_val, max_hp_val, xp, xp_to_next, level, maxi(wave_director.wave, 1), score, kills, run_time, elem)


func _on_parry_diegetic(_info: Dictionary) -> void:
	if diegetic_hud:
		diegetic_hud.on_parry()


func _player_health() -> PlayerHealth:
	if player and player.get("health") is PlayerHealth:
		return player.get("health") as PlayerHealth
	return get_tree().get_first_node_in_group("player_health") as PlayerHealth


func _player_center() -> Vector3:
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	if head:
		return head.global_position - Vector3(0.0, 0.35, 0.0)
	if player:
		return player.global_position + Vector3(0.0, 1.2, 0.0)
	return Vector3(0.0, 1.2, 0.0)


func _player_view_frame() -> Transform3D:
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	if head:
		var fwd := -head.global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 1e-4:
			fwd = Vector3.FORWARD
		else:
			fwd = fwd.normalized()
		return Transform3D(Basis.looking_at(fwd, Vector3.UP), head.global_position)
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.65, 1.8))


func _clear_souls() -> void:
	if _souls_root == null:
		return
	for c in _souls_root.get_children():
		if c is SoulOrb and VfxPool:
			VfxPool.release_soul_orb(c as SoulOrb)
		else:
			c.queue_free()


func _clear_ofuda() -> void:
	active_ofuda.clear()
	if _ofuda_root == null:
		return
	for c in _ofuda_root.get_children():
		c.queue_free()


func _clear_end_screen() -> void:
	restart_ofuda = null
	if _end_screen_root == null:
		return
	for c in _end_screen_root.get_children():
		c.queue_free()
