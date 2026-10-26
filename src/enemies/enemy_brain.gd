class_name EnemyBrain
extends Node
## Swappable decision-making component of an enemy.
##
## The body (ragdoll, locomotion) asks the brain what to do via [method think]
## and executes the answer every frame. Brains decide *what*, bodies decide
## *how*. Later phases plug in an FSM brain for yōkai and an LLM-guided brain
## for the Oni boss without touching the body code (docs/GDD.md, section 7).

## The enemy body this brain controls (set by the body).
var body: Node3D
## Data for this enemy (set by the body).
var profile: EnemyProfile


## Called once by the body after it created / found this brain.
func setup(p_body: Node3D, p_profile: EnemyProfile) -> void:
	body = p_body
	profile = p_profile


## Return an intent Dictionary for this frame. Known keys:
## - "pose": String, name of the target pose (e.g. "guard")
## - "face_position": Vector3, world point to turn toward (optional)
## - "attacking": bool, the weapon is in an attack (can be parried)
## [param context] carries perception: "player_position", "self_position"
## (Vector3, optional) and "can_act" (bool, false while knocked down).
func think(_delta: float, _context: Dictionary) -> Dictionary:
	return {"pose": "guard"}


## Called by the body when it gets hit (after damage was applied).
func on_hit(_hit: Dictionary) -> void:
	pass


## Called by the body when the player parried its attack.
func on_parried(_info: Dictionary) -> void:
	pass
