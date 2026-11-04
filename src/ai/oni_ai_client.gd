class_name OniAiClient
extends Node
## Asynchronous client for Meta Model API (Muse Spark / Llama) driving the Oni Boss.
##
## Docs/GDD.md §8 (Meta AI features), Zadanie D15.
## - Sends combat context asynchronously (HTTPRequest); NEVER blocks physics or frame.
## - Whitelist validation of tactics, attacks, target distance and speech text.
## - Instant graceful fallback to local rule-based combat on timeout, error, or missing key.
## - Supports mock provider for zero-latency, networkless automated testing.

signal decision_received(decision: Dictionary)
## N8: a request left for the API (url only, never the key) – tests count the cadence.
signal request_sent(url: String)

const DEFAULT_META_ENDPOINT := "https://api.meta.ai/v1/chat/completions"
const META_ENDPOINT := DEFAULT_META_ENDPOINT
const DEFAULT_MODEL := "muse-spark-1.3"
## Melee standoff the boss may ask for, in metres from its pelvis to the player.
## The kanabō chop lands 1.73 m forward of the pelvis and reaches the torso between
## 1.43 and 2.03 m (see run_oni_boss.gd); a standoff outside that range whiffs.
const MELEE_STANDOFF_MIN := 1.4
const MELEE_STANDOFF_MAX := 1.9
const TIMEOUT_SECONDS := 3.0
## N8: the boss says one short line; longer replies are cut at a word boundary + "…".
const MAX_SPEECH_CHARS := 60
## N8 (debug/test only): `-- --oni-ai-endpoint=http://127.0.0.1:PORT/v1/chat/completions`
## points the client at a local mock server. Release builds ignore it and any http:// URL.
const ENDPOINT_ARG := "--oni-ai-endpoint="
const VALID_TACTICS: Array[String] = [
	"stalk", "advance", "retreat", "circle_left", "circle_right", "attack", "taunt",
	# F5: the katana duelist boss (masked swordsman) picks among these.
	"aggressive", "defensive", "feint", "flank_left", "flank_right",
]
## F5: tactics of the masked katana swordsman boss (subset of VALID_TACTICS).
const DUELIST_TACTICS: Array[String] = [
	"aggressive", "defensive", "feint", "flank_left", "flank_right", "retreat"
]
const VALID_ATTACKS: Array[String] = [
	"slam", "sweep", "thrust", "combo"
]

const FALLBACK_SPEECH_PL_P1: Array[String] = [
	"Pokaż mi swą stal!",
	"Ten las spłynie twoją krwią.",
	"Nie uciekniesz przed przeznaczeniem.",
	"Słabe to twoje cięcie!",
]
const FALLBACK_SPEECH_PL_P2: Array[String] = [
	"Zatańcz ze śmiercią!",
	"Ciężar mojego żelaza cię zmiażdży!",
	"Dobra obrona... lecz daremna!",
	"Twoja dusza należy do mnie!",
]
const FALLBACK_SPEECH_PL_P3: Array[String] = [
	"GIŃ!",
	"Oni nie znają litości!",
	"Poczuj gniew demonów!",
	"Koniec twojej drogi!",
]

const FALLBACK_SPEECH_EN_P1: Array[String] = [
	"Show me your steel!",
	"The forest will drink your blood.",
	"Destiny cannot be outrun.",
	"A feeble swing!",
]
const FALLBACK_SPEECH_EN_P2: Array[String] = [
	"Dance with death!",
	"Feel the crush of demon iron!",
	"A valiant guard... yet futile!",
	"Your soul is mine!",
]
const FALLBACK_SPEECH_EN_P3: Array[String] = [
	"PERISH!",
	"The Oni knows no mercy!",
	"Feel demonic fury!",
	"Your path ends here!",
]

var _http: HTTPRequest
var _mock_provider: Callable
## Test seam: when set, it receives (url, headers, body) instead of HTTPRequest
## so tests can capture the effective endpoint without touching the network.
var _request_hook: Callable
## URL of the last dispatched request (visible to tests/logs; never the key).
var last_request_url := ""
var _pending_callback: Callable
var _is_busy := false
## Seconds the request in flight has been waiting (counted in game frames, so a stalled
## socket can never hold the fight: past [constant TIMEOUT_SECONDS] the fallback answers).
var _inflight_s := 0.0
var _inflight_state := {}
var _rng := RandomNumberGenerator.new()
## F5: true when the client drives the katana duelist boss (prompt and fallback use
## the swordsman's tactics; the fallback tactic "duel" = the duelist's own logic).
var katana_mode := false


