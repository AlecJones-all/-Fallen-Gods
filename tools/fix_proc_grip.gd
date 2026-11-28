extends SceneTree

# 程序化连弩的握把补偿：把 Crossbow 在 pivot 空间里前移 8.5cm、抬高 2cm，
# 让木握把落进拳心（对应 docs/19 第十一节问题 1）
const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const OFFSET := Vector3(0, 0.02, -0.085)


func _initialize() -> void:
	var root: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var xb: Node3D = root.find_child("Crossbow", true, false) as Node3D
	if xb == null:
		push_error("找不到 Crossbow")
		quit(1)
		return
	print("原 position = ", xb.position)
	xb.position += OFFSET
	print("新 position = ", xb.position)
	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, SCENE))
	quit(0)
