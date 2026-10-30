extends Node
## D18 distant matsuri fireworks (docs/FIREWORKS_PLAN.md). Time is stepped with
## DistantFireworks.advance(); nothing waits in real time.
##   godot --headless --path . --fixed-fps 90 res://tests/distant_fireworks_test.tscn -- --desktop

const PROFILE := preload("res://data/worldgen/default_profile.tres")
const SIM_STEP := 0.1
const SIM_SECONDS := 1200.0

var failures := 0


func _ready() -> void:
	_schedule_and_bands()
	_direction_and_sound_delay()
	_bus_and_levels()
	_budget_and_pool()
	_flash_reduction()
	_lifecycle_and_wave_hook()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


## Rhythm: irregular far gaps, short series, rare near escalations. Every number
## from the profile's bands.
func _schedule_and_bands() -> void:
	var fw := _make_fireworks(7)
	fw.set_enabled(true)
	_simulate(fw, SIM_SECONDS)
	var far: Array[Dictionary] = []
	var near: Array[Dictionary] = []
	for b in fw.burst_log:
		if b.kind == "far":
			far.append(b)
		else:
			near.append(b)

	var starts: Array[Dictionary] = []
	var series_gaps_ok := true
	var series_members_ok := true
	var gap_values := {}
	for i in range(1, far.size()):
		var gap: float = far[i].t - far[i - 1].t
		if far[i].series_start:
			starts.append(far[i])
			gap_values[snappedf(gap, 0.5)] = true
			if gap < PROFILE.firework_interval_min - 1e-6 or gap > PROFILE.firework_interval_max + SIM_STEP:
				series_gaps_ok = false
		else:
			if gap < 0.6 - 1e-6 or gap > 2.5 + SIM_STEP:
				series_members_ok = false
	_check("far bursts come in gaps of %.0f–%.0f s between series" % [PROFILE.firework_interval_min, PROFILE.firework_interval_max],
		series_gaps_ok and starts.size() >= 8)
	_check("series members follow 0.6–2.5 s apart (no fixed rhythm)", series_members_ok)
	_check("gaps are irregular, not a fixed beat (%d distinct gaps)" % gap_values.size(), gap_values.size() >= 6)
	var series_seen := false
	for b in far:
		if not b.series_start:
			series_seen = true
	_check("some far bursts open series of 2–4 bursts", series_seen)

	var far_ok := true
	var height_ok := true
	for b in far:
		far_ok = far_ok and b.dist >= PROFILE.firework_far_min and b.dist <= PROFILE.firework_far_max
		height_ok = height_ok and b.height >= 18.0 and b.height <= 60.0
	_check("far bursts sit %.0f–%.0f m out, above the tree line (18–60 m)" % [PROFILE.firework_far_min, PROFILE.firework_far_max],
		far_ok and height_ok and far.size() >= 20)

	var near_ok := true
	var near_gap_ok := true
	for i in near.size():
		near_ok = near_ok and near[i].dist >= PROFILE.firework_near_min and near[i].dist <= PROFILE.firework_near_max
		if i > 0:
			near_gap_ok = near_gap_ok and near[i].t - near[i - 1].t >= PROFILE.firework_near_interval_min - SIM_STEP
	_check("near escalations are 40–80 m out and never closer than 40 m", near_ok and near.size() >= 1)
	_check("near escalations are rare: 5–10 in 20 min (every 2–4 min), at least 120 s apart (%d)" % near.size(),
		near.size() >= 4 and near.size() <= 10 and near_gap_ok)
	fw.queue_free()


## Each new direction differs from the last two by at least 70 degrees, so the
## burst never repeats a spot. The sound arrives at distance / 343 m/s.
func _direction_and_sound_delay() -> void:
	var fw := _make_fireworks(11)
	fw.set_enabled(true)
	_simulate(fw, SIM_SECONDS)
	var log_ := fw.burst_log
	var angle_ok := log_.size() >= 30
	for i in range(2, log_.size()):
		var a: float = log_[i].azimuth
		for j in [i - 1, i - 2]:
			var gap := absf(wrapf(a - float(log_[j].azimuth), -PI, PI))
			if gap < deg_to_rad(70.0) - 1e-4:
				angle_ok = false
	_check("every new direction is ≥ 70° from the last two bursts", angle_ok)

	var delay_ok := true
	var far_delay_ok := true
	for b in log_:
		delay_ok = delay_ok and absf(float(b.delay) - float(b.dist) / 343.0) < 1e-5
		if b.kind == "far":
			far_delay_ok = far_delay_ok and b.delay >= 0.4 and b.delay <= 1.2
	_check("each sound is late by distance / 343 m/s", delay_ok)
	_check("far sounds lag their flash by 0.4–1.2 s", far_delay_ok)

	# A sound is queued until its delay has passed, then plays.
	var probe := _make_fireworks(3)
	probe.set_enabled(false)
	var info := probe.fire(DistantFireworks.Kind.FAR, true)
	var lag := float(info.delay)
	probe.advance(lag * 0.5)
	var held := probe.pending_sound_count() == 1
	probe.advance(lag * 0.5 + 0.02)
	_check("the far sound waits for its delay before it starts", held and probe.pending_sound_count() == 0)
	probe.queue_free()
	fw.queue_free()


