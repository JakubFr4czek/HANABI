class_name DuelistBrain
extends EnemyBrain
## Sword duelist for the training dummy (and later oni / samurai yōkai). It
## decides *what* to do; the body executes it. Between attacks the sword arm is
## steered continuously through [SwordArmIK] ("guard_line" intent), so the
## blade moves fluidly instead of jumping between poses.
##
##   IDLE ──(sparring on)──> STALK ──(an opening, in reach, in view)──> ATTACK
##   STALK: guard. The point of the sword stays on the player's throat and
##          leans toward their blade; footwork keeps ma-ai (just outside its own
##          reach) smoothly, follows when the player backs off, gives ground
##          when they rush in, and drifts slowly around them.
##   Defence: the player's blades are seen [member DuelistDifficulty.reaction_time]
##          late and extrapolated. A blade heading for the body is a threat: the
##          dummy reads it (block_chance) and lays its blade across the cut's
##          path (BLOCK), or steps out of reach (evade). A block that meets a
##          light swing deflects it (enemy parry) and is answered with a
##          riposte into the opening; a committed full-arm swing (power above
##          guard_strength) beats the guard aside and staggers it.
##   ATTACK: chosen by the opening: after the player's swing missed, when their
##          blade is out of line (raised, low, wide), when they step into reach,
##          or when its patience runs out. WINDUP on planted feet (anticipation
##          pose + tell), sometimes held a moment (hesitation), may feint ->
##          STRIKE with one step in -> combo or RECOVER (follow-through, then a
##          step back to ma-ai).
##   STAGGER (parried, guard broken, hit hard in a wind-up) -> RECOVER -> STALK.
##
## Fairness rules (not tunable): a strike only comes after at least MIN_TELL
## seconds of wind-up during which the enemy was inside the player's view
## cone, and a wind-up the player cannot see for LOOK_AWAY_ABORT is dropped.
##
## Tactics read from the profile: attacks, track_player, attack_set,
## engage_distance (ma-ai), min_distance, leash_radius, block_time,
## interrupt_damage, difficulty (preset name, used when the profile has no
## [DuelistDifficulty]).

enum State { IDLE, STALK, ATTACK, BLOCK, STAGGER, RECOVER }
enum AttackPhase { NONE, WINDUP, STRIKE }

const STATE_NAMES := ["idle", "stalk", "attack", "block", "stagger", "recover"]
## Longest step in (m) the strike may take to cover the gap to the player.
const MAX_STEP := 0.55
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
## How far ahead (s) a blade's path is extrapolated to see if it reaches the body.
const THREAT_HORIZON := 0.3
## A blade passing closer than this (m) to the body's centre line is a threat
## (the body is ~0.2 m deep; a blade brushing past is met too).
const THREAT_RADIUS := 0.42
## Where the guard meets a cut: this far (m) out from the body's centre line.
const INTERCEPT_DISTANCE := 0.4
## Spring frequencies (1/s) of the guard line: calm guard, and a block.
const GUARD_RESPONSE := 9.0
const BLOCK_RESPONSE := 24.0

var attack_table: Dictionary = ATTACKS.duplicate(true)
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
## Why the last attack was started ("whiff", "raised", "wide", "low",
## "entering", "patience", "riposte", "forced").
var last_opening := ""

var _timer := 0.0
var _clock := 0.0
var _tick := 1.0 / 90.0
var _windup_needed := 0.0
var _visible_time := 0.0
var _hidden_time := 0.0
var _feint_at := -1.0
var _feinted := false
var _strike_blocked := false
var _recover_needed := 0.6
var _stagger_needed := 1.3
var _cooldown := 1.0
var _patience := 3.0
var _hesitate := 0.0
var _step_speed := 0.0
var _evade_time := 0.0
var _zanshin_time := 0.0
var _retreat_time := 0.0
var _forced_attack := ""
var _rng := RandomNumberGenerator.new()
# Footwork.
var _circle_dir := 1.0
var _circle_smooth := 0.0
var _circle_timer := 3.0
var _orbit_phase := 0.0
var _prev_dist := -1.0
var _approach_speed := 0.0  # how fast the player closes in (m/s, smoothed)
var _entered_at := -10.0  # when the player last stepped into our reach
# Perception.
var _seen: Array = []  # [{t, blades}] newest last
var _threat := {}
var _threat_seen_at := -10.0
var _swing_decision := ""  # "block", "evade" or "none" for the current swing
var _swing_peak := 0.0  # fastest player blade in the current swing
var _swing_touched := false  # the current swing met our blade or body
var _swing_end := -10.0  # when the last fast swing ended
# Guard line (world): the IK target, filtered by a critically damped spring.
var _line_start := Vector3.INF
var _line_dir := Vector3.FORWARD
var _line_start_vel := Vector3.ZERO
var _line_dir_vel := Vector3.ZERO
# Block.
var _block_pose := "block_high"
var _block_landed := false
var _block_landed_at := 0.0
var _block_line := []  # [start, dir] world, the wanted defence line
var _load_read := -1  # the cut being loaded: -1 none yet, 1 read, 0 missed
var _loading := false  # the player is loading a cut within reach right now


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
	_retreat_time = 0.0
	_evade_time = 0.0
	_cooldown = 1.0
	_seen.clear()
	_threat = {}
	_swing_decision = ""
	_swing_peak = 0.0
	_swing_end = -10.0
	_load_read = -1
	_loading = false
	_entered_at = -10.0
	_approach_speed = 0.0
	_prev_dist = -1.0
	_line_start = Vector3.INF
	current_attack = ""
	strikes_in_sequence = 0
	_enter(State.IDLE)


