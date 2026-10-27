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

## Milk fog is solid here. The old 9 m bubble read as a small arena with a
## few trees; opened up as far as the Quest triangle budget allows (the tree
## ring past it is thinned, not cut, so trunks still dissolve into the fog).
const RUN_FOG_END := 10.5
## Night "milk" fog (sRGB): pale moonlit haze that swallows the forest.
const RUN_FOG_COLOR := Color(0.5, 0.53, 0.6)

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
## Linear storm_fog_color the run sets for the sky horizon (see _configure_run_forest).
var horizon_fog_color := Color.BLACK


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

	# The dojo's ring wall would keep the player on the 5.2 m disc; in a run the
	# shrine is only the spawn point and the player walks out into the forest,
	# whose chunks carry their own terrain colliders (ForestWorld).
	var boundary := get_node_or_null("Room/Boundary") as StaticBody3D
	if boundary:
		boundary.collision_layer = 0
		boundary.collision_mask = 0
	# A converging pack must not shove the player around, nor may they climb
	# onto bodies on the ground: in VR both are camera motion the player did
	# not make. Standing yōkai (layer 2) and fallen ones (layer 8) still stop
	# at claw range on their own.
	var bodies: Array = [player] if player is CharacterBody3D else player.find_children("*", "CharacterBody3D", true, false)
	for pb in bodies:
		(pb as CharacterBody3D).collision_mask &= ~(2 | 8)
		(pb as CharacterBody3D).collision_mask |= ForestWorld.TRUNK_LAYER
	# The blades meet trunks, gates, lanterns and boulders too: a swing into
	# a tree stops on the bark instead of passing through it.
	for w in get_tree().get_nodes_in_group("player_weapons"):
		if w is RigidBody3D:
			(w as RigidBody3D).collision_mask |= ForestWorld.TRUNK_LAYER

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
	# The bake source must not stay in the world: it was an invisible 88 m
	# floor under the hills.
	floor_body.queue_free()


## Dojo set pieces the run does not show: it spawns in a forest clearing, with
## no stone disc, seal circle or arena gates (sky, moon and lightning stay).
const DOJO_ONLY_NODES := [
	"Arena/WaterMirror", "Arena/WaterMistLow", "Arena/WaterMistHigh", "Arena/PlatformDisc",
	"Arena/PlatformRim", "Arena/NorthThreshold", "Arena/SpawnSeal", "Arena/ToriiGates",
	"Arena/Rocks", "Room/WeaponRest", "Kanabo", "Arena/SkyDome",
]


func _configure_run_forest() -> void:
	for path in DOJO_ONLY_NODES:
		var n := get_node_or_null(path) as Node3D
		if n == null:
			continue
		n.visible = false
		n.process_mode = Node.PROCESS_MODE_DISABLED
		for body in ([n] if n is CollisionObject3D else []) + n.find_children("*", "CollisionObject3D", true, false):
			(body as CollisionObject3D).collision_layer = 0
			(body as CollisionObject3D).collision_mask = 0
	# The run is katana-only: keep the dojo kanabō out of reach and recall.
	if kanabo:
		kanabo.remove_from_group("player_weapons")
		kanabo.freeze = true
		kanabo.global_position = Vector3(0.0, -60.0, 0.0)
	if player is DesktopPlayer:
		(player as DesktopPlayer).weapons = [katana]
	# The forest terrain is the floor now, not the dojo's square slab.
	var room_floor := get_node_or_null("Room/Floor") as CollisionObject3D
	if room_floor:
		room_floor.collision_layer = 0
		room_floor.collision_mask = 0
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	var arena_lm := get_node_or_null("Arena/LightmapGI") as LightmapGI
	if we and we.environment:
		# Endless-forest illusion (GDD §9): depth fog reaches full strength at
		# RUN_FOG_END, where everything takes the exact sky-horizon color
		# (storm_fog_color), so the forest dissolves before the edge of the
		# loaded chunks wherever the player walks. Exponential + height fog left
		# hills and gates 30 m away as hard dark silhouettes.
		we.environment.fog_enabled = true
		we.environment.fog_mode = Environment.FOG_MODE_DEPTH
		we.environment.fog_light_color = RUN_FOG_COLOR
		we.environment.fog_light_energy = 1.0
		we.environment.fog_depth_begin = 0.4
		we.environment.fog_depth_end = RUN_FOG_END
		we.environment.fog_depth_curve = 1.0
		# Inside milk fog there is no sky: the background is the fog itself,
		# so nothing ever outlines the forest edge.
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = RUN_FOG_COLOR
		if lightning:
			lightning.base_fog_light_color = RUN_FOG_COLOR
		we.environment.fog_density = 1.0
		we.environment.fog_height_density = 0.0
		# The background is fogged too, so it is the fog color by construction.
		we.environment.fog_sky_affect = 1.0
		# Environment colors are sRGB but the sky shader's storm_fog_color is
		# read as linear: the same numbers rendered the fog dark navy and the
		# horizon pale lavender, so fogged hills never dissolved into the sky.
		# Lock the horizon to the color the fog actually renders.
		horizon_fog_color = we.environment.fog_light_color.srgb_to_linear()
		RenderingServer.global_shader_parameter_set("storm_fog_color", horizon_fog_color)
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
	var moon := get_node_or_null("Moon") as DirectionalLight3D
	if moon:
		forest_world.moon_direction = moon.global_basis.z.normalized()
	_configure_run_light(we, moon)
	forest_world.setup(player, arena_lm)
	if get_node_or_null("RunForestAmbience") == null:
		var forest_amb := RunForestAmbience.new()
		forest_amb.name = "RunForestAmbience"
		add_child(forest_amb)
	if get_node_or_null("StormMusic") == null:
		var music := StormMusic.new()
		music.name = "StormMusic"
		add_child(music)
	if get_node_or_null("StormAmbience") == null:
		var storm := StormAmbience.new()
		storm.name = "StormAmbience"
		storm.lightning = get_node_or_null("Arena/StormLightning") as StormLightning
		add_child(storm)
	_setup_run_storm_rain()


