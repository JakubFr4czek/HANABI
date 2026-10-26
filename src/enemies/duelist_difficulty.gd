class_name DuelistDifficulty
extends Resource
## How hard a sword-wielding enemy fights ([DuelistBrain]). Pure data, so a
## profile, a wave director or the later AI phase can swap or tweak it.
##
## Fairness is not tunable here: every attack shows its wind-up for at least
## [constant DuelistBrain.MIN_TELL] seconds while the enemy is in the player's
## view, whatever the scales below say.

@export var level := "normal"
## Multiplies every attack's wind-up (anticipation) time. > 1 = easier to read.
@export var windup_scale := 1.0
## Multiplies recover time after an attack (the player's punish window).
@export var recover_scale := 1.0
## Seconds between attack sequences (random in range).
@export var attack_cooldown := Vector2(1.6, 2.8)
## Chance to chain one more attack after a strike, and the longest chain.
@export var combo_chance := 0.35
@export var max_combo := 2
## Chance that a wind-up is a feint that switches into a different attack.
@export var feint_chance := 0.15
## Chance to read an incoming player swing and lay the guard across it.
@export var block_chance := 0.7
## Chance to step back out of reach of a swing instead (rolled after the block).
@export var evade_chance := 0.2
## Chance to answer a successful block with an immediate counter-attack. A
## block raised early enough to deflect the swing (a parry) doubles it.
@export var riposte_chance := 0.55
## Perception lag (s): the enemy acts on where the player's blade was this long
## ago, extrapolated. Lower = sharper reads of fast or curving swings.
@export var reaction_time := 0.18
## Chance to read a cut the player is loading (sword lifted, or drawn back to
## a side) and move the guard to cover that line before the cut starts.
@export var anticipation := 0.8
## How fast the sword arm may move (1 = ~400°/s of joint motion).
@export var arm_speed := 1.0
## Swing power (0..1, how much arm is behind it) that beats this guard aside
## instead of being parried. Higher = sturdier guard.
@export var guard_strength := 0.6
## Chance to hold a finished wind-up a moment longer before striking, so the
## rhythm cannot be timed by counting.
@export var hesitate_chance := 0.25
## Multiplies the damage of each attack.
@export var damage_scale := 1.0
## Walking speed (m/s) when closing in or backing off.
@export var move_speed := 1.0
## 0..1: tendency to press forward rather than circle and wait.
@export var aggression := 0.5
## Multiplies the damage a hit must do to interrupt a wind-up (poise).
@export var interrupt_scale := 1.0
## Seconds staggered after the player parries an attack.
@export var stagger_time := 1.3


static func preset(name: String) -> DuelistDifficulty:
	var d := DuelistDifficulty.new()
	d.level = name
	match name:
		"easy":
			d.windup_scale = 1.45
			d.recover_scale = 1.4
			d.attack_cooldown = Vector2(2.4, 3.8)
			d.combo_chance = 0.1
			d.max_combo = 1
			d.feint_chance = 0.0
			d.block_chance = 0.35
			d.evade_chance = 0.1
			d.riposte_chance = 0.15
			d.hesitate_chance = 0.1
			d.arm_speed = 0.7
			d.guard_strength = 0.45
			d.anticipation = 0.35
			d.interrupt_scale = 0.8
			d.reaction_time = 0.32
			d.damage_scale = 0.6
			d.move_speed = 0.8
			d.aggression = 0.3
			d.stagger_time = 1.7
		"hard":
			d.windup_scale = 0.75
			d.recover_scale = 0.75
			d.attack_cooldown = Vector2(0.9, 1.7)
			d.combo_chance = 0.6
			d.max_combo = 3
			d.feint_chance = 0.3
			d.block_chance = 0.88
			d.evade_chance = 0.08
			d.riposte_chance = 0.75
			d.hesitate_chance = 0.35
			d.arm_speed = 1.25
			d.guard_strength = 0.75
			d.anticipation = 1.0
			d.interrupt_scale = 1.6
			d.reaction_time = 0.14
			d.damage_scale = 1.4
			d.move_speed = 1.3
			d.aggression = 0.75
			d.stagger_time = 1.0
	return d
