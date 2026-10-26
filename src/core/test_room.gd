extends Node3D
## Physics test room: spawns the VR rig when an OpenXR runtime is running,
## otherwise the desktop rig. R (desktop) or A/X (VR) resets the dummy and puts
## weapons nobody holds back on the table. P (desktop) or B/Y without grip (VR)
## toggles the dummy's attacks for parry practice.
##
## Pass `-- --desktop` on the command line to force the desktop rig.

const XR_PLAYER := preload("res://scenes/player/xr_player.tscn")

@onready var dummy: TrainingDummy = $TrainingDummy
@onready var katana: HeldWeapon = $Katana
@onready var kanabo: HeldWeapon = $Kanabo
@onready var spawn: Marker3D = $PlayerSpawn

## Kept for older callers/tests: the default weapon.
var sword: HeldWeapon:
	get: return katana

var player: Node3D
var _homes := {}  # weapon -> Transform3D on the table


func _ready() -> void:
	for w in [katana, kanabo]:
		_homes[w] = w.global_transform
	GameEvents.clear()
	TimeController.clear()
	var use_xr := is_xr_available() and not OS.get_cmdline_user_args().has("--desktop")
	GameEvents.log_event("session_start", {"scene": "test_room", "xr": use_xr})
	if use_xr:
		player = XR_PLAYER.instantiate()
		player.reset_requested.connect(reset_room)
		player.toggle_attacks_requested.connect(toggle_dummy_attacks)
	else:
		player = DesktopPlayer.new()
		player.name = "DesktopPlayer"
		player.weapons = [katana, kanabo]
		player.toggle_attacks_requested.connect(toggle_dummy_attacks)
	add_child(player)
	player.global_transform = spawn.global_transform
	if player is DesktopPlayer:
		(player as DesktopPlayer).holder.grab(katana)


static func is_xr_available() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and xr.is_initialized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset_room()


func toggle_dummy_attacks() -> void:
	dummy.set_attacks_enabled(not dummy.attacks_enabled())


func reset_room() -> void:
	TimeController.clear()
	dummy.reset_dummy()
	for w: HeldWeapon in _homes:
		if not w.is_held():
			w.global_transform = _homes[w]
			w.linear_velocity = Vector3.ZERO
			w.angular_velocity = Vector3.ZERO
			if w.trail:
				w.trail.clear()
