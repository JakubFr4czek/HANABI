extends SceneTree
## Writes the World Gen presets (data/worldgen/*.tres) from code, so every preset
## is reproducible and reviewable as a diff. Run after changing a preset here:
##   godot --headless --path . -s res://tools/worldgen/make_presets.gd
## The default preset carries the numbers the forest has always used; the others
## are variations on it (see docs/WORLDGEN_TOOL.md).

const OUT_DIR := "res://data/worldgen"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var failures := 0
	failures += _save(WorldGenProfile.make_default(), "default_profile")
	failures += _save(_dense_dusk(), "dense_dusk")
	failures += _save(_quest_perf(), "quest_perf")
	quit(1 if failures > 0 else 0)


func _save(profile: WorldGenProfile, file: String) -> int:
	var path := "%s/%s.tres" % [OUT_DIR, file]
	var err := ResourceSaver.save(profile, path)
	print("PRESET %s -> %s (%s)" % [file, path, "ok" if err == OK else "error %d" % err])
	return 0 if err == OK else 1


## Thicker forest with more sakura and gates: for screenshots and the mood.
func _dense_dusk() -> WorldGenProfile:
	var p := WorldGenProfile.make_default()
	p.world_seed = 4242
	p.tree_keep_min = 0.7
	p.tree_keep_max = 1.0
	p.trees[1].focal_chance = 0.3
	p.torii_chunk_chance = 0.5
	p.lantern_max_per_chunk = 8
	p.fog_start = 2.0
	p.fog_end = 13.0
	p.tree_draw_radius = 13.0
	p.focal_draw_radius = 13.0
	p.lod_near_radius = 7.0
	return p


## Quest-first preset: fewer trunks, shorter draw reach, lighter ground.
func _quest_perf() -> WorldGenProfile:
	var p := WorldGenProfile.make_default()
	p.tree_keep_min = 0.35
	p.tree_keep_max = 0.8
	p.fog_end = 24.0
	p.tree_draw_radius = 24.0
	p.focal_draw_radius = 24.0
	p.lod_near_radius = 6.0
	p.terrain_resolution = 33
	p.torii_chunk_chance = 0.25
	p.lantern_max_per_chunk = 3
	p.shafts_max_per_chunk = 2
	p.undergrowth[0].max_per_chunk = 2
	return p
