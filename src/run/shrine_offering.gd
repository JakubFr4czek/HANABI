class_name ShrineOffering
extends Node3D
## The yellow Ofuda choice of a hokora (docs/ELEMENTS_PLAN.md, D12, section 4).
##
## A hand on the offering table ([method try_open]) hangs three yellow talismans in
## free air in front of the player, and the world holds still exactly as it does for
## the skill-tree menu ([method PauseController.hold_for_offering]). Slicing one with
## the katana grants its buff; the other two fade and the shrine goes dark for the run.
## Nothing in the choice lets a yōkai's blade or body reach a card: the cards only go
## where a box query finds no enemy, trunk, rock or prop.

signal opened(shrine: HokoraShrine)
signal chosen(shrine: HokoraShrine, kind: int)

## Cards hang at this many metres below eye level, centred on the player's view.
const CARD_HEIGHT_BELOW_HEAD := 0.35
## Candidate distances from the eyes (m), nearest first; the arc is tried at each.
const RADII := [1.0, 0.9, 1.15, 0.8, 1.25]
## Yaw of the three cards around the view (deg). The arc is 24° apart, so the cards
## keep a gap of about 8 cm.
const ARC_YAW_DEG := [-24.0, 0.0, 24.0]
## Whole-arc shifts tried when the centred arc is blocked (deg).
const SHIFT_YAW_DEG := [0.0, -12.0, 12.0]
## Free space around a card (m) that no enemy, trunk or prop may enter.
const CLEAR_MARGIN := 0.2
## static_world (1), dynamic_props (2), enemy_body (4 = bit 8), trunk (bit 64).
const CLEAR_MASK := 1 | 2 | 8 | 64

var run_game: RunGame
var pause: PauseController
var _shrine: HokoraShrine = null
var _cards: Array[VotiveTablet] = []


func setup(game: RunGame, p_pause: PauseController) -> void:
	run_game = game
	pause = p_pause


func is_open() -> bool:
	return _shrine != null


## Opens the choice for [param shrine]. False (nothing changes) when a choice is
## already open, the run is not playing, a living yōkai stands within
## HOKORA_REFUSE_ENEMY_RADIUS of the player, or there is no free room for three cards.
func try_open(shrine: HokoraShrine) -> bool:
	if is_open() or run_game == null or pause == null:
		return false
	if run_game.state != RunGame.RunState.PLAYING or enemy_near_player():
		return false
	var placement := plan_placement()
	if placement.is_empty():
		return false
	if not pause.hold_for_offering():
		return false
	_shrine = shrine
	var entries := OfudaTalisman.entries()
	for i in 3:
		var card := OfudaTalisman.new()
		card.setup(entries[i], i)
		card.sliced.connect(_on_card_sliced)
		add_child(card)
		card.global_transform = placement[i]
		_cards.append(card)
	shrine.ring_accepted()
	opened.emit(shrine)
	return true


## Ends the choice without a buff (the run ended under it). The shrine stays lit.
func cancel() -> void:
	if not is_open():
		return
	_shrine = null
	for c in _cards:
		if is_instance_valid(c):
			c.dismiss()
	_cards.clear()
	if pause:
		pause.release_from_offering()


## True when a living yōkai is close enough to refuse the touch (D12: no choice in a fight).
func enemy_near_player() -> bool:
	var head := _head()
	if head == null or run_game.wave_director == null:
		return false
	var p := head.global_position
	for e in run_game.wave_director.alive_enemies():
		if p.distance_to(e.root_part().global_position) <= ElementBalance.HOKORA_REFUSE_ENEMY_RADIUS:
			return true
	return false


## Three card transforms in free space in front of the player, left to right, or an
## empty array when no arc fits. Each card faces the player.
func plan_placement() -> Array[Transform3D]:
	var head := _head()
	if head == null:
		return []
	var head_pos := head.global_position
	var flat := -head.global_basis.z
	flat.y = 0.0
	if flat.length_squared() < 0.01:
		flat = Vector3.FORWARD
	var base_yaw := atan2(flat.x, flat.z)
	var space := head.get_world_3d().direct_space_state
	for radius: float in RADII:
		for shift: float in SHIFT_YAW_DEG:
			var out: Array[Transform3D] = []
			for arc: float in ARC_YAW_DEG:
				var yaw := base_yaw + deg_to_rad(arc + shift)
				var pos := head_pos + Vector3(sin(yaw), 0.0, cos(yaw)) * radius
				pos.y = head_pos.y - CARD_HEIGHT_BELOW_HEAD
				var to_head := Vector3(head_pos.x, pos.y, head_pos.z) - pos
				var at := Transform3D(Basis.looking_at(to_head, Vector3.UP), pos)
				if not card_clear(space, at):
					break
				out.append(at)
			if out.size() == ARC_YAW_DEG.size():
				return out
	return []


## True when a card at [param at] has no enemy, trunk, rock or prop within CLEAR_MARGIN.
static func card_clear(space: PhysicsDirectSpaceState3D, at: Transform3D) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(VotiveTablet.WIDTH + 2.0 * CLEAR_MARGIN,
		VotiveTablet.HEIGHT + 2.0 * CLEAR_MARGIN, 0.08 + 2.0 * CLEAR_MARGIN)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = at
	query.collision_mask = CLEAR_MASK
	return space.intersect_shape(query, 1).is_empty()


func _on_card_sliced(card: VotiveTablet, entry: Dictionary) -> void:
	if _shrine == null:
		return
	var shrine := _shrine
	var kind := int(entry.get("kind", RunBuffs.Kind.SPEED))
	_shrine = null
	for c in _cards:
		if is_instance_valid(c) and c != card:
			c.dismiss()
	_cards.clear()
	pause.release_from_offering()
	run_game.buff_chosen(shrine, kind)
	chosen.emit(shrine, kind)


func _head() -> Node3D:
	return get_tree().get_first_node_in_group("player_head") as Node3D
