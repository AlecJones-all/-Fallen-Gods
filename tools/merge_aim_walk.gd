extends SceneTree

# 把动画包里的 aim_walk 合进玩家场景的 AnimationPlayer
const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const PACK := "res://dist/anim_pack_v1/rogue_knight_anims.tres"


func _initialize() -> void:
	var pack: AnimationLibrary = load(PACK)
	if pack == null or not pack.has_animation("aim_walk"):
		push_error("包里没有 aim_walk")
		quit(1)
		return
	var root: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		push_error("找不到 AnimationPlayer")
		quit(1)
		return

	var lib: AnimationLibrary = ap.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)
	if lib.has_animation("aim_walk"):
		lib.remove_animation("aim_walk")
	lib.add_animation("aim_walk", pack.get_animation("aim_walk").duplicate(true))
	print("动画数 = ", ap.get_animation_list().size(), " 列表 = ", ap.get_animation_list())

	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, SCENE))
	quit(0)
