extends Node
## Runtime guard (autoload "RuntimeGuard"): shouts in the console the moment
## something goes wrong while the game runs, with enough context to find it.
##
## Two sources:
## - every engine / script error and warning, caught through a Logger;
## - game invariants checked every other physics tick: torn joints, bodies
##   under the ground or launched, NaN transforms, a lost or locked katana,
##   a stuck time scale, an inconsistent run state, a silent run, growing
##   orphan nodes, frame hitches.
##
## The first occurrence of each kind prints a loud "[GUARD]" error with
## context; repeats are counted and summed up at exit ("GUARD SUMMARY").
## On in debug builds (editor runs, also with a headset over Link) and with
## --guard; off in release exports. --guard-strict makes tests fail on any.

const TICK_EVERY := 2
## Engine messages that are expected noise, not bugs.
const IGNORED_MESSAGES := [
	"OpenXR", "HMD was not detected", "xr/openxr/extensions/hand_tracking",
	"Custom solver bias", "at exit", "still in use", "Pages in use",
	"Leaked instance dependency", "ObjectDB instances", "Check logged errors",
	"Godot will start in normal mode", "[GUARD]",
]

var enabled := false
var strict := false
var violations := {}  # code -> count
var _first_seen := {}  # code -> first message
var _frame := 0
var _since := {}  # condition key -> seconds it has held
var _orphan_samples: Array[int] = []
var _orphan_timer := 0.0
var _boot_time := 0.0
var _logger: GuardLogger
var _pending: Array[String] = []
var _pending_lock := Mutex.new()
## Every violation also lands here (works on the Quest standalone too; the
## previous session is kept as runtime_guard_prev.log).
const LOG_PATH := "user://runtime_guard.log"
var _log: FileAccess


