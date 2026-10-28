class_name ControlsMap
extends RefCounted
## The controller diagram on Settings > CONTROLS (docs/GDD.md §14).
##
## Built from the project's own OpenXR action map (res://openxr_action_map.tres,
## the Quest "oculus/touch_controller" profile), so it cannot drift from the
## bindings the game reads. Only what each input does is written here, once per
## role; the hand roles (katana, move stick, turn stick, wrist HUD) follow the
## dominant-hand setting. Tests: tests/vr_menu_pause_test.gd.

const ACTION_MAP_PATH := "res://openxr_action_map.tres"
const PROFILE := "/interaction_profiles/oculus/touch_controller"

## Where each pressable control sits on the drawn controller, in icon units
## (the right hand; the left hand mirrors x).
const ANCHORS := {
	"top_button": Vector2(-40, -100),  # Meta on the right, Menu on the left
	"face_top": Vector2(70, -75),  # A (right) / X (left)
	"face_bottom": Vector2(70, -25),  # B (right) / Y (left)
	"stick": Vector2(-45, -35),
	"trigger": Vector2(52, 70),
	"grip": Vector2(0, 130),
}
## Top to bottom on the drawing, so the callouts read in order.
const ORDER := ["top_button", "face_top", "stick", "face_bottom", "trigger", "grip"]

static var _bindings: Array[Dictionary] = []


## Every binding of the Quest profile: {path, side, io, input, action}.
static func bindings() -> Array[Dictionary]:
	if not _bindings.is_empty():
		return _bindings
	var map = load(ACTION_MAP_PATH)
	if map == null:
		push_error("ControlsMap: cannot load %s" % ACTION_MAP_PATH)
		return _bindings
	for profile in map.get_interaction_profiles():
		if String(profile.get_interaction_profile_path()) != PROFILE:
			continue
		for b in profile.get_bindings():
			var path := String(b.get_binding_path())
			var parts := path.split("/")  # "", "user", "hand", side, io, input...
			_bindings.append({
				"path": path,
				"side": parts[3],
				"io": parts[4],
				"input": "/".join(parts.slice(5)),
				"action": String(b.get_action().resource_name),
			})
	return _bindings


## The roles for [param dominant] ("right" or "left"): the katana hand, the
## stick that walks, the stick that turns, and the hand with the wrist HUD.
static func roles_for(dominant: String) -> Dictionary:
	var katana := "left" if dominant == "left" else "right"
	var move := "right" if katana == "left" else "left"
	return {"katana": katana, "move": move, "turn": katana, "hud": move}


## Two lines for the top of the page: what the katana hand, the sticks and the HUD do.
static func summary(dominant: String) -> Array[String]:
	var r := roles_for(dominant)
	return [
		"KATANA  %s   ·   WRIST HUD  %s" % [String(r.katana).to_upper(), String(r.hud).to_upper()],
		"WALK  %s STICK   ·   TURN  %s STICK" % [String(r.move).to_upper(), String(r.turn).to_upper()],
	]


## The whole diagram for [param dominant]:
## {hands: {left, right}: callouts, roles, footnote: [{label, bindings, actions}],
##  rules: [String], unmapped: [path], actions: [String], bindings: [path]}.
## A callout is {side, slot, anchor (icon units, mirrored for left), title, body,
## bindings, actions, system}. Anything the drawing does not place is in
## [member unmapped], which the tests keep empty.
static func layout(dominant: String) -> Dictionary:
	var roles := roles_for(dominant)
	var hands := {"left": {}, "right": {}}
	var footnote := {}
	var unmapped: Array[String] = []
	for b: Dictionary in bindings():
		var slot := _slot(String(b.input))
		if slot != "":
			var callout: Dictionary = hands[b.side].get_or_add(slot, _callout(b, slot, roles))
			callout.bindings.append(b.path)
			if not callout.actions.has(b.action):
				callout.actions.append(b.action)
			continue
		var group := _footnote_group(b)
		if group == "":
			unmapped.append(String(b.path))
			continue
		var g: Dictionary = footnote.get_or_add(group, {"label": _group_label(group), "bindings": [], "actions": []})
		g.bindings.append(b.path)
		if not g.actions.has(b.action):
			g.actions.append(b.action)

	var out := {"hands": {}, "roles": roles, "footnote": [], "rules": RULES.duplicate(),
			"unmapped": unmapped, "actions": [], "bindings": []}
	for side in ["left", "right"]:
		var list: Array[Dictionary] = []
		for slot in ORDER:
			if hands[side].has(slot):
				list.append(hands[side][slot])
		out.hands[side] = list
	for group in FOOTNOTE_ORDER:
		if footnote.has(group):
			out.footnote.append(footnote[group])
	out.actions = _union(out, "actions")
	out.bindings = _union(out, "bindings")
	return out


