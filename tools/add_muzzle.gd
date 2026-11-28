extends SceneTree

# 在 Crossbow 下加枪口 Marker3D（局部坐标取自弩身几何：箭槽前端）
const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const MUZZLE := Vector3(0, 0.02, 0.30)


func _initialize() -> void:
	var root: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var xb: Node3D = root.find_child("Crossbow", true, false) as Node3D
	if xb == null:
		push_error("找不到 Crossbow")
		quit(1)
		return
	var old := xb.get_node_or_null("Muzzle")
	if old != null:
		xb.remove_child(old)
		old.queue_free()
	var m := Marker3D.new()
	m.name = "Muzzle"
	m.position = MUZZLE
	xb.add_child(m)
	m.owner = root
	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, SCENE))
	quit(0)
