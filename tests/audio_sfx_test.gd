extends Node

var failures := 0


func _ready() -> void:
	_check("Sfx exposes Kenney run categories", Sfx._streams.has("firework") and Sfx._streams.has("soul_collect"))
	_check("Thunder uses single distant roll (no crack category)", not Sfx.CATEGORIES.has("thunder_crack"))
	_check("Sfx pool is pre-sized for combat", Sfx._pool.size() >= 20)
	Sfx.play_at("soul_collect", Vector3.ZERO, -20.0)
	Sfx.play_at("firework", Vector3(1, 0, 0), -20.0)
	_check("Sfx play_at uses pooled players without new nodes", Sfx.get_child_count() <= 30)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
