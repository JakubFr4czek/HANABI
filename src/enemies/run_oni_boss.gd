class_name RunOniBoss
extends TrainingDummy
## Periodic Oni boss for survival runs (docs/GDD.md §7, NIGHT_PLAN.md §4).
## Reuses [DuelistBrain] parryable combos; dies for good instead of reviving.

signal boss_defeated(oni: RunOniBoss, hit: Dictionary)

var is_dead := false
var _last_hit := {}


func _ready() -> void:
	add_to_group("oni_boss")
	add_to_group("enemies")
	scale = Vector3(1.26, 1.26, 1.26)
	super._ready()
	_eyes.emission = Color(1.55, 0.22, 0.1)
	_eyes.emission_energy_multiplier = 1.15
	_sash.emission_enabled = true
	_sash.emission = Color(0.55, 0.06, 0.04)
	_sash.emission_energy_multiplier = 0.35
	set_attacks_enabled(true)
	GameEvents.log_event("oni_spawned", {"hp": hp})


func _allow_revive_after_knockout() -> bool:
	return false


func receive_hit(part: RagdollPart, hit: Dictionary) -> Dictionary:
	_last_hit = hit
	return super.receive_hit(part, hit)


func _on_permanent_defeat() -> void:
	if is_dead:
		return
	is_dead = true
	set_attacks_enabled(false)
	if sword:
		sword.attacking = false
	var chest := parts.get("chest") as RagdollPart if parts.has("chest") else null
	var pos := chest.global_position if chest else global_position + Vector3(0, 1.2, 0)
	if is_inside_tree() and get_tree().current_scene:
		SparkBurst.spawn(get_tree().current_scene, pos, Vector3.UP, Color(1.5, 0.28, 0.12), 32, 4.2)
	GameEvents.log_event("oni_defeated", {"hp": 0.0})
	boss_defeated.emit(self, _last_hit)
	call_deferred("queue_free")
