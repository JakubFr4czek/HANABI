extends SceneTree
## CI only: merges the coverage sessions into res://coverage-report/lcov.info
## and always restores the original scripts from the backups.
##   godot --headless --path . --script res://ci/coverage_report.gd


func _init() -> void:
	var code := 0
	if ClassDB.class_exists("CoverageApi"):
		var r: Dictionary = ClassDB.instantiate("CoverageApi").generate_coverage_report({})
		print("REPORT: ", r)
		if not r.has("report_path"):
			code = 1
	else:
		push_error("Nano Coverage CoverageApi missing")
		code = 2
	if ClassDB.class_exists("DiskInstrumenter"):
		var d: Dictionary = ClassDB.instantiate("DiskInstrumenter").restore_from_disk({})
		print("RESTORE: ", d)
	quit(code)
