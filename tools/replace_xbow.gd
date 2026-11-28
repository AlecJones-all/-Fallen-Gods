extends SceneTree

# 把玩家手里的程序化连弩换成 assets/weapons/xbow_steampunk
# 用法: godot --headless --path . --script res://tools/replace_xbow.gd [-- zhuge]

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const STEAM := "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn"
const ZHUGE := "res://assets/weapons/xbow_zhuge/xbow_zhuge.tscn"


func _initialize() -> void:
	var which := STEAM
	if OS.get_cmdline_user_args().has("zhuge"):
		which = ZHUGE

	var root: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)

	var pivot: Node3D = root.find_child("XbowPivot", true, false) as Node3D
	if pivot == null:
		push_error("找不到 XbowPivot")
		quit(1)
		return

	for c in pivot.get_children():
		if c.name == "Crossbow":
			pivot.remove_child(c)
			c.queue_free()
			print("已移除旧的程序化 Crossbow")

	var inst: Node3D = (load(which) as PackedScene).instantiate() as Node3D
	inst.name = "Crossbow"
	inst.visible = false  # 默认拿剑，切到连弩才显示
	pivot.add_child(inst)
	inst.owner = root

	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, SCENE))
	print("装入：", which)

	# 自检
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("动画片段 = ", ap.get_animation_list().size())
	print("剑仍在 = ", root.find_child("Cube_009", true, false) != null)
	print("斧仍在 = ", root.find_child("Axe", true, false) != null)
	var xb: Node = root.find_child("Crossbow", true, false)
	print("新弩节点 = ", xb.name if xb != null else "null", " 子件 = ", xb.get_child_count() if xb != null else -1)
	quit(0)
