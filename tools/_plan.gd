extends SceneTree

# 平面校对：世界不转、相机垂直向下，只看墙体平面关系。
# 用法：godot --path . --resolution 1200x1200 --script res://tools/_plan.gd -- <tag>
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _rig: Node3D
var _cam: Camera3D
var _world: Node3D
var _f := 0
var _tag := "plan"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_tag = String(args[0])
	var m: Node = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(m)
	_rig = m.get_node_or_null("CameraRig") as Node3D
	_world = m.get_node_or_null("World") as Node3D
	_cam = _rig.get_node_or_null("Camera3D") as Camera3D
	var hud := m.get_node_or_null("HUD")
	if hud != null:
		hud.set("visible", false)
	var we := m.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.fog_enabled = false


func _process(_d: float) -> bool:
	_f += 1
	if _f == 4:
		if _world != null:
			_world.rotation.y = 0.0
		_rig.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_rig.global_position = Vector3(24.0, 0.0, 0.0)
		_cam.size = 52.0
		return false
	if _f == 16:
		get_root().get_texture().get_image().save_png("res://docs/wall/%s_plan.png" % _tag)
		print("saved plan")
		return true
	return false
