extends Node3D
## N19: a short test of the Oni boss speech bubble and late AI replies. It checks only that:
##  - the bubble is gone a few seconds after the last AI line,
##  - a late AI reply does not show a new line: superseded by a newer request, landing while
##    decisions are on hold, or landing after the boss died (OniBossBrain._on_ai_reply, N18).
## The katana boss stands alone on a floor and uses a fake AI client that keeps every request
## until the test answers it. No network, no run.tscn. Runs in well under a minute (headless).

## A fake AI client: every request waits in [member pending] until the test answers it.
class HeldAiClient extends OniAiClient:
	var pending: Array[Callable] = []

	func request_decision(_state: Dictionary, callback: Callable) -> void:
		pending.append(callback)

	func answer(i: int, tactic: String, speech: String) -> void:
		var cb: Callable = pending[i]
		cb.call({"tactic": tactic, "attack": "sweep", "speech": speech, "source": "ai"})


var failures := 0
var boss: RunOniBoss
var brain: OniBossBrain
var client: HeldAiClient
var hz := 60.0


func _ready() -> void:
	seed(20261104)
	get_tree().create_timer(120.0).timeout.connect(func():
		print("\nWATCHDOG TIMEOUT in oni_bubble_fade_test!")
		get_tree().quit(1)
	)
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	print("--- N19: Oni speech bubble fade + late AI replies ---")
	hz = float(Engine.physics_ticks_per_second)
	_build_world()
	await _ticks(10)
	var bubble := boss.speech_bubble

	# 1. A reply in time: the line shows, then the bubble is gone a few seconds after it.
	brain._ai_timer = 0.0
	await _wait_requests(1)
	client.answer(0, "flank_left", "Linia pierwsza.")
	_check("an AI reply in time shows its line ('%s')" % bubble.get_text(),
		bubble.is_showing() and bubble.get_text() == "Linia pierwsza.")
	brain._ai_timer = 999.0  # decisions on hold: no new lines from here on
	var life := OniSpeechBubble.FADE_IN_TIME + OniSpeechBubble.DEFAULT_DURATION + OniSpeechBubble.FADE_OUT_TIME
	var gone_at := -1.0
	for f in int((life + 0.4) * hz):
		await get_tree().physics_frame
		if f == int(OniSpeechBubble.DEFAULT_DURATION * 0.5 * hz):
			_check("the line is still up half-way through its hold", bubble.is_showing())
		if gone_at < 0.0 and not bubble.is_showing():
			gone_at = float(f + 1) / hz
	_check("the bubble is gone a few seconds after the last line (gone after %.2f s, life %.2f s)" % [gone_at, life],
		not bubble.is_showing() and gone_at > OniSpeechBubble.DEFAULT_DURATION * 0.5 and gone_at <= life + 0.4)

	# 2. A reply that lands while decisions are on hold is dropped: the bubble stays hidden.
	brain._ai_timer = 0.0
	await _wait_requests(2)
	brain._ai_timer = 999.0
	var tactic_before := brain.current_tactic
	client.answer(1, "aggressive", "Spóźniona linia.")
	await _ticks(3)
	_check("a reply landing while decisions are on hold shows no line (showing=%s, '%s')" % [bubble.is_showing(), bubble.get_text()],
		not bubble.is_showing() and bubble.get_text() != "Spóźniona linia.")
	_check("... and changes no tactic (%s)" % brain.current_tactic, brain.current_tactic == tactic_before)
	_check("... and is logged as dropped (decisions_on_hold)", _last_drop() == "decisions_on_hold")

	# 3. Two requests in flight: the newer answer shows, the older one landing late is dropped.
	brain._ai_timer = 0.0
	await _wait_requests(3)
	brain._ai_timer = 0.0
	await _wait_requests(4)
	client.answer(3, "flank_right", "Nowa linia.")
	# The bubble was hidden: the line fades in over FADE_IN_TIME (0.06 s) before is_showing().
	await _ticks(int(ceilf((OniSpeechBubble.FADE_IN_TIME + 0.04) * hz)))
	_check("the newest reply shows its line ('%s')" % bubble.get_text(),
		bubble.is_showing() and bubble.get_text() == "Nowa linia.")
	client.answer(2, "aggressive", "Stara linia.")
	await _ticks(3)
	_check("an older (superseded) reply does not replace it ('%s')" % bubble.get_text(),
		bubble.get_text() == "Nowa linia.")
	_check("... and is logged as dropped (superseded)", _last_drop() == "superseded")
	_check("... and the tactic stays the newest one (%s)" % brain.current_tactic, brain.current_tactic == "flank_right")

	# 4. A reply that lands after the boss died shows no line.
	brain._ai_timer = 0.0
	await _wait_requests(5)
	_check("the poll gap is in the normal range (%.2f s), so only death can drop the reply" % brain._ai_timer,
		brain._ai_timer <= OniBossBrain.AI_MAX_POLL_GAP)
	boss.hp = 0.0
	client.answer(4, "aggressive", "Z zaświatów.")
	_check("a reply landing after the boss died shows no line ('%s')" % bubble.get_text(),
		bubble.get_text() != "Z zaświatów.")
	_check("... and is logged as dropped (boss_dead)", _last_drop() == "boss_dead")


func _build_world() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 3.0)
	add_child(cam)
	cam.current = true
	# A stand-in for the player's head, so the boss has someone to face.
	var head := Node3D.new()
	head.add_to_group("player_head")
	head.position = Vector3(0.0, 1.6, 3.0)
	add_child(head)

	boss = RunOniBoss.new()
	boss.katana_duelist = true
	boss.profile = EnemyCatalog.make_oni_profile(400.0)
	boss.profile.display_name = "Masked Ronin"
	boss.hold_sword = true
	boss.home_position = Vector3.ZERO
	add_child(boss)
	boss.set_difficulty(EnemyCatalog.oni_difficulty())
	boss.set_attacks_enabled(true)
	brain = boss.brain as OniBossBrain
	client = HeldAiClient.new()
	client.name = "HeldAiClient"
	brain.add_child(client)
	brain.ai_client = client
	brain._ai_timer = 999.0


func _wait_requests(n: int) -> void:
	for _i in 30:
		if client.pending.size() >= n:
			return
		await get_tree().physics_frame
	_check("the brain sent request #%d (sent %d)" % [n, client.pending.size()], false)
	# Keep indices valid so the remaining checks fail cleanly instead of crashing.
	while client.pending.size() < n:
		client.pending.append(func(_d: Dictionary) -> void: pass)


func _last_drop() -> String:
	var d := GameEvents.recent(1, "oni_ai_decision_dropped")
	return String(d[0].get("reason", "")) if d.size() > 0 else ""


func _ticks(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s" % label)
		failures += 1
