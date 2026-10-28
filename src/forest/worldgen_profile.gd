@tool
class_name WorldGenProfile
extends Resource
## The one source of truth for the endless forest (ForestWorld) and its look.
## Edit it in the inspector of data/worldgen/*.tres or through the "World Gen"
## dock; the game reads the profile named in project.godot
## (hanabi/worldgen/profile). Guide: docs/WORLDGEN_TOOL.md.
##
## The defaults are the numbers the forest has always used, so a fresh profile
## reproduces the shipped look. Mesh shapes (crown clumps, root ribbons) stay in
## ForestWorld: they are geometry, not generation settings.

const DEFAULT_PATH := "res://data/worldgen/default_profile.tres"
const SETTING_PATH := "hanabi/worldgen/profile"
const TORII_SCENE_PATH := "res://assets/models/environment/forest_quaternius/torii_gate_polyfork.glb"

@export_group("Seed")
## Same seed + same profile = the same forest, chunk for chunk, in every run.
@export_range(0, 999999, 1) var world_seed := 0
## Chunk edge in metres. The 3×3 ring around the player is nine of these.
@export_range(12.0, 64.0, 0.5) var chunk_size := 28.0
## Chunks loaded around the player's chunk (1 = 3×3 ring).
@export_range(0, 3, 1) var chunk_radius := 1
## Glade around the spawn with no trees and no hills.
@export_range(2.0, 20.0, 0.1) var clearing_radius := 5.2
## Props (trees, gates, boulders) keep out of this disc around the spawn.
@export_range(1.0, 12.0, 0.1) var prop_clearing_radius := 3.4

@export_group("Terrain")
## Height of the broad hills and valleys, metres.
@export_range(0.0, 15.0, 0.05) var hill_amplitude := 4.6
## Feature size of the hills: lower = broader swells.
@export_range(0.002, 0.06, 0.001) var hill_frequency := 0.013
## Detail layers on the hills (1 = smooth, 5 = crumbly).
@export_range(1, 5, 1) var hill_octaves := 3
## Gentle roll on top of the hills, metres.
@export_range(0.0, 1.5, 0.01) var bump_amplitude := 0.18
@export_range(0.01, 0.3, 0.001) var bump_frequency := 0.05
## Little roots and pockets on the flats (never on steep slopes).
@export_range(0.0, 0.6, 0.01) var pocket_amount := 0.15
@export_range(0.0, 0.5, 0.01) var root_amount := 0.10
@export_range(0.05, 1.5, 0.01) var floor_frequency := 0.38
## Distance over which the glade blends into the hills, metres.
@export_range(2.0, 40.0, 0.5) var hill_blend_distance := 9.0
## Mesh grid per chunk side (higher = smoother ground, more triangles).
@export_range(9, 81, 1) var terrain_resolution := 41

@export_group("Trees")
## Tree kinds. Ordinary entries share the trunks by weight; focal entries (sakura) take one tree per chunk now and then.
@export var trees: Array[TreeEntry] = []
## Density noise scale (metres⁻¹ × 0.09 in the old code): how wide the clumps and clearings are.
@export_range(0.01, 0.5, 0.001) var density_frequency := 0.09
## Keep chance on the calmest and the densest spots of the density noise.
@export_range(0.0, 1.0, 0.01) var tree_keep_min := 0.5
@export_range(0.0, 1.0, 0.01) var tree_keep_max := 0.97

@export_group("Undergrowth")
## Ground cover: boulders now, ferns, stumps and logs when D5 assets land.
@export var undergrowth: Array[UndergrowthEntry] = []