## Run-only. The dojo keeps its own moon. Here the light is the fog: no sky
## reflection, no specular moon, ambient the same grey as the air.
func _configure_run_light(we: WorldEnvironment, moon: DirectionalLight3D) -> void:
	if we and we.environment:
		var env := we.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = RUN_FOG_COLOR
		env.ambient_light_energy = 0.55
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.tonemap_exposure = 0.92
		env.glow_intensity = 0.16
		env.glow_hdr_threshold = 1.7
	if moon:
		moon.light_color = Color(0.64, 0.66, 0.68)
		moon.light_energy = 0.5
		moon.light_specular = 0.0


func _setup_run_storm_rain() -> void:
	if get_node_or_null("RunStormRain") != null:
		return
	var rain := StormRain.new()
	rain.name = "RunStormRain"
	rain.rain_amount = 880
	rain.splash_amount = 80
	rain.platform_radius = 5.4
	add_child(rain)
	if katana:
		StormRain.add_blade_drips(katana, katana.blade_tip)
		_set_katana_rain_droplets(katana, 1.0)


func _set_katana_rain_droplets(weapon: Node, amount: float) -> void:
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		var surf := mi as MeshInstance3D
		for si in surf.get_surface_override_material_count():
			var mat := surf.get_surface_override_material(si)
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				if sm.shader and String(sm.shader.resource_path).ends_with("katana_steel.gdshader"):
					sm.set_shader_parameter("droplets", amount)


func _soul_element_for_kill(yokai: Yokai) -> String:
	if yokai.is_elite() and yokai.elite_element != Elements.NONE:
		return yokai.elite_element
	var le := yokai.last_kill_element
	if le != Elements.NONE and le != "physical":
		return le
	if element_system and element_system.visual_element() != Elements.NONE:
		return element_system.visual_element()
	return Elements.NONE


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
	if forest_world:
		wave_director.ground_height = forest_world.height_at
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
		# The dojo maps A/X to "reset the dummy" and B/Y to its attack toggle;
		# in a run the dummy is parked under the floor, so A/X skips the intro
		# and B/Y does nothing.
		if xr.reset_requested.is_connected(reset_room):
			xr.reset_requested.disconnect(reset_room)
		if xr.toggle_attacks_requested.is_connected(toggle_dummy_attacks):
			xr.toggle_attacks_requested.disconnect(toggle_dummy_attacks)
		xr.reset_requested.connect(_on_xr_primary_button)

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
	# The intro places the player itself and hands movement back at
	# touchdown, so they may have walked off before taking the katana: only a
	# run without the intro is put on the spawn here. (Teleporting after the
	# grab yanked a VR player, camera and all, back to the spawn.)
	var place := skip_run_intro
	if player is DesktopPlayer:
		var dp := player as DesktopPlayer
		if place:
			dp.teleport(spawn.global_position, spawn.global_rotation.y)
		if katana and not katana.is_held():
			dp.take_weapon(katana)
	elif player is XRPlayer:
		var xr := player as XRPlayer
		if place:
			xr.set_rig_locked(true)
			xr.global_transform = spawn.global_transform
			xr.set_rig_locked(false)
		if xr.right_holder and katana and not katana.is_held():
			xr.right_holder.grab(katana)
			katana.snap_to_hand()
	wave_director.start_director()
	GameEvents.log_event("run_started", {"high_score": high_score})
	run_started.emit()
	_refresh_hud()


