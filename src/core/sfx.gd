extends Node
## One-shot positional sound effects (autoload "Sfx").
##
## Each category is a set of sound files picked at random with a little pitch
## variation. A small pool of AudioStreamPlayer3D nodes is reused.

const CATEGORIES := {
	"swing": ["res://assets/audio/sfx/sword_swing", ""],
	"clash": ["res://assets/audio/sfx/sword_clash", ""],
	"impact_light": ["res://assets/audio/sfx/impact", "impactPlank"],
	"impact_heavy": ["res://assets/audio/sfx/impact", "impactPunch"],
}
const POOL_SIZE := 12

var _streams := {}  # category -> AudioStreamRandomizer
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0


func _ready() -> void:
	for category in CATEGORIES:
		var dir: String = CATEGORIES[category][0]
		var prefix: String = CATEGORIES[category][1]
		var randomizer := AudioStreamRandomizer.new()
		randomizer.random_pitch = 1.08
		randomizer.random_volume_offset_db = 2.0
		for file in ResourceLoader.list_directory(dir):
			if file.get_extension() != "ogg" or not file.begins_with(prefix):
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
		add_child(player)
		_pool.append(player)


func play_at(category: String, position: Vector3, volume_db: float = 0.0) -> void:
	if not _streams.has(category):
		return
	var player := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = _streams[category]
	player.volume_db = volume_db
	player.global_position = position
	player.play()
