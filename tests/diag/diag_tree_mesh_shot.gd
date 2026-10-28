extends Node3D
## Renders the rebuilt tree mesh alone (debug).

func _ready() -> void:
	var fw := ForestWorld.new()
	fw.profile = WorldGenProfile.make_default()
	fw._apply_profile()
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 6, 22)
	cam.look_at(Vector3(0, 6, 0))
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation = Vector3(-0.8, 0.5, 0)
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = fw._tree_meshes[0]
		mi.position = Vector3(-8 + k * 16, 0, 0)
		if k == 1:
			mi.material_override = fw._tree_mats[0]
		add_child(mi)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/hanabi_shots/tree_mesh.png")
	print("saved; tree_mat ", fw._tree_mats[0])
	get_tree().quit()