func set_seed(value: int) -> void:
	_rng.seed = value


## Start [param attack] as soon as the rules allow (tests, scripted moments).
func force_attack(attack: String) -> void:
	_forced_attack = attack
	_cooldown = 0.0
	_hesitate = 0.0
	if state in [State.RECOVER, State.IDLE]:
		_enter(State.STALK)


func think(delta: float, ctx: Dictionary) -> Dictionary:
	var t: Dictionary = profile.tactics if profile else {}
	_timer += delta
	_clock += delta
	_tick = delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	var intent := {"pose": "guard", "attacking": false, "move": Vector3.ZERO, "tell": 0.0, "arm_speed": difficulty.arm_speed}

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

	_perceive(delta, ctx, dist)

	if not ctx.get("can_act", true):
		if state in [State.ATTACK, State.BLOCK]:
			_enter(State.STALK)
		_line_start = Vector3.INF
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
			_patience -= delta
			if not _defend(ctx, dist, fwd, intent):
				_footwork(delta, ctx, t, dist, fwd, intent)
				_set_guard_line(intent, ctx, delta, false)
				_take_initiative(ctx, dist)
		State.ATTACK:
			_attack(delta, ctx, dist, fwd, intent)
		State.BLOCK:
			_block(delta, ctx, t, fwd, intent)
		State.STAGGER:
			intent.pose = "staggered"
			if _timer < 0.4:
				intent.move = -fwd * 0.5
			if _timer >= _stagger_needed:
				_recover_needed = 0.5
				_enter(State.RECOVER)
		State.RECOVER:
			# Follow through first, then ease back into the guard while
			# stepping back out to ma-ai (zanshin).
			var follow := _recover_needed * RECOVER_FOLLOW_THROUGH
			if _timer < follow:
				intent.pose = "recover"
				intent.plant = true
			else:
				_set_guard_line(intent, ctx, delta, false)
				if _zanshin_time > 0.0 and dist < float(t.get("engage_distance", 1.9)):
					_zanshin_time -= delta
					intent.move = -fwd * difficulty.move_speed * 0.8
				# Late in the recovery it can already defend itself.
				_defend(ctx, dist, fwd, intent)
			if _retreat_time > 0.0:
				_retreat_time -= delta
				intent.move = -fwd * difficulty.move_speed * 0.8
			if state == State.RECOVER and _timer >= _recover_needed:
				_enter(State.STALK)
				if dist < float(t.get("engage_distance", 1.9)) - 0.15:
					_retreat_time = maxf(_zanshin_time, 0.3)
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
		_enter_recover(attack_table[current_attack].recover * difficulty.recover_scale * 1.2)


## Our guard met the player's blade. Returns "parry" (raised in time against a
## light swing: deflected, riposte likely), "block" (stopped it), "broken" (a
## committed swing beat the guard aside) or "" (not blocking).
func on_block_contact(info: Dictionary) -> String:
	_swing_touched = true
	if state == State.BLOCK and _block_landed:
		return ""
	if state not in [State.BLOCK, State.STALK, State.RECOVER]:
		return ""
	# Blades merely touching (pressing, crossing in the guard) is not a block:
	# only a real cut that the guard caught.
	if state != State.BLOCK and (float(info.get("speed", 0.0)) < 2.0 or (_swing_peak < 3.0 and _threat.is_empty())):
		return ""
	# Caught by the guard itself (no block raised) counts as a plain block.
	var raised := state == State.BLOCK
	if raised:
		_block_landed = true
		_block_landed_at = _timer
	var power := float(info.get("power", 0.0))
	var result := "block"
	if power >= difficulty.guard_strength:
		result = "broken"
	elif raised and _timer >= 0.06:
		result = "parry"
	var riposte := false
	if result == "broken":
		_stagger_needed = difficulty.stagger_time * 0.45
		_enter(State.STAGGER)
	else:
		riposte = _rng.randf() < difficulty.riposte_chance * (1.0 if result == "parry" else 0.5)
	GameEvents.log_event("enemy_block", {"enemy": _name(), "pose": _block_pose, "landed": true, "parry": result == "parry", "result": result, "power": power, "riposte": riposte})
	if result == "broken":
		GameEvents.log_event("enemy_guard_broken", {"enemy": _name(), "power": power})
	elif not raised:
		# The guard took it: hold the line a moment, then answer.
		_cooldown = minf(_cooldown, 0.2)
	if riposte:
		var attack := _attack_for_opening("riposte", maxf(_prev_dist, 0.0))
		if attack != "":
			last_opening = "riposte"
			_start_attack(attack, 0.6)
	return result


