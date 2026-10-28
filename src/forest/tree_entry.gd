@tool
class_name TreeEntry
extends Resource
## One kind of tree in the endless forest (docs/WORLDGEN_TOOL.md). A profile
## lists several. Ordinary entries share the chunk's trunks by weight; an entry
## with focal_chance > 0 sometimes turns one trunk of the chunk into its focal
## tree (the neon sakura of GDD §9).

## How the crown is built from [member scene].
enum Crown {
	## Cherry scan, bark kept and a solid cedar crown grown over it: tall, dark, tiered.
	CEDAR,
	## Same bark with the rounded blossom crown, drawn with the neon sakura shader.
	SAKURA,
	## The scene's own mesh, merged as it comes (imported assets, see D5).
	SCENE,
}

## Name shown in the dock and in validation messages.
@export var label := "Tree"
## Crown style. CEDAR and SAKURA rebuild the scan's bark into a solid crown; SCENE uses the mesh as is.
@export var crown: Crown = Crown.CEDAR
## Mesh source. Empty falls back to the procedural cedar (validation warns).
@export var scene: PackedScene = preload("res://assets/models/environment/forest_trees/cherry_forest.gltf")
## Relative chance of this kind among the ordinary trees. 0 switches it off.
@export_range(0.0, 10.0, 0.05) var weight := 1.0
## Chance per chunk that one tree of this kind becomes the chunk's focal tree. 0 = never.
## Rare by design: about one chunk in five-six holds a sakura (GDD §9).
@export_range(0.0, 1.0, 0.01) var focal_chance := 0.0
## Trunk scale range (metres of tree per metre of mesh). Focal trees get focal_scale_boost on top.
@export_range(0.2, 3.0, 0.01) var scale_min := 0.85
## Largest trunk scale.
@export_range(0.2, 3.0, 0.01) var scale_max := 1.4
## Extra scale a focal tree gets over an ordinary one.
@export_range(1.0, 2.0, 0.01) var focal_scale_boost := 1.2
## Turn each tree to a random heading (off = all face the same way).
@export var random_yaw := true
## How far the trunk leans with the hill: 0 stands straight, 1 follows the slope fully.
@export_range(0.0, 1.0, 0.01) var hill_lean := 0.72
## Smallest trunk-to-trunk distance for this kind (Poisson-disk radius, metres).
@export_range(0.8, 10.0, 0.05) var min_spacing := 2.7
## Solid trunk: the player and the blade stop on it (yōkai steer around it).
@export var obstacle := true
## Neon sakura look (only for crown SAKURA): accent glow, petals, rim light, emission and sparsity.
@export var neon_color := Color(1.0, 0.30, 0.68)
## Petal colour of the neon crown (sakura only).
@export var petal_color := Color(0.76, 0.28, 0.48)
## Rim light on the sakura crown (sakura only).
@export var rim_color := Color(0.96, 0.65, 0.98)
## Neon emission strength of the sakura crown.
@export_range(0.0, 4.0, 0.01) var emission := 1.35
## How sparse the neon blossoms are: higher means fewer lit petals.
@export_range(0.0, 1.0, 0.01) var neon_sparsity := 0.70


func is_focal() -> bool:
	return focal_chance > 0.0


func has_scene() -> bool:
	return scene != null
