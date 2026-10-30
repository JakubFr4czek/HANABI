class_name ElementBalance
extends RefCounted
## Every tunable number of the element system in one place (docs/ELEMENTS_PLAN.md,
## Phase E4). [ElementSystem] and [SkillTreeData] read these constants, and the
## headless balance model (tools/balance_model.gd) reads the very same ones, so
## "what the game does" and "what the balance table says" cannot drift apart.
##
## Reading guide: a school has two abilities (A / B). Names are
## <ABILITY>_<STAT>; a _T<n> suffix is the value after the node of that tier
## (cost and prerequisites live in [SkillTreeData]). Damage is in hit points of a
## wave yōkai (95 HP at the start, growing ~14% per wave and 0.4% per second;
## a solid sword cut is ~85) and is multiplied by the run's Razor Edge stacks,
## see [method ElementSystem.ability_power].

# --- Imbue (one constant for every school) -------------------------------------
## Seconds a torii gate keeps the blade imbued. THE one place for the 20 s.
const IMBUE_SECONDS := 20.0
## Node 1 ("school awakening") of every tree adds this many seconds.
const IMBUE_NODE_BONUS_SECONDS := 4.0
## The last seconds of an imbue pulse (blade, trail, wrist crest) as a warning.
const FADE_WARNING_SECONDS := 3.0
## Passing the same school's gate again tops the clock up and takes this share
## off both cooldowns.
const REFRESH_COOLDOWN_KEEP := 0.5

## Every direct ability hit is multiplied by the blade's Razor Edge factor and by
## (1 + this × (soul rank − 1)): yōkai gain ~14% HP per wave, the abilities must
## keep up. Rank 10 ≈ ×1.36.
const POWER_PER_RANK := 0.04

# --- Sakura 桜: pack cutter. Cheap volley, a barrier that keeps you alive. ------
const SENBONZAKURA_COOLDOWN := 4.0
const SENBONZAKURA_PETALS := 6
const SENBONZAKURA_PETALS_T2 := 7
const SENBONZAKURA_DAMAGE := 12.0
const SENBONZAKURA_DAMAGE_T1 := 15.0       # Petal Sense: +25%
const SENBONZAKURA_PIERCE := 2
const SENBONZAKURA_PIERCE_T2 := 99
const SENBONZAKURA_FAN_DEGREES := 32.0
const SENBONZAKURA_SPEED := 12.0
const SENBONZAKURA_LIFETIME := 0.65
const HANAMAI_COOLDOWN := 13.0
const HANAMAI_PETALS := 4
const HANAMAI_DURATION := 6.0
const HANAMAI_DURATION_T3 := 8.5
const HANAMAI_DAMAGE := 7.0                # per petal contact
const HANAMAI_TICK := 0.45                 # seconds between contacts on one enemy
const HANAMAI_RADIUS := 1.2
const HANAMAI_DAMAGE_TAKEN := 0.70         # incoming damage multiplier
const HANAMAI_DAMAGE_TAKEN_T3 := 0.55
const LIFE_BLOOM_HEAL_HIT := 4.0
const LIFE_BLOOM_HEAL_KILL := 12.0
const KAGEYOSHI_DAMAGE := 100.0            # Senbonzakura during Hanamai: orbit detonates
const KAGEYOSHI_RADIUS := 3.2

# --- Storm 雷: burst and mobility. Hits many, hits first, gets out. -----------------
const RAIKIRI_COOLDOWN := 3.5
const RAIKIRI_COOLDOWN_T2 := 2.5
const RAIKIRI_PRIMARY_DAMAGE := 45.0
const RAIKIRI_CHAIN_DAMAGE := 24.0
const RAIKIRI_CHAIN_TARGETS := 3
const RAIKIRI_CHAIN_TARGETS_T1 := 5
const RAIKIRI_RANGE := 8.0
const RAIKIRI_CHAIN_RADIUS := 5.0
const RAIKIRI_STUN_T2 := 1.0
const SHIDEN_COOLDOWN := 8.0
const SHIDEN_DISTANCE := 4.2
const SHIDEN_DISTANCE_T3 := 6.0
const SHIDEN_STAGGER := 1.4
const SHIDEN_STAGGER_T3 := 2.2
const SHIDEN_RADIUS := 2.8
const SHIDEN_DAMAGE := 15.0
const OVERCHARGE_DAMAGE := 14.0
const OVERCHARGE_COOLDOWN := 0.3           # between arcs
const IKAZUCHI_DURATION := 4.0
const IKAZUCHI_DAMAGE := 20.0              # per 0.5 s while a yōkai stands on the line

