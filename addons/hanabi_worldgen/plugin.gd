@tool
extends EditorPlugin
## Adds the "World Gen" dock to the editor. The dock talks to the WorldGenPreview
## of the scene being edited (tools/worldgen/worldgen_preview.tscn).

var _dock: WorldGenDock = null


func _enter_tree() -> void:
	_dock = WorldGenDock.new()
	_dock.name = "World Gen"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	scene_changed.connect(_on_scene_changed)
	_on_scene_changed(get_editor_interface().get_edited_scene_root())


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _on_scene_changed(root: Node) -> void:
	if _dock == null:
		return
	_dock.attach(_find_preview(root))


func _find_preview(node: Node) -> WorldGenPreview:
	if node == null:
		return null
	if node is WorldGenPreview:
		return node as WorldGenPreview
	for child in node.get_children():
		var found := _find_preview(child)
		if found != null:
			return found
	return null
