class_name RunForestAmbience
extends Node
## Subtle forest wind bed on the Ambience bus during survival runs.

const WIND := preload("res://assets/audio/sfx/hanabi_proc/forest_wind_loop.wav")

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "ForestWind"
	var stream := WIND
	if stream is AudioStreamWAV:
		var dup := stream.duplicate() as AudioStreamWAV
		dup.loop_mode = AudioStreamWAV.LOOP_FORWARD
		dup.loop_end = int(dup.get_length() * dup.mix_rate)
		stream = dup
	_player.stream = stream
	_player.volume_db = -22.0
	_player.bus = Sfx.MUSIC_BUS
	add_child(_player)
	_player.play()
