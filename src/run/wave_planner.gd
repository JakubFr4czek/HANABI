@tool
class_name WavePlanner
extends RefCounted
## The pacing of the yōkai waves, with no nodes: when a wave opens, how many credits
## it spends, what each spawn costs, when the Oni is due. WaveDirector drives the
## game with it, and the editor simulation ("Symuluj run") drives the same code, so
## the panel's table is the game's curve (docs/SPAWN_PLAN.md §3).

enum State { BUILD, PEAK, RELAX }

const STATE_NAMES := {State.BUILD: "build", State.PEAK: "peak", State.RELAX: "relax"}

## What one [method step] reports back. kind is "" when nothing spawned this step.
## wave_started is 0 unless a wave opened this step; oni is true when the Oni is due.
var profile: WaveProfile
var rng := RandomNumberGenerator.new()
var t := 0.0
var wave := 0
var state := State.BUILD
## Credits the open wave can still spend.
var credits := 0.0
var wave_open := false
var _wave_timer := 0.0
var _rest_timer := 0.0
var _spawn_timer := 0.0
var _oni_next_at := 0.0
var _oni_pending := false


func _init(p_profile: WaveProfile = null, seed_value: int = 0) -> void:
	profile = p_profile if p_profile != null else WaveProfile.new()
	rng.seed = seed_value
	reset()


func reset() -> void:
	t = 0.0
	wave = 0
	state = State.BUILD
	credits = 0.0
	wave_open = false
	_wave_timer = 0.0
	_rest_timer = profile.initial_wave_delay
	_spawn_timer = 0.0
	_oni_next_at = profile.oni_first_seconds
	_oni_pending = false


## Director state of wave number [param n] (1-based). Deterministic: every
## peak_every_waves-th wave peaks and the wave after a peak relaxes.
func state_for_wave(n: int) -> int:
	var k := (n - 1) % profile.peak_every_waves
	if k == profile.peak_every_waves - 1:
		return State.PEAK
	if k == 0 and n > 1:
		return State.RELAX
	return State.BUILD


func cap() -> int:
	return profile.cap_at(t)


## Spawn gap in seconds at the current point of the ramp.
func stagger() -> float:
	var share := clampf(t / profile.ramp_seconds, 0.0, 1.0)
	return lerpf(profile.stagger_calm, profile.stagger_full, share)


func is_calm() -> bool:
	return t < profile.calm_seconds


## Advances the plan by [param dt] seconds. [param alive] is the live yōkai count and
## [param oni_alive] whether the Oni is on the field. The caller spawns what the
## result asks for.
func step(dt: float, alive: int, oni_alive: bool) -> Dictionary:
	var out := {"kind": "", "wave_started": 0, "oni": false}
	t += dt
	_wave_timer += dt
	if t >= _oni_next_at and not oni_alive:
		_oni_pending = true

	if not wave_open:
		_rest_timer -= dt
		if _rest_timer <= 0.0:
			_open_wave(out)

	if wave_open and credits >= profile.swarm_cost and alive < cap():
		_spawn_timer -= dt
		if _spawn_timer <= 0.0:
			_spawn_timer = stagger()
			out.kind = _pick_kind()
			credits -= profile.elite_cost if out.kind == "elite" else profile.swarm_cost

	if wave_open and credits < profile.swarm_cost and (alive == 0 or _wave_timer >= profile.max_wave_duration):
		_close_wave()
	return out


func _open_wave(out: Dictionary) -> void:
	wave += 1
	state = state_for_wave(wave)
	var mult := 1.0
	match state:
		State.PEAK:
			mult = profile.peak_budget_mult
		State.RELAX:
			mult = profile.relax_budget_mult
	credits = profile.wave_credits(t) * mult
	wave_open = true
	_wave_timer = 0.0
	_spawn_timer = 0.0
	out.wave_started = wave
	if state == State.PEAK and _oni_pending:
		out.oni = true
		_oni_pending = false
		_oni_next_at = t + profile.oni_interval


func _close_wave() -> void:
	wave_open = false
	_rest_timer = profile.rest_after(state, t)


## An elite when the credits cover it, the run is past elite_from_seconds, and the roll hits.
func _pick_kind() -> String:
	if credits >= profile.elite_cost and rng.randf() < profile.elite_chance(t):
		return "elite"
	return "swarm"


## Result of an editor simulation: one row per whole minute plus the totals.
class SimResult:
	extends RefCounted
	var minutes: Array[Dictionary] = []
	var spawned := 0
	var elites := 0
	var kills := 0
	var max_alive := 0
	var first_minute_spawned := 0
	var first_minute_max_alive := 0
	var waves := 0


## Runs the plan for [param seconds] with a stand-in player who kills one yōkai at a
## time (profile.sim_player_dps, sim_gap). Deterministic for a given seed. The cap
## counts yōkai only, as in the game; the Oni is a separate body.
static func simulate(p_profile: WaveProfile, seconds: float, seed_value: int = 7) -> SimResult:
	var res := SimResult.new()
	var plan := WavePlanner.new(p_profile, seed_value)
	var dt := 0.1
	var yokai: Array[float] = []   # remaining hp of each live yōkai, oldest first
	var oni_hp := 0.0              # > 0 while the Oni is on the field
	var engage := 0.0
	var counts := {"swarm": 0, "elite": 0}
	var minute_alive_sum := 0.0
	var minute_samples := 0
	var next_minute := 60.0
	var last_wave := 0
	while plan.t < seconds:
		var out := plan.step(dt, yokai.size(), oni_hp > 0.0)
		if out.kind != "":
			var elite: bool = out.kind == "elite"
			yokai.append(p_profile.hp_for(plan.wave, plan.t, elite))
			res.spawned += 1
			counts[out.kind] = int(counts[out.kind]) + 1
			if plan.t < 60.0:
				res.first_minute_spawned += 1
		if out.oni:
			oni_hp = p_profile.hp_for(plan.wave, plan.t) * p_profile.oni_hp_mult
		if plan.wave != last_wave:
			last_wave = plan.wave
			res.waves = plan.wave
		# Player: the oldest yōkai first, the Oni once the field is clear of yōkai.
		var target_hp := -1.0
		if not yokai.is_empty():
			target_hp = yokai[0]
		elif oni_hp > 0.0:
			target_hp = oni_hp
		if target_hp > 0.0:
			if engage > 0.0:
				engage -= dt
			else:
				var left := target_hp - p_profile.sim_player_dps * dt
				if not yokai.is_empty():
					yokai[0] = left
				else:
					oni_hp = left
				if left <= 0.0:
					if not yokai.is_empty():
						yokai.pop_front()
					else:
						oni_hp = 0.0
					res.kills += 1
					engage = p_profile.sim_gap
		res.max_alive = maxi(res.max_alive, yokai.size())
		if plan.t < 60.0:
			res.first_minute_max_alive = maxi(res.first_minute_max_alive, yokai.size())
		minute_alive_sum += yokai.size()
		minute_samples += 1
		if plan.t >= next_minute - 0.0001:
			res.minutes.append({"minute": int(round(next_minute / 60.0)), "wave": plan.wave,
				"alive": yokai.size(), "cap": plan.cap(), "spawned": res.spawned,
				"swarm": counts.swarm, "elite": counts.elite,
				"avg_alive": minute_alive_sum / maxf(minute_samples, 1)})
			minute_alive_sum = 0.0
			minute_samples = 0
			next_minute += 60.0
	res.elites = counts.elite
	return res