func on_hit(hit: Dictionary) -> void:
	_swing_touched = true
	var t: Dictionary = profile.tactics if profile else {}
	var dmg := float(hit.get("damage", 0.0))
	if state == State.ATTACK and attack_phase == AttackPhase.WINDUP and dmg >= float(t.get("interrupt_damage", 25.0)) * difficulty.interrupt_scale:
		GameEvents.log_event("enemy_interrupted", {"enemy": _name(), "attack": current_attack, "damage": dmg})
		_stagger_needed = difficulty.stagger_time * 0.6
		_enter(State.STAGGER)


func state_name() -> String:
	return STATE_NAMES[state]


## The blade line the guard currently aims for (world [start, dir]), or [].
func guard_line() -> Array:
	return [] if _line_start == Vector3.INF else [_line_start, _line_dir]


# --- Perception -------------------------------------------------------------------

## Remember what the player's blades do; the brain acts on them
## [member DuelistDifficulty.reaction_time] late, extrapolated to now.
func _perceive(delta: float, ctx: Dictionary, dist: float) -> void:
	_seen.append({"t": _clock, "blades": ctx.get("player_blades", [])})
	while _seen.size() > 2 and float(_seen[1].t) <= _clock - difficulty.reaction_time:
		_seen.pop_front()
	# The player stepping in (smoothed closing speed).
	if _prev_dist >= 0.0 and dist < INF:
		_approach_speed = lerpf(_approach_speed, (_prev_dist - dist) / maxf(delta, 1e-4), 1.0 - exp(-8.0 * delta))
	_prev_dist = dist if dist < INF else -1.0
	# Track the player's swings: peak speed, and whether they touched us.
	var fastest := 0.0
	for b: Dictionary in ctx.get("player_blades", []):
		fastest = maxf(fastest, (b.velocity as Vector3).length())
	if fastest > 3.0:
		if _swing_peak <= 0.0:
			_swing_touched = false
		_swing_peak = maxf(_swing_peak, fastest)
	elif _swing_peak > 0.0 and fastest < 1.2:
		if _swing_peak > 4.0:
			_swing_end = _clock
		_swing_peak = 0.0
	_threat = _find_threat(ctx)
	if _threat.is_empty() and not _loading:
		if _clock - _threat_seen_at > 0.3:
			_swing_decision = ""
	else:
		_threat_seen_at = _clock


## The player's blades as the brain sees them: reaction_time old, extrapolated.
func _delayed_blades() -> Array:
	if _seen.is_empty():
		return []
	var snap: Dictionary = _seen[0]
	var lag := _clock - float(snap.t)
	var out := []
	for b: Dictionary in snap.blades:
		var p := b.duplicate()
		p.tip = (b.tip as Vector3) + (b.velocity as Vector3) * lag
		p.start = (b.get("start", b.tip) as Vector3) + (b.get("start_velocity", b.velocity) as Vector3) * lag
		out.append(p)
	return out


## The first moment (within THREAT_HORIZON) a seen blade would cross the body's
## centre line closer than THREAT_RADIUS: {t, point (on their blade), body
## (on our centre line), axis, sweep (velocity there), power}. Empty: no threat.
func _find_threat(ctx: Dictionary) -> Dictionary:
	if not ctx.has("chest_position"):
		return {}
	var bottom: Vector3 = ctx.self_position
	var top: Vector3 = (ctx.chest_position as Vector3) + Vector3.UP * 0.42
	for b: Dictionary in _delayed_blades():
		var v_tip: Vector3 = b.velocity
		var v_start: Vector3 = b.get("start_velocity", v_tip)
		if v_tip.length() < 1.5:
			continue
		for k in 6:
			var dt := THREAT_HORIZON * k / 5.0
			var s: Vector3 = (b.start as Vector3) + v_start * dt
			var e: Vector3 = (b.tip as Vector3) + v_tip * dt
			var pts := Geometry3D.get_closest_points_between_segments(s, e, bottom, top)
			if pts[0].distance_to(pts[1]) > THREAT_RADIUS:
				continue
			var u := clampf(s.distance_to(pts[0]) / maxf(s.distance_to(e), 0.01), 0.0, 1.0)
			var sweep := v_start.lerp(v_tip, u)
			# Only a blade that is coming toward us, not one being pulled back
			# (judged horizontally: a cut from above always comes down at us).
			var away := pts[1] - pts[0]
			away.y = 0.0
			var sweep_h := Vector3(sweep.x, 0.0, sweep.z)
			if sweep_h.dot(away) < -0.5 * away.length() * maxf(sweep_h.length(), 0.001) and away.length() > 0.1:
				continue
			return {"t": dt, "point": pts[0], "body": pts[1], "axis": (e - s).normalized(), "sweep": sweep, "power": float(b.get("commit", 0.0))}
	return {}


