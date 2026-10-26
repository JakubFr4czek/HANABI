class_name DuelistBrain
extends EnemyBrain
## Sword duelist: a readable state machine for the training dummy (and later
## oni / samurai yōkai). It decides *what* to do; the body executes it.
##
##   IDLE ──(sparring on)──> STALK ──(cooldown over, in range, in view)──> ATTACK
##   STALK: close in, back off, circle at engage distance, never leaving the
##          player's view for long; may raise a BLOCK against a player swing.
##   ATTACK: WINDUP (anticipation pose + tell) -> STRIKE (blade "attacking",
##          the parry window) -> combo into another attack, or RECOVER.
##          A wind-up may be a feint that switches into a different attack.
##   BLOCK -> STALK, or a riposte (new ATTACK) after a successful block.
##   STAGGER (parried, or hit hard during a wind-up) -> RECOVER -> STALK.
##
## Fairness rules (not tunable): a strike only comes after at least MIN_TELL
## seconds of wind-up during which the enemy was inside the player's view
## cone, and a wind-up the player cannot see for LOOK_AWAY_ABORT is dropped.
##
## Tactics read from the profile: attacks, track_player, attack_set,
## engage_distance, min_distance, leash_radius, block_time, interrupt_damage,
## difficulty (preset name, used when the profile has no [DuelistDifficulty]).

enum State { IDLE, STALK, ATTACK, BLOCK, STAGGER, RECOVER }
enum AttackPhase { NONE, WINDUP, STRIKE }

const STATE_NAMES := ["idle", "stalk", "attack", "block", "stagger", "recover"]
## Shortest wind-up the player ever gets to read an attack (seconds).
const MIN_TELL := 0.4
## The enemy counts as seen inside this half-angle of the player's view (deg).
const VIEW_HALF_ANGLE := 40.0
## A wind-up the player has not seen for this long is cancelled (seconds).
const LOOK_AWAY_ABORT := 0.8
## Attack table. Times in seconds at difficulty 1, range in m (pelvis to the
## player's head, horizontal), lunge in m/s during the strike.
const ATTACKS := {
	"vertical": {"windup_pose": "windup", "strike_pose": "strike", "windup": 0.6, "strike": 0.45, "recover": 0.65, "damage": 18.0, "range": 1.75, "lunge": 0.4},
	"horizontal": {"windup_pose": "windup_h", "strike_pose": "strike_h", "windup": 0.55, "strike": 0.4, "recover": 0.55, "damage": 14.0, "range": 1.7, "lunge": 0.3},
	"thrust": {"windup_pose": "windup_t", "strike_pose": "strike_t", "windup": 0.65, "strike": 0.32, "recover": 0.75, "damage": 20.0, "range": 2.0, "lunge": 1.2},
}
## Share of the recovery spent in the follow-through pose before the guard.
const RECOVER_FOLLOW_THROUGH := 0.45
## Which attacks may follow which in a combo.
const COMBOS := {
	"vertical": ["horizontal", "thrust"],
	"horizontal": ["vertical"],
	"thrust": ["horizontal"],
}

var state := State.IDLE
var attack_phase := AttackPhase.NONE
var current_attack := ""
var attacks_enabled := false
var difficulty: DuelistDifficulty
## Strikes made in the current attack sequence (combo length so far).
var strikes_in_sequence := 0
## Wind-up time of the last strike, and how long the player could see it.
var last_windup_time := 0.0
var last_visible_tell := 0.0

var _timer := 0.0
var _windup_needed := 0.0
var _visible_time := 0.0
var _hidden_time := 0.0
var _feint_at := -1.0
var _feinted := false
var _strike_blocked := false
var _recover_needed := 0.6
var _stagger_needed := 1.3
var _cooldown := 1.0
var _circle_dir := 1.0
var _circle_timer := 0.0
var _retreat_time := 0.0
var _block_pose := "block_high"
var _block_react := -1.0
var _block_tip := Vector3.ZERO
var _block_landed := false
var _swing_watch_cooldown := 0.0
var _forced_attack := ""
var _rng := RandomNumberGenerator.new()


func setup(p_body: Node3D, p_profile: EnemyProfile) -> void:
	super.setup(p_body, p_profile)
	var t: Dictionary = p_profile.tactics if p_profile else {}
	attacks_enabled = t.get("attacks", false)
	if difficulty == null:
		if p_profile and p_profile.difficulty:
			difficulty = p_profile.difficulty.duplicate()
		else:
			difficulty = DuelistDifficulty.preset(String(t.get("difficulty", "normal")))
	_rng.randomize()


## Back to a calm guard (room reset).
func reset() -> void:
	_forced_attack = ""
	_block_react = -1.0
	_retreat_time = 0.0
	_cooldown = 1.0
	current_attack = ""
	strikes_in_sequence = 0
	_enter(State.IDLE)


