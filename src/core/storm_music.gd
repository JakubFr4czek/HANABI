class_name StormMusic
extends Node
## Subdued CC0 ambient loop on the Music bus (NIGHT_PLAN §15).

const TRACK := preload("res://assets/audio/music/cc0_run/orientalsomber.ogg")

@export var volume_db := -20.0

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "RunMusic"
	var stream := TRACK
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	_player.stream = stream
	_player.volume_db = volume_db
	_player.bus = Sfx.MUSIC_BUS
	add_child(_player)
	_player.play()
