@tool
class_name WaveProfile
extends Resource
## Every number of the yōkai waves (docs/SPAWN_PLAN.md, docs/SPAWN_TOOL.md): pacing,
## the credit budget per wave, the director's peak/relax cycle, the caps, the spawn
## ring and the enemy scaling. The game reads nothing else. Presets live in
## data/waves/*.tres (written by tools/waves/make_presets.gd), and the "Fale" dock
## in the editor edits the same resource.

## The Quest 3 share of the stressed run: 8 yōkai draw ~338 calls against a 345
## budget (RunPerfBudget). A cap above this is a warning in validate().
const QUEST_YOKAI_CAP := 8
const PRESET_DIR := "res://data/waves"
## Launch argument (after `--`) that plays the 3-minute demo profile.
const DEMO_FLAG := "--demo"

const GROUP_PACING := "Pacing"
const GROUP_BUDGET := "Budget"
const GROUP_DIRECTOR := "Director"
const GROUP_CAPS := "Caps"
const GROUP_RING := "Spawn ring"
const GROUP_ENEMIES := "Enemies"
const GROUP_SCALING := "Scaling"
const GROUP_ONI := "Oni"
const GROUP_ELEMENTS := "Elements"
const GROUP_SIM := "Simulation"

## Seconds of run time before the first yōkai of the calm opening wave.
@export_group(GROUP_PACING)
@export_range(0.0, 300.0, 1.0, "suffix:s") var calm_seconds := 75.0
## Run time over which the budget and the rest times ease to their full values.
@export_range(60.0, 1200.0, 1.0, "suffix:s") var ramp_seconds := 480.0
@export_range(0.0, 30.0, 0.1, "suffix:s") var initial_wave_delay := 5.0
@export_range(0.5, 60.0, 0.1, "suffix:s") var rest_calm := 14.0
@export_range(0.5, 30.0, 0.1, "suffix:s") var rest_full := 2.5
## A wave closes after this long even if a yōkai is still alive.
@export_range(5.0, 60.0, 0.5, "suffix:s") var max_wave_duration := 18.0
@export_range(0.1, 3.0, 0.05, "suffix:s") var stagger_calm := 1.3
@export_range(0.1, 3.0, 0.05, "suffix:s") var stagger_full := 0.35

## Credits each wave may spend on yōkai, from the first wave to the ramp end.
@export_group(GROUP_BUDGET)
@export_range(0.0, 40.0, 0.5) var wave_credits_start := 1.0
@export_range(0.0, 60.0, 0.5) var wave_credits_full := 18.0
## Shapes the credit curve over the ramp (x = run time / ramp, y = share). Empty = linear.
@export var budget_curve: Curve
@export_range(0.5, 10.0, 0.5) var swarm_cost := 1.0
@export_range(0.5, 20.0, 0.5) var elite_cost := 4.0

## The director's cycle: every peak_every_waves-th wave is a PEAK, the one after
## it a RELAX, the rest BUILD.
@export_group(GROUP_DIRECTOR)
@export_range(2, 10, 1) var peak_every_waves := 3
@export_range(0.5, 3.0, 0.05) var peak_budget_mult := 1.5
@export_range(0.1, 1.0, 0.05) var relax_budget_mult := 0.5
@export_range(0.1, 2.0, 0.05) var peak_rest_mult := 0.5
@export_range(0.5, 4.0, 0.05) var relax_rest_mult := 1.8

## One live cap at the start, one more every cap_step_seconds, up to cap_hard.
@export_group(GROUP_CAPS)
@export_range(1, 12, 1) var cap_start := 2
@export_range(10.0, 300.0, 1.0, "suffix:s") var cap_step_seconds := 45.0
@export_range(1, 16, 1) var cap_hard := 8

## Where yōkai appear: a ring round the player, outside the camera's view cone.
@export_group(GROUP_RING)
@export_range(3.0, 20.0, 0.1, "suffix:m") var ring_min := 7.6
@export_range(3.0, 20.0, 0.1, "suffix:m") var ring_max := 10.8
@export_range(5.0, 40.0, 0.5, "suffix:m") var straggler_distance := 17.0
## Half the angle, in degrees, kept clear around the view direction.
@export_range(30.0, 90.0, 1.0, "suffix:°") var view_half_angle := 60.0
## Radius of the clearance sphere checked against the world geometry.
@export_range(0.2, 1.5, 0.05, "suffix:m") var clearance_radius := 0.5

@export_group(GROUP_ENEMIES)
## No elites before this run time.
@export_range(0.0, 900.0, 1.0, "suffix:s") var elite_from_seconds := 150.0
## Elite chance at the ramp end (linear from elite_from_seconds).
@export_range(0.0, 1.0, 0.01) var elite_chance_full := 0.25

