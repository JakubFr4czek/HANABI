@tool
extends EditorPlugin
## Adds the "Fale" dock (yōkai waves, docs/SPAWN_TOOL.md) next to the World Gen dock.
## The dock works from the presets in data/waves, so it needs no scene open.

var _dock: WaveDock = null


func _enter_tree() -> void:
	_dock = WaveDock.new()
	_dock.name = "Fale"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