# --- Guard and defence ------------------------------------------------------------

## The guard's blade line: the fist in front of the belly, the point on the
## player's throat, leaning toward their blade so it stays in its way. When the
## player loads a cut (sword lifted, or drawn back to one side) within reach,
## the guard already moves to cover that line: reading the wind-up.
func _guard_target(ctx: Dictionary) -> Array:
	var chest: Vector3 = ctx.chest_position
	var facing: Vector3 = ctx.get("self_forward", Vector3.BACK)
	var left := Vector3(facing.z, 0.0, -facing.x)
	# Where the authored guard holds the fist: the arm can reach it comfortably.
	var fist := chest + facing * 0.44 + Vector3.DOWN * 0.17 - left * 0.05
	var aim: Vector3 = (ctx.player_position as Vector3) + Vector3.DOWN * 0.25 if ctx.has("player_position") else chest + facing * 2.0
	var nearest := _nearest_blade(ctx.get("player_blades", []), chest, 2.6)
	if not nearest.is_empty():
		var mid: Vector3 = ((nearest.tip as Vector3) + (nearest.get("start", nearest.tip) as Vector3)) * 0.5
		aim = aim.lerp(mid, 0.45)
		fist += left * clampf((mid - chest).dot(left) * 0.35, -0.12, 0.12)
		fist.y += clampf((mid.y - chest.y) * 0.15, -0.06, 0.08)
	# The point is alive: a slow small circle, never a frozen guard.
	var wobble := (left * sin(_clock * 1.7) + Vector3.UP * sin(_clock * 1.1 + 1.0)) * 0.02
	var dir := (aim + wobble - fist).normalized()
	var line := [fist + dir * 0.1, dir, "guard"]
	var load := _loaded_cut(ctx, nearest)
	# Each loaded cut is read (or not) once, with the anticipation chance.
	var amount: float = 0.0 if load.is_empty() else load.amount
	_loading = amount > 0.3
	if amount < 0.15:
		_load_read = -1
	elif _load_read < 0 and amount > 0.3:
		_decide_swing()
		_load_read = 1 if _swing_decision == "block" and _rng.randf() < difficulty.anticipation else 0
	if _load_read == 1 and amount > 0.0:
		var cover := _cover_line(ctx, load.kind)
		var k: float = smoothstep(0.3, 0.7, amount)
		var d2: Vector3 = (line[1] as Vector3).slerp(cover[1], k)
		line = [(line[0] as Vector3).lerp(cover[0], k), d2.normalized(), "block_" + String(load.kind) if k > 0.4 else "guard"]
	return line


## Is the player loading a cut with [param blade]? {kind: "high" / "left" /
## "right" (from our side of view), amount 0..1}, or {} when not in reach.
func _loaded_cut(ctx: Dictionary, blade: Dictionary) -> Dictionary:
	if blade.is_empty() or not ctx.has("player_position"):
		return {}
	var head: Vector3 = ctx.player_position
	var me: Vector3 = ctx.self_position
	var flat := me - head
	flat.y = 0.0
	if flat.length() > 2.4:
		return {}
	var tip: Vector3 = blade.tip
	var start: Vector3 = blade.get("start", tip)
	# Hands up near eye level and the tip above the head: an overhead cut is coming.
	var high := smoothstep(head.y - 0.15, head.y + 0.35, tip.y) * smoothstep(head.y - 0.3, head.y + 0.05, start.y)
	# Their right is our left: a blade drawn back to their right comes at our left.
	var their_right := Vector3(-flat.z, 0.0, flat.x).normalized()
	var mid := (tip + start) * 0.5
	var lateral := (mid - head).dot(their_right)
	var wide := smoothstep(0.25, 0.6, absf(lateral))
	if high >= wide and high > 0.05:
		return {"kind": "high", "amount": high}
	if wide > 0.05:
		# Drawn back low (at our waist or below): the cut comes in under a
		# raised guard, so cover it with the point down.
		var chest_y: float = (ctx.chest_position as Vector3).y if ctx.has("chest_position") else head.y - 0.35
		var low := "low_" if mid.y < chest_y else ""
		return {"kind": low + ("left" if lateral > 0.0 else "right"), "amount": wide}
	return {}