@export_group(GROUP_SCALING)
@export_range(10.0, 500.0, 1.0) var base_hp := 95.0
@export_range(0.5, 6.0, 0.05) var base_speed := 2.05
@export_range(1.0, 60.0, 0.5) var base_damage := 12.0
@export_range(0.0, 1.0, 0.01) var hp_per_wave := 0.14
@export_range(0.0, 0.05, 0.001) var hp_per_second := 0.004
@export_range(0.0, 0.5, 0.01) var speed_per_wave := 0.06
@export_range(0.0, 0.05, 0.0001) var speed_per_second := 0.0015
@export_range(1.0, 6.0, 0.05) var speed_cap := 3.15
@export_range(0.0, 0.5, 0.01) var damage_per_wave := 0.08
@export_range(1.0, 5.0, 0.05) var elite_hp_mult := 2.35
## Strength of the ordinary (swarm) yōkai, on top of the scaling above. Elites and the
## Oni are not multiplied by these: they keep the numbers above. The D12 economy model
## (tools/balance_model.gd) still runs on the stock HP: its master-technique window
## (6–10 min) does not survive any HP increase, so that window needs a design call.
@export_range(0.5, 3.0, 0.05) var swarm_hp_mult := 1.4
@export_range(0.5, 3.0, 0.05) var swarm_damage_mult := 1.25

@export_group(GROUP_ONI)
@export_range(0.0, 900.0, 1.0, "suffix:s") var oni_first_seconds := 180.0
@export_range(20.0, 900.0, 1.0, "suffix:s") var oni_interval := 200.0
@export_range(1.0, 20.0, 0.1) var oni_hp_mult := 6.5

## Only the editor simulation uses these: a stand-in player who kills one yōkai
## at a time. Mirrors the "average" profile of tools/balance_model.gd.
## Which yōkai carry a school (D17, docs/ELEMENT_COUNTERS.md). The plain share (no
## school) eases from start to full over the ramp; the rest is split by the four weights.
## Elites always carry a school and do not use these weights.
@export_group(GROUP_ELEMENTS)
@export_range(0.0, 1.0, 0.01) var plain_share_start := 0.70
@export_range(0.0, 1.0, 0.01) var plain_share_full := 0.35
@export_range(0.0, 5.0, 0.05) var weight_sakura := 1.0
@export_range(0.0, 5.0, 0.05) var weight_storm := 1.0
@export_range(0.0, 5.0, 0.05) var weight_ink := 1.0
@export_range(0.0, 5.0, 0.05) var weight_shadow := 1.0

@export_group(GROUP_SIM)
@export_range(1.0, 300.0, 1.0) var sim_player_dps := 51.0
@export_range(0.0, 5.0, 0.1, "suffix:s") var sim_gap := 1.4


## Credits a wave of [param t] run seconds may spend (before its director multiplier).
func wave_credits(t: float) -> float:
	if t < calm_seconds:
		return wave_credits_start
	var share := ramp_share(t)
	if budget_curve != null:
		share = budget_curve.sample_baked(share)
	return lerpf(wave_credits_start, wave_credits_full, share)


## 0 at the end of the calm opening, 1 at ramp_seconds.
func ramp_share(t: float) -> float:
	var span := maxf(ramp_seconds - calm_seconds, 1.0)
	return clampf((t - calm_seconds) / span, 0.0, 1.0)


## Seconds of rest after a wave of the given director state.
func rest_after(state: int, t: float) -> float:
	var rest := lerpf(rest_calm, rest_full, ramp_share(t))
	match state:
		WavePlanner.State.PEAK:
			return rest * peak_rest_mult
		WavePlanner.State.RELAX:
			return rest * relax_rest_mult
	return rest


## Live yōkai allowed at run time [param t].
func cap_at(t: float) -> int:
	var stepped := cap_start + int(floor(maxf(t, 0.0) / cap_step_seconds))
	return clampi(stepped, cap_start, cap_hard)


func elite_chance(t: float) -> float:
	if t < elite_from_seconds:
		return 0.0
	var span := maxf(ramp_seconds - elite_from_seconds, 1.0)
	return clampf(elite_chance_full * (t - elite_from_seconds) / span, 0.0, elite_chance_full)


## Share of swarm yōkai with no school at run time [param t] (D17).
func plain_share(t: float) -> float:
	return lerpf(plain_share_start, plain_share_full, ramp_share(t))


