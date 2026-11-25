extends SceneTree

# 墙面正视校对：把场地转 45°，相机沿 -z 看，墙面正对镜头（只看形体，不是交付机位）。
# 用法：godot --path . --resolution 1400x800 --script res://tools/_wallface.gd -- <tag> <x>
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _rig: Node3D
var _cam: Camera3D
var _world: Node3D
var _f := 0
var _tag := "face"
var _x := 24.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_tag = String(args[0])
	if args.size() >= 2:
		_x = float(args[1])
	var m: Node = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(m)
	_rig = m.get_node_or_null("CameraRig") as Node3D
	_world = m.get_node_or_null("World") as Node3D
	_cam = _rig.get_node_or_null("Camera3D") as Camera3D
	var hud := m.get_node_or_null("HUD")
	if hud != null:
		hud.set("visible", false)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 6:
		if _world != null:
			_world.rotation.y = deg_to_rad(45.0)
		_rig.rotation_degrees = Vector3(-18.0, 45.0, 0.0)
		_rig.global_position = _world.transform * Vector3(_x, 1.6, 0.0)
		_cam.size = 14.0
		return false
	if _f == 22:
		get_root().get_texture().get_image().save_png("res://docs/wall/%s_face.png" % _tag)
		print("saved face")
		return true
	return false
