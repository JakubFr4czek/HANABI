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

const DEFAULT_META_ENDPOINT := "https://api.meta.ai/v1/chat/completions"
const META_ENDPOINT := DEFAULT_META_ENDPOINT
const DEFAULT_MODEL := "muse-spark-1.3"
const TIMEOUT_SECONDS := 3.0
const VALID_TACTICS: Array[String] = [
	"stalk", "advance", "retreat", "circle_left", "circle_right", "attack", "taunt"
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
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_http = HTTPRequest.new()
	_http.name = "AiHttp"
	_http.timeout = TIMEOUT_SECONDS
	add_child(_http)
	_http.request_completed.connect(_on_http_request_completed)


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
		var fallback := local_fallback_decision(state)
		callback.call(fallback)
		decision_received.emit(fallback)
		return

	# 3. Dispatch async HTTP request to Meta Model API
	_is_busy = true
	_pending_callback = callback

	var model: String = settings.ai_model if settings != null else DEFAULT_MODEL
	var lang: String = settings.ai_language if settings != null else "pl"

	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
	]

	var sys_prompt := (
		"You are the combat intelligence of the Oni Warlord in a VR Japanese dark-fantasy sword duel. "
		+ "Analyze current state and respond ONLY with a raw JSON object (no markdown, no backticks): "
		+ "{\"tactic\": \"stalk\"|\"advance\"|\"retreat\"|\"circle_left\"|\"circle_right\"|\"attack\"|\"taunt\", "
		+ "\"attack\": \"slam\"|\"sweep\"|\"thrust\"|\"combo\", "
		+ "\"target_distance\": float between 1.5 and 3.5, "
		+ "\"speech\": short taunt in %s, max 8 words, under 60 chars}."
	) % ["Polish" if lang == "pl" else "English"]

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
	var endpoint := DEFAULT_META_ENDPOINT
	if settings != null and settings.has_method("get_effective_meta_api_endpoint"):
		var configured: String = settings.get_effective_meta_api_endpoint()
		if configured.strip_edges() != "":
			endpoint = configured.strip_edges()
	last_request_url = endpoint
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
		var fallback := local_fallback_decision({})
		if cb.is_valid():
			cb.call(fallback)
		decision_received.emit(fallback)
		return

	var text := body.get_string_from_utf8().strip_edges()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		var fallback := local_fallback_decision({})
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
		var fallback := local_fallback_decision({})
		if cb.is_valid():
			cb.call(fallback)
		decision_received.emit(fallback)
		return

	var decision := _validate_decision(inner_json.data as Dictionary, {})
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
	if not VALID_TACTICS.has(tactic):
		tactic = fallback.tactic

	var attack := String(raw.get("attack", fallback.attack)).to_lower().strip_edges()
	if not VALID_ATTACKS.has(attack):
		attack = fallback.attack

	var target_d := float(raw.get("target_distance", fallback.target_distance))
	target_d = clampf(target_d, 1.4, 4.0)

	var speech := String(raw.get("speech", fallback.speech)).strip_edges()
	# Strip non-printable / control characters and sanitize length
	speech = speech.replace("\n", " ").replace("\r", " ").replace("\"", "").replace("'", "")
	while speech.contains("  "):
		speech = speech.replace("  ", " ")
	if speech.length() > 80:
		speech = speech.substr(0, 77) + "..."
	if speech == "":
		speech = fallback.speech

	return {
		"tactic": tactic,
		"attack": attack,
		"target_distance": snappedf(target_d, 0.1),
		"speech": speech,
		"source": "ai",
	}


## Produces deterministic offline combat tactics and atmospheric taunts.
func local_fallback_decision(state: Dictionary) -> Dictionary:
	var phase := int(state.get("phase", 1))
	var dist := float(state.get("distance", 3.0))
	var s := _get_settings()
	var lang: String = s.ai_language if s != null else "pl"

	var tactic := "stalk"
	var attack := "slam"
	var target_d := 2.2

	if dist > 3.2:
		tactic = "advance"
		target_d = 2.0
	elif dist < 1.6:
		tactic = "attack" if phase >= 2 else "retreat"
		target_d = 1.9
	else:
		match phase:
			1:
				tactic = "attack" if _rng.randf() < 0.55 else "stalk"
				attack = "slam" if _rng.randf() < 0.65 else "sweep"
				target_d = 2.2
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
