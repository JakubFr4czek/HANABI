class_name SkillTreeData
extends RefCounted
## Per-element skill trees (docs/ELEMENTS_PLAN.md section (d), Phase E2c; D12 currency).
##
## Four trees (Sakura, Storm, Ink, Shadow) of five nodes each. Node 1 is the
## school awakening, Nodes 2/3 augment Ability 1/2, Node 4 is a passive that
## needs Node 2 OR Node 3, and Node 5 is the master technique needing Node 4.
## Costs are 1/1/1/2/3 skill points (D12): every level of the run gives one point,
## so the path to the master technique (Node 1, 2 or 3, 4, 5) costs 7. Points come
## from XP (enemies drop soul orbs), see ElementBalance.XP_* and
## tools/balance_model.gd for the numbers the tests assert (about 5 nodes by minute 8
## for an average run, master by minute 8–10 on a good run).
## All numeric effects come from [ElementBalance].
##
## This class is pure data + unlock state: it never touches the scene tree.
## [RunGame] owns the skill-point wallet and spends through [method try_unlock];
## [ElementSystem] reads numeric ability parameters through
## [method effect_value], so an unlock changes the ability it names.
## Unlock state is per-run: [method reset] clears it (called on run start
## and on player death).

## Seconds a school imbue lasts once its Node 1 is bought (20 s + the node bonus).
const IMBUE_T1 := ElementBalance.IMBUE_SECONDS + ElementBalance.IMBUE_NODE_BONUS_SECONDS

const REASON_OK := "ok"
const REASON_UNKNOWN_NODE := "unknown_node"
const REASON_ALREADY_UNLOCKED := "already_unlocked"
const REASON_PREREQUISITE := "missing_prerequisite"
const REASON_POINTS := "insufficient_points"

