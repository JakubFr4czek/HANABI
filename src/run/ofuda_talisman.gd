class_name OfudaTalisman
extends VotiveTablet
## A yellow shrine Ofuda (docs/ELEMENTS_PLAN.md, D12, section 4): one of three buff
## choices that hang in free air in front of the player while the world holds still.
## Slicing it with the katana grants its buff ([signal sliced] carries the entry, so
## [member entry].kind is the [enum RunBuffs.Kind]).
##
## It is the sliceable card of VotiveTablet with light paper: the ink is dark on yellow,
## and the cinnabar seal stands in for the glow of the ema. It keeps running while the
## world is paused (process_mode ALWAYS), so the blade still cuts it.

const PAPER := Color(0.93, 0.80, 0.46)
const INK := Color(0.08, 0.065, 0.055)
const CINNABAR := Color(0.74, 0.13, 0.10)
## Small cinnabar text on the paper needs a darker red to read (contrast ≥ 4.5 : 1).
const CINNABAR_TEXT := Color(0.56, 0.08, 0.06)
const INK_SOFT := Color(0.2, 0.16, 0.12)


func _ready() -> void:
	# The shrine choice holds the world: the card must keep moving and take the cut.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ofuda_talismans")
	super._ready()


## The three choices, in the order the shrine lays them out (left to right).
static func entries() -> Array[Dictionary]:
	return [
		_entry(RunBuffs.Kind.SPEED, "速", "SWIFT STEP", "+20 % speed · 60 s"),
		_entry(RunBuffs.Kind.DAMAGE, "攻", "STRIKE FORCE", "+20 % damage · 60 s"),
		_entry(RunBuffs.Kind.HEAL, "癒", "HEALING", "+35 % HP now · +15 % over 10 s"),
	]


static func _entry(kind: int, kanji: String, title: String, subtitle: String) -> Dictionary:
	return {
		"kind": kind,
		"header": "御札 · SHRINE",
		"kanji": kanji,
		"title": title,
		"subtitle": subtitle,
		"color": CINNABAR,
		"paper": PAPER,
		"ink": INK,
		"sub_ink": INK_SOFT,
		"header_ink": CINNABAR_TEXT,
		"kanji_ink": CINNABAR,
		"outline": Color(PAPER, 0.0),
	}
