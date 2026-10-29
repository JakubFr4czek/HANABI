extends Node
## RuntimeGuard bookkeeping: each broken invariant is counted (the first one is
## kept with its message), the summary says clean or lists the codes, engine
## noise from the ignore list is dropped, and the pending queue is capped.
##   godot --headless --path . --fixed-fps 90 res://tests/runtime_guard_test.tscn -- --desktop

var failures := 0


func _ready() -> void:
	_run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	RuntimeGuard.reset()
	_check("a fresh guard reports no violations", RuntimeGuard.violation_count() == 0)

	RuntimeGuard.report("TEST_CODE", "first problem")
	RuntimeGuard.report("TEST_CODE", "second problem")
	RuntimeGuard.report("OTHER_CODE", "other problem")
	_check("every report is counted", RuntimeGuard.violation_count() == 3)
	_check("the first message of a code is the one kept", RuntimeGuard._first_seen["TEST_CODE"] == "first problem")
	_check("counts are kept per code", RuntimeGuard.violations["TEST_CODE"] == 2 and RuntimeGuard.violations["OTHER_CODE"] == 1)

	RuntimeGuard.reset()
	_check("reset clears every count", RuntimeGuard.violation_count() == 0 and RuntimeGuard._first_seen.is_empty())

	RuntimeGuard._pending.clear()
	RuntimeGuard.queue_engine_message("some real engine warning")
	_check("a real engine message is queued", RuntimeGuard._pending.size() == 1)
	RuntimeGuard.queue_engine_message(String(RuntimeGuard.IGNORED_MESSAGES[0]) + " noise")
	_check("an ignored engine message is dropped", RuntimeGuard._pending.size() == 1)
	RuntimeGuard._pending.clear()
	for i in 260:
		RuntimeGuard.queue_engine_message("warning %d" % i)
	_check("the pending queue never holds more than 200 messages", RuntimeGuard._pending.size() == 200)
	RuntimeGuard._pending.clear()
	RuntimeGuard.reset()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
