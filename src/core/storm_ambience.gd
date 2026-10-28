class_name StormAmbience
extends Node
## Storm soundscape: a stereo rain bed on the Ambience bus, and distant thunder
## rolling in a moment after each lightning strike, placed in the direction of
## the bolt so it pans and gets the World bus reverb.

const RAIN := preload("res://assets/audio/sfx/cc0_storm/amb_rain_loop_1.ogg")

@export var rain_volume_db := -14.0
@export var thunder_volume_db := 2.0
## Seconds between the flash and the thunder (distant storm).
@export var thunder_delay_min := 0.9
@export var thunder_delay_max := 2.6
@export var thunder_distance := 30.0

var lightning: StormLightning
var rain_player: AudioStreamPlayer
var thunders_played := 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Keeps playing while a menu pauses the game (ducked by Sfx.set_pause_ducking).
	process_mode = Node.PROCESS_MODE_ALWAYS
	rain_player = AudioStreamPlayer.new()
	rain_player.name = "Rain"
	var stream: AudioStream = RAIN
	if stream is AudioStreamOggVorbis:
		var ogg := (stream as AudioStreamOggVorbis).duplicate()
		ogg.loop = true
		stream = ogg
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			var looped := wav.duplicate()
			looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
			looped.loop_end = int(looped.get_length() * looped.mix_rate)
			stream = looped
	rain_player.stream = stream
	rain_player.volume_db = rain_volume_db
	rain_player.bus = Sfx.AMBIENCE_BUS
	add_child(rain_player)
	rain_player.play()
	if lightning:
		lightning.struck.connect(_on_struck)


func _on_struck(direction: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	var origin := cam.global_position if cam else Vector3.ZERO
	var dir := Vector3(direction.x, 0.3, direction.y).normalized()
	var delay := _rng.randf_range(thunder_delay_min, thunder_delay_max)
	get_tree().create_timer(delay, true, false, true).timeout.connect(_thunder.bind(direction, delay))


func _thunder(direction: Vector2, delay: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var origin := cam.global_position if cam else Vector3.ZERO
	var dir := Vector3(direction.x, 0.3, direction.y).normalized()
	# Farther strikes (longer delay) are quieter.
	Sfx.play_at("thunder", origin + dir * thunder_distance, thunder_volume_db - delay * 2.5, thunder_distance)
	thunders_played += 1
