class_name RunBuffs
extends RefCounted
## The three shrine buffs of a run (docs/ELEMENTS_PLAN.md, D12, section 5).
##
## Speed and damage last ElementBalance.BUFF_SECONDS. Taking the same kind again
## refreshes the clock to full; different kinds run side by side and multiply.
## Healing pays a share of max HP at once and a second share, spread over
## BUFF_HEAL_SECONDS, that runs as regeneration. Max HP never grows.
##
## Timers only move while the run is PLAYING: [RunGame] calls [method step] from its
## playing branch, so the menu and the shrine choice freeze them with the world.

enum Kind { SPEED, DAMAGE, HEAL }

var _left: Dictionary = {}  # Kind -> seconds left (speed, damage)
var _heal_left := 0.0
var _heal_per_second := 0.0


## Starts [param kind]. Heal pays its first share at once through [param health]
## (PlayerHealth.heal, so it never goes above max HP). Returns the HP it restored.
func apply(kind: int, health: PlayerHealth) -> float:
	if kind == Kind.HEAL:
		var max_hp := health.max_hp if health else 100.0
		var gained := health.heal(ElementBalance.BUFF_HEAL_NOW * max_hp) if health else 0.0
		_heal_left = ElementBalance.BUFF_HEAL_SECONDS
		_heal_per_second = ElementBalance.BUFF_HEAL_OVER_TIME * max_hp / ElementBalance.BUFF_HEAL_SECONDS
		return gained
	_left[kind] = ElementBalance.BUFF_SECONDS
	return 0.0


## Advances the timers by [param delta] seconds (run time, not real time).
func step(delta: float, health: PlayerHealth) -> void:
	for kind in _left.keys():
		_left[kind] = maxf(float(_left[kind]) - delta, 0.0)
		if float(_left[kind]) <= 0.0:
			_left.erase(kind)
	if _heal_left > 0.0:
		var spent := minf(delta, _heal_left)
		_heal_left -= spent
		if health:
			health.heal(_heal_per_second * spent)


func is_active(kind: int) -> bool:
	return remaining(kind) > 0.0


## Seconds left on [param kind] (heal: the regeneration left).
func remaining(kind: int) -> float:
	if kind == Kind.HEAL:
		return _heal_left
	return float(_left.get(kind, 0.0))


## Walking speed factor from the speed buff (1.0 without it).
func speed_multiplier() -> float:
	return ElementBalance.BUFF_SPEED_MULTIPLIER if is_active(Kind.SPEED) else 1.0


## Outgoing damage factor from the damage buff (1.0 without it).
func damage_multiplier() -> float:
	return ElementBalance.BUFF_DAMAGE_MULTIPLIER if is_active(Kind.DAMAGE) else 1.0


func clear() -> void:
	_left.clear()
	_heal_left = 0.0
	_heal_per_second = 0.0


## HUD line: the active buffs with their seconds ("速 41 s · 攻 12 s · 癒 6 s"), "" when none.
func hud_text() -> String:
	var parts: Array[String] = []
	if is_active(Kind.SPEED):
		parts.append("速 %d s" % ceili(remaining(Kind.SPEED)))
	if is_active(Kind.DAMAGE):
		parts.append("攻 %d s" % ceili(remaining(Kind.DAMAGE)))
	if is_active(Kind.HEAL):
		parts.append("癒 %d s" % ceili(remaining(Kind.HEAL)))
	return " · ".join(parts)
