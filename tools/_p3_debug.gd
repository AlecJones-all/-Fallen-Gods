extends SceneTree

# P3 调试：列出场景内所有自发光网格；把远景板染红验证是否可见。
# 用法：godot --path . --script res://tools/_p3_debug.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _m: Node
var _f := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/baseline"))
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		var player := _m.get_node_or_null("World/Player") as Node3D
		var world := _m.get_node_or_null("World") as Node3D
		var rig := _m.get_node_or_null("CameraRig") as Node3D
		if player != null:
			player.position = Vector3(44.0, 0.05, 0.0)
		if rig != null and world != null:
			rig.global_position = world.transform * Vector3(44.0, 1.0, 0.0)
		_dump_emissive()
		_tint_vista_red()
	if _f == 24:
		get_root().get_texture().get_image().save_png("res://docs/baseline/p3_vista_red.png")
		print("saved p3_vista_red.png")
		return true
	return false


func _dump_emissive() -> void:
	var root := _m
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat: Material = mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.get_active_material(0)
		if not (mat is BaseMaterial3D):
			continue
		var bm := mat as BaseMaterial3D
		if not bm.emission_enabled:
			continue
		print("GLOW ", mi.name, " at ", mi.global_position, " energy=", bm.emission_energy_multiplier,
			" albedo=", bm.albedo_color)


func _tint_vista_red() -> void:
	var vista := _m.get_node_or_null("World/Vista")
	if vista == null:
		print("VISTA missing")
		return
	print("VISTA node children=", vista.get_child_count(), " visible=", (vista as Node3D).visible)
	for child: Node in vista.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		mi.position = Vector3(52.0, 1.5, 0.0)
		var quad := mi.mesh as QuadMesh
		if quad != null:
			quad.size = Vector2(40.0, 8.0)
		print("VISTA mesh global=", mi.global_position, " aabb=", mi.get_aabb(), " visible=", mi.is_visible_in_tree())
		var red := StandardMaterial3D.new()
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		red.albedo_color = Color(1.0, 0.0, 0.0)
		red.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = red