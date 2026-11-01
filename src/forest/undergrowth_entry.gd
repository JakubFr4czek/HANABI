@tool
class_name UndergrowthEntry
extends Resource
## One kind of ground cover (boulders, stumps, logs, ferns): scattered on the
## chunk floor, clustered by the scatter noise (docs/WORLDGEN_TOOL.md).

## Mesh source. BOULDER is the procedural low-poly stone used since D0; SCENE takes [member scene].
enum Source {
	BOULDER,
	SCENE,
}

## Name shown in the dock and in validation messages.
@export var label := "Boulder"
## BOULDER is the procedural stone; SCENE takes the mesh from the scene below.
@export var source: Source = Source.BOULDER
## Used when source is SCENE (imported ferns, logs, stumps: D5).
@export var scene: PackedScene
## Relative chance of this kind when the chunk picks what to place next.
@export_range(0.0, 10.0, 0.05) var weight := 1.0
## Largest number of this kind per chunk (a 28 m chunk holds a handful of boulders).
@export_range(0, 24, 1) var max_per_chunk := 4
## Scale range, applied on top of the mesh's own size.
@export_range(0.2, 4.0, 0.01) var scale_min := 1.0
## Largest scale of this kind.
@export_range(0.2, 4.0, 0.01) var scale_max := 2.3
## Fraction of the height sunk into the floor, so it does not balance on the slope.
@export_range(0.0, 0.6, 0.01) var bury := 0.15
## Smallest distance between two of this kind, metres (Poisson-disk spacing).
@export_range(0.5, 12.0, 0.05) var min_spacing := 3.0
## Base clearance to other props, metres (grows by half the scale).
@export_range(0.0, 6.0, 0.05) var clearance := 1.0
## Scatter-noise value below which the kind is not placed: higher = more clustered, fewer spots.
@export_range(0.0, 1.0, 0.01) var cluster_threshold := 0.56
## Solid: the player and the blade stop on it.
@export var obstacle := true
## Leaf card with its own alpha (ferns, N5): drawn with the cut-out foliage shader on its
## alpha channel (the baked atlas is RGBA, see tools/prep_forest_assets.py --alpha).
@export var cutout := false
## Along the footpaths only (N5 ferns): sites come from the trail edges, never from the
## open floor, and the kind keeps off the trail itself.
@export var along_path := false
## Metres from the trail centre line to the kind's centre when along_path is on. The trail is
## 2 m wide (edge 1.0 m off the centre), so 1.7 m puts the kind's centre 0.7 m past the edge.
@export_range(1.0, 4.0, 0.05) var path_edge_offset := 1.7
## Distance from the camera where the kind starts to fade and where it is gone, metres.
## Small plants fade well inside the fog; trees use the profile's draw radius.
@export_range(4.0, 80.0, 0.5) var fade_start := 18.0
@export_range(4.0, 80.0, 0.5) var fade_end := 26.0
