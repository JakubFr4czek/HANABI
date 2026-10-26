extends Node3D
## Physics test room: spawns the VR rig when an OpenXR runtime is running,
## otherwise the desktop rig. R (desktop) or A/X (VR) resets the dummy and,
## if nobody holds it, puts the practice sword back on its table.
##
## Pass `-- --desktop` on the command line to force the desktop rig.

const XR_PLAYER := preload("res://scenes/player/xr_player.tscn")

@onready var dummy: TrainingDummy = $TrainingDummy
@onready var sword: HeldWeapon = $PracticeSword
@onready var spawn: Marker3D = $PlayerSpawn

var player: Node3D
var _sword_home: Transform3D


func _ready() -> void:
	_sword_home = sword.global_transform
	GameEvents.clear()
	var use_xr := is_xr_available() and not OS.get_cmdline_user_args().has("--desktop")
	GameEvents.log_event("session_start", {"scene": "test_room", "xr": use_xr})
	if use_xr:
		player = XR_PLAYER.instantiate()
		player.reset_requested.connect(reset_room)
	else:
		player = DesktopPlayer.new()
		player.name = "DesktopPlayer"
	add_child(player)
	player.global_transform = spawn.global_transform
	if player is DesktopPlayer:
		(player as DesktopPlayer).holder.grab(sword)


static func is_xr_available() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and xr.is_initialized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset_room()


func reset_room() -> void:
	dummy.reset_dummy()
	if not sword.is_held():
		sword.global_transform = _sword_home
		sword.linear_velocity = Vector3.ZERO
		sword.angular_velocity = Vector3.ZERO