# --- Ink 墨: control. Slows, holds, makes the ground yours. ------------------------
const SUMI_COOLDOWN := 5.0
const SUMI_RANGE := 4.5
const SUMI_HALF_DEGREES := 30.0
const SUMI_HALF_DEGREES_T2 := 45.0
const SUMI_DAMAGE := 7.0
const SUMI_SLOW_SECONDS := 5.0
const SUMI_SLOW_SCALE := 0.40              # speed multiplier while slowed
const SUMI_SLOW_SCALE_T1 := 0.25
const SUMI_POOL_RADIUS := 2.2
const SUMI_POOL_SECONDS := 5.0
const SUMI_POOL_DPS := 8.0
const SUMI_POOL_DPS_T2 := 16.0
const KAGE_NAWA_COOLDOWN := 10.0
const KAGE_NAWA_TARGETS := 3
const KAGE_NAWA_TARGETS_T3 := 5
const KAGE_NAWA_RANGE := 7.0
const KAGE_NAWA_DAMAGE := 20.0
const KAGE_NAWA_ROOT_SECONDS := 2.8
const KAGE_NAWA_ROOT_SCALE := 0.25
const KAGE_NAWA_PULL := 1.5
const DRAGON_DAMAGE_MULTIPLIER := 1.35
const ABYSSAL_SPEED_MULTIPLIER := 1.2

# --- Shadow 影: the duelist. Misdirect, appear behind, one cut that counts. ---------
const KAGEMUSHA_COOLDOWN := 9.0
const KAGEMUSHA_SECONDS := 4.0
const KAGEMUSHA_SECONDS_T1 := 6.0
const KAGEMUSHA_HITS := 2
const YAMI_COOLDOWN := 6.5
const YAMI_COOLDOWN_T3 := 5.0
const YAMI_RANGE := 4.5
const YAMI_RANGE_T3 := 6.5
const YAMI_CRIT_MULTIPLIER := 2.2          # next sword cut within the window
const YAMI_CRIT_SECONDS := 2.5
const DECOY_EXPLOSION_DAMAGE := 60.0
const DECOY_EXPLOSION_RADIUS := 3.0
const BACKSTAB_MULTIPLIER := 3.0           # was 2.5 + a bonus Ofuda (D1: Ofuda come from hokora only)
const SHADOW_CLONES := 2

# --- Kirisute / tachi (D4): the tier-5 finisher of every school ---------------------
## Real m/s of the blade relative to the yōkai at contact for a cut to split it.
const KIRISUTE_MIN_SPEED := 8.0
## Cosine of the edge against the motion (1 = edge square on): only clean cuts split.
const KIRISUTE_MIN_ALIGNMENT := 0.85
## An elite takes this share of its max HP extra; it splits only when that kills it.
const KIRISUTE_ELITE_FRACTION := 0.5
## Pieces alive at once (the oldest dissolves first) and cuts that may split in one physics frame.
const KIRISUTE_MAX_PIECES := 8
const KIRISUTE_CUTS_PER_FRAME := 2
## Seconds a piece lies before it dissolves into petals; its cut glows at full
## strength for a moment and then fades over KIRISUTE_CAP_FADE_SECONDS.
const KIRISUTE_PIECE_SECONDS := 2.6
const KIRISUTE_DISSOLVE_SECONDS := 0.8
const KIRISUTE_CAP_FADE_SECONDS := 1.6
## An Oni takes a glowing wound instead of splitting; it stays open this long.
const KIRISUTE_WOUND_SECONDS := 2.0

# --- XP and skill points (D12): enemies give XP, every level gives one point ----------
## XP per kill, the sum of the soul orbs the kill drops (orbs × value per orb).
## Yōkai: 4 orbs × 6. Elite: 4 × 12 (twice a yōkai, so it is worth turning to).
## The Oni: 8 × 8.
const XP_YOKAI := 24
const XP_ELITE := 48
const XP_ONI := 64
const ORBS_PER_KILL := 4
## XP to climb from level L to L+1: linear, 150 + 45 × (L − 1). Gives one skill point
## per level (SkillTreeData costs 1/1/1/2/3). Measured in tools/balance_model.gd.
const XP_FIRST_LEVEL := 60
const XP_LEVEL_STEP := 40

