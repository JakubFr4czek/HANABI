extends Node
## One-shot positional sound effects (autoload "Sfx").
##
## Each category is a set of sound files picked at random with a little pitch
## variation. A small pool of AudioStreamPlayer3D nodes is reused. Positional
## sounds go through the "World" bus (open-air reverb over water); looping
## ambience uses the "Ambience" bus.

const CATEGORIES := {
	"swing": ["res://assets/audio/sfx/sword_swing", ""],
	"clash": ["res://assets/audio/sfx/sword_clash", ""],
	"impact_light": ["res://assets/audio/sfx/impact", "impactPlank"],
	"impact_heavy": ["res://assets/audio/sfx/impact", "impactPunch"],
	"blade_ring": ["res://assets/audio/generated", "blade_ring"],
	"thunder": ["res://assets/audio/generated", "thunder"],
	"enemy_tell": ["res://assets/audio/generated", "enemy_tell"],
	"player_hurt": ["res://assets/audio/generated", "player_hurt"],
	"cut": ["res://assets/audio/generated", "cut"],
	"slap": ["res://assets/audio/generated", "slap"],
}
const POOL_SIZE := 12
const WORLD_BUS := &"World"
const AMBIENCE_BUS := &"Ambience"

var _streams := {}  # category -> AudioStreamRandomizer
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0


func _ready() -> void:
	_setup_buses()
	for category in CATEGORIES:
		var dir: String = CATEGORIES[category][0]
		var prefix: String = CATEGORIES[category][1]
		var randomizer := AudioStreamRandomizer.new()
		randomizer.random_pitch = 1.08
		randomizer.random_volume_offset_db = 2.0
		for file in ResourceLoader.list_directory(dir):
			if file.get_extension() not in ["ogg", "wav"] or not file.begins_with(prefix):
				continue
			var stream := load(dir.path_join(file)) as AudioStream
			if stream:
				randomizer.add_stream(-1, stream)
		if randomizer.streams_count > 0:
			_streams[category] = randomizer
		else:
			push_warning("Sfx: no sounds found for '%s' in %s" % [category, dir])
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 4.0
		player.max_polyphony = 1
		player.bus = WORLD_BUS
		add_child(player)
		_pool.append(player)


func play_at(category: String, position: Vector3, volume_db: float = 0.0, unit_size: float = 4.0) -> void:
	if not _streams.has(category):
		return
	var player := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = _streams[category]
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.global_position = position
	player.play()


func _setup_buses() -> void:
	if AudioServer.get_bus_index(WORLD_BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, WORLD_BUS)
		AudioServer.set_bus_send(i, &"Master")
		var reverb := AudioEffectReverb.new()
		reverb.predelay_msec = 45.0
		reverb.room_size = 0.75
		reverb.damping = 0.6
		reverb.spread = 0.85
		reverb.hipass = 0.12
		reverb.dry = 1.0
		reverb.wet = 0.22
		AudioServer.add_bus_effect(i, reverb)
	if AudioServer.get_bus_index(AMBIENCE_BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, AMBIENCE_BUS)
		AudioServer.set_bus_send(i, &"Master")
