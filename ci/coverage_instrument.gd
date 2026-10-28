extends SceneTree
## CI only: instruments the project's scripts on disk for Nano Coverage
## (backups in res://.nano_coverage). ci/coverage_report.gd restores them.
##   godot --headless --path . --script res://ci/coverage_instrument.gd


func _init() -> void:
	if not ClassDB.class_exists("DiskInstrumenter"):
		push_error("Nano Coverage GDExtension is not loaded (run --import after copying the addon)")
		quit(2)
		return
	var r: Dictionary = ClassDB.instantiate("DiskInstrumenter").instrument_to_disk({})
	print("INSTRUMENT: ", r)
	quit(1 if str(r.get("status", "")) == "error" else 0)
