extends Node
## Windowed screenshots of the World Gen preview (docs/WORLDGEN_TOOL.md): the default
## profile and quest_perf from the same viewpoints, to judge them against the concept
## (docs/concept/forest_concept.jpg). Needs a window, so it is not a headless test:
##   godot --path . --fixed-fps 90 res://tools/worldgen/worldgen_screenshots.tscn -- --desktop --shots /tmp/hanabi_d8

const PREVIEW_SCENE := preload("res://tools/worldgen/worldgen_preview.tscn")
const PROFILES := ["default_profile", "quest_perf"]

var out_dir := "/tmp/hanabi_d8"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	for file in PROFILES:
		var preview := PREVIEW_SCENE.instantiate() as WorldGenPreview
		preview.profile = load("res://data/worldgen/%s.tres" % file) as WorldGenProfile
		add_child(preview)
		await _frames(20)
		var cam := preview.camera
		# Vista: from the glade edge across the rolling forest, eye height.
		cam.global_position = Vector3(-4.0, 2.4, 13.0)
		cam.look_at(Vector3(4.0, 3.5, -12.0), Vector3.UP)
		await _frames(12)
		await _shot("%s_vista" % file)
		# Wide: high over the 3×3 ring with the fog off, to read the layout of
		# paths and gates (the game keeps its fog on).
		preview.show_fog = false
		cam.global_position = Vector3(0.0, 30.0, 34.0)
		cam.look_at(Vector3(0.0, 0.0, -4.0), Vector3.UP)
		await _frames(12)
		await _shot("%s_wide" % file)
		preview.show_fog = true
		# Path: standing beside a trodden line, looking along it.
		var sample := _path_sample(preview.forest)
		if sample.w != 0.0 or sample.z != 0.0:
			var at := Vector3(sample.x, preview.forest.height_at(sample.x, sample.y), sample.y)
			var along := Vector3(sample.z, 0.0, sample.w).normalized()
			var side := Vector3(-along.z, 0.0, along.x)
			cam.global_position = at + side * 2.6 + Vector3(0.0, 1.5, 0.0)
			cam.look_at(at + along * 6.0 + Vector3(0.0, 0.6, 0.0), Vector3.UP)
			await _frames(12)
			await _shot("%s_path" % file)
		preview.free()
		await _frames(4)
	get_tree().quit(0)


## First path sample in the ring: Vector4(x, z, tangent.x, tangent.y), or zeros.
func _path_sample(forest: ForestWorld) -> Vector4:
	if forest.paths == null:
		return Vector4.ZERO
	var size := forest.profile.chunk_size * 1.5
	var found := forest.paths.samples_in_rect(Rect2(Vector2(-size, -size), Vector2(size * 2.0, size * 2.0)), 2.0)
	for s in found:
		if Vector2(s.x, s.y).length() > 8.0:
			return Vector4(s.x, s.y, s.z, s.w)
	return Vector4.ZERO


func _frames(count: int) -> void:
	for k in count:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHOT %s" % out_dir.path_join(name + ".png"))