## Guard lines that cover a cut from above, or from our left / right side
## (the block lines solved with tests/diag/diag_block_ik.tscn, so the arm can
## reach them), relative to the chest: [x left, y up, z forward] and direction.
const COVER_LINES := {
	"high": [Vector3(-0.22, 0.46, 0.36), Vector3(0.8, 0.19, 0.05)],
	"left": [Vector3(0.06, -0.07, 0.44), Vector3(0.5, 0.58, 0.33)],
	"right": [Vector3(-0.27, -0.02, 0.52), Vector3(-0.4, 0.59, 0.44)],
	"low_left": [Vector3(0.0, 0.04, 0.56), Vector3(0.49, -0.66, 0.12)],
	"low_right": [Vector3(-0.29, -0.02, 0.62), Vector3(-0.3, -0.75, 0.19)],
}


func _cover_line(ctx: Dictionary, kind: String) -> Array:
	var chest: Vector3 = ctx.chest_position
	var facing: Vector3 = ctx.get("self_forward", Vector3.BACK)
	var left := Vector3(facing.z, 0.0, -facing.x)
	var c: Array = COVER_LINES[kind]
	var p: Vector3 = c[0]
	var d: Vector3 = c[1]
	return [chest + left * p.x + Vector3.UP * p.y + facing * p.z, (left * d.x + Vector3.UP * d.y + facing * d.z).normalized()]


## Lay the blade across the threat's path, between it and the body.
func _defence_target(ctx: Dictionary, threat: Dictionary) -> Array:
	var body_pt: Vector3 = threat.body
	var out: Vector3 = (threat.point as Vector3) - body_pt
	var facing: Vector3 = ctx.get("self_forward", Vector3.BACK)
	if out.length() < 0.05:
		out = facing
	out = (out.normalized() + facing * 0.6).normalized()
	var q := body_pt + out * INTERCEPT_DISTANCE
	var chest: Vector3 = ctx.chest_position
	q.y = clampf(q.y, chest.y - 0.2, chest.y + 0.75)
	var axis: Vector3 = threat.axis
	var sweep: Vector3 = threat.sweep
	var across := axis.cross(sweep)
	if across.length() < 0.15 * sweep.length():
		# A thrust: deflect it with the blade slanted across the centre.
		across = axis.cross(Vector3.UP) + Vector3.UP * 0.8
	across = (across - out * across.dot(out)).normalized()
	# Of the two ways to hold that line, take the one the fist reaches easily:
	# low, on the sword-hand side, close to the body.
	var left := Vector3(facing.z, 0.0, -facing.x)
	var best := []
	var best_cost := INF
	for sgn in [1.0, -1.0]:
		var d: Vector3 = across * sgn
		var start := q - d * 0.32
		var cost := (start.y - (chest.y - 0.1)) * 1.5 + (start - chest).dot(left) * 1.0 + maxf(0.0, -d.y) * 2.0
		if cost < best_cost:
			best_cost = cost
			best = [start, d, _pose_name_for(ctx, threat)]
	return best


## Steer the guard line toward its target through a critically damped spring.
func _set_guard_line(intent: Dictionary, ctx: Dictionary, delta: float, blocking: bool) -> void:
	var target := _block_line if blocking and not _block_line.is_empty() else _guard_target(ctx)
	var w := BLOCK_RESPONSE if blocking else GUARD_RESPONSE
	if _line_start == Vector3.INF:
		# Start from where the blade really is, so the guard eases in.
		_line_start = ctx.get("sword_start", target[0])
		_line_dir = ctx.get("sword_dir", target[1])
		_line_start_vel = Vector3.ZERO
		_line_dir_vel = Vector3.ZERO
	var acc: Vector3 = ((target[0] as Vector3) - _line_start) * w * w - _line_start_vel * 2.0 * w
	_line_start_vel += acc * delta
	_line_start += _line_start_vel * delta
	var acc_d: Vector3 = ((target[1] as Vector3) - _line_dir) * w * w - _line_dir_vel * 2.0 * w
	_line_dir_vel += acc_d * delta
	_line_dir = (_line_dir + _line_dir_vel * delta).normalized()
	intent["guard_line"] = [_line_start, _line_dir]
	intent["guard_pose"] = target[2] if target.size() > 2 else "guard"


## Decide once per player swing what to do about it: "block", "evade" or
## "none" (misread). Rolled when the cut is first seen loading or coming.
func _decide_swing() -> void:
	if _swing_decision != "":
		return
	var r := _rng.randf()
	if r < difficulty.block_chance:
		_swing_decision = "block"
	elif r < difficulty.block_chance + difficulty.evade_chance:
		_swing_decision = "evade"
	else:
		_swing_decision = "none"


