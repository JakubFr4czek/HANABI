class_name YokaiBrain
extends EnemyBrain
## Swarm brain for basic yōkai (docs/GDD.md §7, NIGHT_PLAN.md §1).
##
## Closes in from the fog across the water, separates from nearby yōkai so a
## pack surrounds the player instead of stacking in one spot, respects VR
## fairness (only winds up inside the player's view or drifts into view first,
## >= 0.45 s telegraphed wind-up with glowing eyes and sound), and lunges with
## a claw swipe.

enum State { APPROACH, WINDUP, SLASH, RECOVER, STAGGER }

const ATTACKS := ["left", "right", "double"]
const WINDUP_POSES := {"left": "windup_l", "right": "windup_r", "double": "windup_double"}
const SLASH_POSES := {"left": "slash_l", "right": "slash_r", "double": "slash_double"}

@export var move_speed := 2.05
@export var attack_range := 1.42
@export var stop_distance := 1.08
@export var windup_time := 0.50
@export var slash_time := 0.24
@export var recover_time := 0.55
@export var stagger_time := 0.48
@export var attack_cooldown := 0.85
@export var base_damage := 12.0
@export var attacks_enabled := true

var state := State.APPROACH
var current_attack := "right"
var _timer := 0.0
var _cooldown := 0.35
var _look_away_time := 0.0
var _strafe_sign := 1.0
var _attack_idx := 0
var _rng := RandomNumberGenerator.new()


func setup(p_body: Node3D, p_profile: EnemyProfile) -> void:
	super.setup(p_body, p_profile)
	_rng.seed = randi()
	_strafe_sign = -1.0 if _rng.randf() < 0.5 else 1.0
	_cooldown = _rng.randf_range(0.15, 0.55)


func reset() -> void:
	state = State.APPROACH
	_timer = 0.0
	_cooldown = 0.35
	_look_away_time = 0.0


func force_attack(kind: String = "right") -> void:
	current_attack = kind if ATTACKS.has(kind) else "right"
	_enter(State.WINDUP)


func stagger(duration: float = -1.0) -> void:
	if duration > 0.0:
		stagger_time = duration
	_enter(State.STAGGER)


func on_hit(hit: Dictionary) -> void:
	var dmg := float(hit.get("damage", 0.0))
	var power := float(hit.get("power", 0.5))
	if dmg >= 14.0 or power >= 0.35:
		_enter(State.STAGGER)


func think(delta: float, ctx: Dictionary) -> Dictionary:
	_timer += delta
	_cooldown = maxf(_cooldown - delta, 0.0)

	if not bool(ctx.get("can_act", true)):
		state = State.APPROACH
		_timer = 0.0
		return {"pose": "stalk", "move": Vector3.ZERO, "tell": 0.0, "attacking": false}

	var self_pos: Vector3 = ctx.get("self_position", Vector3.ZERO)
	var player_pos: Vector3 = ctx.get("player_position", Vector3(0, 1.6, 0))
	var player_alive: bool = ctx.get("player_alive", true)
	var to_player := player_pos - self_pos
	to_player.y = 0.0
	var dist := to_player.length()
	var dir_to_player := to_player / maxf(dist, 0.001)
	var right := Vector3(-dir_to_player.z, 0.0, dir_to_player.x)

	var in_view := _is_in_player_view(self_pos, player_pos, ctx.get("player_forward", Vector3.FORWARD))

	match state:
		State.STAGGER:
			if _timer >= stagger_time:
				_cooldown = maxf(_cooldown, 0.35)
				_enter(State.APPROACH)
			return {
				"pose": "staggered",
				"face_position": player_pos,
				"move": -dir_to_player * 0.45,
				"plant": true,
				"tell": 0.0,
				"attacking": false,
			}

		State.WINDUP:
			if not player_alive:
				_enter(State.APPROACH)
			elif not in_view:
				_look_away_time += delta
				if _look_away_time >= 0.8:
					_enter(State.APPROACH)
			else:
				_look_away_time = 0.0
			var progress := clampf(_timer / maxf(windup_time, 0.4), 0.0, 1.0)
			if _timer >= maxf(windup_time, 0.4):
				_enter(State.SLASH)
			return {
				"pose": WINDUP_POSES.get(current_attack, "windup_r"),
				"face_position": player_pos,
				"move": dir_to_player * 0.2,
				"plant": true,
				"tell": progress,
				"attacking": false,
			}

		State.SLASH:
			if _timer >= slash_time:
				_cooldown = attack_cooldown * _rng.randf_range(0.85, 1.15)
				_enter(State.RECOVER)
			return {
				"pose": SLASH_POSES.get(current_attack, "slash_r"),
				"face_position": player_pos,
				"move": dir_to_player * (2.6 if dist > 0.85 else 0.3),
				"plant": true,
				"tell": 1.0,
				"attacking": true,
				"attack": current_attack,
				"damage": base_damage * (1.25 if current_attack == "double" else 1.0),
			}

		State.RECOVER:
			if _timer >= recover_time:
				_enter(State.APPROACH)
			return {
				"pose": "recover",
				"face_position": player_pos,
				"move": -dir_to_player * 0.35,
				"plant": false,
				"tell": 0.0,
				"attacking": false,
			}

		_:
			# State.APPROACH
			var sep: Vector3 = ctx.get("separation", Vector3.ZERO)
			var move := Vector3.ZERO
			if not player_alive:
				move = Vector3.ZERO
			elif dist > attack_range:
				move = (dir_to_player + sep * 0.65).normalized() * move_speed
			elif dist < stop_distance * 0.85:
				move = (-dir_to_player * 0.6 + sep * 0.8) * (move_speed * 0.55)
			else:
				# In attack band: drift into player's view if behind them, or circle slightly.
				var drift_dir := _strafe_sign
				if not in_view and ctx.has("player_forward"):
					var pf: Vector3 = ctx.player_forward
					pf.y = 0.0
					var cross_y := pf.normalized().cross(-dir_to_player).y
					drift_dir = -1.0 if cross_y > 0.0 else 1.0
				move = right * (drift_dir * move_speed * 0.45 if not in_view else drift_dir * move_speed * 0.22) + sep * 0.9

			if attacks_enabled and player_alive and dist <= attack_range and _cooldown <= 0.0 and in_view:
				current_attack = ATTACKS[_attack_idx % ATTACKS.size()]
				_attack_idx += 1
				_enter(State.WINDUP)

			var pose := "stalk"
			if move.length() > 0.85:
				pose = "approach"
			elif dist <= attack_range:
				pose = "stalk"
			return {
				"pose": pose,
				"face_position": player_pos,
				"move": move,
				"plant": false,
				"tell": 0.0,
				"attacking": false,
			}


func _enter(new_state: State) -> void:
	state = new_state
	_timer = 0.0
	_look_away_time = 0.0


static func _is_in_player_view(self_pos: Vector3, player_pos: Vector3, player_forward: Vector3) -> bool:
	var f := Vector3(player_forward.x, 0.0, player_forward.z)
	var to_enemy := Vector3(self_pos.x - player_pos.x, 0.0, self_pos.z - player_pos.z)
	if f.length_squared() < 1e-4 or to_enemy.length_squared() < 1e-4:
		return true
	return f.normalized().dot(to_enemy.normalized()) >= cos(deg_to_rad(52.0))
