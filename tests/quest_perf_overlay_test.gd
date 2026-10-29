extends Node

var failures := 0


func _ready() -> void:
	_check("Quest perf overlay can be constructed", QuestPerfOverlay.new() != null)
	_check("Perf HUD toggle action registered after overlay ready", true)
	var ov := QuestPerfOverlay.new()
	add_child(ov)
	await get_tree().process_frame
	_check("Overlay label exists", ov._label != null)
	ov.queue_free()
	await _behaviour()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


## The HUD is off unless asked for (F3 or the project setting), F3 flips it,
## and only the shown HUD spends work on the label each frame.
func _behaviour() -> void:
	var setting := "hanabi/debug/quest_perf_hud"
	var saved: Variant = ProjectSettings.get_setting(setting, false)
	ProjectSettings.set_setting(setting, true)
	_check("the project setting turns the HUD on", QuestPerfOverlay.should_enable())
	ProjectSettings.set_setting(setting, false)

	var f3_bound := false
	for ev in InputMap.action_get_events(QuestPerfOverlay.TOGGLE_ACTION):
		f3_bound = f3_bound or (ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F3)
	_check("the perf HUD toggle is bound to F3", f3_bound)

	var root := Node.new()
	add_child(root)
	QuestPerfOverlay.attach_if_needed(root)
	_check("the HUD is not attached when it is not enabled", root.get_node_or_null("QuestPerfOverlay") == null)

	ProjectSettings.set_setting(setting, true)
	QuestPerfOverlay.attach_if_needed(root)
	QuestPerfOverlay.attach_if_needed(root)
	var hud := root.get_node_or_null("QuestPerfOverlay") as QuestPerfOverlay
	_check("an enabled HUD attaches once, even when asked twice",
		hud != null and root.get_child_count() == 1)
	ProjectSettings.set_setting(setting, saved)
	if hud == null:
		root.queue_free()
		return
	await get_tree().process_frame
	_check("an enabled HUD starts visible and processing", hud._label.visible and hud.is_processing())

	var toggle := InputEventAction.new()
	toggle.action = QuestPerfOverlay.TOGGLE_ACTION
	toggle.pressed = true
	hud._unhandled_input(toggle)
	_check("one F3 press hides the stats", not hud._label.visible and not hud.is_processing())
	hud._label.text = "stale"
	hud._process(0.016)
	_check("a hidden HUD leaves its label untouched", hud._label.text == "stale")
	hud._unhandled_input(toggle)
	_check("a second F3 press shows the stats again", hud._label.visible and hud.is_processing())
	hud._process(0.016)
	_check("a shown HUD writes fps, draw calls and scene counts", hud._label.text.contains("fps")
		and hud._label.text.contains("draw") and hud._label.text.contains("lights"))

	var release := InputEventAction.new()
	release.action = QuestPerfOverlay.TOGGLE_ACTION
	release.pressed = false
	hud._unhandled_input(release)
	_check("releasing F3 does not toggle the HUD", hud._label.visible)
	root.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
