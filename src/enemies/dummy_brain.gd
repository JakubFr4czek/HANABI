class_name DummyBrain
extends EnemyBrain
## Training dummy brain: holds its guard and slowly turns to face the player.
## Tactics read from the profile: "track_player" (bool).


func think(_delta: float, context: Dictionary) -> Dictionary:
	var intent := {"pose": "guard"}
	if profile and profile.tactics.get("track_player", true) and context.has("player_position"):
		intent["face_position"] = context["player_position"]
	return intent
