extends Node
## V3: shader and texture integrity audit. Walks what the player sees (the forest's material
## registry, a torii gate as ToriiManager spawns it, the katana and kanabo, the hokora shrine, the
## wrist HUD, a yokai and the Oni boss) and every spatial shader in src/shaders. It fails on what
## would render as a default or broken surface in VR:
##   - a mesh surface with no material (Godot falls back to its grey default),
##   - a key texture left null (black or missing texels), see KEY_TEXTURES,
##   - a BaseMaterial3D with normal or detail enabled and no texture for it,
##   - a shader that does not compile (its uniform list comes back short),
##   - a shader that is not a shader (no shader_type, unbalanced braces).
## It warns, without failing, on other sampled maps left null (the shader may gate them off) and on
## opaque depth-writing shaders that write ALPHA without a scissor threshold: those sort per object
## and can flicker where two of them overlap.
##   godot --headless --path . --fixed-fps 90 res://tests/shader_texture_audit_test.tscn -- --desktop

const SHADER_DIR := "res://src/shaders"
const KATANA_SCENE := preload("res://scenes/weapons/katana.tscn")
const KANABO_SCENE := preload("res://scenes/weapons/kanabo.tscn")
const TORII_SCENE := preload("res://scenes/world/torii_gate.tscn")
const HOKORA_SCENE := preload("res://scenes/world/hokora_shrine.tscn")
## Textures that must be set wherever the shader samples them. The value is the gate uniform: the
## map is only needed while that uniform is above 0 ("" = always needed). Keep in step with the shaders.
const KEY_TEXTURES := {
	"forest_diffuse.gdshader": {"albedo_texture": "", "normal_texture": ""},
	"sakura_tree.gdshader": {"albedo_texture": "", "normal_texture": ""},
	"forest_ground.gdshader": {"soil_albedo": "", "soil_normal": "", "grass_albedo": "", "grass_normal": "",
		"stone_albedo": "", "stone_normal": "", "moss_albedo": "", "moss_normal": "",
		"path_albedo": "", "path_normal": ""},
	"katana_steel.gdshader": {"albedo_texture": "", "normal_texture": ""},
	"wet_surface.gdshader": {"normal_texture": "normal_depth", "orm_texture": "orm_mode"},
}

var failures := 0
var warnings := 0
var _audited_materials: Dictionary = {}  # material instance id -> true
var _regex_uniform := RegEx.create_from_string("(?m)^\\s*uniform\\s")
var _regex_render_mode := RegEx.create_from_string("(?m)^\\s*render_mode\\s+([^;]+);")
var _regex_alpha_write := RegEx.create_from_string("(?m)^\\s*ALPHA\\s*=")


func _ready() -> void:
	await _run_all()
	print("\n%d warning(s)" % warnings)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	print("== Shaders: %s" % SHADER_DIR)
	_audit_shader_files()
	_check_key_texture_gates()

	print("== World instances")
	var root := Node3D.new()
	root.name = "AuditRoot"
	add_child(root)
	var follow := Node3D.new()
	follow.name = "Follow"
	root.add_child(follow)

	# The forest's materials and meshes are built by apply_profile() alone. Chunks, gates and
	# trunks need setup() and a physics ring (about a second of build), so they are not walked here:
	# every chunk shares these materials, and the torii gate below is the scene ToriiManager spawns.
	var forest := ForestWorld.new()
	forest.name = "ForestWorld"
	root.add_child(forest)
	forest.apply_profile(WorldGenProfile.load_active())
	_audit_forest_registry(forest)

	var gate: ToriiGate = TORII_SCENE.instantiate()
	gate.element = Elements.SAKURA
	gate.position = Vector3(200.0, 0.0, 200.0)
	root.add_child(gate)
	var katana: HeldWeapon = KATANA_SCENE.instantiate()
	root.add_child(katana)
	var kanabo: Node3D = KANABO_SCENE.instantiate()
	root.add_child(kanabo)
	var shrine: Node3D = HOKORA_SCENE.instantiate()
	shrine.position = Vector3(-200.0, 0.0, -200.0)
	root.add_child(shrine)
	# DiegeticHud hangs its wrist unit on the player's camera, so a real DesktopPlayer is needed.
	var player := DesktopPlayer.new()
	player.name = "Player"
	root.add_child(player)
	var hud := DiegeticHud.new()
	root.add_child(hud)
	hud.setup(player, katana)
	var yokai := Yokai.new()
	yokai.body_element = Elements.STORM
	root.add_child(yokai)
	var oni := RunOniBoss.new()
	root.add_child(oni)
	await _frames(3)

	_audit_tree("torii gate", gate)
	_audit_tree("katana", katana)
	_audit_tree("kanabo", kanabo)
	_audit_tree("hokora shrine", shrine)
	_audit_tree("wrist HUD", hud.wrist_unit)
	_audit_tree("yokai", yokai)
	_audit_tree("Oni boss", oni)
	root.queue_free()


