extends SceneTree

# 修正握持偏移：把 Model 沿武器局部 +Y 抬 0.16（根缩放前），让弩身落进掌心
# 用法: godot --headless --path . --script res://tools/fix_grip_offset.gd -- [x y z]

const TSCN := "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var d := Vector3(0, 0.16, 0)
	if a.size() >= 3:
		d = Vector3(float(a[0]), float(a[1]), float(a[2]))

	var root: Node3D = (load(TSCN) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var model := root.get_node_or_null("Model") as Node3D
	if model == null:
		push_error("找不到 Model")
		quit(1)
		return
	print("原 Model.position = ", model.position)
	model.position += d
	print("新 Model.position = ", model.position)

	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, TSCN))
	quit(0)