func set_seed(value: int) -> void:
	_rng.seed = value


## Start [param attack] as soon as the rules allow (tests, scripted moments).
func force_attack(attack: String) -> void:
	_forced_attack = attack
	_cooldown = 0.0


func think(delta: float, ctx: Dictionary) -> Dictionary:
	var t: Dictionary = profile.tactics if profile else {}
	_timer += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_swing_watch_cooldown -= delta
	var intent := {"pose": "guard", "attacking": false, "move": Vector3.ZERO, "tell": 0.0}

	var has_player := ctx.has("player_position") and ctx.has("self_position")
	var to_player := Vector3.ZERO
	var dist := INF
	if has_player:
		to_player = ctx.player_position - ctx.self_position
		to_player.y = 0.0
		dist = to_player.length()
	var fwd := to_player / maxf(dist, 0.001) if has_player else Vector3.FORWARD
	if has_player and t.get("track_player", true) and state != State.STAGGER:
		intent["face_position"] = ctx.player_position

	if not ctx.get("can_act", true):
		if state in [State.ATTACK, State.BLOCK]:
			_enter(State.STALK)
		return intent

	var engaged: bool = attacks_enabled and has_player and ctx.get("player_alive", true)
	if not engaged and state != State.STAGGER and state != State.IDLE:
		_enter(State.IDLE)
	elif engaged and state == State.IDLE:
		_enter(State.STALK)

	match state:
		State.IDLE:
			intent.move = _toward_home(ctx)
		State.STALK:
			_stalk(delta, ctx, t, dist, fwd, intent)
			_watch_player_blades(delta, ctx)
		State.ATTACK:
			_attack(delta, ctx, dist, fwd, intent)
		State.BLOCK:
			intent.pose = _block_pose
			if _timer >= float(t.get("block_time", 0.7)):
				_enter(State.STALK)
		State.STAGGER:
			intent.pose = "staggered"
			if _timer < 0.4:
				intent.move = -fwd * 0.5
			if _timer >= _stagger_needed:
				_recover_needed = 0.5
				_enter(State.RECOVER)
		State.RECOVER:
			# Follow through first, then ease back into the guard.
			if _timer < _recover_needed * RECOVER_FOLLOW_THROUGH:
				intent.pose = "recover"
			if _retreat_time > 0.0:
				_retreat_time -= delta
				intent.move = -fwd * difficulty.move_speed * 0.8
			if _timer >= _recover_needed:
				_enter(State.STALK)
	intent.move = _keep_in_leash(intent.move, ctx, t)
	return intent


func on_parried(_info: Dictionary) -> void:
	_stagger_needed = difficulty.stagger_time
	_enter(State.STAGGER)


## The player blocked our strike without a parry: the blade bounces off.
func on_strike_blocked(_info: Dictionary) -> void:
	if state == State.ATTACK and attack_phase == AttackPhase.STRIKE and not _strike_blocked:
		_strike_blocked = true
		GameEvents.log_event("enemy_attack_blocked", {"enemy": _name(), "attack": current_attack})
		_enter_recover(ATTACKS[current_attack].recover * difficulty.recover_scale * 1.2)


## Our raised guard met the player's blade.
func on_block_contact(_info: Dictionary) -> void:
	if state != State.BLOCK or _block_landed:
		return
	_block_landed = true
	var riposte := _rng.randf() < difficulty.riposte_chance
	GameEvents.log_event("enemy_block", {"enemy": _name(), "pose": _block_pose, "landed": true, "riposte": riposte})
	if riposte:
		var attack := _pick_attack(INF)
		if attack != "":
			_start_attack(attack, 0.6)


func on_hit(hit: Dictionary) -> void:
	var t: Dictionary = profile.tactics if profile else {}
	var dmg := float(hit.get("damage", 0.0))
	if state == State.ATTACK and attack_phase == AttackPhase.WINDUP and dmg >= float(t.get("interrupt_damage", 25.0)):
		GameEvents.log_event("enemy_interrupted", {"enemy": _name(), "attack": current_attack, "damage": dmg})
		_stagger_needed = difficulty.stagger_time * 0.6
		_enter(State.STAGGER)
	elif state == State.STALK and dmg > 0.0 and _rng.randf() < 0.5:
		_retreat_time = 0.6


func state_name() -> String:
	return STATE_NAMES[state]


# --- States -------------------------------------------------------------------