## React to a threat: decide once per swing (block / evade / misread) and act.
## Returns true while defending this tick.
func _defend(ctx: Dictionary, dist: float, fwd: Vector3, intent: Dictionary) -> bool:
	if _evade_time > 0.0:
		_evade_time -= _tick
		intent.move = -fwd * difficulty.move_speed * 1.5
		intent.plant = true
		_set_guard_line(intent, ctx, _tick, false)
		return true
	# A cut being loaded within reach: an evade starts now, before it comes.
	if _threat.is_empty() and not (_loading and _swing_decision == "evade"):
		return false
	_decide_swing()
	match _swing_decision:
		"block":
			if _threat.is_empty():
				return false
			_block_line = _defence_target(ctx, _threat)
			_block_pose = _pose_name_for(ctx, _threat)
			_enter(State.BLOCK)
			GameEvents.log_event("enemy_block", {"enemy": _name(), "pose": _block_pose, "landed": false})
			_set_guard_line(intent, ctx, _tick, true)
			intent.plant = true
			return true
		"evade":
			_swing_decision = "evaded"
			_evade_time = 0.4
			GameEvents.log_event("enemy_evade", {"enemy": _name()})
			intent.move = -fwd * difficulty.move_speed * 1.5
			intent.plant = true
			_set_guard_line(intent, ctx, _tick, false)
			return true
	return false


func _block(delta: float, ctx: Dictionary, t: Dictionary, fwd: Vector3, intent: Dictionary) -> void:
	intent.plant = true
	if not _threat.is_empty() and not _block_landed:
		# Keep the blade on the cut's current line while it comes in.
		_block_line = _defence_target(ctx, _threat)
		_block_pose = _pose_name_for(ctx, _threat)
	if _block_line.is_empty():
		# Raised without a seen threat (scripted): hold the authored pose.
		intent.pose = _block_pose
	else:
		_set_guard_line(intent, ctx, delta, true)
	var quiet := _clock - _threat_seen_at
	if _timer >= float(t.get("block_time", 0.7)) or (_block_landed and _timer >= _block_landed_at + 0.25) \
			or (not _block_line.is_empty() and quiet > 0.2 and _timer > 0.2):
		_block_line = []
		_enter(State.STALK)


## A readable name for where the guard goes (logs, debug).
func _pose_name_for(ctx: Dictionary, threat: Dictionary) -> String:
	var chest: Vector3 = ctx.chest_position
	var p: Vector3 = threat.point
	if p.y > chest.y + 0.45 and (threat.sweep as Vector3).y < 0.5:
		return "block_high"
	var facing: Vector3 = ctx.get("self_forward", Vector3.BACK)
	var lateral := (p - chest).dot(Vector3(facing.z, 0.0, -facing.x))
	if absf(lateral) < 0.15:
		return "block_mid"
	var low := "low_" if p.y < chest.y - 0.1 else ""
	return "block_" + low + ("left" if lateral > 0.0 else "right")


func _nearest_blade(blades: Array, to: Vector3, max_distance: float) -> Dictionary:
	var best := {}
	var best_d := max_distance
	for b: Dictionary in blades:
		var d := (b.tip as Vector3).distance_to(to)
		if d < best_d:
			best_d = d
			best = b
	return best


# --- Footwork ------------------------------------------------------------------------

## Keep ma-ai smoothly: a spring on the distance with a dead band, back off
## from a player rushing in, follow one backing off, and a slow drift around
## them that reverses now and then (always eased, never a sudden switch).
func _footwork(delta: float, ctx: Dictionary, t: Dictionary, dist: float, fwd: Vector3, intent: Dictionary) -> void:
	var ma_ai := float(t.get("engage_distance", 1.9))
	var min_d := float(t.get("min_distance", 1.1))
	var speed := difficulty.move_speed
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	if _retreat_time > 0.0:
		_retreat_time -= delta
		intent.move = -fwd * speed
		return
	var err := dist - ma_ai
	var radial := 0.0
	if dist < min_d:
		radial = -speed
	elif absf(err) > 0.12:
		radial = clampf((err - signf(err) * 0.12) * 1.8, -speed, speed)
	# Rushed: give ground a little more (unless about to meet it with a cut).
	if _approach_speed > 0.6 and err < 0.3:
		radial = minf(radial, -speed * 0.6)
	_circle_timer -= delta
	if _circle_timer <= 0.0 or ctx.get("move_blocked", false):
		_circle_timer = _rng.randf_range(2.5, 5.0)
		if ctx.get("move_blocked", false) or _rng.randf() < 0.5:
			_circle_dir = -_circle_dir
	if absf(_view_angle(ctx)) > VIEW_HALF_ANGLE * 0.6:
		_circle_dir = _side_toward_view(ctx, side)
	_circle_smooth = move_toward(_circle_smooth, _circle_dir, delta * 0.8)
	_orbit_phase += delta
	var lateral := _circle_smooth * speed * 0.3 * (0.65 + 0.35 * sin(_orbit_phase * 0.9))
	intent.move = fwd * radial + side * lateral


