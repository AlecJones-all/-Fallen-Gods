extends SceneTree

# 方案 A 第一步：把弩的挂载朝向转正，使开火姿态下弩口对准角色正前方
# 用法: godot --headless --path . --script res://tools/align_xbow.gd -- [rx ry rz]

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const ROT := Vector3(-5.8, -87.8, 5.5)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var rot := ROT
	if a.size() >= 3:
		rot = Vector3(float(a[0]), float(a[1]), float(a[2]))

	var root: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var xb: Node3D = root.find_child("Crossbow", true, false) as Node3D
	if xb == null:
		push_error("找不到 Crossbow")
		quit(1)
		return
	print("原 rotation = ", xb.rotation_degrees, "  position = ", xb.position)
	xb.rotation_degrees = rot
	# 握把是 Crossbow 的子件，局部 (0,-0.085,-0.02)；转正后它会绕原点甩出去，
	# 所以按"掌心点在 pivot 空间的位置"反推挂点：
	#   掌心 palm 由未旋转时的经验补偿反推 = position0 + grip_local
	var grip_local := Vector3(0, -0.085, -0.02)
	var palm := Vector3(0, 0.02, -0.085) + grip_local
	xb.position = palm - xb.basis * grip_local
	print("新 rotation = ", xb.rotation_degrees)
	print("新 position = ", xb.position, "（掌心 ", palm, "）")

	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, SCENE))
	quit(0)