## ForestWorld builds one material per kind and one mesh per tree or undergrowth kind; every mesh
## is drawn with its matching material as material_override. Each material must exist and each mesh
## list must pair up with its material list, or a kind would draw with the default render.
func _audit_forest_registry(forest: ForestWorld) -> void:
	var pairs := [
		["tree", forest._tree_meshes, forest._tree_mats],
		["far tree", forest._tree_far_meshes, forest._tree_far_mats],
		["undergrowth", forest._under_meshes, forest._under_mats],
	]
	var holes := 0
	var materials := 0
	for pair in pairs:
		var meshes: Array = pair[1]
		var mats: Array = pair[2]
		_check("forest %s: one material per mesh (%d meshes, %d materials)" % [pair[0], meshes.size(), mats.size()],
			meshes.size() == mats.size() and not meshes.is_empty())
		for i in mats.size():
			if mats[i] == null:
				holes += 1
				_fail("forest %s %d has no material" % [pair[0], i])
			else:
				materials += 1
				_audit_material(mats[i], "forest %s %d" % [pair[0], i])
	var singles := {
		"ground": forest._ground_mat, "torii": forest._torii_mat,
		"lantern": forest._lantern_mat, "moon shaft": forest._shaft_mat,
	}
	for label in singles:
		var mat: Material = singles[label]
		if mat == null:
			holes += 1
			_fail("forest %s has no material" % label)
			continue
		materials += 1
		_audit_material(mat, "forest %s" % label)
	print("   forest registry: %d material(s), %d hole(s)" % [materials, holes])
	_check("forest: every mesh kind has a material", holes == 0)


## Every .gdshader in src/shaders must load, declare shader_type and compile. A compile error leaves
## Shader.get_shader_uniform_list() short of the declared uniforms (verified by hand on a broken
## shader; the engine prints it as SHADER ERROR). Shaders without uniforms get the static checks only.
func _audit_shader_files() -> void:
	var names := DirAccess.get_files_at(SHADER_DIR)
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".gdshader"):
			continue
		var shader := load("%s/%s" % [SHADER_DIR, file_name]) as Shader
		_check("shader %s loads" % file_name, shader != null)
		if shader == null:
			continue
		var code := shader.code
		_check("shader %s declares shader_type" % file_name, code.contains("shader_type "))
		_check("shader %s has balanced braces" % file_name,
			code.count("{") == code.count("}") and code.count("{") > 0)
		var declared := _regex_uniform.search_all(code).size()
		var parsed := shader.get_shader_uniform_list().size()
		_check("shader %s compiles (%d of %d uniforms parsed)" % [file_name, parsed, declared], parsed == declared)
		_warn_opaque_alpha(file_name, code)
		print("   OK   %s: %s, %d uniform(s)" % [file_name, _mode_summary(code), parsed])


func _mode_summary(code: String) -> String:
	var found := _regex_render_mode.search(code)
	return "render_mode " + found.get_string(1).strip_edges() if found != null else "no render_mode"


## Opaque shaders that write ALPHA sort per object as transparent. Only the scissor threshold
## (ALPHA_SCISSOR_THRESHOLD) keeps depth-writing foliage and cloth in the opaque pass.
func _warn_opaque_alpha(file_name: String, code: String) -> void:
	if not code.contains("depth_draw_opaque") or _regex_alpha_write.search(code) == null:
		return
	if code.contains("ALPHA_SCISSOR_THRESHOLD"):
		return
	_warn("%s writes ALPHA with depth_draw_opaque and no ALPHA_SCISSOR_THRESHOLD: sorts per object, overlaps can flicker" % file_name)