# --- Initiative ---------------------------------------------------------------------

## Attack into an opening once the cooldown is over and the player is in reach.
func _take_initiative(ctx: Dictionary, dist: float) -> void:
	if _cooldown > 0.0 or not _in_view(ctx):
		return
	if _forced_attack != "":
		if dist <= float(attack_table[_forced_attack].range) + MAX_STEP:
			last_opening = "forced"
			var a := _forced_attack
			_forced_attack = ""
			_start_attack(a, 1.0)
		return
	var opening := _find_opening(ctx, dist)
	if opening == "":
		return
	var attack := _attack_for_opening(opening, dist)
	if attack == "":
		return
	last_opening = opening
	GameEvents.log_event("enemy_opening", {"enemy": _name(), "opening": opening, "attack": attack, "cooldown": _cooldown, "patience": _patience})
	_start_attack(attack, 0.75 if opening in ["whiff", "entering"] else 1.0)


## What the player leaves open right now ("" = nothing worth attacking).
func _find_opening(ctx: Dictionary, dist: float) -> String:
	if dist > float(attack_table.thrust.range) + MAX_STEP:
		return ""
	# Just swung and missed: still recovering.
	if _clock - _swing_end < 0.5 and not _swing_touched:
		return "whiff"
	# A cut on its way: defend first, answer after it.
	if not _threat.is_empty() or _swing_peak > 0.0:
		return ""
	# Stepped into our reach without a cut ready: meet them as they come in.
	if _approach_speed > 0.5 and dist < float(attack_table.vertical.range) + MAX_STEP:
		_entered_at = _clock
	if _clock - _entered_at < 0.35 and not _loading:
		return "entering"
	var head: Vector3 = ctx.player_position
	var nearest := _nearest_blade(ctx.get("player_blades", []), head, 2.0)
	if nearest.is_empty():
		return "unarmed" if _patience <= 0.0 else ""
	var tip: Vector3 = nearest.tip
	var me: Vector3 = ctx.self_position
	var line := me - head
	line.y = 0.0
	var side := Vector3(line.z, 0.0, -line.x).normalized()
	var lateral := absf((tip - head).dot(side))
	var start: Vector3 = nearest.get("start", tip)
	var axis := (tip - start).normalized()
	# Lifted overhead (jōdan): hands high, blade steep up.
	if tip.y > head.y + 0.2 and start.y > head.y - 0.2 and axis.y > 0.75:
		return "raised"
	if tip.y < head.y - 0.95:
		return "low"
	if lateral > 0.5:
		return "wide"
	return "patience" if _patience <= 0.0 and not _loading else ""


func _attack_for_opening(opening: String, dist: float) -> String:
	var t: Dictionary = profile.tactics if profile else {}
	var allowed: Array = t.get("attack_set", attack_table.keys())
	var prefs: Array
	match opening:
		"raised": prefs = ["thrust", "horizontal"]
		"low": prefs = ["vertical", "thrust"]
		"wide": prefs = ["horizontal", "vertical"]
		"entering": prefs = ["thrust", "vertical"]
		"whiff", "riposte": prefs = ["vertical", "horizontal", "thrust"]
		_: prefs = ["vertical", "horizontal", "thrust"]
	var options := prefs.filter(func(n): return allowed.has(n) and dist <= float(attack_table[n].range) + MAX_STEP)
	if options.is_empty():
		return ""
	# Mostly the best answer, sometimes the second: readable, not scripted.
	return options[0] if options.size() == 1 or _rng.randf() < 0.7 else options[_rng.randi_range(1, options.size() - 1)]


# --- Attacks -------------------------------------------------------------------------