## Fireworks bus: low-pass per burst (far stays low), reverb wet over dry,
## compressor and limiter in the chain, levels in their bands, Ambience slider.
func _bus_and_levels() -> void:
	var fw := _make_fireworks(5)
	fw.set_enabled(false)
	var idx := AudioServer.get_bus_index("Fireworks")
	_check("the Fireworks bus exists and is sent to Master", idx >= 0 and String(AudioServer.get_bus_send(idx)) == "Master")
	var kinds: Array[String] = []
	for i in AudioServer.get_bus_effect_count(idx):
		kinds.append(AudioServer.get_bus_effect(idx, i).get_class())
	_check("bus chain is low-pass, reverb, compressor, limiter",
		kinds == ["AudioEffectLowPassFilter", "AudioEffectReverb", "AudioEffectCompressor", "AudioEffectHardLimiter"])
	var reverb := AudioServer.get_bus_effect(idx, 1) as AudioEffectReverb
	_check("reverb is wet, so the wet signal is louder than the dry one", reverb.wet > reverb.dry)

	var far := fw.fire(DistantFireworks.Kind.FAR, false)
	var near := fw.fire(DistantFireworks.Kind.NEAR, false)
	_check("far bursts are low-passed at 800 Hz or less (%.0f Hz)" % float(far.cutoff),
		float(far.cutoff) <= 800.0 and float(far.cutoff) >= 300.0)
	_check("near bursts stay muffled, at 1.2 kHz or less (%.0f Hz)" % float(near.cutoff), float(near.cutoff) <= 1200.0)
	_check("far level sits at −24…−18 dB (%.1f dB)" % float(far.db), float(far.db) >= -24.0 and float(far.db) <= -18.0)
	_check("near level stays at −12…−9 dB (%.1f dB)" % float(near.db), float(near.db) >= -12.0 and float(near.db) <= -9.0)

	var saved_ambience: int = VrComfortSettings.audio_percent["ambience"]
	VrComfortSettings.audio_percent["ambience"] = 50
	VrComfortSettings.settings_changed.emit()
	var half := AudioServer.get_bus_volume_db(idx)
	_check("the Ambience slider at 50 %% brings the fireworks bus to about −6 dB (%.1f)" % half, absf(half + 6.02) < 0.1)
	VrComfortSettings.audio_percent["ambience"] = saved_ambience
	VrComfortSettings.settings_changed.emit()
	fw.queue_free()


## Quest budget: no dynamic light, at most four extra draw calls, two voices, and
## a fixed node pool that does not grow with bursts.
func _budget_and_pool() -> void:
	var fw := _make_fireworks(21)
	fw.set_enabled(true)
	var nodes_before := fw.pool_node_count()
	var max_draws := 0
	var max_voices := 0
	var max_glows := 0
	var lights := 0
	for _s in int(SIM_SECONDS / SIM_STEP):
		fw.advance(SIM_STEP)
		max_draws = maxi(max_draws, fw.visible_draw_calls())
		max_voices = maxi(max_voices, fw.active_voice_count())
		max_glows = maxi(max_glows, fw.active_glow_count())
		lights = maxi(lights, fw.light_count())
	_check("at most %d extra draw calls at once (max %d)" % [4, max_draws], max_draws <= 4)
	_check("no dynamic light is ever added (max %d)" % lights, lights == 0)
	_check("at most two sound voices at once (max %d)" % max_voices, max_voices <= 2)
	_check("at most three glows on screen at once (max %d)" % max_glows, max_glows <= 3)
	_check("the node pool does not grow with bursts (%d nodes)" % fw.pool_node_count(), fw.pool_node_count() == nodes_before)
	fw.queue_free()


## Settings > ACCESS at 0 % removes the glow of a burst; the sound stays, like the thunder.
func _flash_reduction() -> void:
	var fw := _make_fireworks(9)
	var saved: int = VrComfortSettings.flash_percent
	VrComfortSettings.flash_percent = 0
	var dark := fw.fire(DistantFireworks.Kind.NEAR, true)
	_check("with flash at 0 %, a near burst shows no glow", not dark.glow and fw.active_glow_count() == 0)
	_check("with flash at 0 %, its sound still plays", fw.pending_sound_count() == 1)
	VrComfortSettings.flash_percent = 100
	var bright := fw.fire(DistantFireworks.Kind.NEAR, true)
	_check("with flash at 100 %, a near burst shows its glow", bright.glow and fw.active_glow_count() >= 1)
	VrComfortSettings.flash_percent = saved
	fw.queue_free()


## Nothing fires until the run starts or after death; a wave start can bring a
## near burst a moment later (D10 hook), and only when the profile says so.
func _lifecycle_and_wave_hook() -> void:
	var fw := _make_fireworks(13)
	_simulate(fw, 300.0)
	_check("no burst before the run starts (menus, splash, intro)", fw.burst_log.is_empty())
	fw.set_enabled(true)
	fw.set_enabled(false)
	_simulate(fw, 300.0)
	_check("no burst after the run is stopped (death screen)", fw.burst_log.is_empty())

	var eager := PROFILE.duplicate() as WorldGenProfile
	eager.firework_wave_chance = 1.0
	fw.profile = eager
	fw.set_enabled(true)
	fw.on_wave_started(1, 6)
	_simulate(fw, 3.2)
	var near_after_wave := false
	for b in fw.burst_log:
		near_after_wave = near_after_wave or b.kind == "near"
	_check("a wave start can bring a near burst within 3 s (hook to D10)", near_after_wave)
	fw.queue_free()


## A fresh fireworks node on the shipped profile, with its own seeded random stream.
func _make_fireworks(seed_value: int) -> DistantFireworks:
	var player := Node3D.new()
	add_child(player)
	var fw := DistantFireworks.new()
	add_child(fw)
	fw.setup(PROFILE, player)
	fw.seed_rng(seed_value)
	return fw


func _simulate(fw: DistantFireworks, seconds: float) -> void:
	for _s in int(seconds / SIM_STEP):
		fw.advance(SIM_STEP)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