func _on_xr_primary_button() -> void:
	if state == RunState.INTRO and run_intro and run_intro.is_active():
		run_intro.skip()


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
		wave_director.recall_stragglers(p_pos)
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
		# Pooled orbs come back still connected from their last life.
		if not orb.collected.is_connected(_on_soul_collected):
			orb.collected.connect(_on_soul_collected)
	GameEvents.log_event("oni_boss_kill", {"kills": kills, "element": hit.get("element", Elements.NONE)})


func _on_enemy_died(yokai: Yokai, _hit: Dictionary) -> void:
	if state == RunState.GAME_OVER:
		return
	kills += 1
	element_system.on_enemy_died(yokai)
	score = compute_score()
	var origin: Vector3 = (yokai.parts["chest"] as RagdollPart).global_position if yokai.parts.has("chest") else yokai.global_position + Vector3(0, 1.0, 0)
	var elem: String = _soul_element_for_kill(yokai)
	var orbs := SoulOrb.spawn_cluster(_souls_root, origin, orbs_per_kill, xp_per_orb, elem)
	for orb in orbs:
		if not orb.collected.is_connected(_on_soul_collected):
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
	var music := get_node_or_null("StormMusic") as StormMusic
	if music:
		music.duck_for_level_up(2.8, -9.0)

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
		if not element_system.active_elements.has(element) and element_system.active_elements.size() >= 1:
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
	set_seal_progress(element_system.active_elements, 0)


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
	# The boss leaves too: it kept fighting a dead player through the end
	# screen, swinging into the stele and the restart talisman.
	var oni := wave_director.get_active_oni()
	if is_instance_valid(oni) and not oni.is_dead:
		oni._on_permanent_defeat()
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

	# One single-line label per row at a fixed height: Label3D centers a
	# multi-line text vertically, so an extra "NEW RECORD" line used to push
	# the block into the subtitle above and the BUILD line below.
	var mins := int(run_time) / 60
	var secs := int(run_time) % 60
	var rows: Array = [
		["散華", 72, 0.00185, Color(1.12, 0.34, 0.26), 0.235],
		["RUN ENDED", 30, 0.00112, Color(0.78, 0.8, 0.88), 0.165],
		["%d pt" % int(summary.score), 46, 0.00150, Color(0.96, 0.97, 1.0), 0.108],
	]
	if summary.get("new_record", false):
		rows.append(["★ NEW RECORD", 28, 0.00112, Color(1.1, 0.78, 0.42), 0.058])
	rows.append(["%02d:%02d  ·  斬 %d  ·  LV %d  ·  波 %d" % [mins, secs, int(summary.kills), int(summary.level), int(summary.wave)],
		32, 0.00118, Color(0.9, 0.92, 0.98), 0.005])
	rows.append(["BEST  %d" % int(summary.high_score), 30, 0.00112, Color(0.8, 0.84, 0.94), -0.055])
	rows.append(["BUILD  %s" % String(summary.get("build", "Unbound")), 32, 0.00118, Color(0.9, 0.76, 1.0), -0.115])
	for row in rows:
		var lbl := MemorialTypography.stele_label(String(row[0]), int(row[1]), float(row[2]), row[3] as Color, Vector3(0, float(row[4]), 0.024))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		board.add_child(lbl)

	var upg_parts: Array[String] = []
	for u_id in upgrade_stacks:
		var def := UpgradePool.get_upgrade(String(u_id))
		var tag := String(def.get("kanji", ""))
		if tag.is_empty():
			tag = String(def.get("title", String(u_id))).substr(0, 3)
		upg_parts.append("%s×%d" % [tag, int(upgrade_stacks[u_id])])
	var upg_line := _short_upgrade_line(upg_parts)
	var upg_lbl := MemorialTypography.stele_label(upg_line, 28, 0.00108, Color(0.74, 0.8, 0.92), Vector3(0, -0.19, 0.024))
	upg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


func _short_upgrade_line(parts: Array[String]) -> String:
	if parts.is_empty():
		return "拾得  —"
	const MAX_SHOW := 3
	const MAX_CHARS := 36
	var shown := parts.slice(0, MAX_SHOW)
	var line := "拾得  " + " · ".join(shown)
	if parts.size() > MAX_SHOW:
		line += "  …+%d" % (parts.size() - MAX_SHOW)
	if line.length() > MAX_CHARS:
		line = line.substr(0, MAX_CHARS - 1) + "…"
	return line


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


## Lent soul orbs live under _souls_root: hand them back to the pool before
## this scene is freed, or they die with it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_souls()


func _clear_souls() -> void:
	if _souls_root == null:
		return
	for c in _souls_root.get_children():
		if c is SoulOrb and is_instance_valid(VfxPool):
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
