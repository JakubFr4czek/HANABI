class_name HitDebugPanel
extends Node3D
## World-space debug panel (readable in VR): last hits with speed and damage,
## the best hit so far, last weapon clash and the dummy's state.
## Also spawns a floating damage number at every hit point.

const MAX_LINES := 8

@export var dummy_path: NodePath

var _label := Label3D.new()
var _lines: Array[String] = []
var _best_speed := 0.0
var _best_damage := 0.0
var _last_clash := "-"
var _parries := 0
var _dummy: TrainingDummy


func _ready() -> void:
	_label.font_size = 36
	_label.outline_size = 8
	_label.pixel_size = 0.0022
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.width = 900
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.modulate = Color(0.85, 0.95, 1.0)
	add_child(_label)
	_dummy = get_node_or_null(dummy_path) as TrainingDummy
	GameEvents.hit_landed.connect(_on_hit)
	GameEvents.weapon_clash.connect(_on_clash)
	GameEvents.parry.connect(func(_p): _parries += 1)
	_refresh()


func _on_hit(hit: Dictionary) -> void:
	_best_speed = maxf(_best_speed, hit.speed)
	_best_damage = maxf(_best_damage, hit.get("damage", 0.0))
	_lines.push_front("%5.1f m/s  arm %3d%%  %4.1f N·s  →  %5.1f dmg   %-6s %-11s (%s)%s" % [hit.speed, roundi(float(hit.get("power", 0.0)) * 100.0), float(hit.get("impulse", 0.0)), hit.get("damage", 0.0), String(hit.get("strike", "")).to_upper(), hit.get("part", "?"), hit.get("zone", "?"), "  COUNTER" if hit.get("counter", false) else ""])
	if _lines.size() > MAX_LINES:
		_lines.pop_back()
	DamageNumber.spawn(get_tree().current_scene, hit.point, hit.get("damage", 0.0), hit.speed)
	_refresh()


func _on_clash(clash: Dictionary) -> void:
	_last_clash = "%.1f m/s at %.0f°, arm %d%%%s" % [clash.speed, clash.angle_deg, roundi(float(clash.get("power", 0.0)) * 100.0), "  PARRY!" if clash.get("parry", false) else ""]
	_refresh()


func _process(_delta: float) -> void:
	# Dummy state changes continuously; refresh a few times per second.
	if Engine.get_process_frames() % 10 == 0:
		_refresh()


func _refresh() -> void:
	var text := "HIT DEBUG\n"
	if _dummy:
		var states := ["STANDING", "KNOCKED DOWN", "GETTING UP"]
		text += "Dummy  HP %d/%d   balance %.2f   muscle %.2f   %s   attacks %s\n" % [
			_dummy.hp, _dummy.profile.max_hp, _dummy.balance, _dummy.muscle, states[_dummy.state], "ON" if _dummy.attacks_enabled() else "off"]
		if _dummy.counter_time_left() > 0.0:
			text += ">> COUNTER WINDOW %.1f s <<\n" % _dummy.counter_time_left()
	text += "Best   %.1f m/s   %.1f dmg\n" % [_best_speed, _best_damage]
	text += "Clash  %s   parries %d\n" % [_last_clash, _parries]
	text += "──────────────────────────────\n"
	text += "\n".join(_lines) if not _lines.is_empty() else "(swing at the dummy)"
	_label.text = text