## Audits every mesh and multimesh under node: each surface needs a material, and every new material is checked.
func _audit_tree(label: String, node: Node) -> void:
	var instances := 0
	var surfaces := 0
	var materials := 0
	var holes := 0
	var all_nodes: Array[Node] = [node]
	all_nodes.append_array(node.find_children("*", "", true, false))
	for n in all_nodes:
		var gi: GeometryInstance3D = null
		var mesh: Mesh = null
		if n is MeshInstance3D:
			gi = n as MeshInstance3D
			mesh = (gi as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			gi = n as MultiMeshInstance3D
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			continue
		instances += 1
		for s in mesh.get_surface_count():
			surfaces += 1
			var mat := _surface_material(gi, mesh, s)
			if mat == null:
				holes += 1
				_fail("%s: %s surface %d has no material (default render)" % [label, _path_of(n, node), s])
				continue
			if _audited_materials.has(mat.get_instance_id()):
				continue
			_audited_materials[mat.get_instance_id()] = true
			materials += 1
			_audit_material(mat, "%s: %s" % [label, _path_of(n, node)])
	print("   %s: %d instance(s), %d surface(s), %d new material(s), %d hole(s)" % [label, instances, surfaces, materials, holes])
	_check("%s: every surface has a material" % label, holes == 0)


func _surface_material(gi: GeometryInstance3D, mesh: Mesh, s: int) -> Material:
	if gi.material_override != null:
		return gi.material_override
	if gi is MeshInstance3D and (gi as MeshInstance3D).get_surface_override_material(s) != null:
		return (gi as MeshInstance3D).get_surface_override_material(s)
	return mesh.surface_get_material(s)


func _audit_material(mat: Material, where: String) -> void:
	if mat is ShaderMaterial:
		_audit_shader_material(mat as ShaderMaterial, where)
	elif mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		var normal_ok := not bm.normal_enabled or bm.normal_texture != null
		var detail_ok := not bm.detail_enabled or bm.detail_albedo != null
		_check("%s: StandardMaterial3D has the maps its flags need" % where, normal_ok and detail_ok)
		print("   OK   material StandardMaterial3D on %s" % where)


func _audit_shader_material(sm: ShaderMaterial, where: String) -> void:
	if sm.shader == null:
		_fail("%s: ShaderMaterial without a shader" % where)
		return
	var file := sm.shader.resource_path.get_file()
	var code := sm.shader.code
	var keys: Dictionary = KEY_TEXTURES.get(file, {})
	for key in _needed_key_textures(sm):
		_check("%s: key texture %s of %s is set" % [where, key, file], sm.get_shader_parameter(key) != null)
	var sampled := 0
	for u in sm.shader.get_shader_uniform_list():
		var uname: String = u["name"]
		if not _is_sampled(code, uname):
			continue
		sampled += 1
		if keys.has(uname) or sm.get_shader_parameter(uname) != null or _has_default_hint(code, uname):
			continue
		_warn("%s: optional map %s of %s is unset (flat, or gated off by its uniform)" % [where, uname, file])
	print("   OK   material %s on %s (%d sampled map(s))" % [file, where, sampled])


## Key maps this material needs: sampled by its shader, and not gated off by the gate uniform.
func _needed_key_textures(sm: ShaderMaterial) -> Array[String]:
	var needed: Array[String] = []
	var keys: Dictionary = KEY_TEXTURES.get(sm.shader.resource_path.get_file(), {})
	for key in keys:
		var gate: String = keys[key]
		if _is_sampled(sm.shader.code, key) and (gate == "" or _as_float(sm.get_shader_parameter(gate)) > 0.0):
			needed.append(key)
	return needed


## Detector self-test on the real shaders: an unset key map is reported, a gated-off one is not.
func _check_key_texture_gates() -> void:
	var forest_mat := ShaderMaterial.new()
	forest_mat.shader = load("%s/forest_diffuse.gdshader" % SHADER_DIR)
	_check("detector: forest_diffuse with no maps needs albedo_texture",
		_needed_key_textures(forest_mat).has("albedo_texture"))
	_check("detector: forest_diffuse with no maps needs normal_texture",
		_needed_key_textures(forest_mat).has("normal_texture"))
	var wet_mat := ShaderMaterial.new()
	wet_mat.shader = load("%s/wet_surface.gdshader" % SHADER_DIR)
	_check("detector: wet_surface at normal_depth 0 does not need normal_texture",
		not _needed_key_textures(wet_mat).has("normal_texture"))
	wet_mat.set_shader_parameter("normal_depth", 0.5)
	_check("detector: wet_surface at normal_depth 0.5 needs normal_texture",
		_needed_key_textures(wet_mat).has("normal_texture"))


func _as_float(value: Variant) -> float:
	return float(value) if value != null else 0.0


func _is_sampled(code: String, uname: String) -> bool:
	return RegEx.create_from_string("\\b(texture|textureLod|texelFetch|textureGrad)\\s*\\(\\s*%s\\b" % uname).search(code) != null


func _has_default_hint(code: String, uname: String) -> bool:
	var decl := RegEx.create_from_string("uniform\\s+sampler2D\\s+%s\\b[^;]*;" % uname).search(code)
	return decl != null and decl.get_string().contains("hint_default")


func _path_of(n: Node, root_node: Node) -> String:
	return str(root_node.get_path_to(n)) if n != root_node else "."


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _fail(label: String) -> void:
	print("FAIL  %s" % label)
	failures += 1


func _warn(label: String) -> void:
	print("WARN  %s" % label)
	warnings += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