func _attack(delta: float, ctx: Dictionary, dist: float, fwd: Vector3, intent: Dictionary) -> void:
	var a: Dictionary = attack_table[current_attack]
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
			# Attacked early in our wind-up: drop it and defend instead.
			if not _threat.is_empty() and _timer < _windup_needed * 0.5 and strikes_in_sequence == 0:
				if _swing_decision == "" and _rng.randf() < difficulty.block_chance:
					GameEvents.log_event("enemy_attack_aborted", {"enemy": _name(), "attack": current_attack, "reason": "defend"})
					_cooldown = 0.3
					_enter(State.STALK)
					_swing_decision = "block"
					_defend(ctx, dist, fwd, intent)
					return
			if _feint_at >= 0.0 and _timer >= _feint_at:
				var other := _pick_other_attack(current_attack)
				if other != "":
					GameEvents.log_event("enemy_feint", {"enemy": _name(), "from": current_attack, "to": other})
					_feinted = true
					_start_attack(other, 1.0)
					return
				_feint_at = -1.0
			# Feet planted: no walking while winding up. If the player has
			# backed off well out of reach, the attack is quietly dropped.
			intent.plant = true
			if dist > float(a.range) + MAX_STEP + 0.4:
				GameEvents.log_event("enemy_attack_aborted", {"enemy": _name(), "attack": current_attack, "reason": "out_of_reach"})
				_cooldown = 0.4
				_enter(State.STALK)
				return
			if _timer >= _windup_needed + _hesitate and _visible_time >= MIN_TELL:
				last_windup_time = _timer
				last_visible_tell = _visible_time
				attack_phase = AttackPhase.STRIKE
				_timer = 0.0
				_strike_blocked = false
				strikes_in_sequence += 1
				# One decisive step in that covers the gap, in the first part of the cut.
				var step := clampf(dist - (float(a.range) - 0.3), 0.0, MAX_STEP)
				_step_speed = step / (float(a.strike) * 0.55)
				_log_phase("strike")
		AttackPhase.STRIKE:
			intent.pose = a.strike_pose
			intent.attacking = not _strike_blocked
			intent.tell = 1.0
			intent.attack = current_attack
			intent.damage = float(a.damage) * difficulty.damage_scale
			intent.plant = true
			intent.move = fwd * (float(a.lunge) + (_step_speed if _timer < float(a.strike) * 0.55 else 0.0))
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
	# Tempo varies from attack to attack so it cannot be timed by counting.
	_windup_needed = maxf(float(attack_table[attack].windup) * difficulty.windup_scale * windup_mult * _rng.randf_range(0.85, 1.2), MIN_TELL)
	_hesitate = _rng.randf_range(0.15, 0.45) if _rng.randf() < difficulty.hesitate_chance else 0.0
	_visible_time = 0.0
	_hidden_time = 0.0
	_feint_at = -1.0
	if not _feinted and strikes_in_sequence == 0 and _rng.randf() < difficulty.feint_chance:
		_feint_at = _windup_needed * 0.55
	_log_phase("windup")


func _enter_recover(seconds: float) -> void:
	_recover_needed = seconds
	_retreat_time = 0.0
	_zanshin_time = _rng.randf_range(0.5, 0.9)
	_enter(State.RECOVER)


func _enter(new_state: State) -> void:
	var previous := state
	state = new_state
	_timer = 0.0
	if new_state != State.ATTACK:
		attack_phase = AttackPhase.NONE
	if new_state == State.BLOCK:
		_block_landed = false
	else:
		_block_line = []
	if new_state != State.STALK:
		_evade_time = 0.0
	if new_state in [State.STAGGER, State.IDLE, State.ATTACK, State.RECOVER]:
		_line_start = Vector3.INF
	if new_state == State.STALK and previous in [State.RECOVER, State.ATTACK, State.BLOCK]:
		if _forced_attack != "":
			_cooldown = 0.0
		else:
			var c := difficulty.attack_cooldown
			_cooldown = _rng.randf_range(c.x, c.y) * lerpf(1.3, 0.7, difficulty.aggression) * 0.5
			_patience = _rng.randf_range(c.x, c.y) * lerpf(1.3, 0.7, difficulty.aggression)
	elif new_state == State.STALK and previous == State.IDLE and _forced_attack == "":
		# Size the player up before the first attack.
		_cooldown = difficulty.attack_cooldown.x * lerpf(1.2, 0.6, difficulty.aggression)
		_patience = _cooldown + _rng.randf_range(0.5, 1.5)
	GameEvents.log_event("enemy_state", {"enemy": _name(), "state": STATE_NAMES[new_state]})
	_log_phase(STATE_NAMES[new_state])


# --- Helpers -----------------------------------------------------------------------------

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


## Any attack from the profile's set that reaches from [param dist].
func _pick_attack(dist: float) -> String:
	var t: Dictionary = profile.tactics if profile else {}
	var options: Array = t.get("attack_set", attack_table.keys())
	var in_range := options.filter(func(n): return attack_table.has(n) and dist <= float(attack_table[n].range) + MAX_STEP)
	if in_range.is_empty():
		return ""
	return in_range[_rng.randi() % in_range.size()]


func _pick_other_attack(attack: String) -> String:
	var t: Dictionary = profile.tactics if profile else {}
	var options: Array = t.get("attack_set", attack_table.keys()).filter(func(n): return n != attack and attack_table.has(n))
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