## One entry per node. "requires_all" must all be unlocked; "requires_any"
## needs at least one unlocked (empty = no constraint). "effects" maps an
## ElementSystem parameter key to its upgraded value for that node's element.
const NODES: Array[Dictionary] = [
	# --- Sakura (桜) ---------------------------------------------------------
	{
		"id": "petal_sense", "element": Elements.SAKURA, "tier": 1,
		"kanji": "花気", "title": "PETAL SENSE",
		"subtitle": "Senbonzakura +25% damage · imbue 24 s",
		"cost": 1, "requires_all": [], "requires_any": [],
		"effects": {"senbonzakura_damage": ElementBalance.SENBONZAKURA_DAMAGE_T1, "imbue_duration": IMBUE_T1},
	},
	{
		"id": "razor_petals", "element": Elements.SAKURA, "tier": 2,
		"kanji": "刃花", "title": "RAZOR PETALS",
		"subtitle": "Senbonzakura: 7 petals, pierces all",
		"cost": 1, "requires_all": ["petal_sense"], "requires_any": [],
		"effects": {"senbonzakura_petal_count": ElementBalance.SENBONZAKURA_PETALS_T2, "senbonzakura_pierce": ElementBalance.SENBONZAKURA_PIERCE_T2},
	},
	{
		"id": "hanami_storm", "element": Elements.SAKURA, "tier": 3,
		"kanji": "花宴", "title": "STORM OF HANAMI",
		"subtitle": "Hanamai 8.5 s · damage taken −45%",
		"cost": 1, "requires_all": ["petal_sense"], "requires_any": [],
		"effects": {"hanamai_duration": ElementBalance.HANAMAI_DURATION_T3, "incoming_damage_multiplier": ElementBalance.HANAMAI_DAMAGE_TAKEN_T3},
	},
	{
		"id": "life_bloom", "element": Elements.SAKURA, "tier": 4,
		"kanji": "命咲", "title": "LIFE BLOOM",
		"subtitle": "Sakura cuts heal 4 HP · kills heal 12 HP",
		"cost": 2, "requires_all": [], "requires_any": ["razor_petals", "hanami_storm"],
		"effects": {"heal_on_hit": ElementBalance.LIFE_BLOOM_HEAL_HIT, "heal_on_kill": ElementBalance.LIFE_BLOOM_HEAL_KILL},
	},
	{
		"id": "senbonzakura_kageyoshi", "element": Elements.SAKURA, "tier": 5,
		"kanji": "景厳", "title": "SENBONZAKURA KAGEYOSHI",
		"subtitle": "Kageyoshi burst (100 dmg) · Hanadachi: cuts split yōkai",
		"cost": 3, "requires_all": ["life_bloom"], "requires_any": [],
		"effects": {"kageyoshi_burst_damage": ElementBalance.KAGEYOSHI_DAMAGE, "kirisute": true},
	},
	# --- Storm (雷) ----------------------------------------------------------
	{
		"id": "static_conduit", "element": Elements.STORM, "tier": 1,
		"kanji": "導電", "title": "STATIC CONDUIT",
		"subtitle": "Raikiri chains to 5 · imbue 24 s",
		"cost": 1, "requires_all": [], "requires_any": [],
		"effects": {"raikiri_chain_targets": ElementBalance.RAIKIRI_CHAIN_TARGETS_T1, "imbue_duration": IMBUE_T1},
	},
	{
		"id": "thunder_splitter", "element": Elements.STORM, "tier": 2,
		"kanji": "雷破", "title": "THUNDER SPLITTER",
		"subtitle": "Raikiri cooldown 2.5 s · primary target stunned",
		"cost": 1, "requires_all": ["static_conduit"], "requires_any": [],
		"effects": {"cooldown_ability_1": ElementBalance.RAIKIRI_COOLDOWN_T2, "raikiri_stun_duration": ElementBalance.RAIKIRI_STUN_T2},
	},
	{
		"id": "flash_stride", "element": Elements.STORM, "tier": 3,
		"kanji": "瞬歩", "title": "FLASH STRIDE",
		"subtitle": "Shiden dash 6.0 m · stagger 2.2 s",
		"cost": 1, "requires_all": ["static_conduit"], "requires_any": [],
		"effects": {"shiden_distance": ElementBalance.SHIDEN_DISTANCE_T3, "shiden_stagger": ElementBalance.SHIDEN_STAGGER_T3},
	},
	{
		"id": "overcharge", "element": Elements.STORM, "tier": 4,
		"kanji": "過負荷", "title": "OVERCHARGE",
		"subtitle": "Storm cuts arc 14 dmg to a nearby yōkai",
		"cost": 2, "requires_all": [], "requires_any": ["thunder_splitter", "flash_stride"],
		"effects": {"overcharge_damage": ElementBalance.OVERCHARGE_DAMAGE},
	},
	{
		"id": "ikazuchi_avatar", "element": Elements.STORM, "tier": 5,
		"kanji": "雷神", "title": "IKAZUCHI AVATAR",
		"subtitle": "Shiden barrier 4 s · Raidachi: cuts split yōkai",
		"cost": 3, "requires_all": ["overcharge"], "requires_any": [],
		"effects": {"shiden_barrier_duration": ElementBalance.IKAZUCHI_DURATION, "shiden_barrier_damage": ElementBalance.IKAZUCHI_DAMAGE, "kirisute": true},
	},
	# --- Ink (墨) ------------------------------------------------------------
	{
		"id": "sumi_mastery", "element": Elements.INK, "tier": 1,
		"kanji": "墨法", "title": "SUMI MASTERY",
		"subtitle": "Ink slow 75% · imbue 24 s",
		"cost": 1, "requires_all": [], "requires_any": [],
		"effects": {"ink_slow_scale": ElementBalance.SUMI_SLOW_SCALE_T1, "imbue_duration": IMBUE_T1},
	},
	{
		"id": "splatter_tide", "element": Elements.INK, "tier": 2,
		"kanji": "墨浪", "title": "SPLATTER TIDE",
		"subtitle": "Sumi-gaeshi 90° cone · ink damage ×2",
		"cost": 1, "requires_all": ["sumi_mastery"], "requires_any": [],
		"effects": {"sumi_cone_half_deg": ElementBalance.SUMI_HALF_DEGREES_T2, "ink_dps": ElementBalance.SUMI_POOL_DPS_T2},
	},
	{
		"id": "black_bind", "element": Elements.INK, "tier": 3,
		"kanji": "黒縛", "title": "BLACK BIND",
		"subtitle": "Kage-nawa snares 5 · pulls into melee",
		"cost": 1, "requires_all": ["sumi_mastery"], "requires_any": [],
		"effects": {"kage_nawa_targets": ElementBalance.KAGE_NAWA_TARGETS_T3},
	},
	{
		"id": "dragon_calligraphy", "element": Elements.INK, "tier": 4,
		"kanji": "墨龍", "title": "DRAGON CALLIGRAPHY",
		"subtitle": "Yōkai standing in ink take +35% sword damage",
		"cost": 2, "requires_all": [], "requires_any": ["splatter_tide", "black_bind"],
		"effects": {"dragon_damage_multiplier": ElementBalance.DRAGON_DAMAGE_MULTIPLIER},
	},
	{
		"id": "abyssal_sea", "element": Elements.INK, "tier": 5,
		"kanji": "墨海", "title": "ABYSSAL SEA",
		"subtitle": "Abyssal ward +20% speed · Sumidachi: cuts split yōkai",
		"cost": 3, "requires_all": ["dragon_calligraphy"], "requires_any": [],
		"effects": {"abyssal_speed_multiplier": ElementBalance.ABYSSAL_SPEED_MULTIPLIER, "kirisute": true},
	},
	# --- Shadow (影) ----------------------------------------------------------
	{
		"id": "night_veil", "element": Elements.SHADOW, "tier": 1,
		"kanji": "夜帳", "title": "NIGHT VEIL",
		"subtitle": "Kagemusha decoy 6.0 s · imbue 24 s",
		"cost": 1, "requires_all": [], "requires_any": [],
		"effects": {"kagemusha_duration": ElementBalance.KAGEMUSHA_SECONDS_T1, "imbue_duration": IMBUE_T1},
	},
	{
		"id": "phantom_retaliation", "element": Elements.SHADOW, "tier": 2,
		"kanji": "幻影", "title": "PHANTOM RETALIATION",
		"subtitle": "Decoy expiry explodes for 60 dmg",
		"cost": 1, "requires_all": ["night_veil"], "requires_any": [],
		"effects": {"decoy_explosion_damage": ElementBalance.DECOY_EXPLOSION_DAMAGE},
	},
	{
		"id": "umbral_reach", "element": Elements.SHADOW, "tier": 3,
		"kanji": "影界", "title": "UMBRAL REACH",
		"subtitle": "Yami-watari range 6.5 m · cooldown 5.0 s",
		"cost": 1, "requires_all": ["night_veil"], "requires_any": [],
		"effects": {"yami_range": ElementBalance.YAMI_RANGE_T3, "cooldown_ability_2": ElementBalance.YAMI_COOLDOWN_T3},
	},
	{
		"id": "backstab_execution", "element": Elements.SHADOW, "tier": 4,
		"kanji": "暗殺", "title": "BACKSTAB EXECUTION",
		"subtitle": "Rear strikes ×3 damage",
		"cost": 2, "requires_all": [], "requires_any": ["phantom_retaliation", "umbral_reach"],
		"effects": {"backstab_multiplier": ElementBalance.BACKSTAB_MULTIPLIER},
	},
	{
		"id": "shadow_clones", "element": Elements.SHADOW, "tier": 5,
		"kanji": "影分身", "title": "SHADOW CLONES",
		"subtitle": "Mirrored cuts · Kagedachi: cuts split yōkai",
		"cost": 3, "requires_all": ["backstab_execution"], "requires_any": [],
		"effects": {"shadow_clone_count": ElementBalance.SHADOW_CLONES, "kirisute": true},
	},
]

