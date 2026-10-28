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
	# Only nodes that are actually drawn: a hidden parent (the arena props, the
	# stowed kanabō, the finished intro) takes its whole subtree out of the frame.
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		draws += 1
		prims += _mesh_primitives((mi as MeshInstance3D).mesh)
		# A material's next_pass draws the mesh again (the blade's rim light).
		var pass_mat: Material = (mi as MeshInstance3D).get_active_material(0)
		while pass_mat and pass_mat.next_pass:
			draws += 1
			pass_mat = pass_mat.next_pass
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		var inst := mmi as MultiMeshInstance3D
		if not inst.is_visible_in_tree():
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


static func count_dynamic_lights(root: Node) -> int:
	var n := 0
	for lamp in root.find_children("*", "OmniLight3D", true, false):
		var o := lamp as OmniLight3D
		if o.visible and o.light_energy > 0.05:
			n += 1
	return n


static func count_audio_voices(root: Node) -> int:
	var voices := 0
	for p in root.find_children("*", "AudioStreamPlayer", true, false):
		if (p as AudioStreamPlayer).playing:
			voices += 1
	for p in root.find_children("*", "AudioStreamPlayer3D", true, false):
		if (p as AudioStreamPlayer3D).playing:
			voices += 1
	return voices
