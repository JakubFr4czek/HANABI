class_name RunPerfProbe
extends RefCounted

static func rendering_info() -> Dictionary:
	return {
		"draw_calls": int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	}


static func estimate_scene_cost(root: Node) -> Dictionary:
	var draws := 0
	var prims := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).visible:
			continue
		draws += 1
		prims += _mesh_primitives((mi as MeshInstance3D).mesh)
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		var inst := mmi as MultiMeshInstance3D
		if not inst.visible:
			continue
		draws += 1
		var mm := inst.multimesh
		if mm and mm.mesh:
			prims += _mesh_primitives(mm.mesh) * mm.instance_count
	return {"draw_calls": draws, "primitives": prims}


static func _mesh_primitives(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		if arrays.size() > Mesh.ARRAY_VERTEX:
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts is PackedVector3Array:
				total += int((verts as PackedVector3Array).size())
	return total


static func count_yokai_physics_bodies(root: Node) -> int:
	var count := 0
	for n in root.find_children("*", "Yokai", true, false):
		var y := n as Yokai
		if y and y.parts:
			count += y.parts.size()
	return count


static func estimate_particles(root: Node) -> int:
	var alive := 0
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		if p.emitting:
			alive += p.amount
	return alive
