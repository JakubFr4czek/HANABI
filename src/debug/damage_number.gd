class_name DamageNumber
extends Label3D
## Floating damage number that rises and fades out, then frees itself.

const LIFETIME := 0.9

var _age := 0.0
var _velocity := Vector3(0, 0.9, 0)


static func spawn(parent: Node, at: Vector3, value: float, speed: float) -> DamageNumber:
	var n := DamageNumber.new()
	n.text = "%d" % roundi(value)
	n.font_size = 48 + int(clampf(value, 0.0, 80.0))
	n.outline_size = 12
	n.pixel_size = 0.0018
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.fixed_size = false
	# White for light hits, through orange to red for heavy ones.
	n.modulate = Color(1, 1, 1).lerp(Color(1, 0.25, 0.15), clampf(value / 60.0, 0.0, 1.0))
	n.outline_modulate = Color(0, 0, 0, 0.8)
	parent.add_child(n)
	n.global_position = at + Vector3(0, 0.05, 0)
	n._velocity.x = randf_range(-0.15, 0.15)
	n._velocity.y += speed * 0.03
	return n


func _process(delta: float) -> void:
	_age += delta
	global_position += _velocity * delta
	_velocity.y = maxf(_velocity.y - 1.5 * delta, 0.1)
	modulate.a = 1.0 - clampf((_age - LIFETIME * 0.5) / (LIFETIME * 0.5), 0.0, 1.0)
	if _age >= LIFETIME:
		queue_free()