func _stalk(delta: float, ctx: Dictionary, t: Dictionary, dist: float, fwd: Vector3, intent: Dictionary) -> void:
	var engage := float(t.get("engage_distance", 1.55))
	var min_d := float(t.get("min_distance", 0.95))
	var speed := difficulty.move_speed
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	if _retreat_time > 0.0:
		_retreat_time -= delta
		intent.move = -fwd * speed
	elif dist > engage + 0.25:
		intent.move = fwd * speed
	elif dist < min_d:
		intent.move = -fwd * speed * 0.9
	else:
		_circle_timer -= delta
		if _circle_timer <= 0.0 or ctx.get("move_blocked", false):
			_circle_timer = _rng.randf_range(1.2, 2.6)
			_circle_dir = -_circle_dir if (ctx.get("move_blocked", false) or _rng.randf() < 0.5) else _circle_dir
		# Drift back toward the middle of the player's view instead of flanking.
		if absf(_view_angle(ctx)) > VIEW_HALF_ANGLE * 0.6:
			_circle_dir = _side_toward_view(ctx, side)
		intent.move = side * _circle_dir * speed * 0.5 + fwd * clampf((dist - engage) * 1.5, -0.5, 0.5)

	if _cooldown > 0.0:
		return
	var attack := _forced_attack if _forced_attack != "" else _pick_attack(dist)
	if attack != "" and dist <= float(ATTACKS[attack].range) + 0.4 and _in_view(ctx):
		_forced_attack = ""
		_start_attack(attack, 1.0)


func _attack(delta: float, ctx: Dictionary, dist: float, fwd: Vector3, intent: Dictionary) -> void:
	var a: Dictionary = ATTACKS[current_attack]
	match attack_phase:
		AttackPhase.WINDUP:
			intent.pose = a.windup_pose
			intent.tell = clampf(_timer / _windup_needed, 0.0, 1.0)
			if _in_view(ctx):
				_visible_time += delta
				_hidden_time = 0.0
			else:
				_hidden_time += delta
				_visible_time = 0.0
			if _hidden_time > LOOK_AWAY_ABORT:
				GameEvents.log_event("enemy_attack_aborted", {"enemy": _name(), "attack": current_attack, "reason": "out_of_view"})
				_cooldown = 0.6
				_enter(State.STALK)
				return
			if _feint_at >= 0.0 and _timer >= _feint_at:
				var other := _pick_other_attack(current_attack)
				if other != "":
					GameEvents.log_event("enemy_feint", {"enemy": _name(), "from": current_attack, "to": other})
					_feinted = true
					_start_attack(other, 1.0)
					return
				_feint_at = -1.0
			if dist > float(a.range):
				intent.move = fwd * difficulty.move_speed
			if _timer >= _windup_needed and _visible_time >= MIN_TELL:
				last_windup_time = _timer
				last_visible_tell = _visible_time
				attack_phase = AttackPhase.STRIKE
				_timer = 0.0
				_strike_blocked = false
				strikes_in_sequence += 1
				_log_phase("strike")
		AttackPhase.STRIKE:
			intent.pose = a.strike_pose
			intent.attacking = not _strike_blocked
			intent.tell = 1.0
			intent.attack = current_attack
			intent.damage = float(a.damage) * difficulty.damage_scale
			intent.move = fwd * float(a.lunge)
			if _timer >= float(a.strike):
				var nexts: Array = COMBOS.get(current_attack, [])
				if strikes_in_sequence < difficulty.max_combo and not nexts.is_empty() and _rng.randf() < difficulty.combo_chance:
					_start_attack(nexts[_rng.randi() % nexts.size()], 0.7)
				else:
					_enter_recover(float(a.recover) * difficulty.recover_scale)


func _start_attack(attack: String, windup_mult: float) -> void:
	var continuing := state == State.ATTACK
	if not continuing:
		strikes_in_sequence = 0
		_feinted = false
		_enter(State.ATTACK)
	_timer = 0.0
	current_attack = attack
	attack_phase = AttackPhase.WINDUP
	_windup_needed = maxf(float(ATTACKS[attack].windup) * difficulty.windup_scale * windup_mult, MIN_TELL)
	_visible_time = 0.0
	_hidden_time = 0.0
	_feint_at = -1.0
	if not _feinted and strikes_in_sequence == 0 and _rng.randf() < difficulty.feint_chance:
		_feint_at = _windup_needed * 0.55
	_log_phase("windup")


func _enter_recover(seconds: float) -> void:
	_recover_needed = seconds
	_retreat_time = 0.5 if _rng.randf() < 0.35 else 0.0
	_enter(State.RECOVER)


func _enter(new_state: State) -> void:
	var previous := state
	state = new_state
	_timer = 0.0
	if new_state != State.ATTACK:
		attack_phase = AttackPhase.NONE
	if new_state == State.BLOCK:
		_block_landed = false
	if new_state == State.STALK and previous in [State.RECOVER, State.ATTACK, State.BLOCK]:
		var c := difficulty.attack_cooldown
		_cooldown = _rng.randf_range(c.x, c.y) * lerpf(1.3, 0.7, difficulty.aggression)
	elif new_state == State.STALK and previous == State.IDLE and _forced_attack == "":
		# Size the player up before the first attack.
		_cooldown = difficulty.attack_cooldown.x * lerpf(1.2, 0.6, difficulty.aggression)
	GameEvents.log_event("enemy_state", {"enemy": _name(), "state": STATE_NAMES[new_state]})
	_log_phase(STATE_NAMES[new_state])


