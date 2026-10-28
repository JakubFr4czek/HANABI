class_name WorldGenBudget
extends RefCounted
## Quest 3 share of the forest (docs/WORLDGEN_TOOL.md, budget). The whole run is
## capped by RunPerfBudget (draw calls 345, primitives 420k); the forest gets a
## fixed share so a profile that draws too much shows up in the World Gen dock
## before it reaches the headset.
##
## The default profile draws about 63 calls (9 chunks × terrain, two tree kinds,
## gates, lanterns, boulders, shafts) plus up to two shrine spurs, so the share
## leaves room for the shrines and the run's own draws.

const FOREST_DRAW_CALLS := 96
const FOREST_TRIANGLES := 150_000
const FOREST_INSTANCES := 980


## Warnings for one [method ForestWorld.stats] reading, in Polish.
static func warnings(stats: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var draws: int = stats.get("draws", 0)
	var triangles: int = stats.get("triangles", 0)
	var instances: int = stats.get("instances", 0)
	if draws > FOREST_DRAW_CALLS:
		out.append("UWAGA: las rysuje %d wywołań (budżet Quest dla lasu: %d z %d)." % [draws, FOREST_DRAW_CALLS, RunPerfBudget.MAX_DRAW_CALLS])
	if triangles > FOREST_TRIANGLES:
		out.append("UWAGA: w widoku %d trójkątów lasu (budżet %d)." % [triangles, FOREST_TRIANGLES])
	if instances > FOREST_INSTANCES:
		out.append("UWAGA: %d instancji lasu (budżet %d)." % [instances, FOREST_INSTANCES])
	return out
