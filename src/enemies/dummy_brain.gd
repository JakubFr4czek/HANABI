class_name DummyBrain
extends EnemyBrain
## Training dummy brain. Holds its guard and turns to face the player. With
## attacks enabled it repeats a telegraphed overhead cut when the player is in
## range: guard -> windup -> strike -> recover. Its blade is "attacking" only
## during the strike, so blocking it then is a parry.
##
## Tactics read from the profile: track_player, attacks, attack_interval,
## attack_range, windup_time, strike_time, recover_time, parry_stun_time.

enum Phase { GUARD, WINDUP, STRIKE, RECOVER, STUNNED }

var phase := Phase.GUARD
var attacks_enabled := false

var _timer := 0.0


func setup(p_body: Node3D, p_profile: EnemyProfile) -> void:
	super.setup(p_body, p_profile)
	attacks_enabled = p_profile.tactics.get("attacks", false) if p_profile else false


func think(delta: float, context: Dictionary) -> Dictionary:
	var t: Dictionary = profile.tactics if profile else {}
	var intent := {"pose": "guard", "attacking": false}
	if t.get("track_player", true) and context.has("player_position") and phase != Phase.STRIKE:
		intent["face_position"] = context["player_position"]

	_timer += delta
	var in_range := false
	if context.has("player_position") and context.has("self_position"):
		var d: Vector3 = context.player_position - context.self_position
		d.y = 0.0
		in_range = d.length() <= float(t.get("attack_range", 2.4))
	var can_act: bool = context.get("can_act", true)

	match phase:
		Phase.GUARD:
			if attacks_enabled and in_range and can_act and _timer >= float(t.get("attack_interval", 2.2)):
				_enter(Phase.WINDUP)
		Phase.WINDUP:
			intent.pose = "windup"
			if _timer >= float(t.get("windup_time", 0.55)):
				_enter(Phase.STRIKE)
		Phase.STRIKE:
			intent.pose = "strike"
			intent.attacking = true
			if _timer >= float(t.get("strike_time", 0.45)):
				_enter(Phase.RECOVER)
		Phase.RECOVER:
			if _timer >= float(t.get("recover_time", 0.6)):
				_enter(Phase.GUARD)
		Phase.STUNNED:
			intent.pose = "staggered"
			if _timer >= float(t.get("parry_stun_time", 1.2)):
				_enter(Phase.GUARD)
	if not can_act and phase in [Phase.WINDUP, Phase.STRIKE]:
		_enter(Phase.GUARD)
		intent.pose = "guard"
		intent.attacking = false
	return intent


func on_parried(_info: Dictionary) -> void:
	_enter(Phase.STUNNED)


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_timer = 0.0
	var names := ["guard", "windup", "strike", "recover", "stunned"]
	GameEvents.log_event("enemy_phase", {"enemy": profile.display_name if profile else "", "phase": names[new_phase]})
