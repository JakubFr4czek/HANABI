class_name StormMusic
extends Node
## Subdued CC0 ambient loop on the Music bus (NIGHT_PLAN §15, §18).
## Dual-player crossfade avoids OGG loop clicks; ducks under level-up stingers.
## Features a subtle CC0 shakuhachi & taiko layer on the Music bus (Zadanie 5).

const TRACK := preload("res://assets/audio/music/cc0_run/orientalsomber.ogg")
const LAYER_TRACK := preload("res://assets/audio/music/cc0_run/shakuhachi_taiko_layer.wav")
const CROSSFADE_SEC := 0.5
const LOOP_TAIL_TRIM_SEC := 0.2

@export var volume_db := -12.0
@export var layer_volume_db := -15.5

var _players: Array[AudioStreamPlayer] = []
var _lead := 0
var _track_length := 279.0
var _duck_offset_db := 0.0
var _crossfading := false
var _duck_tween: Tween

var _layer_player: AudioStreamPlayer


func _ready() -> void:
	# Keeps playing while a menu pauses the game (ducked by Sfx.set_pause_ducking).
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stream := _music_stream()
	_track_length = stream.get_length()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "RunMusic%d" % i
		player.stream = stream
		player.volume_db = _target_volume_db()
		player.bus = Sfx.MUSIC_BUS
		add_child(player)
		_players.append(player)
	_players[0].play()

	_setup_layer_player()
	set_process(true)


func _music_stream() -> AudioStream:
	var stream: AudioStream = TRACK
	if stream is AudioStreamOggVorbis:
		var ogg := (stream as AudioStreamOggVorbis).duplicate()
		ogg.loop = false
		return ogg
	return stream


func _setup_layer_player() -> void:
	_layer_player = AudioStreamPlayer.new()
	_layer_player.name = "RunMusicLayer"
	_layer_player.stream = LAYER_TRACK
	_layer_player.volume_db = _target_layer_volume_db()
	_layer_player.bus = Sfx.MUSIC_BUS
	add_child(_layer_player)
	_layer_player.play()


func get_layer_player() -> AudioStreamPlayer:
	return _layer_player


func _process(_delta: float) -> void:
	if is_instance_valid(_layer_player) and not _layer_player.playing:
		_layer_player.volume_db = _target_layer_volume_db()
		_layer_player.play()

	if _crossfading or _players.is_empty():
		return
	var lead := _players[_lead]
	if not lead.playing:
		# Never let the run go silent: an interrupted or finished lead
		# (audio focus change on the headset, a stream hiccup) restarts
		# instead of leaving the music dead for the rest of the session.
		lead.volume_db = _target_volume_db()
		lead.play()
		return
	var tail := maxf(2.0, _track_length - LOOP_TAIL_TRIM_SEC)
	if lead.get_playback_position() >= tail - CROSSFADE_SEC:
		_begin_crossfade()


func _begin_crossfade() -> void:
	if _crossfading:
		return
	_crossfading = true
	var out_idx := _lead
	var in_idx := 1 - _lead
	var out := _players[out_idx]
	var inn := _players[in_idx]
	inn.volume_db = _target_volume_db() - 40.0
	inn.play()
	inn.seek(0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(out, "volume_db", _target_volume_db() - 48.0, CROSSFADE_SEC)
	tween.tween_property(inn, "volume_db", _target_volume_db(), CROSSFADE_SEC)
	tween.chain().tween_callback(func() -> void:
		out.stop()
		out.volume_db = _target_volume_db()
		_lead = in_idx
		_crossfading = false
	)


func duck_for_level_up(duration: float = 2.6, depth_db: float = -9.0) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck_offset, 0.0, depth_db, 0.12)
	_duck_tween.tween_interval(duration)
	_duck_tween.tween_method(_set_duck_offset, depth_db, 0.0, 0.45)


func _set_duck_offset(db: float) -> void:
	_duck_offset_db = db
	_apply_volume_to_players()


func _target_volume_db() -> float:
	return volume_db + _duck_offset_db


func _target_layer_volume_db() -> float:
	return layer_volume_db + _duck_offset_db


func _apply_volume_to_players() -> void:
	var vol := _target_volume_db()
	for p in _players:
		if p.playing or p == _players[_lead]:
			p.volume_db = vol
	if is_instance_valid(_layer_player):
		_layer_player.volume_db = _target_layer_volume_db()
