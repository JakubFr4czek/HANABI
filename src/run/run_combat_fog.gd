class_name RunCombatFog
extends Node
## Softens run fog within ~8 m of the player when enemies are close (GDD §9,
## point-12 readability). Distant forest still vanishes into fog past the torii.

const CLEAR_RADIUS := 8.0

var _env: Environment
var _base_density := 1.32
var _base_begin := 2.2
var _base_height_density := 0.68
var _last_bubble := 0.0


func bind_environment(world_env: WorldEnvironment) -> void:
	if world_env == null or world_env.environment == null:
		return
	_env = world_env.environment
	_base_density = _env.fog_density
	_base_begin = _env.fog_depth_begin
	_base_height_density = _env.fog_height_density


func base_fog_density() -> float:
	return _base_density


func step(player_pos: Vector3, enemies: Array, active: bool) -> void:
	if _env == null:
		return
	if not active:
		_apply_bubble(0.0)
		return
	var bubble := 0.0
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		var anchor: Vector3 = (e as Node3D).global_position if e is Node3D else Vector3.ZERO
		if e.has_method("root_part"):
			var rp: Variant = e.call("root_part")
			if rp is Node3D:
				anchor = (rp as Node3D).global_position
		var d: float = anchor.distance_to(player_pos)
		if d < CLEAR_RADIUS:
			bubble = maxf(bubble, 1.0 - d / CLEAR_RADIUS)
		if e.is_in_group("oni_boss") and d < CLEAR_RADIUS:
			bubble = maxf(bubble, 0.62)
	_apply_bubble(bubble)


func _apply_bubble(bubble: float) -> void:
	_last_bubble = bubble
	_env.fog_density = lerpf(_base_density, _base_density * 0.66, bubble)
	_env.fog_depth_begin = lerpf(_base_begin, _base_begin + 3.6, bubble)
	_env.fog_height_density = lerpf(_base_height_density, _base_height_density * 0.38, bubble)