# --- Hokora shrine and the yellow Ofuda choice (D12) ----------------------------------
## Walking into the shrine's reach is not enough: the player places a hand on the
## offering table (no katana in it) within HOKORA_HAND_RADIUS, standing within
## HOKORA_TOUCH_RADIUS of the altar. A living yōkai within HOKORA_REFUSE_ENEMY_RADIUS
## of the player refuses the touch, so the choice never opens in a fight by accident.
const HOKORA_HAND_RADIUS := 0.35
const HOKORA_TOUCH_RADIUS := 2.2
const HOKORA_REFUSE_ENEMY_RADIUS := 3.5
## The forest is cut into square slots of profile.shrine_slot_size metres on a
## side, and a slot holds one shrine with profile.shrine_slot_chance (both in the
## WorldGenProfile: placement is world generation, not balance). The player only
## meets a shrine inside the spawn radius, a 68 m band across the walk.
## So a shrine is met about every S² / (68 × chance × valid share) metres (see
## tools/balance_model.gd hokora_spacing): ~215 m, about 80 s of walking at an
## average pace, roughly 8× rarer than the 18–32 m torii spacing.
## Share of slots whose candidates include a spot that passes the placement rules
## (the balance model's spacing). Shrines stand on footpaths (uwaga 8), and every slot
## that holds one finds a valid spur spot among its path samples. tests/hokora_test.gd
## walks 1.5 km and meets 9 shrines, which the 5–11 range there accepts.
const HOKORA_VALID_SHARE := 1.0
## The first shrine stands this far in front of the spawn, so the economy starts
## inside the first minute (≈12 s of walking) and the mechanic is in view at once.
const HOKORA_OPENING_DISTANCE := 30.0
## A shrine is built when the player comes this close and freed past the cull
## distance (the fog hides everything past 10.5 m; the halo shows to ~35 m).
const HOKORA_SPAWN_RADIUS := 34.0
const HOKORA_CULL_RADIUS := 60.0
## Keep shrines away from torii gates (metres) and from the spawn ring.
const HOKORA_TORII_CLEARANCE := 10.0
const HOKORA_MIN_START_DISTANCE := 20.0

# --- Shrine buffs (D12): one of three yellow Ofuda, a minute long --------------------
## Speed: walking speed × this, for BUFF_SECONDS. Stacks with the ink boost and the
## walking pace of Settings (both multiply).
const BUFF_SPEED_MULTIPLIER := 1.2
## Damage: every blade and ability hit × this, for BUFF_SECONDS.
const BUFF_DAMAGE_MULTIPLIER := 1.2
const BUFF_SECONDS := 60.0
## Heal: a share of max HP at once, then a share of max HP over BUFF_HEAL_SECONDS.
## Max HP never grows, and a heal at full health adds nothing.
const BUFF_HEAL_NOW := 0.35
const BUFF_HEAL_OVER_TIME := 0.15
const BUFF_HEAL_SECONDS := 10.0

# --- Counter ring (D17, docs/ELEMENT_COUNTERS.md): who hurts whom more ----------------
## Each school beats exactly one other and is beaten by exactly one:
## Ink gasi Storm, Storm rozwiewa Sakurę, Sakura przebija Shadow, Shadow omija Ink.
## The two pairs across the ring (Ink–Sakura, Storm–Shadow) are neutral.
const BEATS := {
	Elements.INK: Elements.STORM,
	Elements.STORM: Elements.SAKURA,
	Elements.SAKURA: Elements.SHADOW,
	Elements.SHADOW: Elements.INK,
}
## Damage multiplier of an attack on a defender it beats, the same school, and any other pair.
## Plain steel (Elements.NONE) and the non-school "physical" are always neutral.
const COUNTER_MULTIPLIER := 1.5
const SAME_MULTIPLIER := 0.5
const NEUTRAL_MULTIPLIER := 1.0
## A countering blade hit holds the world this much longer (seconds, capped by the hit-stop limit).
const COUNTER_HIT_STOP_EXTRA := 0.02


## Damage multiplier of an attack by [param attacker] on a body of [param defender].
## The one place where the element table turns into numbers (enemy profiles call it).
static func matchup(attacker: String, defender: String) -> float:
	if not Elements.COMBAT_ELEMENTS.has(attacker) or not Elements.COMBAT_ELEMENTS.has(defender):
		return NEUTRAL_MULTIPLIER
	if attacker == defender:
		return SAME_MULTIPLIER
	if beats(attacker, defender):
		return COUNTER_MULTIPLIER
	return NEUTRAL_MULTIPLIER


## True when [param attacker] is the school on the ring that [param defender] loses to.
static func beats(attacker: String, defender: String) -> bool:
	return String(BEATS.get(attacker, Elements.NONE)) == defender


## The school that beats [param defender] (for a weakness label, or the matchup test).
static func countered_by(defender: String) -> String:
	for attacker: String in BEATS:
		if BEATS[attacker] == defender:
			return attacker
	return Elements.NONE