## Short rules that are not tied to one button, shown under the drawing.
const RULES := [
	"Recenter: hold Menu for 1 s, or hold B/Y for 0.6 s with an empty hand.",
	"Eye height: with the katana hand empty, hold B and push the turn stick up or down.",
]
const FOOTNOTE_ORDER := ["touch", "pose", "output"]


## The callout slot for an input path after /input/ (or "" for the rest).
static func _slot(input: String) -> String:
	match input:
		"x/click", "a/click":
			return "face_top"
		"y/click", "b/click":
			return "face_bottom"
		"thumbstick", "thumbstick/click":
			return "stick"
		"trigger/value":
			return "trigger"
		"squeeze/value":
			return "grip"
		"menu/click", "system/click":
			return "top_button"
	return ""


static func _footnote_group(b: Dictionary) -> String:
	var input := String(b.input)
	if input.ends_with("/touch"):
		return "touch"
	if input.ends_with("/pose"):
		return "pose"
	if String(b.io) == "output":
		return "output"
	return ""


static func _group_label(group: String) -> String:
	match group:
		"touch":
			return "Touch sensors (not used)"
		"pose":
			return "Tracking poses"
		"output":
			return "Haptic output (strength in ACCESS)"
	return group


static func _callout(b: Dictionary, slot: String, roles: Dictionary) -> Dictionary:
	var side := String(b.side)
	var letter := String(b.input).substr(0, 1).to_upper()
	var anchor: Vector2 = ANCHORS[slot]
	if side == "left":
		anchor.x = -anchor.x
	var c := {"side": side, "slot": slot, "anchor": anchor, "title": "", "body": "",
			"bindings": [], "actions": [], "system": false}
	match slot:
		"top_button":
			if side == "right":
				c.title = "META  ·  SYSTEM"
				c.body = "Reserved by the headset, not the game"
				c.system = true
			else:
				c.title = "MENU"
				c.body = "Tap: skill tree  ·  hold 1 s: recenter"
		"face_top":
			c.title = "%s  ·  ABILITY 1" % letter
			c.body = "Element skill 1, from either hand"
		"face_bottom":
			c.title = "%s  ·  ABILITY 2" % letter
			c.body = "Skill 2 with the katana. Grip + B/Y: recall"
		"stick":
			c.title = "THUMBSTICK"
			c.body = "Walk, smooth locomotion" if side == roles.move else "Turn, snap or smooth"
		"trigger":
			c.title = "TRIGGER"
			c.body = "Pick in menus  ·  skip the splash"
		"grip":
			c.title = "GRIP"
			c.body = "Grab or drop the katana, hold near the blade"
	return c


static func _union(out: Dictionary, key: String) -> Array[String]:
	var seen := {}
	var collect := func(list: Array) -> void:
		for item in list:
			for v in item[key]:
				seen[String(v)] = true
	for side in ["left", "right"]:
		collect.call(out.hands[side])
	collect.call(out.footnote)
	var names: Array[String] = []
	for k in seen:
		names.append(String(k))
	names.sort()
	return names