# --- Perception helpers ----------------------------------------------------------

func _watch_player_blades(delta: float, ctx: Dictionary) -> void:
	if _block_react >= 0.0:
		_block_react -= delta
		if _block_react < 0.0:
			_block_pose = _choose_block_pose(ctx, _block_tip)
			_enter(State.BLOCK)
			GameEvents.log_event("enemy_block", {"enemy": _name(), "pose": _block_pose, "landed": false})
		return
	if _swing_watch_cooldown > 0.0 or not ctx.has("chest_position"):
		return
	for blade: Dictionary in ctx.get("player_blades", []):
		var rel: Vector3 = ctx.chest_position - blade.tip
		var v: Vector3 = blade.velocity
		if rel.length() < 1.6 and v.length() > 3.0 and v.dot(rel.normalized()) > 1.0:
			_swing_watch_cooldown = 0.7
			if _rng.randf() < difficulty.block_chance:
				_block_react = difficulty.reaction_time
				_block_tip = blade.tip
			return


func _choose_block_pose(ctx: Dictionary, tip: Vector3) -> String:
	var chest: Vector3 = ctx.chest_position
	if tip.y > chest.y + 0.3:
		return "block_high"
	var facing: Vector3 = ctx.get("self_forward", Vector3.BACK)
	var left := Vector3(facing.z, 0.0, -facing.x)
	return "block_left" if (tip - chest).dot(left) > 0.0 else "block_right"


## Signed angle (deg) of this enemy away from the player's view direction.
func _view_angle(ctx: Dictionary) -> float:
	if not ctx.has("player_forward") or not ctx.has("player_position"):
		return 0.0
	var pf: Vector3 = ctx.player_forward
	var e: Vector3 = ctx.self_position - ctx.player_position
	pf.y = 0.0
	e.y = 0.0
	if pf.length_squared() < 1e-6 or e.length_squared() < 1e-6:
		return 0.0
	return rad_to_deg(pf.normalized().signed_angle_to(e.normalized(), Vector3.UP))


func _in_view(ctx: Dictionary) -> bool:
	return absf(_view_angle(ctx)) <= VIEW_HALF_ANGLE


func _side_toward_view(ctx: Dictionary, side: Vector3) -> float:
	var best := _circle_dir
	var best_angle := INF
	for s in [-1.0, 1.0]:
		var probe := ctx.duplicate()
		probe.self_position = ctx.self_position + side * s * 0.3
		var a := absf(_view_angle(probe))
		if a < best_angle:
			best_angle = a
			best = s
	return best


func _pick_attack(dist: float) -> String:
	var t: Dictionary = profile.tactics if profile else {}
	var options: Array = t.get("attack_set", ATTACKS.keys())
	var in_range := options.filter(func(n): return ATTACKS.has(n) and dist <= float(ATTACKS[n].range) + 0.4)
	if in_range.is_empty():
		return ""
	return in_range[_rng.randi() % in_range.size()]


func _pick_other_attack(attack: String) -> String:
	var t: Dictionary = profile.tactics if profile else {}
	var options: Array = t.get("attack_set", ATTACKS.keys()).filter(func(n): return n != attack and ATTACKS.has(n))
	return "" if options.is_empty() else options[_rng.randi() % options.size()]


func _toward_home(ctx: Dictionary) -> Vector3:
	if not ctx.has("home_position"):
		return Vector3.ZERO
	# Measured from the anchor (where the body is told to stand), not the
	# swaying pelvis, so standing still really is still.
	var d: Vector3 = ctx.home_position - ctx.get("anchor_position", ctx.self_position)
	d.y = 0.0
	return Vector3.ZERO if d.length() < 0.03 else d.normalized() * minf(0.6, d.length() * 3.0)


func _keep_in_leash(move: Vector3, ctx: Dictionary, t: Dictionary) -> Vector3:
	if not ctx.has("home_position") or move == Vector3.ZERO:
		return move
	var from_home: Vector3 = ctx.get("anchor_position", ctx.self_position) - ctx.home_position
	from_home.y = 0.0
	var leash := float(t.get("leash_radius", 3.0))
	if from_home.length() > leash and move.dot(from_home) > 0.0:
		var out := from_home.normalized()
		move -= out * move.dot(out)
	return move


func _name() -> String:
	return profile.display_name if profile else ""


func _log_phase(phase: String) -> void:
	GameEvents.log_event("enemy_phase", {"enemy": _name(), "phase": phase, "attack": current_attack, "state": STATE_NAMES[state]})
