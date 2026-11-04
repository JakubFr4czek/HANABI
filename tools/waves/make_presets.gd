extends SceneTree
## Writes the wave presets (data/waves/*.tres) from code, so each preset is
## reproducible and reviewable as a diff. Run after changing a preset here:
##   .tools/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/waves/make_presets.gd
## The default preset is the WaveProfile defaults; the others are variations on it
## (docs/SPAWN_TOOL.md).

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(WaveProfile.PRESET_DIR)
	var failures := 0
	failures += _save(WaveProfile.new(), "default")
	failures += _save(_demo(), "demo")
	failures += _save(_demo_gentle(), "demo_gentle")
	failures += _save(_hardcore(), "hardcore")
	quit(1 if failures > 0 else 0)


func _save(profile: WaveProfile, file: String) -> int:
	var path := WaveProfile.preset_path(file)
	var err := ResourceSaver.save(profile, path)
	print("PRESET %s -> %s (%s)" % [file, path, "ok" if err == OK else "error %d" % err])
	return 0 if err == OK else 1


## Demo 3 min (N7, `-- --demo`): quiet to 30 s, first contact at 30 s, the budget climbs to a
## crowded peak by 2 min, the first elite at 100 s, the Oni on the first PEAK after 120 s
## (the window 120–150 s is a test). Cap 2 → 7, one more every 30 s.
func _demo() -> WaveProfile:
	var p := WaveProfile.new()
	p.calm_seconds = 30.0
	p.initial_wave_delay = 26.0
	p.ramp_seconds = 150.0
	p.rest_calm = 15.0
	p.rest_full = 4.0
	p.wave_credits_full = 12.0
	p.cap_step_seconds = 30.0
	p.cap_hard = 7
	p.elite_from_seconds = 100.0
	p.elite_chance_full = 0.5
	p.oni_first_seconds = 60.0
	p.oni_interval = 100.0
	return p


## Demo: a long, quiet opening; the budget eases in; a lighter cap for the first minutes.
func _demo_gentle() -> WaveProfile:
	var p := WaveProfile.new()
	p.calm_seconds = 120.0
	p.ramp_seconds = 600.0
	p.initial_wave_delay = 6.0
	p.rest_calm = 18.0
	p.wave_credits_start = 1.0
	p.wave_credits_full = 9.0
	p.cap_step_seconds = 60.0
	p.cap_hard = 6
	p.elite_from_seconds = 240.0
	p.elite_chance_full = 0.10
	p.oni_first_seconds = 300.0
	p.oni_interval = 150.0
	p.hp_per_second = 0.003
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.5, 0.25))
	curve.add_point(Vector2(1.0, 1.0))
	p.budget_curve = curve
	return p


## Hardcore: short calm, a fast ramp to the Quest cap, elites early and an Oni sooner.
func _hardcore() -> WaveProfile:
	var p := WaveProfile.new()
	p.calm_seconds = 45.0
	p.ramp_seconds = 420.0
	p.initial_wave_delay = 3.0
	p.rest_calm = 8.0
	p.wave_credits_full = 20.0
	p.cap_step_seconds = 30.0
	p.peak_budget_mult = 1.7
	p.elite_from_seconds = 120.0
	p.elite_chance_full = 0.35
	p.oni_first_seconds = 150.0
	p.oni_interval = 80.0
	p.hp_per_wave = 0.16
	p.hp_per_second = 0.005
	return p