## Weights of the four schools for a swarm yōkai at run time [param t] (the plain share
## is not in here: see [method plain_share]).
func school_weights() -> Dictionary:
	return {
		Elements.SAKURA: maxf(weight_sakura, 0.0),
		Elements.STORM: maxf(weight_storm, 0.0),
		Elements.INK: maxf(weight_ink, 0.0),
		Elements.SHADOW: maxf(weight_shadow, 0.0),
	}


## Rolls the school of one swarm yōkai spawned at run time [param t]: plain with the
## plain share, otherwise a school by weight. Elements.NONE when every weight is zero.
func roll_swarm_element(t: float, rng: RandomNumberGenerator) -> String:
	if rng.randf() < plain_share(t):
		return Elements.NONE
	var weights := school_weights()
	var total := 0.0
	for school: String in weights:
		total += float(weights[school])
	if total <= 0.0:
		return Elements.NONE
	var pick := rng.randf() * total
	for school: String in weights:
		pick -= float(weights[school])
		if pick < 0.0:
			return school
	return Elements.NONE


func hp_for(wave_num: int, t: float, elite: bool = false) -> float:
	var w := maxi(wave_num, 1)
	var hp := base_hp * (1.0 + hp_per_wave * float(w - 1) + t * hp_per_second)
	return hp * elite_hp_mult if elite else hp


## HP of an ordinary yōkai: the scaled HP times [member swarm_hp_mult].
func swarm_hp_for(wave_num: int, t: float) -> float:
	return hp_for(wave_num, t) * swarm_hp_mult


func speed_for(wave_num: int, t: float) -> float:
	var w := maxi(wave_num, 1)
	return clampf(base_speed + speed_per_wave * float(w - 1) + t * speed_per_second, base_speed, speed_cap)


## Damage of an elite or the Oni's base (without the swarm multiplier).
func damage_for(wave_num: int) -> float:
	return base_damage * (1.0 + damage_per_wave * float(maxi(wave_num, 1) - 1))


## Damage of an ordinary yōkai: the scaled damage times [member swarm_damage_mult].
func swarm_damage_for(wave_num: int) -> float:
	return damage_for(wave_num) * swarm_damage_mult


## Errors (the game refuses to start on them) and warnings (shown in the panel),
## in the same form as WorldGenProfile.validate(). Empty list = clean.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if cap_start > cap_hard:
		out.append("BŁĄD: cap startowy (%d) jest wyższy niż cap twardy (%d)." % [cap_start, cap_hard])
	if ring_min >= ring_max:
		out.append("BŁĄD: pierścień spawnu: min (%.1f m) musi być mniejszy niż max (%.1f m)." % [ring_min, ring_max])
	if peak_every_waves < 2:
		out.append("BŁĄD: szczyt co %d fale nie zostawia fali na oddech (minimum 2)." % peak_every_waves)
	if ramp_seconds <= elite_from_seconds:
		out.append("BŁĄD: elity startują po %.0f s, a rampa kończy się po %.0f s." % [elite_from_seconds, ramp_seconds])
	if wave_credits_full < wave_credits_start:
		out.append("BŁĄD: pełny budżet fali (%.1f) jest niższy niż startowy (%.1f)." % [wave_credits_full, wave_credits_start])
	if cap_hard > QUEST_YOKAI_CAP:
		out.append("UWAGA: cap %d przekracza zmierzoną bazę Quest (%d yōkai ≈ 338 wywołań z 345). Sprawdź draw calls." % [cap_hard, QUEST_YOKAI_CAP])
	if swarm_cost > wave_credits_start:
		out.append("UWAGA: pierwsza fala nie kupi ani jednego yōkai (koszt %.1f, budżet %.1f)." % [swarm_cost, wave_credits_start])
	return out


## Presets as (file name, label). The label is the name shown in the panel.
static func preset_list() -> Array[Array]:
	return [
		["demo", "Demo 3 min"],
		["demo_gentle", "Demo – łagodny"],
		["default", "Domyślny"],
		["hardcore", "Hardcore"],
	]


static func preset_path(file: String) -> String:
	return "%s/%s.tres" % [PRESET_DIR, file]


## The profile the game uses when none is set. Same numbers as the "Domyślny" preset.
static func load_default() -> WaveProfile:
	var res := load(preset_path("default")) as WaveProfile
	return res if res != null else WaveProfile.new()


## The profile of a launch: the 3-minute demo when the game starts with `-- --demo`
## (docs/SPAWN_PLAN.md §N7), otherwise the default. Read once per WaveDirector.
static func load_for_launch() -> WaveProfile:
	if OS.get_cmdline_user_args().has(DEMO_FLAG):
		var demo := load(preset_path("demo")) as WaveProfile
		if demo != null:
			return demo
	return load_default()