@export_group("Torii")
## Full-size gates in the forest. Mesh for each gate; empty uses the procedural box.
@export var torii_scene: PackedScene = preload("res://assets/models/environment/forest_quaternius/torii_gate_polyfork.glb")
## Share of chunks that hold gates at all (rarity).
@export_range(0.0, 1.0, 0.01) var torii_chunk_chance := 0.34
@export_range(0, 6, 1) var torii_max_per_chunk := 3
## Smallest distance between two gates of a chunk, metres (Poisson-disk spacing).
@export_range(2.0, 30.0, 0.5) var torii_min_spacing := 8.0
## Share of candidates kept inside a chosen chunk: gates come in small groups.
@export_range(0.1, 1.0, 0.01) var torii_group_keep := 0.75
## Gate height range, metres.
@export_range(2.0, 12.0, 0.1) var torii_height_min := 4.2
@export_range(2.0, 12.0, 0.1) var torii_height_max := 6.2
## Clearance from trunks, metres: gates stand well clear of the trees.
@export_range(0.0, 6.0, 0.05) var torii_tree_clearance := 2.5
## Clearance from other props and between gates of a group.
@export_range(0.0, 6.0, 0.05) var torii_prop_clearance := 1.5
## Share of the row noise above which a chunk holds a senbon row (a short line of gates).
@export_range(0.4, 1.0, 0.01) var torii_row_threshold := 0.64
@export_range(2, 12, 1) var torii_row_min := 4
@export_range(2, 12, 1) var torii_row_max := 7
## Distance between gates of a row, metres.
@export_range(2.0, 12.0, 0.1) var torii_row_spacing := 4.2

@export_group("Lanterns")
## Stone lantern used along the forest path. Empty uses the procedural lantern.
@export var lantern_scene: PackedScene
@export_range(0, 12, 1) var lantern_max_per_chunk := 5
## Smallest distance between two lanterns of a chunk, metres (Poisson-disk spacing).
@export_range(1.0, 30.0, 0.5) var lantern_min_spacing := 5.0
@export_range(0.2, 3.0, 0.01) var lantern_scale_min := 0.6
@export_range(0.2, 3.0, 0.01) var lantern_scale_max := 1.33
## Scatter-noise threshold: higher = lanterns cluster in fewer spots.
@export_range(0.0, 1.0, 0.01) var lantern_cluster_threshold := 0.5
## Clearance from trunks and other props, metres.
@export_range(0.0, 6.0, 0.05) var lantern_clearance := 1.0

@export_group("Shrines")
## A hokora shrine slot is this many chunks on a side (see HokoraManager).
@export_range(1, 12, 1) var shrine_slot_chunks := 4
## Chance that a slot holds a shrine at all. Shrines must stay rarer than the torii (validate()).
@export_range(0.0, 1.0, 0.01) var shrine_slot_chance := 0.9

@export_group("Lights and sky")
## Moonlight through canopy gaps: shafts per chunk.
@export_range(0, 8, 1) var shafts_max_per_chunk := 5
@export_range(4.0, 40.0, 0.5) var shaft_length := 15.0
## Depth fog: where the milk starts and how fast it thickens (the density knob).
## Fog reaches full strength at fog_end, which must stay inside the loaded chunks.
@export_range(0.0, 20.0, 0.1) var fog_start := 0.4
@export_range(4.0, 14.0, 0.1) var fog_end := 10.5
@export_range(0.2, 4.0, 0.05) var fog_curve := 1.0
## Milk fog colour (sRGB). The background is the same colour, so the forest has no edge.
@export var fog_color := Color(0.5, 0.53, 0.6)
@export_range(0.0, 2.0, 0.01) var ambient_energy := 0.55
@export var moon_color := Color(0.64, 0.66, 0.68)
@export_range(0.0, 3.0, 0.01) var moon_energy := 0.5
@export_range(0.5, 1.5, 0.01) var exposure := 0.92
@export_range(0.0, 1.0, 0.01) var glow_intensity := 0.16
## Volumetric fog is a PC-only recording setting (GDD §9): it is slow on Quest.
@export var volumetric_fog := false

@export_group("Ground")
@export_range(0.0, 1.0, 0.01) var ground_wetness := 0.3
@export_range(0.0, 1.0, 0.01) var ground_cavity_ao := 0.85
@export_range(0.0, 3.0, 0.01) var ground_normal_strength := 1.2
@export_range(0.0, 1.0, 0.01) var ground_roughness_wet := 0.72

