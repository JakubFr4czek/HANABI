@tool
class_name WorldGenPreview
extends Node3D
## Live preview of the forest for the World Gen tool (docs/WORLDGEN_TOOL.md).
## Open tools/worldgen/worldgen_preview.tscn in the editor: the forest of the
## profile is regenerated shortly after each change (debounced), under the same
## sky, fog and moon as the run (WorldGenLook), so what you see is what plays.

signal regenerated(stats: Dictionary)

const DEBOUNCE_SECONDS := 0.35
const MOON_DIRECTION := Vector3(0.18, 0.407, -0.896)
const PRESET_FOLDER := "res://data/worldgen"

## The profile being previewed. Empty uses the active profile of the game.
@export var profile: WorldGenProfile = null:
	set(value):
		profile = value
		if is_inside_tree():
			regenerate()
## Orbit of the preview camera for screenshots (degrees per second; 0 = still).
@export_range(0.0, 60.0, 0.5) var orbit_speed := 0.0
@export_range(6.0, 60.0, 0.5) var orbit_radius := 16.0
@export_range(-60.0, 10.0, 1.0) var orbit_pitch := -12.0
## Buttons in the inspector (Godot 4.4+ tool buttons).
@export_tool_button("Regeneruj") var button_regenerate: Callable = regenerate
@export_tool_button("Losuj seed") var button_seed: Callable = new_seed

var forest: ForestWorld = null
var camera: Camera3D = null
var moon: DirectionalLight3D = null
var environment_node: WorldEnvironment = null
var last_stats: Dictionary = {}
var _follow: Node3D = null
var _signature := 0
var _pending := -1.0
var _poll := 0.0
var _angle := 0.0


func _ready() -> void:
	_ensure_nodes()
	regenerate()


func _process(delta: float) -> void:
	if forest == null:
		return
	if orbit_speed != 0.0:
		_angle = fmod(_angle + orbit_speed * delta, 360.0)
		frame_camera(_angle)
	# Debounce: a change in the inspector regenerates once the values settle.
	# The signature is checked five times a second, not every frame.
	_poll += delta
	if _poll < 0.2:
		return
	_poll = 0.0
	var active := active_profile()
	if active.signature() != _signature:
		if _pending < 0.0:
			_pending = DEBOUNCE_SECONDS
		_pending -= delta
		if _pending <= 0.0:
			regenerate()
	else:
		_pending = -1.0


## The profile the preview shows (the inspector one, else the game's).
func active_profile() -> WorldGenProfile:
	if profile != null:
		return profile
	return WorldGenProfile.load_active()


## The profile to edit in place: the game's one is copied first, so changes
## stay in the preview and never touch the shared resource of the game.
func editable_profile() -> WorldGenProfile:
	if profile == null:
		profile = WorldGenProfile.load_active().duplicate(true) as WorldGenProfile
	return profile


## Rebuilds the forest from the profile at once. Returns the stats afterwards.
## The forest is built the way the run builds it (new ForestWorld, profile,
## setup), and the old one is freed on the spot, so no state is carried over.
func regenerate() -> Dictionary:
	_ensure_nodes()
	var active := active_profile()
	WorldGenLook.apply_fog(environment_node.environment, active)
	WorldGenLook.apply_light(environment_node.environment, active)
	WorldGenLook.apply_moon(moon, active)
	if forest != null:
		remove_child(forest)
		forest.free()
	forest = ForestWorld.new()
	forest.name = "ForestWorld"
	forest.profile = active
	forest.moon_direction = MOON_DIRECTION
	add_child(forest)
	forest.setup(_follow)
	_signature = active.signature()
	_pending = -1.0
	last_stats = forest.stats()
	regenerated.emit(last_stats)
	return last_stats


## A fresh world seed in the previewed profile, then regenerate.
func new_seed() -> void:
	editable_profile().randomize_seed()
	regenerate()


## Saves the previewed profile as a preset (.tres) and returns its path.
func save_preset(file_name: String = "") -> String:
	var active := active_profile().duplicate(true) as WorldGenProfile
	var name := file_name if file_name != "" else "preset_seed%d" % active.world_seed
	var path := "%s/%s.tres" % [PRESET_FOLDER, name]
	DirAccess.make_dir_recursive_absolute(PRESET_FOLDER)
	var err := ResourceSaver.save(active, path)
	return path if err == OK else ""


## Puts the camera on the orbit at [param degrees] around the glade.
func frame_camera(degrees: float) -> void:
	_ensure_nodes()
	var rad := deg_to_rad(degrees)
	var pitch := deg_to_rad(orbit_pitch)
	var at := Vector3(sin(rad) * cos(pitch), -sin(pitch), cos(rad) * cos(pitch)) * orbit_radius
	camera.position = at + Vector3(0.0, 2.6, 0.0)
	camera.look_at(Vector3(0.0, 2.6, 0.0), Vector3.UP)


func _ensure_nodes() -> void:
	if _follow != null and is_instance_valid(_follow):
		return
	for child in get_children():
		child.free()
	_follow = Node3D.new()
	_follow.name = "Follow"
	add_child(_follow)
	environment_node = WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	environment_node.environment = Environment.new()
	add_child(environment_node)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.basis = Basis.looking_at(-MOON_DIRECTION)
	add_child(moon)
	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = 62.0
	add_child(camera)
	camera.current = not Engine.is_editor_hint()
	frame_camera(_angle)