class GuardLogger extends Logger:
	var guard: Node

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := "warning" if error_type == ERROR_TYPE_WARNING else ("script error" if error_type == ERROR_TYPE_SCRIPT else "error")
		var text := rationale if rationale != "" else code
		guard.queue_engine_message("%s: %s (%s:%d %s)" % [kind, text, file.get_file(), line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	enabled = OS.is_debug_build() or args.has("--guard") or args.has("--guard-strict")
	strict = args.has("--guard-strict")
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not enabled:
		set_physics_process(false)
		set_process(false)
		return
	_logger = GuardLogger.new()
	_logger.guard = self
	OS.add_logger(_logger)
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path("user://runtime_guard_prev.log"))
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_write_log("session %s, %s, args %s" % [Time.get_datetime_string_from_system(), OS.get_name(), OS.get_cmdline_user_args()])


func _exit_tree() -> void:
	if not enabled:
		return
	_drain_engine_messages()
	print_summary()
	if _logger:
		OS.remove_logger(_logger)


## Called from any thread by the logger; drained on the main thread.
func queue_engine_message(msg: String) -> void:
	for skip in IGNORED_MESSAGES:
		if msg.contains(skip):
			return
	_pending_lock.lock()
	if _pending.size() < 200:
		_pending.append(msg)
	_pending_lock.unlock()


func violation_count() -> int:
	var n := 0
	for c in violations:
		n += int(violations[c])
	return n


func reset() -> void:
	violations.clear()
	_first_seen.clear()
	_since.clear()


func print_summary() -> void:
	if violations.is_empty():
		print("GUARD SUMMARY: clean")
		_write_log("summary: clean")
		return
	print("GUARD SUMMARY: %d violation(s)" % violation_count())
	_write_log("summary: %d violation(s)" % violation_count())
	var codes := violations.keys()
	codes.sort()
	for c in codes:
		var line := "  %-26s x%-5d first: %s" % [c, violations[c], _first_seen[c]]
		print(line)
		_write_log(line)


func _write_log(line: String) -> void:
	if _log:
		_log.store_line("[%7.2f] %s" % [Time.get_ticks_msec() / 1000.0, line])
		_log.flush()


## Report a broken invariant. First of each [param code] is loud.
func report(code: String, msg: String) -> void:
	var n := int(violations.get(code, 0)) + 1
	violations[code] = n
	if n == 1:
		_first_seen[code] = msg
		push_error("[GUARD] %s: %s" % [code, msg])
		_write_log("%s: %s" % [code, msg])
	elif n == 10 or n == 100 or n == 1000:
		print("[GUARD] %s happened %d times" % [code, n])


## True once [param key] has held for [param seconds] (reset when it stops).
func _held(key: String, cond: bool, seconds: float, delta: float) -> bool:
	if not cond:
		_since.erase(key)
		return false
	var t := float(_since.get(key, 0.0)) + delta
	_since[key] = t
	return t >= seconds


func _process(delta: float) -> void:
	_drain_engine_messages()
	var real := delta / maxf(Engine.time_scale, 0.001)
	_boot_time += real
	# Hitches: a frame over 60 ms once the scene is up (loading is exempt).
	# Wall-clock hitches only mean something in a real window (headless test
	# runs are CPU-bound and step a fixed delta).
	if _boot_time > 4.0 and real > 0.06 and DisplayServer.get_name() != "headless":
		report("frame_hitch", "frame took %.0f ms" % (real * 1000.0))
	_orphan_timer += real
	if _orphan_timer >= 5.0:
		_orphan_timer = 0.0
		_sample_orphans()


func _drain_engine_messages() -> void:
	_pending_lock.lock()
	var msgs := _pending.duplicate()
	_pending.clear()
	_pending_lock.unlock()
	for m in msgs:
		report("engine_" + String(m).get_slice(":", 0).replace(" ", "_"), m)


func _sample_orphans() -> void:
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_orphan_samples.append(orphans)
	if _orphan_samples.size() > 8:
		_orphan_samples.pop_front()
	if _orphan_samples.size() == 8:
		var rising := true
		for i in range(1, 8):
			rising = rising and _orphan_samples[i] > _orphan_samples[i - 1]
		if rising and _orphan_samples[-1] - _orphan_samples[0] > 150:
			report("orphan_leak", "orphan nodes keep growing: %s" % [_orphan_samples])


func _physics_process(delta: float) -> void:
	_frame += 1
	if _frame % TICK_EVERY != 0:
		return
	var dt := delta * TICK_EVERY
	var tree := get_tree()
	var run := tree.get_first_node_in_group("run_game") as RunGame
	_check_time(dt)
	_check_ragdolls(tree, dt)
	_check_weapons(tree, run, dt)
	if run:
		_check_run(run, dt)


func _check_time(dt: float) -> void:
	var real := dt / maxf(Engine.time_scale, 0.001)
	var slowed := Engine.time_scale < 0.99
	if _held("time_stuck", slowed and not TimeController.is_active(), 0.25, real):
		report("time_scale_stuck", "Engine.time_scale %.2f with no time effect active" % Engine.time_scale)
	if _held("hit_stop_long", TimeController.is_active("hit_stop"), 0.6, real):
		report("hit_stop_stuck", "hit-stop active for over 0.6 s")


static func _bad(v: Vector3) -> bool:
	return is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or is_inf(v.x) or is_inf(v.y) or is_inf(v.z)


func _check_ragdolls(tree: SceneTree, dt: float) -> void:
	for n in tree.get_nodes_in_group("enemies"):
		var r := n as ActiveRagdoll
		if r == null or not r.is_inside_tree() or r.parts.is_empty():
			continue
		var id := str(r.get_instance_id())
		var dead: bool = r.get("is_dead") == true
		if not r.visible:
			if not dead and r is Yokai:
				report("ghost_enemy", "%s is alive but invisible" % r.name)
			# Hidden (burst, pooled): this life's timers end here.
			for k in ["gap", "under", "launch", "corpse"]:
				_since.erase(k + id)
			continue
		var pelvis := r.root_part()
		var worst_gap := 0.0
		var worst_part := ""
		for part_name in r.parts:
			var part := r.parts[part_name] as RagdollPart
			if _bad(part.global_position) or _bad(part.linear_velocity):
				report("nan_body", "%s.%s has a NaN/inf transform or velocity" % [r.name, part_name])
				return
			if r is Yokai and (r as Yokai).is_severed(part_name):
				continue
			if part.linear_velocity.length() > r.max_part_speed * 1.6:
				report("part_speed", "%s.%s moving %.1f m/s (cap %.1f)" % [r.name, part_name, part.linear_velocity.length(), r.max_part_speed])
			var def: Dictionary = r._defs.get(part_name, {})
			if def.has("parent") and def.has("joint"):
				var parent := r.parts.get(String(def.parent)) as RagdollPart
				var j: Vector3 = def.joint
				var a := parent.global_transform * ((r._rest[parent.name] as Transform3D).affine_inverse() * j)
				var b := part.global_transform * ((r._rest[part_name] as Transform3D).affine_inverse() * j)
				if a.distance_to(b) > worst_gap:
					worst_gap = a.distance_to(b)
					worst_part = part_name
		if not dead and _held("gap" + id, worst_gap > 0.15, 0.25, dt):
			report("joint_torn", "%s: joint of %s open %.2f m (living, state %d)" % [r.name, worst_part, worst_gap, r.state])
		if r.ground_probe.is_valid():
			var gy := float(r.ground_probe.call(pelvis.global_position.x, pelvis.global_position.z))
			if _held("under" + id, pelvis.global_position.y < gy - 1.5, 0.5, dt):
				report("body_under_ground", "%s pelvis %.2f m below the terrain (dead %s)" % [r.name, gy - pelvis.global_position.y, dead])
			if _held("launch" + id, not dead and pelvis.global_position.y > gy + 4.0, 0.5, dt):
				report("body_launched", "%s pelvis %.1f m above the terrain" % [r.name, pelvis.global_position.y - gy])
		if r is Yokai and _held("corpse" + id, dead, 3.0, dt):
			var y := r as Yokai
			report("corpse_stuck", "%s dead and still on the field after 3 s (dissolve %.2f s, burst %s, physics %s, state %d)" % [
				r.name, y._dissolve_timer, y._petal_burst_done, y.is_physics_processing(), r.state])


func _check_weapons(tree: SceneTree, run: RunGame, dt: float) -> void:
	for n in tree.get_nodes_in_group("player_weapons"):
		var w := n as HeldWeapon
		if w == null or not w.is_inside_tree():
			continue
		var id := str(w.get_instance_id())
		if _bad(w.global_position) or _bad(w.linear_velocity):
			report("nan_weapon", "%s has a NaN/inf transform" % w.name)
			continue
		if w.is_held():
			var holder := w.holders[0] as Node3D
			var gap := w.get_grip_point_global(holder).distance_to(holder.global_position) if holder else 0.0
			if _held("lost" + id, gap > 1.2, 1.0, dt):
				report("weapon_left_hand", "%s held but %.2f m from the hand for 1 s" % [w.name, gap])
		if run and run.state == RunGame.RunState.PLAYING and w == run.katana:
			if _held("locked" + id, w.grab_locked, 0.5, dt):
				report("katana_locked_in_play", "the katana is grab-locked during play")
			if _held("invisible" + id, not w.visible, 0.5, dt):
				report("katana_invisible", "the katana is invisible during play")
		if run and run.forest_world and not w.freeze:
			var gy := run.forest_world.height_at(w.global_position.x, w.global_position.z)
			if _held("wunder" + id, w.global_position.y < gy - 1.0, 0.5, dt):
				report("weapon_under_ground", "%s %.2f m below the terrain (held %s)" % [w.name, gy - w.global_position.y, w.is_held()])


func _check_run(run: RunGame, dt: float) -> void:
	var playing := run.state == RunGame.RunState.PLAYING
	# A director stopped after it ran is a deliberate hold (tests, debug);
	# one that never started while the run plays is the bug.
	if _held("director", playing and not run.wave_director.started_this_run, 1.0, dt):
		report("director_idle", "run is PLAYING but the wave director never started")
	if _held("norestart", run.state == RunGame.RunState.GAME_OVER and not is_instance_valid(run.restart_ema), 5.0, dt):
		report("no_restart", "GAME_OVER for 5 s without a restart ema")
	var health := run._player_health()
	if health:
		if is_nan(health.hp) or health.hp < 0.0 or health.hp > health.max_hp + 0.01:
			report("bad_hp", "player hp %.2f / %.2f" % [health.hp, health.max_hp])
		if _held("deadplay", playing and not health.is_alive(), 1.0, dt):
			report("dead_but_playing", "player is down but the run is still PLAYING")
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	if head and run.forest_world:
		if _bad(head.global_position):
			report("nan_player", "player head has a NaN/inf position")
		else:
			var gy := run.forest_world.height_at(head.global_position.x, head.global_position.z)
			if _held("pfall", head.global_position.y < gy + 0.3, 0.5, dt):
				report("player_under_ground", "player head %.2f m above terrain" % (head.global_position.y - gy))
	var music := run.get_node_or_null("StormMusic") as StormMusic
	if music and _held("music", playing and not music._players.any(func(p): return p.playing), 2.0, dt):
		report("music_silent", "the run is playing but no music player is")
	for y in run.wave_director._enemies:
		if is_instance_valid(y) and not y.is_dead and not y.is_inside_tree():
			report("enemy_off_tree", "%s counted alive but not in the scene" % y.name)
