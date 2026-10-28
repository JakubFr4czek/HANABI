class_name CalorieMeter
extends Node
## Estimated energy spent in a run (docs/GDD.md §15, D14). A MET-style estimate,
## not a medical figure: kcal = MET × body weight (kg) × hours, where MET rises with
## how fast the hands and the body move. It counts only while [member counting] is
## on (RunGame sets it while the run is PLAYING) and freezes while the tree is paused.
##
## Anchors (MET = kcal per kg per hour): quiet standing about 1.3; vigorous active
## video games and boxing-style arm work about 4 to 6. The shares below spread a
## standing body up to [constant MET_MAX] over the arm and walking speeds of a sword fight.

const MET_STANDING := 1.3
const MET_MAX := 5.3
## Hand speed (m/s) at which the arms add their full share, and the body speed for the walk share.
const HAND_SPEED_FULL := 1.5
const HAND_MET_SHARE := 2.6
const BODY_SPEED_FULL := 1.2
const BODY_MET_SHARE := 1.4
const DEFAULT_WEIGHT_KG := 70.0
## Speed smoothing (s): hands and body flicker a lot tick to tick.
const SPEED_SMOOTH_SECONDS := 0.5
## A single tick's displacement above this (m/s) is a jump (the menu, a teleport), not movement.
const MAX_SAMPLE_SPEED := 4.0

## Estimated kilocalories in this run so far.
var kcal := 0.0
var counting := false
var _hands: Array[Node3D] = []
var _head: Node3D = null
var _last_pos := {}
var _hand_speed := 0.0
var _body_speed := 0.0


## Reads the hands and the head from the player rig (XR controllers or the desktop sword hand).
func setup(player: Node3D) -> void:
	if player is XRPlayer:
		var xr := player as XRPlayer
		set_sources([xr.left_controller, xr.right_controller], xr.get_node_or_null("XROrigin3D/XRCamera3D") as Node3D)
	elif player is DesktopPlayer:
		var dp := player as DesktopPlayer
		set_sources([dp.hand], dp.camera)


## The nodes whose motion counts: the hands (their mean speed) and the head (the walk share).
func set_sources(hands: Array[Node3D], head: Node3D) -> void:
	_hands = hands
	_head = head
	_last_pos.clear()


func reset() -> void:
	kcal = 0.0
	_hand_speed = 0.0
	_body_speed = 0.0


## MET for a given hand and body speed (m/s): standing, plus the arm share and the walk share.
static func met_for(hand_speed: float, body_speed: float) -> float:
	var met := MET_STANDING \
		+ HAND_MET_SHARE * clampf(hand_speed / HAND_SPEED_FULL, 0.0, 1.0) \
		+ BODY_MET_SHARE * clampf(body_speed / BODY_SPEED_FULL, 0.0, 1.0)
	return clampf(met, MET_STANDING, MET_MAX)


## Energy of one step: kcal = MET × kg × hours.
static func kcal_for(met: float, weight_kg: float, seconds: float) -> float:
	return met * weight_kg * seconds / 3600.0


func current_met() -> float:
	return met_for(_hand_speed, _body_speed)


func _physics_process(delta: float) -> void:
	if _hands.is_empty() or _head == null or delta <= 0.0:
		return
	var hand_v := 0.0
	for hand in _hands:
		hand_v += _sample_speed(hand, delta)
	hand_v /= float(_hands.size())
	var body_v := _sample_speed(_head, delta)
	# Positions are sampled every tick, counting or not, so a pause never reads as a jump.
	if not counting or get_tree().paused:
		_hand_speed = 0.0
		_body_speed = 0.0
		return
	var k := 1.0 - exp(-delta / SPEED_SMOOTH_SECONDS)
	_hand_speed = lerpf(_hand_speed, hand_v, k)
	_body_speed = lerpf(_body_speed, body_v, k)
	kcal += kcal_for(current_met(), _weight_kg(), delta)


## Speed of a node since the last tick (m/s), clamped so one jump cannot count as exertion.
func _sample_speed(node: Node3D, delta: float) -> float:
	var pos := node.global_position
	var key := node.get_instance_id()
	var speed := 0.0
	if _last_pos.has(key):
		speed = minf(pos.distance_to(_last_pos[key]) / delta, MAX_SAMPLE_SPEED)
	_last_pos[key] = pos
	return speed


func _weight_kg() -> float:
	return VrComfortSettings.body_weight_kg if VrComfortSettings else DEFAULT_WEIGHT_KG