var unlocked: Dictionary = {}  # node id -> true


static func node_by_id(id: String) -> Dictionary:
	for n: Dictionary in NODES:
		if String(n.get("id", "")) == id:
			return n
	return {}


static func nodes_for_element(element: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n: Dictionary in NODES:
		if String(n.get("element", "")) == element:
			out.append(n)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tier", 0)) < int(b.get("tier", 0)))
	return out


static func tree_cost(element: String) -> int:
	var total := 0
	for n: Dictionary in nodes_for_element(element):
		total += int(n.get("cost", 0))
	return total


func reset() -> void:
	unlocked.clear()


func is_unlocked(id: String) -> bool:
	return bool(unlocked.get(id, false))


func unlocked_count() -> int:
	return unlocked.size()


## True when every "requires_all" entry is unlocked and (when the node has
## a "requires_any" list) at least one of those is unlocked too.
func prerequisites_met(id: String) -> bool:
	var node := node_by_id(id)
	if node.is_empty():
		return false
	for req: String in node.get("requires_all", []):
		if not is_unlocked(req):
			return false
	var any_reqs: Array = node.get("requires_any", [])
	if not any_reqs.is_empty():
		var any_met := false
		for req: String in any_reqs:
			if is_unlocked(req):
				any_met = true
				break
		if not any_met:
			return false
	return true


## Whether [param id] can be bought right now with [param points_available].
## Returns {"ok": bool, "reason": String, "cost": int}; never mutates state.
func can_unlock(id: String, points_available: int) -> Dictionary:
	var node := node_by_id(id)
	if node.is_empty():
		return {"ok": false, "reason": REASON_UNKNOWN_NODE, "cost": 3}
	if is_unlocked(id):
		return {"ok": false, "reason": REASON_ALREADY_UNLOCKED, "cost": int(node.cost)}
	if not prerequisites_met(id):
		return {"ok": false, "reason": REASON_PREREQUISITE, "cost": int(node.cost)}
	if points_available < int(node.cost):
		return {"ok": false, "reason": REASON_POINTS, "cost": int(node.cost)}
	return {"ok": true, "reason": REASON_OK, "cost": int(node.cost)}


## Attempts the purchase against [param points_available]. On success the
## node is marked unlocked and the caller deducts "cost" from its wallet
## (see RunGame.unlock_skill); on failure nothing changes.
func try_unlock(id: String, points_available: int) -> Dictionary:
	var verdict := can_unlock(id, points_available)
	if bool(verdict.get("ok", false)):
		unlocked[id] = true
	return verdict


## Upgraded value of ElementSystem parameter [param key] for [param element]
## from unlocked nodes of that element, or [param default_value] when no
## unlocked node defines it. Later tiers win when two nodes set the key.
func effect_value(element: String, key: String, default_value: Variant) -> Variant:
	var result: Variant = default_value
	var best_tier := -1
	for n: Dictionary in NODES:
		if String(n.get("element", "")) != element:
			continue
		if not is_unlocked(String(n.get("id", ""))):
			continue
		var effects: Dictionary = n.get("effects", {})
		if effects.has(key) and int(n.get("tier", 0)) >= best_tier:
			best_tier = int(n.get("tier", 0))
			result = effects[key]
	return result


## True when any unlocked node of [param element] defines [param key].
func has_effect(element: String, key: String) -> bool:
	for n: Dictionary in NODES:
		if String(n.get("element", "")) != element:
			continue
		if is_unlocked(String(n.get("id", ""))) and (n.get("effects", {}) as Dictionary).has(key):
			return true
	return false
