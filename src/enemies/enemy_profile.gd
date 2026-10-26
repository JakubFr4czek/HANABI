class_name EnemyProfile
extends Resource
## Data for one enemy type: stats, damage multipliers, resistances and tactics.
## Kept as data (not code) so the later AI phase can read and override it,
## e.g. an "awakened" enemy gaining a resistance (docs/GDD.md, section 8).

@export var display_name := "Enemy"
@export var max_hp := 100.0
## Damage multiplier per hit zone ("head", "torso", "limb").
@export var zone_multipliers := {"head": 1.5, "torso": 1.0, "limb": 0.7}
## Damage multiplier per element ("sakura", "storm", "ink", "shadow", "physical").
## Below 1 = resistant, above 1 = weak. Missing = 1.
@export var resistances := {}
## How much balance one point of damage removes (0..1 scale). Higher = staggers easier.
@export var poise_damage_scale := 0.012
## How much muscle strength one point of damage removes.
@export var muscle_damage_scale := 0.006
## Balance / muscle regained per second while standing.
@export var balance_regen := 0.7
@export var muscle_regen := 0.9
## Seconds lying down before getting up, and how long getting up takes.
@export var knockdown_time := 1.6
@export var getup_time := 1.8
## After being parried: seconds the enemy is open to a counter, and the damage multiplier then.
@export var counter_window := 1.5
@export var counter_multiplier := 1.5
## Free-form tactic parameters read by the enemy's brain.
@export var tactics := {}
## How hard a sword duelist fights (null = the "difficulty" preset named in tactics).
@export var difficulty: DuelistDifficulty


func damage_multiplier(zone: String, element: String = "physical") -> float:
	return float(zone_multipliers.get(zone, 1.0)) * float(resistances.get(element, 1.0))