@export_group("Paths")
## Footpaths joining the glade, the gates and the shrines (see ForestPaths).
@export var paths_enabled := true
## Lattice spacing of the path network, metres: a node per cell, joined to the start.
@export_range(28.0, 140.0, 0.5) var path_node_spacing := 56.0
## Width of the trodden strip, metres (terrain colour and clearing of trees).
@export_range(0.6, 4.0, 0.05) var path_width := 1.6
## Share of the lattice edges that also become loops (0 = a tree of paths).
@export_range(0.0, 1.0, 0.01) var path_loop_chance := 0.25
## How much the routes meander around the terrain's bumps.
@export_range(0.0, 2.0, 0.01) var path_curviness := 0.6
## Gap kept free of trunks beside a path, metres (on top of half the width).
@export_range(0.0, 6.0, 0.05) var path_tree_clearance := 1.2
## Share of gates that stand beside a path instead of at a random site.
@export_range(0.0, 1.0, 0.01) var torii_on_path := 0.6
## Share of lanterns that stand along a path instead of at a random site.
@export_range(0.0, 1.0, 0.01) var lantern_on_path := 0.7

@export_group("Distance and LOD")
## Trees are drawn out to this distance from the camera; past it they are fog.
@export_range(4.0, 60.0, 0.5) var tree_draw_radius := 11.0
## Focal (sakura) trees keep their longer reach so the neon reads from far off.
@export_range(4.0, 80.0, 0.5) var focal_draw_radius := 14.0
## Beyond this distance every second tree is skipped (stable per tree, no shimmer).
@export_range(0.0, 60.0, 0.5) var tree_far_start := 9.5
@export_range(0.0, 1.0, 0.01) var tree_far_keep := 0.5
## Ground fade from the camera: start and full fade, metres.
@export_range(5.0, 200.0, 0.5) var ground_fade_start := 60.0
@export_range(5.0, 200.0, 0.5) var ground_fade_end := 70.0

## Set in the editor (a fresh seed each click) or by randomize_seed().
func randomize_seed() -> void:
	world_seed = randi() % 1000000


func _init() -> void:
	trees = [_cedar_entry(), _sakura_entry()]
	undergrowth = [_boulder_entry()]
	torii_scene = load(TORII_SCENE_PATH)


static func make_default() -> WorldGenProfile:
	return WorldGenProfile.new()


## The profile the game uses: project setting, else the default preset.
static func load_active() -> WorldGenProfile:
	var path := String(ProjectSettings.get_setting(SETTING_PATH, DEFAULT_PATH))
	var res := load(path) as WorldGenProfile
	if res == null:
		res = load(DEFAULT_PATH) as WorldGenProfile
	return res


## Copies the defaults of one inspector group back onto this profile
## ("Przywróć domyślne" in the dock). Other groups are untouched.
func reset_group(group: String) -> void:
	var fresh := WorldGenProfile.new()
	var current := ""
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_GROUP:
			current = String(p.name)
			continue
		if current == group and p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			set(p.name, fresh.get(p.name))


## Names of the inspector groups in order, for the dock.
func group_names() -> PackedStringArray:
	var out := PackedStringArray()
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_GROUP and String(p.name) != "":
			out.append(String(p.name))
	return out


## Everything the generator reads, as one number. The preview regenerates when it changes.
func signature() -> int:
	var parts: PackedStringArray = []
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			parts.append("%s=%s" % [p.name, _key(get(p.name))])
	return "\n".join(parts).hash()


static func _key(v: Variant) -> String:
	if v is Resource:
		var r := v as Resource
		var parts: PackedStringArray = []
		for p in r.get_property_list():
			if p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				parts.append("%s=%s" % [p.name, _key(r.get(p.name))])
		return "{" + ";".join(parts) + "}"
	if v is Array:
		var items: PackedStringArray = []
		for item in v:
			items.append(_key(item))
		return "[" + ",".join(items) + "]"
	return var_to_str(v)


func _cedar_entry() -> TreeEntry:
	var t := TreeEntry.new()
	t.label = "Cedar (sugi)"
	t.crown = TreeEntry.Crown.CEDAR
	t.weight = 1.0
	return t


func _sakura_entry() -> TreeEntry:
	var t := TreeEntry.new()
	t.label = "Sakura (neon focal)"
	t.crown = TreeEntry.Crown.SAKURA
	t.weight = 0.0
	t.focal_chance = 0.18
	return t


func _boulder_entry() -> UndergrowthEntry:
	var u := UndergrowthEntry.new()
	u.label = "Boulder (moss)"
	u.source = UndergrowthEntry.Source.BOULDER
	u.max_per_chunk = 4
	u.scale_min = 0.85
	u.scale_max = 3.2
	return u
