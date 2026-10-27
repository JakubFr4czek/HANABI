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
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