func _ready() -> void:
	_rng.seed = randi()
	_http = HTTPRequest.new()
	_http.name = "AiHttp"
	# The frame-counted deadline in _process answers first; this is only a backstop.
	_http.timeout = TIMEOUT_SECONDS + 2.0
	add_child(_http)
	_http.request_completed.connect(_on_http_request_completed)


func _process(delta: float) -> void:
	if not _is_busy:
		return
	_inflight_s += delta
	if _inflight_s >= TIMEOUT_SECONDS:
		# Timeout: drop the request and answer locally in this very tick.
		if _http != null:
			_http.cancel_request()
		_is_busy = false
		var cb := _pending_callback
		_pending_callback = Callable()
		var fallback := local_fallback_decision(_inflight_state)
		fallback["fallback_reason"] = "timeout"
		if cb.is_valid():
			cb.call(fallback)
		decision_received.emit(fallback)


## The endpoint actually used: Settings, then the debug command-line override; an
## http:// or loopback URL only counts in a debug build (tests, the local mock server).
static func resolve_endpoint(configured: String) -> String:
	var ep := configured.strip_edges()
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with(ENDPOINT_ARG):
				ep = a.substr(ENDPOINT_ARG.length()).strip_edges()
	if ep == "":
		return DEFAULT_META_ENDPOINT
	if not OS.is_debug_build() and not ep.begins_with("https://"):
		return DEFAULT_META_ENDPOINT
	return ep


## N8 telemetry: 2–3 plain facts about how the player fights, from the player's own hits
## in the event log. [param right] = the player's view right vector (flat).
## {"cut_from": "right"|"left"|"above"|"mixed", "favourite_element": String, "cuts": int}
static func player_style_facts(hits: Array, right: Vector3) -> Dictionary:
	var from_right := 0
	var from_left := 0
	var from_above := 0
	var elements := {}
	var n := 0
	for h in hits:
		if not (h is Dictionary):
			continue
		var d: Variant = h.get("direction", Vector3.ZERO)
		if not (d is Vector3) or (d as Vector3).length_squared() < 0.01:
			continue
		n += 1
		var dir := (d as Vector3).normalized()
		if dir.y < -0.6:
			from_above += 1
		elif dir.dot(right) < -0.3:
			from_right += 1  # the blade travels right -> left
		elif dir.dot(right) > 0.3:
			from_left += 1
		var el := String(h.get("element", "physical"))
		elements[el] = int(elements.get(el, 0)) + 1
	var facts := {"cuts": n}
	if n == 0:
		return facts
	var best := maxi(from_right, maxi(from_left, from_above))
	var side := "mixed"
	if best >= maxi(2, int(ceil(n * 0.55))):
		side = "right" if best == from_right else ("left" if best == from_left else "above")
	facts["cut_from"] = side
	var fav := ""
	var fav_n := 0
	for el in elements:
		if int(elements[el]) > fav_n:
			fav = String(el)
			fav_n = int(elements[el])
	facts["favourite_element"] = fav
	return facts


## Injects a test mock callable: `func(state: Dictionary) -> Dictionary`.
## When set, all calls go through this mock instantly without network requests.
func set_decision_provider(mock: Callable) -> void:
	set_mock_provider(mock)


func set_mock_provider(mock: Callable) -> void:
	_mock_provider = mock


## Clears any active mock provider.
func clear_mock_provider() -> void:
	_mock_provider = Callable()


## Injects a test hook replacing the HTTP dispatch: `func(url, headers, body) -> int`.
func set_request_hook(hook: Callable) -> void:
	_request_hook = hook


## Requests an AI combat decision asynchronously.
## [param state] contains current fight telemetry (HP, distance, phase, player actions).
## [param callback] is called with the validated decision dictionary:
## `{"tactic": String, "attack": String, "target_distance": float, "speech": String, "source": "ai" | "fallback"}`

func _get_settings() -> Node:
	if is_inside_tree() and get_tree().root.has_node("VrComfortSettings"):
		return get_tree().root.get_node("VrComfortSettings")
	return null

