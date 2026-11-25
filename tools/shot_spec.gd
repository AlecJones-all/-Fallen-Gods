extends SceneTree

# 规格预览截图：加载主场景 → 打开 F1 线框 → 拉成全景 → 存图
# 用法: godot --path . --resolution 1600x900 --script res://tools/shot_spec.gd -- spec_shot.png
var _f := 0
var _out := "res://_spec.png"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_out = "res://" + a[0]
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 4:
		var overlay: Node = get_root().find_child("SpecOverlay", true, false)
		if overlay != null and overlay.has_method(&"toggle"):
			overlay.call(&"toggle")
		var hud: Node = get_root().find_child("HUD", true, false)
		if hud != null:
			hud.set("visible", false)
		var rig: Node3D = get_root().find_child("CameraRig", true, false) as Node3D
		if rig != null:
			rig.set_physics_process(false)
			rig.global_position = Vector3(24.0, 1.0, 0.0)
			var cam: Camera3D = rig.get_node_or_null("Camera3D") as Camera3D
			if cam != null:
				cam.size = 42.0
	if _f == 14:
		get_root().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
