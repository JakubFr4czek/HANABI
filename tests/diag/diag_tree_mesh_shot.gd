extends Node3D
## Renders the rebuilt tree mesh alone (debug).

func _ready() -> void:
	var fw := ForestWorld.new()
	fw._build_meshes()
	fw._build_materials() if fw.has_method("_build_materials") else null
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 6, 22)
	cam.look_at(Vector3(0, 6, 0))
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation = Vector3(-0.8, 0.5, 0)
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = fw._tree_mesh
		mi.position = Vector3(-8 + k * 16, 0, 0)
		if k == 1 and fw._tree_mat:
			mi.material_override = fw._tree_mat
		add_child(mi)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/hanabi_shots/tree_mesh.png")
	print("saved; tree_mat ", fw._tree_mat)
	get_tree().quit()