func request_decision(state: Dictionary, callback: Callable) -> void:
	if not callback.is_valid():
		return

	# 1. Mock provider (test suite / offline mock verification)
	if _mock_provider.is_valid():
		var raw: Variant = _mock_provider.call(state)
		var decision: Dictionary
		if raw is Dictionary:
			decision = _validate_decision(raw as Dictionary, state)
			decision["source"] = "mock"
		else:
			decision = local_fallback_decision(state)
		callback.call(decision)
		decision_received.emit(decision)
		return

	# 2. Check if Meta AI is configured and active
	var key := ""
	var active := false
	var settings := _get_settings()
	if settings != null and settings.has_method("get_effective_meta_api_key"):
		key = settings.get_effective_meta_api_key()
		active = settings.is_meta_ai_active()

	if not active or key == "" or _is_busy:
		# Quietly local: no key / AI off / a request still in flight. Nothing is logged.
		var fallback := local_fallback_decision(state)
		callback.call(fallback)
		decision_received.emit(fallback)
		return

	# 3. Dispatch async HTTP request to Meta Model API
	_is_busy = true
	_pending_callback = callback

	var model: String = settings.ai_model if settings != null else DEFAULT_MODEL
	var lang: String = settings.ai_language if settings != null else "en"

	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
	]

	var speech_lang := "Polish" if lang == "pl" else "English"
	var sys_prompt := (
		"You are the combat intelligence of the Oni Warlord in a VR Japanese dark-fantasy sword duel. "
		+ "Analyze current state and respond ONLY with a raw JSON object (no markdown, no backticks): "
		+ "{\"tactic\": \"stalk\"|\"advance\"|\"retreat\"|\"circle_left\"|\"circle_right\"|\"attack\"|\"taunt\", "
		+ "\"attack\": \"slam\"|\"sweep\"|\"thrust\"|\"combo\", "
		+ "\"target_distance\": float between 1.5 and 1.9, "
		+ "\"speech\": short taunt in %s, max 8 words, under 60 chars}."
	) % speech_lang
	var style_hint := (" The user JSON has player_style (cut_from: the side the player usually cuts from;"
		+ " favourite_element). When it is known, the speech may mock that habit, e.g. 'You always cut from the right'.")
	if katana_mode:
		sys_prompt = (
			"You are the combat intelligence of a masked ronin swordsman (katana, Oni mask) in a VR Japanese dark-fantasy sword duel. "
			+ "Choose the tactic for the next few seconds. Respond ONLY with a raw JSON object (no markdown, no backticks): "
			+ "{\"tactic\": \"aggressive\"|\"defensive\"|\"feint\"|\"flank_left\"|\"flank_right\"|\"retreat\", "
			+ "\"attack\": \"slam\"|\"sweep\"|\"thrust\"|\"combo\", "
			+ "\"target_distance\": float between 1.4 and 1.9, "
			+ "\"speech\": short taunt in %s, max 8 words, under 60 chars}."
		) % speech_lang
	sys_prompt += style_hint
	sys_prompt += " The speech field MUST be written in %s only." % speech_lang

	var body_dict := {
		"model": model,
		"messages": [
			{"role": "system", "content": sys_prompt},
			{"role": "user", "content": JSON.stringify(state)},
		],
		"temperature": 0.7,
		"max_tokens": 100,
	}

	var json_body := JSON.stringify(body_dict)
	# The endpoint comes from Settings (fallback: the Meta default constant).
	var configured := ""
	if settings != null and settings.has_method("get_effective_meta_api_endpoint"):
		configured = settings.get_effective_meta_api_endpoint()
	var endpoint := resolve_endpoint(configured)
	last_request_url = endpoint
	_inflight_s = 0.0
	_inflight_state = state.duplicate()
	request_sent.emit(endpoint)
	var err := OK
	if _request_hook.is_valid():
		err = int(_request_hook.call(endpoint, headers, json_body))
	else:
		err = _http.request(endpoint, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_is_busy = false
		var fallback := local_fallback_decision(state)
		_pending_callback = Callable()
		callback.call(fallback)
		decision_received.emit(fallback)


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _is_busy:
		return
	_is_busy = false
	var cb := _pending_callback
	_pending_callback = Callable()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var fallback := local_fallback_decision(_inflight_state)
		fallback["fallback_reason"] = "http_%d" % response_code if result == HTTPRequest.RESULT_SUCCESS else "net_%d" % result
		if cb.is_valid():
			cb.call(fallback)
		decision_received.emit(fallback)
		return

	var text := body.get_string_from_utf8().strip_edges()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		var fallback := local_fallback_decision(_inflight_state)
		fallback["fallback_reason"] = "bad_json"
		if cb.is_valid():
			cb.call(fallback)
		decision_received.emit(fallback)
		return

	var res_dict := json.data as Dictionary
	var content := ""
	var choices: Array = res_dict.get("choices", [])
	if choices.size() > 0 and choices[0] is Dictionary:
		var msg: Dictionary = choices[0].get("message", {})
		content = String(msg.get("content", "")).strip_edges()

	# Remove potential markdown fences ```json ... ```
	if content.begins_with("```"):
		var lines := content.split("\n")
		var clean_lines: Array[String] = []
		for line in lines:
			var s := line.strip_edges()
			if not s.begins_with("```"):
				clean_lines.append(s)
		content = "\n".join(clean_lines).strip_edges()

	var inner_json := JSON.new()
	if inner_json.parse(content) != OK or not (inner_json.data is Dictionary):
		var fallback := local_fallback_decision(_inflight_state)
		fallback["fallback_reason"] = "bad_content"
		if cb.is_valid():
			cb.call(fallback)
		decision_received.emit(fallback)
		return

	var decision := _validate_decision(inner_json.data as Dictionary, _inflight_state)
	decision["source"] = "ai"
	if cb.is_valid():
		cb.call(decision)
	decision_received.emit(decision)


## Strictly validates and sanitizes a decision dictionary against whitelists.
func _sanitize_response(raw: Dictionary, state: Dictionary = {}) -> Dictionary:
	return _validate_decision(raw, state)


func _validate_decision(raw: Dictionary, state: Dictionary) -> Dictionary:
	var fallback := local_fallback_decision(state)

	var tactic := String(raw.get("tactic", fallback.tactic)).to_lower().strip_edges()
	if not VALID_TACTICS.has(tactic) or (katana_mode and not DUELIST_TACTICS.has(tactic)):
		tactic = fallback.tactic

	var attack := String(raw.get("attack", fallback.attack)).to_lower().strip_edges()
	if not VALID_ATTACKS.has(attack):
		attack = fallback.attack

	var target_d := float(raw.get("target_distance", fallback.target_distance))
	target_d = clampf(target_d, MELEE_STANDOFF_MIN, MELEE_STANDOFF_MAX)

	var speech := String(raw.get("speech", fallback.speech)).strip_edges()
	# Strip non-printable / control characters and sanitize length
	speech = clip_speech(speech)
	if speech == "":
		speech = fallback.speech

	return {
		"tactic": tactic,
		"attack": attack,
		"target_distance": snappedf(target_d, 0.1),
		"speech": speech,
		"source": "ai",
	}


## One printable line of at most [constant MAX_SPEECH_CHARS] chars, cut at a word + "…".
static func clip_speech(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 32 or c == 127:
			out += " "
		elif c != 34 and c != 96 and c != 60 and c != 62:  # no quotes, backticks, <>
			out += String.chr(c)
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.length() > MAX_SPEECH_CHARS:
		var cut := out.substr(0, MAX_SPEECH_CHARS - 1)
		var sp := cut.rfind(" ")
		if sp >= MAX_SPEECH_CHARS / 2:
			cut = cut.substr(0, sp)
		out = cut.strip_edges().trim_suffix(",").trim_suffix(".") + "…"
	return out


## Produces deterministic offline combat tactics and atmospheric taunts.
func local_fallback_decision(state: Dictionary) -> Dictionary:
	var phase := int(state.get("phase", 1))
	var dist := float(state.get("distance", 3.0))
	var s := _get_settings()
	var lang: String = s.ai_language if s != null else "en"

	var tactic := "stalk"
	var attack := "slam"
	var target_d := 1.8
	if katana_mode:
		# Offline: the swordsman keeps its own duelist logic; only the taunt comes from here.
		tactic = "duel"

	if katana_mode:
		pass
	elif dist > 3.2:
		tactic = "advance"
		target_d = 1.9
	elif dist < 1.6:
		tactic = "attack" if phase >= 2 else "retreat"
		target_d = 1.9
	else:
		match phase:
			1:
				tactic = "attack" if _rng.randf() < 0.55 else "stalk"
				attack = "slam" if _rng.randf() < 0.65 else "sweep"
				target_d = 1.8
			2:
				tactic = "attack" if _rng.randf() < 0.70 else "circle_left"
				attack = "combo" if _rng.randf() < 0.55 else "thrust"
				target_d = 1.9
			_:
				tactic = "attack"
				attack = "combo" if _rng.randf() < 0.60 else "thrust"
				target_d = 1.6

	var pool: Array[String]
	if lang == "en":
		pool = FALLBACK_SPEECH_EN_P1 if phase == 1 else (FALLBACK_SPEECH_EN_P2 if phase == 2 else FALLBACK_SPEECH_EN_P3)
	else:
		pool = FALLBACK_SPEECH_PL_P1 if phase == 1 else (FALLBACK_SPEECH_PL_P2 if phase == 2 else FALLBACK_SPEECH_PL_P3)

	var speech_line := pool[_rng.randi() % pool.size()]

	return {
		"tactic": tactic,
		"attack": attack,
		"target_distance": target_d,
		"speech": speech_line,
		"source": "fallback",
	}

func validate_decision(raw: Dictionary, state: Dictionary) -> Dictionary:
	return _validate_decision(raw, state)
