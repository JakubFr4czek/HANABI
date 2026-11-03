class_name MetaApiMockServer
extends Node
## N8: a local stand-in for the Meta chat-completions API (no network, no key).
## Listens on 127.0.0.1 and answers POSTs in the Meta/OpenAI chat-completions shape,
## the decision JSON in choices[0].message.content. [member mode] picks the reply:
##   "ok" (reply = [member decision]), "401", "500", "garbage" (not JSON),
##   "bad_content" (content is prose), "hang" (never answers: the client must time out).

var mode := "ok"
var decision := {"tactic": "flank_left", "attack": "sweep", "speech": "You always cut from the right."}
var port := 0
## Every request body (parsed JSON or {}), oldest first.
var requests: Array[Dictionary] = []
var auth_headers: Array[String] = []

var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _buffers: Array[PackedByteArray] = []


func start(p_port: int = 0) -> int:
	for attempt in 20:
		var try_port := p_port if p_port > 0 else 18900 + randi() % 900
		if _server.listen(try_port, "127.0.0.1") == OK:
			port = try_port
			return OK
	return ERR_CANT_CREATE


func endpoint() -> String:
	return "http://127.0.0.1:%d/v1/chat/completions" % port


func _exit_tree() -> void:
	for p in _peers:
		p.disconnect_from_host()
	_server.stop()


func _process(_delta: float) -> void:
	poll()


func _physics_process(_delta: float) -> void:
	poll()


func poll() -> void:
	while _server.is_connection_available():
		_peers.append(_server.take_connection())
		_buffers.append(PackedByteArray())
	for i in range(_peers.size() - 1, -1, -1):
		var peer := _peers[i]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.remove_at(i)
			_buffers.remove_at(i)
			continue
		var avail := peer.get_available_bytes()
		if avail > 0:
			var got := peer.get_data(avail)
			if got[0] == OK:
				_buffers[i].append_array(got[1])
		var text := _buffers[i].get_string_from_utf8()
		var head_end := text.find("\r\n\r\n")
		if head_end < 0:
			continue
		var length := 0
		for line in text.substr(0, head_end).split("\r\n"):
			var l := line.to_lower()
			if l.begins_with("content-length:"):
				length = int(l.substr(15).strip_edges())
			if l.begins_with("authorization:"):
				auth_headers.append(line.substr(14).strip_edges())
		var body_bytes := _buffers[i].size() - (text.substr(0, head_end + 4).to_utf8_buffer().size())
		if body_bytes < length:
			continue
		var body := text.substr(head_end + 4)
		var parsed: Variant = JSON.parse_string(body)
		requests.append(parsed if parsed is Dictionary else {})
		_buffers[i] = PackedByteArray()
		if mode == "hang":
			continue
		_reply(peer)
		peer.disconnect_from_host()
		_peers.remove_at(i)
		_buffers.remove_at(i)


func _reply(peer: StreamPeerTCP) -> void:
	var code := 200
	var body := ""
	match mode:
		"401":
			code = 401
			body = JSON.stringify({"error": {"message": "invalid api key"}})
		"500":
			code = 500
			body = JSON.stringify({"error": {"message": "internal"}})
		"garbage":
			body = "<html>upstream broke {{{"
		"bad_content":
			body = _completion("Sorry, I cannot do JSON today.")
		_:
			body = _completion(JSON.stringify(decision))
	var bytes := body.to_utf8_buffer()
	var status := {200: "OK", 401: "Unauthorized", 500: "Internal Server Error"}
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		code, status.get(code, "OK"), bytes.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(bytes)


static func _completion(content: String) -> String:
	return JSON.stringify({
		"id": "chatcmpl-mock", "object": "chat.completion", "model": "muse-spark-1.3",
		"choices": [{"index": 0, "finish_reason": "stop",
			"message": {"role": "assistant", "content": content}}],
		"usage": {"prompt_tokens": 120, "completion_tokens": 30, "total_tokens": 150},
	})
